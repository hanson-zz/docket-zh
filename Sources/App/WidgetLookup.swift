import Foundation

/// 在所有布局里找、写小组件。
///
/// 卡片自己写配置时只在当前布局里找得到它；到点提醒的后台调度和弹出卡片上的
/// 按钮要动的小组件可能在文件夹里，也可能在别的布局里，所以从这里走：先找当前
/// 布局，再找其余的。
extension AppState {
    /// 每个布局里的每个小组件，文件夹里的也算。同一个 id 只出现一次（当前布局优先）。
    var allWidgets: [WidgetInstance] {
        var seen = Set<UUID>()
        var result: [WidgetInstance] = []
        let active = state.customDock.profileID
        let ordered = state.profiles.filter { $0.id == active } + state.profiles.filter { $0.id != active }
        for profile in ordered {
            for widget in DockItemTree.widgets(in: profile.items) where seen.insert(widget.id).inserted {
                result.append(widget)
            }
        }
        return result
    }

    /// 某个小组件现在存着的样子。
    func widgetAnywhere(_ id: UUID) -> WidgetInstance? {
        if let active = customProfile, let found = DockItemTree.widget(id, in: active.items) { return found }
        for profile in state.profiles {
            if let found = DockItemTree.widget(id, in: profile.items) { return found }
        }
        return nil
    }

    /// 正在播放上的卡带外观迁走（`CassetteMigration`）：每个布局都看，文件夹里的也算，
    /// 没有要迁的布局不写。
    func migrateCassetteLooks(unlocked: Bool) {
        for index in state.profiles.indices {
            if let items = CassetteMigration.migrated(state.profiles[index].items, unlocked: unlocked) {
                state.profiles[index].items = items
            }
        }
    }

    /// 写回一个小组件：当前布局里有就写那里，否则写到它所在的布局。
    func writeWidgetAnywhere(_ instance: WidgetInstance) {
        let active = state.customDock.profileID
        let order = state.profiles.indices.sorted { lhs, rhs in
            (state.profiles[lhs].id == active ? 0 : 1, lhs) < (state.profiles[rhs].id == active ? 0 : 1, rhs)
        }
        for index in order {
            if let items = DockItemTree.replacing(instance, in: state.profiles[index].items) {
                state.profiles[index].items = items
                return
            }
        }
    }
}
