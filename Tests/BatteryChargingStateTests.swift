import XCTest

final class BatteryChargingStateTests: XCTestCase {
    func testPowerSourceYesWins() {
        XCTAssertTrue(BatteryChargingState.isCharging(powerSourceSays: true, onPower: true, charged: false,
                                                      registryIsCharging: nil, amperage: nil))
    }

    func testRegistrySaysChargingOnAdapter() {
        XCTAssertTrue(BatteryChargingState.isCharging(powerSourceSays: false, onPower: true, charged: false,
                                                      registryIsCharging: true, amperage: nil))
    }

    func testCurrentIntoBatteryCounts() {
        XCTAssertTrue(BatteryChargingState.isCharging(powerSourceSays: false, onPower: true, charged: false,
                                                      registryIsCharging: false, amperage: 2400))
    }

    func testTrickleAndDischargeDoNotCount() {
        XCTAssertFalse(BatteryChargingState.isCharging(powerSourceSays: false, onPower: true, charged: false,
                                                       registryIsCharging: false, amperage: 20))
        XCTAssertFalse(BatteryChargingState.isCharging(powerSourceSays: false, onPower: true, charged: false,
                                                       registryIsCharging: nil, amperage: -800))
    }

    func testOnBatteryOrChargedNeverCharging() {
        XCTAssertFalse(BatteryChargingState.isCharging(powerSourceSays: false, onPower: false, charged: false,
                                                       registryIsCharging: true, amperage: 2000))
        XCTAssertFalse(BatteryChargingState.isCharging(powerSourceSays: false, onPower: true, charged: true,
                                                       registryIsCharging: true, amperage: 2000))
    }
}
