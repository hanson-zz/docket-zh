import Foundation
import XCTest

final class PerfectDayTests: XCTestCase {
    private let calendar = PerfectDay.calendar

    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    private func key(_ date: Date) -> String { HabitTracker.dayKey(date, calendar: calendar) }

    private func record(_ k: String, _ marks: String) -> PerfectDayRecord {
        PerfectDayRecord(decoding: "\(k)|\(marks)")!
    }

    // MARK: The rule

    func testThreeItems() {
        XCTAssertEqual(PerfectDay.tier(met: 3, participating: 3), .gold)
        XCTAssertEqual(PerfectDay.tier(met: 2, participating: 3), .silver)
        XCTAssertEqual(PerfectDay.tier(met: 1, participating: 3), .bronze)
        XCTAssertNil(PerfectDay.tier(met: 0, participating: 3))
    }

    func testFewerItems() {
        XCTAssertEqual(PerfectDay.tier(met: 2, participating: 2), .gold)
        XCTAssertEqual(PerfectDay.tier(met: 1, participating: 2), .bronze)
        XCTAssertNil(PerfectDay.tier(met: 0, participating: 2))
        XCTAssertEqual(PerfectDay.tier(met: 1, participating: 1), .bronze, "one item alone is never gold")
        XCTAssertNil(PerfectDay.tier(met: 0, participating: 0))
        XCTAssertEqual(PerfectDay.tier(met: 5, participating: 2), .gold, "met is capped at participating")
    }

    func testTierNames() {
        XCTAssertEqual(PerfectDayTier.gold.title, "完美一天")
        XCTAssertEqual(PerfectDayTier.silver.title, "美好一天")
        XCTAssertEqual(PerfectDayTier.bronze.title, "奈斯一天")
        XCTAssertTrue(PerfectDayTier.gold > .silver && PerfectDayTier.silver > .bronze)
    }

    func testRecordEncodingRoundTrips() {
        let r = PerfectDayRecord(key: "20261015", water: .met, habit: .off, focus: .missed)
        XCTAssertEqual(r.encoded, "20261015|1-0")
        XCTAssertEqual(PerfectDayRecord(decoding: r.encoded), r)
        XCTAssertEqual(r.participating, 2)
        XCTAssertEqual(r.tier, .bronze)
        XCTAssertNil(PerfectDayRecord(decoding: "20261015|11"))
        XCTAssertNil(PerfectDayRecord(decoding: "2026-10-15|111"))
        XCTAssertNil(PerfectDayRecord(decoding: "20261015|1x1"))
    }

    func testArchiveDecodesLeniently() throws {
        let archive = try JSONDecoder().decode(PerfectDayArchive.self, from: Data("{}".utf8))
        XCTAssertEqual(archive, PerfectDayArchive())
        var full = PerfectDayArchive()
        full.setRecords([record("20261002", "111"), record("20261001", "0-1")])
        full.earned = ["firstPerfect": "20261002"]
        let back = try JSONDecoder().decode(PerfectDayArchive.self, from: JSONEncoder().encode(full))
        XCTAssertEqual(back, full)
        XCTAssertEqual(back.records.map(\.key), ["20261001", "20261002"])
    }

    // MARK: Sources

    func testWaterReadsTodayAgainstTheCurrentGoalAndPastDaysFrozen() {
        let today = day(2026, 10, 15, hour: 15)
        var config = WidgetConfig(["goal": .number(1000)])
        var days = WaterIntake.logging(.water, amount: 1000, in: [], goal: 1000, now: today, calendar: calendar)
        days.append(WaterDay(key: "20261014", goal: 2000, summary: 1500))
        WaterIntake.store(days, in: &config, now: today, calendar: calendar)

        XCTAssertEqual(PerfectDay.water([config], on: today, today: today, calendar: calendar).mark, .met)
        XCTAssertEqual(PerfectDay.water([config], on: day(2026, 10, 14), today: today, calendar: calendar).mark,
                       .missed, "yesterday keeps its own 2000 ml goal")
        XCTAssertEqual(PerfectDay.water([], on: today, today: today, calendar: calendar).mark, .off)
    }

    func testHabitsAllDoneAcrossWidgetsAndOffWithoutHabits() {
        let today = day(2026, 10, 15)
        var a = WidgetConfig()
        HabitTracker.store([Habit(id: "x", name: "早起", days: ["20261015"])], in: &a, now: today)
        var b = WidgetConfig()
        HabitTracker.store([Habit(id: "y", name: "读书", days: ["20261014"]),
                            Habit(id: "x", name: "早起", days: ["20261015"])], in: &b, now: today)
        let mixed = PerfectDay.habits([a, b], on: today, calendar: calendar)
        XCTAssertEqual(mixed.mark, .missed)
        XCTAssertEqual(mixed.detail, "1/2 项", "a habit in two widgets counts once")
        XCTAssertEqual(PerfectDay.habits([a], on: today, calendar: calendar).mark, .met)
        XCTAssertEqual(PerfectDay.habits([WidgetConfig()], on: today, calendar: calendar).mark, .off)
    }

    func testFocusAgainstTheGoal() {
        XCTAssertEqual(PerfectDay.focus(minutes: 50, goal: 50, hasTimer: true).mark, .met)
        XCTAssertEqual(PerfectDay.focus(minutes: 30, goal: 50, hasTimer: true).mark, .missed)
        XCTAssertEqual(PerfectDay.focus(minutes: 30, goal: 50, hasTimer: true).fraction, 0.6, accuracy: 0.001)
        XCTAssertEqual(PerfectDay.focus(minutes: 0, goal: 50, hasTimer: false).mark, .off)
        XCTAssertEqual(PerfectDay.focus(minutes: 60, goal: 50, hasTimer: false).mark, .met,
                       "minutes logged count even with no timer tile placed")
    }

    func testProgressReadsTheFocusLog() {
        let today = day(2026, 10, 15)
        let minutes = FocusLog.minutes(["20261015|50"])
        let items = PerfectDay.progress(water: [], habits: [], focusMinutes: minutes, focusGoal: 50,
                                        hasTimer: true, on: today, today: today, calendar: calendar)
        XCTAssertEqual(items.map(\.item), [.water, .habit, .focus])
        let r = PerfectDay.record(items, key: "20261015")
        XCTAssertEqual(r.encoded, "20261015|--1")
        XCTAssertEqual(r.tier, .bronze)
    }

    // MARK: Settling

    func testSettlingRereadsTodayAndYesterdayAndFreezesOlderDays() {
        let today = day(2026, 10, 15)
        let old = [record("20261012", "000"), record("20261013", "000"), record("20261014", "000")]
        let settled = PerfectDay.settled(old, today: today, calendar: calendar) { date in
            PerfectDayRecord(key: "", water: .met, habit: .met, focus: .met)
        }
        XCTAssertEqual(settled.map(\.encoded),
                       ["20261012|000", "20261013|000", "20261014|111", "20261015|111"])
    }

    func testSettlingFillsGapsButNothingBeforeTheFirstDay() {
        let today = day(2026, 10, 15)
        let settled = PerfectDay.settled([record("20261011", "111")], today: today, calendar: calendar) { _ in
            PerfectDayRecord(key: "", water: .met)
        }
        XCTAssertEqual(settled.map(\.key), ["20261011", "20261012", "20261013", "20261014", "20261015"])
        XCTAssertEqual(settled.first?.encoded, "20261011|111", "the first day was frozen")
        XCTAssertEqual(PerfectDay.settled([], today: today, calendar: calendar) { _ in PerfectDayRecord(key: "") }
            .map(\.key), ["20261015"], "a new history starts today")
    }

    func testSettlingDropsDaysAheadOfToday() {
        let settled = PerfectDay.settled([record("20261020", "111")], today: day(2026, 10, 15),
                                         calendar: calendar) { _ in PerfectDayRecord(key: "") }
        XCTAssertFalse(settled.contains { $0.key == "20261020" })
    }

    // MARK: Months

    func testMonthCountsSunsAndCells() {
        let today = day(2026, 10, 15)
        let records = [record("20260930", "111"), record("20261001", "111"), record("20261002", "110"),
                       record("20261003", "100"), record("20261004", "000"), record("20261005", "111")]
        let counts = PerfectDay.counts(records, month: today, calendar: calendar)
        XCTAssertEqual(counts[.gold], 2)
        XCTAssertEqual(counts[.silver], 1)
        XCTAssertEqual(counts[.bronze], 1)
        XCTAssertEqual(PerfectDay.suns(records, month: today, calendar: calendar), [.gold, .silver, .bronze, .gold])

        let cells = PerfectDay.monthDays(records, month: today, today: today, calendar: calendar)
        XCTAssertEqual(cells.count, 31)
        XCTAssertEqual(cells[14].isToday, true)
        XCTAssertTrue(cells[15].isFuture)
        XCTAssertEqual(cells[0].tier, .gold)
        XCTAssertNil(cells[3].tier)
    }

    func testMonthGridFollowsTheFirstWeekday() {
        let today = day(2026, 10, 15)
        // 2026-10-01 is a Thursday.
        let sunday = PerfectDay.monthGrid([], month: today, today: today, firstWeekday: 1, calendar: calendar)
        XCTAssertEqual(sunday[0].prefix(4).filter { $0 == nil }.count, 4)
        XCTAssertEqual(sunday[0][4]?.day, 1)
        let monday = PerfectDay.monthGrid([], month: today, today: today, firstWeekday: 2, calendar: calendar)
        XCTAssertEqual(monday[0][3]?.day, 1)
        XCTAssertTrue(monday.allSatisfy { $0.count == 7 })
        XCTAssertEqual(PerfectDay.weekdaySymbols(firstWeekday: 1).first, "日")
        XCTAssertEqual(PerfectDay.weekdaySymbols(firstWeekday: 2), ["一", "二", "三", "四", "五", "六", "日"])
    }

    func testStreaks() {
        let today = day(2026, 10, 15)
        let records = [record("20261010", "111"), record("20261012", "100"), record("20261013", "110"),
                       record("20261014", "111"), record("20261015", "000")]
        XCTAssertEqual(PerfectDay.currentStreak(records, today: today, calendar: calendar), 3,
                       "today without a sun yet keeps yesterday's run")
        XCTAssertEqual(PerfectDay.longestRun(["20261030", "20261031", "20261101"], calendar: calendar), 3)
        XCTAssertEqual(PerfectDay.longestRun([], calendar: calendar), 0)
    }

    func testMonthTitle() {
        XCTAssertEqual(PerfectDay.monthTitle(day(2026, 10, 15), calendar: calendar), "2026年10月")
    }

    // MARK: Badges

    private func run(from start: Date, days: Int, marks: String) -> [PerfectDayRecord] {
        (0..<days).map { offset in
            record(key(calendar.date(byAdding: .day, value: offset, to: start)!), marks)
        }
    }

    func testBadgesUnlockFromRecords() {
        let records = run(from: day(2026, 10, 1), days: 7, marks: "110")
        let statuses = PerfectBadges.statuses(records: records, focusMinutes: 0, earned: [:], calendar: calendar)
        func status(_ badge: PerfectBadge) -> PerfectBadgeStatus { statuses.first { $0.badge == badge }! }
        XCTAssertFalse(status(.firstPerfect).unlocked)
        XCTAssertTrue(status(.sunStreak3).unlocked)
        XCTAssertTrue(status(.sunStreak7).unlocked)
        XCTAssertFalse(status(.sunStreak30).unlocked)
        XCTAssertEqual(status(.sunStreak30).progressText, "7/30")
        XCTAssertTrue(status(.water7).unlocked)
        XCTAssertTrue(status(.habit7).unlocked)
        XCTAssertEqual(PerfectBadge.allCases.count, statuses.count)
    }

    func testPerfectMonthAndCollectorAndFocus() {
        let records = run(from: day(2026, 9, 25), days: 15, marks: "111")
        XCTAssertEqual(PerfectBadges.measure(.perfectMonth10, records: records, focusMinutes: 0, calendar: calendar), 9,
                       "best single month, not a run across two")
        XCTAssertEqual(PerfectBadges.measure(.suns50, records: records, focusMinutes: 0, calendar: calendar), 15)
        let focus = PerfectBadges.statuses(records: [], focusMinutes: 630, earned: [:], calendar: calendar)
        XCTAssertTrue(focus.first { $0.badge == .focus10h }!.unlocked)
        let hundred = focus.first { $0.badge == .focus100h }!
        XCTAssertFalse(hundred.unlocked)
        XCTAssertEqual(hundred.progressText, "10/100 小时")
    }

    func testEarnedBadgesAreKeptAndDated() {
        let today = day(2026, 10, 15)
        let records = [record("20261015", "111")]
        let earned = PerfectBadges.earning([:], records: records, focusMinutes: 0, today: today, calendar: calendar)
        XCTAssertEqual(earned["firstPerfect"], "20261015")
        // Later the records are gone; the badge stays.
        let kept = PerfectBadges.earning(earned, records: [], focusMinutes: 0, today: day(2026, 12, 1),
                                         calendar: calendar)
        XCTAssertEqual(kept["firstPerfect"], "20261015")
        let statuses = PerfectBadges.statuses(records: [], focusMinutes: 0, earned: kept, calendar: calendar)
        XCTAssertTrue(statuses.first { $0.badge == .firstPerfect }!.unlocked)
    }

    func testCatalogAndSearch() {
        let entry = WidgetCatalog.entry(.perfectDay)
        XCTAssertEqual(entry?.name, "完美一天")
        XCTAssertEqual(WidgetCatalog.configurableKeys(.perfectDay), [], "the focus goal is the timer panel's")
        for query in ["完美", "太阳", "wmyt", "洞悉", "打卡汇总", "perfect"] {
            XCTAssertTrue(WidgetSearch.matches(query, names: ["完美一天"], kind: "perfect-day"), query)
        }
    }

    // MARK: FocusLog lifetime total

    func testLifetimeTotalStartsFromTheLogAndOnlyGrows() {
        let lines = ["20261014|50", "20261015|25"]
        XCTAssertEqual(FocusLog.lifetimeMinutes(stored: 0, lines: lines), 75, "seeded from the log")
        XCTAssertEqual(FocusLog.lifetimeMinutes(stored: 900, lines: lines), 900, "older minutes are kept")
        XCTAssertEqual(FocusLog.lifetimeMinutes(stored: 10, lines: lines), 75, "never below the log")
        XCTAssertEqual(FocusLog.addingTotal(seconds: 25 * 60, stored: 900, lines: lines), 925)
        XCTAssertEqual(FocusLog.addingTotal(seconds: 20, stored: 900, lines: lines), 900)
        XCTAssertEqual(FocusLog.addedMinutes(seconds: .nan), 0)
        XCTAssertEqual(FocusLog.addedMinutes(seconds: 89), 1)
    }
}
