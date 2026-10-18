import Foundation

/// 专注计时的轮次：专注、休息、几轮后长休息。一个环节到点后接下一个，卡片上的
/// 第几轮小点、休息时变绿提示起身，都按这里算。
///
/// 规则：
/// - 专注到点：完成数加一，接着自动开始休息；满 `sessions` 轮时是长休息。
///   休息从专注结束的那一刻算起，Mac 合盖期间过去的时间照样算。
/// - 休息或长休息到点：回到专注，停在开始前，等人按开始。长休息后轮次从头数。
/// - 到点超过 12 小时（几天没碰的计时器）：直接回到第一轮专注、没开始。
public enum FocusCycle {
    /// 超过这么久没管的到点，不再接着走，直接回到开头。
    public static let staleAfter: TimeInterval = 12 * 3600
    /// 卡片上最多画几颗小点。
    public static let maxDots = 8

    /// 正在跑：有结束时刻、没暂停、还没到点。
    public static func isRunning(_ state: TimerState, now: Date) -> Bool {
        guard state.paused == nil, let deadline = state.deadline else { return false }
        return deadline > now
    }

    /// 到点后的下一步；还没到点、暂停或没开始时是 nil。
    public static func advanced(_ state: TimerState, now: Date) -> TimerState? {
        guard state.paused == nil, let deadline = state.deadline, deadline <= now else { return nil }
        var next = state
        next.paused = nil
        if now.timeIntervalSince(deadline) > staleAfter {
            next.phase = .focus
            next.completed = 0
            next.deadline = nil
            next.duration = nil
            return next
        }
        switch state.phase {
        case .focus:
            next.completed = state.completed + 1
            let sessions = max(1, state.sessions)
            next.phase = next.completed % sessions == 0 ? .long : .rest
            let length = TimeInterval(max(1, next.minutes) * 60)
            next.duration = length
            next.deadline = deadline.addingTimeInterval(length)
        case .rest, .long:
            if state.phase == .long { next.completed = 0 }
            next.phase = .focus
            next.deadline = nil
            next.duration = nil
            next.stoodUp = deadline
        }
        return next
    }

    /// 现在是第几轮（从 1 数）。专注时是正在做的这一轮，休息时是刚做完的那一轮。
    public static func round(_ state: TimerState) -> Int {
        let sessions = max(1, state.sessions)
        switch state.phase {
        case .focus: return state.completed % sessions + 1
        case .rest, .long: return max(0, state.completed - 1) % sessions + 1
        }
    }

    /// 卡片上画几颗点：一组的轮数，最多 8 颗。
    public static func dotCount(_ state: TimerState) -> Int {
        min(maxDots, max(1, state.sessions))
    }

    /// 亮几颗：做到第几轮就亮到第几颗，当前这一轮也亮。
    public static func litDots(_ state: TimerState) -> Int {
        min(dotCount(state), round(state))
    }

    /// 休息环节、并且开着“休息时提醒起身”：卡片变绿，写“站起来走走”。
    public static func showsStandUp(_ state: TimerState) -> Bool {
        state.standUp && state.phase != .focus
    }

    /// “专注 · 第 2 轮”“休息 · 站起来走走”。
    public static func caption(_ state: TimerState) -> String {
        if showsStandUp(state) { return tr("\(state.phase.label) · 站起来走走") }
        return tr("\(state.phase.label) · 第 \(round(state)) 轮")
    }
}

/// 久坐提醒和专注计时不抢：开着专注计时（并且打开了“休息时提醒起身”）时，
/// 起身交给专注的休息环节，久坐提醒不发通知、小熊猫趴着不打扰；专注的休息结束后，
/// 久坐从那一刻重新算。两个都放在码头上也只提醒一次。
public enum SitFocus {
    /// 久坐提醒现在要不要让位给专注计时。
    public static func postureYields(to timer: TimerState, now: Date) -> Bool {
        timer.standUp && FocusCycle.isRunning(timer, now: now)
    }

    /// 久坐从哪一刻算：自己记的起身和专注休息结束，取晚的那个。
    public static func lastBreak(posture: Date?, timer: TimerState) -> Date? {
        guard timer.standUp, let stood = timer.stoodUp else { return posture }
        guard let posture else { return stood }
        return max(posture, stood)
    }

    /// 六格进度：每格是提醒间隔的六分之一，坐满一格亮一格。
    public static let cells = 6

    public static func litCells(sat: TimeInterval, interval: TimeInterval) -> Int {
        guard interval > 0, sat > 0 else { return 0 }
        return min(cells, Int((sat / interval * Double(cells)).rounded(.down)))
    }

    /// 已经坐了多久（秒）：从起身那一刻（或今天提醒时段开始）到现在。
    public static func sat(_ schedule: PostureSchedule, lastBreak: Date?, now: Date,
                           calendar: Calendar = .current) -> TimeInterval {
        max(0, now.timeIntervalSince(schedule.anchor(lastBreak: lastBreak, now: now, calendar: calendar)))
    }

    /// “已坐 48 分钟”“已坐 1 小时 5 分”。
    public static func satText(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 60 { return tr("已坐 \(minutes) 分钟") }
        let (h, m) = (minutes / 60, minutes % 60)
        return m == 0 ? tr("已坐 \(h) 小时") : tr("已坐 \(h) 小时 \(m) 分")
    }

    /// “60 分钟时叫你”“1 小时 30 分时叫你”。
    public static func dueText(_ interval: TimeInterval) -> String {
        let minutes = max(1, Int(interval / 60))
        if minutes <= 90 { return tr("\(minutes) 分钟时叫你") }
        let (h, m) = (minutes / 60, minutes % 60)
        return m == 0 ? tr("\(h) 小时时叫你") : tr("\(h) 小时 \(m) 分时叫你")
    }
}
