import XCTest

/// 专注环境音一轮里的决定（`FocusAmbientRound`）、谁在放（`AmbientOwner`）、面板上的状态小字。
final class FocusAmbientRoundTests: XCTestCase {
    func testStartsThenRetunesThenStops() {
        var round = FocusAmbientRound()
        XCTAssertEqual(round.step(wanted: nil, choice: "rain", level: 55, ours: false, blocked: false), .none)
        XCTAssertEqual(round.step(wanted: .rain, choice: "rain", level: 55, ours: false, blocked: false), .start(.rain))
        round.started(.rain, volume: 55)
        XCTAssertEqual(round.step(wanted: .rain, choice: "rain", level: 55, ours: true, blocked: false), .none)
        XCTAssertEqual(round.step(wanted: .rain, choice: "rain", level: 40, ours: true, blocked: false),
                       .retune(.rain, volume: 40))
        XCTAssertEqual(round.step(wanted: .waves, choice: "waves", level: 40, ours: true, blocked: false),
                       .retune(.waves, volume: 40))
        XCTAssertEqual(round.step(wanted: nil, choice: "waves", level: 40, ours: true, blocked: false), .stop)
        XCTAssertNil(round.playing)
    }

    func testYieldsToTheWidgetAndSaysWhy() {
        var round = FocusAmbientRound()
        XCTAssertEqual(round.step(wanted: .rain, choice: "rain", level: 55, ours: false, blocked: true), .none)
        XCTAssertEqual(round.skip, .widgetPlaying)
        // 每秒再走一步也不抢。
        XCTAssertEqual(round.step(wanted: .rain, choice: "rain", level: 55, ours: false, blocked: false), .none)
        // 专注停下：让开作废，下一轮照常放。
        XCTAssertEqual(round.step(wanted: nil, choice: "rain", level: 55, ours: false, blocked: true), .none)
        XCTAssertNil(round.skip)
    }

    func testUserTakingOverYieldsForTheRound() {
        var round = FocusAmbientRound()
        _ = round.step(wanted: .fire, choice: "fire", level: 55, ours: false, blocked: false)
        round.started(.fire, volume: 55)
        XCTAssertEqual(round.step(wanted: .fire, choice: "fire", level: 55, ours: false, blocked: false), .none)
        XCTAssertEqual(round.skip, .userTookOver)
        XCTAssertEqual(round.step(wanted: .fire, choice: "fire", level: 55, ours: false, blocked: false), .none)
    }

    func testPickingAnotherSoundInTheFocusPanelOverridesAYield() {
        var round = FocusAmbientRound()
        _ = round.step(wanted: .rain, choice: "rain", level: 55, ours: false, blocked: true)
        XCTAssertEqual(round.skip, .widgetPlaying)
        // 在专注面板里改选：明确要放，连小组件也不让了。
        XCTAssertEqual(round.step(wanted: .wind, choice: "wind", level: 55, ours: false, blocked: true), .start(.wind))
        XCTAssertNil(round.skip)
    }

    func testAudioFailureStopsRetryingUntilTheChoiceChanges() {
        var round = FocusAmbientRound()
        XCTAssertEqual(round.step(wanted: .pink, choice: "pink", level: 55, ours: false, blocked: false), .start(.pink))
        round.failed(choice: "pink")
        XCTAssertEqual(round.skip, .audioFailed)
        XCTAssertEqual(round.step(wanted: .pink, choice: "pink", level: 55, ours: false, blocked: false), .none)
        XCTAssertEqual(round.step(wanted: .brown, choice: "brown", level: 55, ours: false, blocked: false), .start(.brown))
    }

    func testOwnershipRules() {
        // 小组件出现时同步组合：只在没放、或放的本来就是小组件自己的时候改。
        XCTAssertTrue(AmbientOwner.primeChangesPlayback(owner: .widget, playing: true))
        XCTAssertTrue(AmbientOwner.primeChangesPlayback(owner: .focus, playing: false))
        XCTAssertFalse(AmbientOwner.primeChangesPlayback(owner: .focus, playing: true))
        XCTAssertFalse(AmbientOwner.primeChangesPlayback(owner: .preview, playing: true))
        // 专注开始时只让给正在放的小组件，试听直接接过来。
        XCTAssertTrue(AmbientOwner.blocksFocus(owner: .widget, playing: true))
        XCTAssertFalse(AmbientOwner.blocksFocus(owner: .widget, playing: false))
        XCTAssertFalse(AmbientOwner.blocksFocus(owner: .preview, playing: true))
    }

    func testStatusLine() {
        XCTAssertEqual(FocusAmbientStatus.text(chosen: false, running: true, wanted: false, playing: false, skip: nil),
                       "选一种声音，开始专注时自动播放")
        XCTAssertEqual(FocusAmbientStatus.text(chosen: true, running: false, wanted: false, playing: false, skip: nil),
                       "开始专注时自动播放")
        XCTAssertEqual(FocusAmbientStatus.text(chosen: true, running: true, wanted: true, playing: true, skip: nil),
                       "正在播放")
        XCTAssertEqual(FocusAmbientStatus.text(chosen: true, running: true, wanted: false, playing: false, skip: nil),
                       "休息时声音停下，回到专注再放")
        for skip in FocusAmbientSkip.allCases {
            XCTAssertEqual(FocusAmbientStatus.text(chosen: true, running: true, wanted: true, playing: false, skip: skip),
                           skip.note)
            XCTAssertFalse(skip.note.isEmpty)
        }
        XCTAssertEqual(FocusAmbientSkip.allCases.count, 3)
    }

    func testNewInstallsStartWithASoftSoundAndOldFilesKeepTheirChoice() throws {
        XCTAssertEqual(TimerState.firstRun.ambient, FocusAmbient.firstRunSound.rawValue)
        XCTAssertEqual(PersistedState().timer.ambient, "rain")
        XCTAssertEqual(TimerState().ambient, "", "老的默认仍是不播放，存过的选择不动")
        let old = try JSONDecoder().decode(TimerState.self, from: Data(#"{"ambient":""}"#.utf8))
        XCTAssertEqual(old.ambient, "")
    }
}
