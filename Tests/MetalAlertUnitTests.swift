import XCTest

/// 黄金白银切换单位后，提醒价跟着按汇率和克/盎司换算。
final class MetalAlertUnitTests: XCTestCase {
    private let rate = 7.2

    private func config(_ alerts: [String], unit: PreciousMetal.DisplayUnit,
                        alertUnit: PreciousMetal.DisplayUnit? = nil, fired: [String] = []) -> WidgetConfig {
        var values: [String: WidgetConfig.Value] = [
            "alerts": .list(alerts.map { .string($0) }),
            "metalUnit": .string(unit.rawValue),
            "alertsFired": .list(fired.map { .string($0) }),
        ]
        if let alertUnit { values[PreciousMetal.alertUnitKey] = .string(alertUnit.rawValue) }
        return WidgetConfig(values)
    }

    func testConvertedRoundTrips() {
        let cny = PreciousMetal.converted(3110.35, from: .usdPerOunce, to: .cnyPerGram, usdToCny: rate)!
        XCTAssertEqual(cny, 720, accuracy: 0.0001)
        let usd = PreciousMetal.converted(cny, from: .cnyPerGram, to: .usdPerOunce, usdToCny: rate)!
        XCTAssertEqual(usd, 3110.35, accuracy: 0.0001)
        XCTAssertEqual(PreciousMetal.converted(5, from: .usdPerOunce, to: .usdPerOunce, usdToCny: nil), 5)
        XCTAssertNil(PreciousMetal.converted(5, from: .usdPerOunce, to: .cnyPerGram, usdToCny: nil))
    }

    func testRounding() {
        XCTAssertEqual(PreciousMetal.roundedAlertPrice(780.5251), 780.53)
        XCTAssertEqual(PreciousMetal.roundedAlertPrice(9.87654), 9.877)
    }

    func testSwitchingConvertsMetalAlertsOnly() {
        let start = config(["GC=F>720", "AAPL<200", "SI=F<9"], unit: .cnyPerGram)
        let next = PreciousMetal.switching(start, to: .usdPerOunce, usdToCny: rate)
        XCTAssertEqual(next.string("metalUnit"), "usdPerOunce")
        XCTAssertEqual(next.string(PreciousMetal.alertUnitKey), "usdPerOunce")
        let alerts = StockBoard.alerts(next)
        XCTAssertEqual(alerts.map(\.symbol), ["GC=F", "AAPL", "SI=F"])
        XCTAssertEqual(alerts[0].price, 3110.35, accuracy: 0.01)
        XCTAssertTrue(alerts[0].above)
        XCTAssertEqual(alerts[1].price, 200)
        XCTAssertEqual(alerts[2].price, 38.88, accuracy: 0.01)
        XCTAssertFalse(alerts[2].above)
        // 换回来回到原来的数。
        let back = PreciousMetal.switching(next, to: .cnyPerGram, usdToCny: rate)
        XCTAssertEqual(StockBoard.alerts(back)[0].price, 720, accuracy: 0.01)
        XCTAssertEqual(StockBoard.alerts(back)[2].price, 9, accuracy: 0.01)
    }

    func testFiredRecordFollowsConversion() {
        let start = config(["GC=F>720"], unit: .cnyPerGram, fired: ["GC=F>720"])
        let next = PreciousMetal.switching(start, to: .usdPerOunce, usdToCny: rate)
        let alerts = StockBoard.alerts(next)
        XCTAssertEqual(next.strings("alertsFired"), alerts.map(\.text))
        // 换算后不会被当成一条新提醒再响一遍。
        XCTAssertTrue(StockBoard.newlyReached(alerts, prices: ["GC=F": 3200], fired: Set(next.strings("alertsFired"))).isEmpty)
    }

    func testSwitchWithoutRateWaitsAndSkipsChecks() {
        let start = config(["GC=F>3000"], unit: .usdPerOunce)
        let next = PreciousMetal.switching(start, to: .cnyPerGram, usdToCny: nil)
        XCTAssertEqual(next.string("metalUnit"), "cnyPerGram")
        XCTAssertEqual(PreciousMetal.alertUnit(next), .usdPerOunce)
        XCTAssertTrue(PreciousMetal.alertsPending(next))
        XCTAssertEqual(StockBoard.alerts(next)[0].price, 3000)
        // 没汇率时显示的仍是美元/盎司，提醒价也是美元/盎司，照样能比。
        XCTAssertTrue(PreciousMetal.canCheck(StockBoard.alerts(next)[0], config: next, usdToCny: nil))
        // 汇率到了再换。
        let settled = PreciousMetal.reconciled(next, usdToCny: rate)!
        XCTAssertFalse(PreciousMetal.alertsPending(settled))
        XCTAssertEqual(StockBoard.alerts(settled)[0].price, 694.46, accuracy: 0.01)
        XCTAssertNil(PreciousMetal.reconciled(settled, usdToCny: rate))
    }

    func testCannotCheckWhenShownUnitDiffers() {
        // 提醒价记的是元/克，汇率没了，卡片退回显示美元/盎司：不能拿 3000 去比 720。
        let config = config(["GC=F>720", "AAPL>1"], unit: .cnyPerGram, alertUnit: .cnyPerGram)
        let alerts = StockBoard.alerts(config)
        XCTAssertFalse(PreciousMetal.canCheck(alerts[0], config: config, usdToCny: nil))
        XCTAssertTrue(PreciousMetal.canCheck(alerts[0], config: config, usdToCny: rate))
        XCTAssertTrue(PreciousMetal.canCheck(alerts[1], config: config, usdToCny: nil))
    }

    func testLegacyConfigGetsStamped() {
        let legacy = config(["GC=F>720"], unit: .cnyPerGram)
        XCTAssertEqual(PreciousMetal.alertUnit(legacy), .cnyPerGram)
        let stamped = PreciousMetal.reconciled(legacy, usdToCny: nil)!
        XCTAssertEqual(stamped.string(PreciousMetal.alertUnitKey), "cnyPerGram")
        XCTAssertEqual(StockBoard.alerts(stamped)[0].price, 720)
        // 没有黄金白银提醒的不写。
        XCTAssertNil(PreciousMetal.reconciled(config(["AAPL>1"], unit: .cnyPerGram), usdToCny: rate))
    }

    func testSettingsPickerChangeIsReconciledLater() {
        // 设置窗口里直接改了 metalUnit，提醒价单位还记着旧的。
        let changed = config(["SI=F>40"], unit: .cnyPerGram, alertUnit: .usdPerOunce)
        let settled = PreciousMetal.reconciled(changed, usdToCny: rate)!
        XCTAssertEqual(StockBoard.alerts(settled)[0].price, 9.259, accuracy: 0.001)
    }

    func testStoredAlertPrice() {
        let pending = config([], unit: .cnyPerGram, alertUnit: .cnyPerGram)
        XCTAssertEqual(PreciousMetal.storedAlertPrice(237, symbol: "AAPL", config: pending, usdToCny: nil), 237)
        XCTAssertEqual(PreciousMetal.storedAlertPrice(720, symbol: "GC=F", config: pending, usdToCny: rate), 720)
        // 显示的是美元/盎司（没汇率），提醒价按元/克记：换不过去，不让加。
        XCTAssertNil(PreciousMetal.storedAlertPrice(3000, symbol: "GC=F", config: pending, usdToCny: nil))
    }

    func testNotificationRoute() {
        let id = UUID()
        let info: [AnyHashable: Any] = NotificationRoute.userInfo(widget: id)
        XCTAssertEqual(NotificationRoute.widgetID(from: info), id)
        XCTAssertNil(NotificationRoute.widgetID(from: [:]))
        XCTAssertNil(NotificationRoute.widgetID(from: [NotificationRoute.widgetKey: "nope"]))
    }
}
