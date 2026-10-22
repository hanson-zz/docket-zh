import Foundation

// MARK: - 面板实心主按钮的颜色（液态玻璃）

/// 面板里实心主按钮（「发送」「保存」「拷贝」这类）可用、禁用两种样子的颜色约定，
/// 放在 Core 里算对比度、写测试；界面那边的 `PanelSolidButtonStyle` 照这里画。
///
/// 原来禁用时是把实心色整体调到 0.35 左右，字还是白的：浅色玻璃上变成淡蓝底
/// 白字，几乎看不清（真机截图里 AI 助手的「复制问题并打开」）。现在：
/// - 可用：实心 #2563EB 白字（对比度 5.2）；卡片设了主题色时按 `solid(for:)`：
///   优先白字，不够 4.5 同色相加深，加深得发灰发黑就改深色字配原色。
/// - 禁用：中性浅灰底（同 `panelFill`：浅色黑 0.05，深色白 0.09）加一道细边，
///   字用次级字色（同 `panelSecondary`：浅色 #18161C 的 0.68，深色白 0.68），
///   浅色下对比度约 5.5，深色约 6，都过 4.5。
/// - 禁用的小芯片（「剪贴板」）：字用三级字色（同 `panelTertiary`），至少 3:1。
///
/// 这里的透明度和 PanelColors.swift 里的语义色一一对应，改那边时这里一起改。
public enum PanelButtonLook {
    /// 实心蓝（和刘海对话的实心按钮同一个蓝）。
    public static let solidBlueHex = "#2563EB"
    public static let solidBlue = ColorCode(red: 0x25 / 255.0, green: 0x63 / 255.0, blue: 0xEB / 255.0)

    /// 浅色玻璃按近白算（同 `PanelContrast.lightGlass`）。
    public static let lightGlass = PanelContrast.lightGlass
    /// 深色玻璃按深灰算（液态玻璃深色下大致的底色）。
    public static let darkGlass = ColorCode(red: 0x26 / 255.0, green: 0x26 / 255.0, blue: 0x2A / 255.0)

    /// 浅色下的字色底子（`panelPrimary` 浅色）。
    public static let lightInk = ColorCode(red: 0.094, green: 0.086, blue: 0.11)
    public static let white = ColorCode(red: 1, green: 1, blue: 1)
    public static let black = ColorCode(red: 0, green: 0, blue: 0)

    /// 禁用底：`panelFill`。
    public static let disabledFillAlphaLight = 0.05
    public static let disabledFillAlphaDark = 0.09
    /// 禁用主按钮的字：`panelSecondary`。
    public static let disabledTextAlpha = 0.68
    /// 禁用小芯片的字：`panelTertiary`（浅色 0.54，深色 0.5）。
    public static let disabledChipTextAlphaLight = 0.54
    public static let disabledChipTextAlphaDark = 0.5

    /// `top` 以 `alpha` 盖在 `bottom` 上之后的颜色。
    public static func blend(_ top: ColorCode, alpha: Double, over bottom: ColorCode) -> ColorCode {
        let a = min(1, max(0, alpha.isFinite ? alpha : 0))
        return ColorCode(red: top.red * a + bottom.red * (1 - a),
                         green: top.green * a + bottom.green * (1 - a),
                         blue: top.blue * a + bottom.blue * (1 - a))
    }

    /// 禁用按钮的底（已经叠在玻璃上）。
    public static func disabledFill(dark: Bool) -> ColorCode {
        dark ? blend(white, alpha: disabledFillAlphaDark, over: darkGlass)
             : blend(black, alpha: disabledFillAlphaLight, over: lightGlass)
    }

    /// 禁用主按钮的字在禁用底上的对比度。
    public static func disabledTextContrast(dark: Bool) -> Double {
        let fill = disabledFill(dark: dark)
        let text = blend(dark ? white : lightInk, alpha: disabledTextAlpha, over: fill)
        return WidgetTint.contrastRatio(text, fill)
    }

    /// 禁用小芯片的字在芯片底上的对比度。
    public static func disabledChipContrast(dark: Bool) -> Double {
        let fill = disabledFill(dark: dark)
        let alpha = dark ? disabledChipTextAlphaDark : disabledChipTextAlphaLight
        let text = blend(dark ? white : lightInk, alpha: alpha, over: fill)
        return WidgetTint.contrastRatio(text, fill)
    }

    /// 可用时实心蓝底上的白字。
    public static var solidTextContrast: Double { WidgetTint.contrastRatio(white, solidBlue) }

    // MARK: 主题色实心按钮

    /// 主题色按钮上的深色字（主题色太浅、加深又会发灰发黑时用）。
    public static let darkInkHex = "#1A1A1A"
    public static let darkInk = ColorCode(red: 0x1A / 255.0, green: 0x1A / 255.0, blue: 0x1A / 255.0)
    /// 按钮字的最低对比度（WCAG 正文 AA）。
    public static let minimumTextContrast = 4.5
    /// 加深时瞄准的对比度：比 4.5 多留一点，换成 8 位色、过色彩管理后也不掉到线下。
    public static let darkenTarget = 4.6
    /// 加深时每一步降低的 HSL 亮度。
    public static let darkenStep = 0.01
    /// 加深后的相对亮度不到原来的这么多，或 HSL 亮度低于 `muddyLightness`，
    /// 就算「明显发灰发黑」（黄、琥珀、黄绿、浅色马卡龙这类），改用深色字配原色。
    public static let muddyLuminanceRatio = 0.4
    public static let muddyLightness = 0.3
    /// 按下时再加深的 HSL 亮度。
    public static let pressedStep = 0.06

    /// 实心按钮可用态的一组颜色：底、按下的底、字。
    public struct SolidLook: Equatable, Sendable {
        public var fill: ColorCode
        public var pressedFill: ColorCode
        public var ink: ColorCode
        /// 字是深色（`darkInk`）。
        public var inkIsDark: Bool
        /// 底色是在原主题色基础上加深过的。
        public var darkened: Bool

        public var contrast: Double { WidgetTint.contrastRatio(ink, fill) }
        public var pressedContrast: Double { WidgetTint.contrastRatio(ink, pressedFill) }
    }

    /// 没设主题色时：#2563EB 白字（本来就过 4.5）。
    public static var defaultSolid: SolidLook { solid(for: solidBlue) }

    /// 给定主题色，返回按钮底色和字色，字的对比度保证不低于 4.5：
    /// 1. 白字够 4.5，原色白字。
    /// 2. 不够，同色相一点一点降低亮度，直到白字够 4.5。
    /// 3. 加深得太多（明显发灰发黑），而深色字配原色够 4.5，改用原色配深色字。
    /// 按下态再加深一档；深色字时只加深到对比度仍够 4.5 的程度。
    /// 底色是不透明的，浅色、深色外观下字和底的对比度一样。
    public static func solid(for theme: ColorCode) -> SolidLook {
        if WidgetTint.contrastRatio(white, theme) >= minimumTextContrast {
            return SolidLook(fill: theme, pressedFill: pressed(theme, ink: white), ink: white,
                             inkIsDark: false, darkened: false)
        }
        let deep = darkenedForWhite(theme)
        let muddy = WidgetTint.luminance(deep) < WidgetTint.luminance(theme) * muddyLuminanceRatio
            || HSL(deep).lightness < muddyLightness
        if muddy, WidgetTint.contrastRatio(darkInk, theme) >= minimumTextContrast {
            return SolidLook(fill: theme, pressedFill: pressed(theme, ink: darkInk), ink: darkInk,
                             inkIsDark: true, darkened: false)
        }
        return SolidLook(fill: deep, pressedFill: pressed(deep, ink: white), ink: white,
                         inkIsDark: false, darkened: true)
    }

    /// 半透明的主题色先按外观盖在玻璃上（浅色近白，深色深灰），再按不透明色算。
    public static func solid(for theme: ColorCode, alpha: Double, dark: Bool) -> SolidLook {
        guard alpha.isFinite, alpha < 1 else { return solid(for: theme) }
        return solid(for: blend(theme, alpha: alpha, over: dark ? darkGlass : lightGlass))
    }

    /// 同色相降低 HSL 亮度，直到白字对比度够 4.6（留余量，最差降到黑）。
    public static func darkenedForWhite(_ color: ColorCode) -> ColorCode {
        var hsl = HSL(color)
        var code = color
        var guardSteps = 0
        while WidgetTint.contrastRatio(white, code) < darkenTarget, guardSteps < 200 {
            hsl.lightness = max(0, hsl.lightness - darkenStep)
            code = hsl.color
            guardSteps += 1
            if hsl.lightness <= 0 { break }
        }
        return code
    }

    /// 按下的底：再降一档亮度。白字越深越清楚；深色字只降到对比度仍够的程度，降不了就不变。
    static func pressed(_ fill: ColorCode, ink: ColorCode) -> ColorCode {
        let hsl = HSL(fill)
        for step in [pressedStep, pressedStep * 2 / 3, pressedStep / 3] {
            var next = hsl
            next.lightness = max(0, hsl.lightness - step)
            let code = next.color
            if WidgetTint.contrastRatio(ink, code) >= minimumTextContrast { return code }
        }
        return fill
    }

    /// 0 到 1 的 HSL（色相用 0 到 1 一圈）。
    public struct HSL: Equatable, Sendable {
        public var hue: Double
        public var saturation: Double
        public var lightness: Double

        public init(_ c: ColorCode) {
            let maxV = max(c.red, c.green, c.blue), minV = min(c.red, c.green, c.blue)
            let l = (maxV + minV) / 2
            let d = maxV - minV
            guard d > 0 else { hue = 0; saturation = 0; lightness = l; return }
            saturation = l > 0.5 ? d / (2 - maxV - minV) : d / (maxV + minV)
            var h: Double
            if maxV == c.red {
                h = (c.green - c.blue) / d + (c.green < c.blue ? 6 : 0)
            } else if maxV == c.green {
                h = (c.blue - c.red) / d + 2
            } else {
                h = (c.red - c.green) / d + 4
            }
            hue = h / 6
            lightness = l
        }

        public var color: ColorCode {
            let l = min(1, max(0, lightness)), s = min(1, max(0, saturation))
            guard s > 0 else { return ColorCode(red: l, green: l, blue: l) }
            let q = l < 0.5 ? l * (1 + s) : l + s - l * s
            let p = 2 * l - q
            func channel(_ t0: Double) -> Double {
                var t = t0
                if t < 0 { t += 1 }
                if t > 1 { t -= 1 }
                if t < 1.0 / 6 { return p + (q - p) * 6 * t }
                if t < 1.0 / 2 { return q }
                if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
                return p
            }
            return ColorCode(red: channel(hue + 1.0 / 3), green: channel(hue), blue: channel(hue - 1.0 / 3))
        }
    }
}
