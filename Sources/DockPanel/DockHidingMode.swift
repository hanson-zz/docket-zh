import AppKit

/// “替换并自动隐藏”时让系统程序坞也自动隐藏，离开时还原。
///
/// 判断全在 Core 的 `SystemDockHiding`，这里只按它给的步骤读写程序坞偏好、
/// 记下或清掉原值。原值存在 `PersistedState.hiddenDockAutoHide` 里，先记后写：
/// 写到一半崩了，下次启动照样知道该还原成什么。
@MainActor
public enum DockHidingMode {

    /// 设置变了（换了方式、借保留区还完了）之后调用。
    public static func sync(state: PersistedState, record: (Bool?) -> Void) {
        let step = SystemDockHiding.step(
            wanted: SystemDockHiding.wanted(setup: state.setup, settings: state.customDock),
            recorded: state.hiddenDockAutoHide,
            borrowingStrut: state.borrowedDockPrefs != nil,
            systemAutoHide: DockStrut.currentAutoHide())
        perform(step, record: record)
    }

    /// 启动时：上次没还原（崩溃、强制退出）又已经不在这一档，就还原。
    public static func repayIfOwed(state: PersistedState, record: (Bool?) -> Void) {
        perform(SystemDockHiding.launchStep(
            wanted: SystemDockHiding.wanted(setup: state.setup, settings: state.customDock),
            recorded: state.hiddenDockAutoHide,
            systemAutoHide: DockStrut.currentAutoHide()), record: record)
    }

    /// 退出时：有记录就还原，同步完成。
    public static func restoreOnQuit(state: PersistedState, record: (Bool?) -> Void) {
        perform(SystemDockHiding.quitStep(recorded: state.hiddenDockAutoHide,
                                          systemAutoHide: DockStrut.currentAutoHide()),
                record: record)
    }

    /// 返回是否真的改了程序坞，调用方据此重读程序坞设置。
    @discardableResult
    private static func perform(_ step: SystemDockHiding.Step, record: (Bool?) -> Void) -> Bool {
        switch step {
        case .none:
            return false
        case .hide(let original, let write):
            // 先记原值再写，中间断掉也能还原。
            record(original)
            if write { DockStrut.setAutoHideNow(true) }
            SystemDockSettings.shared.refresh()
            return write
        case .restore(let original, let write):
            if write { DockStrut.setAutoHideNow(original) }
            record(nil)
            SystemDockSettings.shared.refresh()
            return write
        }
    }
}
