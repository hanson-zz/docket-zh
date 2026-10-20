import XCTest

/// 倒计时的多个计时器和日期倒计时（`CountdownList`），闹钟的法定工作日重复。
final class TimerNextTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, _ s: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s))!
    }

    // MARK: 多个计时器

    func testLegacyConfigIsTheFirstTimer() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let config = WidgetConfig(["duration": .number(180), "deadline": .number(1_000_000 + 60),
                                   "name": .string("泡面")])
        let timers = CountdownList.timers(config)
        XCTAssertEqual(timers.count, 1, "旧卡片只有第一个计时器，不用改写")
        XCTAssertEqual(timers[0].id, CountdownList.mainID)
        XCTAssertEqual(timers[0].name, "泡面")
        XCTAssertEqual(CountdownList.phase(timers[0], now: now), CountdownRun.phase(config, now: now))
        XCTAssertTrue(CountdownList.dates(config, now: now, calendar: calendar).isEmpty)
        XCTAssertEqual(CountdownList.focus(config, now: now, calendar: calendar), .timer(timers[0]))
    }

    func testStoringTimersKeepsMainInOldKeys() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        var config = WidgetConfig(["duration": .number(300)])
        let tea = CountdownList.adding(name: "泡茶 | 绿茶", duration: 120, to: &config, now: now)
        XCTAssertNotNil(tea)
        XCTAssertEqual(CountdownList.extras(config).first?.name, "泡茶 | 绿茶", "名字里有竖线也不会读错")
        XCTAssertEqual(CountdownList.extras(config).first?.deadline, 2_000_000 + 120, "加了就马上开始")
        XCTAssertNil(config["deadline"], "第一个计时器没动")

        CountdownList.update(CountdownList.mainID, in: &config) {
            $0 = CountdownList.starting($0, duration: 600, now: now)
        }
        XCTAssertEqual(config.double("deadline"), 2_000_000 + 600, "第一个写回原来的键")
        XCTAssertEqual(config.double("duration"), 600)
        XCTAssertEqual(CountdownList.timers(config).count, 2)

        CountdownList.remove(CountdownList.mainID, in: &config)
        XCTAssertEqual(CountdownList.timers(config).count, 2, "第一个不能删，只回到没开始")
        XCTAssertEqual(CountdownRun.phase(config, now: now), .idle)

        CountdownList.remove(tea!.id, in: &config)
        XCTAssertTrue(CountdownList.extras(config).isEmpty)
        XCTAssertNil(config[CountdownList.timersKey])
    }

    func testTimerLimit() {
        let now = Date(timeIntervalSince1970: 0)
        var config = WidgetConfig()
        for index in 0..<20 {
            CountdownList.adding(name: "第\(index)", duration: 60, to: &config, now: now)
        }
        XCTAssertEqual(CountdownList.timers(config).count, CountdownList.maxTimers)
        XCTAssertFalse(CountdownList.canAddTimer(config))
        XCTAssertEqual(Set(CountdownList.extras(config).map(\.id)).count, CountdownList.maxTimers - 1)
    }

    func testTimerActions() {
        let now = Date(timeIntervalSince1970: 5_000)
        let base = CountdownTimer(id: "t1", duration: 300)
        let running = CountdownList.starting(base, duration: 300, now: now)
        XCTAssertEqual(CountdownList.phase(running, now: now.addingTimeInterval(100)),
                       .running(left: 200, fraction: 1 - 200.0 / 300))
        let paused = CountdownList.pausing(running, now: now.addingTimeInterval(100))
        XCTAssertEqual(paused.paused, 200)
        XCTAssertNil(paused.deadline)
        let resumed = CountdownList.resuming(paused, now: now.addingTimeInterval(1000))
        XCTAssertEqual(resumed.deadline, 5_000 + 1000 + 200)
        let more = CountdownList.adding(60, to: resumed, now: now.addingTimeInterval(1000))
        XCTAssertEqual(more.duration, 360)
        XCTAssertEqual(more.deadline, 5_000 + 1000 + 260)
        XCTAssertEqual(CountdownList.phase(CountdownList.stopping(more), now: now), .idle)
        XCTAssertEqual(CountdownList.adding(60, to: base, now: now), base, "没开始时加时间不动")
    }

    func testCardShowsTheNearestTimer() {
        let now = Date(timeIntervalSince1970: 10_000)
        var config = WidgetConfig(["duration": .number(600)])
        XCTAssertEqual(CountdownList.focus(config, now: now, calendar: calendar), .idle)

        let long = CountdownList.adding(name: "晾衣服", duration: 1800, to: &config, now: now)!
        XCTAssertEqual(CountdownList.focus(config, now: now, calendar: calendar), .timer(long),
                       "第一个没开始时显示在跑的那个")
        let short = CountdownList.adding(name: "泡面", duration: 180, to: &config, now: now)!
        XCTAssertEqual(CountdownList.focus(config, now: now, calendar: calendar), .timer(short), "最快到点的")
        XCTAssertEqual(CountdownList.activeCount(config, now: now), 2)

        let later = now.addingTimeInterval(200)
        guard case .timer(let ringing) = CountdownList.focus(config, now: later, calendar: calendar) else {
            return XCTFail("应该是计时器")
        }
        XCTAssertEqual(ringing.id, short.id, "在响的排最前")

        CountdownList.update(short.id, in: &config) { $0 = CountdownList.stopping($0) }
        CountdownList.update(long.id, in: &config) { $0 = CountdownList.pausing($0, now: later) }
        guard case .timer(let paused) = CountdownList.focus(config, now: later, calendar: calendar) else {
            return XCTFail("应该是暂停的计时器")
        }
        XCTAssertEqual(paused.id, long.id, "没有在跑的时显示暂停的")
    }

    func testCardFallsBackToNearestDate() {
        let now = date(2026, 10, 20, 9)
        var config = WidgetConfig()
        CountdownList.addingDate(name: "发布日", on: date(2026, 12, 1), yearly: false, to: &config, calendar: calendar)
        let birthday = CountdownList.addingDate(name: "生日", on: date(1990, 11, 3), yearly: true, to: &config,
                                                calendar: calendar)!
        CountdownList.addingDate(name: "上线", on: date(2026, 10, 1), yearly: false, to: &config, calendar: calendar)
        XCTAssertEqual(CountdownList.focus(config, now: now, calendar: calendar), .date(birthday, days: 14))

        CountdownList.adding(name: "泡面", duration: 180, to: &config, now: now)
        if case .date = CountdownList.focus(config, now: now, calendar: calendar) {
            XCTFail("有计时器在跑时先显示计时器")
        }
        let order = CountdownList.dates(config, now: now, calendar: calendar).map(\.name)
        XCTAssertEqual(order, ["生日", "发布日", "上线"], "近的在前，过了的排最后")
    }

    func testTimedAlertsFollowEachTimer() {
        let start = Date(timeIntervalSince1970: 50_000)
        var config = WidgetConfig(["duration": .number(600)])
        let tea = CountdownList.adding(name: "泡茶", duration: 60, to: &config, now: start)!
        XCTAssertEqual(TimedAlertWake.countdownNext(config, now: start), start.addingTimeInterval(60))

        let tick = start.addingTimeInterval(60)
        let extra = CountdownList.timer(tea.id, in: config)!
        XCTAssertEqual(TimedAlertScan.countdownRang(extra, after: tick.addingTimeInterval(-1), upTo: tick), tick)
        XCTAssertNil(TimedAlertScan.countdownRang(config, after: tick.addingTimeInterval(-1), upTo: tick),
                     "第一个计时器没在跑")
        XCTAssertTrue(TimedAlertScan.countdownStillRinging(config, timerID: tea.id, due: tick, now: tick))
        XCTAssertFalse(TimedAlertScan.countdownStillRinging(config, due: tick, now: tick))
        XCTAssertEqual(TimedAlertScan.countdownChime(extra, now: tick)?.key, "\(tea.id):\(Int(tick.timeIntervalSince1970))")

        TimedAlertScan.restartingCountdown(&config, duration: 60, now: tick, timerID: tea.id)
        XCTAssertEqual(CountdownList.timer(tea.id, in: config)?.deadline, tick.timeIntervalSince1970 + 60)
        XCTAssertNil(config["deadline"], "再来一次只动那一个")
        TimedAlertScan.stoppingCountdown(&config, timerID: tea.id)
        XCTAssertEqual(CountdownList.phase(CountdownList.timer(tea.id, in: config)!, now: tick), .idle)
    }

    // MARK: 日期倒计时

    func testDateCountdownDays() {
        let now = date(2026, 10, 20, 23, 30)
        let today = CountdownDate(id: "d1", name: "今天", day: "20261020")
        let yearly = CountdownDate(id: "d2", name: "生日", day: "19900115", yearly: true)
        let passedYearly = CountdownDate(id: "d3", name: "纪念日", day: "20201019", yearly: true)
        let past = CountdownDate(id: "d4", name: "上线", day: "20261017")
        XCTAssertEqual(CountdownList.daysLeft(today, now: now, calendar: calendar), 0)
        XCTAssertEqual(CountdownList.daysLeft(yearly, now: now, calendar: calendar), 87)
        XCTAssertEqual(CountdownList.daysLeft(passedYearly, now: now, calendar: calendar), 364, "今年过了算明年")
        XCTAssertEqual(CountdownList.daysLeft(past, now: now, calendar: calendar), -3)
        XCTAssertEqual(CountdownList.daysLeft(CountdownDate(id: "y", name: "", day: "20261020", yearly: true),
                                              now: now, calendar: calendar), 0, "每年重复的今天就是今天")
    }

    func testLeapDayInCommonYear() {
        let leap = CountdownDate(id: "d1", name: "生日", day: "20000229", yearly: true)
        let now = date(2027, 2, 1, 8)
        let next = CountdownList.nextDay(leap, now: now, calendar: calendar)
        XCTAssertEqual(next, date(2027, 2, 28), "平年算 2 月 28 日")
        XCTAssertEqual(CountdownList.nextDay(leap, now: date(2028, 2, 1), calendar: calendar), date(2028, 2, 29))
    }

    func testDateTextsAndStorage() {
        XCTAssertEqual(CountdownList.daysText(0), "就是今天")
        XCTAssertEqual(CountdownList.daysText(1), "明天")
        XCTAssertEqual(CountdownList.daysText(66), "还有 66 天")
        XCTAssertEqual(CountdownList.daysText(-3), "已过 3 天")
        XCTAssertEqual(CountdownList.daysShort(66), "66 天")
        XCTAssertEqual(CountdownList.dateText(CountdownDate(id: "a", name: "", day: "20261225", yearly: true)),
                       "每年 12月25日")
        XCTAssertEqual(CountdownList.dateText(CountdownDate(id: "a", name: "", day: "20270101")), "2027年1月1日")

        var config = WidgetConfig()
        CountdownList.addingDate(name: "生日", on: date(1990, 1, 15), yearly: true, to: &config, calendar: calendar)
        let stored = CountdownList.storedDates(config)
        XCTAssertEqual(stored, [CountdownDate(id: "d1", name: "生日", day: "19900115", yearly: true)])
        config.set(CountdownList.datesKey, .list([.string("bad"), .string("d9|2026130|1|x"),
                                                  .string("d1|20261231|0|跨年|夜")]))
        XCTAssertEqual(CountdownList.storedDates(config).map(\.name), ["跨年|夜"], "读不懂的行跳过")
        CountdownList.removeDate("d1", in: &config)
        XCTAssertNil(config[CountdownList.datesKey])
    }

    // MARK: 闹钟的法定工作日

    func testLegalWorkdayRepeatIsStoredAndOldCodesStay() {
        var config = WidgetConfig()
        AlarmBook.store([
            AlarmItem(id: "a1", minutes: 8 * 60, name: "上班", repeats: .legalWorkdays),
            AlarmItem(id: "a2", minutes: 9 * 60, name: "站会", repeats: .workdays),
        ], in: &config)
        XCTAssertEqual(config.strings(AlarmBook.repeatsKey), ["a1|legal", "a2|12345"])
        XCTAssertEqual(AlarmBook.items(config).map(\.repeats), [.legalWorkdays, .workdays], "旧的 12345 仍是普通工作日")
        XCTAssertEqual(AlarmRepeat(code: "12345"), .workdays)
        XCTAssertEqual(AlarmRepeat.legalWorkdays.days, [1, 2, 3, 4, 5])
        XCTAssertFalse(AlarmRepeat.legalWorkdays.isDaily)
        XCTAssertEqual(AlarmBook.repeatText(.legalWorkdays, now: Date(), calendar: calendar), "法定工作日")
    }

    func testLegalWorkdaysSkipHolidaysAndRingOnMakeupDays() {
        let bundled = HolidaySchedule.bundled
        func rings(_ y: Int, _ m: Int, _ d: Int) -> Bool {
            AlarmBook.rings(.legalWorkdays, on: date(y, m, d, 7), calendar: calendar, holidays: bundled)
        }
        XCTAssertFalse(rings(2026, 10, 1), "国庆节不响")
        XCTAssertFalse(rings(2026, 10, 5), "国庆假期里的周一不响")
        XCTAssertTrue(rings(2026, 10, 10), "调休上班的周六照响")
        XCTAssertTrue(rings(2026, 9, 20), "调休上班的周日照响")
        XCTAssertTrue(rings(2026, 10, 8), "普通周四响")
        XCTAssertFalse(rings(2026, 10, 11), "普通周日不响")
        XCTAssertFalse(rings(2026, 10, 18), "普通周日不响")
        XCTAssertTrue(rings(2026, 2, 14), "春节前调休的周六照响")
        XCTAssertFalse(rings(2026, 2, 16), "春节不响")
    }

    func testLegalWorkdaysFallBackToPlainWeekdaysWithoutSchedule() {
        let bundled = HolidaySchedule.bundled
        XCTAssertNil(bundled[2027])
        XCTAssertTrue(AlarmBook.rings(.legalWorkdays, on: date(2027, 1, 1, 7), calendar: calendar, holidays: bundled),
                      "没有那一年的安排时退回普通工作日")
        XCTAssertFalse(AlarmBook.rings(.legalWorkdays, on: date(2027, 1, 2, 7), calendar: calendar, holidays: bundled))

        var fetched = bundled
        fetched[2027] = [HolidayDay(name: "元旦", date: "2027-01-01", isOffDay: true)]
        XCTAssertFalse(AlarmBook.rings(.legalWorkdays, on: date(2027, 1, 1, 7), calendar: calendar, holidays: fetched),
                       "联网取到的年份照样认")
    }

    func testLegalWorkdayNextOccurrenceJumpsLongBreaks() {
        let alarm = AlarmItem(id: "a1", minutes: 8 * 60, name: "上班", repeats: .legalWorkdays)
        let bundled = HolidaySchedule.bundled
        XCTAssertEqual(AlarmBook.nextOccurrence(alarm, after: date(2026, 9, 30, 9), calendar: calendar,
                                                holidays: bundled),
                       date(2026, 10, 8, 8), "跨过国庆七天")
        XCTAssertEqual(AlarmBook.nextOccurrence(alarm, after: date(2026, 2, 13, 9), calendar: calendar,
                                                holidays: bundled),
                       date(2026, 2, 14, 8), "调休的周六")
        XCTAssertEqual(AlarmBook.nextOccurrence(alarm, after: date(2026, 2, 14, 9), calendar: calendar,
                                                holidays: bundled),
                       date(2026, 2, 24, 8), "跨过春节九天")
    }

    func testAlarmHolidaysCanBeUpdated() {
        let original = AlarmHolidays.current
        defer { AlarmHolidays.update(original) }
        var fetched = original
        fetched[2027] = [HolidayDay(name: "元旦", date: "2027-01-01", isOffDay: true)]
        AlarmHolidays.update(fetched)
        XCTAssertFalse(AlarmBook.rings(.legalWorkdays, on: date(2027, 1, 1, 7), calendar: calendar),
                       "默认查的是应用取到的安排")
    }
}
