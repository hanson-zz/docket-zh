import Foundation

// MARK: - 小熊猫六状态
//
// 面板里的小熊猫不再各自写死图名：面板只说「现在发生了什么」（AI 在生成、待办勾完一条、
// 喝水到提醒时间了），`PandaStateResolver` 把它解析成六种状态之一，再解析成图名。
// 首选 Resources/PandaStates/panda-state-<状态>.png（按同一母版画的坐姿全身，底部锚点统一），
// 缺图时回退原来的小熊猫素材，界面不会空一块。
//
// 这里只有纯逻辑（不碰 SwiftUI 和 AppKit），好写测试；画法在 Widgets/PandaStateView.swift。

/// 小熊猫的六种核心状态。
public enum PandaState: String, CaseIterable, Sendable {
    /// 待机：正面微笑，偶尔眨眼。
    case idle
    /// 思考：AI 请求发出后等回答、资料处理中。
    case thinking
    /// 探头：只露头和两只扒边的爪，刘海出现、新消息、轻量引导。
    case peek
    /// 提醒：轻举一爪，重要天气、到喝水时间、出错。
    case alert
    /// 完成：举爪庆祝，回答完、任务完成、达标。
    case done
    /// 休息：闭眼放松，空列表、专注休息。
    case rest

    /// 同时有几件事想让小熊猫表态时谁说了算：提醒最高，其次思考（正在干活不被庆祝打断），
    /// 再是完成、探头、待机，休息最低。
    public var priority: Int {
        switch self {
        case .alert: 5
        case .thinking: 4
        case .done: 3
        case .peek: 2
        case .idle: 1
        case .rest: 0
        }
    }

    /// 完成、提醒是「单次动作」：切进来时轻轻动一下（0.6 到 1.2 秒，不循环）。
    public var isOneShot: Bool { self == .done || self == .alert }
}

/// 六状态之外的场景扩展动作（规范里「饮水中」不算核心状态）：照旧用原来那几张图。
public enum PandaExtra: String, CaseIterable, Sendable {
    /// 抱竹筒举到嘴边喝一口（喝水卡片点 +、天气的紫外线 / 补水建议）。
    case drink
    /// 抱竹筒小口喝着（喝水 30% 到 70%）。
    case sip
    /// 还渴着（喝水 0 到 30%）。
    case thirsty
    /// 渴成骷髅（5 小时没喝）。
    case parched

    /// 扩展动作用的现成图。
    public var imageName: String {
        switch self {
        case .drink: "pet-panda-drink"
        case .sip: "pet-panda-sip"
        case .thirsty: "pet-panda-hungry"
        case .parched: "WaterPanda-skeleton"
        }
    }
}

/// 场景图：和六状态同一母版、同画布、同底部锚点的九张（Resources/PandaStates/panda-scene-<名>.png）。
/// 天气（晴、雨雪、冷、热）、喝水、待办记下、录音、收音机在听、AI 助手输入与生成中用；缺图时回退待机。
public enum PandaScene: String, CaseIterable, Sendable {
    /// 晴天。
    case sunny
    /// 下雨下雪。
    case rain
    /// 冷（体感 5℃ 及以下）。
    case cold
    /// 热（30℃ 及以上）。
    case hot
    /// 抱竹筒喝水（喝水点 +、该喝水了、天气的紫外线 / 补水建议）。
    case drink
    /// 拿笔记下（待办添加成功）。
    case write
    /// 戴着耳机对着麦克风（正在录音；收音机正在出声时也用它，当「在听电台」）。
    case record
    /// 对着笔记本打字（AI 助手输入框里有字、还没提交）。
    case aiInput = "ai-input"
    /// 抬头等回答，头顶三个点的气泡（AI 助手提交后到答完之前）。
    case aiGenerating = "ai-generating"

    public var imageName: String { "panda-scene-\(rawValue)" }
}

/// 面板这一刻让小熊猫摆的样子：六状态之一、一个场景扩展动作，或一张场景图。
public enum PandaPose: Equatable, Sendable {
    case state(PandaState)
    case extra(PandaExtra)
    case scene(PandaScene)

    /// 扩展动作和场景图按待机算（排优先级、算动效时）。
    public var state: PandaState {
        switch self {
        case .state(let state): state
        case .extra, .scene: .idle
        }
    }
}

/// 一次短暂的表态（勾完一条的「完成」、出错的「提醒」）：从 `started` 起到 `until` 为止
/// 盖在面板的常态上，过了就回常态。`started` 不变时界面不重播动作（连续勾选合并）。
public struct PandaPulse: Equatable, Sendable {
    public var state: PandaState
    public var started: Date
    public var until: Date
    /// 这次表态画哪张场景图（待办记下时的「记下」）；nil 时画 `state` 的图。优先级仍按 `state` 算。
    public var scene: PandaScene?

    public init(state: PandaState, started: Date, until: Date, scene: PandaScene? = nil) {
        self.state = state
        self.started = started
        self.until = until
        self.scene = scene
    }

    /// 这次表态要画的样子。
    public var pose: PandaPose { scene.map(PandaPose.scene) ?? .state(state) }

    public func isActive(at now: Date) -> Bool { now >= started && now < until }
}

/// 连续庆祝的合并和冷却：冷却时间里再来一次不重播，只把这一次表态往后延。
public struct PandaCelebration: Equatable, Sendable {
    public private(set) var pulse: PandaPulse?

    public init(pulse: PandaPulse? = nil) { self.pulse = pulse }

    /// 记一次庆祝（或提醒），返回现在该显示的表态。
    ///
    /// - 上一次开始到现在不到 `cooldown`、而且还在显示：合并，`started` 不变（不重播），
    ///   `until` 延到这一次的 `hold` 之后；状态取优先级高的那个。
    /// - 否则重新开始一次。
    @discardableResult
    public mutating func register(_ state: PandaState = .done, scene: PandaScene? = nil, at now: Date,
                                  hold: TimeInterval = PandaMotion.doneHold,
                                  cooldown: TimeInterval = PandaMotion.celebrationCooldown) -> PandaPulse {
        let until = now.addingTimeInterval(max(0, hold))
        if var current = pulse, current.isActive(at: now), now.timeIntervalSince(current.started) < cooldown {
            current.until = max(current.until, until)
            if state.priority > current.state.priority {
                current.state = state
                current.scene = scene
            }
            pulse = current
            return current
        }
        let fresh = PandaPulse(state: state, started: now, until: until, scene: scene)
        pulse = fresh
        return fresh
    }

    /// 清掉（比如撤销了刚才那一步）。
    public mutating func reset() { pulse = nil }
}

/// 动效的统一节奏和尺寸。界面都从这里取，不在各个面板里各写各的数。
public enum PandaMotion {
    /// 状态之间淡入淡出的时长（规范 0.25 到 0.45 秒）。
    public static let transition: TimeInterval = 0.32
    /// 完成、提醒单次动作的时长（规范 0.6 到 1.2 秒，不循环）。
    public static let oneShot: TimeInterval = 0.9
    /// 「完成」停留多久回常态。
    public static let doneHold: TimeInterval = 2.4
    /// 出错的「提醒」停留多久回常态（面板顶上那只；结果卡片上失败一直显示提醒）。
    public static let alertHold: TimeInterval = 6
    /// 连续勾选：这么久里只庆祝一次。
    public static let celebrationCooldown: TimeInterval = 3
    /// 待机偶尔眨眼的间隔范围（有眨眼图时才眨）。
    public static let blinkInterval: ClosedRange<TimeInterval> = 10...20
    /// 一次眨眼闭眼多久。
    public static let blinkDuration: TimeInterval = 0.16

    /// 切换动画时长；减弱动态效果时 0（直接换静帧）。
    public static func transitionDuration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? 0 : transition
    }

    /// 切进这个状态时要不要播单次动作；减弱动态效果时一律不播。
    public static func playsOneShot(_ state: PandaState, reduceMotion: Bool) -> Bool {
        !reduceMotion && state.isOneShot
    }

    /// 待机时要不要眨眼：减弱动态效果、不是待机、没有眨眼图时都不眨。
    public static func blinks(_ state: PandaState, reduceMotion: Bool, hasBlinkFrame: Bool) -> Bool {
        !reduceMotion && state == .idle && hasBlinkFrame
    }

    /// 下一次眨眼前等几秒：`unit` 是 0...1 的随机数（测试里给定值）。
    public static func blinkDelay(unit: Double) -> TimeInterval {
        let u = min(max(unit.isFinite ? unit : 0, 0), 1)
        return blinkInterval.lowerBound + (blinkInterval.upperBound - blinkInterval.lowerBound) * u
    }
}

/// 统一尺寸：几种常用的高度（点）。图是方形画布，按高度画、底部对齐。
public enum PandaStage: CGFloat, CaseIterable, Sendable {
    /// 提醒卡一行、设置页顶栏。
    case mini = 24
    /// 面板顶栏、进度环里。
    case small = 34
    /// 天气告警卡、对话头像。
    case regular = 40
    /// 卡片里的空状态。
    case medium = 48
    /// 面板里的空状态。
    case large = 72
    /// 「今天清空啦」。
    case hero = 96

    public var side: CGFloat { rawValue }

    /// 底部锚点：全身图脚底在画布 98.7% 处，探头图下沿切到画布底。
    public static func baseline(_ state: PandaState) -> CGFloat {
        state == .peek ? 1 : 0.987
    }
}

public enum PandaStateResolver {
    /// 六状态正式素材的目录前缀：Resources/PandaStates/panda-state-<状态>.png。
    public static func preferredName(_ state: PandaState) -> String {
        "panda-state-\(state.rawValue)"
    }

    /// 待机眨眼用的那一张（可选，没有就不眨）。
    public static let blinkName = "panda-state-idle-blink"

    /// 缺正式素材时回退的现成图（都是小熊猫，选单帧做静态）。
    public static func fallbackNames(_ state: PandaState) -> [String] {
        switch state {
        case .idle: ["pet-panda-idle"]
        case .thinking: ["pet-sprite-lookup-4", "pet-panda-idle"]
        case .peek: ["notch-panda-peek", "desk-panda-peek", "pet-panda-idle"]
        case .alert: ["pet-sprite-front-wave-1", "pet-panda-idle"]
        case .done: ["pet-panda-cheer"]
        case .rest: ["pet-panda-rest", "pet-sprite-fallasleep-6"]
        }
    }

    /// 按顺序试的图名：先正式素材，再回退。
    public static func candidates(_ state: PandaState) -> [String] {
        [preferredName(state)] + fallbackNames(state)
    }

    public static func candidates(_ pose: PandaPose) -> [String] {
        switch pose {
        case .state(let state): candidates(state)
        case .extra(let extra): [extra.imageName] + candidates(.idle)
        case .scene(let scene): [scene.imageName] + candidates(.idle)
        }
    }

    /// 这张图是 Resources/PandaStates 里的正式素材（六状态或场景图），不是老图。
    public static func isFormalArt(_ name: String) -> Bool {
        name.hasPrefix("panda-state-") || name.hasPrefix("panda-scene-")
    }

    /// 第一张存在的图名；一张都没有时 nil（界面画占位符号）。
    public static func imageName(_ pose: PandaPose, exists: (String) -> Bool) -> String? {
        candidates(pose).first(where: exists)
    }

    public static func imageName(_ state: PandaState, exists: (String) -> Bool) -> String? {
        imageName(.state(state), exists: exists)
    }

    /// 常态加上一次短暂表态：表态还在显示、而且优先级不低于常态时用表态，否则用常态。
    public static func resolve(base: PandaPose, pulse: PandaPulse?, now: Date) -> PandaPose {
        guard let pulse, pulse.isActive(at: now), pulse.state.priority >= base.state.priority else { return base }
        return pulse.pose
    }

    // MARK: 老图名迁移

    /// 面板里原来直接写的小熊猫静态图对应哪种状态：站着待机、欢呼完成、歇着休息，
    /// 化了、饿了、病了（提醒、状态差）算提醒。喝水、吃东西、骷髅这些场景扩展动作，
    /// 电子宠物、桌面伙伴、专注、刘海的专属素材都不在这里，照旧用原图。
    public static func legacyState(_ name: String) -> PandaState? {
        switch name {
        case "pet-panda-idle": .idle
        case "pet-panda-cheer": .done
        case "pet-panda-rest": .rest
        case "pet-panda-melt", "pet-panda-hungry", "pet-panda-sick": .alert
        default: nil
        }
    }

    /// 面板拿老图名来要图时实际画哪张：能对应到六状态、而且正式素材在，就换成正式素材；
    /// 否则原样返回（老图照旧，缺图回退）。
    public static func migratedName(_ name: String, exists: (String) -> Bool) -> String {
        guard let state = legacyState(name) else { return name }
        let preferred = preferredName(state)
        return exists(preferred) ? preferred : name
    }

    // MARK: 各面板：事件 → 状态

    /// 天气：下雨下雪（不管是不是提醒级别）用雨雪场景图代替举爪；风大、空气差这类重要天气 alert；
    /// 只剩紫外线（补水、防晒）时用喝水场景图；其余平常天按现在的天气给场景（`weatherScene`），
    /// 没有天气数据时 idle。
    public static func weather(_ kind: WeatherTips.Tip.Kind?, alertStyle: Bool,
                               conditions: WeatherSceneInput? = nil) -> PandaPose {
        if let kind {
            switch kind {
            case .rain: return .scene(.rain)
            case .wind, .air: if alertStyle { return .state(.alert) }
            case .uv: return .scene(.drink)
            case .cooling, .swing, .clothing: break
            }
        }
        return conditions.flatMap(weatherScene).map(PandaPose.scene) ?? .state(.idle)
    }

    /// 体感到这么低（℃）算冷。
    public static let coldApparentC: Double = 5
    /// 气温到这么高（℃）算热。
    public static let hotC: Double = 30

    /// 平常天按现在的天气挑场景图：正在下雨下雪 rain，体感 5℃ 及以下 cold，30℃ 及以上 hot，
    /// 白天晴 sunny，其他（多云、阴、雾、夜里）nil（待机）。哪项数据没有就跳过那项，不猜。
    public static func weatherScene(_ input: WeatherSceneInput) -> PandaScene? {
        if input.precipitating { return .rain }
        if let feels = input.apparentC ?? input.temperatureC, feels <= coldApparentC { return .cold }
        if let celsius = input.temperatureC ?? input.apparentC, celsius >= hotC { return .hot }
        if input.clearDay { return .sunny }
        return nil
    }

    /// AI：没问过 idle；思考、回答中 thinking；答完 done（短暂，靠表态）；失败 alert。
    /// 网页、App 方式码头拿不到回答，不假装在思考或已完成，一律 idle。
    public static func ai(_ phase: AIQuickResultPhase?, mode: AIOpenMode = .api) -> PandaState {
        guard mode == .api, let phase else { return .idle }
        switch phase {
        case .thinking, .answering: return .thinking
        case .done: return .done
        case .failed: return .alert
        }
    }

    /// AI 面板顶上那只的常态：正在思考、回答时 thinking，其余 idle（答完、失败靠短暂表态）。
    public static func aiBase(_ phase: AIQuickResultPhase?) -> PandaState {
        guard let phase, !phase.isFinished else { return .idle }
        return .thinking
    }

    /// AI 面板顶上那只的常态：提交后到答完用「生成中」场景图，输入框里有字用「输入」场景图，其余待机。
    /// 网页、App 方式没有阶段，只看有没有在输入。缺图时场景图回退待机。
    public static func aiPose(_ phase: AIQuickResultPhase?, typing: Bool) -> PandaPose {
        if let phase, !phase.isFinished { return .scene(.aiGenerating) }
        return typing ? .scene(.aiInput) : .state(.idle)
    }

    /// AI 扩展栏竖版卡片（状态陪伴卡）的小熊猫：和横版（坐着的待机）分开，平时对着笔记本
    /// （「输入」场景图），提交后到答完换「等回答」场景图。答完、出错仍靠短暂表态。
    public static func aiDockPose(_ phase: AIQuickResultPhase?) -> PandaPose {
        if let phase, !phase.isFinished { return .scene(.aiGenerating) }
        return .scene(.aiInput)
    }

    /// AI 一次回答收尾时该不该冒一个短暂表态（面板顶上那只，答完 done、失败 alert）。
    public static func aiPulse(from old: AIQuickResultPhase?, to new: AIQuickResultPhase?,
                               at now: Date) -> PandaPulse? {
        guard let new, new.isFinished, old.map({ !$0.isFinished }) ?? false else { return nil }
        switch new {
        case .done: return PandaPulse(state: .done, started: now, until: now.addingTimeInterval(PandaMotion.doneHold))
        case .failed: return PandaPulse(state: .alert, started: now, until: now.addingTimeInterval(PandaMotion.alertHold))
        default: return nil
        }
    }

    /// 待办的常态：一条都没有 rest；今天的都做完（清空）done；其余 idle。
    public static func todo(openCount: Int, todayCleared: Bool, totalCount: Int) -> PandaState {
        if todayCleared { return .done }
        if totalCount == 0 || openCount == 0 { return .rest }
        return .idle
    }

    /// 喝水（只给小熊猫；其他角色照旧用自己的图）：达标 done；提醒时段里很久没喝 alert
    /// （画的时候用喝水场景图，见 `waterImageName`）；快喝饱了 idle；刚点 + 喝一口用喝水场景图；
    /// 小口喝、还渴着、渴成骷髅保留原来的扩展动作。
    public static func water(_ look: WaterPose.Look) -> PandaPose {
        switch look {
        case .stage(.done): .state(.done)
        case .stage(.nearlyFull): .state(.idle)
        case .dry: .state(.alert)
        case .stage(.sipping): .extra(.sip)
        case .stage(.thirsty): .extra(.thirsty)
        case .gulp: .scene(.drink)
        case .parched: .extra(.parched)
        }
    }

    /// 喝水「渴了」（提醒该喝水）用喝水场景图；没有时用正式提醒图，再没有照旧口渴图
    /// （不突然换成举爪的回退帧）。点 + 喝一口那一下没有场景图时回退原来的抱竹筒图。
    public static func waterImageName(_ look: WaterPose.Look, exists: (String) -> Bool) -> String? {
        switch look {
        case .dry:
            return [PandaScene.drink.imageName, preferredName(.alert), PandaExtra.thirsty.imageName]
                .first(where: exists)
        case .gulp:
            return ([PandaScene.drink.imageName, PandaExtra.drink.imageName] + candidates(.idle))
                .first(where: exists)
        default:
            return imageName(water(look), exists: exists)
        }
    }

    /// 收音机（面板和卡片原来没有小熊猫的地方，只在播放时出现，不常驻）：
    /// 没在放（暂停、停止、添加小组件里的预览）nil，不画；连不上（重连中）alert；
    /// 刚连上还没出声、中途缓冲 thinking（等着，不是出错）；正在出声戴耳机听（录音场景图）。
    public static func radio(playing: Bool, buffering: Bool, problem: Bool) -> PandaPose? {
        guard playing else { return nil }
        if problem { return .state(.alert) }
        if buffering { return .state(.thinking) }
        return .scene(.record)
    }

    /// 专注只做状态兼容：等开始 idle、专注中 nil（用专注自己的动画：小熊猫爬竹竿、其他吉祥物的专注图）、
    /// 休息 rest、刚完成 done。面板和刘海小岛都按 `FocusMascotState.of` 取同一个样子，画哪只
    /// 仍由用户选的吉祥物决定（六只都保留，不改回小熊猫），这里只给出对应的六状态。
    public static func focus(_ state: FocusMascotState) -> PandaState? {
        switch state {
        case .idle: .idle
        case .focus: nil
        case .`break`: .rest
        case .done: .done
        }
    }
}

/// 天气场景要用的几项真实数据（面板手上有哪项给哪项，没有的留空）。
public struct WeatherSceneInput: Equatable, Sendable {
    public var temperatureC: Double?
    public var apparentC: Double?
    /// 现在正在下雨下雪（天气图标是雨雪，或这一小时已有降水）。
    public var precipitating: Bool
    /// 白天晴（不是多云、不是夜里）。
    public var clearDay: Bool

    public init(temperatureC: Double?, apparentC: Double?, precipitating: Bool, clearDay: Bool) {
        self.temperatureC = temperatureC
        self.apparentC = apparentC
        self.precipitating = precipitating
        self.clearDay = clearDay
    }

    /// 从面板手上的天气图标（SF Symbol 名）和这一小时降水量拼出来。
    public init(temperatureC: Double?, apparentC: Double?, symbolName: String?, precipitationMM: Double?) {
        let symbol = symbolName ?? ""
        let wet = ["rain", "drizzle", "snow", "sleet", "hail"].contains { symbol.contains($0) }
        let raining = (precipitationMM ?? 0) >= WeatherTips.rainingNowMM
        self.init(temperatureC: temperatureC, apparentC: apparentC, precipitating: wet || raining,
                  clearDay: symbol.hasPrefix("sun.max"))
    }
}
