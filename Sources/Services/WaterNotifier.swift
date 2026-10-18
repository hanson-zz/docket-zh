import Foundation
@preconcurrency import UserNotifications

/// Schedules the 喝水 widget's reminder, the way PostureNotifier schedules
/// the stand-up one.
///
/// One pending request per widget, replaced whenever the next reminder moves:
/// a drink is logged, the goal is met, the interval or the hours change, or
/// an ignored one fires and the next repeat comes due. `WaterReminder` already
/// skips the hours outside the window, the rest of a day whose goal is met,
/// and anything sooner than an interval after the last drink. Permission is
/// asked the first time a reminder is scheduled, not at launch.
@MainActor
final class WaterNotifier {
    static let shared = WaterNotifier()

    private var scheduled: [UUID: Date] = [:]
    private var asked = false
    private let presenter = BannerPresenter()

    private init() {}

    private static func identifier(_ id: UUID) -> String { "docket.water.\(id.uuidString)" }

    /// `next` nil (reminders off) withdraws the pending one.
    func update(_ instance: WidgetInstance, next: Date?) {
        let id = Self.identifier(instance.id)
        guard let next else {
            if scheduled.removeValue(forKey: instance.id) != nil {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
            }
            return
        }
        if let existing = scheduled[instance.id], abs(existing.timeIntervalSince(next)) < 1 { return }
        scheduled[instance.id] = next
        // The words are fixed now; any drink before then reschedules, which
        // rewrites them with the new amount still to go.
        // One that waits for tomorrow starts the day from nothing.
        let today = WaterIntake.today(instance.config)
        let total = WaterIntake.calendar.isDate(next, inSameDayAs: .now) ? today.total : 0
        let message = WaterReminder.message(at: next, total: total, goal: today.goal,
                                            ounces: WaterIntake.usesOunces(instance.config))
        Task { await schedule(id: id, at: next, title: message.title, body: message.body) }
    }

    private func schedule(id: String, at date: Date, title: String, body: String) async {
        let center = UNUserNotificationCenter.current()
        if center.delegate == nil { center.delegate = presenter }
        if !asked {
            asked = true
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        // 提醒音效里喝水选了“不响”或音效总开关关着时不带声音。应用在运行时
        // 由 BannerPresenter 换成所选的音色播放，见 ReminderSoundPlayer。
        content.sound = ReminderSoundPlayer.shared.notificationHasSound(.water) ? .default : nil
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow),
                                                        repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try? await center.add(request)
    }
}
