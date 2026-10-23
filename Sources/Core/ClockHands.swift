import Foundation

/// 小表盘三根指针的角度和秒针的尺寸。时钟「标准」样式卡片左侧的小表盘、
/// 世界时钟卡片和时钟面板城市行共用一个表盘（`AnalogClockFace`），
/// 只有时钟标准卡片画秒针，见 `ClockReadout.secondHand`；时钟面板的大表盘
/// （`PanelDial`）秒针颜色也从这里取，和卡片一致。
///
/// 角度从 12 点起顺时针，单位是度，0..<360。
public enum ClockHands {
    /// 时、分、秒三根指针的角度。时针跟着分钟走，分针跟着整分走（和原来
    /// 一样不随秒爬），秒针每秒跳一格。
    public static func angles(_ date: Date, zone: TimeZone) -> (hour: Double, minute: Double, second: Double) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        let second = Double(parts.second ?? 0)
        let minute = Double(parts.minute ?? 0)
        let hour = Double((parts.hour ?? 0) % 12) + minute / 60
        return (hour / 12 * 360, minute / 60 * 360, second / 60 * 360)
    }

    /// 秒针长度占表盘直径的比例：比分针（0.37）稍长。
    public static let secondLength = 0.40
    /// 秒针粗细（pt）。原来 0.9pt，扩展栏缩小后在淡色徽章上几乎看不见，
    /// 加粗到 1.2pt，仍比分针（1.6）细。
    public static let secondWidth = 1.2
    /// 中心小圆点直径占表盘直径的比例，不小于 `minimumDot`（26pt 表盘约 3.6pt）。
    public static let dotRatio = 0.14
    public static let minimumDot = 2.6

    public static func dotDiameter(_ diameter: Double) -> Double {
        max(minimumDot, diameter * dotRatio)
    }

    // MARK: 开关

    /// 标准样式小表盘秒针的开关，默认开。和数字样式的「显示秒」（seconds）
    /// 分开：老卡片配置里常见 seconds=false（以前在标准样式下它什么都不管），
    /// 秒针加上以后被它悄悄藏掉，所以标准样式改读这个新键。
    public static let secondHandKey = "secondHand"
    /// 数字样式的「显示秒」。
    public static let secondsKey = "seconds"

    /// 标准卡片小表盘画不画秒针：只看 `secondHandKey`，没写过算开，
    /// 老配置里的 seconds=false 不再影响秒针。
    public static func showsSecondHand(_ config: WidgetConfig) -> Bool {
        config.bool(secondHandKey, default: true)
    }

    /// 设置里两个秒开关各在哪个样式下列：标准样式只列「表盘秒针」，
    /// 其他样式只列「显示秒」。不是这两个键返回 nil，交给样式注册表判断。
    public static func applies(_ key: String, isStandard: Bool) -> Bool? {
        switch key {
        case secondHandKey: isStandard
        case secondsKey: !isStandard
        default: nil
        }
    }

    // MARK: 颜色

    /// 秒针颜色从哪来。卡片小表盘和时钟面板大表盘（`PanelDial`）共用这一个来源，
    /// 两边色相一致，只按各自底色做可读性微调。
    public enum SecondHandSource: Equatable, Sendable {
        /// 跟随系统强调色，由界面取系统的强调色。
        case system
        /// 选了预设或自定义颜色是它的主色；没选（默认）是 `defaultColor`。
        case color(ColorCode)
    }

    /// 没选颜色时卡片和面板秒针共用的默认色：时钟自己的琥珀色（#FFB340），
    /// 也就是卡片徽章那层淡色的颜色。面板原来写的是系统橙，统一成它。
    public static let defaultColor: ColorCode = WidgetTint.defaultPalette(.clock).main

    /// 秒针的颜色来源，和面板强调色（`WidgetTint.panelAccent`）同一个判定：
    /// 默认用 `defaultColor`；跟随系统是 `.system`；选了颜色用那个颜色的主色。
    /// 没解锁 Pro 时自定义颜色退回默认，和卡片、面板一样。
    public static func source(_ config: WidgetConfig, unlocked: Bool) -> SecondHandSource {
        let choice = WidgetTint.shownChoice(config, unlocked: unlocked)
        switch WidgetTint.panelAccent(choice, kind: .clock) {
        case .own: return .color(defaultColor)
        case .system: return .system
        case .color: return .color(WidgetTint.palette(choice, kind: .clock)?.main ?? defaultColor)
        }
    }

    /// 细秒针要的对比度：比图形的 3:1 高一点，1.2pt 的线抗锯齿后会显得更淡。
    public static let handContrast = 3.5

    /// 卡片徽章的底：卡片底上铺一层主题色，深色 18%、浅色 16%（同 `TileBadge`）。
    /// 秒针和徽章是同一个颜色，所以要按这层底而不是卡片底算对比度。
    public static func badgeBackground(tint: ColorCode, dark: Bool) -> ColorCode {
        let card = dark ? WidgetTint.darkCard : WidgetTint.lightCard
        return card.mixed(with: WidgetTint.readable(tint, dark: dark), by: dark ? 0.18 : 0.16)
    }

    /// 把颜色调到在 `background` 上够 `minimum`：深色往白里调，浅色往黑里调，
    /// 只改明暗不改色相。本来就够的原样返回。
    public static func readable(_ color: ColorCode, dark: Bool, on background: ColorCode,
                                minimum: Double = handContrast) -> ColorCode {
        let target = dark ? ColorCode(red: 1, green: 1, blue: 1) : ColorCode(red: 0, green: 0, blue: 0)
        var amount = 0.0
        var result = color
        while WidgetTint.contrastRatio(result, background) < minimum, amount < 1 {
            amount = min(1, amount + 0.05)
            result = color.mixed(with: target, by: amount)
        }
        return result
    }

    /// 卡片小表盘的秒针色：在同色淡徽章上看得清。
    public static func cardColor(_ base: ColorCode, dark: Bool) -> ColorCode {
        readable(base, dark: dark, on: badgeBackground(tint: base, dark: dark))
    }

    /// 面板大表盘的秒针色：面板玻璃上看得清（按卡片底近似）。
    public static func panelColor(_ base: ColorCode, dark: Bool) -> ColorCode {
        readable(base, dark: dark, on: dark ? WidgetTint.darkCard : WidgetTint.lightCard)
    }
}
