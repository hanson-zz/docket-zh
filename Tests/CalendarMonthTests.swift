import Foundation
import XCTest
@testable import Docket

/// 日历面板的外观设置（`CalendarLook`）和月历（`MonthGrid`）。时刻按上海时区，周一开头。
final class CalendarMonthTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func entry(_ id: String, color: String = "") -> WeekEntry {
        WeekEntry(id: id, title: id, start: at(2026, 10, 22, 9), end: at(2026, 10, 22, 10), colorHex: color)
    }

    // MARK: 设置

    func testDefaultsHighlightWeekendWithOutlineAndColouredDots() {
        let look = CalendarLook(WidgetConfig())
        XCTAssertEqual(look.highlighted, [5, 6])
        XCTAssertTrue(look.outline)
        XCTAssertTrue(look.dots)
        XCTAssertTrue(look.colorDots)
        XCTAssertFalse(look.weekNumbers)
        XCTAssertEqual(look, CalendarLook())
        // 2026-10-24 周六、10-25 周日突出，10-23 周五不突出。
        XCTAssertTrue(look.isHighlighted(at(2026, 10, 24), calendar: calendar))
        XCTAssertTrue(look.isHighlighted(at(2026, 10, 25, 23), calendar: calendar))
        XCTAssertFalse(look.isHighlighted(at(2026, 10, 23), calendar: calendar))
    }

    func testCatalogDefaultsMatchTheLook() {
        for kind in [WidgetKind.calendar, .week] {
            let defaults = WidgetCatalog.entry(kind)!.defaults
            XCTAssertEqual(CalendarLook(defaults), CalendarLook(), "\(kind)")
        }
    }

    func testStoredHighlightDaysAndUnknownValues() {
        let config = WidgetConfig([CalendarLook.highlightKey: .list([.string("1"), .string("3"), .string("9"), .string("x")]),
                                   CalendarLook.weekNumbersKey: .bool(true)])
        let look = CalendarLook(config)
        XCTAssertEqual(look.highlighted, [0, 2])
        XCTAssertTrue(look.weekNumbers)
        XCTAssertTrue(look.isHighlighted(at(2026, 10, 19), calendar: calendar))  // 周一
        XCTAssertFalse(look.isHighlighted(at(2026, 10, 24), calendar: calendar)) // 周六
        // 一个都不勾就是都不突出。
        let none = CalendarLook(WidgetConfig([CalendarLook.highlightKey: .list([])]))
        XCTAssertTrue(none.highlighted.isEmpty)
        XCTAssertEqual(CalendarLook.weekdayChoices.map(\.value), ["1", "2", "3", "4", "5", "6", "7"])
    }

    func testColourDotsOnlyOfferedWhileDotsAreOn() {
        for kind in [WidgetKind.calendar, .week] {
            XCTAssertTrue(WidgetCatalog.applies(CalendarLook.colorDotsKey, to: WidgetConfig(), kind: kind))
            XCTAssertFalse(WidgetCatalog.applies(CalendarLook.colorDotsKey,
                                                 to: WidgetConfig([CalendarLook.dotsKey: .bool(false)]), kind: kind))
            XCTAssertTrue(WidgetCatalog.applies(CalendarLook.highlightKey, to: WidgetConfig(), kind: kind))
        }
    }

    func testDotsAreCappedColouredOrPlain() {
        let entries = [entry("a", color: "#FF0000"), entry("b"), entry("c", color: "#00FF00"), entry("d", color: "#0000FF")]
        XCTAssertEqual(CalendarLook().dots(for: entries), [.color("#FF0000"), .color(""), .color("#00FF00")])
        XCTAssertEqual(CalendarLook(colorDots: false).dots(for: entries), [.plain, .plain, .plain])
        XCTAssertEqual(CalendarLook(dots: false).dots(for: entries), [])
        XCTAssertEqual(CalendarLook().dots(for: [entry("a")]), [.color("")])
        XCTAssertEqual(CalendarLook().dots(for: []), [])
    }

    // MARK: 月历

    func testOctober2026Grid() {
        // 10 月 1 日周四，31 日周六：5 行，前面补 9 月 28 到 30 日，后面补 11 月 1 日。
        let weeks = MonthGrid.weeks(at(2026, 10, 15), now: at(2026, 10, 22, 13), calendar: calendar)
        XCTAssertEqual(weeks.count, 5)
        XCTAssertEqual(weeks.first?.days.first?.date, at(2026, 9, 28))
        XCTAssertEqual(weeks.last?.days.last?.date, at(2026, 11, 1))
        XCTAssertEqual(weeks.first?.days.prefix(3).map(\.inMonth), [false, false, false])
        XCTAssertEqual(weeks.first?.days[3].inMonth, true)
        XCTAssertEqual(weeks.last?.days.last?.inMonth, false)
        XCTAssertEqual(weeks.flatMap(\.days).filter(\.isToday).map(\.date), [at(2026, 10, 22)])
        XCTAssertEqual(weeks.map(\.number), [40, 41, 42, 43, 44])
        XCTAssertEqual(MonthGrid.interval(at(2026, 10, 15), calendar: calendar),
                       DateInterval(start: at(2026, 9, 28), end: at(2026, 11, 2)))
    }

    func testFebruaryStartingMondayIsFourRowsAndAMonthNeedsSix() {
        // 2027 年 2 月 1 日周一，28 天：正好 4 行。
        let feb = MonthGrid.weeks(at(2027, 2, 10), now: at(2026, 10, 22), calendar: calendar)
        XCTAssertEqual(feb.count, 4)
        XCTAssertTrue(feb.allSatisfy { $0.days.allSatisfy(\.inMonth) })
        // 2026 年 8 月 1 日周六，31 天：6 行。
        XCTAssertEqual(MonthGrid.weeks(at(2026, 8, 1), now: at(2026, 10, 22), calendar: calendar).count, 6)
    }

    func testISOWeekNumbersAcrossTheYearEnd() {
        // 2026 年 1 月 1 日周四，所以 2026 有第 53 周；2027-01-04 周一是第 1 周。
        XCTAssertEqual(MonthGrid.isoWeek(at(2026, 12, 28), calendar: calendar), 53)
        XCTAssertEqual(MonthGrid.isoWeek(at(2027, 1, 3), calendar: calendar), 53)
        XCTAssertEqual(MonthGrid.isoWeek(at(2027, 1, 4), calendar: calendar), 1)
        let january = MonthGrid.weeks(at(2027, 1, 1), now: at(2026, 10, 22), calendar: calendar)
        XCTAssertEqual(january.first?.number, 53)
        XCTAssertEqual(january.dropFirst().first?.number, 1)
    }

    func testShiftAndTitle() {
        XCTAssertEqual(MonthGrid.shift(at(2026, 12, 20), by: 1, calendar: calendar), at(2027, 1, 1))
        XCTAssertEqual(MonthGrid.shift(at(2026, 3, 31), by: -1, calendar: calendar), at(2026, 2, 1))
        XCTAssertEqual(MonthGrid.monthStart(at(2026, 10, 22, 13), calendar: calendar), at(2026, 10, 1))
        XCTAssertEqual(MonthGrid.title(at(2026, 10, 22), english: false, calendar: calendar), "2026 年 10 月")
        XCTAssertEqual(MonthGrid.title(at(2026, 10, 22), english: true, calendar: calendar), "October 2026")
        XCTAssertEqual(MonthGrid.dayTitle(at(2026, 10, 23), english: false, calendar: calendar), "10 月 23 日 周五")
        XCTAssertEqual(MonthGrid.dayTitle(at(2026, 10, 25), english: true, calendar: calendar), "Sun, Oct 25")
    }

    func testOutlineFollowsTheMonthsCells() {
        func pts(_ weeks: [MonthGrid.Week]) -> [[Int]] { MonthGrid.outline(weeks).map { [$0.x, $0.y] } }
        // 10 月：从第 4 列开始，最后一行到第 6 列（周六）为止。
        let october = MonthGrid.weeks(at(2026, 10, 1), now: at(2026, 10, 22), calendar: calendar)
        XCTAssertEqual(pts(october), [[3, 0], [7, 0], [7, 4], [6, 4], [6, 5], [0, 5], [0, 1], [3, 1]])
        // 2027 年 2 月整整 4 行：一个矩形。
        let feb = MonthGrid.weeks(at(2027, 2, 1), now: at(2026, 10, 22), calendar: calendar)
        XCTAssertEqual(pts(feb), [[0, 0], [7, 0], [7, 4], [0, 4]])
        // 2026 年 5 月 31 日是周日：右下角不缺；5 月 1 日周五。
        let may = MonthGrid.weeks(at(2026, 5, 1), now: at(2026, 10, 22), calendar: calendar)
        XCTAssertEqual(pts(may), [[4, 0], [7, 0], [7, may.count], [0, may.count], [0, 1], [4, 1]])
        XCTAssertTrue(MonthGrid.outline([]).isEmpty)
    }
}
