import Foundation
@preconcurrency import UserNotifications

/// 调休上班的前一晚再提醒一次：补班日前一天 20:00 发一条通知。
///
/// 卡片从提前 N 天起就整行变红，这条通知是怕卡片没看见。全应用只排一条（几个农历
/// 卡片不会响几次），按最近的补班日排；调休提醒关掉、或者已经过了那个时间就撤掉。
/// 日期只来自 `HolidaySchedule`，见 `LunarCard.eveReminder`。第一次排的时候才请求
/// 通知权限。
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

    private func schedule(at date: Date, title: String, body: String) async {
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
        let request = UNNotificationRequest(identifier: Self.identifier, content: content, trigger: trigger)
        try? await center.add(request)
    }
}
