import Foundation
import XCTest

/// 快速待办输入框的自然语言时间：认片段、去掉片段剩下的标题、提醒时间和分组、预览一行。
/// 示例时刻 2026-10-22 周四 16:10（北京时间）。
final class TodoTimeParseTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func at(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private var now: Date { at(10, 22, 16, 10) }

    private func parse(_ text: String) -> TodoTimeParse? {
        TodoTimeParse.parse(text, now: now, calendar: calendar)
    }

    // MARK: 中文

    func testTomorrowAtNineWithTheFragmentMarked() throws {
        let result = try XCTUnwrap(parse("明天 9 点交稿"))
        XCTAssertEqual(result.title, "交稿")
        XCTAssertEqual(result.fragment, "明天 9 点")
        XCTAssertEqual(result.start, 0)
        XCTAssertEqual(result.length, ("明天 9 点" as NSString).length)
        XCTAssertEqual(result.remindAt, at(10, 23, 9))
        XCTAssertFalse(result.today, "明天的进「稍后」")
        XCTAssertEqual(result.preview(now: now, calendar: calendar), "明天 10/23 周五 09:00 提醒")
    }

    func testTheFragmentCanSitAtTheEnd() throws {
        let result = try XCTUnwrap(parse("交稿明天9点"))
        XCTAssertEqual(result.title, "交稿")
        XCTAssertEqual(result.start, 2)
        XCTAssertEqual(result.remindAt, at(10, 23, 9))
    }

    func testTodayAloneGoesIntoTodayWithoutAReminder() throws {
        let result = try XCTUnwrap(parse("今天 交电费"))
        XCTAssertEqual(result.title, "交电费")
        XCTAssertNil(result.remindAt)
        XCTAssertTrue(result.today)
        XCTAssertEqual(result.preview(now: now, calendar: calendar), "放进今天")
    }

    func testPeriodsAndHalfHours() throws {
        XCTAssertEqual(parse("今晚 跑步")?.remindAt, at(10, 22, 20))
        XCTAssertEqual(parse("今晚 跑步")?.today, true)
        XCTAssertEqual(parse("明天下午3点半 复盘")?.remindAt, at(10, 23, 15, 30))
        XCTAssertEqual(parse("晚上十点 关灯")?.remindAt, at(10, 22, 22))
        XCTAssertEqual(parse("明天上午 体检")?.remindAt, at(10, 23, 9))
        XCTAssertEqual(parse("明早 晨跑")?.remindAt, at(10, 23, 9))
        XCTAssertEqual(parse("后天 3点一刻 面试")?.remindAt, at(10, 24, 15, 15))
        XCTAssertEqual(parse("大后天 交报告")?.remindAt, at(10, 25, 9))
        // 下午 3 点今天已经过了：明天下午 3 点。
        XCTAssertEqual(parse("下午3点开会")?.remindAt, at(10, 23, 15))
    }

    func testABareClockPicksTheNextOneThatHasNotPassed() throws {
        // 16:10 说 7 点：今晚 19:00，放进今天。
        let dinner = try XCTUnwrap(parse("7点吃饭"))
        XCTAssertEqual(dinner.remindAt, at(10, 22, 19))
        XCTAssertTrue(dinner.today)
        // 3 点和 15 点都过了：明天下午 3 点。
        XCTAssertEqual(parse("3点开会")?.remindAt, at(10, 23, 15))
        XCTAssertEqual(parse("交稿 18:30")?.remindAt, at(10, 22, 18, 30))
        XCTAssertEqual(parse("交稿 18:30")?.fragment, "18:30")
        XCTAssertEqual(parse("交稿 18：30")?.remindAt, at(10, 22, 18, 30), "全角冒号也认")
        // 明天的 1 到 6 点当下午，和日历「写一句」一样。
        XCTAssertEqual(parse("明天3点开会")?.remindAt, at(10, 23, 15))
        XCTAssertEqual(parse("明天8点 早会")?.remindAt, at(10, 23, 8))
        XCTAssertEqual(parse("两点钟 开会")?.remindAt, at(10, 23, 14))
    }

    func testWeekdaysAndNextWeek() throws {
        // 今天周四：周五是明天，周四 9 点已经过了就是下周四。
        XCTAssertEqual(parse("周五 10:00 订会议室")?.remindAt, at(10, 23, 10))
        XCTAssertEqual(parse("订会议室 周五 10:00")?.title, "订会议室")
        XCTAssertEqual(parse("周四 9点 写周报")?.remindAt, at(10, 29, 9))
        XCTAssertEqual(parse("星期日 爬山")?.remindAt, at(10, 25, 9))
        XCTAssertEqual(parse("下周一 交周报")?.remindAt, at(10, 26, 9))
        XCTAssertEqual(parse("下周四 体检")?.remindAt, at(10, 29, 9))
        XCTAssertEqual(parse("下下周一 复查")?.remindAt, at(11, 2, 9))
    }

    func testDates() throws {
        let gift = try XCTUnwrap(parse("10/27 给妈妈挑生日礼物"))
        XCTAssertEqual(gift.title, "给妈妈挑生日礼物")
        XCTAssertEqual(gift.remindAt, at(10, 27, 9))
        XCTAssertEqual(gift.preview(now: now, calendar: calendar), "10/27 周二 09:00 提醒")
        // 早于今天的日子是明年的。
        XCTAssertEqual(parse("10月1日 交房租")?.remindAt, at(10, 1, 9, year: 2027))
        XCTAssertEqual(parse("11月3号 下午4点 开会")?.remindAt, at(11, 3, 16))
        XCTAssertNil(parse("2/30 不存在的日子"), "不存在的日子不认")
    }

    // MARK: 英文

    func testEnglish() throws {
        let call = try XCTUnwrap(parse("Call mom tomorrow at 9am"))
        XCTAssertEqual(call.title, "Call mom")
        XCTAssertEqual(call.fragment, "tomorrow at 9am")
        XCTAssertEqual(call.remindAt, at(10, 23, 9))
        let review = try XCTUnwrap(parse("9pm tomorrow review"))
        XCTAssertEqual(review.title, "review")
        XCTAssertEqual(review.remindAt, at(10, 23, 21))
        XCTAssertEqual(parse("next friday pay rent")?.remindAt, at(10, 30, 9))
        XCTAssertEqual(parse("Pay rent on Friday")?.remindAt, at(10, 23, 9))
        XCTAssertEqual(parse("gym tonight")?.remindAt, at(10, 22, 20))
        XCTAssertEqual(parse("standup 3:30 pm")?.remindAt, at(10, 23, 15, 30), "today's 3:30 pm has passed")
        XCTAssertEqual(parse("Ship it today")?.remindAt, nil)
        XCTAssertEqual(parse("Ship it today")?.today, true)
        XCTAssertEqual(parse("Ship it today")?.title, "Ship it")
    }

    // MARK: 不认的

    func testThingsThatAreNotTimes() {
        XCTAssertNil(parse("买牛奶"))
        XCTAssertNil(parse("快一点交稿"), "汉字数字没有上下文时多半不是钟点")
        XCTAssertNil(parse("明天"), "去掉以后没剩字，整句照原样记")
        XCTAssertNil(parse(""))
        XCTAssertNil(parse("Monitor the build"), "单词里的 mon 不算星期一")
    }

    // MARK: 写法

    func testDueTextsForThePill() {
        XCTAssertEqual(TodoTimeText.due(at(10, 21, 18), now: now, calendar: calendar), "昨天 18:00")
        XCTAssertEqual(TodoTimeText.due(at(10, 22, 17, 30), now: now, calendar: calendar), "17:30")
        XCTAssertEqual(TodoTimeText.due(at(10, 23, 10), now: now, calendar: calendar), "明天 10:00")
        XCTAssertEqual(TodoTimeText.due(at(10, 26, 9), now: now, calendar: calendar), "周一 09:00")
        XCTAssertEqual(TodoTimeText.due(at(11, 2, 9), now: now, calendar: calendar), "11/2 09:00")
        XCTAssertEqual(TodoTimeText.day("2026-10-21", today: "2026-10-22", calendar: calendar), "昨天")
        XCTAssertEqual(TodoTimeText.day("2026-10-19", today: "2026-10-22", calendar: calendar), "10/19")
    }
}
