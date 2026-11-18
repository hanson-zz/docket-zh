import Foundation

// MARK: - 专注吉祥物（从拾掇搬来）
//
// 六只吉祥物各四种状态的图放在 Resources/Focus（`focus-mascot-<吉祥物>-<状态>.png`，
// 高 256 像素、压过的透明 PNG）。专注面板进度环左下角显示当前状态的那张，刘海小岛专注时
// 左边放它、右边放剩余时间。选小熊猫时专注进行中照旧爬竹竿（`FocusPandaClimb`），
// 其余时候也用小熊猫的状态图。

/// 专注吉祥物：选的存在 `TimerState.mascot`，空或认不出时是小熊猫。
public enum FocusMascot: String, CaseIterable, Sendable {
    case panda, shiba, cat, penguin, otter, octopus

    public static let fallback: FocusMascot = .panda

    /// 存的值换成吉祥物：空、认不出的都是小熊猫。
    public static func from(_ raw: String) -> FocusMascot {
        FocusMascot(rawValue: raw) ?? fallback
    }

    public static func of(_ state: TimerState) -> FocusMascot { from(state.mascot) }

    /// 小熊猫免费，其余五只是码头 Pro。
    public var requiresPro: Bool { self != .panda }

    /// 实际显示哪只：没解锁时选了 Pro 吉祥物也显示小熊猫（存的选择不动，解锁后自动回来）。
    public static func of(_ state: TimerState, unlocked: Bool) -> FocusMascot {
        let chosen = of(state)
        return chosen.requiresPro && !unlocked ? fallback : chosen
    }

    /// 资源里的图名（不带扩展名）。
    public func imageName(_ state: FocusMascotState) -> String {
        "focus-mascot-\(rawValue)-\(state.rawValue)"
    }

    /// 小熊猫专注时爬竹竿，别的吉祥物用状态图。
    public var climbsBamboo: Bool { self == .panda }

    public var title: String {
        switch self {
        case .panda: tr("小熊猫")
        case .shiba: tr("柴犬")
        case .cat: tr("橘猫")
        case .penguin: tr("企鹅")
        case .otter: tr("水獭")
        case .octopus: tr("八爪鱼")
        }
    }
}

/// 吉祥物的四种状态：等开始、专注中、休息、刚完成一轮（撒花）。
public enum FocusMascotState: String, CaseIterable, Sendable {
    case idle, focus, `break`, done

    /// 专注到点、休息自动开始后，先撒花这么久再换成休息的样子。
    public static let doneWindow: TimeInterval = 60

    /// 现在该显示哪种：专注在跑是专注中，专注没开始或暂停是等开始；休息刚开始的
    /// `doneWindow` 秒内是刚完成，其余（含暂停的休息）是休息。
    public static func of(_ state: TimerState, now: Date) -> FocusMascotState {
        switch state.phase {
        case .focus:
            return FocusCycle.isRunning(state, now: now) ? .focus : .idle
        case .rest, .long:
            if state.paused == nil, let since = FocusMascotDisplay.secondsIntoBreak(state, now: now),
               since < doneWindow {
                return .done
            }
            return .`break`
        }
    }
}

public enum FocusMascotDisplay {
    /// 小熊猫爬到顶欢呼大约多久（`FocusBambooClimber` 演 3 秒），这段时间不再另画一只。
    public static let cheerWindow: TimeInterval = 3.5

    /// 休息已经走了多少秒；没在跑的休息是 nil。
    public static func secondsIntoBreak(_ state: TimerState, now: Date) -> TimeInterval? {
        guard state.phase != .focus, state.paused == nil,
              let deadline = state.deadline, let duration = state.duration else { return nil }
        let start = deadline.addingTimeInterval(-duration)
        guard now >= start, now < deadline else { return nil }
        return now.timeIntervalSince(start)
    }

    /// 专注面板进度环旁边要不要画吉祥物的状态图。别的吉祥物一直画；小熊猫专注进行中在
    /// 竹竿上（免费版竹竿旁是一只静态的），不再另画；解锁时刚完成那几秒在竹竿顶上欢呼，也不画。
    public static func showsStill(_ mascot: FocusMascot, state: TimerState, now: Date, unlocked: Bool) -> Bool {
        guard mascot.climbsBamboo else { return true }
        if FocusPandaClimb.isActive(state) { return false }
        if unlocked, let since = secondsIntoBreak(state, now: now), since < cheerWindow { return false }
        return true
    }
}

// MARK: - 拖大数字定时长

/// 专注还没开始时，左右或上下拖剩余时间的大数字调专注时长：5 分钟一档，5 到 90 分钟。
public enum FocusScrub {
    public static let range = 5...90
    public static let step = 5
    /// 拖多远换一档（点）。
    public static let pointsPerStep: Double = 14

    /// 只有专注环节、还没开始（没在跑也没暂停）时能拖。
    public static func canScrub(_ state: TimerState) -> Bool {
        state.phase == .focus && state.deadline == nil && state.paused == nil
    }

    /// 起点：现在的时长对齐到最近的一档，夹在范围里。
    public static func base(_ minutes: Int) -> Int {
        let snapped = Int((Double(minutes) / Double(step)).rounded()) * step
        return clamp(snapped)
    }

    public static func clamp(_ minutes: Int) -> Int {
        min(range.upperBound, max(range.lowerBound, minutes))
    }

    /// 拖了几档：向右、向上是加；横竖取移动多的那个方向。`dy` 是屏幕坐标（向下为正）。
    public static func steps(dx: Double, dy: Double) -> Int {
        let up = -dy
        let distance = abs(dx) >= abs(up) ? dx : up
        return Int((distance / pointsPerStep).rounded(.towardZero))
    }

    /// 从 `start` 分钟起拖了 (dx, dy)，时长变成多少。还没拖满一档时原样不动（设置里调成
    /// 120 分钟的，碰一下不会被夹成 90）。
    public static func minutes(from start: Int, dx: Double, dy: Double) -> Int {
        let n = steps(dx: dx, dy: dy)
        guard n != 0 else { return start }
        return clamp(base(start) + n * step)
    }

    /// 把专注时长写进计时器：连钉住的长度一起清掉，面板上的数字马上跟着变。
    public static func applying(_ minutes: Int, to state: TimerState) -> TimerState {
        var next = state
        next.work = minutes
        next.duration = nil
        return next
    }
}

// MARK: - 跳过

public extension FocusCycle {
    /// 跳过这一段：专注跳到休息（不算完成，停在开始前），休息、长休息跳回专注（长休息后
    /// 轮次从头数）。跳过的专注不记番茄。
    static func skipped(_ state: TimerState) -> TimerState {
        var next = state
        next.deadline = nil
        next.paused = nil
        next.duration = nil
        switch state.phase {
        case .focus:
            next.phase = .rest
        case .rest:
            next.phase = .focus
        case .long:
            next.phase = .focus
            next.completed = 0
        }
        return next
    }
}

// MARK: - 结束提示音

/// 专注结束、休息结束时响的提示音：用 macOS 自带的系统声音（/System/Library/Sounds），
/// 不打包音频。存的值空是默认，`none` 是不响，认不出的名字退回默认。
public enum FocusEndSound {
    public static let none = "none"
    public static let system = ["Hero", "Glass", "Ping", "Purr", "Submarine", "Funk", "Blow", "Bottle",
                                "Pop", "Tink", "Morse", "Sosumi"]
    public static let defaultFocusEnd = "Hero"
    public static let defaultRestEnd = "Glass"
    public static let repeatsRange = 1...5

    /// 设置里可选的：系统声音，最后是「不响」。
    public static var choices: [String] { system + [Self.none] }

    public static func resolve(_ raw: String, fallback: String) -> String {
        if raw == Self.none { return Self.none }
        return system.contains(raw) ? raw : fallback
    }

    public static func focusEnd(_ state: TimerState) -> String {
        resolve(state.focusEndSound, fallback: defaultFocusEnd)
    }

    public static func restEnd(_ state: TimerState) -> String {
        resolve(state.restEndSound, fallback: defaultRestEnd)
    }

    /// `state` 这一段到点时响哪个：专注到点是专注结束的声音，休息、长休息到点是休息结束的。
    public static func ending(_ state: TimerState) -> String {
        state.phase == .focus ? focusEnd(state) : restEnd(state)
    }

    public static func repeats(_ state: TimerState) -> Int {
        clampRepeats(state.soundRepeats)
    }

    public static func clampRepeats(_ value: Int) -> Int {
        min(repeatsRange.upperBound, max(repeatsRange.lowerBound, value))
    }

    public static func title(_ name: String) -> String {
        switch name {
        case Self.none: tr("不响")
        case "Glass": tr("玻璃")
        case "Hero": tr("英雄")
        case "Ping": tr("乒")
        case "Purr": tr("呼噜")
        case "Submarine": tr("潜水艇")
        case "Funk": tr("放克")
        case "Blow": tr("吹气")
        case "Bottle": tr("瓶子")
        case "Pop": tr("啵")
        case "Tink": tr("叮")
        case "Morse": tr("摩尔斯")
        default: name
        }
    }
}

// MARK: - 结束通知

/// 一个环节到点时的本机通知文字。`ended` 是到点那一段，`next` 是接下来的。
public enum FocusEndNotice {
    public static func title(ended: TimerState) -> String {
        ended.phase == .focus ? tr("专注完成") : tr("休息结束")
    }

    public static func body(ended: TimerState, next: TimerState) -> String {
        guard ended.phase == .focus else { return tr("准备好开始下一轮专注了吗？") }
        let focused = max(1, Int(((ended.duration ?? Double(ended.work * 60)) / 60).rounded()))
        let rest = max(1, next.minutes)
        return tr("已专注 \(focused) 分钟，起来活动一下，休息 \(rest) 分钟。")
    }
}
