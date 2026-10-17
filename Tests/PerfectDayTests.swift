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
        XCTAssertEqual(PerfectDayTier.gold.title, "满篮一天")
        XCTAssertEqual(PerfectDayTier.silver.title, "丰收一天")
        XCTAssertEqual(PerfectDayTier.bronze.title, "小有收获")
        XCTAssertEqual(PerfectDayTier.allCases.map(\.leafName), ["铜竹叶", "银竹叶", "金竹叶"])
        XCTAssertTrue(PerfectDayTier.gold > .silver && PerfectDayTier.silver > .bronze)
        XCTAssertEqual(PerfectDay.headline(nil), "还没有竹叶")
        XCTAssertEqual(PerfectDay.headline(.gold), "满篮一天")
        XCTAssertEqual(PerfectDay.subline(.silver), "小熊猫收到一片银竹叶")
    }

    func testRulesNameEveryTierAndTheGoal() {
        let rules = PerfectDay.rules(focusGoal: 45)
        XCTAssertTrue(rules.contains("45 分钟"))
        for tier in PerfectDayTier.allCases {
            XCTAssertTrue(rules.contains(tier.title), tier.title)
            XCTAssertTrue(rules.contains(tier.leafName), tier.leafName)
        }
        XCTAssertTrue(rules.contains("竹篮"))
    }

    /// 用户看得到的文案里不再出现最初借鉴时的叫法。
    func testUserFacingWordsAreBambooThemed() {
        var texts = PerfectDayTier.allCases.flatMap { [$0.title, $0.leafName] }
        texts += PerfectBadge.allCases.flatMap { [$0.title, $0.condition] }
        texts += [PerfectDay.headline(nil), PerfectDay.subline(nil), PerfectDay.rules(focusGoal: 50)]
        texts += WidgetSearch.keywords["perfect-day"] ?? []
        texts.append(WidgetCatalog.entry(.perfectDay)?.name ?? "")
        // 写成转义，这样在仓库里搜索这些词时只会搜到真正的问题。
        let banned = ["\u{5B8C}\u{7F8E}", "\u{7F8E}\u{597D}\u{4E00}\u{5929}", "\u{5948}\u{65AF}", "\u{592A}\u{9633}", "\u{73BB}\u{7483}\u{7F50}", "\u{7F50}\u{5B50}", "\u{6D1E}\u{6089}", "sun", "perfect"]
        for text in texts {
            for word in banned {
                XCTAssertFalse(text.lowercased().contains(word), "\(text) contains \(word)")
            }
        }
    }

    func testBadgeIdsStayCompatibleWithSavedArchives() {
        XCTAssertEqual(Array(PerfectBadge.allCases.prefix(10)).map(\.rawValue),
                       ["firstPerfect", "sunStreak3", "sunStreak7", "sunStreak30", "perfectMonth10", "suns50",
                        "water7", "habit7", "focus10h", "focus100h"])
        XCTAssertEqual(Set(PerfectBadge.allCases.map(\.title)).count, PerfectBadge.allCases.count, "names are distinct")
        XCTAssertEqual(Array(PerfectBadge.allCases.prefix(10)).map(\.title),
                       ["第一只满篮", "三日靠岸", "七日航程", "码头常客", "金叶之月", "竹林小仓",
                        "潮水七日", "七日打卡", "静心 10 小时", "静心 100 小时"])
    }

    func testAnArchiveWrittenBeforeTheRenameStillReads() throws {
        let json = #"{"days":["20261014|111","20261015|1-0"],"earned":{"firstPerfect":"20261014","sunStreak3":"20261015"}}"#
        let archive = try JSONDecoder().decode(PerfectDayArchive.self, from: Data(json.utf8))
        XCTAssertEqual(archive.records.map(\.tier), [.gold, .bronze])
        let statuses = PerfectBadges.statuses(records: archive.records, focusMinutes: 0, earned: archive.earned,
                                              calendar: calendar)
        XCTAssertTrue(statuses.first { $0.badge == .firstFullBasket }!.unlocked)
        XCTAssertTrue(statuses.first { $0.badge == .leafStreak3 }!.unlocked)
        XCTAssertEqual(statuses.first { $0.badge == .leafStreak3 }?.earnedOn, "20261015")
        XCTAssertEqual(WidgetKind.perfectDay.rawValue, "perfect-day", "placed widgets keep their kind")
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

    func testMonthCountsLeavesAndCells() {
        let today = day(2026, 10, 15)
        let records = [record("20260930", "111"), record("20261001", "111"), record("20261002", "110"),
                       record("20261003", "100"), record("20261004", "000"), record("20261005", "111")]
        let counts = PerfectDay.counts(records, month: today, calendar: calendar)
        XCTAssertEqual(counts[.gold], 2)
        XCTAssertEqual(counts[.silver], 1)
        XCTAssertEqual(counts[.bronze], 1)
        XCTAssertEqual(PerfectDay.leaves(records, month: today, calendar: calendar), [.gold, .silver, .bronze, .gold])

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
                       "today without a leaf yet keeps yesterday's run")
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
        XCTAssertFalse(status(.firstFullBasket).unlocked)
        XCTAssertTrue(status(.leafStreak3).unlocked)
        XCTAssertTrue(status(.leafStreak7).unlocked)
        XCTAssertFalse(status(.leafStreak30).unlocked)
        XCTAssertEqual(status(.leafStreak30).progressText, "7/30")
        XCTAssertTrue(status(.water7).unlocked)
        XCTAssertTrue(status(.habit7).unlocked)
        XCTAssertEqual(PerfectBadge.allCases.count, statuses.count)
    }

    func testGoldMonthAndCollectorAndFocus() {
        let records = run(from: day(2026, 9, 25), days: 15, marks: "111")
        XCTAssertEqual(PerfectBadges.measure(.goldMonth10, records: records, focusMinutes: 0, calendar: calendar), 9,
                       "best single month, not a run across two")
        XCTAssertEqual(PerfectBadges.measure(.leaves50, records: records, focusMinutes: 0, calendar: calendar), 15)
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
        XCTAssertTrue(statuses.first { $0.badge == .firstFullBasket }!.unlocked)
    }

    func testCatalogAndSearch() {
        let entry = WidgetCatalog.entry(.perfectDay)
        XCTAssertEqual(entry?.name, "小熊猫的竹篮")
        XCTAssertEqual(WidgetCatalog.configurableKeys(.perfectDay), [LiquidLooks.key], "只有外观；专注目标在专注计时的面板里")
        for query in ["竹篮", "竹叶", "小熊猫", "zl", "zhulan", "满篮", "打卡汇总", "徽章", "bamboo"] {
            XCTAssertTrue(WidgetSearch.matches(query, names: ["小熊猫的竹篮"], kind: "perfect-day"), query)
        }
        XCTAssertFalse(WidgetSearch.matches("太阳", names: ["小熊猫的竹篮"], kind: "perfect-day"))
        XCTAssertEqual(WidgetCatalog.accentHex(.perfectDay), PerfectDay.bambooHex)
    }

    // MARK: Badge categories

    func testTheFirstTenBadgesAreBasicAndGroupsComeInOrder() {
        let basic = PerfectBadge.allCases.prefix(10)
        XCTAssertTrue(basic.allSatisfy { $0.category == .basic })
        XCTAssertTrue(basic.allSatisfy { $0.hint == nil && $0.festivalWindow == nil })
        XCTAssertEqual(PerfectBadgeCategory.allCases.map(\.title), ["初级", "隐藏", "节日限定"])
        XCTAssertEqual(PerfectBadgeCategory.allCases.map(\.rawValue), ["basic", "hidden", "festival"])
        let statuses = PerfectBadges.statuses(records: [], focusMinutes: 0, earned: [:], calendar: calendar)
        let groups = PerfectBadges.grouped(statuses)
        XCTAssertEqual(groups.map(\.category), [.basic, .hidden, .festival])
        XCTAssertEqual(groups.map(\.statuses.count), [10, 8, 12])
        let locked = statuses.first { $0.badge == .leafStreak7 }!
        XCTAssertFalse(locked.isConcealed)
        XCTAssertEqual(locked.shownTitle, "七日航程")
        XCTAssertEqual(locked.shownCondition, "连续 7 天收到竹叶")
    }

    func testOnlyALockedHiddenBadgeIsConcealed() {
        XCTAssertTrue(PerfectBadges.isConcealed(category: .hidden, unlocked: false))
        XCTAssertFalse(PerfectBadges.isConcealed(category: .hidden, unlocked: true))
        XCTAssertFalse(PerfectBadges.isConcealed(category: .basic, unlocked: false))
        XCTAssertFalse(PerfectBadges.isConcealed(category: .festival, unlocked: false))
        XCTAssertEqual(PerfectBadges.concealedTitle, "？？？")
    }

    func testGregorianWindowIncludingAcrossTheYearEnd() {
        let christmas = FestivalWindow(.gregorian, from: .init(12, 24), to: .init(12, 26))
        XCTAssertTrue(christmas.contains(day(2026, 12, 24), base: calendar))
        XCTAssertTrue(christmas.contains(day(2026, 12, 26, hour: 23), base: calendar))
        XCTAssertFalse(christmas.contains(day(2026, 12, 27), base: calendar))
        let newYear = FestivalWindow(.gregorian, from: .init(12, 31), to: .init(1, 2))
        XCTAssertTrue(newYear.contains(day(2026, 12, 31), base: calendar))
        XCTAssertTrue(newYear.contains(day(2027, 1, 2), base: calendar))
        XCTAssertFalse(newYear.contains(day(2027, 1, 3), base: calendar))
        XCTAssertEqual(christmas.text, "公历12月24日至12月26日")
    }

    func testLunarWindowUsesTheChineseCalendar() {
        // 2026 年春节是 2 月 17 日（农历正月初一），元宵节是 3 月 3 日。
        let springFestival = FestivalWindow(.chinese, from: .init(1, 1), to: .init(1, 15))
        XCTAssertFalse(springFestival.contains(day(2026, 2, 16), base: calendar), "除夕 is still 腊月")
        XCTAssertTrue(springFestival.contains(day(2026, 2, 17), base: calendar))
        XCTAssertTrue(springFestival.contains(day(2026, 3, 3), base: calendar))
        XCTAssertFalse(springFestival.contains(day(2026, 3, 4), base: calendar))
        XCTAssertEqual(springFestival.text, "农历正月初一至正月十五")
        // 跨年的农历窗口：腊月廿三（小年）到正月十五。
        let lunarNewYear = FestivalWindow(.chinese, from: .init(12, 23), to: .init(1, 15))
        XCTAssertTrue(lunarNewYear.contains(day(2026, 2, 16), base: calendar))
        XCTAssertEqual(lunarNewYear.text, "农历腊月廿三至正月十五")
        XCTAssertEqual(FestivalWindow.lunarDay(10), "初十")
        XCTAssertEqual(FestivalWindow.lunarDay(21), "廿一")
        XCTAssertEqual(FestivalWindow.lunarDay(30), "三十")
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
