import Foundation
import Observation
@preconcurrency import UserNotifications

/// 系统活动的超阈值提醒（码头 Pro）：按规则判断，到点发系统通知，卡片上那个读数变红。
///
/// 由 SystemMetrics 每秒的采样喂进来，每 5 秒判断一次，所以不靠卡片在屏幕上。
/// 规则读第一个系统活动小组件的 `alertRules`（见 `SystemAlertRules`）；一个都
/// 没有就什么也不做。判断逻辑在 Core 的 `SystemAlertTracker`。
@MainActor @Observable
final class SystemAlerts {
    static let shared = SystemAlerts()

    /// 正在提醒的指标，卡片和面板读它把读数画红。
    private(set) var firing: Set<SystemMetricKind> = []

    @ObservationIgnored var rules: @MainActor () -> [SystemAlertRule]? = { nil }
    @ObservationIgnored private var tracker = SystemAlertTracker()
    @ObservationIgnored private var lastCheck = Date.distantPast
    @ObservationIgnored private var asked = false
    @ObservationIgnored private let presenter = BannerPresenter()

    private init() {}

    func check(_ reading: SystemAlertReading) {
        let now = Date.now
        guard now.timeIntervalSince(lastCheck) >= 5 else { return }
        lastCheck = now
        guard let rules = rules() else {
            tracker = SystemAlertTracker()
            if !firing.isEmpty { firing = [] }
            return
        }
        let result = tracker.check(reading, rules: rules, unlocked: ProAccess.isUnlocked, now: now)
        if result.firing != firing { firing = result.firing }
        for alert in result.alerts {
            Task { await post(alert) }
        }
    }

    private func post(_ alert: SystemAlert) async {
        let center = UNUserNotificationCenter.current()
        if center.delegate == nil { center.delegate = presenter }
        if !asked {
            asked = true
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        let request = UNNotificationRequest(identifier: "docket.system.\(alert.ruleID)",
                                            content: content, trigger: nil)
        try? await center.add(request)
    }
}
