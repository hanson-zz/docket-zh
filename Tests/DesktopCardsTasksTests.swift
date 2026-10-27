import Foundation
import XCTest

/// 桌面卡片 Tasks 组：接管哪些种类、每档几行、放不下怎么收、小号的主操作、便签字号、喝水快捷量。
final class DesktopCardsTasksTests: XCTestCase {

    func testHandlesTheEightKinds() {
        for kind in [WidgetKind.todo, .reminders, .notes, .habit, .water, .posture, .perfectDay, .pet] {
            XCTAssertTrue(DesktopCardsTasksPlan.handles(kind), "\(kind)")
        }
        XCTAssertFalse(DesktopCardsTasksPlan.handles(.clock))
        XCTAssertFalse(DesktopCardsTasksPlan.handles(.calculator))
        XCTAssertEqual(DesktopCardsTasksPlan.kinds.count, 8)
    }

    func testListRowsGrowWithTheCard() {
        for kind in [WidgetKind.todo, .reminders, .habit] {
            let small = DesktopCardsTasksPlan.listRows(kind, size: .small)
            let medium = DesktopCardsTasksPlan.listRows(kind, size: .medium)
            let large = DesktopCardsTasksPlan.listRows(kind, size: .large)
            XCTAssertEqual(small, 1)
            XCTAssertEqual(medium, 3)
            XCTAssertGreaterThan(large, medium)
        }
        XCTAssertEqual(DesktopCardsTasksPlan.listRows(.water, size: .large), 0)
    }

    func testCutKeepsALineForWhatIsLeft() {
        XCTAssertEqual(DesktopCardsTasksPlan.cut(total: 3, rows: 3), .init(shown: 3, more: 0))
        XCTAssertEqual(DesktopCardsTasksPlan.cut(total: 2, rows: 3), .init(shown: 2, more: 0))
        // 4 条放 3 行：画 2 条，第 3 行写「还有 2 项」。
        XCTAssertEqual(DesktopCardsTasksPlan.cut(total: 4, rows: 3), .init(shown: 2, more: 2))
        XCTAssertEqual(DesktopCardsTasksPlan.cut(total: 10, rows: 6), .init(shown: 5, more: 5))
        // 只有一行：画第一条。
        XCTAssertEqual(DesktopCardsTasksPlan.cut(total: 5, rows: 1), .init(shown: 1, more: 4))
        XCTAssertEqual(DesktopCardsTasksPlan.cut(total: 0, rows: 3), .init(shown: 0, more: 0))
        XCTAssertEqual(DesktopCardsTasksPlan.cut(total: -2, rows: 3), .init(shown: 0, more: 0))
        XCTAssertEqual(DesktopCardsTasksPlan.cut(total: 4, rows: 0), .init(shown: 0, more: 4))
    }

    func testNextHabitSkipsDoneAndLocked() {
        let calendar = HabitTracker.calendar
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 10))!
        let key = HabitTracker.dayKey(today, calendar: calendar)
        let done = Habit(id: "a", name: "早起", days: [key])
        let open = Habit(id: "b", name: "读书")
        XCTAssertEqual(DesktopCardsTasksPlan.nextHabit([done, open], today: today, unlocked: false,
                                                       calendar: calendar)?.id, "b")
        XCTAssertNil(DesktopCardsTasksPlan.nextHabit([done], today: today, unlocked: false, calendar: calendar))
        // 没解锁时第 4 个起锁着，前三个都完成了就没有能打卡的。
        let first = [Habit(id: "1", name: "一", days: [key]), Habit(id: "2", name: "二", days: [key]),
                     Habit(id: "3", name: "三", days: [key]), Habit(id: "4", name: "四")]
        XCTAssertNil(DesktopCardsTasksPlan.nextHabit(first, today: today, unlocked: false, calendar: calendar))
        XCTAssertEqual(DesktopCardsTasksPlan.nextHabit(first, today: today, unlocked: true,
                                                       calendar: calendar)?.id, "4")
    }

    func testPetPrimaryAction() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        // 都还好：照顾最低的那项。
        XCTAssertEqual(DesktopCardsTasksPlan.petPrimaryAction(PetState(food: 90, mood: 70, energy: 80, clean: 85, at: now)),
                       .play)
        // 低于警戒线：最低的那项。
        XCTAssertEqual(DesktopCardsTasksPlan.petPrimaryAction(PetState(food: 30, mood: 70, energy: 80, clean: 85, at: now)),
                       .feed)
        // 病了：看病。
        XCTAssertEqual(DesktopCardsTasksPlan.petPrimaryAction(PetState(food: 1, mood: 70, energy: 80, clean: 85, at: now)),
                       .heal)
    }

    func testNotePointSize() {
        XCTAssertEqual(DesktopCardsTasksPlan.notePointSize(panel: 22, size: .large), 22)
        XCTAssertEqual(DesktopCardsTasksPlan.notePointSize(panel: 22, size: .medium), 19)
        XCTAssertEqual(DesktopCardsTasksPlan.notePointSize(panel: 22, size: .small), 15)
        // 再小也不小于 13pt。
        XCTAssertEqual(DesktopCardsTasksPlan.notePointSize(panel: 13, size: .small), 13)
        XCTAssertFalse(DesktopCardsTasksPlan.noteShowsTitle(.small))
        XCTAssertTrue(DesktopCardsTasksPlan.noteShowsTitle(.medium))
        XCTAssertTrue(DesktopCardsTasksPlan.noteShowsTitle(.large))
    }

    func testWaterQuickAmounts() {
        XCTAssertEqual(DesktopCardsTasksPlan.waterQuickAmounts(cup: 250), [250, 125])
        XCTAssertEqual(DesktopCardsTasksPlan.waterQuickAmounts(cup: 236), [236, 120])
        XCTAssertEqual(DesktopCardsTasksPlan.waterQuickAmounts(cup: 300), [300, 150])
        XCTAssertEqual(DesktopCardsTasksPlan.waterQuickAmounts(cup: 10), [10])
        XCTAssertEqual(DesktopCardsTasksPlan.waterQuickAmounts(cup: 0), [10])
    }
}
