import Foundation
import XCTest

/// 点弹出卡片主体时面板挂在哪里，以及喝水提醒交给后台计时器以后每秒交来的时间怎么处理。
final class WidgetPanelRouteTests: XCTestCase {
    private let water = WidgetInstance(kind: .water, config: WidgetConfig())
    private let stock = WidgetInstance(kind: .stock, config: WidgetConfig())

    private func route(_ id: UUID, _ items: [DockItem], anywhere: Bool = true, shelf: Bool = true,
                       detail: Bool = true) -> WidgetPanelRoute {
        WidgetPanelRoute.decide(widget: id, current: items, existsAnywhere: anywhere, shelfShown: shelf,
                                hasDetail: detail)
    }

    // MARK: 面板挂在哪里

    func testTopLevelWidgetOpensFromItsTile() {
        XCTAssertEqual(route(water.id, [.spacer(id: UUID(), size: .small), .widget(water)]), .tile)
    }

    func testWidgetInFolderOpensFromTheFolder() {
        let group = DockGroup(name: "日常", items: [.widget(stock), .widget(water)])
        XCTAssertEqual(route(water.id, [.group(group)]), .folder(group.id))
    }

    func testWidgetInNestedFolderOpensFromTheTopLevelFolder() {
        let inner = DockGroup(name: "里", items: [.widget(water)])
        let outer = DockGroup(name: "外", items: [.group(inner)])
        XCTAssertEqual(route(water.id, [.group(outer)]), .folder(outer.id))
    }

    func testWidgetOnAnotherLayoutFloats() {
        XCTAssertEqual(route(water.id, [.widget(stock)]), .floating)
    }

    func testNoShelfFloatsEvenWhenOnTheCurrentLayout() {
        XCTAssertEqual(route(water.id, [.widget(water)], shelf: false), .floating)
        let group = DockGroup(name: "日常", items: [.widget(water)])
        XCTAssertEqual(route(water.id, [.group(group)], shelf: false), .floating)
    }

    func testMissingWidgetOrNoPanelDoesNothing() {
        XCTAssertEqual(route(water.id, [.widget(stock)], anywhere: false), .none)
        XCTAssertEqual(route(water.id, [.widget(water)], detail: false), .none)
    }

    func testCurrentLayoutCountsEvenIfLookupMissedIt() {
        XCTAssertEqual(route(water.id, [.widget(water)], anywhere: false), .tile)
    }

    // MARK: 喝水的后台调度

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testSameTimeKeepsTheTimer() {
        XCTAssertEqual(WaterAlertPlan.step(pending: now.addingTimeInterval(600),
                                           next: now.addingTimeInterval(600.4), now: now), .keep)
        XCTAssertEqual(WaterAlertPlan.step(pending: nil, next: nil, now: now), .keep)
    }

    func testFirstTimeArms() {
        let next = now.addingTimeInterval(900)
        XCTAssertEqual(WaterAlertPlan.step(pending: nil, next: next, now: now), .rearm(next))
    }

    func testSnoozeMovesAFutureReminder() {
        // 「稍后 15 分钟」写下的时间取代还没到的那一次。
        let snoozed = now.addingTimeInterval(900)
        XCTAssertEqual(WaterAlertPlan.step(pending: now.addingTimeInterval(300), next: snoozed, now: now),
                       .rearm(snoozed))
    }

    func testTurningOffDisarms() {
        XCTAssertEqual(WaterAlertPlan.step(pending: now.addingTimeInterval(300), next: nil, now: now), .rearm(nil))
    }

    func testDueReminderFiresBeforeTheNextReplacesIt() {
        // 到点那一秒下一次已经往后挪了一个间隔：先弹出到点的那一次。
        let due = now
        let next = now.addingTimeInterval(3600)
        XCTAssertEqual(WaterAlertPlan.step(pending: due, next: next, now: now),
                       .fireThenRearm(due: due, next: next))
        XCTAssertEqual(WaterAlertPlan.step(pending: due.addingTimeInterval(0.3), next: next, now: now),
                       .fireThenRearm(due: due.addingTimeInterval(0.3), next: next))
    }

    func testDueReminderFiresEvenWhenRemindersTurnOff() {
        XCTAssertEqual(WaterAlertPlan.step(pending: now.addingTimeInterval(-1), next: nil, now: now),
                       .fireThenRearm(due: now.addingTimeInterval(-1), next: nil))
    }

    func testRemovedWidgetsAreWithdrawn() {
        let a = UUID(), b = UUID(), c = UUID()
        XCTAssertEqual(WaterAlertPlan.removed(known: [a, b], present: [b, c]), [a])
        XCTAssertEqual(WaterAlertPlan.removed(known: [], present: [a]), [])
    }
}
