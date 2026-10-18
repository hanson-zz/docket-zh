import Foundation
import XCTest

final class ReminderPopupTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }()

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0, second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute, second: second))!
    }

    private func reminder(_ id: String, _ title: String, due: Date, list: String = "") -> ReminderAlert {
        ReminderAlert(kind: .reminders, itemID: id, title: title, due: due, list: list)
    }

    // MARK: 设置

    func testSettingsDefaultOnAndDecodeLeniently() throws {
        let fresh = ReminderPopupSettings()
        for kind in ReminderSoundKind.allCases { XCTAssertTrue(fresh.enabled(kind)) }
        let old = try JSONDecoder().decode(ReminderPopupSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(old, fresh)
        let partial = try JSONDecoder().decode(ReminderPopupSettings.self, from: Data(#"{"water":false,"todo":"x"}"#.utf8))
        XCTAssertFalse(partial.water)
        XCTAssertTrue(partial.todo)
        XCTAssertTrue(partial.reminders)
    }

    func testOldStateFileHasPopupsOn() throws {
        let state = try JSONDecoder().decode(PersistedState.self, from: Data("{}".utf8))
        XCTAssertEqual(state.reminderPopups, ReminderPopupSettings())
    }

    func testWaterFallsBackToNotificationOnlyWhenItsPopupIsOff() {
        var settings = ReminderPopupSettings()
        XCTAssertFalse(ReminderPopupDecision.waterUsesNotification(settings))
        settings.setEnabled(false, for: .reminders)
        XCTAssertFalse(ReminderPopupDecision.waterUsesNotification(settings))
        XCTAssertFalse(ReminderPopupDecision.shows(.reminders, settings: settings))
        settings.setEnabled(false, for: .water)
        XCTAssertTrue(ReminderPopupDecision.waterUsesNotification(settings))
        XCTAssertTrue(ReminderPopupDecision.shows(.todo, settings: settings))
    }

    func testLateTimerAfterSleepDoesNotPop() {
        let due = at(18, 15)
        XCTAssertTrue(ReminderPopupDecision.isFresh(due: due, now: due.addingTimeInterval(2)))
        XCTAssertTrue(ReminderPopupDecision.isFresh(due: due, now: due.addingTimeInterval(80)))
        XCTAssertFalse(ReminderPopupDecision.isFresh(due: due, now: due.addingTimeInterval(3600)))
    }

    // MARK: 合并

    func testSameAlertFromTwoTilesPopsOnce() {
        var queue = ReminderPopupQueue()
        let alert = reminder("a", "交房租", due: at(18, 15))
        XCTAssertEqual(queue.post(alert, now: at(18, 15)), .shown)
        XCTAssertEqual(queue.post(alert, now: at(18, 15, second: 1)), .ignored)
        XCTAssertEqual(queue.cards.count, 1)
        XCTAssertEqual(queue.front?.alerts.count, 1)
        XCTAssertFalse(queue.stacked)
    }

    func testSameKindWithinSecondsMergesIntoOneCard() {
        var queue = ReminderPopupQueue()
        let now = at(18, 15)
        XCTAssertEqual(queue.post(reminder("b", "交周报", due: now), now: now), .shown)
        XCTAssertEqual(queue.post(reminder("a", "给房东打电话", due: now), now: now.addingTimeInterval(1)), .merged)
        XCTAssertEqual(queue.post(reminder("c", "取快递", due: now), now: now.addingTimeInterval(2)), .merged)
        XCTAssertEqual(queue.cards.count, 1)
        XCTAssertEqual(queue.front?.alerts.map(\.title), ["交周报", "取快递", "给房东打电话"].sorted())
        XCTAssertEqual(queue.front?.others.count, 2)
        XCTAssertTrue(queue.stacked)
    }

    func testOtherKindOrLaterOneQueuesBehind() {
        var queue = ReminderPopupQueue()
        let now = at(18, 15)
        XCTAssertEqual(queue.post(reminder("a", "交房租", due: now), now: now), .shown)
        let water = ReminderAlert(kind: .water, itemID: "w", title: "该喝水啦", due: now)
        XCTAssertEqual(queue.post(water, now: now.addingTimeInterval(1)), .queued)
        XCTAssertEqual(queue.post(reminder("b", "交周报", due: now.addingTimeInterval(60)),
                                  now: now.addingTimeInterval(60)), .queued)
        XCTAssertEqual(queue.cards.map(\.kind), [.reminders, .water, .reminders])
        XCTAssertTrue(queue.stacked)
        queue.dismissFront()
        XCTAssertEqual(queue.front?.kind, .water)
        queue.dismissFront()
        queue.dismissFront()
        XCTAssertNil(queue.front)
        queue.dismissFront()
        XCTAssertTrue(queue.cards.isEmpty)
    }

    func testResolvingOneLeavesTheRestAndEmptyCardGoes() {
        var queue = ReminderPopupQueue()
        let now = at(18, 15)
        let a = reminder("a", "甲", due: now)
        let b = reminder("b", "乙", due: now)
        _ = queue.post(a, now: now)
        _ = queue.post(b, now: now)
        queue.resolve(a.id)
        XCTAssertEqual(queue.front?.primary?.itemID, "b")
        queue.resolve(b.id)
        XCTAssertNil(queue.front)
    }

    func testRepeatOfTheSameItemReplacesIt() {
        var queue = ReminderPopupQueue()
        let first = ReminderAlert(kind: .water, itemID: "w", title: "该喝水啦", due: at(18, 14))
        _ = queue.post(first, now: at(18, 14))
        let again = ReminderAlert(kind: .water, itemID: "w", title: "该喝水啦", due: at(18, 15))
        XCTAssertEqual(queue.post(again, now: at(18, 15)), .merged)
        XCTAssertEqual(queue.cards.count, 1)
        XCTAssertEqual(queue.front?.alerts.count, 1)
        XCTAssertEqual(queue.front?.primary?.due, at(18, 15))
    }

    func testUpdateKeepsPlace() {
        var queue = ReminderPopupQueue()
        let info = WaterPopupInfo(total: 1000, goal: 2000, cup: 250, ounces: false, character: "panda", lastDrink: nil)
        var alert = ReminderAlert(kind: .water, itemID: "w", title: "该喝水啦", due: at(18, 15), water: info)
        _ = queue.post(alert, now: at(18, 15))
        alert.water?.total = 1250
        queue.update(alert)
        XCTAssertEqual(queue.front?.primary?.water?.total, 1250)
    }

    // MARK: 自动收起

    func testCountdownPausesWhileHoveredAndExpires() {
        let start = at(18, 15)
        var countdown = ReminderPopupCountdown()
        countdown.start(at: start)
        XCTAssertEqual(countdown.remaining(at: start), 30)
        XCTAssertFalse(countdown.isExpired(at: start.addingTimeInterval(29)))
        countdown.pause(at: start.addingTimeInterval(28))
        XCTAssertFalse(countdown.isExpired(at: start.addingTimeInterval(300)))
        // 移开后至少再留 5 秒。
        countdown.resume(at: start.addingTimeInterval(300))
        XCTAssertEqual(countdown.remaining(at: start.addingTimeInterval(300)), 5, accuracy: 0.001)
        XCTAssertTrue(countdown.isExpired(at: start.addingTimeInterval(305)))
        countdown.start(at: start.addingTimeInterval(400))
        XCTAssertEqual(countdown.remaining(at: start.addingTimeInterval(410)), 20, accuracy: 0.001)
    }

    // MARK: 推迟

    func testTonightIsEightAndDisappearsLateInTheDay() {
        XCTAssertEqual(ReminderPopupSnooze.tonight(now: at(18, 15), calendar: calendar), at(18, 20))
        XCTAssertNil(ReminderPopupSnooze.tonight(now: at(18, 19, 55), calendar: calendar))
        XCTAssertNil(ReminderPopupSnooze.tonight(now: at(18, 21), calendar: calendar))
        XCTAssertEqual(ReminderPopupSnooze.choices(now: at(18, 15), calendar: calendar), [.hour, .tonight, .tomorrow])
        XCTAssertEqual(ReminderPopupSnooze.choices(now: at(18, 22), calendar: calendar), [.hour, .tomorrow])
    }

    func testReminderSnoozeTargets() {
        let now = at(18, 15, 2)
        let due = ReminderDue(date: at(18, 15), hasTime: true)
        XCTAssertEqual(ReminderPopupSnooze.reminderDue(.hour, from: due, now: now, calendar: calendar)?.date, at(18, 16, 2))
        XCTAssertEqual(ReminderPopupSnooze.reminderDue(.tonight, from: due, now: now, calendar: calendar)?.date, at(18, 20))
        XCTAssertEqual(ReminderPopupSnooze.reminderDue(.tomorrow, from: due, now: now, calendar: calendar)?.date, at(19, 15))
        XCTAssertNil(ReminderPopupSnooze.reminderDue(.tonight, from: due, now: at(18, 21), calendar: calendar))
    }

    func testLaterLandsOnAWholeMinute() {
        XCTAssertEqual(ReminderPopupSnooze.later(minutes: 15, now: at(18, 14, 30, second: 40), calendar: calendar),
                       at(18, 14, 45))
        XCTAssertEqual(ReminderPopupSnooze.later(minutes: ReminderPopupSnooze.todoMinutes, now: at(18, 16), calendar: calendar),
                       at(18, 16, 10))
    }

    // MARK: 喇叭

    func testSoundChipShowsToneAndStrikesWhenSilent() {
        let settings = ReminderSoundSettings()
        let master = WidgetSoundSettings()
        let quiet = ReminderSoundEnvironment()
        XCTAssertEqual(ReminderPopupSoundChip.make(.reminders, settings: settings, master: master, environment: quiet),
                       ReminderPopupSoundChip(label: "Glass", muted: false))
        XCTAssertEqual(ReminderPopupSoundChip.make(.water, settings: settings, master: master,
                                                   environment: ReminderSoundEnvironment(focusActive: true)),
                       ReminderPopupSoundChip(label: "Pop", muted: true))
        var off = settings
        off.setTone(.off, for: .todo)
        XCTAssertEqual(ReminderPopupSoundChip.make(.todo, settings: off, master: master, environment: quiet),
                       ReminderPopupSoundChip(label: "不响", muted: true))
        var silent = master
        silent.enabled = false
        XCTAssertTrue(ReminderPopupSoundChip.make(.todo, settings: settings, master: silent, environment: quiet).muted)
    }

    // MARK: 字

    func testHeaderSaysNowOnlyRightAtTheTime() {
        let due = at(18, 15)
        XCTAssertEqual(ReminderPopupText.header(.reminders, due: due, now: due.addingTimeInterval(5), calendar: calendar),
                       "提醒事项 · 现在")
        XCTAssertEqual(ReminderPopupText.header(.water, due: due, now: due.addingTimeInterval(120), calendar: calendar),
                       "喝水 · 15:00")
        XCTAssertEqual(ReminderPopupText.header(.todo, due: at(18, 16), now: at(18, 16), calendar: calendar),
                       "待办 · 16:00")
    }

    func testReminderLines() {
        XCTAssertEqual(ReminderPopupText.reminderDetail(due: at(18, 15), list: "工作", highPriority: true, calendar: calendar),
                       "15:00 到点 · 工作 · 高优先级 !!!")
        XCTAssertEqual(ReminderPopupText.reminderDetail(due: at(18, 9, 5), list: "", highPriority: false, calendar: calendar),
                       "09:05 到点")
        XCTAssertEqual(ReminderPopupText.listStamp(due: at(18, 15), list: "家里", calendar: calendar), "15:00 · 家里")
        XCTAssertEqual(ReminderPopupText.moreLine(2), "同时到点的还有 2 条")
    }

    func testWaterLines() {
        let now = at(18, 14, 30)
        XCTAssertEqual(ReminderPopupText.waterDetail(due: now, lastDrink: at(18, 12, 50), now: now, calendar: calendar),
                       "14:30 · 上一杯在 1 小时 40 分钟前")
        XCTAssertEqual(ReminderPopupText.waterDetail(due: now, lastDrink: at(17, 22), now: now, calendar: calendar),
                       "14:30 · 今天还没喝")
        let info = WaterPopupInfo(total: 1250, goal: 2000, cup: 250, ounces: false, character: "shiba", lastDrink: nil)
        XCTAssertEqual(info.filledCups, 5)
        XCTAssertEqual(info.cupsLeft, 3)
        XCTAssertEqual(ReminderPopupText.waterTally(info), "1250 / 2000 毫升")
        XCTAssertEqual(ReminderPopupText.cupsLeft(info), "还差 3 杯")
        XCTAssertEqual(ReminderPopupText.drinkButton(info), "加一杯 250 毫升")
        var done = info
        done.total = 2100
        XCTAssertEqual(ReminderPopupText.cupsLeft(done), "达标啦")
    }

    func testTodoLines() {
        let today = TodoDay.key(at(18, 16), calendar: calendar)
        let yesterday = TodoDay.key(at(17, 16), calendar: calendar)
        XCTAssertEqual(ReminderPopupText.todoDetail(TodoPopupInfo(today: true, addedDay: yesterday), today: today,
                                                    calendar: calendar),
                       "今天三件事之一 · 昨天记下的")
        XCTAssertEqual(ReminderPopupText.todoDetail(TodoPopupInfo(today: false, addedDay: today), today: today,
                                                    calendar: calendar),
                       "今天记下的")
        XCTAssertEqual(ReminderPopupText.todoDetail(TodoPopupInfo(today: false, addedDay: "2026-10-03"), today: today,
                                                    calendar: calendar),
                       "10 月 3 日记下的")
        XCTAssertEqual(ReminderPopupText.todoDetail(nil, today: today, calendar: calendar), "快速待办")
        XCTAssertEqual(ReminderPopupText.todoProgress(done: 1, total: 3), "今天 1 / 3")
    }

    func testTodoInfoListsTheOtherTodayItems() {
        let items = [TodoItem(id: "a", text: "写完季度复盘", today: true),
                     TodoItem(id: "b", text: "回复设计稿意见", done: true, today: true),
                     TodoItem(id: "c", text: "取快递")]
        let info = TodoPopupInfo.from(items[0], in: items)
        XCTAssertTrue(info.today)
        XCTAssertEqual(info.others, [TodoPopupInfo.Row(text: "回复设计稿意见", done: true)])
        XCTAssertEqual(info.todayDone, 1)
        XCTAssertEqual(info.todayTotal, 2)
        XCTAssertFalse(TodoPopupInfo.from(items[2], in: items).today)
    }

    // MARK: 窗口位置

    func testNotchCentresUnderTheNotch() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let frame = ReminderPopupLayout.windowFrame(screen: screen, visibleMaxY: 982 - 37, notch: 37,
                                                    shiduoRunning: false, island: nil, height: 200)
        XCTAssertEqual(frame.width, ReminderPopupLayout.windowWidth)
        XCTAssertEqual(frame.midX, screen.midX, accuracy: 0.001)
        XCTAssertEqual(frame.maxY, 982 - 37 - ReminderPopupLayout.notchGap, accuracy: 0.001)
        XCTAssertEqual(ReminderPopupLayout.origin(hasNotch: true, shiduoRunning: false), .notch)
    }

    func testExternalScreenSitsUnderTheMenuBar() {
        let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let frame = ReminderPopupLayout.windowFrame(screen: screen, visibleMaxY: 1415, notch: 0,
                                                    shiduoRunning: true, island: nil, height: 200)
        XCTAssertEqual(frame.midX, screen.midX, accuracy: 0.001)
        XCTAssertEqual(frame.maxY, 1415 - ReminderPopupLayout.menuBarGap, accuracy: 0.001)
        XCTAssertEqual(ReminderPopupLayout.origin(hasNotch: false, shiduoRunning: true), .menuBar)
    }

    func testShiduoMovesItOffTheNotch() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let frame = ReminderPopupLayout.windowFrame(screen: screen, visibleMaxY: 945, notch: 37,
                                                    shiduoRunning: true, island: nil, height: 200)
        XCTAssertEqual(ReminderPopupLayout.origin(hasNotch: true, shiduoRunning: true), .corner)
        XCTAssertEqual(frame.maxX - ReminderPopupLayout.shadowInset, screen.maxX - ReminderPopupLayout.edgeMargin,
                       accuracy: 0.001)
        XCTAssertEqual(frame.maxY, 945 - ReminderPopupLayout.menuBarGap, accuracy: 0.001)
        // 刘海那一段（屏幕正中约 200pt 宽）不压着。
        let notch = CGRect(x: screen.midX - 100, y: 945 - 300, width: 200, height: 337)
        XCTAssertFalse(frame.insetBy(dx: ReminderPopupLayout.shadowInset, dy: 0).intersects(notch))
    }

    func testIslandPushesTheCardBelowIt() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let island = CGRect(x: screen.midX - 220, y: 982 - 37 - 4 - 46, width: 440, height: 46)
        let frame = ReminderPopupLayout.windowFrame(screen: screen, visibleMaxY: 945, notch: 37,
                                                    shiduoRunning: false, island: island, height: 200)
        XCTAssertEqual(frame.maxY, island.minY - ReminderPopupLayout.islandGap, accuracy: 0.001)
    }

    // MARK: 待办的提醒时间

    func testTodoReminderRoundTripsAndOldDataHasNone() {
        let item = TodoItem(id: "a1", text: "写完季度复盘", today: true, addedDay: "2026-10-18",
                            remindAt: Date(timeIntervalSince1970: 1_800_000_000.7))
        var config = WidgetConfig()
        QuickTodo.store([item], in: &config)
        let back = QuickTodo.items(config)
        XCTAssertEqual(back.first?.remindAt, Date(timeIntervalSince1970: 1_800_000_000))
        XCTAssertEqual(back.first?.text, "写完季度复盘")
        XCTAssertTrue(back.first?.today == true)

        var old = WidgetConfig()
        old.set(QuickTodo.key, .list([.string("x1\t0\t取快递\ts=1")]))
        XCTAssertNil(QuickTodo.items(old).first?.remindAt)
        XCTAssertEqual(TodoItem(id: "x", text: "取快递").encoded, "x\t0\t取快递")

        var bad = WidgetConfig()
        bad.set(QuickTodo.key, .list([.string("x1\t0\t取快递\tr=abc")]))
        XCTAssertNil(QuickTodo.items(bad).first?.remindAt)
        XCTAssertEqual(QuickTodo.items(bad).first?.text, "取快递 r=abc")
    }

    func testSettingAndClearingAReminder() {
        let items = [TodoItem(id: "a", text: "甲"), TodoItem(id: "b", text: "乙")]
        let set = QuickTodo.settingReminder("b", at: at(18, 16, second: 30), in: items)
        XCTAssertEqual(set.first(where: { $0.id == "b" })?.remindAt, at(18, 16, second: 30))
        XCTAssertNil(set.first(where: { $0.id == "a" })?.remindAt)
        let cleared = QuickTodo.settingReminder("b", at: nil, in: set)
        XCTAssertNil(cleared.first(where: { $0.id == "b" })?.remindAt)
    }

    func testDueRemindersSkipDoneAndLongGaps() {
        let items = [TodoItem(id: "a", text: "甲", remindAt: at(18, 16)),
                     TodoItem(id: "b", text: "乙", done: true, remindAt: at(18, 16)),
                     TodoItem(id: "c", text: "丙", remindAt: at(18, 17))]
        XCTAssertEqual(QuickTodo.dueReminders(items, after: at(18, 15, 59, second: 59), upTo: at(18, 16)).map(\.id), ["a"])
        XCTAssertEqual(QuickTodo.dueReminders(items, after: at(18, 16), upTo: at(18, 16, second: 1)).map(\.id), [])
        XCTAssertEqual(QuickTodo.dueReminders(items, after: at(18, 10), upTo: at(18, 17)).map(\.id), [])
    }

    func testReminderLabel() {
        let now = at(18, 10)
        XCTAssertEqual(QuickTodo.reminderLabel(at(18, 16), now: now, calendar: calendar), "16:00")
        XCTAssertEqual(QuickTodo.reminderLabel(at(19, 9), now: now, calendar: calendar), "明天 09:00")
        XCTAssertEqual(QuickTodo.reminderLabel(at(21, 9, 30), now: now, calendar: calendar), "10/21 09:30")
    }

    func testQuickChoices() {
        let now = at(18, 15, 20, second: 9)
        XCTAssertEqual(TodoReminderChoice.inOneHour.date(now: now, calendar: calendar), at(18, 16, 20))
        XCTAssertEqual(TodoReminderChoice.tonight.date(now: now, calendar: calendar), at(18, 20))
        XCTAssertEqual(TodoReminderChoice.tomorrowMorning.date(now: now, calendar: calendar), at(19, 9))
        XCTAssertEqual(TodoReminderChoice.available(now: at(18, 21), calendar: calendar), [.inOneHour, .tomorrowMorning])
    }

    func testCarryOverMovesOrClearsTheReminder() {
        let now = at(18, 10)
        XCTAssertEqual(QuickTodo.carriedReminder(at(17, 16), now: now, calendar: calendar), at(18, 16))
        XCTAssertNil(QuickTodo.carriedReminder(at(17, 8), now: now, calendar: calendar))
        XCTAssertEqual(QuickTodo.carriedReminder(at(19, 9), now: now, calendar: calendar), at(19, 9))
        XCTAssertNil(QuickTodo.carriedReminder(nil, now: now, calendar: calendar))

        let today = TodoDay.key(now, calendar: calendar)
        let yesterday = TodoDay.key(at(17, 10), calendar: calendar)
        let items = [TodoItem(id: "a", text: "甲", addedDay: yesterday, remindAt: at(17, 16)),
                     TodoItem(id: "b", text: "乙", addedDay: yesterday, remindAt: at(17, 8)),
                     TodoItem(id: "c", text: "丙", addedDay: today, remindAt: at(17, 8))]
        let moved = QuickTodo.carryingOver(items, today: today, now: now, calendar: calendar)
        XCTAssertEqual(moved.first(where: { $0.id == "a" })?.remindAt, at(18, 16))
        XCTAssertNil(moved.first(where: { $0.id == "b" })?.remindAt)
        // 今天记下的不是“昨天没做完的”，不动。
        XCTAssertEqual(moved.first(where: { $0.id == "c" })?.remindAt, at(17, 8))
        XCTAssertTrue(moved.allSatisfy { $0.addedDay == today })
    }

    func testRolloverDropsFinishedItemsWithTheirReminders() {
        let items = [TodoItem(id: "a", text: "甲", done: true, doneDay: "2026-10-17", remindAt: at(17, 16)),
                     TodoItem(id: "b", text: "乙", addedDay: "2026-10-17", remindAt: at(17, 16))]
        let rolled = QuickTodo.rollingOver(items, today: "2026-10-18")
        XCTAssertEqual(rolled.map(\.id), ["b"])
        XCTAssertEqual(rolled.first?.remindAt, at(17, 16))
    }
}
