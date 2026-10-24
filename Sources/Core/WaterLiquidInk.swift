import Foundation

/// 喝水液态卡片上的字和 + 按钮用什么颜色，水用什么颜色。
///
/// 原来一律白字加一圈淡黑描边：浅色外观下卡片底是奶白的，水只有 46% 到 62%
/// 的浓度，淡粉、淡紫、浅黄这类水色叠出来接近白，白字只有 2:1 左右，真机上
/// 看不清。这里按“水面上方”和“水里”两块的实际底色分别挑字色，保证每一块
/// 都过 WCAG 正文的 4.5:1：
///
/// - 水面上方：卡片本身（`WidgetTint.lightCard` / `darkCard`），加两道浪之间
///   只有后浪的那一条。
/// - 水里：前浪从水面到底边每一层（前浪浓度从上到下渐淡，叠在后浪上），满了时
///   顶上那一抹白色高光（`fullHighlight`）也算进去。
///
/// 挑法：先试一种字色两块都够（浅色外观先试深字，深色外观先试白字），够了
/// 整张卡一个颜色；不够时水面上方和水里各用各的（卡片按水面把字分成两种颜色
/// 画），水色浅用深字、水色深用白字。深字是水色同色相往黑里压到够 4.5 的那一档，
/// 不用纯黑。水的颜色只在两种字都不够的中间亮度时（比如深色外观下的玫红）
/// 按同色相压暗或调浅一点点，改得越少越好。
///
/// + 按钮是一个实心圆：圆底是水色同色相压到白色加号够 4.5 的那一档，加号是白的，
/// 放在水里、水面上方都一样清楚。
///
/// 卡片底色是估的（玻璃透出桌面，顶上还有一抹主题色光晕），算的时候按 4.6 留一点
/// 余量。达标那一刻水面闪几秒金光没算进去（转瞬即逝）。
public enum WaterLiquidInk {
    /// WCAG AA 正文的最低对比度。
    public static let minimumContrast = 4.5
    /// 实际按这个算，比 4.5 多留一点余量。
    public static let targetContrast = 4.6
    /// 满了时顶上那抹高光最亮处的白色不透明度（和 `LiquidWater` 画的一致）。
    public static let highlightOpacity = 0.22

    static let white = ColorCode(red: 1, green: 1, blue: 1)
    static let black = ColorCode(red: 0, green: 0, blue: 0)

    public struct Look: Equatable, Sendable {
        /// 画水用的颜色：一般就是主题色，只有中间亮度时才按同色相改一点。
        public var water: ColorCode
        /// 水面上方的字。
        public var dry: ColorCode
        /// 水里的字。和 `dry` 一样时整张卡片一个颜色。
        public var wet: ColorCode
        /// + 按钮的实心圆底。
        public var button: ColorCode
        /// + 号（白色）。
        public var buttonInk: ColorCode

        /// 水面上下的字是不是两种颜色。
        public var splits: Bool { dry != wet }
    }

    /// 卡片的底色（估的）：深色外观深灰玻璃，浅色外观浅灰玻璃。
    public static func card(dark: Bool) -> ColorCode {
        dark ? WidgetTint.darkCard : WidgetTint.lightCard
    }

    /// 水面上方字底下可能是什么颜色：卡片本身，和只有后浪的那一条。
    public static func dryBackgrounds(water: ColorCode, dark: Bool,
                                      density: LiquidDensity = LiquidLooks.waterDensity) -> [ColorCode] {
        let card = card(dark: dark)
        return [card, card.mixed(with: water, by: density.back)]
    }

    /// 水里字底下可能是什么颜色：前浪从水面（`top`）到底边（`bottom`）的每一层
    /// 叠在后浪上，每层再算一遍盖了满水高光的样子。
    public static func wetBackgrounds(water: ColorCode, dark: Bool,
                                      density: LiquidDensity = LiquidLooks.waterDensity) -> [ColorCode] {
        let behind = card(dark: dark).mixed(with: water, by: density.back)
        var result: [ColorCode] = []
        for step in 0...10 {
            let u = Double(step) / 10
            let alpha = density.top + (density.bottom - density.top) * u
            let layer = behind.mixed(with: water, by: alpha)
            result.append(layer)
            result.append(layer.mixed(with: white, by: highlightOpacity))
        }
        return result
    }

    /// 字在这些底色上最差的那个对比度。
    public static func worstContrast(_ ink: ColorCode, on backgrounds: [ColorCode]) -> Double {
        backgrounds.map { WidgetTint.contrastRatio(ink, $0) }.min() ?? 21
    }

    /// 和 `hue` 同色相、在这些底色上都够 `targetContrast` 的最浅的深色：
    /// 往黑里压（各分量乘同一个比例，色相不变），压到黑都不够返回 nil。
    public static func deepInk(_ hue: ColorCode, on backgrounds: [ColorCode]) -> ColorCode? {
        func ok(_ f: Double) -> Bool {
            worstContrast(PanelContrast.darkened(hue, by: f), on: backgrounds) >= targetContrast
        }
        if ok(0) { return hue }
        guard ok(1) else { return nil }
        var low = 0.0, high = 1.0
        while high - low > 0.002 {
            let mid = (low + high) / 2
            if ok(mid) { high = mid } else { low = mid }
        }
        return PanelContrast.darkened(hue, by: high)
    }

    /// 这些底色上的字：`light` 时先试白字，否则先试同色相深字；先试的不够再试另一个。
    static func ink(on backgrounds: [ColorCode], hue: ColorCode, preferLight: Bool) -> ColorCode? {
        let whiteOK = worstContrast(white, on: backgrounds) >= targetContrast
        if preferLight, whiteOK { return white }
        if let deep = deepInk(hue, on: backgrounds) { return deep }
        return whiteOK ? white : nil
    }

    /// 水里该用白字还是深字：看哪个在最差的那层水上对比度高（水色浅用深字，深用白字）。
    static func wetPrefersLight(_ backgrounds: [ColorCode]) -> Bool {
        worstContrast(white, on: backgrounds) >= worstContrast(black, on: backgrounds)
    }

    /// 字和按钮的颜色。`tint` 是卡片的主题色（已按外观调过亮度的那个）。
    public static func look(tint: ColorCode, dark: Bool,
                            density: LiquidDensity = LiquidLooks.waterDensity) -> Look {
        var water = tint
        var wetBackgrounds = wetBackgrounds(water: water, dark: dark, density: density)
        var dryBackgrounds = dryBackgrounds(water: water, dark: dark, density: density)

        // 水里的字够不够；两种都不够时把水按同色相一点点压暗（配白字）或调浅（配深字），
        // 取改得少的那个方向。
        if ink(on: wetBackgrounds, hue: tint, preferLight: wetPrefersLight(wetBackgrounds)) == nil {
            var adjusted: ColorCode?
            var step = 0.02
            while adjusted == nil, step <= 1 {
                let darker = PanelContrast.darkened(tint, by: step)
                let lighter = tint.mixed(with: white, by: step)
                let darkerBG = Self.wetBackgrounds(water: darker, dark: dark, density: density)
                let lighterBG = Self.wetBackgrounds(water: lighter, dark: dark, density: density)
                // 深色外观先压暗（水面上方是白字，水里也白字最省事），浅色外观先调浅。
                let tries: [(ColorCode, [ColorCode])] = dark
                    ? [(darker, darkerBG), (lighter, lighterBG)]
                    : [(lighter, lighterBG), (darker, darkerBG)]
                for (candidate, backgrounds) in tries
                where ink(on: backgrounds, hue: candidate, preferLight: wetPrefersLight(backgrounds)) != nil {
                    adjusted = candidate
                    break
                }
                step += 0.02
            }
            water = adjusted ?? PanelContrast.darkened(tint, by: 1)
            wetBackgrounds = Self.wetBackgrounds(water: water, dark: dark, density: density)
            dryBackgrounds = Self.dryBackgrounds(water: water, dark: dark, density: density)
        }

        let dry: ColorCode
        let wet: ColorCode
        if let single = ink(on: dryBackgrounds + wetBackgrounds, hue: water, preferLight: dark) {
            dry = single
            wet = single
        } else {
            dry = ink(on: dryBackgrounds, hue: water, preferLight: dark) ?? (dark ? white : black)
            wet = ink(on: wetBackgrounds, hue: water, preferLight: wetPrefersLight(wetBackgrounds))
                ?? (wetPrefersLight(wetBackgrounds) ? white : black)
        }

        return Look(water: water, dry: dry, wet: wet, button: buttonDisc(water), buttonInk: white)
    }

    /// + 按钮的圆底：水色同色相压到白色加号够 `targetContrast` 的最浅一档。
    public static func buttonDisc(_ water: ColorCode) -> ColorCode {
        func ok(_ f: Double) -> Bool {
            WidgetTint.contrastRatio(white, PanelContrast.darkened(water, by: f)) >= targetContrast
        }
        if ok(0) { return water }
        var low = 0.0, high = 1.0
        while high - low > 0.002 {
            let mid = (low + high) / 2
            if ok(mid) { high = mid } else { low = mid }
        }
        return PanelContrast.darkened(water, by: high)
    }

    /// 颜色是浅的（深字配浅描边，白字配深描边，描边只是辅助）。
    public static func isLight(_ color: ColorCode) -> Bool {
        WidgetTint.luminance(color) > 0.4
    }
}
