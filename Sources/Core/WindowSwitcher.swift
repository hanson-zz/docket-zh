import CoreGraphics
import Foundation

// MARK: - 设置

/// ⌥Tab 按窗口切换（免费功能）的设置，在设置 ▸ 快捷键 ▸ 窗口切换。
///
/// 快捷键默认 ⌥Tab。清空后存成显式的 null，和“从来没设过”（读成默认 ⌥Tab）分开，
/// 所以编码时 nil 也要写出来。
public struct WindowSwitcherSettings: Codable, Hashable, Sendable {
    /// ⌥Tab：Tab 的键码 48，加 Option。
    public static let defaultHotKey = KeyCombo(keyCode: 48, modifiers: KeyCombo.Modifier.option)

    public var hotKey: KeyCombo? = WindowSwitcherSettings.defaultHotKey
    /// 只列当前桌面的窗口（最小化的窗口拿不到桌面时照样列出）。默认关。
    public var currentDesktopOnly = false
    /// 同一个 App 的窗口挨在一起，App 之间按最近使用排。默认关。
    public var groupByApp = false
    /// 也列已最小化的窗口和已隐藏 App 的窗口。默认开。
    public var includeMinimized = true

    public init(hotKey: KeyCombo? = WindowSwitcherSettings.defaultHotKey, currentDesktopOnly: Bool = false,
                groupByApp: Bool = false, includeMinimized: Bool = true) {
        self.hotKey = hotKey
        self.currentDesktopOnly = currentDesktopOnly
        self.groupByApp = groupByApp
        self.includeMinimized = includeMinimized
    }

    private enum CodingKeys: String, CodingKey { case hotKey, currentDesktopOnly, groupByApp, includeMinimized }

    /// 少了键用默认值；快捷键键在但是 null 表示用户清空了；读不懂的快捷键当默认。
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if c.contains(.hotKey) {
            if (try? c.decodeNil(forKey: .hotKey)) == true {
                hotKey = nil
            } else {
                hotKey = (try? c.decode(KeyCombo.self, forKey: .hotKey)) ?? Self.defaultHotKey
            }
        } else {
            hotKey = Self.defaultHotKey
        }
        currentDesktopOnly = (try? c.decodeIfPresent(Bool.self, forKey: .currentDesktopOnly)) ?? false
        groupByApp = (try? c.decodeIfPresent(Bool.self, forKey: .groupByApp)) ?? false
        includeMinimized = (try? c.decodeIfPresent(Bool.self, forKey: .includeMinimized)) ?? true
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let hotKey { try c.encode(hotKey, forKey: .hotKey) } else { try c.encodeNil(forKey: .hotKey) }
        try c.encode(currentDesktopOnly, forKey: .currentDesktopOnly)
        try c.encode(groupByApp, forKey: .groupByApp)
        try c.encode(includeMinimized, forKey: .includeMinimized)
    }

    /// 真正要注册的快捷键：没设、缺 ⌃⌥⌘ 的不注册。
    public var registrableHotKey: KeyCombo? {
        hotKey.flatMap { $0.hasRequiredModifier ? $0 : nil }
    }
}

public enum WindowSwitcherHotKeyAdvice {
    /// 录到常见冲突时在设置里提醒一句，不拒收。
    public static func warning(for combo: KeyCombo?, others: [KeyCombo?] = []) -> String? {
        guard let combo else { return nil }
        typealias M = KeyCombo.Modifier
        if combo.keyCode == 48, combo.modifiers & M.command != 0,
           combo.modifiers & (M.option | M.control) == 0 {
            return tr("⌘Tab 是系统切换 App 的快捷键，建议换一个。")
        }
        if others.contains(where: { $0 == combo }) {
            return tr("和码头里另一个快捷键一样，只有一个会生效。")
        }
        return nil
    }
}

// MARK: - 列表

/// ⌥Tab 窗口切换器里能测的部分：排序、过滤、分组、搜索、选中移动、按键含义和布局。
/// 读窗口、截图、激活窗口在 App 里（`WindowCatalog`、`WindowSwitcherController`）。
public enum WindowSwitcher {

    /// 窗口在哪个桌面。拿不到桌面号时 `other(nil)`，卡片只标「其他桌面」。
    public enum Desktop: Equatable, Hashable, Sendable {
        case current
        case other(Int?)
    }

    /// 一个窗口，排序和搜索要的字段全是值。
    public struct Entry: Equatable, Identifiable, Sendable {
        /// 这次打开里唯一的编号。
        public var id: Int
        /// 跨多次打开认得出同一个窗口的键（系统窗口号，拿不到时进程加标题加位置）。
        public var key: String
        public var pid: Int32
        public var appName: String
        public var title: String
        /// 在当前桌面屏幕上从前往后的位置，0 是最前面那个窗口；不在屏幕上是 nil。
        public var zOrder: Int?
        /// App 最近被切到前台的先后，0 是最近。
        public var appRank: Int
        /// 在这个 App 自己的窗口列表里的位置（系统给的，一般最近用的在前）。
        public var windowIndex: Int
        public var minimized: Bool
        /// App 被隐藏（⌘H）。
        public var hidden: Bool
        public var desktop: Desktop

        public init(id: Int, key: String = "", pid: Int32 = 0, appName: String, title: String,
                    zOrder: Int? = nil, appRank: Int = 0, windowIndex: Int = 0,
                    minimized: Bool = false, hidden: Bool = false, desktop: Desktop = .current) {
            self.id = id
            self.key = key.isEmpty ? "\(id)" : key
            self.pid = pid
            self.appName = appName
            self.title = title
            self.zOrder = zOrder
            self.appRank = appRank
            self.windowIndex = windowIndex
            self.minimized = minimized
            self.hidden = hidden
            self.desktop = desktop
        }

        /// 已最小化或 App 已隐藏：卡片半透明。
        public var dimmed: Bool { minimized || hidden }
    }

    // MARK: 排序（最近使用）

    /// 按最近使用排：
    /// 1. 当前最前面的窗口；
    /// 2. `previous`：上次用切换器离开的那个窗口（只在最前面还是上次切过去的窗口时传），
    ///    这样连按两次 ⌥Tab 总能回到原处，哪怕它在别的桌面；
    /// 3. 当前桌面屏幕上的其他窗口，按前后（系统的叠放次序就是最近用的次序）；
    /// 4. 别的桌面上的窗口，按 App 最近用的先后，同一个 App 按它自己的先后；
    /// 5. 已最小化、已隐藏的，同样按 App 先后。
    public static func ordered(_ entries: [Entry], previous: String? = nil) -> [Entry] {
        func tier(_ e: Entry) -> Int {
            if e.dimmed { return 4 }
            if e.zOrder == 0 { return 0 }
            if let previous, e.key == previous { return 1 }
            if e.zOrder != nil { return 2 }
            return 3
        }
        return entries.enumerated().sorted { a, b in
            let x = a.element, y = b.element
            let tx = tier(x), ty = tier(y)
            if tx != ty { return tx < ty }
            if tx == 2, let zx = x.zOrder, let zy = y.zOrder, zx != zy { return zx < zy }
            if x.appRank != y.appRank { return x.appRank < y.appRank }
            if x.windowIndex != y.windowIndex { return x.windowIndex < y.windowIndex }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// 按设置过滤：只显示当前桌面时去掉确定在别的桌面上的；不含最小化时去掉已最小化、已隐藏的。
    public static func filtered(_ entries: [Entry], settings: WindowSwitcherSettings) -> [Entry] {
        entries.filter { e in
            if !settings.includeMinimized, e.dimmed { return false }
            if settings.currentDesktopOnly, case .other = e.desktop { return false }
            return true
        }
    }

    /// 按 App 分组：App 按它排得最前的那个窗口的先后排，组内保持原来的先后。
    public static func grouped(_ entries: [Entry]) -> [Entry] {
        var firstSeen: [Int32: Int] = [:]
        for (i, e) in entries.enumerated() where firstSeen[e.pid] == nil { firstSeen[e.pid] = i }
        return entries.enumerated().sorted { a, b in
            let ga = firstSeen[a.element.pid] ?? 0, gb = firstSeen[b.element.pid] ?? 0
            if ga != gb { return ga < gb }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// 排序、过滤、分组一步做完，给面板用。
    public static func arrange(_ entries: [Entry], settings: WindowSwitcherSettings,
                               previous: String? = nil) -> [Entry] {
        let list = filtered(ordered(entries, previous: previous), settings: settings)
        return settings.groupByApp ? grouped(list) : list
    }

    /// 刚弹出时选中第二个（上一个用过的窗口），只有一个时选它。排第一的不是前台 App 的
    /// 当前窗口时（比如点了桌面，前台是没有窗口的访达）选第一个。
    public static func initialSelection(count: Int, firstIsFront: Bool = true) -> Int {
        count > 1 && firstIsFront ? 1 : 0
    }

    // MARK: 卡片文字

    /// 卡片底下那一行：「备忘录 · 周末采购清单」。没标题或标题就是 App 名时只写 App 名。
    public static func cardTitle(appName: String, title: String) -> String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || t == appName || t == tr("无标题窗口") { return appName }
        if appName.isEmpty { return t }
        return "\(appName) · \(t)"
    }

    /// 缩略图右上角的小角标，一张卡片最多一个：最小化优先，其次隐藏，再其次别的桌面。
    public enum Badge: Equatable, Sendable {
        case minimized
        case hidden
        case desktop(Int?)

        public var text: String {
            switch self {
            case .minimized: tr("已最小化")
            case .hidden: tr("已隐藏")
            case .desktop(let n?): tr("桌面 \(n)")
            case .desktop(nil): tr("其他桌面")
            }
        }
    }

    public static func badge(for e: Entry) -> Badge? {
        if e.minimized { return .minimized }
        if e.hidden { return .hidden }
        if case .other(let n) = e.desktop { return .desktop(n) }
        return nil
    }

    /// 顶上搜索框右边：「6 个窗口」。
    public static func countText(_ n: Int) -> String {
        tr("\(n) 个窗口")
    }

    // MARK: 选中移动

    /// 前后移动，到头环绕。
    public static func step(_ index: Int, by delta: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let i = ((index % count) + count) % count
        return (((i + delta) % count) + count) % count
    }

    /// 上下移动一行（按行从左到右排的网格）。目标格子不存在时：往下落到最后一个，
    /// 往上不动；只有一行时不动。
    public static func vertical(_ index: Int, rows delta: Int, columns: Int, count: Int) -> Int {
        guard count > 0, columns > 0 else { return 0 }
        let i = min(max(0, index), count - 1)
        let target = i + delta * columns
        if target >= 0, target < count { return target }
        if delta > 0, i / columns < (count - 1) / columns { return count - 1 }
        return i
    }

    // MARK: 按键

    /// 弹出期间一次按键的意思。
    public enum KeyAction: Equatable, Sendable {
        case next, previous, left, right, up, down
        case commit, cancel
        case closeWindow, minimizeWindow, quitApp
        /// 开始搜索但还没有字（按了 /）。
        case startSearch
        case type(String)
        case backspace
        /// 不认识的键：吞掉，什么也不做。
        case ignore
        /// 带 ⌘ 的组合：收起切换器，把按键交还给前台 App。
        case passThrough
    }

    /// 键码（ANSI 布局，按物理位置，和输入法无关）。
    public enum Key {
        public static let tab: UInt32 = 48
        public static let returnKey: UInt32 = 36
        public static let enter: UInt32 = 76
        public static let escape: UInt32 = 53
        public static let delete: UInt32 = 51
        public static let forwardDelete: UInt32 = 117
        public static let left: UInt32 = 123
        public static let right: UInt32 = 124
        public static let down: UInt32 = 125
        public static let up: UInt32 = 126
        public static let w: UInt32 = 13
        public static let m: UInt32 = 46
        public static let q: UInt32 = 12
        public static let slash: UInt32 = 44
        public static let space: UInt32 = 49
    }

    /// - Parameters:
    ///   - keyCode: 按下的键。
    ///   - characters: 不算修饰键时这个键打出的字（`charactersIgnoringModifiers`）。
    ///   - modifiers: Carbon 修饰键位（`KeyCombo.Modifier`）。
    ///   - triggerKey: 快捷键本身的键（默认 Tab），按它也是下一个。
    ///   - searching: 已经在搜索（打过字或按过 /）：W、M、Q 当字打进搜索框。
    public static func action(keyCode: UInt32, characters: String, modifiers: UInt32,
                              triggerKey: UInt32 = Key.tab, searching: Bool) -> KeyAction {
        typealias M = KeyCombo.Modifier
        let shift = modifiers & M.shift != 0
        switch keyCode {
        case Key.escape: return .cancel
        case Key.returnKey, Key.enter: return .commit
        case Key.left: return .left
        case Key.right: return .right
        case Key.up: return .up
        case Key.down: return .down
        default: break
        }
        if keyCode == triggerKey || keyCode == Key.tab {
            return shift ? .previous : .next
        }
        if modifiers & M.command != 0 { return .passThrough }
        if keyCode == Key.delete || keyCode == Key.forwardDelete {
            return searching ? .backspace : .ignore
        }
        if !searching {
            switch keyCode {
            case Key.w: return .closeWindow
            case Key.m: return .minimizeWindow
            case Key.q: return .quitApp
            case Key.slash: return .startSearch
            case Key.space: return .ignore
            default: break
            }
        }
        let text = characters.lowercased()
        guard text.count == 1, let ch = text.unicodeScalars.first,
              CharacterSet.alphanumerics.contains(ch) || (searching && (ch == " " || CharacterSet.punctuationCharacters.contains(ch)))
        else { return .ignore }
        return .type(text)
    }

    /// 快捷键的修饰键（不算 ⇧）有没有松开：任何一个松开就算，松开就切换。
    public static func released(trigger: UInt32, current: UInt32) -> Bool {
        typealias M = KeyCombo.Modifier
        let held = trigger & (M.control | M.option | M.command)
        guard held != 0 else { return true }
        return current & held != held
    }
}

// MARK: - 搜索

/// 搜索匹配：App 名和窗口标题，不分大小写，也认拼音全拼和首字母（「微信」打 wx 或 weixin）。
public enum WindowSwitcherSearch {

    /// 一个窗口的搜索索引。拼音只在第一次打字时算一次。
    public struct Index: Equatable, Sendable {
        public var app: String
        public var title: String
        public var appPinyin: String
        public var appInitials: String
        public var titlePinyin: String
        public var titleInitials: String

        public init(appName: String, title: String) {
            app = normalized(appName)
            self.title = normalized(title)
            let a = pinyin(appName)
            let t = pinyin(title)
            appPinyin = a.full
            appInitials = a.initials
            titlePinyin = t.full
            titleInitials = t.initials
        }
    }

    static func normalized(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// 全拼（去声调、去空格）和首字母。汉字用系统的汉字转拉丁字母；英文单词各取首字母。
    public static func pinyin(_ text: String) -> (full: String, initials: String) {
        guard text.unicodeScalars.contains(where: { (0x3400...0x9FFF).contains($0.value) }) else {
            let words = normalized(text).split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            return (words.joined(), String(words.compactMap(\.first)))
        }
        let latin = (text.applyingTransform(.mandarinToLatin, reverse: false) ?? text)
        let plain = normalized(latin)
        let words = plain.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        return (words.joined(), String(words.compactMap(\.first)))
    }

    /// 匹配得多好，越小越靠前；不匹配是 nil。多个词用空格分开时每个词都要匹配。
    public static func score(_ query: String, _ index: Index) -> Int? {
        let tokens = normalized(query).split(separator: " ").map(String.init).filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return 0 }
        var worst = 0
        for token in tokens {
            guard let s = tokenScore(token, index) else { return nil }
            worst = max(worst, s)
        }
        return worst
    }

    private static func tokenScore(_ q: String, _ i: Index) -> Int? {
        if i.app.hasPrefix(q) || i.title.hasPrefix(q) { return 0 }
        if i.appInitials.hasPrefix(q) || i.titleInitials.hasPrefix(q)
            || i.appPinyin.hasPrefix(q) || i.titlePinyin.hasPrefix(q) { return 1 }
        if wordStart(q, i.app) || wordStart(q, i.title) { return 2 }
        if i.app.contains(q) || i.title.contains(q) { return 3 }
        if i.appPinyin.contains(q) || i.titlePinyin.contains(q)
            || i.appInitials.contains(q) || i.titleInitials.contains(q) { return 4 }
        return nil
    }

    private static func wordStart(_ q: String, _ s: String) -> Bool {
        s.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains { $0.hasPrefix(q) }
    }

    /// 按匹配程度过滤并排序，同样程度的保持原来（最近使用）的先后。返回原列表里的位置。
    public static func filter(_ query: String, indexes: [Index]) -> [Int] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Array(indexes.indices) }
        return indexes.enumerated()
            .compactMap { offset, index in score(q, index).map { (offset, $0) } }
            .sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.0 < $1.0 }
            .map(\.0)
    }
}

// MARK: - 布局

/// 面板和卡片的尺寸（pt）。照效果图 design/window-switcher.png：卡片 186 宽，缩略图 112 高，
/// 间距 14，左右内边距 26；窗口多时先换行，再缩小卡片，到上限后横向滚动。
public enum WindowSwitcherLayout {
    public static let cardWidth: CGFloat = 186
    public static let thumbnailHeight: CGFloat = 112
    /// 卡片里缩略图四周的留白。
    public static let cardInset: CGFloat = 10
    /// 图标加标题那一行。
    public static let captionHeight: CGFloat = 22
    public static let gap: CGFloat = 14
    public static let paddingX: CGFloat = 26
    public static let paddingTop: CGFloat = 22
    public static let searchHeight: CGFloat = 40
    public static let searchGap: CGFloat = 24
    public static let hintsGap: CGFloat = 18
    public static let hintsHeight: CGFloat = 22
    public static let paddingBottom: CGFloat = 20
    /// 选中时往上抬多少。
    public static let lift: CGFloat = 4
    /// 面板最窄，放得下搜索框和底部按键提示。
    public static let minPanelWidth: CGFloat = 600
    /// 面板最多占屏幕可见范围的比例。
    public static let maxWidthFraction: CGFloat = 0.9
    public static let maxHeightFraction: CGFloat = 0.82
    /// 最多几行，再多就缩小卡片，缩到最小后横向滚动。
    public static let maxRows = 3
    /// 依次试的缩放。
    public static let scales: [CGFloat] = [1, 0.9, 0.8, 0.72]

    public struct Layout: Equatable, Sendable {
        public var scale: CGFloat
        /// 一行几张（滚动时是总列数）。
        public var columns: Int
        public var rows: Int
        /// 一屏露出几列。
        public var visibleColumns: Int
        public var scrolls: Bool
        public var cardSize: CGSize
        public var thumbnailSize: CGSize
        /// 卡片区露出部分的大小。
        public var gridSize: CGSize
        public var panelSize: CGSize
    }

    public static func cardSize(scale: CGFloat) -> CGSize {
        let width = (cardWidth * scale).rounded()
        let thumb = (thumbnailHeight * scale).rounded()
        return CGSize(width: width, height: cardInset + thumb + cardInset + captionHeight + cardInset)
    }

    public static func thumbnailSize(scale: CGFloat) -> CGSize {
        CGSize(width: (cardWidth * scale).rounded() - 2 * cardInset, height: (thumbnailHeight * scale).rounded())
    }

    /// 卡片以外的高度：顶边、搜索框、间距、按键提示、底边。
    public static var chromeHeight: CGFloat {
        paddingTop + searchHeight + searchGap + hintsGap + hintsHeight + paddingBottom
    }

    /// - Parameters:
    ///   - count: 卡片数，0 时按一张卡片的高度留出空状态。
    ///   - visible: 所在屏幕可见范围的大小。
    public static func layout(count: Int, visible: CGSize) -> Layout {
        let n = max(1, count)
        let maxWidth = max(minPanelWidth, visible.width * maxWidthFraction)
        let maxGridHeight = max(cardSize(scale: scales.last ?? 1).height,
                                visible.height * maxHeightFraction - chromeHeight)

        func fitColumns(_ card: CGSize) -> Int {
            max(1, Int((maxWidth - 2 * paddingX + gap) / (card.width + gap)))
        }
        func rowsThatFit(_ card: CGSize) -> Int {
            max(1, min(maxRows, Int((maxGridHeight + gap) / (card.height + gap))))
        }

        for scale in scales {
            let card = cardSize(scale: scale)
            let columns = min(n, fitColumns(card))
            let rows = Int((Double(n) / Double(columns)).rounded(.up))
            if rows <= rowsThatFit(card) {
                return make(scale: scale, columns: columns, rows: rows, visibleColumns: columns,
                            scrolls: false, count: count)
            }
        }
        let scale = scales.last ?? 1
        let card = cardSize(scale: scale)
        let rows = rowsThatFit(card)
        let columns = Int((Double(n) / Double(rows)).rounded(.up))
        return make(scale: scale, columns: columns, rows: rows, visibleColumns: min(columns, fitColumns(card)),
                    scrolls: true, count: count)
    }

    private static func make(scale: CGFloat, columns: Int, rows: Int, visibleColumns: Int,
                             scrolls: Bool, count: Int) -> Layout {
        let card = cardSize(scale: scale)
        let gridWidth = CGFloat(visibleColumns) * card.width + CGFloat(max(0, visibleColumns - 1)) * gap
        let gridHeight = CGFloat(rows) * card.height + CGFloat(max(0, rows - 1)) * gap
        let panelWidth = max(minPanelWidth, gridWidth + 2 * paddingX)
        return Layout(scale: scale, columns: columns, rows: rows, visibleColumns: visibleColumns,
                      scrolls: scrolls, cardSize: card, thumbnailSize: thumbnailSize(scale: scale),
                      gridSize: CGSize(width: gridWidth, height: gridHeight),
                      panelSize: CGSize(width: panelWidth, height: gridHeight + chromeHeight))
    }

    /// 面板左下角（AppKit 屏幕坐标）：在可见范围里水平居中，竖直略偏上（上下留白 4:6）。
    public static func origin(size: CGSize, visible: CGRect) -> CGPoint {
        let x = visible.minX + ((visible.width - size.width) / 2).rounded()
        let free = max(0, visible.height - size.height)
        let y = visible.minY + (free * 0.6).rounded()
        return CGPoint(x: x, y: y)
    }

    /// 缩略图要截多大（像素）：窗口按比例铺满缩略图框（多出来的裁掉），再乘屏幕倍数。
    public static func captureSize(window: CGSize, box: CGSize, scale: CGFloat) -> CGSize {
        let s = max(1, scale)
        guard window.width > 0, window.height > 0 else {
            return CGSize(width: box.width * s, height: box.height * s)
        }
        let ratio = min(1, max(box.width / window.width, box.height / window.height))
        return CGSize(width: max(1, (window.width * ratio * s).rounded()),
                      height: max(1, (window.height * ratio * s).rounded()))
    }
}
