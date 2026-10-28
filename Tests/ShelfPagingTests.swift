import XCTest

final class ShelfPagingTests: XCTestCase {

    // MARK: 设置

    func testDefaultIsHorizontal() {
        XCTAssertEqual(CustomDockSettings().pageDirection, .horizontal)
    }

    func testOldStateDecodesAsHorizontal() throws {
        let settings = try JSONDecoder().decode(CustomDockSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(settings.pageDirection, .horizontal)
    }

    func testUnknownValueFallsBackToHorizontal() throws {
        let data = Data(#"{"pageDirection":"diagonal","swipeOpensPanels":false}"#.utf8)
        let settings = try JSONDecoder().decode(CustomDockSettings.self, from: data)
        XCTAssertEqual(settings.pageDirection, .horizontal)
        XCTAssertFalse(settings.swipeOpensPanels)
    }

    func testRoundTrip() throws {
        var settings = CustomDockSettings()
        settings.pageDirection = .vertical
        let back = try JSONDecoder().decode(CustomDockSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(back.pageDirection, .vertical)
    }

    func testLabels() {
        XCTAssertEqual(ShelfPageDirection.horizontal.label, "左右")
        XCTAssertEqual(ShelfPageDirection.vertical.label, "上下")
    }

    // MARK: Pro

    func testVerticalIsPro() {
        var settings = CustomDockSettings()
        settings.pageDirection = .vertical
        XCTAssertTrue(ProLicenseGate.verticalPagingActive(settings, unlocked: true))
        XCTAssertFalse(ProLicenseGate.verticalPagingActive(settings, unlocked: false))
        settings.pageDirection = .horizontal
        XCTAssertFalse(ProLicenseGate.verticalPagingActive(settings, unlocked: true))
        XCTAssertTrue(ProFeatures.Setting.allCases.contains(.verticalPaging))
        XCTAssertTrue(ProUnlockHighlights.allItems.contains(.setting(.verticalPaging)))
        XCTAssertEqual(ProUnlockHighlights.title(.setting(.verticalPaging)), "上下翻页")
    }

    func testVerticalPagingActiveByDirectionFollowsUnlock() {
        // 滚动事件里每次现算：试用到期立刻按左右，解锁立刻恢复上下。
        XCTAssertTrue(ProLicenseGate.verticalPagingActive(direction: .vertical, unlocked: true))
        XCTAssertFalse(ProLicenseGate.verticalPagingActive(direction: .vertical, unlocked: false))
        XCTAssertFalse(ProLicenseGate.verticalPagingActive(direction: .horizontal, unlocked: true))
        var settings = CustomDockSettings()
        for direction in ShelfPageDirection.allCases {
            settings.pageDirection = direction
            for unlocked in [true, false] {
                XCTAssertEqual(ProLicenseGate.verticalPagingActive(settings, unlocked: unlocked),
                               ProLicenseGate.verticalPagingActive(direction: direction, unlocked: unlocked))
            }
        }
    }

    // MARK: 翻页后的尾巴

    func testTailPassesBeforeAnyPage() {
        let tail = ShelfPagingTail()
        XCTAssertFalse(tail.swallows(phased: true, momentum: false))
        XCTAssertFalse(tail.swallows(phased: false, momentum: true))
    }

    func testTailSwallowsRestOfGestureAndMomentumAfterPage() {
        var tail = ShelfPagingTail()
        tail.begin()
        tail.didPage()
        // 翻页后指针下变成小组件、或新布局放不下：剩下的手指事件和惯性都不交给滚动。
        XCTAssertTrue(tail.swallows(phased: true, momentum: false))
        XCTAssertTrue(tail.swallows(phased: false, momentum: true))
    }

    func testTailNeverSwallowsMouseWheel() {
        var tail = ShelfPagingTail()
        tail.didPage()
        XCTAssertFalse(tail.swallows(phased: false, momentum: false))
    }

    func testTailResetsOnNextGesture() {
        var tail = ShelfPagingTail()
        tail.didPage()
        tail.begin()
        XCTAssertFalse(tail.swallows(phased: true, momentum: false))
        XCTAssertFalse(tail.swallows(phased: false, momentum: true))
    }

    // MARK: 哪条扩展栏

    func testVerticalOnlyOnHorizontalShelves() {
        XCTAssertTrue(ShelfPaging.verticalApplies(direction: .vertical, shelfIsVertical: false))
        XCTAssertFalse(ShelfPaging.verticalApplies(direction: .vertical, shelfIsVertical: true))
        XCTAssertFalse(ShelfPaging.verticalApplies(direction: .horizontal, shelfIsVertical: false))
    }

    // MARK: 方向

    func testFingerUpIsNextPageWithNaturalScrolling() {
        // 自然滚动：手指往上，dy 为负。
        let delta = ShelfPaging.verticalDelta(dy: -10, inverted: true)
        XCTAssertLessThan(delta, 0)
        var gesture = LayoutGesture()
        XCTAssertNil(gesture.feed(delta, precise: true, at: 0))
        XCTAssertEqual(gesture.feed(delta * 4, precise: true, at: 0.01), 1)
    }

    func testFingerUpIsNextPageWithoutNaturalScrolling() {
        // 不开自然滚动：手指往上，dy 为正。
        XCTAssertLessThan(ShelfPaging.verticalDelta(dy: 10, inverted: false), 0)
    }

    func testFingerDownIsPreviousPage() {
        XCTAssertGreaterThan(ShelfPaging.verticalDelta(dy: 10, inverted: true), 0)
        XCTAssertGreaterThan(ShelfPaging.verticalDelta(dy: -10, inverted: false), 0)
    }

    // MARK: 归属

    private func route(dx: Double = 0, dy: Double = 0, precise: Bool = true, command: Bool = false,
                       overflowing: Bool = false, vertical: Bool, overPanel: Bool = false) -> ShelfPaging.Route {
        ShelfPaging.route(dx: dx, dy: dy, precise: precise, inverted: true, command: command,
                          overflowing: overflowing, vertical: vertical, overPanelTarget: overPanel)
    }

    func testVerticalModeUprightSwipePages() {
        // 自然滚动：手指往上 dy 为负，下一页（增量为负）。
        XCTAssertEqual(route(dy: -6, vertical: true), .page(-6))
        XCTAssertEqual(route(dx: 1, dy: 6, vertical: true), .page(6))
    }

    func testVerticalModeOverflowingShelfStillPages() {
        XCTAssertEqual(route(dy: -6, overflowing: true, vertical: true), .page(-6))
    }

    func testVerticalModeSidewaysSwipeScrolls() {
        XCTAssertEqual(route(dx: 8, dy: 1, vertical: true), .pass)
    }

    func testVerticalModeDiagonalIsNeither() {
        XCTAssertEqual(route(dx: 5, dy: 6, vertical: true), .pass)
    }

    func testVerticalModeLeavesWidgetsToPanelSwipe() {
        XCTAssertEqual(route(dy: -6, vertical: true, overPanel: true), .pass)
    }

    func testVerticalModeMouseWheelDoesNotPage() {
        XCTAssertEqual(route(dy: -1, precise: false, vertical: true), .pass)
    }

    func testCommandAlwaysPages() {
        XCTAssertEqual(route(dy: -1, precise: false, command: true, vertical: true), .page(-1))
        XCTAssertEqual(route(dx: 3, dy: 1, command: true, vertical: false), .page(3))
    }

    func testHorizontalModeUnchanged() {
        XCTAssertEqual(route(dx: 8, dy: 1, vertical: false), .page(8))
        XCTAssertEqual(route(dx: 8, dy: 1, overflowing: true, vertical: false), .pass)
        XCTAssertEqual(route(dy: -6, vertical: false), .pass)
        XCTAssertEqual(route(dx: 8, dy: 1, precise: false, vertical: false), .pass)
    }

    // MARK: 动画

    func testEntryOffset() {
        XCTAssertEqual(ShelfPaging.entryOffset(step: 1, reduceMotion: false), ShelfPaging.slideDistance)
        XCTAssertEqual(ShelfPaging.entryOffset(step: -1, reduceMotion: false), -ShelfPaging.slideDistance)
        XCTAssertEqual(ShelfPaging.entryOffset(step: 0, reduceMotion: false), 0)
        XCTAssertEqual(ShelfPaging.entryOffset(step: 1, reduceMotion: true), 0)
    }
}
