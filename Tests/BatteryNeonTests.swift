import XCTest

/// 霓虹灯管电池外观（`BatteryNeon`）：电量到颜色、灌亮比例和遮罩高度、插电动画
/// 什么时候播、30 秒节流、每一刻画什么。
final class BatteryNeonTests: XCTestCase {

    // MARK: 颜色

    func testBandsFollowTheThresholds() {
        XCTAssertEqual(BatteryNeon.band(percent: 0), .red)
        XCTAssertEqual(BatteryNeon.band(percent: 20), .red)
        XCTAssertEqual(BatteryNeon.band(percent: 21), .orange)
        XCTAssertEqual(BatteryNeon.band(percent: 50), .orange)
        XCTAssertEqual(BatteryNeon.band(percent: 51), .yellow)
        XCTAssertEqual(BatteryNeon.band(percent: 90), .yellow)
        XCTAssertEqual(BatteryNeon.band(percent: 91), .green)
        XCTAssertEqual(BatteryNeon.band(percent: 100), .green)
    }

    func testColoursMatchTheMockupsAndAreNeverBlue() {
        // 效果图里 68% 的黄：深色 #FFC424，浅色 #F6AC08。
        XCTAssertEqual(BatteryNeon.color(percent: 68, dark: true), BatteryNeon.RGB(1, 196.0 / 255, 36.0 / 255))
        XCTAssertEqual(BatteryNeon.color(percent: 68, dark: false), BatteryNeon.RGB(246.0 / 255, 172.0 / 255, 8.0 / 255))
        for band in BatteryNeon.Band.allCases {
            for dark in [true, false] {
                let c = BatteryNeon.color(band, dark: dark)
                XCTAssertLessThan(c.blue, max(c.red, c.green), "\(band) \(dark) 不能是蓝色")
            }
        }
        // 浅色底上压深一点：亮度不高于深色底那一版。
        for band in BatteryNeon.Band.allCases {
            let light = BatteryNeon.color(band, dark: false)
            let dark = BatteryNeon.color(band, dark: true)
            XCTAssertLessThanOrEqual(light.red + light.green + light.blue, dark.red + dark.green + dark.blue)
        }
    }

    func testCoreIsLighterThanTheTube() {
        let c = BatteryNeon.color(.red, dark: true)
        let core = BatteryNeon.core(c, dark: true)
        XCTAssertGreaterThan(core.green, c.green)
        XCTAssertGreaterThan(core.blue, c.blue)
    }

    // MARK: 灌亮

    func testFillFractionIsClampedAndNeverInvented() {
        XCTAssertEqual(BatteryNeon.fillFraction(percent: nil), 0)
        XCTAssertEqual(BatteryNeon.fillFraction(percent: -5), 0)
        XCTAssertEqual(BatteryNeon.fillFraction(percent: 68), 0.68, accuracy: 1e-9)
        XCTAssertEqual(BatteryNeon.fillFraction(percent: 140), 1)
    }

    func testMaskStartsAtTheBaselineAndReachesTheTopOfTheDigits() {
        XCTAssertEqual(BatteryNeon.maskHeight(fraction: 0, descent: 10, capHeight: 50), 0)
        XCTAssertEqual(BatteryNeon.maskHeight(fraction: 0.5, descent: 10, capHeight: 50), 35, accuracy: 1e-9)
        XCTAssertEqual(BatteryNeon.maskHeight(fraction: 0.01, descent: 10, capHeight: 50), 10.5, accuracy: 1e-9)
        // 满电多盖一点，圆顶的弧线不会留一道没亮的边。
        XCTAssertGreaterThan(BatteryNeon.maskHeight(fraction: 1, descent: 10, capHeight: 50), 60)
        XCTAssertEqual(BatteryNeon.maskHeight(fraction: 3, descent: 10, capHeight: 50),
                       BatteryNeon.maskHeight(fraction: 1, descent: 10, capHeight: 50))
        XCTAssertEqual(BatteryNeon.maskHeight(fraction: .nan, descent: 10, capHeight: 50), 0)
    }

    func testTubeWidthScalesButStaysVisible() {
        XCTAssertEqual(BatteryNeon.tubeWidth(fontSize: 10), 1.2)
        XCTAssertEqual(BatteryNeon.tubeWidth(fontSize: 100), 4.5, accuracy: 1e-9)
    }

    func testHoursAndMinutes() {
        XCTAssertNil(BatteryNeon.hoursMinutes(nil))
        XCTAssertNil(BatteryNeon.hoursMinutes(0))
        XCTAssertTrue(BatteryNeon.hoursMinutes(72)! == (1, 12))
        XCTAssertTrue(BatteryNeon.hoursMinutes(45)! == (0, 45))
    }

    // MARK: 什么时候播

    func testOnlyBatteryToPowerIsAPlugIn() {
        XCTAssertTrue(BatteryNeon.isPlugIn(from: .battery, to: .ac))
        XCTAssertFalse(BatteryNeon.isPlugIn(from: nil, to: .ac), "启动时第一次读到接着电源不算")
        XCTAssertFalse(BatteryNeon.isPlugIn(from: .ac, to: .ac))
        XCTAssertFalse(BatteryNeon.isPlugIn(from: .ac, to: .battery))
        XCTAssertFalse(BatteryNeon.isPlugIn(from: .battery, to: nil))
    }

    func testThePlugAnimationIsOnUntilTurnedOff() {
        XCTAssertTrue(BatteryNeon.plugAnimationEnabled(stored: nil))
        XCTAssertTrue(BatteryNeon.plugAnimationEnabled(stored: true))
        XCTAssertFalse(BatteryNeon.plugAnimationEnabled(stored: false))
        XCTAssertFalse(BatteryNeon.plugAnimationEnabled(stored: NSNumber(value: false)))
    }

    func testDecisionOrder() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let gate = BatteryNeon.PlugGate()
        XCTAssertEqual(BatteryNeon.plugDecision(.init(), gate: gate, at: now), .play)
        XCTAssertEqual(BatteryNeon.plugDecision(.init(enabled: false), gate: gate, at: now), .off)
        XCTAssertEqual(BatteryNeon.plugDecision(.init(unlocked: false), gate: gate, at: now), .locked)
        XCTAssertEqual(BatteryNeon.plugDecision(.init(fullscreen: true), gate: gate, at: now), .fullscreen)
        XCTAssertEqual(BatteryNeon.plugDecision(.init(sharing: true), gate: gate, at: now), .sharing)
        XCTAssertEqual(BatteryNeon.plugDecision(.init(presenting: true), gate: gate, at: now), .presenting)
        XCTAssertEqual(BatteryNeon.plugDecision(.init(notchBusy: true), gate: gate, at: now), .notchBusy)
        // 关掉的开关最先看：没解锁、刘海又忙，也只报关着。
        XCTAssertEqual(BatteryNeon.plugDecision(.init(enabled: false, unlocked: false, notchBusy: true),
                                                gate: gate, at: now), .off)
    }

    func testRepeatedPlugsWithinThirtySecondsPlayOnce() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        var gate = BatteryNeon.PlugGate()
        XCTAssertEqual(BatteryNeon.plugDecision(.init(), gate: gate, at: start), .play)
        gate.recordPlay(at: start)
        XCTAssertEqual(BatteryNeon.plugDecision(.init(), gate: gate, at: start.addingTimeInterval(5)), .throttled)
        XCTAssertEqual(BatteryNeon.plugDecision(.init(), gate: gate, at: start.addingTimeInterval(29.9)), .throttled)
        XCTAssertEqual(BatteryNeon.plugDecision(.init(), gate: gate, at: start.addingTimeInterval(30)), .play)
        // 时间往回拨了不卡住。
        XCTAssertTrue(gate.wouldAllow(at: start.addingTimeInterval(-60)))
    }

    func testASkippedPlugDoesNotUseUpTheWindow() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let gate = BatteryNeon.PlugGate()
        // 全屏时跳过，没有记 recordPlay；退出全屏后 5 秒再插，照常播。
        XCTAssertEqual(BatteryNeon.plugDecision(.init(fullscreen: true), gate: gate, at: start), .fullscreen)
        XCTAssertEqual(BatteryNeon.plugDecision(.init(), gate: gate, at: start.addingTimeInterval(5)), .play)
    }

    // MARK: 每一刻画什么

    func testTimelineRunsInOrder() {
        typealias P = BatteryNeon.Plug
        XCTAssertEqual(P.duration, 2.5)
        XCTAssertEqual(P.total, 5.9, accuracy: 1e-9)

        // 刘海先亮，数字和胶囊都还没有。
        let start = P.frame(at: 0.1)
        XCTAssertGreaterThan(start.edgeGlow, 0.5)
        XCTAssertNil(start.drop)
        XCTAssertEqual(start.digits, 0)
        XCTAssertEqual(start.chip, 0)

        // 光滴往下落，越落越快。
        let a = P.frame(at: 0.4).drop!
        let b = P.frame(at: 0.6).drop!
        let c = P.frame(at: 0.8).drop!
        XCTAssertLessThan(a, b)
        XCTAssertGreaterThan(c - b, b - a)
        XCTAssertNil(P.frame(at: 0.9).drop)

        // 落进数字后从 0 灌到满（满 = 当前电量），之后不再变。
        XCTAssertEqual(P.frame(at: 0.85).fill, 0)
        XCTAssertGreaterThan(P.frame(at: 1.3).fill, 0.5)
        XCTAssertEqual(P.frame(at: 1.85).fill, 1)
        XCTAssertEqual(P.frame(at: 2.4).fill, 1)
        var last = 0.0
        for step in 0...100 {
            let fill = P.frame(at: Double(step) * 0.03).fill
            XCTAssertGreaterThanOrEqual(fill, last)
            last = fill
        }

        // 数字全亮一段，再淡出；胶囊接着留 3 秒后淡出。
        XCTAssertEqual(P.frame(at: 1.2).digits, 1)
        XCTAssertLessThan(P.frame(at: 2.4).digits, 0.5)
        XCTAssertEqual(P.frame(at: 2.5).digits, 0)
        XCTAssertEqual(P.frame(at: 3).chip, 1)
        XCTAssertEqual(P.frame(at: 5.4).chip, 1)
        XCTAssertLessThan(P.frame(at: 5.7).chip, 1)
        XCTAssertEqual(P.frame(at: 6).chip, 0)
        let before = P.frame(at: -1)
        XCTAssertEqual(before.edgeGlow, 0)
        XCTAssertEqual(before.digits, 0)
        XCTAssertEqual(before.chip, 0)
        XCTAssertEqual(P.frame(at: 100).chip, 0)
    }

    // MARK: 扩展栏卡片

    func testNeonCardStaysStillExceptForThePlugInMoment() {
        XCTAssertNil(BatteryMotion.framesPerSecond(look: .neon, charging: true, pulsing: false, flourish: false,
                                                   host: .card(visible: true), reduceMotion: false))
        XCTAssertEqual(BatteryMotion.framesPerSecond(look: .neon, charging: true, pulsing: false, flourish: true,
                                                     host: .card(visible: true), reduceMotion: false),
                       BatteryMotion.maxFPS)
        XCTAssertNil(BatteryMotion.framesPerSecond(look: .neon, charging: true, pulsing: false, flourish: true,
                                                   host: .card(visible: true), reduceMotion: true))
    }
}
