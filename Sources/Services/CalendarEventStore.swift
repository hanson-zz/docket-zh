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

    // MARK: 日历面板：读一段时间、新建、改时间、删除

    /// 一段时间里选中日历的日程，拍平成 `WeekEntry`。空的筛选是全部日历，筛选里的日历都没了也是。
    static func entries(in span: DateInterval, chosen: Set<String>) -> [WeekEntry] {
        guard hasAccess else { return [] }
        let all = shared.calendars(for: .event)
        let wanted = all.filter { chosen.contains($0.calendarIdentifier) }
        let scope = wanted.isEmpty ? all : wanted
        guard !scope.isEmpty else { return [] }
        let predicate = shared.predicateForEvents(withStart: span.start, end: span.end, calendars: scope)
        return shared.events(matching: predicate).compactMap(WeekEvents.entry)
    }

    /// 账户里的全部日历（筛选菜单用），按名字排。
    static func calendars() -> [EKCalendar] {
        guard hasAccess else { return [] }
        return shared.calendars(for: .event)
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// 能写的日历（订阅的、节假日这类只读的不算），新建时选。
    static func writableCalendars() -> [EKCalendar] {
        calendars().filter(\.allowsContentModifications)
    }

    /// 系统设置里的默认日历。
    static var defaultCalendarID: String? {
        guard hasAccess else { return nil }
        return shared.defaultCalendarForNewEvents?.calendarIdentifier
    }

    enum WriteError: Error { case noAccess, noCalendar, notFound, readOnly }

    /// 新建一个日程写进系统日历。
    static func add(title: String, slot: CalendarPlanner.Slot, calendarID: String?) throws {
        guard hasAccess else { throw WriteError.noAccess }
        let calendar = calendarID.flatMap { shared.calendar(withIdentifier: $0) } ?? shared.defaultCalendarForNewEvents
        guard let calendar, calendar.allowsContentModifications else { throw WriteError.noCalendar }
        let event = EKEvent(eventStore: shared)
        event.title = title
        event.calendar = calendar
        event.isAllDay = slot.isAllDay
        event.startDate = slot.start
        // EventKit 的全天日程结束日写当天就行，写第二天零点会变成两天。
        event.endDate = slot.isAllDay ? slot.end.addingTimeInterval(-1) : slot.end
        try shared.save(event, span: .thisEvent, commit: true)
    }

    /// 面板上一条日程对应的 `EKEvent`：`WeekEntry.id` 是「事件 id-这一次的开始时刻」，
    /// 重复日程的每一次 id 前半一样，所以在这一次前后各一天里按整个 id 找。
    static func event(for entry: WeekEntry) -> EKEvent? {
        guard hasAccess else { return nil }
        let calendars = shared.calendars(for: .event)
        guard !calendars.isEmpty else { return nil }
        let predicate = shared.predicateForEvents(withStart: entry.start.addingTimeInterval(-86_400),
                                                  end: entry.end.addingTimeInterval(86_400), calendars: calendars)
        return shared.events(matching: predicate).first { WeekEvents.entry($0)?.id == entry.id }
    }

    /// 这条日程能不能改（日历只读、订阅的不能）。
    static func canEdit(_ entry: WeekEntry) -> Bool {
        event(for: entry)?.calendar?.allowsContentModifications ?? false
    }

    /// 是重复日程里的一次：改和删都只动这一次。
    static func isRecurring(_ entry: WeekEntry) -> Bool {
        event(for: entry)?.hasRecurrenceRules ?? false
    }

    /// 改时间写回系统日历，重复日程只改这一次。
    static func move(_ entry: WeekEntry, start: Date, end: Date) throws {
        guard let event = event(for: entry) else { throw WriteError.notFound }
        guard event.calendar?.allowsContentModifications ?? false else { throw WriteError.readOnly }
        event.startDate = start
        event.endDate = end
        try shared.save(event, span: .thisEvent, commit: true)
    }

    /// 从系统日历删除，重复日程只删这一次。
    static func delete(_ entry: WeekEntry) throws {
        guard let event = event(for: entry) else { throw WriteError.notFound }
        guard event.calendar?.allowsContentModifications ?? false else { throw WriteError.readOnly }
        try shared.remove(event, span: .thisEvent, commit: true)
    }
}
