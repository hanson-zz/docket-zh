import Foundation

/// 快捷指令卡片上一个图标的颜色：面板“外观”里的八个色点。
///
/// 存英文名而不是色值，以后调色不用迁移配置；认不出的名字退回默认。
public enum ShortcutColor: String, CaseIterable, Sendable {
    case orange, red, yellow, green, blue, indigo, purple, gray

    public var hex: String {
        switch self {
        case .orange: "#E07A3A"
        case .red: "#C9503F"
        case .yellow: "#D9A520"
        case .green: "#2FA37A"
        case .blue: "#3A93C9"
        case .indigo: "#6C63D9"
        case .purple: "#B05AC9"
        case .gray: "#7A7F8C"
        }
    }

    public var name: String {
        switch self {
        case .orange: tr("橙色")
        case .red: tr("红色")
        case .yellow: tr("黄色")
        case .green: tr("绿色")
        case .blue: tr("蓝色")
        case .indigo: tr("靛蓝")
        case .purple: tr("紫色")
        case .gray: tr("灰色")
        }
    }
}

/// 图标里的白色 SF Symbol：效果图里的图片、文稿、闪电、时钟、水滴、月亮。
public enum ShortcutSymbol: String, CaseIterable, Sendable {
    case bolt, photo, text, clock, drop, moon

    public var systemName: String {
        switch self {
        case .bolt: "bolt.fill"
        case .photo: "photo"
        case .text: "text.alignleft"
        case .clock: "clock"
        case .drop: "drop.fill"
        case .moon: "moon.fill"
        }
    }

    public var name: String {
        switch self {
        case .bolt: tr("闪电")
        case .photo: tr("图片")
        case .text: tr("文稿")
        case .clock: tr("时钟")
        case .drop: tr("水滴")
        case .moon: tr("月亮")
        }
    }
}

/// 卡片上的一个快捷指令：名字，加上它在卡片上的颜色和图标。
///
/// 存成一行文字 `颜色|图标|名字`，名字放最后、只切前两刀，所以名字里有
/// “|”也原样保留。名字是运行时交给 `shortcuts run` 的那个名字。
public struct ShortcutItem: Hashable, Sendable, Identifiable {
    public var name: String
    public var color: ShortcutColor
    public var symbol: ShortcutSymbol

    public var id: String { name }

    public init(name: String, color: ShortcutColor, symbol: ShortcutSymbol) {
        self.name = name
        self.color = color
        self.symbol = symbol
    }

    public var encoded: String { "\(color.rawValue)|\(symbol.rawValue)|\(name)" }

    /// 认不出的颜色或图标退回默认；没有名字的行丢掉。
    public init?(parsing text: String) {
        let parts = text.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let name = String(parts[2]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let fallback = ShortcutDeck.defaultStyle(at: 0)
        self.name = name
        self.color = ShortcutColor(rawValue: String(parts[0])) ?? fallback.color
        self.symbol = ShortcutSymbol(rawValue: String(parts[1])) ?? fallback.symbol
    }
}

/// 一张快捷指令卡片放的那串快捷指令（`items`），以及卡片的尺寸。
///
/// 旧卡片只存一个名字（`name`）。读的时候它就是列表第一项；面板第一次写
/// 列表时把旧键删掉，这样全部取消勾选后旧名字不会又冒出来。
public enum ShortcutDeck {
    public static let key = "items"
    public static let legacyKey = "name"
    /// 卡片一排最多放几个，多出来的只在面板里。
    public static let tileLimit = 4
    /// 最多勾选几个：面板按内容长高，再多就要滚动了。
    public static let limit = 12

    /// 新勾选的快捷指令依次用的颜色和图标，让相邻两个一眼分得开。
    static let colorCycle: [ShortcutColor] = [.indigo, .orange, .green, .yellow, .blue, .red, .purple, .gray]
    static let symbolCycle: [ShortcutSymbol] = ShortcutSymbol.allCases

    public static func defaultStyle(at index: Int) -> (color: ShortcutColor, symbol: ShortcutSymbol) {
        let i = max(0, index)
        return (colorCycle[i % colorCycle.count], symbolCycle[i % symbolCycle.count])
    }

    /// 存着的列表，按保存的顺序，同名的只留第一个。没有列表时读旧的单个名字。
    public static func items(_ config: WidgetConfig) -> [ShortcutItem] {
        var seen = Set<String>()
        let stored = config.strings(key).compactMap(ShortcutItem.init(parsing:))
            .filter { seen.insert($0.name).inserted }
        if !stored.isEmpty || (config[key] != nil && config[legacyKey] == nil) {
            return Array(stored.prefix(limit))
        }
        let legacy = config.string(legacyKey).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !legacy.isEmpty else { return [] }
        let style = defaultStyle(at: 0)
        return [ShortcutItem(name: legacy, color: style.color, symbol: style.symbol)]
    }

    /// 写回列表，顺手删掉旧的单个名字。
    public static func write(_ items: [ShortcutItem], into config: inout WidgetConfig) {
        config.set(key, .list(items.prefix(limit).map { .string($0.encoded) }))
        config.set(legacyKey, nil)
    }

    /// 卡片上画的那几个：列表前 4 个。
    public static func tileItems(_ config: WidgetConfig) -> [ShortcutItem] {
        Array(items(config).prefix(tileLimit))
    }

    /// 勾选或取消：已经在列表里就拿掉，不在就加到最后（满了原样返回），
    /// 颜色和图标按它是第几个加的轮着给。
    public static func toggling(_ name: String, in items: [ShortcutItem]) -> [ShortcutItem] {
        if items.contains(where: { $0.name == name }) {
            return items.filter { $0.name != name }
        }
        guard items.count < limit, !name.isEmpty else { return items }
        let used = Set(items.map(\.color))
        // 先挑还没人用的颜色，八个都用过了再按位置轮。
        let color = colorCycle.first { !used.contains($0) } ?? defaultStyle(at: items.count).color
        let symbol = defaultStyle(at: items.count).symbol
        return items + [ShortcutItem(name: name, color: color, symbol: symbol)]
    }

    /// 改一个快捷指令的颜色或图标，其余不动。
    public static func restyling(_ name: String, color: ShortcutColor? = nil, symbol: ShortcutSymbol? = nil,
                                 in items: [ShortcutItem]) -> [ShortcutItem] {
        items.map { item in
            guard item.name == name else { return item }
            var copy = item
            if let color { copy.color = color }
            if let symbol { copy.symbol = symbol }
            return copy
        }
    }

    /// 把第 `from` 个挪到第 `to` 个的位置（挪完之后的下标）。
    public static func moving(from: Int, to: Int, in items: [ShortcutItem]) -> [ShortcutItem] {
        guard items.indices.contains(from) else { return items }
        let target = min(max(0, to), items.count - 1)
        guard target != from else { return items }
        var copy = items
        let item = copy.remove(at: from)
        copy.insert(item, at: target)
        return copy
    }

    /// 拖动把手时按位移算落到哪一格：每过半行换一格。
    public static func dropIndex(from: Int, translation: Double, rowHeight: Double, count: Int) -> Int {
        guard count > 0, rowHeight > 0 else { return from }
        let steps = Int((translation / rowHeight).rounded())
        return min(max(0, from + steps), count - 1)
    }

    /// 编辑态搜索：名字、拼音全拼或首字母都算；空搜索列出全部。
    public static func search(_ query: String, in names: [String]) -> [String] {
        names.filter { WidgetSearch.matches(query, names: [$0], kind: "") }
    }

    /// 勾选了、但系统快捷指令里已经找不到的名字（被改名或删了）。
    /// 还没读到系统列表时什么都不算缺。
    public static func missing(_ items: [ShortcutItem], available: [String]?) -> Set<String> {
        guard let available else { return [] }
        let known = Set(available)
        return Set(items.map(\.name).filter { !known.contains($0) })
    }

    // MARK: 尺寸

    /// 横排卡片里一个图标的边长，和 `WidgetStyle.badge` 一样。
    public static let iconSize: Double = 40
    public static let iconSpacing: Double = 8
    /// 竖排时图标两个一行。
    public static let columnIconSize: Double = 26

    /// 横排卡片的宽：按卡片上的个数算（最多 4 个），每个 40、间隔 8，
    /// 加两边各 10 的内边距。一个都没选时是放“选择快捷指令”的旧宽度。
    public static func tileWidth(count: Int) -> Double {
        let shown = min(max(count, 0), tileLimit)
        guard shown > 0 else { return 140 }
        return Double(shown) * iconSize + Double(shown - 1) * iconSpacing + 20
    }

    /// 竖排卡片的高：两个一行。
    public static func columnHeight(count: Int) -> Double {
        let shown = min(max(count, 0), tileLimit)
        guard shown > 0 else { return 76 }
        let rows = (shown + 1) / 2
        return max(62, Double(rows) * (columnIconSize + 4) + 16)
    }
}

/// 一次运行的结果，以及面板上那行“今天 09:12 · 已完成”。
public enum ShortcutRun {
    public enum Status: Codable, Equatable, Sendable {
        case ok
        case failed(String)
        case cancelled
    }

    /// 最近一次跑完的记录。`output` 是 `shortcuts run` 打到 stdout 的文字，没有就是 nil。
    public struct Record: Codable, Equatable, Sendable {
        public var finishedAt: Date
        public var status: Status
        public var output: String?

        public init(finishedAt: Date, status: Status, output: String?) {
            self.finishedAt = finishedAt
            self.status = status
            self.output = output
        }
    }

    /// 输出最多留多少字：面板只展开看一眼，太长的截掉。
    public static let outputLimit = 2000

    /// stdout 里能显示的文字。不是 UTF-8（图片、文件这类二进制）或只有空白时
    /// 返回 nil，面板就不显示输出。
    public static func output(from data: Data) -> String? {
        guard !data.isEmpty, !data.contains(0), let text = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count > outputLimit else { return trimmed }
        return String(trimmed.prefix(outputLimit)) + "…"
    }

    /// stderr 第一行，就是工具说的失败原因；去掉开头的 “Error: ”。
    public static func reason(fromStderr text: String) -> String? {
        let line = text
            .split(whereSeparator: \.isNewline)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let line, !line.isEmpty else { return nil }
        return line.hasPrefix("Error: ") ? String(line.dropFirst(7)) : line
    }

    /// “今天 09:12”“昨天 18:40”，更早的写“10月18日 18:40”。
    public static func when(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute, .month, .day], from: date)
        let clock = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return tr("今天 \(clock)")
        case -1: return tr("昨天 \(clock)")
        default: return tr("\(parts.month ?? 1)月\(parts.day ?? 1)日 \(clock)")
        }
    }

    public enum Tone: Equatable, Sendable { case plain, success, running, failure }

    /// 面板每一行名字下面那行字和它的颜色。
    public static func line(record: Record?, running: Bool, missing: Bool = false,
                            now: Date, calendar: Calendar = .current) -> (text: String, tone: Tone) {
        if running { return (tr("正在运行…"), .running) }
        if missing { return (tr("在“快捷指令”里找不到了，可能改了名或删了"), .failure) }
        guard let record else { return (tr("还没运行过"), .plain) }
        let at = when(record.finishedAt, now: now, calendar: calendar)
        switch record.status {
        case .ok: return (tr("\(at) · 已完成"), .success)
        case .cancelled: return (tr("\(at) · 已停止"), .plain)
        case .failed(let why): return (tr("\(at) · \(why)"), .failure)
        }
    }

    /// 头部副标题：“5 个已选 · 前 4 个放在卡片上”。
    public static func header(count: Int) -> String {
        switch count {
        case 0: return tr("还没选快捷指令")
        case 1...ShortcutDeck.tileLimit: return tr("\(count) 个已选 · 都放在卡片上")
        default: return tr("\(count) 个已选 · 前 \(ShortcutDeck.tileLimit) 个放在卡片上")
        }
    }
}
