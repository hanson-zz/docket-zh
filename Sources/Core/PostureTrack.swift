import Foundation

/// 久坐提醒的今天和近 7 天：每次起身的时间、每天起身几次、每天目标几次，
/// 以及由它们算出的坐着的段、最长连坐、平均每次坐多久。
///
/// 存在小组件自己的配置里：
/// - `breaks`：今天每次起身的时间戳（秒），跨天清空；和 `breakDay` 同一天才算数。
/// - `history`：最近 7 天每天起身次数，`"2026-10-20=4"` 这样一项一天。
/// - `goal`：每天目标次数，默认 8，1 到 20。
///
/// 改版前记的起身只有 `breakCount` 和 `lastBreak`，没有时间戳：今天次数仍用
/// `breakCount`（见 `PostureTally`），时间轴只能按 `lastBreak` 切一刀。
/// 锁屏或空闲的「离开」自动记的休息见 `PostureAway`，算段时传进来（`away`），
/// 离开那段不算坐着，回来后的一段从回来那一刻算。
public enum PostureTrack {
    public static let breaksKey = "breaks"
    public static let historyKey = "history"
    public static let goalKey = "goal"

    public static let defaultGoal = 8
    public static let goalRange = 1...20
    /// 近几天的柱状图，今天算在内。
    public static let keptDays = 7

    // MARK: 目标

    public static func goal(_ config: WidgetConfig) -> Int {
        let raw = config.int(goalKey, default: defaultGoal)
        return min(goalRange.upperBound, max(goalRange.lowerBound, raw))
    }

    // MARK: 起身时间戳

    /// 今天记下的起身时刻，按先后排。不是今天记的（`breakDay` 不是今天）一律不算。
    public static func breaks(_ config: WidgetConfig, now: Date, calendar: Calendar = .current) -> [Date] {
        let today = PostureTally.dayKey(now, calendar: calendar)
        guard config.string("breakDay") == today, case .list(let list) = config[breaksKey] else { return [] }
        return list.compactMap { value -> Date? in
            guard case .number(let seconds) = value else { return nil }
            let date = Date(timeIntervalSince1970: seconds)
            return PostureTally.dayKey(date, calendar: calendar) == today ? date : nil
        }
        .sorted()
    }

    /// 记一次起身之后的 `breaks`：今天已有的加上这一次，昨天的丢掉。
    /// `at` 是起身的时刻，默认就是现在；离开电脑自动记的休息记在离开那一刻。
    public static func breaksAfterLogging(_ config: WidgetConfig, at: Date? = nil, now: Date,
                                          calendar: Calendar = .current) -> [WidgetConfig.Value] {
        (breaks(config, now: now, calendar: calendar) + [at ?? now])
            .sorted()
            .map { .number($0.timeIntervalSince1970) }
    }

    // MARK: 近 7 天

    /// `history` 读成 日期 → 次数；格式不对的项丢掉。
    public static func history(_ config: WidgetConfig) -> [String: Int] {
        var days: [String: Int] = [:]
        for item in config.strings(historyKey) {
            let parts = item.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2, parts[0].count == 10, let count = Int(parts[1]), count >= 0 else { continue }
            days[parts[0]] = count
        }
        return days
    }

    /// 记一次起身之后的 `history`：今天写成新的次数，只留最近 7 天，按日期排。
    public static func historyAfterLogging(_ config: WidgetConfig, todayCount: Int, now: Date,
                                           calendar: Calendar = .current) -> [WidgetConfig.Value] {
        var days = history(config)
        days[PostureTally.dayKey(now, calendar: calendar)] = max(0, todayCount)
        let kept = Set(recentDays(now: now, calendar: calendar).map { PostureTally.dayKey($0, calendar: calendar) })
        return days.keys.filter { kept.contains($0) }.sorted()
            .map { .string("\($0)=\(days[$0] ?? 0)") }
    }

    /// 最近 7 天每天零点，最早的在前，最后一个是今天。
    public static func recentDays(now: Date, calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: now)
        return (0..<keptDays).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }

    public struct Day: Equatable, Sendable {
        public var date: Date
        public var count: Int
        public var isToday: Bool
    }

    /// 近 7 天补零的序列，最早的在前。今天用 `todayCount`（来自 `breakCount`，
    /// 改版前的数据也对），不看 `history` 里今天那项。
    public static func week(_ config: WidgetConfig, todayCount: Int, now: Date,
                            calendar: Calendar = .current) -> [Day] {
        let days = history(config)
        let todayKey = PostureTally.dayKey(now, calendar: calendar)
        return recentDays(now: now, calendar: calendar).map { date in
            let key = PostureTally.dayKey(date, calendar: calendar)
            let isToday = key == todayKey
            return Day(date: date, count: isToday ? max(0, todayCount) : (days[key] ?? 0), isToday: isToday)
        }
    }

    /// 柱状图的顶：目标和最多那天取大的，再留一点头。
    public static func chartCeiling(_ days: [Day], goal: Int) -> Int {
        max(goal, days.map(\.count).max() ?? 0) + 2
    }

    // MARK: 今天坐着的段

    public struct Stretch: Equatable, Sendable {
        public var start: Date
        public var end: Date
        /// 还在坐着（到现在为止）的那一段。
        public var ongoing: Bool
        /// 这段是离开电脑自动记的休息之后开始的（时间轴上那个起身点画浅一点）。
        public var afterAway: Bool = false

        public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
    }

    /// 今天提醒时段的开始和结束。时段还没开始（今天的开始在 `now` 之后）时是 nil。
    public static func window(_ schedule: PostureSchedule, now: Date,
                              calendar: Calendar = .current) -> (start: Date, end: Date)? {
        let start = schedule.currentWindowStart(now, calendar: calendar)
        var length = schedule.end - schedule.start
        if length <= 0 { length += 1440 }
        let end = start.addingTimeInterval(TimeInterval(length * 60))
        // 普通时段（比如 09:00-18:00）过了午夜还没到开始：今天的还没开始。
        if PostureTally.dayKey(start, calendar: calendar) != PostureTally.dayKey(now, calendar: calendar),
           now >= end {
            return nil
        }
        return (start, end)
    }

    /// 从提醒时段开始，到每次起身，再到现在（或时段结束）的一段段坐着。
    ///
    /// `breaks` 可以乱序、可以重复（相差 1 秒内算一次），时段外的不算。
    /// `away` 是离开电脑自动记的休息（见 `PostureAway`）：那一段不算坐着，坐着的段
    /// 在离开那一刻结束，下一段从回来那一刻开始；还没回来就没有正在坐的段。
    /// 时段还没开始时没有段。
    public static func stretches(_ schedule: PostureSchedule, breaks: [Date],
                                 away: [PostureAway.Segment] = [], now: Date,
                                 calendar: Calendar = .current) -> [Stretch] {
        guard let window = window(schedule, now: now, calendar: calendar) else { return [] }
        let stop = min(now, window.end)
        guard stop > window.start else { return [] }
        // 起身是一刻（开始和结束相同），离开是一段。
        var gaps: [(start: Date, end: Date, away: Bool)] = []
        for date in breaks where date > window.start && date < stop {
            gaps.append((date, date, false))
        }
        for segment in away {
            let end = min(segment.end ?? now, stop)
            guard end > window.start, segment.start < stop else { continue }
            gaps.append((max(segment.start, window.start), max(end, segment.start), true))
        }
        gaps.sort { ($0.start, $0.away ? 0 : 1) < ($1.start, $1.away ? 0 : 1) }

        var result: [Stretch] = []
        var from = window.start
        var lastCut: Date?
        var afterAway = false
        for gap in gaps {
            if !gap.away {
                // 离开那段里面（含两头）的起身不另算；相差 1 秒内的起身算一次。
                if gap.start <= from, afterAway { continue }
                if let lastCut, gap.start.timeIntervalSince(lastCut) < 1 { continue }
            }
            if gap.start > from {
                result.append(Stretch(start: from, end: gap.start, ongoing: false, afterAway: afterAway))
            }
            if gap.away || gap.end > from {
                afterAway = gap.away
            }
            from = max(from, gap.end)
            lastCut = from
        }
        let stillAway = away.contains { $0.end == nil && $0.start < stop }
        if stop > from, !stillAway {
            result.append(Stretch(start: from, end: stop, ongoing: now < window.end, afterAway: afterAway))
        }
        return result
    }

    /// 今天最长的一段（含还在坐着的），没有段时是 nil。
    public static func longest(_ stretches: [Stretch]) -> Stretch? {
        stretches.max { $0.duration < $1.duration }
    }

    /// 平均每次坐多久（秒）：起身结束的那几段的平均；还没起过身就用正在坐的这段。
    public static func average(_ stretches: [Stretch]) -> TimeInterval? {
        let done = stretches.filter { !$0.ongoing }
        let pool = done.isEmpty ? stretches : done
        guard !pool.isEmpty else { return nil }
        return pool.map(\.duration).reduce(0, +) / Double(pool.count)
    }

    /// 时间轴上一段的粉色深浅，0 最淡 1 最深：坐到间隔的六成以下最淡，
    /// 到间隔的 2.2 倍最深。
    public static func heat(_ duration: TimeInterval, interval: TimeInterval) -> Double {
        guard interval > 0 else { return 0 }
        let value = (duration - interval * 0.6) / (interval * 1.6)
        return min(1, max(0, value))
    }

    /// 某个时刻在时段里的位置，0 到 1。
    public static func fraction(_ date: Date, start: Date, end: Date) -> Double {
        let span = end.timeIntervalSince(start)
        guard span > 0 else { return 0 }
        return min(1, max(0, date.timeIntervalSince(start) / span))
    }

    /// 时间轴下的刻度（午夜后的分钟数）：开始、结束，中间两处取整点三等分。
    /// 时段不到 3 小时时只标两头。
    public static func ticks(_ schedule: PostureSchedule) -> [Int] {
        var length = schedule.end - schedule.start
        if length <= 0 { length += 1440 }
        guard length >= 180 else { return [schedule.start, schedule.start + length] }
        let inner = [1, 2].map { part -> Int in
            let raw = schedule.start + length * part / 3
            return Int((Double(raw) / 60).rounded()) * 60
        }
        return [schedule.start] + inner + [schedule.start + length]
    }
}
