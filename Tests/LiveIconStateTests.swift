import XCTest

final class LiveIconStateTests: XCTestCase {
    func testProgressClampsToVisibleRange() {
        XCTAssertEqual(LiveIconState.running(progress: -0.3).normalizedProgress, 0)
        XCTAssertEqual(LiveIconState.running(progress: 0.65).normalizedProgress, 0.65)
        XCTAssertEqual(LiveIconState.running(progress: 1.7).normalizedProgress, 1)
        XCTAssertNil(LiveIconState.running(progress: .nan).normalizedProgress)
        XCTAssertNil(LiveIconState.running(progress: .infinity).normalizedProgress)
        XCTAssertNil(LiveIconState.running(progress: nil).normalizedProgress)
        XCTAssertNil(LiveIconState.idle.normalizedProgress)
    }

    func testRunningStateIsOnlyActiveState() {
        XCTAssertTrue(LiveIconState.running(progress: nil).isActive)
        XCTAssertFalse(LiveIconState.idle.isActive)
        XCTAssertFalse(LiveIconState.completed.isActive)
        XCTAssertFalse(LiveIconState.attention.isActive)
    }

    func testMotionRespectsAccessibilityAndPower() {
        XCTAssertEqual(LiveIconPolicy().presentation(for: .running(progress: nil)), .animatedProgress)
        XCTAssertEqual(LiveIconPolicy(reduceMotion: true).presentation(for: .running(progress: 0.5)), .staticProgress)
        XCTAssertEqual(LiveIconPolicy(lowPowerMode: true).presentation(for: .running(progress: 0.5)), .staticProgress)
        XCTAssertEqual(LiveIconPolicy(enabled: false).presentation(for: .completed), .staticIcon)
    }

    func testCompletedAndAttentionAreNotContinuousAnimations() {
        let policy = LiveIconPolicy()
        XCTAssertEqual(policy.presentation(for: .idle), .staticIcon)
        XCTAssertEqual(policy.presentation(for: .completed), .completionMark)
        XCTAssertEqual(policy.presentation(for: .attention), .attentionMark)
    }
}
