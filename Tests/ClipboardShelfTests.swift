import XCTest

/// 剪贴板面板的货架排法。
final class ClipboardShelfTests: XCTestCase {

    func testRowsSplitByThree() {
        XCTAssertEqual(ClipboardShelf.rows(count: 0), [])
        XCTAssertEqual(ClipboardShelf.rows(count: 2), [0..<2])
        XCTAssertEqual(ClipboardShelf.rows(count: 7), [0..<3, 3..<6, 6..<7])
        XCTAssertEqual(ClipboardShelf.rows(count: 4, perRow: 0), [])
    }

    func testTiltIsSmallStableAndAlternates() {
        for i in -12..<24 {
            XCTAssertLessThanOrEqual(abs(ClipboardShelf.tilt(index: i)), 3)
            XCTAssertEqual(ClipboardShelf.tilt(index: i), ClipboardShelf.tilt(index: i))
        }
        for i in 0..<12 {
            let a = ClipboardShelf.tilt(index: i)
            let b = ClipboardShelf.tilt(index: i + 1)
            XCTAssertTrue(a * b < 0, "相邻两张往不同方向歪")
        }
    }

    func testExcerptFlattensAndTruncates() {
        XCTAssertEqual(ClipboardShelf.excerpt("  第一行\n第二行  "), "第一行 第二行")
        XCTAssertEqual(ClipboardShelf.excerpt("abcdef", limit: 3), "abc…")
        XCTAssertEqual(ClipboardShelf.excerpt("abc", limit: 3), "abc")
    }
}
