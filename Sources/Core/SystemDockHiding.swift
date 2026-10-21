import Foundation

/// “替换并自动隐藏”时把系统程序坞也设成自动隐藏，离开时还原。
///
/// 这一档的扩展栏自己藏起来、不借保留区，系统程序坞如果还按用户原来的设置
/// 常驻，扩展栏一收起就露出它，等于没替换。所以进入这一档时把程序坞的
/// `autohide` 写成开，并把原值记进状态（`PersistedState.hiddenDockAutoHide`）；
/// 离开这一档、码头正常退出、或者下次启动发现上次没还原（崩溃、强制退出），
/// 都按记下的原值写回。
///
/// 和借保留区（`StrutMode`，`borrowedDockPrefs`）是两件事：两边都改程序坞
/// 的 `autohide`，谁先记下原值谁说了算。借着保留区时不动手，等它还完再记，
/// 免得把借保留区写进去的“关”当成用户的原值。
public enum SystemDockHiding {

    /// 下一步要做的事。
    public enum Step: Equatable, Sendable {
        /// 什么都不做。
        case none
        /// 记下原值 `original`；`write` 为真时还要把程序坞改成自动隐藏并重启它
        /// （原本就是自动隐藏时只记不写，不必重启程序坞）。
        case hide(original: Bool, write: Bool)
        /// 把程序坞的自动隐藏改回 `original` 并清掉记录；`write` 为假时现在
        /// 已经是原值，只清记录。
        case restore(original: Bool, write: Bool)
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
    ///   - systemAutoHide: 系统程序坞现在是不是自动隐藏。
    ///
    /// 已经记下、仍然要隐藏时不再动：用户中途自己在系统设置里改回常驻，
    /// 不跟他抢，退出时照样还原成最初的原值。
    public static func step(wanted: Bool, recorded: Bool?,
                            borrowingStrut: Bool, systemAutoHide: Bool) -> Step {
        if let original = recorded {
            if wanted { return .none }
            return .restore(original: original, write: systemAutoHide != original)
        }
        guard wanted, !borrowingStrut else { return .none }
        return .hide(original: systemAutoHide, write: !systemAutoHide)
    }

    /// 启动时：上次留下了记录、而现在不在这一档，说明上次没来得及还原，
    /// 现在还。仍在这一档就留着，程序坞本来就该是隐藏的。
    public static func launchStep(wanted: Bool, recorded: Bool?, systemAutoHide: Bool) -> Step {
        guard let original = recorded, !wanted else { return .none }
        return .restore(original: original, write: systemAutoHide != original)
    }

    /// 退出时：有记录就还原，不管现在是哪一档。
    public static func quitStep(recorded: Bool?, systemAutoHide: Bool) -> Step {
        guard let original = recorded else { return .none }
        return .restore(original: original, write: systemAutoHide != original)
    }

    /// 这一档里扩展栏顶替了系统程序坞：程序坞虽然在同一条边上自动隐藏，扩展栏
    /// 不再为它抬高（“为系统程序坞留出空间”），指针碰到边时也不给它让位
    /// （“为系统程序坞让位”），不然扩展栏永远滑不出来。其他方式照旧。
    public static func shelfIgnoresSystemDock(setup: DockSetup, settings: CustomDockSettings) -> Bool {
        wanted(setup: setup, settings: settings)
    }
}
