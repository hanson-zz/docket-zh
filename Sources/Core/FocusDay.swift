import Foundation

/// 专注计时面板的“今天”：每个完整结束的番茄记成一段（开始、结束、任务名），
/// 时间轴每段一格并标出现在；任务名和最近用过的任务名；开始专注时放的环境音。
///
/// 记录存成字符串列表，一段一行 `开始秒|结束秒|任务名`（任务名在最后，里面有竖线
/// 也不怕），和 `FocusLog` 一样放在全局，不放在某张卡片的配置里：计时器全应用只有
/// 一个。只留最近 `keptDays` 天、最多 `maxSegments` 段，够画今天和 Pro 的历史统计。
public enum FocusDay {
    /// 留几天的番茄段。
    public static let keptDays = 7
    /// 最多留几段，防止异常数据把列表撑大。
    public static let maxSegments = 400
    /// 任务名最多几个字。
    public static let maxTaskLength = 40
    /// “最近的任务名”最多留几个。
    public static let maxRecentTasks = 6
    /// 时间轴默认画 8 点到 20 点，有更早或更晚的番茄就往外扩。
    public static let defaultStartHour = 8
    public static let defaultEndHour = 20

    /// 时间轴上的一段。`live` 为正在进行的这一个番茄（画淡一点）。
    public struct Segment: Equatable, Sendable {
        public var start: Date
        public var end: Date
        public var task: String
        public var live: Bool

        public init(start: Date, end: Date, task: String = "", live: Bool = false) {
            self.start = start
            self.end = end
            self.task = task
            self.live = live
        }

        public var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
    }

    // MARK: 读写

    /// 解析存的记录：格式不对、结束不晚于开始的行跳过，按开始时刻排好。
    public static func segments(_ lines: [String]) -> [Segment] {
        lines.compactMap { line -> Segment? in
            let parts = line.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count >= 2, let a = Double(parts[0]), let b = Double(parts[1]),
                  a.isFinite, b.isFinite, b > a else { return nil }
            let task = parts.count == 3 ? String(parts[2]) : ""
            return Segment(start: Date(timeIntervalSince1970: a), end: Date(timeIntervalSince1970: b),
                           task: cleanTask(task))
        }
        .sorted { $0.start < $1.start }
    }

    public static func line(_ segment: Segment) -> String {
        "\(Int(segment.start.timeIntervalSince1970.rounded()))|\(Int(segment.end.timeIntervalSince1970.rounded()))|\(cleanTask(segment.task))"
    }

    /// 记一段完整结束的番茄：`seconds` 是这一轮的长度，`endedAt` 是到点的时刻。
    /// 同一个结束时刻记过就不再记（同一轮被看到两次）。丢掉 `keptDays` 天以前的。
    public static func adding(seconds: TimeInterval, endedAt: Date, task: String, to lines: [String],
                              calendar: Calendar = HabitTracker.calendar) -> [String] {
        guard seconds.isFinite, seconds >= 30 else { return pruned(lines, now: endedAt, calendar: calendar) }
        var list = segments(lines)
        if list.contains(where: { abs($0.end.timeIntervalSince(endedAt)) < 1 }) {
            return pruned(lines, now: endedAt, calendar: calendar)
        }
        list.append(Segment(start: endedAt.addingTimeInterval(-seconds), end: endedAt, task: task))
        return pruned(list.sorted { $0.start < $1.start }.map(line), now: endedAt, calendar: calendar)
    }

    /// 只留最近 `keptDays` 天（按结束那天算）和最后 `maxSegments` 段。
    public static func pruned(_ lines: [String], now: Date, calendar: Calendar = HabitTracker.calendar) -> [String] {
        let startToday = calendar.startOfDay(for: now)
        let cutoff = calendar.date(byAdding: .day, value: -(keptDays - 1), to: startToday) ?? startToday
        let kept = segments(lines).filter { $0.end >= cutoff }
        return kept.suffix(maxSegments).map(line)
    }

    /// 今天的段：结束在今天的，开始早于今天零点的截到零点。
    public static func today(_ lines: [String], now: Date, calendar: Calendar = HabitTracker.calendar) -> [Segment] {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return segments(lines).compactMap { segment in
            guard segment.end > start, segment.start < end else { return nil }
            var clipped = segment
            clipped.start = max(segment.start, start)
            clipped.end = min(segment.end, end)
            return clipped
        }
    }

    // MARK: 正在进行的番茄

    /// 正在专注（在跑或暂停）时，时间轴上这一段：从开始到现在。休息、没开始时是 nil。
    /// 开始时刻按“已经专注了多久”倒推，暂停过的不算暂停那段。
    public static func live(_ state: TimerState, now: Date, task: String? = nil) -> Segment? {
        guard state.phase == .focus else { return nil }
        let total = max(1, state.duration ?? Double(max(1, state.work) * 60))
        let left: TimeInterval
        if let paused = state.paused {
            left = max(0, min(paused, total))
        } else if let deadline = state.deadline, deadline > now {
            left = max(0, min(deadline.timeIntervalSince(now), total))
        } else {
            return nil
        }
        let done = total - left
        guard done > 0 else { return nil }
        return Segment(start: now.addingTimeInterval(-done), end: now, task: task ?? state.task, live: true)
    }

    // MARK: 时间轴

    /// 时间轴画几点到几点（整点，偶数）：默认 8 到 20，有更早的段或现在更早就往前扩，
    /// 更晚就往后扩，最多 0 到 24。
    public static func window(_ segments: [Segment], now: Date,
                              calendar: Calendar = HabitTracker.calendar) -> ClosedRange<Int> {
        var lo = defaultStartHour, hi = defaultEndHour
        let day = calendar.startOfDay(for: now)
        func hours(_ date: Date) -> Double { date.timeIntervalSince(day) / 3600 }
        let points = segments.flatMap { [hours($0.start), hours($0.end)] } + [hours(now)]
        for h in points where h >= 0 && h <= 24 {
            lo = min(lo, Int(h.rounded(.down)))
            hi = max(hi, Int(h.rounded(.up)))
        }
        lo = max(0, lo - lo % 2)
        hi = min(24, hi + hi % 2)
        if hi <= lo { hi = min(24, lo + 2) }
        return lo...hi
    }

    /// 刻度：12 小时以内每 2 小时一个，再长每 4 小时一个，两头都在。
    public static func ticks(_ window: ClosedRange<Int>) -> [Int] {
        let span = window.upperBound - window.lowerBound
        let step = span <= 12 ? 2 : 4
        var result = Array(stride(from: window.lowerBound, through: window.upperBound, by: step))
        if result.last != window.upperBound { result.append(window.upperBound) }
        return result
    }

    /// 某一刻在时间轴上的位置，0 到 1。
    public static func fraction(_ date: Date, window: ClosedRange<Int>,
                                calendar: Calendar = HabitTracker.calendar) -> Double {
        let day = calendar.startOfDay(for: date)
        let h = date.timeIntervalSince(day) / 3600
        let span = Double(max(1, window.upperBound - window.lowerBound))
        return min(1, max(0, (h - Double(window.lowerBound)) / span))
    }

    // MARK: 文案

    /// “4 个番茄 · 第 5 个进行中”“还没有完成的番茄”。
    public static func footer(done: Int, live: Bool) -> String {
        switch (done, live) {
        case (0, false): tr("今天还没有完成的番茄")
        case (0, true): tr("第 1 个番茄进行中")
        case (_, false): tr("\(done) 个番茄")
        case (_, true): tr("\(done) 个番茄 · 第 \(done + 1) 个进行中")
        }
    }

    /// “已专注 1 小时 40 分”“已专注 25 分钟”“还没开始专注”。
    public static func focusedText(minutes: Int) -> String {
        guard minutes > 0 else { return tr("还没开始专注") }
        if minutes < 60 { return tr("已专注 \(minutes) 分钟") }
        let (h, m) = (minutes / 60, minutes % 60)
        return m == 0 ? tr("已专注 \(h) 小时") : tr("已专注 \(h) 小时 \(m) 分")
    }

    /// 面板标题下一行：“专注中 · 第 2 / 4 轮”“已暂停 · 第 2 / 4 轮”“准备专注 · 第 1 / 4 轮”，
    /// 休息时“休息 · 站起来走走”或“休息 · 第 2 / 4 轮”。
    public static func status(_ state: TimerState, now: Date) -> String {
        let round = tr("第 \(FocusCycle.round(state)) / \(max(1, state.sessions)) 轮")
        if state.phase != .focus {
            if FocusCycle.showsStandUp(state) { return FocusCycle.caption(state) }
            return "\(state.phase.label) · \(round)"
        }
        if state.paused != nil { return tr("已暂停 · \(round)") }
        if FocusCycle.isRunning(state, now: now) { return tr("专注中 · \(round)") }
        return tr("准备专注 · \(round)")
    }

    // MARK: 设置里的加减

    /// 专注、短休息、长休息（分钟）和几轮一组的范围与步长，和设置里一样。
    public static let workRange = 1...180
    public static let restRange = 1...60
    public static let longRange = 1...180
    public static let sessionsRange = 1...12

    /// 按一下 + 或 −：按 `step` 对齐着走（25 → 30 → 35），小于一步时一分一分走，
    /// 夹在 `range` 里。
    public static func stepped(_ value: Int, up: Bool, step: Int, range: ClosedRange<Int>) -> Int {
        let step = max(1, step)
        let v = min(range.upperBound, max(range.lowerBound, value))
        let next: Int
        if up {
            next = v < step ? v + 1 : (v / step + 1) * step
        } else {
            next = v <= step ? v - 1 : ((v - 1) / step) * step
        }
        return min(range.upperBound, max(range.lowerBound, next))
    }

    // MARK: 任务名

    /// 去掉首尾空白和换行，最多 `maxTaskLength` 个字。
    public static func cleanTask(_ raw: String) -> String {
        let flat = raw.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(flat.prefix(maxTaskLength))
    }

    /// 用过一个任务名后“最近的任务名”：放到最前，重复的去掉，最多 `maxRecentTasks` 个。
    /// 空的不记。
    public static func remembering(_ task: String, in recent: [String]) -> [String] {
        let task = cleanTask(task)
        let rest = recent.map(cleanTask).filter { !$0.isEmpty && $0 != task }
        guard !task.isEmpty else { return Array(rest.prefix(maxRecentTasks)) }
        return Array(([task] + rest).prefix(maxRecentTasks))
    }

    public static func forgetting(_ task: String, in recent: [String]) -> [String] {
        recent.filter { $0 != task }
    }
}

/// 开始专注时自动放的环境音：专注在跑就放选好的那种，休息时按“休息时声音停下”
/// 停或接着放；暂停、重置、没选声音时不放。
public enum FocusAmbient {
    public static let volumeRange = 0...100
    public static let defaultVolume = 55

    /// 选的声音；空字符串或认不出的值是“不播放”。
    public static func sound(_ state: TimerState) -> AmbientSound? {
        AmbientSound(rawValue: state.ambient)
    }

    /// 现在应该放哪种声音，nil 是不放。
    public static func wanted(_ state: TimerState, now: Date) -> AmbientSound? {
        guard let sound = sound(state), FocusCycle.isRunning(state, now: now) else { return nil }
        if state.phase != .focus, state.quietOnBreak { return nil }
        return sound
    }

    /// 选声音时的下一个（面板上“换”）：按目录顺序轮，最后一个之后回到第一个。
    /// 没选时从第一个开始。
    public static func next(after raw: String) -> AmbientSound {
        let all = AmbientSound.allCases
        guard let current = AmbientSound(rawValue: raw), let index = all.firstIndex(of: current) else {
            return all[0]
        }
        return all[(index + 1) % all.count]
    }

    public static func clampVolume(_ value: Int) -> Int {
        min(volumeRange.upperBound, max(volumeRange.lowerBound, value))
    }
}

/// 专注计时的 Pro：历史统计（近七天报告）是 Pro，免费只看今天。
/// 记录照样每天都记，解锁或试用时历史马上回来。
public extension ProLicenseGate {
    static func canSeeFocusHistory(unlocked: Bool) -> Bool { unlocked }
}
