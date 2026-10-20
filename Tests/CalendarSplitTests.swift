import Foundation
import XCTest
@testable import Docket

/// 日历 / 一周日程 / 农历与假期分工：会议链接识别、倒计时、今日时间线布局、
/// 忙闲计算、最空下午、调休提醒优先级。
final class MeetingLinkTests: XCTestCase {
    private func find(url: String? = nil, location: String? = nil, notes: String? = nil) -> MeetingLink? {
        MeetingLink.find(url: url.flatMap(URL.init(string:)), location: location, notes: notes)
    }

    func testRecognisesEachProviderInLocationAndNotes() {
        XCTAssertEqual(find(location: "腾讯会议 https://meeting.tencent.com/dm/abc123")?.provider, .tencent)
        XCTAssertEqual(find(notes: "点击加入 https://voovmeeting.com/dm/xyz 会议号 123")?.provider, .tencent)
        XCTAssertEqual(find(notes: "Join Zoom Meeting\nhttps://us02web.zoom.us/j/123456789?pwd=abc")?.provider, .zoom)
        XCTAssertEqual(find(notes: "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0")?.provider,
                       .teams)
        XCTAssertEqual(find(location: "https://vc.feishu.cn/j/123456789")?.provider, .feishu)
        XCTAssertEqual(find(notes: "视频会议：https://meet.google.com/abc-defg-hij")?.provider, .meet)
    }

    func testIgnoresLinksThatAreNotMeetings() {
        XCTAssertNil(find(notes: "文档 https://abc.feishu.cn/docx/AbCdEf"))
        XCTAssertNil(find(notes: "下载 https://zoom.us/download"))
        XCTAssertNil(find(notes: "https://teams.microsoft.com/"))
        XCTAssertNil(find(location: "3 号会议室"))
        XCTAssertNil(find(notes: "资料 https://example.com/slides"))
        XCTAssertNil(find())
    }

    func testURLFieldWinsAndUnknownHostStillJoins() {
        XCTAssertEqual(find(url: "https://meeting.tencent.com/dm/one", notes: "https://zoom.us/j/1")?.url.absoluteString,
                       "https://meeting.tencent.com/dm/one")
        // 不认得的 URL 字段：备注里有认得的会议就用备注的。
        XCTAssertEqual(find(url: "https://example.com/room", notes: "https://zoom.us/j/1")?.provider, .zoom)
        // 只有 URL 字段：也算会议入口，按钮写「加入会议」。
        let other = find(url: "https://example.com/room")
        XCTAssertEqual(other?.provider, .other)
        XCTAssertEqual(other?.provider.joinTitle, "加入会议")
        XCTAssertEqual(MeetingLink.Provider.tencent.joinTitle, "加入腾讯会议")
        XCTAssertNil(find(url: "mailto:a@b.com"))
    }

    func testLocationThatIsOnlyALink() {
        XCTAssertTrue(MeetingLink.isOnlyLink(" https://meeting.tencent.com/dm/abc "))
        XCTAssertFalse(MeetingLink.isOnlyLink("3 号会议室"))
        XCTAssertFalse(MeetingLink.isOnlyLink("腾讯会议 https://meeting.tencent.com/dm/abc"))
        XCTAssertFalse(MeetingLink.isOnlyLink(""))
    }
}

final class CalendarDayTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func at(_ h: Int, _ m: Int = 0, day: Int = 20) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: m))!
    }

    private func span(_ id: String, _ start: Date, _ end: Date, allDay: Bool = false) -> CalendarSpan {
        CalendarSpan(id: id, start: start, end: end, isAllDay: allDay)
    }

    func testCountdownWords() {
        let now = at(10, 5)
        XCTAssertEqual(CalendarDay.countdown(start: at(10, 30), end: at(11, 15), now: now), "还有 25 分钟")
        XCTAssertEqual(CalendarDay.countdown(start: at(11, 10), end: at(12), now: now), "还有 1 小时 5 分钟")
        XCTAssertEqual(CalendarDay.countdown(start: at(12, 5), end: at(13), now: now), "还有 2 小时")
        XCTAssertEqual(CalendarDay.countdown(start: now.addingTimeInterval(30), end: at(11), now: now), "马上开始")
        XCTAssertEqual(CalendarDay.countdown(start: at(10), end: at(10, 25), now: now), "进行中 · 还剩 20 分钟")
        XCTAssertEqual(CalendarDay.nextLine(start: at(10, 30), now: now), "下一个 25 分钟后")
        XCTAssertEqual(CalendarDay.nextLine(start: at(10), now: now), "进行中")
        XCTAssertEqual(CalendarDay.range(at(10, 30), at(11, 15), calendar: calendar), "10:30-11:15")
    }

    func testRemainingAndDots() {
        let now = at(10, 5)
        let spans = [span("b", at(14), at(15)), span("a", at(9), at(9, 30)),
                     span("c", at(10), at(10, 30)), span("all", at(0), at(0, day: 21), allDay: true)]
        XCTAssertEqual(CalendarDay.remaining(spans, now: now).map(\.id), ["c", "b"])
        let dots = CalendarDay.dots(spans, now: now)
        XCTAssertEqual(dots.map(\.id), ["a", "c", "b"])
        XCTAssertEqual(dots.map(\.past), [true, false, false])
        XCTAssertEqual(CalendarDay.dots(spans, now: now, limit: 2).count, 2)
    }

    func testAgendaLayoutBecomesTimeline() {
        let old = WidgetConfig(["layout": .string("agenda"), "allDay": .bool(false)])
        let moved = CalendarDay.migratingLayout(old)
        XCTAssertEqual(moved.string("layout"), "timeline")
        XCTAssertEqual(moved.bool("allDay", default: true), false)
        XCTAssertEqual(CalendarDay.layout(old), "timeline")
        let other = WidgetConfig(["layout": .string("date")])
        XCTAssertEqual(CalendarDay.migratingLayout(other), other)
        XCTAssertEqual(CalendarDay.layout(WidgetConfig()), "nextEvent")
    }

    func testSavedAgendaWidgetDecodesAsTimeline() throws {
        let saved = WidgetInstance(kind: .calendar, expanded: true,
                                   config: WidgetConfig(["layout": .string("agenda")]))
        let data = try JSONEncoder().encode(saved)
        let back = try JSONDecoder().decode(WidgetInstance.self, from: data)
        XCTAssertEqual(back.id, saved.id)
        XCTAssertEqual(back.config.string("layout"), "timeline")
        XCTAssertEqual(WidgetCatalog.variantTitle(matching: back.config, kind: .calendar), "今日时间线")
        XCTAssertEqual(WidgetCatalog.naturalSize(back), CGSize(width: 300, height: 62))
        // 没迁移过的旧值也按时间线的尺寸算。
        XCTAssertEqual(WidgetCatalog.naturalSize(saved), CGSize(width: 300, height: 62))
    }

    func testCalendarOffersFourStyles() {
        let titles = WidgetCatalog.entry(.calendar)?.variants.map { $0.title }
        XCTAssertEqual(titles, ["下一个日程", "今日时间线", "日期", "日期 + 下一个日程"])
    }
}

final class DayTimelineTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func at(_ h: Int, _ m: Int = 0, day: Int = 20) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: m))!
    }

    private var day: Date { at(0) }

    private func span(_ id: String, _ start: Date, _ end: Date, allDay: Bool = false) -> CalendarSpan {
        CalendarSpan(id: id, start: start, end: end, isAllDay: allDay)
    }

    func testRangeDefaultsToNineToSevenAndGrowsToFit() {
        XCTAssertEqual(DayTimeline.hourRange([], day: day, calendar: calendar), 9...19)
        XCTAssertEqual(DayTimeline.hourRange([span("a", at(10), at(11))], day: day, calendar: calendar), 9...19)
        XCTAssertEqual(DayTimeline.hourRange([span("a", at(8, 30), at(9))], day: day, calendar: calendar), 8...19)
        XCTAssertEqual(DayTimeline.hourRange([span("a", at(18), at(20, 15))], day: day, calendar: calendar), 9...21)
        // 跨午夜只算到今天结束；全天日程不撑开轴。
        XCTAssertEqual(DayTimeline.hourRange([span("a", at(23), at(1, day: 21))], day: day, calendar: calendar), 9...24)
        XCTAssertEqual(DayTimeline.hourRange([span("all", at(0), at(0, day: 21), allDay: true)],
                                             day: day, calendar: calendar), 9...19)
    }

    func testBlocksSitWhereTheirHoursAreAndPastIsMarked() {
        let now = at(12)
        let blocks = DayTimeline.blocks([span("late", at(14), at(15)), span("early", at(10), at(11))],
                                        hours: 9...19, day: day, now: now, calendar: calendar)
        XCTAssertEqual(blocks.map(\.id), ["early", "late"])
        XCTAssertEqual(blocks[0].from, 0.1, accuracy: 1e-9)
        XCTAssertEqual(blocks[0].to, 0.2, accuracy: 1e-9)
        XCTAssertEqual(blocks[1].from, 0.5, accuracy: 1e-9)
        XCTAssertEqual(blocks.map(\.isPast), [true, false])
        XCTAssertEqual(blocks.map(\.lanes), [1, 1])
        XCTAssertEqual(DayTimeline.nowFraction(at(14), hours: 9...19, day: day, calendar: calendar)!, 0.5, accuracy: 1e-9)
        XCTAssertNil(DayTimeline.nowFraction(at(20), hours: 9...19, day: day, calendar: calendar))
        XCTAssertNil(DayTimeline.nowFraction(at(10, day: 21), hours: 9...19, day: day, calendar: calendar))
    }

    func testOverlapsSplitIntoLanes() {
        let blocks = DayTimeline.blocks([span("a", at(10), at(11)), span("b", at(10, 30), at(11, 30)),
                                         span("c", at(12), at(13)),
                                         span("d", at(15), at(16)), span("e", at(15), at(16)), span("f", at(15), at(16))],
                                        hours: 9...19, day: day, now: at(8), calendar: calendar)
        let byID = Dictionary(uniqueKeysWithValues: blocks.map { ($0.id, $0) })
        XCTAssertEqual(byID["a"]?.lane, 0)
        XCTAssertEqual(byID["b"]?.lane, 1)
        XCTAssertEqual(byID["a"]?.lanes, 2)
        XCTAssertEqual(byID["b"]?.lanes, 2)
        XCTAssertEqual(byID["c"]?.lanes, 1)
        XCTAssertEqual(byID["c"]?.lane, 0)
        // 三个同时：最多两行，第三个挤进第二行。
        XCTAssertEqual(byID["f"]?.lane, 1)
        XCTAssertEqual(byID["d"]?.lanes, 2)
    }

    func testClampedAtTheEnds() {
        let blocks = DayTimeline.blocks([span("night", at(23), at(1, day: 21))],
                                        hours: 9...24, day: day, now: at(8), calendar: calendar)
        XCTAssertEqual(blocks[0].to, 1, accuracy: 1e-9)
        XCTAssertGreaterThan(blocks[0].from, 0.9)
    }

    func testLabelsAndHitTest() {
        XCTAssertEqual(DayTimeline.labelHours(9...19), [9, 12, 15, 18])
        XCTAssertEqual(DayTimeline.labelHours(0...24), [0, 8, 16])
        XCTAssertEqual(DayTimeline.labelHours(9...11), [9, 10, 11])
        let blocks = DayTimeline.blocks([span("a", at(10), at(11)), span("b", at(14), at(15))],
                                        hours: 9...19, day: day, now: at(8), calendar: calendar)
        XCTAssertEqual(DayTimeline.block(at: 0.15, in: blocks), 0)
        XCTAssertEqual(DayTimeline.block(at: 0.55, in: blocks), 1)
        XCTAssertEqual(DayTimeline.block(at: 0.21, in: blocks), 0, "一点点偏出去也算")
        XCTAssertNil(DayTimeline.block(at: 0.35, in: blocks))
    }
}

final class WeekBusyTests: XCTestCase {
    private let calendar = WeekAgenda.calendar

    private func at(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!
    }

    private func entry(_ id: String, _ start: Date, _ end: Date, allDay: Bool = false) -> WeekEntry {
        WeekEntry(id: id, title: id, start: start, end: end, isAllDay: allDay)
    }

    /// 2026-10-19 是周一。
    private func week(now: Date) -> [WeekDay] {
        WeekAgenda.days([
            entry("mon1", at(19, 9), at(19, 10)), entry("mon2", at(19, 9, 30), at(19, 11)),
            entry("tue", at(20, 13), at(20, 17)),
            entry("wed", at(21, 14), at(21, 15)), entry("wedAll", at(21, 0), at(22, 0), allDay: true),
            entry("thu1", at(22, 9, 30), at(22, 10)), entry("thu2", at(22, 10), at(22, 11, 30)),
            entry("fri", at(23, 12), at(23, 13)),
        ], now: now, calendar: calendar)
    }

    func testLoadIsHoursNotCount() {
        let days = week(now: at(20, 10, 5))
        XCTAssertEqual(WeekBusy.load(days[0], calendar: calendar), HalfDayLoad(morning: 2, afternoon: 0))
        XCTAssertEqual(WeekBusy.load(days[1], calendar: calendar), HalfDayLoad(morning: 0, afternoon: 4))
        XCTAssertEqual(WeekBusy.load(days[2], calendar: calendar), HalfDayLoad(morning: 0, afternoon: 1),
                       "全天日程不算占用")
        XCTAssertEqual(WeekBusy.busyHours(days[0], calendar: calendar), 2, accuracy: 1e-9)
        XCTAssertEqual(WeekBusy.totalHours(days, calendar: calendar), 10, accuracy: 1e-9)
        XCTAssertEqual(WeekBusy.fill(hours: 0), 0)
        XCTAssertEqual(WeekBusy.fill(hours: 1), 0.25, accuracy: 1e-9)
        XCTAssertEqual(WeekBusy.fill(hours: 5), 1)
        XCTAssertEqual(WeekBusy.fill(hours: 0.25), 0.15, accuracy: 1e-9)
        XCTAssertEqual(WeekBusy.hoursText(21.5), "21.5")
        XCTAssertEqual(WeekBusy.hoursText(3), "3")
        XCTAssertEqual(WeekBusy.hoursText(10), "10")
    }

    func testFreestAfternoonIsTheLongestGapLeftThisWeek() {
        let now = at(20, 10, 5)
        let days = week(now: now)
        let free = WeekBusy.freestAfternoon(days, now: now, calendar: calendar)
        XCTAssertEqual(free?.dayIndex, 3)
        XCTAssertEqual(free?.hours ?? 0, 6, accuracy: 1e-9)
        XCTAssertEqual(free.map { WeekBusy.freeTitle($0, todayIndex: 1) }, "周四下午空")
        // 周四放假：换成周五 13:00 以后。
        let friday = WeekBusy.freestAfternoon(days, now: now, workdays: [0, 1, 2, 4], calendar: calendar)
        XCTAssertEqual(friday?.dayIndex, 4)
        XCTAssertEqual(friday?.start, at(23, 13))
        XCTAssertEqual(friday?.hours ?? 0, 5, accuracy: 1e-9)
    }

    func testPastAfternoonsDoNotCount() {
        // 周五 17:00：周五下午只剩 1 小时，之前的日子都过去了。
        let now = at(23, 17)
        let free = WeekBusy.freestAfternoon(week(now: now), now: now, calendar: calendar)
        XCTAssertEqual(free?.dayIndex, 4)
        XCTAssertEqual(free?.hours ?? 0, 1, accuracy: 1e-9)
        XCTAssertEqual(free.map { WeekBusy.freeTitle($0, todayIndex: 4) }, "今天下午空")
        // 周五 17:45：不到半小时，不算。
        XCTAssertNil(WeekBusy.freestAfternoon(week(now: at(23, 17, 45)), now: at(23, 17, 45), calendar: calendar))
    }

    func testTodayCountsFromNow() {
        let now = at(20, 15)
        let free = WeekBusy.longestFreeAfternoon(week(now: now)[1], now: now, calendar: calendar)
        XCTAssertEqual(free?.start, at(20, 17))
        XCTAssertEqual(free?.hours ?? 0, 1, accuracy: 1e-9)
    }

    func testFreeNote() {
        let now = at(19, 8)
        let days = week(now: now)
        XCTAssertEqual(WeekBusy.freeNote(days[3], now: now, calendar: calendar), "11:30 以后全空")
        XCTAssertEqual(WeekBusy.freeNote(days[1], now: now, calendar: calendar), "17:00 以后全空")
        XCTAssertEqual(WeekBusy.freeNote(days[5], now: now, calendar: calendar), "全天空")
        let late = WeekAgenda.days([entry("a", at(21, 12), at(21, 14)), entry("b", at(21, 17), at(21, 19))],
                                   now: now, calendar: calendar)
        XCTAssertEqual(WeekBusy.freeNote(late[2], now: now, calendar: calendar), "下午 14:00-17:00 空")
    }
}

private func cn(_ key: String, hour: Int = 9) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = ChineseCalendar.zone
    let day = ChineseCalendar.day(key)!
    return calendar.date(byAdding: .hour, value: hour, to: day)!
}

final class LunarCardTests: XCTestCase {
    private let known = HolidaySchedule.bundled

    private func breaks(_ now: Date) -> [HolidayBreak] {
        let year = ChineseCalendar.gregorian.component(.year, from: now)
        return HolidaySchedule.breaks(years: year...(year + 1), known: known)
    }

    private func headline(_ key: String, hour: Int = 9, lead: Int = 7, showTerm: Bool = true,
                          workAlert: Bool = true) -> LunarCard.Headline {
        let now = cn(key, hour: hour)
        return LunarCard.headline(now: now, known: known, breaks: breaks(now), leadDays: lead,
                                  showTerm: showTerm, workAlert: workAlert)
    }

    func testLeadDaysSetting() {
        XCTAssertEqual(LunarCard.leadDays(WidgetConfig()), 7)
        XCTAssertEqual(LunarCard.leadDays(WidgetConfig(["workAlertLead": .string("14")])), 14)
        XCTAssertEqual(LunarCard.leadDays(WidgetConfig(["workAlertLead": .string("3")])), 3)
        XCTAssertEqual(LunarCard.leadDays(WidgetConfig(["workAlertLead": .string("5")])), 7)
        XCTAssertEqual(WidgetCatalog.configurableKeys(.lunar), ["showAlmanac", "showTerm", "workAlert", "workAlertLead"])
        XCTAssertFalse(WidgetCatalog.applies("workAlertLead", to: WidgetConfig(["workAlert": .bool(false)]), kind: .lunar))
        XCTAssertTrue(WidgetCatalog.applies("workAlertLead", to: WidgetConfig(), kind: .lunar))
    }

    func testMakeupWorkdayComesFirstWithinTheLead() {
        // 2026-10-04 周日，还在国庆假期里；10-10 周六补班，6 天后。
        let now = cn("2026-10-04")
        let item = headline("2026-10-04")
        XCTAssertTrue(item.isAlert)
        XCTAssertEqual(LunarCard.title(item, now: now), "下周六要上班")
        XCTAssertEqual(LunarCard.caption(item, now: now), "10月10日 调休补班")
        // 提前 3 天时还没到，显示假期第几天。
        let quiet = headline("2026-10-04", lead: 3)
        XCTAssertFalse(quiet.isAlert)
        XCTAssertEqual(LunarCard.title(quiet, now: now), "国庆假期第 4 天")
        XCTAssertEqual(LunarCard.caption(quiet, now: now), "还剩 3 天")
        // 关掉调休提醒也不显示。
        XCTAssertFalse(headline("2026-10-04", workAlert: false).isAlert)
    }

    func testMakeupWordingByDistance() {
        XCTAssertEqual(LunarCard.title(headline("2026-10-09"), now: cn("2026-10-09")), "明天要上班")
        XCTAssertEqual(LunarCard.title(headline("2026-10-10"), now: cn("2026-10-10")), "今天调休上班")
        // 2026-09-14 周一，09-20 周日补班，同一周。
        XCTAssertEqual(LunarCard.title(headline("2026-09-14"), now: cn("2026-09-14")), "本周日要上班")
        // 提前 14 天：09-06 周日看 09-20，隔两周。
        XCTAssertEqual(LunarCard.title(headline("2026-09-06", lead: 14), now: cn("2026-09-06")), "14 天后要上班")
        // 过了补班日就不再提。
        XCTAssertFalse(headline("2026-10-11").isAlert)
    }

    func testSolarTermAndFestivalDays() {
        let frost = ChineseCalendar.solarTerms(year: 2026).first { $0.name == "霜降" }!.day
        let key = ChineseCalendar.key(frost)
        let item = headline(key)
        XCTAssertEqual(item, .special(name: "霜降"))
        XCTAssertEqual(LunarCard.title(item, now: cn(key)), "今日霜降")
        XCTAssertEqual(LunarCard.caption(item, now: cn(key)), "农历" + ChineseCalendar.lunar(cn(key)).short)
        // 不显示节气时，那天是平常的倒计时。
        if case .countdown = headline(key, showTerm: false) {} else { XCTFail("expected countdown") }

        let chongyang = ChineseCalendar.gregorianDay(lunarMonth: 9, day: 9, inGregorianYear: 2026)!
        XCTAssertEqual(headline(ChineseCalendar.key(chongyang)), .special(name: "重阳节"))
    }

    func testCountdownToTheNextHoliday() {
        // 2026-06-01：端午 06-19 起放 3 天。
        let now = cn("2026-06-01")
        let item = headline("2026-06-01")
        guard case .countdown(let next) = item else { return XCTFail("expected countdown, got \(item)") }
        XCTAssertEqual(next.name, "端午节")
        XCTAssertEqual(LunarCard.title(item, now: now), "端午还有 18 天")
        XCTAssertEqual(LunarCard.caption(item, now: now), "6月19日起 连放 3 天")
    }

    func testEveReminderIsTheNightBefore() {
        let eve = LunarCard.eveReminder(now: cn("2026-10-05"), known: known)
        XCTAssertEqual(eve?.workday, ChineseCalendar.day("2026-10-10"))
        XCTAssertEqual(eve?.fire, cn("2026-10-09", hour: 20))
        XCTAssertEqual(eve?.holiday, "国庆节")
        XCTAssertNil(LunarCard.eveReminder(now: cn("2026-10-09", hour: 21), known: known))
        // 离补班还有三周：不排。
        XCTAssertNil(LunarCard.eveReminder(now: cn("2026-08-25"), known: known))
    }

    func testMonthGridMarksOffAndWorkDays() {
        XCTAssertEqual(LunarCard.leadingBlanks(year: 2026, month: 10), 3, "10 月 1 日是周四")
        let cells = LunarCard.month(year: 2026, month: 10, now: cn("2026-10-18"), known: known, showTerm: true)
        XCTAssertEqual(cells.count, 31)
        XCTAssertEqual(cells[0].mark, .off)
        XCTAssertEqual(cells[0].sub, "国庆")
        XCTAssertTrue(cells[0].subIsSpecial)
        XCTAssertEqual(cells[1].mark, .off)
        XCTAssertFalse(cells[1].subIsSpecial)
        XCTAssertEqual(cells[6].mark, .off)
        XCTAssertEqual(cells[7].mark, .none)
        XCTAssertEqual(cells[9].mark, .work, "10 月 10 日补班")
        XCTAssertTrue(cells[17].isToday)
        XCTAssertTrue(cells[9].isWeekend)
        let frost = ChineseCalendar.solarTerms(year: 2026).first { $0.name == "霜降" }!.day
        let index = ChineseCalendar.gregorian.component(.day, from: frost) - 1
        XCTAssertEqual(cells[index].sub, "霜降")
        let noTerms = LunarCard.month(year: 2026, month: 10, now: cn("2026-10-18"), known: known, showTerm: false)
        XCTAssertNotEqual(noTerms[index].sub, "霜降")
    }

    func testUpcomingMixesTermsAndHolidays() {
        let now = cn("2026-10-18")
        let items = LunarCard.upcoming(now: now, breaks: breaks(now), showTerm: true)
        XCTAssertEqual(items.first?.title, "霜降", "霜降是 10 月 23 日前后，比立冬早")
        XCTAssertEqual(items.first?.isHoliday, false)
        XCTAssertEqual(items.dropFirst().first?.isHoliday, true)
        XCTAssertEqual(items.map(\.date), items.map(\.date).sorted())
        let midHoliday = LunarCard.upcoming(now: cn("2026-10-03"), breaks: breaks(cn("2026-10-03")), showTerm: false)
        XCTAssertEqual(midHoliday.first?.title, "国庆 · 放 7 天")
        XCTAssertLessThan(midHoliday.first?.days ?? 0, 0)
    }
}
