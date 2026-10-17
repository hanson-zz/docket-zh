import Foundation

/// 添加小组件面板的分组规则：推荐列表、“新”角标、侧栏计数和应用、文件夹的显示名。
///
/// 放在 Core 里是为了能测：面板本身是 SwiftUI，测试只编译 Core 和目录。
public enum WidgetLibraryGroups {

    /// “推荐”里固定的精选，按显示顺序。推荐是独立的列表，不改小组件自己的分类。
    public static let featured: [WidgetKind] = [
        .clock, .weather, .calendar, .todo, .water, .aiAssistant, .music, .battery,
    ]

    /// 近期新增、在卡片上标“新”的小组件。
    ///
    /// 按 git 历史挑的：上一个正式版 v0.6.0（2026-10-13）的目录里还没有、之后
    /// 才加进来的 kind。下一个正式版发布后应当清空或换成那之后新增的。
    public static let newKinds: [WidgetKind] = [
        .slacker, .aiAssistant, .translate, .water, .pet, .perfectDay, .podcast,
    ]

    public static func isNew(_ kind: WidgetKind) -> Bool { newKinds.contains(kind) }

    /// 每个分类里卡片的先后，按分类定稿时列的顺序。不在这里的排在最后，保持目录顺序。
    public static let displayOrder: [WidgetKind] = [
        .appSwitcher, .shortcut,
        .clock, .world, .countdown, .stopwatch, .alarm, .progress, .slacker, .calendar, .week, .lunar,
        .todo, .reminders, .anniversary, .notes,
        .water, .posture, .habit, .timer, .perfectDay, .pet,
        .aiAssistant, .aiUsage, .translate, .clipboard, .search, .bookmarks, .github, .mail,
        .calculator, .converter, .currency, .colorPicker, .capture, .emoji, .toggles,
        .music, .podcast, .radio, .ambient, .recorder, .photos, .volume, .appVolume,
        .downloads, .trash, .fileShelf, .screenshots, .airdrop,
        .battery, .system, .network, .gauges, .microphone, .wallpaper,
        .weather,
        .stock, .watchlist, .crypto,
    ]

    /// 排序用的位置：在 `displayOrder` 里的按它的位置，不在的排在后面。
    public static func rank(_ kind: WidgetKind) -> Int {
        displayOrder.firstIndex(of: kind) ?? displayOrder.count
    }

    /// “推荐”的内容：先是精选，再接标“新”的（去重），只保留 `available` 里有的。
    public static func recommended(available: [WidgetKind]) -> [WidgetKind] {
        let offered = Set(available)
        var seen = Set<WidgetKind>()
        return (featured + newKinds).filter { offered.contains($0) && seen.insert($0).inserted }
    }

    /// 侧栏的数字：小组件个数，同一个小组件的多个样式只算一个。
    public static func kindCount(_ kinds: [WidgetKind]) -> Int { Set(kinds).count }

    /// 侧栏要显示的分类：按 `ordered` 的顺序，去掉没有小组件的。
    /// `alwaysShown` 里的分类即使没有小组件也保留（应用和文件夹还有应用和文件夹本身）。
    public static func visibleCategories(_ categories: [WidgetCategory],
                                         alwaysShown: Set<WidgetCategory> = [.appsAndFolders]) -> [WidgetCategory] {
        let present = Set(categories)
        return WidgetCategory.ordered.filter { present.contains($0) || alwaysShown.contains($0) }
    }

    /// 应用的显示名：去掉末尾的“.app”（不分大小写），去完是空的就保留原样。
    public static func appTitle(_ name: String) -> String {
        guard name.lowercased().hasSuffix(".app") else { return name }
        let trimmed = String(name.dropLast(4))
        return trimmed.trimmingCharacters(in: .whitespaces).isEmpty ? name : trimmed
    }

    /// 文件夹的显示名：用户主目录叫“个人”，其他照系统给的名字。
    public static func folderTitle(path: String, systemName: String, homePath: String) -> String {
        standardized(path) == standardized(homePath) ? tr("个人") : systemName
    }

    private static func standardized(_ path: String) -> String {
        var p = (path as NSString).standardizingPath
        while p.count > 1, p.hasSuffix("/") { p.removeLast() }
        return p
    }
}
