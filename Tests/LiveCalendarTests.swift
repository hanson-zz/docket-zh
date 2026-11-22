import XCTest

final class LiveCalendarTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }

    /// 2026-11-20（周五）这天的 h:m。
    private func at(_ h: Int, _ m: Int, _ s: Int = 0, day: Int = 20) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: h, minute: m, second: s))!
    }

    private func event(_ id: String, _ h: Int, _ m: Int, minutes: Int = 30, day: Int = 20,
                       allDay: Bool = false, declined: Bool = false) -> LiveCalendarEvent {
        let start = at(h, m, day: day)
        return LiveCalendarEvent(id: id, title: id, start: start, end: start.addingTimeInterval(Double(minutes) * 60),
                                 isAllDay: allDay, colorHex: "#5B8CFF", declined: declined)
    }

    func testTodaySkipsAllDayDeclinedAndOtherDays() {
        let events = [event("b", 14, 0), event("allday", 0, 0, allDay: true), event("no", 10, 0, declined: true),
                      event("tomorrow", 9, 0, day: 21), event("yesterday", 9, 0, day: 19), event("a", 9, 30)]
        let ids = LiveCalendar.today(events, now: at(8, 0), calendar: calendar).map(\.id)
        XCTAssertEqual(ids, ["a", "b"])
    }

    func testTargetIsNextUnstartedOrJustStarted() {
        let events = [event("a", 9, 0), event("b", 10, 0)]
        XCTAssertEqual(LiveCalendar.target(events, now: at(8, 0), calendar: calendar)?.id, "a")
        // 开始后停留一分钟「进行中」，再换下一场。
        XCTAssertEqual(LiveCalendar.target(events, now: at(9, 0, 30), calendar: calendar)?.id, "a")
        XCTAssertEqual(LiveCalendar.target(events, now: at(9, 1), calendar: calendar)?.id, "b")
        XCTAssertNil(LiveCalendar.target(events, now: at(10, 2), calendar: calendar))
        XCTAssertNil(LiveCalendar.target([], now: at(8, 0), calendar: calendar))
    }

    func testAgendaKeepsRunningEventsAndCapsAtFour() {
        let events = [event("a", 9, 0, minutes: 60), event("b", 10, 0), event("c", 11, 0), event("d", 12, 0),
                      event("e", 13, 0), event("past", 7, 0)]
        let ids = LiveCalendar.agenda(events, now: at(9, 30), calendar: calendar).map(\.id)
        XCTAssertEqual(ids, ["a", "b", "c", "d"])
        XCTAssertEqual(LiveCalendar.agendaLimit, 4)
    }

    func testLevelDrainsFromFullToEmptyOverTheLead() {
        let start = at(10, 0)
        let lead: TimeInterval = 30 * 60
        XCTAssertEqual(LiveCalendar.level(start: start, now: at(9, 0), lead: lead), 1)
        XCTAssertEqual(LiveCalendar.level(start: start, now: at(9, 30), lead: lead), 1)
        XCTAssertEqual(LiveCalendar.level(start: start, now: at(9, 45), lead: lead), 0.5, accuracy: 1e-9)
        XCTAssertEqual(LiveCalendar.level(start: start, now: at(10, 0), lead: lead), 0)
        XCTAssertEqual(LiveCalendar.level(start: start, now: at(10, 1), lead: lead), 0)
    }

    func testPhasesAndWarmth() {
        let start = at(10, 0)
        let lead: TimeInterval = 30 * 60
        XCTAssertEqual(LiveCalendar.phase(start: start, now: at(9, 0), lead: lead), .waiting)
        XCTAssertEqual(LiveCalendar.phase(start: start, now: at(9, 36), lead: lead), .counting)
        XCTAssertEqual(LiveCalendar.phase(start: start, now: at(9, 55), lead: lead), .warm)
        XCTAssertEqual(LiveCalendar.phase(start: start, now: at(9, 59, 30), lead: lead), .imminent)
        XCTAssertEqual(LiveCalendar.phase(start: start, now: at(10, 0), lead: lead), .inProgress)
        XCTAssertFalse(LiveCalendarPhase.counting.isWarm)
        XCTAssertFalse(LiveCalendarPhase.waiting.isWarm)
        XCTAssertTrue(LiveCalendarPhase.warm.isWarm)
        XCTAssertTrue(LiveCalendarPhase.imminent.isWarm)
        XCTAssertTrue(LiveCalendarPhase.inProgress.isWarm)
    }

    func testCountdownLabelsShortenWithoutShrinking() {
        let start = at(10, 0)
        let lead: TimeInterval = 30 * 60
        let counting = LiveCalendar.label(start: start, now: at(9, 36), lead: lead, calendar: calendar)
        XCTAssertEqual(counting, LiveCalendarLabel(full: "24 分", compact: "24分", minimal: "24"))
        // 24 分 1 秒向上取整成 25 分。
        XCTAssertEqual(LiveCalendar.label(start: start, now: at(9, 35, 59), lead: lead, calendar: calendar).minimal, "25")
        XCTAssertEqual(LiveCalendar.label(start: start, now: at(9, 55), lead: lead, calendar: calendar).full, "5 分")
        XCTAssertEqual(LiveCalendar.label(start: start, now: at(9, 59, 30), lead: lead, calendar: calendar).candidates,
                       ["即将开始", "即将"])
        XCTAssertEqual(LiveCalendar.label(start: start, now: at(10, 0, 10), lead: lead, calendar: calendar).candidates,
                       ["进行中", "现在"])
        XCTAssertEqual(LiveCalendar.label(start: at(14, 5), now: at(9, 0), lead: lead, calendar: calendar).candidates,
                       ["14:05"])
    }

    func testClockWeekdayAndDay() {
        XCTAssertEqual(LiveCalendar.clock(at(9, 5), calendar: calendar), "9:05")
        XCTAssertEqual(LiveCalendar.clock(at(14, 0), calendar: calendar), "14:00")
        XCTAssertEqual(LiveCalendar.weekday(at(9, 0), calendar: calendar, english: false), "周五")
        XCTAssertEqual(LiveCalendar.weekday(at(9, 0), calendar: calendar, english: true), "FRI")
        XCTAssertEqual(LiveCalendar.dayNumber(at(9, 0), calendar: calendar), "20")
    }

    func testFlipOnlyOnARealSwitchAndNeverInARow() {
        var flip = LiveCalendarFlip()
        let t = at(9, 0)
        XCTAssertFalse(flip.update(to: "a", at: t), "第一次出现不转")
        XCTAssertFalse(flip.update(to: "a", at: t.addingTimeInterval(1)), "同一场不转")
        XCTAssertTrue(flip.update(to: "b", at: t.addingTimeInterval(60)), "换到下一场转一圈")
        XCTAssertFalse(flip.update(to: "b", at: t.addingTimeInterval(61)))
        XCTAssertFalse(flip.update(to: "c", at: t.addingTimeInterval(62)), "十秒内又换，不再转")
        XCTAssertEqual(flip.shownID, "c")
        XCTAssertFalse(flip.update(to: nil, at: t.addingTimeInterval(120)), "没日程了不转")
        XCTAssertFalse(flip.update(to: "d", at: t.addingTimeInterval(180)), "从没日程到有日程不转")
        XCTAssertTrue(flip.update(to: "e", at: t.addingTimeInterval(240)))
    }

    func testNextTickFollowsMinutesPixelsAndPower() {
        let start = at(10, 0)
        let lead: TimeInterval = 30 * 60
        // 没有日程：一分钟看一次。
        XCTAssertEqual(LiveCalendar.nextTick(start: nil, now: at(9, 0), lead: lead, pixelHeight: 60, lowPower: false), 60)
        // 提前量里：1800 秒 / 60 像素 = 每 30 秒降 1 像素，比整分更早。
        XCTAssertEqual(LiveCalendar.nextTick(start: start, now: at(9, 40), lead: lead, pixelHeight: 60, lowPower: false),
                       30.05, accuracy: 1e-6)
        // 低电量：只跟分钟。
        XCTAssertEqual(LiveCalendar.nextTick(start: start, now: at(9, 40), lead: lead, pixelHeight: 60, lowPower: true),
                       60, accuracy: 1e-6)
        XCTAssertEqual(LiveCalendar.nextTick(start: start, now: at(9, 40, 20), lead: lead, pixelHeight: 60, lowPower: true),
                       40.05, accuracy: 1e-6)
        // 还没进提前量：在进入那一刻醒来。
        XCTAssertEqual(LiveCalendar.nextTick(start: start, now: at(9, 29, 50), lead: lead, pixelHeight: 60, lowPower: false),
                       10.05, accuracy: 1e-6)
        // 进行中：停留一分钟后换下一场。
        XCTAssertEqual(LiveCalendar.nextTick(start: start, now: at(10, 0, 20), lead: lead, pixelHeight: 60, lowPower: false),
                       40.05, accuracy: 1e-6)
        // 永远在 1 到 60 秒之间。
        XCTAssertEqual(LiveCalendar.nextTick(start: start, now: at(9, 59, 59), lead: lead,
                                             pixelHeight: 10_000, lowPower: false), 1)
    }

    func testLeadSettingFallsBackToDefault() {
        XCTAssertEqual(LiveCalendar.leadMinutes(stored: nil), 30)
        XCTAssertEqual(LiveCalendar.leadMinutes(stored: 15), 15)
        XCTAssertEqual(LiveCalendar.leadMinutes(stored: 7), 30)
        XCTAssertEqual(LiveCalendar.leadKey, "liveIcons.calendarLead")
        XCTAssertEqual(LiveCalendar.bundleID, "com.apple.iCal")
    }

    func testPillTextIsReadableInEveryAppearance() {
        for dark in [false, true] {
            for warm in [false, true] {
                let hex = LiveCalendar.pillHex(dark: dark, warm: warm)
                XCTAssertGreaterThanOrEqual(PaperInk.contrast(paper: hex, ink: "#FFFFFF"), PaperInk.minimumContrast,
                                            "胶囊白字对比度 dark=\(dark) warm=\(warm)")
            }
        }
    }
}
