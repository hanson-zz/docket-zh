import XCTest

/// 设置页「可拖动勾选列表」的规则（`OrderedChecklist`）。
final class OrderedChecklistTests: XCTestCase {
    private let all = ["cpu", "memory", "network", "disk", "battery"]

    func testRowsPutCheckedFirstInSavedOrderThenTheRestInCatalogOrder() {
        let rows = OrderedChecklist.rows(saved: ["disk", "cpu", "bogus", "disk"], all: all)
        XCTAssertEqual(rows.map(\.value), ["disk", "cpu", "memory", "network", "battery"])
        XCTAssertEqual(rows.map(\.on), [true, true, false, false, false])
    }

    func testEmptySavedListShowsEverythingUnchecked() {
        let rows = OrderedChecklist.rows(saved: [], all: all)
        XCTAssertEqual(rows.map(\.value), all)
        XCTAssertTrue(rows.allSatisfy { !$0.on })
    }

    func testMovingOntoAnotherCheckedRowTakesItsPlace() {
        let saved = ["cpu", "memory", "disk"]
        XCTAssertEqual(OrderedChecklist.move(saved: saved, all: all, value: "disk", onto: "cpu"), ["disk", "cpu", "memory"])
        XCTAssertEqual(OrderedChecklist.move(saved: saved, all: all, value: "cpu", onto: "disk"), ["memory", "disk", "cpu"])
        XCTAssertEqual(OrderedChecklist.move(saved: saved, all: all, value: "cpu", onto: "memory"), ["memory", "cpu", "disk"])
    }

    func testMovingOntoAnUncheckedRowGoesToTheEndOfTheCheckedOnes() {
        XCTAssertEqual(OrderedChecklist.move(saved: ["cpu", "memory"], all: all, value: "cpu", onto: "battery"),
                       ["memory", "cpu"])
    }

    func testUncheckedRowsAndNoOpMovesWriteNothing() {
        XCTAssertNil(OrderedChecklist.move(saved: ["cpu"], all: all, value: "disk", onto: "cpu"), "没勾的不能拖")
        XCTAssertNil(OrderedChecklist.move(saved: ["cpu", "disk"], all: all, value: "cpu", onto: "cpu"))
        XCTAssertNil(OrderedChecklist.move(saved: ["cpu", "disk"], all: all, value: "disk", onto: "battery"), "已经在最后")
        XCTAssertNil(OrderedChecklist.move(saved: ["cpu", "disk"], all: all, value: "cpu", onto: "bogus"))
    }

    func testStepMovesOneAndStopsAtTheEnds() {
        XCTAssertEqual(OrderedChecklist.step(saved: ["cpu", "memory", "disk"], all: all, value: "disk", by: -1),
                       ["cpu", "disk", "memory"])
        XCTAssertNil(OrderedChecklist.step(saved: ["cpu", "memory"], all: all, value: "cpu", by: -1))
        XCTAssertNil(OrderedChecklist.step(saved: ["cpu", "memory"], all: all, value: "memory", by: 1))
        XCTAssertNil(OrderedChecklist.step(saved: ["cpu"], all: all, value: "disk", by: 1))
    }

    func testCheckingAppendsAndUncheckingRemoves() {
        XCTAssertEqual(OrderedChecklist.toggle(saved: ["disk", "cpu"], all: all, value: "memory", on: true),
                       ["disk", "cpu", "memory"])
        XCTAssertEqual(OrderedChecklist.toggle(saved: ["disk", "cpu"], all: all, value: "disk", on: false), ["cpu"])
    }

    func testTheLastOneCannotBeUncheckedAndTheLimitHolds() {
        XCTAssertNil(OrderedChecklist.toggle(saved: ["cpu"], all: all, value: "cpu", on: false))
        XCTAssertFalse(OrderedChecklist.canUncheck(saved: ["cpu", "bogus"], all: all))
        XCTAssertTrue(OrderedChecklist.canUncheck(saved: ["cpu", "disk"], all: all))
        XCTAssertNil(OrderedChecklist.toggle(saved: ["cpu", "disk"], all: all, value: "memory", on: true, limit: 2))
        XCTAssertNil(OrderedChecklist.toggle(saved: ["cpu"], all: all, value: "cpu", on: true), "已经勾上")
        XCTAssertNil(OrderedChecklist.toggle(saved: ["cpu"], all: all, value: "bogus", on: true))
    }

    func testEveryReorderableKeyHasAFixedChoiceSetInTheCatalog() {
        // 这几个键在卡片上都按存的先后画。
        XCTAssertEqual(GaugeReading.rings(WidgetConfig(["rings": .list([.string("cpu"), .string("storage")])])),
                       ["cpu", "storage"])
        XCTAssertEqual(AmbientSound.parse(["fire", "rain"]), [.fire, .rain])
        XCTAssertEqual(SlackerClock.items(["friday", "payday"]), [.friday, .payday])
        XCTAssertEqual(QuickToggle.chosen(WidgetConfig([QuickToggle.key: .list([.string("lock"), .string("darkMode")])])),
                       [.lock, .darkMode])
        XCTAssertEqual(SystemCardMetrics.shown(WidgetConfig(["metrics": .list([.string("disk"), .string("cpu")])])),
                       ["disk", "cpu"])
        XCTAssertEqual(OrderedChecklist.keys, ["metrics", "rings", "actions", "sounds", "more", "buttons"])
    }
}
