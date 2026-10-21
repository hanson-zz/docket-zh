import XCTest

/// 外观 ▸ 颜色里的色调强度和文字颜色：强度到透明度的映射、默认值和旧数据、
/// 手选字色的对比度检查和退回「自动」。
final class WidgetTintTuningTests: XCTestCase {

    private let white = ColorCode(red: 1, green: 1, blue: 1)
    private let black = ColorCode(red: 0, green: 0, blue: 0)

    // MARK: 存储

    func testOldConfigsReadAsDefaults() {
        let old = WidgetConfig([WidgetTint.key: .string("blue")])
        XCTAssertEqual(WidgetTint.strength(old), .strong)
        XCTAssertEqual(WidgetTint.textInk(old), .auto)
        XCTAssertEqual(WidgetTint.strength(WidgetConfig()), WidgetTint.Strength.standard)
        XCTAssertEqual(WidgetTint.textInk(WidgetConfig()), WidgetTint.TextInk.standard)
    }

    func testUnknownValuesFallBackToDefaults() {
        let config = WidgetConfig([WidgetTint.strengthKey: .string("extra"),
                                   WidgetTint.inkKey: .string("neon")])
        XCTAssertEqual(WidgetTint.strength(config), .strong)
        XCTAssertEqual(WidgetTint.textInk(config), .auto)
    }

    func testRetiredLevelsMergeIntoTheTwoLeft() {
        // 10-21 精简成两档：旧的「中」读成「浓」，旧的白、暖白读成「自动」。
        XCTAssertEqual(WidgetTint.strength(WidgetConfig([WidgetTint.strengthKey: .string("medium")])), .strong)
        XCTAssertEqual(WidgetTint.strength(WidgetConfig([WidgetTint.strengthKey: .string("strong")])), .strong)
        XCTAssertEqual(WidgetTint.strength(WidgetConfig([WidgetTint.strengthKey: .string("soft")])), .soft)
        XCTAssertEqual(WidgetTint.textInk(WidgetConfig([WidgetTint.inkKey: .string("white")])), .auto)
        XCTAssertEqual(WidgetTint.textInk(WidgetConfig([WidgetTint.inkKey: .string("warmWhite")])), .auto)
        XCTAssertEqual(WidgetTint.textInk(WidgetConfig([WidgetTint.inkKey: .string("theme")])), .theme)
        XCTAssertEqual(WidgetTint.Strength.allCases.count, 2)
        XCTAssertEqual(WidgetTint.TextInk.allCases.count, 2)
    }

    func testRoundTripThroughConfig() {
        for strength in WidgetTint.Strength.allCases {
            var config = WidgetConfig()
            config.set(WidgetTint.strengthKey, strength.raw.isEmpty ? nil : .string(strength.raw))
            XCTAssertEqual(WidgetTint.strength(config), strength)
        }
        for ink in WidgetTint.TextInk.allCases {
            var config = WidgetConfig()
            config.set(WidgetTint.inkKey, ink.raw.isEmpty ? nil : .string(ink.raw))
            XCTAssertEqual(WidgetTint.textInk(config), ink)
        }
        // 默认值写回时是空串（删掉键），不在旧卡片里多留一个键。
        XCTAssertEqual(WidgetTint.Strength.strong.raw, "")
        XCTAssertEqual(WidgetTint.TextInk.auto.raw, "")
    }

    // MARK: 强度

    func testStrongMatchesThePreviousLook() {
        let darkMedium = WidgetTint.glowLevels(.strong, dark: true)
        XCTAssertEqual(darkMedium.glow, 0.15, accuracy: 1e-9)
        XCTAssertEqual(darkMedium.edge, 0.14, accuracy: 1e-9)
        XCTAssertEqual(darkMedium.reach, WidgetTint.glowReach, accuracy: 1e-9)
        let lightMedium = WidgetTint.glowLevels(.strong, dark: false)
        XCTAssertEqual(lightMedium.glow, 0.12, accuracy: 1e-9)
        XCTAssertEqual(lightMedium.edge, 0.12, accuracy: 1e-9)
        // 不传强度的老接口就是「浓」。
        XCTAssertEqual(WidgetTint.glowOpacity(.preset(.blue), kind: .countdown, dark: true),
                       WidgetTint.glowOpacity(.preset(.blue), kind: .countdown, dark: true, strength: .strong))
    }

    func testStrengthIsOrderedAndCapped() {
        for dark in [true, false] {
            let soft = WidgetTint.glowLevels(.soft, dark: dark)
            let strong = WidgetTint.glowLevels(.strong, dark: dark)
            // 两档拉开：淡的光晕不到浓的一半，铺得也更浅。
            XCTAssertLessThanOrEqual(soft.glow * 2, strong.glow + 1e-9)
            XCTAssertLessThan(soft.edge, strong.edge)
            XCTAssertLessThan(soft.reach, strong.reach)
            for level in [soft, strong] {
                XCTAssertLessThanOrEqual(level.glow, 0.15)
                XCTAssertLessThanOrEqual(level.edge, 0.15)
                XCTAssertGreaterThan(level.glow, 0)
                XCTAssertLessThan(level.reach, 1)
            }
        }
        // 构造时也会夹住，传多少都不超过上限。
        XCTAssertEqual(WidgetTint.GlowLevels(glow: 0.9, edge: 2, reach: 3).glow, WidgetTint.maxGlowOpacity)
    }

    func testStrengthDoesNothingWithTheDefaultColour() {
        for strength in WidgetTint.Strength.allCases {
            for dark in [true, false] {
                XCTAssertEqual(WidgetTint.glowLevels(.kindDefault, kind: .countdown,
                                                     strength: strength, dark: dark), .off)
                XCTAssertEqual(WidgetTint.cardGlowOpacity(.kindDefault, kind: .countdown, background: .plain,
                                                          dark: dark, strength: strength), 0)
                XCTAssertEqual(WidgetTint.edgeOpacity(.kindDefault, kind: .countdown,
                                                      dark: dark, strength: strength), 0)
            }
            // 不能选颜色的小组件即使配置里留着颜色也不画。
            XCTAssertEqual(WidgetTint.glowLevels(.preset(.blue), kind: .photos,
                                                 strength: strength, dark: true), .off)
            // 渐变背景照旧不叠光晕。
            XCTAssertEqual(WidgetTint.cardGlowOpacity(.preset(.blue), kind: .countdown, background: .gradient,
                                                      dark: true, strength: strength), 0)
        }
    }

    // MARK: 文字颜色

    func testAutoIsThePreviousInk() {
        for preset in WidgetTint.Preset.allCases {
            let fill = WidgetTint.readable(preset.palette.main, dark: true)
            let resolved = WidgetTint.resolveInk(.auto, accent: fill, on: fill)
            XCTAssertEqual(resolved.color, WidgetTint.labelIsDark(on: fill) ? black : white, preset.rawValue)
            XCTAssertFalse(resolved.fellBack)
        }
    }

    func testChosenInkIsKeptOrFallsBack() {
        let inks: [WidgetTint.TextInk] = [.theme]
        let fills = WidgetTint.Preset.allCases.map { WidgetTint.readable($0.palette.main, dark: true) }
            + [ColorCode(hex: "#101030")!, ColorCode(hex: "#FFFFFF")!, ColorCode(hex: "#7F7F7F")!]
        for fill in fills {
            for ink in inks {
                let wanted = WidgetTint.requestedInk(ink, accent: fill, on: fill)
                let resolved = WidgetTint.resolveInk(ink, accent: fill, on: fill)
                if WidgetTint.contrastRatio(wanted, fill) >= WidgetTint.minimumTextContrast {
                    XCTAssertEqual(resolved.color, wanted, "\(ink.rawValue) on \(fill.hex)")
                    XCTAssertFalse(resolved.fellBack)
                } else {
                    XCTAssertEqual(resolved.color, WidgetTint.autoInk(on: fill), "\(ink.rawValue) on \(fill.hex)")
                    XCTAssertTrue(resolved.fellBack)
                }
                // 选了的字色要么够 4.5，要么就是「自动」的结果。
                XCTAssertTrue(resolved.fellBack
                              || WidgetTint.contrastRatio(resolved.color, fill) >= WidgetTint.minimumTextContrast)
            }
        }
    }

    func testAutoInkAlwaysReachesTextContrast() {
        // 「自动」本身到 4.5，任何底色都是（黑白里高的那个至少 4.58）。
        var fills = WidgetTint.Preset.allCases.flatMap { preset in
            [ColorCode(hex: preset.hex)!,
             WidgetTint.readable(preset.palette.main, dark: true),
             WidgetTint.readable(preset.palette.main, dark: false)]
        }
        for step in 0...20 {
            let v = Double(step) / 20
            fills += [ColorCode(red: v, green: v, blue: v), ColorCode(red: v, green: 0.3, blue: 1 - v)]
        }
        for fill in fills {
            let resolved = WidgetTint.resolveInk(.auto, accent: fill, on: fill)
            XCTAssertGreaterThanOrEqual(WidgetTint.contrastRatio(resolved.color, fill),
                                        WidgetTint.minimumTextContrast, fill.hex)
        }
    }

    func testChosenInkOnBlueNoLongerLooksIgnored() {
        // 蓝底以前「自动」是白字 3.89，手选什么都退回白字，看起来没反应。
        let blue = ColorCode(hex: WidgetTint.Preset.blue.hex)!
        XCTAssertEqual(WidgetTint.autoInk(on: blue), black, "蓝底自动换深色字")
        let theme = WidgetTint.resolveInk(.theme, accent: blue, on: blue)
        XCTAssertFalse(theme.fellBack, "蓝底压暗的蓝字够清楚")
        XCTAssertNotEqual(theme.color, black)
    }

    func testThemeInkStaysInTheSameHue() {
        let yellow = ColorCode(hex: WidgetTint.Preset.yellow.hex)!
        let resolved = WidgetTint.resolveInk(.theme, accent: yellow, on: yellow)
        XCTAssertFalse(resolved.fellBack, "黄底压暗的黄字够清楚")
        XCTAssertNotEqual(resolved.color, black)
        XCTAssertEqual(resolved.color.hslComponents.h, yellow.hslComponents.h, accuracy: 2)
        XCTAssertGreaterThanOrEqual(WidgetTint.contrastRatio(resolved.color, yellow), 4.5)
    }
}
