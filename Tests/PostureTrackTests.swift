import XCTest

/// 久坐提醒改版的今天和近 7 天：起身时间戳、每天次数、目标，和由它们算出的
/// 坐着的段、最长连坐、平均每次坐多久。
final class PostureTrackTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private let schedule = PostureSchedule(interval: 1800, start: 9 * 60, end: 18 * 60)

    // MARK: 目标

    func testGoalDefaultsToEightAndIsClamped() {
        XCTAssertEqual(PostureTrack.goal(WidgetConfig()), 8)
        XCTAssertEqual(PostureTrack.goal(WidgetConfig(["goal": .number(12)])), 12)
        XCTAssertEqual(PostureTrack.goal(WidgetConfig(["goal": .number(0)])), 1)
        XCTAssertEqual(PostureTrack.goal(WidgetConfig(["goal": .number(99)])), 20)
    }

    func testTheCatalogOffersTheGoalWithItsDefault() {
        XCTAssertEqual(WidgetCatalog.entry(.posture)?.defaults.values["goal"], .number(8))
    }

    // MARK: 起身时间戳

    func testBreaksAreTodaysOnlyAndClearAcrossMidnight() {
        let now = date(2026, 10, 20, 14)
        let config = WidgetConfig([
            "breakDay": .string("2026-10-20"),
            "breaks": .list([.number(date(2026, 10, 20, 11).timeIntervalSince1970),
                             .number(date(2026, 10, 20, 10).timeIntervalSince1970)]),
        ])
        XCTAssertEqual(PostureTrack.breaks(config, now: now, calendar: calendar),
                       [date(2026, 10, 20, 10), date(2026, 10, 20, 11)])
        // 第二天：昨天的全丢掉，记一次只剩这一次。
        let tomorrow = date(2026, 10, 21, 9, 30)
        XCTAssertTrue(PostureTrack.breaks(config, now: tomorrow, calendar: calendar).isEmpty)
        XCTAssertEqual(PostureTrack.breaksAfterLogging(config, now: tomorrow, calendar: calendar),
                       [.number(tomorrow.timeIntervalSince1970)])
    }

    func testLoggingAppendsToTodaysBreaks() {
        let now = date(2026, 10, 20, 14)
        let config = WidgetConfig([
            "breakDay": .string("2026-10-20"),
            "breaks": .list([.number(date(2026, 10, 20, 10).timeIntervalSince1970)]),
        ])
        XCTAssertEqual(PostureTrack.breaksAfterLogging(config, now: now, calendar: calendar),
                       [.number(date(2026, 10, 20, 10).timeIntervalSince1970), .number(now.timeIntervalSince1970)])
    }

    // MARK: 近 7 天

    func testHistoryKeepsSevenDaysAndWritesToday() {
        let now = date(2026, 10, 20, 14)
        let config = WidgetConfig(["history": .list([
            .string("2026-10-10=5"), .string("2026-10-14=6"), .string("2026-10-19=7"), .string("坏的"),
        ])])
        XCTAssertEqual(PostureTrack.historyAfterLogging(config, todayCount: 4, now: now, calendar: calendar),
                       [.string("2026-10-14=6"), .string("2026-10-19=7"), .string("2026-10-20=4")])
    }

    func testWeekIsZeroFilledAndTodayComesFromTheCount() {
        let now = date(2026, 10, 20, 14)
        let config = WidgetConfig(["history": .list([.string("2026-10-15=9"), .string("2026-10-20=1")])])
        let week = PostureTrack.week(config, todayCount: 4, now: now, calendar: calendar)
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week.map(\.count), [0, 9, 0, 0, 0, 0, 4])
        XCTAssertEqual(week.map(\.isToday), [false, false, false, false, false, false, true])
        XCTAssertEqual(week.first?.date, date(2026, 10, 14))
        XCTAssertEqual(PostureTrack.chartCeiling(week, goal: 8), 11)
    }

    /// 改版前没有 history：近 7 天只有今天，次数照旧来自 breakCount。
    func testOldDataStillShowsTodaysCount() {
        let now = date(2026, 10, 20, 14)
        let old = WidgetConfig(["breakDay": .string("2026-10-20"), "breakCount": .number(3)])
        let today = PostureTally.today(storedDay: old.string("breakDay"), count: old.int("breakCount"),
                                       now: now, calendar: calendar)
        XCTAssertEqual(PostureTrack.week(old, todayCount: today, now: now, calendar: calendar).map(\.count),
                       [0, 0, 0, 0, 0, 0, 3])
        XCTAssertTrue(PostureTrack.breaks(old, now: now, calendar: calendar).isEmpty)
    }

    // MARK: 坐着的段

    func testStretchesRunFromTheWindowThroughEachBreakToNow() {
        let now = date(2026, 10, 20, 14, 3)
        let breaks = [date(2026, 10, 20, 9, 40), date(2026, 10, 20, 10, 52),
                      date(2026, 10, 20, 11, 20), date(2026, 10, 20, 12, 5)]
        let stretches = PostureTrack.stretches(schedule, breaks: breaks, now: now, calendar: calendar)
        XCTAssertEqual(stretches.map { Int($0.duration / 60) }, [40, 72, 28, 45, 118])
        XCTAssertEqual(stretches.map(\.ongoing), [false, false, false, false, true])
        XCTAssertEqual(PostureTrack.longest(stretches).map { Int($0.duration / 60) }, 118)
        // 平均只算起过身的段：(40 + 72 + 28 + 45) / 4。
        XCTAssertEqual(PostureTrack.average(stretches).map { Int($0 / 60) }, 46)
    }

    func testDuplicateAndOutOfWindowBreaksAreIgnored() {
        let now = date(2026, 10, 20, 10)
        let breaks = [date(2026, 10, 20, 8), date(2026, 10, 20, 9, 30),
                      date(2026, 10, 20, 9, 30).addingTimeInterval(0.5), date(2026, 10, 20, 11)]
        let stretches = PostureTrack.stretches(schedule, breaks: breaks, now: now, calendar: calendar)
        XCTAssertEqual(stretches.map { Int($0.duration / 60) }, [30, 30])
    }

    func testNoBreaksYetAveragesTheCurrentStretch() {
        let now = date(2026, 10, 20, 9, 50)
        let stretches = PostureTrack.stretches(schedule, breaks: [], now: now, calendar: calendar)
        XCTAssertEqual(stretches.count, 1)
        XCTAssertEqual(PostureTrack.average(stretches).map { Int($0 / 60) }, 50)
    }

    func testBeforeTheWindowThereIsNothingAndAfterItTheDayIsClosed() {
        XCTAssertTrue(PostureTrack.stretches(schedule, breaks: [], now: date(2026, 10, 20, 8),
                                             calendar: calendar).isEmpty)
        XCTAssertNil(PostureTrack.window(schedule, now: date(2026, 10, 20, 8), calendar: calendar))
        let evening = PostureTrack.stretches(schedule, breaks: [date(2026, 10, 20, 12)],
                                             now: date(2026, 10, 20, 20), calendar: calendar)
        XCTAssertEqual(evening.map { Int($0.duration / 60) }, [180, 360])
        XCTAssertEqual(evening.last?.ongoing, false)
    }

    func testOvernightWindowCarriesPastMidnight() {
        let night = PostureSchedule(interval: 1800, start: 22 * 60, end: 6 * 60)
        let window = PostureTrack.window(night, now: date(2026, 10, 21, 2), calendar: calendar)
        XCTAssertEqual(window?.start, date(2026, 10, 20, 22))
        XCTAssertEqual(window?.end, date(2026, 10, 21, 6))
    }

    // MARK: 画法

    func testHeatGoesFromPaleToDeep() {
        XCTAssertEqual(PostureTrack.heat(600, interval: 1800), 0)
        XCTAssertEqual(PostureTrack.heat(1800 * 2.2, interval: 1800), 1, accuracy: 0.0001)
        XCTAssertEqual(PostureTrack.heat(10_000, interval: 1800), 1)
        XCTAssertLessThan(PostureTrack.heat(1800, interval: 1800), PostureTrack.heat(3600, interval: 1800))
    }

    func testTicksSplitTheWindowIntoThirdsOnTheHour() {
        XCTAssertEqual(PostureTrack.ticks(schedule), [540, 720, 900, 1080])
        XCTAssertEqual(PostureTrack.ticks(PostureSchedule(interval: 1800, start: 600, end: 720)), [600, 720])
        XCTAssertEqual(PostureTrack.fraction(date(2026, 10, 20, 12), start: date(2026, 10, 20, 9),
                                             end: date(2026, 10, 20, 18)), 1.0 / 3, accuracy: 0.0001)
    }
}
