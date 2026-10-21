import Foundation
import XCTest

/// 悬停扩展栏时的布局名小标签：出不出现、页码点、什么时候淡出。
final class LayoutLabelTests: XCTestCase {

    // MARK: 出不出现

    func testOnlyOneLayoutShowsNoLabel() {
        XCTAssertFalse(LayoutLabel.isAvailable(enabled: true, layoutCount: 0))
        XCTAssertFalse(LayoutLabel.isAvailable(enabled: true, layoutCount: 1))
        XCTAssertTrue(LayoutLabel.isAvailable(enabled: true, layoutCount: 2))
    }

    func testSwitchedOffShowsNoLabel() {
        XCTAssertFalse(LayoutLabel.isAvailable(enabled: false, layoutCount: 3))
    }

    // MARK: 页码点

    func testDotsMarkTheCurrentLayout() {
        let ids = [UUID(), UUID(), UUID()]
        XCTAssertEqual(LayoutLabel.pages(ids: ids, current: ids[1]), .dots([false, true, false]))
        XCTAssertEqual(LayoutLabel.pages(ids: ids, current: ids[0]), .dots([true, false, false]))
    }

    func testUnknownCurrentLightsNoDot() {
        let ids = [UUID(), UUID()]
        XCTAssertEqual(LayoutLabel.pages(ids: ids, current: nil), .dots([false, false]))
        XCTAssertEqual(LayoutLabel.pages(ids: ids, current: UUID()), .dots([false, false]))
    }

    func testManyLayoutsBecomeACounter() {
        let ids = (0..<12).map { _ in UUID() }
        XCTAssertEqual(LayoutLabel.pages(ids: ids, current: ids[2]), .counter(3, 12))
        XCTAssertEqual(LayoutLabel.pages(ids: ids, current: nil), .counter(0, 12))
        // 正好到上限还是点。
        let eight = Array(ids.prefix(LayoutLabel.maxDots))
        XCTAssertEqual(LayoutLabel.pages(ids: eight, current: eight[7]),
                       .dots([false, false, false, false, false, false, false, true]))
    }

    // MARK: 淡出

    func testHoverKeepsItVisibleWithNoDeadline() {
        var v = LayoutLabelVisibility()
        XCTAssertFalse(v.isVisible(at: 0))
        v.pointer(onShelf: true, at: 0)
        XCTAssertTrue(v.isVisible(at: 100))
        XCTAssertNil(v.hideDeadline(at: 100))
    }

    func testLeavingLingersThenFades() {
        var v = LayoutLabelVisibility()
        v.pointer(onShelf: true, at: 0)
        v.pointer(onShelf: false, at: 10)
        XCTAssertTrue(v.isVisible(at: 10.5))
        XCTAssertEqual(v.hideDeadline(at: 10.5)!, 10 + LayoutLabel.lingerAfterLeave, accuracy: 1e-9)
        XCTAssertFalse(v.isVisible(at: 10 + LayoutLabel.lingerAfterLeave + 0.01))
        XCTAssertNil(v.hideDeadline(at: 11))
    }

    /// 从扩展栏挪到标签上去点：路上不消失，到了标签上一直亮着。
    func testMovingOntoTheLabelKeepsItUp() {
        var v = LayoutLabelVisibility()
        v.pointer(onShelf: true, at: 0)
        v.pointer(onShelf: false, at: 1)
        v.pointer(onLabel: true, at: 1.3)
        XCTAssertTrue(v.isVisible(at: 5))
        v.pointer(onLabel: false, at: 5)
        XCTAssertTrue(v.isVisible(at: 5.5))
        XCTAssertFalse(v.isVisible(at: 6))
    }

    func testFlashLastsOneAndAHalfSeconds() {
        var v = LayoutLabelVisibility()
        v.flash(at: 2)
        XCTAssertTrue(v.isVisible(at: 3.4))
        XCTAssertEqual(v.hideDeadline(at: 2)!, 3.5, accuracy: 1e-9)
        XCTAssertFalse(v.isVisible(at: 3.6))
    }

    /// 闪现和离开的余留取晚的那个。
    func testDeadlineIsTheLaterOfFlashAndLinger() {
        var v = LayoutLabelVisibility()
        v.pointer(onShelf: true, at: 0)
        v.flash(at: 0.5)
        v.pointer(onShelf: false, at: 0.6)
        XCTAssertEqual(v.hideDeadline(at: 0.6)!, 2.0, accuracy: 1e-9)
        XCTAssertTrue(v.isVisible(at: 1.9))
    }

    func testResetHidesAtOnce() {
        var v = LayoutLabelVisibility()
        v.pointer(onShelf: true, at: 0)
        v.flash(at: 0)
        v.reset()
        XCTAssertFalse(v.isVisible(at: 0.1))
        XCTAssertNil(v.hideDeadline(at: 0.1))
    }

    // MARK: 设置

    func testSettingDefaultsOnForOldState() throws {
        let old = try JSONDecoder().decode(CustomDockSettings.self, from: Data("{}".utf8))
        XCTAssertTrue(old.showLayoutLabelOnHover)
        XCTAssertTrue(CustomDockSettings().showLayoutLabelOnHover)

        var off = CustomDockSettings()
        off.showLayoutLabelOnHover = false
        let round = try JSONDecoder().decode(CustomDockSettings.self,
                                             from: JSONEncoder().encode(off))
        XCTAssertFalse(round.showLayoutLabelOnHover)
    }
}
