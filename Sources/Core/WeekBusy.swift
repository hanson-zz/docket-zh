import Foundation

/// 一周日程只管「这周哪天忙、哪天空」：按占用时长算忙闲，不按日程个数。
///
/// 每天两格，上午和下午，各自填多少是这半天被占了几小时（重叠的只算一次），
/// 满格是 `fullHours` 小时。「最空的下午」是本周剩下的工作日里，下午连续空闲
/// 最长的那天。纯逻辑，界面把 `WeekDay` 交过来就行。
public struct HalfDayLoad: Equatable, Sendable {
    /// 上午被占的小时数。
    public var morning: Double
    /// 下午被占的小时数。
    public var afternoon: Double

    public init(morning: Double, afternoon: Double) {
        self.morning = morning
        self.afternoon = afternoon
    }
}

/// 某天下午的空闲：最长一段从几点到几点。
public struct FreeAfternoon: Equatable, Sendable {
    /// 0 是周一。
    public var dayIndex: Int
    public var start: Date
    public var end: Date
    public var hours: Double { end.timeIntervalSince(start) / 3_600 }
}

public enum WeekBusy {
    /// 上午 8 点到 12 点，下午 12 点到 18 点。
    public static let morningHours = 8..<12
    public static let afternoonHours = 12..<18
    /// 一格填满是 4 小时。
    public static let fullHours: Double = 4

    /// 这些时段（已经剪到同一天）合并重叠后的总时长，秒。
    static func union(_ intervals: [(Date, Date)]) -> TimeInterval {
        let sorted = intervals.filter { $0.1 > $0.0 }.sorted { $0.0 < $1.0 }
        var total: TimeInterval = 0
        var current: (Date, Date)?
        for item in sorted {
            if let open = current, item.0 <= open.1 {
                current = (open.0, max(open.1, item.1))
            } else {
                if let open = current { total += open.1.timeIntervalSince(open.0) }
                current = item
            }
        }
        if let open = current { total += open.1.timeIntervalSince(open.0) }
        return total
    }

    /// 合并重叠后的时段，按开始排。
    static func merged(_ intervals: [(Date, Date)]) -> [(Date, Date)] {
        let sorted = intervals.filter { $0.1 > $0.0 }.sorted { $0.0 < $1.0 }
        var result: [(Date, Date)] = []
        for item in sorted {
            if let last = result.last, item.0 <= last.1 {
                result[result.count - 1] = (last.0, max(last.1, item.1))
            } else {
                result.append(item)
            }
        }
        return result
    }

    /// 某天定时日程剪到 [from, to) 里的时段。全天日程不算占用：它们多半是
    /// 生日、出差这类标记，不是被会议占掉的时间。
    static func clipped(_ day: WeekDay, from: Date, to: Date) -> [(Date, Date)] {
        day.entries.filter { !$0.isAllDay }.compactMap { entry in
            let start = max(entry.start, from), end = min(entry.end, to)
            return end > start ? (start, end) : nil
        }
    }

    static func at(_ day: Date, hour: Int, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day.addingTimeInterval(Double(hour) * 3_600)
    }

    static func nextDay(_ day: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
    }

    /// 一天被占了几小时（整天，重叠只算一次）。
    public static func busyHours(_ day: WeekDay, calendar: Calendar = WeekAgenda.calendar) -> Double {
        union(clipped(day, from: day.date, to: nextDay(day.date, calendar: calendar))) / 3_600
    }

    /// 本周一共排了几小时。
    public static func totalHours(_ days: [WeekDay], calendar: Calendar = WeekAgenda.calendar) -> Double {
        days.reduce(0) { $0 + busyHours($1, calendar: calendar) }
    }

    /// 上下午各被占几小时。
    public static func load(_ day: WeekDay, calendar: Calendar = WeekAgenda.calendar) -> HalfDayLoad {
        let m = clipped(day, from: at(day.date, hour: morningHours.lowerBound, calendar: calendar),
                        to: at(day.date, hour: morningHours.upperBound, calendar: calendar))
        let a = clipped(day, from: at(day.date, hour: afternoonHours.lowerBound, calendar: calendar),
                        to: at(day.date, hour: afternoonHours.upperBound, calendar: calendar))
        return HalfDayLoad(morning: union(m) / 3_600, afternoon: union(a) / 3_600)
    }

    /// 一格填多少，0...1。有日程就至少露一点，不会因为只有 15 分钟就看不见。
    public static func fill(hours: Double) -> Double {
        guard hours > 0 else { return 0 }
        return max(0.15, min(1, hours / fullHours))
    }

    /// 「21.5」「3」，最多一位小数。
    public static func hoursText(_ hours: Double) -> String {
        let rounded = (hours * 2).rounded() / 2
        return rounded == rounded.rounded() ? "\(Int(rounded))" : String(format: "%.1f", rounded)
    }

    /// 某天下午最长的一段空闲。今天的下午从现在算起；已经过去的下午为 nil。
    public static func longestFreeAfternoon(_ day: WeekDay, now: Date,
                                            calendar: Calendar = WeekAgenda.calendar) -> FreeAfternoon? {
        var start = at(day.date, hour: afternoonHours.lowerBound, calendar: calendar)
        let end = at(day.date, hour: afternoonHours.upperBound, calendar: calendar)
        if now > start { start = now }
        guard end.timeIntervalSince(start) >= 30 * 60 else { return nil }
        var cursor = start
        var best: (Date, Date)?
        for busy in merged(clipped(day, from: start, to: end)) {
            if busy.0 > cursor, busy.0.timeIntervalSince(cursor) > (best.map { $0.1.timeIntervalSince($0.0) } ?? 0) {
                best = (cursor, busy.0)
            }
            cursor = max(cursor, busy.1)
        }
        if end > cursor, end.timeIntervalSince(cursor) > (best.map { $0.1.timeIntervalSince($0.0) } ?? 0) {
            best = (cursor, end)
        }
        guard let best, best.1.timeIntervalSince(best.0) >= 30 * 60 else { return nil }
        return FreeAfternoon(dayIndex: day.index, start: best.0, end: best.1)
    }

    /// 本周剩下的工作日里下午空得最久的那天。一样长的取早的。`workdays` 是周一为 0
    /// 的下标，默认周一到周五；放假的日子和调休上班的周末由调用方算好传进来。
    public static func freestAfternoon(_ days: [WeekDay], now: Date, workdays: Set<Int> = Set(0...4),
                                       calendar: Calendar = WeekAgenda.calendar) -> FreeAfternoon? {
        let today = calendar.startOfDay(for: now)
        var best: FreeAfternoon?
        for day in days where workdays.contains(day.index) && day.date >= today {
            guard let free = longestFreeAfternoon(day, now: now, calendar: calendar) else { continue }
            if best == nil || free.hours > best!.hours + 1e-6 { best = free }
        }
        return best
    }

    /// 悬停某天时那句：「13:00 以后全空」「全天空」「下午排满了」。
    public static func freeNote(_ day: WeekDay, now: Date, calendar: Calendar = WeekAgenda.calendar) -> String {
        let timed = day.entries.filter { !$0.isAllDay }
        if timed.isEmpty { return tr("全天空") }
        let dayEnd = at(day.date, hour: afternoonHours.upperBound, calendar: calendar)
        let lastEnd = timed.map(\.end).max() ?? day.date
        if lastEnd < dayEnd {
            return tr("\(CalendarDay.clock(lastEnd, calendar: calendar)) 以后全空")
        }
        if let free = longestFreeAfternoon(day, now: calendar.startOfDay(for: day.date), calendar: calendar) {
            return tr("下午 \(CalendarDay.clock(free.start, calendar: calendar))-\(CalendarDay.clock(free.end, calendar: calendar)) 空")
        }
        return tr("下午排满了")
    }

    /// 「周四下午空」，今天的写「今天下午空」。
    public static func freeTitle(_ free: FreeAfternoon, todayIndex: Int?) -> String {
        if free.dayIndex == todayIndex { return tr("今天下午空") }
        return tr("周\(WeekAgenda.weekdayNames[max(0, min(6, free.dayIndex))])下午空")
    }
}
