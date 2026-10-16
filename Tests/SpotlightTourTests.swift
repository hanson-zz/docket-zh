import CoreGraphics
import XCTest

/// 新手引导的聚光灯导览。
final class SpotlightTourTests: XCTestCase {
    private let bounds = CGRect(x: 0, y: 0, width: 560, height: 640)

    func testStopsHaveUniqueIDsAndText() {
        let stops = SpotlightTour.onboarding
        XCTAssertGreaterThanOrEqual(stops.count, 2)
        XCTAssertEqual(Set(stops.map(\.id)).count, stops.count)
        for stop in stops {
            XCTAssertFalse(stop.title.isEmpty)
            XCTAssertFalse(stop.message.isEmpty)
        }
    }

    func testCutoutGrowsAndStaysInside() {
        let hole = SpotlightTour.cutout(CGRect(x: 100, y: 100, width: 50, height: 20), padding: 6, in: bounds)
        XCTAssertEqual(hole, CGRect(x: 94, y: 94, width: 62, height: 32))
        let edge = SpotlightTour.cutout(CGRect(x: 0, y: 0, width: 30, height: 30), padding: 10, in: bounds)
        XCTAssertEqual(edge.minX, 0)
        XCTAssertEqual(edge.minY, 0)
        XCTAssertEqual(SpotlightTour.cutout(CGRect(x: 900, y: 900, width: 5, height: 5), padding: 1, in: bounds), .zero)
    }

    func testCalloutGoesBelowWhenRoomElseAbove() {
        let top = CGRect(x: 100, y: 20, width: 300, height: 20)
        XCTAssertEqual(SpotlightTour.placement(cutout: top, calloutHeight: 120, gap: 12, in: bounds), .below)
        let bottom = CGRect(x: 30, y: 580, width: 500, height: 48)
        XCTAssertEqual(SpotlightTour.placement(cutout: bottom, calloutHeight: 120, gap: 12, in: bounds), .above)
    }

    func testCalloutCenterIsClampedToWindow() {
        let size = CGSize(width: 280, height: 120)
        let right = CGRect(x: 500, y: 20, width: 40, height: 20)
        let c = SpotlightTour.calloutCenter(cutout: right, size: size, gap: 12, margin: 16, in: bounds)
        XCTAssertEqual(c.x, 560 - 16 - 140)
        XCTAssertEqual(c.y, 40 + 12 + 60)
        let bottom = CGRect(x: 30, y: 580, width: 500, height: 48)
        let b = SpotlightTour.calloutCenter(cutout: bottom, size: size, gap: 12, margin: 16, in: bounds)
        XCTAssertEqual(b.y, 580 - 12 - 60)
        XCTAssertEqual(b.x, bottom.midX)
    }

    func testCounterAndNext() {
        XCTAssertEqual(SpotlightTour.counter(index: 0, total: 3), "1 / 3")
        XCTAssertEqual(SpotlightTour.counter(index: 7, total: 3), "3 / 3")
        XCTAssertEqual(SpotlightTour.next(after: 0, total: 3), 1)
        XCTAssertNil(SpotlightTour.next(after: 2, total: 3))
    }
}
