import Foundation
import XCTest

final class WeekAgendaTests: XCTestCase {
    private let calendar = WeekAgenda.calendar

    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private func entry(_ id: String, _ start: Date, _ end: Date, allDay: Bool = false,
                       color: String = "") -> WeekEntry {
        WeekEntry(id: id, title: id, start: start, end: end, isAllDay: allDay, colorHex: color)
    }

    func testWeekStartsOnMondayWhateverTheDay() {
        // 12 October 2026 is a Monday.
        let monday = at(2026, 10, 12)
        XCTAssertEqual(WeekAgenda.weekStart(at(2026, 10, 12, 9), calendar: calendar), monday)
        XCTAssertEqual(WeekAgenda.weekStart(at(2026, 10, 14, 23, 59), calendar: calendar), monday)
        // Sunday belongs to the week that began the Monday before, not the next.
        XCTAssertEqual(WeekAgenda.weekStart(at(2026, 10, 18, 22), calendar: calendar), monday)
        let span = WeekAgenda.interval(at(2026, 10, 15), calendar: calendar)
        XCTAssertEqual(span.start, monday)
        XCTAssertEqual(span.end, at(2026, 10, 19))
    }

    func testEventsLandOnTheirDaysInOrder() {
        let now = at(2026, 10, 14, 9)
        let days = WeekAgenda.days([
            entry("b", at(2026, 10, 14, 15), at(2026, 10, 14, 16)),
            entry("a", at(2026, 10, 14, 10), at(2026, 10, 14, 11)),
            entry("all", at(2026, 10, 14), at(2026, 10, 15), allDay: true),
            entry("fri", at(2026, 10, 16, 9), at(2026, 10, 16, 10)),
            entry("lastweek", at(2026, 10, 9, 9), at(2026, 10, 9, 10)),
            entry("nextweek", at(2026, 10, 19, 9), at(2026, 10, 19, 10)),
        ], now: now, calendar: calendar)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.map(\.index), Array(0..<7))
        XCTAssertEqual(days.map(\.isToday), [false, false, true, false, false, false, false])
        XCTAssertEqual(days[2].entries.map(\.id), ["a", "b", "all"], "timed first, all-day last")
        XCTAssertEqual(days[4].entries.map(\.id), ["fri"])
        XCTAssertEqual(days.map(\.count), [0, 0, 3, 0, 1, 0, 0])
        XCTAssertEqual(WeekAgenda.total(days), 4)
    }

    func testAllDayCanBeLeftOut() {
        let now = at(2026, 10, 14, 9)
        let days = WeekAgenda.days([entry("all", at(2026, 10, 14), at(2026, 10, 15), allDay: true)],
                                   now: now, includeAllDay: false, calendar: calendar)
        XCTAssertEqual(WeekAgenda.total(days), 0)
    }

    func testOvernightAndMidnightEdges() {
        let now = at(2026, 10, 12, 9)
        let days = WeekAgenda.days([
            // Across midnight: on both days, counted once in the total.
            entry("overnight", at(2026, 10, 13, 22), at(2026, 10, 14, 2)),
            // Ends exactly at midnight: Tuesday only.
            entry("tomidnight", at(2026, 10, 13, 20), at(2026, 10, 14)),
            // Zero length: the day it starts.
            entry("instant", at(2026, 10, 15, 8), at(2026, 10, 15, 8)),
            // Began last week, ends Monday morning: Monday only.
            entry("spill", at(2026, 10, 11, 23), at(2026, 10, 12, 1)),
        ], now: now, calendar: calendar)
        XCTAssertEqual(days[0].entries.map(\.id), ["spill"])
        XCTAssertEqual(days[1].entries.map(\.id), ["tomidnight", "overnight"])
        XCTAssertEqual(days[2].entries.map(\.id), ["overnight"])
        XCTAssertEqual(days[3].entries.map(\.id), ["instant"])
        XCTAssertEqual(WeekAgenda.total(days), 4)
    }

    func testMultiDayAllDayEventSpansItsDays() {
        let now = at(2026, 10, 12, 9)
        let days = WeekAgenda.days([entry("trip", at(2026, 10, 16), at(2026, 10, 19), allDay: true)],
                                   now: now, calendar: calendar)
        XCTAssertEqual(days.map(\.count), [0, 0, 0, 0, 1, 1, 1])
    }

    func testFillScalesAgainstTheBusiestDay() {
        XCTAssertEqual(WeekAgenda.fill(count: 0, busiest: 5), 0)
        XCTAssertEqual(WeekAgenda.fill(count: 5, busiest: 5), 1)
        XCTAssertEqual(WeekAgenda.fill(count: 1, busiest: 10), 0.2, "never a sliver")
        XCTAssertEqual(WeekAgenda.fill(count: 3, busiest: 0), 0)
    }

    func testBarsTurnIntoACountWhenBusy() {
        let now = at(2026, 10, 12, 9)
        let five = (0..<5).map { entry("e\($0)", at(2026, 10, 12, 9 + $0), at(2026, 10, 12, 10 + $0), color: "#00000\($0)") }
        let day = WeekAgenda.days(five, now: now, calendar: calendar)[0]
        let marks = WeekAgenda.bars(day)
        XCTAssertEqual(marks.colors, ["#000000", "#000001"])
        XCTAssertEqual(marks.more, 3)
        let few = WeekAgenda.days(Array(five.prefix(3)), now: now, calendar: calendar)[0]
        XCTAssertEqual(WeekAgenda.bars(few).colors.count, 3)
        XCTAssertEqual(WeekAgenda.bars(few).more, 0)
    }

    func testTitles() {
        XCTAssertEqual(WeekAgenda.rangeTitle(at(2026, 10, 14), calendar: calendar), "10月12日至18日")
        XCTAssertEqual(WeekAgenda.rangeTitle(at(2026, 10, 1), calendar: calendar), "9月28日至10月4日")
        let days = WeekAgenda.days([], now: at(2026, 10, 14, 9), calendar: calendar)
        XCTAssertEqual(days.map(WeekAgenda.dayTitle), ["周一", "周二", "今天", "周四", "周五", "周六", "周日"])
    }

    func testCatalogSizes() {
        let instance = WidgetCatalog.make(.week)!
        XCTAssertEqual(WidgetCatalog.contentSize(instance, position: .bottom).height, 58)
        XCTAssertEqual(WidgetCatalog.contentSize(instance, position: .left).width, WidgetCatalog.columnWidth)
        XCTAssertGreaterThanOrEqual(WidgetCatalog.verticalHeight(instance), 7 * 14)
        XCTAssertEqual(WidgetCatalog.openTarget(.week), .app(bundleID: "com.apple.iCal"))
    }
}
