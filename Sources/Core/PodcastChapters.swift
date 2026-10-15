import Foundation

/// 单集简介里的时间轴，比如
///
///     00:00 开场
///     03:12 聊聊 AI 编程
///     (1:02:30) 听众来信
///
/// 读成章节，播放时在进度条下面像歌词一样跟着走。小宇宙没有逐句文稿的
/// 公开接口，主播自己写的时间轴是能拿到的最接近的东西。纯函数，测试用
/// 真实写法的各种变体。
public struct PodcastChapter: Codable, Equatable, Sendable, Identifiable {
    /// 秒。
    public var start: Double
    public var title: String

    public var id: Double { start }

    public init(start: Double, title: String) {
        self.start = start
        self.title = title
    }
}

public enum PodcastChapters {
    /// 少于两条不算时间轴（简介里偶尔提一句“第 5:00 分钟”不是章节）。
    public static let minimumCount = 2
    public static let maxTitleLength = 60

    /// 从简介（纯文本或 HTML）里读出章节，按时间排好、去重。
    /// 时间超过 `duration`（大于 0 时）的行丢掉。
    public static func parse(_ text: String, duration: Double = 0) -> [PodcastChapter] {
        var found: [PodcastChapter] = []
        for line in plainLines(text) {
            guard let chapter = chapter(line) else { continue }
            if duration > 0, chapter.start > duration { continue }
            found.append(chapter)
        }
        // 先按原顺序去重（同一时间留先写的那行），再排序。
        var seen = Set<Double>()
        let unique = found.filter { seen.insert($0.start).inserted }.sorted { $0.start < $1.start }
        return unique.count >= minimumCount ? unique : []
    }

    /// 播放到 `position` 秒时所在的章节下标；第一章开始之前是 nil。
    public static func currentIndex(_ chapters: [PodcastChapter], at position: Double) -> Int? {
        guard position.isFinite else { return nil }
        var index: Int?
        for (i, chapter) in chapters.enumerated() where chapter.start <= position + 0.5 {
            index = i
        }
        return index
    }

    public static func current(_ chapters: [PodcastChapter], at position: Double) -> PodcastChapter? {
        currentIndex(chapters, at: position).map { chapters[$0] }
    }

    // MARK: Parsing

    /// 一行：开头（可带序号、括号、方括号、项目符号）是时间，后面是标题。
    static func chapter(_ line: String) -> PodcastChapter? {
        let pattern = #/^[\s\-\*•·▶►>\d\.、]*?[\(（\[【]?\s*((?:\d{1,2}:)?\d{1,2}:\d{2})\s*[\)）\]】]?\s*[\-\u{2013}\u{2014}:：|｜]?\s*(.+)$/#
        guard let match = line.firstMatch(of: pattern),
              let seconds = seconds(String(match.output.1)) else { return nil }
        var title = String(match.output.2).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        if title.count > maxTitleLength { title = String(title.prefix(maxTitleLength)) + "…" }
        return PodcastChapter(start: seconds, title: title)
    }

    /// "3:12" 是 3 分 12 秒，"1:02:30" 是 1 小时 2 分 30 秒。
    public static func seconds(_ text: String) -> Double? {
        let parts = text.split(separator: ":").map { Int($0) }
        guard parts.allSatisfy({ $0 != nil }) else { return nil }
        let n = parts.compactMap { $0 }
        switch n.count {
        case 2:
            guard n[1] < 60 else { return nil }
            return Double(n[0] * 60 + n[1])
        case 3:
            guard n[1] < 60, n[2] < 60 else { return nil }
            return Double(n[0] * 3600 + n[1] * 60 + n[2])
        default:
            return nil
        }
    }

    /// HTML 换成一行一行的纯文本：块级标签和 <br> 断行，其他标签去掉，
    /// 常见实体还原。
    static func plainLines(_ text: String) -> [String] {
        var s = text
        s = s.replacingOccurrences(of: #"(?i)<br\s*/?>|</p>|</li>|</div>|</h\d>"#, with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        for (entity, char) in [("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
                               ("&quot;", "\""), ("&#39;", "'")] {
            s = s.replacingOccurrences(of: entity, with: char)
        }
        return s.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
