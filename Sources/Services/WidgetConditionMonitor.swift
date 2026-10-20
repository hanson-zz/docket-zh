import Foundation
import Observation

/// Keeps `WidgetConditions` current for the shelf's visibility rules.
///
/// A widget hidden by its condition has no tile on screen, and every tile
/// starts its own service on appear, so nothing would ever notice the
/// condition coming true again. This starts the services the rules need,
/// samples them once a second, and publishes one value that changes only
/// when a condition does: the shelf observes that, not a player's scrubber.
@MainActor @Observable
final class WidgetConditionMonitor {
    static let shared = WidgetConditionMonitor()

    private(set) var conditions: WidgetConditions = .unknown

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var watched: Set<WidgetKind> = []

    private init() {}

    /// The kinds whose condition currently matters.
    static func conditionalKinds(in items: [DockItem]) -> Set<WidgetKind> {
        Set(items.compactMap(\.widget).filter {
            WidgetVisibility.mode($0.config) == .conditional
                && WidgetVisibility.supportsCondition($0.kind)
        }.map(\.kind))
    }

    /// 按条件显示的「正在播放」卡片允不允许读浏览器标签页（任一张允许就算）；
    /// 没有这样的卡片是 nil。卡片藏着时没人替它同步这个开关。
    static func musicBrowsersAllowed(in items: [DockItem]) -> Bool? {
        let music = items.compactMap(\.widget).filter {
            $0.kind == .music && WidgetVisibility.mode($0.config) == .conditional
        }
        guard !music.isEmpty else { return nil }
        return music.contains { $0.config.bool("browsers", default: true) }
    }

    func watch(_ kinds: Set<WidgetKind>) {
        watched = kinds
        guard !kinds.isEmpty else {
            timer?.invalidate()
            timer = nil
            return
        }
        // The services are idempotent and shared with the tiles; starting
        // one the user already has a tile for costs nothing.
        // 浏览器标签页在播也算「正在播放」，卡片藏着时也得有人读它。
        if kinds.contains(.music) { MusicService.shared.start(); BrowserMedia.shared.start() }
        if kinds.contains(.battery) { BatteryMetrics.shared.start() }
        if kinds.contains(.mail) { MailService.shared.start() }
        if kinds.contains(.microphone) { MicrophoneMonitor.shared.start() }
        if kinds.contains(.aiUsage) { CodexService.shared.startActivity() }
        sample()
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func sample() {
        var next = WidgetConditions()
        if watched.contains(.music) {
            let music = MusicService.shared
            // Waiting on consent is not "nothing playing": the tile has to
            // stay up so its connect button can be pressed.
            // 任一播放器或允许的浏览器标签页在播就算，和面板固定在哪个来源无关
            // （Core `MusicCardChoice.anyPlaying`）。
            let browser = BrowserMedia.shared.enabled
                ? BrowserMedia.shared.track.map { MusicCardChoice.Browser(hasTrack: true, isPlaying: $0.isPlaying) }
                : nil
            next.musicPlaying = music.needsAutomationPermission
                ? nil : MusicCardChoice.anyPlaying(players: music.switchPlayers, browser: browser)
        }
        if watched.contains(.battery), let mac = BatteryMetrics.shared.device(.mac), mac.present {
            next.onBattery = !mac.onPower
            next.batteryLevel = mac.level
        }
        if watched.contains(.microphone) {
            let mic = MicrophoneMonitor.shared
            next.micInUse = mic.hasDevice ? mic.inUse : false
        }
        if watched.contains(.mail) {
            switch MailService.shared.state {
            case .unread(let count): next.mailUnread = count
            // Closed Mail has nothing to report, so the badge has nothing to say.
            case .notRunning: next.mailUnread = 0
            // A refusal or a failure stays visible so the tile can say so.
            case .denied, .failed: next.mailUnread = nil
            }
        }
        if watched.contains(.aiUsage) {
            let activity = CodexService.shared.activity
            next.codexActive = activity == .working || activity == .waiting
        }
        if watched.contains(.ambient) {
            next.ambientPlaying = AmbientPlayer.shared.isPlaying
        }
        if watched.contains(.radio) {
            next.radioPlaying = RadioPlayer.shared.isPlaying
        }
        // Read by GitHubService on its own schedule, which the shelf keeps
        // for every GitHub widget whether or not its tile is showing.
        if watched.contains(.github) {
            next.githubFeedback = GitHubService.shared.feedbackCounts
        }
        if next != conditions { conditions = next }
    }
}
