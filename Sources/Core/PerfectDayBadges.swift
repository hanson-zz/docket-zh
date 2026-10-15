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
/// 比如腊月廿三到正月十五。
public struct FestivalWindow: Equatable, Hashable, Sendable {
    public enum Kind: String, Sendable, Hashable {
        case gregorian
        case chinese
    }

    public var kind: Kind
    public var start: MonthDay
    public var end: MonthDay
    public var leapMonth: Bool

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

    public init(_ kind: Kind, from start: MonthDay, to end: MonthDay, leapMonth: Bool = false) {
        self.kind = kind
        self.start = start
        self.end = end
        self.leapMonth = leapMonth
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
        let lunarOrSolar = self.calendar(base: base)
        let c = lunarOrSolar.dateComponents([.month, .day, .isLeapMonth], from: date)
        guard let month = c.month, let day = c.day else { return false }
        if kind == .chinese, (c.isLeapMonth ?? false) != leapMonth { return false }
        let today = MonthDay(month, day)
        if start <= end { return start <= today && today <= end }
        return today >= start || today <= end
    }

    /// “农历正月初一至正月十五”“公历12月24日至12月26日”。
    public var text: String {
        switch kind {
        case .gregorian:
            return "公历\(start.month)月\(start.day)日至\(end.month)月\(end.day)日"
        case .chinese:
            let leap = leapMonth ? "闰" : ""
            return "农历\(leap)\(Self.lunarMonth(start.month))\(Self.lunarDay(start.day))至\(leap)\(Self.lunarMonth(end.month))\(Self.lunarDay(end.day))"
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

/// 小熊猫的竹篮的徽章：码头的木牌，按已结算的日子和专注总时长算出来。
///
/// Earned once and kept: `PerfectDayArchive.earned` remembers the day each
/// was first earned, and `earning` only ever adds to it, so trimming old days
/// or deleting a widget never takes a badge back. The raw values are the ids
/// already written into perfect-day.json, so they never change even though
/// the cases were renamed.
public enum PerfectBadge: String, CaseIterable, Sendable, Hashable, Identifiable {
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
        }
    }

    /// What it takes, shown under a locked badge.
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
        }
    }

    /// The tag's two gradient stops, as hex: bamboo greens, harbour blues
    /// and the red panda's russet.
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
        }
    }

    /// 分类。现有十枚都是初级；隐藏和节日限定的徽章等确认后再加。
    public var category: PerfectBadgeCategory {
        switch self {
        case .firstFullBasket, .leafStreak3, .leafStreak7, .leafStreak30, .goldMonth10, .leaves50,
             .water7, .habit7, .focus10h, .focus100h:
            .basic
        }
    }

    /// 隐藏徽章未解锁时显示的一句提示。初级徽章没有。
    public var hint: String? {
        switch category {
        case .hidden: "继续收集竹叶，也许会遇到惊喜"
        case .basic, .festival: nil
        }
    }

    /// 节日徽章能解锁的日期窗口。其他分类没有，任何一天都能解锁。
    public var festivalWindow: FestivalWindow? {
        switch self {
        case .firstFullBasket, .leafStreak3, .leafStreak7, .leafStreak30, .goldMonth10, .leaves50,
             .water7, .habit7, .focus10h, .focus100h:
            nil
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
        }
    }
}

/// One badge with how far along it is.
public struct PerfectBadgeStatus: Equatable, Hashable, Sendable, Identifiable {
    public var badge: PerfectBadge
    /// Best so far, in the badge's own unit (days, leaves, minutes), capped at the target.
    public var current: Int
    public var unlocked: Bool
    /// When it was earned, `yyyyMMdd`, if it was.
    public var earnedOn: String?

    public var id: String { badge.rawValue }

    /// 未解锁的隐藏徽章：名称、条件和图形都不露出来。
    public var isConcealed: Bool { PerfectBadges.isConcealed(category: badge.category, unlocked: unlocked) }

    /// 面板上显示的名称。
    public var shownTitle: String { isConcealed ? PerfectBadges.concealedTitle : badge.title }

    /// 面板上名称下面的一行：隐藏徽章只给提示，节日徽章带上日期窗口。
    public var shownCondition: String {
        if isConcealed { return badge.hint ?? PerfectBadges.concealedHint }
        if let window = badge.festivalWindow { return "\(badge.condition)（\(window.text)）" }
        return badge.condition
    }

    /// "3/7", or "4/10 小时" for the focus badges.
    public var progressText: String {
        switch badge {
        case .focus10h, .focus100h: "\(current / 60)/\(badge.target / 60) 小时"
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
    /// The best figure each badge has reached in `records` and the focus total.
    public static func measure(_ badge: PerfectBadge, records: [PerfectDayRecord], focusMinutes: Int,
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
        case .focus10h, .focus100h:
            return max(0, focusMinutes)
        }
    }

    /// Every badge, in catalogue order, with what `earned` already holds
    /// counting as unlocked whatever the records say now.
    public static func statuses(records: [PerfectDayRecord], focusMinutes: Int, earned: [String: String],
                                calendar: Calendar = PerfectDay.calendar) -> [PerfectBadgeStatus] {
        PerfectBadge.allCases.map { badge in
            let value = measure(badge, records: records, focusMinutes: focusMinutes, calendar: calendar)
            let kept = earned[badge.rawValue]
            // 节日徽章只认在窗口里记下的那一次：窗口外达到条件不算解锁。
            let unlocked = kept != nil || (badge.festivalWindow == nil && value >= badge.target)
            return PerfectBadgeStatus(badge: badge, current: unlocked ? badge.target : min(value, badge.target),
                                      unlocked: unlocked, earnedOn: kept)
        }
    }

    /// `earned` with every badge reached by now added, dated `today`.
    /// Never removes one.
    public static func earning(_ earned: [String: String], records: [PerfectDayRecord], focusMinutes: Int,
                               today: Date, calendar: Calendar = PerfectDay.calendar) -> [String: String] {
        var result = earned
        let key = HabitTracker.dayKey(today, calendar: calendar)
        for badge in PerfectBadge.allCases where result[badge.rawValue] == nil {
            if let window = badge.festivalWindow, !window.contains(today, base: calendar) { continue }
            if measure(badge, records: records, focusMinutes: focusMinutes, calendar: calendar) >= badge.target {
                result[badge.rawValue] = key
            }
        }
        return result
    }

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
