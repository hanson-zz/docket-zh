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
///
/// 今天三件事、拖进来的链接和当天清用到的几样东西跟在后面，每样一段
/// `键=值`（`s=1` 标为今天、`u=` 链接或文件地址、`a=` 记下的那天、`d=` 做完的那天、
/// `r=` 提醒时间，1970 年起的秒数）。一样都没有时写出来和原来一模一样，旧数据
/// 读出来就是没有提醒时间。
public struct TodoItem: Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var text: String
    public var done: Bool
    /// 标为“今天三件事”之一。
    public var today: Bool
    /// 拖进来的链接或文件地址（绝对 URL 字符串），点一下打开。
    public var link: String?
    /// 记下这一条的那天（`TodoDay` 的 yyyy-MM-dd），当天清用来认出“昨天没做完的”。
    public var addedDay: String?
    /// 勾掉的那天，第二天打开时据此收起。
    public var doneDay: String?
    /// 可选的提醒时间：到点弹出卡片（见 `QuickTodo.dueReminders`）。
    public var remindAt: Date?

    public init(id: String = TodoItem.newID(), text: String, done: Bool = false,
                today: Bool = false, link: String? = nil,
                addedDay: String? = nil, doneDay: String? = nil, remindAt: Date? = nil) {
        self.id = id
        self.text = text
        self.done = done
        self.today = today
        self.link = link
        self.addedDay = addedDay
        self.doneDay = doneDay
        self.remindAt = remindAt.map { Date(timeIntervalSince1970: $0.timeIntervalSince1970.rounded(.down)) }
    }

    public static func newID() -> String {
        String(UUID().uuidString.prefix(8)).lowercased()
    }

    /// 能打开的地址：网页链接或本机文件。
    public var url: URL? {
        guard let link, let url = URL(string: link), url.scheme != nil else { return nil }
        return url
    }

    var encoded: String {
        var fields = ["\(id)\t\(done ? 1 : 0)\t\(text)"]
        if today { fields.append("s=1") }
        if let link, !link.isEmpty { fields.append("u=\(link)") }
        if let addedDay { fields.append("a=\(addedDay)") }
        if let doneDay { fields.append("d=\(doneDay)") }
        if let remindAt { fields.append("r=\(Int(remindAt.timeIntervalSince1970))") }
        return fields.joined(separator: "\t")
    }

    /// Tolerant on purpose: a string written by hand or by an older build is
    /// still somebody's task, so anything without the two tabs is read as an
    /// open item with the whole string as its words.
    init?(decoding raw: String, fallbackID: String) {
        let parts = raw.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        if parts.count >= 3, parts[1] == "0" || parts[1] == "1" {
            // 文字里不会有制表符（`QuickTodo.clean` 换掉了），后面不认识的段
            // 是手写的就接回文字里，不丢字。
            var words = [parts[2]]
            var today = false
            var link: String?
            var added: String?
            var finished: String?
            var remind: Date?
            for field in parts.dropFirst(3) {
                if field == "s=1" { today = true }
                else if field.hasPrefix("u=") { link = String(field.dropFirst(2)) }
                else if field.hasPrefix("a="), TodoDay.isKey(String(field.dropFirst(2))) { added = String(field.dropFirst(2)) }
                else if field.hasPrefix("d="), TodoDay.isKey(String(field.dropFirst(2))) { finished = String(field.dropFirst(2)) }
                else if field.hasPrefix("r="), let seconds = Int(field.dropFirst(2)), seconds > 0 {
                    remind = Date(timeIntervalSince1970: TimeInterval(seconds))
                }
                else { words.append(field) }
            }
            let text = words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let id = parts[0]
            self.init(id: id.isEmpty ? fallbackID : id, text: text, done: parts[1] == "1",
                      today: today, link: link?.isEmpty == true ? nil : link,
                      addedDay: added, doneDay: finished, remindAt: remind)
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
    ///
    /// - Parameters:
    ///   - link: 拖进来的链接或文件地址，没有时为 nil。
    ///   - day: 记下的那天（`TodoDay.key`），当天清用；nil 时不记。
    public static func adding(_ text: String, to items: [TodoItem], id: String = TodoItem.newID(),
                              link: String? = nil, day: String? = nil) -> [TodoItem] {
        guard let words = clean(text), items.count < maxItems else { return ordered(items) }
        let current = ordered(items)
        let address = link.map { String($0.prefix(maxLinkLength)) }
        let item = TodoItem(id: id, text: words, link: address, addedDay: day)
        return open(current) + [item] + current.filter(\.done)
    }

    /// 链接最长存多少个字符。
    public static let maxLinkLength = 2_000

    /// Finished items go to the bottom; reopened ones go to the end of the
    /// open list, which is where a task you just put back belongs.
    ///
    /// - Parameter day: 勾掉的那天，记在这一条上，第二天据此收起；重新打开时清掉。
    public static func toggling(_ id: String, in items: [TodoItem], day: String? = nil) -> [TodoItem] {
        guard var item = items.first(where: { $0.id == id }) else { return ordered(items) }
        item.done.toggle()
        item.doneDay = item.done ? day : nil
        let rest = ordered(items.filter { $0.id != id })
        return open(rest) + (item.done ? [] : [item]) + rest.filter(\.done) + (item.done ? [item] : [])
    }

    public static func renaming(_ id: String, to text: String, in items: [TodoItem]) -> [TodoItem] {
        guard let words = clean(text) else { return removing(id, from: items) }
        return ordered(items.map { item in
            guard item.id == id else { return item }
            var renamed = item
            renamed.text = words
            return renamed
        })
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
        case (0, 0): tr("点按添加待办")
        case (0, _): tr("全部完成")
        case (1, _): tr("只剩这一项")
        default: tr("另外还有 \(open - 1) 项")
        }
    }
}
