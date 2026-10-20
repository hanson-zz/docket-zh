import Foundation

/// 农历与假期卡片同一时间只说一件事，按优先级挑：
///
/// 1. 调休上班（红色）：接下来 `leadDays` 天内有要补班的周末，从提前那天起一直显示，
///    前一天晚上再发一次通知。
/// 2. 节气、传统节日当天：做大标题，下面写农历。
/// 3. 平常：离下一个法定假日还有几天，下面写从哪天起放几天。
///
/// 放假和调休的日期只来自 `HolidaySchedule`（内置的国务院通知和之后联网取到的年份），
/// 这里不写任何日期。
public enum LunarCard {
    /// 提醒提前几天：可选 3、7、14，默认 7。
    public static let leadKey = "workAlertLead"
    public static let leadChoices = [3, 7, 14]
    public static let defaultLead = 7

    public static func leadDays(_ config: WidgetConfig) -> Int {
        let raw = Int(config.string(leadKey, default: "\(defaultLead)")) ?? defaultLead
        return leadChoices.contains(raw) ? raw : defaultLead
    }

    /// 前一天晚上几点再提醒一次。
    public static let eveHour = 20

    public enum Headline: Equatable, Sendable {
        /// 要上班的那天，离今天几天（0 是今天），属于哪个假期。
        case makeupWorkday(date: Date, days: Int, holiday: String)
        /// 农历生日、纪念日当天：名字、种类、农历日期，卡片上小熊猫送祝福。
        case event(name: String, kind: LunarEvent.Kind, lunar: String)
        /// 节气或节日当天。
        case special(name: String)
        /// 下一个法定假日。
        case countdown(HolidayBreak)
        case none

        public var isAlert: Bool {
            if case .makeupWorkday = self { return true }
            return false
        }
    }

    /// 接下来要补班的那天（今天也算），在 `leadDays` 天以内才算。
    public static func nextMakeupWorkday(now: Date, known: [Int: [HolidayDay]],
                                         within leadDays: Int) -> (date: Date, days: Int, holiday: String)? {
        let today = ChineseCalendar.gregorian.startOfDay(for: now)
        let all = known.values.flatMap { $0 }.filter { !$0.isOffDay }
            .compactMap { day in ChineseCalendar.day(day.date).map { (date: $0, name: day.name) } }
            .filter { $0.date >= today }
            .sorted { $0.date < $1.date }
        guard let first = all.first else { return nil }
        let days = ChineseCalendar.days(from: today, to: first.date)
        guard days <= max(0, leadDays) else { return nil }
        return (first.date, days, first.name)
    }

    /// 今天调休上班 > 农历生日、纪念日当天 > 提前几天的调休提醒 > 节日 > 节气 > 下一个假期。
    public static func headline(now: Date, known: [Int: [HolidayDay]], breaks: [HolidayBreak],
                                leadDays: Int, showTerm: Bool, workAlert: Bool,
                                events: [LunarEvent] = []) -> Headline {
        let work = workAlert ? nextMakeupWorkday(now: now, known: known, within: leadDays) : nil
        if let work, work.days == 0 {
            return .makeupWorkday(date: work.date, days: work.days, holiday: work.holiday)
        }
        if let event = LunarEvents.today(events, now: now).first {
            return .event(name: event.name, kind: event.kind, lunar: event.lunarText)
        }
        if let work {
            return .makeupWorkday(date: work.date, days: work.days, holiday: work.holiday)
        }
        if let festival = ChineseCalendar.festival(on: now) { return .special(name: festival) }
        if showTerm, let term = ChineseCalendar.term(on: now) { return .special(name: term) }
        if let next = HolidaySchedule.next(after: now, in: breaks) { return .countdown(next) }
        return .none
    }

    /// 大标题：「下周六要上班」「今日霜降」「国庆还有 12 天」。
    public static func title(_ headline: Headline, now: Date) -> String {
        switch headline {
        case .makeupWorkday(let date, let days, _):
            return workTitle(date: date, days: days, now: now)
        case .event(let name, _, _):
            return tr("今天是\(name)")
        case .special(let name):
            return tr("今日\(trKey(name))")
        case .countdown(let item):
            let days = ChineseCalendar.days(from: now, to: item.start)
            let name = trKey(HolidaySchedule.shortName(item.name))
            if days > 0 { return tr("\(name)还有 \(days) 天") }
            if item.length <= 1 { return tr("今天是\(name)") }
            return tr("\(name)假期第 \(1 - days) 天")
        case .none:
            return ChineseCalendar.lunar(now).short
        }
    }

    /// 小标题：「10月10日 调休补班」「农历九月十四」「10月1日起 连放 7 天」。
    public static func caption(_ headline: Headline, now: Date) -> String {
        let calendar = ChineseCalendar.gregorian
        switch headline {
        case .makeupWorkday(let date, _, _):
            return tr("\(calendar.component(.month, from: date))月\(calendar.component(.day, from: date))日 调休补班")
        case .event(_, let kind, let lunar):
            return tr("\(lunar) · \(LunarEvents.greeting(kind))")
        case .special, .none:
            return tr("农历\(ChineseCalendar.lunar(now).short)")
        case .countdown(let item):
            let days = ChineseCalendar.days(from: now, to: item.start)
            let month = calendar.component(.month, from: item.start)
            let day = calendar.component(.day, from: item.start)
            if item.estimated { return tr("\(month)月\(day)日 · 放假安排未公布") }
            if days <= 0 {
                let left = item.length - (1 - days)
                return left > 0 ? tr("还剩 \(left) 天") : tr("明天上班")
            }
            return item.length > 1 ? tr("\(month)月\(day)日起 连放 \(item.length) 天") : tr("\(month)月\(day)日 放 1 天")
        }
    }

    /// 今天、明天、本周六、下周六，再远写「N 天后」。
    static func workTitle(date: Date, days: Int, now: Date) -> String {
        if days == 0 { return tr("今天调休上班") }
        if days == 1 { return tr("明天要上班") }
        // 周一开头，按中国的时区算，和放假数据一致。
        var week = ChineseCalendar.gregorian
        week.firstWeekday = 2
        week.minimumDaysInFirstWeek = 4
        let thisWeek = WeekAgenda.weekStart(now, calendar: week)
        let thatWeek = WeekAgenda.weekStart(date, calendar: week)
        let index = (week.component(.weekday, from: date) + 5) % 7
        let name = WeekAgenda.weekdayNames[index]
        let weeks = ChineseCalendar.days(from: thisWeek, to: thatWeek) / 7
        if weeks == 0 { return tr("本周\(name)要上班") }
        if weeks == 1 { return tr("下周\(name)要上班") }
        return tr("\(days) 天后要上班")
    }

    /// 前一天晚上的那次提醒：补班日前一天 `eveHour` 点。已经过了就是 nil。
    public static func eveReminder(now: Date, known: [Int: [HolidayDay]])
        -> (fire: Date, workday: Date, holiday: String)? {
        let calendar = ChineseCalendar.gregorian
        // 只看最近的那个补班日：前一晚的提醒最多提前两周排，够用了。
        guard let work = nextMakeupWorkday(now: now, known: known, within: 14),
              let eve = calendar.date(byAdding: .day, value: -1, to: work.date),
              let fire = calendar.date(bySettingHour: eveHour, minute: 0, second: 0, of: eve),
              fire > now else { return nil }
        return (fire, work.date, work.holiday)
    }

    // MARK: 面板：本月月历

    public enum CellMark: Equatable, Sendable {
        case off
        case work
        case none
    }

    public struct MonthCell: Equatable, Sendable {
        public var date: Date
        public var day: Int
        /// 下面那行小字：节日、节气或农历日（初一写月份）。
        public var sub: String
        /// 小字是节日或节气，要高亮。
        public var subIsSpecial: Bool
        public var mark: CellMark
        public var isToday: Bool
        public var isWeekend: Bool
    }

    /// 本月 1 日在第一行的第几格（周一为 0）。
    public static func leadingBlanks(year: Int, month: Int) -> Int {
        let calendar = ChineseCalendar.gregorian
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return 0 }
        return (calendar.component(.weekday, from: first) + 5) % 7
    }

    public static func month(year: Int, month: Int, now: Date, known: [Int: [HolidayDay]],
                             showTerm: Bool) -> [MonthCell] {
        let calendar = ChineseCalendar.gregorian
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: first) else { return [] }
        let today = calendar.startOfDay(for: now)
        let terms = showTerm ? ChineseCalendar.solarTerms(year: year) : []
        return range.compactMap { day -> MonthCell? in
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
            let kind = HolidaySchedule.kind(of: date, known: known)
            let mark: CellMark
            switch kind {
            case .holiday: mark = .off
            case .makeupWorkday: mark = .work
            default: mark = .none
            }
            let weekday = calendar.component(.weekday, from: date)
            var sub: String
            var special = true
            if let festival = ChineseCalendar.festival(on: date) {
                sub = festival
            } else if let term = terms.first(where: { $0.day == date })?.name {
                sub = term
            } else if case .holiday(let name) = kind, isFirstDay(of: name, date: date, known: known) {
                sub = HolidaySchedule.shortName(name)
            } else {
                special = false
                let lunar = ChineseCalendar.lunar(date)
                sub = lunar.day == 1 ? lunar.monthName : lunar.dayName
            }
            return MonthCell(date: date, day: day, sub: sub, subIsSpecial: special, mark: mark,
                             isToday: date == today, isWeekend: weekday == 1 || weekday == 7)
        }
    }

    /// 假期第一天，写假期名（国庆、元旦）。
    static func isFirstDay(of name: String, date: Date, known: [Int: [HolidayDay]]) -> Bool {
        let calendar = ChineseCalendar.gregorian
        guard let before = calendar.date(byAdding: .day, value: -1, to: date) else { return true }
        if case .holiday(let previous) = HolidaySchedule.kind(of: before, known: known) { return previous != name }
        return true
    }

    // MARK: 面板：接下来

    public struct Upcoming: Equatable, Sendable {
        public var date: Date
        public var title: String
        public var days: Int
        public var isHoliday: Bool
    }

    /// 接下来：下一个节气，和之后的几个假期（还在放的也算），按日期排，最多 `limit` 条。
    public static func upcoming(now: Date, breaks: [HolidayBreak], showTerm: Bool, limit: Int = 4) -> [Upcoming] {
        let today = ChineseCalendar.gregorian.startOfDay(for: now)
        var items: [Upcoming] = []
        if showTerm, let term = ChineseCalendar.nextTerm(after: today) {
            items.append(Upcoming(date: term.day, title: trKey(term.name),
                                  days: ChineseCalendar.days(from: today, to: term.day), isHoliday: false))
        }
        for item in breaks where ChineseCalendar.days(from: today, to: item.start) + item.length > 0 {
            let name = trKey(HolidaySchedule.shortName(item.name))
            let title = item.estimated ? name
                : (item.length > 1 ? tr("\(name) · 放 \(item.length) 天") : tr("\(name) · 放 1 天"))
            items.append(Upcoming(date: item.start, title: title,
                                  days: ChineseCalendar.days(from: today, to: item.start), isHoliday: true))
        }
        return Array(items.sorted { $0.date < $1.date }.prefix(max(0, limit)))
    }

    // MARK: 面板：近期节日节气

    public enum AgendaKind: Equatable, Sendable {
        case term
        /// 传统节日，带它的农历日期（十月初一）。
        case festival(lunar: String)
        /// 法定假日：放几天，安排还没公布时 `estimated`。
        case holiday(length: Int, estimated: Bool)
        /// 调休上班，属于哪个假期。
        case makeupWorkday(holiday: String)
    }

    public struct AgendaItem: Equatable, Sendable {
        public var date: Date
        public var name: String
        public var kind: AgendaKind
        /// 离今天几天，0 是今天，负数是假期已经开始。
        public var days: Int

        /// 名字后面那行灰字：节气、十月初一、放 7 天、国庆调休。
        public var kindText: String {
            switch kind {
            case .term: return tr("节气")
            case .festival(let lunar): return lunar
            case .holiday(let length, let estimated):
                if estimated { return tr("安排未公布") }
                return tr("放 \(length) 天")
            case .makeupWorkday(let holiday): return tr("\(trKey(HolidaySchedule.shortName(holiday)))调休")
            }
        }

        /// 右边的倒数：3 天、今天、放假中。
        public var countdownText: String {
            if days > 0 { return tr("\(days) 天") }
            if days == 0 { return tr("今天") }
            return tr("放假中")
        }

        public var isAlert: Bool {
            if case .makeupWorkday = kind { return true }
            return false
        }
    }

    /// 近期节日节气：节气（开关）、传统节日、法定假日（还在放的也算）、调休上班（开关），
    /// 按日期排，最多 `limit` 条。传统节日和同名的法定假日（中秋、春节、清明节气和清明节）
    /// 前后十天内只留法定假日那条，免得一件事出现两次。
    public static func agenda(now: Date, known: [Int: [HolidayDay]], breaks: [HolidayBreak],
                              showTerm: Bool, workAlert: Bool, limit: Int = 4) -> [AgendaItem] {
        let calendar = ChineseCalendar.gregorian
        let today = calendar.startOfDay(for: now)
        let year = calendar.component(.year, from: today)
        func days(_ date: Date) -> Int { ChineseCalendar.days(from: today, to: date) }

        var holidays: [AgendaItem] = []
        for item in breaks where days(item.start) + item.length > 0 {
            holidays.append(AgendaItem(date: item.start, name: item.name,
                                       kind: .holiday(length: item.length, estimated: item.estimated),
                                       days: days(item.start)))
        }
        let holidayNames = holidays.map { (HolidaySchedule.shortName($0.name), $0.date) }
        func coveredByHoliday(_ name: String, _ date: Date) -> Bool {
            let short = HolidaySchedule.shortName(name)
            return holidayNames.contains { $0.0 == short && abs(ChineseCalendar.days(from: $0.1, to: date)) <= 10 }
        }

        var others: [AgendaItem] = []
        if showTerm {
            for term in ChineseCalendar.solarTerms(year: year) + ChineseCalendar.solarTerms(year: year + 1)
            where term.day >= today && !coveredByHoliday(term.name, term.day) {
                others.append(AgendaItem(date: term.day, name: term.name, kind: .term, days: days(term.day)))
            }
        }
        var festivals: [(Date, String)] = []
        for gregorianYear in (year - 1)...(year + 1) {
            for (key, name) in ChineseCalendar.lunarFestivals {
                let parts = key.split(separator: "-").compactMap { Int($0) }
                guard parts.count == 2,
                      let date = ChineseCalendar.gregorianDay(lunarMonth: parts[0], day: parts[1],
                                                              inGregorianYear: gregorianYear) else { continue }
                festivals.append((date, name))
            }
            if let eve = ChineseCalendar.newYearsEve(lunarNewYearIn: gregorianYear + 1) {
                festivals.append((eve, "除夕"))
            }
        }
        var seen = Set<String>()
        for (date, name) in festivals where date >= today && !coveredByHoliday(name, date) {
            guard seen.insert("\(name)@\(ChineseCalendar.key(date))").inserted else { continue }
            others.append(AgendaItem(date: date, name: name,
                                     kind: .festival(lunar: ChineseCalendar.lunar(date).short), days: days(date)))
        }
        if workAlert {
            for day in known.values.flatMap({ $0 }) where !day.isOffDay {
                guard let date = ChineseCalendar.day(day.date), date >= today else { continue }
                others.append(AgendaItem(date: date, name: tr("调休上班"), kind: .makeupWorkday(holiday: day.name),
                                         days: days(date)))
            }
        }
        let all = (holidays + others).sorted { lhs, rhs in
            lhs.date != rhs.date ? lhs.date < rhs.date : order(lhs.kind) < order(rhs.kind)
        }
        return Array(all.prefix(max(0, limit)))
    }

    /// 同一天时：调休在前（要上班最要紧），再法定假日、节日、节气。
    static func order(_ kind: AgendaKind) -> Int {
        switch kind {
        case .makeupWorkday: 0
        case .holiday: 1
        case .festival: 2
        case .term: 3
        }
    }
}

/// 农历面板自己的几个小规则。
public enum LunarPanel {
    /// 宜忌开关，默认开。节气和调休补班沿用原来的 `showTerm`、`workAlert`。
    public static let almanacKey = "showAlmanac"

    /// 月历格子里第二行最多放三个字（13pt 一格约 39pt 宽）：南北小年都写「小年」，
    /// 闰月初一写「闰六」，再长的去掉「节」。
    public static func cellName(_ name: String) -> String {
        if name.hasSuffix("小年") { return "小年" }
        if name.hasPrefix("闰"), name.hasSuffix("月"), name.count == 3 { return String(name.dropLast()) }
        if name.count > 3 { return HolidaySchedule.shortName(name) }
        return name
    }
}
