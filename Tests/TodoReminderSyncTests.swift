import Foundation
import XCTest

/// 快速待办和系统提醒事项双向同步（Pro）：指纹、分辨哪边改过、两边删除、新建和关联，
/// 以及没解锁时不跑。读写 EventKit 在 Services 里，这里只测算出来的计划。
final class TodoReminderSyncTests: XCTestCase {
    private let today = "2026-10-22"
    /// 正好落在整分钟上，指纹按分钟算，两边一致。
    private let due = Date(timeIntervalSince1970: 1_792_000_020)
    /// 2027 年，离“今天”很远，换时区也不会落到今天。
    private let farFuture = Date(timeIntervalSince1970: 1_830_000_000)
    /// 2026 年初，早于今天。
    private let past = Date(timeIntervalSince1970: 1_767_600_000)

    private func linked(_ item: TodoItem, to remote: String) -> TodoItem {
        QuickTodo.linking(item.id, to: remote, in: [item])[0]
    }

    // MARK: 指纹

    func testFingerprintIsStableFNV() {
        // "a␟0␟-␟0" 的 FNV-1a 64 位，换进程、换机器都一样。
        XCTAssertEqual(TodoReminderSync.fingerprint(title: "a", done: false, due: nil, important: false),
                       "1bb92d7147cdf2fc")
        let item = TodoItem(id: "1", text: "交稿", remindAt: due, important: true)
        let remote = TodoRemoteReminder(id: "R", title: "  交稿 ", due: due, important: true)
        XCTAssertEqual(TodoReminderSync.fingerprint(item), TodoReminderSync.fingerprint(remote))
        XCTAssertNotEqual(TodoReminderSync.fingerprint(item),
                          TodoReminderSync.fingerprint(TodoItem(id: "1", text: "交稿", done: true,
                                                                remindAt: due, important: true)))
    }

    func testLinkingRemembersTheRemoteAndTheMark() {
        let item = linked(TodoItem(id: "1", text: "买牛奶"), to: "R1")
        XCTAssertEqual(item.externalID, "R1")
        XCTAssertEqual(item.syncMark, TodoReminderSync.fingerprint(item))
        XCTAssertNil(QuickTodo.unlinkingAll([item])[0].externalID)
        XCTAssertNil(QuickTodo.unlinkingAll([item])[0].syncMark)
    }

    // MARK: 哪边改过

    func testNothingChangedTouchesNothing() {
        let item = linked(TodoItem(id: "1", text: "买牛奶", remindAt: due), to: "R1")
        let plan = TodoReminderSync.plan(items: [item], archive: [],
                                         remote: [TodoRemoteReminder(id: "R1", title: "买牛奶", due: due)],
                                         known: ["R1"], today: today)
        XCTAssertFalse(plan.touchesRemote)
        XCTAssertEqual(plan.items, [item])
        XCTAssertEqual(plan.known, ["R1"])
    }

    func testOnlyTheReminderChangedSoTheTodoFollows() {
        let item = linked(TodoItem(id: "1", text: "买牛奶"), to: "R1")
        let plan = TodoReminderSync.plan(items: [item], archive: [],
                                         remote: [TodoRemoteReminder(id: "R1", title: "买燕麦奶", done: true,
                                                                     important: true)],
                                         known: ["R1"], today: today)
        XCTAssertFalse(plan.touchesRemote)
        let changed = plan.items[0]
        XCTAssertEqual(changed.text, "买燕麦奶")
        XCTAssertTrue(changed.done)
        XCTAssertEqual(changed.doneDay, today)
        XCTAssertTrue(changed.important)
        XCTAssertEqual(changed.syncMark, TodoReminderSync.fingerprint(changed))
    }

    func testAReminderMovedToTodayPutsTheTodoInToday() {
        let item = linked(TodoItem(id: "1", text: "交电费"), to: "R1")
        let plan = TodoReminderSync.plan(items: [item], archive: [],
                                         remote: [TodoRemoteReminder(id: "R1", title: "交电费", due: past)],
                                         known: ["R1"], today: today)
        XCTAssertTrue(plan.items[0].today)
        XCTAssertEqual(plan.items[0].todaySince, today)
    }

    func testTheTodoChangedSoTheReminderIsWritten() {
        var item = linked(TodoItem(id: "1", text: "买牛奶"), to: "R1")
        item.text = "买两盒牛奶"
        let plan = TodoReminderSync.plan(items: [item], archive: [],
                                         remote: [TodoRemoteReminder(id: "R1", title: "买牛奶")],
                                         known: ["R1"], today: today)
        XCTAssertEqual(plan.update.map(\.remoteID), ["R1"])
        XCTAssertEqual(plan.update.first?.item.text, "买两盒牛奶")
        XCTAssertEqual(plan.items[0].syncMark, TodoReminderSync.fingerprint(plan.items[0]))
    }

    func testWhenBothChangedTheTodoWins() {
        var item = linked(TodoItem(id: "1", text: "买牛奶"), to: "R1")
        item.important = true
        let plan = TodoReminderSync.plan(items: [item], archive: [],
                                         remote: [TodoRemoteReminder(id: "R1", title: "买酸奶")],
                                         known: ["R1"], today: today)
        XCTAssertEqual(plan.update.first?.item.text, "买牛奶")
        XCTAssertEqual(plan.items[0].text, "买牛奶")
        XCTAssertTrue(plan.items[0].important)
    }

    // MARK: 删除

    func testDeletedInRemindersAndUntouchedHereGoesToo() {
        let item = linked(TodoItem(id: "1", text: "买牛奶"), to: "R1")
        let plan = TodoReminderSync.plan(items: [item], archive: [], remote: [], known: ["R1"], today: today)
        XCTAssertTrue(plan.items.isEmpty)
        XCTAssertTrue(plan.known.isEmpty)
        XCTAssertFalse(plan.touchesRemote)
    }

    func testDeletedInRemindersButEditedHereIsMadeAgain() {
        var item = linked(TodoItem(id: "1", text: "买牛奶"), to: "R1")
        item.text = "买豆浆"
        let plan = TodoReminderSync.plan(items: [item], archive: [], remote: [], known: ["R1"], today: today)
        XCTAssertEqual(plan.items.map(\.text), ["买豆浆"])
        XCTAssertNil(plan.items[0].externalID)
        XCTAssertEqual(plan.create, ["1"])
    }

    func testAnUnknownRemoteIsUnlinkedNotDeleted() {
        // 换了列表：原来的标识不在 known 里，只解开，没做完的在新列表里建。
        let open = linked(TodoItem(id: "1", text: "买牛奶"), to: "OLD1")
        let done = linked(TodoItem(id: "2", text: "交稿", done: true), to: "OLD2")
        let plan = TodoReminderSync.plan(items: [open, done], archive: [], remote: [], known: [], today: today)
        XCTAssertEqual(plan.items.count, 2)
        XCTAssertTrue(plan.items.allSatisfy { $0.externalID == nil && $0.syncMark == nil })
        XCTAssertEqual(plan.create, ["1"])
    }

    func testDeletedHereRemovesOpenRemindersButKeepsFinishedOnes() {
        let plan = TodoReminderSync.plan(items: [], archive: [],
                                         remote: [TodoRemoteReminder(id: "R2", title: "订会议室"),
                                                  TodoRemoteReminder(id: "R3", title: "写周报", done: true)],
                                         known: ["R2", "R3"], today: today)
        XCTAssertEqual(plan.delete, ["R2"])
        XCTAssertTrue(plan.items.isEmpty)
        XCTAssertFalse(plan.known.contains("R2"))
    }

    func testShelvedItemsKeepTheirFinishedReminders() {
        let shelved = linked(TodoItem(id: "9", text: "写周报", done: true), to: "R5")
        let plan = TodoReminderSync.plan(items: [], archive: [shelved],
                                         remote: [TodoRemoteReminder(id: "R5", title: "写周报", done: true)],
                                         known: ["R5"], today: today)
        XCTAssertTrue(plan.delete.isEmpty)
        XCTAssertTrue(plan.items.isEmpty)
        XCTAssertEqual(plan.known, ["R5"])
    }

    // MARK: 新建

    func testNewOpenRemindersBecomeTodos() {
        let plan = TodoReminderSync.plan(items: [], archive: [],
                                         remote: [TodoRemoteReminder(id: "R6", title: "订机票", due: farFuture,
                                                                     important: true),
                                                  TodoRemoteReminder(id: "R7", title: "交电费", due: past),
                                                  TodoRemoteReminder(id: "R8", title: "看过的", done: true)],
                                         known: [], today: today, newID: { "n\(UUID().uuidString.prefix(4))" })
        XCTAssertEqual(plan.items.count, 2)
        let flight = plan.items.first { $0.externalID == "R6" }
        XCTAssertEqual(flight?.text, "订机票")
        XCTAssertEqual(flight?.today, false)
        XCTAssertEqual(flight?.important, true)
        XCTAssertEqual(flight?.addedDay, today)
        XCTAssertEqual(flight.map { TodoReminderSync.fingerprint($0) }, flight?.syncMark)
        let bill = plan.items.first { $0.externalID == "R7" }
        XCTAssertEqual(bill?.today, true)
        XCTAssertEqual(bill?.todaySince, today)
        XCTAssertEqual(Set(plan.known), ["R6", "R7"])
        XCTAssertFalse(plan.touchesRemote)
    }

    func testUnlinkedOpenTodosAreCreatedInReminders() {
        let plan = TodoReminderSync.plan(items: [TodoItem(id: "1", text: "买牛奶"),
                                                 TodoItem(id: "2", text: "交稿", done: true)],
                                         archive: [], remote: [], known: [], today: today)
        XCTAssertEqual(plan.create, ["1"])
        XCTAssertTrue(plan.touchesRemote)
    }

    // MARK: 开关

    func testSyncRunsOnlyWhenOnAndUnlocked() {
        var config = WidgetConfig()
        XCTAssertFalse(TodoReminderSync.isActive(config, unlocked: true))
        config.set(TodoReminderSync.enabledKey, .bool(true))
        XCTAssertTrue(TodoReminderSync.isEnabled(config))
        XCTAssertTrue(TodoReminderSync.isActive(config, unlocked: true))
        // 没解锁：开关照旧存着，只是不跑。
        XCTAssertFalse(TodoReminderSync.isActive(config, unlocked: false))
        XCTAssertTrue(TodoReminderSync.isEnabled(config))
        TodoReminderSync.storeKnown(["R1", "R2"], in: &config)
        XCTAssertEqual(TodoReminderSync.known(config), ["R1", "R2"])
        TodoReminderSync.storeKnown([], in: &config)
        XCTAssertTrue(TodoReminderSync.known(config).isEmpty)
    }
}
