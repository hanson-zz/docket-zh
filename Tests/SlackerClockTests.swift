import XCTest

/// 摸鱼时钟的计算：状态、倒计时、发薪、周五、节日、今天赚了和本月已赚。
/// 时钟拨在 2026 年，用随应用打包的 2026 年放假安排。
final class SlackerClockTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.firstWeekday = 2
        return calendar
    }

    private let known = HolidaySchedule.bundled
    private let standard = SlackerClock.Settings()

    private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day,
                                           hour: hour, minute: minute, second: second))!
    }

    private func reading(_ date: Date, _ settings: SlackerClock.Settings? = nil) -> SlackerClock.Reading {
        SlackerClock.reading(now: date, settings: settings ?? standard, calendar: calendar, known: known)
    }

    private func cell(_ item: SlackerClock.Item, _ date: Date, _ settings: SlackerClock.Settings? = nil) -> SlackerClock.Cell {
        let s = settings ?? standard
        let phase = SlackerClock.phase(now: date, settings: s, calendar: calendar, known: known)
        return SlackerClock.cell(item, now: date, phase: phase, settings: s, calendar: calendar, known: known)
    }

    // MARK: Settings

    func testDefaults() {
        let s = SlackerClock.Settings(config: WidgetConfig())
        XCTAssertEqual(s.workdays, [1, 2, 3, 4, 5])
        XCTAssertEqual(s.start, 9 * 60)
        XCTAssertEqual(s.end, 18 * 60)
        XCTAssertEqual(s.payday, 15)
        XCTAssertEqual(s.income, 100)
        XCTAssertEqual(s.items, SlackerClock.Item.allCases, "显示更多默认全选")
        XCTAssertTrue(s.followsHolidays)
    }

    func testAnEndBeforeTheStartIsANightShift() {
        var config = WidgetConfig()
        config.set("start", .string("18:00"))
        config.set("end", .string("09:00"))
        let s = SlackerClock.Settings(config: config)
        XCTAssertEqual(s.start, 18 * 60, "下班早于上班是夜班，不再退回默认")
        XCTAssertEqual(s.end, 9 * 60)
        XCTAssertTrue(s.isOvernight)
        XCTAssertEqual(s.workSeconds, 15 * 3600)
        XCTAssertFalse(SlackerClock.isValidWindow(start: 600, end: 600), "开始和结束一样不合格")
        XCTAssertFalse(SlackerClock.isValidWindow(start: 0, end: 1440), "00:00 到 24:00 等于开始和结束一样")
        XCTAssertFalse(SlackerClock.isValidWindow(start: 1440, end: 600))
        XCTAssertFalse(SlackerClock.isValidWindow(start: 600, end: -1))
        XCTAssertTrue(SlackerClock.isValidWindow(start: 22 * 60, end: 2 * 60), "夜班合格")
        XCTAssertTrue(SlackerClock.isValidWindow(start: 22 * 60, end: 0), "00:00 下班也是夜班")
        XCTAssertTrue(SlackerClock.isValidWindow(start: 8 * 60 + 30, end: 17 * 60 + 30))

        config.set("start", .string("10:00"))
        config.set("end", .string("10:00"))
        let same = SlackerClock.Settings(config: config)
        XCTAssertEqual([same.start, same.end], [9 * 60, 18 * 60], "开始和结束一样时退回 09:00 到 18:00")
        XCTAssertFalse(same.isOvernight)

        config.set("start", .string("8:30"))
        config.set("end", .string("17:30"))
        let ok = SlackerClock.Settings(config: config)
        XCTAssertEqual(ok.start, 8 * 60 + 30)
        XCTAssertEqual(ok.end, 17 * 60 + 30)
        XCTAssertFalse(ok.isOvernight)
    }

    // MARK: Night shift

    /// 22:00 至次日 06:00，周一到周五，不跟法定节假日（2026-10-14 是周三）。
    private let night = SlackerClock.Settings(start: 22 * 60, end: 6 * 60, followsHolidays: false)

    private func phase(_ date: Date, _ settings: SlackerClock.Settings) -> SlackerClock.Phase {
        SlackerClock.phase(now: date, settings: settings, calendar: calendar, known: known)
    }

    func testNightShiftCountsDownAcrossMidnight() {
        XCTAssertEqual(phase(at(2026, 10, 14, 23), night), .working(secondsLeft: 7 * 3600), "周三晚上上班")
        XCTAssertEqual(phase(at(2026, 10, 14, 22), night), .working(secondsLeft: 8 * 3600))
        XCTAssertEqual(phase(at(2026, 10, 15, 3), night), .working(secondsLeft: 3 * 3600), "周四凌晨还在上周三那一班")
        XCTAssertEqual(phase(at(2026, 10, 15, 5, 59, 59), night), .working(secondsLeft: 1))
        XCTAssertEqual(phase(at(2026, 10, 15, 6), night), .afterWork(secondsSince: 0), "06:00 下班")
        XCTAssertEqual(phase(at(2026, 10, 15, 7), night), .afterWork(secondsSince: 3600))
        XCTAssertEqual(phase(at(2026, 10, 15, 12), night), .beforeWork(secondsLeft: 10 * 3600), "白天等今晚上班")
        XCTAssertEqual(SlackerClock.title(phase(at(2026, 10, 15, 21), night)), "距离上班 01:00")
        XCTAssertEqual(SlackerClock.title(phase(at(2026, 10, 15, 3), night)), "距离下班 03:00:00")
    }

    func testNightShiftOnTheWeekend() {
        // 周五晚上那一班到周六 06:00 才下班。
        XCTAssertEqual(phase(at(2026, 10, 17, 3), night), .working(secondsLeft: 3 * 3600))
        XCTAssertEqual(phase(at(2026, 10, 17, 7), night), .afterWork(secondsSince: 3600))
        XCTAssertEqual(phase(at(2026, 10, 17, 12), night), .dayOff(greeting: "周末快乐"))
        XCTAssertEqual(phase(at(2026, 10, 17, 23), night), .dayOff(greeting: "周末快乐"), "周六晚上不上班")
        XCTAssertEqual(phase(at(2026, 10, 18, 3), night), .dayOff(greeting: "周末快乐"))
        // 周一凌晨：周日没上班，等周一晚上。
        XCTAssertEqual(phase(at(2026, 10, 19, 3), night), .beforeWork(secondsLeft: 19 * 3600))
        XCTAssertEqual(phase(at(2026, 10, 19, 22, 30), night), .working(secondsLeft: 7 * 3600 + 1800))
    }

    func testNightShiftEndingAtMidnight() {
        let late = SlackerClock.Settings(start: 22 * 60, end: 0, followsHolidays: false)
        XCTAssertTrue(late.isOvernight)
        XCTAssertEqual(late.workSeconds, 2 * 3600)
        XCTAssertEqual(phase(at(2026, 10, 14, 23, 30), late), .working(secondsLeft: 1800))
        XCTAssertEqual(phase(at(2026, 10, 15, 0, 30), late), .afterWork(secondsSince: 1800))
        XCTAssertEqual(SlackerClock.hoursLine(late), "夜班：22:00 至次日 00:00")
    }

    func testNightShiftProgressAndMoney() {
        let p = phase(at(2026, 10, 15, 3), night)
        let progress = SlackerClock.progress(p, settings: night)
        XCTAssertEqual(progress?.done, 5 * 3600)
        XCTAssertEqual(progress?.left, 3 * 3600)
        XCTAssertEqual(progress?.fraction ?? 0, 0.625, accuracy: 1e-9)
        XCTAssertEqual(SlackerClock.earnedToday(phase: p, settings: night), 62.5, accuracy: 1e-9)
        XCTAssertEqual(SlackerClock.waterLevel(p, settings: night), 0.625, accuracy: 1e-9)
        XCTAssertNil(SlackerClock.progress(phase(at(2026, 10, 15, 12), night), settings: night))
        XCTAssertEqual(SlackerClock.progressLine(done: 4 * 3600 + 24 * 60, left: 3 * 3600 + 36 * 60),
                       "已上 4 小时 24 分 · 还有 3 小时 36 分")
    }

    func testNightShiftCountsTowardTheDayItStarted() {
        // 10 月 1 日是周四。周四凌晨 3 点：周三那一班还没下，算到 13 日共 9 班。
        XCTAssertEqual(SlackerClock.workdaysPassedThisMonth(now: at(2026, 10, 15, 3), settings: night,
                                                            calendar: calendar, known: known), 9)
        XCTAssertEqual(SlackerClock.workdaysPassedThisMonth(now: at(2026, 10, 15, 7), settings: night,
                                                            calendar: calendar, known: known), 10)
        XCTAssertEqual(SlackerClock.workdaysPassedThisMonth(now: at(2026, 10, 15, 23), settings: night,
                                                            calendar: calendar, known: known), 10,
                       "今晚这一班明天下班才算")
        XCTAssertEqual(SlackerClock.workdaysPassedThisMonth(now: at(2026, 10, 1, 7), settings: night,
                                                            calendar: calendar, known: known), 0,
                       "9 月 30 日那一班算 9 月")
    }

    func testHoursLineAndDurations() {
        XCTAssertEqual(SlackerClock.hoursLine(night), "夜班：22:00 至次日 06:00")
        XCTAssertEqual(SlackerClock.hoursLine(standard), "工作时间：09:00 至 18:00")
        XCTAssertEqual(SlackerClock.duration(seconds: 30), "不到 1 分")
        XCTAssertEqual(SlackerClock.duration(seconds: 600), "10 分")
        XCTAssertEqual(SlackerClock.duration(seconds: 3600), "1 小时")
        XCTAssertEqual(SlackerClock.duration(seconds: 7 * 3600 + 24 * 60 + 59), "7 小时 24 分")
        XCTAssertEqual(SlackerClock.progress(phase(at(2026, 10, 14, 13), standard), settings: standard)?.done,
                       4 * 3600, "白班进度照旧")
    }

    func testItemsAreOrderedDedupedAndCapped() {
        XCTAssertEqual(SlackerClock.items(["earned", "payday", "bogus", "payday"]), [.earned, .payday])
        XCTAssertEqual(SlackerClock.items([]), [])
        XCTAssertEqual(SlackerClock.items(["holiday", "friday", "earned", "payday"]).count, SlackerClock.maxItems)
    }

    func testPaydayAndIncomeAreClamped() {
        XCTAssertEqual(SlackerClock.Settings(payday: 40).payday, 31)
        XCTAssertEqual(SlackerClock.Settings(payday: 0).payday, 1)
        XCTAssertEqual(SlackerClock.Settings(income: -5).income, 0)
    }

    // MARK: Phase and title

    func testWorkingCountsDownToTheSecond() {
        let r = reading(at(2026, 10, 14, 15, 24, 42))
        XCTAssertEqual(r.phase, .working(secondsLeft: 2 * 3600 + 35 * 60 + 18))
        XCTAssertEqual(r.title, "距离下班 02:35:18")
        XCTAssertEqual(r.art, .work)
    }

    func testWorkingHourBoundaries() {
        XCTAssertEqual(reading(at(2026, 10, 14, 9, 0, 0)).title, "距离下班 09:00:00", "开始那一秒已经在上班")
        XCTAssertEqual(reading(at(2026, 10, 14, 8, 59, 59)).title, "距离上班 00:01", "向上取整到分钟")
        XCTAssertEqual(reading(at(2026, 10, 14, 17, 59, 59)).title, "距离下班 00:00:01")
        let off = reading(at(2026, 10, 14, 18, 0, 0))
        XCTAssertEqual(off.phase, .afterWork(secondsSince: 0), "结束那一秒已经下班")
        XCTAssertEqual(off.title, "下班啦")
        XCTAssertEqual(off.art, .rest)
    }

    func testBeforeAndAfterWork() {
        XCTAssertEqual(reading(at(2026, 10, 14, 6, 0, 0)).title, "还没上班")
        XCTAssertEqual(reading(at(2026, 10, 14, 7, 0, 0)).title, "距离上班 02:00", "2 小时内开始倒数")
        XCTAssertEqual(reading(at(2026, 10, 14, 7, 0, 0)).art, .rest)
        XCTAssertEqual(reading(at(2026, 10, 14, 19, 59, 59)).title, "下班啦")
        XCTAssertEqual(reading(at(2026, 10, 14, 20, 0, 0)).title, "休息时间")
    }

    func testWeekend() {
        let r = reading(at(2026, 10, 17, 10))
        XCTAssertEqual(r.title, "周末快乐")
        XCTAssertEqual(r.art, .weekend)
    }

    func testAnOffWeekdayIsARestDay() {
        let s = SlackerClock.Settings(workdays: [1, 2, 3, 4])
        XCTAssertEqual(reading(at(2026, 10, 16, 10), s).title, "休息日快乐")
    }

    func testOfficialHolidaysAndMakeupDays() {
        XCTAssertEqual(reading(at(2026, 10, 2, 10)).title, "国庆快乐", "法定假日的周五不上班")
        XCTAssertEqual(reading(at(2026, 4, 5, 10)).title, "清明安康")
        let makeup = reading(at(2026, 10, 10, 10))
        XCTAssertEqual(makeup.phase, .working(secondsLeft: 8 * 3600), "调休的周六要上班")
    }

    func testHolidaysCanBeIgnored() {
        let s = SlackerClock.Settings(followsHolidays: false)
        XCTAssertEqual(reading(at(2026, 10, 2, 10), s).phase, .working(secondsLeft: 8 * 3600))
        XCTAssertEqual(reading(at(2026, 10, 3, 10), s).title, "国庆快乐", "节日窗口里的周末照样祝节日")
        XCTAssertEqual(reading(at(2026, 10, 10, 10), s).title, "周末快乐", "不按调休时周六就是周末")
        XCTAssertEqual(reading(at(2026, 10, 17, 10), s).title, "周末快乐")
    }

    func testClockFormatting() {
        XCTAssertEqual(SlackerClock.clock(seconds: 0), "00:00:00")
        XCTAssertEqual(SlackerClock.clock(seconds: 9 * 3600 + 5), "09:00:05")
        XCTAssertEqual(SlackerClock.clockMinutes(seconds: 10), "00:01")
        XCTAssertEqual(SlackerClock.clockMinutes(seconds: 3600), "01:00")
        XCTAssertEqual(SlackerClock.titleLines(.working(secondsLeft: 61)).top, "距离下班")
        XCTAssertEqual(SlackerClock.titleLines(.working(secondsLeft: 61)).bottom, "00:01:01")
        XCTAssertNil(SlackerClock.titleLines(.dayOff(greeting: "周末快乐")).bottom)
    }

    // MARK: Payday

    func testPaydayCountsDays() {
        XCTAssertEqual(SlackerClock.daysUntilPayday(15, now: at(2026, 10, 12), calendar: calendar), 3)
        XCTAssertEqual(SlackerClock.daysUntilPayday(15, now: at(2026, 10, 16), calendar: calendar), 30, "过了就算下个月")
        XCTAssertEqual(SlackerClock.daysUntilPayday(5, now: at(2026, 12, 20), calendar: calendar), 16, "跨年")
    }

    func testPaydayFallsBackToTheEndOfTheMonth() {
        XCTAssertEqual(SlackerClock.daysUntilPayday(31, now: at(2026, 4, 15), calendar: calendar), 15, "4 月没有 31 号，取 30 号")
        XCTAssertEqual(SlackerClock.daysUntilPayday(31, now: at(2026, 4, 30), calendar: calendar), 0)
        XCTAssertEqual(SlackerClock.daysUntilPayday(30, now: at(2026, 2, 27), calendar: calendar), 1, "2 月取 28 号")
        XCTAssertEqual(SlackerClock.daysUntilPayday(31, now: at(2026, 5, 1), calendar: calendar), 30)
    }

    func testPaydayCell() {
        let s = SlackerClock.Settings(payday: 14)
        let today = cell(.payday, at(2026, 10, 14), s)
        XCTAssertEqual("\(today.label)\(today.value)", "今天发薪")
        let later = cell(.payday, at(2026, 10, 12), s)
        XCTAssertEqual([later.label, later.value, later.unit], ["发薪", "2", "天"])
    }

    // MARK: Friday

    func testFriday() {
        XCTAssertEqual(SlackerClock.daysUntilFriday(at(2026, 10, 14), calendar: calendar), 2)
        XCTAssertEqual(SlackerClock.daysUntilFriday(at(2026, 10, 12), calendar: calendar), 4)
        let friday = cell(.friday, at(2026, 10, 16))
        XCTAssertEqual("\(friday.value)\(friday.unit)", "就是今天")
        XCTAssertEqual(friday.label, "周五")
        let wednesday = cell(.friday, at(2026, 10, 14))
        XCTAssertEqual([wednesday.label, wednesday.value, wednesday.unit], ["周五", "2", "天"])
    }

    func testOnTheWeekendTheFridayCellCountsToWork() {
        let saturday = cell(.friday, at(2026, 10, 17))
        XCTAssertEqual([saturday.label, saturday.value, saturday.unit], ["上班", "2", "天"])
        let holiday = cell(.friday, at(2026, 10, 3))
        XCTAssertEqual(holiday.value, "5", "国庆假期到 10 月 7 日，8 日上班")
    }

    // MARK: Festivals

    func testNextFestival() throws {
        let now = at(2026, 10, 14)
        let next = try XCTUnwrap(SlackerClock.nextFestival(after: now, calendar: calendar))
        let doubleNinth = try XCTUnwrap(ChineseCalendar.gregorianDay(lunarMonth: 9, day: 9, inGregorianYear: 2026))
        XCTAssertEqual(next.name, "重阳节")
        XCTAssertEqual(next.days, ChineseCalendar.days(from: now, to: doubleNinth))
        let c = cell(.holiday, now)
        XCTAssertEqual(c.label, "重阳节")
        XCTAssertEqual(c.unit, "天")
    }

    func testInsideAFestivalWindow() throws {
        let next = try XCTUnwrap(SlackerClock.nextFestival(after: at(2026, 10, 3), calendar: calendar))
        XCTAssertEqual(next, .init(name: "国庆节", days: 0))
        let c = cell(.holiday, at(2026, 10, 3))
        XCTAssertEqual("\(c.value)\(c.unit)", "就是今天")
    }

    func testNewYearIsNextAtTheEndOfTheYear() throws {
        let next = try XCTUnwrap(SlackerClock.nextFestival(after: at(2026, 12, 30), calendar: calendar))
        XCTAssertEqual(next, .init(name: "元旦", days: 2))
    }

    func testGreetings() {
        XCTAssertEqual(SlackerClock.greeting(festival: "国庆节"), "国庆快乐")
        XCTAssertEqual(SlackerClock.greeting(festival: "春节"), "春节快乐")
        XCTAssertEqual(SlackerClock.greeting(festival: "端午节"), "端午安康")
    }

    // MARK: Money

    func testEarnedTodayIsProportional() {
        let now = at(2026, 10, 14, 15, 24, 42)
        let c = cell(.earned, now)
        XCTAssertEqual(c.label, "今天赚了")
        // 已工作 6:24:42 = 23082 秒，一天 9 小时 = 32400 秒。
        XCTAssertEqual(c.value, String(format: "%.2f", 100.0 * 23082 / 32400))
        XCTAssertEqual(c.value, "71.24")
        XCTAssertEqual(c.unit, "¥")
    }

    func testEarnedOutsideWorkingHours() {
        XCTAssertEqual(cell(.earned, at(2026, 10, 14, 8)).value, "0.00", "上班前是 0")
        XCTAssertEqual(cell(.earned, at(2026, 10, 14, 9)).value, "0.00", "刚上班也是 0")
        XCTAssertEqual(cell(.earned, at(2026, 10, 14, 18)).value, "100.00", "下班后满额")
        XCTAssertEqual(cell(.earned, at(2026, 10, 14, 23)).value, "100.00")
    }

    func testEarnedThisMonthOnTheWeekend() {
        // 10 月 1 日到 7 日放假，8、9 日上班，10 日调休上班，12 到 16 日上班：8 天。
        let c = cell(.earned, at(2026, 10, 17, 10))
        XCTAssertEqual([c.label, c.value, c.unit], ["本月已赚", "800", "¥"])
        XCTAssertEqual(SlackerClock.workdaysPassedThisMonth(now: at(2026, 10, 17), settings: standard,
                                                            calendar: calendar, known: known), 8)
    }

    func testThisMonthCountsTodayOnlyAfterWork() {
        XCTAssertEqual(SlackerClock.workdaysPassedThisMonth(now: at(2026, 10, 14, 15), settings: standard,
                                                            calendar: calendar, known: known), 5)
        XCTAssertEqual(SlackerClock.workdaysPassedThisMonth(now: at(2026, 10, 14, 19), settings: standard,
                                                            calendar: calendar, known: known), 6)
    }

    func testMoneyFormatting() {
        XCTAssertEqual(SlackerClock.money(68.5), "68.50")
        XCTAssertEqual(SlackerClock.monthMoney(1800), "1800")
        XCTAssertEqual(SlackerClock.monthMoney(1833.333), "1833.33")
    }

    // MARK: Cells and look

    func testOnlyChosenCellsAreShown() {
        let s = SlackerClock.Settings(items: [.earned, .payday])
        XCTAssertEqual(reading(at(2026, 10, 14, 10), s).cells.map(\.item), [.earned, .payday], "按设置里拖好的先后")
        XCTAssertTrue(reading(at(2026, 10, 14, 10), SlackerClock.Settings(items: [])).cells.isEmpty)
    }

    func testArtAndColours() {
        XCTAssertEqual(SlackerClock.Art.work.imageName, "slacker-panda-work-512")
        XCTAssertEqual(SlackerClock.Art.rest.imageName, "slacker-panda-rest-512")
        XCTAssertEqual(SlackerClock.Art.weekend.imageName, "slacker-panda-weekend-512")
        XCTAssertEqual(SlackerClock.backgroundHex(WidgetConfig(), art: .rest), SlackerClock.restHex, "默认随状态变色")
        var config = WidgetConfig()
        config.set("tint", .bool(false))
        XCTAssertEqual(SlackerClock.backgroundHex(config, art: .rest), SlackerClock.defaultBackgroundHex, "默认背景是小熊猫橙")
        config.set("background", .string("#123456"))
        XCTAssertEqual(SlackerClock.backgroundHex(config, art: .weekend), "#123456")
        config.set("background", .string("oops"))
        XCTAssertEqual(SlackerClock.backgroundHex(config, art: .weekend), SlackerClock.defaultBackgroundHex)
        XCTAssertNil(SlackerClock.backgroundImagePath(config))
        config.set("backgroundImage", .string("/tmp/a.png"))
        XCTAssertEqual(SlackerClock.backgroundImagePath(config), "/tmp/a.png")
        config.set("tint", .bool(true))
        XCTAssertNil(SlackerClock.backgroundImagePath(config), "随状态变色时不用背景图")
        XCTAssertEqual(SlackerClock.textHex(WidgetConfig()), "#FFFFFF")
        XCTAssertEqual(SlackerClock.font(WidgetConfig()), .system)
    }

    // MARK: Catalog and search

    func testCatalogEntry() throws {
        let entry = try XCTUnwrap(WidgetCatalog.entry(.slacker))
        XCTAssertEqual(entry.name, "摸鱼时钟")
        XCTAssertEqual(WidgetKind.slacker.rawValue, "slacker")
        XCTAssertNotNil(WidgetCatalog.make(.slacker))
        XCTAssertNil(WidgetCatalog.openTarget(.slacker), "点卡片打开面板")
        var fewer = try XCTUnwrap(WidgetCatalog.make(.slacker))
        fewer.config.set("more", .list([.string("payday")]))
        XCTAssertLessThan(WidgetCatalog.naturalSize(fewer).width,
                          WidgetCatalog.naturalSize(WidgetCatalog.make(.slacker)!).width)
        XCTAssertLessThan(WidgetCatalog.verticalHeight(fewer),
                          WidgetCatalog.verticalHeight(WidgetCatalog.make(.slacker)!))
    }

    func testSearchTerms() {
        for query in ["摸鱼", "moyu", "my", "mo yu", "下班", "倒计时", "发薪", "工资", "slacker"] {
            XCTAssertTrue(WidgetSearch.matches(query, names: ["摸鱼时钟"], kind: "slacker"), query)
        }
    }

    func testNoEmDashInWhatTheCardSays() {
        var texts = SlackerClock.Item.allCases.map(\.title) + SlackerClock.FontChoice.allCases.map(\.title)
        for day in 10...17 {
            let r = reading(at(2026, 10, day, 10))
            texts.append(r.title)
            texts += r.cells.flatMap { [$0.label, $0.value, $0.unit] }
        }
        for text in texts { XCTAssertFalse(text.contains("\u{2014}"), text) }
    }

    // MARK: 液态

    func testLookDefaultsToIllustratedAndReadsLiquid() {
        XCTAssertEqual(SlackerClock.look(WidgetConfig()), .illustrated)
        var config = WidgetConfig()
        config.set(SlackerClock.lookKey, .string("liquid"))
        XCTAssertEqual(SlackerClock.look(config), .liquid)
        config.set(SlackerClock.lookKey, .string("nonsense"))
        XCTAssertEqual(SlackerClock.look(config), .illustrated)
        XCTAssertEqual(SlackerClock.Look.liquid.title, "液态")
    }

    func testWaterLevelFollowsTheWorkday() {
        // 2026-10-14 是周三。
        let before = SlackerClock.phase(now: at(2026, 10, 14, 8), settings: standard, calendar: calendar, known: known)
        let noon = SlackerClock.phase(now: at(2026, 10, 14, 13, 30), settings: standard, calendar: calendar, known: known)
        let after = SlackerClock.phase(now: at(2026, 10, 14, 19), settings: standard, calendar: calendar, known: known)
        let saturday = SlackerClock.phase(now: at(2026, 10, 17, 10), settings: standard, calendar: calendar, known: known)
        XCTAssertEqual(SlackerClock.waterLevel(before, settings: standard), 0)
        XCTAssertEqual(SlackerClock.waterLevel(noon, settings: standard), 0.5, accuracy: 1e-9)
        XCTAssertEqual(SlackerClock.waterLevel(after, settings: standard), 1)
        XCTAssertEqual(SlackerClock.waterLevel(saturday, settings: standard), 1)
    }

    func testGoldenOnlyInTheFirstMinuteAfterWork() {
        XCTAssertTrue(SlackerClock.isGolden(.afterWork(secondsSince: 0)))
        XCTAssertTrue(SlackerClock.isGolden(.afterWork(secondsSince: 59)))
        XCTAssertFalse(SlackerClock.isGolden(.afterWork(secondsSince: 60)))
        XCTAssertFalse(SlackerClock.isGolden(.working(secondsLeft: 1)))
    }

    func testLiquidMotionSavesPower() {
        XCTAssertEqual(SlackerClock.liquidFPS(.working(secondsLeft: 100), visible: true, reduceMotion: false), 10)
        XCTAssertEqual(SlackerClock.liquidFPS(.afterWork(secondsSince: 5), visible: true, reduceMotion: false), 30)
        XCTAssertNil(SlackerClock.liquidFPS(.working(secondsLeft: 100), visible: false, reduceMotion: false))
        XCTAssertNil(SlackerClock.liquidFPS(.working(secondsLeft: 100), visible: true, reduceMotion: true))
        XCTAssertNil(SlackerClock.liquidFPS(.dayOff(greeting: "周末快乐"), visible: true, reduceMotion: false))
    }
}
