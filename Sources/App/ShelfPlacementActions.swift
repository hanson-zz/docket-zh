import Foundation

/// 菜单栏 ▸ 位置 和设置页共用的写法：算好新的设置后一次写回，扩展栏、
/// 保留区和菜单都从 `state` 的同一次变化里读到。
extension AppState {
    /// 当前方式，菜单里打勾、一级菜单右侧灰字用。没有扩展栏时是 nil。
    var placementMode: ShelfPlacementMode? {
        ShelfPlacement.mode(setup: state.setup, settings: state.customDock)
    }

    func applyPlacement(_ mode: ShelfPlacementMode) {
        commitPlacement(ShelfPlacement.applying(mode, setup: state.setup,
                                                settings: state.customDock,
                                                currentScale: effectiveScale))
    }

    func applyPlacementEdge(_ edge: DockPosition) {
        commitPlacement(ShelfPlacement.applyingEdge(edge, setup: state.setup,
                                                    settings: state.customDock,
                                                    currentScale: effectiveScale))
    }

    func resetPlacement() {
        commitPlacement(ShelfPlacement.reset(setup: state.setup, settings: state.customDock,
                                             currentScale: effectiveScale))
    }

    /// 一次写回：分两次写，中间那一刻的组合（比如已经是替换、边还在顶部）
    /// 会先被扩展栏和保留区当真处理一遍。
    private func commitPlacement(_ result: (setup: DockSetup, settings: CustomDockSettings)) {
        var next = state
        next.setup = result.setup
        next.customDock = result.settings
        state = next
    }
}
