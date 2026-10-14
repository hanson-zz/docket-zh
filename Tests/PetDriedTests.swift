import XCTest

/// 渴成骷髅: 喝水 three days short in a row, switched on in the pet's panel.
final class PetDriedTests: XCTestCase {
    private let calendar = WaterIntake.calendar

    private func day(_ back: Int, from today: Date, total: Int) -> WaterDay {
        let date = calendar.date(byAdding: .day, value: -back, to: today)!
        return WaterDay(key: HabitTracker.dayKey(date, calendar: calendar), goal: 2000, summary: total)
    }

    func testMissedDaysStopsAtAMetDayAndTheFirstLog() {
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 15))!
        let days = [day(5, from: today, total: 2100), day(3, from: today, total: 500),
                    day(1, from: today, total: 800)]
        // Yesterday, the empty day before it and day 3 missed; day 5 was met.
        XCTAssertEqual(WaterIntake.missedDays(days, goal: 2000, today: today, calendar: calendar), 4)
        let fresh = [day(1, from: today, total: 0)]
        XCTAssertEqual(WaterIntake.missedDays(fresh, goal: 2000, today: today, calendar: calendar), 1)
        XCTAssertEqual(WaterIntake.missedDays([], goal: 2000, today: today, calendar: calendar), 0)
    }

    func testTodayMetRevives() {
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 15))!
        let days = [day(3, from: today, total: 0), day(0, from: today, total: 2000)]
        XCTAssertEqual(WaterIntake.missedDays(days, goal: 2000, today: today, calendar: calendar), 0)
    }

    func testSwitchAndPicture() {
        var config = WidgetConfig()
        XCTAssertFalse(VirtualPet.isDried(config, missedDays: 5), "off by default")
        config.set(VirtualPet.dryKey, .bool(true))
        XCTAssertFalse(VirtualPet.isDried(config, missedDays: 2))
        XCTAssertTrue(VirtualPet.isDried(config, missedDays: 3))
        XCTAssertEqual(VirtualPet.imageName(.redPanda, .dried), "pet-panda-skeleton")
        XCTAssertEqual(VirtualPet.imageName(.octopus, .dried), "pet-octopus-skeleton")
        let state = VirtualPet.sample(now: .now)
        XCTAssertEqual(VirtualPet.look(state, now: .now, dried: true), .dried)
    }
}
