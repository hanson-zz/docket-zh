import Foundation

/// 外观 ▸ 颜色里的两项细调：色调强度和文字颜色。
///
/// 只在选了非默认颜色时生效：默认颜色时卡片和面板不画光晕、主题色按钮
/// 也不换，这两项读出来什么都不改。
///
/// 和颜色、背景一样存在小组件自己的配置里，两个键都不在目录默认值里：
/// 旧卡片没有这两个键，读出来是「中」和「自动」，也就是加这两项之前的样子。
///
/// - `tintStrength`：`soft`、`medium`（默认，写回时存空）、`strong`。
/// - `tintInk`：`auto`（默认，写回时存空）、`white`、`warmWhite`、`theme`。
///
/// 涨跌红绿、警告、电量、天气、照片这些有意思的颜色不读这两项。
public extension WidgetTint {
    static let strengthKey = "tintStrength"
    static let inkKey = "tintInk"

    // MARK: 色调强度

    /// 卡片和面板顶上那一抹主题色光晕、一圈细描边有多显眼。
    enum Strength: String, CaseIterable, Sendable, Identifiable {
        case soft, medium, strong

        public var id: String { rawValue }

        /// 没设置、认不出时用的那一档，等于加这项之前的效果。
        public static let standard: Strength = .medium

        public init(raw: String) {
            self = Strength(rawValue: raw.trimmingCharacters(in: .whitespaces)) ?? .standard
        }

        /// 写回配置的值：默认写空串，读回来一样是默认。
        public var raw: String { self == .standard ? "" : rawValue }

        public var title: String {
            switch self {
            case .soft: tr("淡")
            case .medium: tr("中")
            case .strong: tr("浓")
            }
        }
    }

    static func strength(_ config: WidgetConfig) -> Strength {
        Strength(raw: config.string(strengthKey))
    }

    /// 一档强度落到具体数值：光晕顶边的不透明度、细描边的不透明度，以及
    /// 光晕往下铺到卡片高度的多少。不透明度都不超过 `maxGlowOpacity`（15%）。
    struct GlowLevels: Equatable, Sendable {
        public var glow: Double
        public var edge: Double
        public var reach: Double

        public init(glow: Double, edge: Double, reach: Double) {
            let cap = WidgetTint.maxGlowOpacity
            self.glow = min(cap, max(0, glow))
            self.edge = min(cap, max(0, edge))
            self.reach = min(0.95, max(0.05, reach))
        }

        public static let off = GlowLevels(glow: 0, edge: 0, reach: WidgetTint.glowReach)
    }

    /// 强度到透明度的映射。「中」就是原来的数值（深色 15% / 14%，浅色
    /// 12% / 12%，铺到 60%）；「淡」大约一半；「浓」深色外观的光晕已经
    /// 顶到 15% 的上限，所以靠铺得更深和描边多一点显得浓，不再加亮。
    /// 浅色外观的卡片本身亮，颜色更显，同一档给得少一点。
    static func glowLevels(_ strength: Strength, dark: Bool) -> GlowLevels {
        switch (strength, dark) {
        case (.soft, true): GlowLevels(glow: 0.08, edge: 0.07, reach: 0.45)
        case (.soft, false): GlowLevels(glow: 0.06, edge: 0.06, reach: 0.45)
        case (.medium, true): GlowLevels(glow: 0.15, edge: 0.14, reach: glowReach)
        case (.medium, false): GlowLevels(glow: 0.12, edge: 0.12, reach: glowReach)
        case (.strong, true): GlowLevels(glow: 0.15, edge: 0.15, reach: 0.8)
        case (.strong, false): GlowLevels(glow: 0.14, edge: 0.15, reach: 0.8)
        }
    }

    /// 这张卡片此刻的光晕：默认颜色、不能选颜色的小组件都是 `off`。
    static func glowLevels(_ choice: Choice, kind: WidgetKind, strength: Strength,
                           dark: Bool) -> GlowLevels {
        guard offersColor(kind), choice.isChosen else { return .off }
        return glowLevels(strength, dark: dark)
    }

    // MARK: 文字颜色

    /// 压在主题色上的字（主按钮、选中的分段）用什么颜色。
    enum TextInk: String, CaseIterable, Sendable, Identifiable {
        /// 按亮度和对比度选深色或白色，对比度总能到 4.5。
        case auto
        case white
        case warmWhite
        /// 同色系的字：底亮时是压暗的主题色，底暗时是调浅的主题色。
        case theme

        public var id: String { rawValue }

        public static let standard: TextInk = .auto

        public init(raw: String) {
            self = TextInk(rawValue: raw.trimmingCharacters(in: .whitespaces)) ?? .standard
        }

        public var raw: String { self == .standard ? "" : rawValue }

        public var title: String {
            switch self {
            case .auto: tr("自动")
            case .white: tr("白")
            case .warmWhite: tr("暖白")
            case .theme: tr("主题色")
            }
        }
    }

    static func textInk(_ config: WidgetConfig) -> TextInk {
        TextInk(raw: config.string(inkKey))
    }

    /// 文字和底色的最低对比度（WCAG 正文 AA）。手选的字色不到这个数就退回「自动」。
    static let minimumTextContrast = 4.5

    static let inkWhite = ColorCode(red: 1, green: 1, blue: 1)
    static let inkBlack = ColorCode(red: 0, green: 0, blue: 0)
    /// 暖白：带一点米色的白，不刺眼。
    static let inkWarmWhite = ColorCode(red: 1, green: 0.957, blue: 0.878)

    /// 「自动」：按亮度选深色或白色（`labelIsDark`），白字不到 4.5 就看黑白谁更清楚，
    /// 所以「自动」本身总能到 4.5，手选退回它时一定看得清。
    static func autoInk(on fill: ColorCode) -> ColorCode {
        labelIsDark(on: fill) ? inkBlack : inkWhite
    }

    /// 选的字色本身（还没检查对比度）。
    static func requestedInk(_ ink: TextInk, accent: ColorCode, on fill: ColorCode) -> ColorCode {
        switch ink {
        case .auto: autoInk(on: fill)
        case .white: inkWhite
        case .warmWhite: inkWarmWhite
        case .theme: themeInk(accent: accent, on: fill)
        }
    }

    /// 同色系的字：底亮时往黑里压（从 72% 起），底暗时往白里调（从 80% 起），
    /// 对比度不到 4.5 就再多调一点，最多 92% / 95%，仍保留主题色的色相。
    /// 到头还不够，`resolveInk` 会退回「自动」。
    static func themeInk(accent: ColorCode, on fill: ColorCode) -> ColorCode {
        let dark = labelIsDark(on: fill)
        let target = dark ? inkBlack : inkWhite
        var amount = dark ? 0.72 : 0.8
        let limit = dark ? 0.92 : 0.95
        var result = accent.mixed(with: target, by: amount)
        while contrastRatio(result, fill) < minimumTextContrast, amount < limit {
            amount = min(limit, amount + 0.04)
            result = accent.mixed(with: target, by: amount)
        }
        return result
    }

    /// 解出来的字色，和有没有退回「自动」。
    struct InkResolution: Equatable, Sendable {
        public var color: ColorCode
        /// 选的字色和底色对比度不到 `minimumTextContrast`，改用了「自动」的结果。
        public var fellBack: Bool

        public init(color: ColorCode, fellBack: Bool) {
            self.color = color
            self.fellBack = fellBack
        }
    }

    /// 压在 `fill` 上的字色：选「自动」就是 `autoInk`；选别的，和底色的
    /// 对比度到了 4.5 就用选的，不到就退回「自动」的结果。
    static func resolveInk(_ ink: TextInk, accent: ColorCode, on fill: ColorCode) -> InkResolution {
        let automatic = autoInk(on: fill)
        guard ink != .auto else { return InkResolution(color: automatic, fellBack: false) }
        let wanted = requestedInk(ink, accent: accent, on: fill)
        if contrastRatio(wanted, fill) >= minimumTextContrast {
            return InkResolution(color: wanted, fellBack: false)
        }
        return InkResolution(color: automatic, fellBack: true)
    }
}
