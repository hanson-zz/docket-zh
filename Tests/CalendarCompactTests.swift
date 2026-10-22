import Foundation
import XCTest
@testable import Docket

/// 日历面板的两处压缩：时间轴空段折叠（`AgendaFold` / `AgendaAxis`）和一周条农历小字（`WeekLunar`）。
/// 时刻按 2026-10-20 周二（上海时区）。
final class CalendarCompactTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 10, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private var day: Date { at(20, 0) }
    /// 别的日子，不保护现在线。
    private var elsewhere: Date { at(22, 15) }

    private func span(_ id: String, _ start: Date, _ end: Date, allDay: Bool = false) -> CalendarSpan {
        CalendarSpan(id: id, start: start, end: end, isAllDay: allDay)
    }

    private typealias Segment = AgendaFold.Segment

    private func plain(_ start: Int, _ end: Int) -> Segment { Segment(kind: .hours, start: start, end: end) }
    private func free(_ start: Int, _ end: Int) -> Segment { Segment(kind: .free, start: start, end: end) }
    private func collapse(_ at: Int) -> Segment { Segment(kind: .collapse, start: at, end: at) }

    private func segments(_ spans: [CalendarSpan], _ hours: ClosedRange<Int> = 9...18, now: Date? = nil,
                          expanded: Set<Int> = []) -> [Segment] {
        AgendaFold.segments(spans, hours: hours, day: day, now: now ?? elsewhere, expanded: expanded, calendar: calendar)
    }

    // MARK: 折叠

    func testNoEventsFoldsWholeAxisAndReportsNoTimed() {
        XCTAssertFalse(AgendaFold.hasTimed([], day: day, calendar: calendar))
        XCTAssertEqual(segments([]), [free(9, 18)])
        XCTAssertEqual(AgendaFold.emptyLine(day: day, now: at(20, 10), hasAllDay: false, calendar: calendar),
                       "今天没有日程，安排点什么吧")
        XCTAssertEqual(AgendaFold.emptyLine(day: day, now: elsewhere, hasAllDay: false, calendar: calendar), "这天没有日程")
    }

    func testBusyDayFoldsOnlyTwoHourStretches() {
        let spans = [span("评审", at(20, 9, 30), at(20, 10, 15)), span("对稿", at(20, 11), at(20, 12)),
                     span("需求会", at(20, 14), at(20, 15, 30)), span("快递", at(20, 16, 30), at(20, 17, 30))]
        XCTAssertTrue(AgendaFold.hasTimed(spans, day: day, calendar: calendar))
        // 12、13 点空着，正好 2 小时，折；17:30 到 18 点不够一个整点空着，不折。
        XCTAssertEqual(segments(spans, now: at(20, 10, 23)), [plain(9, 12), free(12, 14), plain(14, 18)])
        XCTAssertEqual(segments(spans), [plain(9, 12), free(12, 14), plain(14, 18)])
    }

    func testSingleFreeHourIsNotFolded() {
        let spans = [span("a", at(20, 9), at(20, 10)), span("b", at(20, 11), at(20, 12))]
        XCTAssertEqual(segments(spans, 9...12), [plain(9, 12)])
    }

    func testEventEndingOnTheHourLeavesNextHourFree() {
        let spans = [span("午饭", at(20, 12), at(20, 13))]
        XCTAssertEqual(segments(spans), [free(9, 12), plain(12, 13), free(13, 18)])
    }

    func testNowHourAndNextAreNeverFolded() {
        let spans = [span("早会", at(20, 9), at(20, 10))]
        XCTAssertEqual(segments(spans), [plain(9, 10), free(10, 18)])
        // 现在 13:20：13、14 点照常画，两边各剩 3 小时折起来。
        XCTAssertEqual(segments(spans, now: at(20, 13, 20)), [plain(9, 10), free(10, 13), plain(13, 15), free(15, 18)])
        // 现在 11:40：11、12 点不折；10 点只空一个整点，也不折。
        XCTAssertEqual(segments(spans, now: at(20, 11, 40)), [plain(9, 13), free(13, 18)])
        // 现在 17:30：17、18 点保护，18 是轴的终点。
        XCTAssertEqual(segments(spans, now: at(20, 17, 30)), [plain(9, 10), free(10, 17), plain(17, 18)])
    }

    func testExpandedFoldIsDrawnAsHours() {
        let spans = [span("早会", at(20, 9), at(20, 10))]
        // 点开的段照常画，顶上插一条「收起」。
        XCTAssertEqual(segments(spans, now: at(20, 13, 20), expanded: [10]),
                       [plain(9, 10), collapse(10), plain(10, 15), free(15, 18)])
        XCTAssertEqual(segments(spans, now: at(20, 13, 20), expanded: [10, 15]),
                       [plain(9, 10), collapse(10), plain(10, 15), collapse(15), plain(15, 18)])
        // 点开过的起点对不上（比如现在线挪了）时照常折。
        XCTAssertEqual(segments(spans, expanded: [11]), [plain(9, 10), free(10, 18)])
    }

    func testCollapseRefoldsAndStartsAxisWhenFirstHoursAreFree() {
        let spans = [span("午饭", at(20, 12), at(20, 13))]
        // 轴从空闲段开头：「收起」在最上面。
        XCTAssertEqual(segments(spans, expanded: [9]), [collapse(9), plain(9, 13), free(13, 18)])
        // 收起就是把起点从点开的集合里拿掉，回到原来的样子。
        XCTAssertEqual(segments(spans, expanded: []), [free(9, 12), plain(12, 13), free(13, 18)])
        // 只空一个整点的地方没有折叠，也就没有「收起」。
        let tight = [span("a", at(20, 9), at(20, 10)), span("b", at(20, 11), at(20, 12))]
        XCTAssertEqual(segments(tight, 9...12, expanded: [10]), [plain(9, 12)])
    }

    func testOverlappingEventsCountOnce() {
        let spans = [span("a", at(20, 13), at(20, 15)), span("b", at(20, 14, 30), at(20, 16)),
                     span("c", at(20, 14), at(20, 14, 45))]
        XCTAssertEqual(segments(spans), [free(9, 13), plain(13, 16), free(16, 18)])
    }

    func testEventsCrossingMidnightOnlyCountTheirPartOfTheDay() {
        let overnight = span("夜班", at(19, 22), at(20, 2))
        XCTAssertTrue(AgendaFold.hasTimed([overnight], day: day, calendar: calendar))
        XCTAssertEqual(segments([overnight], 0...18), [plain(0, 2), free(2, 18)])
        let late = span("跨年", at(20, 23), at(21, 1))
        XCTAssertEqual(segments([late], 9...24), [free(9, 23), plain(23, 24)])
        // 正好在零点结束的前一天的日程不算这天的。
        let ended = span("昨晚", at(19, 22), at(20, 0))
        XCTAssertFalse(AgendaFold.hasTimed([ended], day: day, calendar: calendar))
        XCTAssertEqual(segments([ended]), [free(9, 18)])
    }

    func testAllDayEventsAreNotOnTheAxis() {
        let allDay = span("出差", at(20, 0), at(21, 0), allDay: true)
        XCTAssertFalse(AgendaFold.hasTimed([allDay], day: day, calendar: calendar))
        XCTAssertEqual(segments([allDay]), [free(9, 18)])
        XCTAssertEqual(AgendaFold.emptyLine(day: day, now: elsewhere, hasAllDay: true, calendar: calendar),
                       "除了全天日程，没有别的安排")
    }

    func testZeroLengthEventStillOccupiesItsHour() {
        let ping = span("提醒", at(20, 13), at(20, 13))
        XCTAssertEqual(segments([ping]), [free(9, 13), plain(13, 14), free(14, 18)])
    }

    func testFreeTitle() {
        XCTAssertEqual(AgendaFold.freeTitle(free(12, 15)), "空闲 3 小时")
        XCTAssertEqual(AgendaFold.freeAccessibility(free(12, 15)), "12 点到 15 点空闲，点按展开")
        XCTAssertEqual(AgendaFold.collapseAccessibility(collapse(12)), "收起 12 点起的空闲")
    }

    func testEmptyFocusGapOnlyForTodayWithTimeLeft() {
        XCTAssertEqual(AgendaFold.emptyFocusGap(day: day, now: at(20, 13, 20), calendar: calendar),
                       DateInterval(start: at(20, 13, 20), end: at(21, 0)))
        // 别的日子不放。
        XCTAssertNil(AgendaFold.emptyFocusGap(day: day, now: elsewhere, calendar: calendar))
        // 离午夜不到 30 分钟不放，正好 30 分钟放。
        XCTAssertNil(AgendaFold.emptyFocusGap(day: day, now: at(20, 23, 40), calendar: calendar))
        XCTAssertEqual(AgendaFold.emptyFocusGap(day: day, now: at(20, 23, 30), calendar: calendar),
                       DateInterval(start: at(20, 23, 30), end: at(21, 0)))
        // 给出的空档交给专注时长：按偏好的 25 分钟，不超过剩下的。
        let gap = AgendaFold.emptyFocusGap(day: day, now: at(20, 13, 20), calendar: calendar)!
        XCTAssertEqual(CalendarPlanner.focusMinutes(gap, now: at(20, 13, 20), preferred: 25), 25)
    }

    // MARK: 折叠后的轴

    func testAxisMapsHoursAcrossFolds() {
        let axis = AgendaAxis(segments: [plain(9, 12), free(12, 14), plain(14, 18)], hourHeight: 30, foldHeight: 28)
        XCTAssertEqual(axis.height, 238, accuracy: 0.001)
        XCTAssertEqual(axis.tops, [0, 90, 118])
        XCTAssertEqual(axis.y(hour: 10.5), 45, accuracy: 0.001)
        XCTAssertEqual(axis.y(hour: 12), 90, accuracy: 0.001)
        XCTAssertEqual(axis.y(hour: 13), 104, accuracy: 0.001)
        XCTAssertEqual(axis.y(hour: 14), 118, accuracy: 0.001)
        XCTAssertEqual(axis.y(hour: 15), 148, accuracy: 0.001)
        XCTAssertEqual(axis.y(hour: 7), 0)
        XCTAssertEqual(axis.y(hour: 20), 238, accuracy: 0.001)
        XCTAssertEqual(axis.y(at(20, 15, 30), day: day, calendar: calendar), 163, accuracy: 0.001)
        XCTAssertEqual(axis.labelHours, [9, 10, 11, 12, 14, 15, 16, 17, 18])
        XCTAssertEqual(AgendaAxis(segments: [], hourHeight: 30).height, 0)
    }

    func testAxisCollapseRowTakesHeightButNoTime() {
        let axis = AgendaAxis(segments: [plain(9, 10), collapse(10), plain(10, 13), free(13, 18)],
                              hourHeight: 30, foldHeight: 28, collapseHeight: 22)
        XCTAssertEqual(axis.height, 30 + 22 + 90 + 28, accuracy: 0.001)
        XCTAssertEqual(axis.tops, [0, 30, 52, 142])
        // 10 点当起点落在细行下面，当终点落在细行上面。
        XCTAssertEqual(axis.y(hour: 10), 52, accuracy: 0.001)
        XCTAssertEqual(axis.y(hour: 10, trailing: true), 30, accuracy: 0.001)
        XCTAssertEqual(axis.y(at(20, 10), day: day, trailing: true, calendar: calendar), 30, accuracy: 0.001)
        XCTAssertEqual(axis.y(hour: 9.5), 15, accuracy: 0.001)
        XCTAssertEqual(axis.y(hour: 11.5), 97, accuracy: 0.001)
        // 别处的整点两种算法一样。
        XCTAssertEqual(axis.y(hour: 13), 142, accuracy: 0.001)
        XCTAssertEqual(axis.y(hour: 13, trailing: true), 142, accuracy: 0.001)
        XCTAssertEqual(axis.y(hour: 18), 170, accuracy: 0.001)
        XCTAssertEqual(axis.y(hour: 18, trailing: true), 170, accuracy: 0.001)
        XCTAssertEqual(axis.y(hour: 9, trailing: true), 0, accuracy: 0.001)
        // 细行不写整点，10 点只写一次。
        XCTAssertEqual(axis.labelHours, [9, 10, 11, 12, 13])
        // 轴一开头就是细行：最早的时刻也落在细行下面。
        let top = AgendaAxis(segments: [collapse(9), plain(9, 12)], hourHeight: 30, collapseHeight: 22)
        XCTAssertEqual(top.y(hour: 9), 22, accuracy: 0.001)
        XCTAssertEqual(top.y(hour: 8), 0)
        XCTAssertEqual(top.y(hour: 12), 112, accuracy: 0.001)
    }

    func testGapIsClippedAtTheFirstFold() {
        let segs = [plain(9, 10), free(10, 13), plain(13, 15), free(15, 18)]
        let gap = DateInterval(start: at(20, 13, 20), end: at(20, 18))
        XCTAssertEqual(AgendaFold.visible(gap, in: segs, day: day, calendar: calendar),
                       DateInterval(start: at(20, 13, 20), end: at(20, 15)))
        // 起点在折叠段里的看不见。
        let hidden = DateInterval(start: at(20, 10, 30), end: at(20, 12))
        XCTAssertNil(AgendaFold.visible(hidden, in: segs, day: day, calendar: calendar))
        // 露出来不到 30 分钟的也不画。
        let sliver = DateInterval(start: at(20, 9, 45), end: at(20, 12))
        XCTAssertNil(AgendaFold.visible(sliver, in: segs, day: day, calendar: calendar))
        // 不碰折叠段的原样返回。
        let whole = DateInterval(start: at(20, 13, 30), end: at(20, 14, 30))
        XCTAssertEqual(AgendaFold.visible(whole, in: segs, day: day, calendar: calendar), whole)
    }

    func testGapAroundCollapseRow() {
        // 早会 9 到 10:20，10 点那一小时忙，11 点起点开了。
        let segs = [plain(9, 11), collapse(11), plain(11, 15), free(15, 18)]
        // 前半截只有 10 分钟：从细行下面开始画，到折叠段为止。
        let short = DateInterval(start: at(20, 10, 50), end: at(20, 18))
        XCTAssertEqual(AgendaFold.visible(short, in: segs, day: day, calendar: calendar),
                       DateInterval(start: at(20, 11), end: at(20, 15)))
        // 前半截够 30 分钟（现在线那一段）：只画前半截。
        let long = DateInterval(start: at(20, 10, 20), end: at(20, 18))
        XCTAssertEqual(AgendaFold.visible(long, in: segs, day: day, calendar: calendar),
                       DateInterval(start: at(20, 10, 20), end: at(20, 11)))
        // 正好从细行开始或整个在细行下面的不受影响。
        let below = DateInterval(start: at(20, 11), end: at(20, 12))
        XCTAssertEqual(AgendaFold.visible(below, in: segs, day: day, calendar: calendar), below)
        let above = DateInterval(start: at(20, 10, 20), end: at(20, 11))
        XCTAssertEqual(AgendaFold.visible(above, in: segs, day: day, calendar: calendar), above)
        // 两条细行：第一条前面不够就跳到它下面，再遇到第二条时前面够了就停。
        let two = [plain(9, 10), collapse(10), plain(10, 13), plain(13, 14), collapse(14), plain(14, 18)]
        let wide = DateInterval(start: at(20, 9, 50), end: at(20, 18))
        XCTAssertEqual(AgendaFold.visible(wide, in: two, day: day, calendar: calendar),
                       DateInterval(start: at(20, 10), end: at(20, 14)))
    }

    // MARK: 一周条农历

    private func cn(_ year: Int, _ month: Int, _ day: Int) -> Date { at(day, 0, month: month, year: year) }

    func testDensityByWidthAndLanguage() {
        XCTAssertEqual(WeekLunar.density(columnWidth: 50, english: false), .full)
        XCTAssertEqual(WeekLunar.density(columnWidth: 36, english: false), .full)
        XCTAssertEqual(WeekLunar.density(columnWidth: 30, english: false), .compact)
        XCTAssertEqual(WeekLunar.density(columnWidth: 20, english: false), .hidden)
        XCTAssertEqual(WeekLunar.density(columnWidth: 50, english: true), .hidden)
        XCTAssertEqual(WeekLunar.density(columnWidth: .nan, english: false), .hidden)
        XCTAssertNil(WeekLunar.label(for: cn(2026, 10, 23), density: .hidden, calendar: calendar))
    }

    func testSolarTermWinsAndUsesTermStyle() {
        let label = WeekLunar.label(for: cn(2026, 10, 23), density: .compact, calendar: calendar)
        XCTAssertEqual(label, WeekLunar.Label("霜降", .term))
    }

    func testHolidayAndMakeupWorkday() {
        // 2026 国庆：10 月 1 日放假，10 月 10 日（周六）调休上班。
        XCTAssertEqual(WeekLunar.label(for: cn(2026, 10, 1), density: .full, calendar: calendar), WeekLunar.Label("休", .holiday))
        XCTAssertEqual(WeekLunar.label(for: cn(2026, 10, 10), density: .compact, calendar: calendar), WeekLunar.Label("班", .makeup))
        // 正月初一（2026-02-17）同时是春节假期：休在前。
        XCTAssertEqual(ChineseCalendar.lunar(cn(2026, 2, 17)).day, 1)
        XCTAssertEqual(WeekLunar.label(for: cn(2026, 2, 17), density: .full, calendar: calendar)?.style, .holiday)
        // 没有安排数据时不标。
        XCTAssertNotEqual(WeekLunar.label(for: cn(2026, 10, 1), density: .full, holidays: [:], calendar: calendar)?.style,
                          .holiday)
    }

    func testFirstDayShowsMonthName() throws {
        // 寒衣节（十月初一）在立冬（11 月 7 日前后）和小雪之间。
        let days = (8...21).map { cn(2026, 11, $0) }
        let first = try XCTUnwrap(days.first { ChineseCalendar.lunar($0).day == 1 })
        XCTAssertEqual(ChineseCalendar.lunar(first).month, 10)
        XCTAssertEqual(WeekLunar.label(for: first, density: .compact, calendar: calendar), WeekLunar.Label("十月", .month))
        // 闰月两个字写不下「闰六月」：2025-07-25 是闰六月初一。
        XCTAssertEqual(WeekLunar.label(for: cn(2025, 7, 25), density: .full, holidays: [:], calendar: calendar),
                       WeekLunar.Label("闰六", .month))
    }

    func testOrdinaryDayShowsDayNameOnlyWhenWide() throws {
        let date = cn(2026, 10, 21)
        let lunar = ChineseCalendar.lunar(date)
        try XCTSkipIf(lunar.day == 1 || ChineseCalendar.term(on: date) != nil)
        XCTAssertEqual(WeekLunar.label(for: date, density: .full, calendar: calendar), WeekLunar.Label(lunar.dayName, .day))
        XCTAssertNil(WeekLunar.label(for: date, density: .compact, calendar: calendar))
        // 所有标签都不超过两个字，13pt 下 36pt 宽的一列放得下。
        for offset in 0..<400 {
            let d = calendar.date(byAdding: .day, value: offset, to: cn(2025, 1, 1))!
            let text = WeekLunar.label(for: d, density: .full, calendar: calendar)?.text ?? ""
            XCTAssertLessThanOrEqual(text.count, 2, text)
        }
    }

    func testWeekLabelsAcrossYearAndLocalDayInOtherZones() {
        // 东京零点在上海还是前一天 23 点：按墙上的日期对齐，仍是霜降。
        var tokyo = calendar
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let midnight = tokyo.date(from: DateComponents(year: 2026, month: 10, day: 23))!
        XCTAssertEqual(WeekLunar.label(for: midnight, density: .compact, calendar: tokyo)?.text, "霜降")
        // 一周七天一起算，跨年那周也对（2026-12-28 到 2027-01-03，小寒在 1 月 5 日前后不在内）。
        let week = (0..<7).map { calendar.date(byAdding: .day, value: $0, to: cn(2026, 12, 28))! }
        let labels = WeekLunar.labels(for: week, density: .full, calendar: calendar)
        for date in week {
            XCTAssertEqual(labels[date], WeekLunar.label(for: date, density: .full, calendar: calendar))
        }
        XCTAssertTrue(WeekLunar.labels(for: week, density: .hidden, calendar: calendar).isEmpty)
    }
}
