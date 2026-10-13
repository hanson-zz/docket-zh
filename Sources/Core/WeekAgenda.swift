import Foundation

/// 一周日程：this week's events sorted into seven days, Monday first.
///
/// Pure: the views flatten each `EKEvent` into a `WeekEntry` the moment the
/// store returns it, and everything after that (which week, which day an
/// event lands on, how tall a day's bar is) happens here, where it is tested
/// without a calendar database.
public struct WeekEntry: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var calendar: String
    /// The calendar's colour as `#RRGGBB`, or empty for the widget's accent.
    public var colorHex: String

    public init(id: String, title: String, start: Date, end: Date,
                isAllDay: Bool = false, calendar: String = "", colorHex: String = "") {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendar = calendar
        self.colorHex = colorHex
    }
}

/// One of the week's seven days and what is on it.
public struct WeekDay: Identifiable, Hashable, Sendable {
    public var date: Date
    /// 0 for Monday through 6 for Sunday.
    public var index: Int
    public var isToday: Bool
    /// Timed events in start order, then all-day ones.
    public var entries: [WeekEntry]

    public var id: Date { date }
    public var count: Int { entries.count }
}

public enum WeekAgenda {
    /// Gregorian with Monday first, the way a Chinese wall calendar runs,
    /// whatever the Mac's own first weekday is.
    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    public static let weekdayNames = ["一", "二", "三", "四", "五", "六", "日"]

    /// Midnight on the Monday of the week containing `date`.
    public static func weekStart(_ date: Date, calendar: Calendar = WeekAgenda.calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let back = (calendar.component(.weekday, from: day) - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -back, to: day) ?? day
    }

    /// The fetch window: Monday 00:00 to the next Monday 00:00.
    public static func interval(_ date: Date, calendar: Calendar = WeekAgenda.calendar) -> DateInterval {
        let start = weekStart(date, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(7 * 86_400)
        return DateInterval(start: start, end: end)
    }

    /// The week containing `now`, each day holding every entry that overlaps
    /// it. An event running across midnight is on both days; one ending
    /// exactly at midnight is not on the next. A zero-length event counts on
    /// the day it starts.
    public static func days(_ entries: [WeekEntry], now: Date, includeAllDay: Bool = true,
                            calendar: Calendar = WeekAgenda.calendar) -> [WeekDay] {
        let start = weekStart(now, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        let wanted = includeAllDay ? entries : entries.filter { !$0.isAllDay }
        return (0..<7).compactMap { index in
            guard let dayStart = calendar.date(byAdding: .day, value: index, to: start),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
            let on = wanted.filter { entry in
                let end = max(entry.end, entry.start.addingTimeInterval(1))
                return entry.start < dayEnd && end > dayStart
            }
            let sorted = on.filter { !$0.isAllDay }.sorted(by: order) + on.filter(\.isAllDay).sorted(by: order)
            return WeekDay(date: dayStart, index: index, isToday: dayStart == today, entries: sorted)
        }
    }

    private static func order(_ a: WeekEntry, _ b: WeekEntry) -> Bool {
        a.start == b.start ? a.title < b.title : a.start < b.start
    }

    /// Entries across the week, each counted once however many days it spans.
    public static func total(_ days: [WeekDay]) -> Int {
        Set(days.flatMap { $0.entries.map(\.id) }).count
    }

    /// How full a day's bar is against the busiest day of the week, 0...1.
    /// Never a sliver for a day with something on it, and never empty because
    /// another day was busier.
    public static func fill(count: Int, busiest: Int) -> Double {
        guard count > 0, busiest > 0 else { return 0 }
        return max(0.2, min(1, Double(count) / Double(busiest)))
    }

    /// "10月12日至18日", or across a month end "9月28日至10月4日".
    public static func rangeTitle(_ now: Date, calendar: Calendar = WeekAgenda.calendar) -> String {
        let span = interval(now, calendar: calendar)
        guard let last = calendar.date(byAdding: .day, value: 6, to: span.start) else { return "" }
        let a = calendar.dateComponents([.month, .day], from: span.start)
        let b = calendar.dateComponents([.month, .day], from: last)
        let head = "\(a.month ?? 0)月\(a.day ?? 0)日"
        return a.month == b.month ? "\(head)至\(b.day ?? 0)日" : "\(head)至\(b.month ?? 0)月\(b.day ?? 0)日"
    }

    /// "周一" through "周日", or "今天".
    public static func dayTitle(_ day: WeekDay) -> String {
        day.isToday ? "今天" : "周\(weekdayNames[day.index])"
    }

    /// The marks a day's column on the shelf can hold: one bar per entry in
    /// the entry's calendar colour, and past `limit` the last slot becomes a
    /// "+n" so a busy day still says how busy.
    public static func bars(_ day: WeekDay, limit: Int = 3) -> (colors: [String], more: Int) {
        guard limit > 0 else { return ([], day.count) }
        if day.count <= limit { return (day.entries.map(\.colorHex), 0) }
        return (day.entries.prefix(limit - 1).map(\.colorHex), day.count - (limit - 1))
    }
}
