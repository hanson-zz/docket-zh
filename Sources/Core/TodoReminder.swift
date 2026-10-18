import Foundation

// 快速待办的可选提醒时间：面板里每一条可以设一个时刻，到点弹出卡片。
//
// 存在每一条自己的 `r=` 段里（见 `TodoItem`），旧数据没有这一段，读出来就是
// 没有提醒。这里是设、清、到点判断，以及新的一天顺延时提醒跟着怎么走。

/// 面板里设提醒的快捷选项，另有“自定义…”挑日期和时刻。
public enum TodoReminderChoice: String, CaseIterable, Sendable {
    case inOneHour, tonight, tomorrowMorning

    public var title: String {
        switch self {
        case .inOneHour: tr("1 小时后")
        case .tonight: tr("今晚 20:00")
        case .tomorrowMorning: tr("明天 9:00")
        }
    }

    /// 落在哪一刻。“今晚 20:00”已经过了（或不到 10 分钟就到）时为 nil，菜单里不列。
    public func date(now: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .inOneHour:
            return ReminderPopupSnooze.later(minutes: 60, now: now, calendar: calendar)
        case .tonight:
            return ReminderPopupSnooze.tonight(now: now, calendar: calendar)
        case .tomorrowMorning:
            let start = calendar.startOfDay(for: now)
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: start) else { return nil }
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
        }
    }

    public static func available(now: Date, calendar: Calendar = .current) -> [TodoReminderChoice] {
        allCases.filter { $0.date(now: now, calendar: calendar) != nil }
    }
}

extension QuickTodo {
    /// 设或清一条的提醒时间（nil 是清掉）。秒数抹掉，存的是整秒。
    public static func settingReminder(_ id: String, at date: Date?, in items: [TodoItem]) -> [TodoItem] {
        ordered(items.map { item in
            guard item.id == id else { return item }
            var changed = item
            changed.remindAt = date.map { Date(timeIntervalSince1970: $0.timeIntervalSince1970.rounded(.down)) }
            return changed
        })
    }

    /// 在 (`after`, `now`] 里到点、还没做完的那几条，按到点先后。两次检查隔得
    /// 太久（合盖睡眠）就不补弹，和提醒音效一样。
    public static func dueReminders(_ items: [TodoItem], after: Date, upTo now: Date) -> [TodoItem] {
        let gap = now.timeIntervalSince(after)
        guard gap > 0, gap <= ReminderSoundDecision.maxGap else { return [] }
        return open(items)
            .filter { item in
                guard let at = item.remindAt else { return false }
                return at > after && at <= now
            }
            .sorted { ($0.remindAt ?? now, $0.text) < ($1.remindAt ?? now, $1.text) }
    }

    /// 卡片和面板上闹钟旁边的字：今天的写“16:00”，明天写“明天 9:00”，
    /// 更远的写“10/20 9:00”，昨天以前的写“10/16 16:00”。
    public static func reminderLabel(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let clock = ReminderPopupText.clock(date, calendar: calendar)
        let days = ReminderTiming.dayOffset(date, from: now, calendar: calendar)
        switch days {
        case 0: return clock
        case 1: return tr("明天 \(clock)")
        default:
            let parts = calendar.dateComponents([.month, .day], from: date)
            return "\(parts.month ?? 0)/\(parts.day ?? 0) \(clock)"
        }
    }

    /// 提醒时间过了没有（卡片上把过了的闹钟画淡一些）。
    public static func reminderPassed(_ item: TodoItem, now: Date) -> Bool {
        guard let at = item.remindAt else { return false }
        return at <= now
    }

    /// 顺延到今天时提醒跟着走：定在今天以前的，挪到今天的同一时刻；今天的那个
    /// 时刻已经过了就清掉，不在顺延的那一下弹出一张过时的卡片。今天和以后的不动。
    public static func carriedReminder(_ date: Date?, now: Date, calendar: Calendar = .current) -> Date? {
        guard let date else { return nil }
        let today = calendar.startOfDay(for: now)
        guard date < today else { return date }
        let time = calendar.dateComponents([.hour, .minute, .second], from: date)
        guard let moved = calendar.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0,
                                        second: time.second ?? 0, of: today) else { return nil }
        return moved > now ? moved : nil
    }

    /// 顺延到今天，提醒时间一并处理（见 `carriedReminder`）。
    public static func carryingOver(_ items: [TodoItem], today: String, now: Date,
                                    calendar: Calendar = .current) -> [TodoItem] {
        let late = Set(leftover(items, today: today).map(\.id))
        return carryingOver(items, today: today).map { item in
            guard late.contains(item.id) else { return item }
            var moved = item
            moved.remindAt = carriedReminder(item.remindAt, now: now, calendar: calendar)
            return moved
        }
    }
}
