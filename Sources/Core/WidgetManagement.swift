import Foundation

/// 设置 ▸ 小组件管理：列出当前布局里的小组件，开关显示和拖动排序；下半列出
/// 还没放上去的小组件，打开开关就加到扩展栏末尾。
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

    // MARK: - 未添加

    /// 下半列表里的一种小组件：小组件库里的一种，带库里的名字、分类和默认样式。
    public struct Candidate: Equatable, Sendable, Identifiable {
        public var kind: WidgetKind
        /// 库里的名字（种类名，不是样式名）。
        public var name: String
        public var category: WidgetCategory
        /// 库里这一种的第一张卡片的样式，加的时候用它，和在库里点第一张卡片一样。
        public var overrides: [String: WidgetConfig.Value]
        /// 搜索时一起比对的别名，比如英文名。
        public var aliases: [String]

        public var id: WidgetKind { kind }

        public init(kind: WidgetKind, name: String, category: WidgetCategory,
                    overrides: [String: WidgetConfig.Value] = [:], aliases: [String] = []) {
            self.kind = kind
            self.name = name
            self.category = category
            self.overrides = overrides
            self.aliases = aliases
        }

        public func matches(_ query: String) -> Bool {
            WidgetSearch.matches(query, names: [name] + aliases, kind: kind.rawValue)
        }
    }

    /// 下半的一个分类：分类和其中还没添加的小组件。
    public struct Section: Equatable, Sendable, Identifiable {
        public var category: WidgetCategory
        public var items: [Candidate]
        public var id: WidgetCategory { category }
    }

    /// 可以在扩展栏上放好几个的小组件：已经放了一个，下半照样列出来，可以再加。
    ///
    /// 小组件库本身不拦重复添加，这里挑的是放多个有意义的：不同表盘或城市的时钟、
    /// 好几个倒计时和闹钟、不同尺度的时间进度、几张便签、不同快捷指令、不同相册、
    /// 不同指标的圆环仪表、不同的股票。其余的放了一个就算添加过，从下半消失。
    public static let repeatableKinds: Set<WidgetKind> = [
        .clock, .world, .countdown, .alarm, .progress, .notes, .shortcut, .photos, .gauges, .stock,
    ]

    public static func canAddAgain(_ kind: WidgetKind) -> Bool { repeatableKinds.contains(kind) }

    /// 每类展开后先显示几个，其余收在“还有 N 个”里。
    public static let previewCount = 4

    /// 小组件库里列出的种类，按库里的顺序：只要库里显示的（`selfContained`），
    /// 已经并掉或废弃的旧种类不在目录里，自然不会出现。`alias` 给每种补上别名
    /// （界面上传英文名或中文名，测试里不传）。
    public static func catalogCandidates(alias: (String) -> [String] = { _ in [] }) -> [Candidate] {
        WidgetCatalog.entries
            .filter(\.selfContained)
            .enumerated()
            .sorted { (WidgetLibraryGroups.rank($0.element.kind), $0.offset)
                < (WidgetLibraryGroups.rank($1.element.kind), $1.offset) }
            .map(\.element)
            .map { entry in
                Candidate(kind: entry.kind, name: entry.name, category: entry.category,
                          overrides: entry.variants.first?.overrides ?? [:],
                          aliases: alias(entry.name))
            }
    }

    /// 还没添加的：当前布局顶层没有这一种的，加上可以再放一个的。隐藏着的也算
    /// 已添加（它在上半，开关关着）。同一种只列一次，保持传进来的顺序。
    public static func unadded(_ candidates: [Candidate], placed: [WidgetKind]) -> [Candidate] {
        let onShelf = Set(placed)
        var seen = Set<WidgetKind>()
        return candidates.filter { candidate in
            guard seen.insert(candidate.kind).inserted else { return false }
            return !onShelf.contains(candidate.kind) || canAddAgain(candidate.kind)
        }
    }

    /// 按搜索词筛过、按库的分类顺序（`WidgetCategory.ordered`）分好的分类；
    /// 没有小组件的分类不列。分类里保持传进来的顺序。
    public static func sections(_ candidates: [Candidate], query: String = "") -> [Section] {
        let matching = candidates.filter { $0.matches(query) }
        return WidgetCategory.ordered.compactMap { category in
            let items = matching.filter { $0.category == category }
            return items.isEmpty ? nil : Section(category: category, items: items)
        }
    }

    /// 上半按搜索词筛：`names` 给出每个小组件可比对的名字（中文名、英文名）。
    public static func filter(_ widgets: [WidgetInstance], query: String,
                              names: (WidgetInstance) -> [String]) -> [WidgetInstance] {
        widgets.filter { WidgetSearch.matches(query, names: names($0), kind: $0.kind.rawValue) }
    }

    /// 搜索词是不是有内容（全是空白算没有，和搜索本身一样不分空格）。
    public static func hasQuery(_ query: String) -> Bool {
        query.contains { !$0.isWhitespace }
    }

    /// 分类是否展开。有搜索词时有匹配的分类都展开（没匹配的已经不在列表里）；
    /// 没有搜索词时按用户点过的，没点过的只有第一类展开。
    public static func isExpanded(_ category: WidgetCategory, in sections: [Section],
                                  query: String, choices: [WidgetCategory: Bool]) -> Bool {
        if hasQuery(query) { return true }
        if let choice = choices[category] { return choice }
        return sections.first?.category == category
    }

    /// 展开的分类里先显示的几个，和收起来的个数。点过“还有 N 个”或有搜索词时全显示。
    public static func visible(_ items: [Candidate], showAll: Bool) -> (shown: [Candidate], more: Int) {
        guard !showAll, items.count > previewCount else { return (items, 0) }
        return (Array(items.prefix(previewCount)), items.count - previewCount)
    }
}
