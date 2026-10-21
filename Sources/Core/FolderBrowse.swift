import CoreGraphics
import Foundation

// 扩展栏文件夹小窗（点文件夹格子弹出的浏览小窗）里不碰界面的部分：
// 点文件夹时做什么、隐藏文件规则、排序、按文件名过滤、相对时间分档、
// 子文件夹路径、窗口大小。界面在 DockPanel/FolderBrowserWindow.swift。

/// 设置 ▸ 扩展栏「点文件夹时」。
public enum FolderClickAction: String, Codable, Sendable, CaseIterable {
    /// 在扩展栏上方弹出小窗浏览（默认）。
    case browse
    /// 和以前一样交给访达打开。
    case finder

    public static let defaultValue: Self = .browse

    public var label: String {
        switch self {
        case .browse: tr("小窗浏览")
        case .finder: tr("在访达中打开")
        }
    }
}

/// 小窗里的排序方式。
public enum FolderSort: String, Codable, Sendable, CaseIterable {
    /// 修改时间，新的在前（默认）。
    case modified
    /// 名称，按访达的自然顺序（「文件 2」在「文件 10」前面）。
    case name
    /// 大小，大的在前；文件夹没有大小，排在最后。
    case size
    /// 种类（「PDF 文稿」「文件夹」这类说明），同种类按名称。
    case kind

    public static let defaultValue: Self = .modified

    public var label: String {
        switch self {
        case .modified: tr("修改时间")
        case .name: tr("名称")
        case .size: tr("大小")
        case .kind: tr("种类")
        }
    }
}

/// 小窗里的一项。读文件夹的那一边（主程序）填好这些，排序、过滤只看它们。
public struct FolderEntry: Hashable, Sendable, Identifiable {
    public var url: URL
    public var name: String
    /// 能在小窗里点进去的文件夹。App、照片图库这类包算文件，不进去。
    public var isFolder: Bool
    public var modified: Date?
    /// 文件的字节数，文件夹是 nil。
    public var size: Int64?
    /// 系统给的种类说明（「PDF 文稿」），读不到时空字符串。
    public var kind: String

    public var id: URL { url }

    public init(url: URL, name: String, isFolder: Bool, modified: Date?, size: Int64?, kind: String) {
        self.url = url
        self.name = name
        self.isFolder = isFolder
        self.modified = modified
        self.size = size
        self.kind = kind
    }
}

public enum FolderBrowse {

    // MARK: 隐藏文件

    /// 不显示的项：点开头的（.DS_Store、.git 这类）、系统标了隐藏的、
    /// 访达自定义图标留下的「Icon\r」，以及 iCloud 还没下载的占位
    /// （.xxx.icloud 也是点开头）。
    public static func isHidden(name: String, hiddenFlag: Bool) -> Bool {
        if hiddenFlag { return true }
        if name.isEmpty || name.hasPrefix(".") { return true }
        if name == "Icon\r" { return true }
        return false
    }

    // MARK: 排序

    /// 按 `sort` 排好。名称一样的再按完整路径，保证每次顺序一样，列表不跳。
    public static func sorted(_ entries: [FolderEntry], by sort: FolderSort) -> [FolderEntry] {
        entries.sorted { a, b in
            switch sort {
            case .modified:
                let da = a.modified ?? .distantPast, db = b.modified ?? .distantPast
                if da != db { return da > db }
            case .name:
                break
            case .size:
                // 文件夹（nil）排在所有文件后面。
                switch (a.size, b.size) {
                case let (x?, y?) where x != y: return x > y
                case (.some, nil): return true
                case (nil, .some): return false
                default: break
                }
            case .kind:
                let order = a.kind.localizedStandardCompare(b.kind)
                if order != .orderedSame { return order == .orderedAscending }
            }
            return nameOrder(a, b)
        }
    }

    private static func nameOrder(_ a: FolderEntry, _ b: FolderEntry) -> Bool {
        let order = a.name.localizedStandardCompare(b.name)
        if order != .orderedSame { return order == .orderedAscending }
        return a.url.path < b.url.path
    }

    // MARK: 过滤

    /// 搜索框里的字按文件名过滤当前这一层：不分大小写、全半角、重音，
    /// 前后空格不算；空的就是全部。
    public static func filter(_ entries: [FolderEntry], query: String) -> [FolderEntry] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return entries }
        return entries.filter {
            $0.name.range(of: needle,
                          options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) != nil
        }
    }

    // MARK: 相对时间

    /// 格子名字下面那行的档位。
    public enum Age: Equatable, Sendable {
        /// 一分钟以内（也包括时间比现在还晚的，时钟不准的移动硬盘常见）。
        case justNow
        case minutes(Int)
        case hours(Int)
        case days(Int)
        case weeks(Int)
        case months(Int)
        case years(Int)
    }

    public static func age(of date: Date, now: Date) -> Age {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return .justNow }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return .minutes(minutes) }
        let hours = minutes / 60
        if hours < 24 { return .hours(hours) }
        let days = hours / 24
        if days < 7 { return .days(days) }
        if days < 30 { return .weeks(days / 7) }
        if days < 365 { return .months(max(1, days / 30)) }
        return .years(days / 365)
    }

    /// 「27 分钟前」「2 days ago」：系统的相对时间格式，按界面语言。
    public static func relativeText(for date: Date, now: Date, locale: Locale) -> String {
        let components: DateComponents
        switch age(of: date, now: now) {
        case .justNow: return tr("刚刚")
        case .minutes(let n): components = DateComponents(minute: -n)
        case .hours(let n): components = DateComponents(hour: -n)
        case .days(let n): components = DateComponents(day: -n)
        case .weeks(let n): components = DateComponents(weekOfMonth: -n)
        case .months(let n): components = DateComponents(month: -n)
        case .years(let n): components = DateComponents(year: -n)
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .numeric
        return formatter.localizedString(from: components)
    }

    // MARK: 子文件夹路径

    /// 从扩展栏上那个文件夹走到当前这一层经过的名字，第一个是根自己。
    /// 当前不在根下面时（不该发生）只给当前这一层的名字。
    public static func trail(root: URL, current: URL) -> [String] {
        let rootParts = root.standardizedFileURL.pathComponents
        let parts = current.standardizedFileURL.pathComponents
        guard parts.count >= rootParts.count, Array(parts.prefix(rootParts.count)) == rootParts else {
            return [current.lastPathComponent]
        }
        return [root.lastPathComponent] + parts.dropFirst(rootParts.count)
    }

    /// 返回上一层：已经在根上时是 nil。
    public static func parent(of current: URL, root: URL) -> URL? {
        let here = current.standardizedFileURL.pathComponents
        let top = root.standardizedFileURL.pathComponents
        guard here.count > top.count, Array(here.prefix(top.count)) == top else { return nil }
        return current.deletingLastPathComponent()
    }

    // MARK: 拖进来移动

    /// 拖进小窗的文件里真要移进 `folder` 的那些：本来就在这一层的（从小窗里拖起
    /// 又放回来）、`folder` 自己、`folder` 的上层（把文件夹移进它自己的子文件夹）
    /// 都去掉，重复的只留一个。
    public static func movable(_ sources: [URL], into folder: URL) -> [URL] {
        let target = folder.standardizedFileURL.pathComponents
        var seen = Set<String>()
        return sources.filter { url in
            let parts = url.standardizedFileURL.pathComponents
            let path = parts.joined(separator: "/")
            guard seen.insert(path).inserted else { return false }
            if Array(parts.dropLast()) == target { return false }
            if parts.count <= target.count, Array(target.prefix(parts.count)) == parts { return false }
            return true
        }
    }

    // MARK: 窗口大小

    /// 一格的宽、高，格子之间、四周的留白，顶栏的高度。
    public static let cellWidth: CGFloat = 100
    public static let cellHeight: CGFloat = 116
    public static let spacing: CGFloat = 8
    public static let padding: CGFloat = 14
    public static let headerHeight: CGFloat = 48

    /// 小窗的列数和大小：约 6 列宽、2.5 行高（露出半行提示能滚），
    /// 屏幕放不下时少几列、矮一点，最少 3 列。
    public static func layout(visible: CGSize) -> (columns: Int, size: CGSize) {
        let step = cellWidth + spacing
        let room = visible.width * 0.92 - padding * 2 + spacing
        let columns = max(3, min(6, Int(room / step)))
        let width = padding * 2 + CGFloat(columns) * cellWidth + CGFloat(columns - 1) * spacing
        let rows: CGFloat = 2.5
        let natural = headerHeight + padding + rows * cellHeight + 2 * spacing + padding
        let height = max(220, min(natural, visible.height * 0.6))
        return (columns, CGSize(width: width, height: height.rounded()))
    }
}
