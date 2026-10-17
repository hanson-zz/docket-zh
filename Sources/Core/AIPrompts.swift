import Foundation

// MARK: - AI 助手：提示词

/// 一条常用提示词：名字加内容。内容里的 `{文本}` 在用的时候换成输入框或
/// 剪贴板里的文字；没写 `{文本}` 时，文字接在内容后面另起一段。
public struct AIPrompt: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var content: String

    public init(id: String, name: String, content: String) {
        self.id = id
        self.name = name
        self.content = content
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? ""
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        content = (try? c.decodeIfPresent(String.self, forKey: .content)) ?? ""
    }
}

/// 面板上的四个快捷指令。提示词写死在这里，和常用提示词一样用 `{文本}`。
public enum AIQuickAction: String, CaseIterable, Sendable {
    case translate, summarize, polish, explain

    public var title: String {
        switch self {
        case .translate: tr("翻译")
        case .summarize: tr("总结")
        case .polish: tr("润色")
        case .explain: tr("解释")
        }
    }

    public var symbol: String {
        switch self {
        case .translate: "character.bubble"
        case .summarize: "text.badge.checkmark"
        case .polish: "wand.and.stars"
        case .explain: "lightbulb"
        }
    }

    public var template: String {
        switch self {
        case .translate:
            tr("把下面的文字翻译成简体中文；如果原文已经是中文，就翻译成英文。只给出译文，不要解释。\n\n{文本}")
        case .summarize:
            tr("用简体中文总结下面的内容：先用一句话概括，再分条列出要点。\n\n{文本}")
        case .polish:
            tr("润色下面的文字，让它更通顺、自然、准确，保持原意和原来的语言。只给出润色后的结果。\n\n{文本}")
        case .explain:
            tr("用通俗易懂的简体中文解释下面的内容，必要时举个例子。\n\n{文本}")
        }
    }
}

/// 提示词的纯逻辑：占位替换、文字从哪来、常用提示词的增删改排序。
public enum AIPrompts {
    /// 内容里的占位，用的时候换成文字。
    public static let placeholder = "{文本}"
    /// 最多存多少条常用提示词。
    public static let maxCount = 30
    /// 名字最长几个字。
    public static let nameLimit = 20
    /// 内容最长几个字。
    public static let contentLimit = 4000

    /// 把文字套进提示词：有 `{文本}` 的全部替换；没有的接在后面另起一段。
    /// 文字是空白时只交出提示词本身（去掉占位）。
    public static func fill(_ template: String, with text: String) -> String {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if template.contains(placeholder) {
            let filled = template.replacingOccurrences(of: placeholder, with: body)
            return filled.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let head = template.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.isEmpty { return head }
        if head.isEmpty { return body }
        return head + "\n\n" + body
    }

    /// 提示词要用的文字来自哪里。
    public enum Source: Equatable, Sendable {
        /// 输入框里写了字，用它。
        case draft(String)
        /// 输入框空着，用剪贴板里的文字。
        case clipboard(String)
        /// 两边都没有。
        case none
    }

    /// 输入框优先，空白时用剪贴板。
    public static func source(draft: String, clipboard: String?) -> Source {
        if let text = AIAsk.question(draft) { return .draft(text) }
        if let clip = clipboard, let text = AIAsk.question(clip) { return .clipboard(text) }
        return .none
    }

    /// 要交出去的完整提示词；两边都没有文字时为 nil。
    public static func compose(_ template: String, draft: String, clipboard: String?) -> String? {
        switch source(draft: draft, clipboard: clipboard) {
        case .draft(let text), .clipboard(let text): fill(template, with: text)
        case .none: nil
        }
    }

    // MARK: 常用提示词的编辑

    public enum EditError: Error, Equatable, Sendable {
        case emptyName, emptyContent, nameTooLong, contentTooLong, duplicateName, full

        public var message: String {
            switch self {
            case .emptyName: tr("给提示词起个名字。")
            case .emptyContent: tr("提示词内容不能为空。")
            case .nameTooLong: tr("名字最多 \(AIPrompts.nameLimit) 个字。")
            case .contentTooLong: tr("内容最多 \(AIPrompts.contentLimit) 个字。")
            case .duplicateName: tr("已经有同名的提示词了。")
            case .full: tr("最多存 \(AIPrompts.maxCount) 条常用提示词。")
            }
        }
    }

    /// 检查名字和内容，返回整理好的（去掉首尾空白）。
    static func cleaned(name: String, content: String, id: String?,
                        among list: [AIPrompt]) -> Result<(String, String), EditError> {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty { return .failure(.emptyName) }
        if trimmedContent.isEmpty { return .failure(.emptyContent) }
        if trimmedName.count > nameLimit { return .failure(.nameTooLong) }
        if trimmedContent.count > contentLimit { return .failure(.contentTooLong) }
        if list.contains(where: {
            $0.id != id && $0.name.compare(trimmedName, options: [.caseInsensitive]) == .orderedSame
        }) {
            return .failure(.duplicateName)
        }
        return .success((trimmedName, trimmedContent))
    }

    /// 加在最后。出错时列表不变，返回原因。
    @discardableResult
    public static func add(name: String, content: String, id: String,
                           to list: inout [AIPrompt]) -> EditError? {
        guard list.count < maxCount else { return .full }
        switch cleaned(name: name, content: content, id: nil, among: list) {
        case .failure(let error): return error
        case .success(let (cleanName, cleanContent)):
            list.append(AIPrompt(id: id, name: cleanName, content: cleanContent))
            return nil
        }
    }

    /// 改名字或内容，位置不变。找不到这一条时什么都不做。
    @discardableResult
    public static func update(_ id: String, name: String, content: String,
                              in list: inout [AIPrompt]) -> EditError? {
        guard let index = list.firstIndex(where: { $0.id == id }) else { return nil }
        switch cleaned(name: name, content: content, id: id, among: list) {
        case .failure(let error): return error
        case .success(let (cleanName, cleanContent)):
            list[index].name = cleanName
            list[index].content = cleanContent
            return nil
        }
    }

    public static func remove(_ id: String, from list: inout [AIPrompt]) {
        list.removeAll { $0.id == id }
    }

    /// 上移（负数）或下移（正数），到头了就停在头上。
    public static func move(_ id: String, by offset: Int, in list: inout [AIPrompt]) {
        guard let index = list.firstIndex(where: { $0.id == id }) else { return }
        let target = min(max(index + offset, 0), list.count - 1)
        guard target != index else { return }
        let item = list.remove(at: index)
        list.insert(item, at: target)
    }

    /// 读出来的列表：丢掉没名字、没内容、没 id 的，id 重复的只留第一条，
    /// 超过上限的截掉。手改坏的状态文件也能读。
    public static func sanitized(_ list: [AIPrompt]) -> [AIPrompt] {
        var seen = Set<String>()
        var result: [AIPrompt] = []
        for item in list {
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let content = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !item.id.isEmpty, !name.isEmpty, !content.isEmpty, seen.insert(item.id).inserted else { continue }
            result.append(AIPrompt(id: item.id, name: String(name.prefix(nameLimit)),
                                   content: String(content.prefix(contentLimit))))
            if result.count == maxCount { break }
        }
        return result
    }

    /// 内容的一行预览，用在列表里。
    public static func preview(_ content: String, limit: Int = 40) -> String {
        AIClipboard.preview(content, limit: limit) ?? ""
    }
}

// MARK: - 剪贴板接力

/// 把剪贴板里的文字带进输入框。
public enum AIClipboard {
    /// 带进输入框的最多几个字，太长的截掉（一次问答也放不下更多）。
    public static let insertLimit = 20_000

    /// 一行预览：空白合成一个空格，超过 `limit` 个字截断并加省略号。
    /// 空白或没有文字时为 nil。
    public static func preview(_ text: String?, limit: Int = 60) -> String? {
        guard let text else { return nil }
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        guard !words.isEmpty else { return nil }
        let line = words.joined(separator: " ")
        guard line.count > limit else { return line }
        return String(line.prefix(max(limit, 1))) + "…"
    }

    /// 剪贴板文字接进草稿：草稿空白时直接换成它，否则另起一行接在后面。
    /// 剪贴板空白时草稿不变。
    public static func insert(_ clipboard: String?, into draft: String) -> String {
        guard let clipboard, AIAsk.question(clipboard) != nil else { return draft }
        let clip = String(clipboard.trimmingCharacters(in: .whitespacesAndNewlines).prefix(insertLimit))
        if AIAsk.question(draft) == nil { return clip }
        let head = draft.hasSuffix("\n") ? draft : draft + "\n"
        return head + clip
    }

    /// 剪贴板的字数是不是超过了能带进去的上限。
    public static func isTruncated(_ clipboard: String?) -> Bool {
        guard let clipboard else { return false }
        return clipboard.trimmingCharacters(in: .whitespacesAndNewlines).count > insertLimit
    }
}
