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

    /// 种类小标题后面的一句说明，没有就是 nil。
    public static func note(_ kind: WidgetKind) -> String? {
        switch kind {
        case .reminders: tr("和系统提醒事项同步")
        case .todo: tr("随手记，不同步")
        // 数剩余时间的四个按尺度分工，卡片上写明各管多长。
        case .countdown: tr("几分钟内")
        case .alarm: tr("今天某个时刻")
        case .anniversary: tr("按天")
        case .progress: tr("年月周日百分比")
        default: nil
        }
    }

    /// 卡片的悬停说明：小标题那句说明，加上需要哪项系统权限。
    ///
    /// 卡片上原来的权限小锁去掉了（看着像锁住不能用），第一次用到时再请求；
    /// 需要权限这件事只留在悬停说明里。Pro 的小锁不归这里管。
    public static func cardHelp(_ kind: WidgetKind) -> String {
        var parts: [String] = []
        if let note = note(kind) { parts.append(note) }
        if let permission = WidgetSearch.permissions[kind.rawValue] {
            parts.append(tr("需要“\(trKey(permission))”权限，第一次用到时会请求。"))
        }
        return parts.joined(separator: "\n")
    }

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

    /// 分类里按种类分组：把已经按种类排好的卡片切成连续的几组，每种小组件
    /// 一组，组内和组间都保持原来的顺序。同一种不连续出现时各成一组，不重排。
    public static func groupedByKind<T>(_ items: [T], kind: (T) -> WidgetKind) -> [[T]] {
        var groups: [[T]] = []
        var current: WidgetKind?
        for item in items {
            let k = kind(item)
            if k == current, !groups.isEmpty {
                groups[groups.count - 1].append(item)
            } else {
                groups.append([item])
                current = k
            }
        }
        return groups
    }

    /// 方向键用的行：每组从新的一行开始，按 `columns` 列折行。返回每行里卡片
    /// 在整个列表（所有组连起来）中的下标。
    public static func gridRows(groupSizes: [Int], columns: Int) -> [[Int]] {
        let width = max(1, columns)
        var rows: [[Int]] = []
        var start = 0
        for size in groupSizes where size > 0 {
            var offset = 0
            while offset < size {
                let end = min(size, offset + width)
                rows.append(Array((start + offset)..<(start + end)))
                offset = end
            }
            start += size
        }
        return rows
    }

    /// 上下方向键：从下标 `index` 移到上一行（`delta` 为 -1）或下一行（1）的
    /// 同一列；那一行没这么多列时落到它的最后一张。没有那一行时返回 nil。
    public static func verticalMove(from index: Int, rows: [[Int]], by delta: Int) -> Int? {
        guard let row = rows.firstIndex(where: { $0.contains(index) }),
              let column = rows[row].firstIndex(of: index) else { return nil }
        let target = row + delta
        guard rows.indices.contains(target), let last = rows[target].last else { return nil }
        return column < rows[target].count ? rows[target][column] : last
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
