import Foundation

/// 日历面板（日历和一周日程共用）的四项外观设置，以及面板里可以展开的月历。
///
/// - 突出显示的星期：一到日七个勾，默认周六、周日；被选的日子在一周条和月历里数字用淡一点的强调色。
/// - 月历框出本月：本月日期那一片描一圈细线，前后月份补位的日子变淡（默认开）。
/// - 日程圆点：有日程的日子下面画小圆点（默认开），子项「圆点按日历颜色」每个日程按所在日历的颜色，
///   最多 3 个；关掉统一画灰点。
/// - 月历显示周数：月历左边一列 ISO 周数（默认关）。
///
/// 纯逻辑，界面拿 `CalendarLook` 和 `MonthGrid` 画，测试不需要日历数据库。
public struct CalendarLook: Equatable, Sendable {
    public static let highlightKey = "highlightDays"
    public static let outlineKey = "monthOutline"
    public static let dotsKey = "eventDots"
    public static let colorDotsKey = "eventDotsColor"
    public static let weekNumbersKey = "weekNumbers"

    /// 默认突出周六、周日。值和摸鱼时钟的工作日一样：周一 "1" 到周日 "7"。
    public static let defaultHighlight = ["6", "7"]
    public static let defaultOutline = true
    public static let defaultDots = true
    public static let defaultColorDots = true
    public static let defaultWeekNumbers = false

    /// 设置里那一排勾的标题和值，周一在前，和一周条、月历的列一致（英文「Mon」不会两个「S」分不清）。
    public static var weekdayChoices: [(title: String, value: String)] { SlackerClock.weekdayChoices }

    /// 突出显示的星期，0 是周一，6 是周日（和 `WeekDay.index` 一样）。
    public var highlighted: Set<Int>
    public var outline: Bool
    public var dots: Bool
    public var colorDots: Bool
    public var weekNumbers: Bool

    public init(highlighted: Set<Int> = [5, 6], outline: Bool = CalendarLook.defaultOutline,
                dots: Bool = CalendarLook.defaultDots, colorDots: Bool = CalendarLook.defaultColorDots,
                weekNumbers: Bool = CalendarLook.defaultWeekNumbers) {
        self.highlighted = highlighted
        self.outline = outline
        self.dots = dots
        self.colorDots = colorDots
        self.weekNumbers = weekNumbers
    }

    /// 从小组件配置读；没存过的键按默认。认不出的星期值丢掉，一个都不勾也行（就是不突出）。
    public init(_ config: WidgetConfig) {
        let days = config.strings(Self.highlightKey, default: Self.defaultHighlight)
        self.init(highlighted: Set(days.compactMap { Int($0) }.filter { (1...7).contains($0) }.map { $0 - 1 }),
                  outline: config.bool(Self.outlineKey, default: Self.defaultOutline),
                  dots: config.bool(Self.dotsKey, default: Self.defaultDots),
                  colorDots: config.bool(Self.colorDotsKey, default: Self.defaultColorDots),
                  weekNumbers: config.bool(Self.weekNumbersKey, default: Self.defaultWeekNumbers))
    }

    /// 那天是不是突出显示的星期。
    public func isHighlighted(_ date: Date, calendar: Calendar = WeekAgenda.calendar) -> Bool {
        highlighted.contains(Self.weekdayIndex(date, calendar: calendar))
    }

    /// 周一 0 到周日 6，不管日历的一周从哪天开始。
    public static func weekdayIndex(_ date: Date, calendar: Calendar = WeekAgenda.calendar) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7
    }

    /// 一个圆点：按日历颜色（`#RRGGBB`，空串是小组件的强调色），或者统一的灰点。
    public enum Dot: Equatable, Hashable, Sendable {
        case color(String)
        case plain
    }

    /// 最多画几个点。
    public static let maxDots = 3

    /// 那天下面画的点：一个日程一个，最多 3 个，按传进来的先后（定时的在前）。圆点关着时没有。
    public func dots(for entries: [WeekEntry]) -> [Dot] {
        guard dots else { return [] }
        return entries.prefix(Self.maxDots).map { colorDots ? .color($0.colorHex) : .plain }
    }
}

/// 月历：一个月按周一开头排成 4 到 6 行，前后用相邻月份的日子补满。
public enum MonthGrid {
    public struct Day: Identifiable, Hashable, Sendable {
        public var date: Date
        public var inMonth: Bool
        public var isToday: Bool
        public var id: Date { date }
    }

    public struct Week: Identifiable, Hashable, Sendable {
        /// ISO 8601 周数（周一开头，1 月 4 日所在的那周是第 1 周）。
        public var number: Int
        public var days: [Day]
        public var id: Date { days.first?.date ?? .distantPast }
    }

    /// 那个月第一天零点。
    public static func monthStart(_ date: Date, calendar: Calendar = WeekAgenda.calendar) -> Date {
        let parts = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: parts) ?? calendar.startOfDay(for: date)
    }

    /// 前后挪几个月，落在那个月第一天。
    public static func shift(_ month: Date, by months: Int, calendar: Calendar = WeekAgenda.calendar) -> Date {
        monthStart(calendar.date(byAdding: .month, value: months, to: monthStart(month, calendar: calendar)) ?? month,
                   calendar: calendar)
    }

    /// 月历的行：从 1 号所在那周的周一，到最后一天所在那周的周日。
    public static func weeks(_ month: Date, now: Date, calendar: Calendar = WeekAgenda.calendar) -> [Week] {
        let first = monthStart(month, calendar: calendar)
        guard let next = calendar.date(byAdding: .month, value: 1, to: first),
              let last = calendar.date(byAdding: .day, value: -1, to: next) else { return [] }
        let start = WeekAgenda.weekStart(first, calendar: calendar)
        let end = WeekAgenda.weekStart(last, calendar: calendar)
        let today = calendar.startOfDay(for: now)
        let thisMonth = calendar.component(.month, from: first)
        var result: [Week] = []
        var monday = start
        while monday <= end {
            let days: [Day] = (0..<7).compactMap { offset in
                guard let date = calendar.date(byAdding: .day, value: offset, to: monday) else { return nil }
                return Day(date: date, inMonth: calendar.component(.month, from: date) == thisMonth,
                           isToday: date == today)
            }
            result.append(Week(number: isoWeek(monday, calendar: calendar), days: days))
            guard let following = calendar.date(byAdding: .day, value: 7, to: monday) else { break }
            monday = following
        }
        return result
    }

    /// 月历盖住的整段时间，读日程用。
    public static func interval(_ month: Date, calendar: Calendar = WeekAgenda.calendar) -> DateInterval? {
        let rows = weeks(month, now: month, calendar: calendar)
        guard let start = rows.first?.days.first?.date, let lastDay = rows.last?.days.last?.date,
              let end = calendar.date(byAdding: .day, value: 1, to: lastDay) else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// ISO 8601 周数，按那天在本地日历上的年月日算（时区不同也对齐墙上的日期）。
    public static func isoWeek(_ date: Date, calendar: Calendar = WeekAgenda.calendar) -> Int {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone
        return iso.component(.weekOfYear, from: date)
    }

    /// 月历头上的「2026 年 10 月」，英文界面「October 2026」。
    public static func title(_ month: Date, english: Bool, calendar: Calendar = WeekAgenda.calendar) -> String {
        let parts = calendar.dateComponents([.year, .month], from: month)
        let year = parts.year ?? 0, number = parts.month ?? 1
        guard english else { return "\(year) 年 \(number) 月" }
        let names = DateFormatter()
        names.locale = Locale(identifier: "en_US_POSIX")
        let monthName = names.standaloneMonthSymbols[(number - 1 + 12) % 12]
        return "\(monthName) \(year)"
    }

    /// 读屏念的那天：「10 月 23 日 周五」，英文界面「Fri, Oct 23」。
    public static func dayTitle(_ date: Date, english: Bool, calendar: Calendar = WeekAgenda.calendar) -> String {
        let parts = calendar.dateComponents([.month, .day], from: date)
        let month = parts.month ?? 1, day = parts.day ?? 1
        let index = CalendarLook.weekdayIndex(date, calendar: calendar)
        guard english else { return "\(month) 月 \(day) 日 周" + ["一", "二", "三", "四", "五", "六", "日"][index] }
        let names = DateFormatter()
        names.locale = Locale(identifier: "en_US_POSIX")
        let weekday = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][index]
        return "\(weekday), \(names.shortStandaloneMonthSymbols[(month - 1 + 12) % 12]) \(day)"
    }

    /// 本月那一片的轮廓，按格子算的折线顶点（x 是列 0...7，y 是行 0...行数），顺时针，首尾不重复。
    /// 第一行从 1 号那一列开始，最后一行到月底那一列为止，中间整行；正好从周一开始或到周日结束时少两个角。
    public static func outline(_ weeks: [Week]) -> [(x: Int, y: Int)] {
        guard let firstRow = weeks.first, let lastRow = weeks.last,
              let c0 = firstRow.days.firstIndex(where: \.inMonth),
              let cl = lastRow.days.lastIndex(where: \.inMonth) else { return [] }
        let rows = weeks.count
        var points: [(x: Int, y: Int)] = [(c0, 0), (7, 0)]
        if cl == 6 {
            points.append((7, rows))
        } else {
            points += [(7, rows - 1), (cl + 1, rows - 1), (cl + 1, rows)]
        }
        if c0 == 0 {
            points.append((0, rows))
        } else {
            points += [(0, rows), (0, 1), (c0, 1)]
        }
        // 只有一行的月份不存在（最少 28 天），这里不用处理折回去的情况。
        return points
    }
}
