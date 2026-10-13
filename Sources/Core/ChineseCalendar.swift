import Foundation

/// 农历、节气与法定节假日，全部在本机计算，只有调休安排需要联网更新。
///
/// The lunar date comes from Foundation's own Chinese calendar. Solar terms
/// are computed from the Sun's apparent longitude (Meeus' low-precision
/// formula, good to about 0.01 degree, so a term lands within a quarter of an
/// hour of the almanac). Public holidays and make-up workdays are announced by
/// the State Council each November, so they are data: one year is bundled and
/// later years are fetched (see `HolidayService`), and a year nobody has
/// announced yet falls back to the festival days themselves, marked as
/// estimates.
public enum ChineseCalendar {
    public static let zone = TimeZone(identifier: "Asia/Shanghai")!

    static var gregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    static var lunarCalendar: Calendar {
        var calendar = Calendar(identifier: .chinese)
        calendar.timeZone = zone
        return calendar
    }

    // MARK: Lunar date

    public struct LunarDate: Equatable, Sendable {
        /// Position in the sixty-year cycle, 1 to 60.
        public var cycleYear: Int
        public var month: Int
        public var day: Int
        public var isLeapMonth: Bool

        static let stems = Array("甲乙丙丁戊己庚辛壬癸").map(String.init)
        static let branches = Array("子丑寅卯辰巳午未申酉戌亥").map(String.init)
        static let animals = Array("鼠牛虎兔龙蛇马羊猴鸡狗猪").map(String.init)
        static let monthNames = ["正", "二", "三", "四", "五", "六", "七", "八", "九", "十", "冬", "腊"]
        static let digits = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]

        /// 丙午
        public var ganzhiYear: String {
            let index = max(cycleYear - 1, 0)
            return Self.stems[index % 10] + Self.branches[index % 12]
        }

        /// 马
        public var zodiac: String { Self.animals[max(cycleYear - 1, 0) % 12] }

        /// 九月, 闰六月
        public var monthName: String {
            (isLeapMonth ? "闰" : "") + Self.monthNames[(month - 1) % 12] + "月"
        }

        /// 初三, 十五, 廿一, 三十
        public var dayName: String {
            switch day {
            case 10: "初十"
            case 20: "二十"
            case 30: "三十"
            case 1...9: "初" + Self.digits[day - 1]
            case 11...19: "十" + Self.digits[day - 11]
            case 21...29: "廿" + Self.digits[day - 21]
            default: "\(day)"
            }
        }

        /// 九月初三
        public var short: String { monthName + dayName }

        /// 丙午马年 九月初三
        public var full: String { "\(ganzhiYear)\(zodiac)年 \(short)" }
    }

    public static func lunar(_ date: Date) -> LunarDate {
        let calendar = lunarCalendar
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return LunarDate(cycleYear: parts.year ?? 1, month: parts.month ?? 1, day: parts.day ?? 1,
                         isLeapMonth: parts.isLeapMonth ?? false)
    }

    /// The Gregorian day a lunar date falls on in a given Gregorian year, for
    /// the festivals: 春节 is lunar 1-1 of the lunar year that starts in that
    /// Gregorian year, and every other festival follows it.
    public static func gregorianDay(lunarMonth: Int, day: Int, inGregorianYear year: Int) -> Date? {
        let lunar = lunarCalendar
        // Lunar new year falls between Jan 21 and Feb 20, so mid-March is
        // always in the lunar year that started this Gregorian year.
        guard let anchor = gregorian.date(from: DateComponents(year: year, month: 3, day: 15)) else { return nil }
        var parts = lunar.dateComponents([.era, .year], from: anchor)
        parts.month = lunarMonth
        parts.day = day
        parts.isLeapMonth = false
        guard let found = lunar.date(from: parts) else { return nil }
        return gregorian.startOfDay(for: found)
    }

    /// 除夕: the day before the next lunar new year. Its Gregorian year is the
    /// lunar new year's, which can be a different one from the eve's own in
    /// late January.
    public static func newYearsEve(lunarNewYearIn year: Int) -> Date? {
        guard let newYear = gregorianDay(lunarMonth: 1, day: 1, inGregorianYear: year) else { return nil }
        return gregorian.date(byAdding: .day, value: -1, to: newYear)
    }

    /// Traditional days that are not public holidays, shown beside the date.
    static let lunarFestivals: [String: String] = [
        "1-1": "春节", "1-15": "元宵节", "2-2": "龙抬头", "3-3": "上巳节",
        "5-5": "端午节", "7-7": "七夕", "7-15": "中元节", "8-15": "中秋节",
        "9-9": "重阳节", "10-1": "寒衣节", "10-15": "下元节", "12-8": "腊八节",
        "12-23": "北方小年", "12-24": "南方小年",
    ]

    /// 春节, 七夕, 除夕, or nil.
    public static func festival(on date: Date) -> String? {
        let lunar = lunar(date)
        if !lunar.isLeapMonth, let name = lunarFestivals["\(lunar.month)-\(lunar.day)"] { return name }
        let calendar = gregorian
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) {
            let next = Self.lunar(tomorrow)
            if next.month == 1, next.day == 1, !next.isLeapMonth { return "除夕" }
        }
        return nil
    }

    // MARK: Solar terms

    /// In calendar order through a Gregorian year, starting with 小寒.
    public static let termNames = [
        "小寒", "大寒", "立春", "雨水", "惊蛰", "春分", "清明", "谷雨",
        "立夏", "小满", "芒种", "夏至", "小暑", "大暑", "立秋", "处暑",
        "白露", "秋分", "寒露", "霜降", "立冬", "小雪", "大雪", "冬至",
    ]

    public struct SolarTerm: Equatable, Sendable {
        public var name: String
        /// The moment the Sun reaches the term's longitude.
        public var moment: Date
        /// The day that moment falls on in China.
        public var day: Date
    }

    /// The Sun's apparent ecliptic longitude in degrees, 0 to 360.
    static func solarLongitude(julianDay jd: Double) -> Double {
        let t = (jd - 2_451_545.0) / 36_525.0
        let l0 = 280.46646 + 36_000.76983 * t + 0.0003032 * t * t
        let m = (357.52911 + 35_999.05029 * t - 0.0001537 * t * t) * .pi / 180
        let c = (1.914602 - 0.004817 * t - 0.000014 * t * t) * sin(m)
            + (0.019993 - 0.000101 * t) * sin(2 * m)
            + 0.000289 * sin(3 * m)
        let omega = (125.04 - 1934.136 * t) * .pi / 180
        let apparent = l0 + c - 0.00569 - 0.00478 * sin(omega)
        let wrapped = apparent.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    static func julianDay(_ date: Date) -> Double { date.timeIntervalSince1970 / 86_400 + 2_440_587.5 }
    static func date(julianDay jd: Double) -> Date { Date(timeIntervalSince1970: (jd - 2_440_587.5) * 86_400) }

    /// The 24 terms of a Gregorian year, in order.
    public static func solarTerms(year: Int) -> [SolarTerm] {
        let calendar = gregorian
        guard let jan6 = calendar.date(from: DateComponents(year: year, month: 1, day: 6, hour: 12)) else { return [] }
        let start = julianDay(jan6)
        return termNames.enumerated().map { index, name in
            let target = (285.0 + 15.0 * Double(index)).truncatingRemainder(dividingBy: 360)
            var jd = start + 15.2184 * Double(index)
            for _ in 0..<6 {
                var delta = target - solarLongitude(julianDay: jd)
                if delta > 180 { delta -= 360 }
                if delta < -180 { delta += 360 }
                jd += delta / 360 * 365.2422
            }
            // Meeus works in dynamical time, about 69 seconds ahead of UTC.
            let moment = date(julianDay: jd - 69.0 / 86_400)
            return SolarTerm(name: name, moment: moment, day: calendar.startOfDay(for: moment))
        }
    }

    /// The term that falls on this day, if any.
    public static func term(on date: Date) -> String? {
        let calendar = gregorian
        let day = calendar.startOfDay(for: date)
        let year = calendar.component(.year, from: date)
        return solarTerms(year: year).first { $0.day == day }?.name
    }

    /// The next term on or after today.
    public static func nextTerm(after date: Date) -> SolarTerm? {
        let calendar = gregorian
        let day = calendar.startOfDay(for: date)
        let year = calendar.component(.year, from: date)
        return (solarTerms(year: year) + solarTerms(year: year + 1)).first { $0.day >= day }
    }

    // MARK: Days

    /// Whole days from one day to another, both read in China.
    public static func days(from: Date, to: Date) -> Int {
        let calendar = gregorian
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: from),
                                       to: calendar.startOfDay(for: to)).day ?? 0
    }

    /// yyyy-MM-dd in China.
    public static func key(_ date: Date) -> String {
        let parts = gregorian.dateComponents([.year, .month, .day], from: date)
        let year = parts.year ?? 0, month = parts.month ?? 0, day = parts.day ?? 0
        return "\(year)-\(month < 10 ? "0" : "")\(month)-\(day < 10 ? "0" : "")\(day)"
    }

    /// Midnight in China of a yyyy-MM-dd key.
    public static func day(_ key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        return gregorian.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

// MARK: - Public holidays

/// One day of the official schedule: off, or a weekend worked to make up.
public struct HolidayDay: Equatable, Hashable, Sendable, Codable {
    public var name: String
    /// yyyy-MM-dd in China.
    public var date: String
    public var isOffDay: Bool

    public init(name: String, date: String, isOffDay: Bool) {
        self.name = name
        self.date = date
        self.isOffDay = isOffDay
    }
}

/// A run of days off under one name.
public struct HolidayBreak: Equatable, Sendable {
    public var name: String
    public var start: Date
    public var length: Int
    /// The make-up workdays that belong to it.
    public var workdays: [Date]
    /// True when this year's schedule is not out yet and only the festival
    /// day itself is known.
    public var estimated: Bool
}

public enum HolidaySchedule {
    /// The State Council's notice of 2025-11 (国办发明电〔2025〕7号), as
    /// published at gov.cn and mirrored by NateScarlet/holiday-cn.
    public static let bundled: [Int: [HolidayDay]] = [
        2026: parseCompact("""
        元旦 2026-01-01 1 2026-01-02 1 2026-01-03 1 2026-01-04 0
        春节 2026-02-14 0 2026-02-15 1 2026-02-16 1 2026-02-17 1 2026-02-18 1 2026-02-19 1 2026-02-20 1 2026-02-21 1 2026-02-22 1 2026-02-23 1 2026-02-28 0
        清明节 2026-04-04 1 2026-04-05 1 2026-04-06 1
        劳动节 2026-05-01 1 2026-05-02 1 2026-05-03 1 2026-05-04 1 2026-05-05 1 2026-05-09 0
        端午节 2026-06-19 1 2026-06-20 1 2026-06-21 1
        中秋节 2026-09-25 1 2026-09-26 1 2026-09-27 1
        国庆节 2026-09-20 0 2026-10-01 1 2026-10-02 1 2026-10-03 1 2026-10-04 1 2026-10-05 1 2026-10-06 1 2026-10-07 1 2026-10-10 0
        """),
    ]

    /// `name date flag date flag ...`, one holiday per line.
    static func parseCompact(_ text: String) -> [HolidayDay] {
        text.split(separator: "\n").flatMap { line -> [HolidayDay] in
            let words = line.split(separator: " ").map(String.init)
            guard let name = words.first else { return [] }
            return stride(from: 1, to: words.count - 1, by: 2).map {
                HolidayDay(name: name, date: words[$0], isOffDay: words[$0 + 1] == "1")
            }
        }
    }

    /// holiday-cn's yearly file: `{"year": 2026, "days": [{"name", "date", "isOffDay"}]}`.
    /// Nil for a malformed file and for an empty one, which is what a year
    /// looks like before the notice is out.
    public static func parse(_ data: Data) -> [HolidayDay]? {
        struct File: Decodable { var days: [HolidayDay] }
        guard let file = try? JSONDecoder().decode(File.self, from: data) else { return nil }
        let days = file.days.filter { ChineseCalendar.day($0.date) != nil && !$0.name.isEmpty }
        return days.isEmpty ? nil : days
    }

    /// The festival days alone, for a year with no schedule yet.
    public static func estimated(year: Int) -> [HolidayBreak] {
        let calendar = ChineseCalendar.gregorian
        func day(_ month: Int, _ day: Int) -> Date? {
            calendar.date(from: DateComponents(year: year, month: month, day: day))
        }
        let qingming = ChineseCalendar.solarTerms(year: year).first { $0.name == "清明" }?.day
        let candidates: [(String, Date?)] = [
            ("元旦", day(1, 1)),
            ("春节", ChineseCalendar.newYearsEve(lunarNewYearIn: year)),
            ("清明节", qingming),
            ("劳动节", day(5, 1)),
            ("端午节", ChineseCalendar.gregorianDay(lunarMonth: 5, day: 5, inGregorianYear: year)),
            ("中秋节", ChineseCalendar.gregorianDay(lunarMonth: 8, day: 15, inGregorianYear: year)),
            ("国庆节", day(10, 1)),
        ]
        return candidates.compactMap { name, date in
            date.map { HolidayBreak(name: name, start: calendar.startOfDay(for: $0), length: 1,
                                    workdays: [], estimated: true) }
        }
        .sorted { $0.start < $1.start }
    }

    /// Consecutive days off with one name become one break, and each
    /// make-up workday is attached to the break of its name nearest to it.
    public static func breaks(_ days: [HolidayDay]) -> [HolidayBreak] {
        let calendar = ChineseCalendar.gregorian
        let dated = days.compactMap { day in ChineseCalendar.day(day.date).map { (day, $0) } }
            .sorted { $0.1 < $1.1 }
        var result: [HolidayBreak] = []
        for (day, date) in dated where day.isOffDay {
            if var last = result.last, last.name == day.name,
               let end = calendar.date(byAdding: .day, value: last.length, to: last.start), end == date {
                last.length += 1
                result[result.count - 1] = last
            } else {
                result.append(HolidayBreak(name: day.name, start: date, length: 1, workdays: [], estimated: false))
            }
        }
        for (day, date) in dated where !day.isOffDay {
            let named = result.indices.filter { result[$0].name == day.name }
            let pool = named.isEmpty ? Array(result.indices) : named
            guard let nearest = pool.min(by: {
                abs(result[$0].start.timeIntervalSince(date)) < abs(result[$1].start.timeIntervalSince(date))
            }) else { continue }
            result[nearest].workdays.append(date)
        }
        return result
    }

    /// Every break of the years asked for: official where known, estimated
    /// where not.
    public static func breaks(years: ClosedRange<Int>, known: [Int: [HolidayDay]]) -> [HolidayBreak] {
        years.flatMap { year -> [HolidayBreak] in
            if let days = known[year], !days.isEmpty { return breaks(days) }
            return estimated(year: year)
        }
        .sorted { $0.start < $1.start }
    }

    /// The break running today or the next to start.
    public static func next(after date: Date, in breaks: [HolidayBreak]) -> HolidayBreak? {
        let calendar = ChineseCalendar.gregorian
        let today = calendar.startOfDay(for: date)
        return breaks.first { item in
            guard let end = calendar.date(byAdding: .day, value: item.length, to: item.start) else { return false }
            return end > today
        }
    }

    public enum DayKind: Equatable, Sendable {
        case holiday(String)
        case makeupWorkday(String)
        case weekend
        case workday
    }

    public static func kind(of date: Date, known: [Int: [HolidayDay]]) -> DayKind {
        let calendar = ChineseCalendar.gregorian
        let key = ChineseCalendar.key(date)
        let year = calendar.component(.year, from: date)
        if let entry = known[year]?.first(where: { $0.date == key }) {
            return entry.isOffDay ? .holiday(entry.name) : .makeupWorkday(entry.name)
        }
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 || weekday == 7 ? .weekend : .workday
    }

    /// The one line worth interrupting for: a worked weekend tomorrow or
    /// today, or a break starting tomorrow. Nil on an ordinary day.
    public static func alert(now: Date, known: [Int: [HolidayDay]]) -> String? {
        let calendar = ChineseCalendar.gregorian
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else { return nil }
        let today = kind(of: now, known: known)
        let next = kind(of: tomorrow, known: known)
        if case .makeupWorkday = today { return "今天调休上班" }
        if case .makeupWorkday = next { return "明天调休，要上班" }
        if case .holiday(let name) = next {
            if case .holiday = today { return nil }
            return "明天开始放\(shortName(name))假"
        }
        if case .holiday = today, case .workday = next { return "假期最后一天" }
        return nil
    }

    /// 国庆节 -> 国庆, 中秋节 -> 中秋, 元旦 stays.
    public static func shortName(_ name: String) -> String {
        let first = name.split(separator: "、").first.map(String.init) ?? name
        return first.hasSuffix("节") && first.count > 2 ? String(first.dropLast()) : first
    }

    /// 距元旦还有 80 天, 国庆假期第 3 天, 今天是元旦.
    public static func countdown(_ item: HolidayBreak, now: Date) -> String {
        let days = ChineseCalendar.days(from: now, to: item.start)
        let name = shortName(item.name)
        if days > 0 { return "距\(name)还有 \(days) 天" }
        if item.length <= 1 { return "今天是\(name)" }
        return "\(name)假期第 \(1 - days) 天"
    }

    /// 10月1日起 放 8 天, with 调休 dates.
    public static func describe(_ item: HolidayBreak) -> String {
        let calendar = ChineseCalendar.gregorian
        let month = calendar.component(.month, from: item.start)
        let day = calendar.component(.day, from: item.start)
        if item.estimated { return "\(month)月\(day)日 · 放假安排未公布" }
        var text = item.length > 1 ? "\(month)月\(day)日起 放 \(item.length) 天" : "\(month)月\(day)日 放 1 天"
        if !item.workdays.isEmpty {
            let dates = item.workdays.sorted().map {
                "\(calendar.component(.month, from: $0))月\(calendar.component(.day, from: $0))日"
            }
            text += " · \(dates.joined(separator: "、"))上班"
        }
        return text
    }
}
