import Foundation

/// The pure half of the file widgets: where the screenshots go, which files
/// are screenshots, and how a listing is ordered.
public enum ScreenshotLocation {
    /// `com.apple.screencapture location`, which may carry a tilde, a
    /// trailing slash, or be missing entirely. The Desktop is where macOS
    /// writes them when nobody has said otherwise.
    public static func resolve(_ raw: String?, home: URL) -> URL {
        let desktop = home.appendingPathComponent("Desktop", isDirectory: true)
        guard var path = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else {
            return desktop
        }
        if path == "~" { return home }
        if path.hasPrefix("~/") { path = home.path + String(path.dropFirst(1)) }
        guard path.hasPrefix("/") else { return desktop }
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }
}

public enum ScreenshotNaming {
    /// The prefixes macOS names a capture with, across the languages and
    /// releases it has shipped. A custom `name` default is checked as well.
    public static let prefixes = ["Screenshot", "Screen Shot", "截屏", "屏幕快照",
                                  "Screen Recording", "录屏", "屏幕录制"]

    public static func looksLikeCapture(_ fileName: String, customPrefix: String? = nil) -> Bool {
        if let customPrefix, !customPrefix.isEmpty, fileName.hasPrefix(customPrefix) { return true }
        return prefixes.contains { fileName.hasPrefix($0) }
    }
}

/// A file as the listing widgets carry it.
public struct ListedFile: Hashable, Sendable, Identifiable {
    public var url: URL
    public var date: Date
    public var isDirectory: Bool
    public var size: Int64?

    public var id: URL { url }
    public var name: String { url.lastPathComponent }

    public init(url: URL, date: Date, isDirectory: Bool = false, size: Int64? = nil) {
        self.url = url
        self.date = date
        self.isDirectory = isDirectory
        self.size = size
    }

    /// Newest first, then by name so equal dates do not shuffle between polls.
    public static func newestFirst(_ files: [ListedFile], limit: Int) -> [ListedFile] {
        let sorted = files.sorted {
            $0.date != $1.date ? $0.date > $1.date
                : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return Array(sorted.prefix(max(0, limit)))
    }

    /// Extensions treated as pictures without asking Launch Services.
    public static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "tif", "tiff", "bmp", "webp", "avif",
    ]

    public var isImage: Bool { Self.imageExtensions.contains(url.pathExtension.lowercased()) }

    /// An unfinished browser download, which is not a file yet.
    public var isPartialDownload: Bool {
        ["download", "crdownload", "part", "partial"].contains(url.pathExtension.lowercased())
    }
}

/// A short "how long ago" in Chinese, for captions.
public enum RelativeAge {
    public static func caption(_ date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "刚刚"
        case ..<3600: return "\(Int(seconds / 60)) 分钟前"
        case ..<86_400: return "\(Int(seconds / 3600)) 小时前"
        case ..<(86_400 * 30): return "\(Int(seconds / 86_400)) 天前"
        default:
            let f = DateFormatter()
            f.locale = Locale(identifier: "zh_Hans")
            f.dateFormat = "yyyy年M月d日"
            return f.string(from: date)
        }
    }
}

/// Which picture a slideshow shows at a moment.
///
/// Derived from the clock rather than kept in a timer: the shelf already
/// redraws every second, so the frame is a function of the time and every
/// copy of the tile agrees without coordinating.
public enum Slideshow {
    public static func index(at date: Date, interval: Double, count: Int, shuffle: Bool) -> Int {
        guard count > 0 else { return 0 }
        let step = max(1, interval.isFinite ? interval : 30)
        let slot = Int((date.timeIntervalSinceReferenceDate / step).rounded(.down))
        let ordered = ((slot % count) + count) % count
        // Two pictures alternate whichever way they are ordered.
        guard shuffle, count > 2 else { return ordered }
        // Every picture once per round, each round in its own order, and the
        // first of a round never the last of the one before it.
        let round = Int((Double(slot) / Double(count)).rounded(.down))
        return order(round: round, count: count)[ordered]
    }

    private static func order(round: Int, count: Int) -> [Int] {
        var order = permutation(seed: round, count: count)
        let previousLast = permutation(seed: round - 1, count: count)[count - 1]
        if order[0] == previousLast { order.swapAt(0, 1) }
        return order
    }

    /// Fisher-Yates driven by SplitMix64, so a round's order is the same on
    /// every redraw and every Mac.
    private static func permutation(seed: Int, count: Int) -> [Int] {
        var state = UInt64(bitPattern: Int64(seed)) &+ 0x9E37_79B9_7F4A_7C15
        func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        var items = Array(0..<count)
        for i in stride(from: count - 1, to: 0, by: -1) {
            let j = Int(next() % UInt64(i + 1))
            items.swapAt(i, j)
        }
        return items
    }
}
