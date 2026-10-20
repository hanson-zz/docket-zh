import Foundation
import XCTest
@testable import Docket

/// 日历面板：一周条圆点、时间轴范围和空档、接下来、快速新建的预设和冲突、拖两端改时间，
/// 以及「写一句」的中文解析。时刻都按 2026-10-20 周二 10:23（上海时区）。
final class CalendarPlannerTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private var now: Date { at(20, 10, 23) }

    private func entry(_ id: String, _ start: Date, _ end: Date, allDay: Bool = false) -> WeekEntry {
        WeekEntry(id: id, title: id, start: start, end: end, isAllDay: allDay)
    }

    private var today: [WeekEntry] {
        [entry("设计评审", at(20, 9, 30), at(20, 10, 15)),
         entry("和小周对稿", at(20, 11), at(20, 12)),
         entry("需求会", at(20, 14), at(20, 15, 30)),
         entry("取快递", at(20, 16, 30), at(20, 17, 30))]
    }

    // MARK: 一周条

    func testDotsCapAtThree() {
        XCTAssertEqual(CalendarPlanner.dots(0), 0)
        XCTAssertEqual(CalendarPlanner.dots(2), 2)
        XCTAssertEqual(CalendarPlanner.dots(7), 3)
        XCTAssertEqual(CalendarPlanner.dots(-1), 0)
    }

    func testEntriesOnDayPutAllDayLast() {
        let all = today + [entry("交付", at(20, 0), at(21, 0), allDay: true), entry("明天", at(21, 9), at(21, 10))]
        let ids = CalendarPlanner.entries(on: now, all, calendar: calendar).map(\.id)
        XCTAssertEqual(ids, ["设计评审", "和小周对稿", "需求会", "取快递", "交付"])
        XCTAssertFalse(CalendarPlanner.entries(on: now, all, includeAllDay: false, calendar: calendar).map(\.id).contains("交付"))
    }

    func testHeadlineAndDayLabels() {
        XCTAssertEqual(CalendarPlanner.headline(day: now, now: now, count: 4, calendar: calendar), "10 月 · 今天 4 个日程")
        XCTAssertEqual(CalendarPlanner.headline(day: at(22, 0), now: now, count: 0, calendar: calendar), "10 月 · 后天没有日程")
        XCTAssertEqual(CalendarPlanner.dayLabel(at(21, 9), now: now, calendar: calendar), "明天")
        XCTAssertEqual(CalendarPlanner.dayLabel(at(19, 9), now: now, calendar: calendar), "昨天")
        XCTAssertEqual(CalendarPlanner.dayLabel(at(23, 9), now: now, calendar: calendar), "周五")
        XCTAssertEqual(CalendarPlanner.dayLabel(at(25, 9), now: now, calendar: calendar), "周日")
        XCTAssertEqual(CalendarPlanner.dayLabel(at(3, 9, month: 11), now: now, calendar: calendar), "11月3日")
    }

    // MARK: 时间轴

    func testHourRangeDefaultsAndGrows() {
        XCTAssertEqual(CalendarPlanner.hourRange(today, day: now, now: now, calendar: calendar), 9...18)
        let late = today + [entry("晚饭", at(20, 19), at(20, 20, 30))]
        XCTAssertEqual(CalendarPlanner.hourRange(late, day: now, now: now, calendar: calendar), 9...21)
        // 看今天、现在是早上 7 点：轴从 7 点起，红线画得出来。
        XCTAssertEqual(CalendarPlanner.hourRange([], day: now, now: at(20, 7, 10), calendar: calendar), 7...18)
        // 别的日子不管现在几点。
        XCTAssertEqual(CalendarPlanner.hourRange([], day: at(22, 0), now: at(20, 22), calendar: calendar), 9...18)
    }

    func testOffsetIsHoursFromAxisStart() {
        XCTAssertEqual(CalendarPlanner.offset(at(20, 10, 30), hours: 9...18, day: now, calendar: calendar), 1.5, accuracy: 0.001)
        XCTAssertEqual(CalendarPlanner.offset(at(20, 7), hours: 9...18, day: now, calendar: calendar), 0)
        XCTAssertEqual(CalendarPlanner.offset(at(20, 20), hours: 9...18, day: now, calendar: calendar), 9)
    }

    func testGapsAreFutureFreeSpansOfThirtyMinutesOrMore() {
        let gaps = CalendarPlanner.gaps(today, day: now, hours: 9...18, now: now, calendar: calendar)
        // 10:25 到 11:00（现在往后取整到 5 分钟）、12:00 到 14:00；15:30 到 16:30；17:30 到 18:00。
        XCTAssertEqual(gaps.map(\.start), [at(20, 10, 25), at(20, 12), at(20, 15, 30), at(20, 17, 30)])
        XCTAssertEqual(gaps.map(\.end), [at(20, 11), at(20, 14), at(20, 16, 30), at(20, 18)])
        XCTAssertEqual(CalendarPlanner.gapTitle(gaps[1]), "空档 2 小时")
        XCTAssertEqual(CalendarPlanner.rangeText(gaps[1].start, gaps[1].end, calendar: calendar), "12:00 至 14:00")
    }

    func testShortGapsAndOtherDaysHaveNoFocus() {
        let tight = [entry("a", at(20, 10, 30), at(20, 11)), entry("b", at(20, 11, 20), at(20, 18))]
        XCTAssertTrue(CalendarPlanner.gaps(tight, day: now, hours: 9...18, now: now, calendar: calendar).isEmpty)
        XCTAssertTrue(CalendarPlanner.gaps([], day: at(21, 0), hours: 9...18, now: now, calendar: calendar).isEmpty)
        // 已经过了轴的终点。
        XCTAssertTrue(CalendarPlanner.gaps([], day: now, hours: 9...18, now: at(20, 18, 10), calendar: calendar).isEmpty)
        // 全天日程不占空档。
        let allDay = [entry("x", at(20, 0), at(21, 0), allDay: true)]
        XCTAssertEqual(CalendarPlanner.gaps(allDay, day: now, hours: 9...18, now: now, calendar: calendar).count, 1)
    }

    func testFocusMinutesFitTheGap() {
        let gap = DateInterval(start: at(20, 12), end: at(20, 14))
        XCTAssertEqual(CalendarPlanner.focusMinutes(gap, now: now, preferred: 25), 25)
        let short = DateInterval(start: at(20, 10, 25), end: at(20, 11))
        XCTAssertEqual(CalendarPlanner.focusMinutes(short, now: at(20, 10, 40), preferred: 25), 20)
        XCTAssertEqual(CalendarPlanner.focusMinutes(short, now: at(20, 10, 58), preferred: 25), 5)
    }

    // MARK: 接下来

    func testUpcomingStartsTomorrow() {
        let all = today + [entry("牙医复诊", at(21, 9, 30), at(21, 10, 30)),
                           entry("交付首页稿", at(22, 0), at(23, 0), allDay: true),
                           entry("周会", at(26, 10), at(26, 11)),
                           entry("远", at(5, 10, month: 11), at(5, 11, month: 11))]
        let items = CalendarPlanner.upcoming(all, now: now, calendar: calendar)
        XCTAssertEqual(items.map(\.entry.id), ["牙医复诊", "交付首页稿", "周会"])
        XCTAssertEqual(items.map(\.day), ["明天", "后天", "周一"])
        XCTAssertEqual(items.map(\.time), ["09:30", "全天", "10:00"])
    }

    // MARK: 快速新建

    func testDefaultStartIsNextHalfHourTodayOrNineOtherwise() {
        XCTAssertEqual(CalendarPlanner.defaultStart(day: now, now: now, calendar: calendar), at(20, 10, 30))
        XCTAssertEqual(CalendarPlanner.defaultStart(day: now, now: at(20, 10, 30), calendar: calendar), at(20, 11))
        XCTAssertEqual(CalendarPlanner.defaultStart(day: at(22, 0), now: now, calendar: calendar), at(22, 9))
        XCTAssertEqual(CalendarPlanner.defaultStart(day: now, now: at(20, 23, 50), calendar: calendar), at(20, 23, 30))
    }

    func testPresetsMakeSlots() {
        let start = at(20, 15, 30)
        XCTAssertEqual(CalendarPlanner.slot(.half, start: start, calendar: calendar).end, at(20, 16))
        XCTAssertEqual(CalendarPlanner.slot(.twoHours, start: start, calendar: calendar).end, at(20, 17, 30))
        let allDay = CalendarPlanner.slot(.allDay, start: start, calendar: calendar)
        XCTAssertEqual(allDay, CalendarPlanner.Slot(start: at(20, 0), end: at(21, 0), isAllDay: true))
        XCTAssertEqual(CalendarPlanner.length(of: allDay), .allDay)
        XCTAssertEqual(CalendarPlanner.length(of: CalendarPlanner.slot(.hour, start: start, calendar: calendar)), .hour)
        XCTAssertNil(CalendarPlanner.length(of: CalendarPlanner.Slot(start: start, end: at(20, 15, 45))))
        XCTAssertEqual(CalendarPlanner.Length.allCases.map(\.title), ["30 分钟", "1 小时", "2 小时", "全天"])
    }

    func testConflicts() {
        let free = CalendarPlanner.Slot(start: at(20, 15, 30), end: at(20, 16))
        XCTAssertTrue(CalendarPlanner.conflicts(free, in: today).isEmpty)
        // 离得最近的是刚结束的需求会。
        XCTAssertEqual(CalendarPlanner.conflictLine(free, in: today, calendar: calendar).text, "和「需求会」不冲突")
        XCTAssertFalse(CalendarPlanner.conflictLine(free, in: today, calendar: calendar).clash)

        let clash = CalendarPlanner.Slot(start: at(20, 15), end: at(20, 16))
        XCTAssertEqual(CalendarPlanner.conflicts(clash, in: today).map(\.id), ["需求会"])
        XCTAssertEqual(CalendarPlanner.conflictLine(clash, in: today, calendar: calendar).text, "和「需求会」冲突")
        XCTAssertTrue(CalendarPlanner.conflictLine(clash, in: today, calendar: calendar).clash)

        let wide = CalendarPlanner.Slot(start: at(20, 10), end: at(20, 15))
        XCTAssertEqual(CalendarPlanner.conflictLine(wide, in: today, calendar: calendar).text, "和「设计评审」等 3 个日程冲突")

        // 正在改的那个自己不算。
        let own = CalendarPlanner.Slot(start: at(20, 14, 15), end: at(20, 15))
        XCTAssertTrue(CalendarPlanner.conflicts(own, in: today, excluding: "需求会").isEmpty)

        XCTAssertEqual(CalendarPlanner.conflictLine(free, in: [], calendar: calendar).text, "这段时间没有别的日程")
        let allDay = CalendarPlanner.slot(.allDay, start: now, calendar: calendar)
        XCTAssertFalse(CalendarPlanner.conflictLine(allDay, in: today, calendar: calendar).clash)
    }

    // MARK: 拖两端

    func testDragSnapsAndKeepsFifteenMinutes() {
        let start = at(20, 10, 15), end = at(20, 11)
        XCTAssertEqual(CalendarPlanner.drag(start: start, end: end, edge: .start, to: at(20, 9, 52), calendar: calendar).start,
                       at(20, 9, 45))
        XCTAssertEqual(CalendarPlanner.drag(start: start, end: end, edge: .end, to: at(20, 11, 38), calendar: calendar).end,
                       at(20, 11, 45))
        // 拖过头：至少留 15 分钟。
        XCTAssertEqual(CalendarPlanner.drag(start: start, end: end, edge: .start, to: at(20, 12), calendar: calendar).start,
                       at(20, 10, 45))
        XCTAssertEqual(CalendarPlanner.drag(start: start, end: end, edge: .end, to: at(20, 8), calendar: calendar).end,
                       at(20, 10, 30))
        // 不跨出这一天。
        XCTAssertEqual(CalendarPlanner.drag(start: at(20, 23), end: at(20, 23, 30), edge: .end, to: at(21, 1),
                                            calendar: calendar).end, at(21, 0))
    }

    func testEditHours() {
        XCTAssertEqual(CalendarPlanner.editHours(start: at(20, 10, 15), end: at(20, 11), calendar: calendar), 9...12)
        XCTAssertEqual(CalendarPlanner.editHours(start: at(20, 14), end: at(20, 17, 30), calendar: calendar), 13...19)
        XCTAssertEqual(CalendarPlanner.editHours(start: at(20, 23), end: at(21, 0), calendar: calendar), 21...24)
        XCTAssertEqual(CalendarPlanner.editHours(start: at(20, 0, 10), end: at(20, 0, 40), calendar: calendar), 0...3)
    }

    // MARK: 写一句

    private func parse(_ text: String, now: Date? = nil) -> CalendarSentence? {
        CalendarSentence.parse(text, now: now ?? self.now, calendar: calendar)
    }

    func testTomorrowAfternoon() {
        let s = parse("明天下午 3 点开会")
        XCTAssertEqual(s?.title, "开会")
        XCTAssertEqual(s?.slot, CalendarPlanner.Slot(start: at(21, 15), end: at(21, 16)))
        XCTAssertEqual(s?.understood, true)
    }

    func testRelativeDays() {
        XCTAssertEqual(parse("今天上午10点 写周报")?.slot.start, at(20, 10))
        XCTAssertEqual(parse("后天晚上8点吃饭")?.slot.start, at(22, 20))
        XCTAssertEqual(parse("后天晚上8点吃饭")?.title, "吃饭")
        XCTAssertEqual(parse("大后天9点体检")?.slot.start, at(23, 9))
        XCTAssertEqual(parse("今晚7点半看电影")?.slot.start, at(20, 19, 30))
    }

    func testWeekdays() {
        // 今天周二：周四是这周四，周一已经过了是下周一，周二就是今天。
        XCTAssertEqual(parse("周四下午2点评审")?.slot.start, at(22, 14))
        XCTAssertEqual(parse("周一 9点 例会")?.slot.start, at(26, 9))
        XCTAssertEqual(parse("周二 下午4点 复盘")?.slot.start, at(20, 16))
        XCTAssertEqual(parse("下周三上午十点面试")?.slot.start, at(28, 10))
        XCTAssertEqual(parse("下周三上午十点面试")?.title, "面试")
        XCTAssertEqual(parse("星期五晚上聚餐")?.slot.start, at(23, 19))
        XCTAssertEqual(parse("下周日 爬山")?.slot, CalendarPlanner.Slot(start: at(1, 0, month: 11), end: at(2, 0, month: 11),
                                                                     isAllDay: true))
        XCTAssertEqual(parse("这周一 补记账")?.slot.start, at(19, 0))
    }

    func testHalfHoursAndMinutes() {
        XCTAssertEqual(parse("明天3点半开会")?.slot.start, at(21, 15, 30))
        XCTAssertEqual(parse("明天上午九点一刻 晨会")?.slot.start, at(21, 9, 15))
        XCTAssertEqual(parse("十点十分 打电话")?.slot.start, at(20, 10, 10))
        XCTAssertEqual(parse("15:45 交稿")?.slot.start, at(20, 15, 45))
        XCTAssertEqual(parse("下午3点15分 开会")?.slot.start, at(20, 15, 15))
    }

    func testRanges() {
        let s = parse("明天下午3点到5点 需求会")
        XCTAssertEqual(s?.slot, CalendarPlanner.Slot(start: at(21, 15), end: at(21, 17)))
        XCTAssertEqual(s?.title, "需求会")
        XCTAssertEqual(parse("周四 9点至11点半 培训")?.slot, CalendarPlanner.Slot(start: at(22, 9), end: at(22, 11, 30)))
        XCTAssertEqual(parse("3-5点 写代码")?.slot, CalendarPlanner.Slot(start: at(20, 15), end: at(20, 17)))
        XCTAssertEqual(parse("上午11点到1点 午餐会")?.slot, CalendarPlanner.Slot(start: at(20, 11), end: at(20, 13)))
        XCTAssertEqual(parse("晚上8点到10点 加班")?.slot, CalendarPlanner.Slot(start: at(20, 20), end: at(20, 22)))
    }

    func testPeriodsWithoutClock() {
        XCTAssertEqual(parse("明天下午 开会")?.slot.start, at(21, 14))
        XCTAssertEqual(parse("明天上午 开会")?.slot.start, at(21, 9))
        XCTAssertEqual(parse("明晚 看球")?.slot.start, at(21, 19))
        XCTAssertEqual(parse("中午12点 午饭")?.slot.start, at(20, 12))
        XCTAssertEqual(parse("中午1点 午饭")?.slot.start, at(20, 13))
    }

    func testNoPeriodMeansAfternoonForSmallHours() {
        XCTAssertEqual(parse("3点开会")?.slot.start, at(20, 15))
        XCTAssertEqual(parse("9点开会")?.slot.start, at(20, 9))
        XCTAssertEqual(parse("凌晨2点 赶飞机")?.slot.start, at(20, 2))
        XCTAssertEqual(parse("上午6点 跑步")?.slot.start, at(20, 6))
    }

    func testDayOnlyIsAllDayAndDates() {
        XCTAssertEqual(parse("明天 交报告")?.slot, CalendarPlanner.Slot(start: at(21, 0), end: at(22, 0), isAllDay: true))
        XCTAssertEqual(parse("10月25日 生日")?.slot.isAllDay, true)
        XCTAssertEqual(parse("10月25日 生日")?.slot.start, at(25, 0))
        XCTAssertEqual(parse("10月25号下午2点 看展")?.slot.start, at(25, 14))
        XCTAssertEqual(parse("明天全天 出差")?.slot.isAllDay, true)
        XCTAssertEqual(parse("明天全天 出差")?.title, "出差")
    }

    func testTitleOnlyAndEmpty() {
        let s = parse("买菜")
        XCTAssertEqual(s?.title, "买菜")
        XCTAssertEqual(s?.understood, false)
        XCTAssertEqual(s?.slot.start, at(20, 10, 30))
        XCTAssertNil(parse("   "))
        XCTAssertEqual(parse("明天下午3点")?.title, "新日程")
        // 地点里的「3号」不当成钟点。
        XCTAssertEqual(parse("明天下午2点 3号会议室开会")?.title, "3号会议室开会")
        XCTAssertEqual(parse("提醒我明天9点 交水费")?.title, "交水费")
    }

    func testChineseNumbers() {
        XCTAssertEqual(CalendarSentence.number("十"), 10)
        XCTAssertEqual(CalendarSentence.number("十二"), 12)
        XCTAssertEqual(CalendarSentence.number("二十五"), 25)
        XCTAssertEqual(CalendarSentence.number("两"), 2)
        XCTAssertEqual(CalendarSentence.number("7"), 7)
        XCTAssertNil(CalendarSentence.number("百"))
    }
}
