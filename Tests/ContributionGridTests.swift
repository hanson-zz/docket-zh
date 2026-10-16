import XCTest

/// 习惯卡片和 GitHub 面板的周格子。
final class ContributionGridTests: XCTestCase {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        c.firstWeekday = 2
        return c
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    func testColumnsEndWithThisWeekMondayFirst() {
        // 2026-10-16 是周五。
        let today = day(2026, 10, 16)
        let cols = ContributionGrid.columns(weeks: 3, today: today, calendar: calendar,
                                            count: { _ in 1 }, level: { $0 })
        XCTAssertEqual(cols.count, 3)
        XCTAssertTrue(cols.allSatisfy { $0.count == 7 })
        XCTAssertEqual(cols[2][0].date, day(2026, 10, 12), "最右一列从本周一开始")
        XCTAssertEqual(cols[0][0].date, day(2026, 9, 28))
        XCTAssertTrue(cols[2][4].isToday)
        XCTAssertFalse(cols[2][4].isFuture)
        XCTAssertTrue(cols[2][5].isFuture)
        XCTAssertEqual(cols[2][5].level, 0, "未来的格子不上色")
        XCTAssertEqual(cols[2][6].count, 0)
    }

    func testSundayIsLastRow() {
        let sunday = day(2026, 10, 18)
        let cols = ContributionGrid.columns(weeks: 1, today: sunday, calendar: calendar,
                                            count: { _ in 0 }, level: { $0 })
        XCTAssertTrue(cols[0][6].isToday)
        XCTAssertFalse(cols[0].contains { $0.isFuture })
    }

    func testGoalLevels() {
        XCTAssertEqual(ContributionGrid.level(count: 0, goal: 8), 0)
        XCTAssertEqual(ContributionGrid.level(count: 1, goal: 8), 1)
        XCTAssertEqual(ContributionGrid.level(count: 7, goal: 8), 3)
        XCTAssertEqual(ContributionGrid.level(count: 8, goal: 8), 4)
        XCTAssertEqual(ContributionGrid.level(count: 1, goal: 1), 4)
        XCTAssertEqual(ContributionGrid.level(count: 3, goal: 0), 4)
    }

    func testBusiestLevels() {
        XCTAssertEqual(ContributionGrid.level(count: 0, busiest: 5), 0)
        XCTAssertEqual(ContributionGrid.level(count: 1, busiest: 8), 1)
        XCTAssertEqual(ContributionGrid.level(count: 8, busiest: 8), 4)
        XCTAssertEqual(ContributionGrid.level(count: 20, busiest: 8), 4)
    }

    func testTallyGroupsByDay() {
        let base = day(2026, 10, 16)
        let tally = ContributionGrid.tally([base.addingTimeInterval(3600), base.addingTimeInterval(7200),
                                            base.addingTimeInterval(-3600)], calendar: calendar)
        XCTAssertEqual(tally[base], 2)
        XCTAssertEqual(tally[day(2026, 10, 15)], 1)
    }

    func testDelayGrowsAndStaysWithinTotal() {
        XCTAssertEqual(ContributionGrid.delay(column: 0, row: 0, columns: 10), 0)
        let last = ContributionGrid.delay(column: 9, row: 6, columns: 10)
        XCTAssertEqual(last, 0.45, accuracy: 0.0001)
        XCTAssertLessThan(ContributionGrid.delay(column: 2, row: 0, columns: 10),
                          ContributionGrid.delay(column: 3, row: 0, columns: 10))
    }

    func testZeroWeeksIsEmpty() {
        XCTAssertTrue(ContributionGrid.columns(weeks: 0, today: .now, count: { _ in 0 }, level: { $0 }).isEmpty)
    }
}
