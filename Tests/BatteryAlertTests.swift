import XCTest

/// Battery reminders: each level once per charge, nothing for levels already passed.
final class BatteryAlertTests: XCTestCase {
    private let defaults = BatteryAlertSettings()

    private func run(_ tracker: inout BatteryAlertTracker, _ percent: Int, power: Bool,
                     settings: BatteryAlertSettings? = nil, celsius: Double? = nil,
                     now: Date = .now) -> [String] {
        tracker.check(BatteryReading(percent: percent, onPower: power, celsius: celsius),
                      accessories: [], settings: settings ?? defaults, now: now).map(\.id)
    }

    func testDefaultsFromEmptyConfig() {
        XCTAssertEqual(BatteryAlertSettings(config: WidgetConfig()), BatteryAlertSettings())
    }

    func testChargeOncePerCharge() {
        var t = BatteryAlertTracker()
        XCTAssertEqual(run(&t, 60, power: true), [])
        XCTAssertEqual(run(&t, 80, power: true), ["charge"])
        XCTAssertEqual(run(&t, 81, power: true), [])
        XCTAssertEqual(run(&t, 70, power: false), [])
        XCTAssertEqual(run(&t, 70, power: true), [])
        XCTAssertEqual(run(&t, 80, power: true), ["charge"])
    }

    func testPluggingInAboveLevelIsQuiet() {
        var t = BatteryAlertTracker()
        XCTAssertEqual(run(&t, 85, power: true), [])
        XCTAssertEqual(run(&t, 90, power: true), [])
    }

    func testOptionalLevels() {
        var t = BatteryAlertTracker()
        let s = BatteryAlertSettings(charge: [80, 90, 95])
        _ = run(&t, 50, power: true, settings: s)
        XCTAssertEqual(run(&t, 90, power: true, settings: s), ["charge"])
        XCTAssertEqual(run(&t, 95, power: true, settings: s), ["charge"])
    }

    func testLowBattery() {
        var t = BatteryAlertTracker()
        _ = run(&t, 50, power: false)
        XCTAssertEqual(run(&t, 20, power: false), ["low"])
        XCTAssertEqual(run(&t, 10, power: false), [])
        let s = BatteryAlertSettings(low: [20, 10])
        var u = BatteryAlertTracker()
        _ = run(&u, 30, power: false, settings: s)
        XCTAssertEqual(run(&u, 19, power: false, settings: s), ["low"])
        XCTAssertEqual(run(&u, 10, power: false, settings: s), ["low"])
    }

    func testFullForTwoHours() {
        var t = BatteryAlertTracker()
        let s = BatteryAlertSettings(full: true)
        let start = Date(timeIntervalSince1970: 0)
        _ = run(&t, 99, power: true, settings: s, now: start)
        XCTAssertEqual(run(&t, 100, power: true, settings: s, now: start), [])
        XCTAssertEqual(run(&t, 100, power: true, settings: s, now: start + 7300), ["full"])
        XCTAssertEqual(run(&t, 100, power: true, settings: s, now: start + 9000), [])
    }

    func testHotOnceUntilCooled() {
        var t = BatteryAlertTracker()
        let s = BatteryAlertSettings(hot: true)
        XCTAssertEqual(run(&t, 50, power: true, settings: s, celsius: 41), ["hot"])
        XCTAssertEqual(run(&t, 50, power: true, settings: s, celsius: 42), [])
        _ = run(&t, 50, power: true, settings: s, celsius: 30)
        XCTAssertEqual(run(&t, 50, power: true, settings: s, celsius: 41), ["hot"])
    }

    func testAccessory() {
        var t = BatteryAlertTracker()
        func check(_ p: Int) -> [String] {
            t.check(nil, accessories: [AccessoryReading(id: "mouse", name: "妙控鼠标", percent: p)],
                    settings: defaults).map(\.id)
        }
        XCTAssertEqual(check(40), [])
        XCTAssertEqual(check(15), ["accessory.mouse"])
        XCTAssertEqual(check(10), [])
        XCTAssertEqual(check(20), [])
        XCTAssertEqual(check(14), [])
        XCTAssertEqual(check(80), [])
        XCTAssertEqual(check(12), ["accessory.mouse"])
    }
}
