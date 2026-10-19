import XCTest

/// 电池跟随「外观 ▸ 颜色」：默认照旧红黄绿，选了颜色用主题色，低电量仍报红。
final class BatteryThemeTests: XCTestCase {
    private let blue = ColorCode(hex: "#2F7BFF")!
    private let accent = ColorCode(hex: "#FF6FA8")!

    // MARK: 主题色

    func testDefaultChoiceHasNoTheme() {
        XCTAssertNil(BatteryTheme.color(.kindDefault, systemAccent: accent, dark: true))
        XCTAssertNil(BatteryTheme.color(.kindDefault, systemAccent: accent, dark: false))
    }

    func testPresetCustomAndSystemGiveReadableTheme() {
        let preset = BatteryTheme.color(.preset(.blue), systemAccent: nil, dark: true)
        XCTAssertEqual(preset, WidgetTint.readable(WidgetTint.Preset.blue.palette.main, dark: true))
        let custom = BatteryTheme.color(.custom(blue), systemAccent: nil, dark: false)
        XCTAssertEqual(custom, WidgetTint.readable(blue, dark: false))
        let system = BatteryTheme.color(.system, systemAccent: accent, dark: true)
        XCTAssertEqual(system, WidgetTint.readable(accent, dark: true))
        XCTAssertNil(BatteryTheme.color(.system, systemAccent: nil, dark: true), "读不到系统强调色就照旧")
    }

    func testDarkUsesReadableVersion() {
        // 很深的蓝在深色卡片上看不清，深色外观要往亮里调。
        let navy = ColorCode(red: 0.05, green: 0.05, blue: 0.3)
        let dark = BatteryTheme.color(.custom(navy), systemAccent: nil, dark: true)!
        XCTAssertNotEqual(dark, navy)
        XCTAssertGreaterThanOrEqual(WidgetTint.contrastRatio(dark, WidgetTint.darkCard), WidgetTint.minimumContrast)
    }

    // MARK: 默认回落红黄绿

    func testDefaultCellWaterIsUnchanged() {
        for level in [0.05, 0.2, 0.35, 0.5, 0.8, 1.0] {
            for charging in [false, true] {
                for lowPower in [false, true] {
                    XCTAssertEqual(
                        BatteryTheme.cellWaterColor(level: level, charging: charging, lowPower: lowPower, theme: nil),
                        BatteryLiquidFX.cellWaterColor(level: level, charging: charging, lowPower: lowPower))
                }
            }
        }
        XCTAssertEqual(BatteryTheme.cellWaterColor(level: 0.8, charging: false, lowPower: true, theme: nil),
                       BatteryColorMap.lowPowerYellow, "低电量模式黄")
        XCTAssertEqual(BatteryTheme.cellWaterColor(level: 0.1, charging: true, lowPower: false, theme: nil),
                       BatteryLiquidFX.green, "充电绿")
    }

    func testDefaultGaugeTintIsUnchanged() {
        for level in [0.05, 0.3, 0.6, 0.9] {
            let classic = BatteryTheme.gaugeTint(level: level, charging: false, lowPower: false, present: true,
                                                 liquid: false, theme: nil)
            XCTAssertEqual(classic, BatteryColorMap.tint(level: level, lowPower: false, charging: false))
            let liquid = BatteryTheme.gaugeTint(level: level, charging: false, lowPower: false, present: true,
                                                liquid: true, theme: nil)
            XCTAssertEqual(liquid.color, BatteryLiquidFX.gaugeWaterColor(level: level, lowPower: false))
        }
        let lowPower = BatteryTheme.gaugeTint(level: 0.7, charging: true, lowPower: true, present: true,
                                              liquid: true, theme: nil)
        XCTAssertEqual(lowPower.color, BatteryColorMap.lowPowerYellow)
    }

    func testDefaultClassicFillAndAccentFallBack() {
        XCTAssertNil(BatteryTheme.classicFill(tone: .normal, theme: nil))
        XCTAssertNil(BatteryTheme.accent(level: 0.1, charging: false, present: true, theme: nil))
    }

    // MARK: 选了颜色用主题色

    func testChosenColorReplacesLevelColours() {
        let rgb = BatteryRGB(blue.red, blue.green, blue.blue)
        // 高电量、中电量、充电、低电量模式都换成主题色。
        XCTAssertEqual(BatteryTheme.cellWaterColor(level: 0.8, charging: false, lowPower: false, theme: blue), rgb)
        XCTAssertEqual(BatteryTheme.cellWaterColor(level: 0.35, charging: false, lowPower: false, theme: blue), rgb)
        XCTAssertEqual(BatteryTheme.cellWaterColor(level: 0.6, charging: true, lowPower: false, theme: blue), rgb)
        XCTAssertEqual(BatteryTheme.cellWaterColor(level: 0.6, charging: false, lowPower: true, theme: blue), rgb)
        XCTAssertEqual(BatteryTheme.cellWaterColor(level: 0.1, charging: true, lowPower: false, theme: blue), rgb,
                       "充电时不报警")

        let gauge = BatteryTheme.gaugeTint(level: 0.45, charging: false, lowPower: true, present: true,
                                           liquid: true, theme: blue)
        XCTAssertEqual(gauge.color, rgb)
        XCTAssertEqual(gauge.highlight, rgb.mixed(with: .white, 0.35))
        XCTAssertFalse(gauge.pulses)

        XCTAssertEqual(BatteryTheme.classicFill(tone: .normal, theme: blue), blue)
        XCTAssertEqual(BatteryTheme.accent(level: 0.7, charging: false, present: true, theme: blue), rgb)
    }

    // MARK: 低电量仍红

    func testLowBatteryStaysRedWithChosenColor() {
        for level in [0.03, 0.15, 0.20] {
            XCTAssertEqual(BatteryTheme.cellWaterColor(level: level, charging: false, lowPower: false, theme: blue),
                           BatteryTheme.warningRed)
            XCTAssertEqual(BatteryTheme.cellWaterColor(level: level, charging: false, lowPower: true, theme: blue),
                           BatteryTheme.warningRed, "低电量模式下也照样报警")
            let gauge = BatteryTheme.gaugeTint(level: level, charging: false, lowPower: false, present: true,
                                               liquid: true, theme: blue)
            XCTAssertEqual(gauge.color, BatteryTheme.warningRed)
            XCTAssertEqual(gauge.band, .red)
            XCTAssertTrue(gauge.pulses)
            XCTAssertEqual(BatteryTheme.accent(level: level, charging: false, present: true, theme: blue),
                           BatteryTheme.warningRed)
        }
        // 21% 已经不报警。
        XCTAssertNotEqual(BatteryTheme.cellWaterColor(level: 0.21, charging: false, lowPower: false, theme: blue),
                          BatteryTheme.warningRed)
        // 经典的一截低电量照旧橙、红（不换成主题色）。
        XCTAssertNil(BatteryTheme.classicFill(tone: .low, theme: blue))
        XCTAssertNil(BatteryTheme.classicFill(tone: .critical, theme: blue))
        XCTAssertNil(BatteryTheme.classicFill(tone: .absent, theme: blue))
        // 液态的低电量圆滴不受颜色影响。
        XCTAssertTrue(BatteryLiquidFX.isLow(level: 0.15, charging: false, present: true))
    }

    // MARK: 经典上色后的数字

    func testClassicThemedInkFollowsTheme() {
        XCTAssertEqual(BatteryStatusCell.inkOnFill(tone: .normal, liquid: false, themed: true), .onTheme)
        XCTAssertEqual(BatteryStatusCell.inkOnFill(tone: .normal, liquid: false, themed: false), .inverted)
        XCTAssertEqual(BatteryStatusCell.inkOnFill(tone: .normal, liquid: true, themed: true), .white)
        XCTAssertEqual(BatteryStatusCell.inkOnFill(tone: .low, liquid: false, themed: true), .white)
    }
}
