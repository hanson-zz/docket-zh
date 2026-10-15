import Foundation

/// 徽章的分类：面板按这个顺序分组展示。
public enum PerfectBadgeCategory: String, CaseIterable, Sendable, Hashable, Identifiable {
    /// 初级：条件公开，未解锁时显示条件和进度。
    case basic
    /// 隐藏：未解锁时只显示问号和一句提示，不透露名称和条件。
    case hidden
    /// 节日限定：只有在日期窗口里才能解锁，窗口可以按公历或农历写。
    case festival

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .basic: "初级"
        case .hidden: "隐藏"
        case .festival: "节日限定"
        }
    }
}

/// 节日徽章能解锁的日期窗口：起止都按所选历法的“月、日”写，包含首尾两天。
///
/// 农历用 `Calendar(identifier: .chinese)`，月份是农历月（1 是正月），
/// `leapMonth` 为真时只认闰月，为假时只认非闰月。起点晚于终点表示跨年，
/// 比如腊月廿三到正月十五。`leadDays` 把起点前的几天也算进来：春节写成
/// 正月初一到初七再往前多算一天，这样除夕不管是腊月廿九还是三十都在里面。
/// 节气（清明、冬至）用 `.solarTerm`，按 `ChineseCalendar` 算出的北京时间
/// 那一天来认。
public struct FestivalWindow: Equatable, Hashable, Sendable {
    public enum Kind: String, Sendable, Hashable {
        case gregorian
        case chinese
        case solarTerm
    }

    public var kind: Kind
    public var start: MonthDay
    public var end: MonthDay
    public var leapMonth: Bool
    /// 起点之前也算进窗口的天数。
    public var leadDays: Int
    /// `.solarTerm` 的节气名，比如“清明”。
    public var term: String?

    public struct MonthDay: Equatable, Hashable, Sendable, Comparable {
        public var month: Int
        public var day: Int

        public init(_ month: Int, _ day: Int) {
            self.month = month
            self.day = day
        }

        public static func < (lhs: MonthDay, rhs: MonthDay) -> Bool {
            (lhs.month, lhs.day) < (rhs.month, rhs.day)
        }
    }

    public init(_ kind: Kind, from start: MonthDay, to end: MonthDay, leapMonth: Bool = false, leadDays: Int = 0) {
        self.kind = kind
        self.start = start
        self.end = end
        self.leapMonth = leapMonth
        self.leadDays = max(0, leadDays)
        self.term = nil
    }

    /// 只有一天的窗口。
    public init(_ kind: Kind, on day: MonthDay) {
        self.init(kind, from: day, to: day)
    }

    /// 节气当天，比如 `FestivalWindow(solarTerm: "清明")`。
    public init(solarTerm name: String) {
        self.kind = .solarTerm
        self.start = MonthDay(0, 0)
        self.end = MonthDay(0, 0)
        self.leapMonth = false
        self.leadDays = 0
        self.term = name
    }

    /// 窗口用的历法，时区跟着本地日历走。
    public func calendar(base: Calendar = PerfectDay.calendar) -> Calendar {
        var calendar = Calendar(identifier: kind == .chinese ? .chinese : .gregorian)
        calendar.timeZone = base.timeZone
        calendar.locale = Locale(identifier: "zh_CN")
        return calendar
    }

    /// `date` 在不在窗口里。
    public func contains(_ date: Date, base: Calendar = PerfectDay.calendar) -> Bool {
        if kind == .solarTerm {
            guard let term else { return false }
            let c = base.dateComponents([.year, .month, .day], from: date)
            guard let year = c.year, let day = Self.termDay(term, year: year) else { return false }
            return day.month == c.month && day.day == c.day
        }
        let lunarOrSolar = self.calendar(base: base)
        if inRange(date, calendar: lunarOrSolar) { return true }
        guard leadDays > 0 else { return false }
        for ahead in 1...leadDays {
            guard let later = lunarOrSolar.date(byAdding: .day, value: ahead, to: date) else { continue }
            if monthDay(later, calendar: lunarOrSolar) == start { return true }
        }
        return false
    }

    private func monthDay(_ date: Date, calendar: Calendar) -> MonthDay? {
        let c = calendar.dateComponents([.month, .day, .isLeapMonth], from: date)
        guard let month = c.month, let day = c.day else { return nil }
        if kind == .chinese, (c.isLeapMonth ?? false) != leapMonth { return nil }
        return MonthDay(month, day)
    }

    private func inRange(_ date: Date, calendar: Calendar) -> Bool {
        guard let today = monthDay(date, calendar: calendar) else { return false }
        if start <= end { return start <= today && today <= end }
        return today >= start || today <= end
    }

    /// 某个节气在公历某年落在哪一天（北京时间）。
    static func termDay(_ name: String, year: Int) -> (month: Int, day: Int)? {
        guard let found = ChineseCalendar.solarTerms(year: year).first(where: { $0.name == name }) else { return nil }
        let c = ChineseCalendar.gregorian.dateComponents([.month, .day], from: found.day)
        guard let month = c.month, let day = c.day else { return nil }
        return (month, day)
    }

    /// 这个窗口在公历 `year` 年里的第一天和最后一天（都是当天零点）。
    /// 农历窗口取那一年正月开始的农历年；起点晚于终点时终点落在下一年。
    public func occurrence(inYear year: Int, base: Calendar = PerfectDay.calendar) -> (start: Date, end: Date)? {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = base.timeZone
        switch kind {
        case .solarTerm:
            guard let term, let day = Self.termDay(term, year: year),
                  let date = gregorian.date(from: DateComponents(year: year, month: day.month, day: day.day))
            else { return nil }
            return (date, date)
        case .gregorian:
            guard var first = gregorian.date(from: DateComponents(year: year, month: start.month, day: start.day)),
                  let last = gregorian.date(from: DateComponents(year: start <= end ? year : year + 1,
                                                                 month: end.month, day: end.day))
            else { return nil }
            if leadDays > 0, let earlier = gregorian.date(byAdding: .day, value: -leadDays, to: first) { first = earlier }
            return (first, last)
        case .chinese:
            let lunar = calendar(base: base)
            // 农历新年在 1 月 21 日到 2 月 20 日之间，3 月中旬一定已经进了这一年开始的农历年。
            guard let anchor = gregorian.date(from: DateComponents(year: year, month: 3, day: 15)) else { return nil }
            let era = lunar.dateComponents([.era, .year], from: anchor)
            func day(_ md: MonthDay, nextYear: Bool) -> Date? {
                var parts = DateComponents()
                parts.era = era.era
                parts.year = (era.year ?? 0) + (nextYear ? 1 : 0)
                parts.month = md.month
                parts.day = md.day
                parts.isLeapMonth = leapMonth
                guard let found = lunar.date(from: parts) else { return nil }
                let check = lunar.dateComponents([.month, .day, .isLeapMonth], from: found)
                guard check.month == md.month, check.day == md.day,
                      (check.isLeapMonth ?? false) == leapMonth else { return nil }
                return gregorian.startOfDay(for: found)
            }
            guard var first = day(start, nextYear: false), let last = day(end, nextYear: start > end) else { return nil }
            if leadDays > 0, let earlier = gregorian.date(byAdding: .day, value: -leadDays, to: first) { first = earlier }
            return (first, last)
        }
    }

    /// “农历正月初一至正月十五”“公历12月24日至12月26日”“农历除夕至正月初七”“清明当天”。
    public var text: String {
        switch kind {
        case .solarTerm:
            return "\(term ?? "")当天"
        case .gregorian:
            if start == end, leadDays == 0 { return "公历\(start.month)月\(start.day)日" }
            return "公历\(start.month)月\(start.day)日至\(end.month)月\(end.day)日"
        case .chinese:
            let leap = leapMonth ? "闰" : ""
            let from = (leadDays == 1 && start == MonthDay(1, 1) && !leapMonth)
                ? "除夕" : "\(leap)\(Self.lunarMonth(start.month))\(Self.lunarDay(start.day))"
            if start == end, leadDays == 0 { return "农历\(from)" }
            return "农历\(from)至\(leap)\(Self.lunarMonth(end.month))\(Self.lunarDay(end.day))"
        }
    }

    static func lunarMonth(_ month: Int) -> String {
        let names = ["正月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "冬月", "腊月"]
        return names.indices.contains(month - 1) ? names[month - 1] : "\(month)月"
    }

    static func lunarDay(_ day: Int) -> String {
        let digits = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]
        guard (1...30).contains(day) else { return "\(day)日" }
        switch day {
        case 10: return "初十"
        case 20: return "二十"
        case 30: return "三十"
        default:
            let prefix = ["初", "十", "廿"][(day - 1) / 10]
            return prefix + digits[(day - 1) % 10]
        }
    }
}

/// 小熊猫的竹篮的徽章：码头的木牌，按已结算的日子、专注总时长和喝水杯数算出来。
///
/// Earned once and kept: `PerfectDayArchive.earned` remembers the day each
/// was first earned, and `earning` only ever adds to it, so trimming old days
/// or deleting a widget never takes a badge back. The raw values are the ids
/// written into perfect-day.json, so they never change even though the first
/// ten cases were renamed.
public enum PerfectBadge: String, CaseIterable, Sendable, Hashable, Identifiable {
    // 初级
    case firstFullBasket = "firstPerfect"
    case leafStreak3 = "sunStreak3"
    case leafStreak7 = "sunStreak7"
    case leafStreak30 = "sunStreak30"
    case goldMonth10 = "perfectMonth10"
    case leaves50 = "suns50"
    case water7
    case habit7
    case focus10h
    case focus100h
    // 隐藏
    case nightOwl
    case earlyWater
    case comeback
    case goldWeek
    case fullMonth
    case cups1000
    case focus200h
    case leapDay
    // 节日限定
    case festNewYear
    case festSpring
    case festLantern
    case festArbor
    case festWaterDay
    case festQingming
    case festDragonBoat
    case festQixi
    case festMidAutumn
    case festNational
    case festDoubleNinth
    case festWinterSolstice

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .firstFullBasket: "第一只满篮"
        case .leafStreak3: "三日靠岸"
        case .leafStreak7: "七日航程"
        case .leafStreak30: "码头常客"
        case .goldMonth10: "金叶之月"
        case .leaves50: "竹林小仓"
        case .water7: "潮水七日"
        case .habit7: "七日打卡"
        case .focus10h: "静心 10 小时"
        case .focus100h: "静心 100 小时"
        case .nightOwl: "夜猫子"
        case .earlyWater: "早起竹笋"
        case .comeback: "失而复得"
        case .goldWeek: "金色一周"
        case .fullMonth: "整月满篮"
        case .cups1000: "千杯不醉"
        case .focus200h: "两百小时"
        case .leapDay: "闰日竹叶"
        case .festNewYear: "元旦"
        case .festSpring: "春节"
        case .festLantern: "元宵"
        case .festArbor: "植树节"
        case .festWaterDay: "世界水日"
        case .festQingming: "清明"
        case .festDragonBoat: "端午"
        case .festQixi: "七夕"
        case .festMidAutumn: "中秋"
        case .festNational: "国庆"
        case .festDoubleNinth: "重阳"
        case .festWinterSolstice: "冬至"
        }
    }

    /// What it takes, shown under a locked badge (a hidden one only once unlocked).
    public var condition: String {
        switch self {
        case .firstFullBasket: "得到第一个\(PerfectDayTier.gold.title)"
        case .leafStreak3: "连续 3 天收到竹叶"
        case .leafStreak7: "连续 7 天收到竹叶"
        case .leafStreak30: "连续 30 天收到竹叶"
        case .goldMonth10: "一个月内 10 个\(PerfectDayTier.gold.title)"
        case .leaves50: "累计收到 50 片竹叶"
        case .water7: "喝水连续 7 天达标"
        case .habit7: "习惯连续 7 天全部完成"
        case .focus10h: "专注累计 10 小时"
        case .focus100h: "专注累计 100 小时"
        case .nightOwl: "晚上 23 点以后完成一轮专注"
        case .earlyWater: "早上 7 点前喝下当天第一杯水"
        case .comeback: "断了 3 天以上，又回来收到竹叶"
        case .goldWeek: "连续 7 天都是\(PerfectDayTier.gold.leafName)"
        case .fullMonth: "一个自然月每天都收到竹叶"
        case .cups1000: "累计喝水 1000 杯"
        case .focus200h: "专注累计 200 小时"
        case .leapDay: "2 月 29 日收到竹叶"
        case .festWaterDay: "当天喝水达标"
        case .festDragonBoat: "当天收到竹叶，包成粽叶"
        case .festNewYear, .festSpring, .festLantern, .festArbor, .festQingming, .festQixi,
             .festMidAutumn, .festDoubleNinth, .festWinterSolstice:
            "当天收到任意竹叶"
        case .festNational: "期间任意一天收到竹叶"
        }
    }

    public var symbol: String {
        switch self {
        case .firstFullBasket: "basket.fill"
        case .leafStreak3: "ferry.fill"
        case .leafStreak7: "sailboat.fill"
        case .leafStreak30: "pawprint.fill"
        case .goldMonth10: "leaf.fill"
        case .leaves50: "tree.fill"
        case .water7: "water.waves"
        case .habit7: "checkmark.seal.fill"
        case .focus10h: "hourglass"
        case .focus100h: "moon.stars.fill"
        case .nightOwl: "moon.zzz.fill"
        case .earlyWater: "sunrise.fill"
        case .comeback: "arrow.uturn.backward"
        case .goldWeek: "sparkles"
        case .fullMonth: "calendar.badge.checkmark"
        case .cups1000: "drop.circle.fill"
        case .focus200h: "figure.mind.and.body"
        case .leapDay: "29.circle.fill"
        case .festNewYear: "party.popper.fill"
        case .festSpring: "fireworks"
        case .festLantern: "lamp.table.fill"
        case .festArbor: "camera.macro"
        case .festWaterDay: "globe.asia.australia.fill"
        case .festQingming: "cloud.drizzle.fill"
        case .festDragonBoat: "triangle.fill"
        case .festQixi: "bird.fill"
        case .festMidAutumn: "moon.fill"
        case .festNational: "star.fill"
        case .festDoubleNinth: "mountain.2.fill"
        case .festWinterSolstice: "snowflake"
        }
    }

    /// The tag's two gradient stops, as hex: bamboo greens, harbour blues
    /// and the red panda's russet, festival reds and golds.
    public var hexes: (light: String, deep: String) {
        switch self {
        case .firstFullBasket: ("#F6D27A", "#B9822A")
        case .leafStreak3: ("#9FD8C8", "#2F8F7A")
        case .leafStreak7: ("#8FC6F0", "#2D6FB0")
        case .leafStreak30: ("#F2A57A", "#C0502A")
        case .goldMonth10: ("#FFE27A", "#D99A12")
        case .leaves50: ("#A8E08F", "#3E8E3A")
        case .water7: ("#8FD3FF", "#2B7FE0")
        case .habit7: ("#C6E58A", "#6B9A22")
        case .focus10h: ("#D9C3A0", "#8A6338")
        case .focus100h: ("#B9B3E8", "#4B4596")
        case .nightOwl: ("#7F8BD9", "#262E6B")
        case .earlyWater: ("#CDEB9A", "#5E9A2E")
        case .comeback: ("#F6C08E", "#B4612E")
        case .goldWeek: ("#FFF0A6", "#C98A0C")
        case .fullMonth: ("#9EDDB0", "#2E7D4F")
        case .cups1000: ("#A6E3FF", "#1F6FC4")
        case .focus200h: ("#D4B8F0", "#6A3FA0")
        case .leapDay: ("#F7B6CF", "#B23F73")
        case .festNewYear: ("#8E8CE8", "#2C2A7A")
        case .festSpring: ("#FF8A7A", "#B81E1E")
        case .festLantern: ("#FFB38A", "#C8442A")
        case .festArbor: ("#B8E39A", "#4E8A2E")
        case .festWaterDay: ("#9AD8FF", "#2A78C8")
        case .festQingming: ("#C9E6B4", "#5C8E4A")
        case .festDragonBoat: ("#A9D98C", "#3F7A2A")
        case .festQixi: ("#C5B8F2", "#4E3C9E")
        case .festMidAutumn: ("#FFE39A", "#2E3A7A")
        case .festNational: ("#FF8C7A", "#C41E1E")
        case .festDoubleNinth: ("#FFD36E", "#B87A0A")
        case .festWinterSolstice: ("#E2EEFA", "#7C97B8")
        }
    }

    public var category: PerfectBadgeCategory {
        switch self {
        case .firstFullBasket, .leafStreak3, .leafStreak7, .leafStreak30, .goldMonth10, .leaves50,
             .water7, .habit7, .focus10h, .focus100h:
            .basic
        case .nightOwl, .earlyWater, .comeback, .goldWeek, .fullMonth, .cups1000, .focus200h, .leapDay:
            .hidden
        case .festNewYear, .festSpring, .festLantern, .festArbor, .festWaterDay, .festQingming,
             .festDragonBoat, .festQixi, .festMidAutumn, .festNational, .festDoubleNinth, .festWinterSolstice:
            .festival
        }
    }

    /// 隐藏徽章未解锁时显示的一句提示。其他分类没有。
    public var hint: String? {
        switch self {
        case .nightOwl: "月亮出来以后"
        case .earlyWater: "天亮前的第一口"
        case .comeback: "回来就好"
        case .goldWeek: "一整周都闪闪发光"
        case .fullMonth: "一天都不落下"
        case .cups1000: "喝了好多好多水"
        case .focus200h: "坐得住的小熊猫"
        case .leapDay: "四年一遇"
        default: nil
        }
    }

    /// 节日徽章能解锁的日期窗口。其他分类没有，任何一天都能解锁。
    public var festivalWindow: FestivalWindow? {
        switch self {
        case .festNewYear: FestivalWindow(.gregorian, on: .init(1, 1))
        case .festSpring: FestivalWindow(.chinese, from: .init(1, 1), to: .init(1, 7), leadDays: 1)
        case .festLantern: FestivalWindow(.chinese, on: .init(1, 15))
        case .festArbor: FestivalWindow(.gregorian, on: .init(3, 12))
        case .festWaterDay: FestivalWindow(.gregorian, on: .init(3, 22))
        case .festQingming: FestivalWindow(solarTerm: "清明")
        case .festDragonBoat: FestivalWindow(.chinese, on: .init(5, 5))
        case .festQixi: FestivalWindow(.chinese, on: .init(7, 7))
        case .festMidAutumn: FestivalWindow(.chinese, on: .init(8, 15))
        case .festNational: FestivalWindow(.gregorian, from: .init(10, 1), to: .init(10, 7))
        case .festDoubleNinth: FestivalWindow(.chinese, on: .init(9, 9))
        case .festWinterSolstice: FestivalWindow(solarTerm: "冬至")
        default: nil
        }
    }

    /// 节日那天要满足什么：世界水日要喝水达标，其他节日有竹叶就行。
    public func festivalQualifies(_ record: PerfectDayRecord) -> Bool {
        switch self {
        case .festWaterDay: record.water == .met
        default: record.tier != nil
        }
    }

    /// The number to reach.
    public var target: Int {
        switch self {
        case .firstFullBasket: 1
        case .leafStreak3: 3
        case .leafStreak7: 7
        case .leafStreak30: 30
        case .goldMonth10: 10
        case .leaves50: 50
        case .water7: 7
        case .habit7: 7
        case .focus10h: 10 * 60
        case .focus100h: 100 * 60
        case .goldWeek: 7
        case .cups1000: 1000
        case .focus200h: 200 * 60
        case .nightOwl, .earlyWater, .comeback, .fullMonth, .leapDay: 1
        case .festNewYear, .festSpring, .festLantern, .festArbor, .festWaterDay, .festQingming,
             .festDragonBoat, .festQixi, .festMidAutumn, .festNational, .festDoubleNinth, .festWinterSolstice:
            1
        }
    }
}

/// 徽章需要的、竹篮记录之外的数字。都是只增不减的累计或“发生过没有”。
public struct PerfectBadgeInput: Equatable, Sendable {
    /// 专注累计分钟（`FocusLog.lifetimeMinutes`）。
    public var focusMinutes: Int
    /// 喝水累计杯数（`PerfectDayArchive.cupCount`）。
    public var waterCups: Int
    /// 有没有在深夜完成过一轮专注（`FocusLog.isLateNight`）。
    public var lateFocus: Bool
    /// 有没有哪天第一杯水在清早（`PerfectBadges.hasEarlyFirstDrink`）。
    public var earlyDrink: Bool

    public init(focusMinutes: Int = 0, waterCups: Int = 0, lateFocus: Bool = false, earlyDrink: Bool = false) {
        self.focusMinutes = focusMinutes
        self.waterCups = waterCups
        self.lateFocus = lateFocus
        self.earlyDrink = earlyDrink
    }
}

/// 节日徽章今年处在哪一步。
public enum FestivalPhase: String, Sendable, Hashable {
    /// 今年已经收下。
    case earned
    /// 今天就在窗口里，还没收下。
    case open
    /// 今年的窗口还没到。
    case upcoming
    /// 今年的窗口已经过了，没收下：明年再来。
    case missed
}

/// One badge with how far along it is.
public struct PerfectBadgeStatus: Equatable, Hashable, Sendable, Identifiable {
    public var badge: PerfectBadge
    /// Best so far, in the badge's own unit (days, leaves, minutes, cups), capped at the target.
    public var current: Int
    /// 解锁过（节日徽章是哪一年收下过都算）。
    public var unlocked: Bool
    /// When it was first earned, `yyyyMMdd`, if it was.
    public var earnedOn: String?
    /// 节日徽章收下的年份，从早到晚。
    public var years: [Int] = []
    /// 节日徽章今年的状态；不知道今天（或不是节日徽章）时为 nil。
    public var phase: FestivalPhase?

    public var id: String { badge.rawValue }

    /// 未解锁的隐藏徽章：名称、条件和图形都不露出来。
    public var isConcealed: Bool { PerfectBadges.isConcealed(category: badge.category, unlocked: unlocked) }

    /// 木牌亮不亮：节日徽章只在今年收下后亮，其他徽章解锁后一直亮。
    public var isLit: Bool {
        if badge.category == .festival, let phase { return phase == .earned }
        return unlocked
    }

    /// 面板上显示的名称。
    public var shownTitle: String { isConcealed ? PerfectBadges.concealedTitle : badge.title }

    /// 面板上名称下面的一行：隐藏徽章只给提示，节日徽章带上日期窗口。
    public var shownCondition: String {
        if isConcealed { return "（\(badge.hint ?? PerfectBadges.concealedHint)）" }
        if let window = badge.festivalWindow { return "\(badge.condition)（\(window.text)）" }
        return badge.condition
    }

    /// 节日徽章的一行：今年收下了、明年再来、今天就能收、或者窗口日期；
    /// 收下过的年份跟在后面。
    public var festivalLine: String? {
        guard badge.category == .festival else { return nil }
        let collected = years.isEmpty ? nil : "已收 " + years.map(String.init).joined(separator: "、")
        let head: String
        switch phase {
        case .earned: head = "今年已收下"
        case .missed: head = PerfectBadges.missedText
        case .open: head = "今天收到竹叶就能拿到"
        case .upcoming, .none: head = badge.festivalWindow?.text ?? ""
        }
        return [head, collected].compactMap { $0 }.joined(separator: "\n")
    }

    /// "3/7", or "4/10 小时" for the focus badges.
    public var progressText: String {
        switch badge {
        case .focus10h, .focus100h, .focus200h: "\(current / 60)/\(badge.target / 60) 小时"
        case .cups1000: "\(current)/\(badge.target) 杯"
        default: "\(current)/\(badge.target)"
        }
    }
}

/// 面板上的一组徽章。
public struct PerfectBadgeGroup: Equatable, Sendable, Identifiable {
    public var category: PerfectBadgeCategory
    public var statuses: [PerfectBadgeStatus]

    public var id: String { category.rawValue }
}

public enum PerfectBadges {
    /// 错过今年节日窗口时的文字。
    public static let missedText = "明年再来"
    /// 断了几天以上再回来算“失而复得”。
    public static let comebackGapDays = 3
    /// 清早的第一杯水：4:00 到 6:59（4 点前算熬夜，不算早起）。
    public static let earlyDrinkMinutes = (4 * 60)..<(7 * 60)
    /// 节日徽章只看最近这么多天的记录：更早的日子在当时已经看过了。
    public static let festivalLookbackDays = PerfectDay.backfillDays + 2

    // MARK: Measuring

    /// The best figure each badge has reached in `records` and `input`.
    /// 节日徽章不在这里算（见 `earning` 和 `festivalYears`），总是 0。
    public static func measure(_ badge: PerfectBadge, records: [PerfectDayRecord], input: PerfectBadgeInput,
                               calendar: Calendar = PerfectDay.calendar) -> Int {
        switch badge {
        case .firstFullBasket:
            return records.filter { $0.tier == .gold }.count
        case .leafStreak3, .leafStreak7, .leafStreak30:
            return PerfectDay.longestRun(Set(records.filter { $0.tier != nil }.map(\.key)), calendar: calendar)
        case .goldMonth10:
            var byMonth: [Substring: Int] = [:]
            for record in records where record.tier == .gold { byMonth[record.key.prefix(6), default: 0] += 1 }
            return byMonth.values.max() ?? 0
        case .leaves50:
            return records.filter { $0.tier != nil }.count
        case .water7:
            return PerfectDay.longestRun(Set(records.filter { $0.water == .met }.map(\.key)), calendar: calendar)
        case .habit7:
            return PerfectDay.longestRun(Set(records.filter { $0.habit == .met }.map(\.key)), calendar: calendar)
        case .focus10h, .focus100h, .focus200h:
            return max(0, input.focusMinutes)
        case .nightOwl:
            return input.lateFocus ? 1 : 0
        case .earlyWater:
            return input.earlyDrink ? 1 : 0
        case .comeback:
            return hasComeback(records, calendar: calendar) ? 1 : 0
        case .goldWeek:
            return PerfectDay.longestRun(Set(records.filter { $0.tier == .gold }.map(\.key)), calendar: calendar)
        case .fullMonth:
            return hasFullMonth(records, calendar: calendar) ? 1 : 0
        case .cups1000:
            return max(0, input.waterCups)
        case .leapDay:
            return records.contains { $0.tier != nil && $0.key.hasSuffix("0229") } ? 1 : 0
        case .festNewYear, .festSpring, .festLantern, .festArbor, .festWaterDay, .festQingming,
             .festDragonBoat, .festQixi, .festMidAutumn, .festNational, .festDoubleNinth, .festWinterSolstice:
            return 0
        }
    }

    /// 旧的调用方式：只有专注分钟。
    public static func measure(_ badge: PerfectBadge, records: [PerfectDayRecord], focusMinutes: Int,
                               calendar: Calendar = PerfectDay.calendar) -> Int {
        measure(badge, records: records, input: PerfectBadgeInput(focusMinutes: focusMinutes), calendar: calendar)
    }

    /// 两片竹叶之间隔了 `comebackGapDays` 天以上没有竹叶（没记录的日子也算断了）。
    /// 记录开始之前的日子不算。
    public static func hasComeback(_ records: [PerfectDayRecord], calendar: Calendar = PerfectDay.calendar) -> Bool {
        let dates = Set(records.filter { $0.tier != nil }.map(\.key))
            .compactMap { HabitTracker.date(fromKey: $0, calendar: calendar) }.sorted()
        for (previous, next) in zip(dates, dates.dropFirst()) {
            let gap = (calendar.dateComponents([.day], from: previous, to: next).day ?? 0) - 1
            if gap >= comebackGapDays { return true }
        }
        return false
    }

    /// 有没有一个自然月，从 1 号到最后一天每天都有竹叶。
    public static func hasFullMonth(_ records: [PerfectDayRecord], calendar: Calendar = PerfectDay.calendar) -> Bool {
        var byMonth: [String: Int] = [:]
        for record in records where record.tier != nil { byMonth[String(record.key.prefix(6)), default: 0] += 1 }
        for (month, count) in byMonth where count >= 28 {
            guard let first = HabitTracker.date(fromKey: month + "01", calendar: calendar),
                  let days = calendar.range(of: .day, in: .month, for: first)?.count else { continue }
            if count >= days { return true }
        }
        return false
    }

    /// 某天的第一杯水是不是在清早（`earlyDrinkMinutes`）。只看还留着每一杯的日子。
    public static func hasEarlyFirstDrink(_ days: [WaterDay]) -> Bool {
        days.contains { day in
            guard day.summary == nil, let first = day.entries.map(\.minute).min() else { return false }
            return earlyDrinkMinutes.contains(first)
        }
    }

    // MARK: Statuses

    /// Every badge, in catalogue order, with what `earned` already holds
    /// counting as unlocked whatever the records say now. With `today`,
    /// festival badges also say where this year's window stands.
    public static func statuses(records: [PerfectDayRecord], input: PerfectBadgeInput, earned: [String: String],
                                years: [String: [Int]] = [:], today: Date? = nil,
                                calendar: Calendar = PerfectDay.calendar) -> [PerfectBadgeStatus] {
        PerfectBadge.allCases.map { badge in
            let value = measure(badge, records: records, input: input, calendar: calendar)
            let kept = earned[badge.rawValue]
            // 节日徽章只认在窗口里记下的那一次：窗口外达到条件不算解锁。
            let unlocked = kept != nil || (badge.festivalWindow == nil && value >= badge.target)
            let got = (years[badge.rawValue] ?? []).sorted()
            var status = PerfectBadgeStatus(badge: badge, current: unlocked ? badge.target : min(value, badge.target),
                                            unlocked: unlocked, earnedOn: kept, years: got)
            if let today, let window = badge.festivalWindow {
                status.phase = phase(window, years: got, today: today, calendar: calendar)
            }
            return status
        }
    }

    /// 旧的调用方式：只有专注分钟。
    public static func statuses(records: [PerfectDayRecord], focusMinutes: Int, earned: [String: String],
                                calendar: Calendar = PerfectDay.calendar) -> [PerfectBadgeStatus] {
        statuses(records: records, input: PerfectBadgeInput(focusMinutes: focusMinutes), earned: earned,
                 calendar: calendar)
    }

    /// 节日徽章今年的状态。
    public static func phase(_ window: FestivalWindow, years: [Int], today: Date,
                             calendar: Calendar = PerfectDay.calendar) -> FestivalPhase {
        let year = calendar.component(.year, from: today)
        if years.contains(year) { return .earned }
        if window.contains(today, base: calendar) { return .open }
        guard let occurrence = window.occurrence(inYear: year, base: calendar) else { return .upcoming }
        return calendar.startOfDay(for: today) < occurrence.start ? .upcoming : .missed
    }

    // MARK: Earning

    /// `earned` with every badge reached by now added, dated `today`.
    /// Never removes one. 节日徽章记的是最近 `festivalLookbackDays` 天里
    /// 第一个在窗口里、满足条件的那天。
    public static func earning(_ earned: [String: String], records: [PerfectDayRecord], input: PerfectBadgeInput,
                               today: Date, calendar: Calendar = PerfectDay.calendar) -> [String: String] {
        var result = earned
        let key = HabitTracker.dayKey(today, calendar: calendar)
        let recent = recentFestivalDays(records, today: today, calendar: calendar)
        for badge in PerfectBadge.allCases where result[badge.rawValue] == nil {
            if let window = badge.festivalWindow {
                if let hit = recent.first(where: { badge.festivalQualifies($0.record)
                    && window.contains($0.date, base: calendar) }) {
                    result[badge.rawValue] = hit.record.key
                }
                continue
            }
            if measure(badge, records: records, input: input, calendar: calendar) >= badge.target {
                result[badge.rawValue] = key
            }
        }
        return result
    }

    /// 旧的调用方式：只有专注分钟。
    public static func earning(_ earned: [String: String], records: [PerfectDayRecord], focusMinutes: Int,
                               today: Date, calendar: Calendar = PerfectDay.calendar) -> [String: String] {
        earning(earned, records: records, input: PerfectBadgeInput(focusMinutes: focusMinutes), today: today,
                calendar: calendar)
    }

    /// 节日徽章收下的年份：最近 `festivalLookbackDays` 天里，每个在窗口里、
    /// 满足条件的日子把它所在的公历年份记上。只增不减，每年最多记一次。
    public static func festivalYears(_ years: [String: [Int]], records: [PerfectDayRecord], today: Date,
                                     calendar: Calendar = PerfectDay.calendar) -> [String: [Int]] {
        var result = years
        let recent = recentFestivalDays(records, today: today, calendar: calendar)
        for badge in PerfectBadge.allCases {
            guard let window = badge.festivalWindow else { continue }
            var got = Set(result[badge.rawValue] ?? [])
            for day in recent where badge.festivalQualifies(day.record) && window.contains(day.date, base: calendar) {
                got.insert(calendar.component(.year, from: day.date))
            }
            if !got.isEmpty { result[badge.rawValue] = got.sorted() }
        }
        return result
    }

    /// 最近 `festivalLookbackDays` 天（不晚于今天）有记录的日子，从早到晚，
    /// 取当天中午，免得夏令时把日子推到前一天。
    private static func recentFestivalDays(_ records: [PerfectDayRecord], today: Date,
                                           calendar: Calendar) -> [(record: PerfectDayRecord, date: Date)] {
        let todayKey = HabitTracker.dayKey(today, calendar: calendar)
        let cutoff = calendar.date(byAdding: .day, value: -festivalLookbackDays, to: calendar.startOfDay(for: today))
            .map { HabitTracker.dayKey($0, calendar: calendar) } ?? ""
        return records
            .filter { $0.key >= cutoff && $0.key <= todayKey }
            .sorted { $0.key < $1.key }
            .compactMap { record in
                guard let start = HabitTracker.date(fromKey: record.key, calendar: calendar),
                      let noon = calendar.date(byAdding: .hour, value: 12, to: start) else { return nil }
                return (record: record, date: noon)
            }
    }

    // MARK: Water cups

    /// 喝水累计杯数：每一杯（任何饮品）算一杯。
    ///
    /// 喝水记录只保留 120 天，而且 7 天前的日子只剩总量，所以杯数另外记在
    /// 竹篮存档里：`days` 是最近还在喝水记录里的日子各自几杯，更早的折进
    /// `folded`。还留着每一杯的日子按实际杯数（多个喝水小组件取最多的那个）；
    /// 只剩总量、又没数过的日子（升级前的记录）按 `WaterIntake.defaultCup`
    /// 毫升一杯估算；已经数过的日子保留原来的数。
    public static func countingCups(folded: Int, days: [String: Int], water: [WaterDay], today: Date,
                                    calendar: Calendar = PerfectDay.calendar) -> (folded: Int, days: [String: Int]) {
        var counted = days
        var best: [String: (cups: Int, exact: Bool)] = [:]
        for day in water {
            let exact = day.summary == nil
            let cups = exact ? day.entries.count : estimatedCups(millilitres: day.summary ?? 0)
            if let old = best[day.key] {
                if (exact && !old.exact) || (exact == old.exact && cups > old.cups) { best[day.key] = (cups, exact) }
            } else {
                best[day.key] = (cups, exact)
            }
        }
        let todayKey = HabitTracker.dayKey(today, calendar: calendar)
        for (key, value) in best where key <= todayKey {
            if value.exact || counted[key] == nil { counted[key] = value.cups }
        }
        var folded = max(0, folded)
        let cutoff = calendar.date(byAdding: .day, value: -(WaterIntake.keptDays + 10), to: today)
            .map { HabitTracker.dayKey($0, calendar: calendar) } ?? ""
        for (key, cups) in counted where key < cutoff {
            folded += max(0, cups)
            counted[key] = nil
        }
        return (folded, counted.filter { $0.value > 0 })
    }

    static func estimatedCups(millilitres: Int) -> Int {
        guard millilitres > 0 else { return 0 }
        return max(1, Int((Double(millilitres) / Double(WaterIntake.defaultCup)).rounded()))
    }

    // MARK: Words and groups

    /// 未解锁的隐藏徽章显示的名称和默认提示。
    public static let concealedTitle = "？？？"
    public static let concealedHint = "还没被发现的徽章"

    public static func isConcealed(category: PerfectBadgeCategory, unlocked: Bool) -> Bool {
        category == .hidden && !unlocked
    }

    /// 按分类分组，顺序是初级、隐藏、节日限定；空的分类不出现。
    public static func grouped(_ statuses: [PerfectBadgeStatus]) -> [PerfectBadgeGroup] {
        PerfectBadgeCategory.allCases.compactMap { category in
            let members = statuses.filter { $0.badge.category == category }
            return members.isEmpty ? nil : PerfectBadgeGroup(category: category, statuses: members)
        }
    }
}
