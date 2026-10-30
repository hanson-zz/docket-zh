import Foundation
import XCTest
@testable import Docket

/// 农历面板：农历生日每年换算（闰月、小月）、存取、提醒时间、宜忌、近期节日节气。
final class LunarPanelTests: XCTestCase {
    private func day(_ key: String, hour: Int = 10) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = ChineseCalendar.zone
        return calendar.date(byAdding: .hour, value: hour, to: ChineseCalendar.day(key)!)!
    }

    private func keys(_ list: [LunarEvents.Occurrence]) -> [String] { list.map { ChineseCalendar.key($0.date) } }

    // MARK: 换算

    func testEveryYearToGregorian() {
        let next = LunarEvents.occurrences(month: 10, day: 8, leap: false, from: day("2026-10-20"))
        XCTAssertEqual(keys(next), ["2026-11-16", "2027-11-05"], "效果图：农历十月初八今年 11月16日，明年 11月5日")
        XCTAssertEqual(keys(LunarEvents.occurrences(month: 11, day: 23, leap: false, from: day("2026-10-20"), count: 1)),
                       ["2026-12-31"])
        XCTAssertEqual(keys(LunarEvents.occurrences(month: 12, day: 18, leap: false, from: day("2026-10-20"), count: 1)),
                       ["2027-01-25"], "腊月在下一个公历年")
    }

    func testTodayCountsAndPassedMovesToNextYear() {
        let today = LunarEvents.occurrences(month: 9, day: 11, leap: false, from: day("2026-10-20", hour: 23), count: 1)
        XCTAssertEqual(keys(today), ["2026-10-20"], "当天晚上也还是今天")
        let passed = LunarEvents.occurrences(month: 9, day: 10, leap: false, from: day("2026-10-20"), count: 1)
        XCTAssertEqual(keys(passed), ["2027-10-09"])
    }

    func testShortMonthFallsBackToTheTwentyNinth() {
        // 2026 年（丙午）的腊月只有 29 天。
        let found = LunarEvents.occurrences(month: 12, day: 30, leap: false, from: day("2026-10-20"), count: 1)
        XCTAssertEqual(keys(found), ["2027-02-05"])
        XCTAssertEqual(found.first?.shortMonth, true)
        XCTAssertEqual(found.first?.day, 29)
        let event = LunarEvent(name: "爷爷生日", month: 12, day: 30)
        XCTAssertEqual(LunarEvents.note(event, found[0]), "这一年腊月只有 29 天，按廿九过")
    }

    func testLeapMonthUsesTheLeapWhenItExistsAndThePlainMonthOtherwise() {
        // 2025 年有闰六月（7月25日到8月22日），2026 年没有。
        let leap = LunarEvents.occurrences(month: 6, day: 10, leap: true, from: day("2025-07-01"))
        XCTAssertEqual(keys(leap), ["2025-08-03", "2026-07-23"])
        XCTAssertEqual(leap[0].isLeap, true)
        XCTAssertEqual(leap[0].leapFallback, false)
        XCTAssertEqual(leap[1].isLeap, false)
        XCTAssertEqual(leap[1].leapFallback, true)
        let event = LunarEvent(name: "闰月生日", month: 6, day: 10, isLeap: true)
        XCTAssertEqual(LunarEvents.note(event, leap[1]), "这一年没有闰六月，按六月过")
        XCTAssertNil(LunarEvents.note(event, leap[0]))

        let plain = LunarEvents.occurrences(month: 6, day: 10, leap: false, from: day("2025-07-01"), count: 1)
        XCTAssertEqual(keys(plain), ["2025-07-04"], "记的是普通月，有闰月的年份也只按普通月")

        // 2025 的闰六月只有 29 天。
        let leapThirty = LunarEvents.occurrences(month: 6, day: 30, leap: true, from: day("2025-07-01"), count: 1)
        XCTAssertEqual(keys(leapThirty), ["2025-08-22"])
        XCTAssertEqual(leapThirty.first?.shortMonth, true)
    }

    func testRowsSortByDaysLeft() {
        let now = day("2026-10-20")
        let events = [
            LunarEvent(id: "c", name: "结婚纪念日", kind: .anniversary, month: 12, day: 18),
            LunarEvent(id: "a", name: "妈妈生日", month: 10, day: 8),
            LunarEvent(id: "b", name: "外婆生日", month: 11, day: 23),
        ]
        let rows = LunarEvents.rows(events, now: now)
        XCTAssertEqual(rows.map(\.event.id), ["a", "b", "c"])
        XCTAssertEqual(rows.map(\.days), [27, 72, 97], "效果图上的 27、72、97 天")
        XCTAssertEqual(LunarEvents.subtitle(rows[0]), "农历十月初八 · 11月16日 周一")
        XCTAssertTrue(LunarEvents.rows([], now: now).isEmpty)
        XCTAssertTrue(LunarEvents.today(events, now: now).isEmpty)
        XCTAssertEqual(LunarEvents.today(events, now: day("2026-11-16")).map(\.id), ["a"])
    }

    // MARK: 存取

    func testStoreAndReadRoundTrip() {
        var config = WidgetConfig()
        XCTAssertTrue(LunarEvents.events(config).isEmpty)
        let event = LunarEvent(id: "x", name: "名字|带竖线", kind: .other, month: 6, day: 30, isLeap: true,
                               lead: 7, minute: 20 * 60 + 30)
        LunarEvents.store([event], in: &config)
        XCTAssertEqual(LunarEvents.events(config), [event])
        LunarEvents.store([], in: &config)
        XCTAssertNil(config[LunarEvents.key], "删掉最后一条，键也清掉")
    }

    func testBadEntriesAreSkippedAndValuesClamped() {
        let config = WidgetConfig([LunarEvents.key: .list([
            .string("a|b|13|1|0|3|540|坏月份"),
            .string("b|b|1|31|0|3|540|坏日子"),
            .string("c|b|1|1|0|3|540|   "),
            .string("d|z|1|1|0|5|9999|好的"),
            .string("d|b|2|2|0|3|540|重复的 id"),
            .string("乱写"),
        ])])
        let events = LunarEvents.events(config)
        XCTAssertEqual(events.map(\.id), ["d"])
        XCTAssertEqual(events.first?.kind, .other, "认不出的种类算其他")
        XCTAssertEqual(events.first?.lead, LunarEvents.defaultLead, "不在选项里的提前天数退回默认")
        XCTAssertEqual(events.first?.minute, 24 * 60 - 1)
    }

    func testSavingRemovingAndLimit() {
        let a = LunarEvent(id: "a", name: "甲", month: 1, day: 1)
        var list = LunarEvents.saving(a, in: [])
        var changed = a
        changed.name = "乙"
        list = LunarEvents.saving(changed, in: list)
        XCTAssertEqual(list.map(\.name), ["乙"], "同一个 id 就地改")
        XCTAssertTrue(LunarEvents.removing("a", from: list).isEmpty)
        let full = (0..<LunarEvents.limit).map { LunarEvent(id: "\($0)", name: "第\($0)", month: 1, day: 1) }
        XCTAssertEqual(LunarEvents.saving(LunarEvent(id: "new", name: "多一个", month: 1, day: 1), in: full).count,
                       LunarEvents.limit, "放满了加不进去")
    }

    func testCleanNames() {
        XCTAssertNil(LunarEvents.clean("  \n "))
        XCTAssertEqual(LunarEvents.clean("  妈妈生日 \n"), "妈妈生日")
        XCTAssertEqual(LunarEvents.clean(String(repeating: "字", count: 40))?.count, LunarEvents.nameLimit)
    }

    // MARK: 提醒

    func testRemindersLeadAndDay() {
        let event = LunarEvent(name: "妈妈生日", month: 10, day: 8, lead: 3, minute: 9 * 60)
        let list = LunarEvents.reminders(event, now: day("2026-10-20"))
        XCTAssertEqual(list.map(\.slot), ["lead", "day"])
        XCTAssertEqual(list[0].fire, day("2026-11-13", hour: 9))
        XCTAssertEqual(list[1].fire, day("2026-11-16", hour: 9))
        XCTAssertEqual(list[1].title, "今天是妈妈生日")

        // 提前那天已经过了，只剩当天。
        XCTAssertEqual(LunarEvents.reminders(event, now: day("2026-11-14")).map(\.slot), ["day"])
        // 当天 9 点已过，今年的都不排了。
        XCTAssertTrue(LunarEvents.reminders(event, now: day("2026-11-16", hour: 10)).isEmpty)

        var quiet = event
        quiet.lead = -1
        XCTAssertTrue(LunarEvents.reminders(quiet, now: day("2026-10-20")).isEmpty)
        var sameDay = event
        sameDay.lead = 0
        XCTAssertEqual(LunarEvents.reminders(sameDay, now: day("2026-10-20")).map(\.slot), ["day"])
    }

    func testReminderTexts() {
        XCTAssertEqual(LunarEvents.reminderText(LunarEvent(name: "x", month: 1, day: 1, lead: 3)),
                       "提前 3 天 09:00 提醒，当天再提醒一次")
        XCTAssertEqual(LunarEvents.reminderText(LunarEvent(name: "x", month: 1, day: 1, lead: 0, minute: 450)),
                       "当天 07:30 提醒")
        XCTAssertEqual(LunarEvents.reminderText(LunarEvent(name: "x", month: 1, day: 1, lead: -1)), "不提醒")
        XCTAssertEqual(LunarEvents.minuteChoices.first, 360)
        XCTAssertEqual(LunarEvents.minuteChoices.last, 22 * 60)
        XCTAssertTrue(LunarEvents.minuteChoices.contains(LunarEvents.defaultMinute))
    }

    // MARK: 卡片

    func testEventDayTakesTheCard() {
        let events = [LunarEvent(name: "妈妈生日", month: 10, day: 8)]
        let known = HolidaySchedule.bundled
        let now = day("2026-11-16")
        let breaks = HolidaySchedule.breaks(years: 2026...2027, known: known)
        let headline = LunarCard.headline(now: now, known: known, breaks: breaks, leadDays: 7,
                                          showTerm: true, workAlert: true, events: events)
        XCTAssertEqual(LunarCard.title(headline, now: now), "今天是妈妈生日")
        XCTAssertEqual(LunarCard.caption(headline, now: now), "农历十月初八 · 生日快乐")
        let other = LunarCard.headline(now: day("2026-11-15"), known: known, breaks: breaks, leadDays: 7,
                                       showTerm: true, workAlert: true, events: events)
        if case .event = other { XCTFail("前一天不算") }
    }

    func testMakeupWorkdayTodayStillWinsOverABirthday() {
        // 2026-10-10 周六调休上班（农历九月初一）。
        let lunar = ChineseCalendar.lunar(day("2026-10-10"))
        let events = [LunarEvent(name: "生日", month: lunar.month, day: lunar.day)]
        let known = HolidaySchedule.bundled
        let breaks = HolidaySchedule.breaks(years: 2026...2027, known: known)
        let headline = LunarCard.headline(now: day("2026-10-10"), known: known, breaks: breaks, leadDays: 7,
                                          showTerm: true, workAlert: true, events: events)
        XCTAssertTrue(headline.isAlert)
        // 提前几天的调休提醒让给生日。
        let lunar9 = ChineseCalendar.lunar(day("2026-10-08"))
        let early = LunarCard.headline(now: day("2026-10-08"), known: known, breaks: breaks, leadDays: 7,
                                       showTerm: true, workAlert: true,
                                       events: [LunarEvent(name: "生日", month: lunar9.month, day: lunar9.day)])
        if case .event = early {} else { XCTFail("当天生日排在提前的调休提醒前面") }
    }

    // MARK: 宜忌（和卜卦每日一签同一份真黄历）

    func testDayGanzhi() {
        XCTAssertEqual(ChineseAlmanac.dayGanzhi(day("2026-10-20")), "丁卯")
        XCTAssertEqual(ChineseAlmanac.dayGanzhi(day("1970-01-01")), "辛巳")
        XCTAssertEqual(ChineseAlmanac.dayGanzhi(day("2026-11-16")), "甲午")
        XCTAssertEqual(ChineseAlmanac.dayGanzhi(day("1969-12-31")), "庚辰", "1970 年以前也不出负数")
        XCTAssertEqual(LunarPanel.almanac(day("2026-10-20")).dayGanzhi, "丁卯")
    }

    func testOfficersFollowTheSolarMonth() {
        func officer(_ key: String) -> String { LunarPanel.almanac(day(key)).officer }
        XCTAssertEqual(officer("2026-10-20"), "执日")
        // 寒露当天换戌月，和前一天同是执日（重建）。
        XCTAssertEqual(officer("2026-10-07"), "执日")
        XCTAssertEqual(officer("2026-10-08"), "执日")
        XCTAssertEqual(officer("2026-11-16"), "危日")
        // 小寒以前还是子月。
        XCTAssertEqual(officer("2026-01-04"), "满日")
        XCTAssertEqual(officer("2026-01-06"), "平日")
        XCTAssertEqual(officer("2026-02-04"), "危日")
        XCTAssertEqual(officer("2026-12-07"), "平日")
    }

    /// 农历面板宜忌页、桌面中号卡片和卜卦每日一签页拿的是同一份：一年多里每一天（不同钟点问也一样）
    /// 干支、建除、星宿、宜忌完全一致，也和不经缓存现算的一致。
    func testPanelAlmanacMatchesTheDivinationPage() {
        for offset in 0..<400 {
            let date = Calendar(identifier: .gregorian).date(byAdding: .day, value: offset, to: day("2026-01-01"))!
            let panel = LunarPanel.almanac(date)
            let divination = ChineseAlmanac.day(date.addingTimeInterval(3 * 3600))
            XCTAssertEqual(panel, divination, ChineseCalendar.key(date))
            XCTAssertEqual(panel, ChineseAlmanac.compute(date), ChineseCalendar.key(date))
            XCTAssertFalse(panel.good.isEmpty)
            XCTAssertFalse(panel.bad.isEmpty)
        }
        // 今天：2026-10-30 丁丑日、平日、娄金狗，宜祭祀、平治道涂，忌嫁娶。
        let today = LunarPanel.almanac(day("2026-10-30"))
        XCTAssertEqual(today.dayGanzhi, "丁丑")
        XCTAssertEqual(today.officer, "平日")
        XCTAssertEqual(today.mansionText, "娄金狗")
        XCTAssertEqual(Array(today.good.prefix(2)), ["祭祀", "平治道涂"])
        XCTAssertEqual(today.bad.first, "嫁娶")
        XCTAssertEqual(LunarPanel.cardWordCounts, [4, 3, 2, 1])
    }

    /// 界面上两处都走 `LunarPanel.almanac`，旧的「每值日四宜四忌」简表已经删掉。
    func testLunarViewsUseTheRealAlmanac() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let detail = try String(contentsOf: root.appendingPathComponent("Sources/Widgets/Details/LunarDetail.swift"),
                                encoding: .utf8)
        let card = try String(contentsOf: root.appendingPathComponent(
            "Sources/Widgets/DesktopCards/DesktopCardsTime+Days.swift"), encoding: .utf8)
        for source in [detail, card] {
            XCTAssertTrue(source.contains("LunarPanel.almanac(now)"))
            XCTAssertFalse(source.contains("LunarAlmanac"))
        }
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources/Core/LunarAlmanac.swift").path))
    }

    // MARK: 近期节日节气

    func testAgendaMatchesTheDesign() {
        let known = HolidaySchedule.bundled
        let now = day("2026-10-20")
        let breaks = HolidaySchedule.breaks(years: 2026...2027, known: known)
        let items = LunarCard.agenda(now: now, known: known, breaks: breaks, showTerm: true, workAlert: true)
        XCTAssertEqual(items.map(\.name), ["霜降", "立冬", "寒衣节", "小雪"])
        XCTAssertEqual(items.map(\.days), [3, 18, 20, 33])
        XCTAssertEqual(items[2].kindText, "十月初一")
        XCTAssertEqual(items[0].kindText, "节气")
        XCTAssertEqual(items[0].countdownText, "3 天")

        let noTerms = LunarCard.agenda(now: now, known: known, breaks: breaks, showTerm: false, workAlert: true)
        XCTAssertFalse(noTerms.contains { $0.kind == .term })
        XCTAssertEqual(noTerms.first?.name, "寒衣节")
    }

    func testAgendaDuringAHolidayAndWithMakeupDays() {
        let known = HolidaySchedule.bundled
        let breaks = HolidaySchedule.breaks(years: 2026...2027, known: known)
        let items = LunarCard.agenda(now: day("2026-10-03"), known: known, breaks: breaks,
                                     showTerm: true, workAlert: true, limit: 10)
        XCTAssertEqual(items.first?.name, "国庆节")
        XCTAssertEqual(items.first?.countdownText, "放假中")
        XCTAssertEqual(items.first?.kindText, "放 7 天")
        XCTAssertTrue(items.contains { $0.isAlert && ChineseCalendar.key($0.date) == "2026-10-10" })
        let quiet = LunarCard.agenda(now: day("2026-10-03"), known: known, breaks: breaks,
                                     showTerm: true, workAlert: false, limit: 10)
        XCTAssertFalse(quiet.contains { $0.isAlert }, "调休补班关掉就不列")
    }

    func testAgendaDoesNotListAFestivalTwice() {
        let known = HolidaySchedule.bundled
        let breaks = HolidaySchedule.breaks(years: 2026...2027, known: known)
        let items = LunarCard.agenda(now: day("2026-09-01"), known: known, breaks: breaks,
                                     showTerm: true, workAlert: true, limit: 20)
        XCTAssertEqual(items.filter { HolidaySchedule.shortName($0.name) == "中秋" }.count, 1)
        XCTAssertEqual(items.map(\.date), items.map(\.date).sorted())
        let spring = LunarCard.agenda(now: day("2026-03-25"), known: known, breaks: breaks,
                                      showTerm: true, workAlert: true, limit: 20)
        XCTAssertEqual(spring.filter { HolidaySchedule.shortName($0.name) == "清明" }.count, 1,
                       "清明节气和清明节假期只留一条")
    }

    func testMonthCellNamesFitThreeCharacters() {
        XCTAssertEqual(LunarPanel.cellName("北方小年"), "小年")
        XCTAssertEqual(LunarPanel.cellName("南方小年"), "小年")
        XCTAssertEqual(LunarPanel.cellName("闰六月"), "闰六")
        XCTAssertEqual(LunarPanel.cellName("龙抬头"), "龙抬头")
        XCTAssertEqual(LunarPanel.cellName("十月"), "十月")
        XCTAssertEqual(LunarPanel.cellName("初八"), "初八")
    }

    func testDefaultsTurnTheAlmanacOn() {
        let defaults = WidgetCatalog.entry(.lunar)?.defaults
        XCTAssertEqual(defaults?.bool(LunarPanel.almanacKey), true)
        XCTAssertNil(defaults?[LunarEvents.key], "生日在面板里加，不进设置页")
    }
}
