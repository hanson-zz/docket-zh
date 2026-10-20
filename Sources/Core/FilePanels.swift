import Foundation
import CoreGraphics

// 「下载」和「最近截图」两个面板的纯逻辑：搜索、按类型和日期筛、分天、
// 文件类型的小标、多选、改名和撞名、压缩包的名字、下载还剩多久，以及
// 截图标注的几何（箭头、框、马赛克、文字）和撤销。都不碰磁盘，方便测试。

// MARK: - 类型筛选

/// 「下载」面板顶上的筛选：全部、图片、文档、安装包、压缩包。
public enum DownloadKind: String, CaseIterable, Sendable {
    case all, image, document, installer, archive

    public var title: String {
        switch self {
        case .all: tr("全部")
        case .image: tr("图片")
        case .document: tr("文档")
        case .installer: tr("安装包")
        case .archive: tr("压缩包")
        }
    }

    static let images: Set<String> = ListedFile.imageExtensions.union(["svg", "psd", "raw", "dng", "ico", "icns"])
    static let documents: Set<String> = [
        "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "key", "pages", "numbers",
        "txt", "md", "rtf", "rtfd", "csv", "epub", "odt", "ods", "odp", "json", "xml", "html", "htm",
    ]
    static let installers: Set<String> = ["dmg", "pkg", "mpkg", "app", "iso", "xip"]
    static let archives: Set<String> = ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "zst"]

    /// 一个文件属于哪一类（不是「全部」）；文件夹和认不出的返回 nil。
    public static func of(_ file: ListedFile) -> DownloadKind? {
        guard !file.isDirectory else { return nil }
        let ext = file.url.pathExtension.lowercased()
        if images.contains(ext) { return .image }
        if documents.contains(ext) { return .document }
        if installers.contains(ext) { return .installer }
        if archives.contains(ext) { return .archive }
        return nil
    }

    public func matches(_ file: ListedFile) -> Bool {
        self == .all || Self.of(file) == self
    }
}

/// 「最近截图」顶上的筛选：全部、今天、本周、录屏。
public enum ShotFilter: String, CaseIterable, Sendable {
    case all, today, week, recording

    public var title: String {
        switch self {
        case .all: tr("全部")
        case .today: tr("今天")
        case .week: tr("本周")
        case .recording: tr("录屏")
        }
    }

    static let videoExtensions: Set<String> = ["mov", "mp4", "m4v"]

    public static func isRecording(_ file: ListedFile) -> Bool {
        videoExtensions.contains(file.url.pathExtension.lowercased())
    }

    public func matches(_ file: ListedFile, now: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .all: true
        case .today: calendar.isDate(file.date, inSameDayAs: now)
        case .week: calendar.isDate(file.date, equalTo: now, toGranularity: .weekOfYear)
        case .recording: Self.isRecording(file)
        }
    }
}

// MARK: - 搜索

public enum FileQuery {
    /// 名字里有这几个字（不分大小写、全半角），或者日期对得上：
    /// 「10-20」「10月20日」「10/20」「2026-10-20」。空搜索全部算。
    public static func matches(_ file: ListedFile, query raw: String, calendar: Calendar = .current) -> Bool {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let options: String.CompareOptions = [.caseInsensitive, .widthInsensitive, .diacriticInsensitive]
        if file.name.range(of: query, options: options) != nil { return true }
        return dateTokens(file.date, calendar: calendar).contains { $0.range(of: query, options: options) != nil }
    }

    static func dateTokens(_ date: Date, calendar: Calendar) -> [String] {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        guard let y = c.year, let m = c.month, let d = c.day else { return [] }
        let mm = String(format: "%02d", m)
        let dd = String(format: "%02d", d)
        return ["\(y)-\(mm)-\(dd)", "\(m)-\(d)", "\(mm)-\(dd)", "\(m)/\(d)", "\(m)月\(d)日", "\(m).\(d)"]
    }

    public static func filter(_ files: [ListedFile], query: String, calendar: Calendar = .current) -> [ListedFile] {
        files.filter { matches($0, query: query, calendar: calendar) }
    }
}

// MARK: - 分天和日期小字

public enum FileDayGroup: Int, CaseIterable, Sendable {
    case today, yesterday, earlier

    public var title: String {
        switch self {
        case .today: tr("今天")
        case .yesterday: tr("昨天")
        case .earlier: tr("更早")
        }
    }

    public static func of(_ date: Date, now: Date, calendar: Calendar = .current) -> FileDayGroup {
        if calendar.isDate(date, inSameDayAs: now) { return .today }
        if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: y) {
            return .yesterday
        }
        return .earlier
    }

    /// 按今天、昨天、更早分好，空的组不出现，组里保持原来的顺序。
    public static func sections(_ files: [ListedFile], now: Date,
                                calendar: Calendar = .current) -> [FileDaySection] {
        var buckets: [FileDayGroup: [ListedFile]] = [:]
        for file in files { buckets[of(file.date, now: now, calendar: calendar), default: []].append(file) }
        return allCases.compactMap { group in
            guard let list = buckets[group], !list.isEmpty else { return nil }
            return FileDaySection(group: group, files: list)
        }
    }
}

public struct FileDaySection: Identifiable, Equatable, Sendable {
    public var group: FileDayGroup
    public var files: [ListedFile]
    public var id: FileDayGroup { group }
}

public enum FileDate {
    /// 行里的时间：今天写「10:05」，昨天写「昨天」，一周内写「周日」，再早写「10月12日」。
    public static func short(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let english = L10n.isEnglish
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: english ? "en_US" : "zh_Hans")
        switch FileDayGroup.of(date, now: now, calendar: calendar) {
        case .today:
            f.dateFormat = "HH:mm"
        case .yesterday:
            return tr("昨天")
        case .earlier:
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date),
                                               to: calendar.startOfDay(for: now)).day ?? 99
            if days >= 0 && days < 7 {
                f.dateFormat = "EEE"
            } else if calendar.isDate(date, equalTo: now, toGranularity: .year) {
                f.dateFormat = english ? "MMM d" : "M月d日"
            } else {
                f.dateFormat = english ? "MMM d, yyyy" : "yyyy年M月d日"
            }
        }
        return f.string(from: date)
    }
}

// MARK: - 文件类型小标

/// 行首那张折角纸上写的字和颜色。
public struct FileBadge: Equatable, Sendable {
    public var label: String
    public var colorHex: String

    public static func of(_ file: ListedFile) -> FileBadge {
        if file.isDirectory { return FileBadge(label: "", colorHex: "#5A9BEF") }
        return of(extension: file.url.pathExtension)
    }

    public static func of(extension raw: String) -> FileBadge {
        let ext = raw.lowercased()
        let label: String
        switch ext {
        case "docx": label = "DOC"
        case "xlsx": label = "XLS"
        case "pptx": label = "PPT"
        case "jpeg": label = "JPG"
        case "": label = "FILE"
        default: label = String(ext.uppercased().prefix(4))
        }
        let color: String
        switch ext {
        case "pdf": color = "#E5534B"
        case "doc", "docx", "pages", "rtf", "txt", "md", "odt": color = "#3E8ED0"
        case "xls", "xlsx", "numbers", "csv", "ods": color = "#2FA37A"
        case "ppt", "pptx", "key", "odp": color = "#E07B39"
        case "dmg", "pkg", "mpkg", "app", "iso", "xip": color = "#7A7F8C"
        case "mov", "mp4", "m4v", "avi", "mkv", "webm": color = "#E0567A"
        case "mp3", "m4a", "wav", "aac", "flac", "aiff": color = "#C95BD6"
        default:
            if DownloadKind.images.contains(ext) { color = "#8E6CE0" }
            else if DownloadKind.archives.contains(ext) { color = "#D9A520" }
            else { color = "#6B7280" }
        }
        return FileBadge(label: label, colorHex: color)
    }
}

// MARK: - 多选

/// 多选里勾了哪些。两个面板共用。
public struct MultiSelection<ID: Hashable & Sendable>: Equatable, Sendable {
    public private(set) var ids: Set<ID> = []

    public init(_ ids: Set<ID> = []) { self.ids = ids }

    public var count: Int { ids.count }
    public var isEmpty: Bool { ids.isEmpty }
    public func contains(_ id: ID) -> Bool { ids.contains(id) }

    public mutating func toggle(_ id: ID) {
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
    }

    public mutating func clear() { ids.removeAll() }

    /// 看得见的都勾上了就全取消（只取消看得见的），否则把看得见的都勾上。
    public mutating func toggleAll(_ visible: [ID]) {
        if allSelected(visible) { ids.subtract(visible) } else { ids.formUnion(visible) }
    }

    public func allSelected(_ visible: [ID]) -> Bool {
        !visible.isEmpty && visible.allSatisfy(ids.contains)
    }

    /// 文件被删、被移走、被改名以后，勾着的旧名字要去掉，不然按钮上的个数不对。
    public mutating func prune(keeping existing: some Sequence<ID>) {
        ids.formIntersection(existing)
    }

    /// 按列表的顺序取出勾着的。
    public func ordered(_ all: [ID]) -> [ID] { all.filter(ids.contains) }
}

// MARK: - 改名和撞名

public enum FileRename {
    public enum Problem: Error, Equatable, Sendable {
        case empty, invalidCharacter, hidden, taken, tooLong

        public var message: String {
            switch self {
            case .empty: tr("名字不能为空")
            case .invalidCharacter: tr("名字里不能有「/」或「:」")
            case .hidden: tr("名字不能以「.」开头")
            case .taken: tr("这个名字已经有了")
            case .tooLong: tr("名字太长了")
            }
        }
    }

    /// 检查新名字，返回真正要用的名字；和原来一样时返回 nil（什么都不用做）。
    /// 删掉了扩展名时把原来的补回去，免得文件改完打不开。
    /// `siblings` 是同一个文件夹里的其他名字，比较时不分大小写（APFS 默认如此），
    /// 只改大小写的自己不算撞名。
    public static func check(_ proposed: String, original: String,
                             siblings: Set<String>) -> Result<String?, Problem> {
        var name = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .failure(.empty) }
        guard !name.contains("/"), !name.contains(":") else { return .failure(.invalidCharacter) }
        guard !name.hasPrefix(".") else { return .failure(.hidden) }
        let originalExt = (original as NSString).pathExtension
        if !originalExt.isEmpty, (name as NSString).pathExtension.isEmpty {
            name += "." + originalExt
        }
        guard name.utf8.count <= 255 else { return .failure(.tooLong) }
        if name == original { return .success(nil) }
        let lower = name.lowercased()
        let taken = siblings.contains { $0.lowercased() == lower && $0 != original }
        if taken { return .failure(.taken) }
        return .success(name)
    }

    /// 「报价单.xlsx」在目标文件夹里已经有了，就叫「报价单 2.xlsx」「报价单 3.xlsx」。
    public static func unique(_ name: String, taken: Set<String>) -> String {
        let lowered = Set(taken.map { $0.lowercased() })
        guard lowered.contains(name.lowercased()) else { return name }
        let ns = name as NSString
        let ext = ns.pathExtension
        let base = ext.isEmpty ? name : ns.deletingPathExtension
        var n = 2
        while true {
            let candidate = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            if !lowered.contains(candidate.lowercased()) { return candidate }
            n += 1
        }
    }
}

public enum ArchiveNaming {
    /// 和访达一样：一个文件压成「名字.zip」，几个文件压成「归档.zip」。撞名时加编号。
    public static func name(for names: [String], taken: Set<String>) -> String {
        let base = names.count == 1 ? names[0] : tr("归档")
        return FileRename.unique(base + ".zip", taken: taken)
    }
}

/// 「移到…」菜单里最近选过的文件夹，最新的在前，最多 3 个，不重复。
public enum RecentFolders {
    public static let limit = 3

    public static func adding(_ path: String, to list: [String]) -> [String] {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return Array(list.prefix(limit)) }
        return Array(([trimmed] + list.filter { $0 != trimmed }).prefix(limit))
    }
}

// MARK: - 下载还剩多久

public enum DownloadETA {
    /// 从第一次看到它（时间、进度）到现在的平均速度推还剩几秒。
    /// 看到不到 2 秒、进度没动或倒退、不知道进度时返回 nil。
    public static func remaining(firstAt: Date, firstFraction: Double?,
                                 now: Date, fraction: Double?) -> TimeInterval? {
        guard let f0 = firstFraction, let f1 = fraction else { return nil }
        let elapsed = now.timeIntervalSince(firstAt)
        guard elapsed >= 2, f1 > f0, f1 < 1 else { return nil }
        let rate = (f1 - f0) / elapsed
        let left = (1 - f1) / rate
        return left.isFinite ? left : nil
    }

    public static func caption(_ seconds: TimeInterval) -> String {
        switch seconds {
        case ..<60: return tr("还剩不到 1 分钟")
        case ..<3600: return tr("还剩 \(Int((seconds / 60).rounded(.up))) 分钟")
        default:
            let hours = Int((seconds / 3600).rounded(.up))
            return hours > 24 ? tr("还要很久") : tr("还剩 \(hours) 小时")
        }
    }

    /// 正在下载那张卡上的小字：「64% · 还剩 1 分钟」「64%」「下载中」。
    public static func line(fraction: Double?, remaining: TimeInterval?) -> String {
        let percent = DownloadProgress.caption(fraction)
        guard fraction != nil, let remaining else { return percent }
        return "\(percent) · \(caption(remaining))"
    }
}

// MARK: - 标注

public enum MarkupTool: String, CaseIterable, Sendable {
    case arrow, box, mosaic, text

    public var title: String {
        switch self {
        case .arrow: tr("箭头")
        case .box: tr("框")
        case .mosaic: tr("马赛克")
        case .text: tr("文字")
        }
    }
}

public enum MarkupColor: String, CaseIterable, Sendable {
    case red, yellow, green, white

    public var hex: String {
        switch self {
        case .red: "#FF6B5A"
        case .yellow: "#FFC94D"
        case .green: "#5BD98A"
        case .white: "#FFFFFF"
        }
    }

    public var title: String {
        switch self {
        case .red: tr("红色")
        case .yellow: tr("黄色")
        case .green: tr("绿色")
        case .white: tr("白色")
        }
    }

    /// 0...1 的 RGB，给 CoreGraphics 用。
    public var rgb: (r: Double, g: Double, b: Double) {
        let digits = hex.dropFirst()
        let value = UInt32(digits, radix: 16) ?? 0xFFFFFF
        return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }
}

/// 一笔标注。点都用 0...1 的比例记（左上角是 0,0，向下为正），
/// 所以面板里的小图和存出去的原尺寸图画出来位置一样。
public struct Markup: Equatable, Sendable, Identifiable {
    public var id: Int
    public var tool: MarkupTool
    public var color: MarkupColor
    public var start: CGPoint
    public var end: CGPoint
    /// 只有文字用。
    public var text: String

    public init(id: Int, tool: MarkupTool, color: MarkupColor, start: CGPoint, end: CGPoint, text: String = "") {
        self.id = id
        self.tool = tool
        self.color = color
        self.start = start
        self.end = end
        self.text = text
    }

    /// 框和马赛克的范围（比例）。
    public var rect: CGRect { MarkupGeometry.rect(from: start, to: end) }
}

/// 画了哪几笔和撤销。
public struct MarkupDocument: Equatable, Sendable {
    public private(set) var marks: [Markup] = []
    private var nextID = 1
    /// 最近一次拷贝或存图以后又画过。
    public private(set) var dirty = false

    public init() {}

    public var isEmpty: Bool { marks.isEmpty }
    public var canUndo: Bool { !marks.isEmpty }

    /// 加一笔。拖得太短的箭头、框、马赛克（手抖点了一下）和空文字不算，返回 false。
    @discardableResult
    public mutating func add(_ tool: MarkupTool, color: MarkupColor, from start: CGPoint, to end: CGPoint,
                             text: String = "") -> Bool {
        let a = MarkupGeometry.clamp(start)
        let b = MarkupGeometry.clamp(end)
        switch tool {
        case .text:
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        case .arrow:
            guard ((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y)).squareRoot() >= MarkupGeometry.minimumDrag else { return false }
        case .box, .mosaic:
            let r = MarkupGeometry.rect(from: a, to: b)
            guard r.width >= MarkupGeometry.minimumDrag, r.height >= MarkupGeometry.minimumDrag else { return false }
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        marks.append(Markup(id: nextID, tool: tool, color: color, start: a, end: b, text: trimmed))
        nextID += 1
        dirty = true
        return true
    }

    public mutating func undo() {
        guard !marks.isEmpty else { return }
        marks.removeLast()
        dirty = !marks.isEmpty
    }

    public mutating func clear() {
        marks.removeAll()
        dirty = false
    }

    /// 拷贝或存好了。
    public mutating func markExported() { dirty = false }
}

public enum MarkupGeometry {
    /// 比例里拖不到这么长（约图宽的 1.5%）不算一笔。
    public static let minimumDrag: CGFloat = 0.015

    public static func clamp(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 0), 1), y: min(max(p.y, 0), 1))
    }

    /// 图按比例放进框里、居中，返回图实际占的区域。
    public static func fit(image: CGSize, in box: CGSize) -> CGRect {
        guard image.width > 0, image.height > 0, box.width > 0, box.height > 0 else { return .zero }
        let scale = min(box.width / image.width, box.height / image.height)
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(x: (box.width - size.width) / 2, y: (box.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    /// 面板里的一个点换成图上的比例（夹在图里）。
    public static func normalized(_ p: CGPoint, in rect: CGRect) -> CGPoint {
        guard rect.width > 0, rect.height > 0 else { return .zero }
        return clamp(CGPoint(x: (p.x - rect.minX) / rect.width, y: (p.y - rect.minY) / rect.height))
    }

    /// 比例换回一个区域里的点（左上角为原点）。
    public static func point(_ p: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height)
    }

    public static func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    /// 线宽跟着图宽走，面板里的小图和原图看起来一样粗。
    public static func lineWidth(imageWidth: CGFloat) -> CGFloat { max(2, imageWidth * 0.004) }

    /// 箭头两翼的端点。
    public static func arrowHead(from a: CGPoint, to b: CGPoint, length: CGFloat,
                                 spread: CGFloat = 0.5) -> (CGPoint, CGPoint) {
        let angle = atan2(b.y - a.y, b.x - a.x)
        let left = CGPoint(x: b.x - length * cos(angle + spread), y: b.y - length * sin(angle + spread))
        let right = CGPoint(x: b.x - length * cos(angle - spread), y: b.y - length * sin(angle - spread))
        return (left, right)
    }

    /// 马赛克一格多大（像素），至少 6。
    public static func mosaicCell(imageWidth: CGFloat) -> CGFloat { max(6, (imageWidth / 90).rounded()) }

    /// 文字字号（像素），至少 12。
    public static func textSize(imageWidth: CGFloat) -> CGFloat { max(12, imageWidth * 0.028) }
}

public enum MarkupNaming {
    /// 存为新图的名字：「截屏 10.18.33.png」存成「截屏 10.18.33 标注.png」，撞名加编号。
    public static func newName(original: String, taken: Set<String>) -> String {
        let base = (original as NSString).deletingPathExtension
        return FileRename.unique("\(base) \(tr("标注")).png", taken: taken)
    }
}
