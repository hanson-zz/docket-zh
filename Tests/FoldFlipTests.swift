import XCTest

/// 折叠翻页的拆格、倒计时外观，以及超过目标时的第二圈。
final class FoldFlipTests: XCTestCase {

    func testDigitsFlipAndSeparatorsDoNot() {
        let cells = FoldFlip.cells("1:05:09")
        XCTAssertEqual(cells.map(\.text), ["1", ":", "0", "5", ":", "0", "9"])
        XCTAssertEqual(cells.map(\.flips), [true, false, true, true, false, true, true])
    }

    func testSlotsCountFromTheRight() {
        XCTAssertEqual(FoldFlip.slot(3, count: 4), 0)
        XCTAssertEqual(FoldFlip.slot(0, count: 4), 3)
        // 10:00 走到 9:59：秒的个位在两边都是 0 号。
        XCTAssertEqual(FoldFlip.slot(4, count: 5), FoldFlip.slot(3, count: 4))
    }

    func testCountdownLookDefaultsToPlainDigits() {
        XCTAssertEqual(FoldFlip.countdownLook(WidgetConfig()), .plain)
        XCTAssertEqual(FoldFlip.countdownLook(WidgetConfig(["look": .string("fold")])), .fold)
        XCTAssertEqual(FoldFlip.countdownLook(WidgetConfig(["look": .string("spiral")])), .plain)
    }

    func testTheCatalogOffersTheFoldingClockAndCountdownLook() {
        // 折叠翻页并进了“翻页”的“翻法：折叠”，旧的 fold 值仍画成折叠翻页、仍免费。
        let clock = WidgetCatalog.entry(.clock)!
        XCTAssertFalse(clock.variants.contains { $0.overrides["layout"] == .string(FoldFlip.clockLayout) })
        XCTAssertEqual(ClockStyles.resolve(WidgetConfig(["layout": .string(FoldFlip.clockLayout)])).face, .foldFlip)
        XCTAssertEqual(ClockStyles.resolve(WidgetConfig(["layout": .string("flip"),
                                                         ClockStyles.Key.flip: .string("fold")])).face, .foldFlip)
        XCTAssertFalse(WidgetCatalog.isSupporterOnly(["layout": .string(FoldFlip.clockLayout)]))
        XCTAssertFalse(WidgetCatalog.isSupporterOnly([ClockStyles.Key.flip: .string("fold")]))
        let countdown = WidgetCatalog.entry(.countdown)!
        XCTAssertEqual(countdown.defaults[FoldFlip.countdownLookKey], .string(FoldFlip.CountdownLook.plain.rawValue))
    }

    // MARK: Rings that lap

    func testUnderTheGoalIsOneLap() {
        XCTAssertEqual(RingLap.progress(total: 500, goal: 2000), 0.25)
        let split = RingLap.split(0.25)
        XCTAssertEqual(split.first, 0.25)
        XCTAssertEqual(split.second, 0)
        XCTAssertFalse(RingLap.isLapping(1))
    }

    func testPastTheGoalStartsASecondLap() {
        XCTAssertEqual(RingLap.progress(total: 2600, goal: 2000), 1.3, accuracy: 1e-9)
        let split = RingLap.split(1.3)
        XCTAssertEqual(split.first, 1)
        XCTAssertEqual(split.second, 0.3, accuracy: 1e-9)
        XCTAssertTrue(RingLap.isLapping(1.3))
    }

    func testTheSecondLapStopsWhenFull() {
        XCTAssertEqual(RingLap.progress(total: 9000, goal: 2000), RingLap.maxLaps)
        let split = RingLap.split(7)
        XCTAssertEqual(split.first, 1)
        XCTAssertEqual(split.second, 1)
    }

    func testNothingStrangeGoesIn() {
        XCTAssertEqual(RingLap.progress(total: 100, goal: 0), 0)
        XCTAssertEqual(RingLap.progress(total: -5, goal: 2000), 0)
        XCTAssertEqual(RingLap.split(.nan).first, 0)
        XCTAssertEqual(RingLap.split(-1).second, 0)
    }
}
