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

/// 便签上的勾选行：行首写 `[ ]`（或 `[]`，中文输入法打出来的 `【】` 也认）就是
/// 一个没勾的清单项，`[x]` 是勾上的。点框子只改这一行的框，字一个不动。
///
/// 字照旧整段存在 `text` 里，没有另外的结构：设置页的「便签内容」、拖进来的
/// 文字、旧便签都不用迁移，删掉框子就变回普通的一行字。
public enum StickyChecklist {
    public enum Line: Equatable, Sendable {
        case text(String)
        case item(done: Bool, text: String)
    }

    /// 框子：前面可以有空格和 `- `，框后的空格算框子的一部分。
    struct Box {
        var prefix: Substring
        var done: Bool
        var rest: Substring
    }

    static func box(_ line: Substring) -> Box? {
        var i = line.startIndex
        while i < line.endIndex, line[i] == " " || line[i] == "\t" { i = line.index(after: i) }
        if line[i...].hasPrefix("- ") { i = line.index(i, offsetBy: 2) }
        let prefix = line[line.startIndex..<i]
        let tail = line[i...]
        let openers: [Character: Character] = ["[": "]", "【": "】"]
        guard let open = tail.first, let close = openers[open] else { return nil }
        var j = tail.index(after: tail.startIndex)
        var inner = ""
        while j < tail.endIndex, tail[j] != close, inner.count < 2 {
            inner.append(tail[j])
            j = tail.index(after: j)
        }
        guard j < tail.endIndex, tail[j] == close else { return nil }
        let mark = inner.trimmingCharacters(in: .whitespaces)
        let done: Bool
        switch mark {
        case "": done = false
        case "x", "X", "✓", "√": done = true
        default: return nil
        }
        var k = tail.index(after: j)
        while k < tail.endIndex, tail[k] == " " { k = tail.index(after: k) }
        return Box(prefix: prefix, done: done, rest: tail[k...])
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
    /// `[x] ` / `[ ] `，字不动。
    public static func toggling(line index: Int, in text: String) -> String {
        var rows = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard rows.indices.contains(index), let box = box(Substring(rows[index])) else { return text }
        rows[index] = String(box.prefix) + (box.done ? "[ ] " : "[x] ") + String(box.rest)
        return rows.joined(separator: "\n")
    }

    /// 写字时按回车：最后一行是有字的清单项，就另起一行接一个空框，接着写；
    /// 最后一行是空框，把它去掉收尾；别的情况照旧收尾。
    public static func submitting(_ text: String) -> (text: String, keepWriting: Bool) {
        var rows = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
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
}
