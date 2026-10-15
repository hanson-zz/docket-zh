import XCTest

/// The shelf on the top edge, under the menu bar.
///
/// All in AppKit screen coordinates, where y runs up: a screen's top is its
/// `maxY`. The numbers model a 1512x982 notched display whose menu bar (and
/// notch) is 37pt tall, so its `visibleFrame` stops at 945.
final class TopEdgeTests: XCTestCase {

    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let menuBar: CGFloat = 37
    private var visibleMaxY: CGFloat { screen.maxY - menuBar }
    private let shelf = CGSize(width: 600, height: 80)

    // MARK: The edge itself

    func testTopIsAHorizontalEdgeTheSystemDockCannotTake() {
        XCTAssertTrue(DockPosition.top.isHorizontal)
        XCTAssertFalse(DockPosition.top.isVertical)
        XCTAssertFalse(DockPosition.top.isSystemDockEdge)
        XCTAssertTrue(DockPosition.top.opensDownward)
        for edge in [DockPosition.left, .bottom, .right] {
            XCTAssertTrue(edge.isSystemDockEdge, "\(edge)")
            XCTAssertFalse(edge.opensDownward, "\(edge)")
        }
        XCTAssertTrue(DockPosition.left.isVertical)
        XCTAssertTrue(DockPosition.right.isVertical)
        XCTAssertFalse(DockPosition.bottom.isVertical)
    }

    func testSettingsOrderIsLeftTopBottomRight() {
        XCTAssertEqual(DockPosition.allCases, [.left, .top, .bottom, .right])
        XCTAssertEqual(DockPosition.allCases.map(\.displayName), ["左侧", "顶部", "底部", "右侧"])
    }

    func testSavedEdgesKeepTheirRawValues() throws {
        // Older saves wrote these three words; they must still decode as before.
        let cases: [(String, DockPosition)] = [("left", .left), ("bottom", .bottom),
                                               ("right", .right), ("top", .top)]
        for (raw, edge) in cases {
            let decoded = try JSONDecoder().decode([DockPosition].self, from: Data("[\"\(raw)\"]".utf8))
            XCTAssertEqual(decoded, [edge])
            XCTAssertEqual(edge.rawValue, raw)
        }
    }

    func testATopShelfUsesTheHorizontalTileMetrics() {
        XCTAssertEqual(Geometry.widgetCross(.top), Geometry.widgetCross(.bottom))
        for scale in [0.3, 0.5, 0.9] {
            XCTAssertEqual(Geometry.resizedScale(scale, delta: 10, position: .top),
                           Geometry.resizedScale(scale, delta: 10, position: .bottom), accuracy: 1e-12)
            XCTAssertEqual(Geometry.resizedScale(scale, delta: 10, position: .top, hasWidgets: false),
                           Geometry.resizedScale(scale, delta: 10, position: .bottom, hasWidgets: false),
                           accuracy: 1e-12)
        }
    }

    // MARK: The ceiling

    func testCeilingIsTheUndersideOfTheMenuBar() {
        XCTAssertEqual(Geometry.topCeiling(frameMaxY: screen.maxY, visibleMaxY: visibleMaxY,
                                           menuBarHeight: menuBar), 945)
    }

    func testCeilingStillClearsAMenuBarThatHidesItself() {
        // An auto-hidden menu bar gives the whole height back to visibleFrame.
        XCTAssertEqual(Geometry.topCeiling(frameMaxY: screen.maxY, visibleMaxY: screen.maxY,
                                           menuBarHeight: 24), screen.maxY - 24)
    }

    func testCeilingOnASecondDisplayAboveTheMain() {
        let upper = CGRect(x: -200, y: 982, width: 1920, height: 1080)
        XCTAssertEqual(Geometry.topCeiling(frameMaxY: upper.maxY, visibleMaxY: upper.maxY - 24,
                                           menuBarHeight: 24), upper.maxY - 24)
    }

    // MARK: Where the shelf sits

    private var bounds: CGRect {
        CGRect(x: 0, y: 0, width: screen.width, height: visibleMaxY)
    }

    func testTopShelfHangsUnderTheMenuBarCentred() {
        let origin = Geometry.shelfOrigin(edge: .top, size: shelf, bounds: bounds, inset: 6)
        let frame = CGRect(origin: origin, size: shelf)
        XCTAssertEqual(frame.maxY, visibleMaxY - 6, accuracy: 1e-9, "6pt under the menu bar")
        XCTAssertEqual(frame.midX, screen.midX, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(frame.maxY, visibleMaxY, "never over the menu bar")
    }

    func testTopShelfWithNoGapTouchesTheMenuBar() {
        let origin = Geometry.shelfOrigin(edge: .top, size: shelf, bounds: bounds, inset: 0)
        XCTAssertEqual(origin.y + shelf.height, visibleMaxY, accuracy: 1e-9)
    }

    func testAnOversizedTopShelfIsClampedOnScreen() {
        let huge = CGSize(width: 2000, height: 80)
        let origin = Geometry.shelfOrigin(edge: .top, size: huge, bounds: bounds, inset: 6)
        XCTAssertEqual(origin.x, bounds.minX)
        XCTAssertLessThanOrEqual(origin.y + huge.height, visibleMaxY)
    }

    func testTopShelfOnAnOffsetDisplay() {
        let other = CGRect(x: 1512, y: -300, width: 1920, height: 1056)
        let origin = Geometry.shelfOrigin(edge: .top, size: shelf, bounds: other, inset: 6)
        XCTAssertEqual(origin.x + shelf.width / 2, other.midX, accuracy: 1e-9)
        XCTAssertEqual(origin.y + shelf.height, other.maxY - 6, accuracy: 1e-9)
    }

    func testTheOtherEdgesAreUnchanged() {
        let bottom = Geometry.shelfOrigin(edge: .bottom, size: shelf, bounds: bounds, inset: 6)
        XCTAssertEqual(bottom, CGPoint(x: bounds.midX - 300, y: 6))
        let side = CGSize(width: 80, height: 500)
        let left = Geometry.shelfOrigin(edge: .left, size: side, bounds: bounds, inset: 6)
        XCTAssertEqual(left, CGPoint(x: 6, y: bounds.midY - 250))
        let right = Geometry.shelfOrigin(edge: .right, size: side, bounds: bounds, inset: 6)
        XCTAssertEqual(right, CGPoint(x: bounds.maxX - 86, y: bounds.midY - 250))
    }

    // MARK: Hiding and revealing

    func testAHiddenTopShelfLeavesPastTheTopBezel() {
        let shown = Geometry.shelfOrigin(edge: .top, size: shelf, bounds: bounds, inset: 6)
        let hidden = Geometry.hiddenShelfOrigin(edge: .top, shown: shown, size: shelf,
                                                screen: screen, peek: 0)
        XCTAssertEqual(hidden.x, shown.x, "slides straight up")
        XCTAssertEqual(hidden.y, screen.maxY, "entirely off the screen")
        let peeking = Geometry.hiddenShelfOrigin(edge: .top, shown: shown, size: shelf,
                                                 screen: screen, peek: 3)
        XCTAssertEqual(peeking.y, screen.maxY - 3)
    }

    func testHiddenBottomShelfIsUnchanged() {
        let shown = CGPoint(x: 400, y: 6)
        let hidden = Geometry.hiddenShelfOrigin(edge: .bottom, shown: shown, size: shelf,
                                                screen: screen, peek: 3)
        XCTAssertEqual(hidden, CGPoint(x: 400, y: -77))
    }

    func testTopRevealZoneIsABandUnderTheMenuBar() {
        let shown = Geometry.shelfOrigin(edge: .top, size: shelf, bounds: bounds, inset: 6)
        let frame = CGRect(origin: shown, size: shelf)
        let zone = Geometry.revealZone(edge: .top, shelf: frame, screen: screen,
                                       ceiling: visibleMaxY, depth: 6)
        XCTAssertEqual(zone.maxY, visibleMaxY, "hangs from the menu bar's underside")
        XCTAssertEqual(zone.height, 6)
        XCTAssertEqual(zone.minX, frame.minX)
        XCTAssertEqual(zone.width, frame.width)
        // The menu bar itself, where an auto-hidden menu bar reveals, is clear.
        XCTAssertFalse(zone.contains(CGPoint(x: frame.midX, y: screen.maxY - 1)))
        XCTAssertFalse(zone.contains(CGPoint(x: frame.midX, y: visibleMaxY + 1)))
        XCTAssertTrue(zone.contains(CGPoint(x: frame.midX, y: visibleMaxY - 2)))
    }

    func testBottomRevealZoneStillRunsAlongTheBezel() {
        let frame = CGRect(x: 456, y: 6, width: 600, height: 80)
        let zone = Geometry.revealZone(edge: .bottom, shelf: frame, screen: screen,
                                       ceiling: visibleMaxY, depth: 3)
        XCTAssertEqual(zone, CGRect(x: 456, y: 0, width: 600, height: 3))
    }

    // MARK: Popups open away from the shelf

    func testPopupsOpenDownwardsFromATopShelf() {
        let anchor = CGPoint(x: 700, y: 850)
        let size = CGSize(width: 300, height: 200)
        let origin = Geometry.popupOrigin(edge: .top, anchor: anchor, size: size, gap: 10)
        XCTAssertEqual(origin.y + size.height, anchor.y - 10, accuracy: 1e-9, "entirely below the tile")
        XCTAssertEqual(origin.x + size.width / 2, anchor.x, accuracy: 1e-9, "centred on it")
    }

    func testPopupsOpenUpwardsFromABottomShelf() {
        let anchor = CGPoint(x: 700, y: 90)
        let size = CGSize(width: 300, height: 200)
        let origin = Geometry.popupOrigin(edge: .bottom, anchor: anchor, size: size, gap: 10)
        XCTAssertEqual(origin.y, anchor.y + 10, accuracy: 1e-9)
    }

    func testTopAndBottomPopupsMirrorEachOther() {
        let size = CGSize(width: 240, height: 120)
        let anchor = CGPoint(x: 500, y: 500)
        let up = CGRect(origin: Geometry.popupOrigin(edge: .bottom, anchor: anchor, size: size, gap: 12),
                        size: size)
        let down = CGRect(origin: Geometry.popupOrigin(edge: .top, anchor: anchor, size: size, gap: 12),
                          size: size)
        XCTAssertEqual(up.minY - anchor.y, anchor.y - down.maxY, accuracy: 1e-9)
        XCTAssertEqual(up.midX, down.midX, accuracy: 1e-9)
    }

    func testSidePopupsAreUnchanged() {
        let size = CGSize(width: 240, height: 120)
        let anchor = CGPoint(x: 100, y: 500)
        XCTAssertEqual(Geometry.popupOrigin(edge: .left, anchor: anchor, size: size, gap: 2),
                       CGPoint(x: 102, y: 440))
        XCTAssertEqual(Geometry.popupOrigin(edge: .right, anchor: anchor, size: size, gap: 2),
                       CGPoint(x: -142, y: 440))
    }

    func testANameBesideATopShelfSitsBelowIt() {
        let frame = CGRect(x: 456, y: 859, width: 600, height: 80)
        let size = CGSize(width: 120, height: 24)
        let origin = Geometry.besideShelfOrigin(edge: .top, shelf: frame, size: size, gap: 4)
        XCTAssertEqual(origin.y + size.height, frame.minY - 4, accuracy: 1e-9)
        XCTAssertEqual(origin.x + size.width / 2, frame.midX, accuracy: 1e-9)
    }

    func testTailOffsetOnATopShelfFollowsTheTileAlongX() {
        let size = CGSize(width: 300, height: 200)
        let anchor = CGPoint(x: 60, y: 850)
        // Clamped against the left of the screen: the panel's middle is at
        // 158, so the tail reaches 98pt back to the tile.
        let placed = CGPoint(x: 8, y: 640)
        XCTAssertEqual(Geometry.popupTailOffset(edge: .top, anchor: anchor, placed: placed, size: size),
                       -98, accuracy: 1e-9)
        XCTAssertEqual(Geometry.popupTailOffset(edge: .top, anchor: anchor, placed: placed, size: size),
                       Geometry.popupTailOffset(edge: .bottom, anchor: anchor, placed: placed, size: size))
    }
}
