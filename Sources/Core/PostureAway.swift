import Foundation

/// 久坐提醒的「离开检测」：离开电脑（锁屏、休眠、屏保、显示器睡眠，或一直没碰
/// 键盘鼠标）满一定时间，自动算一次起身休息。
///
/// 这里只放判断，不碰系统：读空闲秒数和听锁屏、休眠通知的是
/// `PostureAwayMonitor`（Services），它把读到的东西喂给 `Tracker`，再按 `steps`
/// 写回每张久坐卡片。
///
/// 存在小组件自己的配置里：
/// - `away`：开关，默认开。
/// - `awayAfter`：离开多久算一次休息，"2"、"5"、"10"（分钟），默认 "5"。
/// - `autoBreaks`：今天自动记的休息，一项一段 `"离开时刻-回来时刻"`（秒，取整），
///   还没回来时是 `"离开时刻-"`。和 `breaks`、`breakDay` 一样跨天清空。
///   自动记的休息同时也在 `breaks` 里（离开那一刻），今天次数和近 7 天照常算它。
public enum PostureAway {
    public static let enabledKey = "away"
    public static let afterKey = "awayAfter"
    public static let segmentsKey = "autoBreaks"

    public static let minuteChoices = [2, 5, 10]
    public static let defaultMinutes = 5

    // MARK: 设置

    public static func isEnabled(_ config: WidgetConfig) -> Bool {
        config.bool(enabledKey, default: true)
    }

    /// 离开多少分钟算一次休息；不在 2、5、10 里的退回 5。
    public static func minutes(_ config: WidgetConfig) -> Int {
        let raw = Int(config.string(afterKey, default: "\(defaultMinutes)")) ?? defaultMinutes
        return minuteChoices.contains(raw) ? raw : defaultMinutes
    }

    public static func threshold(_ config: WidgetConfig) -> TimeInterval {
        TimeInterval(minutes(config) * 60)
    }

    // MARK: 判断离开和回来

    /// 喂给 `Tracker` 的东西。
    public enum Event: Equatable, Sendable {
        /// 采样一次：距上次键盘、鼠标、触控板输入过了多少秒。
        case idle(TimeInterval)
        /// 某个「肯定不在电脑前」的原因开始或结束：锁屏、休眠、屏保、显示器睡眠、
        /// 切换到别的用户。
        case blocked(Reason)
        case unblocked(Reason)
    }

    public enum Reason: String, Hashable, Sendable, CaseIterable {
        case locked, asleep, screensaver, displayOff, userSwitched
    }

    /// `Tracker` 看出来的变化。
    public enum Change: Equatable, Sendable {
        /// 离开了，从 `since`（最后一次输入或锁屏那一刻）算起。离开期间到点不提醒。
        case left(since: Date)
        /// 回来了，`at` 是回来那一刻（第一下输入或解锁）。
        case back(since: Date, at: Date)
    }

    /// 离开还是在：锁屏这类原因任一在就算离开；没有原因时，空闲满 `idleAfter`
    /// 秒算离开（离开从最后一次输入算），之后又有输入算回来（回来从那一下输入算）。
    ///
    /// `idleAfter` 是服务按所有开着离开检测的久坐卡片里最短的门槛给的；锁屏不等，
    /// 一锁就算离开，所以短暂锁屏期间到点也不提醒。
    public struct Tracker: Equatable, Sendable {
        public var idleAfter: TimeInterval
        public private(set) var since: Date?
        public private(set) var reasons: Set<Reason> = []

        /// 两次采样之间算出的「最后一次输入」会抖动一两秒，差这么多以内不算新的输入。
        public static let jitter: TimeInterval = 2

        public init(idleAfter: TimeInterval) {
            self.idleAfter = idleAfter
        }

        public var isAway: Bool { since != nil }

        public mutating func handle(_ event: Event, at now: Date) -> Change? {
            switch event {
            case .blocked(let reason):
                reasons.insert(reason)
                guard since == nil else { return nil }
                since = now
                return .left(since: now)

            case .unblocked(let reason):
                reasons.remove(reason)
                guard reasons.isEmpty, let start = since else { return nil }
                since = nil
                return .back(since: start, at: max(start, now))

            case .idle(let seconds):
                // 锁屏、休眠这些期间空闲读数不作数，等解锁。
                guard reasons.isEmpty else { return nil }
                let lastInput = now.addingTimeInterval(-max(0, seconds))
                if let start = since {
                    guard lastInput > start.addingTimeInterval(Self.jitter) else { return nil }
                    since = nil
                    return .back(since: start, at: lastInput)
                }
                guard seconds >= idleAfter else { return nil }
                since = lastInput
                return .left(since: lastInput)
            }
        }
    }

    // MARK: 每张卡片该做什么

    public enum Step: Equatable, Sendable {
        /// 离开满了门槛：算一次休息。`logged` 为真时记进今天的 breaks 和时间轴
        /// （起身时刻是 `since`），久坐计时从 `now` 清零（回来再从回来那一刻算）。
        case rest(since: Date, logged: Bool)
        /// 回来了，而这次离开算过休息：久坐从 `at` 重新计时，时间轴那段收尾。
        case resume(at: Date)
    }

    /// 一张久坐卡片在这一刻要做的事。
    ///
    /// - `back` 为 nil 表示还在离开中（采样时调用），否则是回来的那一刻。
    /// - `rested` 是这次离开这张卡片是不是已经算过休息。
    /// - 离开检测关着时什么都不做。
    /// - 离开那一刻不在提醒时段里、或和现在不是同一天（比如晚上锁屏第二天早上回来），
    ///   照样清零计时，但不记进今天的次数和时间轴。
    public static func steps(_ config: WidgetConfig, schedule: PostureSchedule,
                             since: Date, now: Date, back: Date?, rested: Bool,
                             calendar: Calendar = .current) -> [Step] {
        guard isEnabled(config) else { return [] }
        var result: [Step] = []
        let end = back ?? now
        if !rested, end.timeIntervalSince(since) >= threshold(config) {
            result.append(.rest(since: since, logged: shouldLog(schedule, since: since, now: now,
                                                                 calendar: calendar)))
        }
        if let back, rested || !result.isEmpty {
            result.append(.resume(at: back))
        }
        return result
    }

    /// 离开那一刻在提醒时段里，并且和现在是同一天。
    public static func shouldLog(_ schedule: PostureSchedule, since: Date, now: Date,
                                 calendar: Calendar = .current) -> Bool {
        schedule.isActive(since, calendar: calendar)
            && PostureTally.dayKey(since, calendar: calendar) == PostureTally.dayKey(now, calendar: calendar)
    }

    /// 离开期间到点不提醒：离开检测开着并且现在离开中。
    public static func suppresses(_ config: WidgetConfig, away: Bool) -> Bool {
        away && isEnabled(config)
    }

    // MARK: 今天自动记的休息

    public struct Segment: Equatable, Sendable {
        public var start: Date
        /// 还没回来时是 nil。
        public var end: Date?

        public init(start: Date, end: Date? = nil) {
            self.start = start
            self.end = end
        }
    }

    /// 今天自动记的休息，按先后排。不是今天记的（`breakDay` 不是今天）一律不算。
    public static func segments(_ config: WidgetConfig, now: Date,
                                calendar: Calendar = .current) -> [Segment] {
        let today = PostureTally.dayKey(now, calendar: calendar)
        guard config.string("breakDay") == today else { return [] }
        return config.strings(segmentsKey).compactMap(parse)
            .filter { PostureTally.dayKey($0.start, calendar: calendar) == today }
            .sorted { $0.start < $1.start }
    }

    static func parse(_ text: String) -> Segment? {
        let parts = text.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, let start = Double(parts[0]) else { return nil }
        let startDate = Date(timeIntervalSince1970: start)
        if parts[1].isEmpty { return Segment(start: startDate) }
        guard let end = Double(parts[1]), end >= start else { return nil }
        return Segment(start: startDate, end: Date(timeIntervalSince1970: end))
    }

    static func encode(_ segment: Segment) -> WidgetConfig.Value {
        let start = Int(segment.start.timeIntervalSince1970.rounded(.down))
        guard let end = segment.end else { return .string("\(start)-") }
        return .string("\(start)-\(max(start, Int(end.timeIntervalSince1970.rounded(.down))))")
    }

    /// 自动记一次休息之后的 `autoBreaks`：今天已有的加上这次（还没回来）。
    public static func segmentsAfterResting(_ config: WidgetConfig, since: Date, now: Date,
                                            calendar: Calendar = .current) -> [WidgetConfig.Value] {
        (segments(config, now: now, calendar: calendar) + [Segment(start: since)]).map(encode)
    }

    /// 回来之后的 `autoBreaks`：还没回来的那几段收在 `at`。
    public static func segmentsAfterReturning(_ config: WidgetConfig, at: Date, now: Date,
                                              calendar: Calendar = .current) -> [WidgetConfig.Value] {
        segments(config, now: now, calendar: calendar).map { segment in
            var segment = segment
            if segment.end == nil { segment.end = max(segment.start, at) }
            return encode(segment)
        }
    }

    /// 时间轴上画的自动休息：裁到今天的提醒时段和现在之内，还没回来的画到现在。
    public static func rests(_ schedule: PostureSchedule, segments: [Segment], now: Date,
                             calendar: Calendar = .current) -> [PostureTrack.Stretch] {
        guard let window = PostureTrack.window(schedule, now: now, calendar: calendar) else { return [] }
        let stop = min(now, window.end)
        return segments.compactMap { segment in
            let start = max(segment.start, window.start)
            let end = min(segment.end ?? now, stop)
            guard end > start else { return nil }
            return PostureTrack.Stretch(start: start, end: end, ongoing: segment.end == nil)
        }
    }
}
