import Foundation

// MARK: - 动态图标：Chrome 与 Safari
//
// 悬停：Chrome 中间的彩色圆盘轻转一下弹回，Safari 只有表盘轻摆两下停住，外壳都不动。
// 加载：只有 Chrome 能读到「当前标签页在不在加载」（AppleScript），读到时沿图标边缘走一道
// 细蓝弧；Safari 没有不需要用户去开开发者设置的加载信号，所以 Safari 只有悬停，不画进度。
// 下载、播放、标签数都没有可靠来源，不做，更不画假数字。

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
