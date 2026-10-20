import XCTest

final class BatteryLiquidFXTests: XCTestCase {
    // MARK: 插拔事件

    func testPlugEventNeedsAPreviousReading() {
        XCTAssertNil(BatteryLiquidFX.plugEvent(previous: nil, current: true))
        XCTAssertNil(BatteryLiquidFX.plugEvent(previous: nil, current: false))
        XCTAssertNil(BatteryLiquidFX.plugEvent(previous: true, current: true))
        XCTAssertNil(BatteryLiquidFX.plugEvent(previous: false, current: false))
        XCTAssertEqual(BatteryLiquidFX.plugEvent(previous: false, current: true), .plugged)
        XCTAssertEqual(BatteryLiquidFX.plugEvent(previous: true, current: false), .unplugged)
    }

    func testActiveSloshPicksTheLatestEventAndExpires() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        XCTAssertNil(BatteryLiquidFX.activeSlosh(pluggedAt: nil, unpluggedAt: nil, now: now))

        let plugged = BatteryLiquidFX.activeSlosh(pluggedAt: now.addingTimeInterval(-0.5), unpluggedAt: nil, now: now)
        XCTAssertEqual(plugged?.event, .plugged)
        XCTAssertEqual(plugged?.elapsed ?? 0, 0.5, accuracy: 1e-9)

        // 拔掉比插上晚：算拔掉。
        let both = BatteryLiquidFX.activeSlosh(pluggedAt: now.addingTimeInterval(-0.9),
                                               unpluggedAt: now.addingTimeInterval(-0.2), now: now)
        XCTAssertEqual(both?.event, .unplugged)

        // 晃完了、或者时间在将来，都不算在晃。
        XCTAssertNil(BatteryLiquidFX.activeSlosh(pluggedAt: now.addingTimeInterval(-1.3), unpluggedAt: nil, now: now))
        XCTAssertNil(BatteryLiquidFX.activeSlosh(pluggedAt: nil, unpluggedAt: now.addingTimeInterval(-0.8), now: now))
        XCTAssertNil(BatteryLiquidFX.activeSlosh(pluggedAt: now.addingTimeInterval(5), unpluggedAt: nil, now: now))
    }

    // MARK: 晃荡

    func testSloshDecaysAndEndsFlat() {
        XCTAssertEqual(BatteryLiquidFX.plugSloshDuration, 1.2)
        XCTAssertEqual(BatteryLiquidFX.slosh(.plugged, elapsed: 0), 0, accuracy: 1e-12)
        XCTAssertEqual(BatteryLiquidFX.slosh(.plugged, elapsed: -0.1), 0)
        XCTAssertEqual(BatteryLiquidFX.slosh(.plugged, elapsed: 1.2), 0)
        XCTAssertEqual(BatteryLiquidFX.slosh(.plugged, elapsed: .nan), 0)
        // 快结束时几乎平了。
        XCTAssertLessThan(abs(BatteryLiquidFX.slosh(.plugged, elapsed: 1.19)), 0.001)

        // 每个半周期的峰值一个比一个小（衰减）。
        let samples = stride(from: 0.0, to: 1.2, by: 0.005).map { BatteryLiquidFX.slosh(.plugged, elapsed: $0) }
        var peaks: [Double] = []
        for i in 1..<(samples.count - 1) where abs(samples[i]) > abs(samples[i - 1]) && abs(samples[i]) >= abs(samples[i + 1]) {
            peaks.append(abs(samples[i]))
        }
        XCTAssertGreaterThanOrEqual(peaks.count, 3)
        for (a, b) in zip(peaks, peaks.dropFirst()) { XCTAssertGreaterThan(a, b) }
        // 克制：最大倾斜不超过区域高度的 7%。
        XCTAssertLessThanOrEqual(samples.map { abs($0) }.max() ?? 1, BatteryLiquidFX.plugTilt)
        // 晃荡有正有负，是来回晃。
        XCTAssertTrue(samples.contains { $0 > 0.005 })
        XCTAssertTrue(samples.contains { $0 < -0.005 })
    }

    func testUnplugIsASmallerShorterSlosh() {
        let plug = stride(from: 0.0, to: 1.2, by: 0.005).map { abs(BatteryLiquidFX.slosh(.plugged, elapsed: $0)) }.max() ?? 0
        let unplug = stride(from: 0.0, to: 1.2, by: 0.005).map { abs(BatteryLiquidFX.slosh(.unplugged, elapsed: $0)) }.max() ?? 0
        XCTAssertGreaterThan(unplug, 0)
        XCTAssertLessThan(unplug, plug * 0.5)
        XCTAssertLessThan(BatteryLiquidFX.unplugSloshDuration, BatteryLiquidFX.plugSloshDuration)
        XCTAssertEqual(BatteryLiquidFX.slosh(.unplugged, elapsed: 0.7), 0)
    }

    func testTiltLiftIsOppositeAtTheEnds() {
        XCTAssertEqual(BatteryLiquidFX.tiltLift(x: 0, slosh: 0.05), 0.05, accuracy: 1e-12)
        XCTAssertEqual(BatteryLiquidFX.tiltLift(x: 1, slosh: 0.05), -0.05, accuracy: 1e-12)
        XCTAssertEqual(BatteryLiquidFX.tiltLift(x: 0.5, slosh: 0.05), 0, accuracy: 1e-12)
        XCTAssertEqual(BatteryLiquidFX.tiltLift(x: 2, slosh: 0.05), -0.05, accuracy: 1e-12)
    }

    func testColorBlendRunsZeroToOne() {
        XCTAssertEqual(BatteryLiquidFX.colorBlend(.plugged, elapsed: 0), 0)
        XCTAssertEqual(BatteryLiquidFX.colorBlend(.plugged, elapsed: 1.2), 1)
        XCTAssertEqual(BatteryLiquidFX.colorBlend(.plugged, elapsed: 5), 1)
        let mid = BatteryLiquidFX.colorBlend(.plugged, elapsed: 0.6)
        XCTAssertGreaterThan(mid, 0.5)
        XCTAssertLessThan(mid, 1)
    }

    // MARK: 水珠

    func testDropletsOnlyOnPlugAndLandBack() {
        XCTAssertTrue(BatteryLiquidFX.droplets(.unplugged, elapsed: 0.2).isEmpty)
        XCTAssertTrue(BatteryLiquidFX.droplets(.plugged, elapsed: -0.1).isEmpty)
        XCTAssertTrue(BatteryLiquidFX.droplets(.plugged, elapsed: 2).isEmpty)

        let flying = BatteryLiquidFX.droplets(.plugged, elapsed: 0.3)
        XCTAssertGreaterThanOrEqual(flying.count, 3)
        XCTAssertLessThanOrEqual(flying.count, 5)
        for drop in flying {
            XCTAssertGreaterThan(drop.height, 0)
            XCTAssertLessThanOrEqual(drop.height, 1)
            XCTAssertTrue((0...1).contains(drop.x))
            XCTAssertTrue((0...1).contains(drop.opacity))
        }
        // 最多 5 颗。
        XCTAssertLessThanOrEqual(BatteryLiquidFX.droplets(.plugged, elapsed: 0.3, count: 9).count, 5)
        // 都在晃荡结束前落回。
        XCTAssertTrue(BatteryLiquidFX.droplets(.plugged, elapsed: BatteryLiquidFX.plugSloshDuration).isEmpty)
    }

    // MARK: 低电量

    func testLowThresholdIsTwentyPercentWhileNotCharging() {
        XCTAssertTrue(BatteryLiquidFX.isLow(level: 0.20, charging: false, present: true))
        XCTAssertTrue(BatteryLiquidFX.isLow(level: 0.204, charging: false, present: true))
        XCTAssertTrue(BatteryLiquidFX.isLow(level: 0.03, charging: false, present: true))
        XCTAssertFalse(BatteryLiquidFX.isLow(level: 0.21, charging: false, present: true))
        XCTAssertFalse(BatteryLiquidFX.isLow(level: 0.10, charging: true, present: true))
        XCTAssertFalse(BatteryLiquidFX.isLow(level: 0.10, charging: false, present: false))
        XCTAssertFalse(BatteryLiquidFX.isLow(level: .nan, charging: false, present: true))
    }

    func testBlobBreathesGently() {
        XCTAssertEqual(BatteryLiquidFX.blobScale(t: nil), 0.91)
        let samples = stride(from: 0.0, to: 6.4, by: 0.1).map { BatteryLiquidFX.blobScale(t: $0) }
        XCTAssertGreaterThanOrEqual(samples.min() ?? 0, 0.82 - 1e-9)
        XCTAssertLessThanOrEqual(samples.max() ?? 2, 1 + 1e-9)
        XCTAssertEqual(BatteryLiquidFX.blobScale(t: 0), BatteryLiquidFX.blobScale(t: BatteryLiquidFX.blobPeriod), accuracy: 1e-9)
    }

    // MARK: 颜色

    func testGradientRunsRedYellowGreen() {
        XCTAssertEqual(BatteryLiquidFX.gradientColor(level: 0), BatteryLiquidFX.red)
        XCTAssertEqual(BatteryLiquidFX.gradientColor(level: 0.2), BatteryLiquidFX.red)
        XCTAssertEqual(BatteryLiquidFX.gradientColor(level: 0.3), BatteryLiquidFX.orange)
        XCTAssertEqual(BatteryLiquidFX.gradientColor(level: 0.5), BatteryLiquidFX.yellow)
        XCTAssertEqual(BatteryLiquidFX.gradientColor(level: 0.65), BatteryLiquidFX.green)
        XCTAssertEqual(BatteryLiquidFX.gradientColor(level: 1), BatteryLiquidFX.green)
        XCTAssertEqual(BatteryLiquidFX.gradientColor(level: .nan), BatteryLiquidFX.red)
        // 绿就是卡片平时的电池绿。
        XCTAssertEqual(MetricColor.batteryPresent, "#34C759")

        // 平滑：每 1% 绿色通道不往回走，单步变化很小。
        var previous = BatteryLiquidFX.gradientColor(level: 0)
        for percent in 1...100 {
            let color = BatteryLiquidFX.gradientColor(level: Double(percent) / 100)
            let step = abs(color.red - previous.red) + abs(color.green - previous.green) + abs(color.blue - previous.blue)
            XCTAssertLessThan(step, 0.1, "\(percent)%")
            if percent <= 50 { XCTAssertGreaterThanOrEqual(color.green, previous.green - 1e-12) }
            previous = color
        }
        // 两点之间是插值，不是跳变。
        let mid = BatteryLiquidFX.gradientColor(level: 0.4)
        XCTAssertGreaterThan(mid.green, BatteryLiquidFX.orange.green)
        XCTAssertLessThan(mid.green, BatteryLiquidFX.yellow.green)
    }

    func testExistingPrioritiesStay() {
        // 低电量模式最优先，黄色。
        XCTAssertEqual(BatteryLiquidFX.cellWaterColor(level: 0.1, charging: true, lowPower: true),
                       BatteryColorMap.lowPowerYellow)
        XCTAssertEqual(BatteryLiquidFX.gaugeWaterColor(level: 0.9, lowPower: true), BatteryColorMap.lowPowerYellow)
        // 电池格充电时不报警，照旧电池绿。
        XCTAssertEqual(BatteryLiquidFX.cellWaterColor(level: 0.1, charging: true, lowPower: false), BatteryLiquidFX.green)
        // 其余按电量。
        XCTAssertEqual(BatteryLiquidFX.cellWaterColor(level: 0.1, charging: false, lowPower: false), BatteryLiquidFX.red)
        XCTAssertEqual(BatteryLiquidFX.gaugeWaterColor(level: 0.1, lowPower: false), BatteryLiquidFX.red)
    }

    // MARK: 帧率

    func testFrameRateIdlesAndStops() {
        XCTAssertNil(BatteryLiquidFX.framesPerSecond(visible: false, reduceMotion: false, sloshing: true))
        XCTAssertNil(BatteryLiquidFX.framesPerSecond(visible: true, reduceMotion: true, sloshing: true))
        XCTAssertEqual(BatteryLiquidFX.framesPerSecond(visible: true, reduceMotion: false, sloshing: true), 30)
        XCTAssertEqual(BatteryLiquidFX.framesPerSecond(visible: true, reduceMotion: false, sloshing: false), 10)
    }

    // MARK: Pro

    func testLiquidStaysProAndCountsDoNotChange() {
        XCTAssertTrue(ProFeatures.isProChoice(kind: .battery, key: BatteryLook.key, value: BatteryLook.liquid.rawValue))
        XCTAssertEqual(ProLicenseGate.batteryLook(config: WidgetConfig([BatteryLook.key: .string("liquid")]),
                                                  unlocked: false), .classic)
        XCTAssertEqual(ProFeatures.proKinds.count, 14)
    }
}
