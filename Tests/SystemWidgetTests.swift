import Foundation
import XCTest

/// 系统小组件：快照编码、扩展点按叠加（`SystemWidgetSnapshot.applying`）、动作文件读写
/// （`SystemWidgetStore`），以及主 App 从卡片拼快照、合并点按（`SystemWidgetBridge`）。
final class SystemWidgetTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func tempStore() throws -> SystemWidgetStore {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "sw-\(UUID().uuidString)", directoryHint: .isDirectory)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return SystemWidgetStore(directory: dir)
    }

    private func sample(now: Date) -> SystemWidgetSnapshot {
        SystemWidgetSnapshot(
            todos: [.init(id: "T", title: "快速待办", items: [
                .init(id: "a", text: "交稿", today: true),
                .init(id: "b", text: "买菜", today: false),
            ])],
            waters: [.init(id: "W", title: "喝水", day: SystemWidgetSnapshot.dayKey(now), total: 500,
                           goal: 2000, cup: 250)])
    }

    // MARK: 快照

    func testSnapshotRoundTripsThroughTheStore() throws {
        let store = try tempStore()
        let now = date(2026, 10, 27)
        var snap = sample(now: now)
        snap.weather = .init(city: "北京", temperatureC: 12.5, symbol: "sun.max.fill", condition: "晴",
                             highC: 16, lowC: 6, asOf: now)
        snap.clocks = [.init(id: "C", title: "世界时钟", cities: [.init(name: "伦敦", zone: "Europe/London")])]
        XCTAssertTrue(try store.save(snap))
        XCTAssertEqual(store.loadSnapshot(), snap)
        XCTAssertFalse(try store.save(snap), "unchanged content is not rewritten")
        snap.language = "en"
        XCTAssertTrue(try store.save(snap))
    }

    func testANewerSnapshotVersionIsRefused() throws {
        let store = try tempStore()
        var snap = sample(now: .now)
        snap.version = SystemWidgetSnapshot.currentVersion + 1
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try SystemWidgetStore.encoder().encode(snap).write(to: store.snapshotURL)
        XCTAssertNil(store.loadSnapshot())
    }

    func testDaysToATargetAreSigned() {
        let today = date(2026, 10, 27, 23)
        XCTAssertEqual(SystemWidgetSnapshot.days(to: "2026-10-30", from: today, calendar: calendar), 3)
        XCTAssertEqual(SystemWidgetSnapshot.days(to: "2026-10-27", from: today, calendar: calendar), 0)
        XCTAssertEqual(SystemWidgetSnapshot.days(to: "2026-10-20", from: today, calendar: calendar), -7)
        XCTAssertNil(SystemWidgetSnapshot.days(to: "坏的", from: today, calendar: calendar))
        XCTAssertEqual(SystemWidgetSnapshot.dayKey(date(2026, 3, 5), calendar: calendar), "2026-03-05")
    }

    // MARK: 叠加点按

    func testTogglingATodoIsAppliedOnTopOfTheSnapshot() {
        let now = date(2026, 10, 27)
        let snap = sample(now: now)
        let shown = snap.applying([.toggleTodo(card: "T", item: "a", done: true, at: now)], now: now)
        XCTAssertEqual(shown.todos[0].items.first { $0.id == "a" }?.done, true)
        // 设成某个状态，叠两次还是那个状态。
        let twice = snap.applying([.toggleTodo(card: "T", item: "a", done: true, at: now),
                                   .toggleTodo(card: "T", item: "a", done: true, at: now)], now: now)
        XCTAssertEqual(twice, shown)
        // 后点的赢。
        let back = snap.applying([.toggleTodo(card: "T", item: "a", done: true, at: now),
                                  .toggleTodo(card: "T", item: "a", done: false, at: now.addingTimeInterval(1))],
                                 now: now)
        XCTAssertEqual(back.todos[0].items.first { $0.id == "a" }?.done, false)
    }

    func testAddingWaterCountsEachTapAndSkipsHandledOnes() {
        let now = date(2026, 10, 27)
        var snap = sample(now: now)
        let one = SystemWidgetAction.addWater(card: "W", amount: nil, at: now)
        let two = SystemWidgetAction.addWater(card: "W", amount: 300, at: now.addingTimeInterval(5))
        XCTAssertEqual(snap.applying([one, two], now: now).waters[0].total, 500 + 250 + 300)
        // 主 App 已经把第一杯合并进快照：不再叠。
        snap.waters[0].total = 750
        snap.handled = [one.id]
        XCTAssertEqual(snap.applying([one, two], now: now).waters[0].total, 1050)
    }

    func testWaterFromAnotherDayStartsAtZero() {
        let yesterday = date(2026, 10, 26)
        let today = date(2026, 10, 27)
        let snap = sample(now: yesterday)
        XCTAssertEqual(snap.waterTotal(snap.waters[0], now: today), 0)
        XCTAssertEqual(snap.waterTotal(snap.waters[0], now: yesterday), 500)
        let shown = snap.applying([.addWater(card: "W", amount: nil, at: today)], now: today)
        XCTAssertEqual(shown.waters[0].total, 250)
        XCTAssertEqual(shown.waters[0].day, SystemWidgetSnapshot.dayKey(today))
    }

    func testUnknownCardsAndItemsAreIgnored() {
        let now = date(2026, 10, 27)
        let snap = sample(now: now)
        let shown = snap.applying([.toggleTodo(card: "X", item: "a", done: true, at: now),
                                   .toggleTodo(card: "T", item: "zz", done: true, at: now),
                                   .addWater(card: "nope", amount: 250, at: now)], now: now)
        XCTAssertEqual(shown, snap)
    }

    func testHandledIdsAreCappedAndDeduplicated() {
        let kept = SystemWidgetSnapshot.remembering(["c", "a"], in: ["a", "b"], limit: 3)
        XCTAssertEqual(kept, ["a", "b", "c"])
        let capped = SystemWidgetSnapshot.remembering(["d", "e"], in: ["a", "b", "c"], limit: 3)
        XCTAssertEqual(capped, ["c", "d", "e"])
    }

    func testShownTodosPutTodayFirstThenLaterThenDone() {
        let items: [SystemWidgetSnapshot.TodoItem] = [
            .init(id: "1", text: "x", done: true, today: true),
            .init(id: "2", text: "y", today: false),
            .init(id: "3", text: "z", today: true),
        ]
        XCTAssertEqual(SystemWidgetSnapshot.shownTodos(items, limit: 5).map(\.id), ["3", "2", "1"])
        XCTAssertEqual(SystemWidgetSnapshot.shownTodos(items, limit: 2).map(\.id), ["3", "2"])
        XCTAssertEqual(SystemWidgetSnapshot.openToday(items), 1)
    }

    // MARK: 动作文件

    func testRecordedActionsArePendingUntilRemoved() throws {
        let store = try tempStore()
        // 整秒：动作文件里的时间按 ISO 8601 存，不带小数秒。
        let now = Date(timeIntervalSince1970: Date.now.timeIntervalSince1970.rounded(.down))
        try store.save(sample(now: now))
        let action = SystemWidgetAction.addWater(card: "W", amount: nil, at: now)
        try store.record(action)
        XCTAssertEqual(store.pendingActions().map(\.action), [action])
        XCTAssertEqual(store.current(now: now)?.waters.first?.total, 750)
        try FileManager.default.removeItem(at: store.pendingActions()[0].url)
        XCTAssertTrue(store.pendingActions().isEmpty)
        XCTAssertEqual(store.current(now: now)?.waters.first?.total, 500)
    }

    func testAnUnreadableActionFileIsReportedNotApplied() throws {
        let store = try tempStore()
        try FileManager.default.createDirectory(at: store.actionsDirectory, withIntermediateDirectories: true)
        let bad = store.actionsDirectory.appending(path: "bad.json")
        try Data("{".utf8).write(to: bad)
        XCTAssertTrue(store.pendingActions().isEmpty)
        XCTAssertEqual(store.unreadableActionFiles().map(\.lastPathComponent), ["bad.json"])
    }

    // MARK: 主 App 拼快照

    private func todoWidget(_ items: [TodoItem]) -> WidgetInstance {
        var config = WidgetConfig()
        QuickTodo.store(items, in: &config)
        return WidgetInstance(kind: .todo, config: config)
    }

    func testTodoCardsCarryOpenItemsAndTodaysDoneOnes() {
        let now = date(2026, 10, 27)
        let today = TodoDay.key(now)
        let w = todoWidget([
            TodoItem(id: "a", text: "交稿", today: true, tag: .red),
            TodoItem(id: "b", text: "买菜", today: false),
            TodoItem(id: "c", text: "旧的", done: true, today: true, doneDay: "2026-10-01"),
            TodoItem(id: "d", text: "刚做完", done: true, today: true, doneDay: today),
        ])
        let snap = SystemWidgetBridge.snapshot(from: [w], live: .init(), now: now)
        XCTAssertEqual(snap.todos.count, 1)
        XCTAssertEqual(snap.todos[0].id, w.id.uuidString)
        XCTAssertEqual(snap.todos[0].title, "快速待办")
        XCTAssertEqual(snap.todos[0].items.map(\.id), ["a", "b", "d"])
        XCTAssertEqual(snap.todos[0].items[0].color, TodoTag.red.hex, "red is free")
    }

    func testCardsOfOneKindAreNumberedAndDeduplicated() {
        let a = todoWidget([])
        let b = todoWidget([])
        let snap = SystemWidgetBridge.snapshot(from: [a, b, a], live: .init(), now: date(2026, 10, 27))
        XCTAssertEqual(snap.todos.map(\.title), ["快速待办 1", "快速待办 2"])
        XCTAssertEqual(SystemWidgetBridge.numbered("喝水", index: 0, count: 1), "喝水")
    }

    func testWaterWorldClockNotesAndCalcAreCarried() {
        let now = date(2026, 10, 27)
        var water = WidgetConfig()
        WaterIntake.store(WaterIntake.logging(.water, amount: 400, in: [], goal: 2000, now: now),
                          in: &water, now: now)
        var world = WidgetConfig()
        WorldClockList.write([WorldCity(name: "东京", zone: "Asia/Tokyo"),
                              WorldCity(name: "伦敦", zone: "Europe/London")], to: &world)
        var note = WidgetConfig()
        note.set(StickyStack.textKey, .string("买牛奶\n[ ] 鸡蛋\n[x] 面包"))
        var calc = WidgetConfig()
        calc.set(SmartCalc.expressionKey, .string("12*3"))
        let widgets = [WidgetInstance(kind: .water, config: water),
                       WidgetInstance(kind: .world, config: world),
                       WidgetInstance(kind: .notes, config: note),
                       WidgetInstance(kind: .calculator, config: calc),
                       WidgetInstance(kind: .stock, config: WidgetConfig())]
        let snap = SystemWidgetBridge.snapshot(from: widgets, live: .init(language: "en"), now: now)
        XCTAssertEqual(snap.language, "en")
        XCTAssertEqual(snap.waters.first?.total, 400)
        XCTAssertEqual(snap.waters.first?.cup, WaterIntake.cupSize(water))
        XCTAssertEqual(snap.waters.first?.day, SystemWidgetSnapshot.dayKey(now))
        XCTAssertEqual(snap.clocks.first?.cities.map(\.zone), ["Asia/Tokyo", "Europe/London"])
        XCTAssertEqual(snap.notes.first?.text, "买牛奶\n☐ 鸡蛋\n☑ 面包")
        XCTAssertEqual(snap.notes.first?.title, "便签 · 买牛奶")
        XCTAssertEqual(snap.notes.first?.paper, PaperColor.yellow.hex)
        XCTAssertEqual(snap.calcs.first?.result, "36")
    }

    func testAnniversaryTargetsReadAsUpcomingTodayOrPast() {
        let now = date(2026, 10, 27)
        var config = WidgetConfig()
        Anniversary.store([
            AnniversaryEvent(id: "x", title: "圣诞", day: "20261225", kind: .countdown),
            AnniversaryEvent(id: "y", title: "在一起", day: "20200520", kind: .countup),
            AnniversaryEvent(id: "z", title: "今天", day: "20261027", kind: .countdown),
        ], in: &config)
        let snap = SystemWidgetBridge.snapshot(from: [WidgetInstance(kind: .anniversary, config: config)],
                                               live: .init(), now: now)
        let events = snap.anniversaries[0].events
        func days(_ id: String) -> Int? {
            events.first { $0.id == id }.flatMap { SystemWidgetSnapshot.days(to: $0.target, from: now) }
        }
        XCTAssertEqual(days("z"), 0)
        XCTAssertEqual(days("x"), 59)
        XCTAssertLessThan(days("y") ?? 0, 0, "counting up reads as 已经 N 天")
        XCTAssertEqual(events.first?.id, "z", "today comes first")
    }

    // MARK: 合并点按

    func testTogglingResolvesToTheCardAndKnowsWhenItClearsToday() {
        let w = todoWidget([TodoItem(id: "a", text: "交稿", today: true),
                            TodoItem(id: "b", text: "买菜", today: false)])
        let action = SystemWidgetAction.toggleTodo(card: w.id.uuidString, item: "a", done: true)
        XCTAssertEqual(SystemWidgetBridge.resolve(action, widgets: [w]),
                       .toggleTodo(widget: w.id, item: "a", cheering: true))
        let later = SystemWidgetAction.toggleTodo(card: w.id.uuidString, item: "b", done: true)
        XCTAssertEqual(SystemWidgetBridge.resolve(later, widgets: [w]),
                       .toggleTodo(widget: w.id, item: "b", cheering: false))
    }

    func testAnActionAlreadyInPlaceOrForAMissingCardIsSkipped() {
        let w = todoWidget([TodoItem(id: "a", text: "交稿", done: true, today: true)])
        XCTAssertEqual(SystemWidgetBridge.resolve(.toggleTodo(card: w.id.uuidString, item: "a", done: true),
                                                  widgets: [w]), .skip)
        XCTAssertEqual(SystemWidgetBridge.resolve(.toggleTodo(card: w.id.uuidString, item: "gone", done: true),
                                                  widgets: [w]), .skip)
        XCTAssertEqual(SystemWidgetBridge.resolve(.toggleTodo(card: UUID().uuidString, item: "a", done: false),
                                                  widgets: [w]), .skip)
        XCTAssertEqual(SystemWidgetBridge.resolve(.addWater(card: w.id.uuidString, amount: 250),
                                                  widgets: [w]), .skip, "wrong kind")
    }

    func testAddingWaterUsesTheCupAndClampsTheAmount() {
        let w = WidgetInstance(kind: .water, config: WidgetConfig())
        XCTAssertEqual(SystemWidgetBridge.resolve(.addWater(card: w.id.uuidString, amount: nil), widgets: [w]),
                       .addWater(widget: w.id, amount: WaterIntake.cupSize(w.config)))
        XCTAssertEqual(SystemWidgetBridge.resolve(.addWater(card: w.id.uuidString, amount: 99_999), widgets: [w]),
                       .addWater(widget: w.id, amount: WaterIntake.cupRange.upperBound))
    }
}
