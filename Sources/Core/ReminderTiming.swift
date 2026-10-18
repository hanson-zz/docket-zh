import Foundation

/// 提醒事项的到期时间：哪一天，带不带具体时刻。
///
/// 系统“提醒事项”里一条提醒可以只有日期（当天全天），也可以带时刻；卡片和面板
/// 读出来、推迟和改期写回去都用这一个值，写回时再换成 EventKit 的日期组件。
public struct ReminderDue: Equatable, Hashable, Sendable {
    public var date: Date
    /// false 是只有日期、全天的提醒，`date` 取那天零点。
    public var hasTime: Bool

    public init(date: Date, hasTime: Bool) {
        self.date = date
        self.hasTime = hasTime
    }
}

/// 提醒事项的优先级，按系统“提醒事项”App 的四档。
///
/// EventKit 的 priority 是 0 到 9：0 是无，1 到 4 是高，5 是中，6 到 9 是低。
/// 写回时用 App 自己写的那个值（1、5、9），iPhone 上看到的是同一档。
public enum ReminderPriority: Int, CaseIterable, Sendable {
    case none = 0
    case high = 1
    case medium = 5
    case low = 9

    public init(eventKit value: Int) {
        switch value {
        case 1...4: self = .high
        case 5: self = .medium
        case 6...9: self = .low
        default: self = .none
        }
    }

    /// 菜单里的顺序：无、低、中、高。
    public static let menuOrder: [ReminderPriority] = [.none, .low, .medium, .high]

    /// 和“提醒事项”App 一样的感叹号。
    public var marks: String {
        switch self {
        case .none: ""
        case .low: "!"
        case .medium: "!!"
        case .high: "!!!"
        }
    }

    public var title: String {
        switch self {
        case .none: tr("无")
        case .low: tr("低")
        case .medium: tr("中")
        case .high: tr("高")
        }
    }
}

/// 提醒事项卡片和面板里和时间有关的纯计算：相对时间那句话、过没过期，以及
/// “推迟 1 小时”“推到明天”“推到下周一”落在哪一刻。界面和 EventKit 都不在这里，
/// 方便单独测试。
public enum ReminderTiming {
    // MARK: 过期

    /// 带时刻的过了那一刻就算过期；只有日期的要等那一天过完。
    public static func isOverdue(_ due: ReminderDue, now: Date, calendar: Calendar = .current) -> Bool {
        due.hasTime ? due.date < now : due.date < calendar.startOfDay(for: now)
    }

    // MARK: 相对时间

    /// “40 分钟后”“1 小时 20 分钟后”“已过期 15 分钟”“明天”“3 天后”“昨天”。
    ///
    /// 将来的按分钟向上取整（还差 39 分 30 秒说“40 分钟后”，和下面写的 15:00
    /// 对得上），过去的向下取整。超过今天的只说哪天，不再数小时。
    public static func relative(_ due: ReminderDue, now: Date, calendar: Calendar = .current) -> String {
        let days = dayOffset(due.date, from: now, calendar: calendar)
        if !due.hasTime || days != 0 {
            return dayWord(days)
        }
        let seconds = due.date.timeIntervalSince(now)
        if seconds > 0 {
            let minutes = max(1, Int((seconds / 60).rounded(.up)))
            return tr("\(duration(minutes))后")
        }
        let minutes = Int((-seconds / 60).rounded(.down))
        if minutes < 1 { return tr("刚到期") }
        return tr("已过期 \(duration(minutes))")
    }

    /// 下一个提醒那一行：“40 分钟后 · 15:00”。只有日期的不写时刻，只写哪天。
    /// - Parameter clock: 时刻的写法，由界面按系统设置格式化好传进来。
    public static func nextLine(_ due: ReminderDue, now: Date, clock: String,
                                calendar: Calendar = .current) -> String {
        let when = relative(due, now: now, calendar: calendar)
        guard due.hasTime else { return when }
        return "\(when) · \(clock)"
    }

    /// 列表行右侧的短写法：今天的写时刻（全天的写“全天”），昨天、明天写词，
    /// 更远的返回 nil，由界面写月日。
    public static func shortDay(_ due: ReminderDue, now: Date, calendar: Calendar = .current) -> String? {
        switch dayOffset(due.date, from: now, calendar: calendar) {
        case 0: return due.hasTime ? nil : tr("全天")
        case -1: return tr("昨天")
        case 1: return tr("明天")
        default: return nil
        }
    }

    /// 两个日期之间差几个日历日，按 `calendar` 的零点算。
    public static func dayOffset(_ date: Date, from now: Date, calendar: Calendar = .current) -> Int {
        let a = calendar.startOfDay(for: now)
        let b = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }

    static func dayWord(_ days: Int) -> String {
        switch days {
        case 0: return tr("今天")
        case 1: return tr("明天")
        case -1: return tr("昨天")
        case let d where d > 1: return tr("\(d) 天后")
        default: return tr("已过期 \(-days) 天")
        }
    }

    /// “40 分钟”“2 小时”“1 小时 20 分钟”。
    static func duration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return tr("\(rest) 分钟") }
        if rest == 0 { return tr("\(hours) 小时") }
        return tr("\(hours) 小时 \(rest) 分钟")
    }

    // MARK: 推迟

    /// 推迟 1 小时：还没到的从原来的时刻往后推；已经过了的从现在往后推，
    /// 不然推完还是过期。只有日期的变成带时刻的，现在起一小时后。秒数抹掉。
    public static func snoozed(_ due: ReminderDue, hours: Int = 1, now: Date,
                               calendar: Calendar = .current) -> ReminderDue {
        let base = due.hasTime ? max(due.date, now) : now
        let moved = base.addingTimeInterval(TimeInterval(hours) * 3600)
        return ReminderDue(date: wholeMinute(moved, calendar: calendar), hasTime: true)
    }

    /// 推到明天：今天之后的那一天，时刻不变；全天的仍是全天。
    public static func tomorrow(_ due: ReminderDue, now: Date, calendar: Calendar = .current) -> ReminderDue {
        let day = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return moved(due, toDay: day, calendar: calendar)
    }

    /// 推到下周一：今天之后最近的一个星期一（今天就是周一时是下一个周一），
    /// 时刻不变；全天的仍是全天。和系统“一周从哪天开始”的设置无关。
    public static func nextMonday(_ due: ReminderDue, now: Date, calendar: Calendar = .current) -> ReminderDue {
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today) // 1 是周日，2 是周一
        var ahead = (2 - weekday + 7) % 7
        if ahead == 0 { ahead = 7 }
        let day = calendar.date(byAdding: .day, value: ahead, to: today) ?? today
        return moved(due, toDay: day, calendar: calendar)
    }

    /// 换到 `day` 那天，保留原来的时和分。
    static func moved(_ due: ReminderDue, toDay day: Date, calendar: Calendar) -> ReminderDue {
        let start = calendar.startOfDay(for: day)
        guard due.hasTime else { return ReminderDue(date: start, hasTime: false) }
        let time = calendar.dateComponents([.hour, .minute], from: due.date)
        let date = calendar.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0,
                                 second: 0, of: start) ?? start
        return ReminderDue(date: date, hasTime: true)
    }

    static func wholeMinute(_ date: Date, calendar: Calendar) -> Date {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return calendar.date(from: parts) ?? date
    }

    // MARK: 新提醒

    /// 新提醒的默认时刻：下一个整点；已经过了晚上 11 点就是明天早上 9 点。
    public static func suggestedTime(now: Date, calendar: Calendar = .current) -> Date {
        let parts = calendar.dateComponents([.year, .month, .day, .hour], from: now)
        let hour = calendar.date(from: parts) ?? now
        let next = calendar.date(byAdding: .hour, value: 1, to: hour) ?? now
        if calendar.isDate(next, inSameDayAs: now), calendar.component(.hour, from: now) < 23 {
            return next
        }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? next
    }

    /// 面板编辑器里分开选的日期和时刻拼成一个到期时间。不带时刻时取那天零点。
    public static func combine(day: Date, time: Date?, calendar: Calendar = .current) -> ReminderDue {
        let start = calendar.startOfDay(for: day)
        guard let time else { return ReminderDue(date: start, hasTime: false) }
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        let date = calendar.date(bySettingHour: parts.hour ?? 9, minute: parts.minute ?? 0,
                                 second: 0, of: start) ?? start
        return ReminderDue(date: date, hasTime: true)
    }

    /// 保存后还在不在面板里：面板只列已过期和今天到期的，没有日期或者改到
    /// 明天以后的，保存完就看不到了，要说一句。
    public static func staysInToday(_ due: ReminderDue?, now: Date, calendar: Calendar = .current) -> Bool {
        guard let due else { return false }
        return dayOffset(due.date, from: now, calendar: calendar) <= 0
    }

    // MARK: 和 EventKit 互换

    /// 写回 `EKReminder.dueDateComponents` 的组件：只有日期的不带时和分，
    /// “提醒事项”App 和 iPhone 才会把它当全天。
    public static func components(_ due: ReminderDue, calendar: Calendar = .current) -> DateComponents {
        var parts = calendar.dateComponents(due.hasTime ? [.year, .month, .day, .hour, .minute]
                                                        : [.year, .month, .day], from: due.date)
        parts.calendar = calendar
        if due.hasTime { parts.timeZone = calendar.timeZone }
        return parts
    }

    /// 从 `dueDateComponents` 读回来。没有日期的提醒是 nil。
    public static func due(from components: DateComponents?, calendar: Calendar = .current) -> ReminderDue? {
        guard let components, components.year != nil, components.month != nil, components.day != nil else {
            return nil
        }
        var parts = components
        let hasTime = components.hour != nil
        if !hasTime { parts.hour = 0; parts.minute = 0; parts.second = 0 }
        // `date` 只有组件里带着日历时才有值，EventKit 不保证带。
        let using = components.calendar ?? calendar
        parts.calendar = using
        guard let date = parts.date ?? using.date(from: parts) else { return nil }
        return ReminderDue(date: date, hasTime: hasTime)
    }
}
