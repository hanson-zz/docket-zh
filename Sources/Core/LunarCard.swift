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

    public static func headline(now: Date, known: [Int: [HolidayDay]], breaks: [HolidayBreak],
                                leadDays: Int, showTerm: Bool, workAlert: Bool) -> Headline {
        if workAlert, let work = nextMakeupWorkday(now: now, known: known, within: leadDays) {
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
}
