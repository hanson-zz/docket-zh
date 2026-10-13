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

    func watch(_ kinds: Set<WidgetKind>) {
        watched = kinds
        guard !kinds.isEmpty else {
            timer?.invalidate()
            timer = nil
            return
        }
        // The services are idempotent and shared with the tiles; starting
        // one the user already has a tile for costs nothing.
        if kinds.contains(.music) { MusicService.shared.start() }
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
            next.musicPlaying = music.needsAutomationPermission ? nil : (music.nowPlaying?.isPlaying ?? false)
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
        if next != conditions { conditions = next }
    }
}
