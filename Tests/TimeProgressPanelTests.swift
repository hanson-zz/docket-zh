import XCTest

/// 时间进度面板：今年每一天的标记、接下来的节点、一句话，剩几个周末和工作日。
/// 示例时刻 2026-10-20 周二 10:24，节假日用内置的 2026 年通知。
final class TimeProgressPanelTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    private var now: Date { date(2026, 10, 20, 10, 24) }
    private let known = HolidaySchedule.bundled

    func testWeekAlwaysStartsOnMonday() {
        XCTAssertEqual(TimeProgress.calendar.firstWeekday, 2)
        XCTAssertEqual(TimeProgress.interval(.week, now: now, calendar: calendar)?.start, date(2026, 10, 19))
        XCTAssertEqual(TimeProgress.mondayIndex(date(2026, 10, 19), calendar: calendar), 0)
        XCTAssertEqual(TimeProgress.mondayIndex(date(2026, 10, 25), calendar: calendar), 6)
    }

    func testYearDaysMarkHolidaysMakeupDaysAndToday() {
        let days = TimeProgress.yearDays(now: now, known: known, calendar: calendar)
        XCTAssertEqual(days.count, 365)
        XCTAssertEqual(days.first?.weekday, 3, "2026 年 1 月 1 日是周四")
        func day(_ m: Int, _ d: Int) -> TimeProgress.YearDay? { days.first { $0.month == m && $0.day == d } }
        XCTAssertEqual(day(10, 20)?.mark, .today)
        XCTAssertEqual(day(10, 20)?.ordinal, 293)
        XCTAssertEqual(day(10, 1)?.mark, .holiday)
        XCTAssertEqual(day(10, 1)?.isPast, true)
        XCTAssertEqual(day(10, 10)?.mark, .makeupWorkday)
        XCTAssertEqual(day(1, 4)?.mark, .makeupWorkday)
        XCTAssertEqual(day(10, 19)?.mark, .past)
        XCTAssertEqual(day(10, 21)?.mark, .future)
        XCTAssertEqual(day(12, 31)?.mark, .future)
    }

    func testAnniversariesComeFromTheAnniversaryCard() {
        let events = [
            AnniversaryEvent(title: "生日", day: "19900601", kind: .countdown, yearly: true),
            AnniversaryEvent(title: "纪念", day: "20251128", kind: .countup, yearly: true),
            AnniversaryEvent(title: "明年", day: "20270101"),
            AnniversaryEvent(title: "今天", day: "20261020", yearly: false),
        ]
        let days = TimeProgress.yearDays(now: now, known: known, anniversaries: events, calendar: calendar)
        func day(_ m: Int, _ d: Int) -> TimeProgress.YearDay? { days.first { $0.month == m && $0.day == d } }
        XCTAssertEqual(day(6, 1)?.mark, .anniversary)
        XCTAssertEqual(day(11, 28)?.mark, .anniversary)
        XCTAssertEqual(day(10, 20)?.mark, .today, "今天优先")
        XCTAssertEqual(days.filter { $0.mark == .anniversary }.count, 2)
        // 没有纪念日卡片就什么都不标。
        XCTAssertTrue(TimeProgress.yearDays(now: now, known: known, calendar: calendar)
            .allSatisfy { $0.mark != .anniversary })
        // 每年的纪念日，第一次还没到的年份不标。
        let future = [AnniversaryEvent(title: "以后", day: "20280301", yearly: true)]
        XCTAssertTrue(TimeProgress.anniversaryKeys(future, year: 2026, calendar: calendar).isEmpty)
    }

    func testWorkdaysAndWeekendsLeft() {
        XCTAssertEqual(TimeProgress.workdaysLeft(.month, now: now, known: known, calendar: calendar), 9)
        XCTAssertEqual(TimeProgress.workdaysLeft(.week, now: now, known: known, calendar: calendar), 4)
        XCTAssertEqual(TimeProgress.workdaysLeft(.year, now: now, known: known, calendar: calendar), 53)
        XCTAssertEqual(TimeProgress.workdaysLeft(.day, now: date(2026, 10, 3, 9), known: known, calendar: calendar), 0)
        XCTAssertEqual(TimeProgress.workdaysLeft(.day, now: date(2026, 10, 10, 9), known: known, calendar: calendar), 1,
                       "调休上班算工作日")
        XCTAssertEqual(TimeProgress.weekendsLeft(.year, now: now, calendar: calendar), 10)
        XCTAssertEqual(TimeProgress.weekendsLeft(.week, now: date(2026, 10, 25, 9), calendar: calendar), 1,
                       "周日这个周末也算一个")
        XCTAssertEqual(TimeProgress.daysToWeekend(now, calendar: calendar), 4)
        XCTAssertEqual(TimeProgress.daysToWeekend(date(2026, 10, 24), calendar: calendar), 0)
        XCTAssertTrue(TimeProgress.isWorkday(date(2026, 2, 28), known: known, calendar: calendar))
        XCTAssertFalse(TimeProgress.isWorkday(date(2026, 10, 1), known: known, calendar: calendar))
    }

    func testDayCounts() {
        XCTAssertEqual(TimeProgress.daysLeft(.year, now: now, calendar: calendar), 73)
        XCTAssertEqual(TimeProgress.daysLeft(.month, now: now, calendar: calendar), 12)
        XCTAssertEqual(TimeProgress.daysLeft(.week, now: now, calendar: calendar), 6)
        XCTAssertEqual(TimeProgress.dayOfYear(now, calendar: calendar), 293)
        XCTAssertEqual(TimeProgress.length(.year, now: now, calendar: calendar), 365)
        XCTAssertEqual(TimeProgress.length(.month, now: now, calendar: calendar), 31)
        XCTAssertEqual(TimeProgress.dayIndex(.week, now: now, calendar: calendar), 2)
        XCTAssertEqual(TimeProgress.dayIndex(.month, now: now, calendar: calendar), 20)
        XCTAssertEqual(TimeProgress.weekOfYear(now, calendar: calendar), 43)
        XCTAssertEqual(TimeProgress.remainingDetail(.day, now: now, calendar: calendar), "还剩 13 小时 36 分")
        XCTAssertEqual(TimeProgress.remainingShort(.day, now: now, calendar: calendar), "剩 13时36分")
        XCTAssertEqual(TimeProgress.remainingDetail(.year, now: now, calendar: calendar), "还剩 73 天")
        XCTAssertEqual(TimeProgress.remainingParts(.day, now: now, calendar: calendar),
                       TimeProgress.Remaining(value: "13", unit: "小时 36 分"))
        XCTAssertEqual(TimeProgress.facts(.month, now: now, known: known, calendar: calendar),
                       ["第 20 / 31 天", "9 个工作日"])
        XCTAssertEqual(TimeProgress.facts(.year, now: now, known: known, calendar: calendar),
                       ["第 293 / 365 天", "第 43 周"])
    }

    func testWeekDays() {
        let week = TimeProgress.weekDays(now: now, calendar: calendar)
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week[0].date, date(2026, 10, 19))
        XCTAssertEqual(week[0].fraction, 1)
        XCTAssertTrue(week[1].isToday)
        XCTAssertEqual(week[1].fraction, (10 * 60 + 24) / 1440.0, accuracy: 1e-9)
        XCTAssertEqual(week[2].fraction, 0)
        XCTAssertEqual(week.filter(\.isWeekend).map(\.index), [5, 6])
    }

    func testMilestonesSortedByDays() {
        let items = TimeProgress.milestones(now: now, known: known, calendar: calendar)
        XCTAssertEqual(items.map(\.title), ["霜降", "周末", "月底", "元旦"])
        XCTAssertEqual(items.map(\.days), [3, 4, 11, 73])
        XCTAssertEqual(items.last?.estimated, true, "2027 年的安排还没公布")
        XCTAssertEqual(items.first?.estimated, false)

        // 周六看下个周六；月底那天看下个月底。
        let saturday = TimeProgress.milestones(now: date(2026, 10, 31, 9), known: known, calendar: calendar)
        XCTAssertEqual(saturday.first { $0.kind == .weekend }?.days, 7)
        XCTAssertEqual(saturday.first { $0.kind == .monthEnd }?.days, 30)
        // 正在放的假期按 0 天。
        let holiday = TimeProgress.milestones(now: date(2026, 10, 3, 9), known: known, calendar: calendar)
        XCTAssertEqual(holiday.first?.kind, .holiday)
        XCTAssertEqual(holiday.first?.days, 0)
        XCTAssertEqual(TimeProgress.milestones(now: now, known: known, limit: 2, calendar: calendar).count, 2)
    }

    func testNotesStateFactsOnly() {
        XCTAssertEqual(TimeProgress.note(.year, now: now, known: known, calendar: calendar), "今年还剩 73 天，还有 10 个周末。")
        XCTAssertEqual(TimeProgress.note(.month, now: now, known: known, calendar: calendar), "10月还剩 12 天，其中 9 个工作日。")
        XCTAssertEqual(TimeProgress.note(.week, now: now, known: known, calendar: calendar), "本周还剩 6 天，其中 4 个工作日。")
        XCTAssertEqual(TimeProgress.note(.day, now: now, known: known, calendar: calendar), "今天是今年第 293 天。")
        XCTAssertEqual(TimeProgress.quadNote(now: now, calendar: calendar), "今年第 43 周，本周第 2 天。")
        XCTAssertEqual(TimeProgress.dateTitle(now, calendar: calendar), "10月20日 周二")
    }

    func testScalesAndTicks() {
        let month = TimeProgress.scale(.month, now: now, calendar: calendar)
        XCTAssertEqual(month.map(\.label), ["1日", "8", "15", "22", "31日"])
        XCTAssertEqual(month.last?.position, 1)
        XCTAssertEqual(month.first?.position, 0)
        XCTAssertEqual(TimeProgress.scale(.day, now: now, calendar: calendar).map(\.label), ["0时", "6时", "12时", "18时", "24时"])
        XCTAssertEqual(TimeProgress.scale(.week, now: now, calendar: calendar).count, 7)
        XCTAssertEqual(TimeProgress.scale(.year, now: now, calendar: calendar).map(\.label), ["1月", "4月", "7月", "10月", "年底"])
        XCTAssertEqual(TimeProgress.ringTickCount(.month, now: now, calendar: calendar), 31)
        XCTAssertEqual(TimeProgress.ringTickCount(.day, now: now, calendar: calendar), 24)
        XCTAssertEqual(TimeProgress.unitCount(.year, now: now, calendar: calendar), 52)
        XCTAssertTrue(TimeProgress.isMajorTick(3, period: .year))
        XCTAssertFalse(TimeProgress.isMajorTick(4, period: .year))
    }
}
