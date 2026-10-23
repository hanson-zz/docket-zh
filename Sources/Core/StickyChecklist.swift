import Foundation

// MARK: - 字体和字号

/// 便签的字体：手写（原来的手札体）、普通（系统字体）、等宽。整张便签一种，
/// 存在卡片配置 `font` 里；认不出的按手写，旧便签样子不变。
public enum StickyNoteFont: String, CaseIterable, Sendable {
    case hand, regular, mono

    public static let key = "font"
    public static let fallback = StickyNoteFont.hand

    public init(stored raw: String) { self = StickyNoteFont(rawValue: raw) ?? Self.fallback }

    public static func of(_ config: WidgetConfig) -> StickyNoteFont {
        StickyNoteFont(stored: config.string(key, default: fallback.rawValue))
    }

    public var title: String {
        switch self {
        case .hand: tr("手写")
        case .regular: tr("普通")
        case .mono: tr("等宽")
        }
    }

    /// 手札体同样字号看着小一圈，普通和等宽缩一点才和它一样大。
    var scale: Double {
        switch self {
        case .hand: 1
        case .regular: 0.84
        case .mono: 0.8
        }
    }
}

/// 便签的字号：小、中、大。中就是原来的大小（面板 22、卡片 15、竖排 12）。
/// 存在 `fontSize` 里；认不出的按中。
public enum StickyNoteSize: String, CaseIterable, Sendable {
    case small, medium, large

    public static let key = "fontSize"
    public static let fallback = StickyNoteSize.medium

    public init(stored raw: String) { self = StickyNoteSize(rawValue: raw) ?? Self.fallback }

    public static func of(_ config: WidgetConfig) -> StickyNoteSize {
        StickyNoteSize(stored: config.string(key, default: fallback.rawValue))
    }

    public var title: String {
        switch self {
        case .small: tr("小")
        case .medium: tr("中")
        case .large: tr("大")
        }
    }

    var scale: Double {
        switch self {
        case .small: 0.8
        case .medium: 1
        case .large: 1.22
        }
    }
}

/// 便签字在各处的字号。
public enum StickyNoteType {
    public static let panelBase = 22.0
    public static let cardBase = 15.0
    public static let columnBase = 12.0
    /// 面板里的字不小于 13pt。
    public static let panelMinimum = 13.0
    /// 卡片 58pt 高，再小手札体就糊了。
    public static let cardMinimum = 10.0

    public static func panel(_ font: StickyNoteFont, _ size: StickyNoteSize) -> Double {
        max(panelMinimum, (panelBase * font.scale * size.scale).rounded())
    }

    public static func card(_ font: StickyNoteFont, _ size: StickyNoteSize, column: Bool) -> Double {
        max(cardMinimum, ((column ? columnBase : cardBase) * font.scale * size.scale).rounded())
    }
}

// MARK: - 清单项

/// 便签上的勾选行。行首这些写法都算一个清单项（前面可以有空格，以及 `-`、`*`、`+`
/// 这类列表符号，符号后的空格可有可无）：
///
/// - 没勾的：`[ ]`、`[]`、中文输入法打出来的 `【】`、全角 `［］`，以及单独的
///   `☐`、`□`、`○`、`◯`；
/// - 勾上的：框里写 `x`、`X`、`✓`、`√`、`✔`，以及单独的 `☑`、`✓`、`✔`（单独的 `√` 不算，免得把「√2」当成清单）。
///
/// 点圆圈只改这一行的框，字一个不动。字照旧整段存在 `text` 里，没有另外的结构：
/// 设置页的「便签内容」、拖进来的文字、旧便签都不用迁移，删掉框子就变回普通的一行字。
///
/// 框里写了别的（`[1]`、`[a]`、`[?]`）认不出，不偷偷改字，面板在纸底问一次
/// 「变成清单」（`ambiguousLines`）。
public enum StickyChecklist {
    public enum Line: Equatable, Sendable {
        case text(String)
        case item(done: Bool, text: String)
    }

    /// 一行和它在原文里是第几行（从 0 起），面板按原来的行号去勾。
    public struct Row: Equatable, Sendable {
        public var index: Int
        public var line: Line

        public init(index: Int, line: Line) {
            self.index = index
            self.line = line
        }
    }

    /// 框子：`prefix` 是缩进和列表符号，`rest` 是框后的字（框后的空格算框子的一部分）。
    struct Box {
        var prefix: Substring
        var done: Bool
        var rest: Substring
    }

    static let openers: [Character: Character] = ["[": "]", "【": "】", "［": "］"]
    static let doneMarks: Set<String> = ["x", "X", "✓", "√", "✔"]
    static let openGlyphs: Set<Character> = ["☐", "□", "○", "◯"]
    // 单独的 √ 不算：行首写「√2 ≈ 1.414」的不少，√ 只在框里认。
    static let doneGlyphs: Set<Character> = ["☑", "✓", "✔"]
    static let bullets: Set<Character> = ["-", "*", "+"]

    private static func skipSpaces(_ line: Substring, from i: Substring.Index) -> Substring.Index {
        var i = i
        while i < line.endIndex, line[i] == " " || line[i] == "\t" { i = line.index(after: i) }
        return i
    }

    /// 方括号框：返回框里的字（去掉空白）和收口后面的位置。框里最多两个字。
    private static func bracket(_ tail: Substring) -> (mark: String, end: Substring.Index)? {
        guard let open = tail.first, let close = openers[open] else { return nil }
        var j = tail.index(after: tail.startIndex)
        var inner = ""
        while j < tail.endIndex, tail[j] != close, inner.count < 4 {
            inner.append(tail[j])
            j = tail.index(after: j)
        }
        guard j < tail.endIndex, tail[j] == close else { return nil }
        return (inner.trimmingCharacters(in: .whitespaces), tail.index(after: j))
    }

    /// 一个框子从 `tail` 开头起：认得的返回勾没勾和框后的位置。
    private static func mark(_ tail: Substring) -> (done: Bool, end: Substring.Index)? {
        guard let first = tail.first else { return nil }
        if let found = bracket(tail) {
            if found.mark.isEmpty { return (false, found.end) }
            if doneMarks.contains(found.mark) { return (true, found.end) }
            return nil
        }
        if openGlyphs.contains(first) { return (false, tail.index(after: tail.startIndex)) }
        if doneGlyphs.contains(first) { return (true, tail.index(after: tail.startIndex)) }
        return nil
    }

    /// 缩进和列表符号之后的位置：只有符号后面真有框子时才把符号算进去。
    private static func boxStart(_ line: Substring) -> Substring.Index {
        let i = skipSpaces(line, from: line.startIndex)
        guard i < line.endIndex, bullets.contains(line[i]) else { return i }
        let k = skipSpaces(line, from: line.index(after: i))
        if k < line.endIndex, mark(line[k...]) != nil || bracket(line[k...]) != nil { return k }
        return i
    }

    static func box(_ line: Substring) -> Box? {
        let i = boxStart(line)
        guard let found = mark(line[i...]) else { return nil }
        let k = skipSpaces(line, from: found.end)
        return Box(prefix: line[line.startIndex..<i], done: found.done, rest: line[k...])
    }

    private static func splitRows(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    public static func lines(_ text: String) -> [Line] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { raw in
            if let box = box(raw) { return .item(done: box.done, text: String(box.rest)) }
            return .text(String(raw))
        }
    }

    public static func hasItems(_ text: String) -> Bool {
        lines(text).contains { if case .item = $0 { true } else { false } }
    }

    /// 切换第 `index` 行的框。不是清单项的行、越界的不动。写回时框子统一成
    /// `[x] ` / `[ ] `，缩进、列表符号和字不动。
    public static func toggling(line index: Int, in text: String) -> String {
        var rows = splitRows(text)
        guard rows.indices.contains(index), let box = box(Substring(rows[index])) else { return text }
        rows[index] = String(box.prefix) + (box.done ? "[ ] " : "[x] ") + String(box.rest)
        return rows.joined(separator: "\n")
    }

    /// 写字时按回车：最后一行是有字的清单项，就另起一行接一个空框，接着写；
    /// 最后一行是空框，把它去掉收尾；别的情况照旧收尾。
    public static func submitting(_ text: String) -> (text: String, keepWriting: Bool) {
        var rows = splitRows(text)
        guard let last = rows.last, let box = box(Substring(last)) else { return (text, false) }
        if !box.rest.trimmingCharacters(in: .whitespaces).isEmpty {
            return (text + "\n" + String(box.prefix) + "[ ] ", true)
        }
        rows.removeLast()
        return (rows.joined(separator: "\n"), false)
    }

    /// 卡片上只读的样子：框子画成 ☐ / ☑。
    public static func display(_ text: String) -> String {
        lines(text).map { line in
            switch line {
            case .text(let words): words
            case .item(let done, let words): (done ? "☑ " : "☐ ") + words
            }
        }.joined(separator: "\n")
    }

    /// 几项、勾了几项，卡片和面板的小字用。
    public static func progress(_ text: String) -> (done: Int, total: Int) {
        var done = 0, total = 0
        for case .item(let on, _) in lines(text) {
            total += 1
            if on { done += 1 }
        }
        return (done, total)
    }

    // MARK: 清单视图

    /// 「已完成沉到底部」存在这张便签的配置里，默认开；面板「⋯」菜单里关。
    public static let sinkKey = "sinkDone"

    public static func sinksDone(_ config: WidgetConfig) -> Bool {
        if case .bool(let on) = config[sinkKey] { return on }
        return true
    }

    /// 面板上清单的排法：`sinkDone` 时勾上的项挪到最后一组（只是显示，原文不动），
    /// 别的行照原来的顺序。末尾的空行不画。
    public static func layout(_ text: String, sinkDone: Bool) -> (open: [Row], done: [Row]) {
        var all = lines(text).enumerated().map { Row(index: $0.offset, line: $0.element) }
        while let last = all.last, case .text(let words) = last.line,
              words.trimmingCharacters(in: .whitespaces).isEmpty {
            all.removeLast()
        }
        guard sinkDone else { return (all, []) }
        var open: [Row] = []
        var done: [Row] = []
        for row in all {
            if case .item(true, _) = row.line { done.append(row) } else { open.append(row) }
        }
        return (open, done)
    }

    /// 标题行：清单前面第一行有字的普通行（在第一个清单项之前），进度 2/5 跟在它旁边。
    /// 没有清单项、或第一行就是清单项时没有标题。
    public static func titleLine(_ text: String) -> Int? {
        for (index, line) in lines(text).enumerated() {
            switch line {
            case .item: return nil
            case .text(let words):
                if words.trimmingCharacters(in: .whitespaces).isEmpty { continue }
                return hasItems(text) ? index : nil
            }
        }
        return nil
    }

    /// 全部取消勾选。
    public static func uncheckingAll(_ text: String) -> String {
        var rows = splitRows(text)
        for index in rows.indices {
            guard let box = box(Substring(rows[index])), box.done else { continue }
            rows[index] = String(box.prefix) + "[ ] " + String(box.rest)
        }
        return rows.joined(separator: "\n")
    }

    /// 清除已完成项：勾上的那几行整行去掉，返回去掉了几行。
    public static func removingDone(_ text: String) -> (text: String, removed: Int) {
        let rows = splitRows(text)
        let kept = rows.filter { row in
            guard let box = box(Substring(row)) else { return true }
            return !box.done
        }
        return (kept.joined(separator: "\n"), rows.count - kept.count)
    }

    // MARK: 转成清单

    /// 认不出的框：行首方括号里写了一到三个别的字（`[1]`、`[a]`、`[?]`），后面还有字。
    /// 不偷偷改，面板问一次要不要变成清单。`[链接](网址)` 这种 Markdown 链接不算。
    public static func ambiguousLines(_ text: String) -> [Int] {
        splitRows(text).enumerated().compactMap { index, row in
            ambiguous(Substring(row)) != nil ? index : nil
        }
    }

    /// 认不出的框之前的部分和框后的字。
    private static func ambiguous(_ line: Substring) -> (prefix: Substring, rest: Substring)? {
        guard box(line) == nil else { return nil }
        let i = boxStart(line)
        guard let found = bracket(line[i...]), (1...3).contains(found.mark.count) else { return nil }
        let k = skipSpaces(line, from: found.end)
        let rest = line[k...]
        guard !rest.isEmpty, rest.first != "(", rest.first != "（" else { return nil }
        return (line[line.startIndex..<i], rest)
    }

    /// 把认不出的框都换成空框：`[1]对对对` → `[ ] 对对对`。
    public static func convertingAmbiguous(_ text: String) -> String {
        var rows = splitRows(text)
        for index in rows.indices {
            guard let found = ambiguous(Substring(rows[index])) else { continue }
            rows[index] = String(found.prefix) + "[ ] " + String(found.rest)
        }
        return rows.joined(separator: "\n")
    }

    /// 普通列表的开头：`- `、`* `、`+ `、`• `、`1. `、`1、`、`1) `、`1）`。转清单时去掉，
    /// 免得变成 `[ ] - 牛奶`。
    private static func listMarkerEnd(_ line: Substring, from i: Substring.Index) -> Substring.Index {
        guard i < line.endIndex else { return i }
        let first = line[i]
        if bullets.contains(first) || first == "•" || first == "·" {
            let next = line.index(after: i)
            if next < line.endIndex, line[next] == " " { return skipSpaces(line, from: next) }
            return i
        }
        var j = i
        while j < line.endIndex, line[j].isASCII, line[j].isNumber { j = line.index(after: j) }
        guard j > i, j < line.endIndex, [".", "、", ")", "）"].contains(line[j]) else { return i }
        return skipSpaces(line, from: line.index(after: j))
    }

    /// 清单键（⌘⇧L）：把 `lines` 这几行变成清单项；都已经是清单项时反过来去掉框子。
    /// 空行跳过；只选了一行空行时放一个空框，接着写。认不出的框换成空框，普通列表的
    /// 符号去掉，缩进保留。
    public static func togglingItems(_ text: String, lines target: ClosedRange<Int>) -> String {
        var rows = splitRows(text)
        let last = rows.count - 1
        let lower = min(max(0, target.lowerBound), last)
        let range = lower...min(max(lower, target.upperBound), last)
        let picked = range.filter { !rows[$0].trimmingCharacters(in: .whitespaces).isEmpty }
        if picked.isEmpty {
            // 只在一行空行上：放一个空框，接着写。选了好几行空行不动。
            guard range.count == 1 else { return text }
            rows[range.lowerBound] += "[ ] "
            return rows.joined(separator: "\n")
        }
        let allItems = picked.allSatisfy { box(Substring(rows[$0])) != nil }
        for index in picked {
            let line = Substring(rows[index])
            if allItems {
                guard let box = box(line) else { continue }
                let indent = line[line.startIndex..<skipSpaces(line, from: line.startIndex)]
                rows[index] = String(indent) + String(box.rest)
            } else if box(line) == nil {
                if let found = ambiguous(line) {
                    rows[index] = String(found.prefix) + "[ ] " + String(found.rest)
                    continue
                }
                let start = skipSpaces(line, from: line.startIndex)
                let words = listMarkerEnd(line, from: start)
                rows[index] = String(line[line.startIndex..<start]) + "[ ] " + String(line[words...])
            }
        }
        return rows.joined(separator: "\n")
    }

    /// 选区（按字符数，从 0 起）落在第几行到第几行。越界的夹到首尾。
    public static func lineRange(in text: String, from start: Int, to end: Int) -> ClosedRange<Int> {
        func line(at offset: Int) -> Int {
            var count = 0
            for (position, character) in text.enumerated() {
                if position >= offset { break }
                if character == "\n" { count += 1 }
            }
            return count
        }
        let lower = max(0, min(start, end))
        var upper = max(0, max(start, end))
        // 选到下一行开头（三击选整行时）不算下一行。
        if upper > lower {
            let chars = Array(text)
            if upper - 1 < chars.count, chars[upper - 1] == "\n" { upper -= 1 }
        }
        return line(at: lower)...line(at: upper)
    }
}
