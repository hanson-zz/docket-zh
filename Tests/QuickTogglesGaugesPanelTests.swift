import XCTest

/// 快速开关面板（保持唤醒时长、卡片名字）和圆环仪表面板（警戒线、存储分段）的规则。
final class QuickTogglesGaugesPanelTests: XCTestCase {

    // MARK: 保持唤醒多久

    func testKeepAwakeDefaultsToAlwaysLikeBefore() {
        XCTAssertEqual(KeepAwakeTimer.minutes(WidgetConfig()), 0)
        XCTAssertEqual(KeepAwakeTimer.minutes(WidgetCatalog.make(.toggles)!.config), 0)
        XCTAssertEqual(KeepAwakeTimer.minutes(WidgetConfig([KeepAwakeTimer.key: .string("60")])), 60)
        XCTAssertEqual(KeepAwakeTimer.minutes(WidgetConfig([KeepAwakeTimer.key: .string("45")])), 0, "不认得的退回一直")
        XCTAssertEqual(KeepAwakeTimer.minutes(WidgetConfig([KeepAwakeTimer.key: .string("abc")])), 0)
        XCTAssertEqual(KeepAwakeTimer.choices, [30, 60, 120, 0])
    }

    func testKeepAwakeDeadlineAndRemainingText() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertNil(KeepAwakeTimer.deadline(minutes: 0, from: now))
        XCTAssertEqual(KeepAwakeTimer.deadline(minutes: 30, from: now), now.addingTimeInterval(1800))
        XCTAssertEqual(KeepAwakeTimer.remaining(until: nil, now: now), "一直开着")
        XCTAssertEqual(KeepAwakeTimer.remaining(until: now.addingTimeInterval(42 * 60 - 10), now: now), "剩 42 分")
        XCTAssertEqual(KeepAwakeTimer.remaining(until: now.addingTimeInterval(20), now: now), "剩 1 分", "不到一分钟算一分钟")
        XCTAssertEqual(KeepAwakeTimer.remaining(until: now.addingTimeInterval(-5), now: now), "剩 1 分")
        XCTAssertEqual(KeepAwakeTimer.remaining(until: now.addingTimeInterval(3600), now: now), "剩 1 小时")
        XCTAssertEqual(KeepAwakeTimer.remaining(until: now.addingTimeInterval(65 * 60), now: now), "剩 1 小时 5 分")
        XCTAssertEqual(KeepAwakeTimer.remaining(until: now.addingTimeInterval(105 * 60), now: now, minutesOnly: true), "剩 105 分")
        XCTAssertEqual(KeepAwakeTimer.title(30), "30 分钟")
        XCTAssertEqual(KeepAwakeTimer.title(0), "一直")
    }

    // MARK: 卡片名字

    func testShortNamesFitUnderTheButtons() {
        for toggle in QuickToggle.allCases {
            XCTAssertFalse(toggle.shortTitle.isEmpty, "\(toggle)")
            XCTAssertLessThanOrEqual(toggle.shortTitle.count, 4, "\(toggle) 的短名字放不进 46pt")
        }
        XCTAssertFalse(QuickToggle.showsNames(WidgetConfig()), "旧卡片照旧不显示名字")
        XCTAssertTrue(QuickToggle.showsNames(WidgetConfig([QuickToggle.showNamesKey: .bool(true)])))
        XCTAssertEqual(QuickToggle.length(count: 3), 128)
        XCTAssertEqual(QuickToggle.length(count: 3, names: true), 158)
        // 侧边扩展栏：28pt 圆钮之间隔 6pt，一列八个要 8×28+7×6=266pt，高度不能比这少。
        XCTAssertEqual(QuickToggle.columnLength(count: 8), 296)
        XCTAssertGreaterThanOrEqual(QuickToggle.columnLength(count: 8), 8 * 28 + 7 * 6)
        XCTAssertEqual(QuickToggle.columnLength(count: 3, names: true), 146)
        XCTAssertEqual(WidgetCatalog.verticalHeight(WidgetCatalog.make(.toggles)!),
                       QuickToggle.columnLength(count: QuickToggle.defaults.count))
        var named = WidgetCatalog.make(.toggles)!
        let plain = WidgetCatalog.naturalSize(named).width
        named.config.set(QuickToggle.showNamesKey, .bool(true))
        XCTAssertGreaterThan(WidgetCatalog.naturalSize(named).width, plain)
    }

    func testPanelTitlesFitThreeColumns() {
        for toggle in QuickToggle.allCases {
            XCTAssertLessThanOrEqual(toggle.panelTitle.count, 5, "\(toggle)")
            XCTAssertLessThanOrEqual(toggle.caption(on: true).count, 5, "\(toggle)")
            XCTAssertLessThanOrEqual(toggle.caption(on: false).count, 5, "\(toggle)")
        }
        XCTAssertEqual(QuickToggle.cleanScreen.panelTitle, "清洁")
        XCTAssertEqual(QuickToggle.emptyTrash.panelTitle, "清空废纸篓")
    }

    func testEveryButtonHasAPanelCaption() {
        for toggle in QuickToggle.allCases {
            XCTAssertFalse(toggle.caption(on: false).isEmpty, "\(toggle)")
        }
        XCTAssertEqual(QuickToggle.darkMode.caption(on: true), "开")
        XCTAssertEqual(QuickToggle.darkMode.caption(on: false), "关")
        XCTAssertEqual(QuickToggle.emptyTrash.caption(on: false), "会先确认")
    }

    // MARK: 圆环警戒线

    func testAlertDefaultsKeepTheOldBehaviour() {
        let config = WidgetConfig()
        XCTAssertEqual(GaugeAlert.value("storage", config), 10)
        XCTAssertEqual(GaugeAlert.value("battery", config), 10)
        XCTAssertEqual(GaugeAlert.value("cpu", config), 0)
        XCTAssertEqual(GaugeAlert.value("memory", config), 0)
        XCTAssertEqual(GaugeAlert.value("storage", WidgetConfig(["storageAlert": .string("7")])), 10, "不认得的退回默认")
        XCTAssertEqual(GaugeAlert.value("cpu", WidgetConfig(["cpuAlert": .string("90")])), 90)
        XCTAssertEqual(GaugeAlert.keys, ["storageAlert", "batteryAlert", "cpuAlert", "memoryAlert"])
        let made = WidgetCatalog.make(.gauges)!.config
        for ring in GaugeReading.allRings {
            XCTAssertEqual(GaugeAlert.value(ring, made), GaugeAlert.defaultValue(ring))
        }
    }

    func testCrossingTheLine() {
        // 存储：已用 92%，剩 8%，线是剩 10%。
        XCTAssertTrue(GaugeAlert.isOver("storage", fraction: 0.92, line: 10))
        XCTAssertFalse(GaugeAlert.isOver("storage", fraction: 0.85, line: 10))
        XCTAssertFalse(GaugeAlert.isOver("storage", fraction: 0.99, line: 0), "0 是不变红")
        XCTAssertTrue(GaugeAlert.isOver("battery", fraction: 0.10, line: 10))
        XCTAssertFalse(GaugeAlert.isOver("battery", fraction: 0.05, line: 10, charging: true), "充电时不变红")
        XCTAssertTrue(GaugeAlert.isOver("cpu", fraction: 0.95, line: 90))
        XCTAssertFalse(GaugeAlert.isOver("memory", fraction: 0.89, line: 90))
        XCTAssertFalse(GaugeAlert.isOver("cpu", fraction: 1.0, line: 0))
    }

    func testSteppingStopsAtTheEnds() {
        XCTAssertEqual(GaugeAlert.stepped("storage", from: 10, by: 1), 15)
        XCTAssertEqual(GaugeAlert.stepped("storage", from: 10, by: -1), 5)
        XCTAssertEqual(GaugeAlert.stepped("storage", from: 0, by: -1), 0)
        XCTAssertEqual(GaugeAlert.stepped("cpu", from: 95, by: 1), 95)
        XCTAssertEqual(GaugeAlert.stepped("cpu", from: 0, by: 1), 50)
        XCTAssertEqual(GaugeAlert.short("storage", 10), "剩 10%")
        XCTAssertEqual(GaugeAlert.short("cpu", 0), "不变红")
        XCTAssertEqual(GaugeAlert.caption("battery", 20), "用电池时低于 20% 变红")
        for ring in GaugeReading.allRings {
            XCTAssertEqual(GaugeAlert.choices(ring).first, 0, "\(ring) 第一档是不变红")
            XCTAssertTrue(GaugeAlert.choices(ring).contains(GaugeAlert.defaultValue(ring)))
        }
    }

    func testAlertOptionsOnlyListRingsOnTheCard() {
        let config = WidgetConfig(["rings": .list([.string("cpu"), .string("storage")])])
        XCTAssertTrue(WidgetCatalog.applies("cpuAlert", to: config, kind: .gauges))
        XCTAssertTrue(WidgetCatalog.applies("storageAlert", to: config, kind: .gauges))
        XCTAssertFalse(WidgetCatalog.applies("batteryAlert", to: config, kind: .gauges))
        XCTAssertFalse(WidgetCatalog.applies("memoryAlert", to: config, kind: .gauges))
        XCTAssertTrue(WidgetCatalog.applies("rings", to: config, kind: .gauges))
    }

    // MARK: 存储分段

    func testStorageBreakdownPutsTheRestInOther() {
        let parts = StorageBreakdown(apps: 180, downloads: 100, trash: 20).parts(used: 400, total: 1000)
        XCTAssertEqual(parts.map(\.name), ["应用", "下载", "废纸篓", "其他"])
        XCTAssertEqual(parts.map(\.bytes), [180, 100, 20, 100])
        XCTAssertEqual(parts[0].fraction, 0.18, accuracy: 1e-9)
    }

    func testUnknownPartsAreSkippedAndOtherNeverGoesNegative() {
        let parts = StorageBreakdown(apps: 500, downloads: nil, trash: 0).parts(used: 300, total: 1000)
        XCTAssertEqual(parts.map(\.name), ["应用"], "下载读不到、废纸篓是空的都不画，量出来的比已用还多时没有其他")
        XCTAssertTrue(StorageBreakdown().parts(used: 300, total: 0).isEmpty)
        XCTAssertEqual(StorageBreakdown().parts(used: 300, total: 1000).map(\.name), ["其他"])
    }
}
