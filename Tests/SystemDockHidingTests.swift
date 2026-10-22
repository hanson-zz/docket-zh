import Foundation
import XCTest

/// 替换并自动隐藏：何时让系统程序坞自动隐藏、何时还原、原值怎么记。
final class SystemDockHidingTests: XCTestCase {
    private typealias H = SystemDockHiding

    private func settings(_ edit: (inout CustomDockSettings) -> Void = { _ in }) -> CustomDockSettings {
        var dock = CustomDockSettings()
        edit(&dock)
        return dock
    }

    // MARK: 哪一档要隐藏

    func testOnlyReplaceAutoHideWantsTheDockHidden() {
        let base = settings()
        let modes: [ShelfPlacementMode] = [.beside, .top, .replace, .floating, .pinned(.topLeft)]
        for mode in modes {
            let applied = ShelfPlacement.applying(mode, setup: .both, settings: base, currentScale: 1)
            XCTAssertFalse(H.wanted(setup: applied.setup, settings: applied.settings), "\(mode)")
        }
        let hide = ShelfPlacement.applying(.replaceAutoHide, setup: .both, settings: base, currentScale: 1)
        XCTAssertTrue(H.wanted(setup: hide.setup, settings: hide.settings))
        XCTAssertTrue(H.shelfIgnoresSystemDock(setup: hide.setup, settings: hide.settings))
    }

    func testSystemDockOnlyAndFollowingNeverHide() {
        let hiding = settings { $0.autoHide = true }
        XCTAssertFalse(H.wanted(setup: .macOSDockOnly, settings: hiding))
        // 并排时扩展栏自己隐藏不算这一档。
        XCTAssertFalse(H.wanted(setup: .both, settings: hiding))
        // 跟随程序坞时隐藏看程序坞，不是“替换并隐藏”。
        XCTAssertFalse(H.wanted(setup: .customReplacement,
                                settings: settings { $0.autoHide = true; $0.followSystemDock = true }))
        // 浮动不隐藏。
        XCTAssertFalse(H.wanted(setup: .customReplacement,
                                settings: settings { $0.autoHide = true; $0.floating = true }))
        XCTAssertTrue(H.wanted(setup: .customReplacement,
                               settings: settings { $0.autoHide = true; $0.followSystemDock = false }))
    }

    // MARK: 进入

    private func now(_ autoHide: Bool, _ delay: DockAutoHideDelay = .absent) -> H.Current {
        H.Current(autoHide: autoHide, delay: delay)
    }

    private let hiddenDelay = DockAutoHideDelay.seconds(SystemDockHiding.hiddenDelay)

    func testHiddenDelayIsLongEnoughToNeverPopUp() {
        XCTAssertGreaterThanOrEqual(H.hiddenDelay, 1000)
    }

    func testEnteringRecordsBothOriginalsThenHidesAndStopsThePopUp() {
        XCTAssertEqual(H.step(wanted: true, recorded: nil, borrowingStrut: false, current: now(false)),
                       .hide(original: HiddenDockOriginal(autoHide: false, delay: .absent),
                             changes: H.Changes(autoHide: true, delay: hiddenDelay)))
    }

    func testEnteringRecordsAnExistingDelay() {
        XCTAssertEqual(H.step(wanted: true, recorded: nil, borrowingStrut: false, current: now(true, .seconds(0.5))),
                       .hide(original: HiddenDockOriginal(autoHide: true, delay: .seconds(0.5)),
                             changes: H.Changes(delay: hiddenDelay)))
    }

    func testEnteringWhenAlreadyHiddenWithTheLongDelayOnlyRecords() {
        let step = H.step(wanted: true, recorded: nil, borrowingStrut: false, current: now(true, hiddenDelay))
        XCTAssertEqual(step, .hide(original: HiddenDockOriginal(autoHide: true, delay: hiddenDelay),
                                   changes: H.Changes()))
        if case .hide(_, let changes) = step { XCTAssertTrue(changes.isEmpty) }
    }

    func testEnteringWaitsForTheStrutToBeGivenBack() {
        // 借保留区写的是“关”，这时记下来就把它当成了用户的原值。
        XCTAssertEqual(H.step(wanted: true, recorded: nil, borrowingStrut: true, current: now(false)), .none)
    }

    func testEnteringAgainKeepsTheFirstOriginals() {
        // 已经在这一档：程序坞现在是码头写的样子，再记一次就把它当成原值了。
        let recorded = HiddenDockOriginal(autoHide: false, delay: .absent)
        XCTAssertEqual(H.step(wanted: true, recorded: recorded, borrowingStrut: false,
                              current: now(true, hiddenDelay)), .none)
        // 用户中途自己改回常驻、或改了延迟，也不抢不覆盖。
        XCTAssertEqual(H.step(wanted: true, recorded: recorded, borrowingStrut: false,
                              current: now(false, .seconds(2))), .none)
        XCTAssertEqual(H.launchStep(wanted: true, recorded: recorded, current: now(true, hiddenDelay)), .none)
    }

    func testNothingRecordedAndNotWantedDoesNothing() {
        XCTAssertEqual(H.step(wanted: false, recorded: nil, borrowingStrut: false, current: now(true)), .none)
        XCTAssertEqual(H.step(wanted: false, recorded: nil, borrowingStrut: true, current: now(false)), .none)
    }

    // MARK: 离开

    func testLeavingRestoresBothAndDeletesAMissingDelay() {
        let recorded = HiddenDockOriginal(autoHide: false, delay: .absent)
        XCTAssertEqual(H.step(wanted: false, recorded: recorded, borrowingStrut: false,
                              current: now(true, hiddenDelay)),
                       .restore(changes: H.Changes(autoHide: false, delay: .absent)))
    }

    func testLeavingPutsBackAnExistingDelay() {
        let recorded = HiddenDockOriginal(autoHide: true, delay: .seconds(0.25))
        XCTAssertEqual(H.step(wanted: false, recorded: recorded, borrowingStrut: false,
                              current: now(true, hiddenDelay)),
                       .restore(changes: H.Changes(delay: .seconds(0.25))))
    }

    func testLeavingWhenNothingChangedOnlyClears() {
        let recorded = HiddenDockOriginal(autoHide: true, delay: hiddenDelay)
        XCTAssertEqual(H.step(wanted: false, recorded: recorded, borrowingStrut: false,
                              current: now(true, hiddenDelay)),
                       .restore(changes: H.Changes()))
    }

    func testLeavingRestoresEvenWhileAStrutIsWanted() {
        // 离开这一档进入普通替换：先还原，借保留区才读得到用户的原值。
        let recorded = HiddenDockOriginal(autoHide: false, delay: .absent)
        XCTAssertEqual(H.step(wanted: false, recorded: recorded, borrowingStrut: true,
                              current: now(true, hiddenDelay)),
                       .restore(changes: H.Changes(autoHide: false, delay: .absent)))
    }

    // MARK: 退出和启动

    func testQuitRestoresWhateverTheMode() {
        XCTAssertEqual(H.quitStep(recorded: HiddenDockOriginal(autoHide: false, delay: .absent),
                                  current: now(true, hiddenDelay)),
                       .restore(changes: H.Changes(autoHide: false, delay: .absent)))
        XCTAssertEqual(H.quitStep(recorded: HiddenDockOriginal(autoHide: true, delay: .seconds(1)),
                                  current: now(true, hiddenDelay)),
                       .restore(changes: H.Changes(delay: .seconds(1))))
        XCTAssertEqual(H.quitStep(recorded: nil, current: now(true)), .none)
    }

    func testLaunchRepaysACrashOnlyWhenOutOfTheMode() {
        XCTAssertEqual(H.launchStep(wanted: false, recorded: HiddenDockOriginal(autoHide: false, delay: .absent),
                                    current: now(true, hiddenDelay)),
                       .restore(changes: H.Changes(autoHide: false, delay: .absent)))
        // 仍在这一档：程序坞本来就该藏着，记录留着等退出或离开时还。
        XCTAssertEqual(H.launchStep(wanted: true, recorded: HiddenDockOriginal(autoHide: false, delay: .absent),
                                    current: now(true, hiddenDelay)), .none)
        XCTAssertEqual(H.launchStep(wanted: false, recorded: nil, current: now(true)), .none)
    }

    // MARK: 老状态（只记了自动隐藏）

    func testOldRecordStillInTheModeAddsTheDelay() {
        // 老版本进了这一档：只记了自动隐藏，延迟是用户自己的，补记下来再写长延迟。
        let old = HiddenDockOriginal(autoHide: false, delay: nil)
        let expected = H.Step.hide(original: HiddenDockOriginal(autoHide: false, delay: .seconds(0.5)),
                                   changes: H.Changes(delay: hiddenDelay))
        XCTAssertEqual(H.step(wanted: true, recorded: old, borrowingStrut: false,
                              current: now(true, .seconds(0.5))), expected)
        XCTAssertEqual(H.launchStep(wanted: true, recorded: old, current: now(true, .seconds(0.5))), expected)
        // 原本没有延迟键：记成没有，还原时删键。
        XCTAssertEqual(H.step(wanted: true, recorded: old, borrowingStrut: false, current: now(true)),
                       .hide(original: HiddenDockOriginal(autoHide: false, delay: .absent),
                             changes: H.Changes(delay: hiddenDelay)))
    }

    func testOldRecordLeavingRestoresOnlyAutoHide() {
        // 老版本没碰过延迟，还原时也不碰。
        let old = HiddenDockOriginal(autoHide: false, delay: nil)
        XCTAssertEqual(H.step(wanted: false, recorded: old, borrowingStrut: false, current: now(true, .seconds(0.5))),
                       .restore(changes: H.Changes(autoHide: false)))
        XCTAssertEqual(H.quitStep(recorded: old, current: now(true)),
                       .restore(changes: H.Changes(autoHide: false)))
        XCTAssertEqual(H.launchStep(wanted: false, recorded: old, current: now(false)),
                       .restore(changes: H.Changes()))
    }

    // MARK: 读偏好

    func testDelayReadsNumbersStringsAndMissingKeys() {
        XCTAssertEqual(DockAutoHideDelay(preference: nil), .absent)
        XCTAssertEqual(DockAutoHideDelay(preference: NSNumber(value: 0)), .seconds(0))
        XCTAssertEqual(DockAutoHideDelay(preference: NSNumber(value: 0.5)), .seconds(0.5))
        XCTAssertEqual(DockAutoHideDelay(preference: 2), .seconds(2))
        XCTAssertEqual(DockAutoHideDelay(preference: "1.5"), .seconds(1.5))
        XCTAssertEqual(DockAutoHideDelay(preference: "soon"), .absent)
    }

    // MARK: 原值存盘

    private func roundTrip(_ original: HiddenDockOriginal) throws -> HiddenDockOriginal? {
        var state = PersistedState()
        state.hiddenDockAutoHide = original
        return try JSONDecoder().decode(PersistedState.self, from: JSONEncoder().encode(state)).hiddenDockAutoHide
    }

    func testRecordedOriginalsSurviveARestart() throws {
        for original in [HiddenDockOriginal(autoHide: false, delay: .absent),
                         HiddenDockOriginal(autoHide: true, delay: .seconds(0)),
                         HiddenDockOriginal(autoHide: true, delay: .seconds(0.75)),
                         HiddenDockOriginal(autoHide: false, delay: nil)] {
            XCTAssertEqual(try roundTrip(original), original)
        }
    }

    func testOldBoolRecordDecodesWithoutADelay() throws {
        let old = try JSONDecoder().decode(PersistedState.self,
                                           from: Data(#"{"setup": "custom", "hiddenDockAutoHide": false}"#.utf8))
        XCTAssertEqual(old.hiddenDockAutoHide, HiddenDockOriginal(autoHide: false, delay: nil))
        let hidden = try JSONDecoder().decode(PersistedState.self,
                                              from: Data(#"{"hiddenDockAutoHide": true}"#.utf8))
        XCTAssertEqual(hidden.hiddenDockAutoHide, HiddenDockOriginal(autoHide: true, delay: nil))
    }

    func testRecordWithoutTheDelayFlagIsAnOldRecord() throws {
        let partial = try JSONDecoder().decode(PersistedState.self,
                                               from: Data(#"{"hiddenDockAutoHide": {"autoHide": true}}"#.utf8))
        XCTAssertEqual(partial.hiddenDockAutoHide, HiddenDockOriginal(autoHide: true, delay: nil))
    }

    func testOldStateHasNothingToRestore() throws {
        let old = try JSONDecoder().decode(PersistedState.self, from: Data(#"{"setup": "custom"}"#.utf8))
        XCTAssertNil(old.hiddenDockAutoHide)
    }

    // MARK: 一整轮

    func testFullRoundTripPutsTheUsersSettingsBack() {
        var recorded: HiddenDockOriginal?
        var current = now(false)
        var restarts = 0
        func run(_ step: H.Step) {
            func apply(_ changes: H.Changes) {
                if let autoHide = changes.autoHide { current.autoHide = autoHide }
                if let delay = changes.delay { current.delay = delay }
                if !changes.isEmpty { restarts += 1 }
            }
            switch step {
            case .none: break
            case .hide(let original, let changes):
                recorded = original
                apply(changes)
            case .restore(let changes):
                apply(changes)
                recorded = nil
            }
        }
        run(H.step(wanted: true, recorded: recorded, borrowingStrut: false, current: current))
        XCTAssertEqual(current, now(true, hiddenDelay))
        XCTAssertEqual(recorded, HiddenDockOriginal(autoHide: false, delay: .absent))
        XCTAssertEqual(restarts, 1)
        // 再进一次不覆盖原值，也不重启。
        run(H.step(wanted: true, recorded: recorded, borrowingStrut: false, current: current))
        XCTAssertEqual(recorded, HiddenDockOriginal(autoHide: false, delay: .absent))
        XCTAssertEqual(restarts, 1)
        run(H.step(wanted: false, recorded: recorded, borrowingStrut: false, current: current))
        XCTAssertEqual(current, now(false, .absent))
        XCTAssertNil(recorded)
        XCTAssertEqual(restarts, 2)
    }
}
