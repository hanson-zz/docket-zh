import Foundation
import XCTest

/// 多个纪念日卡片的一年时间轴，和单个卡片撕页上的字。
final class AnniversaryAxisTests: XCTestCase {
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

    // 正数日故意不勾“每年”：周年照样算。
    private let together = AnniversaryEvent(id: "t", title: "在一起", day: "20190520", kind: .countup)
    private let birthday = AnniversaryEvent(id: "b", title: "生日", day: "19901030", kind: .countdown, yearly: true)
    private let national = AnniversaryEvent(id: "n", title: "国庆", day: "20271001", kind: .countdown)
    private let gone = AnniversaryEvent(id: "g", title: "过去了", day: "20250101", kind: .countdown)
    private let far = AnniversaryEvent(id: "f", title: "很远", day: "20281001", kind: .countdown)
    private let spring = AnniversaryEvent(id: "s", title: "春节", day: "20260217", kind: .countdown,
                                          yearly: true, lunar: true)

    private func reading(_ event: AnniversaryEvent, _ today: Date) -> AnniversaryReading {
        Anniversary.reading(event, today: today, calendar: calendar)!
    }

    // MARK: Span and fraction

    func testSpanIsAYearIncludingLeapDays() {
        XCTAssertEqual(Anniversary.axisSpan(today: day(2026, 10, 18), calendar: calendar), 365)
        XCTAssertEqual(Anniversary.axisSpan(today: day(2027, 10, 18), calendar: calendar), 366)
    }

    func testFractionIsClampedToTheYear() {
        let today = day(2026, 10, 18)
        XCTAssertEqual(Anniversary.axisFraction(midnight(2026, 10, 18), today: today, calendar: calendar), 0)
        XCTAssertEqual(Anniversary.axisFraction(midnight(2027, 10, 18), today: today, calendar: calendar), 1)
        XCTAssertEqual(Anniversary.axisFraction(midnight(2026, 1, 1), today: today, calendar: calendar), 0)
        XCTAssertEqual(Anniversary.axisFraction(midnight(2030, 1, 1), today: today, calendar: calendar), 1)
        XCTAssertEqual(Anniversary.axisFraction(midnight(2027, 5, 20), today: today, calendar: calendar),
                       214.0 / 365.0, accuracy: 1e-9)
    }

    // MARK: Points

    func testPointsAreTheNextYearNearestFirst() {
        let today = day(2026, 10, 18)
        let points = Anniversary.axisPoints([national, together, gone, far, birthday], today: today,
                                            calendar: calendar)
        XCTAssertEqual(points.map(\.id), ["b", "t", "n"], "past one-offs and anything beyond a year are left off")
        XCTAssertEqual(points.map(\.daysLeft), [12, 214, 348])
        XCTAssertEqual(points[1].date, midnight(2027, 5, 20), "counting up sits on the next anniversary")
        XCTAssertEqual(points[2].fraction, 348.0 / 365.0, accuracy: 1e-9)
    }

    func testAnniversaryTodaySitsAtZero() {
        let today = day(2027, 5, 20)
        let points = Anniversary.axisPoints([together], today: today, calendar: calendar)
        XCTAssertEqual(points.first?.daysLeft, 0)
        XCTAssertEqual(points.first?.fraction, 0)
    }

    func testCountUpNotStartedUsesItsOwnDay() {
        let start = AnniversaryEvent(id: "j", title: "入职", day: "20261201", kind: .countup)
        let points = Anniversary.axisPoints([start], today: day(2026, 10, 18), calendar: calendar)
        XCTAssertEqual(points.first?.date, midnight(2026, 12, 1))
    }

    func testLunarEventUsesItsNextLunarDay() {
        let points = Anniversary.axisPoints([spring], today: day(2026, 10, 18), calendar: calendar)
        XCTAssertEqual(points.first?.date, midnight(2027, 2, 6), "正月初一 2027 is 6 February")
    }

    // MARK: Ticks

    func testTicksAreEachFirstOfTheMonth() {
        let ticks = Anniversary.axisTicks(today: day(2026, 10, 18), calendar: calendar)
        XCTAssertEqual(ticks.count, 12)
        XCTAssertEqual(ticks.first?.month, 11)
        XCTAssertEqual(ticks.first?.fraction ?? 0, 14.0 / 365.0, accuracy: 1e-9)
        XCTAssertEqual(ticks.last?.month, 10)
        XCTAssertEqual(ticks.map(\.fraction), ticks.map(\.fraction).sorted())
    }

    func testTicksIncludeTodayWhenItIsTheFirst() {
        let ticks = Anniversary.axisTicks(today: day(2026, 11, 1), calendar: calendar)
        XCTAssertEqual(ticks.first?.fraction, 0)
        XCTAssertEqual(ticks.last?.fraction, 1)
        XCTAssertEqual(ticks.count, 13)
    }

    // MARK: Labels

    func testLabelsThatClashAreDropped() {
        let placed = Anniversary.placeLabels(centers: [10, 15, 100], widths: [20, 20, 20], total: 120)
        XCTAssertEqual(placed[0], 10)
        XCTAssertNil(placed[1])
        XCTAssertEqual(placed[2], 100)
    }

    func testLabelsAreKeptInsideTheAxis() {
        let placed = Anniversary.placeLabels(centers: [2, 118], widths: [20, 20], total: 120)
        XCTAssertEqual(placed, [10, 110])
    }

    func testOrderDecidesWhoKeepsTheLabel() {
        let placed = Anniversary.placeLabels(centers: [10, 15], widths: [20, 20], total: 120, order: [1, 0])
        XCTAssertNil(placed[0])
        XCTAssertEqual(placed[1], 15)
    }

    func testMismatchedInputPlacesNothing() {
        XCTAssertEqual(Anniversary.placeLabels(centers: [1, 2], widths: [1], total: 10), [nil, nil])
    }

    // MARK: Hit testing

    func testNearestPointWithinRadius() {
        let centers = [10.0, 40, 44]
        XCTAssertEqual(Anniversary.nearestPoint(to: 12, centers: centers, radius: 8), 0)
        XCTAssertEqual(Anniversary.nearestPoint(to: 43, centers: centers, radius: 8), 2)
        XCTAssertEqual(Anniversary.nearestPoint(to: 42, centers: centers, radius: 8), 1, "a tie goes to the first")
        XCTAssertNil(Anniversary.nearestPoint(to: 25, centers: centers, radius: 8), "blank space opens the timeline")
        XCTAssertNil(Anniversary.nearestPoint(to: 5, centers: [], radius: 8))
    }

    func testHitZonesSplitBetweenNeighbours() {
        let zones = Anniversary.hitZones(centers: [10, 40, 44], radius: 8)
        XCTAssertEqual(zones[0], 2...18)
        XCTAssertEqual(zones[1], 32...42)
        XCTAssertEqual(zones[2], 42...52)
        for x in stride(from: 0.0, through: 60, by: 0.5) {
            let hit = Anniversary.nearestPoint(to: x, centers: [10, 40, 44], radius: 8) != nil
            XCTAssertEqual(hit, zones.contains { $0.contains(x) }, "x \(x)")
        }
    }

    // MARK: Single card text

    func testCountUpLineSaysTheYearAndTheNextAnniversary() {
        let today = day(2026, 10, 18)
        XCTAssertEqual(Anniversary.tileLine(reading(together, today), today: today, calendar: calendar),
                       "第 8 年 · 下个周年 214 天")
        let anniversary = day(2027, 5, 20)
        XCTAssertEqual(Anniversary.tileLine(reading(together, anniversary), today: anniversary, calendar: calendar),
                       "8 周年")
    }

    func testCountdownLineSaysTheWeekday() {
        let today = day(2026, 10, 18)
        XCTAssertEqual(Anniversary.tileLine(reading(birthday, today), today: today, calendar: calendar), "周五 · 每年")
        XCTAssertEqual(Anniversary.tileLine(reading(national, today), today: today, calendar: calendar), "周五 · 2027年")
        XCTAssertEqual(Anniversary.tileLine(reading(gone, today), today: today, calendar: calendar), "2025-01-01 · 已过")
    }

    func testLeafShowsTheDayAndMonth() {
        let today = day(2026, 10, 18)
        let solar = Anniversary.leaf(reading(together, today), calendar: calendar)
        XCTAssertEqual(solar.day, "20")
        XCTAssertEqual(solar.month, "5月")
        let lunar = Anniversary.leaf(reading(spring, today), calendar: calendar)
        XCTAssertEqual(lunar.day, "初一")
        XCTAssertEqual(lunar.month, "正月")
        let next = Anniversary.leaf(reading(birthday, today), calendar: calendar)
        XCTAssertEqual(next.day, "30")
        XCTAssertEqual(next.month, "10月")
    }

    // MARK: Sizing

    func testMultiCardIsOneFixedWidth() {
        let widths = (0...12).map { Anniversary.tileWidth(layout: "multi", count: $0) }
        XCTAssertEqual(Set(widths).count, 1, "the axis is the same length however many dates are on it")
        XCTAssertGreaterThan(widths[0], Anniversary.tileWidth(layout: "single", count: 1))
        XCTAssertGreaterThanOrEqual(Anniversary.columnHeight(layout: "single", count: 1), 84)
    }

    func testMonthShortFollowsTheInterfaceLocale() {
        // 测试包没有本地化表，界面语言是简体中文。
        XCTAssertEqual(Anniversary.monthShort(5), "5月")
        XCTAssertEqual(Anniversary.monthShort(12, locale: Locale(identifier: "zh-Hans")), "12月")
        XCTAssertEqual(Anniversary.monthShort(5, locale: Locale(identifier: "en")), "May")
        XCTAssertEqual(Anniversary.monthShort(9, locale: Locale(identifier: "en")), "Sep")
        // 越界的月份夹到 1 到 12。
        XCTAssertEqual(Anniversary.monthShort(13, locale: Locale(identifier: "en")), "Dec")
        XCTAssertEqual(Anniversary.monthShort(0, locale: Locale(identifier: "en")), "Jan")
    }
}
