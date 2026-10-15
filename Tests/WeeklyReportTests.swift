import Foundation
import XCTest

final class WeeklyReportTests: XCTestCase {
    private let calendar = HabitTracker.calendar

    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    private func key(_ y: Int, _ m: Int, _ d: Int) -> String {
        String(format: "%04d%02d%02d", y, m, d)
    }

    // MARK: WeeklyReport

    func testSevenDaysEndingTodayWithMissingDaysAsZero() {
        // 2026-10-15 is a Thursday.
        let values = [key(2026, 10, 15): 60.0, key(2026, 10, 12): 40, key(2026, 10, 1): 999]
        let report = WeeklyReport.make(values: values, goal: 50, today: day(2026, 10, 15), calendar: calendar)
        XCTAssertEqual(report.days.count, 7)
        XCTAssertEqual(report.days.map(\.key), (9...15).map { key(2026, 10, $0) })
        XCTAssertEqual(report.days.last?.isToday, true)
        XCTAssertEqual(report.days.filter(\.isToday).count, 1)
        XCTAssertEqual(report.days.map(\.value), [0, 0, 0, 40, 0, 0, 60], "a day outside the week is ignored")
        XCTAssertEqual(report.total, 100)
        XCTAssertEqual(report.average, 100.0 / 7, accuracy: 0.0001, "the average is over all seven days")
        XCTAssertEqual(report.metDays, 1)
        XCTAssertEqual(report.best?.key, key(2026, 10, 15))
    }

    func testEmptyWeekHasNoBestAndNoDivisionByZero() {
        let report = WeeklyReport.make(values: [:], goal: 50, today: day(2026, 10, 15), calendar: calendar)
        XCTAssertEqual(report.total, 0)
        XCTAssertEqual(report.average, 0)
        XCTAssertEqual(report.metDays, 0)
        XCTAssertNil(report.best)
        XCTAssertEqual(report.scale, 50)
        XCTAssertEqual(report.goalFraction, 1)
        XCTAssertTrue(report.days.allSatisfy { report.fraction($0) == 0 })
    }

    func testAcrossAMonthAndYearBoundary() {
        let report = WeeklyReport.make(values: [key(2026, 12, 30): 10, key(2027, 1, 2): 20],
                                       goal: 10, today: day(2027, 1, 3), calendar: calendar)
        XCTAssertEqual(report.days.map(\.key),
                       [key(2026, 12, 28), key(2026, 12, 29), key(2026, 12, 30), key(2026, 12, 31),
                        key(2027, 1, 1), key(2027, 1, 2), key(2027, 1, 3)])
        XCTAssertEqual(report.days.map(\.day), [28, 29, 30, 31, 1, 2, 3])
        XCTAssertEqual(report.total, 30)
        XCTAssertEqual(report.metDays, 2)
        XCTAssertEqual(report.best?.key, key(2027, 1, 2))

        let march = WeeklyReport.make(values: [key(2026, 2, 28): 5], goal: 1, today: day(2026, 3, 2),
                                      calendar: calendar)
        XCTAssertEqual(march.days.map(\.day), [24, 25, 26, 27, 28, 1, 2], "2026 is not a leap year")
        XCTAssertEqual(march.total, 5)
    }

    func testZeroGoalMeetsNothingAndDrawsNoLine() {
        let report = WeeklyReport.make(values: [key(2026, 10, 15): 30, key(2026, 10, 14): 0],
                                       goal: 0, today: day(2026, 10, 15), calendar: calendar)
        XCTAssertEqual(report.metDays, 0, "with no goal nothing is met, not everything")
        XCTAssertNil(report.goalFraction)
        XCTAssertEqual(report.scale, 30)
        XCTAssertEqual(report.fraction(report.days[6]), 1)
        XCTAssertFalse(WeeklyReport.isMet(value: 0, goal: 0))
    }

    func testNegativeAndNonFiniteValuesCountAsZero() {
        let report = WeeklyReport.make(values: [key(2026, 10, 15): -5, key(2026, 10, 14): .nan,
                                                key(2026, 10, 13): .infinity],
                                       goal: .nan, today: day(2026, 10, 15), calendar: calendar)
        XCTAssertEqual(report.total, 0)
        XCTAssertEqual(report.goal, 0)
        XCTAssertNil(report.best)
    }

    func testBestDayPrefersTheLaterOnATie() {
        let report = WeeklyReport.make(values: [key(2026, 10, 10): 80, key(2026, 10, 13): 80, key(2026, 10, 14): 20],
                                       goal: 50, today: day(2026, 10, 15), calendar: calendar)
        XCTAssertEqual(report.best?.key, key(2026, 10, 13))
        XCTAssertEqual(report.scale, 80)
        XCTAssertEqual(report.goalFraction ?? 0, 50.0 / 80, accuracy: 0.0001)
    }

    func testPerDayGoalsAndTodayFollowsTheCurrentGoal() {
        let goals = [key(2026, 10, 14): 100.0, key(2026, 10, 15): 100]
        let values = [key(2026, 10, 14): 150.0, key(2026, 10, 15): 150, key(2026, 10, 13): 150]
        let report = WeeklyReport.make(values: values, goal: 200, goals: goals, today: day(2026, 10, 15),
                                       calendar: calendar)
        XCTAssertTrue(report.days[5].isMet, "yesterday keeps its frozen goal")
        XCTAssertFalse(report.days[6].isMet, "today is judged against the goal set now")
        XCTAssertFalse(report.days[4].isMet, "a day without its own goal uses the current one")
        XCTAssertEqual(report.metDays, 1)
    }

    func testAxisLabels() {
        let report = WeeklyReport.make(values: [:], goal: 0, today: day(2026, 10, 15), calendar: calendar)
        XCTAssertEqual(report.days.last?.axisLabel, "15 / 周四")
        XCTAssertEqual(report.days.first?.axisLabel, "9 / 周五")
        XCTAssertEqual(report.days.map(\.weekdayLabel), ["周五", "周六", "周日", "周一", "周二", "周三", "周四"])
    }

    func testWords() {
        XCTAssertEqual(WeeklyReport.duration(minutes: 45), "45 分")
        XCTAssertEqual(WeeklyReport.duration(minutes: 120), "2 小时")
        XCTAssertEqual(WeeklyReport.duration(minutes: 200), "3 小时 20 分")
        XCTAssertEqual(WeeklyReport.duration(minutes: -3), "0 分")
        XCTAssertEqual(WeeklyReport.figure(6), "6")
        XCTAssertEqual(WeeklyReport.figure(5.55), "5.6")
        XCTAssertEqual(WeeklyReport.figure(.nan), "0")
    }

    // MARK: Habits

    func testHabitCompletionRateCheckInsAndPerfectDays() {
        let today = day(2026, 10, 15)
        let habits = [
            Habit(id: "a", name: "早起", days: [key(2026, 10, 15), key(2026, 10, 14), key(2026, 9, 30)]),
            Habit(id: "b", name: "读书", days: [key(2026, 10, 15), key(2026, 10, 10)]),
        ]
        let report = WeeklyReport.habits(habits, today: today, calendar: calendar)
        XCTAssertEqual(report.goal, 100)
        XCTAssertEqual(report.days.map(\.value), [0, 50, 0, 0, 0, 50, 100])
        XCTAssertEqual(report.metDays, 1, "only a day with every habit done is 全勤")
        XCTAssertEqual(WeeklyReport.habitCheckIns(habits, today: today, calendar: calendar), 4)

        let none = WeeklyReport.habits([], today: today, calendar: calendar)
        XCTAssertEqual(none.total, 0)
        XCTAssertEqual(none.metDays, 0)
        XCTAssertNil(none.goalFraction)
    }

    // MARK: Water

    func testWaterUsesTotalsFrozenGoalsAndCountsCups() {
        let today = day(2026, 10, 15)
        let days = [
            WaterDay(key: key(2026, 10, 15), goal: 1500,
                     entries: [WaterEntry(minute: 540, type: .water, amount: 500),
                               WaterEntry(minute: 600, type: .coffee, amount: 250)]),
            WaterDay(key: key(2026, 10, 13), goal: 1000, summary: 1200),
            WaterDay(key: key(2026, 10, 1), goal: 2000, summary: 3000),
        ]
        let report = WeeklyReport.water(days, goal: 2000, today: today, calendar: calendar)
        XCTAssertEqual(report.days[6].value, 700, "coffee counts at 80%")
        XCTAssertEqual(report.days[6].goal, 2000, "today follows the current goal")
        XCTAssertTrue(report.days[4].isMet, "an old day keeps the goal it was frozen with")
        XCTAssertEqual(report.total, 1900)
        XCTAssertEqual(report.metDays, 1)
        XCTAssertEqual(WeeklyReport.waterCups(days, today: today, calendar: calendar), 2)
    }

    // MARK: FocusLog

    func testFocusLogAddsSessionsToTheDayTheyEnded() {
        var lines: [String] = []
        lines = FocusLog.adding(seconds: 25 * 60, endedAt: day(2026, 10, 15, hour: 9), to: lines, calendar: calendar)
        lines = FocusLog.adding(seconds: 25 * 60, endedAt: day(2026, 10, 15, hour: 11), to: lines, calendar: calendar)
        lines = FocusLog.adding(seconds: 50 * 60, endedAt: day(2026, 10, 14, hour: 23), to: lines, calendar: calendar)
        lines = FocusLog.adding(seconds: 20, endedAt: day(2026, 10, 14), to: lines, calendar: calendar)
        XCTAssertEqual(lines, ["20261014|50", "20261015|50"])
        let report = FocusLog.report(lines, goal: FocusLog.defaultGoal, today: day(2026, 10, 15), calendar: calendar)
        XCTAssertEqual(report.total, 100)
        XCTAssertEqual(report.metDays, 2)
    }

    func testFocusLogIsTolerantAndTrimsOldDays() {
        let read = FocusLog.minutes(["20261015|30", "garbage", "20261015|15", "20261399|10", "20261014|-4",
                                     "20261013|5000"])
        XCTAssertEqual(read, ["20261015": 45, "20261013": FocusLog.maxMinutesPerDay])
        let kept = FocusLog.lines(["20260101": 30, "20261015": 10], now: day(2026, 10, 15), calendar: calendar)
        XCTAssertEqual(kept, ["20261015|10"], "older than the kept window is dropped")
    }

    func testFocusGoalDefaultsAndClamps() {
        XCTAssertEqual(FocusLog.goal(stored: 0), 50)
        XCTAssertEqual(FocusLog.goal(stored: 90), 90)
        XCTAssertEqual(FocusLog.goal(stored: 100_000), FocusLog.goalRange.upperBound)
        XCTAssertEqual(FocusLog.clampGoal(1), FocusLog.goalRange.lowerBound)
        var timer = TimerState()
        timer.work = 30
        XCTAssertEqual(FocusLog.sessionSeconds(timer), 1800)
        timer.duration = 900
        XCTAssertEqual(FocusLog.sessionSeconds(timer), 900)
    }
}
