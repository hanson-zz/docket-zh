import AppKit
import EventKit
import SwiftUI

/// 卡片和面板共用的一个 `EKEventStore`，以及所有写回系统“提醒事项”的操作。
///
/// 只放在一处：卡片在完成、推迟，面板在新建、修改、删除，写的是同一个库，
/// 授权后 `reset()` 一次两边都看得到。写完 `commit: true`，系统随后经 iCloud
/// 同步到 iPhone，并发出 `.EKEventStoreChanged`，卡片和面板各自重新读取。
///
/// 这里从不请求权限。没有完全访问权限时每个写操作都直接返回 false：卡片画在
/// 扩展栏上时不能弹授权框，只有用户点开面板才算“第一次用到”。
@MainActor
enum ReminderSync {
    /// 构造它不会弹框，只有 `requestFullAccessToReminders` 会。放在这里而不是
    /// `@State`，是因为卡片每秒都在重建，每次新建一个都要重新连一次提醒事项服务。
    static let store = EKEventStore()

    static var canWrite: Bool {
        EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }

    /// 能往里写的列表，按系统里的顺序。订阅的、只读的列表不列出。
    static func writableLists() -> [EKCalendar] {
        store.calendars(for: .reminder).filter(\.allowsContentModifications)
    }

    /// 新提醒默认放进哪个列表：小组件筛选了列表就放那个，否则用系统的默认列表。
    static func defaultList(named filter: String) -> EKCalendar? {
        let lists = writableLists()
        if !filter.isEmpty, let match = lists.first(where: { $0.title == filter }) { return match }
        return store.defaultCalendarForNewReminders() ?? lists.first
    }

    private static func reminder(_ id: String) -> EKReminder? {
        store.calendarItem(withIdentifier: id) as? EKReminder
    }

    // MARK: 写

    /// 勾掉一条。重复的提醒由系统接着排下一次。
    @discardableResult
    static func complete(_ id: String) -> Bool {
        guard canWrite, let item = reminder(id) else { return false }
        item.isCompleted = true
        return commit(item)
    }

    /// 改到期时间（推迟、推到明天、推到下周一）。
    @discardableResult
    static func reschedule(_ id: String, to due: ReminderDue) -> Bool {
        guard canWrite, let item = reminder(id) else { return false }
        apply(due, to: item)
        return commit(item)
    }

    @discardableResult
    static func remove(_ id: String) -> Bool {
        guard canWrite, let item = reminder(id) else { return false }
        do {
            try store.remove(item, commit: true)
            return true
        } catch {
            NSSound.beep()
            return false
        }
    }

    /// 面板里编辑好的一条：`id` 为 nil 是新建。返回保存后的标识，失败是 nil。
    @discardableResult
    static func save(id: String?, title: String, due: ReminderDue?, priority: ReminderPriority,
                     listID: String?, fallbackList: String) -> String? {
        guard canWrite else { return nil }
        let item: EKReminder
        if let id {
            guard let existing = reminder(id) else { return nil }
            item = existing
        } else {
            item = EKReminder(eventStore: store)
        }
        item.title = title
        item.priority = priority.rawValue
        let current: EKCalendar? = item.calendar
        let chosen: EKCalendar? = listID.flatMap { store.calendar(withIdentifier: $0) }
        guard let list = chosen ?? current ?? defaultList(named: fallbackList) else { return nil }
        if current?.calendarIdentifier != list.calendarIdentifier { item.calendar = list }
        apply(due, to: item, isNew: id == nil)
        return commit(item) ? item.calendarItemIdentifier : nil
    }

    // MARK: 内部

    /// 写日期组件，并把“到点提醒”跟着挪过去。
    ///
    /// “提醒事项”App 给带时刻的提醒加一个绝对时间的闹钟，到点在 Mac 和 iPhone
    /// 上弹通知。只改日期组件不动闹钟，推迟以后通知还会按旧时间响，所以绝对时间
    /// 的闹钟一并换掉；相对时间的（提前 5 分钟这类）跟着到期时间走，不用动。
    private static func apply(_ due: ReminderDue?, to item: EKReminder, isNew: Bool = false) {
        let hadAbsolute = (item.alarms ?? []).contains { $0.absoluteDate != nil }
        for alarm in item.alarms ?? [] where alarm.absoluteDate != nil {
            item.removeAlarm(alarm)
        }
        guard let due else {
            item.dueDateComponents = nil
            item.startDateComponents = nil
            return
        }
        item.dueDateComponents = ReminderTiming.components(due)
        if due.hasTime, isNew || hadAbsolute {
            item.addAlarm(EKAlarm(absoluteDate: due.date))
        }
    }

    private static func commit(_ item: EKReminder) -> Bool {
        do {
            try store.save(item, commit: true)
            return true
        } catch {
            store.rollback()
            NSSound.beep()
            return false
        }
    }
}
