import Foundation

/// 时间进度面板用到的数：今年每一天是什么日子、接下来的四个节点、一句话，
/// 以及剩几个周末、几个工作日。面板五套样式（圆环、百分比、液态、进度条、
/// 四格）画法不同，读的都是这里。
///
/// 一周固定从周一开始（`TimeProgress.calendar`），不跟系统的 firstWeekday，
/// 卡片和面板一样。法定假日和调休复用 `HolidaySchedule`，纪念日读码头上
/// 纪念日卡片的配置，没有就不标。不读日历事件。
extension TimeProgress {

    // MARK: 一年里的每一天

    /// 年度点阵和进度条主视觉里一天的颜色。
    public enum DayMark: String, Equatable, Sendable {
        case past, future, holiday, makeupWorkday, anniversary, today
    }

    public struct YearDay: Equatable, Sendable {
        public var date: Date
        public var month: Int
        public var day: Int
        /// 今年第几天，从 1 起。
        public var ordinal: Int
        /// 0 是周一，6 是周日。
        public var weekday: Int
        public var mark: DayMark
        /// 在今天之前。假日、纪念日过去了和没到画得深浅不同。
        public var isPast: Bool
    }

    /// 周一是 0，周日是 6。
    public static func mondayIndex(_ date: Date, calendar: Calendar = TimeProgress.calendar) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7
    }

    /// 本地日期的 yyyy-MM-dd，和 `HolidayDay.date` 同一种写法。按本地日历取年月日，
    /// 不换算到北京时间，所以哪个时区看都是自己的那一天。
    public static func holidayKey(_ date: Date, calendar: Calendar = TimeProgress.calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// 这一天在国务院通知里的身份；没写的按周六周日放假。
    public static func dayKind(_ date: Date, known: [Int: [HolidayDay]],
                               calendar: Calendar = TimeProgress.calendar) -> HolidaySchedule.DayKind {
        let year = calendar.component(.year, from: date)
        let key = holidayKey(date, calendar: calendar)
        if let entry = known[year]?.first(where: { $0.date == key }) {
            return entry.isOffDay ? .holiday(entry.name) : .makeupWorkday(entry.name)
        }
        return mondayIndex(date, calendar: calendar) >= 5 ? .weekend : .workday
    }

    /// 要上班的日子：普通工作日和调休上班；法定假日不算。
    public static func isWorkday(_ date: Date, known: [Int: [HolidayDay]],
                                 calendar: Calendar = TimeProgress.calendar) -> Bool {
        switch dayKind(date, known: known, calendar: calendar) {
        case .workday, .makeupWorkday: true
        case .weekend, .holiday: false
        }
    }

    /// 纪念日落在这一年的哪些天（yyyy-MM-dd）。每年的取今年那一次（农历的
    /// 按今年碰到的那一次），只一次的取它自己；还没到第一次的年份不标。
    public static func anniversaryKeys(_ events: [AnniversaryEvent], year: Int,
                                       calendar: Calendar = TimeProgress.calendar) -> Set<String> {
        var keys = Set<String>()
        for event in events {
            guard let original = Anniversary.date(fromKey: event.day, calendar: calendar) else { continue }
            var dates = [original]
            if event.yearly {
                // 农历的一年从正月起，腊月的日子落在下一个公历年的一月，所以前一年也看。
                dates += [year - 1, year].compactMap { Anniversary.occurrence(event, year: $0, calendar: calendar) }
                    .filter { $0 >= original }
            }
            for date in dates where calendar.component(.year, from: date) == year {
                keys.insert(holidayKey(date, calendar: calendar))
            }
        }
        return keys
    }

    /// 今年的每一天，标好过去、未来、法定假日、调休上班、纪念日和今天。
    /// 同一天几种身份时，今天优先，其次纪念日、假日、调休。
    public static func yearDays(now: Date, known: [Int: [HolidayDay]],
                                anniversaries: [AnniversaryEvent] = [],
                                calendar: Calendar = TimeProgress.calendar) -> [YearDay] {
        guard let span = calendar.dateInterval(of: .year, for: now) else { return [] }
        let year = calendar.component(.year, from: now)
        let today = calendar.startOfDay(for: now)
        let marked = anniversaryKeys(anniversaries, year: year, calendar: calendar)
        var result: [YearDay] = []
        var day = span.start
        var ordinal = 1
        while day < span.end {
            let parts = calendar.dateComponents([.month, .day], from: day)
            let key = holidayKey(day, calendar: calendar)
            let mark: DayMark
            if day == today {
                mark = .today
            } else if marked.contains(key) {
                mark = .anniversary
            } else {
                switch dayKind(day, known: known, calendar: calendar) {
                case .holiday: mark = .holiday
                case .makeupWorkday: mark = .makeupWorkday
                case .weekend, .workday: mark = day < today ? .past : .future
                }
            }
            result.append(YearDay(date: day, month: parts.month ?? 1, day: parts.day ?? 1, ordinal: ordinal,
                                  weekday: mondayIndex(day, calendar: calendar), mark: mark, isPast: day < today))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = calendar.startOfDay(for: next)
            ordinal += 1
        }
        return result
    }

    // MARK: 天数

    /// 今年第几天，1 月 1 日是 1。
    public static func dayOfYear(_ now: Date, calendar: Calendar = TimeProgress.calendar) -> Int {
        calendar.ordinality(of: .day, in: .year, for: now) ?? 1
    }

    /// 这个周期一共几天（日是 1）。
    public static func length(_ period: Period, now: Date, calendar: Calendar = TimeProgress.calendar) -> Int {
        guard let span = interval(period, now: now, calendar: calendar) else { return 1 }
        return max(1, calendar.dateComponents([.day], from: span.start, to: span.end).day ?? 1)
    }

    /// 这个周期里今天是第几天（日是 1）。
    public static func dayIndex(_ period: Period, now: Date, calendar: Calendar = TimeProgress.calendar) -> Int {
        guard let span = interval(period, now: now, calendar: calendar) else { return 1 }
        let days = calendar.dateComponents([.day], from: span.start, to: calendar.startOfDay(for: now)).day ?? 0
        return days + 1
    }

    /// 从今天（算一天）到周期结束还有几天。
    public static func daysLeft(_ period: Period, now: Date, calendar: Calendar = TimeProgress.calendar) -> Int {
        guard let end = interval(period, now: now, calendar: calendar)?.end else { return 0 }
        return max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: end).day ?? 0)
    }

    /// 今天还剩多少分钟，向上取整。
    public static func minutesLeftToday(_ now: Date, calendar: Calendar = TimeProgress.calendar) -> Int {
        guard let end = interval(.day, now: now, calendar: calendar)?.end else { return 0 }
        return Int((max(0, end.timeIntervalSince(now)) / 60).rounded(.up))
    }

    /// 第几周，一周从周一开始。
    public static func weekOfYear(_ now: Date, calendar: Calendar = TimeProgress.calendar) -> Int {
        calendar.component(.weekOfYear, from: now)
    }

    /// 从今天到周期结束，每一天给 `include` 看一眼，数通过的。
    private static func count(_ period: Period, now: Date, calendar: Calendar,
                              _ include: (Date) -> Bool) -> Int {
        guard let end = interval(period, now: now, calendar: calendar)?.end else { return 0 }
        var day = calendar.startOfDay(for: now)
        var total = 0
        while day < end {
            if include(day) { total += 1 }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = calendar.startOfDay(for: next)
        }
        return total
    }

    /// 剩下要上班的天数，今天算：法定假日不算，调休上班算。
    public static func workdaysLeft(_ period: Period, now: Date, known: [Int: [HolidayDay]],
                                    calendar: Calendar = TimeProgress.calendar) -> Int {
        count(period, now: now, calendar: calendar) { isWorkday($0, known: known, calendar: calendar) }
    }

    /// 剩下几个周末：数今天起的周六；今天是周日时这个周末也算一个。
    public static func weekendsLeft(_ period: Period, now: Date,
                                    calendar: Calendar = TimeProgress.calendar) -> Int {
        let today = calendar.startOfDay(for: now)
        return count(period, now: now, calendar: calendar) { day in
            let index = mondayIndex(day, calendar: calendar)
            return index == 5 || (index == 6 && day == today)
        }
    }

    /// 离周六还有几天；今天是周六或周日时是 0。
    public static func daysToWeekend(_ now: Date, calendar: Calendar = TimeProgress.calendar) -> Int {
        max(0, 5 - mondayIndex(now, calendar: calendar))
    }

    // MARK: 本周七天

    public struct WeekDay: Equatable, Sendable {
        public var date: Date
        /// 0 是周一。
        public var index: Int
        /// 这一天过去了多少：之前的是 1，今天按钟点，之后的是 0。
        public var fraction: Double
        public var isToday: Bool
        public var isWeekend: Bool
    }

    /// 本周一到周日。
    public static func weekDays(now: Date, calendar: Calendar = TimeProgress.calendar) -> [WeekDay] {
        guard let start = interval(.week, now: now, calendar: calendar)?.start else { return [] }
        let today = calendar.startOfDay(for: now)
        return (0..<7).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let date = calendar.startOfDay(for: day)
            let fraction: Double = date < today ? 1 : (date == today ? TimeProgress.fraction(.day, now: now, calendar: calendar) : 0)
            return WeekDay(date: date, index: offset, fraction: fraction, isToday: date == today, isWeekend: offset >= 5)
        }
    }

    /// 本周的格子名：一、二……日。
    public static let weekdayShortNames = ["一", "二", "三", "四", "五", "六", "日"]

    public static func weekdayShort(_ index: Int) -> String {
        trKey(weekdayShortNames[max(0, min(6, index))])
    }

    // MARK: 刻度

    /// 主视觉上的一道刻度：0...1 的位置和写在旁边的字（空串只画线）。
    public struct Tick: Equatable, Sendable {
        public var position: Double
        public var label: String
    }

    /// 圆环外一圈的刻度数：日 24 小时、周 7 天、月按天数、年 12 个月。
    public static func ringTickCount(_ period: Period, now: Date, calendar: Calendar = TimeProgress.calendar) -> Int {
        switch period {
        case .day: 24
        case .week: 7
        case .month: length(.month, now: now, calendar: calendar)
        case .year: 12
        }
    }

    /// 圆环上哪几道刻度画长一点：日每 6 小时、月每 7 天、年每季度、周每天。
    public static func isMajorTick(_ index: Int, period: Period) -> Bool {
        switch period {
        case .day: index % 6 == 0
        case .week: true
        case .month: index % 7 == 0
        case .year: index % 3 == 0
        }
    }

    /// 进度条和大杯旁边的刻度：日按 0/6/12/18/24 时，周按七天，月按
    /// 1/8/15/22 日和月底，年按季度。
    public static func scale(_ period: Period, now: Date, calendar: Calendar = TimeProgress.calendar) -> [Tick] {
        switch period {
        case .day:
            return [0, 6, 12, 18, 24].map { Tick(position: Double($0) / 24, label: tr("\($0)时")) }
        case .week:
            return (0..<7).map { Tick(position: (Double($0) + 0.5) / 7, label: weekdayShort($0)) }
        case .month:
            let days = length(.month, now: now, calendar: calendar)
            return [1, 8, 15, 22].map { day in
                Tick(position: Double(day - 1) / Double(days), label: day == 1 ? tr("\(day)日") : "\(day)")
            } + [Tick(position: 1, label: tr("\(days)日"))]
        case .year:
            let year = calendar.component(.year, from: now)
            let total = Double(length(.year, now: now, calendar: calendar))
            return [1, 4, 7, 10].map { month in
                let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? now
                let ordinal = Double(calendar.ordinality(of: .day, in: .year, for: start) ?? 1)
                return Tick(position: (ordinal - 1) / total, label: tr("\(month)月"))
            } + [Tick(position: 1, label: tr("年底"))]
        }
    }

    /// 进度条样式四周期对比里每条分几段：今天 24 小时、本周 7 天、本月按天数、今年 52 周。
    public static func unitCount(_ period: Period, now: Date, calendar: Calendar = TimeProgress.calendar) -> Int {
        switch period {
        case .day: 24
        case .week: 7
        case .month: length(.month, now: now, calendar: calendar)
        case .year: 52
        }
    }

    // MARK: 文案

    /// 还剩多少，面板上的写法：今天「还剩 13 小时 36 分」，其他「还剩 73 天」。
    public static func remainingDetail(_ period: Period, now: Date, calendar: Calendar = TimeProgress.calendar) -> String {
        if period == .day {
            let minutes = minutesLeftToday(now, calendar: calendar)
            return minutes >= 60 ? tr("还剩 \(minutes / 60) 小时 \(minutes % 60) 分")
                                 : tr("还剩 \(minutes) 分钟")
        }
        return tr("还剩 \(daysLeft(period, now: now, calendar: calendar)) 天")
    }

    /// 四周期对比和四格里的短写法：「剩 13时36分」「剩 73 天」。
    public static func remainingShort(_ period: Period, now: Date, calendar: Calendar = TimeProgress.calendar) -> String {
        if period == .day {
            let minutes = minutesLeftToday(now, calendar: calendar)
            return minutes >= 60 ? tr("剩 \(minutes / 60)时\(minutes % 60)分") : tr("剩 \(minutes) 分钟")
        }
        return tr("剩 \(daysLeft(period, now: now, calendar: calendar)) 天")
    }

    /// 大数字旁边的「还剩」：数字和单位分开写，数字大一号。
    public struct Remaining: Equatable, Sendable {
        public var value: String
        public var unit: String
    }

    public static func remainingParts(_ period: Period, now: Date,
                                      calendar: Calendar = TimeProgress.calendar) -> Remaining {
        if period == .day {
            let minutes = minutesLeftToday(now, calendar: calendar)
            if minutes >= 60 { return Remaining(value: "\(minutes / 60)", unit: tr("小时 \(minutes % 60) 分")) }
            return Remaining(value: "\(minutes)", unit: tr("分钟"))
        }
        return Remaining(value: "\(daysLeft(period, now: now, calendar: calendar))", unit: tr("天"))
    }

    /// 今天是什么日子：上班、周末、调休上班，或者假日的名字。
    public static func todayStatus(_ now: Date, known: [Int: [HolidayDay]],
                                   calendar: Calendar = TimeProgress.calendar) -> String {
        switch dayKind(now, known: known, calendar: calendar) {
        case .workday: tr("今天上班")
        case .weekend: tr("今天周末")
        case .makeupWorkday: tr("今天调休上班")
        case .holiday(let name): trKey(name)
        }
    }

    /// 主视觉旁的两行事实：第几天、第几周、几个工作日。
    public static func facts(_ period: Period, now: Date, known: [Int: [HolidayDay]],
                             calendar: Calendar = TimeProgress.calendar) -> [String] {
        let week = weekOfYear(now, calendar: calendar)
        switch period {
        case .day:
            return [tr("第 \(dayOfYear(now, calendar: calendar)) 天"), todayStatus(now, known: known, calendar: calendar)]
        case .week:
            return [tr("本周第 \(dayIndex(.week, now: now, calendar: calendar)) 天"), tr("第 \(week) 周")]
        case .month:
            return [tr("第 \(dayIndex(.month, now: now, calendar: calendar)) / \(length(.month, now: now, calendar: calendar)) 天"),
                    tr("\(workdaysLeft(.month, now: now, known: known, calendar: calendar)) 个工作日")]
        case .year:
            return [tr("第 \(dayOfYear(now, calendar: calendar)) / \(length(.year, now: now, calendar: calendar)) 天"),
                    tr("第 \(week) 周")]
        }
    }

    /// 底部一句话，按周期只陈述事实：剩几天、几个周末或工作日、第几天。
    public static func note(_ period: Period, now: Date, known: [Int: [HolidayDay]],
                            calendar: Calendar = TimeProgress.calendar) -> String {
        switch period {
        case .day:
            return tr("今天是今年第 \(dayOfYear(now, calendar: calendar)) 天。")
        case .week:
            let left = daysLeft(.week, now: now, calendar: calendar)
            let work = workdaysLeft(.week, now: now, known: known, calendar: calendar)
            return tr("本周还剩 \(left) 天，其中 \(work) 个工作日。")
        case .month:
            let left = daysLeft(.month, now: now, calendar: calendar)
            let work = workdaysLeft(.month, now: now, known: known, calendar: calendar)
            return tr("\(label(.month, now: now, calendar: calendar))还剩 \(left) 天，其中 \(work) 个工作日。")
        case .year:
            let left = daysLeft(.year, now: now, calendar: calendar)
            let weekends = weekendsLeft(.year, now: now, calendar: calendar)
            return tr("今年还剩 \(left) 天，还有 \(weekends) 个周末。")
        }
    }

    /// 四格没有主周期，一句话写第几周、本周第几天。
    public static func quadNote(now: Date, calendar: Calendar = TimeProgress.calendar) -> String {
        tr("今年第 \(weekOfYear(now, calendar: calendar)) 周，本周第 \(dayIndex(.week, now: now, calendar: calendar)) 天。")
    }

    /// 四格面板顶上的日期：「10月20日 周二」。
    public static func dateTitle(_ now: Date, calendar: Calendar = TimeProgress.calendar) -> String {
        let month = calendar.component(.month, from: now)
        let day = calendar.component(.day, from: now)
        return tr("\(month)月\(day)日 \(label(.day, now: now, calendar: calendar))")
    }

    // MARK: 接下来

    public struct Milestone: Equatable, Sendable {
        public enum Kind: String, Sendable { case weekend, monthEnd, solarTerm, holiday }
        public var kind: Kind
        public var title: String
        public var date: Date
        /// 从今天数过去的天数，今天是 0。
        public var days: Int
        /// 下一年的放假安排还没公布，日子按节日本身估的。
        public var estimated: Bool
    }

    /// 接下来的节点：周末、月底、下一个节气、下一个法定假日，按天数排，取前 `limit` 个。
    /// 正在放的假期按 0 天算；当天就是月底时看下个月底。
    public static func milestones(now: Date, known: [Int: [HolidayDay]], limit: Int = 4,
                                  calendar: Calendar = TimeProgress.calendar) -> [Milestone] {
        let today = calendar.startOfDay(for: now)
        func days(to date: Date) -> Int {
            calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: date)).day ?? 0
        }
        var items: [Milestone] = []

        // 周末：下一个周六；今天已是周末就看下周六。
        let toSaturday = (5 - mondayIndex(now, calendar: calendar) + 7) % 7
        let saturdayOffset = toSaturday == 0 ? 7 : toSaturday
        if let saturday = calendar.date(byAdding: .day, value: saturdayOffset, to: today) {
            items.append(Milestone(kind: .weekend, title: tr("周末"), date: saturday, days: saturdayOffset, estimated: false))
        }

        // 月底：这个月最后一天；今天就是最后一天时看下个月的。
        if let end = interval(.month, now: now, calendar: calendar)?.end,
           var last = calendar.date(byAdding: .day, value: -1, to: end) {
            if calendar.startOfDay(for: last) == today,
               let nextEnd = interval(.month, now: end, calendar: calendar)?.end,
               let nextLast = calendar.date(byAdding: .day, value: -1, to: nextEnd) {
                last = nextLast
            }
            items.append(Milestone(kind: .monthEnd, title: tr("月底"), date: calendar.startOfDay(for: last),
                                   days: days(to: last), estimated: false))
        }

        // 下一个节气（今天就是节气时算今天）。节气按北京时间定日子。
        if let term = ChineseCalendar.nextTerm(after: now) {
            let key = ChineseCalendar.key(term.day)
            let day = dateFromHolidayKey(key, calendar: calendar) ?? term.day
            items.append(Milestone(kind: .solarTerm, title: trKey(term.name), date: day,
                                   days: max(0, days(to: day)), estimated: false))
        }

        // 下一个法定假日：今年和明年，没公布的年份按节日本身估。
        let year = calendar.component(.year, from: now)
        let breaks = HolidaySchedule.breaks(years: year...(year + 1), known: known)
        if let item = HolidaySchedule.next(after: now, in: breaks) {
            let key = ChineseCalendar.key(item.start)
            let day = dateFromHolidayKey(key, calendar: calendar) ?? item.start
            items.append(Milestone(kind: .holiday, title: trKey(HolidaySchedule.shortName(item.name)), date: day,
                                   days: max(0, days(to: day)), estimated: item.estimated))
        }

        let order: [Milestone.Kind] = [.solarTerm, .weekend, .monthEnd, .holiday]
        return Array(items.sorted {
            $0.days != $1.days ? $0.days < $1.days
                : (order.firstIndex(of: $0.kind) ?? 0) < (order.firstIndex(of: $1.kind) ?? 0)
        }.prefix(max(0, limit)))
    }

    /// yyyy-MM-dd 在本地日历里的零点。
    static func dateFromHolidayKey(_ key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
