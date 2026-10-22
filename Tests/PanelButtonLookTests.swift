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
}
