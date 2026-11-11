import Foundation
import XCTest

/// 桌面宠物（散步、发呆、睡觉、跳、坐、欢呼、废纸篓救回、站在哪条程序坞上）和
/// 专注计时面板的小熊猫爬竹竿（码头 Pro）。
final class DesktopPetTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let lane: ClosedRange<Double> = 100...700

    /// 从 `start` 起每 1/8 秒走一步，走 `seconds` 秒。
    private func run(_ state: DesktopPetState, from start: Date, seconds: Double, idle: TimeInterval = 0,
                     focusing: Bool = false, random: Double = 0.3) -> (DesktopPetState, Date) {
        var current = state
        var now = start
        let dt = 1 / DesktopPetBrain.fps
        for _ in 0..<Int(seconds * DesktopPetBrain.fps) {
            now = now.addingTimeInterval(dt)
            current = DesktopPetBrain.step(current, dt: dt, now: now, lane: lane, userIdle: idle,
                                           focusing: focusing, random: { random })
        }
        return (current, now)
    }

    // MARK: 设置

    func testSettingsDefaultOffAndDecodeLeniently() throws {
        let settings = DesktopPetSettings()
        XCTAssertFalse(settings.enabled)
        XCTAssertFalse(settings.trashRescue)
        XCTAssertFalse(settings.rescueActive)
        XCTAssertFalse(DesktopPetSettings(enabled: false, trashRescue: true).rescueActive)
        XCTAssertTrue(DesktopPetSettings(enabled: true, trashRescue: true).rescueActive)

        let decoded = try JSONDecoder().decode(DesktopPetSettings.self, from: Data(#"{"enabled":true,"x":1}"#.utf8))
        XCTAssertTrue(decoded.enabled)
        XCTAssertFalse(decoded.trashRescue)
        XCTAssertEqual(decoded.anchor, .dock, "老状态文件没有停靠位置：程序坞上沿")
        XCTAssertEqual(decoded.size, .medium)
        XCTAssertTrue(decoded.bubbles, "头顶气泡默认开")
        XCTAssertNil(decoded.hotKey, "快捷键默认不设")
        XCTAssertNil(decoded.spot)

        let odd = try JSONDecoder().decode(DesktopPetSettings.self, from: Data(
            #"{"enabled":true,"anchor":"sideways","size":7,"bubbles":"yes","spot":{"along":3,"display":"x"}}"#.utf8))
        XCTAssertTrue(odd.enabled)
        XCTAssertEqual(odd.anchor, .dock, "认不出的停靠位置用默认")
        XCTAssertEqual(odd.size, .medium)
        XCTAssertTrue(odd.bubbles)
        XCTAssertEqual(odd.spot?.along, 1, "沿边比例夹在 0…1")
        XCTAssertNil(odd.spot?.display)

        let full = DesktopPetSettings(enabled: true, anchor: .left, size: .large, bubbles: false,
                                      hotKey: KeyCombo(keyCode: 35, modifiers: 0x0900),
                                      spot: DesktopPetSpot(display: 2, along: 0.25))
        let round = try JSONDecoder().decode(DesktopPetSettings.self, from: JSONEncoder().encode(full))
        XCTAssertEqual(round, full)

        var state = PersistedState()
        XCTAssertEqual(state.desktopPet, DesktopPetSettings())
        state.desktopPet = DesktopPetSettings(enabled: true, trashRescue: true)
        let back = try JSONDecoder().decode(PersistedState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(back.desktopPet, state.desktopPet)
        let legacy = try JSONDecoder().decode(PersistedState.self, from: Data("{}".utf8))
        XCTAssertEqual(legacy.desktopPet, DesktopPetSettings())
    }

    // MARK: 动作帧

    func testStripNamesWrapAndExistOnDisk() {
        XCTAssertEqual(DesktopPetStrip.walk.imageName(0), "pet-sprite-walk-1")
        XCTAssertEqual(DesktopPetStrip.walk.imageName(32), "pet-sprite-walk-1")
        XCTAssertEqual(DesktopPetStrip.walk.imageName(31), "pet-sprite-walk-32")
        XCTAssertEqual(DesktopPetStrip.carry.imageName(3), "pet-sprite-carry-4")
        XCTAssertEqual(DesktopPetStrip.sleep.imageName(-1), "pet-sprite-sleep-3")
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Pet/sprites")
        for strip in DesktopPetStrip.allCases {
            for frame in 0..<strip.frameCount {
                let file = folder.appendingPathComponent(strip.imageName(frame) + ".png")
                XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), file.lastPathComponent)
            }
        }
    }

    // MARK: 散步、发呆、睡觉

    func testIdleThenWalkThenIdle() {
        var state = DesktopPetBrain.initial(lane: lane, now: t0)
        guard case .idle = state.activity else { return XCTFail("刚出现在发呆") }
        XCTAssertTrue(lane.contains(state.x))
        // 发呆到点后开始走。
        let (walking, at) = run(state, from: t0, seconds: 5)
        guard case .walk(let target) = walking.activity else { return XCTFail("发呆完去散步，实际 \(walking.activity)") }
        XCTAssertTrue(lane.contains(target))
        // 走到了就停下发呆，不会走出范围。
        state = walking
        var now = at
        var stopped = false
        for _ in 0..<(12 * Int(DesktopPetBrain.fps)) {
            now = now.addingTimeInterval(1 / DesktopPetBrain.fps)
            state = DesktopPetBrain.step(state, dt: 1 / DesktopPetBrain.fps, now: now, lane: lane,
                                         userIdle: 0, focusing: false, random: { 0.3 })
            XCTAssertTrue(lane.contains(state.x))
            if case .idle = state.activity { stopped = true; break }
        }
        XCTAssertTrue(stopped, "走 200 点以内 12 秒应该到了")
        XCTAssertEqual(state.x, target, accuracy: 0.001)
    }

    func testStrollTurnsAroundAtTheEdge() {
        let target = DesktopPetBrain.strollTarget(from: 110, lane: lane, random: { 0.2 })
        XCTAssertGreaterThan(target, 110, "左边走不出去就往右")
        XCTAssertTrue(lane.contains(target))
    }

    func testSleepsAfterUserIdleAndWakes() {
        let state = DesktopPetBrain.initial(lane: lane, now: t0)
        let asleep = DesktopPetBrain.step(state, dt: 0.125, now: t0, lane: lane,
                                          userIdle: DesktopPetBrain.sleepAfter, focusing: false, random: { 0.5 })
        guard case .sleep = asleep.activity else { return XCTFail("没操作几分钟就睡") }
        XCTAssertEqual(DesktopPetBrain.tickRate(asleep), DesktopPetBrain.sleepingFPS)
        XCTAssertEqual(DesktopPetBrain.pose(asleep, now: t0).image, "pet-sprite-sleep-1", "先打哈欠")
        XCTAssertEqual(DesktopPetBrain.pose(asleep, now: t0.addingTimeInterval(10)).image, "pet-sprite-sleep-3")
        let awake = DesktopPetBrain.step(asleep, dt: 0.5, now: t0.addingTimeInterval(60), lane: lane,
                                         userIdle: 1, focusing: false, random: { 0.5 })
        guard case .idle = awake.activity else { return XCTFail("用户回来就醒") }
        XCTAssertEqual(DesktopPetBrain.tickRate(awake), DesktopPetBrain.restingFPS)
    }

    func testPokeJumpsThenSettles() {
        let state = DesktopPetBrain.initial(lane: lane, now: t0)
        let jumping = DesktopPetBrain.poked(state, now: t0)
        guard case .jump = jumping.activity else { return XCTFail("点一下跳") }
        let middle = DesktopPetBrain.pose(jumping, now: t0.addingTimeInterval(DesktopPetBrain.jumpDuration / 2))
        XCTAssertEqual(middle.lift, DesktopPetBrain.jumpHeight, accuracy: 0.01)
        XCTAssertEqual(middle.image, "pet-sprite-jump-2")
        XCTAssertEqual(DesktopPetBrain.jumpLift(0), 0)
        XCTAssertEqual(DesktopPetBrain.jumpLift(1), 0)
        // 跳着时不理会再点一下，也不被睡觉打断。
        XCTAssertEqual(DesktopPetBrain.poked(jumping, now: t0.addingTimeInterval(0.1)), jumping)
        let still = DesktopPetBrain.step(jumping, dt: 0.1, now: t0.addingTimeInterval(0.2), lane: lane,
                                         userIdle: 999, focusing: false, random: { 0.5 })
        guard case .jump = still.activity else { return XCTFail("跳完再说") }
        let done = DesktopPetBrain.step(jumping, dt: 0.1, now: t0.addingTimeInterval(1), lane: lane,
                                        userIdle: 0, focusing: false, random: { 0.5 })
        guard case .idle = done.activity else { return XCTFail("跳完回去发呆") }
    }

    func testFocusSitsAndCheers() {
        let state = DesktopPetBrain.initial(lane: lane, now: t0)
        let sitting = DesktopPetBrain.step(state, dt: 0.1, now: t0, lane: lane, userIdle: 999,
                                           focusing: true, random: { 0.5 })
        XCTAssertEqual(sitting.activity, .sit, "专注时坐着，不睡也不走")
        XCTAssertEqual(DesktopPetBrain.pose(sitting, now: t0).image, "pet-panda-idle")
        let (later, _) = run(sitting, from: t0, seconds: 20, focusing: true)
        XCTAssertEqual(later.activity, .sit)
        XCTAssertEqual(later.x, sitting.x)
        let cheering = DesktopPetBrain.cheer(sitting, now: t0)
        XCTAssertEqual(DesktopPetBrain.pose(cheering, now: t0).image, "pet-panda-cheer")
        let after = DesktopPetBrain.step(cheering, dt: 0.1, now: t0.addingTimeInterval(10), lane: lane,
                                         userIdle: 0, focusing: false, random: { 0.5 })
        guard case .idle = after.activity else { return XCTFail("欢呼完发呆") }
    }

    // MARK: 废纸篓救回

    func testRescueRunsToTrashAndBack() {
        var state = DesktopPetBrain.initial(lane: lane, now: t0)
        let home = state.x
        state = DesktopPetBrain.startRescue(state, trashX: 690, lane: lane, now: t0)
        XCTAssertFalse(state.facingLeft)
        XCTAssertEqual(DesktopPetBrain.pose(state, now: t0).image, "pet-sprite-run-1")
        // 救回途中点它、专注、睡觉都不打断。
        XCTAssertEqual(DesktopPetBrain.poked(state, now: t0), state)
        XCTAssertEqual(DesktopPetBrain.cheer(state, now: t0), state)
        let (atTrash, at) = run(state, from: t0, seconds: 2.5, idle: 999, focusing: true)
        guard case .rescue(.pickUp) = atTrash.activity else { return XCTFail("跑到废纸篓叼起来，实际 \(atTrash.activity)") }
        XCTAssertEqual(atTrash.x, 690)
        let (back, _) = run(atTrash, from: at, seconds: 8)
        XCTAssertTrue(DesktopPetBrain.awaitingPutBack(back), "叼回原处等放回，实际 \(back.activity)")
        XCTAssertEqual(back.x, home)
        let cheered = DesktopPetBrain.finishRescue(back, succeeded: true, now: t0)
        guard case .cheer = cheered.activity else { return XCTFail("放回去了欢呼") }
        let failed = DesktopPetBrain.finishRescue(back, succeeded: false, now: t0)
        guard case .idle = failed.activity else { return XCTFail("没放回去回去发呆，气泡另弹") }
    }

    func testRescueCarryPoses() {
        let state = DesktopPetState(x: 300, activity: .rescue(.back(homeX: 200)), since: t0)
        XCTAssertEqual(DesktopPetBrain.pose(state, now: t0).image, "pet-sprite-carry-4")
        let picking = DesktopPetState(x: 300, activity: .rescue(.pickUp(since: t0, homeX: 200)), since: t0)
        XCTAssertEqual(DesktopPetBrain.pose(picking, now: t0).image, "pet-sprite-carry-1")
    }

    func testFreshTrashItemsOnly() {
        let now = t0
        let items = [
            TrashedItem(trashName: "new.txt", date: now.addingTimeInterval(-3)),
            TrashedItem(trashName: "old.txt", date: now.addingTimeInterval(-60)),
            TrashedItem(trashName: "seen.txt", date: now.addingTimeInterval(-2)),
        ]
        let fresh = DesktopPetRescue.fresh(items, seen: ["seen.txt"], now: now)
        XCTAssertEqual(fresh.map(\.trashName), ["new.txt"])
        XCTAssertTrue(DesktopPetRescue.fresh([], seen: [], now: now).isEmpty, "清空废纸篓不会冒出东西来")
        XCTAssertTrue(DesktopPetRescue.autoPutBack(fresh: 1, added: 1))
        XCTAssertFalse(DesktopPetRescue.autoPutBack(fresh: 0, added: 0))
        XCTAssertFalse(DesktopPetRescue.autoPutBack(fresh: 4, added: 4), "太多不自动放")
        XCTAssertFalse(DesktopPetRescue.autoPutBack(fresh: 2, added: 9), "扔进去的比列出来的多")
        XCTAssertEqual(DesktopPetRescue.bubbleTitle(count: 1), "放回原处")
        XCTAssertEqual(DesktopPetRescue.bubbleTitle(count: 2), "放回原处（2 项）")
        XCTAssertTrue(DesktopPetRescue.finderScript.contains("on run argv"), "路径从参数传，不拼进脚本")
    }

    // MARK: 站在哪

    func testPerchPrefersVisibleSystemDock() {
        let dock = CGRect(x: 400, y: 0, width: 800, height: 70)
        let bar = CGRect(x: 300, y: 0, width: 1000, height: 64)
        let system = DesktopPetPlacement.SystemDock(frame: dock, trashX: 1170, atBottom: true, autoHide: false)
        let shelf = DesktopPetPlacement.Shelf(frame: bar, atBottom: true, tucked: false)
        XCTAssertEqual(DesktopPetPlacement.perch(system: system, shelf: shelf, fullScreen: false)?.frame, dock)
        XCTAssertNil(DesktopPetPlacement.perch(system: system, shelf: shelf, fullScreen: true), "全屏不显示")

        var hidden = system
        hidden.autoHide = true
        let onShelf = DesktopPetPlacement.perch(system: hidden, shelf: shelf, fullScreen: false)
        XCTAssertEqual(onShelf?.frame, bar, "系统程序坞自动隐藏时跟扩展栏")
        XCTAssertNil(onShelf?.trashX)
        XCTAssertEqual(onShelf?.rescueX, onShelf?.lane.upperBound, "拿不到废纸篓位置时用最右端")

        let tucked = DesktopPetPlacement.Shelf(frame: bar, atBottom: true, tucked: true)
        XCTAssertNil(DesktopPetPlacement.perch(system: hidden, shelf: tucked, fullScreen: false), "都收起来了")
        let side = DesktopPetPlacement.SystemDock(frame: dock, atBottom: false, autoHide: false)
        let top = DesktopPetPlacement.Shelf(frame: bar, atBottom: false, tucked: false)
        XCTAssertNil(DesktopPetPlacement.perch(system: side, shelf: top, fullScreen: false), "都不在底边")
    }

    func testLaneAndTrash() {
        let perch = DesktopPetPerch(frame: CGRect(x: 400, y: 0, width: 800, height: 70), trashX: 1170)
        XCTAssertEqual(perch.lane.lowerBound, 436)
        XCTAssertEqual(perch.lane.upperBound, 1164)
        XCTAssertEqual(perch.rescueX, 1164, "废纸篓再靠边也在能走到的范围里")
        let tiny = DesktopPetPerch(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        XCTAssertLessThanOrEqual(tiny.lane.lowerBound, tiny.lane.upperBound)
    }

    func testEstimatedDockAndFullScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let visible = CGRect(x: 0, y: 70, width: 1512, height: 879)
        let dock = DesktopPetPlacement.estimatedDock(screen: screen, visible: visible, tileSize: 48, tiles: 10)
        XCTAssertEqual(dock?.height, 70)
        XCTAssertEqual(dock?.midX, screen.midX)
        XCTAssertNil(DesktopPetPlacement.estimatedDock(screen: screen, visible: screen, tileSize: 48, tiles: 10),
                     "程序坞隐藏着时底下没有空出来")
        XCTAssertTrue(DesktopPetPlacement.coversScreen(CGRect(x: 0, y: 1, width: 1512, height: 981), screen: screen))
        XCTAssertFalse(DesktopPetPlacement.coversScreen(CGRect(x: 0, y: 70, width: 1512, height: 879), screen: screen))
    }

    // MARK: 专注陪伴

    private func focusing(left: TimeInterval, total: TimeInterval = 1500, now: Date) -> TimerState {
        var state = TimerState()
        state.duration = total
        state.deadline = now.addingTimeInterval(left)
        return state
    }

    func testClimbProgress() {
        let now = t0
        XCTAssertEqual(FocusPandaClimb.progress(TimerState(), now: now), 0, "没开始在竹竿底")
        XCTAssertFalse(FocusPandaClimb.isActive(TimerState()))
        let half = focusing(left: 750, now: now)
        XCTAssertTrue(FocusPandaClimb.isActive(half))
        XCTAssertEqual(FocusPandaClimb.progress(half, now: now), 0.5, accuracy: 0.001)
        var paused = half
        paused.deadline = nil
        paused.paused = 375
        XCTAssertTrue(FocusPandaClimb.isActive(paused), "暂停着也在竹竿上")
        XCTAssertEqual(FocusPandaClimb.progress(paused, now: now), 0.75, accuracy: 0.001)
        XCTAssertEqual(FocusPandaClimb.progress(focusing(left: -5, now: now), now: now), 1, "到点在顶上")
        XCTAssertEqual(FocusPandaClimb.climbOffset(progress: 0.5, travel: 110), 55)
        XCTAssertEqual(FocusPandaClimb.climbOffset(progress: 2, travel: 110), 110)
        XCTAssertEqual(FocusPandaClimb.climbOffset(progress: -1, travel: 110), 0)
        var resting = half
        resting.phase = .rest
        XCTAssertFalse(FocusPandaClimb.isActive(resting), "休息时不爬")
    }

    func testClimbEvents() {
        let now = t0
        let running = focusing(left: 600, now: now)
        // 重置（手动结束）：滑下来。
        var reset = running
        reset.deadline = nil
        reset.duration = nil
        XCTAssertEqual(FocusPandaClimb.event(from: running, to: reset, now: now), .slide)
        // 暂停不算结束。
        var paused = running
        paused.deadline = nil
        paused.paused = 600
        XCTAssertNil(FocusPandaClimb.event(from: running, to: paused, now: now))
        // 完成一轮：到顶欢呼。
        let ending = focusing(left: 0, now: now)
        let next = FocusCycle.advanced(ending, now: now.addingTimeInterval(1))
        XCTAssertNotNil(next)
        if let next {
            XCTAssertEqual(FocusPandaClimb.event(from: ending, to: next, now: now.addingTimeInterval(1)), .cheer)
        }
        // 合盖很久回来、计时器自己回到开头：不滑也不欢呼。
        let stale = FocusCycle.advanced(ending, now: now.addingTimeInterval(FocusCycle.staleAfter + 60))
        if let stale {
            XCTAssertNil(FocusPandaClimb.event(from: ending, to: stale, now: now.addingTimeInterval(FocusCycle.staleAfter + 60)))
        }
        // 没在专注时什么都不演。
        XCTAssertNil(FocusPandaClimb.event(from: TimerState(), to: running, now: now))
    }

    func testFocusPandaIsPro() {
        XCTAssertTrue(ProFeatures.Setting.allCases.contains(.focusPanda))
        XCTAssertTrue(ProUnlockHighlights.allItems.contains(.setting(.focusPanda)))
        XCTAssertEqual(ProUnlockHighlights.title(.setting(.focusPanda)), "专注陪伴")
        XCTAssertFalse(ProLicenseGate.canUseFocusPanda(unlocked: false))
        XCTAssertTrue(ProLicenseGate.canUseFocusPanda(unlocked: true))
    }
}
