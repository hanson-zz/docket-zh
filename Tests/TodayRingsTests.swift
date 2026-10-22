import Foundation
import XCTest

final class TodayRingsTests: XCTestCase {
    private let calendar = PerfectDay.calendar

    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    private func record(_ k: String, _ marks: String) -> PerfectDayRecord {
        PerfectDayRecord(decoding: "\(k)|\(marks)")!
    }

    private func water(_ ml: Int, goal: Int = 2000, cup: Int = 250) -> PerfectDayProgress {
        PerfectDayProgress(item: .water, mark: ml >= goal ? .met : .missed,
                           fraction: WaterIntake.progress(total: ml, goal: goal), detail: "",
                           amount: ml, goal: goal, cupSize: cup)
    }

    private func focus(_ minutes: Int, goal: Int = 50) -> PerfectDayProgress {
        PerfectDay.focus(minutes: minutes, goal: goal, hasTimer: true)
    }

    private func habit(_ done: Int, of total: Int, pending: [String] = []) -> PerfectDayProgress {
        PerfectDayProgress(item: .habit, mark: done >= total ? .met : .missed,
                           fraction: Double(done) / Double(total), detail: "",
                           amount: done, goal: total, pending: pending)
    }

    private let off: [PerfectDayItem: PerfectDayProgress] = [
        .water: PerfectDayProgress(item: .water, mark: .off, fraction: 0, detail: "没有放喝水小组件"),
        .habit: PerfectDayProgress(item: .habit, mark: .off, fraction: 0, detail: "还没有设置习惯"),
        .focus: PerfectDayProgress(item: .focus, mark: .off, fraction: 0, detail: "没有放专注计时小组件"),
    ]

    // MARK: Settings

    func testStyleDefaultsToBasketAndReadsRings() {
        XCTAssertEqual(TodayRings.style(WidgetConfig()), .basket, "没存过样式的老卡片保持竹篮")
        XCTAssertEqual(TodayRings.style(WidgetCatalog.make(.perfectDay)!.config), .basket)
        XCTAssertEqual(TodayRings.style(WidgetConfig([TodayRings.styleKey: .string("rings")])), .rings)
        XCTAssertEqual(TodayRings.style(WidgetConfig([TodayRings.styleKey: .string("x")])), .basket)
        XCTAssertEqual(TodayRings.card(WidgetConfig()), .small)
        XCTAssertEqual(TodayRings.card(WidgetConfig([TodayRings.cardKey: .string("medium")])), .medium)
        XCTAssertEqual(PerfectDayStyle.allCases.map(\.title), ["竹篮", "三环"])
        XCTAssertEqual(TodayRingsCard.allCases.map(\.title), ["小", "中"])
    }

    func testOptionsShowOnlyUnderTheirStyle() {
        let basket = WidgetCatalog.make(.perfectDay)!.config
        let rings = WidgetCatalog.make(.perfectDay, overrides: [TodayRings.styleKey: .string("rings")])!.config
        XCTAssertTrue(WidgetCatalog.applies(LiquidLooks.key, to: basket, kind: .perfectDay))
        XCTAssertFalse(WidgetCatalog.applies(TodayRings.cardKey, to: basket, kind: .perfectDay))
        XCTAssertFalse(WidgetCatalog.applies(LiquidLooks.key, to: rings, kind: .perfectDay))
        XCTAssertTrue(WidgetCatalog.applies(TodayRings.cardKey, to: rings, kind: .perfectDay))
        XCTAssertTrue(WidgetCatalog.applies(TodayRings.styleKey, to: rings, kind: .perfectDay))
    }

    func testTileSizeFollowsStyleAndCard() {
        let basket = WidgetCatalog.make(.perfectDay)!
        XCTAssertEqual(WidgetCatalog.naturalSize(basket).width, 196, "竹篮的卡片不变")
        let small = WidgetCatalog.make(.perfectDay, overrides: [TodayRings.styleKey: .string("rings")])!
        let medium = WidgetCatalog.make(.perfectDay, overrides: [TodayRings.styleKey: .string("rings"),
                                                                 TodayRings.cardKey: .string("medium")])!
        XCTAssertEqual(WidgetCatalog.naturalSize(small).width, 168)
        XCTAssertEqual(WidgetCatalog.naturalSize(medium).width, 320)
    }

    // MARK: Colours

    func testOneSharedPaletteForBasketAndRings() {
        XCTAssertEqual(PerfectDayItem.water.hex, "#0FA89A", "喝水青绿")
        XCTAssertEqual(PerfectDayItem.focus.hex, "#F2603A", "专注珊瑚橙")
        XCTAssertEqual(PerfectDayItem.habit.hex, "#7FB21E", "习惯竹黄绿")
        for item in PerfectDayItem.allCases {
            let base = ColorCode(hex: item.hex)!
            let deep = ColorCode(hex: item.deepHex)!
            XCTAssertNotNil(ColorCode(hex: item.lightHex))
            // 第二圈是同色加深一档：每个通道都更暗。
            XCTAssertLessThan(deep.red, base.red + 0.0001)
            XCTAssertLessThan(deep.green, base.green)
            XCTAssertLessThan(deep.blue, base.blue + 0.0001)
        }
        XCTAssertEqual(TodayRings.order, [.water, .focus, .habit], "从外到内")
    }

    // MARK: Laps

    func testLapsWrapPastOneHundredPercent() {
        XCTAssertEqual(TodayRings.laps(0), TodayRingLaps(first: 0, second: 0))
        XCTAssertEqual(TodayRings.laps(-0.2), TodayRingLaps(first: 0, second: 0))
        XCTAssertEqual(TodayRings.laps(.nan), TodayRingLaps(first: 0, second: 0))
        XCTAssertEqual(TodayRings.laps(0.7), TodayRingLaps(first: 0.7, second: 0))
        XCTAssertEqual(TodayRings.laps(1), TodayRingLaps(first: 1, second: 0))
        XCTAssertEqual(TodayRings.laps(1.25).first, 1)
        XCTAssertEqual(TodayRings.laps(1.25).second, 0.25, accuracy: 1e-9)
        XCTAssertEqual(TodayRings.laps(3.4), TodayRingLaps(first: 1, second: 1), "第二圈最多一整圈")
    }

    func testRatioIsUncappedWhileFractionStaysCapped() {
        let w = water(2500)
        XCTAssertEqual(w.fraction, 1)
        XCTAssertEqual(w.ratio, 1.25, accuracy: 1e-9)
        let f = focus(55)
        XCTAssertEqual(f.fraction, 1)
        XCTAssertEqual(f.ratio, 1.1, accuracy: 1e-9)
        XCTAssertEqual(f.amount, 55)
        XCTAssertEqual(off[.water]!.ratio, 0, "不计入的一项没有进度")
    }

    // MARK: Cups

    func testCupsCountWholeGlassesAndGoalRounds() {
        XCTAssertEqual(TodayRings.cups(ml: 2500, cupSize: 250), 10)
        XCTAssertEqual(TodayRings.cups(ml: 490, cupSize: 250), 1, "不满一杯不算")
        XCTAssertEqual(TodayRings.cups(ml: 0, cupSize: 250), 0)
        XCTAssertEqual(TodayRings.cups(ml: 500, cupSize: 0), 0)
        XCTAssertEqual(TodayRings.goalCups(goal: 2000, cupSize: 250), 8)
        XCTAssertEqual(TodayRings.goalCups(goal: 2000, cupSize: 300), 7)
        XCTAssertEqual(TodayRings.goalCups(goal: 100, cupSize: 1000), 1, "至少一杯")
    }

    func testShownCupsAgreeWithTheGoalInMillilitres() {
        XCTAssertTrue(TodayRings.shownCups(ml: 2500, goal: 2000, cupSize: 250) == (10, 8))
        XCTAssertTrue(TodayRings.shownCups(ml: 2250, goal: 2000, cupSize: 250) == (9, 8))
        // 目标 2100、一杯 300：目标 7 杯；喝到 2100 毫升达标，杯数要写到 7。
        XCTAssertTrue(TodayRings.shownCups(ml: 2100, goal: 2100, cupSize: 300) == (7, 7))
        // 目标 2000、一杯 300：目标 7 杯；1950 毫升按杯是 6，没达标不能写成 7/7。
        XCTAssertTrue(TodayRings.shownCups(ml: 1950, goal: 2000, cupSize: 300) == (6, 7))
        XCTAssertTrue(TodayRings.shownCups(ml: 1999, goal: 1800, cupSize: 600) == (3, 3))
        XCTAssertTrue(TodayRings.shownCups(ml: 1790, goal: 1800, cupSize: 200) == (8, 9))
    }

    // MARK: Percent and full

    func testPercentCapsEachItemThenAverages() {
        let items = [water(2500), habit(2, of: 3), focus(35)]
        XCTAssertEqual(TodayRings.percent(items), 79, "设计稿：125%→100、70%、67% 平均 79%")
        XCTAssertEqual(TodayRings.percent(water(2500)), 125)
        XCTAssertEqual(TodayRings.percent(focus(35)), 70)
        XCTAssertEqual(TodayRings.percent([water(1000), off[.habit]!, off[.focus]!]), 50, "只算参加的项")
        XCTAssertEqual(TodayRings.percent([off[.water]!, off[.habit]!, off[.focus]!]), 0)
    }

    func testFullAndRingsLeft() {
        let full = [water(2250), habit(3, of: 3), focus(55)]
        XCTAssertTrue(TodayRings.isFull(full))
        XCTAssertEqual(TodayRings.cardCaption(full), "全满")
        XCTAssertEqual(TodayRings.status(full), "全部达标")
        let going = [water(2500), habit(2, of: 3), focus(35)]
        XCTAssertFalse(TodayRings.isFull(going))
        XCTAssertEqual(TodayRings.ringsLeft(going), 2)
        XCTAssertEqual(TodayRings.cardCaption(going), "还差 2 环")
        XCTAssertEqual(TodayRings.status(going), "1 / 3 达标")
        let none = [off[.water]!, off[.habit]!, off[.focus]!]
        XCTAssertFalse(TodayRings.isFull(none), "一项都不参加不算全满")
        XCTAssertEqual(TodayRings.cardCaption(none), "还没有可计的环")
    }

    // MARK: Words

    func testRemainingLineListsWhatIsMissingOuterToInner() {
        let items = [water(2500), habit(2, of: 3, pending: ["读书"]), focus(35)]
        XCTAssertEqual(TodayRings.remainingLine(items), "还差专注 15 分钟、习惯 1 项")
        let thirsty = [water(1500), habit(3, of: 3), focus(50)]
        XCTAssertEqual(TodayRings.remainingLine(thirsty), "还差喝水 2 杯")
        XCTAssertEqual(TodayRings.remainingLine([off[.water]!, off[.habit]!, off[.focus]!]),
                       "放上喝水、专注计时或习惯打卡小组件就能开始")
    }

    func testCelebrationUsesTheBasketLeafAndNeverBamboo() {
        XCTAssertNil(TodayRings.celebration([water(2500), habit(2, of: 3), focus(35)]))
        XCTAssertEqual(TodayRings.celebration([water(2250), habit(3, of: 3), focus(55)]),
                       "今天三环全满 · 得到一片金竹叶")
        XCTAssertEqual(TodayRings.celebration([water(2000), off[.habit]!, focus(50)]),
                       "今天两环全满 · 得到一片金竹叶", "两项都达标按竹篮规则也是金竹叶")
        XCTAssertEqual(TodayRings.celebration([water(2000), off[.habit]!, off[.focus]!]),
                       "今天一环全满 · 得到一片铜竹叶", "只开一项只能得铜竹叶")
        let all = [TodayRings.celebration([water(2250), habit(3, of: 3), focus(55)]) ?? "",
                   TodayRings.remainingLine([water(2500), habit(2, of: 3), focus(35)])]
        for text in all {
            XCTAssertFalse(text.contains("竹子"), text)
            XCTAssertFalse(text.contains("\u{2014}"), text)
        }
    }

    func testFiguresAndNotes() {
        XCTAssertTrue(TodayRings.figure(water(2500)) == ("10", "/ 8 杯"))
        XCTAssertTrue(TodayRings.figure(focus(35)) == ("35", "/ 50 分钟"))
        XCTAssertTrue(TodayRings.figure(habit(2, of: 3)) == ("2", "/ 3 项"))
        XCTAssertTrue(TodayRings.figure(off[.water]!) == ("", "未计入"))
        XCTAssertEqual(TodayRings.note(water(2500)), "2500 / 2000 毫升")
        XCTAssertEqual(TodayRings.note(focus(35)), "还差 15 分钟")
        XCTAssertEqual(TodayRings.note(focus(55)), "超出 5 分钟")
        XCTAssertEqual(TodayRings.note(focus(50)), "刚好达标")
        XCTAssertEqual(TodayRings.note(habit(2, of: 3, pending: ["读书"])), "还差「读书」")
        XCTAssertEqual(TodayRings.note(habit(1, of: 3, pending: ["读书", "跑步"])), "还差「读书」等 2 项")
        XCTAssertEqual(TodayRings.note(habit(3, of: 3)), "全部打卡")
        XCTAssertEqual(TodayRings.note(off[.habit]!), "还没有设置习惯")
    }

    // MARK: Sources carry the raw numbers

    func testSourcesFillAmountGoalAndPending() {
        let today = day(2026, 10, 22, hour: 15)
        let key = HabitTracker.dayKey(today, calendar: calendar)
        var config = WidgetConfig()
        HabitTracker.store([Habit(id: "a", name: "读书"), Habit(id: "b", name: "跑步", days: [key])],
                           in: &config, now: today)
        let p = PerfectDay.habits([config], on: today, calendar: calendar)
        XCTAssertEqual(p.amount, 1)
        XCTAssertEqual(p.goal, 2)
        XCTAssertEqual(p.pending, ["读书"])
        let w = PerfectDay.water([WidgetConfig(["cupSize": .number(300)])], on: today, today: today, calendar: calendar)
        XCTAssertEqual(w.cupSize, 300)
        XCTAssertGreaterThan(w.goal, 0)
    }

    // MARK: Streak and week

    func testFullStreakCountsDaysWithEveryRingMet() {
        let today = day(2026, 10, 22)
        let records = [record("20261018", "111"), record("20261019", "110"),
                       record("20261020", "1-1"), record("20261021", "111"), record("20261022", "100")]
        XCTAssertEqual(TodayRings.fullStreak(records, today: today, calendar: calendar), 2,
                       "今天还没满，接着算到昨天：21、20（只开两项都满也算）")
        let done = records.dropLast() + [record("20261022", "111")]
        XCTAssertEqual(TodayRings.fullStreak(Array(done), today: today, calendar: calendar), 3)
        XCTAssertEqual(TodayRings.fullStreak([], today: today, calendar: calendar), 0)
        XCTAssertEqual(TodayRings.fullStreak([record("20261020", "111")], today: today, calendar: calendar), 0,
                       "昨天没满就断了")
        XCTAssertFalse(TodayRings.isFull(record("20261020", "---")))
    }

    func testWeekEndsTodayWithTheBasketLeaf() {
        let today = day(2026, 10, 22) // 周四
        let records = [record("20261017", "111"), record("20261020", "1-1"), record("20261021", "1--"),
                       record("20261022", "110")]
        let week = TodayRings.week(records, today: today, calendar: calendar)
        XCTAssertEqual(week.map(\.key), ["20261016", "20261017", "20261018", "20261019", "20261020",
                                         "20261021", "20261022"])
        XCTAssertEqual(week.map(\.label), ["五", "六", "日", "一", "二", "三", "今天"])
        XCTAssertEqual(week.map(\.isToday), [false, false, false, false, false, false, true])
        XCTAssertEqual(week[1].leaf, .gold)
        XCTAssertEqual(week[4].leaf, .gold, "两项都满是金竹叶")
        XCTAssertEqual(week[5].leaf, .bronze, "只开一项满了是铜竹叶")
        XCTAssertNil(week[6].leaf, "没全满不点亮")
        XCTAssertNil(week[0].record)
    }

    func testSampleShowsTheSecondLap() {
        XCTAssertEqual(TodayRings.percent(TodayRings.sample), 79)
        XCTAssertGreaterThan(TodayRings.sample.first { $0.item == .water }!.ratio, 1)
    }

    func testWaterNoteFollowsTheWaterUnit() {
        var p = water(2500)
        p.ounces = true
        XCTAssertEqual(TodayRings.note(p), WaterIntake.tally(total: 2500, goal: 2000, ounces: true))
        XCTAssertTrue(TodayRings.note(p).hasSuffix(WaterIntake.unitLabel(ounces: true)))
    }

    func testWeekCellFollowsTheSettledRecord() {
        // 记录：喝水没达标、习惯不参加、专注达标；读数却是喝水已满、专注没满。
        let settled = record("20261020", "0-1")
        let readings = [water(2400), habit(1, of: 3), focus(20)]
        let rings = TodayRings.weekRings(readings, record: settled)
        let w = rings.first { $0.item == .water }!
        let h = rings.first { $0.item == .habit }!
        let f = rings.first { $0.item == .focus }!
        XCTAssertEqual(w.mark, .missed)
        XCTAssertLessThan(w.ratio, 1)
        XCTAssertEqual(h.mark, .off)
        XCTAssertEqual(f.mark, .met)
        XCTAssertGreaterThanOrEqual(f.ratio, 1)
        // 和记录一致的读数原样保留。
        let same = TodayRings.weekRings([water(1200), focus(60)], record: record("20261020", "0-1"))
        XCTAssertEqual(same.first { $0.item == .water }?.amount, 1200)
        XCTAssertEqual(same.first { $0.item == .focus }?.amount, 60)
        // 没有读数也按记录画：达标满圈。
        let bare = TodayRings.weekRings(nil, record: record("20261020", "1-0"))
        XCTAssertEqual(bare.first { $0.item == .water }?.ratio, 1)
        XCTAssertLessThan(bare.first { $0.item == .focus }?.ratio ?? 1, 1)
        // 没有记录的日子照读数画。
        XCTAssertEqual(TodayRings.weekRings(readings, record: nil), readings)
    }
}
