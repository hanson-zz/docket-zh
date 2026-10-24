import XCTest

/// 电池格沙漏样式面板：什么时候用、品牌沙色、今天的沙柱和小结、健康小格。
final class BatteryHourglassPanelTests: XCTestCase {
    private let dayStart = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ hours: Double) -> Date { dayStart.addingTimeInterval(hours * 3600) }

    private func sample(_ hours: Double, _ percent: Int, charging: Bool = false) -> BatteryHistory.Sample {
        BatteryHistory.Sample(date: at(hours), percent: percent, charging: charging)
    }

    // MARK: 什么时候用

    func testGaugeWithHourglassLookUsesHourglassPanel() {
        XCTAssertTrue(BatteryHourglass.panelHeader(layout: "gauge", look: BatteryLook.classic.rawValue, unlocked: true))
        XCTAssertTrue(BatteryHourglass.panelHeader(layout: "gauge", look: BatteryLook.liquid.rawValue, unlocked: true))
        XCTAssertTrue(BatteryHourglass.panelHeader(layout: ProFeatures.batteryGaugeLayout, look: "", unlocked: true))
    }

    func testOtherLayoutsKeepTheirPanel() {
        for layout in ["status", "icon", ""] {
            XCTAssertFalse(BatteryHourglass.panelHeader(layout: layout, look: BatteryLook.liquid.rawValue,
                                                        unlocked: true), layout)
        }
    }

    func testGaugeWithOwnArtKeepsItsPanel() {
        for look in [BatteryLook.pixel, .particles, .panda] {
            XCTAssertFalse(BatteryHourglass.panelHeader(layout: "gauge", look: look.rawValue, unlocked: true))
        }
    }

    func testLockedGaugeKeepsOldPanel() {
        XCTAssertFalse(BatteryHourglass.panelHeader(layout: "gauge", look: BatteryLook.classic.rawValue, unlocked: false))
    }

    func testHeroKeepsLiquidBallFootprint() {
        XCTAssertEqual(BatteryHourglassPanel.heroHeight, 104)
        XCTAssertEqual(BatteryHourglassPanel.heroWidth, 79)
    }

    // MARK: 颜色

    func testSandIsWarmAndReadableOnLightGlass() {
        let dark = BatteryHourglassPanel.sand(dark: true)
        XCTAssertEqual(dark, BatteryHourglassPanel.sandDark)
        XCTAssertGreaterThan(dark.red, dark.blue)
        let light = BatteryHourglassPanel.sand(dark: false)
        let code = ColorCode(red: light.red, green: light.green, blue: light.blue)
        XCTAssertGreaterThanOrEqual(WidgetTint.contrastRatio(code, PanelContrast.lightGlass), 3)
        XCTAssertGreaterThan(light.red, light.blue, "压暗后还是暖色")
    }

    func testHeroSandFollowsCardRules() {
        let normal = BatteryHourglassPanel.heroSand(level: 0.7, charging: false, lowPower: false, present: true,
                                                    theme: nil, dark: true)
        XCTAssertEqual(normal, BatteryLiquidFX.green)
        let low = BatteryHourglassPanel.heroSand(level: 0.15, charging: false, lowPower: false, present: true,
                                                 theme: nil, dark: true)
        XCTAssertEqual(low, BatteryTheme.warningRed)
        let charging = BatteryHourglassPanel.heroSand(level: 0.15, charging: true, lowPower: false, present: true,
                                                      theme: nil, dark: true)
        XCTAssertEqual(charging, BatteryLiquidFX.green)
    }

    func testHeroSandDeepensOnLightGlass() {
        let light = BatteryHourglassPanel.heroSand(level: 0.7, charging: false, lowPower: true, present: true,
                                                   theme: nil, dark: false)
        let code = ColorCode(red: light.red, green: light.green, blue: light.blue)
        XCTAssertGreaterThanOrEqual(WidgetTint.contrastRatio(code, PanelContrast.lightGlass), 3)
    }

    func testProBadgeInkContrast() {
        XCTAssertGreaterThanOrEqual(WidgetTint.contrastRatio(BatteryHourglassPanel.proInk,
                                                             BatteryHourglassPanel.proFillBottom), 4.5)
        XCTAssertGreaterThanOrEqual(WidgetTint.contrastRatio(BatteryHourglassPanel.proInk,
                                                             BatteryHourglassPanel.proFillTop), 4.5)
    }

    // MARK: 沙柱

    func testTwentyFourColumnsWithLastReadingPerHour() {
        let samples = [sample(0.1, 92), sample(0.9, 90), sample(3.5, 70), sample(3.2, 72)]
        let columns = BatteryHourglassPanel.hourColumns(samples: samples, dayStart: dayStart, now: at(5.5))
        XCTAssertEqual(columns.count, 24)
        XCTAssertEqual(columns.map(\.hour), Array(0..<24))
        XCTAssertEqual(columns[0].percent, 90)
        XCTAssertEqual(columns[3].percent, 70, "同一小时取最晚那次，和样本顺序无关")
        XCTAssertNil(columns[1].percent)
    }

    func testCurrentAndFutureHours() {
        let columns = BatteryHourglassPanel.hourColumns(samples: [], dayStart: dayStart, now: at(14.2))
        XCTAssertTrue(columns[14].isCurrent)
        XCTAssertFalse(columns[13].isFuture)
        XCTAssertFalse(columns[14].isFuture)
        XCTAssertTrue(columns[15].isFuture)
        XCTAssertEqual(columns.filter(\.isCurrent).count, 1)
    }

    func testOtherDayHasNoNow() {
        let columns = BatteryHourglassPanel.hourColumns(samples: [], dayStart: dayStart, now: at(30))
        XCTAssertFalse(columns.contains { $0.isCurrent || $0.isFuture })
    }

    func testChargingAndWarning() {
        let samples = [sample(10.1, 40, charging: true), sample(10.6, 45), sample(15.4, 18), sample(16.2, 15, charging: true)]
        let columns = BatteryHourglassPanel.hourColumns(samples: samples, dayStart: dayStart, now: at(17))
        XCTAssertTrue(columns[10].charging, "这个小时里充过电就算")
        XCTAssertFalse(columns[10].warns)
        XCTAssertTrue(columns[15].warns, "20% 及以下没在充电变红，和卡片一致")
        XCTAssertFalse(columns[16].warns, "充着电不报警")
    }

    func testSamplesOutsideDayAreIgnored() {
        let samples = [sample(-0.5, 50), sample(24.5, 60), sample(26, 70)]
        let columns = BatteryHourglassPanel.hourColumns(samples: samples, dayStart: dayStart, now: at(12))
        XCTAssertEqual(columns[23].percent, 60, "夏令时多出的一小时并进最后一根")
        XCTAssertNil(columns[0].percent)
        XCTAssertEqual(columns.compactMap(\.percent).count, 1)
    }

    func testColumnHeightAndEmpty() {
        let columns = BatteryHourglassPanel.hourColumns(samples: [], dayStart: dayStart, now: at(9))
        XCTAssertTrue(BatteryHourglassPanel.isEmpty(columns))
        XCTAssertEqual(BatteryHourglassPanel.columnHeight(columns[0]), 0)
        let filled = BatteryHourglassPanel.hourColumns(samples: [sample(8.5, 1)], dayStart: dayStart, now: at(9))
        XCTAssertFalse(BatteryHourglassPanel.isEmpty(filled))
        XCTAssertEqual(BatteryHourglassPanel.columnHeight(filled[8]), 0.04, accuracy: 1e-9)
        let full = BatteryHourglassPanel.hourColumns(samples: [sample(8.5, 100)], dayStart: dayStart, now: at(9))
        XCTAssertEqual(BatteryHourglassPanel.columnHeight(full[8]), 1, accuracy: 1e-9)
    }

    // MARK: 小结

    func testSummaryLowestAndChargingTime() {
        let samples = [sample(1, 80), sample(2, 38, charging: true), sample(2.1, 40, charging: true), sample(3, 60)]
        let summary = BatteryHourglassPanel.daySummary(samples: samples)
        XCTAssertEqual(summary.lowest, 38)
        XCTAssertEqual(summary.chargingMinutes, 10)
        XCTAssertEqual(BatteryHourglassPanel.summaryText(summary), "最低 38% · 充电 10 分钟")
    }

    func testSummaryWithoutChargingOrSamples() {
        let summary = BatteryHourglassPanel.daySummary(samples: [sample(1, 55)])
        XCTAssertEqual(BatteryHourglassPanel.summaryText(summary), "最低 55%")
        let empty = BatteryHourglassPanel.daySummary(samples: [])
        XCTAssertNil(empty.lowest)
        XCTAssertNil(BatteryHourglassPanel.summaryText(empty))
    }

    // MARK: 健康小格

    func testCapacityRing() {
        XCTAssertFalse(BatteryHourglassPanel.capacityWarns(80))
        XCTAssertTrue(BatteryHourglassPanel.capacityWarns(79))
        XCTAssertEqual(BatteryHourglassPanel.capacityFraction(92), 0.92, accuracy: 1e-9)
        XCTAssertEqual(BatteryHourglassPanel.capacityFraction(130), 1)
    }
}
