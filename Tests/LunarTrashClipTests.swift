import XCTest
@testable import Docket

private func cn(_ key: String, hour: Int = 9) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = ChineseCalendar.zone
    let day = ChineseCalendar.day(key)!
    return calendar.date(byAdding: .hour, value: hour, to: day)!
}

final class ChineseCalendarTests: XCTestCase {
    func testLunarDateOfKnownDays() {
        // 2026-02-17 is 春节, the first day of 丙午 (马) year.
        let newYear = ChineseCalendar.lunar(cn("2026-02-17"))
        XCTAssertEqual(newYear.month, 1)
        XCTAssertEqual(newYear.day, 1)
        XCTAssertEqual(newYear.ganzhiYear, "丙午")
        XCTAssertEqual(newYear.zodiac, "马")
        XCTAssertEqual(newYear.short, "正月初一")
        // 2026-09-25 is 中秋, lunar 8-15.
        XCTAssertEqual(ChineseCalendar.lunar(cn("2026-09-25")).short, "八月十五")
    }

    func testDayNames() {
        func name(_ day: Int) -> String {
            ChineseCalendar.LunarDate(cycleYear: 43, month: 9, day: day, isLeapMonth: false).dayName
        }
        XCTAssertEqual(name(1), "初一")
        XCTAssertEqual(name(10), "初十")
        XCTAssertEqual(name(11), "十一")
        XCTAssertEqual(name(20), "二十")
        XCTAssertEqual(name(21), "廿一")
        XCTAssertEqual(name(30), "三十")
        XCTAssertEqual(ChineseCalendar.LunarDate(cycleYear: 43, month: 6, day: 2, isLeapMonth: true).monthName, "闰六月")
        XCTAssertEqual(ChineseCalendar.LunarDate(cycleYear: 43, month: 11, day: 2, isLeapMonth: false).monthName, "冬月")
    }

    func testFestivals() {
        XCTAssertEqual(ChineseCalendar.festival(on: cn("2026-02-16")), "除夕")
        XCTAssertEqual(ChineseCalendar.festival(on: cn("2026-02-17")), "春节")
        XCTAssertEqual(ChineseCalendar.festival(on: cn("2026-09-25")), "中秋节")
        XCTAssertNil(ChineseCalendar.festival(on: cn("2026-10-13")))
    }

    func testFestivalDaysByYear() {
        XCTAssertEqual(ChineseCalendar.gregorianDay(lunarMonth: 1, day: 1, inGregorianYear: 2026).map(ChineseCalendar.key), "2026-02-17")
        XCTAssertEqual(ChineseCalendar.gregorianDay(lunarMonth: 5, day: 5, inGregorianYear: 2026).map(ChineseCalendar.key), "2026-06-19")
        // 2027 春节 is Feb 6.
        XCTAssertEqual(ChineseCalendar.gregorianDay(lunarMonth: 1, day: 1, inGregorianYear: 2027).map(ChineseCalendar.key), "2027-02-06")
        XCTAssertEqual(ChineseCalendar.newYearsEve(lunarNewYearIn: 2027).map(ChineseCalendar.key), "2027-02-05")
    }

    func testSolarTermsMatchTheAlmanac() {
        let terms = Dictionary(uniqueKeysWithValues: ChineseCalendar.solarTerms(year: 2026).map { ($0.name, ChineseCalendar.key($0.day)) })
        XCTAssertEqual(terms.count, 24)
        XCTAssertEqual(terms["小寒"], "2026-01-05")
        XCTAssertEqual(terms["立春"], "2026-02-04")
        XCTAssertEqual(terms["清明"], "2026-04-05")
        XCTAssertEqual(terms["夏至"], "2026-06-21")
        XCTAssertEqual(terms["寒露"], "2026-10-08")
        XCTAssertEqual(terms["霜降"], "2026-10-23")
        XCTAssertEqual(terms["冬至"], "2026-12-22")
        XCTAssertEqual(ChineseCalendar.term(on: cn("2026-10-23")), "霜降")
        XCTAssertEqual(ChineseCalendar.nextTerm(after: cn("2026-10-13"))?.name, "霜降")
        XCTAssertEqual(ChineseCalendar.nextTerm(after: cn("2026-12-30"))?.name, "小寒")
    }

    func testKeysRoundTrip() {
        XCTAssertEqual(ChineseCalendar.key(cn("2026-01-04", hour: 23)), "2026-01-04")
        XCTAssertNil(ChineseCalendar.day("2026-13-01"))
        XCTAssertEqual(ChineseCalendar.days(from: cn("2026-10-13", hour: 23), to: cn("2027-01-01", hour: 1)), 80)
    }
}

final class HolidayScheduleTests: XCTestCase {
    let known = HolidaySchedule.bundled

    func testBreaksGroupDaysAndAttachWorkdays() {
        let breaks = HolidaySchedule.breaks(known[2026]!)
        let national = breaks.first { $0.name == "国庆节" }!
        XCTAssertEqual(ChineseCalendar.key(national.start), "2026-10-01")
        XCTAssertEqual(national.length, 7)
        XCTAssertEqual(national.workdays.map(ChineseCalendar.key).sorted(), ["2026-09-20", "2026-10-10"])
        let spring = breaks.first { $0.name == "春节" }!
        XCTAssertEqual(spring.length, 9)
        XCTAssertEqual(breaks.count, 7)
    }

    func testDayKinds() {
        XCTAssertEqual(HolidaySchedule.kind(of: cn("2026-10-02"), known: known), .holiday("国庆节"))
        XCTAssertEqual(HolidaySchedule.kind(of: cn("2026-10-10"), known: known), .makeupWorkday("国庆节"))
        XCTAssertEqual(HolidaySchedule.kind(of: cn("2026-10-11"), known: known), .weekend)
        XCTAssertEqual(HolidaySchedule.kind(of: cn("2026-10-13"), known: known), .workday)
    }

    func testAlerts() {
        XCTAssertEqual(HolidaySchedule.alert(now: cn("2026-10-09"), known: known), "明天调休，要上班")
        XCTAssertEqual(HolidaySchedule.alert(now: cn("2026-10-10"), known: known), "今天调休上班")
        XCTAssertEqual(HolidaySchedule.alert(now: cn("2026-09-30"), known: known), "明天开始放国庆假")
        XCTAssertNil(HolidaySchedule.alert(now: cn("2026-10-03"), known: known))
        XCTAssertEqual(HolidaySchedule.alert(now: cn("2026-10-07"), known: known), "假期最后一天")
        XCTAssertNil(HolidaySchedule.alert(now: cn("2026-10-13"), known: known))
    }

    func testNextBreakFallsBackToEstimatesForAnUnannouncedYear() {
        let all = HolidaySchedule.breaks(years: 2026...2027, known: known)
        let next = HolidaySchedule.next(after: cn("2026-10-13"), in: all)!
        XCTAssertEqual(next.name, "元旦")
        XCTAssertTrue(next.estimated)
        XCTAssertEqual(HolidaySchedule.countdown(next, now: cn("2026-10-13")), "距元旦还有 80 天")
        XCTAssertEqual(HolidaySchedule.describe(next), "1月1日 · 放假安排未公布")
        let spring = all.first { $0.name == "春节" && $0.estimated }!
        XCTAssertEqual(ChineseCalendar.key(spring.start), "2027-02-05")
    }

    func testCountdownDuringABreak() {
        let all = HolidaySchedule.breaks(years: 2026...2026, known: known)
        let national = HolidaySchedule.next(after: cn("2026-10-03"), in: all)!
        XCTAssertEqual(national.name, "国庆节")
        XCTAssertEqual(HolidaySchedule.countdown(national, now: cn("2026-10-03")), "国庆假期第 3 天")
        XCTAssertEqual(HolidaySchedule.describe(national), "10月1日起 放 7 天 · 9月20日、10月10日上班")
    }

    func testParsesHolidayCnFiles() {
        let json = #"{"year":2027,"papers":[],"days":[]}"#
        XCTAssertNil(HolidaySchedule.parse(Data(json.utf8)))
        let full = #"{"year":2027,"days":[{"name":"元旦","date":"2027-01-01","isOffDay":true}]}"#
        XCTAssertEqual(HolidaySchedule.parse(Data(full.utf8)), [HolidayDay(name: "元旦", date: "2027-01-01", isOffDay: true)])
        XCTAssertNil(HolidaySchedule.parse(Data("nope".utf8)))
    }

    func testShortNames() {
        XCTAssertEqual(HolidaySchedule.shortName("国庆节、中秋节"), "国庆")
        XCTAssertEqual(HolidaySchedule.shortName("元旦"), "元旦")
        XCTAssertEqual(HolidaySchedule.shortName("清明节"), "清明")
    }
}

final class TrashFliesTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testNoFliesBelowTheThreshold() {
        XCTAssertEqual(TrashFlies.count(bytes: 0, threshold: 1, overSince: nil, now: now), 0)
        XCTAssertEqual(TrashFlies.count(bytes: 99_000_000, threshold: 100_000_000, overSince: nil, now: now), 0)
    }

    func testMoreFliesForMoreTrash() {
        let t: Int64 = 100_000_000
        XCTAssertEqual(TrashFlies.count(bytes: t, threshold: t, overSince: now, now: now), 1)
        XCTAssertEqual(TrashFlies.count(bytes: 2 * t, threshold: t, overSince: now, now: now), 2)
        XCTAssertEqual(TrashFlies.count(bytes: 8 * t, threshold: t, overSince: now, now: now), 4)
        XCTAssertEqual(TrashFlies.count(bytes: 1_000_000 * t, threshold: t, overSince: now, now: now), TrashFlies.maxFlies)
    }

    func testMoreFliesEveryHourItIsLeft() {
        let t: Int64 = 100_000_000
        let threeHoursAgo = now.addingTimeInterval(-3 * 3_600 - 60)
        XCTAssertEqual(TrashFlies.count(bytes: t, threshold: t, overSince: threeHoursAgo, now: now), 4)
    }

    func testOverSinceStartsKeepsAndClears() {
        let t: Int64 = 10
        let earlier = now.addingTimeInterval(-500)
        XCTAssertEqual(TrashFlies.overSince(previous: nil, bytes: 20, threshold: t, now: now), now)
        XCTAssertEqual(TrashFlies.overSince(previous: earlier, bytes: 20, threshold: t, now: now), earlier)
        XCTAssertNil(TrashFlies.overSince(previous: earlier, bytes: 5, threshold: t, now: now))
    }

    func testThresholdChoices() {
        XCTAssertEqual(TrashFlies.thresholdBytes("1GB"), 1_000_000_000)
        XCTAssertEqual(TrashFlies.thresholdBytes("bogus"), 100_000_000)
        XCTAssertEqual(TrashFlies.thresholdBytes("any"), 1)
    }

    func testFliesStayNearTheBinAndDoNotMoveTogether() {
        for index in 0..<TrashFlies.maxFlies {
            for step in 0..<50 {
                let p = TrashFlies.position(index: index, t: Double(step) * 0.37)
                XCTAssertLessThan(abs(p.x), 1.7)
                XCTAssertLessThan(abs(p.y), 1.3)
            }
        }
        let a = TrashFlies.position(index: 0, t: 2)
        let b = TrashFlies.position(index: 1, t: 2)
        XCTAssertNotEqual(a.x, b.x)
    }

    func testScareCurve() {
        XCTAssertEqual(TrashFlies.scare(elapsed: 0), 0)
        XCTAssertEqual(TrashFlies.scare(elapsed: 1), 1)
        XCTAssertEqual(TrashFlies.scare(elapsed: 4), 0.5, accuracy: 0.001)
        XCTAssertEqual(TrashFlies.scare(elapsed: 10), 0)
    }

    func testSizeText() {
        XCTAssertEqual(TrashFlies.format(bytes: 0), "空")
        XCTAssertEqual(TrashFlies.format(bytes: 512), "512 B")
        XCTAssertEqual(TrashFlies.format(bytes: 1_260_000_000), "1.3 GB")
        XCTAssertEqual(TrashFlies.format(bytes: 340_000_000), "340 MB")
        XCTAssertEqual(TrashFlies.format(bytes: 2_000_000), "2 MB")
    }
}

final class ClipboardPinsTests: XCTestCase {
    func testToggleAddsAtTopAndRemoves() {
        var pins = ClipboardPins.toggling("a", in: [])
        pins = ClipboardPins.toggling("b", in: pins)
        XCTAssertEqual(pins, ["b", "a"])
        XCTAssertEqual(ClipboardPins.toggling("a", in: pins), ["b"])
        XCTAssertEqual(ClipboardPins.toggling("   ", in: pins), pins)
    }

    func testStoreAndReadDropRepeats() {
        var config = WidgetConfig()
        ClipboardPins.store(["x", "y", "x", ""], in: &config)
        XCTAssertEqual(ClipboardPins.pins(config), ["x", "y"])
        XCTAssertTrue(ClipboardPins.isPinned("y", in: ClipboardPins.pins(config)))
    }

    func testLimits() {
        let many = (0..<80).map { "p\($0)" }
        var config = WidgetConfig()
        ClipboardPins.store(many, in: &config)
        XCTAssertEqual(ClipboardPins.pins(config).count, ClipboardPins.maxPins)
        let long = String(repeating: "长", count: 6_000)
        XCTAssertEqual(ClipboardPins.toggling(long, in: []).first?.count, ClipboardPins.maxLength)
        XCTAssertTrue(ClipboardPins.isPinned(long, in: ClipboardPins.toggling(long, in: [])))
    }

    func testMoving() {
        XCTAssertEqual(ClipboardPins.moving("c", by: -1, in: ["a", "b", "c"]), ["a", "c", "b"])
        XCTAssertEqual(ClipboardPins.moving("a", by: -1, in: ["a", "b"]), ["a", "b"])
    }

    func testSearchMatchesEveryWord() {
        XCTAssertTrue(ClipboardPins.matches("家里 WiFi 的密码是 1234", query: "wifi 密码"))
        XCTAssertFalse(ClipboardPins.matches("家里 WiFi", query: "wifi 密码"))
        XCTAssertTrue(ClipboardPins.matches("anything", query: "  "))
        XCTAssertTrue(ClipboardPins.matches("ＡＢＣ", query: "abc"))
    }
}

final class QuickToggleListTests: XCTestCase {
    func testChosenKeepsOrderAndDropsUnknown() {
        var config = WidgetConfig()
        XCTAssertEqual(QuickToggle.chosen(config), QuickToggle.defaults)
        config.set(QuickToggle.key, .list([.string("lock"), .string("nope"), .string("keepAwake"), .string("lock")]))
        XCTAssertEqual(QuickToggle.chosen(config), [.lock, .keepAwake])
        config.set(QuickToggle.key, .list([]))
        XCTAssertEqual(QuickToggle.chosen(config), QuickToggle.defaults)
    }

    func testEverySwitchIsNamed() {
        for toggle in QuickToggle.allCases {
            XCTAssertFalse(toggle.title.isEmpty)
            XCTAssertFalse(toggle.help.isEmpty)
            XCTAssertFalse(toggle.symbol.isEmpty)
        }
        XCTAssertEqual(QuickToggle.length(count: 4), 140)
    }
}

final class ShelfColorTests: XCTestCase {
    func testParseAndDefaults() {
        XCTAssertNil(ShelfColor.parse(""))
        XCTAssertNil(ShelfColor.parse("nope"))
        XCTAssertEqual(ShelfColor.parse("sakura"), .sakura)
        XCTAssertEqual(CustomDockSettings().shelfColor, "")
        for color in ShelfColor.allCases {
            XCTAssertTrue(color.hex.hasPrefix("#") && color.hex.count == 7)
            XCTAssertFalse(color.title.isEmpty)
        }
    }

    func testShelfColorSurvivesASaveAndOldFilesHaveNone() throws {
        var settings = CustomDockSettings()
        settings.shelfColor = "mint"
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(CustomDockSettings.self, from: data).shelfColor, "mint")
        let old = try JSONDecoder().decode(CustomDockSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(old.shelfColor, "")
    }
}
