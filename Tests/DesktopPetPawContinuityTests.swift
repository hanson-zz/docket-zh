import Foundation
import XCTest

final class DesktopPetPawContinuityTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 100)

    private func holdingBoth() -> DesktopPetMousePaws {
        var paws = DesktopPetMousePaws()
        for frame in 0...20 {
            paws.update(buttons: 3, now: start.addingTimeInterval(Double(frame) / 20), enabled: true)
        }
        return paws
    }

    func testCoalescedHoldKeepsBothPawsAtRestWithoutRestartingSmoothRefresh() {
        var paws = holdingBoth()
        for gap in [1.7, 2.5, 6.0] {
            paws.update(buttons: 3, now: start.addingTimeInterval(gap), enabled: true)
            XCTAssertEqual(paws.left, 0.9)
            XCTAssertEqual(paws.right, 0.9)
            XCTAssertFalse(paws.needsSmooth)
        }
    }

    func testFreshButtonStateWinsAfterLongGap() {
        var paws = holdingBoth()
        paws.update(buttons: 1, now: start.addingTimeInterval(2), enabled: true)
        XCTAssertEqual(paws.left, 0.9)
        XCTAssertEqual(paws.right, 0)
        XCTAssertFalse(paws.needsSmooth)
        paws.update(buttons: 0, now: start.addingTimeInterval(3), enabled: true)
        XCTAssertEqual(paws.left, 0)
        XCTAssertEqual(paws.right, 0)
        XCTAssertFalse(paws.needsSmooth)
    }

    func testDisablingStillClearsHeldPawsAndNewPressStillEasesIn() {
        var paws = holdingBoth()
        paws.update(buttons: 3, now: start.addingTimeInterval(10), enabled: false)
        XCTAssertEqual(paws, DesktopPetMousePaws())
        paws.update(buttons: 1, now: start.addingTimeInterval(20), enabled: true)
        XCTAssertEqual(paws.left, 0)
        XCTAssertTrue(paws.needsSmooth)
        paws.update(buttons: 1, now: start.addingTimeInterval(20.05), enabled: true)
        XCTAssertGreaterThan(paws.left, 0)
        XCTAssertLessThan(paws.left, 0.9)
        XCTAssertEqual(paws.right, 0)
    }

    func testBackwardsClockClearsPoseAndNormalReleaseRemainsSmooth() {
        var paws = holdingBoth()
        paws.update(buttons: 3, now: start.addingTimeInterval(-1), enabled: true)
        XCTAssertEqual(paws.left, 0)
        XCTAssertEqual(paws.right, 0)
        paws = holdingBoth()
        paws.update(buttons: 0, now: start.addingTimeInterval(1.05), enabled: true)
        XCTAssertGreaterThan(paws.left, 0)
        XCTAssertLessThan(paws.left, 0.9)
        XCTAssertTrue(paws.needsSmooth)
    }
}
