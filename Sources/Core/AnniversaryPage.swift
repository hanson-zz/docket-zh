import Foundation

/// 一个纪念日的专属页要用的数：里程碑、接下来几个周年，以及时间线顶部“这个月”的小概览。
///
/// 都是纯函数，日子和 `Anniversary` 的其余部分一样按本机时区的公历数，农历事件的周年
/// 也走 `Anniversary.occurrence`，所以和卡片、时间线上的数字永远一致。

/// 里程碑格子里的一格。
public struct AnniversaryMilestone: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        /// 正数日：在一起第 N 天那天。
        case daysSince
        /// 倒数日：还有 N 天的那天。
        case daysLeft
    }

    public var kind: Kind
    /// 100 天，或者还有 100 天。
    public var days: Int
    /// 那一天。
    public var date: Date
    /// 已经过去了（今天不算）。
    public var isPassed: Bool
    /// 就是今天。
    public var isToday: Bool
    /// 还没到的里面最近的一个（今天也算），格子上画一个圆点。
    public var isNext: Bool

    public var id: Int { days }
}

/// 接下来的一个周年。
public struct AnniversaryOccurrence: Equatable, Sendable, Identifiable {
    /// 第 N 个周年。
    public var ordinal: Int
    public var date: Date
    /// 还有几天，今天是 0。
    public var daysLeft: Int

    public var id: Int { ordinal }
}

/// 时间线顶部的“这个月”。
public struct AnniversaryMonthSummary: Equatable, Sendable {
    /// 1...12。
    public var month: Int
    /// 这个月里落着几个纪念日（已经过去的日子也算）。
    public var count: Int
    /// 这个月里还没到的最近一个，今天也算。都过去了就是 nil。
    public var nearest: AnniversaryEvent?
    /// 离 `nearest` 还有几天。
    public var nearestDays: Int?
}

public extension Anniversary {
    /// 正数日的里程碑：100 天、520 天、1000 天、1314 天，再到一万天。
    static let countupMilestones = [100, 520, 1000, 1314, 2000, 3000, 5000, 10_000]
    /// 倒数日的里程碑：还有 100、30、7、1 天的那一天，可以提前准备。
    static let countdownMilestones = [100, 30, 7, 1]
    /// 专属页列几个接下来的周年。
    static let upcomingCount = 4

    /// 一个纪念日的里程碑，按日子从早到晚。
    ///
    /// 正数日：从那天起第 N 天，和卡片上“已经 N 天”是同一种数法，所以第 100 天那天
    /// 卡片上正好写着 100。倒数日：下一次到来之前还有 N 天的那天；一次性的倒数日已经
    /// 过去了就没有里程碑。
    static func milestones(_ event: AnniversaryEvent, today: Date,
                           calendar: Calendar = Anniversary.calendar) -> [AnniversaryMilestone] {
        guard let original = date(fromKey: event.day, calendar: calendar) else { return [] }
        let start = calendar.startOfDay(for: today)
        let items: [(Int, Date)]
        let kind: AnniversaryMilestone.Kind
        switch event.kind {
        case .countup:
            kind = .daysSince
            items = countupMilestones.compactMap { n in
                calendar.date(byAdding: .day, value: n, to: original).map { (n, calendar.startOfDay(for: $0)) }
            }
        case .countdown:
            kind = .daysLeft
            guard let next = nextOccurrence(event, today: start, calendar: calendar) else { return [] }
            items = countdownMilestones.compactMap { n in
                calendar.date(byAdding: .day, value: -n, to: next).map { (n, calendar.startOfDay(for: $0)) }
            }
        }
        let nextIndex = items.firstIndex { $0.1 >= start }
        return items.enumerated().map { index, item in
            AnniversaryMilestone(kind: kind, days: item.0, date: item.1,
                                 isPassed: item.1 < start,
                                 isToday: calendar.isDate(item.1, inSameDayAs: start),
                                 isNext: index == nextIndex)
        }
    }

    /// 接下来的几个周年，今天也算：第几个周年、哪天、还有几天。
    ///
    /// 正数日总有周年；倒数日只有每年重复的才有。第 N 个从选的那天之后第一次到来数起，
    /// 农历事件按农历日子来，日期是落在的公历那天。
    static func upcomingAnniversaries(_ event: AnniversaryEvent, today: Date,
                                      count: Int = Anniversary.upcomingCount,
                                      calendar: Calendar = Anniversary.calendar) -> [AnniversaryOccurrence] {
        guard count > 0, event.kind == .countup || event.yearly,
              let original = date(fromKey: event.day, calendar: calendar) else { return [] }
        let start = calendar.startOfDay(for: today)
        let first = calendar.component(.year, from: original)
        let last = max(first, calendar.component(.year, from: start)) + count + 2
        var ordinal = 0
        var previous = original
        var result: [AnniversaryOccurrence] = []
        for year in (first - 1)...last {
            guard let day = occurrence(event, year: year, calendar: calendar), day > previous else { continue }
            previous = day
            ordinal += 1
            guard day >= start else { continue }
            result.append(AnniversaryOccurrence(ordinal: ordinal, date: day,
                                                daysLeft: days(from: start, to: day, calendar: calendar)))
            if result.count == count { break }
        }
        return result
    }

    /// `today` 所在的那个公历月里有几个纪念日，最近的还没到的是哪个、还有几天。
    static func monthSummary(_ events: [AnniversaryEvent], today: Date,
                             calendar: Calendar = Anniversary.calendar) -> AnniversaryMonthSummary {
        let start = calendar.startOfDay(for: today)
        let year = calendar.component(.year, from: start)
        let month = calendar.component(.month, from: start)
        let found = events.compactMap { event in
            dayInMonth(event, year: year, month: month, calendar: calendar).map { (event, $0) }
        }
        let nearest = found.filter { $0.1 >= start }.min {
            $0.1 != $1.1 ? $0.1 < $1.1 : $0.0.title < $1.0.title
        }
        return AnniversaryMonthSummary(month: month, count: found.count, nearest: nearest?.0,
                                       nearestDays: nearest.map { days(from: start, to: $0.1, calendar: calendar) })
    }

    /// 这个纪念日在公历 `year` 年 `month` 月落在哪天，不在就是 nil。
    ///
    /// 一次性的倒数日只有选的那天；每年重复的和正数日看那年的周年，选的那天本身也算。
    /// 农历腊月的日子会落到下一个公历年的一月，所以前一年的农历年也要看。
    static func dayInMonth(_ event: AnniversaryEvent, year: Int, month: Int,
                           calendar: Calendar = Anniversary.calendar) -> Date? {
        guard let original = date(fromKey: event.day, calendar: calendar) else { return nil }
        func inMonth(_ date: Date) -> Bool {
            let c = calendar.dateComponents([.year, .month], from: date)
            return c.year == year && c.month == month
        }
        if inMonth(original) { return original }
        guard event.yearly || event.kind == .countup else { return nil }
        for candidate in [year - 1, year] {
            if let day = occurrence(event, year: candidate, calendar: calendar), day > original, inMonth(day) {
                return day
            }
        }
        return nil
    }

    // MARK: Text

    /// 周日 … 周六。
    static func weekdayShort(_ date: Date, calendar: Calendar = Anniversary.calendar) -> String {
        let names = [tr("周日"), tr("周一"), tr("周二"), tr("周三"), tr("周四"), tr("周五"), tr("周六")]
        let weekday = calendar.component(.weekday, from: date)
        return names[max(0, min(weekday - 1, 6))]
    }

    /// 2019.8.28，里程碑格子和分享图用。
    static func dotText(_ date: Date, calendar: Calendar = Anniversary.calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0).\(c.month ?? 0).\(c.day ?? 0)"
    }

    /// 2027年5月20日。
    static func longText(_ date: Date, calendar: Calendar = Anniversary.calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return tr("\(String(c.year ?? 0))年\(c.month ?? 0)月\(c.day ?? 0)日")
    }
}
