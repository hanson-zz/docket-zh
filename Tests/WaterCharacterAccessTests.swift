import Foundation
import XCTest

/// 喝水角色的混合解锁：小熊猫免费，柴犬累计达标 3 天、橘猫累计达标 7 天解锁
/// 并永久保留，企鹅、水獭、章鱼是 Pro。电子宠物整种是 Pro，角色照旧。
final class WaterCharacterAccessTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private func at(_ day: Int, _ hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private func key(_ day: Int) -> String { HabitTracker.dayKey(at(day), calendar: calendar) }

    /// A 喝水 config with a hand-set 2000 ml goal and the given days met
    /// (2100 ml) or missed (900 ml).
    private func config(met: [Int], missed: [Int] = [], character: WaterCharacter = .redPanda) -> WidgetConfig {
        var config = WidgetConfig(["character": .string(character.rawValue)])
        WaterGoal.settingManual(2000, in: &config)
        let days = met.map { WaterDay(key: key($0), goal: 2000, summary: 2100) }
            + missed.map { WaterDay(key: key($0), goal: 2000, summary: 900) }
        config.set(WaterIntake.key, .list(days.sorted { $0.key < $1.key }.map { .string($0.encoded) }))
        return config
    }

    func testWhoIsFreeWhoIsEarnedWhoIsPro() {
        XCTAssertNil(WaterCharacter.redPanda.daysToEarn)
        XCTAssertEqual(WaterCharacter.shiba.daysToEarn, 3)
        XCTAssertEqual(WaterCharacter.cat.daysToEarn, 7)
        for character in [WaterCharacter.penguin, .otter, .octopus] {
            XCTAssertNil(character.daysToEarn)
            XCTAssertTrue(character.isSupporterOnly)
        }
        for character in [WaterCharacter.redPanda, .shiba, .cat] {
            XCTAssertFalse(character.isSupporterOnly)
        }
    }

    func testAccessFromCounts() {
        XCTAssertEqual(WaterCharacter.redPanda.access(metDays: 0, earned: [], pro: false), .free)
        XCTAssertEqual(WaterCharacter.shiba.access(metDays: 0, earned: [], pro: false), .locked(daysLeft: 3))
        XCTAssertEqual(WaterCharacter.shiba.access(metDays: 2, earned: [], pro: false), .locked(daysLeft: 1))
        XCTAssertEqual(WaterCharacter.shiba.access(metDays: 3, earned: [], pro: false), .earned)
        XCTAssertEqual(WaterCharacter.cat.access(metDays: 3, earned: [], pro: false), .locked(daysLeft: 4))
        XCTAssertEqual(WaterCharacter.cat.access(metDays: 7, earned: [], pro: false), .earned)
        // Kept once earned, whatever the log says now.
        XCTAssertEqual(WaterCharacter.cat.access(metDays: 0, earned: [.cat], pro: false), .earned)
        // Pro opens the ones still to be earned too.
        XCTAssertEqual(WaterCharacter.shiba.access(metDays: 0, earned: [], pro: true), .pro(unlocked: true))
        XCTAssertEqual(WaterCharacter.otter.access(metDays: 99, earned: [], pro: false), .pro(unlocked: false))
        XCTAssertEqual(WaterCharacter.otter.access(metDays: 0, earned: [], pro: true), .pro(unlocked: true))

        XCTAssertTrue(WaterCharacterAccess.free.isAvailable)
        XCTAssertTrue(WaterCharacterAccess.earned.isAvailable)
        XCTAssertFalse(WaterCharacterAccess.locked(daysLeft: 2).isAvailable)
        XCTAssertFalse(WaterCharacterAccess.pro(unlocked: false).isAvailable)
        XCTAssertTrue(WaterCharacterAccess.pro(unlocked: true).isAvailable)
        XCTAssertEqual(WaterCharacterAccess.locked(daysLeft: 2).daysLeft, 2)
        XCTAssertNil(WaterCharacterAccess.earned.daysLeft)
    }

    /// 累计，不要求连续；没达标的天不算。
    func testMetDaysAreCountedInTotalNotInARow() {
        let c = config(met: [1, 3, 9], missed: [2, 4, 5])
        XCTAssertEqual(WaterCharacter.metDays(c, now: at(19), calendar: calendar), 3)
        XCTAssertEqual(WaterCharacter.access(.shiba, config: c, pro: false, now: at(19), calendar: calendar), .earned)
        XCTAssertEqual(WaterCharacter.access(.cat, config: c, pro: false, now: at(19), calendar: calendar),
                       .locked(daysLeft: 4))
    }

    /// 今天按当前目标算，和连续天数一样。
    func testTodayCountsOnceItIsMet() {
        var c = config(met: [1, 2])
        XCTAssertEqual(WaterCharacter.metDays(c, now: at(19), calendar: calendar), 2)
        let days = WaterIntake.logging(.water, amount: 2000, in: WaterIntake.days(c), goal: 2000,
                                       now: at(19, 15), calendar: calendar)
        WaterIntake.store(days, in: &c, now: at(19, 15), calendar: calendar)
        XCTAssertEqual(WaterCharacter.metDays(c, now: at(19, 16), calendar: calendar), 3)
    }

    func testEarnedCharactersAreWrittenDownAndNeverTakenBack() {
        var c = config(met: [1, 2, 3])
        let fresh = WaterCharacter.recordingEarned(in: &c, now: at(19), calendar: calendar)
        XCTAssertEqual(fresh, [.shiba])
        XCTAssertEqual(WaterCharacter.earned(c), [.shiba])
        XCTAssertEqual(c.strings(WaterCharacter.earnedKey), ["shiba"])
        // Again: nothing new.
        XCTAssertEqual(WaterCharacter.recordingEarned(in: &c, now: at(19), calendar: calendar), [])

        // The log is cleared (or trimmed after 120 days): the shiba stays.
        c.set(WaterIntake.key, nil)
        XCTAssertEqual(WaterCharacter.metDays(c, now: at(19), calendar: calendar), 0)
        XCTAssertEqual(WaterCharacter.recordingEarned(in: &c, now: at(19), calendar: calendar), [])
        XCTAssertEqual(WaterCharacter.access(.shiba, config: c, pro: false, now: at(19), calendar: calendar), .earned)
        XCTAssertEqual(WaterCharacter.access(.cat, config: c, pro: false, now: at(19), calendar: calendar),
                       .locked(daysLeft: 7))
    }

    func testBothCanBeEarnedAtOnce() {
        var c = config(met: Array(1...7))
        XCTAssertEqual(WaterCharacter.recordingEarned(in: &c, now: at(19), calendar: calendar), [.shiba, .cat])
        XCTAssertEqual(WaterCharacter.earned(c), [.shiba, .cat])
    }

    /// Pro 角色和写错的名字不会被“挣”进清单。
    func testOnlyEarnableCharactersAreReadFromTheList() {
        let c = WidgetConfig([WaterCharacter.earnedKey: .list([.string("otter"), .string("llama"), .string("cat")])])
        XCTAssertEqual(WaterCharacter.earned(c), [.cat])
        XCTAssertEqual(WaterCharacter.access(.otter, config: c, pro: false, now: at(19), calendar: calendar),
                       .pro(unlocked: false))
    }

    func testShownFallsBackToTheRedPandaUntilAvailable() {
        let early = config(met: [1], character: .shiba)
        XCTAssertEqual(WaterCharacter.shown(early, unlocked: false, now: at(19), calendar: calendar), .redPanda)
        XCTAssertEqual(WaterCharacter.shown(early, unlocked: true, now: at(19), calendar: calendar), .shiba)
        let earned = config(met: [1, 2, 3], character: .shiba)
        XCTAssertEqual(WaterCharacter.shown(earned, unlocked: false, now: at(19), calendar: calendar), .shiba)
        let otter = config(met: Array(1...10), character: .otter)
        XCTAssertEqual(WaterCharacter.shown(otter, unlocked: false, now: at(19), calendar: calendar), .redPanda)
        XCTAssertEqual(WaterCharacter.shown(otter, unlocked: true, now: at(19), calendar: calendar), .otter)
        // The choice itself is kept, so it comes back once available.
        XCTAssertEqual(WaterCharacter.from(early), .shiba)
    }

    /// 电子宠物整种是 Pro，角色照旧：喝水挣到的柴犬不算数。
    func testThePetKeepsTheOldRule() {
        var pet = WidgetConfig(["character": .string("shiba")])
        pet.set(WaterCharacter.earnedKey, .list([.string("shiba")]))
        XCTAssertEqual(WaterCharacter.petShown(pet, unlocked: false), .redPanda)
        XCTAssertEqual(WaterCharacter.petShown(pet, unlocked: true), .shiba)
        XCTAssertEqual(WaterCharacter.petShown(WidgetConfig(), unlocked: false), .redPanda)
    }

    func testProStylesAreOnlyTheThreeProCharacters() {
        for character in [WaterCharacter.penguin, .otter, .octopus] {
            XCTAssertTrue(ProFeatures.isSupporterStyle(["character": .string(character.rawValue)]))
        }
        for character in [WaterCharacter.redPanda, .shiba, .cat] {
            XCTAssertFalse(ProFeatures.isSupporterStyle(["character": .string(character.rawValue)]))
        }
    }

    func testHints() {
        XCTAssertEqual(WaterCharacter.unlockHint(daysLeft: 3), "再达标 3 天解锁")
        XCTAssertEqual(WaterCharacter.unlockHint(daysLeft: 0), "再达标 1 天解锁")
        XCTAssertEqual(WaterCharacter.cat.earnedLine, "橘猫解锁啦")
    }

    // MARK: 刚解锁的提示

    func testBothCharactersEarnedTogetherAreBothNoticed() {
        let text = WaterCharacter.addingNotices([.shiba, .cat], to: "")
        XCTAssertEqual(text, "shiba,cat")
        XCTAssertEqual(WaterCharacter.notices(text ?? ""), [.shiba, .cat])
        XCTAssertEqual(WaterCharacter.removingNotice(.shiba, from: text ?? ""), "cat")
        XCTAssertNil(WaterCharacter.removingNotice(.cat, from: "cat"))
    }

    func testOldSingleNoticeStillReads() {
        XCTAssertEqual(WaterCharacter.notices("cat"), [.cat])
        XCTAssertEqual(WaterCharacter.addingNotices([.cat], to: "shiba,cat"), "shiba,cat")
        XCTAssertEqual(WaterCharacter.notices("bogus,,shiba"), [.shiba])
        XCTAssertNil(WaterCharacter.addingNotices([], to: ""))
    }
}
