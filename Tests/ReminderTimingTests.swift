import Foundation
import XCTest

/// 提醒事项：相对时间的写法、过期判断、推迟和改期落在哪一刻，以及和 EventKit
/// 日期组件的互换。测试包里没有本地化表，读到的始终是中文。
final class ReminderTimingTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }()

    /// 2026-10-14 是星期三。
    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0, second: Int = 0, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day,
                                           hour: hour, minute: minute, second: second))!
    }

    private func timed(_ date: Date) -> ReminderDue { ReminderDue(date: date, hasTime: true) }
    private func allDay(_ date: Date) -> ReminderDue {
        ReminderDue(date: calendar.startOfDay(for: date), hasTime: false)
    }

    // MARK: 相对时间

    func testFutureMinutesRoundUpToMatchTheClock() {
        let now = at(14, 14, 20, second: 30)
        XCTAssertEqual(ReminderTiming.relative(timed(at(14, 15)), now: now, calendar: calendar), "40 分钟后")
        XCTAssertEqual(ReminderTiming.nextLine(timed(at(14, 15)), now: now, clock: "15:00", calendar: calendar),
                       "40 分钟后 · 15:00")
    }

    func testHoursAndMinutes() {
        let now = at(14, 9)
        XCTAssertEqual(ReminderTiming.relative(timed(at(14, 11)), now: now, calendar: calendar), "2 小时后")
        XCTAssertEqual(ReminderTiming.relative(timed(at(14, 10, 20)), now: now, calendar: calendar), "1 小时 20 分钟后")
        XCTAssertEqual(ReminderTiming.relative(timed(at(14, 9, 0, second: 20)), now: now, calendar: calendar), "1 分钟后")
    }

    func testOverdueToday() {
        let now = at(14, 15, 15, second: 40)
        XCTAssertEqual(ReminderTiming.relative(timed(at(14, 15)), now: now, calendar: calendar), "已过期 15 分钟")
        XCTAssertEqual(ReminderTiming.relative(timed(at(14, 13)), now: now, calendar: calendar), "已过期 2 小时 15 分钟")
        XCTAssertEqual(ReminderTiming.relative(timed(at(14, 15, 15)), now: now, calendar: calendar), "刚到期")
    }

    func testOtherDaysSayTheDayOnly() {
        let now = at(14, 9)
        XCTAssertEqual(ReminderTiming.relative(timed(at(13, 22)), now: now, calendar: calendar), "昨天")
        XCTAssertEqual(ReminderTiming.relative(timed(at(15, 8)), now: now, calendar: calendar), "明天")
        XCTAssertEqual(ReminderTiming.relative(timed(at(17, 8)), now: now, calendar: calendar), "3 天后")
        XCTAssertEqual(ReminderTiming.relative(timed(at(10, 8)), now: now, calendar: calendar), "已过期 4 天")
        XCTAssertEqual(ReminderTiming.relative(allDay(at(14, 0)), now: now, calendar: calendar), "今天")
        // 只有日期的不写时刻。
        XCTAssertEqual(ReminderTiming.nextLine(allDay(at(14, 0)), now: now, clock: "00:00", calendar: calendar), "今天")
    }

    func testShortDay() {
        let now = at(14, 9)
        XCTAssertNil(ReminderTiming.shortDay(timed(at(14, 7, 37)), now: now, calendar: calendar))
        XCTAssertEqual(ReminderTiming.shortDay(allDay(at(14, 0)), now: now, calendar: calendar), "全天")
        XCTAssertEqual(ReminderTiming.shortDay(timed(at(13, 8)), now: now, calendar: calendar), "昨天")
        XCTAssertEqual(ReminderTiming.shortDay(allDay(at(15, 0)), now: now, calendar: calendar), "明天")
        XCTAssertNil(ReminderTiming.shortDay(timed(at(10, 8)), now: now, calendar: calendar))
    }

    func testOverdue() {
        let now = at(14, 12)
        XCTAssertTrue(ReminderTiming.isOverdue(timed(at(14, 11, 59)), now: now, calendar: calendar))
        XCTAssertFalse(ReminderTiming.isOverdue(timed(at(14, 12, 1)), now: now, calendar: calendar))
        // 全天的今天不算过期，昨天的算。
        XCTAssertFalse(ReminderTiming.isOverdue(allDay(at(14, 0)), now: now, calendar: calendar))
        XCTAssertTrue(ReminderTiming.isOverdue(allDay(at(13, 0)), now: now, calendar: calendar))
    }

    // MARK: 推迟

    func testSnoozeFromTheDueTimeWhenItIsStillAhead() {
        let now = at(14, 14, 20)
        XCTAssertEqual(ReminderTiming.snoozed(timed(at(14, 15)), now: now, calendar: calendar), timed(at(14, 16)))
    }

    func testSnoozeFromNowWhenAlreadyLate() {
        let now = at(14, 14, 20, second: 45)
        XCTAssertEqual(ReminderTiming.snoozed(timed(at(13, 9)), now: now, calendar: calendar), timed(at(14, 15, 20)))
    }

    func testSnoozeAllDayGainsATime() {
        let now = at(14, 10, 5)
        let result = ReminderTiming.snoozed(allDay(at(14, 0)), now: now, calendar: calendar)
        XCTAssertEqual(result, timed(at(14, 11, 5)))
    }

    func testTomorrowKeepsTheTime() {
        let now = at(14, 22)
        XCTAssertEqual(ReminderTiming.tomorrow(timed(at(12, 7, 37)), now: now, calendar: calendar), timed(at(15, 7, 37)))
        XCTAssertEqual(ReminderTiming.tomorrow(allDay(at(13, 0)), now: now, calendar: calendar), allDay(at(15, 0)))
    }

    func testTomorrowAcrossTheMonth() {
        let now = at(31, 20)
        XCTAssertEqual(ReminderTiming.tomorrow(timed(at(31, 9)), now: now, calendar: calendar),
                       timed(at(1, 9, month: 11)))
    }

    func testNextMonday() {
        // 星期三 → 下周一 10 月 19 日。
        XCTAssertEqual(ReminderTiming.nextMonday(timed(at(14, 15)), now: at(14, 9), calendar: calendar), timed(at(19, 15)))
        // 星期日 → 第二天。
        XCTAssertEqual(ReminderTiming.nextMonday(allDay(at(18, 0)), now: at(18, 9), calendar: calendar), allDay(at(19, 0)))
        // 今天就是周一 → 下一个周一。
        XCTAssertEqual(ReminderTiming.nextMonday(timed(at(19, 8)), now: at(19, 9), calendar: calendar), timed(at(26, 8)))
    }

    func testNextMondayIgnoresTheFirstWeekday() {
        var sundayFirst = calendar
        sundayFirst.firstWeekday = 1
        var mondayFirst = calendar
        mondayFirst.firstWeekday = 2
        let due = timed(at(16, 10))
        XCTAssertEqual(ReminderTiming.nextMonday(due, now: at(16, 9), calendar: sundayFirst),
                       ReminderTiming.nextMonday(due, now: at(16, 9), calendar: mondayFirst))
    }

    // MARK: 新提醒

    func testSuggestedTime() {
        XCTAssertEqual(ReminderTiming.suggestedTime(now: at(14, 14, 20), calendar: calendar), at(14, 15))
        XCTAssertEqual(ReminderTiming.suggestedTime(now: at(14, 23, 10), calendar: calendar), at(15, 9))
    }

    func testCombineDayAndTime() {
        XCTAssertEqual(ReminderTiming.combine(day: at(14, 23, 59), time: at(1, 15, 30), calendar: calendar),
                       timed(at(14, 15, 30)))
        XCTAssertEqual(ReminderTiming.combine(day: at(14, 23, 59), time: nil, calendar: calendar), allDay(at(14, 0)))
    }

    func testWhatStaysInTodaysPanel() {
        let now = at(14, 9)
        XCTAssertTrue(ReminderTiming.staysInToday(timed(at(14, 23)), now: now, calendar: calendar))
        XCTAssertTrue(ReminderTiming.staysInToday(timed(at(12, 8)), now: now, calendar: calendar))
        XCTAssertFalse(ReminderTiming.staysInToday(allDay(at(15, 0)), now: now, calendar: calendar))
        XCTAssertFalse(ReminderTiming.staysInToday(nil, now: now, calendar: calendar))
    }

    // MARK: 优先级

    func testPriorityFromEventKit() {
        XCTAssertEqual(ReminderPriority(eventKit: 0), .none)
        XCTAssertEqual(ReminderPriority(eventKit: 1), .high)
        XCTAssertEqual(ReminderPriority(eventKit: 4), .high)
        XCTAssertEqual(ReminderPriority(eventKit: 5), .medium)
        XCTAssertEqual(ReminderPriority(eventKit: 9), .low)
        XCTAssertEqual(ReminderPriority.medium.rawValue, 5)
        XCTAssertEqual(ReminderPriority.menuOrder.map(\.marks), ["", "!", "!!", "!!!"])
    }

    // MARK: 日期组件

    func testComponentsRoundTrip() {
        let timedDue = timed(at(14, 15, 30))
        let parts = ReminderTiming.components(timedDue, calendar: calendar)
        XCTAssertEqual(parts.hour, 15)
        XCTAssertEqual(parts.minute, 30)
        XCTAssertEqual(ReminderTiming.due(from: parts, calendar: calendar), timedDue)

        let dayDue = allDay(at(14, 0))
        let dayParts = ReminderTiming.components(dayDue, calendar: calendar)
        XCTAssertNil(dayParts.hour)
        XCTAssertEqual(ReminderTiming.due(from: dayParts, calendar: calendar), dayDue)
    }

    func testComponentsWithoutACalendarStillRead() {
        let parts = DateComponents(year: 2026, month: 10, day: 14)
        XCTAssertEqual(ReminderTiming.due(from: parts, calendar: calendar), allDay(at(14, 0)))
        XCTAssertNil(ReminderTiming.due(from: nil, calendar: calendar))
        XCTAssertNil(ReminderTiming.due(from: DateComponents(hour: 9), calendar: calendar))
    }
}
