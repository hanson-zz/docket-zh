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
        XCTAssertFalse(WidgetCatalog.isSupporterOnly(["layout": .string("wifi")]))
        for style in ["wifiNumeric", "wifiDotted", "wifiThin"] {
            XCTAssertTrue(WidgetCatalog.isSupporterOnly(["layout": .string(style)]))
        }
        XCTAssertEqual(WifiRingStyle.shown(layout: "wifiThin", unlocked: false), .classic)
        XCTAssertEqual(WifiRingStyle.shown(layout: "wifiThin", unlocked: true), .thin)
        XCTAssertNil(WifiRingStyle.shown(layout: "speed", unlocked: true))
    }

    func testTheWifiLayoutsHideTheThroughputOptions() {
        var config = WidgetConfig()
        config.set("layout", .string("wifiDotted"))
        XCTAssertFalse(WidgetCatalog.applies("chart", to: config, kind: .network))
        XCTAssertFalse(WidgetCatalog.applies("display", to: config, kind: .network))
        XCTAssertEqual(WidgetCatalog.variantTitle(matching: config, kind: .network), "Wi-Fi 点状")
    }
}
