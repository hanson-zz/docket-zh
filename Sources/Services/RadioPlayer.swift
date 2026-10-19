import AVFoundation
import Foundation
import Observation

/// Plays the radio widget's station through one shared `AVPlayer`.
///
/// One player for the whole app, like `AmbientPlayer`: two radio widgets on
/// two layouts are two remotes for the same speaker. `AVPlayer` reads plain
/// HTTP MP3 and AAC streams as well as HLS playlists, so nothing here knows
/// which kind a station is.
///
/// A dropped or stalled stream is reconnected on `RadioRetry`'s schedule
/// (2, 4, 8, 16, then every 30 seconds) for as long as the listener has not
/// pressed pause. A pause, or the sleep timer, lets the connection go, so a
/// live station resumes live rather than from a stale buffer.
@MainActor @Observable
final class RadioPlayer {
    static let shared = RadioPlayer()

    /// The listener wants sound: true from play until pause, through stalls
    /// and reconnects.
    private(set) var isPlaying = false
    /// Waiting on the network, at first connect or while reconnecting.
    private(set) var isBuffering = false
    /// The station tuned in, playing or not.
    private(set) var station: RadioStation?
    /// What the station says is on, when its stream sends a title.
    private(set) var nowTitle: String?
    /// Set while the stream cannot be reached; cleared once audio flows.
    private(set) var problem: String?
    /// When the sleep timer stops playback, or nil when it is off.
    private(set) var stopAt: Date?
    /// The sleep timer's length in minutes, 0 when off.
    private(set) var timerMinutes = 0

    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var itemObservation: NSKeyValueObservation?
    @ObservationIgnored private var itemObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var attempt = 0
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var volume: Double = 60
    @ObservationIgnored private let relay = RadioMetadataRelay()

    @ObservationIgnored private var playlist: [RadioStation] = []
    /// 开始播放的那个收音机小组件。媒体键换台时写回它的 index，卡片才知道换到了哪一台。
    @ObservationIgnored private var owner: UUID?

    private init() {}

    // MARK: Controls

    /// Whether this station is the one coming out of the speaker.
    func plays(_ candidate: RadioStation?) -> Bool {
        guard isPlaying, let candidate, let station else { return false }
        return station.url == candidate.url
    }

    func toggle(_ station: RadioStation, volume: Double, stations: [RadioStation]? = nil, owner: UUID? = nil) {
        plays(station) ? pause() : play(station, volume: volume, stations: stations, owner: owner)
    }

    func play(_ station: RadioStation, volume: Double, stations: [RadioStation]? = nil, owner: UUID? = nil) {
        guard RadioDial.streamURL(station.url) != nil else { return }
        if let owner { self.owner = owner }
        if let stations { playlist = stations }
        if !playlist.contains(where: { $0.url == station.url }) { playlist = [station] }
        MediaSessionCoordinator.shared.begin(.radio) { [weak self] command, _ in self?.remote(command) }
        cancelRetry()
        attempt = 0
        if self.station?.url != station.url { nowTitle = nil }
        self.station = station
        self.volume = volume
        problem = nil
        isPlaying = true
        connect()
        if timerMinutes > 0, stopAt == nil {
            stopAt = .now.addingTimeInterval(Double(timerMinutes) * 60)
        }
        startTicker()
        publishSession()
    }

    func pause() {
        isPlaying = false
        isBuffering = false
        problem = nil
        stopAt = nil
        cancelRetry()
        ticker?.invalidate()
        ticker = nil
        dropItem()
        publishSession()
    }

    func stop() {
        pause()
        MediaSessionCoordinator.shared.end(.radio)
    }

    /// 收藏编辑过后跟上新的列表，媒体键的“下一台”不会播到已删除的电台。
    func syncPlaylist(_ stations: [RadioStation], owner: UUID) {
        guard owner == self.owner else { return }
        playlist = stations
    }

    private func remote(_ command: MediaCommand) {
        guard ProAccess.isUnlocked else { return }
        guard let action = MediaSessionRules.action(command, source: .radio, playing: isPlaying) else { return }
        switch action {
        case .play:
            if let station { play(station, volume: volume) }
        case .pause: pause()
        case .stop: stop()
        case .station(let delta):
            // 优先按小组件当前保存的收藏换台，并把 index 写回去。
            if let owner, let instance = WidgetWriter.current(owner), instance.kind == .radio {
                let list = RadioDial.stations(instance.config)
                guard !list.isEmpty else { return }
                let current = list.firstIndex { $0.url == station?.url }
                    ?? RadioDial.index(instance.config, count: list.count)
                let next = delta > 0 ? RadioDial.next(current, count: list.count) : RadioDial.previous(current, count: list.count)
                RadioRemote.tune(instance, to: next, play: true)
                return
            }
            guard !playlist.isEmpty else { return }
            let current = playlist.firstIndex { $0.url == station?.url } ?? 0
            let next = delta > 0 ? RadioDial.next(current, count: playlist.count) : RadioDial.previous(current, count: playlist.count)
            play(playlist[next], volume: volume)
        case .position: break
        }
    }

    private func publishSession() {
        guard let station else { return }
        MediaSessionCoordinator.shared.update(.radio, title: nowTitle ?? station.name,
                                               subtitle: station.name, playing: isPlaying)
    }

    /// 0...100, applied at once whether or not anything plays.
    func setVolume(_ volume: Double) {
        self.volume = volume
        player?.volume = Self.gain(volume)
    }

    /// 0 turns the timer off. Counting starts now when playing, or at the
    /// next play otherwise.
    func setTimer(minutes: Int) {
        timerMinutes = max(0, minutes)
        stopAt = (isPlaying && timerMinutes > 0) ? .now.addingTimeInterval(Double(timerMinutes) * 60) : nil
    }

    private static func gain(_ volume: Double) -> Float {
        Float(min(100, max(0, volume)) / 100)
    }

    // MARK: Connection

    private func connect() {
        guard let station, let url = URL(string: station.url) else { return }
        dropItem()
        let asset = AVURLAsset(url: url, options: [AVURLAssetHTTPUserAgentKey: RadioBrowser.userAgent])
        let item = AVPlayerItem(asset: asset)
        let output = AVPlayerItemMetadataOutput(identifiers: nil)
        output.setDelegate(relay, queue: .main)
        item.add(output)

        let player = self.player ?? makePlayer()
        player.volume = Self.gain(volume)
        player.replaceCurrentItem(with: item)
        isBuffering = true
        watch(item)
        player.play()
    }

    private func makePlayer() -> AVPlayer {
        let player = AVPlayer()
        player.automaticallyWaitsToMinimizeStalling = true
        statusObservation = Self.observeStatus(player) { [weak self] in
            Task { @MainActor in self?.syncStatus() }
        }
        self.player = player
        return player
    }

    private func watch(_ item: AVPlayerItem) {
        itemObservation = Self.observeItem(item) { [weak self] in
            Task { @MainActor in self?.syncItem() }
        }
        let center = NotificationCenter.default
        let names: [Notification.Name] = [.AVPlayerItemPlaybackStalled,
                                          .AVPlayerItemFailedToPlayToEndTime,
                                          // A live stream that "ends" has dropped.
                                          .AVPlayerItemDidPlayToEndTime]
        itemObservers = names.map { name in
            center.addObserver(forName: name, object: item, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.streamDropped() }
            }
        }
    }

    private func dropItem() {
        itemObservation?.invalidate()
        itemObservation = nil
        for observer in itemObservers { NotificationCenter.default.removeObserver(observer) }
        itemObservers = []
        player?.pause()
        player?.replaceCurrentItem(with: nil)
    }

    /// Built outside the main actor on purpose: a closure written inside a
    /// main-actor method inherits that isolation under Swift 6, and KVO may
    /// call it from another thread, which would trap on the executor check.
    private nonisolated static func observeStatus(_ player: AVPlayer,
                                                  _ changed: @escaping @Sendable () -> Void) -> NSKeyValueObservation {
        player.observe(\.timeControlStatus, options: [.new]) { _, _ in changed() }
    }

    private nonisolated static func observeItem(_ item: AVPlayerItem,
                                                _ changed: @escaping @Sendable () -> Void) -> NSKeyValueObservation {
        item.observe(\.status, options: [.new]) { _, _ in changed() }
    }

    private func syncStatus() {
        guard isPlaying, let player else { return }
        switch player.timeControlStatus {
        case .playing:
            isBuffering = false
            problem = nil
            attempt = 0
            cancelRetry()
        case .waitingToPlayAtSpecifiedRate:
            isBuffering = true
        case .paused:
            break
        @unknown default:
            break
        }
    }

    private func syncItem() {
        guard isPlaying, let item = player?.currentItem else { return }
        if item.status == .failed { streamDropped() }
    }

    // MARK: Retry

    private func streamDropped() {
        guard isPlaying, retryTask == nil else { return }
        isBuffering = true
        let wait = RadioRetry.delay(attempt: attempt)
        attempt += 1
        // The first couple of hiccups are routine on a live stream; say so
        // only once it keeps failing.
        if attempt >= 3 { problem = tr("连接不上电台，\(Int(wait)) 秒后重试") }
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.retryNow()
        }
    }

    private func retryNow() {
        retryTask = nil
        guard isPlaying else { return }
        // A stall that cleared on its own needs nothing.
        if let player, player.timeControlStatus == .playing,
           player.currentItem?.status == .readyToPlay { return }
        connect()
    }

    private func cancelRetry() {
        retryTask?.cancel()
        retryTask = nil
    }

    // MARK: Now playing

    fileprivate func received(title: String?) {
        guard isPlaying, let station else { return }
        let clean = RadioDial.nowPlaying(title, stationName: station.name)
        if clean != nowTitle { nowTitle = clean; publishSession() }
    }

    // MARK: Sleep timer

    private func startTicker() {
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        guard isPlaying, let stopAt else { return }
        if Date.now >= stopAt { stop() }
    }
}

/// Receives a stream's timed metadata (an ICY `StreamTitle`, or an HLS ID3
/// title) and hands the title to the player on the main actor.
final class RadioMetadataRelay: NSObject, AVPlayerItemMetadataOutputPushDelegate, @unchecked Sendable {
    func metadataOutput(_ output: AVPlayerItemMetadataOutput,
                        didOutputTimedMetadataGroups groups: [AVTimedMetadataGroup],
                        from track: AVPlayerItemTrack?) {
        let items = groups.flatMap(\.items)
        let match = items.first { $0.identifier == .icyMetadataStreamTitle }
            ?? items.first { $0.commonKey == .commonKeyTitle }
        let title = match?.stringValue
        Task { @MainActor in RadioPlayer.shared.received(title: title) }
    }
}

/// Asks the Radio Browser directory, trying its mirrors in order.
enum RadioDirectory {
    /// A name to look for (empty lists the most listened) inside a region.
    struct Query: Sendable, Equatable {
        var name: String
        var region: RadioRegion

        func url(host: String) -> URL? {
            RadioBrowser.searchURL(name: name, region: region, host: host)
        }
    }

    /// Nil when no mirror answered with a station list.
    nonisolated static func fetch(_ query: Query) async -> [RadioStation]? {
        for host in RadioBrowser.hosts {
            guard let url = query.url(host: host) else { return nil }
            var request = URLRequest(url: url, timeoutInterval: 12)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(RadioBrowser.userAgent, forHTTPHeaderField: "User-Agent")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let stations = RadioBrowser.parse(data) else { continue }
            return stations
        }
        return nil
    }
}
