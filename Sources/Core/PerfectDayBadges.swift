import Foundation

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

    /// "3/7", or "4/10 小时" for the focus badges.
    public var progressText: String {
        switch badge {
        case .focus10h, .focus100h: "\(current / 60)/\(badge.target / 60) 小时"
        default: "\(current)/\(badge.target)"
        }
    }
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
            let unlocked = kept != nil || value >= badge.target
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
            if measure(badge, records: records, focusMinutes: focusMinutes, calendar: calendar) >= badge.target {
                result[badge.rawValue] = key
            }
        }
        return result
    }
}
