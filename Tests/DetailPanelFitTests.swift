import XCTest

/// 小组件详情面板的尺寸和位置：高度随内容，上限是所在屏幕的可用区域，
/// 位置整个夹在屏幕里。
///
/// AppKit 屏幕坐标，y 向上。主屏 1512x982，菜单栏 37pt，可用区域
/// (0, 0, 1512, 945)；第二块 1920x1080 在它右边，菜单栏 25pt。
final class DetailPanelFitTests: XCTestCase {

    private let main = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let mainVisible = CGRect(x: 0, y: 0, width: 1512, height: 945)
    private let other = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
    private let otherVisible = CGRect(x: 1512, y: 0, width: 1920, height: 1055)

    private func assertInside(_ frame: CGRect, _ visible: CGRect,
                              file: StaticString = #filePath, line: UInt = #line) {
        let inner = visible.insetBy(dx: DetailPanelFit.margin, dy: DetailPanelFit.margin)
        XCTAssertGreaterThanOrEqual(frame.minX, inner.minX - 0.001, file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxX, inner.maxX + 0.001, file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.minY, inner.minY - 0.001, file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxY, inner.maxY + 0.001, file: file, line: line)
    }

    // MARK: 底部扩展栏

    func testShortPanelSitsAboveTheTileAtItsNaturalHeight() {
        let p = DetailPanelFit.place(edge: .bottom, anchor: CGPoint(x: 700, y: 80),
                                     natural: CGSize(width: 300, height: 400),
                                     visible: mainVisible)
        XCTAssertEqual(p.frame, CGRect(x: 550, y: 82, width: 300, height: 400))
        XCTAssertFalse(p.overflows)
    }

    func testTallPanelIsCappedAboveTheShelfAndScrolls() {
        // 原来：高 1200 的面板被往下推到 y = -263，顶上和底下都出屏幕。
        let p = DetailPanelFit.place(edge: .bottom, anchor: CGPoint(x: 700, y: 80),
                                     natural: CGSize(width: 340, height: 1200),
                                     visible: mainVisible)
        XCTAssertEqual(p.frame.minY, 82)
        XCTAssertEqual(p.frame.height, 945 - 8 - 82)
        XCTAssertTrue(p.overflows)
        assertInside(p.frame, mainVisible)
    }

    func testNoRoomAboveTheTileFallsBackToTheWholeScreen() {
        let anchor = CGPoint(x: 700, y: 850)
        XCTAssertEqual(DetailPanelFit.heightLimit(edge: .bottom, anchor: anchor, visible: mainVisible),
                       945 - 16)
        let p = DetailPanelFit.place(edge: .bottom, anchor: anchor,
                                     natural: CGSize(width: 300, height: 500),
                                     visible: mainVisible)
        XCTAssertEqual(p.frame.height, 500)
        assertInside(p.frame, mainVisible)
    }

    func testPanelNearTheRightEndIsPulledBackOnScreen() {
        let p = DetailPanelFit.place(edge: .bottom, anchor: CGPoint(x: 1500, y: 80),
                                     natural: CGSize(width: 340, height: 300),
                                     visible: mainVisible)
        XCTAssertEqual(p.frame.minX, 1512 - 8 - 340)
        assertInside(p.frame, mainVisible)
    }

    // MARK: 顶部扩展栏

    func testTopShelfPanelHangsBelowAndIsCappedAtTheBottom() {
        let p = DetailPanelFit.place(edge: .top, anchor: CGPoint(x: 700, y: 900),
                                     natural: CGSize(width: 320, height: 1200),
                                     visible: mainVisible)
        XCTAssertEqual(p.frame.maxY, 900 - 2)
        XCTAssertEqual(p.frame.minY, 8)
        XCTAssertTrue(p.overflows)
    }

    // MARK: 竖排扩展栏

    func testSideShelfPanelNearTheBottomIsLiftedOnScreen() {
        let p = DetailPanelFit.place(edge: .left, anchor: CGPoint(x: 60, y: 100),
                                     natural: CGSize(width: 300, height: 500),
                                     visible: mainVisible)
        XCTAssertEqual(p.frame.minX, 62)
        XCTAssertEqual(p.frame.minY, 8)
        XCTAssertFalse(p.overflows)
    }

    func testSideShelfPanelTallerThanTheScreenUsesTheWholeHeight() {
        let p = DetailPanelFit.place(edge: .right, anchor: CGPoint(x: 1450, y: 500),
                                     natural: CGSize(width: 340, height: 2000),
                                     visible: mainVisible)
        XCTAssertEqual(p.frame.height, 945 - 16)
        XCTAssertEqual(p.frame.maxX, 1450 - 2)
        XCTAssertTrue(p.overflows)
        assertInside(p.frame, mainVisible)
    }

    // MARK: 多显示器

    func testScreenIsChosenByTheTileNotThePanelOrigin() {
        let screens = [main, other]
        XCTAssertEqual(DetailPanelFit.screenIndex(for: CGPoint(x: 2000, y: 50), screens: screens), 1)
        XCTAssertEqual(DetailPanelFit.screenIndex(for: CGPoint(x: 1512, y: 50), screens: screens), 1)
        XCTAssertEqual(DetailPanelFit.screenIndex(for: CGPoint(x: 100, y: 50), screens: screens), 0)
        // 落在所有屏幕外面：取最近的一块。
        XCTAssertEqual(DetailPanelFit.screenIndex(for: CGPoint(x: 5000, y: 50), screens: screens), 1)
        XCTAssertEqual(DetailPanelFit.screenIndex(for: CGPoint(x: -10, y: 10), screens: screens), 0)
        XCTAssertNil(DetailPanelFit.screenIndex(for: .zero, screens: []))
    }

    func testTopShelfOnTheSecondDisplayStaysOnIt() {
        let anchor = CGPoint(x: 1530, y: 1040)
        let p = DetailPanelFit.place(edge: .top, anchor: anchor,
                                     natural: CGSize(width: 360, height: 1400),
                                     visible: otherVisible)
        assertInside(p.frame, otherVisible)
        XCTAssertTrue(p.overflows)
    }

    // MARK: 小工具

    func testFallbackAnchorIsTheShelfsOpenSide() {
        let shelf = CGRect(x: 100, y: 10, width: 800, height: 70)
        XCTAssertEqual(DetailPanelFit.fallbackAnchor(edge: .bottom, shelf: shelf), CGPoint(x: 500, y: 80))
        XCTAssertEqual(DetailPanelFit.fallbackAnchor(edge: .top, shelf: shelf), CGPoint(x: 500, y: 10))
        XCTAssertEqual(DetailPanelFit.fallbackAnchor(edge: .left, shelf: shelf), CGPoint(x: 900, y: 45))
        XCTAssertEqual(DetailPanelFit.fallbackAnchor(edge: .right, shelf: shelf), CGPoint(x: 100, y: 45))
    }

    func testViewportLeavesOutTheTailOnlyOnARow() {
        XCTAssertEqual(DetailPanelFit.viewportHeight(panelHeight: 400, edge: .bottom, tailDepth: 10), 390)
        XCTAssertEqual(DetailPanelFit.viewportHeight(panelHeight: 400, edge: .top, tailDepth: 10), 390)
        XCTAssertEqual(DetailPanelFit.viewportHeight(panelHeight: 400, edge: .left, tailDepth: 10), 400)
    }

    func testTinyHeightJitterDoesNotRefit() {
        XCTAssertFalse(DetailPanelFit.needsRefit(old: 400, new: 400.3))
        XCTAssertTrue(DetailPanelFit.needsRefit(old: 400, new: 412))
    }
}
