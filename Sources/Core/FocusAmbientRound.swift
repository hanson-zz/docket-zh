import Foundation

// 专注环境音一轮里的决定：什么时候放、换、停，什么时候让开、为什么让开，面板上那一行怎么写。
// 全是纯逻辑，`FocusAmbientDriver` 每秒照着走一步，`AmbientPlayer` 按 `AmbientOwner` 分清是谁在放。

/// 环境音播放器现在是谁放起来的。
public enum AmbientOwner: String, Sendable {
    /// 环境音小组件（卡片、面板、桌面卡片、右键换组合）。
    case widget
    /// 专注计时自动放的。
    case focus
    /// 专注面板里选声音时的几秒试听。
    case preview

    /// 小组件出现在屏幕上时会把自己存的组合同步给播放器（`AmbientPlayer.prime`）。
    /// 正在放专注或试听的声音时只记下，不去改：条件显示的环境音小组件正是因为
    /// 「正在播放」才出现的，一出现就把声音换成自己的组合（没选声音时直接停掉），
    /// 专注那一轮就被当成「用户换了」让掉了。
    public static func primeChangesPlayback(owner: AmbientOwner, playing: Bool) -> Bool {
        !playing || owner == .widget
    }

    /// 专注开始时，正在放的声音算不算「用户自己的组合」（要让开）。试听不算，直接接过来。
    public static func blocksFocus(owner: AmbientOwner, playing: Bool) -> Bool {
        playing && owner == .widget
    }
}

/// 这一轮专注没放环境音的原因，面板上用一行小字说明。
public enum FocusAmbientSkip: String, Sendable, CaseIterable {
    /// 环境音小组件正在放用户自己的组合，不去抢。
    case widgetPlaying
    /// 专注中用户手动停了或换了声音，这一轮不再放回来。
    case userTookOver
    /// 声音设备起不来（没有输出设备、被别的程序独占），这一轮不再每秒重试。
    case audioFailed

    public var note: String {
        switch self {
        case .widgetPlaying: tr("环境音小组件正在播放，这一轮不打断它")
        case .userTookOver: tr("这一轮你手动停了或换了声音，下一轮再自动播放")
        case .audioFailed: tr("声音设备没准备好，这一轮先不放，重新选一次声音可再试")
        }
    }
}

/// 一轮专注里环境音这一路的状态机。`FocusAmbientDriver` 每秒调一次 `step`，照返回的动作去做，
/// 做完用 `started` / `failed` 报回结果。
public struct FocusAmbientRound: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case none
        /// 淡入开始放这种声音。
        case start(AmbientSound)
        /// 已经在放：换成这种声音或这个音量。
        case retune(AmbientSound, volume: Int)
        /// 淡出停下（只停自己放起来的）。
        case stop
    }

    /// 我们放起来、现在还在放的声音。
    public private(set) var playing: AmbientSound?
    public private(set) var volume: Int = FocusAmbient.defaultVolume
    /// 这一轮让开了，为什么。
    public private(set) var skip: FocusAmbientSkip?
    /// 让开时面板上选的是什么（`TimerState.ambient`）。用户之后在专注面板里改选别的，
    /// 算明确要放，让开作废，而且不再让给小组件。
    private var skippedChoice = ""
    private var insist = false

    public init() {}

    /// - Parameters:
    ///   - wanted: `FocusAmbient.wanted`，nil 是现在不该放。
    ///   - choice: 面板上选的原始值（`TimerState.ambient`）。
    ///   - level: 面板上的音量。
    ///   - ours: 播放器正在放、是专注放的、放的正是 `playing` 那一种。
    ///   - blocked: 播放器正在放环境音小组件的组合（`AmbientOwner.blocksFocus`）。
    public mutating func step(wanted: AmbientSound?, choice: String, level: Int,
                              ours: Bool, blocked: Bool) -> Action {
        guard let wanted else {
            let action: Action = playing != nil && ours ? .stop : .none
            self = FocusAmbientRound()
            return action
        }
        if skip != nil {
            guard choice != skippedChoice else { return .none }
            // 用户在专注面板里改选了：明确要放，让开作废。
            skip = nil
            skippedChoice = ""
            insist = true
        }
        if let current = playing {
            guard ours else {
                playing = nil
                yield(.userTookOver, choice: choice)
                return .none
            }
            guard current != wanted || level != volume else { return .none }
            playing = wanted
            volume = level
            return .retune(wanted, volume: level)
        }
        if blocked, !insist {
            yield(.widgetPlaying, choice: choice)
            return .none
        }
        return .start(wanted)
    }

    /// `.start` 放起来了。
    public mutating func started(_ sound: AmbientSound, volume level: Int) {
        playing = sound
        volume = level
    }

    /// `.start` 没放起来（音频引擎起不来）。
    public mutating func failed(choice: String) {
        playing = nil
        yield(.audioFailed, choice: choice)
    }

    private mutating func yield(_ reason: FocusAmbientSkip, choice: String) {
        skip = reason
        skippedChoice = choice
    }
}

/// 专注面板环境音那一行下面的一行 13pt 小字：现在是什么状态。
public enum FocusAmbientStatus {
    /// - Parameters:
    ///   - chosen: 选了声音或电台（不是「不播放」）。
    ///   - running: 专注计时在走（`FocusCycle.isRunning`）。
    ///   - wanted: 现在该放（休息且「休息时声音停下」时为 false）。
    ///   - playing: 选的声音或电台正在放。
    ///   - skip: 这一轮让开的原因。
    public static func text(chosen: Bool, running: Bool, wanted: Bool, playing: Bool,
                            skip: FocusAmbientSkip?) -> String {
        guard chosen else { return tr("选一种声音，开始专注时自动播放") }
        if running, let skip { return skip.note }
        if playing { return tr("正在播放") }
        if running, !wanted { return tr("休息时声音停下，回到专注再放") }
        return tr("开始专注时自动播放")
    }
}

public extension FocusAmbient {
    /// 新用户第一次打开专注计时时默认选的声音。
    ///
    /// 选雨声：一听就知道是「环境音」，不会被当成风扇或电流声（棕噪、粉噪容易被误会），
    /// 中频为主、没有明显的节奏（海浪有起伏、篝火有噼啪，专注时容易被吸引注意），
    /// 而且是最多人用来专注的背景声。老用户存过的选择（包括「不播放」）不动。
    static let firstRunSound: AmbientSound = .rain
}

public extension TimerState {
    /// 全新安装时的专注计时：环境音默认 `FocusAmbient.firstRunSound`，其余同 `TimerState()`。
    static var firstRun: TimerState {
        var state = TimerState()
        state.ambient = FocusAmbient.firstRunSound.rawValue
        return state
    }
}
