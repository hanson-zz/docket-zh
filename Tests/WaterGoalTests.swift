import XCTest

/// 喝水的个性化推荐目标：基数、各项加减、取整、上下限、手动目标、旧配置和跨天清零。
final class WaterGoalTests: XCTestCase {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }()

    private func at(_ d: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: d, hour: hour))!
    }

    private func goal(_ profile: WaterProfile) -> Int { WaterGoal.compute(profile).recommended }

    private func goal(_ config: WidgetConfig, on day: Int = 17) -> Int {
        WaterIntake.goal(config, now: at(day), calendar: calendar)
    }

    /// Every breakdown adds up to what it explains.
    private func assertSums(_ result: WaterGoalResult, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(result.lines.reduce(0) { $0 + $1.millilitres }, result.recommended, file: file, line: line)
        XCTAssertEqual(result.lines.first?.id, "base", file: file, line: line)
    }

    // MARK: Old configs

    func testAnOldConfigWithOnlyAWeightGetsThePersonalGoal() {
        let config = WidgetConfig(["weight": .number(60)])
        XCTAssertEqual(goal(config), 2000, "60 x 33 = 1980, to the nearest 50")
        XCTAssertNil(WaterGoal.manualGoal(config))
    }

    func testAnOldDefaultOrOldSuggestionIsNotAHandSetGoal() {
        XCTAssertNil(WaterGoal.manualGoal(WidgetConfig(["goal": .number(2000)])))
        XCTAssertEqual(goal(WidgetConfig(["goal": .number(2000), "weight": .number(60)])), 2000)
        // The old 体重 x 35 suggestion for 60 kg was 2100.
        let suggested = WidgetConfig(["goal": .number(2100), "weight": .number(60)])
        XCTAssertNil(WaterGoal.manualGoal(suggested))
        XCTAssertEqual(goal(suggested), 2000)
    }

    func testAnOldGoalPickedByHandIsKept() {
        let config = WidgetConfig(["goal": .number(2400), "weight": .number(60)])
        XCTAssertEqual(WaterGoal.manualGoal(config), 2400)
        XCTAssertEqual(goal(config), 2400)
        XCTAssertEqual(goal(WidgetConfig(["goal": .number(99_999)])), WaterIntake.goalRange.upperBound)
    }

    // MARK: Defaults

    func testNothingSetUsesTheGuidelineBase() {
        let result = WaterGoal.compute(WaterProfile())
        XCTAssertEqual(result.recommended, 1600)
        XCTAssertEqual(result.goal, 1600)
        XCTAssertFalse(result.isManual)
        XCTAssertNil(result.perKilogram)
        XCTAssertEqual(result.lines.map(\.id), ["base"])
        XCTAssertEqual(goal(WidgetConfig()), 1600)
        XCTAssertEqual(goal(WaterProfile(sex: .male)), 1700)
        XCTAssertEqual(goal(WaterProfile(sex: .female)), 1500)
    }

    func testDefaultsAreTheFirstChoices() {
        let profile = WaterProfile(config: WidgetConfig(), now: at(17), calendar: calendar)
        XCTAssertEqual(profile, WaterProfile())
        XCTAssertNil(profile.weight)
        XCTAssertEqual(profile.sex, .unset)
        XCTAssertEqual(profile.activity, .sedentary)
        XCTAssertEqual(profile.climate, .mild)
        XCTAssertEqual(profile.condition, .none)
        XCTAssertEqual(profile.exerciseMinutes, 0)
        XCTAssertFalse(profile.unwell)
    }

    func testNumbersNoAdultHasAreIgnored() {
        XCTAssertEqual(goal(WaterProfile(weight: 5)), 1600)
        XCTAssertEqual(goal(WaterProfile(weight: .nan)), 1600)
        XCTAssertNil(WaterProfile(age: 0).age)
        XCTAssertNil(WaterProfile(height: 50).height)
        XCTAssertEqual(WaterProfile(exerciseMinutes: -20).exerciseMinutes, 0)
        XCTAssertEqual(WaterProfile(exerciseMinutes: 5000).exerciseMinutes, WaterGoal.maxExerciseMinutes)
        let unknown = WidgetConfig(["sex": .string("x"), "activity": .string("y"), "climate": .string("z")])
        XCTAssertEqual(WaterProfile(config: unknown, now: at(17), calendar: calendar), WaterProfile())
    }

    // MARK: Base

    func testMillilitresPerKilogram() {
        XCTAssertEqual(WaterGoal.perKilogram(WaterProfile(weight: 60)), 33)
        XCTAssertEqual(WaterGoal.perKilogram(WaterProfile(weight: 70, age: 66)), 30, "over 65")
        XCTAssertEqual(WaterGoal.perKilogram(WaterProfile(weight: 70, age: 65)), 33, "65 is not over 65")
        XCTAssertEqual(WaterGoal.perKilogram(WaterProfile(weight: 60, height: 154)), 30, "small frame")
        XCTAssertEqual(WaterGoal.perKilogram(WaterProfile(weight: 49)), 30, "under 50 kg")
        XCTAssertEqual(WaterGoal.perKilogram(WaterProfile(weight: 70, sex: .male, height: 175)), 35)
        XCTAssertEqual(WaterGoal.perKilogram(WaterProfile(weight: 70, sex: .male, height: 174)), 33)
        XCTAssertEqual(WaterGoal.perKilogram(WaterProfile(weight: 70, sex: .male)), 33, "no height, no 35")
        XCTAssertEqual(WaterGoal.perKilogram(WaterProfile(weight: 60, sex: .female)), 32)
        XCTAssertEqual(WaterGoal.perKilogram(WaterProfile(weight: 60, sex: .female, height: 150)), 30)
        XCTAssertEqual(WaterGoal.perKilogram(WaterProfile(weight: 80, sex: .male, age: 70, height: 180)), 30,
                       "age wins over height")
    }

    func testWeightBase() {
        XCTAssertEqual(goal(WaterProfile(weight: 70, sex: .male, height: 180)), 2450)
        XCTAssertEqual(goal(WaterProfile(weight: 70, sex: .male, height: 170)), 2300, "2310")
        XCTAssertEqual(goal(WaterProfile(weight: 60, sex: .female)), 1900, "1920")
        XCTAssertEqual(goal(WaterProfile(weight: 70, age: 70)), 2100)
        let result = WaterGoal.compute(WaterProfile(weight: 60))
        XCTAssertEqual(result.perKilogram, 33)
        XCTAssertEqual(result.lines.first?.detail, "体重 60 公斤 x 33 毫升")
        XCTAssertEqual(result.lines.first?.millilitres, 1980)
        assertSums(result)
    }

    // MARK: Additions

    func testActivityMultipliesTheBase() {
        let moderate = WaterGoal.compute(WaterProfile(weight: 60, activity: .moderate))
        XCTAssertEqual(moderate.recommended, 2200, "1980 x 1.1 = 2178")
        XCTAssertEqual(moderate.lines.map(\.millilitres), [1980, 198, 22])
        assertSums(moderate)
        XCTAssertEqual(goal(WaterProfile(weight: 60, activity: .heavy)), 2400, "2376")
        XCTAssertEqual(goal(WaterProfile(activity: .heavy)), 1900, "1600 x 1.2 = 1920")
        XCTAssertEqual(goal(WaterProfile(activity: .sedentary)), 1600)
    }

    func testExerciseIsProRata() {
        XCTAssertEqual(goal(WaterProfile(exerciseMinutes: 30)), 1900)
        XCTAssertEqual(goal(WaterProfile(exerciseMinutes: 45)), 2050)
        XCTAssertEqual(goal(WaterProfile(exerciseMinutes: 10)), 1700)
        let result = WaterGoal.compute(WaterProfile(exerciseMinutes: 45))
        XCTAssertEqual(result.lines.last?.millilitres, 450)
        assertSums(result)
    }

    func testClimate() {
        XCTAssertEqual(goal(WaterProfile(climate: .hotHumid)), 2100)
        XCTAssertEqual(goal(WaterProfile(climate: .altitude)), 2100)
        XCTAssertEqual(goal(WaterProfile(climate: .dry)), 1850)
        XCTAssertEqual(goal(WaterProfile(climate: .mild)), 1600)
    }

    func testPregnancyAndNursingAndNotForMen() {
        XCTAssertEqual(goal(WaterProfile(sex: .female, condition: .pregnant)), 1800)
        XCTAssertEqual(goal(WaterProfile(sex: .female, condition: .nursing)), 2200)
        XCTAssertEqual(goal(WaterProfile(condition: .nursing)), 2300, "sex not set still counts")
        let male = WaterGoal.compute(WaterProfile(sex: .male, condition: .nursing))
        XCTAssertEqual(male.recommended, 1700)
        XCTAssertFalse(male.lines.contains { $0.id == "condition" })
    }

    func testFeverOrDiarrhoea() {
        XCTAssertEqual(goal(WaterProfile(unwell: true)), 2100)
    }

    func testEverythingTogether() {
        let profile = WaterProfile(weight: 60, sex: .female, age: 30, height: 165, activity: .moderate,
                                   exerciseMinutes: 30, climate: .dry, condition: .nursing, unwell: true)
        // 60 x 32 = 1920, x 1.1 = 2112, +300 +250 +700 +500 = 3862, to 3850.
        let result = WaterGoal.compute(profile)
        XCTAssertEqual(result.recommended, 3850)
        XCTAssertEqual(result.lines.map(\.id), ["base", "activity", "exercise", "climate", "condition", "unwell", "round"])
        assertSums(result)
    }

    // MARK: Rounding and limits

    func testRoundsToTheNearestFifty() {
        XCTAssertEqual(WaterGoal.rounded(2024), 2000)
        XCTAssertEqual(WaterGoal.rounded(2025), 2050, "halves go up")
        XCTAssertEqual(WaterGoal.rounded(2049.9), 2050)
        XCTAssertEqual(goal(WaterProfile(weight: 75)), 2500, "75 x 33 = 2475")
        XCTAssertEqual(goal(WaterProfile(weight: 61)), 2000, "2013")
        let half = WaterGoal.compute(WaterProfile(weight: 61.5))
        XCTAssertEqual(half.recommended, 2050, "2029.5")
        assertSums(half)
        XCTAssertEqual(WaterGoal.compute(WaterProfile()).lines.contains { $0.id == "round" }, false)
    }

    func testKeptBetween1200And4500() {
        let low = WaterGoal.compute(WaterProfile(weight: 20))
        XCTAssertEqual(low.recommended, 1200, "20 x 30 = 600")
        XCTAssertEqual(low.lines.last?.id, "limit")
        XCTAssertEqual(low.lines.last?.millilitres, 600)
        assertSums(low)
        let high = WaterGoal.compute(WaterProfile(weight: 120, sex: .male, height: 190, activity: .heavy,
                                                  exerciseMinutes: 120, climate: .hotHumid, unwell: true))
        XCTAssertEqual(high.recommended, 4500)
        XCTAssertEqual(high.lines.last?.id, "limit")
        assertSums(high)
        XCTAssertEqual(WaterGoal.clamp(100), 1200)
        XCTAssertEqual(WaterGoal.clamp(9000), 4500)
    }

    // MARK: Hand-set goal

    func testAGoalSetByHandWinsAndCanBeUndone() {
        var config = WidgetConfig(["weight": .number(60)])
        WaterGoal.settingManual(2600, in: &config)
        let manual = WaterGoal.result(config, now: at(17), calendar: calendar)
        XCTAssertEqual(manual.goal, 2600)
        XCTAssertEqual(manual.manual, 2600)
        XCTAssertEqual(manual.recommended, 2000)
        XCTAssertTrue(manual.isManual)
        assertSums(manual)
        XCTAssertEqual(goal(config), 2600)

        // A hand-set 2000 is still a hand-set goal once the mode says so.
        WaterGoal.settingManual(2000, in: &config)
        XCTAssertEqual(WaterGoal.manualGoal(config), 2000)

        WaterGoal.followingRecommendation(in: &config)
        XCTAssertNil(config["goal"])
        XCTAssertNil(WaterGoal.manualGoal(config))
        XCTAssertEqual(goal(config), 2000)
    }

    func testAHandSetGoalStaysInsideTheGoalRange() {
        var config = WidgetConfig()
        WaterGoal.settingManual(99_999, in: &config)
        XCTAssertEqual(goal(config), WaterIntake.goalRange.upperBound)
        XCTAssertEqual(WaterGoal.compute(WaterProfile(), manual: 100).goal, WaterIntake.goalRange.lowerBound)
        // Manual mode with the number lost falls back to the old default.
        XCTAssertEqual(WaterGoal.manualGoal(WidgetConfig(["goalMode": .string("manual")])), WaterIntake.defaultGoal)
    }

    // MARK: Today only

    func testExerciseAndFeverClearTheNextDay() {
        var config = WidgetConfig()
        WaterGoal.settingExercise(60, in: &config, now: at(17, 9), calendar: calendar)
        WaterGoal.settingUnwell(true, in: &config, now: at(17, 9), calendar: calendar)
        XCTAssertEqual(config.string("exerciseDay"), "20261017")
        XCTAssertEqual(config.string("unwellDay"), "20261017")

        let today = WaterProfile(config: config, now: at(17, 23), calendar: calendar)
        XCTAssertEqual(today.exerciseMinutes, 60)
        XCTAssertTrue(today.unwell)
        XCTAssertEqual(goal(config, on: 17), 2700, "1600 + 600 + 500")

        let tomorrow = WaterProfile(config: config, now: at(18, 0), calendar: calendar)
        XCTAssertEqual(tomorrow.exerciseMinutes, 0)
        XCTAssertFalse(tomorrow.unwell)
        XCTAssertEqual(goal(config, on: 18), 1600)
    }

    func testClearingTodayRemovesTheKeys() {
        var config = WidgetConfig()
        WaterGoal.settingExercise(30, in: &config, now: at(17), calendar: calendar)
        WaterGoal.settingUnwell(true, in: &config, now: at(17), calendar: calendar)
        WaterGoal.settingExercise(0, in: &config, now: at(17), calendar: calendar)
        WaterGoal.settingUnwell(false, in: &config, now: at(17), calendar: calendar)
        XCTAssertNil(config["exercise"])
        XCTAssertNil(config["exerciseDay"])
        XCTAssertNil(config["unwell"])
        XCTAssertNil(config["unwellDay"])
    }

    func testExerciseWithoutADayIsNotCounted() {
        let config = WidgetConfig(["exercise": .number(60), "unwell": .bool(true)])
        XCTAssertEqual(goal(config), 1600)
    }

    func testTheProfileKeysCoverEveryInput() {
        let keys = Set(WaterGoal.Key.profile)
        for key in ["weight", "sex", "age", "height", "activity", "exercise", "exerciseDay",
                    "climate", "condition", "unwell", "unwellDay", "goalMode", "goal"] {
            XCTAssertTrue(keys.contains(key), key)
        }
    }

    // MARK: The log follows

    func testTodaysRecordUsesTheNewGoal() {
        var config = WidgetConfig(["weight": .number(60), "activity": .string("moderate")])
        let days = WaterIntake.logging(.water, amount: 500, in: [], goal: 2200, now: at(17, 10), calendar: calendar)
        WaterIntake.store(days, in: &config, now: at(17, 10), calendar: calendar)
        XCTAssertEqual(WaterIntake.today(config, now: at(17, 11), calendar: calendar).goal, 2200)
        WaterGoal.settingExercise(30, in: &config, now: at(17, 11), calendar: calendar)
        XCTAssertEqual(WaterIntake.today(config, now: at(17, 12), calendar: calendar).goal, 2500, "2178 + 300")
    }

    func testWords() {
        XCTAssertEqual(WaterGoal.signed(WaterGoalLine(id: "base", title: "基数", detail: "", millilitres: 1980)), "1980 毫升")
        XCTAssertEqual(WaterGoal.signed(WaterGoalLine(id: "x", title: "", detail: "", millilitres: 300)), "+300 毫升")
        XCTAssertEqual(WaterGoal.signed(WaterGoalLine(id: "x", title: "", detail: "", millilitres: -20)), "-20 毫升")
        XCTAssertEqual(WaterGoal.compute(WaterProfile(weight: 62.5)).lines.first?.detail, "体重 62.5 公斤 x 33 毫升")
    }
}
