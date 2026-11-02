import Foundation

/// 应用切换器 v2 的排版、键盘移动和缩略图缓存规则，桌面卡片、扩展栏卡片和面板共用。
///
/// 效果图 design/app-switcher-v2.py：
/// - 面板「固定」「正在运行」两块是只有图标的自适应网格，每格至少 52（图标 44），
///   列数按内容区宽度算（320 面板 5 列，460 面板 7 列）；高度按行数算，最多几行，再多在里面滚。
/// - 点一个图标在网格下面展开名字、「当前 · N 个窗口」和窗口缩略图。缩略图一排放得下时
///   在 92 到 124 宽之间平分，放不下时 92 宽横向滚动。
/// - 方向键在两块网格之间按行列走，回车切换，空格展开收起，Esc 收起。
///
/// 全部是纯函数和值类型，有测试。
public enum AppSwitcherLayout {

    // MARK: 面板网格

    /// 面板网格每格最小边长（`GridItem(.adaptive(minimum: 52))`）。
    public static let panelCell: Double = 52
    /// 面板网格里的图标。
    public static let panelIcon: Double = 44
    /// 同一行两格之间。
    public static let panelColumnSpacing: Double = 4
    /// 两行之间。
    public static let panelRowSpacing: Double = 6
    /// 「正在运行」最多直接摊开几行，再多在网格里滚。
    public static let panelMaxRows = 4

    /// 自适应网格的列数，和 SwiftUI `GridItem(.adaptive(minimum:), spacing:)` 一样：
    /// 每格至少 `minimum`，格间 `spacing`，能放几列放几列，至少 1 列。
    public static func columns(width: Double, minimum: Double = panelCell,
                               spacing: Double = panelColumnSpacing) -> Int {
        guard width > 0, minimum > 0 else { return 1 }
        return max(1, Int(((width + spacing) / (minimum + spacing)).rounded(.down)))
    }

    /// `count` 个格子排成几行。
    public static func rows(count: Int, columns: Int) -> Int {
        guard count > 0, columns > 0 else { return 0 }
        return (count + columns - 1) / columns
    }

    /// 网格高度：行数乘格高加行距；给了 `maxRows` 时最多摊开这么多行。
    public static func gridHeight(count: Int, columns: Int, maxRows: Int? = nil,
                                  cell: Double = panelCell, rowSpacing: Double = panelRowSpacing) -> Double {
        var rows = rows(count: count, columns: columns)
        if let maxRows { rows = min(rows, max(1, maxRows)) }
        guard rows > 0 else { return 0 }
        return Double(rows) * cell + Double(rows - 1) * rowSpacing
    }

    // MARK: 扩展栏卡片

    /// 横排扩展栏卡片最多几格：都放得下时 7 个全放，多了放 6 个加「+N」。
    public static let tileCapacity = 7
    /// 横排卡片的图标和高亮块。
    public static let tileIcon: Double = 30
    public static let tilePlate: Double = 34
    public static let tileSpacing: Double = 2

    /// 横排卡片内容宽：7 格加 6 个间距。
    public static var tileContentWidth: Double {
        Double(tileCapacity) * tilePlate + Double(tileCapacity - 1) * tileSpacing
    }

    // MARK: 展开区缩略图

    /// 缩略图的高宽比（窗口画面框，标题另算）。
    public static let thumbAspect = 0.64
    public static let thumbMinWidth: Double = 92
    public static let thumbMaxWidth: Double = 124
    public static let thumbSpacing: Double = 12

    /// 展开区一排 `count` 张缩略图的宽度，以及要不要横向滚动。
    public static func thumbWidth(count: Int, available: Double, minimum: Double = thumbMinWidth,
                                  maximum: Double = thumbMaxWidth,
                                  spacing: Double = thumbSpacing) -> (width: Double, scrolls: Bool) {
        guard count > 0, available > 0 else { return (minimum, false) }
        let even = (available - Double(count - 1) * spacing) / Double(count)
        if even < minimum { return (minimum, true) }
        return (min(maximum, even), false)
    }

    // MARK: 名字行

    /// 名字后面那一小段：「当前 · 3 个窗口」「3 个窗口」「当前」「没开」。
    /// `windows` 是 nil 时不知道窗口数（没给辅助功能权限、还没读），只写当前与否。
    public static func status(isActive: Bool, isRunning: Bool, windows: Int?) -> String {
        guard isRunning else { return tr("没开") }
        guard let windows else { return isActive ? tr("当前") : "" }
        if windows <= 0 { return isActive ? tr("当前 · 没有窗口") : tr("没有窗口") }
        return isActive ? tr("当前 · \(windows) 个窗口") : tr("\(windows) 个窗口")
    }

    // MARK: 键盘

    /// 网格里的一格：第几块（固定、正在运行），块里第几个。
    public struct Position: Equatable, Hashable, Sendable {
        public var section: Int
        public var index: Int

        public init(section: Int, index: Int) {
            self.section = section
            self.index = index
        }
    }

    public enum Move: Sendable {
        case left, right, up, down
    }

    /// 按一下方向键之后落在哪一格。`sections` 是每块有几个，所有块同样的列数。
    ///
    /// - 还没选中时落在第一块有东西的第一格。
    /// - 左右按先后走，到块头块尾接上一块的最后一个、下一块的第一个，到头不动。
    /// - 上下按列走：上一行（下一行）同一列，那一行短时落在最后一个；块里没有上一行
    ///   时去上一块的最后一行同一列，没有下一行时去下一块的第一行同一列，到头不动。
    public static func move(_ from: Position?, _ move: Move, sections: [Int], columns: Int) -> Position? {
        let filled = sections.indices.filter { sections[$0] > 0 }
        guard let first = filled.first, columns > 0 else { return nil }
        guard let from, sections.indices.contains(from.section), sections[from.section] > 0 else {
            return Position(section: first, index: 0)
        }
        let count = sections[from.section]
        let index = min(max(0, from.index), count - 1)
        let previous = filled.last { $0 < from.section }
        let next = filled.first { $0 > from.section }
        let column = index % columns

        switch move {
        case .left:
            if index > 0 { return Position(section: from.section, index: index - 1) }
            if let previous { return Position(section: previous, index: sections[previous] - 1) }
            return Position(section: from.section, index: index)
        case .right:
            if index < count - 1 { return Position(section: from.section, index: index + 1) }
            if let next { return Position(section: next, index: 0) }
            return Position(section: from.section, index: index)
        case .up:
            if index - columns >= 0 { return Position(section: from.section, index: index - columns) }
            if let previous {
                let total = sections[previous]
                let lastRowStart = ((total - 1) / columns) * columns
                return Position(section: previous, index: min(lastRowStart + column, total - 1))
            }
            return Position(section: from.section, index: index)
        case .down:
            if index + columns < count { return Position(section: from.section, index: index + columns) }
            let row = index / columns, lastRow = (count - 1) / columns
            if row < lastRow { return Position(section: from.section, index: count - 1) }
            if let next { return Position(section: next, index: min(column, sections[next] - 1)) }
            return Position(section: from.section, index: index)
        }
    }

    // MARK: 缩略图缓存

    /// 缩略图缓存一张图留多久算新鲜：过了还先画旧的，后台再截一张换上。
    public static let shotLifetime: TimeInterval = 15
    /// 最多存几张，多了先扔最久没用的。
    public static let shotCapacity = 48
    /// 一批最多截几张（一次只跑一批）。
    public static let shotBatch = 4
}

/// 有寿命、有容量的缓存：存进去的东西过了 `lifetime` 只是不新鲜（还能读），
/// 超过 `capacity` 时扔掉最久没存没读的。键是字符串，值随意。
public struct ExpiringLRUCache<Value> {
    public let capacity: Int
    public let lifetime: TimeInterval

    private var store: [String: (value: Value, stamp: Date)] = [:]
    /// 从旧到新，读和存都挪到最后。
    private var order: [String] = []

    public init(capacity: Int, lifetime: TimeInterval) {
        self.capacity = max(1, capacity)
        self.lifetime = lifetime
    }

    public var count: Int { store.count }

    /// 读一张，不管新不新鲜；读过的挪到最新。
    public mutating func value(for key: String) -> Value? {
        guard let hit = store[key] else { return nil }
        touch(key)
        return hit.value
    }

    /// 只看，不挪先后（重画时用，不改缓存）。
    public func peek(_ key: String) -> Value? { store[key]?.value }

    /// 存进去的时间离 `now` 还没过 `lifetime`。
    public func isFresh(_ key: String, at now: Date) -> Bool {
        guard let hit = store[key] else { return false }
        return now.timeIntervalSince(hit.stamp) < lifetime
    }

    public mutating func insert(_ value: Value, for key: String, at now: Date) {
        store[key] = (value, now)
        touch(key)
        while order.count > capacity {
            let oldest = order.removeFirst()
            store[oldest] = nil
        }
    }

    public mutating func remove(_ key: String) {
        store[key] = nil
        order.removeAll { $0 == key }
    }

    public mutating func removeAll() {
        store = [:]
        order = []
    }

    private mutating func touch(_ key: String) {
        order.removeAll { $0 == key }
        order.append(key)
    }
}
