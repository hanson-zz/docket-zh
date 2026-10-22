import XCTest

/// 面板实心主按钮：禁用时中性灰底 + 次级字色，浅色、深色都要看得清。
final class PanelButtonLookTests: XCTestCase {
    func testDisabledButtonTextReachesBodyContrastInBothAppearances() {
        XCTAssertGreaterThanOrEqual(PanelButtonLook.disabledTextContrast(dark: false), 4.5)
        XCTAssertGreaterThanOrEqual(PanelButtonLook.disabledTextContrast(dark: true), 4.5)
    }

    func testDisabledChipIsAtLeastThreeToOne() {
        XCTAssertGreaterThanOrEqual(PanelButtonLook.disabledChipContrast(dark: false), 3)
        XCTAssertGreaterThanOrEqual(PanelButtonLook.disabledChipContrast(dark: true), 3)
        // 芯片比主按钮淡一档，但不会比主按钮还清楚。
        XCTAssertLessThan(PanelButtonLook.disabledChipContrast(dark: false),
                          PanelButtonLook.disabledTextContrast(dark: false))
    }

    func testSolidBlueKeepsWhiteTextReadable() {
        XCTAssertEqual(PanelButtonLook.solidBlue, ColorCode(hex: PanelButtonLook.solidBlueHex))
        XCTAssertGreaterThanOrEqual(PanelButtonLook.solidTextContrast, 4.5)
    }

    /// 原来的禁用态：#4C9BFF 调到 0.35 压在浅色玻璃上，白字只有 1.5 左右。
    func testOldFadedBlueWasUnreadable() throws {
        let old = PanelButtonLook.blend(try XCTUnwrap(ColorCode(hex: "#4C9BFF")), alpha: 0.35,
                                        over: PanelButtonLook.lightGlass)
        XCTAssertLessThan(WidgetTint.contrastRatio(PanelButtonLook.white, old), 2)
        // 原来的「剪贴板」禁用芯片：主文字 0.35，不到 3:1。
        let fill = PanelButtonLook.disabledFill(dark: false)
        let chip = PanelButtonLook.blend(PanelButtonLook.lightInk, alpha: 0.35, over: fill)
        XCTAssertLessThan(WidgetTint.contrastRatio(chip, fill), 3)
    }

    func testBlendClampsAlpha() {
        let w = PanelButtonLook.white, b = PanelButtonLook.black
        XCTAssertEqual(PanelButtonLook.blend(w, alpha: 2, over: b), w)
        XCTAssertEqual(PanelButtonLook.blend(w, alpha: -1, over: b), b)
        XCTAssertEqual(PanelButtonLook.blend(w, alpha: .nan, over: b), b)
    }

    // MARK: 主题色实心按钮

    private func look(_ hex: String, file: StaticString = #filePath, line: UInt = #line) throws -> PanelButtonLook.SolidLook {
        PanelButtonLook.solid(for: try XCTUnwrap(ColorCode(hex: hex), file: file, line: line))
    }

    /// 换成 8 位色后的对比度（界面最终画的是这个）。
    private func roundedContrast(_ a: ColorCode, _ b: ColorCode) throws -> Double {
        WidgetTint.contrastRatio(try XCTUnwrap(ColorCode(hex: a.hex)), try XCTUnwrap(ColorCode(hex: b.hex)))
    }

    /// 常见主题色、内置 15 种主题色、系统蓝、灰、黑白：可用态和按下态都不低于 4.5。
    func testEveryThemeColorReadable() throws {
        var hexes = ["#FFD60A", "#FFD43B", "#FFF3B0", "#A8E6A3", "#34C759", "#4C9BFF", "#2563EB",
                     "#FF3B30", "#FF4D4F", "#AF52DE", "#8E5CF0", "#007AFF", "#8E8E93", "#808080",
                     "#FFFFFF", "#000000", "#FF9500", "#5AC8FA", "#FF2D55"]
        hexes += WidgetTint.Preset.allCases.map(\.hex)
        for hex in hexes {
            let l = try look(hex)
            XCTAssertGreaterThanOrEqual(l.contrast, 4.5, hex)
            XCTAssertGreaterThanOrEqual(l.pressedContrast, 4.5, hex)
            XCTAssertGreaterThanOrEqual(try roundedContrast(l.ink, l.fill), 4.5, hex)
            XCTAssertGreaterThanOrEqual(try roundedContrast(l.ink, l.pressedFill), 4.5, hex)
        }
    }

    /// 没设主题色：#2563EB 白字原样，不加深。
    func testDefaultBlueUnchanged() {
        let l = PanelButtonLook.defaultSolid
        XCTAssertEqual(l.fill, PanelButtonLook.solidBlue)
        XCTAssertEqual(l.ink, PanelButtonLook.white)
        XCTAssertFalse(l.darkened)
        XCTAssertFalse(l.inkIsDark)
    }

    /// 黄、浅黄、浅绿：加深会变成橄榄色、土黄，改深色字配原色。
    func testYellowAndPastelsUseDarkInk() throws {
        for hex in ["#FFD60A", "#FFD43B", "#FFF3B0", "#A8E6A3", "#FFFFFF", "#F5A524", "#A6D63A"] {
            let l = try look(hex)
            XCTAssertTrue(l.inkIsDark, hex)
            XCTAssertFalse(l.darkened, hex)
            XCTAssertEqual(l.fill, ColorCode(hex: hex), hex)
            XCTAssertEqual(l.ink, PanelButtonLook.darkInk, hex)
        }
    }

    /// 绿、#4C9BFF、红、紫：同色相加深一点，保留白字。
    func testMidTonesDarkenKeepingWhite() throws {
        for hex in ["#34C759", "#4C9BFF", "#FF3B30", "#FF4D4F", "#AF52DE", "#8E5CF0"] {
            let theme = try XCTUnwrap(ColorCode(hex: hex))
            let l = try look(hex)
            XCTAssertFalse(l.inkIsDark, hex)
            XCTAssertTrue(l.darkened, hex)
            XCTAssertEqual(l.ink, PanelButtonLook.white, hex)
            XCTAssertLessThan(WidgetTint.luminance(l.fill), WidgetTint.luminance(theme), hex)
            // 色相不变（差不到 1 度）。
            let dh = abs(PanelButtonLook.HSL(l.fill).hue - PanelButtonLook.HSL(theme).hue)
            XCTAssertLessThan(min(dh, 1 - dh), 1.0 / 360, hex)
        }
    }

    /// 白字本来就够的颜色不动。
    func testAlreadyReadableUntouched() throws {
        for hex in ["#2563EB", "#000000", "#1A4D2E", "#7A1F1F"] {
            let l = try look(hex)
            XCTAssertEqual(l.fill, ColorCode(hex: hex), hex)
            XCTAssertEqual(l.ink, PanelButtonLook.white, hex)
        }
    }

    /// 按下再深一档：白字时更深；深色字时也更深或不变，但对比度不掉到 4.5 以下。
    func testPressedIsDarker() throws {
        for hex in ["#2563EB", "#4C9BFF", "#34C759", "#FFD60A", "#A8E6A3", "#FF3B30"] {
            let l = try look(hex)
            XCTAssertLessThanOrEqual(WidgetTint.luminance(l.pressedFill), WidgetTint.luminance(l.fill), hex)
            XCTAssertNotEqual(l.pressedFill, l.fill, hex)
        }
    }

    /// 半透明主题色先盖在玻璃上再算，浅色、深色外观都过 4.5。
    func testTranslucentThemeOnBothGlasses() throws {
        for hex in ["#34C759", "#FFD60A", "#4C9BFF", "#AF52DE"] {
            let theme = try XCTUnwrap(ColorCode(hex: hex))
            for dark in [false, true] {
                let l = PanelButtonLook.solid(for: theme, alpha: 0.9, dark: dark)
                XCTAssertGreaterThanOrEqual(l.contrast, 4.5, "\(hex) dark=\(dark)")
                XCTAssertGreaterThanOrEqual(l.pressedContrast, 4.5, "\(hex) dark=\(dark)")
            }
        }
        // 不透明的不受外观影响。
        let green = try XCTUnwrap(ColorCode(hex: "#34C759"))
        XCTAssertEqual(PanelButtonLook.solid(for: green, alpha: 1, dark: true),
                       PanelButtonLook.solid(for: green))
    }

    func testHSLRoundTrip() throws {
        for hex in ["#FFD60A", "#34C759", "#4C9BFF", "#8E8E93", "#AF52DE", "#FFFFFF", "#000000"] {
            let c = try XCTUnwrap(ColorCode(hex: hex))
            XCTAssertEqual(PanelButtonLook.HSL(c).color.hex, c.hex, hex)
        }
    }
}
