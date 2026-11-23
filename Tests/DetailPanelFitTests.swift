import XCTest

/// 小组件详情面板的尺寸和位置：高度随内容，上限是统一上限（560pt、屏幕
/// 可见高度的 60%，取小的）和所在屏幕的可用区域，位置整个夹在屏幕里。
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
        // 后来只按屏幕限高，占到 855pt，屏幕的九成；现在统一上限 560pt。
        let p = DetailPanelFit.place(edge: .bottom, anchor: CGPoint(x: 700, y: 80),
                                     natural: CGSize(width: 340, height: 1200),
                                     visible: mainVisible)
        XCTAssertEqual(p.frame.minY, 82)
        XCTAssertEqual(p.frame.height, 560)
        XCTAssertTrue(p.overflows)
        assertInside(p.frame, mainVisible)
    }

    func testExemptPanelStillUsesTheRoomAboveTheShelf() {
        let p = DetailPanelFit.place(edge: .bottom, anchor: CGPoint(x: 700, y: 80),
                                     natural: CGSize(width: 340, height: 1200),
                                     visible: mainVisible, capped: false)
        XCTAssertEqual(p.frame.minY, 82)
        XCTAssertEqual(p.frame.height, 945 - 12 - 82)
        XCTAssertTrue(p.overflows)
    }

    func testPanelUnderTheCapIsNotTouched() {
        let p = DetailPanelFit.place(edge: .bottom, anchor: CGPoint(x: 700, y: 80),
                                     natural: CGSize(width: 320, height: 540),
                                     visible: mainVisible)
        XCTAssertEqual(p.frame.height, 540)
        XCTAssertFalse(p.overflows)
    }

    // MARK: 统一上限

    func testCapIsTheSmallerOfTheFixedHeightAndTheScreenShare() {
        // 945 的六成是 567，比 560 大，取 560。
        XCTAssertEqual(DetailPanelFit.cap(visible: mainVisible), 560)
        XCTAssertEqual(DetailPanelFit.cap(visible: otherVisible), 560)
        // 矮屏：800 的六成 480。
        XCTAssertEqual(DetailPanelFit.cap(visible: CGRect(x: 0, y: 0, width: 1280, height: 800)), 480)
        // 再矮也不低于 minimumHeight。
        XCTAssertEqual(DetailPanelFit.cap(visible: CGRect(x: 0, y: 0, width: 800, height: 200)),
                       DetailPanelFit.minimumHeight)
    }

    func testShortScreenCapsAtSixtyPercent() {
        let visible = CGRect(x: 0, y: 0, width: 1280, height: 775)
        let p = DetailPanelFit.place(edge: .bottom, anchor: CGPoint(x: 600, y: 70),
                                     natural: CGSize(width: 320, height: 900), visible: visible)
        XCTAssertEqual(p.frame.height, 465)
        XCTAssertTrue(p.overflows)
        assertInside(p.frame, visible)
    }

    func testTinyScreenNeverGoesPastTheScreenItself() {
        // 可见高度 150：统一上限不低于 160，但屏幕减边距只有 126，取屏幕的。
        let visible = CGRect(x: 0, y: 0, width: 800, height: 150)
        XCTAssertEqual(DetailPanelFit.heightLimit(edge: .left, anchor: CGPoint(x: 10, y: 75),
                                                  visible: visible), 126)
    }

    func testOnlyThePlannerAndTheAssistantAreExempt() {
        XCTAssertTrue(DetailPanelFit.isCapExempt(.calendar))
        XCTAssertTrue(DetailPanelFit.isCapExempt(.week))
        XCTAssertTrue(DetailPanelFit.isCapExempt(.aiAssistant))
        for kind in [WidgetKind.weather, .water, .posture, .timer, .radio, .lunar, .system, .habit] {
            XCTAssertFalse(DetailPanelFit.isCapExempt(kind), "\(kind)")
        }
    }

    func testNoRoomAboveTheTileFallsBackToTheWholeScreen() {
        let anchor = CGPoint(x: 700, y: 850)
        XCTAssertEqual(DetailPanelFit.heightLimit(edge: .bottom, anchor: anchor, visible: mainVisible,
                                                  capped: false), 945 - 24)
        XCTAssertEqual(DetailPanelFit.heightLimit(edge: .bottom, anchor: anchor, visible: mainVisible), 560)
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
        XCTAssertEqual(p.frame.minX, 1512 - 12 - 340)
        assertInside(p.frame, mainVisible)
    }

    // MARK: 顶部扩展栏

    func testTopShelfPanelHangsBelowAndIsCappedAtTheBottom() {
        let p = DetailPanelFit.place(edge: .top, anchor: CGPoint(x: 700, y: 900),
                                     natural: CGSize(width: 320, height: 1200),
                                     visible: mainVisible)
        XCTAssertEqual(p.frame.maxY, 900 - 2)
        XCTAssertEqual(p.frame.minY, 898 - 560)
        XCTAssertTrue(p.overflows)
    }

    // MARK: 竖排扩展栏

    func testSideShelfPanelNearTheBottomIsLiftedOnScreen() {
        let p = DetailPanelFit.place(edge: .left, anchor: CGPoint(x: 60, y: 100),
                                     natural: CGSize(width: 300, height: 500),
                                     visible: mainVisible)
        XCTAssertEqual(p.frame.minX, 62)
        XCTAssertEqual(p.frame.minY, 12)
        XCTAssertFalse(p.overflows)
    }

    func testSideShelfPanelTallerThanTheScreenIsCapped() {
        let p = DetailPanelFit.place(edge: .right, anchor: CGPoint(x: 1450, y: 500),
                                     natural: CGSize(width: 340, height: 2000),
                                     visible: mainVisible)
        XCTAssertEqual(p.frame.height, 560)
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

    // MARK: 菜单栏

    func testAutoHiddenMenuBarIsStillLeftClear() {
        // 菜单栏自动隐藏：visibleFrame 伸到屏幕顶边，面板仍让出 24pt。
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let visible = CGRect(x: 0, y: 70, width: 1440, height: 830)
        let usable = DetailPanelFit.usableArea(visible: visible, screen: screen, menuBar: 24)
        XCTAssertEqual(usable, CGRect(x: 0, y: 70, width: 1440, height: 806))
        let p = DetailPanelFit.place(edge: .bottom, anchor: CGPoint(x: 700, y: 150),
                                     natural: CGSize(width: 320, height: 1400),
                                     visible: usable, capped: false)
        XCTAssertLessThanOrEqual(p.frame.maxY, 900 - 24 - DetailPanelFit.margin)
        assertInside(p.frame, usable)
    }

    func testVisibleMenuBarIsNotCountedTwice() {
        let usable = DetailPanelFit.usableArea(visible: mainVisible, screen: main, menuBar: 37)
        XCTAssertEqual(usable, mainVisible)
        XCTAssertEqual(DetailPanelFit.usableArea(visible: mainVisible, screen: main, menuBar: 0), mainVisible)
    }

    func testScreenTallerPanelUsesTheWholeUsableHeightWhenExempt() {
        // 最大高度 = 可用高度减上下边距（尾巴含在里面）。
        let p = DetailPanelFit.place(edge: .left, anchor: CGPoint(x: 60, y: 470),
                                     natural: CGSize(width: 300, height: 3000),
                                     visible: mainVisible, capped: false)
        XCTAssertEqual(p.frame.height, 945 - 2 * DetailPanelFit.margin)
        assertInside(p.frame, mainVisible)
    }

    // MARK: 钉住的外观栏

    func testFooterKeepsItsHeightAndTheRestScrolls() {
        let v = DetailPanelFit.viewports(panelHeight: 560, edge: .bottom, tailDepth: 10, footer: 38)
        XCTAssertEqual(v, DetailPanelFit.Viewports(scroll: 512, footer: 38))
        let side = DetailPanelFit.viewports(panelHeight: 560, edge: .right, tailDepth: 10, footer: 38)
        XCTAssertEqual(side, DetailPanelFit.Viewports(scroll: 522, footer: 38))
    }

    func testTallFooterIsSqueezedButLeavesRoomToScroll() {
        // 外观展开后 500 高：滚动区仍留 120。
        let v = DetailPanelFit.viewports(panelHeight: 410, edge: .bottom, tailDepth: 10, footer: 500)
        XCTAssertEqual(v, DetailPanelFit.Viewports(scroll: 120, footer: 280))
        // 面板很矮：各一半。
        let low = DetailPanelFit.viewports(panelHeight: 170, edge: .bottom, tailDepth: 10, footer: 500)
        XCTAssertEqual(low, DetailPanelFit.Viewports(scroll: 80, footer: 80))
    }

    func testNoFooterGivesTheWholeBodyToTheScroll() {
        let v = DetailPanelFit.viewports(panelHeight: 400, edge: .top, tailDepth: 10, footer: 0)
        XCTAssertEqual(v, DetailPanelFit.Viewports(scroll: 390, footer: 0))
    }

    func testFadesFollowTheScrollOffset() {
        XCTAssertTrue(DetailPanelFit.fades(offset: 0, container: 500, content: 400) == (false, false))
        XCTAssertTrue(DetailPanelFit.fades(offset: 0, container: 500, content: 900) == (false, true))
        XCTAssertTrue(DetailPanelFit.fades(offset: 200, container: 500, content: 900) == (true, true))
        XCTAssertTrue(DetailPanelFit.fades(offset: 400, container: 500, content: 900) == (true, false))
    }

    func testContainPullsATallPanelBackOnScreen() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 870)
        let m = DetailPanelFit.margin
        // 顶上出了屏幕
        let out = DetailPanelFit.contain(CGRect(x: 600, y: 300, width: 380, height: 700), in: visible)
        XCTAssertLessThanOrEqual(out.maxY, visible.maxY - m)
        XCTAssertGreaterThanOrEqual(out.minY, visible.minY + m)
        XCTAssertEqual(out.width, 380)
        // 比屏幕还高
        let tall = DetailPanelFit.contain(CGRect(x: 600, y: 0, width: 380, height: 2000), in: visible)
        XCTAssertLessThanOrEqual(tall.height, visible.height - 2 * m)
        XCTAssertTrue(visible.insetBy(dx: m, dy: m).contains(tall))
        // 已经在里面：原样
        let fine = CGRect(x: 600, y: 100, width: 380, height: 500)
        XCTAssertEqual(DetailPanelFit.contain(fine, in: visible), fine)
    }
}
