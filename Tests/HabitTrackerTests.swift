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

    // MARK: 图标、颜色和每日目标

    func testOldSavesReadUnchangedAndWriteBackIdentically() {
        // 旧版本写下的三列格式：没有图标、颜色和目标。
        let raw = ["a\t早起\t20261011,20261012,20261013", "b\t读书\t", "跑步"]
        let config = WidgetConfig([HabitTracker.key: .list(raw.map { .string($0) })])
        let read = HabitTracker.habits(config)
        XCTAssertEqual(read.map(\.name), ["早起", "读书", "跑步"])
        XCTAssertEqual(read[0].days, ["20261011", "20261012", "20261013"])
        XCTAssertTrue(read.allSatisfy { $0.goal == 1 && $0.icon == nil && $0.color == nil && $0.unit == nil })
        XCTAssertEqual(read[0].iconName, Habit.defaultIcon)
        XCTAssertEqual(HabitTracker.goalText(read[0]), "每天 1 次")

        // 原样存回去，字符串和旧格式一模一样，记录一条不少。
        var stored = WidgetConfig()
        HabitTracker.store(read, in: &stored, now: day(2026, 10, 13))
        XCTAssertEqual(stored.strings(HabitTracker.key), ["a\t早起\t20261011,20261012,20261013", "b\t读书\t", "h2\t跑步\t"])
        XCTAssertEqual(HabitTracker.habits(stored), read)
    }

    func testStylesAndGoalsRoundTrip() {
        let habit = Habit(id: "w", name: "喝水", days: ["20261012"], icon: "drop.fill", color: .blue,
                          goal: 8, unit: "杯", counts: ["20261013": 3])
        var config = WidgetConfig()
        HabitTracker.store([habit], in: &config, now: day(2026, 10, 13))
        let read = HabitTracker.habits(config)
        XCTAssertEqual(read, [habit])
        XCTAssertEqual(HabitTracker.goalText(read[0]), "每天 8 杯")
        XCTAssertEqual(HabitTracker.count(read[0], on: day(2026, 10, 13), calendar: calendar), 3)
        XCTAssertEqual(HabitTracker.count(read[0], on: day(2026, 10, 12), calendar: calendar), 8)
        XCTAssertEqual(HabitTracker.todayText(read[0], today: day(2026, 10, 13), calendar: calendar), "3/8 杯")
    }

    func testNewFormatKeepsEveryDayForAnOlderReader() {
        // 旧版本按逗号拆日期、丢掉认不出的项：附加信息那一项必须单独成项，
        // 不能粘在某个日期后面，否则降级时会丢掉一天的记录。
        let habit = Habit(id: "a", name: "运动", days: ["20261012", "20261013"], icon: "figure.run", color: .red)
        var config = WidgetConfig()
        HabitTracker.store([habit], in: &config, now: day(2026, 10, 13))
        let raw = config.strings(HabitTracker.key)[0]
        let items = raw.split(separator: "\t", maxSplits: 2)[2].split(separator: ",").map(String.init)
        XCTAssertEqual(Set(items.filter { $0.count == 8 && Int($0) != nil }), habit.days)
        XCTAssertEqual(items.filter { $0.hasPrefix("@") }.count, 1)
    }

    func testUnknownOrBrokenMetaIsIgnored() {
        let config = WidgetConfig([HabitTracker.key: .list([
            .string("a\t冥想\t20261013,@icon=Bad Icon!;color=chartreuse;goal=abc;future=1;counts=x:1+20261012:0"),
            .string("b\t喝水\t@goal=500;unit=杯;counts=20261012:9+20261013:2"),
        ])])
        let read = HabitTracker.habits(config)
        XCTAssertEqual(read.count, 2)
        XCTAssertEqual(read[0].days, ["20261013"])
        XCTAssertNil(read[0].icon)
        XCTAssertNil(read[0].color)
        XCTAssertEqual(read[0].goal, 1)
        XCTAssertTrue(read[0].counts.isEmpty)
        XCTAssertEqual(read[1].goal, HabitTracker.maxGoal)
        XCTAssertEqual(read[1].unit, "杯")
        XCTAssertEqual(read[1].counts, ["20261012": 9, "20261013": 2])
    }

    func testTappingCountsUpToTheGoalThenClears() {
        let today = day(2026, 10, 13)
        var habits = [Habit(id: "w", name: "喝水", goal: 3, unit: "杯")]
        habits = HabitTracker.tapping("w", day: today, in: habits, today: today, calendar: calendar)
        habits = HabitTracker.tapping("w", day: today, in: habits, today: today, calendar: calendar)
        XCTAssertFalse(HabitTracker.isDone(habits[0], on: today, calendar: calendar))
        XCTAssertEqual(HabitTracker.count(habits[0], on: today, calendar: calendar), 2)
        XCTAssertEqual(HabitTracker.progress(habits[0], on: today, calendar: calendar), 2.0 / 3.0, accuracy: 0.001)
        habits = HabitTracker.tapping("w", day: today, in: habits, today: today, calendar: calendar)
        XCTAssertTrue(HabitTracker.isDone(habits[0], on: today, calendar: calendar))
        XCTAssertTrue(habits[0].counts.isEmpty, "a met day lives only in days")
        XCTAssertEqual(HabitTracker.streak(habits[0], today: today, calendar: calendar), 1)
        habits = HabitTracker.tapping("w", day: today, in: habits, today: today, calendar: calendar)
        XCTAssertEqual(HabitTracker.count(habits[0], on: today, calendar: calendar), 0)

        // 目标 1 次时和勾选一样，也不能打明天的卡。
        var single = [Habit(id: "a", name: "早起")]
        single = HabitTracker.tapping("a", day: today, in: single, today: today, calendar: calendar)
        XCTAssertTrue(HabitTracker.isDone(single[0], on: today, calendar: calendar))
        single = HabitTracker.tapping("a", day: day(2026, 10, 14), in: single, today: today, calendar: calendar)
        XCTAssertEqual(single[0].days.count, 1)
    }

    func testToggleClearsAPartialCount() {
        let today = day(2026, 10, 13)
        var habits = [Habit(id: "w", name: "喝水", goal: 8, counts: ["20261013": 3])]
        habits = HabitTracker.toggling("w", day: today, in: habits, today: today, calendar: calendar)
        XCTAssertTrue(HabitTracker.isDone(habits[0], on: today, calendar: calendar))
        XCTAssertTrue(habits[0].counts.isEmpty)
    }

    func testUpdatingKeepsHistoryAndRenamingKeepsStyle() {
        let base = Habit(id: "a", name: "喝水", days: ["20261010", "20261011"], goal: 8,
                         counts: ["20261012": 5, "20261013": 2])
        var habits = HabitTracker.updating("a", name: "  ", icon: "drop.fill", color: .teal,
                                           goal: 4, unit: "杯", in: [base])
        XCTAssertEqual(habits[0].name, "喝水", "a blank name keeps the old one")
        XCTAssertEqual(habits[0].icon, "drop.fill")
        XCTAssertEqual(habits[0].color, .teal)
        XCTAssertEqual(habits[0].goal, 4)
        XCTAssertEqual(habits[0].days, ["20261010", "20261011", "20261012"], "lowering the goal completes a day that already has enough")
        XCTAssertEqual(habits[0].counts, ["20261013": 2])

        habits = HabitTracker.updating("a", name: "喝水", icon: nil, color: nil, goal: 20, unit: "次", in: habits)
        XCTAssertEqual(habits[0].days.count, 3, "raising the goal never undoes a done day")
        XCTAssertNil(habits[0].unit, "次 is the default unit")
        XCTAssertNil(habits[0].icon)

        let styled = [Habit(id: "b", name: "跑步", days: ["20261013"], icon: "figure.run", color: .red, goal: 2)]
        let renamed = HabitTracker.renaming("b", to: "夜跑", in: styled)
        XCTAssertEqual(renamed[0].name, "夜跑")
        XCTAssertEqual(renamed[0].icon, "figure.run")
        XCTAssertEqual(renamed[0].color, .red)
        XCTAssertEqual(renamed[0].goal, 2)
        XCTAssertEqual(renamed[0].days, ["20261013"])
    }

    func testTemplatesAndLimits() {
        XCTAssertEqual(HabitTracker.templates.map(\.name), ["早起", "阅读", "运动", "冥想", "喝水", "拉伸", "写日记", "不熬夜"])
        XCTAssertEqual(HabitTracker.icons.count, 24)
        XCTAssertEqual(Set(HabitTracker.icons).count, 24)
        XCTAssertTrue(HabitTracker.templates.allSatisfy { HabitTracker.icons.contains($0.icon) })
        XCTAssertEqual(HabitTracker.colors.count, 8)

        var habits = HabitTracker.adding(HabitTracker.templates[4], to: [], id: "w")
        XCTAssertEqual(habits[0].name, "喝水")
        XCTAssertEqual(habits[0].goal, 8)
        XCTAssertEqual(habits[0].unit, "杯")
        XCTAssertEqual(habits[0].color, .blue)
        for template in HabitTracker.templates { habits = HabitTracker.adding(template, to: habits) }
        XCTAssertEqual(habits.count, HabitTracker.maxHabits)

        XCTAssertEqual(HabitTracker.clampGoal(0), 1)
        XCTAssertEqual(HabitTracker.clampGoal(1000), HabitTracker.maxGoal)
        XCTAssertEqual(HabitTracker.cleanUnit("杯;=,+@:"), "杯")
        XCTAssertEqual(HabitTracker.cleanUnit("公里公里公里"), "公里公里")
        XCTAssertNil(HabitTracker.cleanUnit("  "))
        XCTAssertNil(HabitTracker.cleanIcon("drop.fill;x"))
    }

    func testMovingUpDownAndOntoACard() {
        let habits = ["a", "b", "c", "d"].map { Habit(id: $0, name: $0) }
        XCTAssertEqual(HabitTracker.moving("c", by: -1, in: habits).map(\.id), ["a", "c", "b", "d"])
        XCTAssertEqual(HabitTracker.moving("a", by: -1, in: habits).map(\.id), ["a", "b", "c", "d"])
        XCTAssertEqual(HabitTracker.moving("d", by: 1, in: habits).map(\.id), ["a", "b", "c", "d"])
        XCTAssertEqual(HabitTracker.moving("a", to: "c", in: habits).map(\.id), ["b", "c", "a", "d"])
        XCTAssertEqual(HabitTracker.moving("d", to: "a", in: habits).map(\.id), ["d", "a", "b", "c"])
        XCTAssertEqual(HabitTracker.moving("x", by: 1, in: habits), habits)
    }
}
