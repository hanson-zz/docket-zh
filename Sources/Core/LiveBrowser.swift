import Foundation

// MARK: - 动态图标：Chrome 与 Safari
//
// 悬停：Chrome 中间的彩色圆盘轻转一下弹回，Safari 只有表盘轻摆两下停住，外壳都不动。
// 加载：图标边缘走一道细蓝弧。Chrome 用 AppleScript 问当前标签页；Safari 看窗口工具栏上
// 「重新载入」按钮是不是变成了「停止载入」（辅助功能，只读按钮名字，不读网页）。
// 下载：右下角蓝色下载徽标。Safari 读「下载」文件夹里 .download 包自带的已下载/总字节，
// 画真实进度；Chrome 的 .crdownload 没有总大小，只画徽标不画进度。
// 播放：右下角紫色播放徽标加一圈柔光，按系统音频里这个浏览器（含它的网页进程）有没有在出声。
// 读不到就不画，不画假数字。

public enum LiveBrowser: String, CaseIterable, Equatable, Sendable {
    case chrome
    case safari

    public static let safariBundleID = "com.apple.Safari"
    /// Safari 子开关，默认开。Chrome 沿用 `LiveIconToggles.chromeKey`。
    public static let safariKey = "liveIcons.safari"

    public init?(bundleID: String) {
        switch bundleID {
        case LiveIconApp.chromeBundleID: self = .chrome
        case Self.safariBundleID: self = .safari
        default: return nil
        }
    }

    /// 悬停时转动的那一圈占图标内容区的比例：Chrome 连圆盘外一圈白边一起转（白边转了看不出，
    /// 圆盘边上就不会错位），Safari 是表盘。
    public var dialFraction: Double {
        switch self {
        case .chrome: 0.86
        case .safari: 0.84
        }
    }

    /// 悬停转到的角度（度）。Chrome 顺时针 15 度后弹回；Safari 先 +10 再 -6 再回正。
    public var hoverKeyframes: [Double] {
        switch self {
        case .chrome: [15, 0]
        case .safari: [10, -6, 0]
        }
    }
}

/// Chrome 加载时边缘细弧：一圈 1 秒，弧长四分之一圈。
public enum LiveBrowserRing {
    public static let period: TimeInterval = 1.0
    public static let arc = 0.25

    /// 某一刻弧头在边上的位置（0 到 1）。
    public static func head(at time: TimeInterval) -> Double {
        let p = (time / period).truncatingRemainder(dividingBy: 1)
        return p < 0 ? p + 1 : p
    }
}

/// 浏览器此刻的状态。读不到的项保持默认（不画）。
public struct LiveBrowserState: Equatable, Sendable {
    public var loading = false
    public var download: LiveBrowserDownload = .none
    public var playing = false

    public init(loading: Bool = false, download: LiveBrowserDownload = .none, playing: Bool = false) {
        self.loading = loading
        self.download = download
        self.playing = playing
    }

    /// 右下角挂哪个徽标：下载优先于播放，一次只挂一个。
    public var corner: Corner? {
        if download != .none { return .download }
        return playing ? .playing : nil
    }

    public enum Corner: Equatable, Sendable { case download, playing }
}

public enum LiveBrowserDownload: Equatable, Sendable {
    case none
    /// 在下，但不知道总大小。
    case indeterminate
    /// 0 到 1。
    case fraction(Double)

    /// 未完成下载的扩展名。
    public static func browser(forExtension ext: String) -> LiveBrowser? {
        switch ext.lowercased() {
        case "download": .safari
        case "crdownload": .chrome
        default: nil
        }
    }

    /// 最近这么久内还在变的才算正在下；放着不管的半截文件不算。
    public static let activeWindow: TimeInterval = 30

    public static func isActive(modified: Date, now: Date) -> Bool {
        now.timeIntervalSince(modified) <= activeWindow
    }

    /// Safari .download 包里 Info.plist 的已下载 / 总字节。
    public static func safariBytes(_ plist: [String: Any]) -> (done: Double, total: Double)? {
        func number(_ key: String) -> Double? {
            (plist[key] as? NSNumber)?.doubleValue
        }
        guard let total = number("DownloadEntryProgressTotalToLoad"), total > 0 else { return nil }
        let done = number("DownloadEntryProgressBytesSoFar") ?? 0
        return (max(0, done), total)
    }

    /// 几个下载合在一起：都知道总大小时按字节合成一个进度，有一个不知道就不画进度。
    public static func combine(_ parts: [(done: Double, total: Double)?]) -> LiveBrowserDownload {
        guard !parts.isEmpty else { return .none }
        var done = 0.0, total = 0.0
        for part in parts {
            guard let part else { return .indeterminate }
            done += part.done
            total += part.total
        }
        guard total > 0 else { return .indeterminate }
        return .fraction(min(1, max(0, done / total)))
    }
}

/// Safari 工具栏上的「停止载入」按钮：网页在加载时「重新载入」变成它。
public enum LiveSafariLoading {
    static let stopWords = ["stop loading", "停止载入", "停止加载", "停止載入"]

    /// 按钮的说明、标题或提示里有没有「停止载入」。
    public static func isStopButton(_ texts: [String]) -> Bool {
        texts.contains { text in
            let lower = text.lowercased()
            return stopWords.contains { lower.contains($0) }
        }
    }
}
