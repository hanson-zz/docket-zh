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
///
/// 设置里喝水的「到点弹出卡片」开着时（默认）不排系统通知，改为应用里的计时器
/// 到点弹出码头自己的卡片（`ReminderPopupCenter`），同一次提醒不会出现两回；
/// 码头没在运行时也就不提醒。关掉时照旧排系统通知。合盖睡眠醒来时晚了太久的
/// 那一次不补弹，下一次照常。
@MainActor
final class WaterNotifier {
    static let shared = WaterNotifier()

    private var scheduled: [UUID: Date] = [:]
    private var asked = false
    private let presenter = BannerPresenter()
    /// 弹卡片时用的计时器，每个小组件一个。
    private var timers: [UUID: Timer] = [:]
    private var armed: [UUID: Date] = [:]
    /// 每个小组件最近一次交来的下一次提醒，设置切换时按它重排。
    private var latest: [UUID: (instance: WidgetInstance, next: Date?)] = [:]
    /// 这次启动里已经撤过系统通知的小组件。`scheduled` 只记这次启动排的，上次
    /// 运行（或升级前的版本）排下、还没到点的那条系统里还留着，弹卡片时不撤
    /// 就会和卡片同一刻各来一次。
    private var purged: Set<UUID> = []

    private init() {}

    private static func identifier(_ id: UUID) -> String { "docket.water.\(id.uuidString)" }

    /// `next` nil (reminders off) withdraws the pending one.
    func update(_ instance: WidgetInstance, next: Date?) {
        latest[instance.id] = (instance, next)
        let id = Self.identifier(instance.id)
        if ReminderPopupCenter.shared.shows(.water) {
            // 弹卡片：撤掉排着的系统通知，改由应用里的计时器到点弹出。
            let hadOne = scheduled.removeValue(forKey: instance.id) != nil
            if hadOne || purged.insert(instance.id).inserted {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
            }
            arm(instance.id, at: next)
            return
        }
        disarm(instance.id)
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

    /// 「到点弹出卡片」的喝水开关变了：每个小组件按最近一次的下一次提醒重排。
    func popupSettingChanged() {
        for (_, value) in latest {
            update(value.instance, next: value.next)
        }
    }

    // MARK: 弹卡片

    private func arm(_ widget: UUID, at date: Date?) {
        // 下一次提醒往后挪的那一刻，往往就是上一次刚到点的那一秒（卡片每秒重算
        // 下一次）：还没来得及响的那一次先弹出来，不让它被新的顶掉。
        if let pending = armed[widget], pending != date, pending <= Date.now.addingTimeInterval(0.5) {
            fire(widget, due: pending)
        }
        guard let date else { return disarm(widget) }
        if let pending = armed[widget], abs(pending.timeIntervalSince(date)) < 1 { return }
        timers[widget]?.invalidate()
        armed[widget] = date
        let timer = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fire(widget, due: date) }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        timers[widget] = timer
    }

    /// 弹卡片的计时器还在等的那几刻。快到点时 `TimedAlertDriver` 请系统别把计时器
    /// 往后推（App Nap），喝水也算进去，免得晚过 `ReminderPopupDecision.isFresh`
    /// 的期限、这一次就不弹了。
    var armedTimes: [Date] { Array(armed.values) }

    private func disarm(_ widget: UUID) {
        timers.removeValue(forKey: widget)?.invalidate()
        armed[widget] = nil
    }

    private func fire(_ widget: UUID, due: Date) {
        guard armed[widget] == due else { return }
        disarm(widget)
        let now = Date.now
        guard ReminderPopupDecision.isFresh(due: due, now: now), ReminderPopupCenter.shared.shows(.water),
              let instance = WidgetWriter.current(widget) ?? latest[widget]?.instance else { return }
        ReminderPopupCenter.shared.post([ReminderPopupAlerts.water(instance, due: due, now: now)], now: now)
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
