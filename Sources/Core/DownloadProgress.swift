import Foundation

/// “下载”里还没下完的文件和它下到了哪儿，用来在文件图标上画进度。
///
/// 进度从两处读，都读不到时就是“不确定”（只画流动的光，不写百分比）：
/// - 文件的扩展属性 `com.apple.progress.fractionCompleted`，访达自己也是看它
///   在图标上画进度条的，写的是 0 到 1 的小数；
/// - Safari 的 `.download` 包里的 Info.plist，记着已下载和总共的字节数。
/// Chrome 的 `.crdownload` 两样都可能没有，那就显示“下载中”。
public struct ActiveDownload: Hashable, Sendable, Identifiable {
    public var file: ListedFile
    /// 0...1；nil 是不知道总大小。
    public var fraction: Double?

    public var id: URL { file.url }

    public init(file: ListedFile, fraction: Double?) {
        self.file = file
        self.fraction = fraction
    }

    /// 下完以后的名字：去掉 .download / .crdownload / .part 这类尾巴。
    public var finalName: String { DownloadProgress.finalName(file.name) }
}

public enum DownloadProgress {
    public static let attributeName = "com.apple.progress.fractionCompleted"

    /// 扩展属性里的小数。读不懂、是负数或不是有限数时返回 nil，大于 1 按 1 算。
    public static func parseFraction(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        guard let value = Double(trimmed), value.isFinite, value >= 0 else { return nil }
        return min(value, 1)
    }

    /// Safari `.download` 包里 Info.plist 的字节数。总数未知（0 或 -1）时返回 nil。
    public static func fraction(safariInfo info: [String: Any]) -> Double? {
        func number(_ key: String) -> Double? {
            if let n = info[key] as? NSNumber { return n.doubleValue }
            if let s = info[key] as? String { return Double(s) }
            return nil
        }
        guard let total = number("DownloadEntryProgressTotalToLoad"), total > 0,
              let done = number("DownloadEntryProgressBytesSoFar"), done >= 0 else { return nil }
        return min(done / total, 1)
    }

    static let partialExtensions: Set<String> = ["download", "crdownload", "part", "partial"]

    /// “电影.mp4.crdownload”是“电影.mp4”；没有真名的（“未确认 123.crdownload”）去掉尾巴。
    public static func finalName(_ name: String) -> String {
        let ns = name as NSString
        guard partialExtensions.contains(ns.pathExtension.lowercased()) else { return name }
        let stripped = ns.deletingPathExtension
        return stripped.isEmpty ? name : stripped
    }

    /// 下完以后的扩展名，用来找对应类型的图标；没有时返回空字符串。
    public static func finalExtension(_ name: String) -> String {
        (finalName(name) as NSString).pathExtension.lowercased()
    }

    /// 图标下面的一行字。
    public static func caption(_ fraction: Double?) -> String {
        guard let fraction else { return "下载中" }
        return "\(Int((min(max(fraction, 0), 1) * 100).rounded(.down)))%"
    }

    /// 有正在下载的文件时，“下载”文件夹多久看一次，让进度走得顺一些。
    public static func pollInterval(downloading: Bool, idle: Double) -> Double {
        downloading ? min(idle, 1.5) : idle
    }

    #if canImport(Darwin)
    /// 读一个未完成下载的进度。在后台线程调用。
    public static func read(_ url: URL) -> Double? {
        if let raw = attribute(attributeName, of: url), let value = parseFraction(raw) {
            return value
        }
        let info = url.appendingPathComponent("Info.plist")
        if let data = try? Data(contentsOf: info),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            return fraction(safariInfo: plist)
        }
        return nil
    }

    static func attribute(_ name: String, of url: URL) -> String? {
        url.withUnsafeFileSystemRepresentation { path -> String? in
            guard let path else { return nil }
            let size = getxattr(path, name, nil, 0, 0, 0)
            guard size > 0, size < 256 else { return nil }
            var buffer = [UInt8](repeating: 0, count: size)
            let read = getxattr(path, name, &buffer, size, 0, 0)
            guard read > 0 else { return nil }
            return String(decoding: buffer.prefix(read), as: UTF8.self)
        }
    }
    #endif
}
