import XCTest

/// 久坐提醒的离开检测：空闲秒数和锁屏、休眠这些事件怎么变成「离开」「回来」，
/// 离开满门槛怎么算一次自动休息、计时怎么清零，以及时间轴怎么画自动记的那段。
final class PostureAwayTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0, _ s: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s))!
    }

    private let schedule = PostureSchedule(interval: 1800, start: 9 * 60, end: 18 * 60)

    // MARK: 设置

    func testOnByDefaultWithFiveMinutes() {
        let config = WidgetConfig()
        XCTAssertTrue(PostureAway.isEnabled(config))
        XCTAssertEqual(PostureAway.minutes(config), 5)
        XCTAssertEqual(PostureAway.threshold(config), 300)
        XCTAssertEqual(PostureAway.minutes(WidgetConfig(["awayAfter": .string("2")])), 2)
        XCTAssertEqual(PostureAway.minutes(WidgetConfig(["awayAfter": .string("10")])), 10)
        XCTAssertEqual(PostureAway.minutes(WidgetConfig(["awayAfter": .string("7")])), 5, "不在 2、5、10 里退回 5")
        XCTAssertFalse(PostureAway.isEnabled(WidgetConfig(["away": .bool(false)])))
    }

    func testTheCatalogOffersTheSwitchAndThreshold() {
        let defaults = WidgetCatalog.entry(.posture)?.defaults.values
        XCTAssertEqual(defaults?["away"], .bool(true))
        XCTAssertEqual(defaults?["awayAfter"], .string("5"))
        XCTAssertEqual(PostureAway.minuteChoices, [2, 5, 10])
        // 阈值只在开关开着时列出。
        XCTAssertTrue(WidgetCatalog.applies("awayAfter", to: WidgetConfig(), kind: .posture))
        XCTAssertFalse(WidgetCatalog.applies("awayAfter", to: WidgetConfig(["away": .bool(false)]), kind: .posture))
    }

    // MARK: 空闲秒数

    func testIdleUnderTheThresholdIsNotAway() {
        var tracker = PostureAway.Tracker(idleAfter: 300)
        let now = date(2026, 10, 20, 10)
        XCTAssertNil(tracker.handle(.idle(30), at: now))
        XCTAssertNil(tracker.handle(.idle(299), at: now.addingTimeInterval(269)))
        XCTAssertFalse(tracker.isAway)
    }

    func testIdlePastTheThresholdLeavesFromTheLastInputAndInputComesBack() {
        var tracker = PostureAway.Tracker(idleAfter: 300)
        let lastInput = date(2026, 10, 20, 10)
        // 采样序列：10 秒一次，最后一次输入在 10:00。
        var changes: [PostureAway.Change] = []
        for seconds in stride(from: 0, through: 600, by: 10) {
            if let change = tracker.handle(.idle(TimeInterval(seconds)), at: lastInput.addingTimeInterval(TimeInterval(seconds))) {
                changes.append(change)
            }
        }
        XCTAssertEqual(changes, [.left(since: lastInput)], "满 5 分钟算离开，离开从最后一次输入算")
        XCTAssertTrue(tracker.isAway)
        // 10:12 采样时空闲 3 秒：10:11:57 动了鼠标，算回来。
        let back = tracker.handle(.idle(3), at: date(2026, 10, 20, 10, 12))
        XCTAssertEqual(back, .back(since: lastInput, at: date(2026, 10, 20, 10, 11, 57)))
        XCTAssertFalse(tracker.isAway)
    }

    func testSamplingJitterIsNotInput() {
        var tracker = PostureAway.Tracker(idleAfter: 120)
        let lastInput = date(2026, 10, 20, 10)
        _ = tracker.handle(.idle(120), at: lastInput.addingTimeInterval(120))
        // 读数差一秒半：最后一次输入还是 10:00 附近，不算回来。
        XCTAssertNil(tracker.handle(.idle(128.5), at: lastInput.addingTimeInterval(130)))
        XCTAssertTrue(tracker.isAway)
    }

    // MARK: 锁屏、休眠

    func testLockLeavesAtOnceAndUnlockComesBack() {
        var tracker = PostureAway.Tracker(idleAfter: 300)
        let lock = date(2026, 10, 20, 11)
        XCTAssertEqual(tracker.handle(.blocked(.locked), at: lock), .left(since: lock))
        // 锁屏期间空闲读数不作数。
        XCTAssertNil(tracker.handle(.idle(0), at: lock.addingTimeInterval(60)))
        XCTAssertTrue(tracker.isAway)
        let unlock = date(2026, 10, 20, 11, 20)
        XCTAssertEqual(tracker.handle(.unblocked(.locked), at: unlock), .back(since: lock, at: unlock))
    }

    func testEveryReasonHasToClearBeforeComingBack() {
        var tracker = PostureAway.Tracker(idleAfter: 300)
        let start = date(2026, 10, 20, 12)
        XCTAssertEqual(tracker.handle(.blocked(.displayOff), at: start), .left(since: start))
        XCTAssertNil(tracker.handle(.blocked(.locked), at: start.addingTimeInterval(5)))
        XCTAssertNil(tracker.handle(.blocked(.asleep), at: start.addingTimeInterval(10)))
        XCTAssertNil(tracker.handle(.unblocked(.asleep), at: start.addingTimeInterval(3600)))
        XCTAssertNil(tracker.handle(.unblocked(.displayOff), at: start.addingTimeInterval(3601)))
        XCTAssertTrue(tracker.isAway, "还锁着")
        XCTAssertEqual(tracker.handle(.unblocked(.locked), at: start.addingTimeInterval(3630)),
                       .back(since: start, at: start.addingTimeInterval(3630)))
    }

    func testIdleAwayThenLockKeepsTheEarlierStart() {
        var tracker = PostureAway.Tracker(idleAfter: 120)
        let lastInput = date(2026, 10, 20, 15)
        _ = tracker.handle(.idle(150), at: lastInput.addingTimeInterval(150))
        XCTAssertNil(tracker.handle(.blocked(.screensaver), at: lastInput.addingTimeInterval(300)))
        XCTAssertEqual(tracker.handle(.unblocked(.screensaver), at: lastInput.addingTimeInterval(900)),
                       .back(since: lastInput, at: lastInput.addingTimeInterval(900)))
    }

    // MARK: 每张卡片该做什么

    func testReachingTheThresholdRestsOnceAndReturningResets() {
        let config = WidgetConfig()
        let since = date(2026, 10, 20, 10)
        // 离开 4 分钟：还不算。
        XCTAssertEqual(PostureAway.steps(config, schedule: schedule, since: since,
                                         now: since.addingTimeInterval(240), back: nil, rested: false,
                                         calendar: calendar), [])
        // 满 5 分钟：算一次，记进今天。
        XCTAssertEqual(PostureAway.steps(config, schedule: schedule, since: since,
                                         now: since.addingTimeInterval(300), back: nil, rested: false,
                                         calendar: calendar),
                       [.rest(since: since, logged: true)])
        // 已经算过，离开中不再算。
        XCTAssertEqual(PostureAway.steps(config, schedule: schedule, since: since,
                                         now: since.addingTimeInterval(900), back: nil, rested: true,
                                         calendar: calendar), [])
        // 回来：从回来那一刻重新计时。
        let back = since.addingTimeInterval(1200)
        XCTAssertEqual(PostureAway.steps(config, schedule: schedule, since: since, now: back,
                                         back: back, rested: true, calendar: calendar),
                       [.resume(at: back)])
    }

    func testAShortAbsenceChangesNothing() {
        let since = date(2026, 10, 20, 10)
        let back = since.addingTimeInterval(170)
        XCTAssertEqual(PostureAway.steps(WidgetConfig(["awayAfter": .string("5")]), schedule: schedule,
                                         since: since, now: back, back: back, rested: false,
                                         calendar: calendar), [])
        // 同样 170 秒，门槛 2 分钟就算一次（比如合盖睡眠，醒来才看得到）。
        XCTAssertEqual(PostureAway.steps(WidgetConfig(["awayAfter": .string("2")]), schedule: schedule,
                                         since: since, now: back, back: back, rested: false,
                                         calendar: calendar),
                       [.rest(since: since, logged: true), .resume(at: back)])
    }

    func testSwitchedOffDoesNothing() {
        let since = date(2026, 10, 20, 10)
        let back = since.addingTimeInterval(3600)
        XCTAssertEqual(PostureAway.steps(WidgetConfig(["away": .bool(false)]), schedule: schedule,
                                         since: since, now: back, back: back, rested: false,
                                         calendar: calendar), [])
        XCTAssertFalse(PostureAway.suppresses(WidgetConfig(["away": .bool(false)]), away: true))
        XCTAssertTrue(PostureAway.suppresses(WidgetConfig(), away: true))
        XCTAssertFalse(PostureAway.suppresses(WidgetConfig(), away: false))
    }

    func testOutsideTheHoursOrOvernightResetsButIsNotCounted() {
        let config = WidgetConfig()
        // 晚上 19:00 锁屏，第二天 9:10 回来：计时清零，但不记进今天的次数。
        let since = date(2026, 10, 20, 19)
        let back = date(2026, 10, 21, 9, 10)
        XCTAssertEqual(PostureAway.steps(config, schedule: schedule, since: since, now: back,
                                         back: back, rested: false, calendar: calendar),
                       [.rest(since: since, logged: false), .resume(at: back)])
        XCTAssertFalse(PostureAway.shouldLog(schedule, since: date(2026, 10, 20, 8, 30),
                                             now: date(2026, 10, 20, 9, 30), calendar: calendar))
        XCTAssertTrue(PostureAway.shouldLog(schedule, since: date(2026, 10, 20, 12),
                                            now: date(2026, 10, 20, 12, 30), calendar: calendar))
    }

    // MARK: 存的自动休息

    func testSegmentsRoundTripAndCloseOnReturn() {
        let now = date(2026, 10, 20, 12, 30)
        let since = date(2026, 10, 20, 12)
        var config = WidgetConfig(["breakDay": .string("2026-10-20"),
                                   "autoBreaks": .list([.string("\(Int(date(2026, 10, 20, 10).timeIntervalSince1970))-\(Int(date(2026, 10, 20, 10, 15).timeIntervalSince1970))")])])
        config.set("autoBreaks", .list(PostureAway.segmentsAfterResting(config, since: since, now: now, calendar: calendar)))
        XCTAssertEqual(PostureAway.segments(config, now: now, calendar: calendar),
                       [PostureAway.Segment(start: date(2026, 10, 20, 10), end: date(2026, 10, 20, 10, 15)),
                        PostureAway.Segment(start: since)])
        let back = date(2026, 10, 20, 12, 20)
        config.set("autoBreaks", .list(PostureAway.segmentsAfterReturning(config, at: back, now: now, calendar: calendar)))
        XCTAssertEqual(PostureAway.segments(config, now: now, calendar: calendar).last,
                       PostureAway.Segment(start: since, end: back))
        // 第二天全丢掉，格式不对的也丢掉。
        XCTAssertTrue(PostureAway.segments(config, now: date(2026, 10, 21, 10), calendar: calendar).isEmpty)
        let broken = WidgetConfig(["breakDay": .string("2026-10-20"), "autoBreaks": .list([.string("abc"), .string("5-1")])])
        XCTAssertTrue(PostureAway.segments(broken, now: now, calendar: calendar).isEmpty)
    }

    func testAnAutoBreakIsLoggedAtTheMomentOfLeaving() {
        let now = date(2026, 10, 20, 14)
        let config = WidgetConfig(["breakDay": .string("2026-10-20"),
                                   "breaks": .list([.number(date(2026, 10, 20, 13).timeIntervalSince1970)])])
        let since = date(2026, 10, 20, 11)
        XCTAssertEqual(PostureTrack.breaksAfterLogging(config, at: since, now: now, calendar: calendar),
                       [.number(since.timeIntervalSince1970), .number(date(2026, 10, 20, 13).timeIntervalSince1970)])
    }

    // MARK: 时间轴

    func testAwayIsNotSittingAndTheNextStretchStartsOnReturn() {
        let now = date(2026, 10, 20, 12)
        let leave = date(2026, 10, 20, 10)
        let back = date(2026, 10, 20, 10, 20)
        // 自动休息在 breaks 里记在离开那一刻；回来那一刻是 lastBreak，面板也会传进来。
        let breaks = [leave, back, date(2026, 10, 20, 11)]
        let away = [PostureAway.Segment(start: leave, end: back)]
        let stretches = PostureTrack.stretches(schedule, breaks: breaks, away: away, now: now, calendar: calendar)
        XCTAssertEqual(stretches.map { Int($0.duration / 60) }, [60, 40, 60])
        XCTAssertEqual(stretches.map(\.afterAway), [false, true, false])
        XCTAssertEqual(stretches.map(\.ongoing), [false, false, true])
        XCTAssertEqual(stretches[1].start, back)
        // 平均只算起过身的段：(60 + 40) / 2。
        XCTAssertEqual(PostureTrack.average(stretches).map { Int($0 / 60) }, 50)

        let rests = PostureAway.rests(schedule, segments: away, now: now, calendar: calendar)
        XCTAssertEqual(rests.map { Int($0.duration / 60) }, [20])
        XCTAssertEqual(rests.first?.ongoing, false)
    }

    func testStillAwayHasNoOngoingStretch() {
        let now = date(2026, 10, 20, 12)
        let leave = date(2026, 10, 20, 11, 30)
        let away = [PostureAway.Segment(start: leave)]
        let stretches = PostureTrack.stretches(schedule, breaks: [leave], away: away, now: now, calendar: calendar)
        XCTAssertEqual(stretches.map { Int($0.duration / 60) }, [150])
        XCTAssertEqual(stretches.last?.ongoing, false)
        let rests = PostureAway.rests(schedule, segments: away, now: now, calendar: calendar)
        XCTAssertEqual(rests.map { Int($0.duration / 60) }, [30])
        XCTAssertEqual(rests.first?.ongoing, true)
    }

    func testAwayBeforeTheWindowIsClipped() {
        let now = date(2026, 10, 20, 10)
        let away = [PostureAway.Segment(start: date(2026, 10, 20, 8, 50), end: date(2026, 10, 20, 9, 15))]
        let stretches = PostureTrack.stretches(schedule, breaks: [], away: away, now: now, calendar: calendar)
        XCTAssertEqual(stretches.map { Int($0.duration / 60) }, [45])
        XCTAssertEqual(stretches.first?.afterAway, true)
        XCTAssertEqual(PostureAway.rests(schedule, segments: away, now: now, calendar: calendar).map { Int($0.duration / 60) }, [15])
    }

    func testWithoutAwayTheStretchesAreUnchanged() {
        let now = date(2026, 10, 20, 14, 3)
        let breaks = [date(2026, 10, 20, 9, 40), date(2026, 10, 20, 10, 52)]
        let stretches = PostureTrack.stretches(schedule, breaks: breaks, now: now, calendar: calendar)
        XCTAssertEqual(stretches.map { Int($0.duration / 60) }, [40, 72, 191])
        XCTAssertFalse(stretches.contains(where: \.afterAway))
    }
}
