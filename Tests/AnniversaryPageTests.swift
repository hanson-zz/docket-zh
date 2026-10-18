import Foundation
import XCTest

/// 纪念日专属页的里程碑、接下来几个周年和“这个月”的小概览。
final class AnniversaryPageTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    private func midnight(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.startOfDay(for: day(y, m, d))
    }

    private let together = AnniversaryEvent(id: "t", title: "在一起", day: "20190520", kind: .countup, yearly: true)
    private let birthday = AnniversaryEvent(id: "b", title: "生日", day: "19901030", kind: .countdown, yearly: true)

    // MARK: Milestones

    func testCountUpMilestonesMatchTheCard() {
        let today = day(2026, 10, 18)
        XCTAssertEqual(Anniversary.reading(together, today: today, calendar: calendar)?.days, 2708)
        let stones = Anniversary.milestones(together, today: today, calendar: calendar)
        XCTAssertEqual(stones.map(\.days), Anniversary.countupMilestones)
        XCTAssertEqual(stones.first?.date, midnight(2019, 8, 28))
        XCTAssertEqual(stones[1].date, midnight(2020, 10, 21))
        XCTAssertEqual(stones[2].date, midnight(2022, 2, 13))
        XCTAssertEqual(stones.last?.date, midnight(2046, 10, 5))
        XCTAssertTrue(stones.allSatisfy { $0.kind == .daysSince })
        // 2000 天在 2024-11-09，已经过了；3000 天在 2027-08-06，是下一个。
        XCTAssertEqual(stones.filter(\.isPassed).map(\.days), [100, 520, 1000, 1314, 2000])
        XCTAssertEqual(stones.filter(\.isNext).map(\.days), [3000])
        XCTAssertEqual(stones.first { $0.days == 3000 }?.date, midnight(2027, 8, 6))
        XCTAssertFalse(stones.contains { $0.isToday })
    }

    func testMilestoneOnTheDayIsTodayAndNext() {
        let stones = Anniversary.milestones(together, today: day(2019, 8, 28), calendar: calendar)
        let hundred = stones[0]
        XCTAssertTrue(hundred.isToday)
        XCTAssertTrue(hundred.isNext)
        XCTAssertFalse(hundred.isPassed)
        XCTAssertEqual(Anniversary.reading(together, today: day(2019, 8, 28), calendar: calendar)?.days, 100)
    }

    func testCountDownMilestonesLeadUpToTheNextOccurrence() {
        let stones = Anniversary.milestones(birthday, today: day(2026, 10, 18), calendar: calendar)
        XCTAssertEqual(stones.map(\.days), Anniversary.countdownMilestones)
        XCTAssertTrue(stones.allSatisfy { $0.kind == .daysLeft })
        XCTAssertEqual(stones.map(\.date), [midnight(2026, 7, 22), midnight(2026, 9, 30),
                                            midnight(2026, 10, 23), midnight(2026, 10, 29)])
        XCTAssertEqual(stones.map(\.isPassed), [true, true, false, false])
        XCTAssertEqual(stones.map(\.isNext), [false, false, true, false])
    }

    func testFinishedOneOffCountdownHasNoMilestones() {
        let exam = AnniversaryEvent(title: "考试", day: "20260601")
        XCTAssertTrue(Anniversary.milestones(exam, today: day(2026, 10, 18), calendar: calendar).isEmpty)
        // 还没到的一次性倒数日照常有。
        XCTAssertEqual(Anniversary.milestones(exam, today: day(2026, 5, 1), calendar: calendar).count, 4)
    }

    // MARK: Upcoming anniversaries

    func testUpcomingAnniversariesCountFromTheDay() {
        let next = Anniversary.upcomingAnniversaries(together, today: day(2026, 10, 18), calendar: calendar)
        XCTAssertEqual(next.map(\.ordinal), [8, 9, 10, 11])
        XCTAssertEqual(next.map(\.date), [midnight(2027, 5, 20), midnight(2028, 5, 20),
                                          midnight(2029, 5, 20), midnight(2030, 5, 20)])
        XCTAssertEqual(next.map(\.daysLeft), [214, 580, 945, 1310])
    }

    func testUpcomingAnniversaryIncludesToday() {
        let next = Anniversary.upcomingAnniversaries(together, today: day(2027, 5, 20), count: 2, calendar: calendar)
        XCTAssertEqual(next.first?.ordinal, 8)
        XCTAssertEqual(next.first?.daysLeft, 0)
        XCTAssertEqual(next.count, 2)
    }

    func testUpcomingAnniversariesOfABirthdayAreTheAges() {
        let next = Anniversary.upcomingAnniversaries(birthday, today: day(2026, 10, 18), count: 1, calendar: calendar)
        XCTAssertEqual(next.first?.ordinal, 36)
        XCTAssertEqual(next.first?.daysLeft, 12)
    }

    func testOneOffCountdownHasNoAnniversaries() {
        let trip = AnniversaryEvent(title: "旅行", day: "20261201")
        XCTAssertTrue(Anniversary.upcomingAnniversaries(trip, today: day(2026, 10, 18), calendar: calendar).isEmpty)
    }

    func testLunarAnniversariesLandOnTheirSolarDays() {
        // 正月初一：2027 年 2 月 6 日、2028 年 1 月 26 日、2029 年 2 月 13 日。
        let spring = AnniversaryEvent(title: "春节", day: "20260217", yearly: true, lunar: true)
        let next = Anniversary.upcomingAnniversaries(spring, today: day(2026, 10, 18), count: 3, calendar: calendar)
        XCTAssertEqual(next.map(\.ordinal), [1, 2, 3])
        XCTAssertEqual(next.map(\.date), [midnight(2027, 2, 6), midnight(2028, 1, 26), midnight(2029, 2, 13)])
    }

    // MARK: This month

    func testMonthSummaryCountsAndFindsTheNearest() {
        let events = [
            birthday,
            together,
            AnniversaryEvent(id: "n", title: "国庆", day: "20261001", yearly: true),
            AnniversaryEvent(id: "o", title: "面试", day: "20261005"),
            AnniversaryEvent(id: "x", title: "旅行", day: "20261105"),
        ]
        let summary = Anniversary.monthSummary(events, today: day(2026, 10, 18), calendar: calendar)
        XCTAssertEqual(summary.month, 10)
        XCTAssertEqual(summary.count, 3)
        XCTAssertEqual(summary.nearest?.id, "b")
        XCTAssertEqual(summary.nearestDays, 12)

        let late = Anniversary.monthSummary(events, today: day(2026, 10, 31), calendar: calendar)
        XCTAssertEqual(late.count, 3)
        XCTAssertNil(late.nearest)
        XCTAssertNil(late.nearestDays)

        let may = Anniversary.monthSummary(events, today: day(2027, 5, 1), calendar: calendar)
        XCTAssertEqual(may.count, 1)
        XCTAssertEqual(may.nearest?.id, "t")
        XCTAssertEqual(may.nearestDays, 19)
    }

    func testMonthSummaryOnTheDayIsZero() {
        let summary = Anniversary.monthSummary([birthday], today: day(2026, 10, 30), calendar: calendar)
        XCTAssertEqual(summary.count, 1)
        XCTAssertEqual(summary.nearestDays, 0)
    }

    func testYearlyEventSetInTheFutureIsNotCountedBeforeItsDay() {
        let wedding = AnniversaryEvent(title: "婚礼", day: "20271020", yearly: true)
        XCTAssertNil(Anniversary.dayInMonth(wedding, year: 2026, month: 10, calendar: calendar))
        XCTAssertEqual(Anniversary.dayInMonth(wedding, year: 2027, month: 10, calendar: calendar), midnight(2027, 10, 20))
        XCTAssertEqual(Anniversary.dayInMonth(wedding, year: 2028, month: 10, calendar: calendar), midnight(2028, 10, 20))
    }

    func testLunarEventInTheMonthItFallsIn() {
        let spring = AnniversaryEvent(title: "春节", day: "20260217", yearly: true, lunar: true)
        XCTAssertEqual(Anniversary.dayInMonth(spring, year: 2028, month: 1, calendar: calendar), midnight(2028, 1, 26))
        XCTAssertNil(Anniversary.dayInMonth(spring, year: 2028, month: 2, calendar: calendar))
    }

    // MARK: Text

    func testDateTexts() {
        XCTAssertEqual(Anniversary.dotText(midnight(2019, 8, 28), calendar: calendar), "2019.8.28")
        XCTAssertEqual(Anniversary.longText(midnight(2027, 5, 20), calendar: calendar), "2027年5月20日")
        XCTAssertEqual(Anniversary.weekdayShort(midnight(2019, 8, 28), calendar: calendar), "周三")
        XCTAssertEqual(Anniversary.weekdayShort(midnight(2027, 5, 20), calendar: calendar), "周四")
    }
}
