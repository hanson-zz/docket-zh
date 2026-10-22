import Foundation

/// 日历面板（日历和一周日程共用）的两处压缩：
///
/// - `AgendaFold`：那天的时间轴按小时画时，连续 2 小时以上没有定时日程的整点段
///   折成一条细行「空闲 3 小时」，点了展开；现在线所在的那一小时和下一小时永不折叠，
///   这样「专注一下」的空档总看得见。点开的段顶上留一条「收起」细行，点了重新折叠。
///   一天没有定时日程时不画轴，界面给一句空状态；看的是今天时空状态里也能直接专注。
/// - `WeekLunar`：一周条每天数字下面那行农历小字：节气 > 休 / 班 > 初一写月名 > 日名；
///   窄了只留节气、休 / 班和初一；英文界面不显示。
///
/// 纯逻辑，界面把日程拍平成 `CalendarSpan` 后交给这里，测试不需要日历数据库。
public enum AgendaFold {
    /// 至少这么多个整点连着空着才折。
    public static let minimumHours = 2
    /// 折起来那一条的高度（pt），界面和 `AgendaAxis` 共用。
    public static let foldHeight: Double = 28
    /// 点开的段顶上那条「收起」细行的高度（pt）。
    public static let collapseHeight: Double = 22

    /// 时间轴上的一段：照常按小时画，折成一条「空闲 N 小时」，或者是点开的段顶上那条「收起」。
    /// `collapse` 不占时间（起点和终点都是点开那段的起点），只占 `collapseHeight` 的高度。
    public struct Segment: Equatable, Hashable, Sendable {
        public enum Kind: Equatable, Hashable, Sendable { case hours, free, collapse }
        public var kind: Kind
        /// 整点，和轴的范围一样从当天零点算。
        public var start: Int
        public var end: Int

        public init(kind: Kind, start: Int, end: Int) {
            self.kind = kind
            self.start = start
            self.end = end
        }

        public var hours: Int { end - start }
        /// 折起来的段（和它点开后的「收起」）用起点当身份：界面记「哪几段点开了」。
        public var id: Int { start }
    }

    /// 那天有没有要画在轴上的定时日程（全天的不算，跨午夜的只看落在这天的部分）。
    public static func hasTimed(_ spans: [CalendarSpan], day: Date, calendar: Calendar = WeekAgenda.calendar) -> Bool {
        let (dayStart, dayEnd) = bounds(day, calendar: calendar)
        return spans.contains { !$0.isAllDay && $0.start < dayEnd && visibleEnd($0) > dayStart }
    }

    /// 轴分段。`expanded` 是用户点开过的折叠段起点，这些段照常画，前面插一条 `collapse`。
    ///
    /// 每个整点 [h, h+1) 只要和任何定时日程重叠就算忙（首尾相接不算）。看的是今天时，
    /// 现在所在的那一小时和下一小时不折。其余连着空着、至少 `minimum` 小时的整点折成一条。
    public static func segments(_ spans: [CalendarSpan], hours: ClosedRange<Int>, day: Date, now: Date,
                                expanded: Set<Int> = [], minimum: Int = AgendaFold.minimumHours,
                                calendar: Calendar = WeekAgenda.calendar) -> [Segment] {
        let low = hours.lowerBound, high = hours.upperBound
        guard high > low else { return [] }
        let (dayStart, dayEnd) = bounds(day, calendar: calendar)
        let timed = spans.filter { !$0.isAllDay && $0.start < dayEnd && visibleEnd($0) > dayStart }

        var protected: Set<Int> = []
        if calendar.isDate(now, inSameDayAs: day) {
            let hour = Int((now.timeIntervalSince(dayStart) / 3_600).rounded(.down))
            protected = [hour, hour + 1]
        }

        func foldable(_ hour: Int) -> Bool {
            guard !protected.contains(hour) else { return false }
            let from = dayStart.addingTimeInterval(Double(hour) * 3_600)
            let to = from.addingTimeInterval(3_600)
            return !timed.contains { $0.start < to && visibleEnd($0) > from }
        }

        // 先找出所有能折的整点段，再把剩下的并成照常画的段。
        var result: [Segment] = []
        var hour = low
        var plainStart: Int?
        func closePlain(at end: Int) {
            if let start = plainStart, end > start { result.append(Segment(kind: .hours, start: start, end: end)) }
            plainStart = nil
        }
        while hour < high {
            if foldable(hour) {
                var end = hour
                while end < high, foldable(end) { end += 1 }
                if end - hour >= max(1, minimum), !expanded.contains(hour) {
                    closePlain(at: hour)
                    result.append(Segment(kind: .free, start: hour, end: end))
                } else if end - hour >= max(1, minimum) {
                    closePlain(at: hour)
                    result.append(Segment(kind: .collapse, start: hour, end: hour))
                    plainStart = hour
                } else if plainStart == nil {
                    plainStart = hour
                }
                hour = end
            } else {
                if plainStart == nil { plainStart = hour }
                hour += 1
            }
        }
        closePlain(at: high)
        return result
    }

    /// 「空闲 3 小时」。
    public static func freeTitle(_ segment: Segment) -> String {
        tr("空闲 \(segment.hours) 小时")
    }

    /// 读屏念的：「9 点到 12 点空闲，点按展开」。
    public static func freeAccessibility(_ segment: Segment) -> String {
        tr("\(segment.start) 点到 \(segment.end) 点空闲，点按展开")
    }

    /// 「收起」细行读屏念的：「收起 10 点起的空闲」。
    public static func collapseAccessibility(_ segment: Segment) -> String {
        tr("收起 \(segment.start) 点起的空闲")
    }

    /// 一天没有定时日程时空状态里「专注一下」按的空档：从现在到当天结束。
    /// 只有看的是今天、剩下的不到 `minimum` 时才给（别的日子、快到午夜时不放这个按钮）。
    public static func emptyFocusGap(day: Date, now: Date, minimum: TimeInterval = CalendarPlanner.minimumGap,
                                     calendar: Calendar = WeekAgenda.calendar) -> DateInterval? {
        guard calendar.isDate(now, inSameDayAs: day) else { return nil }
        let (_, dayEnd) = bounds(day, calendar: calendar)
        guard dayEnd.timeIntervalSince(now) >= minimum else { return nil }
        return DateInterval(start: now, end: dayEnd)
    }

    /// 一天没有定时日程时那句空状态。只有全天日程时换个说法，免得和顶上的全天条矛盾。
    public static func emptyLine(day: Date, now: Date, hasAllDay: Bool,
                                 calendar: Calendar = WeekAgenda.calendar) -> String {
        if hasAllDay { return tr("除了全天日程，没有别的安排") }
        return calendar.isDate(day, inSameDayAs: now) ? tr("今天没有日程，安排点什么吧") : tr("这天没有日程")
    }

    /// 空档在轴上看得见的那部分：从它的起点到第一段折叠为止。
    /// 空档跨过「收起」细行时不压在它上面：前半截够 `minimum` 就只画前半截（现在线那一段的专注入口不丢），
    /// 不够就从细行下面开始画。看得见的不到 `minimum` 时为 nil（太矮放不下字和按钮）。
    public static func visible(_ gap: DateInterval, in segments: [Segment], day: Date,
                               minimum: TimeInterval = CalendarPlanner.minimumGap,
                               calendar: Calendar = WeekAgenda.calendar) -> DateInterval? {
        let dayStart = calendar.startOfDay(for: day)
        var start = gap.start
        var end = gap.end
        for segment in segments {
            let segStart = dayStart.addingTimeInterval(Double(segment.start) * 3_600)
            let segEnd = dayStart.addingTimeInterval(Double(segment.end) * 3_600)
            switch segment.kind {
            case .hours:
                continue
            case .free:
                if segEnd <= start { continue }
                if segStart <= start { return nil }
                end = min(end, segStart)
            case .collapse:
                if segStart <= start || segStart >= end { continue }
                if segStart.timeIntervalSince(start) >= minimum {
                    end = segStart
                } else {
                    start = segStart
                    continue
                }
            }
            break
        }
        guard end.timeIntervalSince(start) >= minimum else { return nil }
        return DateInterval(start: start, end: end)
    }

    // MARK: Helpers

    static func bounds(_ day: Date, calendar: Calendar) -> (Date, Date) {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return (start, end)
    }

    /// 零长度的日程也占一分钟，和 `DayTimeline.blocks` 一样。
    static func visibleEnd(_ span: CalendarSpan) -> Date {
        max(span.end, span.start.addingTimeInterval(60))
    }
}

/// 折叠后的轴：把「当天第几小时」换成竖直位置。照常画的段每小时 `hourHeight`，
/// 折叠段整条 `foldHeight`（段里的时刻按比例落在这条里，只有被截断的空档会用到），
/// 「收起」细行 `collapseHeight`，不对应任何时刻。
public struct AgendaAxis: Equatable, Sendable {
    public var segments: [AgendaFold.Segment]
    public var hourHeight: Double
    public var foldHeight: Double
    public var collapseHeight: Double

    public init(segments: [AgendaFold.Segment], hourHeight: Double, foldHeight: Double = AgendaFold.foldHeight,
                collapseHeight: Double = AgendaFold.collapseHeight) {
        self.segments = segments
        self.hourHeight = hourHeight
        self.foldHeight = foldHeight
        self.collapseHeight = collapseHeight
    }

    public func height(of segment: AgendaFold.Segment) -> Double {
        switch segment.kind {
        case .hours: Double(segment.hours) * hourHeight
        case .free: foldHeight
        case .collapse: collapseHeight
        }
    }

    public var height: Double { segments.reduce(0) { $0 + height(of: $1) } }

    /// 每段的顶边。
    public var tops: [Double] {
        var y = 0.0
        return segments.map { segment in
            defer { y += height(of: segment) }
            return y
        }
    }

    /// 当天第 `hour` 小时（可带小数）的竖直位置；轴外的夹到两头。
    ///
    /// 正好落在「收起」细行上的整点有两个位置：当起点用（日程、空档的顶边，默认）落在细行下面，
    /// `trailing` 当终点用（底边）落在细行上面，这样首尾相接的日程和空档都不会压住细行。
    public func y(hour: Double, trailing: Bool = false) -> Double {
        guard let first = segments.first, let last = segments.last else { return 0 }
        if hour < Double(first.start) { return 0 }
        if hour > Double(last.end) { return height }
        var top = 0.0
        for segment in segments {
            let h = height(of: segment)
            if segment.kind != .collapse,
               trailing ? hour <= Double(segment.end) : hour < Double(segment.end) {
                let fraction = (hour - Double(segment.start)) / Double(max(1, segment.hours))
                return top + max(0, fraction) * h
            }
            top += h
        }
        return height
    }

    public func y(_ date: Date, day: Date, trailing: Bool = false, calendar: Calendar = WeekAgenda.calendar) -> Double {
        y(hour: date.timeIntervalSince(calendar.startOfDay(for: day)) / 3_600, trailing: trailing)
    }

    /// 左边要写字的整点：照常画的段每个整点都写（两头都写），折叠段不写。
    public var labelHours: [Int] {
        var seen: Set<Int> = []
        var result: [Int] = []
        for segment in segments where segment.kind == .hours {
            for hour in segment.start...segment.end {
                if seen.insert(hour).inserted { result.append(hour) }
            }
        }
        return result
    }
}

// MARK: - 一周条农历

public enum WeekLunar {
    /// 这行字是什么：界面按它配色（节气用强调色，休 / 班用绿 / 橙，其余淡色）。
    public enum Style: Equatable, Sendable { case term, holiday, makeup, month, day }

    public struct Label: Equatable, Sendable {
        public var text: String
        public var style: Style

        public init(_ text: String, _ style: Style) {
            self.text = text
            self.style = style
        }
    }

    /// 宽度够写几种：`full` 每天都写，`compact` 只写节气、休 / 班和初一，`hidden` 不写。
    public enum Density: Equatable, Sendable { case full, compact, hidden }

    /// 一个字 13pt，两个字加左右各一点空要这么宽才放得下。
    public static let fullWidth: Double = 36
    public static let compactWidth: Double = 28

    /// 每天一列有多宽时写几种。英文界面不写（农历和节气是中文用户的东西，英文没有约定俗成的短写法）。
    public static func density(columnWidth: Double, english: Bool) -> Density {
        guard !english, columnWidth.isFinite else { return .hidden }
        if columnWidth >= fullWidth { return .full }
        if columnWidth >= compactWidth { return .compact }
        return .hidden
    }

    /// 某天（按 `calendar` 的那一天，换成中国的同一天去查农历）那一行。
    /// 优先级：节气 > 法定假日「休」/ 调休上班「班」> 初一写月名（闰月写「闰六」）> 日名。
    /// `compact` 时不写日名，普通日子返回 nil。
    public static func label(for date: Date, density: Density,
                             holidays: [Int: [HolidayDay]] = AlarmHolidays.current,
                             terms: [Int: [ChineseCalendar.SolarTerm]]? = nil,
                             calendar: Calendar = WeekAgenda.calendar) -> Label? {
        guard density != .hidden, let day = chinaDay(date, calendar: calendar) else { return nil }
        let year = ChineseCalendar.gregorian.component(.year, from: day)
        let yearTerms = terms?[year] ?? ChineseCalendar.solarTerms(year: year)
        if let term = yearTerms.first(where: { $0.day == day }) { return Label(term.name, .term) }
        switch HolidaySchedule.kind(of: day, known: holidays) {
        case .holiday: return Label("休", .holiday)
        case .makeupWorkday: return Label("班", .makeup)
        case .weekend, .workday: break
        }
        let lunar = ChineseCalendar.lunar(day)
        if lunar.day == 1 { return Label(monthText(lunar), .month) }
        return density == .full ? Label(lunar.dayName, .day) : nil
    }

    /// 一周七天一起算，节气表每年只算一次。
    public static func labels(for dates: [Date], density: Density,
                              holidays: [Int: [HolidayDay]] = AlarmHolidays.current,
                              calendar: Calendar = WeekAgenda.calendar) -> [Date: Label] {
        guard density != .hidden else { return [:] }
        let years = Set(dates.compactMap { chinaDay($0, calendar: calendar) }
            .map { ChineseCalendar.gregorian.component(.year, from: $0) })
        let terms = Dictionary(uniqueKeysWithValues: years.map { ($0, ChineseCalendar.solarTerms(year: $0)) })
        var result: [Date: Label] = [:]
        for date in dates {
            if let label = label(for: date, density: density, holidays: holidays, terms: terms, calendar: calendar) {
                result[date] = label
            }
        }
        return result
    }

    /// 「十月」「正月」「腊月」，闰月两个字写不下「闰六月」，写「闰六」。
    static func monthText(_ lunar: ChineseCalendar.LunarDate) -> String {
        guard lunar.isLeapMonth else { return lunar.monthName }
        return "闰" + ChineseCalendar.LunarDate.monthNames[(lunar.month - 1) % 12]
    }

    /// 本地日历上的那一天换成中国的同一天零点（日、时区不同也按墙上的日期对齐）。
    static func chinaDay(_ date: Date, calendar: Calendar) -> Date? {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return ChineseCalendar.gregorian.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day))
    }
}
