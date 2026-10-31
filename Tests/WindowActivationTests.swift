import XCTest

/// 设置窗口在最前、用户在点，却整个显示成非激活的灰色（macOS 27.2 真机反馈）。
final class WindowActivationTests: XCTestCase {

    func testEscalatesRequestThenForceThenPromote() {
        XCTAssertEqual(WindowActivationPlan.step(attempt: 0, isActive: false), .request)
        XCTAssertEqual(WindowActivationPlan.step(attempt: 1, isActive: false), .force)
        XCTAssertEqual(WindowActivationPlan.step(attempt: 2, isActive: false), .promote)
    }

    func testStopsOnceActive() {
        for attempt in 0..<4 {
            XCTAssertNil(WindowActivationPlan.step(attempt: attempt, isActive: true))
        }
    }

    func testGivesUpAfterPromote() {
        XCTAssertNil(WindowActivationPlan.step(attempt: 3, isActive: false))
        XCTAssertNil(WindowActivationPlan.step(attempt: 10, isActive: false))
    }

    func testWaitsArePositiveAndGrow() {
        let request = WindowActivationPlan.wait(after: .request)
        let force = WindowActivationPlan.wait(after: .force)
        let promote = WindowActivationPlan.wait(after: .promote)
        XCTAssertGreaterThan(request, 0)
        XCTAssertLessThanOrEqual(request, force)
        XCTAssertLessThanOrEqual(force, promote)
        XCTAssertLessThan(request + force + promote, 1.5, "三步加起来要在补设 key 的时限之内")
    }

    func testRestoresAccessoryOnlyWhenPromotedAndAllClosed() {
        XCTAssertTrue(WindowActivationPlan.shouldRestoreAccessory(promoted: true, openWindows: 0))
        XCTAssertFalse(WindowActivationPlan.shouldRestoreAccessory(promoted: true, openWindows: 1))
        XCTAssertFalse(WindowActivationPlan.shouldRestoreAccessory(promoted: false, openWindows: 0))
    }

    func testClickActivatesOnlyWhenInactive() {
        XCTAssertTrue(WindowActivationPlan.activateOnClick(isActive: false))
        XCTAssertFalse(WindowActivationPlan.activateOnClick(isActive: true))
    }

    func testHoverDoesNotStealFromSettingsWindow() {
        XCTAssertFalse(FloatingKeyPolicy.mayTakeKey(.hover, needsKeyboard: true, regularWindowIsKey: true))
        XCTAssertTrue(FloatingKeyPolicy.mayTakeKey(.hover, needsKeyboard: true, regularWindowIsKey: false))
    }

    func testClickTakesKeyOnlyWhenTyping() {
        XCTAssertTrue(FloatingKeyPolicy.mayTakeKey(.click, needsKeyboard: true, regularWindowIsKey: true))
        XCTAssertFalse(FloatingKeyPolicy.mayTakeKey(.click, needsKeyboard: false, regularWindowIsKey: false))
    }

    func testAutomaticNeverTakesKey() {
        for regular in [true, false] {
            XCTAssertFalse(FloatingKeyPolicy.mayTakeKey(.automatic, needsKeyboard: true, regularWindowIsKey: regular))
        }
    }
}
