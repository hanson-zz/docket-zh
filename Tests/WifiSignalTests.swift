import XCTest

final class WifiSignalTests: XCTestCase {
    func testPercentClampsToTheRange() {
        XCTAssertEqual(WifiQuality.percent(rssi: -100), 0)
        XCTAssertEqual(WifiQuality.percent(rssi: -90), 0)
        XCTAssertEqual(WifiQuality.percent(rssi: -60), 50)
        XCTAssertEqual(WifiQuality.percent(rssi: -30), 100)
        XCTAssertEqual(WifiQuality.percent(rssi: -10), 100)
    }

    func testBarsAndLabels() {
        XCTAssertEqual(WifiQuality.bars(rssi: -50), 4)
        XCTAssertEqual(WifiQuality.bars(rssi: -60), 3)
        XCTAssertEqual(WifiQuality.bars(rssi: -70), 2)
        XCTAssertEqual(WifiQuality.bars(rssi: -80), 1)
        XCTAssertEqual(WifiQuality.bars(rssi: -88), 0)
        XCTAssertEqual(WifiQuality.label(rssi: -60), "良好")
    }

    func testSNRNeedsANoiseReading() {
        XCTAssertEqual(WifiQuality.snr(rssi: -55, noise: -92), 37)
        XCTAssertNil(WifiQuality.snr(rssi: -55, noise: 0))
    }

    func testOnlyClassicIsFree() {
        XCTAssertEqual(WifiRingStyle.allCases, [.classic, .numeric])
        XCTAssertFalse(WidgetCatalog.isSupporterOnly(["layout": .string("wifi")]))
        XCTAssertTrue(WidgetCatalog.isSupporterOnly(["layout": .string("wifiNumeric")]))
        XCTAssertEqual(WifiRingStyle.shown(layout: "wifiNumeric", unlocked: false), .classic)
        XCTAssertEqual(WifiRingStyle.shown(layout: "wifiNumeric", unlocked: true), .numeric)
        XCTAssertNil(WifiRingStyle.shown(layout: "speed", unlocked: true))
    }

    func testDottedAndThinFoldIntoClassic() {
        for legacy in ["wifiDotted", "wifiThin"] {
            // 旧值读成经典，不是 nil（否则卡片会退回网速外观），也不再算 Pro。
            XCTAssertEqual(WifiRingStyle.from(layout: legacy), .classic, legacy)
            XCTAssertEqual(WifiRingStyle.shown(layout: legacy, unlocked: true), .classic, legacy)
            XCTAssertEqual(WifiRingStyle.shown(layout: legacy, unlocked: false), .classic, legacy)
            XCTAssertFalse(WidgetCatalog.isSupporterOnly(["layout": .string(legacy)]), legacy)
            XCTAssertFalse(ProFeatures.isSupporterStyle(["layout": .string(legacy)]), legacy)
        }
    }

    func testMigrationRewritesOnlyTheLegacyLayouts() {
        for legacy in ["wifiDotted", "wifiThin"] {
            var old = WidgetConfig()
            old.set("layout", .string(legacy))
            old.set("unit", .string("mbps"))
            let moved = WifiRingStyle.migrating(old)
            XCTAssertEqual(moved.string("layout", default: ""), "wifi", legacy)
            XCTAssertEqual(moved.string("unit", default: ""), "mbps", "其余配置原样保留")
            XCTAssertEqual(WifiRingStyle.migrating(moved), moved, "迁一次就够")
            XCTAssertEqual(WidgetCatalog.variantTitle(matching: moved, kind: .network), "Wi-Fi 经典")
        }
        for layout in ["wifi", "wifiNumeric", "speed", "chart"] {
            var config = WidgetConfig()
            config.set("layout", .string(layout))
            XCTAssertEqual(WifiRingStyle.migrating(config), config, layout)
        }
        XCTAssertEqual(WifiRingStyle.migrating(WidgetConfig()), WidgetConfig())
    }

    func testStoredLegacyCardsDecodeAsClassic() throws {
        var stored = WidgetConfig()
        stored.set("layout", .string("wifiThin"))
        let data = try JSONEncoder().encode(WidgetInstance(kind: .network, config: stored))
        let instance = try JSONDecoder().decode(WidgetInstance.self, from: data)
        XCTAssertEqual(instance.kind, .network)
        XCTAssertEqual(instance.config.string("layout", default: ""), "wifi")
    }

    func testSignalSummaryUsesTheRealReading() {
        let good = WifiSignalSummary(rssi: -52, rate: 866.4)
        XCTAssertEqual(good.label, WifiQuality.label(rssi: -52))
        XCTAssertEqual(good.level, "-52 dBm · \(WifiQuality.percent(rssi: -52))%")
        XCTAssertEqual(good.level, "-52 dBm · 63%")
        XCTAssertEqual(good.link, "连接 866 Mbps")

        let noRate = WifiSignalSummary(rssi: -70, rate: nil)
        XCTAssertEqual(noRate.level, "-70 dBm · 33%")
        XCTAssertNil(noRate.link)
        XCTAssertNil(WifiSignalSummary(rssi: -70, rate: 0).link)

        let off = WifiSignalSummary(rssi: nil, rate: 866)
        XCTAssertEqual(off.label, "未连接")
        XCTAssertNil(off.level)
        XCTAssertNil(off.link)
        XCTAssertNil(WifiSignalSummary(rssi: 0, rate: nil).level, "0 dBm 是没连上")
    }

    func testTheWifiLayoutsHideTheThroughputOptions() {
        var config = WidgetConfig()
        config.set("layout", .string("wifiNumeric"))
        XCTAssertFalse(WidgetCatalog.applies("chart", to: config, kind: .network))
        XCTAssertFalse(WidgetCatalog.applies("display", to: config, kind: .network))
        XCTAssertEqual(WidgetCatalog.variantTitle(matching: config, kind: .network), "Wi-Fi 数字")
    }
}
