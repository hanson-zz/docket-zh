import XCTest

/// 时间进度：周期、百分比、标签、剩余时间，以及新卡片的默认外观。
final class TimeProgressTests: XCTestCase {

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

    func testCaptionCountsDaysLeftInTheYear() {
        let now = date(2026, 10, 13, 9)
        XCTAssertEqual(TimeProgress.label(.year, now: now, calendar: calendar), "2026年")
        // 10 月 13 日到年底：今天也算，共 80 天。
        XCTAssertEqual(TimeProgress.remaining(.year, now: now, calendar: calendar), "剩 80 天")
        XCTAssertEqual(TimeProgress.caption(.year, now: now, calendar: calendar), "2026年 · 剩 80 天")
    }

    func testDayCountsHoursThenMinutes() {
        XCTAssertEqual(TimeProgress.remaining(.day, now: date(2026, 10, 17, 14, 47), calendar: calendar), "剩 9 小时")
        XCTAssertEqual(TimeProgress.remaining(.day, now: date(2026, 10, 17, 23, 30), calendar: calendar), "剩 30 分钟")
        XCTAssertEqual(TimeProgress.label(.day, now: date(2026, 10, 17), calendar: calendar), "周六")
    }

    func testWeekIsAPeriod() {
        let saturday = date(2026, 10, 17, 12)
        // 周一开始的一周，周六中午过了 5.5 天。
        XCTAssertEqual(TimeProgress.fraction(.week, now: saturday, calendar: calendar), 5.5 / 7, accuracy: 1e-9)
        XCTAssertEqual(TimeProgress.remaining(.week, now: saturday, calendar: calendar), "剩 2 天")
        XCTAssertEqual(TimeProgress.label(.week, now: saturday, calendar: calendar), "第42周")
        XCTAssertEqual(TimeProgress.label(.month, now: saturday, calendar: calendar), "10月")
    }

    func testPeriodsCycleShortestFirst() {
        XCTAssertEqual(TimeProgress.Period.day.next, .week)
        XCTAssertEqual(TimeProgress.Period.week.next, .month)
        XCTAssertEqual(TimeProgress.Period.month.next, .year)
        XCTAssertEqual(TimeProgress.Period.year.next, .day)
        XCTAssertEqual(TimeProgress.period(WidgetConfig(["period": .string("nonsense")])), .year)
        XCTAssertEqual(TimeProgress.period(WidgetConfig(["period": .string("week")])), .week)
    }

    func testPercentRoundsDown() {
        XCTAssertEqual(TimeProgress.percent(0.996), 99)
        XCTAssertEqual(TimeProgress.percent(1.4), 100)
        XCTAssertEqual(TimeProgress.percent(-1), 0)
        XCTAssertEqual(TimeProgress.percent(.nan), 0)
        XCTAssertEqual(TimeProgress.fraction(.year, now: date(2026, 1, 1), calendar: calendar), 0)
    }

    func testNewCardsRingButSavedCardsKeepTheirLook() {
        let fresh = WidgetCatalog.make(.progress)
        XCTAssertEqual(fresh.map { TimeProgress.layout($0.config) }, TimeProgress.newWidgetLayout)
        // 没存 layout 的旧卡片补上默认值后仍是进度条。
        let old = WidgetConfig(["period": .string("year")])
        let merged = old.merging(defaults: WidgetCatalog.entry(.progress)?.defaults ?? WidgetConfig())
        XCTAssertEqual(TimeProgress.layout(merged), TimeProgress.legacyLayout)
        // 从样式里挑的照样是挑的那个。
        let liquid = WidgetCatalog.make(.progress, overrides: ["layout": .string(LiquidMotion.layout)])
        XCTAssertEqual(liquid.map { TimeProgress.layout($0.config) }, LiquidMotion.layout)
    }

    func testLiquidMotionCanBeSwitchedOff() {
        XCTAssertTrue(TimeProgress.liquidAnimates(WidgetConfig(), reduceMotion: false))
        XCTAssertFalse(TimeProgress.liquidAnimates(WidgetConfig(), reduceMotion: true))
        XCTAssertFalse(TimeProgress.liquidAnimates(WidgetConfig([TimeProgress.motionKey: .bool(false)]),
                                                   reduceMotion: false))
        let liquid = WidgetConfig(["layout": .string(LiquidMotion.layout)])
        XCTAssertTrue(WidgetCatalog.applies(TimeProgress.motionKey, to: liquid, kind: .progress))
        XCTAssertFalse(WidgetCatalog.applies(TimeProgress.motionKey, to: WidgetConfig(["layout": .string("ring")]),
                                             kind: .progress))
    }

    func testThreeLooksShareOneWidth() {
        for layout in ["ring", "percentage", LiquidMotion.layout] {
            let instance = WidgetCatalog.make(.progress, overrides: ["layout": .string(layout)])
            XCTAssertEqual(instance.map { WidgetCatalog.naturalSize($0).width }, 176, layout)
        }
    }

    func testBubblesRiseAndLoop() {
        XCTAssertTrue(LiquidMotion.bubbles(count: 0, t: 1).isEmpty)
        let bubbles = LiquidMotion.bubbles(count: 4, t: 12.3)
        XCTAssertEqual(bubbles.count, 4)
        for bubble in bubbles {
            XCTAssertTrue((0..<1).contains(bubble.rise))
            XCTAssertTrue((0.1...0.9).contains(bubble.x))
            XCTAssertGreaterThan(bubble.radius, 0)
        }
        XCTAssertEqual(LiquidMotion.bubbles(count: 3, t: 0), LiquidMotion.bubbles(count: 3, t: 0), "静止时是同一张图")
        XCTAssertNotEqual(LiquidMotion.bubbles(count: 3, t: 0), LiquidMotion.bubbles(count: 3, t: 1))
    }
}
