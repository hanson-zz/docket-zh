import Foundation

// 录音面板的纯逻辑：显示名和改名、两位数的时长、转写的分段和拼接、裁剪范围、
// 波形条、按天分组，以及存转写文字的那份小表。界面和系统 API 在
// RecorderDetail、VoiceRecorder、RecordingTranscriber 里，这里只放能测的部分。
//
// 免费和 Pro 的分界（用户 2026-10-20 定）：录音整种免费，录、听、拖动进度、
// 改名、删除和列表都免费；转文字、裁剪和编辑（改文字、存为新录音）是 Pro，见
// `ProLicenseGate.canUseRecorderTools`。没解锁时已有的文字照旧存着、不删，
// 面板不显示，解锁或试用时自动回来。

/// 时长和时刻的写法：面板上是两位数的“06:12”“18:42”，一小时以上“1:02:03”。
public enum RecorderClock {
    public static func text(_ seconds: TimeInterval) -> String {
        // 加一点点再取整：42 秒拖出来可能是 41.999999，不能写成 00:41。
        let total = max(0, Int(((seconds.isFinite ? seconds : 0) + 0.000_5).rounded(.down)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    /// 列表第二行：“09:30 · 18:42”（今天）或“10月18日 09:30 · 03:10”（更早）。
    /// 时长还没读出来时只写时刻。
    public static func caption(date: Date, duration: TimeInterval?, now: Date,
                               calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.month, .day, .hour, .minute], from: date)
        let time = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        var when = time
        if !calendar.isDate(date, inSameDayAs: now) {
            when = tr("\(c.month ?? 0)月\(c.day ?? 0)日 \(time)")
        }
        guard let duration, duration.isFinite, duration > 0 else { return when }
        return "\(when) · \(text(duration))"
    }
}

/// 录音的显示名和改名后的文件名。
///
/// 文件名一直以“录音 ”开头，列表才认得出它（见 `RecordingNaming.isRecording`）：
/// 改名成“需求会”存成“录音 需求会.m4a”，显示时去掉前缀。还是默认的时间戳名字时
/// 显示“录音 09:30”。
public enum RecorderTitle {
    /// 名字最长几个字，太长的截掉。
    public static let maxLength = 60

    /// 文件名（带或不带扩展名）是不是还是录完时自动起的时间戳名字。
    public static func isDefault(_ fileName: String) -> Bool {
        stamp(fileName) != nil
    }

    /// 面板上显示的名字。
    public static func display(fileName: String) -> String {
        let base = baseName(fileName)
        if let stamp = stamp(fileName) {
            return tr("录音 \(stamp)")
        }
        guard base.hasPrefix(RecordingNaming.prefix) else { return base }
        let rest = String(base.dropFirst(RecordingNaming.prefix.count)).trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? base : rest
    }

    /// 改名框里一开始填的字：默认名字时是空的（占位写“录音 09:30”），否则是现在的名字。
    public static func editable(fileName: String) -> String {
        isDefault(fileName) ? "" : display(fileName: fileName)
    }

    /// 输入的名字清理后的样子：去掉首尾空白和换行，“/”“:”换成全角（访达里冒号
    /// 显示成斜杠），去掉开头的点（会变成隐藏文件），截到 `maxLength` 个字。
    /// 清理后是空的返回 nil。
    public static func clean(_ raw: String) -> String? {
        var text = raw.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "/", with: "／")
            .replacingOccurrences(of: ":", with: "：")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasPrefix(".") { text.removeFirst() }
        text = text.trimmingCharacters(in: .whitespaces)
        if text.count > maxLength { text = String(text.prefix(maxLength)).trimmingCharacters(in: .whitespaces) }
        return text.isEmpty ? nil : text
    }

    /// 改名后的文件名：“录音 <名字>.m4a”，和别的文件重名时加“ 2”“ 3”。名字没变
    /// （或清理后是空的）返回 nil，不用改。`taken` 是文件夹里已有的文件名，
    /// 可以包含它自己。
    public static func renamed(_ current: String, to raw: String, taken: Set<String>) -> String? {
        guard let title = clean(raw) else { return nil }
        let wanted = "\(RecordingNaming.prefix)\(title).\(RecordingNaming.fileExtension)"
        if wanted == current { return nil }
        var others = taken
        others.remove(current)
        return RecordingNaming.unique(wanted, taken: others)
    }

    /// 裁剪后存成新录音时的名字：“<原名> 选段”。
    public static func excerptTitle(_ title: String) -> String {
        clean(tr("\(title) 选段")) ?? title
    }

    private static func baseName(_ fileName: String) -> String {
        let ext = "." + RecordingNaming.fileExtension
        return fileName.lowercased().hasSuffix(ext) ? String(fileName.dropLast(ext.count)) : fileName
    }

    /// “录音 2026-10-12 09.30.05”（可带“ 2”）里的“09:30”。
    private static func stamp(_ fileName: String) -> String? {
        let base = baseName(fileName)
        guard base.hasPrefix(RecordingNaming.prefix) else { return nil }
        let rest = Array(String(base.dropFirst(RecordingNaming.prefix.count)))
        // yyyy-MM-dd HH.mm.ss，共 19 个字符，后面可以跟“ 2”这样的序号。
        guard rest.count >= 19 else { return nil }
        let pattern = "dddd-dd-dd dd.dd.dd"
        for (ch, p) in zip(rest.prefix(19), pattern) {
            if p == "d" { if !ch.isASCII || !ch.isNumber { return nil } } else if ch != p { return nil }
        }
        let tail = String(rest.dropFirst(19))
        if !tail.isEmpty {
            guard tail.hasPrefix(" "), Int(tail.dropFirst()) != nil else { return nil }
        }
        return "\(String(rest[11...12])):\(String(rest[14...15]))"
    }
}

/// 一段转写文字：从录音第几秒开始，和这段的字。
public struct TranscriptSegment: Codable, Equatable, Sendable {
    public var start: TimeInterval
    public var text: String

    public init(start: TimeInterval, text: String) {
        self.start = start
        self.text = text
    }
}

/// 识别出来的一个词（系统语音识别的 segment）。
public struct TranscriptWord: Equatable, Sendable {
    public var text: String
    public var start: TimeInterval
    public var duration: TimeInterval

    public init(text: String, start: TimeInterval, duration: TimeInterval) {
        self.text = text
        self.start = start
        self.duration = duration
    }
}

/// 把识别出的词拼成一段一段的文字，以及复制、预览、裁剪时怎么处理这些段。
public enum Transcript {
    /// 停顿多久算新的一段。
    public static let paragraphPause: TimeInterval = 1.6
    /// 一段写到多少字、并且刚好是句末时另起一段。
    public static let paragraphLength = 48

    /// 词拼成段：停顿超过 `paragraphPause` 另起一段；一段够 `paragraphLength` 个字
    /// 且上一个词以句末标点结尾也另起一段。英文和数字之间补空格，中文不补。
    public static func paragraphs(_ words: [TranscriptWord]) -> [TranscriptSegment] {
        var out: [TranscriptSegment] = []
        var current: TranscriptSegment?
        var lastEnd: TimeInterval = 0
        for word in words {
            let piece = word.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !piece.isEmpty else { continue }
            if var seg = current {
                let pause = word.start - lastEnd
                let longEnough = seg.text.count >= paragraphLength && endsSentence(seg.text)
                if pause >= paragraphPause || longEnough {
                    out.append(seg)
                    current = TranscriptSegment(start: max(0, word.start), text: piece)
                } else {
                    seg.text = join(seg.text, piece)
                    current = seg
                }
            } else {
                current = TranscriptSegment(start: max(0, word.start), text: piece)
            }
            lastEnd = max(lastEnd, word.start + max(0, word.duration))
        }
        if let current { out.append(current) }
        return out
    }

    /// 两段文字接起来：两边都是英文字母或数字时中间加一个空格。
    public static func join(_ a: String, _ b: String) -> String {
        guard let last = a.last, let first = b.first else { return a + b }
        let needsSpace = isLatin(last) && isLatin(first)
        return needsSpace ? a + " " + b : a + b
    }

    /// 全部文字，一段一行（复制用）。空段跳过。
    public static func fullText(_ segments: [TranscriptSegment]) -> String {
        segments.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    /// 列表里那一两行预览：段和段之间不换行。
    public static func preview(_ segments: [TranscriptSegment]) -> String {
        segments.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce("") { join($0, $1) }
    }

    /// 有没有字。
    public static func hasText(_ segments: [TranscriptSegment]) -> Bool {
        segments.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// 裁剪成选段后的文字：只留开头落在选段里的段（第一段如果从选段前开始、
    /// 但在选段里还在说，也留下），时间都减去选段开头，从 0 算起。
    public static func trimmed(_ segments: [TranscriptSegment], start: TimeInterval, end: TimeInterval) -> [TranscriptSegment] {
        guard end > start else { return [] }
        let sorted = segments.sorted { $0.start < $1.start }
        var out: [TranscriptSegment] = []
        for (i, seg) in sorted.enumerated() {
            let next = i + 1 < sorted.count ? sorted[i + 1].start : .infinity
            let inside = seg.start >= start && seg.start < end
            let spansStart = seg.start < start && next > start
            guard inside || spansStart else { continue }
            out.append(TranscriptSegment(start: max(0, seg.start - start), text: seg.text))
        }
        return out
    }

    /// 转写进度：说到第几秒除以总长，最多 0.99，结束时才是 1。
    public static func progress(heard: TimeInterval, duration: TimeInterval?) -> Double {
        guard let duration, duration > 0, heard.isFinite else { return 0 }
        return min(0.99, max(0, heard / duration))
    }

    private static func endsSentence(_ text: String) -> Bool {
        guard let last = text.last else { return false }
        return "。！？.!?".contains(last)
    }

    private static func isLatin(_ ch: Character) -> Bool {
        ch.isASCII && (ch.isLetter || ch.isNumber)
    }
}

/// 转写用哪种语言：先跟系统语言，本机识别不支持再试简体中文和英文，去重。
public enum TranscribeLocales {
    public static let fallbacks = ["zh-CN", "en-US"]

    public static func candidates(preferred: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in preferred + fallbacks {
            let id = raw.replacingOccurrences(of: "_", with: "-")
            guard !id.isEmpty, seen.insert(id.lowercased()).inserted else { continue }
            out.append(id)
        }
        return out
    }
}

/// 裁剪的范围：编辑态拖两端改，单位是秒。
public struct RecordingTrim: Equatable, Sendable {
    /// 选段最短几秒，两个把手不会拖到一起。
    public static let minimumLength: TimeInterval = 1

    public private(set) var duration: TimeInterval
    public private(set) var start: TimeInterval
    public private(set) var end: TimeInterval

    public init(duration: TimeInterval) {
        let d = duration.isFinite ? max(0, duration) : 0
        self.duration = d
        start = 0
        end = d
    }

    /// 选的是不是整条（没裁）。
    public var isFull: Bool { start <= 0.05 && end >= duration - 0.05 }
    public var length: TimeInterval { max(0, end - start) }
    public var startFraction: Double { duration > 0 ? start / duration : 0 }
    public var endFraction: Double { duration > 0 ? end / duration : 1 }

    /// 选段最短的长度：录音本身比 1 秒还短时就是整条。
    private var minimum: TimeInterval { min(Self.minimumLength, duration) }

    /// 把开头拖到第几成（0 到 1），不超过结尾减最短长度。
    public mutating func setStart(fraction: Double) {
        let f = fraction.isFinite ? min(1, max(0, fraction)) : 0
        start = min(max(0, f * duration), max(0, end - minimum))
    }

    /// 把结尾拖到第几成，不早于开头加最短长度。
    public mutating func setEnd(fraction: Double) {
        let f = fraction.isFinite ? min(1, max(0, fraction)) : 1
        end = max(min(duration, f * duration), min(duration, start + minimum))
    }

    public mutating func reset() {
        start = 0
        end = duration
    }

    /// “00:42 至 17:10”。
    public var rangeLabel: String {
        tr("\(RecorderClock.text(start)) 至 \(RecorderClock.text(end))")
    }

    /// “剩 16:28”。
    public var remainingLabel: String {
        tr("剩 \(RecorderClock.text(length))")
    }
}

/// 波形：把一串采样的峰值压成固定根数的竖条，高度 0 到 1。
public enum Waveform {
    /// 面板上画几根。
    public static let barCount = 72
    /// 最矮的竖条，静音段也看得见一点。
    public static let floor: Float = 0.06

    /// `peaks` 是按时间顺序的峰值（任意长度），按最大值归一化，压成 `count` 根。
    /// 没有采样时返回一排最矮的条。
    public static func bars(_ peaks: [Float], count: Int = barCount) -> [Float] {
        guard count > 0 else { return [] }
        guard !peaks.isEmpty else { return Array(repeating: floor, count: count) }
        var out: [Float] = []
        out.reserveCapacity(count)
        let n = peaks.count
        for i in 0..<count {
            let lo = i * n / count
            let hi = max(lo + 1, (i + 1) * n / count)
            var peak: Float = 0
            for j in lo..<min(hi, n) { peak = max(peak, abs(peaks[j].isFinite ? peaks[j] : 0)) }
            out.append(peak)
        }
        let top = out.max() ?? 0
        guard top > 0 else { return Array(repeating: floor, count: count) }
        return out.map { max(floor, min(1, $0 / top)) }
    }

    /// 在宽 `width` 的波形上点到 x 处是第几成（0 到 1）。
    public static func fraction(x: CGFloat, width: CGFloat) -> Double {
        guard width > 0, x.isFinite else { return 0 }
        return Double(min(1, max(0, x / width)))
    }
}

/// 列表按天分组：“今天”“昨天”“更早”。
public enum RecorderDay: Hashable, Sendable {
    case today, yesterday, earlier

    public static func of(_ date: Date, now: Date, calendar: Calendar = .current) -> RecorderDay {
        if calendar.isDate(date, inSameDayAs: now) { return .today }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: y) {
            return .yesterday
        }
        return .earlier
    }

    public var title: String {
        switch self {
        case .today: tr("今天")
        case .yesterday: tr("昨天")
        case .earlier: tr("更早")
        }
    }

    /// 一组：哪一天和这天的录音。
    public struct Group<T> {
        public var day: RecorderDay
        public var items: [T]
    }

    /// 按顺序分好组，空组不出现；组内保持原来的顺序（新的在前）。
    public static func groups<T>(_ items: [T], date: (T) -> Date, now: Date,
                                 calendar: Calendar = .current) -> [Group<T>] {
        var buckets: [RecorderDay: [T]] = [:]
        for item in items { buckets[of(date(item), now: now, calendar: calendar), default: []].append(item) }
        return [RecorderDay.today, .yesterday, .earlier].compactMap { day in
            guard let list = buckets[day], !list.isEmpty else { return nil }
            return Group(day: day, items: list)
        }
    }

    /// “今天 · 2 条”。
    public static func header(_ day: RecorderDay, count: Int) -> String {
        tr("\(day.title) · \(count) 条")
    }
}

/// 存转写文字的小表：键是录音文件的完整路径。改名、删除时跟着改。
///
/// 存在应用支持文件夹的 recordings.json 里，不往录音文件夹里放别的文件。
public struct RecordingNotes: Codable, Equatable, Sendable {
    public var version = 1
    public var transcripts: [String: [TranscriptSegment]] = [:]

    public init() {}

    public static func key(_ url: URL) -> String { url.standardizedFileURL.path }

    public func segments(for url: URL) -> [TranscriptSegment]? { transcripts[Self.key(url)] }

    public mutating func set(_ segments: [TranscriptSegment], for url: URL) {
        transcripts[Self.key(url)] = segments
    }

    public mutating func remove(_ url: URL) {
        transcripts[Self.key(url)] = nil
    }

    /// 文件改名或移走后把文字跟过去。新位置原来有的会被换掉。
    public mutating func move(from old: URL, to new: URL) {
        let oldKey = Self.key(old), newKey = Self.key(new)
        guard oldKey != newKey, let value = transcripts[oldKey] else { return }
        transcripts[newKey] = value
        transcripts[oldKey] = nil
    }

    /// 去掉某个文件夹里已经不存在的录音的文字（`existing` 是这个文件夹里现有的
    /// 文件名）。别的文件夹的不动。
    public mutating func prune(folder: URL, existing: Set<String>) {
        let dir = folder.standardizedFileURL.path
        for key in transcripts.keys {
            let url = URL(fileURLWithPath: key)
            guard url.deletingLastPathComponent().standardizedFileURL.path == dir else { continue }
            if !existing.contains(url.lastPathComponent) { transcripts[key] = nil }
        }
    }

    public func encoded() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(self)
    }

    public static func decode(_ data: Data?) -> RecordingNotes {
        guard let data, let notes = try? JSONDecoder().decode(RecordingNotes.self, from: data) else {
            return RecordingNotes()
        }
        return notes
    }
}
