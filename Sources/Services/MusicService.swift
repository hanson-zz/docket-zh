import AppKit
import CoreServices
import Foundation
import Observation

// `MusicSource` lives in Core (MusicSources.swift) so the switching rules can be tested.

/// One player's current track.
///
/// `@unchecked Sendable` only because of `artwork`: `NSImage` carries no
/// `Sendable` conformance, but the image here is built once and never mutated,
/// so handing the struct between actors is safe in practice.
public struct NowPlaying: @unchecked Sendable, Equatable {
    public var title: String
    public var artist: String
    public var album: String
    public var duration: TimeInterval
    public var elapsed: TimeInterval
    public var isPlaying: Bool
    public var artwork: NSImage?
    /// The colour the panel stands on, taken from the artwork's bytes at
    /// decode time rather than from the image afterwards.
    public var tint: ArtworkTint?
    public var source: MusicSource

    // 只有 Apple 音乐 / Spotify（AppleScript）读得到的几项；网易云、QQ 是 nil。
    public var shuffle: Bool?
    public var repeatMode: MusicRepeat?
    /// 播放器自己的音量，0…100。
    public var volume: Double?
    /// Apple 音乐的喜欢（macOS 14 起 favorited，之前 loved）。
    public var favorited: Bool?
    /// Spotify 是 `spotify:track:…`，Apple 音乐是 database ID。
    public var trackID: String?
    /// Spotify 给的封面网址，「刚才听过」记下来当缩略图。
    public var artworkURL: URL?

    /// 0…1, and never NaN - a live stream reports a zero duration.
    public var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, elapsed / duration))
    }

    /// Identity of the *track*, used to decide when artwork has to be refetched.
    var trackKey: String { "\(source.rawValue)\u{1}\(title)\u{1}\(artist)\u{1}\(album)" }
}

/// Spotify and Apple Music, over Apple events.
///
/// Deliberately not MediaRemote: that framework has been entitlement-gated
/// since macOS 15.4. It loads and the symbol resolves, so it looks like it
/// works; the callback is then handed nil, with no error and no diagnostic.
/// Claiming the entitlement is not a way round it either, since an ad-hoc
/// binary asserting a private entitlement is killed at launch.
///
/// Nothing here ever launches a player - an app that is not already running is
/// skipped, so the shelf cannot boot iTunes to ask what is playing.
@MainActor @Observable
public final class MusicService {
    public static let shared = MusicService()

    /// 一个开着的播放器：读得到曲目时带着它。
    public struct Player: Equatable, Sendable {
        public var source: MusicSource
        public var track: NowPlaying?
    }

    /// 面板「接下来」：Apple 音乐当前歌单里排在后面的几首。
    public struct UpNext: Equatable, Sendable {
        public struct Item: Equatable, Sendable, Identifiable {
            public var id: String       // database ID
            public var title: String
            public var artist: String
            public var duration: Double
        }
        public var playlist: String
        public var items: [Item]
    }

    /// The track of the source on screen (`current`). A failed poll leaves it
    /// alone rather than blanking the tile every time a script times out.
    public private(set) var nowPlaying: NowPlaying?
    /// True when a player is running but macOS has not been asked for consent
    /// yet (or consent was refused). The tile shows a "Connect" button for
    /// this instead of us triggering a prompt at launch.
    public private(set) var needsAutomationPermission = false

    /// Whether a *supported* player is open at all.
    public private(set) var hasPlayer = false

    /// 开着的播放器，按偏好顺序，给面板的来源列表和「其他开着的」。
    public private(set) var players: [Player] = []

    /// 正在显示、按钮控制的播放器来源。可能没开（固定的来源没开）。显示的是浏览器
    /// 标签页时停在上一个播放器。
    public private(set) var current: MusicSource?

    /// 卡片和面板共用的「当前显示来源」（Core `MusicDisplay.pick` 挑的）：两边都读它，
    /// 永远显示同一首。
    public private(set) var display: MusicCardChoice.Pick = .none
    /// `display` 是用户手点的（面板来源列表、「其他开着的」里点播放、对它按了播放键）。
    @ObservationIgnored private var manual = false
    @ObservationIgnored private var browserWasPlaying = false

    /// Sources to consult, in the order the config prefers them.
    public var enabled: [MusicSource] = MusicSource.allCases

    /// 「谁开始播放就切到谁」，卡片和面板从配置同步过来（`configure`）。
    public private(set) var autoSwitch = true
    /// 自动切换关着时固定用的来源。
    public private(set) var pinned: MusicSource?

    /// Spotify「刚才听过」，只存在本机。
    public private(set) var recent = MusicRecent.decode(UserDefaults.standard.data(forKey: MusicRecent.defaultsKey))

    /// Apple 音乐的「接下来」，面板开着时才读。
    public private(set) var upNext: UpNext?
    /// 面板开着时才读「接下来」，关着时不为它多发 Apple Event。
    @ObservationIgnored private var wantsUpNext = false

    public func setWantsUpNext(_ on: Bool) {
        guard on != wantsUpNext else { return }
        wantsUpNext = on
        if on { upNextKey = nil; refreshUpNext() }
    }

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var polling = false
    /// Consecutive probes that never came back.
    @ObservationIgnored private var timeouts = 0

    /// When we last spoke to the player ourselves.
    @ObservationIgnored private var lastCommand: Date = .distantPast

    /// The play state the user asked for, until a reading confirms it.
    @ObservationIgnored private var asked: Bool?

    /// 上一次读到时各来源是否在放，认「刚开始播放」用。
    @ObservationIgnored private var wasPlaying: [MusicSource: Bool] = [:]
    /// 上次记进「刚才听过」的 Spotify 曲目。
    @ObservationIgnored private var lastRecorded: String?
    @ObservationIgnored private var upNextKey: String?
    @ObservationIgnored private var upNextLoading = false
    /// 随机、循环、音量、喜欢刚点过时，读数先不盖掉它。
    @ObservationIgnored private var heldExtras: (until: Date, apply: (inout NowPlaying) -> Void)?

    /// How long a reading may contradict what was just asked for before it is
    /// believed. Long enough for the player to hear the command and be read
    /// again, short enough that a command which never landed corrects itself.
    private static let commandHold: TimeInterval = 1.5

    /// How long after one of our own commands a timed-out probe is treated as
    /// our own traffic rather than as the player refusing.
    private static let commandGrace: TimeInterval = 5

    /// Set once a probe has hung; cleared when the user asks to connect.
    @ObservationIgnored private var blocked = false
    @ObservationIgnored private var lastProbe: Date = .distantPast

    /// Only a playing track needs second-by-second refreshing, for its scrubber.
    private var probeInterval: TimeInterval {
        if players.contains(where: { $0.track?.isPlaying == true }) { return 0.85 }
        return nowPlaying == nil && players.isEmpty ? 8 : 5
    }
    @ObservationIgnored private var artworkKey: String?

    private init() {}

    // MARK: Lifecycle

    /// Idempotent; every Now Playing tile on the shelf shares one poll.
    public func start() {
        guard timer == nil else { return }
        refresh()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// 卡片和面板从配置同步来源和切换设置。
    public func configure(_ config: WidgetConfig) {
        let sources = MusicSource.enabled(in: config)
        if enabled != sources { enabled = sources }
        let auto = MusicSourceSwitch.autoSwitch(config)
        let pin = MusicSourceSwitch.pinned(config)
        if pinned != pin || autoSwitch != auto {
            pinned = pin
            autoSwitch = auto
            manual = false
            reselect()
        }
    }

    // MARK: Reading

    public func refresh() {
        // Every reason not to poll is weighed *before* the in-flight flag is
        // armed: arming it first and returning on the throttle leaked the flag
        // and wedged the service for the life of the process.
        let now = Date.now
        guard PollGate.shouldStart(inFlight: polling,
                                   blocked: blocked,
                                   sinceLastStart: now.timeIntervalSince(lastProbe),
                                   interval: probeInterval) else { return }
        polling = true
        lastProbe = now
        let sources = enabled
        let favoriteFor = current == .appleMusic
        Task { [sources] in
            let result = await withTimeout(seconds: 2.5) {
                await Bridge.probe(sources, readFavorite: favoriteFor)
            }
            if let result {
                await self.apply(result)
            } else {
                self.stall()
            }
        }
    }

    /// The probe hung. Slowness is not refusal: a player that has answered
    /// before is waited on, and only one that never has gets the Connect
    /// button after three strikes.
    private func stall() {
        polling = false
        lastProbe = .now
        guard Date().timeIntervalSince(lastCommand) >= Self.commandGrace else { return }
        timeouts += 1
        if Self.hasAnswered {
            lastProbe = Date().addingTimeInterval(min(30, 2 * Double(timeouts)))
            return
        }
        guard timeouts >= 3 else { return }
        blocked = true
        needsAutomationPermission = true
    }

    /// Whether a player has ever answered one of Docket's probes.
    private static var hasAnswered: Bool {
        get { UserDefaults.standard.bool(forKey: "music.hasAnswered") }
        set { UserDefaults.standard.set(newValue, forKey: "music.hasAnswered") }
    }

    private func apply(_ result: Bridge.Probe) async {
        defer { polling = false }
        timeouts = 0
        let hasTrack = result.players.contains { $0.track != nil }
        needsAutomationPermission = result.needsPermission && !hasTrack
        if result.sawRunningPlayer, !needsAutomationPermission { Self.hasAnswered = true }
        hasPlayer = result.sawRunningPlayer

        // 一次失败的读数（脚本超时、读到一半）不该把正在显示的曲目清掉：
        // 还开着的来源这次没读到，沿用上次的曲目。
        var next: [Player] = []
        for reading in result.players {
            var track = reading.track
            if track == nil, !reading.source.readsNowPlaying, !reading.idle,
               let old = players.first(where: { $0.source == reading.source })?.track {
                track = old
            }
            next.append(Player(source: reading.source, track: track))
        }
        recordRecent(next)
        players = next

        let chosen = decide()
        if current != chosen { current = chosen; asked = nil; artworkKey = nil }

        let ref = result.players.first(where: { $0.source == chosen })?.artworkRef
        await show(next.first(where: { $0.source == chosen })?.track, artworkRef: ref)
        refreshUpNext()
    }

    // MARK: 当前显示来源

    /// 允许的浏览器标签页此刻的样子。
    private var browserState: MusicCardChoice.Browser? {
        guard BrowserMedia.shared.enabled, let track = BrowserMedia.shared.track else { return nil }
        return MusicCardChoice.Browser(hasTrack: true, isPlaying: track.isPlaying)
    }

    private func corePlayers(_ list: [Player]) -> [MusicSourceSwitch.Player] {
        list.map { MusicSourceSwitch.Player(source: $0.source, hasTrack: $0.track != nil, isPlaying: $0.track?.isPlaying == true) }
    }

    /// 按 Core `MusicDisplay.pick` 定下 `display`，记下这次的播放状态，返回该给按钮
    /// 控制的播放器来源（显示浏览器时沿用上一个）。
    private func decide() -> MusicSource? {
        let list = corePlayers(players)
        let browser = browserState
        let pick = MusicDisplay.pick(players: list, browser: browser, wasPlaying: wasPlaying,
                                     browserWasPlaying: browserWasPlaying, current: display,
                                     manual: manual, pinned: pinned, autoSwitch: autoSwitch)
        if manual {
            manual = pick == display && MusicDisplay.keepsManual(
                players: list, browser: browser, wasPlaying: wasPlaying,
                browserWasPlaying: browserWasPlaying, current: display)
        }
        wasPlaying = Dictionary(list.map { ($0.source, $0.isPlaying) }, uniquingKeysWith: { a, _ in a })
        browserWasPlaying = browser?.isPlaying == true
        if display != pick { display = pick }
        switch pick {
        case .native(let source): return source
        case .browser: return current
        case .none: return nil
        }
    }

    /// 浏览器标签页开始或停止播放：卡片看到变化时叫一下，不等下一次轮询。
    public func reconcile() {
        let chosen = decide()
        guard chosen != current else { return }
        current = chosen
        asked = nil
        artworkKey = nil
        nowPlaying = players.first(where: { $0.source == chosen })?.track
        lastProbe = .distantPast
        refresh()
    }

    // MARK: 卡片

    /// 给 Core 用的样子。显示中的来源用 `nowPlaying` 的播放状态（刚点过暂停时它先变）。
    public var switchPlayers: [MusicSourceSwitch.Player] {
        players.map { player in
            let track = player.source == current ? (nowPlaying ?? player.track) : player.track
            return MusicSourceSwitch.Player(source: player.source, hasTrack: track != nil,
                                            isPlaying: track?.isPlaying == true)
        }
    }

    /// 某个来源此刻的曲目：显示中的来源就是 `nowPlaying`，别的来源用列表里的读数。
    public func track(for source: MusicSource) -> NowPlaying? {
        if source == current { return nowPlaying }
        return players.first(where: { $0.source == source })?.track
    }

    /// 来源变了（用户在面板里点、固定来源改了）就用已有的读数立即换上，不等下一次轮询。
    private func reselect() {
        let chosen = decide()
        guard chosen != current else { return }
        current = chosen
        asked = nil
        artworkKey = nil
        nowPlaying = players.first(where: { $0.source == chosen })?.track
        lastProbe = .distantPast
        refresh()
    }

    private func show(_ reading: NowPlaying?, artworkRef: Bridge.ArtworkRef?) async {
        guard var track = reading else {
            nowPlaying = nil
            artworkKey = nil
            upNext = nil
            return
        }

        // A probe already in flight when the button was pressed comes back
        // describing the player as it was; held until a reading agrees.
        if let asked {
            if track.isPlaying == asked || Date().timeIntervalSince(lastCommand) >= Self.commandHold {
                self.asked = nil
            } else {
                track.isPlaying = asked
            }
        }
        if let held = heldExtras {
            if Date() < held.until { held.apply(&track) } else { heldExtras = nil }
        }

        if track.trackKey == artworkKey {
            track.artwork = nowPlaying?.artwork
            track.tint = nowPlaying?.tint
            nowPlaying = track
            return
        }

        // Show the new track immediately; artwork catches up a moment later.
        artworkKey = track.trackKey
        nowPlaying = track

        let key = track.trackKey
        // Budgeted: an Apple Music artwork event can hang indefinitely.
        let found = await withTimeout(seconds: 5) {
            await Bridge.artwork(for: artworkRef)
        }
        guard artworkKey == key, var latest = nowPlaying, latest.trackKey == key else { return }
        latest.artwork = found?.image
        latest.tint = found?.tint
        nowPlaying = latest
    }

    // MARK: 刚才听过

    private func recordRecent(_ next: [Player]) {
        guard let track = next.first(where: { $0.source == .spotify })?.track,
              track.isPlaying, let uri = track.trackID, uri != lastRecorded else { return }
        lastRecorded = uri
        var list = recent
        list.record(.init(uri: uri, title: track.title, artist: track.artist,
                          duration: track.duration, artworkURL: track.artworkURL?.absoluteString))
        guard list != recent else { return }
        recent = list
        UserDefaults.standard.set(list.encoded(), forKey: MusicRecent.defaultsKey)
    }

    public func clearRecent() {
        recent.clear()
        UserDefaults.standard.removeObject(forKey: MusicRecent.defaultsKey)
    }

    public func replay(_ entry: MusicRecent.Entry) {
        guard let body = MusicRecent.playCommand(entry.uri) else { return }
        select(.spotify)
        lastCommand = .now
        Bridge.send(body, to: .spotify, cache: false)
        lastProbe = .distantPast
    }

    // MARK: 接下来

    private func refreshUpNext() {
        guard wantsUpNext, let track = nowPlaying, track.source == .appleMusic,
              MusicUpNext.visible(shuffle: track.shuffle ?? false), let id = track.trackID else {
            if nowPlaying?.source != .appleMusic { upNext = nil; upNextKey = nil }
            return
        }
        let wrap = track.repeatMode == .all
        let key = "\(id)|\(wrap)"
        guard key != upNextKey, !upNextLoading else { return }
        upNextLoading = true
        Task {
            let list = await withTimeout(seconds: 4) { await Bridge.upNext(wrap: wrap) }
            self.upNextLoading = false
            // 读的时候歌已经换了就作废，下一次轮询再读。
            guard self.nowPlaying?.trackID == id else { return }
            self.upNextKey = key
            self.upNext = list ?? nil
        }
    }

    public func play(_ item: UpNext.Item) {
        guard let id = Int(item.id) else { return }
        lastCommand = .now
        Bridge.send("play (some track of current playlist whose database ID is \(id))", to: .appleMusic, cache: false)
        lastProbe = .distantPast
    }

    // MARK: Choosing a source

    /// 用户在面板里点了一个来源：卡片和面板都显示它（算手点，别的来源开始播放或它
    /// 关了才换走）。自动切换关着时由面板把它写成固定来源。
    public func select(_ source: MusicSource) {
        manual = true
        if display != .native(source) { display = .native(source) }
        guard current != source else { return }
        current = source
        asked = nil
        artworkKey = nil
        upNext = nil
        upNextKey = nil
        nowPlaying = players.first(where: { $0.source == source })?.track
        lastProbe = .distantPast
        refresh()
    }

    /// 这个来源能不能直接控制：网易云、QQ 只在它是系统「正在播放」时才行，
    /// 否则媒体键会落到别的 App 上。
    public func canControl(_ source: MusicSource) -> Bool {
        guard let player = players.first(where: { $0.source == source }) else { return false }
        return !source.readsNowPlaying || player.track != nil
    }

    /// 打开或切到这个播放器（「在 App 中打开」「打开 X」）。不播放任何东西。
    public func open(_ source: MusicSource) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleID) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in }
    }

    nonisolated public static func isInstalled(_ source: MusicSource) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleID) != nil
    }

    // MARK: Transport

    public func playPause() { command("playpause") }

    /// 列表里别的来源的播放键：切过去再播放/暂停。
    public func playPause(_ source: MusicSource) {
        select(source)
        command("playpause")
    }

    /// 「其他开着的」里点播放：只把显示切到这个来源并让它放，不改固定；已经在放就
    /// 只切显示。
    public func showAndPlay(_ source: MusicSource) {
        select(source)
        guard players.first(where: { $0.source == source })?.track?.isPlaying != true else { return }
        command("playpause")
    }

    public func next() { command("next track") }

    // 卡片上的按钮：控制卡片显示的那个来源，不换面板的来源（固定着时也不动它）。

    public func playPause(on source: MusicSource) {
        guard source != current else { return playPause() }
        command("playpause", to: source)
    }

    public func next(on source: MusicSource) {
        guard source != current else { return next() }
        command("next track", to: source)
    }

    public func previous(on source: MusicSource) {
        guard source != current else { return previous() }
        guard let track = track(for: source) else { return }
        if source.canSeek && track.elapsed > 3 {
            seek(on: source, to: 0)
        } else {
            optimistically(source) { $0.elapsed = 0 }
            Bridge.send("previous track", to: source)
        }
    }

    public func seek(on source: MusicSource, to seconds: TimeInterval) {
        guard source != current else { return seek(to: seconds) }
        guard let track = track(for: source), source.canSeek else { return }
        let target = max(0, track.duration > 0 ? min(seconds, track.duration) : seconds)
        optimistically(source) { $0.elapsed = target }
        lastCommand = .now
        Bridge.send("set player position to \(String(format: "%.2f", target))", to: source)
    }

    public func skip(on source: MusicSource, by seconds: TimeInterval) {
        guard let track = track(for: source) else { return }
        seek(on: source, to: track.elapsed + seconds)
    }

    /// 发给不是面板来源的播放器。
    private func command(_ body: String, to source: MusicSource) {
        guard canControl(source) else { return }
        if body == "playpause" { optimistically(source) { $0.isPlaying.toggle() } }
        lastCommand = .now
        Bridge.send(body, to: source)
    }

    /// 不是面板来源的播放器：先改列表里的读数，下一次轮询换成真的。
    private func optimistically(_ source: MusicSource, _ change: (inout NowPlaying) -> Void) {
        guard let index = players.firstIndex(where: { $0.source == source }),
              var track = players[index].track else { return }
        change(&track)
        players[index].track = track
    }

    /// What both apps do natively: restart the track if we are past the first
    /// few seconds, otherwise step back one.
    public func previous() {
        guard let source = nowPlaying?.source else { return }
        let restart = source.canSeek && (nowPlaying?.elapsed ?? 0) > 3
        if restart {
            seek(to: 0)
        } else {
            optimistically { $0.elapsed = 0 }
            Bridge.send("previous track", to: source)
        }
    }

    public func seek(to seconds: TimeInterval) {
        guard let track = nowPlaying, track.source.canSeek else { return }
        let target = max(0, track.duration > 0 ? min(seconds, track.duration) : seconds)
        optimistically { $0.elapsed = target }
        Bridge.send("set player position to \(String(format: "%.2f", target))", to: track.source)
    }

    /// Skip forward (positive) or back (negative) from where we are.
    public func skip(by seconds: TimeInterval) {
        guard let track = nowPlaying else { return }
        seek(to: track.elapsed + seconds)
    }

    private func command(_ body: String) {
        guard let source = nowPlaying?.source ?? current, canControl(source) else { return }
        // 对显示中的来源按了键：留在它上面，暂停后不被固定的来源顶掉。
        if display == .native(source) { manual = true }
        if body == "playpause" {
            optimistically { $0.isPlaying.toggle() }
            asked = nowPlaying?.isPlaying
        }
        lastCommand = .now
        Bridge.send(body, to: source)
    }

    // MARK: 随机、循环、音量、喜欢

    public func setShuffle(_ on: Bool) {
        guard let source = nowPlaying?.source, source.hasShuffleAndRepeat else { return }
        hold { $0.shuffle = on }
        let body = source == .appleMusic ? "set shuffle enabled to \(on)" : "set shuffling to \(on)"
        lastCommand = .now
        Bridge.send(body, to: source)
    }

    public func cycleRepeat() {
        guard let track = nowPlaying, track.source.hasShuffleAndRepeat else { return }
        let mode = (track.repeatMode ?? .off).next(allowsOne: track.source.hasRepeatOne)
        hold { $0.repeatMode = mode }
        let body = track.source == .appleMusic
            ? "set song repeat to \(mode.rawValue)"
            : "set repeating to \(mode != .off)"
        lastCommand = .now
        Bridge.send(body, to: track.source)
    }

    /// 0…100。拖动时一直调，脚本按整数缓存，最多 101 份。
    public func setVolume(_ percent: Double) {
        guard let source = nowPlaying?.source, MusicVolumeRoute.route(for: source, recordingGranted: false) == .player else { return }
        let value = Int(min(100, max(0, percent)).rounded())
        hold { $0.volume = Double(value) }
        lastCommand = .now
        Bridge.send("set sound volume to \(value)", to: source)
    }

    public func toggleFavorite() {
        guard let track = nowPlaying, track.source.hasFavorite else { return }
        let on = !(track.favorited ?? false)
        hold { $0.favorited = on }
        lastCommand = .now
        Bridge.setFavorite(on)
    }

    /// 改完先显示新值，接下来 2 秒的读数（可能是改之前发出的）不盖掉它。
    private func hold(_ change: @escaping (inout NowPlaying) -> Void) {
        optimistically(change)
        heldExtras = (Date().addingTimeInterval(2), change)
    }

    /// Update the local reading straight away so a tap feels instant; the next
    /// poll (≤1s) replaces it with the truth either way.
    private func optimistically(_ change: (inout NowPlaying) -> Void) {
        guard var track = nowPlaying else { return }
        change(&track)
        nowPlaying = track
        if let index = players.firstIndex(where: { $0.source == track.source }) {
            players[index].track = track
        }
    }

    // MARK: Permission

    /// The only place that is allowed to raise the system consent dialog, and
    /// it runs solely because the user clicked "Connect".
    public func requestAutomationPermission() {
        let sources = enabled
        let policy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        blocked = false
        polling = false
        timeouts = 0
        lastProbe = .distantPast
        Task { [sources] in
            await Bridge.ask(sources)
            NSApp.setActivationPolicy(policy)
            self.refresh()
        }
    }
}

// MARK: - Apple event plumbing

/// Everything that talks to another process, kept off the main thread.
///
/// AppleScript execution is serialised onto one queue: `NSAppleScript` is not
/// documented as thread-safe, and a 1s poll has no need for concurrency.
enum Bridge {
    struct Reading: Sendable {
        var source: MusicSource
        var track: NowPlaying?
        var artworkRef: ArtworkRef?
        /// 播放器明确说没在放（stopped），而不是脚本失败。
        var idle = false
    }

    struct Probe: Sendable {
        var players: [Reading] = []
        var needsPermission = false
        /// Distinguishes "nothing is running" from "the script failed", so a
        /// transient error does not blank the tile.
        var sawRunningPlayer = false
    }

    /// How to obtain artwork for the track we just read.
    enum ArtworkRef: Sendable {
        case url(URL)          // Spotify hands out an https image URL
        case appleMusic        // Music hands out raw bytes, over another event
        case nowPlaying        // 网易云音乐 / QQ 音乐: the system's Now Playing artwork
    }

    private static let queue = DispatchQueue(label: "com.namanparashar.plinth.music")

    private static func offMain<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    // MARK: Probing

    /// 每个开着的来源都读一次（来源列表和「谁开始播放」都要看全部），系统「正在
    /// 播放」只读一次，网易云、QQ、小宇宙各自对一下是不是自己。
    ///
    /// Consent is judged from the result of the actual Apple Event, never from
    /// `AEDeterminePermissionToAutomateTarget`, which blocks.
    static func probe(_ sources: [MusicSource], readFavorite: Bool) async -> Probe {
        await offMain {
            var result = Probe()
            var system: NowPlayingInfo??
            for source in sources where isRunning(source) {
                result.sawRunningPlayer = true
                if source.readsNowPlaying {
                    if system == nil { system = .some(NowPlayingReader.info()) }
                    let track = system.flatMap { $0 }.flatMap { NowPlayingReader.track(from: $0, source: source) }
                    result.players.append(Reading(source: source, track: track,
                                                  artworkRef: track == nil ? nil : .nowPlaying))
                    continue
                }
                switch read(source) {
                case .denied:
                    result.needsPermission = true
                    result.players.append(Reading(source: source, track: nil))
                case .idle:
                    result.players.append(Reading(source: source, track: nil, idle: true))
                case .failed:
                    result.players.append(Reading(source: source, track: nil))
                case .track(var track, let artwork):
                    if source == .appleMusic, readFavorite { track.favorited = favorite() }
                    result.players.append(Reading(source: source, track: track, artworkRef: artwork))
                }
            }
            return result
        }
    }

    /// The image and the colour behind it, together.
    static func artwork(for ref: ArtworkRef?) async -> (image: NSImage?, tint: ArtworkTint?) {
        switch ref {
        case .none:
            return (nil, nil)
        case .url(let url):
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return (nil, nil) }
            return (NSImage(data: data), ArtworkTint.extract(data))
        case .appleMusic:
            let data = await offMain { () -> Data? in
                guard case .value(let descriptor) = script(
                    "tell application id \"com.apple.Music\" to get raw data of artwork 1 of current track"
                ) else { return nil }
                return descriptor.data
            }
            guard let data, !data.isEmpty else { return (nil, nil) }
            return (NSImage(data: data), ArtworkTint.extract(data))
        case .nowPlaying:
            let data = await offMain { NowPlayingReader.artwork() }
            guard let data, !data.isEmpty else { return (nil, nil) }
            return (NSImage(data: data), ArtworkTint.extract(data))
        }
    }

    // MARK: Apple 音乐的喜欢和接下来

    /// macOS 14 起叫 favorited，之前叫 loved。两份脚本分开编译：词典里没有的词
    /// 让整份脚本编译失败，放在一起就连另一个也读不到。
    private static let favoritedScript = "tell application id \"com.apple.Music\" to return (favorited of current track) as text"
    private static let lovedScript = "tell application id \"com.apple.Music\" to return (loved of current track) as text"

    private static func favorite() -> Bool? {
        for source in [favoritedScript, lovedScript] {
            if case .value(let descriptor) = script(source), let text = descriptor.stringValue {
                return text == "true"
            }
        }
        return nil
    }

    static func setFavorite(_ on: Bool) {
        guard isRunning(.appleMusic) else { return }
        queue.async {
            guard permitted(.appleMusic, ask: false) else { return }
            if case .value = script("tell application id \"com.apple.Music\" to set favorited of current track to \(on)") { return }
            _ = script("tell application id \"com.apple.Music\" to set loved of current track to \(on)")
        }
    }

    /// 当前歌单名、当前这首在歌单里第几首、歌单共几首，再按 `MusicUpNext` 取后面几首。
    static func upNext(wrap: Bool) async -> MusicService.UpNext? {
        await offMain {
            guard isRunning(.appleMusic) else { return nil }
            let locate = """
            tell application id "com.apple.Music"
                if player state is stopped then return ""
                set p to current playlist
                set did to database ID of current track
                set i to 0
                try
                    set i to index of (first track of p whose database ID is did)
                end try
                return (name of p) & tab & (i as text) & tab & ((count of tracks of p) as text)
            end tell
            """
            guard case .value(let found) = script(locate), let raw = found.stringValue else { return nil }
            let f = raw.components(separatedBy: "\t")
            guard f.count == 3, let index = Int(f[1]), let count = Int(f[2]) else { return nil }
            let indices = MusicUpNext.indices(current: index, count: count, wrap: wrap)
            guard !indices.isEmpty else { return MusicService.UpNext(playlist: f[0], items: []) }
            let list = indices.map(String.init).joined(separator: ", ")
            let body = """
            tell application id "com.apple.Music"
                set p to current playlist
                set out to ""
                repeat with j in {\(list)}
                    set t to track (j as integer) of p
                    set out to out & ((database ID of t) as text) & tab & (name of t) & tab & (artist of t) & tab & ((duration of t) as text) & linefeed
                end repeat
                return out
            end tell
            """
            guard case .value(let rows) = script(body, cache: false), let text = rows.stringValue else {
                return MusicService.UpNext(playlist: f[0], items: [])
            }
            let items = text.split(separator: "\n").compactMap { line -> MusicService.UpNext.Item? in
                let c = line.components(separatedBy: "\t")
                guard c.count >= 4, !c[1].isEmpty else { return nil }
                return .init(id: c[0], title: c[1], artist: c[2], duration: Double(c[3]) ?? 0)
            }
            return MusicService.UpNext(playlist: f[0], items: items)
        }
    }

    // MARK: Commands

    static func send(_ body: String, to source: MusicSource, cache: Bool = true) {
        guard isRunning(source) else { return }
        if source.readsNowPlaying {
            switch body {
            case "playpause": MediaKeys.press(.playPause)
            case "next track": MediaKeys.press(.next)
            case "previous track": MediaKeys.press(.previous)
            default: break
            }
            return
        }
        let id = source.bundleID
        queue.async {
            guard permitted(source, ask: false) else { return }
            _ = script("tell application id \"\(id)\" to \(body)", cache: cache)
        }
    }

    static func ask(_ sources: [MusicSource]) async {
        await offMain {
            for source in sources where isRunning(source) && !source.readsNowPlaying {
                // A real event raises the dialog; the permission-check API
                // blocks instead of prompting.
                _ = script("tell application id \"\(source.bundleID)\" to return name")
            }
        }
    }

    // MARK: Primitives

    static func isRunning(_ source: MusicSource) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleID).isEmpty
    }

    /// `askUserIfNeeded: false` unless the user explicitly asked to connect -
    /// otherwise every launch throws a consent sheet at them.
    static func permitted(_ source: MusicSource, ask: Bool) -> Bool {
        guard let target = NSAppleEventDescriptor(bundleIdentifier: source.bundleID).aeDesc else { return false }
        return AEDeterminePermissionToAutomateTarget(target, typeWildCard, typeWildCard, ask) == noErr
    }

    enum ScriptOutcome {
        case value(NSAppleEventDescriptor)
        /// The Apple Event was refused, or consent has never been given.
        case denied
        case failed
    }

    /// Compiled scripts, keyed by source. Confined to the serial queue.
    nonisolated(unsafe) private static var compiled: [String: NSAppleScript] = [:]

    private static func script(_ source: String, cache: Bool = true) -> ScriptOutcome {
        let script: NSAppleScript
        if let cached = compiled[source] {
            script = cached
        } else {
            guard let made = NSAppleScript(source: source) else { return .failed }
            made.compileAndReturnError(nil)
            if cache { compiled[source] = made }
            script = made
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard let error else { return .value(result) }
        // -1743 not permitted, -1744 consent never granted.
        let code = (error[NSAppleScript.errorNumber] as? Int) ?? 0
        return (code == -1743 || code == -1744) ? .denied : .failed
    }

    /// One round trip per player. Fields are tab-separated because a track
    /// title can contain almost anything else.
    enum PlayerReading {
        case track(NowPlaying, ArtworkRef?)
        case idle
        case failed
        case denied
    }

    /// 前 6 项两家一样；后面的随机、循环、音量、曲目 id 包在 try 里，读不到
    /// （电台、广告）也不影响曲目本身。
    private static func read(_ source: MusicSource) -> PlayerReading {
        let id = source.bundleID
        let extras = source == .spotify
            ? "(shuffling as text) & tab & (repeating as text) & tab & (sound volume as text) & tab & (id of t) & tab & (artwork url of t)"
            : "(shuffle enabled as text) & tab & (song repeat as text) & tab & (sound volume as text) & tab & ((database ID of t) as text)"
        let body = """
        tell application id "\(id)"
            if player state is stopped then return ""
            set t to current track
            set ex to ""
            try
                set ex to \(extras)
            end try
            return (name of t) & tab & (artist of t) & tab & (album of t) & tab \
        & ((duration of t) as text) & tab & ((player position) as text) & tab \
        & (player state as text) & tab & ex
        end tell
        """
        let outcome = script(body)
        guard case .value(let descriptor) = outcome else {
            if case .denied = outcome { return .denied }
            return .failed
        }
        guard let raw = descriptor.stringValue, !raw.isEmpty else { return .idle }
        let f = raw.components(separatedBy: "\t")
        guard f.count >= 6, !f[0].isEmpty else { return .idle }

        // Spotify reports duration in milliseconds, Music in seconds.
        let rawDuration = Double(f[3]) ?? 0
        let duration = source == .spotify ? rawDuration / 1000 : rawDuration

        var track = NowPlaying(
            title: f[0], artist: f[1], album: f[2],
            duration: max(0, duration),
            elapsed: max(0, Double(f[4]) ?? 0),
            isPlaying: f[5] == "playing",
            artwork: nil, source: source
        )
        // A live stream reports no duration; clamp rather than draw a scrubber
        // past its own end.
        if track.duration > 0 { track.elapsed = min(track.elapsed, track.duration) }

        if f.count >= 10, !f[6].isEmpty {
            track.shuffle = f[6] == "true"
            track.repeatMode = source == .spotify ? (f[7] == "true" ? .all : .off) : MusicRepeat(appleScript: f[7])
            track.volume = Double(f[8].replacingOccurrences(of: ",", with: "."))
            track.trackID = f[9].isEmpty ? nil : f[9]
        }
        var ref: ArtworkRef? = source == .appleMusic ? .appleMusic : nil
        if source == .spotify, f.count >= 11, let url = URL(string: f[10]), url.scheme != nil {
            track.artworkURL = url
            ref = .url(url)
        }
        return .track(track, ref)
    }
}

// MARK: - Formatting

enum MusicTime {
    /// `m:ss`, growing to `h:mm:ss` for anything an hour long.
    static func clock(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let (h, m, s) = (total / 3600, (total / 60) % 60, total % 60)
        return h > 0
            ? "\(h):\(String(format: "%02d:%02d", m, s))"
            : "\(m):\(String(format: "%02d", s))"
    }
}
