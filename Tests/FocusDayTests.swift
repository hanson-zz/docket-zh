import XCTest

/// 专注计时面板：今天的番茄段、时间轴范围和刻度、任务名和最近的任务名、
/// 开始专注时的环境音、设置里的加减，以及历史统计是 Pro。
final class FocusDayTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func date(_ h: Int, _ m: Int = 0, day: Int = 20) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: m))!
    }

    // MARK: 记录

    func testAddingRecordsASegmentWithItsTask() {
        let lines = FocusDay.adding(seconds: 1500, endedAt: date(9, 25), task: "写说明", to: [], calendar: calendar)
        let segments = FocusDay.segments(lines)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].start, date(9))
        XCTAssertEqual(segments[0].end, date(9, 25))
        XCTAssertEqual(segments[0].task, "写说明")
    }

    func testTheSameEndIsNotRecordedTwice() {
        var lines = FocusDay.adding(seconds: 1500, endedAt: date(9, 25), task: "", to: [], calendar: calendar)
        lines = FocusDay.adding(seconds: 1500, endedAt: date(9, 25), task: "", to: lines, calendar: calendar)
        XCTAssertEqual(FocusDay.segments(lines).count, 1)
    }

    func testTooShortSessionsAreNotRecorded() {
        XCTAssertTrue(FocusDay.adding(seconds: 10, endedAt: date(9), task: "", to: [], calendar: calendar).isEmpty)
        XCTAssertTrue(FocusDay.adding(seconds: .nan, endedAt: date(9), task: "", to: [], calendar: calendar).isEmpty)
    }

    func testTaskWithABarSurvives() {
        let lines = FocusDay.adding(seconds: 1500, endedAt: date(9, 25), task: "A|B", to: [], calendar: calendar)
        XCTAssertEqual(FocusDay.segments(lines).first?.task, "A|B")
    }

    func testMalformedLinesAreSkipped() {
        let segments = FocusDay.segments(["", "abc", "10|5|x", "1|2", "1|nan|x"])
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].task, "")
    }

    func testOldDaysArePruned() {
        let old = FocusDay.line(FocusDay.Segment(start: date(9, day: 1), end: date(10, day: 1)))
        let lines = FocusDay.adding(seconds: 1500, endedAt: date(9, 25), task: "", to: [old], calendar: calendar)
        XCTAssertEqual(FocusDay.segments(lines).count, 1)
    }

    func testTodayOnlyKeepsTodayAndClipsAtMidnight() {
        let yesterday = FocusDay.line(FocusDay.Segment(start: date(9, day: 19), end: date(10, day: 19)))
        let overnight = FocusDay.line(FocusDay.Segment(start: date(23, 50, day: 19), end: date(0, 15)))
        let today = FocusDay.today([yesterday, overnight], now: date(10), calendar: calendar)
        XCTAssertEqual(today.count, 1)
        XCTAssertEqual(today[0].start, date(0))
    }

    func testEmptyLogHasNoSegments() {
        XCTAssertTrue(FocusDay.today([], now: date(10), calendar: calendar).isEmpty)
    }

    // MARK: 正在进行

    func testLiveSegmentWhileRunning() {
        var state = TimerState()
        state.duration = 1500
        state.deadline = date(10, 15)
        let live = FocusDay.live(state, now: date(10))
        XCTAssertEqual(live?.start, date(9, 50))
        XCTAssertEqual(live?.live, true)
    }

    func testLiveSegmentWhilePausedCountsOnlyFocusedTime() {
        var state = TimerState()
        state.duration = 1500
        state.paused = 600
        let live = FocusDay.live(state, now: date(10))
        XCTAssertEqual(live?.duration, 900)
    }

    func testNoLiveSegmentWhenIdleOrResting() {
        XCTAssertNil(FocusDay.live(TimerState(), now: date(10)))
        var rest = TimerState()
        rest.phase = .rest
        rest.deadline = date(10, 5)
        XCTAssertNil(FocusDay.live(rest, now: date(10)))
    }

    // MARK: 时间轴

    func testWindowDefaultsToEightToTwenty() {
        XCTAssertEqual(FocusDay.window([], now: date(10), calendar: calendar), 8...20)
        XCTAssertEqual(FocusDay.ticks(8...20), [8, 10, 12, 14, 16, 18, 20])
    }

    func testWindowGrowsForEarlyAndLateFocus() {
        let early = FocusDay.Segment(start: date(6, 40), end: date(7, 5))
        XCTAssertEqual(FocusDay.window([early], now: date(10), calendar: calendar), 6...20)
        XCTAssertEqual(FocusDay.window([], now: date(22, 30), calendar: calendar), 8...24)
        XCTAssertEqual(FocusDay.window([], now: date(0, 30), calendar: calendar), 0...20)
    }

    func testLongWindowTicksEveryFourHours() {
        XCTAssertEqual(FocusDay.ticks(0...24), [0, 4, 8, 12, 16, 20, 24])
        XCTAssertEqual(FocusDay.ticks(6...24), [6, 10, 14, 18, 22, 24])
    }

    func testFractionIsClamped() {
        XCTAssertEqual(FocusDay.fraction(date(14), window: 8...20, calendar: calendar), 0.5, accuracy: 0.0001)
        XCTAssertEqual(FocusDay.fraction(date(5), window: 8...20, calendar: calendar), 0)
        XCTAssertEqual(FocusDay.fraction(date(23), window: 8...20, calendar: calendar), 1)
    }

    // MARK: 文案

    func testFooterAndFocusedText() {
        XCTAssertEqual(FocusDay.footer(done: 4, live: true), "4 个番茄 · 第 5 个进行中")
        XCTAssertEqual(FocusDay.footer(done: 4, live: false), "4 个番茄")
        XCTAssertEqual(FocusDay.footer(done: 0, live: false), "今天还没有完成的番茄")
        XCTAssertEqual(FocusDay.focusedText(minutes: 100), "已专注 1 小时 40 分")
        XCTAssertEqual(FocusDay.focusedText(minutes: 60), "已专注 1 小时")
        XCTAssertEqual(FocusDay.focusedText(minutes: 25), "已专注 25 分钟")
        XCTAssertEqual(FocusDay.focusedText(minutes: 0), "还没开始专注")
    }

    func testStatusLine() {
        var state = TimerState()
        XCTAssertEqual(FocusDay.status(state, now: date(10)), "准备专注 · 第 1 / 4 轮")
        state.completed = 1
        state.deadline = date(10, 20)
        XCTAssertEqual(FocusDay.status(state, now: date(10)), "专注中 · 第 2 / 4 轮")
        state.deadline = nil
        state.paused = 300
        XCTAssertEqual(FocusDay.status(state, now: date(10)), "已暂停 · 第 2 / 4 轮")
    }

    // MARK: 任务名

    func testCleanTaskTrimsAndCaps() {
        XCTAssertEqual(FocusDay.cleanTask("  回邮件\n "), "回邮件")
        XCTAssertEqual(FocusDay.cleanTask(String(repeating: "字", count: 60)).count, FocusDay.maxTaskLength)
    }

    func testRememberingMovesToFrontDedupesAndCaps() {
        var recent: [String] = []
        for task in ["a", "b", "c", "d", "e", "f", "g"] { recent = FocusDay.remembering(task, in: recent) }
        XCTAssertEqual(recent, ["g", "f", "e", "d", "c", "b"])
        recent = FocusDay.remembering("d", in: recent)
        XCTAssertEqual(recent, ["d", "g", "f", "e", "c", "b"])
        XCTAssertEqual(FocusDay.remembering("  ", in: ["x"]), ["x"])
        XCTAssertEqual(FocusDay.forgetting("x", in: ["x"]), [])
    }

    // MARK: 设置

    func testSteppedAlignsToTheStepAndClamps() {
        XCTAssertEqual(FocusDay.stepped(25, up: true, step: 5, range: 1...180), 30)
        XCTAssertEqual(FocusDay.stepped(27, up: true, step: 5, range: 1...180), 30)
        XCTAssertEqual(FocusDay.stepped(27, up: false, step: 5, range: 1...180), 25)
        XCTAssertEqual(FocusDay.stepped(5, up: false, step: 5, range: 1...180), 4)
        XCTAssertEqual(FocusDay.stepped(1, up: false, step: 5, range: 1...180), 1)
        XCTAssertEqual(FocusDay.stepped(3, up: true, step: 5, range: 1...180), 4)
        XCTAssertEqual(FocusDay.stepped(180, up: true, step: 5, range: 1...180), 180)
        XCTAssertEqual(FocusDay.stepped(12, up: true, step: 1, range: 1...12), 12)
    }

    // MARK: 环境音

    func testAmbientPlaysOnlyWhileFocusRuns() {
        var state = TimerState()
        state.ambient = AmbientSound.rain.rawValue
        XCTAssertNil(FocusAmbient.wanted(state, now: date(10)), "没开始不放")
        state.deadline = date(10, 25)
        XCTAssertEqual(FocusAmbient.wanted(state, now: date(10)), .rain)
        state.paused = 600
        XCTAssertNil(FocusAmbient.wanted(state, now: date(10)), "暂停不放")
    }

    func testAmbientStopsOnBreakUnlessAskedToKeepPlaying() {
        var state = TimerState()
        state.ambient = AmbientSound.waves.rawValue
        state.phase = .rest
        state.deadline = date(10, 5)
        XCTAssertNil(FocusAmbient.wanted(state, now: date(10)))
        state.quietOnBreak = false
        XCTAssertEqual(FocusAmbient.wanted(state, now: date(10)), .waves)
    }

    func testNoSoundChosenPlaysNothing() {
        var state = TimerState()
        state.deadline = date(10, 25)
        XCTAssertNil(FocusAmbient.wanted(state, now: date(10)))
        state.ambient = "bogus"
        XCTAssertNil(FocusAmbient.wanted(state, now: date(10)))
    }

    func testNextSoundCycles() {
        XCTAssertEqual(FocusAmbient.next(after: ""), .rain)
        XCTAssertEqual(FocusAmbient.next(after: "rain"), .waves)
        XCTAssertEqual(FocusAmbient.next(after: AmbientSound.allCases.last!.rawValue), .rain)
        XCTAssertEqual(FocusAmbient.clampVolume(140), 100)
        XCTAssertEqual(FocusAmbient.clampVolume(-3), 0)
    }

    // MARK: 存档

    func testNewFieldsSurviveARoundTripAndOldFilesGetDefaults() throws {
        var state = TimerState()
        state.task = "读论文"
        state.recentTasks = ["读论文", "回邮件"]
        state.ambient = "fire"
        state.ambientVolume = 30
        state.quietOnBreak = false
        let data = try JSONEncoder().encode(state)
        let back = try JSONDecoder().decode(TimerState.self, from: data)
        XCTAssertEqual(back, state)

        let old = try JSONDecoder().decode(TimerState.self, from: Data(#"{"work":30}"#.utf8))
        XCTAssertEqual(old.work, 30)
        XCTAssertEqual(old.task, "")
        XCTAssertEqual(old.recentTasks, [])
        XCTAssertEqual(old.ambient, "")
        XCTAssertEqual(old.ambientVolume, 55)
        XCTAssertTrue(old.quietOnBreak)
    }

    // MARK: Pro

    func testFocusHistoryIsPro() {
        XCTAssertFalse(ProLicenseGate.canSeeFocusHistory(unlocked: false))
        XCTAssertTrue(ProLicenseGate.canSeeFocusHistory(unlocked: true))
    }
}
