import XCTest

/// A top shelf and 灵动提示 never cover each other.
///
/// AppKit screen coordinates, y running up. The main display is a 1512x982
/// notched screen whose menu bar (and notch) is 37pt tall; a second, plain
/// display sits to its right.
final class IslandAvoidanceTests: XCTestCase {

    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let other = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
    private let menuBar: CGFloat = 37
    private var ceiling: CGFloat { screen.maxY - menuBar }
    private let shelf = CGSize(width: 900, height: 80)

    private var islandPanel: CGRect {
        IslandLayout.panelFrame(screen: screen, visibleMaxY: ceiling, notch: menuBar)
    }
    private var island: CGRect { IslandLayout.occupied(panel: islandPanel) }

    private var bounds: CGRect {
        CGRect(x: screen.minX, y: screen.minY, width: screen.width, height: ceiling - screen.minY)
    }

    /// Shares some area, so two rects that only touch along an edge do not
    /// count; the spacing is what keeps them apart, not a hairline.
    private func overlaps(_ a: CGRect, _ b: CGRect) -> Bool {
        !a.intersection(b).isEmpty
    }

    private func topOrigin(inset: CGFloat = 6) -> CGPoint {
        Geometry.shelfOrigin(edge: .top, size: shelf, bounds: bounds, inset: inset)
    }

    // MARK: Where the capsule is

    func testCapsuleHangsUnderTheNotchCentred() {
        let panel = islandPanel
        XCTAssertEqual(panel.size, IslandLayout.panelSize)
        XCTAssertEqual(panel.maxY, screen.maxY - menuBar - 4)
        XCTAssertEqual(panel.midX, screen.midX)
    }

    func testWithoutANotchItHangsUnderTheMenuBar() {
        let visible: CGFloat = screen.maxY - 24
        let panel = IslandLayout.panelFrame(screen: screen, visibleMaxY: visible, notch: 0)
        XCTAssertEqual(panel.maxY, visible - 6)
        XCTAssertEqual(panel.midX, screen.midX)
    }

    func testFootprintIsTheCapsuleAndItsShadowAcrossTheWholeWindow() {
        let panel = islandPanel
        let footprint = IslandLayout.occupied(panel: panel)
        XCTAssertEqual(footprint.maxY, panel.maxY, "grows from the window's top edge")
        XCTAssertEqual(footprint.height, IslandLayout.capsuleHeight + IslandLayout.shadowAllowance)
        XCTAssertEqual(footprint.minX, panel.minX)
        XCTAssertEqual(footprint.width, panel.width)
        XCTAssertTrue(panel.contains(footprint))
        // The widest capsule, a meeting title capped at 360pt plus 16pt of
        // padding each side, fits inside it.
        XCTAssertGreaterThanOrEqual(footprint.width, 360 + 32)
    }

    // MARK: The shelf steps aside

    func testAnOrdinaryTopShelfWouldMeetTheCapsule() {
        let frame = CGRect(origin: topOrigin(), size: shelf)
        XCTAssertTrue(frame.intersects(island), "the reason any of this exists")
        XCTAssertTrue(Geometry.islandDisplaces(edge: .top, shelf: frame, island: island, screen: screen))
    }

    func testTopShelfMovesBelowTheCapsuleWithSpacing() {
        let origin = topOrigin()
        let moved = Geometry.avoidingIsland(edge: .top, origin: origin, size: shelf,
                                            island: island, screen: screen, floor: bounds.minY)
        let frame = CGRect(origin: moved, size: shelf)
        XCTAssertEqual(moved.x, origin.x, "straight down, still centred")
        XCTAssertEqual(frame.maxY, island.minY - Geometry.islandSpacing, accuracy: 1e-9)
        XCTAssertFalse(overlaps(frame, island))
    }

    func testEveryEdgeGapAndWidthEndsClear() {
        for inset: CGFloat in [0, 6, 20, 60] {
            for width: CGFloat in [120, 440, 900, 1500] {
                let size = CGSize(width: width, height: 64)
                let origin = Geometry.shelfOrigin(edge: .top, size: size, bounds: bounds, inset: inset)
                let moved = Geometry.avoidingIsland(edge: .top, origin: origin, size: size,
                                                    island: island, screen: screen, floor: bounds.minY)
                let frame = CGRect(origin: moved, size: size)
                XCTAssertFalse(overlaps(frame, island), "inset \(inset), width \(width)")
                XCTAssertLessThanOrEqual(frame.maxY, island.minY - Geometry.islandSpacing + 1e-9)
            }
        }
    }

    func testAShelfAlreadyClearStaysPut() {
        let low = CGPoint(x: topOrigin().x, y: island.minY - 200)
        XCTAssertEqual(Geometry.avoidingIsland(edge: .top, origin: low, size: shelf,
                                               island: island, screen: screen, floor: 0), low)
    }

    func testWithoutTheCapsuleNothingMoves() {
        let origin = topOrigin()
        XCTAssertEqual(Geometry.avoidingIsland(edge: .top, origin: origin, size: shelf,
                                               island: nil, screen: screen, floor: 0), origin)
        XCTAssertFalse(Geometry.islandDisplaces(edge: .top, shelf: CGRect(origin: origin, size: shelf),
                                                island: nil, screen: screen))
    }

    func testOnlyOnTheSameDisplay() {
        // A top shelf on the second display, where the capsule never is.
        let otherBounds = CGRect(x: other.minX, y: other.minY, width: other.width, height: other.height - 24)
        let origin = Geometry.shelfOrigin(edge: .top, size: shelf, bounds: otherBounds, inset: 6)
        XCTAssertNil(Geometry.islandToAvoid(edge: .top, island: island, screen: other))
        XCTAssertEqual(Geometry.avoidingIsland(edge: .top, origin: origin, size: shelf,
                                               island: island, screen: other, floor: 0), origin)
        XCTAssertNotNil(Geometry.islandToAvoid(edge: .top, island: island, screen: screen))
    }

    func testNeverPushedBelowTheFloor() {
        let tiny = CGRect(x: 0, y: 0, width: 800, height: 120)
        let small = CGRect(x: 350, y: 70, width: 100, height: 40)
        let size = CGSize(width: 600, height: 100)
        let moved = Geometry.avoidingIsland(edge: .top, origin: CGPoint(x: 100, y: 10), size: size,
                                            island: small, screen: tiny, floor: 0)
        XCTAssertEqual(moved.y, 0, "clamped to the screen rather than off it")
    }

    // MARK: Other edges are untouched

    func testLeftBottomAndRightIgnoreTheCapsule() {
        for edge in [DockPosition.left, .bottom, .right] {
            let size = edge.isHorizontal ? shelf : CGSize(width: 80, height: 700)
            let origin = Geometry.shelfOrigin(edge: edge, size: size, bounds: bounds, inset: 6)
            // Even a capsule placed right on top of the shelf changes nothing.
            let onTop = CGRect(origin: origin, size: size)
            XCTAssertNil(Geometry.islandToAvoid(edge: edge, island: onTop, screen: screen), "\(edge)")
            XCTAssertEqual(Geometry.avoidingIsland(edge: edge, origin: origin, size: size,
                                                   island: onTop, screen: screen, floor: 0),
                           origin, "\(edge)")
            XCTAssertFalse(Geometry.islandDisplaces(edge: edge, shelf: onTop, island: onTop,
                                                    screen: screen), "\(edge)")
            let zones = Geometry.revealZones(edge: edge, shelf: onTop, screen: screen,
                                             ceiling: ceiling, depth: 3, island: onTop)
            XCTAssertEqual(zones, [Geometry.revealZone(edge: edge, shelf: onTop, screen: screen,
                                                       ceiling: ceiling, depth: 3)], "\(edge)")
        }
    }

    // MARK: The reveal band

    func testRevealBandIsUnchangedWithoutTheCapsule() {
        let frame = CGRect(origin: topOrigin(), size: shelf)
        let zones = Geometry.revealZones(edge: .top, shelf: frame, screen: screen,
                                         ceiling: ceiling, depth: 6, island: nil)
        XCTAssertEqual(zones, [Geometry.revealZone(edge: .top, shelf: frame, screen: screen,
                                                   ceiling: ceiling, depth: 6)])
    }

    func testRevealBandStepsAroundTheCapsule() {
        let frame = CGRect(origin: topOrigin(), size: shelf)
        let band = Geometry.revealZone(edge: .top, shelf: frame, screen: screen, ceiling: ceiling, depth: 6)
        XCTAssertTrue(band.intersects(island), "the plain band would reach into the capsule")

        let zones = Geometry.revealZones(edge: .top, shelf: frame, screen: screen,
                                         ceiling: ceiling, depth: 6, island: island)
        XCTAssertEqual(zones.count, 3)
        for zone in zones {
            XCTAssertFalse(overlaps(zone, island), "\(zone)")
            XCTAssertGreaterThanOrEqual(zone.minX, frame.minX)
            XCTAssertLessThanOrEqual(zone.maxX, frame.maxX)
        }
        // Still covers the shelf's whole width, so it can always be reached.
        XCTAssertEqual(zones.map(\.width).reduce(0, +), frame.width, accuracy: 1e-9)
        // Either side stays under the menu bar; the middle hangs under the capsule.
        XCTAssertEqual(zones[0].maxY, ceiling)
        XCTAssertEqual(zones[2].maxY, ceiling)
        XCTAssertEqual(zones[1].maxY, island.minY)
        XCTAssertEqual(zones[1].minX, island.minX)
        XCTAssertEqual(zones[1].maxX, island.maxX)
        // Hovering the capsule does not bring the shelf out.
        XCTAssertFalse(zones.contains { $0.contains(CGPoint(x: island.midX, y: island.maxY - 2)) })
        XCTAssertTrue(zones.contains { $0.contains(CGPoint(x: island.midX, y: island.minY - 2)) })
    }

    func testANarrowShelfKeepsOnlyTheBandUnderTheCapsule() {
        let size = CGSize(width: 300, height: 64)
        let frame = CGRect(origin: Geometry.shelfOrigin(edge: .top, size: size, bounds: bounds, inset: 6),
                           size: size)
        let zones = Geometry.revealZones(edge: .top, shelf: frame, screen: screen,
                                         ceiling: ceiling, depth: 6, island: island)
        XCTAssertEqual(zones.count, 1)
        XCTAssertEqual(zones[0].minX, frame.minX)
        XCTAssertEqual(zones[0].width, frame.width)
        XCTAssertEqual(zones[0].maxY, island.minY)
        XCTAssertFalse(overlaps(zones[0], island))
    }

    func testRevealBandOnAnotherDisplayIsUnchanged() {
        let frame = CGRect(x: other.midX - 450, y: other.maxY - 110, width: 900, height: 80)
        let zones = Geometry.revealZones(edge: .top, shelf: frame, screen: other,
                                         ceiling: other.maxY - 24, depth: 6, island: island)
        XCTAssertEqual(zones, [Geometry.revealZone(edge: .top, shelf: frame, screen: other,
                                                   ceiling: other.maxY - 24, depth: 6)])
    }

    // MARK: What opens from the shelf

    func testPopupsOpenBelowAShelfThatSteppedAside() {
        let moved = Geometry.avoidingIsland(edge: .top, origin: topOrigin(), size: shelf,
                                            island: island, screen: screen, floor: bounds.minY)
        let frame = CGRect(origin: moved, size: shelf)
        let anchor = CGPoint(x: frame.midX, y: frame.maxY - 40)
        let popup = CGSize(width: 500, height: 300)
        let origin = Geometry.popupOrigin(edge: .top, anchor: anchor, size: popup, gap: 10)
        XCTAssertFalse(overlaps(CGRect(origin: origin, size: popup), island))
        let beside = Geometry.besideShelfOrigin(edge: .top, shelf: frame, size: popup, gap: 4)
        XCTAssertFalse(overlaps(CGRect(origin: beside, size: popup), island))
    }

    func testHiddenTopShelfPeekStaysAboveTheCapsule() {
        // While hidden only a 3pt handle shows at the bezel, inside the
        // menu bar, well above the capsule under the notch.
        let shown = topOrigin()
        let hidden = Geometry.hiddenShelfOrigin(edge: .top, shown: shown, size: shelf, screen: screen, peek: 3)
        let visiblePart = CGRect(origin: hidden, size: shelf).intersection(screen)
        XCTAssertFalse(overlaps(visiblePart, island))
    }
}
