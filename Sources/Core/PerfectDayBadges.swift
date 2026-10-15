import Foundation

/// 完美一天的徽章：里程碑，按已结算的日子和专注总时长算出来。
///
/// Earned once and kept: `PerfectDayArchive.earned` remembers the day each
/// was first earned, and `earning` only ever adds to it, so trimming old days
/// or deleting a widget never takes a badge back.
public enum PerfectBadge: String, CaseIterable, Sendable, Hashable, Identifiable {
    case firstPerfect
    case sunStreak3
    case sunStreak7
    case sunStreak30
    case perfectMonth10
    case suns50
    case water7
    case habit7
    case focus10h
    case focus100h

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .firstPerfect: "初见完美"
        case .sunStreak3: "三日晴"
        case .sunStreak7: "一周晴"
        case .sunStreak30: "满月晴"
        case .perfectMonth10: "金色月份"
        case .suns50: "阳光收藏家"
        case .water7: "水润一周"
        case .habit7: "习惯成自然"
        case .focus10h: "专注 10 小时"
        case .focus100h: "专注 100 小时"
        }
    }

    /// What it takes, shown under a locked badge.
    public var condition: String {
        switch self {
        case .firstPerfect: "得到第一个完美一天"
        case .sunStreak3: "连续 3 天有太阳"
        case .sunStreak7: "连续 7 天有太阳"
        case .sunStreak30: "连续 30 天有太阳"
        case .perfectMonth10: "一个月内 10 个完美一天"
        case .suns50: "累计收集 50 个小太阳"
        case .water7: "喝水连续 7 天达标"
        case .habit7: "习惯连续 7 天全部完成"
        case .focus10h: "专注累计 10 小时"
        case .focus100h: "专注累计 100 小时"
        }
    }

    public var symbol: String {
        switch self {
        case .firstPerfect: "sun.max.fill"
        case .sunStreak3: "flame.fill"
        case .sunStreak7: "sparkles"
        case .sunStreak30: "crown.fill"
        case .perfectMonth10: "calendar.badge.checkmark"
        case .suns50: "star.circle.fill"
        case .water7: "drop.fill"
        case .habit7: "checkmark.seal.fill"
        case .focus10h: "timer"
        case .focus100h: "brain.head.profile"
        }
    }

    /// The disc's two gradient stops, as hex.
    public var hexes: (light: String, deep: String) {
        switch self {
        case .firstPerfect: ("#FFE07A", "#FF9F1C")
        case .sunStreak3: ("#FFB27A", "#F0544F")
        case .sunStreak7: ("#FF9BD2", "#B05CFF")
        case .sunStreak30: ("#FFE9A8", "#D4A017")
        case .perfectMonth10: ("#FFD86B", "#E08A00")
        case .suns50: ("#9FE8FF", "#3D7BFF")
        case .water7: ("#8FD3FF", "#2B7FE0")
        case .habit7: ("#9BF0B4", "#25A55F")
        case .focus10h: ("#C3B6FF", "#6B4EE6")
        case .focus100h: ("#E0B3FF", "#7B2FD0")
        }
    }

    /// The number to reach.
    public var target: Int {
        switch self {
        case .firstPerfect: 1
        case .sunStreak3: 3
        case .sunStreak7: 7
        case .sunStreak30: 30
        case .perfectMonth10: 10
        case .suns50: 50
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
    /// Best so far, in the badge's own unit (days, suns, minutes), capped at the target.
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
        case .firstPerfect:
            return records.filter { $0.tier == .gold }.count
        case .sunStreak3, .sunStreak7, .sunStreak30:
            return PerfectDay.longestRun(Set(records.filter { $0.tier != nil }.map(\.key)), calendar: calendar)
        case .perfectMonth10:
            var byMonth: [Substring: Int] = [:]
            for record in records where record.tier == .gold { byMonth[record.key.prefix(6), default: 0] += 1 }
            return byMonth.values.max() ?? 0
        case .suns50:
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
