import Foundation

// MARK: - 面板实心主按钮的颜色（液态玻璃）

/// 面板里实心主按钮（「发送」「保存」「拷贝」这类）可用、禁用两种样子的颜色约定，
/// 放在 Core 里算对比度、写测试；界面那边的 `PanelSolidButtonStyle` 照这里画。
///
/// 原来禁用时是把实心色整体调到 0.35 左右，字还是白的：浅色玻璃上变成淡蓝底
/// 白字，几乎看不清（真机截图里 AI 助手的「复制问题并打开」）。现在：
/// - 可用：实心 #2563EB（或卡片主题色）底，白字（白字对比度 5.2）。
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
}
