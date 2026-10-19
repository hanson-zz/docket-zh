import Foundation

/// 拖到 AI 任意门上的文字和文件，拼成带进提问面板的那段话。
///
/// 文字原样带进去；纯文本文件（代码、笔记、日志这类）把内容带进去，前面一行
/// 写文件名；别的文件（图片、PDF、文件夹）只写一行路径，让人自己决定怎么问。
/// 总长不超过剪贴板接力的上限（`AIClipboard.insertLimit`），超出的截掉。
public enum AIDrop {
    /// 拖进来的一个文件。`contents` 是读出来的文字，不是文本文件或太大时为 nil。
    public struct File: Equatable, Sendable {
        public var name: String
        public var path: String
        public var contents: String?

        public init(name: String, path: String, contents: String?) {
            self.name = name
            self.path = path
            self.contents = contents
        }
    }

    /// 读文件内容的上限（字节）：再大的文本一次问答也放不下。
    public static let maxFileBytes = 200_000

    /// 一次最多带几个文件。
    public static let maxFiles = 5

    /// 拼好的一段；什么都没有（全是空白）时为 nil。
    public static func compose(texts: [String], files: [File]) -> String? {
        var parts: [String] = []
        for text in texts {
            let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !words.isEmpty { parts.append(words) }
        }
        for file in files.prefix(maxFiles) {
            if let contents = file.contents?.trimmingCharacters(in: .whitespacesAndNewlines), !contents.isEmpty {
                parts.append(tr("文件 \(file.name)：") + "\n" + contents)
            } else {
                parts.append(tr("文件：\(file.path)"))
            }
        }
        guard !parts.isEmpty else { return nil }
        let joined = parts.joined(separator: "\n\n")
        return String(joined.prefix(AIClipboard.insertLimit))
    }
}
