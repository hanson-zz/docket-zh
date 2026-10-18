import Foundation
import XCTest

/// 后台到点调度什么时候重读系统提醒事项。
final class ReminderRefetchTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }()

    private func at(_ hour: Int, _ minute: Int = 0, _ second: Int = 0, day: Int = 19) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute, second: second))!
    }

    private func needed(fetchedAt: Date?, fetchedDay: Date?, fetchedScope: Set<String>??,
                        now: Date, scope: Set<String>?) -> Bool {
        ReminderRefetch.needed(fetchedAt: fetchedAt, fetchedDay: fetchedDay, fetchedScope: fetchedScope,
                               now: now, day: calendar.startOfDay(for: now), scope: scope)
    }

    func testFetchesWhenNeverFetchedOrCleared() {
        XCTAssertTrue(needed(fetchedAt: nil, fetchedDay: nil, fetchedScope: .none, now: at(10), scope: nil))
        // 清空以后 fetchedAt 是 nil：其余都没变也要马上重读。
        let day = calendar.startOfDay(for: at(10))
        XCTAssertTrue(needed(fetchedAt: nil, fetchedDay: day, fetchedScope: .some(nil), now: at(10), scope: nil))
    }

    func testWaitsFiveMinutesWhenNothingChanged() {
        let day = calendar.startOfDay(for: at(10))
        XCTAssertFalse(needed(fetchedAt: at(10), fetchedDay: day, fetchedScope: .some(nil), now: at(10, 4, 59), scope: nil))
        XCTAssertTrue(needed(fetchedAt: at(10), fetchedDay: day, fetchedScope: .some(nil), now: at(10, 5), scope: nil))
    }

    func testRefetchesAfterMidnight() {
        let day = calendar.startOfDay(for: at(23, 58, day: 19))
        XCTAssertTrue(needed(fetchedAt: at(23, 58, day: 19), fetchedDay: day, fetchedScope: .some(nil),
                             now: at(0, 0, 1, day: 20), scope: nil))
    }

    func testRefetchesWhenListsChange() {
        let day = calendar.startOfDay(for: at(10))
        XCTAssertTrue(needed(fetchedAt: at(10), fetchedDay: day, fetchedScope: .some(nil), now: at(10, 1), scope: ["工作"]))
        XCTAssertTrue(needed(fetchedAt: at(10), fetchedDay: day, fetchedScope: .some(["工作"]), now: at(10, 1), scope: nil))
        XCTAssertFalse(needed(fetchedAt: at(10), fetchedDay: day, fetchedScope: .some(["工作"]), now: at(10, 1),
                              scope: ["工作"]))
    }

    func testRefetchesWhenClockWentBackwards() {
        // 系统时间往回拨了一小时：上次读的时刻在“现在”之后，不能等一小时零五分才再读。
        let day = calendar.startOfDay(for: at(10))
        XCTAssertTrue(needed(fetchedAt: at(11), fetchedDay: day, fetchedScope: .some(nil), now: at(10), scope: nil))
    }
}
