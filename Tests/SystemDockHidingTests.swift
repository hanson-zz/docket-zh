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

    func testEnteringRecordsTheOriginalThenHides() {
        XCTAssertEqual(H.step(wanted: true, recorded: nil, borrowingStrut: false, systemAutoHide: false),
                       .hide(original: false, write: true))
    }

    func testEnteringWhenAlreadyHiddenOnlyRecords() {
        XCTAssertEqual(H.step(wanted: true, recorded: nil, borrowingStrut: false, systemAutoHide: true),
                       .hide(original: true, write: false))
    }

    func testEnteringWaitsForTheStrutToBeGivenBack() {
        // 借保留区写的是“关”，这时记下来就把它当成了用户的原值。
        XCTAssertEqual(H.step(wanted: true, recorded: nil, borrowingStrut: true, systemAutoHide: false), .none)
    }

    func testStayingInTheModeDoesNothing() {
        XCTAssertEqual(H.step(wanted: true, recorded: false, borrowingStrut: false, systemAutoHide: true), .none)
        // 用户中途自己改回常驻也不抢。
        XCTAssertEqual(H.step(wanted: true, recorded: false, borrowingStrut: false, systemAutoHide: false), .none)
    }

    func testNothingRecordedAndNotWantedDoesNothing() {
        XCTAssertEqual(H.step(wanted: false, recorded: nil, borrowingStrut: false, systemAutoHide: true), .none)
        XCTAssertEqual(H.step(wanted: false, recorded: nil, borrowingStrut: true, systemAutoHide: false), .none)
    }

    // MARK: 离开

    func testLeavingRestoresTheOriginal() {
        XCTAssertEqual(H.step(wanted: false, recorded: false, borrowingStrut: false, systemAutoHide: true),
                       .restore(original: false, write: true))
    }

    func testLeavingWhenTheOriginalWasHiddenOnlyClears() {
        XCTAssertEqual(H.step(wanted: false, recorded: true, borrowingStrut: false, systemAutoHide: true),
                       .restore(original: true, write: false))
    }

    func testLeavingRestoresEvenWhileAStrutIsWanted() {
        // 离开这一档进入普通替换：先还原，借保留区才读得到用户的原值。
        XCTAssertEqual(H.step(wanted: false, recorded: false, borrowingStrut: true, systemAutoHide: true),
                       .restore(original: false, write: true))
    }

    // MARK: 退出和启动

    func testQuitRestoresWhateverTheMode() {
        XCTAssertEqual(H.quitStep(recorded: false, systemAutoHide: true), .restore(original: false, write: true))
        XCTAssertEqual(H.quitStep(recorded: true, systemAutoHide: true), .restore(original: true, write: false))
        XCTAssertEqual(H.quitStep(recorded: nil, systemAutoHide: true), .none)
    }

    func testLaunchRepaysACrashOnlyWhenOutOfTheMode() {
        XCTAssertEqual(H.launchStep(wanted: false, recorded: false, systemAutoHide: true),
                       .restore(original: false, write: true))
        // 仍在这一档：程序坞本来就该藏着，记录留着等退出或离开时还。
        XCTAssertEqual(H.launchStep(wanted: true, recorded: false, systemAutoHide: true), .none)
        XCTAssertEqual(H.launchStep(wanted: false, recorded: nil, systemAutoHide: true), .none)
    }

    // MARK: 原值存盘

    func testRecordedOriginalSurvivesARestart() throws {
        var state = PersistedState()
        state.hiddenDockAutoHide = false
        let back = try JSONDecoder().decode(PersistedState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(back.hiddenDockAutoHide, false)
    }

    func testOldStateHasNothingToRestore() throws {
        let old = try JSONDecoder().decode(PersistedState.self, from: Data(#"{"setup": "custom"}"#.utf8))
        XCTAssertNil(old.hiddenDockAutoHide)
    }

    // MARK: 一整轮

    func testFullRoundTripPutsTheUsersSettingBack() {
        var recorded: Bool?
        var systemAutoHide = false
        func run(_ step: H.Step) {
            switch step {
            case .none: break
            case .hide(let original, let write):
                recorded = original
                if write { systemAutoHide = true }
            case .restore(let original, let write):
                if write { systemAutoHide = original }
                recorded = nil
            }
        }
        run(H.step(wanted: true, recorded: recorded, borrowingStrut: false, systemAutoHide: systemAutoHide))
        XCTAssertTrue(systemAutoHide)
        XCTAssertEqual(recorded, false)
        run(H.step(wanted: true, recorded: recorded, borrowingStrut: false, systemAutoHide: systemAutoHide))
        XCTAssertEqual(recorded, false)
        run(H.step(wanted: false, recorded: recorded, borrowingStrut: false, systemAutoHide: systemAutoHide))
        XCTAssertFalse(systemAutoHide)
        XCTAssertNil(recorded)
    }
}
