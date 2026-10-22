import Foundation

/// 系统程序坞 `autohide-delay` 的值：原本没有这个键，或者几秒。
///
/// “没有这个键”单独一种，因为还原时要删键而不是写 0：写 0 会让程序坞
/// 一碰边就弹，和系统默认的那一点点延迟不一样。
public enum DockAutoHideDelay: Hashable, Sendable {
    case absent
    case seconds(Double)

    /// 从偏好里读出来的值换成延迟。数字（含整数）和能读成数字的字符串都认，
    /// 没有这个键或者认不出来时当作没有。
    public init(preference value: Any?) {
        if let number = value as? NSNumber {
            self = .seconds(number.doubleValue)
        } else if let text = value as? String, let seconds = Double(text) {
            self = .seconds(seconds)
        } else {
            self = .absent
        }
    }
}

/// “替换并自动隐藏”改程序坞之前记下的原值，存在 `PersistedState.hiddenDockAutoHide`。
///
/// 老版本只存了一个 Bool（自动隐藏的原值），那时也没碰过延迟，所以读到
/// 老格式时 `delay` 是 nil：还原时不动延迟。
public struct HiddenDockOriginal: Codable, Hashable, Sendable {
    /// 自动隐藏原来开没开。
    public var autoHide: Bool
    /// `autohide-delay` 原来的样子；nil 是没记过（老状态），还原时不碰。
    public var delay: DockAutoHideDelay?

    public init(autoHide: Bool, delay: DockAutoHideDelay?) {
        self.autoHide = autoHide
        self.delay = delay
    }

    private enum CodingKeys: String, CodingKey {
        case autoHide, delayRecorded, delay
    }

    public init(from decoder: any Decoder) throws {
        // 老格式：整个值就是一个 Bool。
        if let single = try? decoder.singleValueContainer(), let old = try? single.decode(Bool.self) {
            autoHide = old
            delay = nil
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        autoHide = try c.decode(Bool.self, forKey: .autoHide)
        if (try? c.decodeIfPresent(Bool.self, forKey: .delayRecorded)) == true {
            if let seconds = try? c.decodeIfPresent(Double.self, forKey: .delay) {
                delay = .seconds(seconds)
            } else {
                delay = .absent
            }
        } else {
            delay = nil
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(autoHide, forKey: .autoHide)
        try c.encode(delay != nil, forKey: .delayRecorded)
        if case .seconds(let seconds) = delay {
            try c.encode(seconds, forKey: .delay)
        }
    }
}

/// “替换并自动隐藏”时把系统程序坞设成自动隐藏且不再弹出，离开时还原。
///
/// 这一档的扩展栏自己藏起来、不借保留区，系统程序坞如果还按用户原来的设置
/// 常驻，扩展栏一收起就露出它，等于没替换。光开自动隐藏也不够：指针碰到
/// 屏幕边缘时程序坞照样弹出来，和扩展栏抢同一条边。所以进入这一档时把
/// 程序坞的 `autohide` 写成开、`autohide-delay` 写成 `hiddenDelay`（很久，
/// 实际上不再弹出），`autohide-time-modifier` 不动；两项原值一起记进状态
/// （`PersistedState.hiddenDockAutoHide`）。离开这一档、码头正常退出、或者
/// 下次启动发现上次没还原（崩溃、强制退出），都按记下的原值写回，原本没有
/// 延迟这个键就删掉。两项一起写，程序坞只重启一次。
///
/// 和借保留区（`StrutMode`，`borrowedDockPrefs`）是两件事：两边都改程序坞
/// 的 `autohide`，谁先记下原值谁说了算。借着保留区时不动手，等它还完再记，
/// 免得把借保留区写进去的“关”当成用户的原值。
public enum SystemDockHiding {

    /// 这一档里写给程序坞的 `autohide-delay`（秒）。足够久，指针停在边上
    /// 程序坞也不会出来；⌥⌘D 切换自动隐藏不受它影响。
    public static let hiddenDelay: Double = 1000

    /// 程序坞现在的样子，只看这两项。
    public struct Current: Equatable, Sendable {
        public var autoHide: Bool
        public var delay: DockAutoHideDelay

        public init(autoHide: Bool, delay: DockAutoHideDelay) {
            self.autoHide = autoHide
            self.delay = delay
        }
    }

    /// 要写给程序坞的改动。nil 的项不动；`delay` 为 `.absent` 是删键。
    /// 不为空时写完重启一次程序坞。
    public struct Changes: Equatable, Sendable {
        public var autoHide: Bool?
        public var delay: DockAutoHideDelay?

        public init(autoHide: Bool? = nil, delay: DockAutoHideDelay? = nil) {
            self.autoHide = autoHide
            self.delay = delay
        }

        public var isEmpty: Bool { autoHide == nil && delay == nil }
    }

    /// 下一步要做的事。
    public enum Step: Equatable, Sendable {
        /// 什么都不做。
        case none
        /// 先记下原值 `original`，再写 `changes`（原本就是这样时为空，
        /// 只记不写，不必重启程序坞）。
        case hide(original: HiddenDockOriginal, changes: Changes)
        /// 写回 `changes` 再清掉记录；为空时现在已经是原值，只清记录。
        case restore(changes: Changes)
    }

    /// 现在这一档要不要让系统程序坞自动隐藏：只有“替换并自动隐藏”要。
    /// 浮动、并排、置顶、固定、普通替换和只用系统程序坞都不要。
    public static func wanted(setup: DockSetup, settings: CustomDockSettings) -> Bool {
        ShelfPlacement.mode(setup: setup, settings: settings) == .replaceAutoHide
    }

    /// 根据要不要、有没有记录和程序坞现在的样子，决定下一步。
    ///
    /// - Parameters:
    ///   - wanted: `wanted(setup:settings:)` 的结果。
    ///   - recorded: 已经记下的原值，nil 是没改过程序坞（不欠还原）。
    ///   - borrowingStrut: 借着系统程序坞的保留区（`borrowedDockPrefs` 不为 nil）。
    ///   - current: 系统程序坞现在的自动隐藏和延迟。
    ///
    /// 已经记下、仍然要隐藏时不再动，也不覆盖原值：用户中途自己在系统设置里
    /// 改回常驻或用 ⌥⌘D 切换，不跟他抢，退出时照样还原成最初的原值。唯一
    /// 例外是老状态（只记了自动隐藏、没记延迟）：补记延迟原值并写上延迟。
    public static func step(wanted: Bool, recorded: HiddenDockOriginal?,
                            borrowingStrut: Bool, current: Current) -> Step {
        if let original = recorded {
            if wanted { return upgrade(original, current: current) }
            return .restore(changes: restoreChanges(original, current: current))
        }
        guard wanted, !borrowingStrut else { return .none }
        return .hide(original: HiddenDockOriginal(autoHide: current.autoHide, delay: current.delay),
                     changes: Changes(autoHide: current.autoHide ? nil : true,
                                      delay: delayChange(current.delay)))
    }

    /// 启动时：上次留下了记录、而现在不在这一档，说明上次没来得及还原，
    /// 现在还。仍在这一档就留着，程序坞本来就该是隐藏的（老状态补上延迟）。
    public static func launchStep(wanted: Bool, recorded: HiddenDockOriginal?, current: Current) -> Step {
        guard let original = recorded else { return .none }
        if wanted { return upgrade(original, current: current) }
        return .restore(changes: restoreChanges(original, current: current))
    }

    /// 退出时：有记录就还原，不管现在是哪一档。
    public static func quitStep(recorded: HiddenDockOriginal?, current: Current) -> Step {
        guard let original = recorded else { return .none }
        return .restore(changes: restoreChanges(original, current: current))
    }

    /// 这一档里扩展栏顶替了系统程序坞：程序坞虽然在同一条边上自动隐藏，扩展栏
    /// 不再为它抬高（“为系统程序坞留出空间”），指针碰到边时也不给它让位
    /// （“为系统程序坞让位”），不然扩展栏永远滑不出来。其他方式照旧。
    public static func shelfIgnoresSystemDock(setup: DockSetup, settings: CustomDockSettings) -> Bool {
        wanted(setup: setup, settings: settings)
    }

    // MARK: 内部

    /// 已经是 `hiddenDelay` 就不写。
    private static func delayChange(_ current: DockAutoHideDelay) -> DockAutoHideDelay? {
        current == .seconds(hiddenDelay) ? nil : .seconds(hiddenDelay)
    }

    /// 仍在这一档：记过延迟就什么都不做；老状态只补延迟，自动隐藏的原值照旧。
    private static func upgrade(_ original: HiddenDockOriginal, current: Current) -> Step {
        guard original.delay == nil else { return .none }
        var upgraded = original
        upgraded.delay = current.delay
        return .hide(original: upgraded, changes: Changes(delay: delayChange(current.delay)))
    }

    /// 和现在不一样的项才写回；没记过延迟（老状态）就不碰延迟。
    private static func restoreChanges(_ original: HiddenDockOriginal, current: Current) -> Changes {
        var changes = Changes()
        if current.autoHide != original.autoHide { changes.autoHide = original.autoHide }
        if let delay = original.delay, delay != current.delay { changes.delay = delay }
        return changes
    }
}
