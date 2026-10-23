import Foundation
import XCTest

/// 纪念日沙漏改版：样式迁移、沙量、临近判断和面板要用的数。
final class AnniversaryHourglassTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }()

    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour, minute: minute))!
    }

    private func midnight(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.startOfDay(for: day(y, m, d))
    }

    private func reading(_ event: AnniversaryEvent, _ today: Date) -> AnniversaryReading {
        Anniversary.reading(event, today: today, calendar: calendar)!
    }

    private let newYear = AnniversaryEvent(id: "ny", title: "元旦", day: "20260101", yearly: true, color: .blue)
    private let wedding = AnniversaryEvent(id: "w", title: "结婚纪念日", day: "20201027", yearly: true, color: .pink)
    private let birthday = AnniversaryEvent(id: "b", title: "生日", day: "19900520", yearly: true)
    private let nationalDay = AnniversaryEvent(id: "nd", title: "国庆节", day: "20261001", color: .orange)
    private let job = AnniversaryEvent(id: "j", title: "入职", day: "20221021", kind: .countup, yearly: true)
    private let springFestival = AnniversaryEvent(id: "sf", title: "春节", day: "20260217", yearly: true,
                                                  lunar: true, color: .green)

    // MARK: Look and migration

    func testOldCardsKeepTheTornPageAndNewCardsGetTheLineHourglass() {
        XCTAssertEqual(AnniversaryLook.stored(WidgetConfig()), .leaf, "an existing card has no key and stays a page")
        XCTAssertEqual(AnniversaryLook.stored(WidgetConfig([AnniversaryLook.key: .string("bogus")])), .leaf)
        XCTAssertEqual(WidgetCatalog.entry(.anniversary)?.defaults.string(AnniversaryLook.key), "leaf")
        let fresh = WidgetCatalog.make(.anniversary)!
        XCTAssertEqual(AnniversaryLook.stored(fresh.config), .line, "a new card starts on the free hourglass")
        XCTAssertEqual(AnniversaryLook.newWidget, .line)
    }

    func testGlassIsProAndFallsBackToLineWithoutUnlocking() {
        let glass = WidgetConfig([AnniversaryLook.key: .string("glass")])
        XCTAssertEqual(AnniversaryLook.shown(config: glass, unlocked: true), .glass)
        XCTAssertEqual(AnniversaryLook.shown(config: glass, unlocked: false), .line)
        XCTAssertEqual(ProLicenseGate.anniversaryLook(config: glass, unlocked: false), .line)
        XCTAssertEqual(glass.string(AnniversaryLook.key), "glass", "the choice is kept for when Pro comes back")
        XCTAssertEqual(AnniversaryLook.shown(config: WidgetConfig(), unlocked: false), .leaf)
        XCTAssertEqual(AnniversaryLook.hourglass(config: WidgetConfig(), unlocked: false), .line)
        XCTAssertEqual(AnniversaryLook.hourglass(config: glass, unlocked: true), .glass)

        XCTAssertTrue(ProFeatures.isProChoice(kind: .anniversary, key: AnniversaryLook.key, value: "glass"))
        XCTAssertFalse(ProFeatures.isProChoice(kind: .anniversary, key: AnniversaryLook.key, value: "line"))
        XCTAssertFalse(ProFeatures.isProChoice(kind: .anniversary, key: AnniversaryLook.key, value: "leaf"))
        XCTAssertFalse(ProLicenseGate.canChoose(.anniversary, [AnniversaryLook.key: .string("glass")], unlocked: false))
        XCTAssertTrue(ProLicenseGate.canChoose(.anniversary, [AnniversaryLook.key: .string("line")], unlocked: false))
        XCTAssertTrue(ProFeatures.isPro(WidgetInstance(kind: .anniversary, config: glass)))
        XCTAssertFalse(ProFeatures.isPro(WidgetCatalog.make(.anniversary)!))
        XCTAssertFalse(ProLicenseGate.needsLockOverlay(WidgetInstance(kind: .anniversary, config: glass), unlocked: false),
                       "the glass falls back to the free hourglass instead of being locked")
    }

    func testStyleOptionsOnlyApplyToTheSingleCard() {
        var config = WidgetConfig(["layout": .string("single")])
        XCTAssertTrue(WidgetCatalog.applies(AnniversaryLook.key, to: config, kind: .anniversary))
        XCTAssertTrue(WidgetCatalog.applies("showRing", to: config, kind: .anniversary), "an old page card")
        config.set(AnniversaryLook.key, .string("line"))
        XCTAssertFalse(WidgetCatalog.applies("showRing", to: config, kind: .anniversary), "no page to hide")
        config.set("layout", .string("multi"))
        XCTAssertFalse(WidgetCatalog.applies(AnniversaryLook.key, to: config, kind: .anniversary))
        XCTAssertTrue(WidgetCatalog.configurableKeys(.anniversary).contains(AnniversaryLook.key))
    }

    func testPanelWidths() {
        XCTAssertEqual(Anniversary.panelWidth(layout: "single"), 340)
        XCTAssertEqual(Anniversary.panelWidth(layout: "multi"), 328)
    }

    // MARK: Sand

    func testSandIsWhatIsLeftOfThisRound() {
        let r = reading(newYear, day(2026, 10, 22))
        XCTAssertEqual(r.days, 71)
        let sand = Anniversary.sand(r, today: day(2026, 10, 22), calendar: calendar)
        XCTAssertEqual(sand.upper, 1 - r.progress, accuracy: 1e-12)
        XCTAssertEqual(sand.upper, 71.0 / 365.0, accuracy: 1e-9)
        XCTAssertEqual(sand.upper + sand.lower, 1, accuracy: 1e-12)
        XCTAssertEqual(sand.mood, .calm)
        XCTAssertEqual(sand.daysToGo, 71)
        XCTAssertTrue(sand.flows)
        XCTAssertFalse(sand.pulses(reduceMotion: false), "the stream only pulses when it is near")
    }

    func testNearIsAFixedSevenDays() {
        XCTAssertEqual(Anniversary.nearDays, 7)
        let five = reading(wedding, day(2026, 10, 22))
        XCTAssertTrue(Anniversary.isNear(five, today: day(2026, 10, 22), calendar: calendar))
        let sand = Anniversary.sand(five, today: day(2026, 10, 22), calendar: calendar)
        XCTAssertEqual(sand.mood, .near)
        XCTAssertTrue(sand.pulses(reduceMotion: false))
        XCTAssertFalse(sand.pulses(reduceMotion: true), "still under Reduce Motion")

        XCTAssertTrue(Anniversary.isNear(reading(wedding, day(2026, 10, 20)), today: day(2026, 10, 20), calendar: calendar))
        XCTAssertFalse(Anniversary.isNear(reading(wedding, day(2026, 10, 19)), today: day(2026, 10, 19), calendar: calendar))
        XCTAssertFalse(Anniversary.isNear(reading(wedding, day(2026, 10, 27)), today: day(2026, 10, 27), calendar: calendar),
                       "the day itself is a celebration, not near")
    }

    func testTheDayItselfCelebrates() {
        let r = reading(birthday, day(2026, 5, 20))
        XCTAssertTrue(Anniversary.isCelebrating(r))
        let sand = Anniversary.sand(r, today: day(2026, 5, 20), calendar: calendar)
        XCTAssertEqual(sand.mood, .today)
        XCTAssertFalse(sand.flows)
        XCTAssertEqual(Anniversary.daysToGo(r, today: day(2026, 5, 20), calendar: calendar), 0)
    }

    func testAPassedOneOffHasRunOut() {
        let r = reading(nationalDay, day(2026, 10, 22))
        let sand = Anniversary.sand(r, today: day(2026, 10, 22), calendar: calendar)
        XCTAssertEqual(sand.mood, .spent)
        XCTAssertEqual(sand.upper, 0)
        XCTAssertEqual(sand.lower, 1)
        XCTAssertFalse(sand.flows)
        XCTAssertNil(sand.daysToGo)
    }

    func testCountingUpIsNearItsNextAnniversaryOnlyWhenYearly() {
        let r = reading(job, day(2026, 10, 22))
        XCTAssertEqual(Anniversary.daysToGo(r, today: day(2026, 10, 22), calendar: calendar), 364)
        XCTAssertEqual(Anniversary.sand(r, today: day(2026, 10, 22), calendar: calendar).upper,
                       1 - r.progress, accuracy: 1e-12)
        XCTAssertTrue(Anniversary.isNear(reading(job, day(2026, 10, 18)), today: day(2026, 10, 18), calendar: calendar))
        var once = job
        once.yearly = false
        XCTAssertNil(Anniversary.daysToGo(reading(once, day(2026, 10, 18)), today: day(2026, 10, 18), calendar: calendar))
        XCTAssertFalse(Anniversary.isNear(reading(once, day(2026, 10, 18)), today: day(2026, 10, 18), calendar: calendar))
    }

    func testFlowDotsAreStaggeredAndStayInsideTheStream() {
        let dots = Anniversary.flowDots(t: 0)
        XCTAssertEqual(dots.count, 3)
        XCTAssertEqual(dots[0], 0, accuracy: 1e-12)
        XCTAssertEqual(dots[1], 1.0 / 3, accuracy: 1e-12)
        XCTAssertEqual(dots[2], 2.0 / 3, accuracy: 1e-12)
        for t in stride(from: 0.0, to: 5, by: 0.37) {
            for dot in Anniversary.flowDots(t: t) {
                XCTAssertGreaterThanOrEqual(dot, 0)
                XCTAssertLessThan(dot, 1)
            }
        }
        XCTAssertEqual(Anniversary.flowDots(t: .nan), [])
    }

    func testHourglassGeometry() {
        XCTAssertEqual(HourglassGeometry.halfWidth(t: 0, half: 10, neck: 1), 10, accuracy: 1e-12)
        XCTAssertEqual(HourglassGeometry.halfWidth(t: 1, half: 10, neck: 1), 1, accuracy: 1e-12)
        XCTAssertLessThan(HourglassGeometry.halfWidth(t: 0.7, half: 10, neck: 1),
                          HourglassGeometry.halfWidth(t: 0.3, half: 10, neck: 1))
        XCTAssertEqual(HourglassGeometry.upperSurface(remain: 0), 1, "nothing left up top")
        XCTAssertEqual(HourglassGeometry.upperSurface(remain: 1), 0.05, accuracy: 1e-12, "never touches the cap")
        XCTAssertEqual(HourglassGeometry.lowerHeight(filled: 0), 0)
        XCTAssertEqual(HourglassGeometry.lowerHeight(filled: 1), 0.92, accuracy: 1e-12)
        XCTAssertLessThan(HourglassGeometry.lowerHeight(filled: 0.3), HourglassGeometry.lowerHeight(filled: 0.8))
    }

    // MARK: Panel

    func testClockCountsDownToMidnightOfTheDay() {
        let now = day(2026, 10, 22, hour: 16, minute: 40)
        let clock = Anniversary.clock(reading(newYear, now), now: now)
        XCTAssertEqual(clock, AnniversaryClock(days: 70, hours: 7, minutes: 20))
        let up = reading(job, day(2026, 10, 22))
        let since = Anniversary.clock(up, now: day(2026, 10, 22))
        XCTAssertEqual(since.days, up.days)
        XCTAssertEqual(since.days, 1462)
        XCTAssertEqual(since.hours, 12)
        XCTAssertEqual(Anniversary.clock(reading(birthday, day(2026, 5, 20)), now: day(2026, 5, 20)),
                       AnniversaryClock(days: 0, hours: 0, minutes: 0))
    }

    func testCycleMatchesTheProgress() {
        let today = day(2026, 10, 22)
        let r = reading(newYear, today)
        let cycle = Anniversary.cycle(r, today: today, calendar: calendar)!
        XCTAssertEqual(cycle.start, midnight(2026, 1, 1))
        XCTAssertEqual(cycle.end, midnight(2027, 1, 1))
        XCTAssertEqual(cycle.elapsed, 294)
        XCTAssertEqual(cycle.total, 365)
        XCTAssertEqual(cycle.percent, 80)
        XCTAssertEqual(cycle.fraction, r.progress, accuracy: 1e-9)

        let up = reading(job, today)
        let upCycle = Anniversary.cycle(up, today: today, calendar: calendar)!
        XCTAssertEqual(upCycle.start, midnight(2026, 10, 21))
        XCTAssertEqual(upCycle.end, midnight(2027, 10, 21))
        XCTAssertEqual(upCycle.elapsed, 1)
        XCTAssertEqual(upCycle.fraction, up.progress, accuracy: 1e-9)

        let once = AnniversaryEvent(title: "搬家", day: "20270301")
        let onceReading = reading(once, today)
        let onceCycle = Anniversary.cycle(onceReading, today: today, calendar: calendar)!
        XCTAssertEqual(onceCycle.total, 365)
        XCTAssertEqual(onceCycle.elapsed, 365 - 130)
        XCTAssertEqual(onceCycle.fraction, onceReading.progress, accuracy: 1e-9)

        XCTAssertNil(Anniversary.cycle(reading(nationalDay, today), today: today, calendar: calendar))
    }

    func testNextThreeTimes() {
        let today = day(2026, 10, 22)
        let times = Anniversary.nextTimes(newYear, today: today, calendar: calendar)
        XCTAssertEqual(times.map(\.date), [midnight(2027, 1, 1), midnight(2028, 1, 1), midnight(2029, 1, 1)])
        XCTAssertEqual(times.map(\.daysLeft), [71, 436, 802])

        let firstAhead = AnniversaryEvent(title: "开业", day: "20270301", yearly: true)
        XCTAssertEqual(Anniversary.nextTimes(firstAhead, today: today, calendar: calendar).map(\.date),
                       [midnight(2027, 3, 1), midnight(2028, 3, 1), midnight(2029, 3, 1)])

        let once = AnniversaryEvent(title: "搬家", day: "20270301")
        XCTAssertEqual(Anniversary.nextTimes(once, today: today, calendar: calendar).map(\.daysLeft), [130])
        XCTAssertEqual(Anniversary.nextTimes(nationalDay, today: today, calendar: calendar), [])
        XCTAssertEqual(Anniversary.nextTimes(job, today: today, calendar: calendar).first?.ordinal, 5)
    }

    func testAgendaRunsNearestFirstAndKeepsWhatHasPassed() {
        let today = day(2026, 10, 22)
        let line = Anniversary.agenda([job, nationalDay, springFestival, newYear], today: today, calendar: calendar)
        XCTAssertEqual(line.upcoming.map(\.reading.event.title), ["元旦", "春节", "入职"])
        XCTAssertEqual(line.upcoming.map(\.daysLeft), [71, 107, 364])
        XCTAssertEqual(line.upcoming[1].date, midnight(2027, 2, 6), "lunar new year 2027")
        XCTAssertEqual(line.upcoming[2].ordinal, 5, "the fifth anniversary of starting")
        XCTAssertNil(line.upcoming[0].ordinal)
        XCTAssertEqual(line.past.map(\.event.title), ["国庆节"])
        XCTAssertEqual(Anniversary.agendaLine(line.upcoming[0], calendar: calendar), "1月1日 周五 · 每年")
        XCTAssertEqual(Anniversary.agendaLine(line.upcoming[1], calendar: calendar), "2月6日 周六 · 农历正月初一")
        XCTAssertEqual(Anniversary.agendaLine(line.upcoming[2], calendar: calendar), "第 5 个周年 · 2027年10月21日")
        XCTAssertEqual(Anniversary.lead([job, nationalDay, newYear], today: today, calendar: calendar)?.id, "ny")
    }

    func testCardLineAndRepeatText() {
        let today = day(2026, 10, 22)
        XCTAssertEqual(Anniversary.cardLine(reading(newYear, today), today: today, calendar: calendar), "1月1日 周五 · 每年")
        XCTAssertEqual(Anniversary.cardLine(reading(wedding, today), today: today, calendar: calendar), "10月27日 周二 · 每年")
        XCTAssertEqual(Anniversary.repeatText(newYear), "每年 · 公历")
        XCTAssertEqual(Anniversary.repeatText(springFestival), "每年 · 农历")
        XCTAssertEqual(Anniversary.repeatText(nationalDay), "不重复")
    }

    // MARK: Icons

    func testIconsFollowTheName() {
        func symbol(_ title: String, kind: AnniversaryEvent.Kind = .countdown) -> String {
            AnniversaryIcon.symbol(for: AnniversaryEvent(title: title, day: "20260101", kind: kind))
        }
        XCTAssertEqual(symbol("妈妈生日"), "birthday.cake.fill")
        XCTAssertEqual(symbol("Birthday"), "birthday.cake.fill")
        XCTAssertEqual(symbol("结婚纪念日"), "heart.fill")
        XCTAssertEqual(symbol("在一起", kind: .countup), "heart.fill")
        XCTAssertEqual(symbol("入职", kind: .countup), "briefcase.fill")
        XCTAssertEqual(symbol("元旦"), "sparkles")
        XCTAssertEqual(symbol("春节"), "moon.stars.fill")
        XCTAssertEqual(symbol("国庆节"), "flag.fill")
        XCTAssertEqual(symbol("Movie night"), AnniversaryIcon.countdownFallback)
        XCTAssertEqual(symbol("某天", kind: .countup), AnniversaryIcon.countupFallback)
    }
}
