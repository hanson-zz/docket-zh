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
        XCTAssertEqual(LiveIconApp(bundleID: "com.anthropic.claudefordesktop"), .claude)
        XCTAssertNil(LiveIconApp(bundleID: "com.apple.Safari"))
        XCTAssertNil(LiveIconApp(bundleID: "com.google.Chrome.canary"))
    }

    func testMasterSwitchGatesEverySubSwitch() {
        let off = LiveIconToggles()
        XCTAssertFalse(off.isOn(.finder))
        XCTAssertFalse(off.isOn(.chrome))
        XCTAssertFalse(off.isOn(.openAI))
        XCTAssertFalse(off.isOn(.claude))

        let on = LiveIconToggles(master: true)
        XCTAssertTrue(on.isOn(.finder))
        XCTAssertTrue(on.isOn(.chrome))
        XCTAssertTrue(on.isOn(.openAI))
        XCTAssertTrue(on.isOn(.claude))

        let noChrome = LiveIconToggles(master: true, chrome: false)
        XCTAssertTrue(noChrome.isOn(.finder))
        XCTAssertFalse(noChrome.isOn(.chrome))
        XCTAssertTrue(noChrome.isOn(.openAI))

        let noClaude = LiveIconToggles(master: true, claude: false)
        XCTAssertFalse(noClaude.isOn(.claude))
        XCTAssertTrue(noClaude.isOn(.openAI))
    }

    // MARK: 水位

    private func window(_ id: String, used: Double, resetsIn: TimeInterval? = 3600) -> CodexLimitWindow {
        CodexLimitWindow(id: id, label: id, usedFraction: used,
                         resetsAt: resetsIn.map { t0.addingTimeInterval($0) })
    }

    func testQuotaIsUnknownWithoutFreshData() {
        let w = window("primary", used: 0.4)
        XCTAssertNil(LiveIconUsage.quota(session: nil, weekly: nil, fetchedAt: t0, now: t0))
        XCTAssertNil(LiveIconUsage.quota(session: w, weekly: nil, fetchedAt: nil, now: t0))
        XCTAssertNil(LiveIconUsage.quota(session: w, weekly: nil, fetchedAt: t0, now: t0.addingTimeInterval(31 * 60)))
        XCTAssertNil(LiveIconUsage.quota(nil, now: t0))
        var bad = w
        bad.usedFraction = .nan
        XCTAssertNil(LiveIconUsage.quota(session: bad, weekly: nil, fetchedAt: t0, now: t0))
    }

    func testQuotaIsRemainingNotUsed() {
        let q = LiveIconUsage.quota(session: window("primary", used: 0.4), weekly: nil,
                                    fetchedAt: t0, now: t0.addingTimeInterval(29 * 60))
        XCTAssertEqual(q?.remaining ?? -1, 0.6, accuracy: 1e-9)
        XCTAssertEqual(q?.window, .session)
        XCTAssertEqual(q?.resetsAt, t0.addingTimeInterval(3600))
    }

    func testQuotaPicksTheTighterWindow() {
        let session = window("primary", used: 0.3, resetsIn: 3600)
        let weekly = window("secondary", used: 0.9, resetsIn: 3 * 86_400)
        let q = LiveIconUsage.quota(session: session, weekly: weekly, fetchedAt: t0, now: t0)
        XCTAssertEqual(q?.window, .weekly)
        XCTAssertEqual(q?.remaining ?? -1, 0.1, accuracy: 1e-9)
        XCTAssertEqual(q?.resetsAt, t0.addingTimeInterval(3 * 86_400))

        let looser = window("secondary", used: 0.1, resetsIn: 3 * 86_400)
        XCTAssertEqual(LiveIconUsage.quota(session: session, weekly: looser, fetchedAt: t0, now: t0)?.window, .session)
        // 一样紧时取 5 小时窗口。
        let tie = window("secondary", used: 0.3, resetsIn: 3 * 86_400)
        XCTAssertEqual(LiveIconUsage.quota(session: session, weekly: tie, fetchedAt: t0, now: t0)?.window, .session)
    }

    func testQuotaFallsBackWhenOneWindowIsMissingOrPastReset() {
        let weekly = window("secondary", used: 0.5, resetsIn: 86_400)
        XCTAssertEqual(LiveIconUsage.quota(session: nil, weekly: weekly, fetchedAt: t0, now: t0)?.window, .weekly)
        // 5 小时窗口更紧，但重置时间已经过了：读数是上一轮的，只看每周。
        let stale = window("primary", used: 0.95, resetsIn: -60)
        let q = LiveIconUsage.quota(session: stale, weekly: weekly, fetchedAt: t0, now: t0)
        XCTAssertEqual(q?.window, .weekly)
        XCTAssertEqual(q?.remaining ?? -1, 0.5, accuracy: 1e-9)
        XCTAssertNil(LiveIconUsage.quota(session: stale, weekly: nil, fetchedAt: t0, now: t0))
        // 没有重置时间的窗口照常用。
        let open = window("primary", used: 0.2, resetsIn: nil)
        XCTAssertEqual(LiveIconUsage.quota(session: open, weekly: nil, fetchedAt: t0, now: t0)?.remaining ?? -1,
                       0.8, accuracy: 1e-9)
    }

    func testQuotaFromReport() {
        let report = CodexUsageReport(windows: [window("primary", used: 0.25), window("secondary", used: 0.5,
                                                                                     resetsIn: 86_400)],
                                      fetchedAt: t0)
        let q = LiveIconUsage.quota(report, now: t0)
        XCTAssertEqual(q?.window, .weekly)
        XCTAssertEqual(q?.remaining ?? -1, 0.5, accuracy: 1e-9)
    }

    func testQuotaClamps() {
        XCTAssertEqual(LiveQuota(remaining: 1.4, window: .session, resetsAt: nil).remaining, 1)
        XCTAssertEqual(LiveQuota(remaining: -0.2, window: .session, resetsAt: nil).remaining, 0)
        XCTAssertEqual(LiveIconUsage.quota(session: window("primary", used: 1.4), weekly: nil,
                                           fetchedAt: t0, now: t0)?.remaining, 0)
    }

    func testResetCountdown() {
        XCTAssertEqual(LiveIconUsage.resetCountdown(42 * 60 + 30), "42m")
        XCTAssertEqual(LiveIconUsage.resetCountdown(59), "0m")
        XCTAssertEqual(LiveIconUsage.resetCountdown(3600), "1h 0m")
        XCTAssertEqual(LiveIconUsage.resetCountdown(19 * 3600 + 20), "19h 0m")
        XCTAssertEqual(LiveIconUsage.resetCountdown(23 * 3600 + 59 * 60), "23h 59m")
        XCTAssertEqual(LiveIconUsage.resetCountdown(86_400), "1d 0h")
        XCTAssertEqual(LiveIconUsage.resetCountdown(86_400 + 18 * 3600 + 600), "1d 18h")
        XCTAssertEqual(LiveIconUsage.resetCountdown(-5), "0m")
        XCTAssertEqual(LiveIconUsage.resetCountdown(.nan), "0m")
        XCTAssertEqual(LiveIconUsage.resetCountdown(.infinity), "0m")

        let q = LiveQuota(remaining: 0.5, window: .session, resetsAt: t0.addingTimeInterval(19 * 3600))
        XCTAssertEqual(LiveIconUsage.resetCountdown(q, now: t0), "19h 0m")
        XCTAssertNil(LiveIconUsage.resetCountdown(LiveQuota(remaining: 0.5, window: .session, resetsAt: nil), now: t0))
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
