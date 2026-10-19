import XCTest

final class PaperInkTests: XCTestCase {
    func testEveryPaperColorMeetsBodyTextContrast() {
        for color in PaperColor.allCases {
            let ratio = PaperInk.contrast(paper: color.hex, ink: color.inkHex)
            XCTAssertGreaterThanOrEqual(ratio, PaperInk.minimumContrast,
                                        "\(color) 上的墨对比度只有 \(ratio)")
        }
    }

    func testMidTonePapersAreChecked() {
        // 用户反馈看不清的几种中间色纸，单独再点一遍名。
        for color in [PaperColor.slate, .kraft, .coral, .teal, .graphite] {
            XCTAssertGreaterThanOrEqual(PaperInk.contrast(paper: color.hex, ink: color.inkHex), 4.5, "\(color)")
        }
    }

    func testDarkPapersTakeLightInkAndTheRestDarkInk() {
        XCTAssertTrue(PaperColor.slate.isDark)
        XCTAssertTrue(PaperColor.night.isDark)
        XCTAssertEqual(PaperColor.night.inkHex, PaperInk.lightInk)
        for color in PaperColor.allCases where color != .slate && color != .night {
            XCTAssertFalse(color.isDark, "\(color)")
            XCTAssertEqual(color.inkHex, PaperInk.darkInk, "\(color) 原来的深墨已经够，不改")
        }
    }

    func testInkIsPushedFurtherWhenNeitherDefaultIsEnough() {
        // 中灰纸：默认深墨约 3.7、浅墨约 4.1，都不到 4.5，要加深。
        let paper = "#777777"
        XCTAssertLessThan(PaperInk.contrast(paper: paper, ink: PaperInk.darkInk), 4.5)
        XCTAssertLessThan(PaperInk.contrast(paper: paper, ink: PaperInk.lightInk), 4.5)
        let ink = PaperInk.ink(on: paper)
        XCTAssertNotEqual(ink, PaperInk.darkInk)
        XCTAssertNotEqual(ink, PaperInk.lightInk)
        XCTAssertGreaterThanOrEqual(PaperInk.contrast(paper: paper, ink: ink), 4.5)
    }

    func testStricterTargetAndBadInput() {
        // 要求更高时也朝同一个方向推，最多到纯黑。
        let ink = PaperInk.ink(on: PaperColor.slate.hex, minimum: 7)
        XCTAssertGreaterThanOrEqual(PaperInk.contrast(paper: PaperColor.slate.hex, ink: ink), 4.96)
        XCTAssertEqual(PaperInk.ink(on: "nope"), PaperInk.darkInk)
        XCTAssertEqual(PaperInk.contrast(paper: "nope", ink: "#000000"), 1)
    }
}
