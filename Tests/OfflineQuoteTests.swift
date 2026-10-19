import XCTest

/// 行情断网时卡片底行的「离线 · 10:32 的价」。
final class OfflineQuoteTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    func testSameDayShowsHoursAndMinutes() {
        let now = date(19, 15, 0)
        XCTAssertEqual(OfflineQuote.timeText(date(19, 10, 32), now: now, calendar: calendar), "10:32")
        XCTAssertEqual(OfflineQuote.label(fetched: date(19, 9, 5), now: now, calendar: calendar), "离线 · 09:05 的价")
    }

    func testAnotherDayAddsTheDate() {
        let now = date(19, 9, 0)
        XCTAssertEqual(OfflineQuote.timeText(date(18, 22, 30), now: now, calendar: calendar), "10/18 22:30")
    }

    func testUnknownTimeSaysOfflineOnly() {
        XCTAssertEqual(OfflineQuote.label(fetched: nil, now: date(19, 9, 0), calendar: calendar), "离线")
    }

    func testOldestOfAGroupWins() {
        let early = date(19, 9, 0), late = date(19, 10, 0)
        XCTAssertEqual(OfflineQuote.oldest([late, nil, early]), early, "一组里取最早的，宁可说旧")
        XCTAssertNil(OfflineQuote.oldest([nil, nil]))
        XCTAssertNil(OfflineQuote.oldest([]))
    }

    func testStaleCardIsStillReadable() {
        XCTAssertGreaterThan(OfflineQuote.staleOpacity, 0.55, "有了文字说明，不再淡到 55%")
        XCTAssertLessThan(OfflineQuote.staleOpacity, 1)
    }
}
