import XCTest

final class BatteryVisualsTests: XCTestCase {
    // MARK: Looks

    func testLooksAndSupporterGate() {
        XCTAssertFalse(BatteryLook.classic.isSupporterOnly)
        XCTAssertFalse(BatteryLook.liquid.isSupporterOnly)
        XCTAssertTrue(BatteryLook.pixel.isSupporterOnly)
        XCTAssertTrue(BatteryLook.particles.isSupporterOnly)
        XCTAssertTrue(BatteryLook.panda.isSupporterOnly)

        XCTAssertEqual(BatteryLook.shown("pixel", unlocked: false), .classic)
        XCTAssertEqual(BatteryLook.shown("pixel", unlocked: true), .pixel)
        XCTAssertEqual(BatteryLook.shown("liquid", unlocked: false), .liquid)
        XCTAssertEqual(BatteryLook.shown("nonsense", unlocked: true), .classic)
        XCTAssertEqual(BatteryLook.allCases.map(\.title), ["经典", "液态", "像素电池", "能量粒子", "小熊猫抱电池"])
    }

    func testOldWidgetsKeepClassicAndNewOnesAreLiquid() {
        // A widget saved before looks existed has no key: merged with the
        // catalog defaults it still reads 经典.
        let old = WidgetConfig(["layout": .string("status")])
        let merged = old.merging(defaults: WidgetCatalog.entry(.battery)!.defaults)
        XCTAssertEqual(BatteryLook.shown(config: merged, unlocked: true), .classic)

        let fresh = WidgetCatalog.make(.battery)!
        XCTAssertEqual(BatteryLook.shown(config: fresh.config, unlocked: false), .liquid)

        XCTAssertTrue(WidgetCatalog.isSupporterOnly([BatteryLook.key: .string("panda")]))
        XCTAssertFalse(WidgetCatalog.isSupporterOnly([BatteryLook.key: .string("liquid")]))
        XCTAssertTrue(WidgetCatalog.configurableKeys(.battery).contains(BatteryLook.key))
        XCTAssertFalse(WidgetCatalog.applies(BatteryLook.key, to: WidgetConfig(["layout": .string("icon")]),
                                             kind: .battery))
        XCTAssertTrue(WidgetCatalog.applies(BatteryLook.key, to: WidgetConfig(["layout": .string("gauge")]),
                                            kind: .battery))
    }

    // MARK: Colour

    func testColourBands() {
        XCTAssertEqual(BatteryColorMap.tint(level: 0.51, lowPower: false, charging: false).band, .green)
        XCTAssertEqual(BatteryColorMap.tint(level: 0.50, lowPower: false, charging: false).band, .amber)
        XCTAssertEqual(BatteryColorMap.tint(level: 0.20, lowPower: false, charging: false).band, .amber)
        XCTAssertEqual(BatteryColorMap.tint(level: 0.19, lowPower: false, charging: false).band, .red)
        XCTAssertEqual(BatteryColorMap.tint(level: 0.90, lowPower: true, charging: false).band, .lowPower)
        XCTAssertEqual(BatteryColorMap.tint(level: 0.05, lowPower: true, charging: false).band, .lowPower)
    }

    func testAmberRunsFromOrangeToYellow() {
        let bottom = BatteryColorMap.tint(level: 0.20, lowPower: false, charging: false).color
        let top = BatteryColorMap.tint(level: 0.50, lowPower: false, charging: false).color
        let middle = BatteryColorMap.tint(level: 0.35, lowPower: false, charging: false).color
        XCTAssertEqual(bottom, BatteryColorMap.orange)
        XCTAssertEqual(top.green, BatteryColorMap.yellow.green, accuracy: 0.0001)
        XCTAssertGreaterThan(middle.green, bottom.green)
        XCTAssertLessThan(middle.green, top.green)
    }

    func testOnlyARedLevelOffTheChargerPulses() {
        XCTAssertTrue(BatteryColorMap.tint(level: 0.12, lowPower: false, charging: false).pulses)
        XCTAssertFalse(BatteryColorMap.tint(level: 0.12, lowPower: false, charging: true).pulses)
        XCTAssertFalse(BatteryColorMap.tint(level: 0.30, lowPower: false, charging: false).pulses)
        XCTAssertFalse(BatteryColorMap.tint(level: 0.12, lowPower: true, charging: false).pulses)
        for step in 0..<50 {
            let value = BatteryColorMap.pulse(Double(step) * 0.1)
            XCTAssertGreaterThanOrEqual(value, 0.55 - 0.0001)
            XCTAssertLessThanOrEqual(value, 1 + 0.0001)
        }
    }

    func testHighlightIsLighter() {
        let tint = BatteryColorMap.tint(level: 0.8, lowPower: false, charging: false)
        XCTAssertGreaterThan(tint.highlight.blue, tint.color.blue)
    }

    // MARK: Status line

    func testStatusLines() {
        XCTAssertEqual(BatteryStatusText.line(percent: 60, charging: true, onPower: true, charged: false,
                                              watts: 67, minutesToFull: 48, minutesToEmpty: nil),
                       "充电中 · 67W · 约 48 分钟充满")
        XCTAssertEqual(BatteryStatusText.line(percent: 60, charging: true, onPower: true, charged: false,
                                              watts: nil, minutesToFull: -1, minutesToEmpty: nil),
                       "充电中")
        XCTAssertEqual(BatteryStatusText.line(percent: 100, charging: false, onPower: true, charged: true,
                                              watts: 67, minutesToFull: 0, minutesToEmpty: nil),
                       "已充满")
        XCTAssertEqual(BatteryStatusText.line(percent: 80, charging: false, onPower: true, charged: false,
                                              watts: 96, minutesToFull: nil, minutesToEmpty: nil),
                       "已接电源 · 96W · 暂未充电")
        XCTAssertEqual(BatteryStatusText.line(percent: 40, charging: false, onPower: false, charged: false,
                                              watts: nil, minutesToFull: nil, minutesToEmpty: 121),
                       "使用电池 · 还能用约 2 小时")
        XCTAssertEqual(BatteryStatusText.line(percent: 40, charging: false, onPower: false, charged: false,
                                              watts: nil, minutesToFull: nil, minutesToEmpty: 65535),
                       "使用电池")
    }

    func testDurations() {
        XCTAssertEqual(BatteryStatusText.duration(minutes: 48), "48 分钟")
        XCTAssertEqual(BatteryStatusText.duration(minutes: 0), "1 分钟")
        XCTAssertEqual(BatteryStatusText.duration(minutes: 60), "1 小时")
        XCTAssertEqual(BatteryStatusText.duration(minutes: 86), "1 小时 25 分钟")
        XCTAssertEqual(BatteryStatusText.duration(minutes: 178), "3 小时")
    }

    // MARK: Health

    func testHealth() {
        XCTAssertEqual(BatteryHealth.maximumCapacityPercent(rawMax: 4200, design: 5000, maxCapacity: 100), 84)
        XCTAssertEqual(BatteryHealth.maximumCapacityPercent(rawMax: 5100, design: 5000, maxCapacity: nil), 100)
        XCTAssertEqual(BatteryHealth.maximumCapacityPercent(rawMax: nil, design: nil, maxCapacity: 91), 91)
        XCTAssertEqual(BatteryHealth.maximumCapacityPercent(rawMax: nil, design: 6000, maxCapacity: 4800), 80)
        XCTAssertNil(BatteryHealth.maximumCapacityPercent(rawMax: nil, design: nil, maxCapacity: 4800))
        XCTAssertNil(BatteryHealth.maximumCapacityPercent(rawMax: 0, design: 0, maxCapacity: 0))

        XCTAssertEqual(BatteryHealth.cycleCount(312), 312)
        XCTAssertNil(BatteryHealth.cycleCount(-1))
        XCTAssertNil(BatteryHealth.cycleCount(nil))

        XCTAssertEqual(BatteryHealth.celsius(raw: 3050)!, 30.5, accuracy: 0.001)
        XCTAssertNil(BatteryHealth.celsius(raw: 0))
        XCTAssertNil(BatteryHealth.celsius(raw: 29815))
        XCTAssertEqual(BatteryHealth.celsiusText(30.5), "30.5°C")
    }

    // MARK: Motion

    func testMotionPolicy() {
        let visible = BatteryMotion.Host.card(visible: true)
        let hidden = BatteryMotion.Host.card(visible: false)
        func fps(_ look: BatteryLook, charging: Bool = false, pulsing: Bool = false, flourish: Bool = false,
                 host: BatteryMotion.Host = visible, reduce: Bool = false) -> Double? {
            BatteryMotion.framesPerSecond(look: look, charging: charging, pulsing: pulsing,
                                          flourish: flourish, host: host, reduceMotion: reduce)
        }
        XCTAssertEqual(fps(.liquid, charging: true), 30)
        XCTAssertEqual(fps(.liquid), 10)
        XCTAssertNil(fps(.liquid, charging: true, host: hidden))
        XCTAssertNil(fps(.liquid, charging: true, reduce: true))
        XCTAssertNil(fps(.liquid, charging: true, host: .panel, reduce: true))
        XCTAssertEqual(fps(.liquid, host: .panel), 10)
        XCTAssertNil(fps(.classic, charging: true))
        XCTAssertNil(fps(.pixel))
        XCTAssertEqual(fps(.pixel, pulsing: true), 10)
        XCTAssertEqual(fps(.panda, flourish: true), 30)
        for look in BatteryLook.allCases {
            for charging in [false, true] {
                if let value = fps(look, charging: charging, pulsing: true, flourish: true, host: .panel) {
                    XCTAssertLessThanOrEqual(value, BatteryMotion.maxFPS)
                }
            }
        }
    }

    func testChargeSpeedAndFlourish() {
        XCTAssertEqual(BatteryMotion.chargeSpeed(watts: nil), 1)
        XCTAssertEqual(BatteryMotion.chargeSpeed(watts: 60), 1)
        XCTAssertEqual(BatteryMotion.chargeSpeed(watts: 5), 0.4)
        XCTAssertEqual(BatteryMotion.chargeSpeed(watts: 140), 1.6)
        XCTAssertLessThan(BatteryMotion.chargeSpeed(watts: 30), BatteryMotion.chargeSpeed(watts: 96))

        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(BatteryMotion.isFlourishing(pluggedAt: now.addingTimeInterval(-0.5), fullAt: nil, now: now))
        XCTAssertFalse(BatteryMotion.isFlourishing(pluggedAt: now.addingTimeInterval(-5), fullAt: nil, now: now))
        XCTAssertTrue(BatteryMotion.isFlourishing(pluggedAt: nil, fullAt: now.addingTimeInterval(-2), now: now))
        XCTAssertFalse(BatteryMotion.isFlourishing(pluggedAt: nil, fullAt: nil, now: now))
    }

    func testSurfaceStaysInsideTheGauge() {
        for level in [0.0, 0.02, 0.5, 0.98, 1.0] {
            for step in 0..<40 {
                for layer in 0...1 {
                    let lift = BatteryMotion.surface(x: Double(step) / 40, t: Double(step) * 0.37,
                                                     level: level, layer: layer, speed: 1.6)
                    XCTAssertLessThanOrEqual(abs(lift), 0.035 + 0.0001)
                }
            }
        }
    }

    func testPixelCells() {
        XCTAssertEqual(BatteryMotion.pixelCells(level: 0, charging: false, t: 0), 0)
        XCTAssertEqual(BatteryMotion.pixelCells(level: 0.18, charging: false, t: 0), 1)
        XCTAssertEqual(BatteryMotion.pixelCells(level: 0.41, charging: false, t: 0), 3)
        XCTAssertEqual(BatteryMotion.pixelCells(level: 1, charging: false, t: 0), 5)
        // Charging climbs from the level to five and starts again.
        let seen = Set((0..<40).map { BatteryMotion.pixelCells(level: 0.41, charging: true, t: Double($0) * 0.1) })
        XCTAssertEqual(seen, [3, 4, 5])
        XCTAssertEqual(BatteryMotion.pixelCells(level: 1, charging: true, t: 3), 5)
    }

    // MARK: History

    private let base = Date(timeIntervalSince1970: 1_800_000_000) // on a 5-minute boundary

    func testHistoryCompressesRepeatsIntoRuns() {
        var history = BatteryHistory()
        for i in 0..<12 {
            history.record(percent: 100, charging: false, at: base.addingTimeInterval(Double(i) * 300))
        }
        XCTAssertEqual(history.runs.count, 1)
        XCTAssertEqual(history.sampleCount, 12)
        history.record(percent: 99, charging: false, at: base.addingTimeInterval(12 * 300))
        XCTAssertEqual(history.runs.count, 2)
    }

    func testHistoryKeepsOneSamplePerSlotAndIgnoresTheClockGoingBack() {
        var history = BatteryHistory()
        XCTAssertTrue(history.record(percent: 50, charging: false, at: base))
        XCTAssertFalse(history.record(percent: 49, charging: false, at: base.addingTimeInterval(120)))
        XCTAssertFalse(history.wants(base.addingTimeInterval(299)))
        XCTAssertTrue(history.wants(base.addingTimeInterval(300)))
        XCTAssertTrue(history.record(percent: 49, charging: false, at: base.addingTimeInterval(300)))
        XCTAssertFalse(history.record(percent: 80, charging: false, at: base.addingTimeInterval(-600)))
        XCTAssertEqual(history.samples(from: base, to: base.addingTimeInterval(600)).map(\.percent), [50, 49])
    }

    func testHistoryPrunesAfterTwoDays() {
        var history = BatteryHistory()
        history.record(percent: 70, charging: false, at: base)
        history.record(percent: 70, charging: false, at: base.addingTimeInterval(300))
        let later = base.addingTimeInterval(BatteryHistory.keep + 300)
        history.record(percent: 60, charging: false, at: later)
        XCTAssertEqual(history.runs.count, 1)
        XCTAssertEqual(history.runs.first?.percent, 60)
        // A run straddling the cut is trimmed, not dropped.
        var long = BatteryHistory()
        for i in 0..<10 { long.record(percent: 90, charging: true, at: base.addingTimeInterval(Double(i) * 300)) }
        long.prune(before: BatteryHistory.slot(of: base) + 4)
        XCTAssertEqual(long.sampleCount, 6)
    }

    func testSegmentsBreakAtGaps() {
        var history = BatteryHistory()
        history.record(percent: 80, charging: false, at: base)
        history.record(percent: 79, charging: false, at: base.addingTimeInterval(300))
        // Asleep for an hour.
        history.record(percent: 75, charging: false, at: base.addingTimeInterval(3900))
        history.record(percent: 74, charging: false, at: base.addingTimeInterval(4200))
        let segments = history.segments(from: base, to: base.addingTimeInterval(86400))
        XCTAssertEqual(segments.map { $0.map(\.percent) }, [[80, 79], [75, 74]])
        // The query window cuts samples outside it.
        XCTAssertEqual(history.samples(from: base.addingTimeInterval(1), to: base.addingTimeInterval(3900)).count, 1)
    }

    func testChargingSpans() {
        var history = BatteryHistory()
        history.record(percent: 20, charging: false, at: base)
        history.record(percent: 22, charging: true, at: base.addingTimeInterval(300))
        history.record(percent: 30, charging: true, at: base.addingTimeInterval(600))
        history.record(percent: 31, charging: false, at: base.addingTimeInterval(900))
        history.record(percent: 33, charging: true, at: base.addingTimeInterval(1800))
        let spans = history.chargingSpans(from: base, to: base.addingTimeInterval(86400))
        XCTAssertEqual(spans.count, 2)
        XCTAssertEqual(spans[0].start, base.addingTimeInterval(300))
        XCTAssertEqual(spans[0].end, base.addingTimeInterval(900))
        XCTAssertEqual(spans[1].duration, 300)
    }

    func testHistoryRoundTripsThroughJSON() throws {
        var history = BatteryHistory()
        history.record(percent: 55, charging: true, at: base)
        let data = try JSONEncoder().encode(history)
        XCTAssertEqual(try JSONDecoder().decode(BatteryHistory.self, from: data), history)
    }
}
