import Foundation

/// 快速待办：一份只属于这个小组件的清单，不读也不写系统“提醒事项”。
///
/// The items live in the widget's own config under `items`, which is
/// deliberately not a catalog default: it is the widget's contents, like the
/// file shelf's paths, not a setting, so it is never offered as a text field
/// in the Widgets tab.
///
/// Each item is one string, `id<TAB>0|1<TAB>text`. A string so the existing
/// config type carries it without a new Codable shape, and tab-separated
/// because a tab cannot be typed into the single-line field that adds items.
public struct TodoItem: Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var text: String
    public var done: Bool

    public init(id: String = TodoItem.newID(), text: String, done: Bool = false) {
        self.id = id
        self.text = text
        self.done = done
    }

    public static func newID() -> String {
        String(UUID().uuidString.prefix(8)).lowercased()
    }

    var encoded: String {
        "\(id)\t\(done ? 1 : 0)\t\(text)"
    }

    /// Tolerant on purpose: a string written by hand or by an older build is
    /// still somebody's task, so anything without the two tabs is read as an
    /// open item with the whole string as its words.
    init?(decoding raw: String, fallbackID: String) {
        let parts = raw.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
        if parts.count == 3, parts[1] == "0" || parts[1] == "1" {
            let text = String(parts[2]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let id = String(parts[0])
            self.init(id: id.isEmpty ? fallbackID : id, text: text, done: parts[1] == "1")
        } else {
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            self.init(id: fallbackID, text: text, done: false)
        }
    }
}

public enum QuickTodo {
    public static let key = "items"
    /// Long enough for a real task, short enough that a paste of a whole
    /// document does not become one row.
    public static let maxLength = 200
    /// A shelf list, not a project manager.
    public static let maxItems = 100

    public static func items(_ config: WidgetConfig) -> [TodoItem] {
        var seen = Set<String>()
        var result: [TodoItem] = []
        for (index, raw) in config.strings(key).enumerated() {
            guard var item = TodoItem(decoding: raw, fallbackID: "i\(index)") else { continue }
            // Two rows with one id would toggle together.
            if seen.contains(item.id) { item.id = "\(item.id)-\(index)" }
            seen.insert(item.id)
            result.append(item)
        }
        return ordered(result)
    }

    public static func store(_ items: [TodoItem], in config: inout WidgetConfig) {
        config.set(key, .list(ordered(items).map { .string($0.encoded) }))
    }

    /// Open items first, in the order they were added, then the finished ones.
    public static func ordered(_ items: [TodoItem]) -> [TodoItem] {
        items.filter { !$0.done } + items.filter(\.done)
    }

    public static func open(_ items: [TodoItem]) -> [TodoItem] { items.filter { !$0.done } }

    public static func openCount(_ config: WidgetConfig) -> Int {
        items(config).filter { !$0.done }.count
    }

    /// The words cleaned up: one line, trimmed, capped. Nil when nothing is left.
    public static func clean(_ text: String) -> String? {
        let oneLine = text.components(separatedBy: .newlines).joined(separator: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !oneLine.isEmpty else { return nil }
        return String(oneLine.prefix(maxLength))
    }

    /// A new open item after the other open ones.
    public static func adding(_ text: String, to items: [TodoItem], id: String = TodoItem.newID()) -> [TodoItem] {
        guard let words = clean(text), items.count < maxItems else { return ordered(items) }
        let current = ordered(items)
        return open(current) + [TodoItem(id: id, text: words)] + current.filter(\.done)
    }

    /// Finished items go to the bottom; reopened ones go to the end of the
    /// open list, which is where a task you just put back belongs.
    public static func toggling(_ id: String, in items: [TodoItem]) -> [TodoItem] {
        guard var item = items.first(where: { $0.id == id }) else { return ordered(items) }
        item.done.toggle()
        let rest = ordered(items.filter { $0.id != id })
        return open(rest) + (item.done ? [] : [item]) + rest.filter(\.done) + (item.done ? [item] : [])
    }

    public static func renaming(_ id: String, to text: String, in items: [TodoItem]) -> [TodoItem] {
        guard let words = clean(text) else { return removing(id, from: items) }
        return ordered(items.map { $0.id == id ? TodoItem(id: $0.id, text: words, done: $0.done) : $0 })
    }

    public static func removing(_ id: String, from items: [TodoItem]) -> [TodoItem] {
        ordered(items.filter { $0.id != id })
    }

    public static func clearingDone(_ items: [TodoItem]) -> [TodoItem] {
        items.filter { !$0.done }
    }

    /// What the tile says under the first task.
    public static func caption(open: Int, done: Int) -> String {
        switch (open, done) {
        case (0, 0): "点按添加待办"
        case (0, _): "全部完成"
        case (1, _): "只剩这一项"
        default: "另外还有 \(open - 1) 项"
        }
    }
}
