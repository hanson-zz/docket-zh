import XCTest

/// 颜色主题在卡片以外的地方：面板强调色的默认回落、主题色按钮的字色、
/// 卡片和面板光晕的透明度上限。
final class WidgetTintAccentTests: XCTestCase {

    private let white = ColorCode(red: 1, green: 1, blue: 1)
    private let black = ColorCode(red: 0, green: 0, blue: 0)

    // MARK: 面板强调色

    func testDefaultFallsBackToThePanelsOwnColours() {
        for kind in WidgetKind.allCases {
            XCTAssertEqual(WidgetTint.panelAccent(.kindDefault, kind: kind), .own, kind.rawValue)
            XCTAssertFalse(WidgetTint.panelAccent(.kindDefault, kind: kind).overrides, kind.rawValue)
        }
        // 没写过颜色的配置读出来就是默认。
        XCTAssertEqual(WidgetTint.panelAccent(WidgetTint.choice(WidgetConfig()), kind: .countdown), .own)
    }

    func testKindsWithoutColourIgnoreAStoredChoice() {
        for kind in WidgetKind.allCases where !WidgetTint.offersColor(kind) {
            XCTAssertEqual(WidgetTint.panelAccent(.preset(.blue), kind: kind), .own, kind.rawValue)
            XCTAssertEqual(WidgetTint.glowOpacity(.preset(.blue), kind: kind, dark: true), 0, kind.rawValue)
        }
    }

    func testChosenColourIsReadableOnTheDarkPanelCard() {
        XCTAssertEqual(WidgetTint.panelAccent(.system, kind: .timer), .system)
        for preset in WidgetTint.Preset.allCases {
            guard case .color(let code) = WidgetTint.panelAccent(.preset(preset), kind: .timer) else {
                return XCTFail("预设 \(preset.rawValue) 应该换成选的颜色")
            }
            XCTAssertEqual(code, WidgetTint.readable(preset.palette.main, dark: true))
            XCTAssertGreaterThanOrEqual(WidgetTint.contrastRatio(code, WidgetTint.darkCard),
                                        WidgetTint.minimumContrast - 0.01, preset.rawValue)
        }
        // 很暗的自定义颜色会被调亮，不会在深色面板上看不见。
        let navy = ColorCode(hex: "#101030")!
        guard case .color(let lifted) = WidgetTint.panelAccent(.custom(navy), kind: .countdown) else {
            return XCTFail("自定义颜色应该换上")
        }
        XCTAssertNotEqual(lifted, navy)
        XCTAssertGreaterThanOrEqual(WidgetTint.contrastRatio(lifted, WidgetTint.darkCard),
                                    WidgetTint.minimumContrast - 0.01)
    }

    func testLockedCustomColourFallsBackToDefault() {
        let config = WidgetConfig([WidgetTint.key: .string("#123456")])
        let shown = WidgetTint.shownChoice(config, unlocked: false)
        XCTAssertEqual(WidgetTint.panelAccent(shown, kind: .countdown), .own)
        XCTAssertEqual(WidgetTint.glowOpacity(shown, kind: .countdown, dark: true), 0)
    }

    // MARK: 字色

    func testLabelInkFollowsBrightness() {
        XCTAssertTrue(WidgetTint.labelIsDark(on: ColorCode(hex: WidgetTint.Preset.yellow.hex)!), "黄底深色字")
        XCTAssertTrue(WidgetTint.labelIsDark(on: white))
        XCTAssertFalse(WidgetTint.labelIsDark(on: black))
        // 蓝、紫白字对比度不到 4.5（3.89、4.25），黑字更清楚，换深色字。
        XCTAssertTrue(WidgetTint.labelIsDark(on: ColorCode(hex: WidgetTint.Preset.blue.hex)!), "蓝底深色字")
        XCTAssertTrue(WidgetTint.labelIsDark(on: ColorCode(hex: WidgetTint.Preset.purple.hex)!), "紫底深色字")
        // 够深的颜色白字到 4.5，照旧白字。
        XCTAssertFalse(WidgetTint.labelIsDark(on: ColorCode(hex: "#14204A")!), "深蓝底白字")
        XCTAssertFalse(WidgetTint.labelIsDark(on: ColorCode(hex: "#5B2BB5")!), "深紫底白字")
        // 薄荷绿亮度没过空状态按钮那条线，但白字对比度不够，也换深色字。
        let mint = ColorCode(hex: WidgetTint.Preset.mint.hex)!
        XCTAssertLessThanOrEqual(PandaEmpty.brightness(mint), PandaEmpty.darkLabelThreshold)
        XCTAssertTrue(WidgetTint.labelIsDark(on: mint))
    }

    func testLabelInkAgreesWithTheEmptyStateButtons() {
        // 过了空状态按钮那条亮度线的颜色，一定是深色字。
        for preset in WidgetTint.Preset.allCases {
            let code = ColorCode(hex: preset.hex)!
            if PandaEmpty.brightness(code) > PandaEmpty.darkLabelThreshold {
                XCTAssertTrue(WidgetTint.labelIsDark(on: code), preset.rawValue)
            }
        }
    }

    func testButtonLabelIsAlwaysLegible() {
        let fills = WidgetTint.Preset.allCases.flatMap { preset in
            [ColorCode(hex: preset.hex)!, WidgetTint.readable(preset.palette.main, dark: true)]
        }
        for fill in fills {
            let ink = WidgetTint.labelIsDark(on: fill) ? black : white
            XCTAssertGreaterThanOrEqual(WidgetTint.contrastRatio(fill, ink), WidgetTint.minimumTextContrast, fill.hex)
        }
    }

    // MARK: 光晕

    func testGlowNeverExceedsTheCap() {
        XCTAssertLessThanOrEqual(WidgetTint.maxGlowOpacity, 0.15)
        let choices: [WidgetTint.Choice] = [.kindDefault, .system, .custom(ColorCode(hex: "#FF00FF")!)]
            + WidgetTint.Preset.allCases.map { .preset($0) }
        for kind in WidgetKind.allCases {
            for choice in choices {
                for dark in [true, false] {
                    XCTAssertLessThanOrEqual(WidgetTint.glowOpacity(choice, kind: kind, dark: dark),
                                             WidgetTint.maxGlowOpacity)
                    XCTAssertLessThanOrEqual(WidgetTint.edgeOpacity(choice, kind: kind, dark: dark),
                                             WidgetTint.maxGlowOpacity)
                    for background in WidgetTint.Background.allCases {
                        XCTAssertLessThanOrEqual(
                            WidgetTint.cardGlowOpacity(choice, kind: kind, background: background, dark: dark),
                            WidgetTint.maxGlowOpacity)
                    }
                }
            }
        }
    }

    func testGlowOnlyWhenAColourIsChosen() {
        XCTAssertEqual(WidgetTint.glowOpacity(.kindDefault, kind: .countdown, dark: true), 0)
        XCTAssertEqual(WidgetTint.edgeOpacity(.kindDefault, kind: .countdown, dark: false), 0)
        XCTAssertGreaterThan(WidgetTint.glowOpacity(.preset(.mint), kind: .countdown, dark: true), 0)
        XCTAssertGreaterThan(WidgetTint.glowOpacity(.system, kind: .countdown, dark: false), 0)
        XCTAssertGreaterThan(WidgetTint.edgeOpacity(.preset(.mint), kind: .countdown, dark: true), 0)
        // 浅色外观的卡片本身亮，光晕收一点。
        XCTAssertLessThan(WidgetTint.glowOpacity(.preset(.mint), kind: .countdown, dark: false),
                          WidgetTint.glowOpacity(.preset(.mint), kind: .countdown, dark: true))
    }

    func testGradientBackgroundSkipsTheCardGlow() {
        XCTAssertEqual(WidgetTint.cardGlowOpacity(.preset(.blue), kind: .countdown,
                                                  background: .gradient, dark: true), 0)
        XCTAssertGreaterThan(WidgetTint.cardGlowOpacity(.preset(.blue), kind: .countdown,
                                                        background: .dark, dark: true), 0)
        XCTAssertGreaterThan(WidgetTint.cardGlowOpacity(.preset(.blue), kind: .countdown,
                                                        background: .plain, dark: true), 0)
    }

    func testGlowFadesOutBeforeTheBottom() {
        XCTAssertGreaterThan(WidgetTint.glowReach, 0)
        XCTAssertLessThan(WidgetTint.glowReach, 1)
    }
}
