import Foundation

/// 颜色主题在卡片以外的地方：展开面板的强调色、卡片和面板顶上那一抹
/// 淡淡的主题色光晕，以及压在主题色上的字用深色还是白色。
///
/// 规则只有一条：没选过颜色（默认）时一切照旧，面板用各自原来的颜色，
/// 卡片上不加光晕；选了颜色才换，换的只是原来表示“这个小组件的颜色”
/// 的那些地方。红涨绿跌、警告橙、错误红、电量红黄绿、日历原色这类有
/// 意思的颜色不在这里，各面板自己保留。
public extension WidgetTint {
    /// 展开面板的强调色。
    enum PanelAccent: Equatable, Sendable {
        /// 默认：面板用自己原来的颜色，什么都不换。
        case own
        /// 跟随系统强调色，由界面用系统的强调色画。
        case system
        /// 选了预设或自定义颜色：已经调到在深色面板卡片上看得清。
        case color(ColorCode)

        /// 面板要不要换颜色。
        public var overrides: Bool { self != .own }
    }

    /// 面板的强调色：默认回落到 `.own`；不能选颜色的小组件（照片、壁纸、
    /// 便签……）即使配置里写了颜色也回落。面板卡片（`DetailCard`）总是深色，
    /// 所以按深色外观调可读性。
    static func panelAccent(_ choice: Choice, kind: WidgetKind) -> PanelAccent {
        guard offersColor(kind), choice.isChosen else { return .own }
        guard let palette = palette(choice, kind: kind) else { return .system }
        return .color(readable(palette.main, dark: true))
    }

    // MARK: 光晕

    /// 主题色光晕和细描边最多这么不透明。保持深色玻璃的样子，不发光。
    static let maxGlowOpacity = 0.15

    /// 光晕从顶边往下铺到卡片高度的多少，再往下就完全透明。
    static let glowReach = 0.6

    /// 卡片和面板顶上光晕的不透明度。默认是 0（不画）；浅色外观的卡片
    /// 本身亮，颜色更显，给得少一点。`strength` 是外观 ▸ 颜色里的色调强度，
    /// 不传就是「中」，也就是加这项之前的效果（见 `glowLevels`）。
    static func glowOpacity(_ choice: Choice, kind: WidgetKind, dark: Bool,
                            strength: Strength = .standard) -> Double {
        glowLevels(choice, kind: kind, strength: strength, dark: dark).glow
    }

    /// 卡片上的光晕：选了渐变背景时背景本身就是主题色，不再叠一层。
    static func cardGlowOpacity(_ choice: Choice, kind: WidgetKind,
                                background: Background, dark: Bool,
                                strength: Strength = .standard) -> Double {
        background == .gradient ? 0 : glowOpacity(choice, kind: kind, dark: dark, strength: strength)
    }

    /// 卡片一圈细描边的不透明度，和光晕一样有上限，默认不画。
    static func edgeOpacity(_ choice: Choice, kind: WidgetKind, dark: Bool,
                            strength: Strength = .standard) -> Double {
        glowLevels(choice, kind: kind, strength: strength, dark: dark).edge
    }

    // MARK: 字色

    /// 主题色按钮上的字用深色（true）还是白色。先看感知亮度，和空状态
    /// 按钮同一条线（`PandaEmpty.brightness`、`darkLabelThreshold`）；
    /// 亮度没过线时优先白字，但白字对比度不到 4.5（`minimumTextContrast`，
    /// 蓝、紫、红、玫红、薄荷绿、橙这类）就看黑白哪个对比度高用哪个。
    /// 黑白两者中较高的那个对任何底色都至少有 4.58，所以「自动」总能到 4.5。
    static func labelIsDark(on fill: ColorCode) -> Bool {
        if PandaEmpty.brightness(fill) > PandaEmpty.darkLabelThreshold { return true }
        let white = ColorCode(red: 1, green: 1, blue: 1)
        guard contrastRatio(fill, white) < minimumTextContrast else { return false }
        return inkIsDark(on: fill)
    }
}
