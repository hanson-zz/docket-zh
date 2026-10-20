import EventKit
import Foundation

/// 日历卡片、日历面板和时钟面板共用的一个 EventKit store。
///
/// 原来卡片和面板各有一个私有的 store，时钟面板要读“下一个日程”时又得再开
/// 一个；store 不放在 `@State` 里是因为卡片每秒都在重画，每次新建都是一条到
/// 日历守护进程的新连接。只建 store 不会弹授权，要权限只在日历面板里点按钮时问。
@MainActor
enum CalendarEventStore {
    static let shared = EKEventStore()

    /// 上一次看到的日历权限。从没权限变成有权限时 store 要 `reset()` 一下，
    /// 不然一直按授权前的样子答成空的。
    private static var lastStatus = EKEventStore.authorizationStatus(for: .event)

    /// 有完整的日历权限。权限刚变过时顺手 reset。
    static var hasAccess: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status != lastStatus {
            lastStatus = status
            shared.reset()
        }
        return status == .fullAccess
    }

    /// 接下来 24 小时内最先开始的非全天日程（所有日历）。没权限是 nil，
    /// 时钟面板据此不显示那一行。
    static func nextEvent(after now: Date) -> ClockPanelData.Upcoming? {
        guard hasAccess else { return nil }
        let calendars = shared.calendars(for: .event)
        guard !calendars.isEmpty else { return nil }
        let end = now.addingTimeInterval(24 * 3600)
        let predicate = shared.predicateForEvents(withStart: now, end: end, calendars: calendars)
        let events = shared.events(matching: predicate).map {
            (start: $0.startDate ?? now, title: $0.title ?? "", allDay: $0.isAllDay)
        }
        return ClockPanelData.nextEvent(events, now: now)
    }
}
