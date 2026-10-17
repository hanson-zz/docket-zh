import Foundation

/// 小组件的颜色主题：每种小组件自己的默认主题色（主色加一个对比辅助色）、
/// 颜色面板里的十五种预设、自定义取色、跟随系统强调色，以及卡片背景。
///
/// 存在小组件自己的配置里，两个键都不在目录默认值里：没设置时读出来是
/// “默认”，用这种小组件自己的颜色，所以旧卡片什么都不用迁移。
///
/// - `tint`：空或 `default` 是默认；`system` 跟随系统强调色；预设的名字
///   （`pink`、`blue`……）；或者自定义的 `#RRGGBB`。认不出的当默认。
/// - `tintBackground`：卡片背景，`none`（默认）、`dark`、`frosted`、
///   `gradient`、`dots`、`lines`，全部用 SwiftUI 画，不用位图。
///
/// 只染原来是单色（白、灰、统一强调色）的部分：进度、圆环、图标方底、数字
/// 强调。封面、照片、天气图标这些本身有颜色的内容不动。
public enum WidgetTint {
    public static let key = "tint"
    public static let backgroundKey = "tintBackground"

    // MARK: 预设

    /// 颜色面板里的预设，顺序就是面板上的顺序（参考倒数日 App 的配色面板）：
    /// 粉、浅粉、玫红、红、黄、橙、琥珀、黄绿、薄荷绿、绿、青、天蓝、蓝、淡紫、紫。
    /// 每种带一个对比色，进度渐变的另一端和小点用它。
    public enum Preset: String, CaseIterable, Sendable, Identifiable {
        case pink, blush, rose, red, yellow, orange, amber, lime
        case mint, green, cyan, sky, blue, lavender, purple

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .pink: tr("粉")
            case .blush: tr("浅粉")
            case .rose: tr("玫红")
            case .red: tr("红")
            case .yellow: tr("黄")
            case .orange: tr("橙")
            case .amber: tr("琥珀")
            case .lime: tr("黄绿")
            case .mint: tr("薄荷绿")
            case .green: tr("绿")
            case .cyan: tr("青")
            case .sky: tr("天蓝")
            case .blue: tr("蓝")
            case .lavender: tr("淡紫")
            case .purple: tr("紫")
            }
        }

        public var hex: String {
            switch self {
            case .pink: "#FF6FA8"
            case .blush: "#FFB3C7"
            case .rose: "#E8417A"
            case .red: "#FF4D4F"
            case .yellow: "#FFD43B"
            case .orange: "#FF8A3D"
            case .amber: "#F5A524"
            case .lime: "#A6D63A"
            case .mint: "#3DDBB0"
            case .green: "#34C759"
            case .cyan: "#1FC8D8"
            case .sky: "#4FB7FF"
            case .blue: "#2F7BFF"
            case .lavender: "#B9A6FF"
            case .purple: "#8E5CF0"
            }
        }

        /// 对比色：大致在色环对面，挑不刺眼的那一档。
        public var contrastHex: String {
            switch self {
            case .pink: "#3DDBB0"
            case .blush: "#4FB7FF"
            case .rose: "#1FC8D8"
            case .red: "#1FC8D8"
            case .yellow: "#8E5CF0"
            case .orange: "#2F7BFF"
            case .amber: "#5B5BD6"
            case .lime: "#B05CE6"
            case .mint: "#FF6FA8"
            case .green: "#FF6FA8"
            case .cyan: "#FF8A3D"
            case .sky: "#F5A524"
            case .blue: "#FF8A3D"
            case .lavender: "#F5A524"
            case .purple: "#3DDBB0"
            }
        }

        public var palette: Palette {
            Palette(main: ColorCode(hex: hex) ?? Palette.fallback.main,
                    contrast: ColorCode(hex: contrastHex) ?? Palette.fallback.contrast)
        }
    }

    // MARK: 选择

    /// 颜色面板里选的是哪一种。
    public enum Choice: Equatable, Sendable {
        /// 这种小组件自己的颜色（`defaultPalette`）。没设置时就是它。
        case kindDefault
        /// 跟随系统强调色。
        case system
        case preset(Preset)
        case custom(ColorCode)

        public static let defaultRaw = "default"
        public static let systemRaw = "system"

        public init(raw: String) {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed == Self.defaultRaw {
                self = .kindDefault
            } else if trimmed == Self.systemRaw {
                self = .system
            } else if let preset = Preset(rawValue: trimmed) {
                self = .preset(preset)
            } else if trimmed.hasPrefix("#"), let code = ColorCode(hex: trimmed) {
                self = .custom(code)
            } else {
                self = .kindDefault
            }
        }

        /// 写回配置的值。默认写空串，读回来一样是默认。
        public var raw: String {
            switch self {
            case .kindDefault: ""
            case .system: Self.systemRaw
            case .preset(let preset): preset.rawValue
            case .custom(let code): code.hex
            }
        }

        /// 用户在面板里自己选过颜色（不是默认）。有自己状态色的卡片
        /// （系统活动、Codex 用量、摸鱼时钟、竹篮）只有选过才换颜色。
        public var isChosen: Bool { self != .kindDefault }
    }

    public static func choice(_ config: WidgetConfig) -> Choice {
        Choice(raw: config.string(key))
    }

    // MARK: 配色

    /// 主色加对比辅助色。
    public struct Palette: Equatable, Sendable {
        public var main: ColorCode
        public var contrast: ColorCode

        public init(main: ColorCode, contrast: ColorCode) {
            self.main = main
            self.contrast = contrast
        }

        init(_ main: String, _ contrast: String) {
            self.init(main: ColorCode(hex: main) ?? Self.fallback.main,
                      contrast: ColorCode(hex: contrast) ?? Self.fallback.contrast)
        }

        static let fallback = Palette(main: ColorCode(red: 0.37, green: 0.42, blue: 0.82),
                                      contrast: ColorCode(red: 1, green: 0.7, blue: 0.25))

        /// 渐变浅的那一端：主色往白里调一点。
        public var light: ColorCode { main.mixed(with: ColorCode(red: 1, green: 1, blue: 1), by: 0.35) }
    }

    /// 选中的颜色落到具体配色上。跟随系统强调色时是 nil，由界面用系统的
    /// 强调色画（对比色仍用这种小组件自己的）。
    public static func palette(_ choice: Choice, kind: WidgetKind) -> Palette? {
        switch choice {
        case .kindDefault: return defaultPalette(kind)
        case .system: return nil
        case .preset(let preset): return preset.palette
        case .custom(let code): return Palette(main: code, contrast: complement(code))
        }
    }

    /// 自定义颜色的对比色：色相转 150 度，亮度和饱和度往中间收一点。
    public static func complement(_ code: ColorCode) -> ColorCode {
        var hsl = code.hslComponents
        hsl.h = (hsl.h + 150).truncatingRemainder(dividingBy: 360)
        hsl.s = max(0.45, min(0.9, hsl.s))
        hsl.l = max(0.45, min(0.65, hsl.l))
        return ColorCode(hue: hsl.h, saturation: hsl.s, lightness: hsl.l)
    }

    /// 每种小组件自己的默认主题色和对比辅助色，按小组件的性格挑，常一起
    /// 放的卡片互相不撞色（见测试里的 `commonNeighbours`）。只用来染原来
    /// 单色的部分；本身有颜色的内容不受影响。
    public static func defaultPalette(_ kind: WidgetKind) -> Palette {
        switch kind {
        case .clock: Palette("#FFB340", "#4F8DF5")
        case .world: Palette("#5E6AD2", "#FFB340")
        case .stopwatch: Palette("#FF8A3D", "#4FB7FF")
        case .timer: Palette("#34C759", "#FF6FA8")
        case .progress: Palette("#8E5CF0", "#3DDBB0")
        case .countdown: Palette("#E8417A", "#1FC8D8")
        case .alarm: Palette("#FF6A3D", "#4FB7FF")
        case .calendar: Palette("#FF4D4F", "#4FB7FF")
        case .reminders: Palette("#FF9F0A", "#2F7BFF")
        case .notes: Palette("#FFD43B", "#8E5CF0")
        case .music: Palette("#FF375F", "#1FC8D8")
        case .battery: Palette("#30D158", "#F5A524")
        case .system: Palette("#A6D63A", "#8E5CF0")
        case .network: Palette("#1FC8D8", "#FF8A3D")
        case .aiUsage: Palette("#C04FE0", "#3DDBB0")
        case .shortcut: Palette("#FF5E8A", "#2F7BFF")
        case .airdrop: Palette("#4FB7FF", "#FF6FA8")
        case .weather: Palette("#5AC8FA", "#FFB340")
        case .stripe: Palette("#635BFF", "#3DDBB0")
        case .paddle: Palette("#FFD43B", "#5B5BD6")
        case .shopify: Palette("#5EC26A", "#8E5CF0")
        // 行情：红涨绿跌，主色红、对比色绿。
        case .stock: Palette("#F0443A", "#34C759")
        case .watchlist: Palette("#FF5A5F", "#30D158")
        case .photos: Palette("#FF9F45", "#4F8DF5")
        case .screenshots: Palette("#64D2FF", "#FF8A3D")
        case .downloads: Palette("#2F7BFF", "#FF8A3D")
        case .fileShelf: Palette("#2EC4B6", "#E8417A")
        case .clipboard: Palette("#FF6FA8", "#3DDBB0")
        case .colorPicker: Palette("#AF52DE", "#FFD43B")
        case .converter: Palette("#30B0C7", "#FF8A3D")
        case .capture: Palette("#FF5A5F", "#1FC8D8")
        case .emoji: Palette("#FFCC00", "#FF6FA8")
        case .search: Palette("#3A8EDB", "#F5A524")
        case .volume: Palette("#6155F5", "#A6D63A")
        case .toggles: Palette("#32ADE6", "#FF8A3D")
        case .github: Palette("#39D353", "#8E5CF0")
        case .currency: Palette("#E2B13C", "#2F7BFF")
        case .calculator: Palette("#FF9F0A", "#5AC8FA")
        case .mail: Palette("#0A84FF", "#F5A524")
        case .recorder: Palette("#FF3B30", "#1FC8D8")
        case .bookmarks: Palette("#FFB340", "#5B5BD6")
        case .appSwitcher: Palette("#5E5CE6", "#3DDBB0")
        case .wallpaper: Palette("#3DDBB0", "#FF6FA8")
        case .microphone: Palette("#FF2D55", "#1FC8D8")
        case .gauges: Palette("#A6D63A", "#FF6FA8")
        case .posture: Palette("#4FC3A1", "#FF8A3D")
        case .todo: Palette("#FF8A3D", "#2F7BFF")
        case .ambient: Palette("#00C3D0", "#F5A524")
        case .lunar: Palette("#E0473A", "#E2B13C")
        case .trash: Palette("#34C759", "#FF4D4F")
        case .habit: Palette("#66D17A", "#B05CE6")
        case .week: Palette("#FF7043", "#4F8DF5")
        case .crypto: Palette("#F7931A", "#8E5CF0")
        case .appVolume: Palette("#7A6CF5", "#FF8A3D")
        case .radio: Palette("#FF8D28", "#2EC4B6")
        case .anniversary: Palette("#FF6FA8", "#E2B13C")
        // 喝水：青蓝。
        case .water: Palette("#1FA8E0", "#FFB340")
        case .translate: Palette("#4F8DF5", "#FF8A3D")
        // 宠物和小熊猫的竹篮：小熊猫橙棕，对比色是竹叶绿。
        case .pet: Palette("#E8743B", "#6DBE45")
        case .podcast: Palette("#9B5DE5", "#F5A524")
        case .perfectDay: Palette("#C8642F", "#6DBE45")
        case .slacker: Palette("#F5A524", "#4FB7FF")
        case .aiAssistant: Palette("#D9663A", "#5B5BD6")
        }
    }

    // MARK: 哪些卡片用

    /// 卡片画的全是图片或自己整张的底色，颜色选了也看不出来，面板里不列。
    public static func offersColor(_ kind: WidgetKind) -> Bool {
        switch kind {
        case .photos, .wallpaper, .notes, .stripe, .paddle, .shopify:
            false
        default:
            true
        }
    }

    /// 背景选项：便签纸、照片、壁纸、封面和摸鱼时钟有自己整张的底，不叠背景。
    public static func offersBackground(_ kind: WidgetKind) -> Bool {
        switch kind {
        case .photos, .wallpaper, .notes, .music, .podcast, .slacker,
             .stripe, .paddle, .shopify:
            false
        default:
            true
        }
    }

    // MARK: 背景

    public enum Background: String, CaseIterable, Sendable, Identifiable {
        /// 无背景。原始值写 `none`，叫 plain 是为了不和 Optional 的 none 混。
        case plain = "none"
        case dark, frosted, gradient, dots, lines

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .plain: tr("无")
            case .dark: tr("深色")
            case .frosted: tr("磨砂")
            case .gradient: tr("渐变")
            case .dots: tr("网点")
            case .lines: tr("线条")
            }
        }

        /// 深色和渐变两种背景本身是深的，卡片里的字固定用浅色。
        public var forcesDarkInk: Bool { self == .dark || self == .gradient }
    }

    public static func background(_ config: WidgetConfig) -> Background {
        Background(rawValue: config.string(backgroundKey)) ?? .plain
    }

    // MARK: 对比度

    /// 假设的卡片底色：深色外观是深灰玻璃，浅色外观是浅灰玻璃。
    public static let darkCard = ColorCode(red: 0.17, green: 0.17, blue: 0.18)
    public static let lightCard = ColorCode(red: 0.92, green: 0.92, blue: 0.94)

    /// WCAG 相对亮度。
    public static func luminance(_ c: ColorCode) -> Double {
        func channel(_ v: Double) -> Double {
            v <= 0.039_28 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(c.red) + 0.7152 * channel(c.green) + 0.0722 * channel(c.blue)
    }

    /// WCAG 对比度，1 到 21。
    public static func contrastRatio(_ a: ColorCode, _ b: ColorCode) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// 压在这个颜色上的字用黑色（true）还是白色：哪个对比度高用哪个。
    public static func inkIsDark(on fill: ColorCode) -> Bool {
        contrastRatio(fill, ColorCode(red: 0, green: 0, blue: 0))
            > contrastRatio(fill, ColorCode(red: 1, green: 1, blue: 1))
    }

    /// 图形和强调字的最低对比度（WCAG 对非文字图形要求 3:1）。
    public static let minimumContrast = 3.0

    /// 把颜色调到在卡片上看得清：深色外观往白里调，浅色外观往黑里调，
    /// 一点一点调到对比度够了为止。本来就够的颜色原样返回。
    public static func readable(_ color: ColorCode, dark: Bool,
                                minimum: Double = minimumContrast) -> ColorCode {
        let card = dark ? darkCard : lightCard
        let target = dark ? ColorCode(red: 1, green: 1, blue: 1) : ColorCode(red: 0, green: 0, blue: 0)
        var amount = 0.0
        var result = color
        while contrastRatio(result, card) < minimum, amount < 1 {
            amount = min(1, amount + 0.05)
            result = color.mixed(with: target, by: amount)
        }
        return result
    }
}

public extension ColorCode {
    /// 往另一种颜色里调 `amount`（0 是自己，1 是对方）。
    func mixed(with other: ColorCode, by amount: Double) -> ColorCode {
        let t = amount.isFinite ? min(1, max(0, amount)) : 0
        return ColorCode(red: red + (other.red - red) * t,
                         green: green + (other.green - green) * t,
                         blue: blue + (other.blue - blue) * t)
    }

    /// 色相（0..<360）、饱和度和亮度（0...1）。
    var hslComponents: (h: Double, s: Double, l: Double) {
        let maxV = max(red, green, blue), minV = min(red, green, blue)
        let l = (maxV + minV) / 2
        let d = maxV - minV
        guard d > 0 else { return (0, 0, l) }
        let s = l > 0.5 ? d / (2 - maxV - minV) : d / (maxV + minV)
        var h: Double
        if maxV == red { h = (green - blue) / d + (green < blue ? 6 : 0) }
        else if maxV == green { h = (blue - red) / d + 2 }
        else { h = (red - green) / d + 4 }
        h *= 60
        return (h, s, l)
    }

    init(hue: Double, saturation: Double, lightness: Double) {
        let h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 360
        let s = min(1, max(0, saturation)), l = min(1, max(0, lightness))
        guard s > 0 else {
            self.init(red: l, green: l, blue: l)
            return
        }
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
        self.init(red: channel(h + 1.0 / 3), green: channel(h), blue: channel(h - 1.0 / 3))
    }
}

public extension WidgetTint {
    /// 专注计时的颜色：面板里选过颜色就用选的；没选过时，设置里给专注计时
    /// 换过颜色（不是默认的靛蓝）就照旧用那个，否则用专注计时自己的绿。
    static func timerPalette(_ choice: Choice, session: PaletteColor) -> Palette? {
        if choice.isChosen { return palette(choice, kind: .timer) }
        guard session != .indigo, let code = ColorCode(hex: session.hex) else {
            return defaultPalette(.timer)
        }
        return Palette(main: code, contrast: defaultPalette(.timer).contrast)
    }
}
