import XCTest

/// 时钟面板：卡片画法到面板的映射、今天进度、世界时钟的昼夜和时差、
/// 农历节气、第几周、下一个闹钟和日程、城市配置。
final class ClockPanelTests: XCTestCase {

    private let shanghai = TimeZone(identifier: "Asia/Shanghai")!

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = shanghai
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    /// 2026-10-20 周二 09:57:22，北京时间（效果图那一刻）。
    private var sample: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 9, minute: 57, second: 22))!
    }

    private func at(_ day: Int, _ hour: Int, _ minute: Int, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    // MARK: 映射

    func testEveryFaceOpensItsOwnPanel() {
        XCTAssertEqual(ClockPanelKind.of(.pixel), .pixel)
        XCTAssertEqual(ClockPanelKind.of(.lcd), .lcd)
        XCTAssertEqual(ClockPanelKind.of(.standard(bold: false)), .classic)
        XCTAssertEqual(ClockPanelKind.of(.bigDigits(heavy: true)), .classic)
        XCTAssertEqual(ClockPanelKind.of(.analog), .analog)
        XCTAssertEqual(ClockPanelKind.of(.secondsRing), .analog)
        XCTAssertEqual(ClockPanelKind.of(.flip), .flip)
        XCTAssertEqual(ClockPanelKind.of(.foldFlip), .flip)
        XCTAssertEqual(ClockPanelKind.of(.bigFlipCards), .flip)
        XCTAssertEqual(ClockPanelKind.of(.words), .words)
        XCTAssertEqual(ClockPanelKind.of(.neon), .neon)
        XCTAssertEqual(ClockPanelKind.of(.nixie), .nixie)
    }

    func testLockedProStylesOpenTheFlipPanelLikeTheirCard() {
        for id in ["lcd", "neon", "nixie"] {
            let config = WidgetConfig(["layout": .string(id)])
            XCTAssertEqual(ClockPanelKind.of(ClockStyles.face(config, unlocked: false)), .flip, id)
        }
        let lcd = WidgetConfig(["layout": .string("lcd")])
        XCTAssertEqual(ClockPanelKind.of(ClockStyles.face(lcd, unlocked: true)), .lcd)
        XCTAssertEqual(ClockPanelKind.of(ClockStyles.face(WidgetConfig(["layout": .string("pixel")]),
                                                          unlocked: false)), .pixel)
    }

    // MARK: 今天进度

    func testDayProgressAtTheSampleMoment() {
        let day = ClockPanelData.day(sample, calendar: calendar)
        XCTAssertEqual(day.percent, 41)
        XCTAssertEqual(day.remainingMinutes, 14 * 60 + 2)
        XCTAssertEqual(ClockPanelData.remainingText(day), "还剩 14 时 02 分")
        XCTAssertEqual(ClockPanelData.filledCells(day.fraction, of: 48), 19)
        XCTAssertEqual(ClockPanelData.filledCells(day.fraction, of: 24), 9)
    }

    func testFilledCellsStayInRange() {
        XCTAssertEqual(ClockPanelData.filledCells(0, of: 48), 0)
        XCTAssertEqual(ClockPanelData.filledCells(1, of: 48), 48)
        XCTAssertEqual(ClockPanelData.filledCells(1.4, of: 24), 24)
        XCTAssertEqual(ClockPanelData.filledCells(-1, of: 24), 0)
        XCTAssertEqual(ClockPanelData.filledCells(.nan, of: 24), 0)
        XCTAssertEqual(ClockPanelData.filledCells(0.5, of: 0), 0)
    }

    func testHoursMinutesPadsTheMinutes() {
        XCTAssertEqual(ClockPanelData.hoursMinutes(0), "0 时 00 分")
        XCTAssertEqual(ClockPanelData.hoursMinutes(664), "11 时 04 分")
        XCTAssertEqual(ClockPanelData.hoursMinutes(-5), "0 时 00 分")
    }

    // MARK: 世界时钟

    func testWorldClocksAtTheSampleMoment() {
        let london = ClockPanelData.cityTime(WorldCity(name: "伦敦", zone: "Europe/London"), now: sample, here: shanghai)
        XCTAssertEqual(london.clock, "02:57")
        XCTAssertFalse(london.isDay)
        XCTAssertEqual(london.dayOffset, 0)
        XCTAssertEqual(ClockPanelData.relativeLine(london), "\u{2212}7 时")

        let newYork = ClockPanelData.cityTime(WorldCity(name: "纽约", zone: "America/New_York"), now: sample, here: shanghai)
        XCTAssertEqual(newYork.clock, "21:57")
        XCTAssertFalse(newYork.isDay)
        XCTAssertEqual(newYork.dayOffset, -1)
        XCTAssertEqual(ClockPanelData.relativeLine(newYork), "昨天 \u{2212}12")

        let tokyo = ClockPanelData.cityTime(WorldCity(name: "东京", zone: "Asia/Tokyo"), now: sample, here: shanghai)
        XCTAssertEqual(tokyo.clock, "10:57")
        XCTAssertTrue(tokyo.isDay)
        XCTAssertEqual(ClockPanelData.relativeLine(tokyo), "+1 时")

        let beijing = ClockPanelData.cityTime(WorldCity(name: "北京", zone: "Asia/Shanghai"), now: sample, here: shanghai)
        XCTAssertEqual(ClockPanelData.relativeLine(beijing), "同此处")
    }

    func testDaytimeIsSixToSix() {
        XCTAssertFalse(ClockPanelData.isDaytime(hour: 5))
        XCTAssertTrue(ClockPanelData.isDaytime(hour: 6))
        XCTAssertTrue(ClockPanelData.isDaytime(hour: 17))
        XCTAssertFalse(ClockPanelData.isDaytime(hour: 18))
    }

    func testOffsetTextKeepsHalfHours() {
        XCTAssertEqual(ClockPanelData.offsetText(0), "0")
        XCTAssertEqual(ClockPanelData.offsetText(3600), "+1")
        XCTAssertEqual(ClockPanelData.offsetText(-9000), "\u{2212}2:30")
        XCTAssertEqual(ClockPanelData.offsetText(19800), "+5:30")
    }

    func testCitiesDefaultAndPick() {
        var config = WidgetConfig()
        XCTAssertEqual(ClockPanelData.cities(config).map(\.zone), ["Europe/London", "America/New_York", "Asia/Tokyo"])
        ClockPanelData.set(WorldCity(name: "巴黎", zone: "Europe/Paris"), at: 1, in: &config)
        XCTAssertEqual(ClockPanelData.cities(config).map(\.zone), ["Europe/London", "Europe/Paris", "Asia/Tokyo"])
        XCTAssertEqual(ClockPanelData.cities(config)[1].name, "巴黎")
        ClockPanelData.set(WorldCity(name: "x", zone: "Asia/Seoul"), at: 5, in: &config)
        XCTAssertEqual(ClockPanelData.cities(config).count, 3)
    }

    func testUnreadableStoredCitiesFallBackPerSlot() {
        let config = WidgetConfig([ClockPanelData.citiesKey: .list([.string("Nowhere/Land|x"),
                                                                     .string("Asia/Kolkata")])])
        let cities = ClockPanelData.cities(config)
        XCTAssertEqual(cities.map(\.zone), ["Europe/London", "Asia/Kolkata", "Asia/Tokyo"])
        XCTAssertEqual(cities[1].name, "Kolkata")
    }

    // MARK: 农历、第几周

    func testLunarAndNextTerm() {
        let lunar = ClockPanelData.lunar(sample)
        XCTAssertEqual(lunar.date, "九月十一")
        XCTAssertEqual(lunar.term, "霜降 3 天后")
        XCTAssertEqual(ClockPanelData.lunar(at(23, 12, 0)).term, "今天霜降")
    }

    func testWeekAndDayOfYear() {
        let week = ClockPanelData.week(sample, calendar: calendar)
        XCTAssertEqual(week.week, 43)
        XCTAssertEqual(week.dayOfYear, 293)
    }

    // MARK: 下一个闹钟、日程

    func testNextAlarmAcrossShelfAlarms() {
        var first = WidgetConfig()
        AlarmBook.store([AlarmItem(id: "a", minutes: 7 * 60 + 30, name: "")], in: &first)
        var second = WidgetConfig()
        AlarmBook.store([AlarmItem(id: "b", minutes: 12 * 60, name: "午饭"),
                         AlarmItem(id: "c", minutes: 10 * 60, name: "关着", enabled: false)], in: &second)
        let next = ClockPanelData.nextAlarm([first, second], now: sample, calendar: calendar)
        XCTAssertEqual(next?.title, "午饭")
        XCTAssertEqual(next?.at, at(20, 12, 0))
        let morning = ClockPanelData.nextAlarm([first], now: sample, calendar: calendar)
        XCTAssertEqual(morning?.at, at(21, 7, 30))
        XCTAssertEqual(ClockPanelData.dayWord(morning!.at, now: sample, calendar: calendar), "明天")
        XCTAssertNil(ClockPanelData.nextAlarm([], now: sample, calendar: calendar))
        // 一个闹钟都没有（清空了的闹钟卡片）。没存过 alarms 的旧卡片按卡片自己的旧闹钟读，不算空。
        var empty = WidgetConfig()
        AlarmBook.store([], in: &empty)
        XCTAssertNil(ClockPanelData.nextAlarm([empty], now: sample, calendar: calendar))
    }

    func testNextEventSkipsAllDayStartedAndFarOnes() {
        let events: [(start: Date, title: String, allDay: Bool)] = [
            (at(20, 0, 0), "全天", true),
            (at(20, 9, 30), "已开始", false),
            (at(20, 14, 0), "设计评审", false),
            (at(20, 16, 0), "周会", false),
            (at(22, 9, 0), "太远", false),
        ]
        let next = ClockPanelData.nextEvent(events, now: sample)
        XCTAssertEqual(next?.title, "设计评审")
        XCTAssertEqual(ClockPanelData.untilShort(next!.at, now: sample), "4 时后")
        XCTAssertNil(ClockPanelData.nextEvent([(at(22, 9, 0), "太远", false)], now: sample))
        XCTAssertEqual(ClockPanelData.nextEvent([(at(20, 11, 0), "", false)], now: sample)?.title, "日程")
    }

    func testUntilShort() {
        XCTAssertEqual(ClockPanelData.untilShort(sample.addingTimeInterval(30), now: sample), "马上")
        XCTAssertEqual(ClockPanelData.untilShort(sample.addingTimeInterval(35 * 60), now: sample), "35 分后")
        XCTAssertEqual(ClockPanelData.untilShort(sample.addingTimeInterval(125 * 60), now: sample), "2 时后")
    }

    func testDaylight() {
        XCTAssertEqual(ClockPanelData.daylightText(rise: at(20, 6, 35), set: at(20, 17, 39)), "11 时 04 分")
    }
}
