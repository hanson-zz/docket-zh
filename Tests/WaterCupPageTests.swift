import Foundation
import XCTest

/// 喝水面板「今天」页：三只杯量按钮跟着一杯容量走、还差几杯、角色什么时候
/// 是骷髅、静止水面的相位、时间轴的范围和刻度、记录收起展开。
final class WaterCupPageTests: XCTestCase {

    // MARK: 杯量按钮

    func testDefaultCupGivesHundredCupAndFiveHundred() {
        let buttons = WaterCupPage.cupButtons(cup: 250)
        XCTAssertEqual(buttons.map(\.amount), [100, 250, 500])
        XCTAssertEqual(buttons.map(\.size), [.small, .cup, .large])
    }

    func testMiddleButtonFollowsTheCupSize() {
        XCTAssertEqual(WaterCupPage.cupButtons(cup: 300).map(\.amount), [100, 300, 500])
        XCTAssertEqual(WaterCupPage.cupButtons(cup: 400).map(\.amount), [100, 400, 500])
    }

    func testSmallAndLargeMoveAsideSoAmountsStayDistinct() {
        for cup in [50, 80, 100, 150, 250, 450, 500, 750, 1000] {
            let amounts = WaterCupPage.cupButtons(cup: cup).map(\.amount)
            XCTAssertEqual(amounts[1], cup)
            XCTAssertLessThan(amounts[0], amounts[1], "一杯 \(cup)：小杯要更小")
            XCTAssertLessThan(amounts[1], amounts[2], "一杯 \(cup)：大杯要更大")
        }
        XCTAssertEqual(WaterCupPage.cupButtons(cup: 100).map(\.amount), [50, 100, 500])
        XCTAssertEqual(WaterCupPage.cupButtons(cup: 500).map(\.amount), [100, 500, 1000])
    }

    func testCupOutsideTheRangeIsClamped() {
        XCTAssertEqual(WaterCupPage.cupButtons(cup: 5).map(\.amount)[1], WaterIntake.cupRange.lowerBound)
        XCTAssertEqual(WaterCupPage.cupButtons(cup: 9000).map(\.amount)[1], WaterIntake.cupRange.upperBound)
    }

    // MARK: 还差几杯

    func testCupsLeftRoundsUp() {
        XCTAssertEqual(WaterCupPage.cupsLeft(total: 1250, goal: 2000, cup: 250), 3)
        XCTAssertEqual(WaterCupPage.cupsLeft(total: 1300, goal: 2000, cup: 250), 3, "700 是 2.8 杯，算 3 杯")
        XCTAssertEqual(WaterCupPage.cupsLeft(total: 2000, goal: 2000, cup: 250), 0)
        XCTAssertEqual(WaterCupPage.cupsLeft(total: 2600, goal: 2000, cup: 250), 0)
        XCTAssertEqual(WaterCupPage.cupsLeft(total: 0, goal: 2000, cup: 0), 0)
        XCTAssertEqual(WaterCupPage.cupsToGoal(goal: 2000, cup: 250), 8)
        XCTAssertEqual(WaterCupPage.cupsToGoal(goal: 2100, cup: 250), 9)
        XCTAssertEqual(WaterCupPage.cupsToGoal(goal: 0, cup: 250), 0)
    }

    // MARK: 角色

    func testSkeletonWaitsForTheDrinkMoment() {
        XCTAssertTrue(WaterCupPage.showsSkeleton(parched: true, mood: .idle))
        XCTAssertTrue(WaterCupPage.showsSkeleton(parched: true, mood: .rest))
        XCTAssertFalse(WaterCupPage.showsSkeleton(parched: true, mood: .drink), "刚喝下先举杯子")
        XCTAssertFalse(WaterCupPage.showsSkeleton(parched: false, mood: .idle))
    }

    func testRestingPhaseMovesOnlyWithTheLevel() {
        XCTAssertEqual(WaterCupPage.restingPhase(level: 0.5), WaterCupPage.restingPhase(level: 0.5))
        XCTAssertLessThan(WaterCupPage.restingPhase(level: 0.5), WaterCupPage.restingPhase(level: 0.625))
        XCTAssertEqual(WaterCupPage.restingPhase(level: 2), WaterCupPage.restingPhase(level: 1), "满了就停")
        XCTAssertEqual(WaterCupPage.restingPhase(level: -1), WaterCupPage.restingPhase(level: 0))
    }

    // MARK: 时间轴

    private let hours = WaterReminder(every: 60, start: 9 * 60, end: 21 * 60)

    func testAxisIsTheReminderHoursByDefault() {
        let axis = WaterCupPage.axis(window: hours, entries: [11 * 60 + 30, 14 * 60 + 20], now: 15 * 60, next: 15 * 60 + 20)
        XCTAssertEqual(axis.start, 9 * 60)
        XCTAssertEqual(axis.end, 21 * 60)
        XCTAssertEqual(axis.ticks.map(WaterCupPage.tickLabel), ["09", "11", "13", "15", "17", "19", "21"])
        XCTAssertEqual(axis.fraction(15 * 60), 0.5, accuracy: 0.0001)
    }

    func testAxisStretchesToDrinksOutsideTheHours() {
        let axis = WaterCupPage.axis(window: hours, entries: [7 * 60 + 40], now: 22 * 60 + 10, next: nil)
        XCTAssertEqual(axis.start, 7 * 60)
        XCTAssertEqual(axis.end, 23 * 60)
        XCTAssertEqual(axis.fraction(0), 0, "超出范围夹到两头")
        XCTAssertEqual(axis.fraction(1440), 1)
    }

    func testWholeDayWindowAndMinimumSpan() {
        let whole = WaterCupPage.axis(window: WaterReminder(every: 60, start: 0, end: 0), entries: [], now: 600, next: nil)
        XCTAssertEqual(whole.start, 0)
        XCTAssertEqual(whole.end, 1440)
        XCTAssertEqual(whole.ticks.count, 7, "24 小时每 4 小时一格")

        let short = WaterCupPage.axis(window: WaterReminder(every: 60, start: 20 * 60, end: 22 * 60),
                                      entries: [], now: nil, next: nil)
        XCTAssertEqual(short.end - short.start, WaterCupPage.minimumSpan)
        XCTAssertLessThanOrEqual(short.end, 1440)
    }

    // MARK: 记录

    func testRowsCollapseToThree() {
        XCTAssertEqual(WaterCupPage.shownRows(count: 5, expanded: false), 3)
        XCTAssertEqual(WaterCupPage.shownRows(count: 5, expanded: true), 5)
        XCTAssertEqual(WaterCupPage.shownRows(count: 2, expanded: false), 2)
        XCTAssertFalse(WaterCupPage.canExpand(count: 3))
        XCTAssertTrue(WaterCupPage.canExpand(count: 4))
    }
}
