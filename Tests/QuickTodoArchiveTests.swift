import XCTest

/// 快速待办“已收起”：昨天做完的收起而不是删掉，7 天后清；快捷键小框找分组里的。
final class QuickTodoArchiveTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    func testRolloverMovesYesterdaysFinishedIntoArchive() {
        var config = WidgetConfig()
        QuickTodo.store([TodoItem(id: "a", text: "昨天做完", done: true, today: true, addedDay: "2026-10-17",
                                  doneDay: "2026-10-17", remindAt: Date(timeIntervalSince1970: 1_792_000_000)),
                         TodoItem(id: "b", text: "今天做完", done: true, doneDay: "2026-10-18"),
                         TodoItem(id: "c", text: "没做完", addedDay: "2026-10-17")], in: &config)
        QuickTodo.applyRollover(in: &config, today: "2026-10-18", calendar: calendar)
        XCTAssertEqual(QuickTodo.items(config).map(\.id), ["c", "b"])
        let shelved = QuickTodo.archive(config)
        XCTAssertEqual(shelved.map(\.id), ["a"])
        XCTAssertEqual(shelved.first?.today, false, "收起的不再是今天三件事")
        XCTAssertNil(shelved.first?.remindAt, "收起的不带提醒时间")
        XCTAssertEqual(shelved.first?.doneDay, "2026-10-17")
        // 同一天再收拾一次什么也不改。
        let before = config
        QuickTodo.applyRollover(in: &config, today: "2026-10-18", calendar: calendar)
        XCTAssertEqual(config, before)
    }

    func testArchiveKeepsSevenDays() {
        XCTAssertEqual(QuickTodo.archiveCutoff(today: "2026-10-18", calendar: calendar), "2026-10-11")
        let archive = [TodoItem(id: "old", text: "八天前", done: true, doneDay: "2026-10-10"),
                       TodoItem(id: "edge", text: "七天前", done: true, doneDay: "2026-10-11"),
                       TodoItem(id: "new", text: "昨天", done: true, doneDay: "2026-10-17")]
        let kept = QuickTodo.prunedArchive(archive, today: "2026-10-18", calendar: calendar)
        XCTAssertEqual(kept.map(\.id), ["new", "edge"], "最近做完的在前，满 7 天的清掉")
    }

    func testRolloverPrunesOldArchiveEvenWithNothingNew() {
        var config = WidgetConfig()
        QuickTodo.storeArchive([TodoItem(id: "old", text: "很早", done: true, doneDay: "2026-10-01")], in: &config)
        QuickTodo.applyRollover(in: &config, today: "2026-10-18", calendar: calendar)
        XCTAssertTrue(QuickTodo.archive(config).isEmpty)
        XCTAssertNil(config[QuickTodo.archiveKey])
    }

    func testRestorePutsItBackAsTodaysOpenItem() {
        let items = [TodoItem(id: "x", text: "开着"), TodoItem(id: "y", text: "做完", done: true, doneDay: "2026-10-18")]
        let archive = [TodoItem(id: "a", text: "恢复我", done: true, doneDay: "2026-10-16")]
        let result = QuickTodo.restoring("a", items: items, archive: archive, today: "2026-10-18")
        XCTAssertEqual(result.items.map(\.id), ["x", "a", "y"])
        let back = result.items[1]
        XCTAssertFalse(back.done)
        XCTAssertNil(back.doneDay)
        XCTAssertEqual(back.addedDay, "2026-10-18")
        XCTAssertTrue(result.archive.isEmpty)
        // 恢复的不算“昨天没做完的”，不会再问顺延。
        XCTAssertTrue(QuickTodo.leftover(result.items, today: "2026-10-18").isEmpty)
    }

    func testRestoreAvoidsIDClash() {
        let items = [TodoItem(id: "a", text: "新记的")]
        let archive = [TodoItem(id: "a", text: "旧的", done: true, doneDay: "2026-10-16")]
        let result = QuickTodo.restoring("a", items: items, archive: archive, today: "2026-10-18")
        XCTAssertEqual(Set(result.items.map(\.id)).count, 2)
    }

    func testRemovingArchivedAndDayLabel() {
        let archive = [TodoItem(id: "a", text: "一", done: true, doneDay: "2026-10-17"),
                       TodoItem(id: "b", text: "二", done: true, doneDay: "2026-10-15")]
        XCTAssertEqual(QuickTodo.removingArchived("a", from: archive).map(\.id), ["b"])
        XCTAssertEqual(QuickTodo.archivedDayLabel(archive[0], today: "2026-10-18", calendar: calendar), "昨天")
        XCTAssertEqual(QuickTodo.archivedDayLabel(archive[1], today: "2026-10-18", calendar: calendar), "10/15")
    }

    // MARK: 快捷键小框

    func testCaptureTargetFindsGroupedTodo() {
        let grouped = WidgetInstance(kind: .todo, config: WidgetConfig())
        let other = WidgetInstance(kind: .notes, config: WidgetConfig())
        let inner = DockGroup(name: "里面", items: [.widget(grouped)])
        let items: [DockItem] = [.widget(other), .group(DockGroup(name: "外面", items: [.group(inner)]))]
        XCTAssertEqual(QuickTodo.captureTarget(in: items)?.id, grouped.id)
        // 顶层有就用顶层的。
        let top = WidgetInstance(kind: .todo, config: WidgetConfig())
        XCTAssertEqual(QuickTodo.captureTarget(in: items + [.widget(top)])?.id, top.id)
        XCTAssertNil(QuickTodo.captureTarget(in: [.widget(other)]))
    }

    func testReplacingWidgetInsideGroup() {
        var todo = WidgetInstance(kind: .todo, config: WidgetConfig())
        let items: [DockItem] = [.group(DockGroup(name: "组", items: [.widget(todo)]))]
        QuickTodo.store([TodoItem(id: "n", text: "记一条")], in: &todo.config)
        let updated = ShelfItems.replacingWidget(todo, in: items)
        XCTAssertEqual(updated?.first?.group?.items.first?.widget?.config, todo.config)
        XCTAssertNil(ShelfItems.replacingWidget(WidgetInstance(kind: .todo, config: WidgetConfig()), in: items))
    }
}
