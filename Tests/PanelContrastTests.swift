import XCTest

/// 浅色玻璃上主题色当文字：按目标对比度往黑里压。
final class PanelContrastTests: XCTestCase {
    private func color(_ hex: String) -> ColorCode { ColorCode(hex: hex)! }
    private let glass = PanelContrast.lightGlass

    /// 计算器黄、天气浅蓝、仪表盘浅蓝原来压 30% 不够 4.5，现在够了。
    func testBrightAccentsReachBodyTextContrastOnLightGlass() {
        for hex in ["#FFCC00", "#7CC8F2", "#7FD1FF", "#B9A6FF", "#3DDBB0", "#F5A524", "#FFD60A"] {
            let old = PanelContrast.darkened(color(hex), by: 0.3)
            let new = PanelContrast.readable(color(hex))
            XCTAssertGreaterThanOrEqual(WidgetTint.contrastRatio(new, glass), 4.5, hex)
            XCTAssertGreaterThanOrEqual(WidgetTint.contrastRatio(new, glass),
                                        WidgetTint.contrastRatio(old, glass), hex)
        }
        XCTAssertLessThan(WidgetTint.contrastRatio(PanelContrast.darkened(color("#FFCC00"), by: 0.3), glass), 4.5)
        XCTAssertLessThan(WidgetTint.contrastRatio(PanelContrast.darkened(color("#7CC8F2"), by: 0.3), glass), 4.5)
    }

    /// 本来压 30% 就够的深色主题色保持 30%，看起来和原来一样。
    func testDarkAccentsKeepTheOriginalThirtyPercent() {
        for hex in ["#8E5CF0", "#078AFF", "#CE32E3", "#1C1C1E"] {
            XCTAssertEqual(PanelContrast.fraction(for: color(hex)), 0.3, accuracy: 1e-9, hex)
        }
    }

    /// 取的是够用的最小值：再少压一点就不够了。
    func testFractionIsTheSmallestThatWorks() {
        for hex in ["#FFCC00", "#7CC8F2", "#FFFFFF"] {
            let f = PanelContrast.fraction(for: color(hex))
            XCTAssertGreaterThan(f, 0.3, hex)
            XCTAssertLessThanOrEqual(f, 1, hex)
            let less = PanelContrast.darkened(color(hex), by: f - 0.01)
            XCTAssertLessThan(WidgetTint.contrastRatio(less, glass), 4.5, hex)
        }
    }

    /// 图形按 3:1，压得比文字少。
    func testGraphicTargetDarkensLess() {
        let c = color("#7FD1FF")
        let graphic = PanelContrast.fraction(for: c, minContrast: PanelContrast.graphicContrast)
        let text = PanelContrast.fraction(for: c)
        XCTAssertLessThan(graphic, text)
        XCTAssertGreaterThanOrEqual(WidgetTint.contrastRatio(PanelContrast.readable(c, minContrast: 3), glass), 3)
    }

    /// 图形版：够 3:1 的不动（紫），不够的压到刚好 3:1（浅蓝、绿、橙）。
    func testGraphicOnlyDarkensWhenNeeded() {
        XCTAssertEqual(PanelContrast.graphic(color("#CE32E3")), color("#CE32E3"))
        for hex in ["#7FD1FF", "#34C759", "#FF9F0A", "#F5C451"] {
            let g = PanelContrast.graphic(color(hex))
            let ratio = WidgetTint.contrastRatio(g, glass)
            XCTAssertGreaterThanOrEqual(ratio, 3, hex)
            XCTAssertLessThan(ratio, 3.1, hex)
        }
    }

    /// 背景是中灰，压到纯黑也到不了 4.5（黑对 #666666 约 3.7）：直接给 1，不死循环。
    func testUnreachableTargetReturnsFull() {
        let gray = color("#666666")
        XCTAssertLessThan(WidgetTint.contrastRatio(ColorCode(red: 0, green: 0, blue: 0), gray), 4.5)
        XCTAssertEqual(PanelContrast.fraction(for: color("#FFCC00"), background: gray), 1)
    }

    func testDarkenedScalesComponents() {
        let d = PanelContrast.darkened(ColorCode(red: 1, green: 0.5, blue: 0.2), by: 0.5)
        XCTAssertEqual(d.red, 0.5, accuracy: 1e-9)
        XCTAssertEqual(d.green, 0.25, accuracy: 1e-9)
        XCTAssertEqual(d.blue, 0.1, accuracy: 1e-9)
    }
}
