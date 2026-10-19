import XCTest

/// 电池格沙漏和仅图标大号数字的纯计算。
final class BatteryHourglassTests: XCTestCase {
    private let purple = ColorCode(hex: "#BF5AF2")!

    // MARK: 沙量

    func testSandHeightFollowsLevelLinearly() {
        XCTAssertEqual(BatteryHourglass.sandHeight(level: 1, present: true), 0.92, accuracy: 1e-9)
        XCTAssertEqual(BatteryHourglass.sandHeight(level: 0.5, present: true), 0.46, accuracy: 1e-9)
        XCTAssertEqual(BatteryHourglass.sandHeight(level: 0.45, present: true), 0.92 * 0.45, accuracy: 1e-9)
        let low = BatteryHourglass.sandHeight(level: 0.2, present: true)
        let high = BatteryHourglass.sandHeight(level: 0.8, present: true)
        XCTAssertLessThan(low, high)
    }

    func testSandHeightKeepsThinLayerAndClamps() {
        XCTAssertEqual(BatteryHourglass.sandHeight(level: 0.01, present: true), 0.92 * 0.05, accuracy: 1e-9)
        XCTAssertEqual(BatteryHourglass.sandHeight(level: 0, present: true), 0.92 * 0.05, accuracy: 1e-9)
        XCTAssertEqual(BatteryHourglass.sandHeight(level: 1.4, present: true), 0.92, accuracy: 1e-9)
    }

    func testAbsentDeviceHasNoSand() {
        XCTAssertEqual(BatteryHourglass.sandHeight(level: 0.7, present: false), 0)
        XCTAssertEqual(BatteryHourglass.sandHeight(level: .nan, present: true), 0)
        XCTAssertEqual(BatteryHourglass.topSand(level: 0.3, charging: true, present: false), 0)
    }

    func testTopSandOnlyWhileCharging() {
        XCTAssertEqual(BatteryHourglass.topSand(level: 0.45, charging: false, present: true), 0)
        let charging = BatteryHourglass.topSand(level: 0.45, charging: true, present: true)
        XCTAssertEqual(charging, 0.55 * 0.85, accuracy: 1e-9)
        // 快充满时也留一点，看得出在流。
        XCTAssertEqual(BatteryHourglass.topSand(level: 0.98, charging: true, present: true), 0.12, accuracy: 1e-9)
        XCTAssertGreaterThan(BatteryHourglass.topSand(level: 0.2, charging: true, present: true), charging)
    }

    func testMoundRisesWhileCharging() {
        XCTAssertGreaterThan(BatteryHourglass.moundHeight(charging: true), BatteryHourglass.moundHeight(charging: false))
    }

    // MARK: 帧率

    func testAnimatesOnlyWhileChargingAndVisible() {
        XCTAssertEqual(BatteryHourglass.framesPerSecond(charging: true, present: true, visible: true,
                                                        reduceMotion: false), 20)
        XCTAssertNil(BatteryHourglass.framesPerSecond(charging: false, present: true, visible: true, reduceMotion: false))
        XCTAssertNil(BatteryHourglass.framesPerSecond(charging: true, present: true, visible: false, reduceMotion: false))
        XCTAssertNil(BatteryHourglass.framesPerSecond(charging: true, present: false, visible: true, reduceMotion: false))
    }

    func testReduceMotionIsStill() {
        XCTAssertNil(BatteryHourglass.framesPerSecond(charging: true, present: true, visible: true, reduceMotion: true))
    }

    func testFrameRateStaysFrugal() {
        XCTAssertGreaterThanOrEqual(BatteryHourglass.framesPerSecond, 20)
        XCTAssertLessThanOrEqual(BatteryHourglass.framesPerSecond, 24)
    }

    // MARK: 颜色

    func testDefaultSandIsRedYellowGreen() {
        XCTAssertEqual(BatteryHourglass.sandColor(level: 0.45, charging: true, lowPower: false, present: true,
                                                  theme: nil), BatteryLiquidFX.green)
        XCTAssertEqual(BatteryHourglass.sandColor(level: 0.8, charging: false, lowPower: false, present: true,
                                                  theme: nil), BatteryLiquidFX.green)
        XCTAssertEqual(BatteryHourglass.sandColor(level: 0.12, charging: false, lowPower: false, present: true,
                                                  theme: nil), BatteryTheme.warningRed)
        XCTAssertEqual(BatteryHourglass.sandColor(level: 0.35, charging: false, lowPower: true, present: true,
                                                  theme: nil), BatteryColorMap.lowPowerYellow)
    }

    func testChargingLowBatteryIsNotRed() {
        XCTAssertEqual(BatteryHourglass.sandColor(level: 0.1, charging: true, lowPower: false, present: true,
                                                  theme: nil), BatteryLiquidFX.green)
    }

    func testThemeColorsAllSandEvenWhenLow() {
        let rgb = BatteryRGB(purple.red, purple.green, purple.blue)
        for level in [0.12, 0.45, 0.8] {
            for charging in [false, true] {
                XCTAssertEqual(BatteryHourglass.sandColor(level: level, charging: charging, lowPower: false,
                                                          present: true, theme: purple), rgb)
            }
        }
        XCTAssertEqual(BatteryHourglass.sandColor(level: 0.35, charging: false, lowPower: true, present: true,
                                                  theme: purple), rgb)
    }

    func testNumberTurnsRedAtTwentyPercentUncharged() {
        XCTAssertTrue(BatteryHourglass.numberWarns(level: 0.12, charging: false, present: true))
        XCTAssertTrue(BatteryHourglass.numberWarns(level: 0.20, charging: false, present: true))
        XCTAssertFalse(BatteryHourglass.numberWarns(level: 0.21, charging: false, present: true))
        XCTAssertFalse(BatteryHourglass.numberWarns(level: 0.12, charging: true, present: true))
        XCTAssertFalse(BatteryHourglass.numberWarns(level: 0, charging: false, present: false))
    }

    // MARK: 仅图标 · 数字放不放得下

    func testRoomyKeepsSignAndSize() {
        let fit = BatteryHourglass.readingFit(available: 80, label: "76", fontSize: 20, charging: false)
        XCTAssertEqual(fit, .init(showsSign: true, scale: 1))
    }

    func testDropsSignBeforeShrinking() {
        // “100%” 20pt 约 47 宽，“100” 约 37 宽。
        let full = BatteryHourglass.readingWidth(label: "100", fontSize: 20, sign: true, charging: false)
        let bare = BatteryHourglass.readingWidth(label: "100", fontSize: 20, sign: false, charging: false)
        XCTAssertLessThan(bare, full)
        let fit = BatteryHourglass.readingFit(available: (full + bare) / 2, label: "100", fontSize: 20, charging: false)
        XCTAssertEqual(fit, .init(showsSign: false, scale: 1))
    }

    func testShrinksAfterDroppingSign() {
        let bare = BatteryHourglass.readingWidth(label: "100", fontSize: 20, sign: false, charging: true)
        let fit = BatteryHourglass.readingFit(available: bare * 0.8, label: "100", fontSize: 20, charging: true)
        XCTAssertFalse(fit.showsSign)
        XCTAssertEqual(fit.scale, 0.8, accuracy: 1e-9)
    }

    func testNeverShrinksBelowThirteenPoints() {
        let fit = BatteryHourglass.readingFit(available: 4, label: "100", fontSize: 20, charging: true)
        XCTAssertFalse(fit.showsSign)
        XCTAssertEqual(fit.scale * 20, 13, accuracy: 1e-9)
        XCTAssertEqual(BatteryHourglass.readingFit(available: 4, label: "100", fontSize: 13, charging: false).scale, 1)
    }

    func testChargingBoltTakesRoom() {
        let plain = BatteryHourglass.readingWidth(label: "76", fontSize: 20, sign: true, charging: false)
        let charging = BatteryHourglass.readingWidth(label: "76", fontSize: 20, sign: true, charging: true)
        XCTAssertGreaterThan(charging, plain)
    }

    func testAbsentReadingHasNoSign() {
        let fit = BatteryHourglass.readingFit(available: 80, label: "-", fontSize: 20, charging: false, present: false)
        XCTAssertFalse(fit.showsSign)
    }

    func testIconSlotFitsHundredPercentAtDesignSize() {
        // 环 30 + 间距 5，剩下的给数字：不充电的“100%”整个放得下。
        let room = Double(BatteryHourglass.iconSlotWidth - 35)
        XCTAssertTrue(BatteryHourglass.readingFit(available: room, label: "100", fontSize: 20, charging: false).showsSign)
    }

    func testIconCardWidthGrowsPerSlot() {
        XCTAssertEqual(BatteryHourglass.iconCardWidth(slots: 1), 104)
        XCTAssertEqual(BatteryHourglass.iconCardWidth(slots: 3), 3 * 84 + 2 * 8 + 20)
        XCTAssertEqual(BatteryHourglass.iconCardWidth(slots: 0), 104)
    }
}

extension BatteryHourglassTests {
    func testIconCardIsWideEnoughForReadings() {
        let icon = WidgetConfig(["layout": .string("icon"), "devices": .list([.string("mac")])])
        let size = WidgetCatalog.naturalSize(WidgetInstance(kind: .battery, config: icon))
        XCTAssertEqual(Double(size.width), BatteryHourglass.iconCardWidth(slots: BatteryShelf.slotCount(icon)))
        let gauge = WidgetConfig(["layout": .string("gauge"), "devices": .list([.string("mac")])])
        let gaugeSize = WidgetCatalog.naturalSize(WidgetInstance(kind: .battery, config: gauge))
        XCTAssertGreaterThan(size.width, gaugeSize.width)
    }
}
