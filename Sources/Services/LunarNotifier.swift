import Foundation
@preconcurrency import UserNotifications

/// 调休上班的前一晚再提醒一次：补班日前一天 20:00 发一条通知。
///
/// 卡片从提前 N 天起就整行变红，这条通知是怕卡片没看见。全应用只排一条（几个农历
/// 卡片不会响几次），按最近的补班日排；调休提醒关掉、或者已经过了那个时间就撤掉。
/// 日期只来自 `HolidaySchedule`，见 `LunarCard.eveReminder`。第一次排的时候才请求
/// 通知权限。
///
/// 农历生日和纪念日的提醒也在这里排（`updateEvents`），每条事件一组标识。
@MainActor
final class LunarNotifier {
    static let shared = LunarNotifier()

    private static let identifier = "docket.lunar.makeup-eve"
    private var scheduled: Date?
    private var asked = false
    private let presenter = BannerPresenter()

    private init() {}

    func update(_ instance: WidgetInstance, known: [Int: [HolidayDay]], now: Date = .now) {
        let enabled = instance.config.bool("workAlert", default: true)
        guard enabled, let eve = LunarCard.eveReminder(now: now, known: known) else {
            if scheduled != nil {
                scheduled = nil
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.identifier])
            }
            return
        }
        if let scheduled, abs(scheduled.timeIntervalSince(eve.fire)) < 1 { return }
        scheduled = eve.fire
        let calendar = ChineseCalendar.gregorian
        let month = calendar.component(.month, from: eve.workday)
        let day = calendar.component(.day, from: eve.workday)
        let title = tr("明天要上班")
        let body = tr("\(month)月\(day)日是\(trKey(HolidaySchedule.shortName(eve.holiday)))调休补班，记得定闹钟。")
        let fire = eve.fire
        Task { await schedule(at: fire, title: title, body: body) }
    }

    // MARK: 农历生日、纪念日

    /// 每张卡记下排过的那份（时间和文字），内容没变就不重排；只改名字时间不变也重排。
    private var eventPlans: [UUID: [String: String]] = [:]

    /// 农历生日和纪念日：每条排下一次的提前提醒和当天提醒（见 `LunarEvents.reminders`）。
    /// 改了、删了、或者过了的都撤掉。标识带卡片 id，两张农历卡记了同一个人也各管各的。
    func updateEvents(_ instance: WidgetInstance, now: Date = .now) {
        let prefix = "docket.lunar.event.\(instance.id.uuidString)."
        var wanted: [String: LunarEvents.Reminder] = [:]
        for event in LunarEvents.events(instance.config) {
            for reminder in LunarEvents.reminders(event, now: now) {
                wanted[prefix + event.id + "." + reminder.slot] = reminder
            }
        }
        let plan = wanted.mapValues { "\($0.fire.timeIntervalSince1970)|\($0.title)|\($0.body)" }
        if eventPlans[instance.id] == plan { return }
        eventPlans[instance.id] = plan
        let items = wanted.map { (id: $0.key, fire: $0.value.fire, title: $0.value.title, body: $0.value.body) }
        Task {
            let center = UNUserNotificationCenter.current()
            let pending = await Self.pendingIdentifiers()
            let stale = pending.filter { $0.hasPrefix(prefix) && plan[$0] == nil }
            if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: stale) }
            for item in items {
                await schedule(at: item.fire, title: item.title, body: item.body, identifier: item.id)
            }
        }
    }

    /// 启动时撤掉已经不在任何布局里的农历卡排下的生日、纪念日提醒（卡片删了，
    /// 提醒不该照响）。
    func sweepEvents(keeping live: Set<UUID>) {
        let base = "docket.lunar.event."
        Task {
            let pending = await Self.pendingIdentifiers()
            let stale = pending.filter { id in
                guard id.hasPrefix(base) else { return false }
                let rest = id.dropFirst(base.count)
                guard let uuid = UUID(uuidString: String(rest.prefix(36))) else { return false }
                return !live.contains(uuid)
            }
            if !stale.isEmpty {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: stale)
            }
        }
    }

    /// 在系统线程上读，只把标识带回来。
    private nonisolated static func pendingIdentifiers() async -> [String] {
        await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier)
    }

    private func schedule(at date: Date, title: String, body: String,
                          identifier: String = LunarNotifier.identifier) async {
        let center = UNUserNotificationCenter.current()
        if center.delegate == nil { center.delegate = presenter }
        if !asked {
            asked = true
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await center.add(request)
    }
}
