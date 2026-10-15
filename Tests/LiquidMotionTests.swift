import XCTest

/// 液态外观的共用规则：帧率、水位、金光和专注计时的外观键。
final class LiquidMotionTests: XCTestCase {

    func testFramesOnlyWhileVisibleAndMoving() {
        XCTAssertEqual(LiquidMotion.framesPerSecond(visible: true, reduceMotion: false), 10)
        XCTAssertEqual(LiquidMotion.framesPerSecond(visible: true, reduceMotion: false, golden: true), 30)
        XCTAssertNil(LiquidMotion.framesPerSecond(visible: false, reduceMotion: false))
        XCTAssertNil(LiquidMotion.framesPerSecond(visible: true, reduceMotion: true))
        XCTAssertNil(LiquidMotion.framesPerSecond(visible: true, reduceMotion: false, still: true))
    }

    func testLevelIsClamped() {
        XCTAssertEqual(LiquidMotion.level(-1), 0)
        XCTAssertEqual(LiquidMotion.level(2), 1)
        XCTAssertEqual(LiquidMotion.level(.nan), 0)
        XCTAssertEqual(LiquidMotion.level(0.4), 0.4)
    }

    func testTimerFillsAsFocusGoesOn() {
        XCTAssertEqual(LiquidMotion.timerLevel(remaining: 1500, total: 1500), 0)
        XCTAssertEqual(LiquidMotion.timerLevel(remaining: 750, total: 1500), 0.5, accuracy: 1e-9)
        XCTAssertEqual(LiquidMotion.timerLevel(remaining: 0, total: 1500), 1)
        XCTAssertEqual(LiquidMotion.timerLevel(remaining: 10, total: 0), 0)
    }

    func testTimerGlowsForAMinuteAfterTheEnd() {
        XCTAssertFalse(LiquidMotion.timerGolden(secondsSinceEnd: nil))
        XCTAssertFalse(LiquidMotion.timerGolden(secondsSinceEnd: -5), "还在计时")
        XCTAssertTrue(LiquidMotion.timerGolden(secondsSinceEnd: 0))
        XCTAssertTrue(LiquidMotion.timerGolden(secondsSinceEnd: 59))
        XCTAssertFalse(LiquidMotion.timerGolden(secondsSinceEnd: 60))
    }

    func testTimerLookDefaultsToRing() {
        XCTAssertEqual(LiquidMotion.timerLook(WidgetConfig()), .ring)
        XCTAssertEqual(LiquidMotion.timerLook(WidgetConfig(["look": .string("liquid")])), .liquid)
        XCTAssertEqual(LiquidMotion.timerLook(WidgetConfig(["look": .string("x")])), .ring)
    }

    func testBusyMachinesRippleFasterAndTurnRed() {
        XCTAssertEqual(LiquidMotion.busySpeed(0), 1)
        XCTAssertEqual(LiquidMotion.busySpeed(1), 2.2, accuracy: 1e-9)
        XCTAssertFalse(LiquidMotion.isHot(0.84))
        XCTAssertTrue(LiquidMotion.isHot(0.85))
    }

    func testLiquidIsAStyleForProgressAndSystem() {
        for kind in [WidgetKind.progress, .system] {
            let instance = WidgetCatalog.make(kind, overrides: ["layout": .string(LiquidMotion.layout)])
            XCTAssertNotNil(instance)
            if let instance {
                XCTAssertEqual(WidgetCatalog.variantTitle(matching: instance.config, kind: kind), "液态", "\(kind)")
            }
        }
    }
}
