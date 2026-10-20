import XCTest

/// 倒计时、秒表、闹钟三个展开面板背后的逻辑：快速开始和加时间、计次表、
/// 闹钟的重复日和一次性闹钟。
final class TimerPanelsTests: XCTestCase {

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

    // MARK: 倒计时

    func testCountdownQuickMinutesKeepCardPresets() {
        XCTAssertEqual(CountdownRun.quickMinutes(WidgetConfig()), [1, 3, 5, 10, 15, 25, 30, 60])
        let mine = WidgetConfig(["presets": .list(["7", "40", "90"].map { .string($0) })])
        let quick = CountdownRun.quickMinutes(mine)
        XCTAssertEqual(quick.count, CountdownRun.quickCount)
        XCTAssertTrue([7, 40, 90].allSatisfy(quick.contains), "卡片上的三个预设一定在快速开始里")
        XCTAssertEqual(quick, quick.sorted())
    }

    func testCountdownCustomStepping() {
        XCTAssertEqual(CountdownRun.stepping(1, up: false), 1)
        XCTAssertEqual(CountdownRun.stepping(9, up: true), 10)
        XCTAssertEqual(CountdownRun.stepping(10, up: true), 15)
        XCTAssertEqual(CountdownRun.stepping(15, up: false), 10)
        XCTAssertEqual(CountdownRun.stepping(12, up: false), 10, "不在档位上的先落到下面一档")
        XCTAssertEqual(CountdownRun.stepping(12, up: true), 15)
        XCTAssertEqual(CountdownRun.stepping(60, up: true), 75)
        XCTAssertEqual(CountdownRun.stepping(240, up: true), 240)
    }

    func testCountdownAddingTime() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var idle = WidgetConfig(["duration": .number(300)])
        CountdownRun.adding(60, to: &idle, now: now)
        XCTAssertEqual(CountdownRun.phase(idle, now: now), .idle, "没开始时不动")

        var running = WidgetConfig(["duration": .number(300), "deadline": .number(1_000_000 + 100)])
        CountdownRun.adding(60, to: &running, now: now)
        XCTAssertEqual(running.double("deadline"), 1_000_000 + 160)
        XCTAssertEqual(CountdownRun.duration(running), 360)

        var paused = WidgetConfig(["duration": .number(300), "paused": .number(40)])
        CountdownRun.adding(60, to: &paused, now: now)
        XCTAssertEqual(CountdownRun.phase(paused, now: now), .paused(left: 100, fraction: 1 - 100.0 / 360))

        var ringing = WidgetConfig(["duration": .number(300), "deadline": .number(1_000_000 - 5)])
        CountdownRun.adding(60, to: &ringing, now: now)
        XCTAssertEqual(CountdownRun.phase(ringing, now: now), .running(left: 60, fraction: 0), "到点后从现在起再计")
    }

    func testCountdownTexts() {
        XCTAssertEqual(CountdownRun.remainingText(167), "02:47")
        XCTAssertEqual(CountdownRun.remainingText(166.2), "02:47", "往上取整")
        XCTAssertEqual(CountdownRun.remainingText(3725), "1:02:05")
        XCTAssertNil(CountdownRun.stateText(.idle))
        XCTAssertEqual(CountdownRun.stateText(.ringing(since: 3)), "时间到")
    }

    // MARK: 秒表

    func testStopwatchRowsMarkFastestAndSlowest() {
        let laps: [TimeInterval] = [38.40, 36.95, 44.60, 35.70, 41.22]
        let rows = StopwatchLaps.rows(laps)
        XCTAssertEqual(rows.map(\.number), [5, 4, 3, 2, 1], "新的在上")
        XCTAssertEqual(rows.first { $0.fastest }?.number, 4)
        XCTAssertEqual(rows.first { $0.slowest }?.number, 3)
        XCTAssertNil(rows.last?.delta, "第一圈没有比上圈")
        XCTAssertEqual(rows[0].delta!, 41.22 - 35.70, accuracy: 1e-9)
        XCTAssertEqual(rows[0].total, laps.reduce(0, +), accuracy: 1e-9)
        XCTAssertNil(StopwatchLaps.slowestIndex([10]))
        XCTAssertNil(StopwatchLaps.slowestIndex([10, 10]), "一样快时不标最慢")
    }

    func testStopwatchDeltaAndReport() {
        XCTAssertEqual(StopwatchLaps.deltaText(5.52), "+5.52")
        XCTAssertEqual(StopwatchLaps.deltaText(-1.45), "-1.45")
        XCTAssertEqual(StopwatchLaps.deltaText(0), "+0.00")
        XCTAssertEqual(StopwatchLaps.deltaText(-0.001), "+0.00")
        XCTAssertEqual(StopwatchLaps.deltaText(75.5), "+1:15.50")
        XCTAssertEqual(StopwatchLaps.currentLap([10, 20], elapsed: 35), 5)

        let report = StopwatchLaps.report([38.40, 36.95], elapsed: 80)
        XCTAssertEqual(report.split(separator: "\n").map(String.init), [
            "第 1 圈  0:38.40  累计 0:38.40  最慢",
            "第 2 圈  0:36.95  -1.45  累计 1:15.35  最快",
            "总计 1:20.00",
        ])
    }

    // MARK: 闹钟

    func testAlarmRepeatsAreStoredBesideTheList() {
        var config = WidgetConfig()
        AlarmBook.store([
            AlarmItem(id: "a1", minutes: 7 * 60 + 30, name: "起床", repeats: .workdays),
            AlarmItem(id: "a2", minutes: 12 * 60 + 30, name: "午休|结束"),
            AlarmItem(id: "a3", minutes: 18 * 60, name: "取快递", repeats: .once("20261020")),
        ], in: &config)
        XCTAssertEqual(config.strings(AlarmBook.repeatsKey), ["a1|12345", "a3|once:20261020"])
        let items = AlarmBook.items(config)
        XCTAssertEqual(items.map(\.repeats), [.workdays, .daily, .once("20261020")])
        XCTAssertEqual(items[1].name, "午休|结束")

        // 全是每天的闹钟时不写这个键；旧配置没有它，照样每天。
        AlarmBook.store([AlarmItem(id: "a2", minutes: 600, name: "")], in: &config)
        XCTAssertNil(config[AlarmBook.repeatsKey])
        let legacy = WidgetConfig(["time": .string("07:15"), "name": .string("起床")])
        XCTAssertEqual(AlarmBook.items(legacy).first?.repeats, .daily)
        XCTAssertEqual(AlarmRepeat(code: "x"), .daily)
        XCTAssertEqual(AlarmRepeat(code: "once:bad"), .daily)
        XCTAssertEqual(AlarmItem(id: "z", minutes: 0, name: "", repeats: .weekdays([])).repeats, .daily)
    }

    func testWorkdayAlarmSkipsTheWeekend() {
        // 2026-10-23 是周五，10-24 周六。
        var config = WidgetConfig()
        AlarmBook.store([AlarmItem(id: "w", minutes: 7 * 60 + 30, name: "起床", repeats: .workdays)], in: &config)
        let item = AlarmBook.items(config)[0]
        let fridayNight = date(2026, 10, 23, 22)
        XCTAssertEqual(AlarmBook.nextOccurrence(item, after: fridayNight, calendar: calendar), date(2026, 10, 26, 7, 30))
        XCTAssertEqual(AlarmBook.isoWeekday(date(2026, 10, 25), calendar: calendar), 7)
        XCTAssertNil(AlarmBook.ringing(config, now: date(2026, 10, 24, 7, 31), calendar: calendar), "周六不响")
        XCTAssertEqual(AlarmBook.ringing(config, now: date(2026, 10, 23, 7, 31), calendar: calendar)?.item.id, "w")
        XCTAssertEqual(AlarmBook.upcoming(config, now: fridayNight, calendar: calendar).first?.at, date(2026, 10, 26, 7, 30))
    }

    func testOnceAlarmRingsOnceThenStops() {
        let now = date(2026, 10, 20, 10, 23, 40)
        let quick = AlarmBook.quickOnce(after: 15, now: now, calendar: calendar)
        XCTAssertEqual(quick.minutes, 10 * 60 + 39, "往上取整到分钟")
        XCTAssertEqual(quick.repeats, .once("20261020"))
        XCTAssertEqual(AlarmBook.quickOnce(after: 60, now: date(2026, 10, 20, 23, 30), calendar: calendar).repeats,
                       .once("20261021"), "过了午夜是明天")

        var config = WidgetConfig()
        AlarmBook.store([AlarmItem(id: "q", minutes: quick.minutes, name: "", repeats: quick.repeats)], in: &config)
        let item = AlarmBook.items(config)[0]
        XCTAssertTrue(AlarmBook.isLive(item, config: config, now: now, calendar: calendar))
        XCTAssertEqual(AlarmBook.upcoming(config, now: now, calendar: calendar).count, 1)
        XCTAssertEqual(AlarmBook.ringing(config, now: date(2026, 10, 20, 10, 40), calendar: calendar)?.item.id, "q")

        // 第二天不再响，也不在接下来要响的里。
        let tomorrow = date(2026, 10, 21, 10, 40)
        XCTAssertNil(AlarmBook.ringing(config, now: tomorrow, calendar: calendar))
        XCTAssertTrue(AlarmBook.upcoming(config, now: tomorrow, calendar: calendar).isEmpty)
        XCTAssertFalse(AlarmBook.isLive(item, config: config, now: tomorrow, calendar: calendar))
        XCTAssertEqual(AlarmBook.repeatText(item.repeats, minutes: item.minutes, now: tomorrow, calendar: calendar), "已响过")

        // 关掉这次响铃顺手关掉开关；再打开时改到下一次这个时刻。
        var dismissed = config
        AlarmBook.dismiss("q", in: &dismissed, now: date(2026, 10, 20, 10, 41), calendar: calendar)
        XCTAssertFalse(AlarmBook.items(dismissed)[0].enabled)
        AlarmBook.setEnabled("q", true, in: &dismissed, now: date(2026, 10, 20, 11, 0), calendar: calendar)
        XCTAssertEqual(AlarmBook.items(dismissed)[0].repeats, .once("20261021"))
        XCTAssertTrue(AlarmBook.isLive(AlarmBook.items(dismissed)[0], config: dismissed,
                                       now: date(2026, 10, 20, 11, 0), calendar: calendar))
    }

    func testOnceAlarmSnoozeStillRings() {
        var config = WidgetConfig()
        AlarmBook.store([AlarmItem(id: "q", minutes: 10 * 60, name: "", repeats: .once("20261020"))], in: &config)
        AlarmBook.snooze("q", in: &config, now: date(2026, 10, 20, 10, 1), calendar: calendar)
        let item = AlarmBook.items(config)[0]
        let later = date(2026, 10, 20, 10, 5)
        XCTAssertEqual(AlarmBook.nextRing(item, config: config, now: later, calendar: calendar), date(2026, 10, 20, 10, 10))
        XCTAssertTrue(AlarmBook.isLive(item, config: config, now: later, calendar: calendar))
    }

    func testAlarmTodayMarksAndTexts() {
        let now = date(2026, 10, 20, 10, 23)   // 周二
        var config = WidgetConfig()
        AlarmBook.store([
            AlarmItem(id: "a1", minutes: 7 * 60 + 30, name: "起床", repeats: .workdays),
            AlarmItem(id: "a2", minutes: 12 * 60 + 30, name: "午休结束"),
            AlarmItem(id: "a3", minutes: 9 * 60, name: "周末跑步", repeats: .weekend),
            AlarmItem(id: "a4", minutes: 22 * 60 + 30, name: "早点睡", enabled: false),
        ], in: &config)
        XCTAssertEqual(AlarmBook.today(config, now: now, calendar: calendar).map(\.item.id), ["a1", "a2"])

        XCTAssertEqual(AlarmBook.repeatText(.daily, now: now, calendar: calendar), "每天")
        XCTAssertEqual(AlarmBook.repeatText(.workdays, now: now, calendar: calendar), "工作日")
        XCTAssertEqual(AlarmBook.repeatText(.weekend, now: now, calendar: calendar), "周末")
        XCTAssertEqual(AlarmBook.repeatText(.weekdays([5, 1, 3]), now: now, calendar: calendar), "周一、周三、周五")
        XCTAssertEqual(AlarmBook.repeatText(.once("20261020"), minutes: 18 * 60, now: now, calendar: calendar), "仅今天")
        XCTAssertEqual(AlarmBook.repeatText(.once("20261021"), minutes: 8 * 60, now: now, calendar: calendar), "仅明天")
        XCTAssertEqual(AlarmBook.repeatText(.once("20261025"), minutes: 8 * 60, now: now, calendar: calendar), "仅 10月25日")

        XCTAssertEqual(AlarmBook.ringsInText(date(2026, 10, 20, 12, 30), now: now), "2 小时 7 分钟后响")
        XCTAssertEqual(AlarmBook.ringsInText(date(2026, 10, 20, 11, 23), now: now), "1 小时后响")
        XCTAssertEqual(AlarmBook.ringsInText(date(2026, 10, 20, 10, 58), now: now), "35 分钟后响")
    }
}
