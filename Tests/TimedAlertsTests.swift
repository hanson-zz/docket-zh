import Foundation
import XCTest

/// 到点提醒的后台调度：从所有布局里找出小组件、倒计时和闹钟刚到点和还在响、
/// 准时的判断、提醒事项读哪些列表，倒计时和闹钟的弹出卡片，以及日程悬停浮出卡片。
final class TimedAlertsTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }()

    private func at(_ hour: Int, _ minute: Int = 0, _ second: Int = 0, day: Int = 19) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute, second: second))!
    }

    // MARK: 布局里的小组件

    func testFindsWidgetsInsideGroups() {
        let loose = WidgetInstance(kind: .countdown, config: WidgetConfig())
        let nested = WidgetInstance(kind: .alarm, config: WidgetConfig())
        let items: [DockItem] = [
            .spacer(id: UUID(), size: .small),
            .widget(loose),
            .group(DockGroup(name: "计时", items: [.widget(nested)])),
        ]
        XCTAssertEqual(DockItemTree.widgets(in: items).map(\.id), [loose.id, nested.id])
        XCTAssertEqual(DockItemTree.widget(nested.id, in: items)?.kind, .alarm)
        XCTAssertNil(DockItemTree.widget(UUID(), in: items))
    }

    func testReplacingReachesIntoGroups() {
        let nested = WidgetInstance(kind: .countdown, config: WidgetConfig())
        let items: [DockItem] = [.group(DockGroup(name: "计时", items: [.widget(nested)]))]
        var changed = nested
        changed.config.set("duration", .number(60))
        let replaced = DockItemTree.replacing(changed, in: items)
        XCTAssertEqual(DockItemTree.widget(nested.id, in: replaced ?? [])?.config.double("duration"), 60)
        XCTAssertNil(DockItemTree.replacing(WidgetInstance(kind: .todo, config: WidgetConfig()), in: items),
                     "没找到时不改")
    }

    // MARK: 倒计时

    private func running(deadline: Date, duration: Double = 180) -> WidgetConfig {
        WidgetConfig(["duration": .number(duration), "deadline": .number(deadline.timeIntervalSince1970)])
    }

    func testCountdownRingsOnlyInTheSecondItEnds() {
        let config = running(deadline: at(15, 3))
        XCTAssertNil(TimedAlertScan.countdownRang(config, after: at(15, 2, 58), upTo: at(15, 2, 59)))
        XCTAssertEqual(TimedAlertScan.countdownRang(config, after: at(15, 2, 59), upTo: at(15, 3)), at(15, 3))
        XCTAssertNil(TimedAlertScan.countdownRang(config, after: at(15, 3), upTo: at(15, 3, 1)), "只在那一秒")
        XCTAssertNil(TimedAlertScan.countdownRang(config, after: at(14, 0), upTo: at(15, 3, 1)),
                     "合盖很久回来不补弹")
        let paused = WidgetConfig(["duration": .number(180), "paused": .number(30)])
        XCTAssertNil(TimedAlertScan.countdownRang(paused, after: at(15, 2, 59), upTo: at(15, 3)))
    }

    func testCountdownStillRingingFollowsTheTile() {
        var config = running(deadline: at(15, 3))
        XCTAssertTrue(TimedAlertScan.countdownStillRinging(config, due: at(15, 3), now: at(15, 3, 5)))
        XCTAssertFalse(TimedAlertScan.countdownStillRinging(config, due: at(15, 3), now: at(15, 2)), "还没到点")
        TimedAlertScan.stoppingCountdown(&config)
        XCTAssertFalse(TimedAlertScan.countdownStillRinging(config, due: at(15, 3), now: at(15, 3, 5)), "卡片上点了停")
        XCTAssertEqual(CountdownRun.phase(config, now: at(15, 3, 5)), .idle)
    }

    func testCountdownAgainRunsTheSameLength() {
        var config = running(deadline: at(15, 3), duration: 300)
        TimedAlertScan.restartingCountdown(&config, duration: 300, now: at(15, 3, 10))
        XCTAssertEqual(CountdownRun.phase(config, now: at(15, 3, 10)), .running(left: 300, fraction: 0))
        XCTAssertFalse(TimedAlertScan.countdownStillRinging(config, due: at(15, 3), now: at(15, 3, 10)))
        // 没带时长时按卡片上存的。
        var plain = running(deadline: at(15, 3), duration: 120)
        TimedAlertScan.restartingCountdown(&plain, duration: 0, now: at(15, 3, 10))
        XCTAssertEqual(plain.double("deadline"), at(15, 5, 10).timeIntervalSince1970)
    }

    func testCountdownChimesEveryFourSecondsForThirtySeconds() {
        let config = running(deadline: at(15, 3))
        XCTAssertNil(TimedAlertScan.countdownChime(config, now: at(15, 2, 59)))
        XCTAssertEqual(TimedAlertScan.countdownChime(config, now: at(15, 3))?.bucket, 0)
        XCTAssertEqual(TimedAlertScan.countdownChime(config, now: at(15, 3, 5))?.bucket, 1)
        XCTAssertNil(TimedAlertScan.countdownChime(config, now: at(15, 3, 31)))
        XCTAssertEqual(TimedAlertScan.countdownChime(config, now: at(15, 3))?.key,
                       TimedAlertScan.countdownChime(config, now: at(15, 3, 9))?.key, "同一次到点同一个键")
    }

    // MARK: 闹钟

    private func alarms() -> WidgetConfig {
        var config = WidgetConfig()
        AlarmBook.store([AlarmItem(id: "a1", minutes: 14 * 60 + 30, name: "回电话"),
                         AlarmItem(id: "a2", minutes: 18 * 60, name: "取快递", enabled: false)], in: &config)
        return config
    }

    func testAlarmRingsInTheSecondItStarts() {
        let config = alarms()
        XCTAssertNil(TimedAlertScan.alarmRang(config, after: at(14, 29, 58), upTo: at(14, 29, 59), calendar: calendar))
        let rang = TimedAlertScan.alarmRang(config, after: at(14, 29, 59), upTo: at(14, 30), calendar: calendar)
        XCTAssertEqual(rang?.item.id, "a1")
        XCTAssertEqual(rang?.since, at(14, 30))
        XCTAssertNil(TimedAlertScan.alarmRang(config, after: at(14, 30), upTo: at(14, 30, 1), calendar: calendar),
                     "只在开始的那一秒弹")
        XCTAssertNil(TimedAlertScan.alarmRang(config, after: at(17, 59, 59), upTo: at(18), calendar: calendar),
                     "关着的闹钟不响")
        XCTAssertNil(TimedAlertScan.alarmRang(config, after: at(12), upTo: at(14, 31), calendar: calendar),
                     "合盖很久回来不补弹")
    }

    func testAlarmSnoozeIsNineMinutesAndRingsAgain() {
        XCTAssertEqual(AlarmBook.snoozeMinutes, 9)
        XCTAssertEqual(ReminderPopupSnooze.alarmMinutes, 9)
        var config = alarms()
        AlarmBook.snooze("a1", in: &config, now: at(14, 30, 20), calendar: calendar)
        XCTAssertFalse(TimedAlertScan.alarmStillRinging(config, id: "a1", since: at(14, 30), now: at(14, 30, 21),
                                                        calendar: calendar), "稍后了，弹出的那张收起")
        let again = TimedAlertScan.alarmRang(config, after: at(14, 39, 19), upTo: at(14, 39, 20), calendar: calendar)
        XCTAssertEqual(again?.item.id, "a1")
        XCTAssertEqual(again?.since, at(14, 39, 20))
        XCTAssertTrue(TimedAlertScan.alarmIsSnoozed(config, id: "a1", since: at(14, 39, 20)))
        XCTAssertFalse(TimedAlertScan.alarmIsSnoozed(alarms(), id: "a1", since: at(14, 30)))
    }

    func testAlarmStillRingingUntilDismissed() {
        var config = alarms()
        XCTAssertTrue(TimedAlertScan.alarmStillRinging(config, id: "a1", since: at(14, 30), now: at(14, 31),
                                                       calendar: calendar))
        XCTAssertFalse(TimedAlertScan.alarmStillRinging(config, id: "a1", since: at(14, 30), now: at(14, 41),
                                                        calendar: calendar), "十分钟没人管就停")
        AlarmBook.dismiss("a1", in: &config, now: at(14, 31), calendar: calendar)
        XCTAssertFalse(TimedAlertScan.alarmStillRinging(config, id: "a1", since: at(14, 30), now: at(14, 31, 1),
                                                        calendar: calendar))
    }

    func testAlarmChimesForTwoMinutes() {
        let config = alarms()
        XCTAssertEqual(TimedAlertScan.alarmChime(config, now: at(14, 30), calendar: calendar)?.bucket, 0)
        XCTAssertEqual(TimedAlertScan.alarmChime(config, now: at(14, 31), calendar: calendar)?.bucket, 15)
        XCTAssertNil(TimedAlertScan.alarmChime(config, now: at(14, 32, 1), calendar: calendar), "两分钟后不出声")
        XCTAssertNil(TimedAlertScan.alarmChime(config, now: at(14, 29), calendar: calendar))
    }

    // MARK: 准时

    func testPrecisionOnlyNearADueTimeOrWhileRinging() {
        let now = at(10)
        XCTAssertTrue(TimedAlertWake.needsPrecision(next: now.addingTimeInterval(60), ringing: false, now: now))
        XCTAssertFalse(TimedAlertWake.needsPrecision(next: now.addingTimeInterval(600), ringing: false, now: now))
        XCTAssertFalse(TimedAlertWake.needsPrecision(next: nil, ringing: false, now: now))
        XCTAssertTrue(TimedAlertWake.needsPrecision(next: nil, ringing: true, now: now))
        XCTAssertEqual(TimedAlertWake.soonest([now.addingTimeInterval(-5), now.addingTimeInterval(30),
                                               now.addingTimeInterval(10)], after: now),
                       now.addingTimeInterval(10))
        XCTAssertEqual(TimedAlertWake.countdownNext(running(deadline: at(10, 3)), now: now), at(10, 3))
        XCTAssertNil(TimedAlertWake.countdownNext(running(deadline: at(9, 59)), now: now), "已经到点的不算下一个")
    }

    // MARK: 提醒事项读哪些列表

    func testReminderScopeFollowsEveryTile() {
        XCTAssertEqual(ReminderScanScope.lists(filters: ["工作", " 家庭 "]), ["工作", "家庭"])
        XCTAssertNil(ReminderScanScope.lists(filters: ["工作", ""]), "有一张没筛就是全部列表")
        XCTAssertEqual(ReminderScanScope.lists(filters: []), [])
    }

    // MARK: 弹出卡片

    func testPopupSettingsAddTimerSwitchesThatDefaultOn() throws {
        let legacy = try JSONDecoder().decode(ReminderPopupSettings.self,
                                              from: Data(#"{"reminders":true,"water":false,"todo":true}"#.utf8))
        XCTAssertTrue(legacy.countdown)
        XCTAssertTrue(legacy.alarm)
        XCTAssertFalse(legacy.water)
        var settings = ReminderPopupSettings()
        settings.setEnabled(false, for: .alarm)
        XCTAssertFalse(settings.enabled(.alarm))
        XCTAssertTrue(settings.enabled(.countdown))
        let decoded = try JSONDecoder().decode(ReminderPopupSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(decoded, settings)
    }

    func testTimerKindsKeepTheirOwnSound() {
        XCTAssertEqual(ReminderSoundKind.toneKinds, [.reminders, .water, .todo])
        XCTAssertTrue(ReminderSoundKind.countdown.isTimer)
        XCTAssertFalse(ReminderSoundKind.todo.isTimer)
        let settings = ReminderSoundSettings()
        XCTAssertNil(ReminderSoundDecision.tone(for: .alarm, settings: settings, master: WidgetSoundSettings()),
                     "计时类不响提醒音色，由计时器自己响")
        XCTAssertEqual(ReminderPopupSoundChip.timer(.alarm, sound: true), ReminderPopupSoundChip(label: "Sosumi", muted: false))
        XCTAssertEqual(ReminderPopupSoundChip.timer(.countdown, sound: false), ReminderPopupSoundChip(label: "Glass", muted: true))
    }

    func testTimerCardsStayAsLongAsTheyRing() {
        XCTAssertEqual(ReminderPopupDecision.autoHideSeconds(.alarm), 120)
        XCTAssertEqual(ReminderPopupDecision.autoHideSeconds(.countdown), 30)
        XCTAssertEqual(ReminderPopupDecision.autoHideSeconds(.water), 30)
        XCTAssertTrue(ReminderPopupDecision.escapeStops(.countdown))
        XCTAssertFalse(ReminderPopupDecision.escapeStops(.reminders))
    }

    func testTimerCardWords() {
        XCTAssertEqual(ReminderPopupText.countdownTitle(name: "泡面"), "泡面 时间到")
        XCTAssertEqual(ReminderPopupText.countdownTitle(name: " "), "时间到")
        XCTAssertEqual(ReminderPopupText.countdownDetail(due: at(15, 3), duration: 180, calendar: calendar),
                       "15:03 到点 · 共 3 分钟")
        XCTAssertEqual(ReminderPopupText.alarmDetail(due: at(14, 30), info: TimerPopupInfo(clock: "14:30"),
                                                     calendar: calendar), "14:30 · 闹钟")
        XCTAssertEqual(ReminderPopupText.alarmDetail(due: at(14, 39), info: TimerPopupInfo(clock: "14:30", snoozed: true),
                                                     calendar: calendar), "14:39 · 稍后再响 · 原定 14:30")
        XCTAssertEqual(ReminderPopupText.timerHint(.alarm, info: nil), "稍后：9 分钟后再响一次")
        XCTAssertEqual(ReminderPopupText.timerHint(.countdown, info: TimerPopupInfo(duration: 300)),
                       "再来一次：重新计 5 分钟")
        XCTAssertEqual(ReminderPopupText.header(.alarm, due: at(14, 30), now: at(14, 30, 10), calendar: calendar),
                       "闹钟 · 现在")
    }

    func testQueueListsEverythingStillUp() {
        var queue = ReminderPopupQueue()
        let first = ReminderAlert(kind: .countdown, itemID: "w1", title: "时间到", due: at(15))
        let second = ReminderAlert(kind: .alarm, itemID: "w2#a1", title: "回电话", due: at(15))
        _ = queue.post(first, now: at(15))
        _ = queue.post(second, now: at(15))
        XCTAssertEqual(queue.alerts.map(\.id), [first.id, second.id])
        queue.resolve(first.id)
        XCTAssertEqual(queue.alerts.map(\.id), [second.id])
    }

    // MARK: 日程悬停浮出卡片

    private let tencent = MeetingLink(url: URL(string: "https://meeting.tencent.com/dm/abc")!, provider: .tencent)

    func testPeekTimeLine() {
        let item = EventPeekItem(id: "1", title: "周会", start: at(14), end: at(15))
        XCTAssertEqual(EventPeekText.timeLine(item, now: at(13, 35), calendar: calendar), "14:00-15:00 · 还有 25 分钟")
        XCTAssertEqual(EventPeekText.timeLine(item, now: at(15, 30), calendar: calendar), "14:00-15:00 · 已结束")
        XCTAssertEqual(EventPeekText.timeLine(item, now: at(14, 30, day: 18), calendar: calendar), "14:00-15:00",
                       "不是今天的只写时间")
        let allDay = EventPeekItem(id: "2", title: "假期", start: at(0), end: at(0, day: 20), isAllDay: true)
        XCTAssertEqual(EventPeekText.timeLine(allDay, now: at(9), calendar: calendar), "全天")
    }

    func testPeekPlaceAndJoin() {
        let room = EventPeekItem(id: "1", title: "评审", start: at(14), end: at(15), location: "3 号会议室", link: tencent)
        XCTAssertEqual(EventPeekText.placeLine(room), "3 号会议室")
        let online = EventPeekItem(id: "2", title: "评审", start: at(14), end: at(15), link: tencent)
        XCTAssertEqual(EventPeekText.placeLine(online), "腾讯会议")
        XCTAssertEqual(EventPeekText.placeLine(EventPeekItem(id: "3", title: "x", start: at(14), end: at(15))), "")
        XCTAssertTrue(EventPeekText.showsJoin(online, now: at(14, 50)))
        XCTAssertFalse(EventPeekText.showsJoin(online, now: at(15, 1)), "开完了不给加入")
        XCTAssertFalse(EventPeekText.showsJoin(EventPeekItem(id: "4", title: "x", start: at(14), end: at(15)), now: at(14)))
    }

    func testPeekDayListsFiveThenCounts() {
        let entries = (0..<7).map { EventPeekItem(id: "\($0)", title: "会\($0)", start: at(9 + $0), end: at(10 + $0)) }
        let peek = EventPeek.day(heading: "周三 22日", subheading: "已排 7 小时", entries: entries)
        XCTAssertEqual(peek.items.count, 5)
        XCTAssertEqual(peek.more, 2)
        XCTAssertEqual(EventPeekText.moreLine(peek.more), "还有 2 个")
        let entry = WeekEntry(id: "w", title: "评审", start: at(14), end: at(15), calendar: "工作", colorHex: "#FF9F45",
                              location: "3 号会议室", link: tencent)
        XCTAssertEqual(entry.peekItem.location, "3 号会议室")
        XCTAssertEqual(entry.peekItem.link, tencent)
        XCTAssertEqual(entry.peekItem.colorHex, "#FF9F45")
    }

    func testPeekSitsOutsideTheShelfOverThePointedBlock() {
        let tile = CGRect(x: 100, y: 10, width: 300, height: 50)
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let size = CGSize(width: 260, height: 120)
        let bottom = EventPeekLayout.frame(edge: .bottom, tile: tile, focusX: 200, size: size, visible: visible)
        XCTAssertEqual(bottom.minY, tile.maxY + EventPeekLayout.gap, "底部扩展栏浮在卡片上面")
        XCTAssertEqual(bottom.midX, 200)
        let clamped = EventPeekLayout.frame(edge: .bottom, tile: tile, focusX: 100, size: size, visible: visible)
        XCTAssertEqual(clamped.minX, 4, "靠屏幕边时收回来")
        let top = EventPeekLayout.frame(edge: .top, tile: CGRect(x: 600, y: 800, width: 300, height: 50),
                                        focusX: nil, size: size, visible: visible)
        XCTAssertEqual(top.maxY, 800 - EventPeekLayout.gap, "顶部扩展栏浮在下面")
        XCTAssertEqual(top.midX, 750)
        XCTAssertEqual(EventPeekLayout.anchor(edge: .left, tile: tile, focusX: 999), CGPoint(x: 400, y: 35))
        XCTAssertEqual(EventPeekLayout.anchor(edge: .bottom, tile: tile, focusX: 999).x, 400, "指向不出卡片")
    }
}
