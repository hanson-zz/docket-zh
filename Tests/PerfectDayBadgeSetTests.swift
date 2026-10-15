import Foundation
import XCTest

/// 竹篮的隐藏徽章和节日限定徽章：条件、农历和节气窗口、跨年、年份记录、累计杯数。
final class PerfectDayBadgeSetTests: XCTestCase {
    private let calendar = PerfectDay.calendar

    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    private func key(_ date: Date) -> String { HabitTracker.dayKey(date, calendar: calendar) }

    private func record(_ k: String, _ marks: String) -> PerfectDayRecord {
        PerfectDayRecord(decoding: "\(k)|\(marks)")!
    }

    private func run(from start: Date, days: Int, marks: String) -> [PerfectDayRecord] {
        (0..<days).map { offset in
            record(key(calendar.date(byAdding: .day, value: offset, to: start)!), marks)
        }
    }

    private func measure(_ badge: PerfectBadge, _ records: [PerfectDayRecord],
                         _ input: PerfectBadgeInput = PerfectBadgeInput()) -> Int {
        PerfectBadges.measure(badge, records: records, input: input, calendar: calendar)
    }

    private func window(_ badge: PerfectBadge) -> FestivalWindow { badge.festivalWindow! }

    private func inWindow(_ badge: PerfectBadge, _ y: Int, _ m: Int, _ d: Int) -> Bool {
        window(badge).contains(day(y, m, d), base: calendar)
    }

    // MARK: Catalogue

    func testThirtyBadgesWithHintsAndWindows() {
        let all = PerfectBadge.allCases
        XCTAssertEqual(all.count, 30)
        XCTAssertEqual(Set(all.map(\.rawValue)).count, 30, "ids are distinct")
        XCTAssertEqual(Set(all.map(\.title)).count, 30, "names are distinct")
        let hidden = all.filter { $0.category == .hidden }
        let festival = all.filter { $0.category == .festival }
        XCTAssertEqual(hidden.map(\.title), ["夜猫子", "早起竹笋", "失而复得", "金色一周", "整月满篮", "千杯不醉",
                                             "两百小时", "闰日竹叶"])
        XCTAssertEqual(festival.map(\.title), ["元旦", "春节", "元宵", "植树节", "世界水日", "清明", "端午", "七夕",
                                               "中秋", "国庆", "重阳", "冬至"])
        XCTAssertTrue(hidden.allSatisfy { $0.hint != nil && $0.festivalWindow == nil })
        XCTAssertTrue(festival.allSatisfy { $0.hint == nil && $0.festivalWindow != nil })
        XCTAssertEqual(PerfectBadge.nightOwl.hint, "月亮出来以后")
        XCTAssertEqual(PerfectBadge.leapDay.hint, "四年一遇")
        // 静心 100 小时已经是累计 100 小时，隐藏的这一枚改成 200 小时。
        XCTAssertEqual(PerfectBadge.focus100h.target, 100 * 60)
        XCTAssertEqual(PerfectBadge.focus200h.target, 200 * 60)
        for badge in all {
            XCTAssertFalse(badge.title.contains("\u{2014}") || badge.condition.contains("\u{2014}"))
        }
    }

    func testALockedHiddenBadgeShowsOnlyQuestionMarksAndItsHint() {
        let statuses = PerfectBadges.statuses(records: [], input: PerfectBadgeInput(), earned: [:], calendar: calendar)
        let owl = statuses.first { $0.badge == .nightOwl }!
        XCTAssertTrue(owl.isConcealed)
        XCTAssertFalse(owl.isLit)
        XCTAssertEqual(owl.shownTitle, "？？？")
        XCTAssertEqual(owl.shownCondition, "（月亮出来以后）")
        let shown = PerfectBadges.statuses(records: [], input: PerfectBadgeInput(lateFocus: true), earned: [:],
                                           calendar: calendar).first { $0.badge == .nightOwl }!
        XCTAssertTrue(shown.unlocked)
        XCTAssertEqual(shown.shownTitle, "夜猫子")
        XCTAssertEqual(shown.shownCondition, "晚上 23 点以后完成一轮专注")
    }

    // MARK: Hidden conditions

    func testLateNightFocus() {
        XCTAssertTrue(FocusLog.isLateNight(day(2026, 10, 15, hour: 23), calendar: calendar))
        XCTAssertTrue(FocusLog.isLateNight(day(2026, 10, 16, hour: 3), calendar: calendar))
        XCTAssertFalse(FocusLog.isLateNight(day(2026, 10, 15, hour: 22), calendar: calendar))
        XCTAssertFalse(FocusLog.isLateNight(day(2026, 10, 16, hour: 4), calendar: calendar))
        XCTAssertEqual(measure(.nightOwl, [], PerfectBadgeInput(lateFocus: true)), 1)
        XCTAssertEqual(measure(.nightOwl, []), 0)
    }

    func testEarlyFirstDrink() {
        let early = WaterDay(key: "20261015", goal: 2000, entries: [WaterEntry(minute: 6 * 60 + 40, type: .water, amount: 250),
                                                                    WaterEntry(minute: 9 * 60, type: .tea, amount: 200)])
        XCTAssertTrue(PerfectBadges.hasEarlyFirstDrink([early]))
        // 第一杯在半夜：那是熬夜，不算早起。
        let lateNight = WaterDay(key: "20261015", goal: 2000, entries: [WaterEntry(minute: 60, type: .water, amount: 250),
                                                                        WaterEntry(minute: 6 * 60, type: .water, amount: 250)])
        XCTAssertFalse(PerfectBadges.hasEarlyFirstDrink([lateNight]))
        let seven = WaterDay(key: "20261015", goal: 2000, entries: [WaterEntry(minute: 7 * 60, type: .water, amount: 250)])
        XCTAssertFalse(PerfectBadges.hasEarlyFirstDrink([seven]))
        XCTAssertFalse(PerfectBadges.hasEarlyFirstDrink([WaterDay(key: "20261001", goal: 2000, summary: 2000)]))
        XCTAssertEqual(measure(.earlyWater, [], PerfectBadgeInput(earlyDrink: true)), 1)
    }

    func testComebackNeedsAGapOfThreeDays() {
        let twoDayGap = [record("20261001", "100"), record("20261004", "100")]
        XCTAssertEqual(measure(.comeback, twoDayGap), 0, "two empty days in between")
        let threeDayGap = [record("20261001", "100"), record("20261002", "000"), record("20261006", "100")]
        XCTAssertEqual(measure(.comeback, threeDayGap), 1)
        // 跨年也算。
        XCTAssertEqual(measure(.comeback, [record("20261229", "111"), record("20270102", "111")]), 1)
        XCTAssertEqual(measure(.comeback, [record("20261001", "100")]), 0)
    }

    func testGoldWeekFullMonthAndLeapDay() {
        XCTAssertEqual(measure(.goldWeek, run(from: day(2026, 10, 1), days: 7, marks: "111")), 7)
        XCTAssertEqual(measure(.goldWeek, run(from: day(2026, 10, 1), days: 7, marks: "110")), 0, "silver is not gold")
        XCTAssertEqual(measure(.fullMonth, run(from: day(2027, 2, 1), days: 28, marks: "100")), 1, "February 2027")
        XCTAssertEqual(measure(.fullMonth, run(from: day(2026, 10, 1), days: 30, marks: "100")), 0, "October has 31")
        XCTAssertEqual(measure(.fullMonth, run(from: day(2026, 12, 15), days: 31, marks: "100")), 0, "across two months")
        XCTAssertEqual(measure(.fullMonth, run(from: day(2028, 2, 1), days: 28, marks: "100")), 0, "2028 has a 29th")
        XCTAssertEqual(measure(.leapDay, [record("20280229", "100")]), 1)
        XCTAssertEqual(measure(.leapDay, [record("20280229", "000")]), 0)
        XCTAssertEqual(measure(.leapDay, [record("20270228", "111")]), 0)
    }

    func testCumulativeCupsAndHours() {
        let cups = PerfectBadges.statuses(records: [], input: PerfectBadgeInput(waterCups: 420), earned: [:],
                                          calendar: calendar).first { $0.badge == .cups1000 }!
        XCTAssertFalse(cups.unlocked)
        XCTAssertEqual(cups.progressText, "420/1000 杯")
        XCTAssertEqual(measure(.cups1000, [], PerfectBadgeInput(waterCups: 1000)), 1000)
        let hours = PerfectBadges.statuses(records: [], input: PerfectBadgeInput(focusMinutes: 150 * 60), earned: [:],
                                           calendar: calendar)
        XCTAssertTrue(hours.first { $0.badge == .focus100h }!.unlocked)
        let two = hours.first { $0.badge == .focus200h }!
        XCTAssertFalse(two.unlocked)
        XCTAssertEqual(two.progressText, "150/200 小时")
    }

    // MARK: Festival windows, 2026 and 2027

    func testSpringFestivalRunsFromNewYearsEveToTheSeventhDay() {
        // 2026 年腊月只有 29 天，除夕是腊月廿九（2 月 16 日）。
        XCTAssertFalse(inWindow(.festSpring, 2026, 2, 15))
        XCTAssertTrue(inWindow(.festSpring, 2026, 2, 16))
        XCTAssertTrue(inWindow(.festSpring, 2026, 2, 17))
        XCTAssertTrue(inWindow(.festSpring, 2026, 2, 23))
        XCTAssertFalse(inWindow(.festSpring, 2026, 2, 24))
        // 2027 年春节是 2 月 6 日，除夕 2 月 5 日，初七 2 月 12 日。
        XCTAssertFalse(inWindow(.festSpring, 2027, 2, 4))
        XCTAssertTrue(inWindow(.festSpring, 2027, 2, 5))
        XCTAssertTrue(inWindow(.festSpring, 2027, 2, 12))
        XCTAssertFalse(inWindow(.festSpring, 2027, 2, 13))
        // 2024 年腊月有 30 天：除夕是腊月三十（2 月 9 日），廿九不算。
        XCTAssertTrue(inWindow(.festSpring, 2024, 2, 9))
        XCTAssertFalse(inWindow(.festSpring, 2024, 2, 8))
        XCTAssertEqual(window(.festSpring).text, "农历除夕至正月初七")
        let occurrence = window(.festSpring).occurrence(inYear: 2026, base: calendar)!
        XCTAssertEqual(key(occurrence.start), "20260216")
        XCTAssertEqual(key(occurrence.end), "20260223")
    }

    func testLunarFestivalDays() {
        let expected: [(PerfectBadge, (Int, Int, Int), (Int, Int, Int))] = [
            (.festLantern, (2026, 3, 3), (2027, 2, 20)),
            (.festDragonBoat, (2026, 6, 19), (2027, 6, 9)),
            (.festQixi, (2026, 8, 19), (2027, 8, 8)),
            (.festMidAutumn, (2026, 9, 25), (2027, 9, 15)),
            (.festDoubleNinth, (2026, 10, 18), (2027, 10, 8)),
        ]
        for (badge, a, b) in expected {
            for (y, m, d) in [a, b] {
                XCTAssertTrue(inWindow(badge, y, m, d), "\(badge.title) \(y)-\(m)-\(d)")
                let before = calendar.date(byAdding: .day, value: -1, to: day(y, m, d))!
                let after = calendar.date(byAdding: .day, value: 1, to: day(y, m, d))!
                XCTAssertFalse(window(badge).contains(before, base: calendar), "\(badge.title) day before")
                XCTAssertFalse(window(badge).contains(after, base: calendar), "\(badge.title) day after")
                let occurrence = window(badge).occurrence(inYear: y, base: calendar)!
                XCTAssertEqual(key(occurrence.start), key(day(y, m, d)), badge.title)
                XCTAssertEqual(occurrence.start, occurrence.end)
            }
        }
        XCTAssertEqual(window(.festMidAutumn).text, "农历八月十五")
        XCTAssertEqual(window(.festDragonBoat).text, "农历五月初五")
    }

    func testSolarTermFestivals() {
        XCTAssertTrue(inWindow(.festQingming, 2026, 4, 5))
        XCTAssertFalse(inWindow(.festQingming, 2026, 4, 4))
        XCTAssertTrue(inWindow(.festQingming, 2027, 4, 5))
        XCTAssertFalse(inWindow(.festQingming, 2027, 4, 6))
        XCTAssertTrue(inWindow(.festWinterSolstice, 2026, 12, 22))
        XCTAssertFalse(inWindow(.festWinterSolstice, 2026, 12, 21))
        XCTAssertTrue(inWindow(.festWinterSolstice, 2027, 12, 22))
        XCTAssertFalse(inWindow(.festWinterSolstice, 2027, 12, 23))
        XCTAssertEqual(window(.festQingming).text, "清明当天")
        XCTAssertEqual(key(window(.festWinterSolstice).occurrence(inYear: 2026, base: calendar)!.start), "20261222")
    }

    func testGregorianFestivals() {
        XCTAssertTrue(inWindow(.festNewYear, 2027, 1, 1))
        XCTAssertFalse(inWindow(.festNewYear, 2026, 12, 31))
        XCTAssertTrue(inWindow(.festArbor, 2027, 3, 12))
        XCTAssertTrue(inWindow(.festWaterDay, 2027, 3, 22))
        XCTAssertFalse(inWindow(.festWaterDay, 2027, 3, 23))
        XCTAssertTrue(inWindow(.festNational, 2026, 10, 1))
        XCTAssertTrue(inWindow(.festNational, 2026, 10, 7))
        XCTAssertFalse(inWindow(.festNational, 2026, 10, 8))
        XCTAssertFalse(inWindow(.festNational, 2026, 9, 30))
        XCTAssertEqual(window(.festNational).text, "公历10月1日至10月7日")
        XCTAssertEqual(window(.festNewYear).text, "公历1月1日")
    }

    // MARK: Earning festivals and years

    func testFestivalIsEarnedInItsWindowAndYearsAreRecorded() {
        var records = run(from: day(2026, 9, 30), days: 3, marks: "100")
        var earned = PerfectBadges.earning([:], records: records, input: PerfectBadgeInput(), today: day(2026, 10, 2),
                                           calendar: calendar)
        XCTAssertEqual(earned["festNational"], "20261001", "dated the first day in the window")
        XCTAssertNil(earned["festMidAutumn"])
        var years = PerfectBadges.festivalYears([:], records: records, today: day(2026, 10, 2), calendar: calendar)
        XCTAssertEqual(years["festNational"], [2026])
        // 第二年再拿一次：年份加上，第一次的日期不变。
        records = [record("20271003", "111")]
        earned = PerfectBadges.earning(earned, records: records, input: PerfectBadgeInput(), today: day(2027, 10, 3),
                                       calendar: calendar)
        years = PerfectBadges.festivalYears(years, records: records, today: day(2027, 10, 3), calendar: calendar)
        XCTAssertEqual(earned["festNational"], "20261001")
        XCTAssertEqual(years["festNational"], [2026, 2027])
        // 同一年再拿不重复记。
        years = PerfectBadges.festivalYears(years, records: [record("20271005", "100")], today: day(2027, 10, 5),
                                            calendar: calendar)
        XCTAssertEqual(years["festNational"], [2026, 2027])
    }

    func testANewYearsDayAcrossTheYearEnd() {
        let records = [record("20261231", "111"), record("20270101", "100")]
        let earned = PerfectBadges.earning([:], records: records, input: PerfectBadgeInput(), today: day(2027, 1, 1),
                                           calendar: calendar)
        XCTAssertEqual(earned["festNewYear"], "20270101")
        let years = PerfectBadges.festivalYears([:], records: records, today: day(2027, 1, 1), calendar: calendar)
        XCTAssertEqual(years["festNewYear"], [2027])
        // 2027 年春节窗口里的除夕（2 月 5 日）记在 2027 年。
        let spring = PerfectBadges.festivalYears([:], records: [record("20270205", "100")], today: day(2027, 2, 5),
                                                 calendar: calendar)
        XCTAssertEqual(spring["festSpring"], [2027])
    }

    func testWorldWaterDayNeedsWaterAndNoLeafMeansNothing() {
        let dry = [record("20270322", "011"), record("20270312", "000")]
        let none = PerfectBadges.earning([:], records: dry, input: PerfectBadgeInput(), today: day(2027, 3, 22),
                                         calendar: calendar)
        XCTAssertNil(none["festWaterDay"], "a silver leaf without water does not count")
        XCTAssertNil(none["festArbor"], "no leaf on 植树节")
        let wet = PerfectBadges.earning([:], records: [record("20270322", "1--")], input: PerfectBadgeInput(),
                                        today: day(2027, 3, 22), calendar: calendar)
        XCTAssertEqual(wet["festWaterDay"], "20270322")
    }

    func testFestivalsAreNeverUnlockedOutsideTheirWindowAndOldDaysAreNotRescanned() {
        // 窗口外达到条件不算。
        let statuses = PerfectBadges.statuses(records: run(from: day(2026, 10, 10), days: 5, marks: "111"),
                                              input: PerfectBadgeInput(), earned: [:], calendar: calendar)
        XCTAssertTrue(statuses.filter { $0.badge.category == .festival }.allSatisfy { !$0.unlocked })
        // 早于回看天数的日子当时已经看过，不再补记。
        let old = PerfectBadges.earning([:], records: [record("20260101", "111")], input: PerfectBadgeInput(),
                                        today: day(2026, 10, 15), calendar: calendar)
        XCTAssertNil(old["festNewYear"])
    }

    func testFestivalPhaseThisYear() {
        let today = day(2026, 10, 15)
        let statuses = PerfectBadges.statuses(records: [], input: PerfectBadgeInput(),
                                              earned: ["festNational": "20261001"],
                                              years: ["festNational": [2026], "festMidAutumn": [2025]],
                                              today: today, calendar: calendar)
        func status(_ badge: PerfectBadge) -> PerfectBadgeStatus { statuses.first { $0.badge == badge }! }
        XCTAssertEqual(status(.festNational).phase, .earned)
        XCTAssertTrue(status(.festNational).isLit)
        XCTAssertEqual(status(.festNational).festivalLine, "今年已收下\n已收 2026")
        XCTAssertEqual(status(.festMidAutumn).phase, .missed)
        XCTAssertFalse(status(.festMidAutumn).isLit)
        XCTAssertEqual(status(.festMidAutumn).festivalLine, "明年再来\n已收 2025")
        XCTAssertEqual(status(.festDoubleNinth).phase, .upcoming)
        XCTAssertEqual(status(.festDoubleNinth).festivalLine, "农历九月初九")
        XCTAssertEqual(status(.festWinterSolstice).phase, .upcoming)
        XCTAssertEqual(status(.festNewYear).phase, .missed)
        XCTAssertEqual(PerfectBadges.phase(window(.festDoubleNinth), years: [], today: day(2026, 10, 18),
                                           calendar: calendar), .open)
        XCTAssertEqual(PerfectBadges.phase(window(.festSpring), years: [], today: day(2027, 1, 20),
                                           calendar: calendar), .upcoming)
        // 非节日徽章没有 phase，亮不亮只看解锁。
        XCTAssertNil(status(.leafStreak3).phase)
    }

    // MARK: Water cups

    func testCupsAreSeededFromTheWaterLogAndOnlyCountedOnce() {
        let today = day(2026, 10, 15)
        let entries = (0..<3).map { WaterEntry(minute: 600 + $0 * 60, type: .water, amount: 250) }
        var water = [WaterDay(key: "20261015", goal: 2000, entries: entries),
                     WaterDay(key: "20261001", goal: 2000, summary: 1000)]
        var tally = PerfectBadges.countingCups(folded: 0, days: [:], water: water, today: today, calendar: calendar)
        XCTAssertEqual(tally.days["20261015"], 3)
        XCTAssertEqual(tally.days["20261001"], 4, "1000 ml in 250 ml cups, for days before the count")
        // 一个已经数过的日子后来只剩总量：保留原来的数。
        water = [WaterDay(key: "20261015", goal: 2000, summary: 2000)]
        tally = PerfectBadges.countingCups(folded: tally.folded, days: tally.days, water: water, today: today,
                                           calendar: calendar)
        XCTAssertEqual(tally.days["20261015"], 3)
        // 两个喝水小组件是同一个人：取最多的那个，不相加。
        let more = (0..<5).map { WaterEntry(minute: 600 + $0 * 30, type: .tea, amount: 100) }
        water = [WaterDay(key: "20261015", goal: 2000, entries: entries),
                 WaterDay(key: "20261015", goal: 2000, entries: more)]
        tally = PerfectBadges.countingCups(folded: tally.folded, days: tally.days, water: water, today: today,
                                           calendar: calendar)
        XCTAssertEqual(tally.days["20261015"], 5)
        // 很久以前的日子折进 folded，总数不变。
        let later = day(2027, 6, 1)
        let folded = PerfectBadges.countingCups(folded: tally.folded, days: tally.days, water: [], today: later,
                                                calendar: calendar)
        XCTAssertTrue(folded.days.isEmpty)
        XCTAssertEqual(folded.folded, 9)
        let archive = PerfectDayArchive(cupsFolded: folded.folded, cupDays: ["20270601": 2])
        XCTAssertEqual(archive.cupCount, 11)
    }

    // MARK: Old archives

    func testAnOldArchiveReadsAndTheNewFieldsRoundTrip() throws {
        let json = #"{"days":["20261014|111"],"earned":{"firstPerfect":"20261014"}}"#
        let old = try JSONDecoder().decode(PerfectDayArchive.self, from: Data(json.utf8))
        XCTAssertEqual(old.earned["firstPerfect"], "20261014")
        XCTAssertTrue(old.festivalYears.isEmpty)
        XCTAssertEqual(old.cupCount, 0)
        let next = PerfectDayArchive(days: old.days, earned: old.earned, festivalYears: ["festNational": [2026]],
                                     cupsFolded: 12, cupDays: ["20261015": 3])
        let back = try JSONDecoder().decode(PerfectDayArchive.self, from: JSONEncoder().encode(next))
        XCTAssertEqual(back, next)
        XCTAssertEqual(back.cupCount, 15)
        // 一项写坏了不影响其他项。
        let broken = #"{"days":["20261014|111"],"earned":{},"festivalYears":"oops","cupsFolded":3}"#
        let partial = try JSONDecoder().decode(PerfectDayArchive.self, from: Data(broken.utf8))
        XCTAssertTrue(partial.festivalYears.isEmpty)
        XCTAssertEqual(partial.cupsFolded, 3)
        XCTAssertEqual(partial.records.count, 1)
    }
}
