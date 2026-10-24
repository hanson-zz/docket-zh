import XCTest

/// 喝水液态卡片上的字色、+ 按钮和副标题：任何水位、任何颜色主题、浅色深色下
/// 字都过 4.5:1，浅色水用同色相深字、深色水用白字。
final class WaterLiquidInkTests: XCTestCase {
    /// 颜色面板里每种预设、喝水默认的蓝、系统强调色常见的几种，按外观调过亮度
    /// （和卡片画的一样，`WidgetTintStyle.main`）。
    private func tints(dark: Bool) -> [(String, ColorCode)] {
        var result = WidgetTint.Preset.allCases.map { ($0.rawValue, WidgetTint.readable($0.palette.main, dark: dark)) }
        result.append(("water", WidgetTint.readable(WidgetTint.defaultPalette(.water).main, dark: dark)))
        for hex in ["#0088FF", "#007AFF", "#8E8E93", "#FFB3C7", "#C7ADEE", "#1D3B8A", "#FFFFFF", "#000000"] {
            result.append((hex, WidgetTint.readable(ColorCode(hex: hex)!, dark: dark)))
        }
        return result
    }

    private func assertReadable(_ look: WaterLiquidInk.Look, dark: Bool, _ name: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        let dry = WaterLiquidInk.dryBackgrounds(water: look.water, dark: dark)
        let wet = WaterLiquidInk.wetBackgrounds(water: look.water, dark: dark)
        XCTAssertGreaterThanOrEqual(WaterLiquidInk.worstContrast(look.dry, on: dry), 4.5,
                                    "\(name) \(dark ? "深色" : "浅色") 水面上方", file: file, line: line)
        XCTAssertGreaterThanOrEqual(WaterLiquidInk.worstContrast(look.wet, on: wet), 4.5,
                                    "\(name) \(dark ? "深色" : "浅色") 水里", file: file, line: line)
        // 整张卡一个颜色时，水上水下都要够。
        if !look.splits {
            XCTAssertGreaterThanOrEqual(WaterLiquidInk.worstContrast(look.dry, on: dry + wet), 4.5,
                                        "\(name) 单色", file: file, line: line)
        }
        XCTAssertGreaterThanOrEqual(WidgetTint.contrastRatio(look.buttonInk, look.button), 4.5,
                                    "\(name) + 按钮", file: file, line: line)
    }

    func testEveryThemeIsReadableInBothAppearances() {
        for dark in [false, true] {
            for (name, tint) in tints(dark: dark) {
                assertReadable(WaterLiquidInk.look(tint: tint, dark: dark), dark: dark, name)
            }
        }
    }

    /// 自定义颜色：RGB 每个分量五档，两种外观都过。
    func testAnyCustomColorIsReadable() {
        let steps = [0.0, 0.25, 0.5, 0.75, 1.0]
        for r in steps {
            for g in steps {
                for b in steps {
                    let raw = ColorCode(red: r, green: g, blue: b)
                    for dark in [false, true] {
                        let tint = WidgetTint.readable(raw, dark: dark)
                        assertReadable(WaterLiquidInk.look(tint: tint, dark: dark), dark: dark, raw.hex)
                    }
                }
            }
        }
    }

    /// 浅色外观：整张卡一个深字；字是水色同色相的深色，不是白字。
    ///
    /// “水色不改”只对颜色面板的预设和喝水默认的蓝成立：#1D3B8A 这类自定义深色
    /// 在浅色外观下两种字都不够，水会按同色相调浅一点（见 `WaterLiquidInk.look`），
    /// 这种情况的可读性由 `testEveryThemeIsReadableInBothAppearances` 保证。
    func testLightAppearanceUsesOneDeepInkOfTheSameHue() {
        let presets = Set(WidgetTint.Preset.allCases.map(\.rawValue) + ["water"])
        for (name, tint) in tints(dark: false) where tint.hslComponents.s > 0.15 {
            let look = WaterLiquidInk.look(tint: tint, dark: false)
            XCTAssertFalse(look.splits, name)
            if presets.contains(name) {
                XCTAssertEqual(look.water, tint, "\(name) 水色不改")
            }
            XCTAssertLessThan(WidgetTint.luminance(look.dry), 0.2, name)
            let hue = abs(look.dry.hslComponents.h - tint.hslComponents.h)
            XCTAssertLessThan(min(hue, 360 - hue), 3, "\(name) 同色相")
        }
    }

    /// 用户截图那种淡粉 / 藕紫的满水：原来白字只有 2:1 左右，现在是深字。
    func testPastelWaterGetsDarkInk() {
        for hex in ["#FFB3C7", "#C7ADEE", "#B9A6FF"] {
            let tint = WidgetTint.readable(ColorCode(hex: hex)!, dark: false)
            let look = WaterLiquidInk.look(tint: tint, dark: false)
            XCTAssertFalse(WaterLiquidInk.isLight(look.wet), hex)
            let wet = WaterLiquidInk.wetBackgrounds(water: look.water, dark: false)
            XCTAssertLessThan(WaterLiquidInk.worstContrast(ColorCode(red: 1, green: 1, blue: 1), on: wet), 4.5,
                              "\(hex) 白字本来就不够")
        }
    }

    /// 深色外观：水面上方是白字；深色的水里也是白字，浅色的水里是深字。
    func testDarkAppearanceFollowsTheWater() {
        let deep = WaterLiquidInk.look(tint: WidgetTint.readable(ColorCode(hex: "#1D3B8A")!, dark: true), dark: true)
        XCTAssertTrue(WaterLiquidInk.isLight(deep.dry))
        XCTAssertTrue(WaterLiquidInk.isLight(deep.wet))

        let yellow = WidgetTint.readable(WidgetTint.Preset.yellow.palette.main, dark: true)
        let bright = WaterLiquidInk.look(tint: yellow, dark: true)
        XCTAssertTrue(WaterLiquidInk.isLight(bright.dry))
        XCTAssertFalse(WaterLiquidInk.isLight(bright.wet))
        XCTAssertTrue(bright.splits)
        XCTAssertEqual(bright.water, yellow, "够的时候水色不改")
    }

    /// 两种字都不够的中间亮度（深色外观的玫红、蓝）只改一点水色，色相不变。
    func testWaterIsOnlyNudgedAndKeepsItsHue() {
        for dark in [false, true] {
            for (name, tint) in tints(dark: dark) where tint.hslComponents.s > 0.15 {
                let look = WaterLiquidInk.look(tint: tint, dark: dark)
                let a = look.water.hslComponents.h, b = tint.hslComponents.h
                XCTAssertLessThan(min(abs(a - b), 360 - abs(a - b)), 4, "\(name) 色相")
                let moved = abs(look.water.red - tint.red) + abs(look.water.green - tint.green)
                    + abs(look.water.blue - tint.blue)
                XCTAssertLessThan(moved, 0.9, "\(name) 水色改得太多")
            }
        }
    }

    func testDeepInkIsTheLightestThatPasses() {
        let pink = ColorCode(hex: "#FF6FA8")!
        let card = [WaterLiquidInk.card(dark: false)]
        let ink = WaterLiquidInk.deepInk(pink, on: card)!
        XCTAssertGreaterThanOrEqual(WaterLiquidInk.worstContrast(ink, on: card), WaterLiquidInk.targetContrast)
        XCTAssertLessThan(WaterLiquidInk.worstContrast(ink, on: card), WaterLiquidInk.targetContrast + 0.2)
        XCTAssertNil(WaterLiquidInk.deepInk(pink, on: [ColorCode(red: 0, green: 0, blue: 0)]))
    }

    func testButtonDiscKeepsWhitePlusReadable() {
        for (name, tint) in tints(dark: false) + tints(dark: true) {
            let disc = WaterLiquidInk.buttonDisc(tint)
            XCTAssertGreaterThanOrEqual(WidgetTint.contrastRatio(ColorCode(red: 1, green: 1, blue: 1), disc), 4.5, name)
        }
    }

    // MARK: 版式和副标题

    func testTextKeepsTwelvePointsFromTheEdge() {
        XCTAssertGreaterThanOrEqual(LiquidLooks.liquidTextInset, 12)
        XCTAssertGreaterThan(LiquidLooks.liquidTextInset, DockMetrics.cardInset)
        XCTAssertGreaterThanOrEqual(LiquidLooks.waterTextInset, 12)
        XCTAssertGreaterThan(LiquidLooks.waterTextInset, DockMetrics.cardInset)
    }

    func testCaptionShowsHowFarOverTheGoal() {
        XCTAssertEqual(LiquidLooks.waterCaption(total: 2300, goal: 1600, ounces: false), "今天达标啦 · 144%")
        XCTAssertEqual(LiquidLooks.waterCaption(total: 1600, goal: 1600, ounces: false), "今天达标啦")
        // 只多一点点，四舍五入还是 100%，不写。
        XCTAssertEqual(LiquidLooks.waterCaption(total: 1604, goal: 1600, ounces: false), "今天达标啦")
        XCTAssertEqual(LiquidLooks.waterCaption(total: 3200, goal: 1600, ounces: false), "今天达标啦 · 200%")
        XCTAssertEqual(LiquidLooks.waterCaption(total: 800, goal: 1600, ounces: false), "毫升 · 50%")
        XCTAssertEqual(LiquidLooks.waterCaption(total: 800, goal: 1600, ounces: true), "盎司 · 50%")
        XCTAssertEqual(LiquidLooks.waterCaption(total: 0, goal: 0, ounces: false), "毫升 · 0%")
    }
}
