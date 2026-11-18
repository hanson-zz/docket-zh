import XCTest
@testable import Docket

final class FocusMascotTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: 吉祥物

    func testSixMascotsDefaultToRedPanda() {
        XCTAssertEqual(FocusMascot.allCases, [.panda, .shiba, .cat, .penguin, .otter, .octopus])
        XCTAssertEqual(FocusMascot.from(""), .panda)
        XCTAssertEqual(FocusMascot.from("dragon"), .panda, "认不出的退回小熊猫")
        XCTAssertEqual(FocusMascot.from("otter"), .otter)
        XCTAssertEqual(FocusMascot.of(TimerState()), .panda)
        XCTAssertTrue(FocusMascot.panda.climbsBamboo)
        XCTAssertFalse(FocusMascot.allCases.filter { $0 != .panda }.contains { $0.climbsBamboo })
    }

    func testImageNamesCoverEveryMascotAndState() {
        XCTAssertEqual(FocusMascotState.allCases, [.idle, .focus, .`break`, .done])
        let names = Set(FocusMascot.allCases.flatMap { m in FocusMascotState.allCases.map { m.imageName($0) } })
        XCTAssertEqual(names.count, 24)
        XCTAssertEqual(FocusMascot.shiba.imageName(.`break`), "focus-mascot-shiba-break")
        XCTAssertEqual(FocusMascot.panda.imageName(.done), "focus-mascot-panda-done")
    }

    func testStateFollowsTheTimer() {
        var state = TimerState()
        XCTAssertEqual(FocusMascotState.of(state, now: now), .idle, "没开始")
        state.duration = 1500
        state.deadline = now.addingTimeInterval(600)
        XCTAssertEqual(FocusMascotState.of(state, now: now), .focus, "专注在跑")
        state.deadline = nil
        state.paused = 600
        XCTAssertEqual(FocusMascotState.of(state, now: now), .idle, "专注暂停")

        // 专注到点，休息自动开始：前一分钟撒花，之后是休息。
        var running = TimerState()
        running.duration = 1500
        running.deadline = now
        let rest = FocusCycle.advanced(running, now: now.addingTimeInterval(1))!
        XCTAssertEqual(rest.phase, .rest)
        XCTAssertEqual(FocusMascotState.of(rest, now: now.addingTimeInterval(1)), .done)
        XCTAssertEqual(FocusMascotState.of(rest, now: now.addingTimeInterval(FocusMascotState.doneWindow + 1)), .`break`)
        var paused = rest
        paused.deadline = nil
        paused.paused = 200
        XCTAssertEqual(FocusMascotState.of(paused, now: now.addingTimeInterval(5)), .`break`, "暂停的休息不撒花")
        var idleRest = TimerState()
        idleRest.phase = .long
        XCTAssertEqual(FocusMascotState.of(idleRest, now: now), .`break`)
    }

    func testPandaStillHidesWhileClimbing() {
        var state = TimerState()
        XCTAssertTrue(FocusMascotDisplay.showsStill(.panda, state: state, now: now, unlocked: true), "没开始时画状态图")
        state.duration = 1500
        state.deadline = now.addingTimeInterval(600)
        XCTAssertFalse(FocusMascotDisplay.showsStill(.panda, state: state, now: now, unlocked: true), "在竹竿上")
        XCTAssertFalse(FocusMascotDisplay.showsStill(.panda, state: state, now: now, unlocked: false),
                       "免费版竹竿旁已有一只静态的")
        XCTAssertTrue(FocusMascotDisplay.showsStill(.cat, state: state, now: now, unlocked: true), "别的吉祥物一直画")

        var running = TimerState()
        running.duration = 1500
        running.deadline = now
        let rest = FocusCycle.advanced(running, now: now)!
        XCTAssertFalse(FocusMascotDisplay.showsStill(.panda, state: rest, now: now.addingTimeInterval(1), unlocked: true),
                       "竹竿顶上欢呼那几秒不另画")
        XCTAssertTrue(FocusMascotDisplay.showsStill(.panda, state: rest, now: now.addingTimeInterval(1), unlocked: false))
        XCTAssertTrue(FocusMascotDisplay.showsStill(.panda, state: rest, now: now.addingTimeInterval(10), unlocked: true))
    }

    // MARK: 拖大数字

    func testScrubStepsFiveMinutesWithinFiveToNinety() {
        XCTAssertEqual(FocusScrub.range, 5...90)
        XCTAssertEqual(FocusScrub.step, 5)
        XCTAssertEqual(FocusScrub.minutes(from: 25, dx: 0, dy: 0), 25)
        XCTAssertEqual(FocusScrub.minutes(from: 25, dx: 13, dy: 0), 25, "不满一档不动")
        XCTAssertEqual(FocusScrub.minutes(from: 25, dx: 14, dy: 0), 30)
        XCTAssertEqual(FocusScrub.minutes(from: 25, dx: 29, dy: 3), 35)
        XCTAssertEqual(FocusScrub.minutes(from: 25, dx: -28, dy: 0), 15)
        XCTAssertEqual(FocusScrub.minutes(from: 25, dx: 2, dy: -42), 40, "向上也是加")
        XCTAssertEqual(FocusScrub.minutes(from: 25, dx: 0, dy: 42), 10, "向下是减")
        XCTAssertEqual(FocusScrub.minutes(from: 25, dx: -1000, dy: 0), 5)
        XCTAssertEqual(FocusScrub.minutes(from: 25, dx: 1000, dy: 0), 90)
        XCTAssertEqual(FocusScrub.minutes(from: 27, dx: 14, dy: 0), 30, "先对齐到一档再加")
        XCTAssertEqual(FocusScrub.minutes(from: 120, dx: 5, dy: 0), 120, "碰一下不夹")
        XCTAssertEqual(FocusScrub.minutes(from: 120, dx: -14, dy: 0), 85)
        XCTAssertEqual(FocusScrub.minutes(from: 1, dx: 14, dy: 0), 10)
    }

    func testScrubOnlyBeforeFocusStarts() {
        var state = TimerState()
        XCTAssertTrue(FocusScrub.canScrub(state))
        state.deadline = now
        XCTAssertFalse(FocusScrub.canScrub(state), "在跑")
        state.deadline = nil
        state.paused = 100
        XCTAssertFalse(FocusScrub.canScrub(state), "暂停")
        state.paused = nil
        state.phase = .rest
        XCTAssertFalse(FocusScrub.canScrub(state), "休息")

        var pinned = TimerState()
        pinned.duration = 1500
        let applied = FocusScrub.applying(40, to: pinned)
        XCTAssertEqual(applied.work, 40)
        XCTAssertNil(applied.duration, "钉住的长度清掉，数字马上跟着变")
    }

    // MARK: 跳过

    func testSkipMovesToTheNextPhaseWithoutCounting() {
        var state = TimerState()
        state.completed = 1
        state.duration = 1500
        state.deadline = now.addingTimeInterval(300)
        let toRest = FocusCycle.skipped(state)
        XCTAssertEqual(toRest.phase, .rest)
        XCTAssertEqual(toRest.completed, 1, "跳过的专注不算完成")
        XCTAssertNil(toRest.deadline)
        XCTAssertNil(toRest.duration)
        XCTAssertNil(toRest.paused)

        let back = FocusCycle.skipped(toRest)
        XCTAssertEqual(back.phase, .focus)
        XCTAssertEqual(back.completed, 1)

        var long = TimerState()
        long.phase = .long
        long.completed = 4
        long.paused = 100
        let afterLong = FocusCycle.skipped(long)
        XCTAssertEqual(afterLong.phase, .focus)
        XCTAssertEqual(afterLong.completed, 0, "长休息后轮次从头数")
        XCTAssertNil(afterLong.paused)
    }

    // MARK: 提示音

    func testEndSoundsUseSystemSoundsWithDefaultsAndOff() {
        var state = TimerState()
        XCTAssertEqual(FocusEndSound.focusEnd(state), "Hero")
        XCTAssertEqual(FocusEndSound.restEnd(state), "Glass")
        XCTAssertEqual(FocusEndSound.ending(state), "Hero", "专注到点响专注结束的")
        state.phase = .long
        XCTAssertEqual(FocusEndSound.ending(state), "Glass")
        state.restEndSound = FocusEndSound.none
        XCTAssertEqual(FocusEndSound.ending(state), "none", "可以关")
        state.focusEndSound = "Shiduo-musicbox"
        XCTAssertEqual(FocusEndSound.focusEnd(state), "Hero", "不打包音频，认不出的退回默认")
        state.focusEndSound = "Tink"
        XCTAssertEqual(FocusEndSound.focusEnd(state), "Tink")
        XCTAssertEqual(FocusEndSound.choices.last, FocusEndSound.none)
        XCTAssertEqual(Set(FocusEndSound.system).count, FocusEndSound.system.count)
        XCTAssertTrue(FocusEndSound.system.contains(FocusEndSound.defaultFocusEnd))
        XCTAssertTrue(FocusEndSound.system.contains(FocusEndSound.defaultRestEnd))

        XCTAssertEqual(FocusEndSound.repeats(TimerState()), 1)
        state.soundRepeats = 9
        XCTAssertEqual(FocusEndSound.repeats(state), 5)
        state.soundRepeats = 0
        XCTAssertEqual(FocusEndSound.repeats(state), 1)
    }

    func testEndNoticeText() {
        var focus = TimerState()
        focus.duration = 1500
        focus.deadline = now
        let rest = FocusCycle.advanced(focus, now: now)!
        XCTAssertEqual(FocusEndNotice.title(ended: focus), "专注完成")
        XCTAssertEqual(FocusEndNotice.body(ended: focus, next: rest), "已专注 25 分钟，起来活动一下，休息 5 分钟。")
        XCTAssertEqual(FocusEndNotice.title(ended: rest), "休息结束")
        XCTAssertEqual(FocusEndNotice.body(ended: rest, next: TimerState()), "准备好开始下一轮专注了吗？")
    }

    // MARK: 存档

    func testNewFieldsSurviveARoundTripAndOldFilesGetDefaults() throws {
        var state = TimerState()
        state.mascot = "octopus"
        state.focusEndSound = "Ping"
        state.restEndSound = "none"
        state.soundRepeats = 3
        state.notifyEnd = false
        let back = try JSONDecoder().decode(TimerState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(back, state)

        let old = try JSONDecoder().decode(TimerState.self, from: Data(#"{"work":30}"#.utf8))
        XCTAssertEqual(old.mascot, "")
        XCTAssertEqual(old.focusEndSound, "")
        XCTAssertEqual(old.restEndSound, "")
        XCTAssertEqual(old.soundRepeats, 1)
        XCTAssertTrue(old.notifyEnd)
    }
}
