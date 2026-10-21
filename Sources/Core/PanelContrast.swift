import Foundation

/// 面板浅色玻璃上主题色当文字时要往黑里压多少（`Color.panelReadable` 用）。
///
/// 原来一律往黑里调 30%，紫、蓝这类本来就深的色够了，可计算器的黄 #FFCC00、
/// 天气的浅蓝 #7CC8F2、仪表盘的浅蓝 #7FD1FF 这类高亮度色调完还是太亮，在近白
/// 玻璃上对比度不到 4.5。这里按目标对比度找最少要压多少：至少 30%（和原来
/// 一样，深色主题色看起来不变），不够就继续压到够为止。压法和
/// `NSColor.blended(withFraction:of: .black)` 一致：sRGB 各分量乘 (1 - 比例)。
/// 只管浅色外观；深色外观主题色原样，不经过这里。
public enum PanelContrast {
    /// 浅色玻璃按近白算（液态玻璃浅色下大致的底色）。
    public static let lightGlass = ColorCode(red: 0xF4 / 255.0, green: 0xF4 / 255.0, blue: 0xF6 / 255.0)
    /// 正文文字的目标对比度（WCAG AA）。
    public static let textContrast = 4.5
    /// 图形（圆环、色条、细图标）的目标对比度（WCAG 非文字 3:1）。
    public static let graphicContrast = 3.0
    /// 最少压这么多，和原来固定 30% 一致。
    public static let minimumFraction = 0.3

    /// 往黑里压 `fraction`（0...1）。
    public static func darkened(_ color: ColorCode, by fraction: Double) -> ColorCode {
        let keep = 1 - min(1, max(0, fraction.isFinite ? fraction : 0))
        return ColorCode(red: color.red * keep, green: color.green * keep, blue: color.blue * keep)
    }

    /// 要压多少才能在 `background` 上达到 `minContrast`：结果在
    /// `atLeast...1` 之间，取满足目标的最小值（精度千分之一）。
    /// 压到纯黑都不够（背景本身很暗）就返回 1。
    /// `atLeast` 是下限：文字用 `minimumFraction`（30%），图形传 0，本来够亮度差的就不动。
    public static func fraction(for color: ColorCode,
                                minContrast: Double = textContrast,
                                background: ColorCode = lightGlass,
                                atLeast: Double = minimumFraction) -> Double {
        func ok(_ f: Double) -> Bool {
            WidgetTint.contrastRatio(darkened(color, by: f), background) >= minContrast
        }
        let start = min(1, max(0, atLeast))
        if ok(start) { return start }
        if !ok(1) { return 1 }
        var low = start, high = 1.0
        while high - low > 0.001 {
            let mid = (low + high) / 2
            if ok(mid) { high = mid } else { low = mid }
        }
        return high
    }

    /// 压好的颜色，`fraction(for:)` 加 `darkened`。
    public static func readable(_ color: ColorCode,
                                minContrast: Double = textContrast,
                                background: ColorCode = lightGlass,
                                atLeast: Double = minimumFraction) -> ColorCode {
        darkened(color, by: fraction(for: color, minContrast: minContrast, background: background,
                                     atLeast: atLeast))
    }

    /// 图形（圆环、色条、细图标）在浅色玻璃上的颜色：只在不到 3:1 时压，压到刚好够。
    public static func graphic(_ color: ColorCode) -> ColorCode {
        readable(color, minContrast: graphicContrast, atLeast: 0)
    }
}
