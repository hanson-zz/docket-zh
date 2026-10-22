import Foundation
import XCTest

final class QuickTodoTodayTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    // MARK: 日子

    func testDayKeysAndThePreviousDay() {
        let date = Date(timeIntervalSince1970: 1_772_323_200) // 2026-03-01 00:00 UTC
        XCTAssertEqual(TodoDay.key(date, calendar: utc), "2026-03-01")
        XCTAssertEqual(TodoDay.previous("2026-03-01", calendar: utc), "2026-02-28")
        XCTAssertEqual(TodoDay.previous("2026-01-01", calendar: utc), "2025-12-31")
        XCTAssertTrue(TodoDay.isKey("2026-10-18"))
        XCTAssertFalse(TodoDay.isKey("2026-13-01"))
        XCTAssertFalse(TodoDay.isKey("昨天"))
        XCTAssertNil(TodoDay.previous("nope", calendar: utc))
    }

    // MARK: 存取

    func testNewFieldsRoundTripAndOldStringsStayTheSame() {
        let plain = TodoItem(id: "a", text: "买牛奶")
        XCTAssertEqual(plain.encoded, "a\t0\t买牛奶", "an item with nothing new is written as before")

        let rich = TodoItem(id: "b", text: "看文档", done: true, today: true,
                            link: "https://example.com/a?b=c", addedDay: "2026-10-17", doneDay: "2026-10-18")
        var config = WidgetConfig()
        QuickTodo.store([rich], in: &config)
        XCTAssertEqual(QuickTodo.items(config), [rich])
    }

    func testUnknownTrailingFieldsAreKeptAsWords() {
        let read = TodoItem(decoding: "x\t0\t写周报\t下午", fallbackID: "f")
        XCTAssertEqual(read?.text, "写周报 下午")
        XCTAssertEqual(read?.today, false)
    }

    func testRenameKeepsTheLinkAndTheStar() {
        let items = [TodoItem(id: "a", text: "一", today: true, link: "https://a.cn")]
        let renamed = QuickTodo.renaming("a", to: "二", in: items)
        XCTAssertEqual(renamed.first?.text, "二")
        XCTAssertEqual(renamed.first?.today, true)
        XCTAssertEqual(renamed.first?.link, "https://a.cn")
    }

    func testTogglingStampsAndClearsTheDoneDay() {
        let items = [TodoItem(id: "a", text: "一")]
        let done = QuickTodo.toggling("a", in: items, day: "2026-10-18")
        XCTAssertEqual(done.first?.doneDay, "2026-10-18")
        let reopened = QuickTodo.toggling("a", in: done, day: "2026-10-18")
        XCTAssertNil(reopened.first?.doneDay)
    }

    // MARK: 今天

    func testTodayHasNoLimitAndRemembersTheDay() {
        // 改版后「今天」不再限 3 条：拖进几条都行，记下放进来的那天，拿出去时清掉。
        var items = (1...5).map { TodoItem(id: "\($0)", text: "第\($0)条") }
        for id in ["1", "2", "3", "4", "5"] { items = QuickTodo.togglingToday(id, in: items, day: "2026-10-22") }
        XCTAssertEqual(QuickTodo.todayItems(items).map(\.id), ["1", "2", "3", "4", "5"])
        XCTAssertEqual(items.first?.todaySince, "2026-10-22")
        items = QuickTodo.togglingToday("2", in: items, day: "2026-10-22")
        XCTAssertEqual(QuickTodo.todayItems(items).map(\.id), ["1", "3", "4", "5"])
        XCTAssertNil(items.first { $0.id == "2" }?.todaySince)
    }

    func testTheCardShowsTheMarkedOnesWithTheirProgress() {
        let items = [TodoItem(id: "a", text: "一"),
                     TodoItem(id: "b", text: "二", today: true),
                     TodoItem(id: "c", text: "三", done: true, today: true),
                     TodoItem(id: "d", text: "四", today: true)]
        let card = QuickTodo.cardRows(items)
        XCTAssertTrue(card.focused)
        XCTAssertEqual(card.rows.map(\.id), ["b", "d", "c"], "open ones first, the finished one stays ticked")
        XCTAssertEqual(card.done, 1)
        XCTAssertEqual(card.total, 3)
        XCTAssertEqual(card.hidden, 1)
    }

    func testWithNothingMarkedTheCardShowsTheFirstOpenOnes() {
        let items = [TodoItem(id: "a", text: "一", done: true),
                     TodoItem(id: "b", text: "二"), TodoItem(id: "c", text: "三"),
                     TodoItem(id: "d", text: "四"), TodoItem(id: "e", text: "五")]
        let card = QuickTodo.cardRows(items)
        XCTAssertFalse(card.focused)
        XCTAssertEqual(card.rows.map(\.id), ["b", "c", "d"])
        XCTAssertEqual(card.hidden, 1)
        XCTAssertEqual(card.done, 1)
        XCTAssertEqual(card.total, 5)
    }

    // MARK: 当天清

    func testRolloverClearsYesterdaysFinishedOnesAndKeepsTheRest() {
        let items = [TodoItem(id: "a", text: "昨天做完", done: true, addedDay: "2026-10-17", doneDay: "2026-10-17"),
                     TodoItem(id: "b", text: "今天做完", done: true, addedDay: "2026-10-17", doneDay: "2026-10-18"),
                     TodoItem(id: "c", text: "昨天没做完", addedDay: "2026-10-17"),
                     TodoItem(id: "d", text: "老版本的"),
                     TodoItem(id: "e", text: "老版本做完的", done: true)]
        let rolled = QuickTodo.rollingOver(items, today: "2026-10-18")
        XCTAssertEqual(rolled.map(\.id), ["c", "d", "b", "e"])
        XCTAssertEqual(rolled.first { $0.id == "d" }?.addedDay, "2026-10-18", "old items count as today's")
        XCTAssertEqual(rolled.first { $0.id == "e" }?.doneDay, "2026-10-18")
        XCTAssertEqual(QuickTodo.leftover(rolled, today: "2026-10-18").map(\.id), ["c"])
    }

    func testRolloverRunsOncePerDay() {
        var config = WidgetConfig()
        QuickTodo.store([TodoItem(id: "a", text: "一", done: true, doneDay: "2026-10-17")], in: &config)
        XCTAssertTrue(QuickTodo.needsRollover(config, today: "2026-10-18"))
        QuickTodo.applyRollover(in: &config, today: "2026-10-18")
        XCTAssertEqual(QuickTodo.items(config).count, 0)
        XCTAssertFalse(QuickTodo.needsRollover(config, today: "2026-10-18"))
        QuickTodo.store([TodoItem(id: "b", text: "二", done: true, doneDay: "2026-10-17")], in: &config)
        QuickTodo.applyRollover(in: &config, today: "2026-10-18")
        XCTAssertEqual(QuickTodo.items(config).count, 1, "a second open on the same day changes nothing")
    }

    func testCarryOverAndGiveUp() {
        let items = [TodoItem(id: "a", text: "一", today: true, addedDay: "2026-10-16"),
                     TodoItem(id: "b", text: "二", addedDay: "2026-10-18")]
        let carried = QuickTodo.carryingOver(items, today: "2026-10-18")
        XCTAssertTrue(QuickTodo.leftover(carried, today: "2026-10-18").isEmpty)
        XCTAssertEqual(carried.first { $0.id == "a" }?.today, true)
        XCTAssertEqual(QuickTodo.droppingLeftover(items, today: "2026-10-18").map(\.id), ["b"])
    }

    func testClearedTodayNeedsSomethingFinishedToday() {
        XCTAssertFalse(QuickTodo.isClearedToday([], today: "2026-10-18"))
        let done = [TodoItem(id: "a", text: "一", done: true, doneDay: "2026-10-18")]
        XCTAssertTrue(QuickTodo.isClearedToday(done, today: "2026-10-18"))
        XCTAssertFalse(QuickTodo.isClearedToday(done + [TodoItem(id: "b", text: "二")], today: "2026-10-18"))
        let old = [TodoItem(id: "a", text: "一", done: true, doneDay: "2026-10-17")]
        XCTAssertFalse(QuickTodo.isClearedToday(old, today: "2026-10-18"))
    }

    // MARK: 连续清空

    func testStreakCountsConsecutiveDays() {
        var streak = TodoStreak()
        streak = streak.recording("2026-10-16", calendar: utc)
        streak = streak.recording("2026-10-17", calendar: utc)
        streak = streak.recording("2026-10-17", calendar: utc)
        streak = streak.recording("2026-10-18", calendar: utc)
        XCTAssertEqual(streak.count, 3)
        XCTAssertEqual(streak.current(today: "2026-10-18", calendar: utc), 3)
        XCTAssertEqual(streak.current(today: "2026-10-19", calendar: utc), 3, "still alive the next morning")
        XCTAssertEqual(streak.current(today: "2026-10-20", calendar: utc), 0, "a missed day breaks it")
        XCTAssertEqual(streak.recording("2026-10-20", calendar: utc).count, 1)
        XCTAssertEqual(streak.recording("2026-10-01", calendar: utc), streak, "an earlier day is ignored")
    }

    func testStreakAcrossMonthsAndInConfig() {
        var config = WidgetConfig()
        QuickTodo.recordCleared(in: &config, today: "2026-02-28", calendar: utc)
        QuickTodo.recordCleared(in: &config, today: "2026-03-01", calendar: utc)
        XCTAssertEqual(QuickTodo.streak(config, today: "2026-03-01", calendar: utc), 2)
        XCTAssertFalse(WidgetCatalog.configurableKeys(.todo).contains(TodoStreak.countKey))
    }

    // MARK: 拖进来记

    func testDroppedLinksFilesAndText() {
        let web = TodoDrop.url(URL(string: "https://www.example.com/docs/page/")!)
        XCTAssertEqual(web?.text, "example.com/docs/page")
        XCTAssertEqual(web?.link, "https://www.example.com/docs/page/")

        let file = TodoDrop.url(URL(fileURLWithPath: "/Users/me/Desktop/报价单.pdf"))
        XCTAssertEqual(file?.text, "报价单.pdf")
        XCTAssertEqual(file?.link, URL(fileURLWithPath: "/Users/me/Desktop/报价单.pdf").absoluteString)

        XCTAssertEqual(TodoDrop.text("  https://github.com  ")?.link, "https://github.com")
        XCTAssertEqual(TodoDrop.text("给小张回电话\n今天"), TodoDrop(text: "给小张回电话 今天"))
        XCTAssertNil(TodoDrop.text("   "))
        XCTAssertNil(TodoDrop.url(URL(string: "mailto:a@b.cn")!))
    }

    func testAddingKeepsTheLinkAndTheDay() {
        let items = QuickTodo.adding("报价单.pdf", to: [], id: "a", link: "file:///tmp/a.pdf", day: "2026-10-18")
        XCTAssertEqual(items.first?.link, "file:///tmp/a.pdf")
        XCTAssertEqual(items.first?.addedDay, "2026-10-18")
        XCTAssertEqual(items.first?.url?.isFileURL, true)
    }
}

final class QuickTodoTaglineTests: XCTestCase {
    func testTheLibrarySaysQuickTodoSyncIsOptional() {
        // 默认只存在本机，改版后可以选择和提醒事项双向同步（Pro）。
        XCTAssertEqual(WidgetLibraryGroups.note(.todo), "随手记，可选同步")
    }
}
