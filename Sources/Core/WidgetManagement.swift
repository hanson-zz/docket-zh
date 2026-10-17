import Foundation

/// 设置 ▸ 小组件管理：列出当前布局里的小组件，开关显示和拖动排序。
///
/// 不新造存储：显示和隐藏就是小组件配置里已有的 `visibility`（见
/// `WidgetVisibility`），排序就是布局本身的 `items` 顺序。只动顶层的小组件，
/// 应用、文件夹、分组和间隔留在原来的格子里。
public enum WidgetManagement {

    /// 布局里顶层的小组件，按扩展栏上的顺序。
    public static func widgets(_ items: [DockItem]) -> [WidgetInstance] {
        items.compactMap(\.widget)
    }

    /// 开关的状态：只有明确设成“隐藏”才算关；“满足条件时显示”也算开。
    public static func isShown(_ instance: WidgetInstance) -> Bool {
        WidgetVisibility.mode(instance.config) != .hidden
    }

    /// 打开或关掉一个小组件。关掉写“隐藏”；打开时原来是隐藏的改回“始终显示”，
    /// 原来就开着的（包括条件显示）不动。找不到这个 id 时原样返回。
    public static func setShown(_ shown: Bool, id: UUID, in items: [DockItem]) -> [DockItem] {
        items.map { item in
            guard var widget = item.widget, widget.id == id else { return item }
            if shown {
                guard !isShown(widget) else { return item }
                widget = WidgetVisibility.restored(widget)
            } else {
                guard isShown(widget) else { return item }
                widget.config.set(WidgetVisibility.modeKey, .string(WidgetVisibilityMode.hidden.rawValue))
            }
            return .widget(widget)
        }
    }

    /// 在小组件之间挪动，语义和 SwiftUI 的 `onMove` 一样：`source` 是小组件列表里
    /// 的位置，`destination` 是挪过去之前的插入位置。非小组件的项目位置不变，
    /// 小组件依次填回原来属于小组件的那些格子。越界的位置原样返回。
    public static func move(widgetsAt source: IndexSet, to destination: Int,
                            in items: [DockItem]) -> [DockItem] {
        let slots = items.indices.filter { items[$0].widget != nil }
        let count = slots.count
        guard !source.isEmpty, source.allSatisfy({ $0 >= 0 && $0 < count }),
              destination >= 0, destination <= count else { return items }
        var widgets = slots.map { items[$0] }
        let moving = source.map { widgets[$0] }
        let before = source.filter { $0 < destination }.count
        for index in source.sorted(by: >) { widgets.remove(at: index) }
        widgets.insert(contentsOf: moving, at: destination - before)
        var result = items
        for (slot, item) in zip(slots, widgets) { result[slot] = item }
        return result
    }
}
