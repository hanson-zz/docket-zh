import Foundation

/// 锁定扩展栏：菜单栏、扩展栏右键和设置页共用同一个设置。
extension AppState {
    var shelfLocked: Bool { state.customDock.locked }

    func setShelfLocked(_ locked: Bool) {
        guard state.customDock.locked != locked else { return }
        state.customDock.locked = locked
    }

    /// 某项操作现在能不能做。见 `ShelfLock`。
    func shelfAllows(_ action: ShelfLockAction) -> Bool {
        ShelfLock.allows(action, locked: state.customDock.locked)
    }
}
