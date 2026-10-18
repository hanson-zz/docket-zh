import XCTest

/// 数剩余时间和计时类的分工：倒计时的预设和到点、多个闹钟、秒表计次、
/// 时间进度四格、专注计时轮次，以及久坐提醒给专注让位。
final class TimersSplitTests: XCTestCase {

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

    func testCountdownPresetsDefaultAndFillUp() {
        XCTAssertEqual(CountdownRun.presets(WidgetConfig()), [3, 5, 10])
        let mine = WidgetConfig(["presets": .list([.string("8"), .string("8 分钟"), .string("0"), .string("abc")])])
        XCTAssertEqual(CountdownRun.presets(mine), [8, 3, 5], "去重、丢掉无效的，再用默认补齐三个")
        let many = WidgetConfig(["presets": .list(["1", "2", "15", "30"].map { .string($0) })])
        XCTAssertEqual(CountdownRun.presets(many), [1, 2, 15])
        XCTAssertEqual(CountdownRun.settingPreset(1, to: 999, in: WidgetConfig()), [3, 240, 10])
        XCTAssertEqual(CountdownRun.settingPreset(0, to: 0, in: WidgetConfig()), [1, 5, 10])
    }

    func testCountdownHighlightsTheLastLength() {
        XCTAssertEqual(CountdownRun.lastPresetIndex(WidgetConfig(["duration": .number(300)])), 1)
        XCTAssertNil(CountdownRun.lastPresetIndex(WidgetConfig(["duration": .number(420)])))
    }

    func testCountdownPhases() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(CountdownRun.phase(WidgetConfig(["duration": .number(180)]), now: now), .idle)
        let running = WidgetConfig(["duration": .number(180), "deadline": .number(1_000_000 + 90)])
        XCTAssertEqual(CountdownRun.phase(running, now: now), .running(left: 90, fraction: 0.5))
        let paused = WidgetConfig(["duration": .number(180), "paused": .number(90)])
        XCTAssertEqual(CountdownRun.phase(paused, now: now), .paused(left: 90, fraction: 0.5))
        let rang = WidgetConfig(["duration": .number(180), "deadline": .number(1_000_000 - 5)])
        XCTAssertEqual(CountdownRun.phase(rang, now: now), .ringing(since: 5))
    }

    func testCountdownShakesThenRestsAndRespectsReduceMotion() {
        XCTAssertTrue(CountdownRun.shakes(.ringing(since: 10), reduceMotion: false))
        XCTAssertFalse(CountdownRun.shakes(.ringing(since: 10), reduceMotion: true))
        XCTAssertFalse(CountdownRun.shakes(.ringing(since: 61), reduceMotion: false))
        XCTAssertFalse(CountdownRun.shakes(.running(left: 5, fraction: 0.9), reduceMotion: false))
        XCTAssertEqual(CountdownRun.chimeBucket(since: 0), 0)
        XCTAssertEqual(CountdownRun.chimeBucket(since: 5.5), 1)
        XCTAssertNil(CountdownRun.chimeBucket(since: 31))
        XCTAssertNil(CountdownRun.chimeBucket(since: -1))
    }

    func testCountdownCaptions() {
        XCTAssertEqual(CountdownRun.runningCaption(name: "泡面", duration: 180), "泡面 · 共 3 分钟")
        XCTAssertEqual(CountdownRun.runningCaption(name: "", duration: 5400), "共 1 小时 30 分")
        XCTAssertEqual(CountdownRun.lengthText(3600), "1 小时")
    }

    // MARK: 闹钟

    func testLegacySingleAlarmBecomesAList() {
        let old = WidgetConfig(["time": .string("07:15"), "name": .string("起床"), "enabled": .bool(false)])
        XCTAssertTrue(AlarmBook.isLegacy(old))
        XCTAssertEqual(AlarmBook.items(old), [AlarmItem(id: "a", minutes: 7 * 60 + 15, name: "起床", enabled: false)])

        var migrated = old
        AlarmBook.store(AlarmBook.items(old), in: &migrated)
        XCTAssertFalse(AlarmBook.isLegacy(migrated))
        XCTAssertNil(migrated["time"])
        XCTAssertEqual(AlarmBook.items(migrated), AlarmBook.items(old))
        // 列表清空后仍是新格式，不会退回旧键。
        var emptied = migrated
        AlarmBook.store([], in: &emptied)
        XCTAssertEqual(AlarmBook.items(emptied), [])
    }

    func testNamesWithBarsSurvive() {
        var config = WidgetConfig()
        AlarmBook.store([AlarmItem(id: "x", minutes: 60, name: "A|B")], in: &config)
        XCTAssertEqual(AlarmBook.items(config).first?.name, "A|B")
    }

    private func threeAlarms() -> WidgetConfig {
        var config = WidgetConfig()
        AlarmBook.store([
            AlarmItem(id: "a3", minutes: 21 * 60 + 30, name: "吃药"),
            AlarmItem(id: "a1", minutes: 14 * 60 + 30, name: "给小王回电话"),
            AlarmItem(id: "a2", minutes: 18 * 60, name: "取快递"),
            AlarmItem(id: "a4", minutes: 8 * 60, name: "早会", enabled: false),
        ], in: &config)
        return config
    }

    func testNextAlarmIsTheHeadlineAndTheRestFollow() {
        let config = threeAlarms()
        let now = date(2026, 10, 18, 12, 30)
        XCTAssertEqual(AlarmBook.headline(config, now: now, calendar: calendar)?.id, "a1")
        XCTAssertEqual(AlarmBook.untilText(date(2026, 10, 18, 14, 30), now: now), "还有 2 小时")
        XCTAssertEqual(AlarmBook.laterLine(config, now: now, calendar: calendar), "接着 18:00 取快递 · 21:30 吃药")
        // 今天的都过了，下一个是明天最早的开着的那个。
        let late = date(2026, 10, 18, 22)
        XCTAssertEqual(AlarmBook.headline(config, now: late, calendar: calendar)?.id, "a1")
        XCTAssertEqual(AlarmBook.nextRing(AlarmBook.items(config)[1], config: config, now: late, calendar: calendar),
                       date(2026, 10, 19, 14, 30))
    }

    func testAllOffShowsTheNearestOne() {
        var config = WidgetConfig()
        AlarmBook.store([AlarmItem(id: "b", minutes: 600, name: "", enabled: false),
                         AlarmItem(id: "c", minutes: 900, name: "", enabled: false)], in: &config)
        XCTAssertEqual(AlarmBook.headline(config, now: date(2026, 10, 18, 12), calendar: calendar)?.id, "c")
        XCTAssertNil(AlarmBook.laterLine(config, now: date(2026, 10, 18, 12), calendar: calendar))
    }

    func testRingingSnoozeAndDismiss() {
        var config = threeAlarms()
        let ringTime = date(2026, 10, 18, 14, 30)
        XCTAssertNil(AlarmBook.ringing(config, now: date(2026, 10, 18, 14, 29), calendar: calendar))
        XCTAssertEqual(AlarmBook.ringing(config, now: date(2026, 10, 18, 14, 31), calendar: calendar)?.item.id, "a1")
        XCTAssertNil(AlarmBook.ringing(config, now: date(2026, 10, 18, 14, 41), calendar: calendar), "十分钟没人管就停")

        // 稍后 10 分钟：现在不响，10 分钟后再响。
        let snoozedAt = date(2026, 10, 18, 14, 31)
        AlarmBook.snooze("a1", in: &config, now: snoozedAt, calendar: calendar)
        XCTAssertNil(AlarmBook.ringing(config, now: date(2026, 10, 18, 14, 35), calendar: calendar))
        let again = AlarmBook.ringing(config, now: date(2026, 10, 18, 14, 41, 30), calendar: calendar)
        XCTAssertEqual(again?.item.id, "a1")
        XCTAssertEqual(again?.since, snoozedAt.addingTimeInterval(600))
        // 稍后再响的时刻排进下一个。
        let first = AlarmBook.items(config).first { $0.id == "a1" }!
        XCTAssertEqual(AlarmBook.nextRing(first, config: config,
                                          now: date(2026, 10, 18, 14, 35), calendar: calendar),
                       snoozedAt.addingTimeInterval(600))

        // 关掉：今天不再响，明天照常。
        AlarmBook.dismiss("a1", in: &config, now: date(2026, 10, 18, 14, 42), calendar: calendar)
        XCTAssertNil(AlarmBook.ringing(config, now: date(2026, 10, 18, 14, 43), calendar: calendar))
        XCTAssertEqual(AlarmBook.ringing(config, now: date(2026, 10, 19, 14, 30, 5), calendar: calendar)?.item.id, "a1")
        _ = ringTime
    }

    func testTurningAnAlarmOffSilencesIt() {
        var config = threeAlarms()
        AlarmBook.setEnabled("a1", false, in: &config)
        XCTAssertNil(AlarmBook.ringing(config, now: date(2026, 10, 18, 14, 31), calendar: calendar))
        XCTAssertEqual(AlarmBook.headline(config, now: date(2026, 10, 18, 12), calendar: calendar)?.id, "a2")
        XCTAssertEqual(AlarmBook.newID(existing: AlarmBook.items(config)), "a5")
    }

    func testAlarmUntilText() {
        let now = date(2026, 10, 18, 12)
        XCTAssertEqual(AlarmBook.untilText(date(2026, 10, 18, 13, 20), now: now), "还有 1 小时 20 分")
        XCTAssertEqual(AlarmBook.untilText(date(2026, 10, 18, 12, 35), now: now), "还有 35 分钟")
        XCTAssertEqual(AlarmBook.untilText(now, now: now), "不到 1 分钟")
        XCTAssertEqual(AlarmBook.clockText(date(2026, 10, 18, 9, 5), calendar: calendar), "09:05")
    }

    // MARK: 秒表

    func testLapsAndTheFastestOne() {
        var laps: [TimeInterval] = []
        laps = StopwatchLaps.addingLap(to: laps, elapsed: 24.33)
        XCTAssertNil(StopwatchLaps.fastestIndex(laps), "只有一圈不标最快")
        laps = StopwatchLaps.addingLap(to: laps, elapsed: 55.35)
        laps = StopwatchLaps.addingLap(to: laps, elapsed: 83.45)
        XCTAssertEqual(laps.count, 3)
        XCTAssertEqual(laps[1], 31.02, accuracy: 0.001)
        XCTAssertEqual(laps[2], 28.10, accuracy: 0.001)
        XCTAssertEqual(StopwatchLaps.fastestIndex(laps), 0)
        let recent = StopwatchLaps.recent(laps)
        XCTAssertEqual(recent.map(\.number), [3, 2, 1])
        XCTAssertEqual(recent.map(\.fastest), [false, false, true])

        var config = WidgetConfig()
        StopwatchLaps.store(laps, in: &config)
        XCTAssertEqual(StopwatchLaps.laps(config).count, 3)
        XCTAssertEqual(StopwatchLaps.laps(config)[0], 24.33, accuracy: 0.001)
    }

    func testStopwatchFormats() {
        XCTAssertEqual(StopwatchLaps.main(83.456), "01:23")
        XCTAssertEqual(StopwatchLaps.hundredths(83.456), ".45")
        XCTAssertEqual(StopwatchLaps.main(3683), "1:01:23")
        XCTAssertEqual(StopwatchLaps.lapText(28.1), "0:28.10")
        XCTAssertEqual(StopwatchLaps.caption(running: false, elapsed: 83, lapCount: 3), "已暂停 · 3 次计次")
        XCTAssertEqual(StopwatchLaps.caption(running: false, elapsed: 0, lapCount: 0), "就绪")
    }

    func testStopwatchElapsedBanksRuns() {
        let config = WidgetConfig(["started": .number(1000), "elapsed": .number(20)])
        XCTAssertEqual(StopwatchLaps.elapsed(config, now: Date(timeIntervalSince1970: 1030)), 50)
        XCTAssertTrue(StopwatchLaps.isRunning(config))
    }

    // MARK: 时间进度四格

    func testQuadShowsFourPeriodsLongestFirst() {
        let rows = TimeProgress.quadRows(now: date(2026, 10, 18, 18, 40), calendar: calendar)
        XCTAssertEqual(rows.map(\.period), [.year, .month, .week, .day])
        XCTAssertEqual(rows.map(\.title), ["年", "月", "周", "今天"])
        XCTAssertEqual(rows[3].percent, 77, "18:40 是一天的 77.8%，向下取整")
        // 10 月 18 日是周日，一周快过完。
        XCTAssertGreaterThan(rows[2].percent, 90)
        XCTAssertTrue(rows.allSatisfy { (0...100).contains($0.percent) })
    }

    func testQuadIsAVariantAndHasNoPeriodChoice() {
        let entry = WidgetCatalog.entry(.progress)
        XCTAssertTrue(entry?.variants.contains { $0.overrides["layout"] == .string(TimeProgress.quadLayout) } ?? false)
        let quad = WidgetConfig(["layout": .string(TimeProgress.quadLayout)])
        XCTAssertFalse(WidgetCatalog.applies(TimeProgress.periodKey, to: quad, kind: .progress))
        XCTAssertTrue(WidgetCatalog.applies(TimeProgress.periodKey, to: WidgetConfig(["layout": .string("ring")]),
                                            kind: .progress))
    }

    func testNewWidthsAndScaleNotes() {
        XCTAssertEqual(WidgetCatalog.make(.countdown).map { WidgetCatalog.naturalSize($0).width }, 168)
        XCTAssertEqual(WidgetCatalog.make(.alarm).map { WidgetCatalog.naturalSize($0).width }, 220)
        XCTAssertEqual(WidgetLibraryGroups.note(.countdown), "几分钟内")
        XCTAssertEqual(WidgetLibraryGroups.note(.alarm), "今天某个时刻")
        XCTAssertEqual(WidgetLibraryGroups.note(.anniversary), "按天")
        XCTAssertEqual(WidgetLibraryGroups.note(.progress), "年月周日百分比")
        // 旧的单个闹钟才在设置里给“时间”“名称”。
        XCTAssertTrue(WidgetCatalog.applies("time", to: WidgetConfig(), kind: .alarm))
        XCTAssertFalse(WidgetCatalog.applies("time", to: threeAlarms(), kind: .alarm))
        XCTAssertFalse(WidgetCatalog.applies(CountdownRun.presetsKey, to: WidgetConfig(), kind: .countdown))
    }

    // MARK: 专注计时

    private func focusing(completed: Int = 0, deadline: Date) -> TimerState {
        var state = TimerState()
        state.phase = .focus
        state.completed = completed
        state.duration = 25 * 60
        state.deadline = deadline
        return state
    }

    func testFocusEndsIntoARestThatRunsFromTheDeadline() {
        let end = date(2026, 10, 18, 10)
        XCTAssertNil(FocusCycle.advanced(focusing(deadline: end), now: end.addingTimeInterval(-1)))
        let rest = FocusCycle.advanced(focusing(deadline: end), now: end.addingTimeInterval(2))
        XCTAssertEqual(rest?.phase, .rest)
        XCTAssertEqual(rest?.completed, 1)
        XCTAssertEqual(rest?.deadline, end.addingTimeInterval(5 * 60))
        XCTAssertEqual(rest.map(FocusCycle.round), 1)
        XCTAssertEqual(rest.map(FocusCycle.showsStandUp), true)
        XCTAssertEqual(rest.map(FocusCycle.caption), "休息 · 站起来走走")
    }

    func testFourthRoundEndsIntoALongBreakThenStartsOver() {
        let end = date(2026, 10, 18, 10)
        let long = FocusCycle.advanced(focusing(completed: 3, deadline: end), now: end)
        XCTAssertEqual(long?.phase, .long)
        XCTAssertEqual(long.map(FocusCycle.litDots), 4)
        let back = long.flatMap { FocusCycle.advanced($0, now: end.addingTimeInterval(15 * 60 + 1)) }
        XCTAssertEqual(back?.phase, .focus)
        XCTAssertEqual(back?.completed, 0)
        XCTAssertNil(back?.deadline, "休息完停在开始前")
        XCTAssertEqual(back?.stoodUp, end.addingTimeInterval(15 * 60))
        XCTAssertEqual(back.map(FocusCycle.round), 1)
    }

    func testRoundDotsAndCaption() {
        var state = TimerState()
        state.completed = 1
        XCTAssertEqual(FocusCycle.round(state), 2)
        XCTAssertEqual(FocusCycle.litDots(state), 2)
        XCTAssertEqual(FocusCycle.dotCount(state), 4)
        XCTAssertEqual(FocusCycle.caption(state), "专注 · 第 2 轮")
        state.sessions = 12
        XCTAssertEqual(FocusCycle.dotCount(state), 8)
        state.standUp = false
        state.phase = .rest
        XCTAssertFalse(FocusCycle.showsStandUp(state))
    }

    func testPausedOrStaleTimersDoNotChain() {
        let end = date(2026, 10, 18, 10)
        var paused = focusing(deadline: end)
        paused.paused = 60
        XCTAssertNil(FocusCycle.advanced(paused, now: end.addingTimeInterval(10)))
        let stale = FocusCycle.advanced(focusing(completed: 2, deadline: end), now: end.addingTimeInterval(13 * 3600))
        XCTAssertEqual(stale?.phase, .focus)
        XCTAssertEqual(stale?.completed, 0)
        XCTAssertNil(stale?.deadline)
    }

    func testTimerStateDecodesWithoutTheNewKeys() throws {
        let data = Data(#"{"work":30,"phase":"focus"}"#.utf8)
        let state = try JSONDecoder().decode(TimerState.self, from: data)
        XCTAssertTrue(state.standUp)
        XCTAssertNil(state.stoodUp)
        XCTAssertEqual(state.work, 30)
    }

    // MARK: 久坐和专注不抢

    func testPostureYieldsWhileFocusRuns() {
        let now = date(2026, 10, 18, 10)
        var timer = focusing(deadline: now.addingTimeInterval(600))
        XCTAssertTrue(SitFocus.postureYields(to: timer, now: now))
        timer.standUp = false
        XCTAssertFalse(SitFocus.postureYields(to: timer, now: now), "关了休息时提醒起身，久坐照常提醒")
        timer.standUp = true
        timer.paused = 300
        XCTAssertFalse(SitFocus.postureYields(to: timer, now: now), "暂停时不算开着")
        XCTAssertFalse(SitFocus.postureYields(to: TimerState(), now: now))
    }

    func testFocusBreakCountsAsStandingUp() {
        var timer = TimerState()
        let own = date(2026, 10, 18, 9)
        let focusBreak = date(2026, 10, 18, 9, 30)
        timer.stoodUp = focusBreak
        XCTAssertEqual(SitFocus.lastBreak(posture: own, timer: timer), focusBreak)
        XCTAssertEqual(SitFocus.lastBreak(posture: nil, timer: timer), focusBreak)
        XCTAssertEqual(SitFocus.lastBreak(posture: date(2026, 10, 18, 10), timer: timer), date(2026, 10, 18, 10))
        timer.standUp = false
        XCTAssertEqual(SitFocus.lastBreak(posture: own, timer: timer), own)
    }

    func testSixCellsAndSittingText() {
        XCTAssertEqual(SitFocus.litCells(sat: 48 * 60, interval: 3600), 4)
        XCTAssertEqual(SitFocus.litCells(sat: 50 * 60, interval: 3600), 5)
        XCTAssertEqual(SitFocus.litCells(sat: 2 * 3600, interval: 3600), 6)
        XCTAssertEqual(SitFocus.litCells(sat: 0, interval: 3600), 0)
        XCTAssertEqual(SitFocus.satText(48 * 60), "已坐 48 分钟")
        XCTAssertEqual(SitFocus.satText(65 * 60), "已坐 1 小时 5 分")
        XCTAssertEqual(SitFocus.dueText(3600), "60 分钟时叫你")
        XCTAssertEqual(SitFocus.dueText(2 * 3600), "2 小时时叫你")
        let schedule = PostureSchedule(interval: 3600, start: 9 * 60, end: 18 * 60)
        XCTAssertEqual(SitFocus.sat(schedule, lastBreak: date(2026, 10, 18, 10), now: date(2026, 10, 18, 10, 48),
                                    calendar: calendar), 48 * 60)
    }
}
