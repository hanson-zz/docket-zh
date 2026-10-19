import AVFoundation
import Foundation
import Observation

/// Plays 播客 episodes inside 码头 through one shared `AVPlayer`.
///
/// One player for the whole app, like `RadioPlayer`: two 播客 widgets are
/// two remotes for the same speaker. Where each episode was left is saved to
/// `PodcastService` every few seconds while it plays, on pause and when it
/// ends, so the next play resumes there.
@MainActor @Observable
final class PodcastPlayer {
    static let shared = PodcastPlayer()

    private(set) var episode: PodcastEpisode?
    private(set) var showID: String?
    private(set) var isPlaying = false
    private(set) var isBuffering = false
    /// Seconds into the episode.
    private(set) var position: Double = 0
    /// Seconds, from the file once known, else from the page.
    private(set) var duration: Double = 0
    /// Set when the audio cannot be played; cleared by the next play.
    private(set) var problem: String?

    @ObservationIgnored private var player: AVPlayer?
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var itemObservation: NSKeyValueObservation?
    @ObservationIgnored private var itemObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var lastSaved = Date.distantPast

    private init() {}

    // MARK: Controls

    func isCurrent(_ episode: PodcastEpisode) -> Bool { self.episode?.id == episode.id }

    func toggle(_ episode: PodcastEpisode, show: String) {
        if isCurrent(episode) {
            isPlaying ? pause() : resume()
        } else {
            play(episode, show: show)
        }
    }

    /// Starts `episode` where it was left.
    func play(_ episode: PodcastEpisode, show: String) {
        guard let url = episode.audioURL else {
            problem = tr("这一集没有可播放的音频。")
            return
        }
        MediaSessionCoordinator.shared.begin(.podcast) { [weak self] command, position in self?.remote(command, position: position) }
        saveProgress()
        teardownItem()
        self.episode = episode
        showID = show
        problem = nil
        duration = Double(episode.duration)
        let start = PodcastService.shared.library.resumePosition(episode.id)
        position = start

        let asset = AVURLAsset(url: url, options: [AVURLAssetHTTPUserAgentKey: LinkPreviewFetcher.userAgent])
        let item = AVPlayerItem(asset: asset)
        let player = self.player ?? makePlayer()
        player.replaceCurrentItem(with: item)
        watch(item)
        if start > 0 {
            player.seek(to: CMTime(seconds: start, preferredTimescale: 600))
        }
        isBuffering = true
        isPlaying = true
        player.play()
        publishSession()
    }

    func resume() {
        guard let player, player.currentItem != nil else {
            if let episode, let showID { play(episode, show: showID) }
            return
        }
        MediaSessionCoordinator.shared.begin(.podcast) { [weak self] command, position in self?.remote(command, position: position) }
        problem = nil
        isPlaying = true
        player.play()
        publishSession()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        isBuffering = false
        saveProgress()
        publishSession()
    }

    /// Lets the episode go entirely, as when its show is unsubscribed.
    func stop() {
        pause()
        teardownItem()
        episode = nil
        showID = nil
        position = 0
        duration = 0
        MediaSessionCoordinator.shared.end(.podcast)
    }

    func seek(to seconds: Double) {
        let target = PodcastPlayback.skip(seconds, by: 0, duration: duration)
        position = target
        player?.seek(to: CMTime(seconds: target, preferredTimescale: 600),
                     toleranceBefore: .zero, toleranceAfter: .zero)
        saveProgress()
        publishSession()
    }

    func skip(by delta: Double) {
        seek(to: PodcastPlayback.skip(position, by: delta, duration: duration))
    }

    private func remote(_ command: MediaCommand, position requested: Double?) {
        let chapters = currentEpisode?.chapters ?? []
        guard let action = MediaSessionRules.action(command, source: .podcast, playing: isPlaying,
            position: position, duration: duration, chapters: chapters, requestedPosition: requested) else { return }
        switch action {
        case .play: resume()
        case .pause: pause()
        case .stop: stop()
        case .position(let seconds): seek(to: seconds)
        case .station: break
        }
    }

    private var currentEpisode: PodcastEpisode? {
        guard let episode else { return nil }
        return PodcastService.shared.library.shows.flatMap(\.episodes).first { $0.id == episode.id } ?? episode
    }

    private func publishSession() {
        guard let episode = currentEpisode else { return }
        let show = PodcastService.shared.library.shows.first { $0.id == showID }
        MediaSessionCoordinator.shared.update(.podcast, title: episode.title,
            subtitle: show?.title ?? tr("播客"), playing: isPlaying, duration: duration,
            position: position, imageURL: episode.imageURL ?? show?.imageURL)
    }

    // MARK: Player

    private func makePlayer() -> AVPlayer {
        let player = AVPlayer()
        player.automaticallyWaitsToMinimizeStalling = true
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
                                                      queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.ticked(time.seconds) }
        }
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
        itemObservers = [
            center.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.finished() }
            },
            center.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.failed() }
            },
        ]
    }

    private func teardownItem() {
        itemObservation?.invalidate()
        itemObservation = nil
        for observer in itemObservers { NotificationCenter.default.removeObserver(observer) }
        itemObservers = []
        player?.pause()
        player?.replaceCurrentItem(with: nil)
    }

    /// Built outside the main actor on purpose, as in `RadioPlayer`: KVO may
    /// call these from another thread.
    private nonisolated static func observeStatus(_ player: AVPlayer,
                                                  _ changed: @escaping @Sendable () -> Void) -> NSKeyValueObservation {
        player.observe(\.timeControlStatus, options: [.new]) { _, _ in changed() }
    }

    private nonisolated static func observeItem(_ item: AVPlayerItem,
                                                _ changed: @escaping @Sendable () -> Void) -> NSKeyValueObservation {
        item.observe(\.status, options: [.new]) { _, _ in changed() }
    }

    private func ticked(_ seconds: Double) {
        guard episode != nil, seconds.isFinite else { return }
        if let item = player?.currentItem {
            let length = item.duration.seconds
            if length.isFinite, length > 0 { duration = length }
        }
        // A seek in flight reports the old time once; only a playing
        // player's clock is taken as the position.
        guard isPlaying else { return }
        position = seconds
        if Date.now.timeIntervalSince(lastSaved) >= 5 { saveProgress() }
        publishSession()
    }

    private func syncStatus() {
        guard let player else { return }
        switch player.timeControlStatus {
        case .playing:
            isBuffering = false
            problem = nil
        case .waitingToPlayAtSpecifiedRate:
            isBuffering = isPlaying
        case .paused:
            isBuffering = false
        @unknown default:
            break
        }
    }

    private func syncItem() {
        guard let item = player?.currentItem, item.status == .failed else { return }
        failed()
    }

    private func failed() {
        isPlaying = false
        isBuffering = false
        problem = tr("播放失败，请检查网络后再试。")
        saveProgress()
        MediaSessionCoordinator.shared.end(.podcast)
    }

    private func finished() {
        guard let episode else { return }
        isPlaying = false
        isBuffering = false
        position = duration
        PodcastService.shared.markFinished(episode.id, duration: duration)
        MediaSessionCoordinator.shared.end(.podcast)
    }

    private func saveProgress() {
        guard let episode, position > 0 || PodcastService.shared.library.progress[episode.id] != nil else { return }
        lastSaved = .now
        PodcastService.shared.record(episode.id, position: position, duration: duration)
    }
}
