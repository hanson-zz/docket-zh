import XCTest
@testable import Docket

final class LiveIconUsageTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    /// 转动的测试用参考时间原点：Date 离原点越远精度越差，角度断言会差出百万分之几度。
    private let s0 = Date(timeIntervalSinceReferenceDate: 0)

    // MARK: 认 App 与开关

    func testBundleIDsMapToApps() {
        XCTAssertEqual(LiveIconApp(bundleID: "com.apple.finder"), .finder)
        XCTAssertEqual(LiveIconApp(bundleID: "com.google.Chrome"), .chrome)
        XCTAssertEqual(LiveIconApp(bundleID: "com.openai.chat"), .openAI)
        XCTAssertEqual(LiveIconApp(bundleID: "com.openai.codex"), .openAI)
        XCTAssertNil(LiveIconApp(bundleID: "com.apple.Safari"))
        XCTAssertNil(LiveIconApp(bundleID: "com.google.Chrome.canary"))
    }

    func testMasterSwitchGatesEverySubSwitch() {
        let off = LiveIconToggles()
        XCTAssertFalse(off.isOn(.finder))
        XCTAssertFalse(off.isOn(.chrome))
        XCTAssertFalse(off.isOn(.openAI))

        let on = LiveIconToggles(master: true)
        XCTAssertTrue(on.isOn(.finder))
        XCTAssertTrue(on.isOn(.chrome))
        XCTAssertTrue(on.isOn(.openAI))

        let noChrome = LiveIconToggles(master: true, chrome: false)
        XCTAssertTrue(noChrome.isOn(.finder))
        XCTAssertFalse(noChrome.isOn(.chrome))
        XCTAssertTrue(noChrome.isOn(.openAI))
    }

    // MARK: 水位

    func testLevelIsUnknownWithoutFreshData() {
        XCTAssertNil(LiveIconUsage.level(primaryUsed: nil, fetchedAt: t0, now: t0))
        XCTAssertNil(LiveIconUsage.level(primaryUsed: 0.4, fetchedAt: nil, now: t0))
        XCTAssertNil(LiveIconUsage.level(primaryUsed: .nan, fetchedAt: t0, now: t0))
        XCTAssertNil(LiveIconUsage.level(primaryUsed: 0.4, fetchedAt: t0, now: t0.addingTimeInterval(31 * 60)))
        XCTAssertEqual(LiveIconUsage.level(primaryUsed: 0.4, fetchedAt: t0, now: t0.addingTimeInterval(29 * 60)), 0.4)
    }

    func testLevelClamps() {
        XCTAssertEqual(LiveIconUsage.level(primaryUsed: 1.4, fetchedAt: t0, now: t0), 1)
        XCTAssertEqual(LiveIconUsage.level(primaryUsed: -0.2, fetchedAt: t0, now: t0), 0)
    }

    func testSurfaceStaysInsideContent() {
        XCTAssertEqual(LiveIconUsage.surfaceFraction(0), 0.04, accuracy: 1e-9)
        XCTAssertEqual(LiveIconUsage.surfaceFraction(1), 0.94, accuracy: 1e-9)
        XCTAssertEqual(LiveIconUsage.surfaceFraction(.infinity), 0)
        XCTAssertLessThan(LiveIconUsage.surfaceFraction(0.3), LiveIconUsage.surfaceFraction(0.6))
    }

    func testPercentText() {
        XCTAssertEqual(LiveIconUsage.percentText(0.374), "37%")
        XCTAssertEqual(LiveIconUsage.percentText(0.375), "38%")
        XCTAssertEqual(LiveIconUsage.percentText(2), "100%")
        XCTAssertEqual(LiveIconUsage.percentText(.nan), "")
    }

    func testFlowOnlyWhileCodexIsMidTurn() {
        XCTAssertTrue(LiveIconUsage.isWorking(.working))
        XCTAssertTrue(LiveIconUsage.isWorking(.waiting))
        XCTAssertFalse(LiveIconUsage.isWorking(.idle))
        XCTAssertFalse(LiveIconUsage.isWorking(.done))
    }

    func testIconContentGeometry() {
        let g = LiveIconGeometry.content(side: 100)
        XCTAssertEqual(g.length, 80.5, accuracy: 1e-9)
        XCTAssertEqual(g.inset, 9.75, accuracy: 1e-9)
        XCTAssertEqual(g.corner, 80.5 * 0.2237, accuracy: 1e-9)
        XCTAssertEqual(LiveIconGeometry.content(side: -5).length, 0)
    }

    // MARK: 节奏

    func testLowPowerSlowsEveryAnimation() {
        for kind in [LiveIconMotion.Kind.spin, .flow, .water] {
            XCTAssertGreaterThan(LiveIconMotion.frameInterval(kind, lowPower: true),
                                 LiveIconMotion.frameInterval(kind, lowPower: false))
        }
    }

    func testChromePollSlowsInBackground() {
        XCTAssertEqual(LiveIconMotion.chromePollInterval(chromeFrontmost: true, lowPower: false), 0.5)
        XCTAssertEqual(LiveIconMotion.chromePollInterval(chromeFrontmost: false, lowPower: false), 1.5)
        XCTAssertEqual(LiveIconMotion.chromePollInterval(chromeFrontmost: true, lowPower: true), 1.5)
        XCTAssertEqual(LiveIconMotion.chromePollInterval(chromeFrontmost: true, lowPower: false, failures: 1), 5)
    }

    // MARK: Chrome 读数

    func testChromeReadingFromScriptResult() {
        XCTAssertEqual(LiveChromeReading(loading: true, errorCode: nil), .loading)
        XCTAssertEqual(LiveChromeReading(loading: false, errorCode: nil), .idle)
        XCTAssertEqual(LiveChromeReading(loading: nil, errorCode: -1743), .denied)
        XCTAssertEqual(LiveChromeReading(loading: nil, errorCode: -1744), .denied)
        XCTAssertEqual(LiveChromeReading(loading: nil, errorCode: -2753), .failed)
        XCTAssertEqual(LiveChromeReading(loading: nil, errorCode: nil), .failed)
    }

    func testDeniedFallsBackAndStopsAsking() {
        var a = LiveChromeAvailability()
        XCTAssertEqual(a.status, .unknown)
        XCTAssertFalse(a.record(.denied))
        XCTAssertEqual(a.status, .unavailable)
        XCTAssertTrue(a.stopped)
        a.reset()
        XCTAssertEqual(a.status, .unknown)
        XCTAssertFalse(a.stopped)
    }

    func testRepeatedFailuresFallBackButOneSuccessRecovers() {
        var a = LiveChromeAvailability()
        a.record(.failed)
        a.record(.failed)
        XCTAssertEqual(a.status, .unknown)
        a.record(.failed)
        XCTAssertEqual(a.status, .unavailable)
        XCTAssertFalse(a.stopped)
        XCTAssertTrue(a.record(.loading))
        XCTAssertEqual(a.status, .available)
        XCTAssertEqual(a.failures, 0)
        XCTAssertFalse(a.record(.idle))
    }

    // MARK: 转动

    func testSpinIsSteadyThenSettlesBackToZero() {
        var spin = LiveIconSpin()
        XCTAssertEqual(spin.angle(at: s0), 0)
        XCTAssertFalse(spin.isAnimating(at: s0))

        spin.start(at: s0)
        let quarter = 0.25 * 1.1
        XCTAssertEqual(spin.angle(at: s0.addingTimeInterval(quarter)), 90, accuracy: 1e-3)
        XCTAssertTrue(spin.isAnimating(at: s0.addingTimeInterval(100)))
        XCTAssertNil(spin.endDate(at: s0))

        let stopAt = s0.addingTimeInterval(quarter)
        spin.stop(at: stopAt)
        guard case let .settling(_, from, distance, duration) = spin.phase else {
            return XCTFail("应该在减速")
        }
        XCTAssertEqual(from, 90, accuracy: 1e-3)
        XCTAssertEqual(distance, 270, accuracy: 1e-3)
        XCTAssertEqual(duration, 2 * 270 / LiveIconSpin.degreesPerSecond, accuracy: 1e-6)
        // 减速开头速度接近匀速，不突然慢下来。
        let dt = 0.001
        let early = spin.angle(at: stopAt.addingTimeInterval(dt)) - from
        XCTAssertEqual(early / dt, LiveIconSpin.degreesPerSecond, accuracy: 1)
        // 中途角度一路往前，最后停在原角度。
        var last = from
        for i in 1..<20 {
            let a = spin.angle(at: stopAt.addingTimeInterval(duration * Double(i) / 20))
            XCTAssertGreaterThanOrEqual(a, last)
            last = a
        }
        XCTAssertEqual(spin.angle(at: stopAt.addingTimeInterval(duration + 0.01)), 0, accuracy: 1e-3)
        XCTAssertFalse(spin.isAnimating(at: stopAt.addingTimeInterval(duration + 0.01)))
        spin.settleIfDone(at: stopAt.addingTimeInterval(duration + 0.01))
        XCTAssertEqual(spin.phase, .resting)
    }

    func testShortSettleGetsAnExtraTurn() {
        var spin = LiveIconSpin()
        spin.start(at: s0)
        // 转到 300 度时停：只剩 60 度，太急，多转一圈。
        let at = s0.addingTimeInterval(300 / LiveIconSpin.degreesPerSecond)
        spin.stop(at: at)
        guard case let .settling(_, _, distance, _) = spin.phase else { return XCTFail() }
        XCTAssertEqual(distance, 420, accuracy: 1e-3)
    }

    func testRestartDuringSettleContinuesFromCurrentAngle() {
        var spin = LiveIconSpin()
        spin.start(at: s0)
        spin.stop(at: s0.addingTimeInterval(0.2))
        let again = s0.addingTimeInterval(0.4)
        let angle = spin.angle(at: again)
        spin.start(at: again)
        XCTAssertTrue(spin.isSpinning)
        XCTAssertEqual(spin.angle(at: again), angle, accuracy: 1e-3)
    }

    func testOneTurnFallbackEndsAtZeroAndDoesNotInterrupt() {
        var spin = LiveIconSpin()
        spin.turnOnce(at: s0)
        let mid = spin.angle(at: s0.addingTimeInterval(LiveIconSpin.oneTurnDuration / 2))
        XCTAssertEqual(mid, 180, accuracy: 1e-3)
        XCTAssertEqual(spin.angle(at: s0.addingTimeInterval(LiveIconSpin.oneTurnDuration)), 0, accuracy: 1e-3)

        var busy = LiveIconSpin()
        busy.start(at: s0)
        busy.turnOnce(at: s0.addingTimeInterval(0.1))
        XCTAssertTrue(busy.isSpinning)
    }

    func testStopWhileRestingDoesNothing() {
        var spin = LiveIconSpin()
        spin.stop(at: s0)
        XCTAssertEqual(spin.phase, .resting)
    }
}
