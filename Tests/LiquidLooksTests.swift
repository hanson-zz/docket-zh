import XCTest

/// 喝水、Codex 用量、小熊猫的竹篮的液态外观：默认不变、水位、满水盖过上沿，
/// 以及喝水卡片的渴成骷髅。
final class LiquidLooksTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }()

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: hour, minute: minute))!
    }

    // MARK: 外观选择

    func testLooksDefaultToWhatTheyWere() {
        XCTAssertEqual(LiquidLooks.codexLook(WidgetConfig()), .ring)
        XCTAssertEqual(LiquidLooks.basketLook(WidgetConfig()), .leaf)
        XCTAssertFalse(LiquidLooks.waterIsLiquid(WidgetConfig()))
        XCTAssertEqual(LiquidLooks.codexLook(WidgetConfig(["look": .string("liquid")])), .liquid)
        XCTAssertEqual(LiquidLooks.basketLook(WidgetConfig(["look": .string("liquid")])), .liquid)
        XCTAssertEqual(LiquidLooks.codexLook(WidgetConfig(["look": .string("x")])), .ring)
        XCTAssertTrue(LiquidLooks.waterIsLiquid(WidgetConfig(["layout": .string("liquid")])))
    }

    func testCatalogDefaultsKeepOldLooks() {
        XCTAssertEqual(LiquidLooks.codexLook(WidgetCatalog.make(.aiUsage)!.config), .ring)
        XCTAssertEqual(LiquidLooks.basketLook(WidgetCatalog.make(.perfectDay)!.config), .leaf)
        let water = WidgetCatalog.make(.water)!
        XCTAssertFalse(LiquidLooks.waterIsLiquid(water.config))
        let liquid = WidgetCatalog.make(.water, overrides: ["layout": .string(LiquidMotion.layout)])!
        XCTAssertEqual(WidgetCatalog.variantTitle(matching: liquid.config, kind: .water), "液态")
        XCTAssertEqual(WidgetCatalog.naturalSize(liquid).width, 184)
        XCTAssertFalse(WidgetCatalog.applies(WaterParched.key, to: liquid.config, kind: .water))
        XCTAssertTrue(WidgetCatalog.applies(WaterParched.key, to: water.config, kind: .water))
    }

    // MARK: 水位

    func testWaterLevelStopsAtFull() {
        XCTAssertEqual(LiquidLooks.waterLevel(total: 0, goal: 2000), 0)
        XCTAssertEqual(LiquidLooks.waterLevel(total: 1000, goal: 2000), 0.5, accuracy: 1e-9)
        XCTAssertEqual(LiquidLooks.waterLevel(total: 3000, goal: 2000), 1)
        XCTAssertEqual(LiquidLooks.waterLevel(total: 500, goal: 0), 0)
    }

    func testCodexCupFollowsWhatTheRingShowed() {
        XCTAssertEqual(LiquidLooks.codexLevel(usedFraction: 0.3, showsRemaining: false), 0.3, accuracy: 1e-9)
        XCTAssertEqual(LiquidLooks.codexLevel(usedFraction: 0.3, showsRemaining: true), 0.7, accuracy: 1e-9)
        XCTAssertEqual(LiquidLooks.codexLevel(usedFraction: 1.4, showsRemaining: true), 0)
    }

    func testBasketAveragesOnlyTheItemsTakingPart() {
        let items = [
            PerfectDayProgress(item: .water, mark: .missed, fraction: 0.5, detail: ""),
            PerfectDayProgress(item: .habit, mark: .met, fraction: 1, detail: ""),
            PerfectDayProgress(item: .focus, mark: .off, fraction: 0, detail: ""),
        ]
        XCTAssertEqual(LiquidLooks.basketLevel(items), 0.75, accuracy: 1e-9)
        XCTAssertEqual(LiquidLooks.basketLevel([]), 0)
        XCTAssertEqual(LiquidLooks.basketLevel([items[2]]), 0)
    }

    /// 之前修过的满水顶部黑边：没满最高 94%，满了略高过上沿。
    func testFullCardCoversTheTopEdge() {
        XCTAssertEqual(LiquidLooks.cardFill(0), 0)
        XCTAssertEqual(LiquidLooks.cardFill(0.5), 0.47, accuracy: 1e-9)
        XCTAssertLessThan(LiquidLooks.cardFill(0.999), 1)
        XCTAssertGreaterThan(LiquidLooks.cardFill(1), 1)
        XCTAssertGreaterThan(LiquidLooks.cardFill(2), 1)
    }

    // MARK: 渴成骷髅

    private let window = WaterReminder(every: 60, start: 9 * 60, end: 21 * 60)

    func testParchedAfterFiveDryHours() {
        // 9:00 开始，一口没喝：13:59 还不是，14:00 渴成骷髅。
        XCTAssertFalse(WaterParched.isParched(now: at(13, 59), lastDrink: nil, total: 0, goal: 2000,
                                              window: window, calendar: calendar))
        XCTAssertTrue(WaterParched.isParched(now: at(14), lastDrink: nil, total: 0, goal: 2000,
                                             window: window, calendar: calendar))
        // 10:30 喝过一杯，从那时算起。
        XCTAssertFalse(WaterParched.isParched(now: at(15), lastDrink: at(10, 30), total: 600, goal: 2000,
                                              window: window, calendar: calendar))
        XCTAssertTrue(WaterParched.isParched(now: at(15, 30), lastDrink: at(10, 30), total: 600, goal: 2000,
                                             window: window, calendar: calendar))
        // 昨晚喝的不算，从时段开始算。
        let lastNight = calendar.date(byAdding: .hour, value: -12, to: at(9))!
        XCTAssertTrue(WaterParched.isParched(now: at(14), lastDrink: lastNight, total: 0, goal: 2000,
                                             window: window, calendar: calendar))
    }

    func testParchedWhenTheDayIsLateAndProgressLow() {
        // 9:00 到 21:00，过了 60% 是 16:12；刚喝过一小杯也算渴。
        XCTAssertFalse(WaterParched.isParched(now: at(16), lastDrink: at(15, 50), total: 300, goal: 2000,
                                              window: window, calendar: calendar))
        XCTAssertTrue(WaterParched.isParched(now: at(16, 30), lastDrink: at(16, 20), total: 300, goal: 2000,
                                             window: window, calendar: calendar))
        XCTAssertFalse(WaterParched.isParched(now: at(16, 30), lastDrink: at(16, 20), total: 600, goal: 2000,
                                              window: window, calendar: calendar))
    }

    func testNeverParchedWhenMetOrOutsideTheHours() {
        XCTAssertFalse(WaterParched.isParched(now: at(18), lastDrink: at(9), total: 2000, goal: 2000,
                                              window: window, calendar: calendar))
        XCTAssertFalse(WaterParched.isParched(now: at(22), lastDrink: nil, total: 0, goal: 2000,
                                              window: window, calendar: calendar), "时段外在睡觉")
        XCTAssertFalse(WaterParched.isParched(now: at(18), lastDrink: nil, total: 0, goal: 0,
                                              window: window, calendar: calendar))
    }

    func testParchedSwitchAndPictures() {
        var config = WidgetConfig(["start": .string("09:00"), "end": .string("21:00")])
        XCTAssertTrue(config.bool(WaterParched.key, default: true), "默认开")
        config.set(WaterParched.key, .bool(false))
        XCTAssertFalse(WaterParched.isParched(config, now: at(20), calendar: calendar))
        XCTAssertEqual(WidgetCatalog.make(.water)?.config.bool(WaterParched.key), true)
        XCTAssertEqual(WaterParched.imageName(.redPanda), "WaterPanda-skeleton")
        XCTAssertEqual(WaterParched.imageName(.shiba), "pet-shiba-skeleton")
    }
}
