import Foundation

/// 便签 v3 的编辑器：清单行写字时和不写字时是同一个样子。
///
/// 原文照旧是一整段字（`[ ] 牛奶`、`【】鸡蛋`），存法不变。编辑器里每个认得的框子
/// 换成一个占位字 `U+FFFC`（附件），画成能点的圆圈；框后的字照常编辑。原文和编辑器里
/// 的字一行对一行，行数一样，所以选区落在第几行两边一致。
///
/// 圆圈记着原来那几个框子字（`token`），没动过的行还原回去一字不差，打开便签不会因为
/// 换了写法被改写、多存一次。
public enum StickyEditing {
    /// 编辑器里代替框子的占位字（附件字符）。
    public static let mark: Character = "\u{FFFC}"
    public static let markUnit: UInt16 = 0xFFFC

    /// 一个框子：原文里的那几个字（含框后的空格）和勾没勾。
    public struct Box: Equatable, Sendable {
        public var token: String
        public var done: Bool

        public init(token: String, done: Bool) {
            self.token = token
            self.done = done
        }

        public static let open = Box(token: "[ ] ", done: false)

        /// 点一下：写回时统一成 `[x] ` / `[ ] `，和 `StickyChecklist.toggling` 一样。
        public var toggled: Box { Box(token: done ? "[ ] " : "[x] ", done: !done) }
    }

    /// 一行：缩进和列表符号（原样显示）、框子（画成圆圈）、框后的字。
    public struct Piece: Equatable, Sendable {
        public var prefix: String
        public var box: Box?
        public var rest: String

        public init(prefix: String = "", box: Box? = nil, rest: String) {
            self.prefix = prefix
            self.box = box
            self.rest = rest
        }

        public var isItem: Bool { box != nil }
        /// 编辑器里这一行的字：框子换成一个占位字。
        public var display: String { prefix + (box == nil ? "" : String(StickyEditing.mark)) + rest }
        /// 原文里这一行。
        public var raw: String { prefix + (box?.token ?? "") + rest }
    }

    // MARK: 原文 ↔ 编辑器

    public static func pieces(_ text: String) -> [Piece] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { piece(raw: $0) }
    }

    static func piece(raw line: Substring) -> Piece {
        guard let box = StickyChecklist.box(line) else { return Piece(rest: String(line)) }
        let token = String(line[box.prefix.endIndex..<box.rest.startIndex])
        return Piece(prefix: String(box.prefix), box: Box(token: token, done: box.done), rest: String(box.rest))
    }

    public static func raw(_ pieces: [Piece]) -> String {
        pieces.map(\.raw).joined(separator: "\n")
    }

    /// 编辑器里该有的整段字。
    public static func display(_ text: String) -> String {
        pieces(text).map(\.display).joined(separator: "\n")
    }

    /// 编辑器里一行的内容：字和圆圈。
    public enum Run: Equatable, Sendable {
        case text(String)
        case box(Box)
    }

    /// 编辑器里的一行还原成原文的一行。
    ///
    /// 只认行首（缩进、一个列表符号之后）的第一个圆圈；被挪到行中间的圆圈（删掉换行
    /// 把两行接在一起、拖动）去掉，字留下。字里混进来的裸占位字（粘贴来的）也去掉。
    public static func rawLine(_ runs: [Run]) -> String {
        var before = ""
        var box: Box?
        var after = ""
        for run in runs {
            switch run {
            case .text(let words):
                let clean = words.filter { $0 != mark }
                if box == nil { before += clean } else { after += clean }
            case .box(let found):
                guard box == nil, isPrefix(before) else { continue }
                box = found
            }
        }
        guard let box else { return before }
        return before + box.token + after
    }

    /// 圆圈前面只能是缩进，或者缩进加一个列表符号（`-`、`*`、`+`）再加空格。
    static func isPrefix(_ text: String) -> Bool {
        let core = text.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
        if core.isEmpty { return true }
        guard core.count == 1, let first = core.first else { return false }
        return StickyChecklist.bullets.contains(first)
    }

    // MARK: 回车

    public enum Return: Equatable, Sendable {
        /// 输入法正在组字：交给输入法上屏，不插行、不换行。
        case passThrough
        /// 普通换行。
        case newline
        /// 在这一条后面插一条空的清单项，光标进去。
        case nextItem
        /// 空的一条上再回车：去掉圆圈，退出清单。
        case endItem
        /// ⌘↩：存好，收起编辑。
        case collapse
    }

    /// 回车往哪去。组字时最先判断：中文输入法用回车上屏英文，这一下不能插行（2e38f63
    /// 修过组字闪退，这里也不碰组字中的字）。
    public static func returnAction(command: Bool, shift: Bool, option: Bool,
                                    composing: Bool, line: Piece?) -> Return {
        if composing { return .passThrough }
        if command { return .collapse }
        if shift || option { return .newline }
        guard let line, line.isItem else { return .newline }
        return line.rest.trimmingCharacters(in: .whitespaces).isEmpty ? .endItem : .nextItem
    }

    /// 回车接着写的下一条：缩进和列表符号照这一条，空框。
    public static func nextItem(after line: Piece) -> Piece {
        Piece(prefix: line.prefix, box: .open, rest: "")
    }

    /// 退出清单后的这一行：只留缩进，列表符号和圆圈都去掉。
    public static func endingItem(_ line: Piece) -> Piece {
        let indent = line.prefix.prefix { $0 == " " || $0 == "\t" }
        return Piece(prefix: String(indent), box: nil, rest: line.rest)
    }

    // MARK: 光标

    /// 光标在编辑器里第几行、离行尾多少个 UTF-16 单位。框子换写法只动行首，
    /// 按离行尾算，重画这一行后光标还在原来那个字旁边。
    public static func caretAnchor(in display: String, utf16 location: Int) -> (line: Int, fromEnd: Int) {
        let units = Array(display.utf16)
        let at = min(max(0, location), units.count)
        var line = 0
        for unit in units[0..<at] where unit == 10 { line += 1 }
        var end = at
        while end < units.count, units[end] != 10 { end += 1 }
        return (line, end - at)
    }

    /// 反过来：第 `line` 行离行尾 `fromEnd` 的位置。不会落到行首的圆圈前面。
    public static func location(in display: String, line: Int, fromEnd: Int) -> Int {
        let units = Array(display.utf16)
        var start = 0
        var current = 0
        while current < line, let next = units[start...].firstIndex(of: 10) {
            start = next + 1
            current += 1
        }
        if current < line { return units.count }
        var end = start
        while end < units.count, units[end] != 10 { end += 1 }
        let floor = firstEditable(units, lineStart: start, lineEnd: end)
        return max(floor, end - max(0, fromEnd))
    }

    /// 这一行里光标最靠前能放的位置：有圆圈就在圆圈后面。
    static func firstEditable(_ units: [UInt16], lineStart: Int, lineEnd: Int) -> Int {
        guard let markAt = units[lineStart..<lineEnd].firstIndex(of: markUnit) else { return lineStart }
        return markAt + 1
    }

    /// 光标落在一行的圆圈前面时挪到它后面（打的字进框后，不把圆圈挤到行中间）。
    /// 从圆圈后面往左一格时跳到上一行行尾，左方向键不会卡住。
    public static func adjustedCaret(in display: String, from old: Int, to proposed: Int) -> Int {
        let units = Array(display.utf16)
        guard proposed >= 0, proposed < units.count, units[proposed] == markUnit else { return proposed }
        var start = proposed
        while start > 0, units[start - 1] != 10 { start -= 1 }
        // 圆圈前只有缩进、列表符号时才算行首的圆圈。
        let before = String(decoding: units[start..<proposed], as: UTF16.self)
        guard isPrefix(before) else { return proposed }
        if old == proposed + 1 {
            return start > 0 ? start - 1 : proposed + 1
        }
        return proposed + 1
    }

    // MARK: 发到快速待办

    /// 右键「发到快速待办」发出去的那一句：清单项去掉框子，普通行去掉列表符号，
    /// 去掉首尾空白，按快速待办的长度上限截；空行没有。
    public static func sendable(line index: Int, in text: String) -> String? {
        let all = pieces(text)
        guard all.indices.contains(index) else { return nil }
        let piece = all[index]
        var words = piece.rest
        if !piece.isItem {
            let trimmed = words.trimmingCharacters(in: .whitespaces)
            for marker in ["- ", "* ", "+ ", "• ", "· "] where trimmed.hasPrefix(marker) {
                words = String(trimmed.dropFirst(marker.count))
                break
            }
        }
        return QuickTodo.clean(words)
    }
}
