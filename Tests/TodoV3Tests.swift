import Foundation
import XCTest

/// 快速待办 v3：五色标签（红色就是原来的「重要」）、重复待办、⌥↑ / ⌥↓ 挪动、
/// 「今天」清空即庆祝、最近 7 天的小圆点、扩展栏卡片的几种样子。
final class TodoV3Tests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func roundTrip(_ items: [TodoItem]) -> [TodoItem] {
        var config = WidgetConfig()
        QuickTodo.store(items, in: &config)
        return QuickTodo.items(config)
    }

    // MARK: 标签

    func testTagsRoundTripAndRedIsTheOldImportant() {
        let items = [TodoItem(id: "a", text: "一", tag: .red),
                     TodoItem(id: "b", text: "二", tag: .orange),
                     TodoItem(id: "c", text: "三", tag: .purple),
                     TodoItem(id: "d", text: "四")]
        let back = roundTrip(items)
        XCTAssertEqual(back.map(\.tag), [.red, .orange, .purple, nil])
        XCTAssertEqual(back.map(\.important), [true, false, false, false])
        XCTAssertEqual(back.map(\.text), ["一", "二", "三", "四"], "新字段不会接进文字里")
    }

    func testOldImportantFlagReadsAsRed() {
        var config = WidgetConfig()
        config.set(QuickTodo.key, .list([.string("a\t0\t交电费\tf=1")]))
        let item = QuickTodo.items(config).first
        XCTAssertEqual(item?.tag, .red)
        XCTAssertTrue(item?.important == true)
    }

    func testRedIsStoredAsTheOldFlagSoSyncAndOlderBuildsAgree() {
        var config = WidgetConfig()
        QuickTodo.store([TodoItem(id: "a", text: "一", tag: .red)], in: &config)
        XCTAssertEqual(config.strings(QuickTodo.key), ["a\t0\t一\tf=1"])
        QuickTodo.store([TodoItem(id: "a", text: "一", tag: .green)], in: &config)
        XCTAssertEqual(config.strings(QuickTodo.key), ["a\t0\t一\tc=g"])
    }

    func testImportantSetterOnlyTouchesRed() {
        var item = TodoItem(id: "a", text: "一", tag: .yellow)
        item.important = false
        XCTAssertEqual(item.tag, .yellow, "提醒事项那边没有旗标时，别的颜色不动")
        item.important = true
        XCTAssertEqual(item.tag, .red)
        item.important = false
        XCTAssertNil(item.tag)
        XCTAssertEqual(TodoItem(id: "b", text: "二", important: true).tag, .red)
    }

    func testSyncFromRemindersKeepsNonRedColors() {
        let item = TodoItem(id: "a", text: "交稿", tag: .green)
        let remote = TodoRemoteReminder(id: "R", title: "交稿", important: false)
        XCTAssertEqual(TodoReminderSync.applying(remote, to: item, today: "2026-10-26").tag, .green)
        let flagged = TodoRemoteReminder(id: "R", title: "交稿", important: true)
        XCTAssertEqual(TodoReminderSync.applying(flagged, to: item, today: "2026-10-26").tag, .red)
    }

    func testTagging() {
        let items = [TodoItem(id: "a", text: "一"), TodoItem(id: "b", text: "二")]
        let tagged = QuickTodo.tagging("b", with: .purple, in: items)
        XCTAssertEqual(tagged.map(\.tag), [nil, .purple])
        XCTAssertEqual(QuickTodo.tagging("b", with: nil, in: tagged).map(\.tag), [nil, nil])
    }

    func testProColorsFallBackWhenLockedWithoutRewriting() {
        XCTAssertEqual(TodoTag.shown(.orange, unlocked: false), nil)
        XCTAssertEqual(TodoTag.shown(.red, unlocked: false), .red)
        XCTAssertEqual(TodoTag.shown(.green, unlocked: true), .green)
        XCTAssertTrue(TodoTag.canChoose(.red, unlocked: false))
        XCTAssertTrue(TodoTag.canChoose(nil, unlocked: false))
        XCTAssertFalse(TodoTag.canChoose(.yellow, unlocked: false))
        XCTAssertTrue(TodoTag.canChoose(.yellow, unlocked: true))
        XCTAssertEqual(TodoTag.allCases.filter(\.isPro), [.orange, .yellow, .green, .purple])
    }

    func testShortcutNumbers() {
        XCTAssertEqual(TodoTag.allCases.map(\.shortcutNumber), [1, 2, 3, 4, 5])
        XCTAssertEqual(TodoTag.shortcut(1), .red)
        XCTAssertEqual(TodoTag.shortcut(5), .purple)
        XCTAssertNil(TodoTag.shortcut(0))
        XCTAssertNil(TodoTag.shortcut(6))
        XCTAssertEqual(TodoTag(code: "y"), .yellow)
        XCTAssertNil(TodoTag(code: "z"))
    }

    func testFilterByColorOnlyWhenUnlocked() {
        let items = [TodoItem(id: "a", text: "一", tag: .green),
                     TodoItem(id: "b", text: "二", tag: .red),
                     TodoItem(id: "c", text: "三")]
        XCTAssertEqual(QuickTodo.filtered(items, by: .green, unlocked: true).map(\.id), ["a"])
        XCTAssertEqual(QuickTodo.filtered(items, by: .green, unlocked: false).map(\.id), ["a", "b", "c"])
        XCTAssertEqual(QuickTodo.filtered(items, by: nil, unlocked: true).map(\.id), ["a", "b", "c"])
    }

    // MARK: 重复

    func testRepeatRulesStep() {
        let calendar = utc
        let friday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 9))!
        XCTAssertEqual(TodoDay.key(TodoRepeat.daily.next(after: friday, calendar: calendar), calendar: calendar), "2026-10-24")
        XCTAssertEqual(TodoDay.key(TodoRepeat.weekly.next(after: friday, calendar: calendar), calendar: calendar), "2026-10-30")
        XCTAssertEqual(TodoDay.key(TodoRepeat.weekdays.next(after: friday, calendar: calendar), calendar: calendar), "2026-10-26",
                       "周五之后的工作日是下周一")
    }

    func testRepeatRoundTrips() {
        let back = roundTrip([TodoItem(id: "a", text: "吃药", repeatRule: .weekdays, planDay: "2026-10-27", repeatOf: "z")])
        XCTAssertEqual(back.first?.repeatRule, .weekdays)
        XCTAssertEqual(back.first?.planDay, "2026-10-27")
        XCTAssertEqual(back.first?.repeatOf, "z")
        XCTAssertEqual(back.first?.text, "吃药")
    }

    func testCompletingARepeatSpawnsTheNextOneInLater() {
        let calendar = utc
        let nine = calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 9))!
        let items = [TodoItem(id: "a", text: "吃药", today: true, addedDay: "2026-10-26", remindAt: nine,
                              todaySince: "2026-10-26", tag: .green, repeatRule: .daily)]
        let after = QuickTodo.toggling("a", in: items, day: "2026-10-26", repeats: true, nextID: "n", calendar: calendar)
        XCTAssertEqual(after.count, 2)
        let next = after.first { $0.id == "n" }
        XCTAssertEqual(next?.done, false)
        XCTAssertEqual(next?.today, false, "下一次在「稍后」")
        XCTAssertEqual(next?.tag, .green)
        XCTAssertEqual(next?.repeatRule, .daily)
        XCTAssertEqual(next?.repeatOf, "a")
        XCTAssertEqual(next.flatMap(\.remindAt), calendar.date(byAdding: .day, value: 1, to: nine), "保留时刻")
        XCTAssertEqual(after.last?.id, "a")
        XCTAssertEqual(after.last?.done, true)
    }

    func testRepeatWithoutTimeIsPlannedAndPromotedOnThatDay() {
        let calendar = utc
        let items = [TodoItem(id: "a", text: "周报", today: true, addedDay: "2026-10-23",
                              todaySince: "2026-10-23", repeatRule: .weekdays)]
        let after = QuickTodo.toggling("a", in: items, day: "2026-10-23", repeats: true, nextID: "n", calendar: calendar)
        let next = after.first { $0.id == "n" }
        XCTAssertNil(next?.remindAt)
        XCTAssertEqual(next?.planDay, "2026-10-26")
        // 周一第一次打开：升进「今天」。
        let monday = QuickTodo.planningToday(after, today: "2026-10-26", calendar: calendar)
        XCTAssertEqual(monday.first { $0.id == "n" }?.today, true)
        // 周六还在「稍后」。
        let saturday = QuickTodo.planningToday(after, today: "2026-10-24", calendar: calendar)
        XCTAssertEqual(saturday.first { $0.id == "n" }?.today, false)
    }

    func testLateCompletionSkipsPastOccurrences() {
        let calendar = utc
        let item = TodoItem(id: "a", text: "浇花", addedDay: "2026-10-01", repeatRule: .weekly, planDay: "2026-10-01")
        let next = QuickTodo.nextOccurrence(of: item, finishedOn: "2026-10-20", id: "n", calendar: calendar)
        XCTAssertEqual(next?.planDay, "2026-10-22", "从原来那天按周数，落在勾掉那天之后")
    }

    func testNoSpawnWhenLockedOrNoRule() {
        let items = [TodoItem(id: "a", text: "吃药", today: true, repeatRule: .daily),
                     TodoItem(id: "b", text: "一次", today: true)]
        XCTAssertEqual(QuickTodo.toggling("a", in: items, day: "2026-10-26", repeats: false).count, 2,
                       "没解锁时规则照旧存着，只是不生成")
        XCTAssertEqual(QuickTodo.toggling("b", in: items, day: "2026-10-26", repeats: true).count, 2)
    }

    func testReopeningTakesBackTheSpawnedOne() {
        let items = [TodoItem(id: "a", text: "吃药", today: true, repeatRule: .daily)]
        let done = QuickTodo.toggling("a", in: items, day: "2026-10-26", repeats: true, nextID: "n", calendar: utc)
        XCTAssertEqual(done.count, 2)
        let reopened = QuickTodo.toggling("a", in: done, day: "2026-10-26", repeats: true, calendar: utc)
        XCTAssertEqual(reopened.map(\.id), ["a"])
        XCTAssertEqual(reopened.first?.done, false)
    }

    func testUndoingACompletionTakesBackTheSpawnedOne() {
        let items = [TodoItem(id: "a", text: "吃药", today: true, repeatRule: .daily)]
        var stack = TodoUndoStack()
        stack.recordCompletion(of: "a", in: items)
        let done = QuickTodo.toggling("a", in: items, day: "2026-10-26", repeats: true, nextID: "n", calendar: utc)
        let undone = TodoUndoStack.undoing(stack.last!, in: done)
        XCTAssertEqual(undone.map(\.id), ["a"])
        XCTAssertEqual(undone.first?.done, false)
    }

    func testArchivedRepeatLosesItsRule() {
        let done = TodoItem(id: "a", text: "吃药", done: true, doneDay: "2026-10-25", repeatRule: .daily, planDay: "2026-10-25")
        let shelved = QuickTodo.archiving([done], today: "2026-10-26")
        XCTAssertNil(shelved.first?.repeatRule)
        XCTAssertNil(shelved.first?.planDay)
    }

    // MARK: 挪动

    func testNudgeWithinAndAcrossGroups() {
        let today = "2026-10-26"
        let items = [TodoItem(id: "a", text: "一", today: true), TodoItem(id: "b", text: "二", today: true),
                     TodoItem(id: "c", text: "三"), TodoItem(id: "d", text: "四")]
        XCTAssertEqual(QuickTodo.nudging("b", by: -1, in: items, today: today).map(\.id), ["b", "a", "c", "d"])
        XCTAssertEqual(QuickTodo.nudging("a", by: 1, in: items, today: today).map(\.id), ["b", "a", "c", "d"])
        let down = QuickTodo.nudging("b", by: 1, in: items, today: today)
        XCTAssertEqual(down.map(\.id), ["a", "b", "c", "d"])
        XCTAssertEqual(down.first { $0.id == "b" }?.today, false, "今天最后一条往下进稍后第一条")
        XCTAssertEqual(QuickTodo.items(in: .later, of: down).map(\.id), ["b", "c", "d"])
        let up = QuickTodo.nudging("c", by: -1, in: items, today: today)
        XCTAssertEqual(up.first { $0.id == "c" }?.today, true, "稍后第一条往上进今天最后")
        XCTAssertEqual(QuickTodo.items(in: .today, of: up).map(\.id), ["a", "b", "c"])
        XCTAssertEqual(QuickTodo.nudging("a", by: -1, in: items, today: today).map(\.id), ["a", "b", "c", "d"], "顶上不动")
        XCTAssertEqual(QuickTodo.nudging("d", by: 1, in: items, today: today).map(\.id), ["a", "b", "c", "d"], "底下不动")
    }

    // MARK: 今天清空

    func testClearingTodayCountsEvenWithLaterLeft() {
        let items = [TodoItem(id: "a", text: "一", today: true), TodoItem(id: "b", text: "二")]
        XCTAssertTrue(QuickTodo.clearsToday(toggling: "a", in: items))
        XCTAssertFalse(QuickTodo.clearsToday(toggling: "b", in: items), "勾稍后的不算")
        let two = items + [TodoItem(id: "c", text: "三", today: true)]
        XCTAssertFalse(QuickTodo.clearsToday(toggling: "a", in: two))
        let done = QuickTodo.toggling("a", in: items, day: "2026-10-26")
        XCTAssertTrue(QuickTodo.todayCleared(done, today: "2026-10-26"))
        XCTAssertFalse(QuickTodo.todayCleared(items, today: "2026-10-26"))
        XCTAssertFalse(QuickTodo.todayCleared([TodoItem(id: "b", text: "二")], today: "2026-10-26"),
                       "今天一条都没勾过不算清空")
    }

    func testTodayTally() {
        let items = [TodoItem(id: "a", text: "一", today: true),
                     TodoItem(id: "b", text: "二"),
                     TodoItem(id: "c", text: "三", done: true, today: true, doneDay: "2026-10-26"),
                     TodoItem(id: "d", text: "四", done: true, doneDay: "2026-10-26")]
        let tally = QuickTodo.todayTally(items, today: "2026-10-26")
        XCTAssertEqual(tally.done, 2)
        XCTAssertEqual(tally.total, 3)
        XCTAssertEqual(QuickTodo.todayFraction(items, today: "2026-10-26"), 2.0 / 3.0, accuracy: 0.0001)
    }

    func testWeekDotsFromHistoryAndStreak() {
        let calendar = utc
        var config = WidgetConfig()
        QuickTodo.recordCleared(in: &config, today: "2026-10-20", calendar: calendar)
        QuickTodo.recordCleared(in: &config, today: "2026-10-24", calendar: calendar)
        QuickTodo.recordCleared(in: &config, today: "2026-10-25", calendar: calendar)
        QuickTodo.recordCleared(in: &config, today: "2026-10-26", calendar: calendar)
        XCTAssertEqual(TodoStreak.week(config, today: "2026-10-26", calendar: calendar),
                       [true, false, false, false, true, true, true])
        XCTAssertEqual(QuickTodo.streak(config, today: "2026-10-26", calendar: calendar), 3)
        XCTAssertEqual(TodoStreak.lastWeek("2026-10-26", calendar: calendar).first, "2026-10-20")

        // 旧数据只有连续天数：按连续那几天推出来。
        var old = WidgetConfig()
        TodoStreak(lastDay: "2026-10-25", count: 2).store(in: &old)
        XCTAssertEqual(TodoStreak.week(old, today: "2026-10-26", calendar: calendar),
                       [false, false, false, false, true, true, false])
    }

    func testHistoryIsCapped() {
        let calendar = utc
        var config = WidgetConfig()
        var day = "2026-10-26"
        for _ in 0..<30 {
            TodoStreak.recordHistory(day, in: &config)
            day = TodoDay.previous(day, calendar: calendar)!
        }
        XCTAssertEqual(config.strings(TodoStreak.historyKey).count, TodoStreak.historyLimit)
        XCTAssertEqual(config.strings(TodoStreak.historyKey).last, "2026-10-26")
    }

    // MARK: 卡片

    func testCardStates() {
        XCTAssertEqual(QuickTodo.cardState([]), .empty)
        XCTAssertEqual(QuickTodo.cardState([TodoItem(id: "a", text: "一", today: true)]), .list)
        XCTAssertEqual(QuickTodo.cardState([TodoItem(id: "b", text: "二")]), .cleared,
                       "只放今天：今天空了而稍后有事时写今天清空啦")
        let items = [TodoItem(id: "a", text: "一", today: true), TodoItem(id: "b", text: "二", today: true),
                     TodoItem(id: "c", text: "三", today: true), TodoItem(id: "d", text: "四")]
        XCTAssertEqual(QuickTodo.cardTodayRows(items).map(\.id), ["a", "b"])
    }
}
