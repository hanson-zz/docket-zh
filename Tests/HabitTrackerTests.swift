import Foundation
import XCTest

final class HabitTrackerTests: XCTestCase {
    private let calendar = HabitTracker.calendar

    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    private func keys(_ dates: [Date]) -> Set<String> {
        Set(dates.map { HabitTracker.dayKey($0, calendar: calendar) })
    }

    func testDayKeysRoundTrip() {
        let date = day(2026, 10, 13)
        XCTAssertEqual(HabitTracker.dayKey(date, calendar: calendar), "20261013")
        XCTAssertEqual(HabitTracker.date(fromKey: "20261013", calendar: calendar),
                       calendar.startOfDay(for: date))
        XCTAssertNil(HabitTracker.date(fromKey: "2026-10-13", calendar: calendar))
        XCTAssertNil(HabitTracker.date(fromKey: "20261340", calendar: calendar))
    }

    func testEncodingRoundTripsAndToleratesLooseStrings() {
        var config = WidgetConfig()
        let habits = [Habit(id: "a", name: "早起", days: ["20261012", "20261013"]),
                      Habit(id: "b", name: "读书")]
        HabitTracker.store(habits, in: &config, now: day(2026, 10, 13))
        XCTAssertEqual(HabitTracker.habits(config), habits)

        let loose = WidgetConfig([HabitTracker.key: .list([
            .string("跑步"), .string(""), .string("x\t冥想\t20261013,garbage"), .string("x\t拉伸\t"),
        ])])
        let read = HabitTracker.habits(loose)
        XCTAssertEqual(read.map(\.name), ["跑步", "冥想", "拉伸"])
        XCTAssertEqual(read[1].days, ["20261013"], "a malformed day is dropped, not the habit")
        XCTAssertEqual(Set(read.map(\.id)).count, 3, "duplicate ids must be split")
    }

    func testStoreDropsHistoryOlderThanItKeeps() {
        var config = WidgetConfig()
        let now = day(2026, 10, 13)
        let old = calendar.date(byAdding: .day, value: -(HabitTracker.keptDays + 5), to: now)!
        HabitTracker.store([Habit(id: "a", name: "早起", days: keys([old, now]))], in: &config, now: now)
        XCTAssertEqual(HabitTracker.habits(config).first?.days, keys([now]))
    }

    func testAddRenameRemoveAndLimits() {
        var habits = HabitTracker.adding("  早起\n", to: [], id: "a")
        XCTAssertEqual(habits.map(\.name), ["早起"])
        XCTAssertEqual(HabitTracker.adding("   ", to: habits).count, 1)
        habits = HabitTracker.renaming("a", to: "六点起床", in: habits)
        XCTAssertEqual(habits.first?.name, "六点起床")
        XCTAssertEqual(HabitTracker.renaming("a", to: " ", in: habits).first?.name, "六点起床",
                       "a blank rename keeps the old name")
        XCTAssertTrue(HabitTracker.removing("a", from: habits).isEmpty)
        XCTAssertEqual(HabitTracker.clean(String(repeating: "字", count: 50))?.count, HabitTracker.maxNameLength)

        var full: [Habit] = []
        for index in 0..<20 { full = HabitTracker.adding("习惯\(index)", to: full, id: "\(index)") }
        XCTAssertEqual(full.count, HabitTracker.maxHabits)
    }

    func testToggleChecksInAndOutButNeverTheFuture() {
        let today = day(2026, 10, 13)
        var habits = [Habit(id: "a", name: "早起")]
        habits = HabitTracker.toggling("a", day: today, in: habits, today: today, calendar: calendar)
        XCTAssertTrue(HabitTracker.isDone(habits[0], on: today, calendar: calendar))
        habits = HabitTracker.toggling("a", day: today, in: habits, today: today, calendar: calendar)
        XCTAssertFalse(HabitTracker.isDone(habits[0], on: today, calendar: calendar))
        let tomorrow = day(2026, 10, 14)
        habits = HabitTracker.toggling("a", day: tomorrow, in: habits, today: today, calendar: calendar)
        XCTAssertTrue(habits[0].days.isEmpty)
    }

    func testStreakCountsBackFromTodayOrYesterday() {
        let today = day(2026, 10, 13)
        let done = Habit(name: "早起", days: keys([day(2026, 10, 10), day(2026, 10, 11),
                                                 day(2026, 10, 12), day(2026, 10, 13)]))
        XCTAssertEqual(HabitTracker.streak(done, today: today, calendar: calendar), 4)

        // Not yet today: yesterday's run is still alive.
        let pending = Habit(name: "早起", days: keys([day(2026, 10, 11), day(2026, 10, 12)]))
        XCTAssertEqual(HabitTracker.streak(pending, today: today, calendar: calendar), 2)

        // Missed yesterday: the run is over.
        let broken = Habit(name: "早起", days: keys([day(2026, 10, 10), day(2026, 10, 11)]))
        XCTAssertEqual(HabitTracker.streak(broken, today: today, calendar: calendar), 0)
        XCTAssertEqual(HabitTracker.longestStreak(broken, calendar: calendar), 2)
    }

    func testStreakCrossesAMonthEnd() {
        let habit = Habit(name: "跑步", days: keys([day(2026, 9, 29), day(2026, 9, 30), day(2026, 10, 1)]))
        XCTAssertEqual(HabitTracker.streak(habit, today: day(2026, 10, 1), calendar: calendar), 3)
        XCTAssertEqual(HabitTracker.longestStreak(habit, calendar: calendar), 3)
    }

    func testWeekRowEndsWithToday() {
        let today = day(2026, 10, 13)
        let habit = Habit(name: "早起", days: keys([day(2026, 10, 7), day(2026, 10, 13)]))
        let week = HabitTracker.week(habit, today: today, calendar: calendar)
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week.map(\.day), [7, 8, 9, 10, 11, 12, 13])
        XCTAssertEqual(week.map(\.done), [true, false, false, false, false, false, true])
        XCTAssertEqual(week.map(\.isToday), [false, false, false, false, false, false, true])
    }

    func testMonthGridStartsOnMonday() {
        // 1 October 2026 is a Thursday, so three blanks lead the first week.
        let today = day(2026, 10, 13)
        let habit = Habit(name: "早起", days: keys([day(2026, 10, 1), day(2026, 10, 13)]))
        let grid = HabitTracker.monthGrid(habit, month: today, today: today, calendar: calendar)
        XCTAssertEqual(grid.count, 5)
        XCTAssertTrue(grid.allSatisfy { $0.count == 7 })
        XCTAssertNil(grid[0][0])
        XCTAssertNil(grid[0][2])
        XCTAssertEqual(grid[0][3]?.day, 1)
        XCTAssertEqual(grid[0][3]?.done, true)
        XCTAssertEqual(grid.flatMap { $0 }.compactMap { $0 }.count, 31)
        let thirteenth = grid.flatMap { $0 }.compactMap { $0 }.first { $0.day == 13 }
        XCTAssertEqual(thirteenth?.isToday, true)
        XCTAssertEqual(grid.flatMap { $0 }.compactMap { $0 }.first { $0.day == 14 }?.isFuture, true)
        XCTAssertEqual(HabitTracker.doneCount(habit, month: today, calendar: calendar), 2)
    }

    func testCaptionAndColumnHeight() {
        XCTAssertEqual(HabitTracker.caption(done: 0, total: 0), "点按添加习惯")
        XCTAssertEqual(HabitTracker.caption(done: 1, total: 3), "今天 1/3")
        XCTAssertEqual(HabitTracker.caption(done: 3, total: 3), "今天全部完成")
        XCTAssertGreaterThanOrEqual(HabitTracker.columnHeight(count: 0), 62)
        XCTAssertEqual(HabitTracker.columnHeight(count: 9), HabitTracker.columnHeight(count: 4))
    }

    func testHabitsAreNotASettingAndTheColumnGrows() {
        XCTAssertFalse(WidgetCatalog.configurableKeys(.habit).contains(HabitTracker.key))
        var instance = WidgetCatalog.make(.habit)!
        let empty = WidgetCatalog.verticalHeight(instance)
        HabitTracker.store([Habit(name: "一"), Habit(name: "二"), Habit(name: "三")], in: &instance.config)
        XCTAssertGreaterThan(WidgetCatalog.verticalHeight(instance), empty)
        XCTAssertEqual(WidgetCatalog.contentSize(instance, position: .bottom).height, 58)
    }
}
