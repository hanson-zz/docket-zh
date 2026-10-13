import Foundation
import XCTest

final class AnniversaryTests: XCTestCase {
    /// Fixed to China so the lunar dates below are the almanac's.
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

    private func reading(_ event: AnniversaryEvent, _ today: Date) -> AnniversaryReading {
        Anniversary.reading(event, today: today, calendar: calendar)!
    }

    // MARK: Encoding

    func testEncodingRoundTrips() {
        var config = WidgetConfig()
        let events = [
            AnniversaryEvent(id: "a", title: "春节", day: "20260217", kind: .countdown,
                             yearly: true, lunar: true, color: .green),
            AnniversaryEvent(id: "b", title: "入职时间", day: "20221021", kind: .countup),
            AnniversaryEvent(id: "c", title: "元旦", day: "20270101", yearly: true, color: .blue),
        ]
        Anniversary.store(events, in: &config)
        XCTAssertEqual(Anniversary.events(config), events)
        XCTAssertEqual(config.strings(Anniversary.key).first, "a\t春节\t20260217\tyl\tgreen")
    }

    func testDecodingIsTolerant() {
        let config = WidgetConfig([Anniversary.key: .list([
            .string("x\t生日\t19900101"),                 // no flags, no colour
            .string("x\t  \t20260101\t\t"),               // no title: dropped
            .string("y\t坏日期\t2026-01-01\t\t"),          // no date: dropped
            .string("z\t纪念\t20260230\tuy\tnot-a-colour"), // impossible day is still a key
            .string("\t无编号\t20261001\ty\tred"),
            .string("just a string"),
        ])])
        let read = Anniversary.events(config)
        XCTAssertEqual(read.map(\.title), ["生日", "纪念", "无编号"])
        XCTAssertEqual(read[0].kind, .countdown)
        XCTAssertFalse(read[0].yearly)
        XCTAssertEqual(read[1].kind, .countup)
        XCTAssertTrue(read[1].yearly)
        XCTAssertNil(read[1].color, "an unknown colour is dropped, not the event")
        XCTAssertEqual(read[2].color, .red)
        XCTAssertEqual(Set(read.map(\.id)).count, 3, "duplicate and missing ids must be made unique")
    }

    func testSavingCleansTitlesAndCaps() {
        var events: [AnniversaryEvent] = []
        events = Anniversary.saving(AnniversaryEvent(id: "a", title: "  在一起\n纪念\t日  ", day: "20200520"), in: events)
        XCTAssertEqual(events.first?.title, "在一起 纪念 日")
        events = Anniversary.saving(AnniversaryEvent(id: "b", title: "   ", day: "20200520"), in: events)
        XCTAssertEqual(events.count, 1, "an empty title adds nothing")
        events = Anniversary.saving(AnniversaryEvent(id: "c", title: "x", day: "bad"), in: events)
        XCTAssertEqual(events.count, 1, "a bad date adds nothing")

        let long = String(repeating: "长", count: 40)
        events = Anniversary.saving(AnniversaryEvent(id: "a", title: long, day: "20200520"), in: events)
        XCTAssertEqual(events.count, 1, "the same id is replaced, not added")
        XCTAssertEqual(events[0].title.count, Anniversary.maxTitleLength)

        for i in 0..<20 {
            events = Anniversary.saving(AnniversaryEvent(id: "n\(i)", title: "第\(i)个", day: "20260101"), in: events)
        }
        XCTAssertEqual(events.count, Anniversary.maxEvents)
        XCTAssertEqual(Anniversary.removing("a", from: events).count, Anniversary.maxEvents - 1)
    }

    func testPinnedIsClearedWithItsEvent() {
        var config = WidgetConfig()
        let events = [AnniversaryEvent(id: "a", title: "甲", day: "20260101"),
                      AnniversaryEvent(id: "b", title: "乙", day: "20260102")]
        Anniversary.store(events, in: &config)
        Anniversary.pin("b", in: &config)
        XCTAssertEqual(Anniversary.pinnedID(config), "b")
        Anniversary.store(Anniversary.removing("b", from: events), in: &config)
        XCTAssertNil(Anniversary.pinnedID(config))
    }

    // MARK: Next occurrence

    func testSolarYearlyNextOccurrence() {
        let newYear = AnniversaryEvent(title: "元旦", day: "20250101", yearly: true)
        XCTAssertEqual(Anniversary.nextOccurrence(newYear, today: day(2026, 10, 14), calendar: calendar),
                       midnight(2027, 1, 1))
        XCTAssertEqual(Anniversary.nextOccurrence(newYear, today: day(2027, 1, 1, hour: 23), calendar: calendar),
                       midnight(2027, 1, 1), "today counts as the next occurrence")

        let once = AnniversaryEvent(title: "考试", day: "20261001")
        XCTAssertNil(Anniversary.nextOccurrence(once, today: day(2026, 10, 14), calendar: calendar))
        XCTAssertEqual(Anniversary.nextOccurrence(once, today: day(2026, 9, 1), calendar: calendar),
                       midnight(2026, 10, 1))

        let future = AnniversaryEvent(title: "婚礼", day: "20280501", yearly: true)
        XCTAssertEqual(Anniversary.nextOccurrence(future, today: day(2026, 10, 14), calendar: calendar),
                       midnight(2028, 5, 1), "a yearly event set ahead first counts to its own day")
    }

    func testLeapDayFallsOnTheTwentyEighth() {
        let leap = AnniversaryEvent(title: "生日", day: "20240229", yearly: true)
        XCTAssertEqual(Anniversary.nextOccurrence(leap, today: day(2026, 10, 14), calendar: calendar),
                       midnight(2027, 2, 28))
        XCTAssertEqual(Anniversary.nextOccurrence(leap, today: day(2027, 12, 1), calendar: calendar),
                       midnight(2028, 2, 29))

        let up = AnniversaryEvent(title: "生日", day: "20240229", kind: .countup, yearly: true)
        let r = reading(up, day(2026, 3, 1))
        XCTAssertEqual(r.years, 2, "28 Feb 2025 and 28 Feb 2026 each count as a year")
        XCTAssertEqual(r.remainder, 1)
    }

    func testLunarYearlyNextOccurrence() {
        // 春节, picked on 2026-02-17 (丙午年正月初一).
        let spring = AnniversaryEvent(title: "春节", day: "20260217", yearly: true, lunar: true)
        XCTAssertEqual(Anniversary.nextOccurrence(spring, today: day(2026, 10, 14), calendar: calendar),
                       midnight(2027, 2, 6))

        // 中秋 (八月十五), picked in 2026.
        let moon = AnniversaryEvent(title: "中秋", day: "20260925", yearly: true, lunar: true)
        XCTAssertEqual(Anniversary.nextOccurrence(moon, today: day(2026, 10, 14), calendar: calendar),
                       midnight(2027, 9, 15))
        XCTAssertEqual(Anniversary.nextOccurrence(moon, today: day(2026, 9, 25), calendar: calendar),
                       midnight(2026, 9, 25))
    }

    func testLunarThirtiethFallsBackToTheTwentyNinth() {
        // 除夕 2024 was 腊月三十; the 腊月 of the year starting 2025 has 29 days.
        let eve = AnniversaryEvent(title: "除夕", day: "20240209", yearly: true, lunar: true)
        XCTAssertEqual(Anniversary.occurrence(eve, year: 2025, calendar: calendar), midnight(2026, 2, 16))
        XCTAssertEqual(Anniversary.nextOccurrence(eve, today: day(2025, 10, 1), calendar: calendar),
                       midnight(2026, 2, 16))
    }

    func testLunarLeapMonthRepeatsInTheOrdinaryMonth() {
        // 2025-08-01 was 闰六月初八.
        let leap = AnniversaryEvent(title: "生日", day: "20250801", yearly: true, lunar: true)
        let parts = Anniversary.lunarParts(midnight(2025, 8, 1), calendar: calendar)
        XCTAssertEqual(parts.month, 6)
        XCTAssertEqual(parts.day, 8)
        XCTAssertTrue(parts.isLeap)
        XCTAssertEqual(Anniversary.nextOccurrence(leap, today: day(2025, 9, 1), calendar: calendar),
                       midnight(2026, 7, 21))
        XCTAssertEqual(Anniversary.nextOccurrence(leap, today: day(2026, 10, 14), calendar: calendar),
                       midnight(2027, 7, 11))
    }

    func testLunarText() {
        XCTAssertEqual(Anniversary.lunarText(midnight(2027, 2, 6), calendar: calendar), "丁未年正月初一")
        XCTAssertEqual(Anniversary.lunarShort(midnight(2026, 10, 1), calendar: calendar), "八月廿一")
        XCTAssertEqual(Anniversary.lunarShort(midnight(2025, 8, 1), calendar: calendar), "闰六月初八")
        XCTAssertEqual(Anniversary.solarDate(lunarMonth: 8, day: 15, inLunarYearOf: midnight(2026, 5, 1),
                                             calendar: calendar), midnight(2026, 9, 25))
    }

    // MARK: Counting

    func testCountDown() {
        let spring = AnniversaryEvent(title: "春节", day: "20260217", yearly: true, lunar: true)
        let r = reading(spring, day(2026, 10, 14))
        XCTAssertEqual(r.phase, .upcoming)
        XCTAssertEqual(r.days, 115)
        XCTAssertEqual(r.sentence, "还有 115 天")
        XCTAssertEqual(r.progress, 1 - 115.0 / 354.0, accuracy: 1e-9,
                       "through the 354 days from last 春节 to the next")

        let past = AnniversaryEvent(title: "国庆节", day: "20261001")
        let p = reading(past, day(2026, 10, 14))
        XCTAssertEqual(p.phase, .past)
        XCTAssertEqual(p.days, 13)
        XCTAssertEqual(p.sentence, "已经 13 天")
        XCTAssertEqual(p.progress, 1)

        let once = AnniversaryEvent(title: "考试", day: "20261203")
        let o = reading(once, day(2026, 10, 14))
        XCTAssertEqual(o.days, 50)
        XCTAssertEqual(o.progress, 1 - 50.0 / 365.0, accuracy: 1e-9, "a one-off counts out of a year")
    }

    func testCountUp() {
        let job = AnniversaryEvent(title: "入职时间", day: "20221021", kind: .countup, yearly: true)
        let r = reading(job, day(2026, 10, 14))
        XCTAssertEqual(r.phase, .past)
        XCTAssertEqual(r.days, 1454)
        XCTAssertEqual(r.years, 3)
        XCTAssertEqual(r.remainder, 358)
        XCTAssertEqual(r.progress, 358.0 / 365.0, accuracy: 1e-9, "since the last anniversary")
        XCTAssertEqual(r.sentence, "已经 1454 天")
        XCTAssertFalse(r.isToday)

        let anniversary = reading(job, day(2026, 10, 21))
        XCTAssertTrue(anniversary.isToday, "a yearly anniversary is today's highlight")
        XCTAssertEqual(anniversary.anniversaryNote, "4 周年")
        XCTAssertEqual(anniversary.remainder, 0)

        let ahead = AnniversaryEvent(title: "入学", day: "20261101", kind: .countup)
        let a = reading(ahead, day(2026, 10, 14))
        XCTAssertEqual(a.phase, .upcoming, "counting up from a day not yet come counts down to it")
        XCTAssertEqual(a.days, 18)
    }

    func testToday() {
        let birthday = AnniversaryEvent(title: "生日", day: "19900520", yearly: true)
        let r = reading(birthday, day(2026, 5, 20, hour: 0))
        XCTAssertEqual(r.phase, .today)
        XCTAssertTrue(r.isToday)
        XCTAssertEqual(r.days, 0)
        XCTAssertEqual(r.sentence, "就是今天")
        XCTAssertEqual(reading(birthday, day(2026, 5, 20, hour: 23)).phase, .today, "counted by local day")
        XCTAssertEqual(reading(birthday, day(2026, 5, 19, hour: 23)).days, 1)

        let start = AnniversaryEvent(title: "在一起", day: "20261014", kind: .countup)
        XCTAssertEqual(reading(start, day(2026, 10, 14)).phase, .today)
    }

    // MARK: Ordering

    func testListOrderAndFeatured() {
        let today = day(2026, 10, 14)
        let events = [
            AnniversaryEvent(id: "job", title: "入职", day: "20221021", kind: .countup),
            AnniversaryEvent(id: "spring", title: "春节", day: "20260217", yearly: true, lunar: true),
            AnniversaryEvent(id: "new", title: "元旦", day: "20260101", yearly: true),
            AnniversaryEvent(id: "now", title: "今天", day: "20261014"),
        ]
        let order = Anniversary.readings(events, today: today, calendar: calendar).map(\.event.id)
        XCTAssertEqual(order, ["now", "new", "spring", "job"])

        XCTAssertEqual(Anniversary.featured(events, pinned: nil, today: today, calendar: calendar)?.event.id, "now")
        XCTAssertEqual(Anniversary.featured(events, pinned: "job", today: today, calendar: calendar)?.event.id, "job")
        XCTAssertEqual(Anniversary.featured(events, pinned: "gone", today: today, calendar: calendar)?.event.id, "now")
        XCTAssertNil(Anniversary.featured([], pinned: nil, today: today, calendar: calendar))
    }

    func testTimelineSplitsAtToday() {
        let today = day(2026, 10, 14)
        let events = [
            AnniversaryEvent(id: "job", title: "入职", day: "20221021", kind: .countup, yearly: true),
            AnniversaryEvent(id: "national", title: "国庆节", day: "20261001"),
            AnniversaryEvent(id: "spring", title: "春节", day: "20260217", yearly: true, lunar: true),
            AnniversaryEvent(id: "new", title: "元旦", day: "20260101", yearly: true),
            AnniversaryEvent(id: "solstice", title: "冬至", day: "20261221"),
        ]
        let line = Anniversary.timeline(events, today: today, calendar: calendar)
        XCTAssertEqual(line.future.map(\.event.id), ["spring", "new", "solstice"], "latest first, like the design")
        XCTAssertEqual(line.past.map(\.event.id), ["national", "job"])
    }

    func testSoonCondition() {
        var config = WidgetConfig()
        Anniversary.store([AnniversaryEvent(title: "生日", day: "19900520", yearly: true)], in: &config)
        XCTAssertTrue(Anniversary.hasSoon(config, today: day(2026, 5, 13), calendar: calendar))
        XCTAssertTrue(Anniversary.hasSoon(config, today: day(2026, 5, 20), calendar: calendar))
        XCTAssertFalse(Anniversary.hasSoon(config, today: day(2026, 5, 12), calendar: calendar))
        XCTAssertFalse(Anniversary.hasSoon(WidgetConfig(), today: day(2026, 5, 12), calendar: calendar))
        XCTAssertTrue(WidgetVisibility.supportsCondition(.anniversary))
        XCTAssertEqual(WidgetVisibility.conditionTitle(.anniversary, config: config), "7 天内有纪念日时显示")
    }

    // MARK: Catalog

    func testCatalogEntryAndSizes() {
        let entry = WidgetCatalog.entry(.anniversary)
        XCTAssertEqual(entry?.name, "纪念日")
        XCTAssertEqual(entry?.category, .reminders)
        var widget = WidgetCatalog.make(.anniversary)!
        XCTAssertEqual(widget.config.string("layout"), "single")
        XCTAssertGreaterThanOrEqual(WidgetCatalog.verticalHeight(widget), 76)
        widget.config.set("layout", .string("multi"))
        XCTAssertGreaterThanOrEqual(WidgetCatalog.verticalHeight(widget), 76)
        XCTAssertEqual(WidgetCatalog.variantTitle(matching: widget.config, kind: .anniversary), "多个")
        XCTAssertGreaterThan(WidgetCatalog.naturalSize(widget).width, 140)
    }
}
