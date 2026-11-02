import XCTest
@testable import Docket

/// 每日一签和黄历用同一个日期来源（Core 的 `Divination.calendar`，北京时间）：Mac 设在别的
/// 时区时两边不再差一天，一个北京日内签不变，北京时间零点才换。
final class DivinationDateSourceTests: XCTestCase {

    private func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    func testCalendarIsBeijing() {
        XCTAssertEqual(Divination.calendar.identifier, .gregorian)
        XCTAssertEqual(Divination.calendar.timeZone, ChineseCalendar.zone)
        XCTAssertEqual(Divination.calendar.timeZone.identifier, "Asia/Shanghai")
        XCTAssertEqual(Divination.monthCalendar.timeZone, ChineseCalendar.zone)
        XCTAssertEqual(Divination.monthCalendar.firstWeekday, 2, "签历月历周一开头")
    }

    /// 北京已经过了零点、纽约还是前一天下午：签的日子和黄历的日子都是北京那天。
    func testStickDayMatchesAlmanacDay() throws {
        // 北京 2026-10-30 01:30，纽约 2026-10-29 13:30。
        let moment = date("2026-10-29T17:30:00Z")
        XCTAssertEqual(Divination.dayKey(moment), "2026-10-30")
        let beijingDay = try XCTUnwrap(ChineseCalendar.day("2026-10-30"))
        XCTAssertEqual(ChineseAlmanac.day(moment), ChineseAlmanac.day(beijingDay))
        XCTAssertEqual(ChineseAlmanac.day(moment).lunar,
                       ChineseAlmanac.day(try XCTUnwrap(Divination.date(fromDay: Divination.dayKey(moment)))).lunar)
    }

    /// 本机时区换成别处，默认的签日子照样按北京时间。
    func testDayKeyIgnoresMacTimeZone() {
        let saved = NSTimeZone.default
        defer { NSTimeZone.default = saved }
        let moment = date("2026-10-29T17:30:00Z")
        for zone in ["America/New_York", "America/Los_Angeles", "Europe/London", "Asia/Tokyo", "Pacific/Auckland"] {
            NSTimeZone.default = TimeZone(identifier: zone)!
            XCTAssertEqual(Divination.dayKey(moment), "2026-10-30", zone)
            XCTAssertEqual(Divination.calendar.timeZone.identifier, "Asia/Shanghai", zone)
        }
    }

    /// 一个北京日之内签不变（不管中间纽约换没换日子），北京零点以后才能抽新的一支。
    func testStickStaysForOneBeijingDay() {
        var config = WidgetConfig()
        let earlyMorning = date("2026-10-29T16:05:00Z")   // 北京 10-30 00:05（纽约 10-29 12:05）
        let lateNight = date("2026-10-30T15:55:00Z")      // 北京 10-30 23:55（纽约 10-30 11:55）
        let nextDay = date("2026-10-30T16:05:00Z")        // 北京 10-31 00:05
        let first = Divination.drawStick(in: &config, now: earlyMorning, salt: "card")
        XCTAssertTrue(first.isNew)
        XCTAssertEqual(Divination.todayStick(config, now: lateNight), first.index)
        let again = Divination.drawStick(in: &config, now: lateNight, salt: "card")
        XCTAssertFalse(again.isNew)
        XCTAssertEqual(again.index, first.index)
        XCTAssertNil(Divination.todayStick(config, now: nextDay))
        XCTAssertEqual(Divination.stickLog(config)["2026-10-30"], first.index)
    }

    /// 签卡上的日期和黄历同一天。
    func testShareCardDateUsesSameDay() {
        let moment = date("2026-10-29T17:30:00Z")
        let text = DivinationShareCard.dateText(day: Divination.dayKey(moment), locale: Locale(identifier: "en_US"))
        XCTAssertTrue(text.contains("30"), text)
        XCTAssertTrue(text.contains("Friday"), text)
    }
}
