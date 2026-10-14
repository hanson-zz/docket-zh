import Foundation
import XCTest

final class WaterIntakeTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private func at(_ y: Int, _ m: Int, _ d: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour, minute: minute))!
    }

    private func log(_ days: [WaterDay], _ type: DrinkType = .water, _ amount: Int, at date: Date,
                     goal: Int = 2000, factor: Double? = nil) -> [WaterDay] {
        WaterIntake.logging(type, amount: amount, factor: factor, in: days, goal: goal, now: date, calendar: calendar)
    }

    // MARK: Encoding

    func testEntriesEncodeCompactlyAndRoundTrip() {
        var days: [WaterDay] = []
        days = log(days, .water, 250, at: at(2026, 10, 14, 9, 30))
        days = log(days, .coffee, 200, at: at(2026, 10, 14, 14, 15))
        days = log(days, .custom, 300, at: at(2026, 10, 14, 16, 0), factor: 0.7)
        var config = WidgetConfig()
        WaterIntake.store(days, in: &config, now: at(2026, 10, 14, 17), calendar: calendar)
        XCTAssertEqual(config.strings(WaterIntake.key), ["20261014|2000|0930w250,1415c200,1600x300@70"])
        XCTAssertEqual(WaterIntake.days(config), days)
    }

    func testMalformedTokensLoseOnlyThemselves() {
        let config = WidgetConfig([WaterIntake.key: .list([
            .string("20261014|2000|0930w250,9999w100,1000q200,1100w,1200t300"),
            .string("garbage"),
            .string("2026-10-13|2000|0930w250"),
            .string("20261001|1800|=1900"),
        ])])
        let days = WaterIntake.days(config)
        XCTAssertEqual(days.map(\.key), ["20261001", "20261014"])
        XCTAssertEqual(days[1].entries.map(\.amount), [250, 300])
        XCTAssertEqual(days[0].total, 1900)
        XCTAssertTrue(days[0].isMet)
    }

    func testStoreFoldsOldDaysAndDropsAncientOnes() {
        let now = at(2026, 10, 14, 20)
        var days: [WaterDay] = []
        days = log(days, .water, 500, at: at(2026, 10, 1, 10))
        days = log(days, .tea, 500, at: at(2026, 10, 1, 11))
        days = log(days, .water, 300, at: at(2026, 10, 12, 10))
        days.append(WaterDay(key: "20260501", goal: 2000, summary: 2500))
        days.append(WaterDay(key: "20261013", goal: 2000))
        let kept = WaterIntake.compacted(days, now: now, calendar: calendar)
        XCTAssertEqual(kept.map(\.key), ["20261001", "20261012"], "ancient and empty days go")
        XCTAssertEqual(kept[0].summary, 950, "an old day keeps only its effective total")
        XCTAssertTrue(kept[0].entries.isEmpty)
        XCTAssertNil(kept[1].summary, "a recent day keeps its drinks")
    }

    // MARK: Hydration

    func testEffectiveHydrationUsesTheDrinkFactor() {
        XCTAssertEqual(WaterEntry(minute: 0, type: .water, amount: 250).effective, 250)
        XCTAssertEqual(WaterEntry(minute: 0, type: .tea, amount: 250).effective, 225)
        XCTAssertEqual(WaterEntry(minute: 0, type: .coffee, amount: 250).effective, 200)
        XCTAssertEqual(WaterEntry(minute: 0, type: .milk, amount: 200).effective, 180)
        XCTAssertEqual(WaterEntry(minute: 0, type: .juice, amount: 300).effective, 240)
        XCTAssertEqual(WaterEntry(minute: 0, type: .soda, amount: 330).effective, 198)
        XCTAssertEqual(WaterEntry(minute: 0, type: .custom, amount: 100, factor: 9).factor, 1.5, "clamped")
        let day = WaterDay(key: "20261014", goal: 2000, entries: [
            WaterEntry(minute: 600, type: .water, amount: 500),
            WaterEntry(minute: 700, type: .coffee, amount: 250),
        ])
        XCTAssertEqual(day.total, 700)
    }

    // MARK: Goal and progress

    func testGoalProgressAndWords() {
        XCTAssertEqual(WaterIntake.progress(total: 500, goal: 2000), 0.25)
        XCTAssertEqual(WaterIntake.progress(total: 2600, goal: 2000), 1)
        XCTAssertEqual(WaterIntake.progress(total: 100, goal: 0), 0)
        XCTAssertEqual(WaterIntake.tally(total: 1200, goal: 2000, ounces: false), "1200 / 2000 毫升")
        XCTAssertEqual(WaterIntake.amount(250, ounces: true), "8.5 盎司")
        XCTAssertEqual(WaterIntake.remainingLine(total: 1200, goal: 2000, ounces: false), "还差 800 毫升")
        XCTAssertEqual(WaterIntake.remainingLine(total: 2000, goal: 2000, ounces: false), "今天达标啦")
        XCTAssertEqual(WaterIntake.goal(WidgetConfig()), 2000)
        XCTAssertEqual(WaterIntake.goal(WidgetConfig(["goal": .number(99_999)])), WaterIntake.goalRange.upperBound)
        XCTAssertEqual(WaterIntake.cupSize(WidgetConfig()), 250)
    }

    func testChangingTheGoalOnlyMovesToday() {
        var days: [WaterDay] = []
        days = log(days, .water, 1800, at: at(2026, 10, 13, 10), goal: 1500)
        days = log(days, .water, 1800, at: at(2026, 10, 14, 10), goal: 1500)
        days = WaterIntake.settingGoal(2500, in: days, now: at(2026, 10, 14, 11), calendar: calendar)
        XCTAssertEqual(days.first { $0.key == "20261013" }?.goal, 1500, "yesterday stays met")
        XCTAssertEqual(days.first { $0.key == "20261014" }?.goal, 2500)
    }

    func testUndoAndDelete() {
        var days: [WaterDay] = []
        let now = at(2026, 10, 14, 15)
        days = log(days, .water, 250, at: at(2026, 10, 14, 9))
        days = log(days, .tea, 300, at: at(2026, 10, 14, 11))
        days = log(days, .water, 100, at: at(2026, 10, 14, 13))
        days = WaterIntake.undoingLast(in: days, goal: 2000, now: now, calendar: calendar)
        XCTAssertEqual(WaterIntake.today(days, goal: 2000, now: now, calendar: calendar).entries.map(\.amount), [250, 300])
        days = WaterIntake.removing(at: 0, in: days, goal: 2000, now: now, calendar: calendar)
        XCTAssertEqual(WaterIntake.today(days, goal: 2000, now: now, calendar: calendar).entries.map(\.type), [.tea])
        XCTAssertEqual(WaterIntake.removing(at: 5, in: days, goal: 2000, now: now, calendar: calendar), days)
    }

    // MARK: Streak and rollover

    func testStreakAcrossDays() {
        var days: [WaterDay] = []
        for d in [10, 11, 12, 13] { days = log(days, .water, 2000, at: at(2026, 10, d, 10)) }
        days = log(days, .water, 500, at: at(2026, 10, 14, 10))
        XCTAssertEqual(WaterIntake.streak(days, goal: 2000, today: at(2026, 10, 14, 18), calendar: calendar), 4,
                       "today not met yet keeps yesterday's run")
        days = log(days, .water, 1500, at: at(2026, 10, 14, 19))
        XCTAssertEqual(WaterIntake.streak(days, goal: 2000, today: at(2026, 10, 14, 20), calendar: calendar), 5)
        XCTAssertEqual(WaterIntake.streak(days, goal: 2000, today: at(2026, 10, 16, 9), calendar: calendar), 0,
                       "a missed day breaks it")
    }

    func testDayRolloverStartsAnEmptyDay() {
        var days: [WaterDay] = []
        days = log(days, .water, 2000, at: at(2026, 10, 14, 23, 59))
        let midnight = at(2026, 10, 15, 0, 1)
        let today = WaterIntake.today(days, goal: 2000, now: midnight, calendar: calendar)
        XCTAssertEqual(today.key, "20261015")
        XCTAssertEqual(today.total, 0)
        days = log(days, .water, 250, at: midnight)
        XCTAssertEqual(days.map(\.key), ["20261014", "20261015"])
        XCTAssertEqual(days[0].total, 2000)
        XCTAssertEqual(WaterIntake.lastDrink(days, calendar: calendar), at(2026, 10, 15, 0, 1))
    }

    func testLastSevenDaysAndMonth() {
        var days: [WaterDay] = []
        days = log(days, .water, 2000, at: at(2026, 10, 9, 10))
        days = log(days, .water, 1000, at: at(2026, 10, 14, 10))
        let week = WaterIntake.lastDays(days, goal: 2000, today: at(2026, 10, 14), calendar: calendar)
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week.first?.key, "20261008")
        XCTAssertEqual(week.last?.isToday, true)
        XCTAssertEqual(week.last?.fraction, 0.5)
        XCTAssertEqual(week[1].isMet, true)
        let grid = WaterIntake.monthGrid(days, goal: 2000, month: at(2026, 10, 14), today: at(2026, 10, 14), calendar: calendar)
        XCTAssertEqual(grid.first?.prefix(3).allSatisfy { $0 == nil }, true, "October 2026 starts on a Thursday")
        XCTAssertEqual(WaterIntake.metCount(days, goal: 2000, month: at(2026, 10, 14), today: at(2026, 10, 14), calendar: calendar), 1)
    }

    // MARK: Weight

    func testWeightSuggestion() {
        XCTAssertEqual(WaterIntake.suggestedGoal(weightKilograms: 60), 2100)
        XCTAssertEqual(WaterIntake.suggestedGoal(weightKilograms: 57), 2000, "to the nearest 50")
        XCTAssertEqual(WaterIntake.suggestedGoal(weightKilograms: 200), WaterIntake.goalRange.upperBound)
        XCTAssertNil(WaterIntake.suggestedGoal(weightKilograms: 5))
        XCTAssertNil(WaterIntake.suggestedGoal(weightKilograms: .nan))
    }

    // MARK: Reminders

    private let reminder = WaterReminder(every: 60, start: 9 * 60, end: 21 * 60)

    func testFirstReminderIsAtTheStartOfTheWindow() {
        XCTAssertEqual(reminder.next(now: at(2026, 10, 14, 7), lastDrink: nil, todayTotal: 0, goal: 2000, calendar: calendar),
                       at(2026, 10, 14, 9))
    }

    func testARecentDrinkPushesTheReminderBack() {
        let next = reminder.next(now: at(2026, 10, 14, 10, 40), lastDrink: at(2026, 10, 14, 10, 30),
                                 todayTotal: 500, goal: 2000, calendar: calendar)
        XCTAssertEqual(next, at(2026, 10, 14, 11, 30))
        let early = reminder.next(now: at(2026, 10, 14, 7, 40), lastDrink: at(2026, 10, 14, 7, 30),
                                  todayTotal: 250, goal: 2000, calendar: calendar)
        XCTAssertEqual(early, at(2026, 10, 14, 9), "never before the window opens")
    }

    func testAnIgnoredReminderRepeatsEveryInterval() {
        let next = reminder.next(now: at(2026, 10, 14, 12, 10), lastDrink: at(2026, 10, 14, 10),
                                 todayTotal: 500, goal: 2000, calendar: calendar)
        XCTAssertEqual(next, at(2026, 10, 14, 13))
    }

    func testNothingAfterTheWindowOrOnceTheGoalIsMet() {
        let late = reminder.next(now: at(2026, 10, 14, 20, 30), lastDrink: at(2026, 10, 14, 20, 15),
                                 todayTotal: 1500, goal: 2000, calendar: calendar)
        XCTAssertEqual(late, at(2026, 10, 15, 9), "waits for tomorrow's window")
        let done = reminder.next(now: at(2026, 10, 14, 14), lastDrink: at(2026, 10, 14, 13),
                                 todayTotal: 2000, goal: 2000, calendar: calendar)
        XCTAssertEqual(done, at(2026, 10, 15, 9), "goal met: quiet until tomorrow")
        XCTAssertNil(WaterReminder(every: 0, start: 540, end: 1260)
            .next(now: at(2026, 10, 14, 10), lastDrink: nil, todayTotal: 0, goal: 2000, calendar: calendar))
    }

    func testReminderOptionsFromConfig() {
        XCTAssertEqual(WaterIntake.reminderMinutes(WidgetConfig()), 60)
        XCTAssertEqual(WaterIntake.reminderMinutes(WidgetConfig(["remindEvery": .string("45")])), 45)
        XCTAssertEqual(WaterIntake.reminderMinutes(WidgetConfig(["remindEvery": .string("7")])), 0)
        let schedule = WaterReminder(config: WidgetConfig(["start": .string("8:30"), "end": .string("22:00")]))
        XCTAssertEqual(schedule.start, 510)
        XCTAssertEqual(schedule.end, 1320)
        XCTAssertTrue(schedule.isActive(at(2026, 10, 14, 21), calendar: calendar))
        XCTAssertFalse(schedule.isActive(at(2026, 10, 14, 23), calendar: calendar))
        let message = WaterReminder.message(at: at(2026, 10, 14, 10), total: 1200, goal: 2000)
        XCTAssertTrue(message.body.contains("800 毫升"))
        XCTAssertTrue(message.title.contains("小熊猫") || message.title.contains("喝水") || message.title.contains("补水"))
    }

    // MARK: Wiring

    func testWaterIsWiredIntoTheCatalogAndVisibility() {
        let entry = WidgetCatalog.entry(.water)
        XCTAssertEqual(entry?.name, "喝水")
        XCTAssertEqual(entry?.category, .reminders)
        XCTAssertTrue(WidgetVisibility.supportsCondition(.water))
        var widget = WidgetCatalog.make(.water)!
        XCTAssertEqual(WidgetVisibility.conditionTitle(.water, config: widget.config), "今天未达标时显示")
        XCTAssertEqual(WidgetCatalog.variantTitle(matching: widget.config, kind: .water), "角色")
        XCTAssertGreaterThanOrEqual(WidgetCatalog.verticalHeight(widget), 76)

        widget.config.set(WidgetVisibility.modeKey, .string("conditional"))
        XCTAssertEqual(WidgetVisibility.conditionHolds(widget, .unknown), true, "nothing drunk yet")
        let days = WaterIntake.logging(.water, amount: 2500, in: [], goal: 2000, now: .now)
        WaterIntake.store(days, in: &widget.config)
        XCTAssertEqual(WidgetVisibility.conditionHolds(widget, .unknown), false, "goal met hides it")

        widget.config.set("layout", .string("ring"))
        XCTAssertEqual(WidgetCatalog.variantTitle(matching: widget.config, kind: .water), "圆环")
    }
}
