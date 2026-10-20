import Foundation

/// 新外观跟着内容是深色还是浅色走：扩展栏卡片读扩展栏当前的外观（白底、浅色玻璃
/// 时是浅色，黑底、深色玻璃时是深色，其余跟系统），面板读面板窗口的外观。
public enum RadioSkinTone: String, CaseIterable, Sendable {
    case dark
    case light

    /// `darkContent` 为 true 时内容是深色的（白字），用暗色主版。
    public init(darkContent: Bool) {
        self = darkContent ? .dark : .light
    }
}

/// 收藏里当前那一行的标法，每套新外观不同。
public enum RadioSkinRowStyle: String, Sendable {
    /// 圆角浅色强调底，左边一道竖条（烟晶、灯阵、瓷白圆盘）。
    case round
    /// 直角强调底，左边一颗像素爱心（掌机像素）。
    case square
    /// 不铺色块，下面一根强调色细线（墨白直尺）。
    case line
}

/// 五款新外观各自的暗色、浅色两组颜色，数值照设计稿 design/radio-skins2.py 的
/// `TH_`。界面层只从这里取色，各皮肤自己的装饰色（LED 点阵、液晶屏等）写在
/// 各自的 View 文件里。
///
/// - `background` 面板底色；
/// - `text` 正文色，`secondaryOpacity` 是次要字在 `text` 上的不透明度；
/// - `accent` 实心强调（主播放键、音量条），`ink` 是压在 `accent` 上的图标色，
///   一律深色（墨白直尺浅色版主钮是浅灰实心加黑描边）；
/// - `accentText` 是压在底色上的强调小字（“搜索电台”“正在听”）；
/// - `line` 分隔线的颜色（用时再配很低的不透明度）。
public struct RadioSkinPalette: Equatable, Sendable {
    public var background: ColorCode
    public var text: ColorCode
    public var accent: ColorCode
    public var accentText: ColorCode
    public var ink: ColorCode
    public var secondaryOpacity: Double
    public var line: ColorCode
    /// 收藏当前行的强调底不透明度。
    public var highlightOpacity: Double
    public var rowStyle: RadioSkinRowStyle

    public init(background: String, text: String, accent: String, accentText: String, ink: String,
                secondaryOpacity: Double, line: String, highlightOpacity: Double = 0.15,
                rowStyle: RadioSkinRowStyle = .round) {
        self.background = ColorCode(hex: background) ?? ColorCode(red: 0, green: 0, blue: 0)
        self.text = ColorCode(hex: text) ?? ColorCode(red: 1, green: 1, blue: 1)
        self.accent = ColorCode(hex: accent) ?? ColorCode(red: 1, green: 1, blue: 1)
        self.accentText = ColorCode(hex: accentText) ?? self.accent
        self.ink = ColorCode(hex: ink) ?? ColorCode(red: 0, green: 0, blue: 0)
        self.secondaryOpacity = secondaryOpacity
        self.line = ColorCode(hex: line) ?? self.text
        self.highlightOpacity = highlightOpacity
        self.rowStyle = rowStyle
    }

    /// 有两版配色的皮肤，按选择器里的顺序。
    public static let skins: [RadioSkin] = [.smoke, .led, .porcelain, .pixel, .ruler]

    /// 这套皮肤这一版的配色；经典和三款复古皮肤没有（nil），照旧用自己的颜色。
    public static func palette(_ skin: RadioSkin, tone: RadioSkinTone) -> RadioSkinPalette? {
        switch (skin, tone) {
        case (.smoke, .dark):
            RadioSkinPalette(background: "#1B1A1F", text: "#FFFFFF", accent: "#F4C27A", accentText: "#F4C27A",
                             ink: "#2A1A08", secondaryOpacity: 0.62, line: "#FFFFFF")
        case (.smoke, .light):
            RadioSkinPalette(background: "#F3EFEA", text: "#24201D", accent: "#EDB867", accentText: "#9A5A14",
                             ink: "#2A1A08", secondaryOpacity: 0.66, line: "#24201D")
        case (.led, .dark):
            RadioSkinPalette(background: "#19181B", text: "#FFFFFF", accent: "#FFC845", accentText: "#FFC845",
                             ink: "#2A1E02", secondaryOpacity: 0.62, line: "#FFFFFF")
        case (.led, .light):
            RadioSkinPalette(background: "#F2F1EE", text: "#1D1D21", accent: "#FFC845", accentText: "#8A6200",
                             ink: "#2A1E02", secondaryOpacity: 0.66, line: "#1D1D21")
        case (.porcelain, .dark):
            RadioSkinPalette(background: "#2A2A2E", text: "#F4F2EF", accent: "#FF8A5C", accentText: "#FF9A72",
                             ink: "#2E0E02", secondaryOpacity: 0.64, line: "#FFFFFF")
        case (.porcelain, .light):
            RadioSkinPalette(background: "#ECE9E4", text: "#2B2722", accent: "#F07A4A", accentText: "#B04A1E",
                             ink: "#2E0E02", secondaryOpacity: 0.68, line: "#2B2722")
        case (.pixel, .dark):
            RadioSkinPalette(background: "#1C1A1D", text: "#FFFFFF", accent: "#FF5A48", accentText: "#FF8577",
                             ink: "#2A0703", secondaryOpacity: 0.62, line: "#FFFFFF",
                             highlightOpacity: 0.16, rowStyle: .square)
        case (.pixel, .light):
            RadioSkinPalette(background: "#F2F0EE", text: "#1F1B1C", accent: "#FF5A48", accentText: "#B42318",
                             ink: "#2A0703", secondaryOpacity: 0.66, line: "#1F1B1C",
                             highlightOpacity: 0.16, rowStyle: .square)
        case (.ruler, .dark):
            RadioSkinPalette(background: "#121214", text: "#FFFFFF", accent: "#FFFFFF", accentText: "#FF5A4A",
                             ink: "#111111", secondaryOpacity: 0.6, line: "#FFFFFF", rowStyle: .line)
        case (.ruler, .light):
            // 守“实心按钮深色字”：浅色版主钮是浅灰实心、黑描边、黑图标。
            RadioSkinPalette(background: "#F5F5F3", text: "#111111", accent: "#E4E4E0", accentText: "#C8281C",
                             ink: "#111111", secondaryOpacity: 0.64, line: "#111111", rowStyle: .line)
        default:
            nil
        }
    }

    /// 次要字实际的颜色：`text` 按 `secondaryOpacity` 叠在底色上。
    public var secondaryText: ColorCode { Self.mix(text, over: background, opacity: secondaryOpacity) }

    /// 浅色版（底色亮）。
    public var isLight: Bool { background.isLight }

    /// `top` 以 `opacity` 盖在 `bottom` 上的结果。
    public static func mix(_ top: ColorCode, over bottom: ColorCode, opacity: Double) -> ColorCode {
        let a = min(max(opacity, 0), 1)
        return ColorCode(red: bottom.red + (top.red - bottom.red) * a,
                         green: bottom.green + (top.green - bottom.green) * a,
                         blue: bottom.blue + (top.blue - bottom.blue) * a)
    }

    /// 正文、次要字、强调小字对底色和图标对实心强调里最低的那个对比度。
    public var minimumContrast: Double {
        [WidgetTint.contrastRatio(text, background),
         WidgetTint.contrastRatio(secondaryText, background),
         WidgetTint.contrastRatio(accentText, background),
         WidgetTint.contrastRatio(ink, accent)].min() ?? 0
    }
}
