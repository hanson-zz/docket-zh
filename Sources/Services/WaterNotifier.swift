import Foundation
@preconcurrency import UserNotifications

/// Schedules the 喝水 widget's reminder, the way PostureNotifier schedules
/// the stand-up one.
///
/// 下一次提醒的时间由 `TimedAlertDriver` 每秒从所有布局（含文件夹）里的每个喝水
/// 小组件算好交来（`sync`），不再靠喝水卡片显示在扩展栏上：卡片在文件夹里、在
/// 别的布局里、扩展栏自动隐藏时照样提醒，弹出卡片上「稍后 15 分钟」写下的时间
/// 下一秒就排上。卡片删掉了，排着的那一次也撤掉。
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

    /// 后台计时器每秒交来所有布局里的喝水小组件和各自的下一次提醒。已经不在任何
    /// 布局里的撤掉排着的系统通知和计时器。
    func sync(_ widgets: [(instance: WidgetInstance, next: Date?)]) {
        let present = Set(widgets.map { $0.instance.id })
        for id in WaterAlertPlan.removed(known: Set(latest.keys), present: present) {
            latest[id] = nil
            disarm(id)
            if scheduled.removeValue(forKey: id) != nil {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.identifier(id)])
            }
        }
        for widget in widgets { update(widget.instance, next: widget.next) }
    }

    /// 「到点弹出卡片」的喝水开关变了：每个小组件按最近一次的下一次提醒重排。
    func popupSettingChanged() {
        for (_, value) in latest {
            update(value.instance, next: value.next)
        }
    }

    // MARK: 弹卡片

    private func arm(_ widget: UUID, at date: Date?) {
        switch WaterAlertPlan.step(pending: armed[widget], next: date, now: .now) {
        case .keep:
            return
        case .rearm(let next):
            wait(widget, until: next)
        case .fireThenRearm(let due, let next):
            // 下一次提醒往后挪的那一刻，往往就是上一次刚到点的那一秒（每秒重算下一次）：
            // 还没来得及响的那一次先弹出来，不让它被新的顶掉。
            fire(widget, due: due)
            wait(widget, until: next)
        }
    }

    private func wait(_ widget: UUID, until date: Date?) {
        guard let date else { return disarm(widget) }
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
