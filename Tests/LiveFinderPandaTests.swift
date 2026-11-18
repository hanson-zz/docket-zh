import XCTest
@testable import Docket

final class LiveFinderPandaTests: XCTestCase {
    /// 参考时间原点：离原点近，Date 的精度够用。
    private let s0 = Date(timeIntervalSinceReferenceDate: 0)

    /// 可复现的随机数，眨眼的测试用。
    private struct SplitMix64: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    private func inside(_ p: LiveFinderFace.Point, slack: Double = 1e-9) -> Bool {
        let t = LiveFinderFace.travel
        return (p.x / t.x) * (p.x / t.x) + (p.y / t.y) * (p.y / t.y) <= 1 + slack
    }

    // MARK: 尺寸

    func testPupilNeverLeavesTheSocket() {
        let t = LiveFinderFace.travel, r = LiveFinderFace.pupilRadius, socket = LiveFinderFace.socketRadius
        // 走到头时瞳孔边缘离眼眶还留着边距。
        XCTAssertLessThanOrEqual(t.x + r + 4, socket.x)
        XCTAssertLessThanOrEqual(t.y + r + 4, socket.y)
        XCTAssertGreaterThan(t.x, 0)
        XCTAssertGreaterThan(t.y, 0)
    }

    // MARK: 瞳孔往哪看

    func testPointerOnTheEyeKeepsThePupilCentered() {
        XCTAssertEqual(LiveFinderFace.pupilTarget(dx: 0, dy: 0), .zero)
        XCTAssertEqual(LiveFinderFace.pupilTarget(dx: .nan, dy: 3), .zero)
    }

    func testFarPointerPushesThePupilToTheEdge() {
        let right = LiveFinderFace.pupilTarget(dx: 5000, dy: 0)
        XCTAssertEqual(right.x, LiveFinderFace.travel.x, accuracy: 1e-9)
        XCTAssertEqual(right.y, 0, accuracy: 1e-9)
        let down = LiveFinderFace.pupilTarget(dx: 0, dy: 5000)
        XCTAssertEqual(down.y, LiveFinderFace.travel.y, accuracy: 1e-9)
        let left = LiveFinderFace.pupilTarget(dx: -5000, dy: 0)
        XCTAssertEqual(left.x, -LiveFinderFace.travel.x, accuracy: 1e-9)
    }

    func testNearPointerMovesLessThanFarPointer() {
        let near = LiveFinderFace.pupilTarget(dx: 20, dy: 0).x
        let far = LiveFinderFace.pupilTarget(dx: 200, dy: 0).x
        XCTAssertGreaterThan(near, 0)
        XCTAssertLessThan(near, far)
    }

    func testTargetsStayInsideTheTravelEllipse() {
        for i in 0..<72 {
            let a = Double(i) * .pi / 36
            for d in [3.0, 60, 240, 900] {
                XCTAssertTrue(inside(LiveFinderFace.pupilTarget(dx: cos(a) * d, dy: sin(a) * d)))
            }
        }
        let clamped = LiveFinderFace.clampToTravel(.init(x: 100, y: 100))
        XCTAssertTrue(inside(clamped))
        XCTAssertEqual(LiveFinderFace.clampToTravel(.init(x: 1, y: 2)), .init(x: 1, y: 2))
    }

    func testScreenPointerAboveTheIconLooksUp() {
        // 屏幕坐标 y 向上：指针在图标上方很远，瞳孔往原画的上方（y 为负）走。
        let icon = CGRect(x: 100, y: 0, width: 64, height: 64)
        let up = LiveFinderFace.pupilTarget(eye: LiveFinderFace.leftEye, iconFrame: icon,
                                            pointer: CGPoint(x: 100 + 381.0 / 16, y: 5000))
        XCTAssertLessThan(up.y, -LiveFinderFace.travel.y * 0.99)
        XCTAssertEqual(up.x, 0, accuracy: 0.05)
    }

    func testEyeOnScreenFlipsTheCanvas() {
        let icon = CGRect(x: 10, y: 20, width: 1024, height: 1024)
        let p = LiveFinderFace.eyeOnScreen(.init(x: 100, y: 200), iconFrame: icon)
        XCTAssertEqual(p.x, 110, accuracy: 1e-9)
        XCTAssertEqual(p.y, 20 + 1024 - 200, accuracy: 1e-9)
    }

    // MARK: 弹簧

    func testSpringSettlesWithoutOvershoot() {
        var spring = LiveFinderSpring()
        let target = LiveFinderFace.Point(x: 10, y: -6)
        var maxX = 0.0
        for _ in 0..<90 {
            spring.step(toward: target, dt: 1.0 / 30, omega: LiveFinderGaze.followOmega)
            maxX = max(maxX, spring.position.x)
        }
        XCTAssertTrue(spring.isSettled(at: target))
        XCTAssertLessThanOrEqual(maxX, 10 + 0.01)
    }

    func testSpringIgnoresBadSteps() {
        var spring = LiveFinderSpring()
        spring.step(toward: .init(x: 5, y: 5), dt: .nan, omega: 10)
        spring.step(toward: .init(x: 5, y: 5), dt: -1, omega: 10)
        XCTAssertEqual(spring.position, .zero)
    }

    // MARK: 跟随与回正

    func testFirstReadingIsOnlyABaseline() {
        var gaze = LiveFinderGaze()
        let icon = CGRect(x: 0, y: 0, width: 64, height: 64)
        XCTAssertFalse(gaze.observe(pointer: CGPoint(x: 900, y: 32), iconFrame: icon, at: s0))
        XCTAssertTrue(gaze.isIdle(at: s0))
        XCTAssertTrue(gaze.isSettled(at: s0))
    }

    func testFollowsMovementThenReturnsToCenterAfterThreeSeconds() {
        var gaze = LiveFinderGaze()
        let icon = CGRect(x: 0, y: 0, width: 64, height: 64)
        gaze.observe(pointer: CGPoint(x: 0, y: 32), iconFrame: icon, at: s0)
        let moved = s0.addingTimeInterval(0.1)
        XCTAssertTrue(gaze.observe(pointer: CGPoint(x: 900, y: 32), iconFrame: icon, at: moved))
        // 挪动不到半个点不算动。
        XCTAssertFalse(gaze.observe(pointer: CGPoint(x: 900.2, y: 32), iconFrame: icon, at: moved))
        XCTAssertFalse(gaze.isSettled(at: moved))

        var now = moved
        var eyes = (left: LiveFinderFace.Point.zero, right: LiveFinderFace.Point.zero)
        for _ in 0..<45 {
            now = now.addingTimeInterval(1.0 / 30)
            eyes = gaze.step(at: now)
        }
        XCTAssertGreaterThan(eyes.left.x, LiveFinderFace.travel.x * 0.8)
        XCTAssertGreaterThan(eyes.right.x, LiveFinderFace.travel.x * 0.8)
        XCTAssertTrue(gaze.isSettled(at: now))
        XCTAssertFalse(gaze.isIdle(at: now))

        // 指针停了 3 秒：该回正了，慢慢回来，不是一下跳回去。
        let idle = moved.addingTimeInterval(LiveFinderGaze.idleDelay)
        XCTAssertTrue(gaze.isIdle(at: idle))
        XCTAssertFalse(gaze.isSettled(at: idle))
        gaze.pause()
        now = idle
        eyes = gaze.step(at: now)
        XCTAssertGreaterThan(eyes.left.x, LiveFinderFace.travel.x * 0.5)
        for _ in 0..<150 {
            now = now.addingTimeInterval(1.0 / 30)
            eyes = gaze.step(at: now)
        }
        XCTAssertEqual(eyes.left.x, 0, accuracy: 0.05)
        XCTAssertEqual(eyes.right.x, 0, accuracy: 0.05)
        XCTAssertTrue(gaze.isSettled(at: now))
    }

    func testStepsStayInsideTheTravelEllipse() {
        var gaze = LiveFinderGaze()
        let icon = CGRect(x: 0, y: 0, width: 64, height: 64)
        gaze.observe(pointer: CGPoint(x: 32, y: 32), iconFrame: icon, at: s0)
        var now = s0
        for i in 0..<120 {
            now = now.addingTimeInterval(1.0 / 30)
            let a = Double(i) * 0.7
            gaze.observe(pointer: CGPoint(x: 32 + cos(a) * 3000, y: 32 + sin(a) * 3000), iconFrame: icon, at: now)
            let eyes = gaze.step(at: now)
            XCTAssertTrue(inside(eyes.left))
            XCTAssertTrue(inside(eyes.right))
        }
    }

    // MARK: 眨眼

    func testBlinkPlansStayInRange() {
        var rng = SplitMix64(state: 42)
        var doubles = 0
        let runs = 2000
        for _ in 0..<runs {
            let plan = LiveFinderBlink.next(using: &rng)
            XCTAssertTrue(LiveFinderBlink.interval.contains(plan.wait))
            XCTAssertTrue((1...2).contains(plan.closed.count))
            for c in plan.closed { XCTAssertTrue(LiveFinderBlink.closedDuration.contains(c)) }
            XCTAssertTrue(LiveFinderBlink.gapDuration.contains(plan.gap))
            if plan.closed.count == 2 { doubles += 1 }
        }
        // 偶尔连眨两下：有，但远少于一半。
        XCTAssertGreaterThan(doubles, runs / 20)
        XCTAssertLessThan(doubles, runs * 2 / 5)
    }

    // MARK: 刷新节奏

    func testRefreshNeverFasterThanThirtyPerSecond() {
        for lowPower in [false, true] {
            XCTAssertGreaterThanOrEqual(LiveFinderMotion.frameInterval(lowPower: lowPower), 1.0 / 30 - 1e-12)
            for active in [false, true] {
                XCTAssertGreaterThanOrEqual(LiveFinderMotion.pollInterval(lowPower: lowPower, active: active),
                                            1.0 / 30 - 1e-12)
            }
        }
        XCTAssertGreaterThan(LiveFinderMotion.frameInterval(lowPower: true), LiveFinderMotion.frameInterval(lowPower: false))
        XCTAssertGreaterThan(LiveFinderMotion.pollInterval(lowPower: true, active: true),
                             LiveFinderMotion.pollInterval(lowPower: false, active: true))
        XCTAssertGreaterThan(LiveFinderMotion.pollInterval(lowPower: false, active: false),
                             LiveFinderMotion.pollInterval(lowPower: false, active: true))
    }
}
