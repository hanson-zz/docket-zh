import Foundation
import XCTest

/// 桌面宠物停在屏幕边缘、随意放、拖完吸到哪条边、贴边时的样子（趴着、探头、伸懒腰、
/// 挪几步、睡觉）、鼠标靠近转头、拖着乱蹬和落地回弹、转身过渡、眨眼、头顶气泡、快捷条。
final class DesktopPetEdgeTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    /// 菜单栏 33 点，程序坞在底下占 70 点。
    private let visible = CGRect(x: 0, y: 70, width: 1512, height: 879)

    // MARK: 停靠位置和那条边

    func testAnchorsMapToEdgesAndStyles() {
        XCTAssertEqual(DesktopPetAnchor.allCases.count, 6)
        XCTAssertEqual(DesktopPetAnchor.dock.style, .stroll, "程序坞保留散步")
        XCTAssertEqual(DesktopPetAnchor.left.style, .curl)
        XCTAssertEqual(DesktopPetAnchor.top.style, .curl)
        XCTAssertEqual(DesktopPetAnchor.free.style, .sit)
        XCTAssertEqual(DesktopPetAnchor.left.edge, .left)
        XCTAssertEqual(DesktopPetAnchor.free.edge, .bottom)
        XCTAssertEqual(DesktopPetAnchor.free.title, "随意（拖到哪停哪）")
        XCTAssertEqual(DesktopPetEdge.left.rotation, 90)
        XCTAssertEqual(DesktopPetEdge.right.rotation, -90)
        XCTAssertEqual(DesktopPetEdge.top.rotation, 180)
        XCTAssertEqual(DesktopPetSize.small.scale, 0.8)
        XCTAssertEqual(DesktopPetSize.large.scale, 1.25)
    }

    func testFacingFlipsPerEdge() {
        // 朝沿边坐标变小：底边就是朝左，翻过来；贴左边（顺时针转 90°）本来就朝下，不翻。
        XCTAssertTrue(DesktopPetEdge.bottom.flipped(facingLeft: true))
        XCTAssertFalse(DesktopPetEdge.left.flipped(facingLeft: true))
        XCTAssertTrue(DesktopPetEdge.left.flipped(facingLeft: false))
        XCTAssertTrue(DesktopPetEdge.right.flipped(facingLeft: true))
        XCTAssertFalse(DesktopPetEdge.top.flipped(facingLeft: true))
    }

    func testEdgeTracksStayInsideVisibleArea() throws {
        let left = try XCTUnwrap(DesktopPetTracks.edge(.left, visible: visible, length: 56, spot: nil))
        XCTAssertEqual(left.base, 0)
        XCTAssertGreaterThanOrEqual(left.lane.lowerBound, 70 + 28, "不挡程序坞")
        XCTAssertLessThanOrEqual(left.lane.upperBound, 949 - 28, "不挡菜单栏")
        XCTAssertEqual(left.feet(along: 300, lift: 10), CGPoint(x: 10, y: 300), "贴左边往右抬")

        let right = try XCTUnwrap(DesktopPetTracks.edge(.right, visible: visible, length: 56, spot: nil))
        XCTAssertEqual(right.base, 1512)
        XCTAssertEqual(right.feet(along: 300, lift: 10), CGPoint(x: 1502, y: 300))

        let top = try XCTUnwrap(DesktopPetTracks.edge(.top, visible: visible, length: 56, spot: nil))
        XCTAssertEqual(top.base, 949, "菜单栏下方")
        XCTAssertEqual(top.feet(along: 500, lift: 6), CGPoint(x: 500, y: 943), "倒挂着往下探")

        let bottom = try XCTUnwrap(DesktopPetTracks.edge(.bottom, visible: visible, length: 56, spot: nil))
        XCTAssertEqual(bottom.base, 70)
        XCTAssertNil(DesktopPetTracks.edge(.dock, visible: visible, length: 56, spot: nil), "程序坞另算")
        XCTAssertNil(DesktopPetTracks.edge(.left, visible: CGRect(x: 0, y: 0, width: 40, height: 40),
                                           length: 56, spot: nil))
    }

    func testFreeTrackIsOnePointFromSpot() throws {
        let spot = DesktopPetSpot(display: 1, along: 0.5, across: 0)
        let free = try XCTUnwrap(DesktopPetTracks.edge(.free, visible: visible, length: 56, spot: spot))
        XCTAssertEqual(free.style, .sit)
        XCTAssertEqual(free.lane.lowerBound, free.lane.upperBound, "随意放的地方是一个点")
        XCTAssertEqual(free.lane.lowerBound, 756, accuracy: 0.001)
        XCTAssertEqual(free.base, 70, accuracy: 0.001)
        // 松手的地方算回比例，再放回去还是同一处。
        let point = CGPoint(x: 400, y: 500)
        let saved = DesktopPetSnap.spot(for: point, track: free, visible: visible, display: 1, length: 56)
        let again = try XCTUnwrap(DesktopPetTracks.edge(.free, visible: visible, length: 56, spot: saved))
        XCTAssertEqual(again.lane.lowerBound, 400, accuracy: 0.5)
        XCTAssertEqual(again.base, 500, accuracy: 0.5)
    }

    func testDockTrackKeepsPerchLaneAndTrash() {
        let perch = DesktopPetPerch(frame: CGRect(x: 400, y: 0, width: 800, height: 70), trashX: 1170)
        let track = DesktopPetTracks.dock(perch)
        XCTAssertEqual(track.style, .stroll)
        XCTAssertEqual(track.base, 66, "脚踩进程序坞 4 点")
        XCTAssertEqual(track.lane, perch.lane)
        XCTAssertEqual(track.rescueX, 1164)
    }

    func testTrackFractionRoundTrip() throws {
        let left = try XCTUnwrap(DesktopPetTracks.edge(.left, visible: visible, length: 56, spot: nil))
        let along = left.along(fraction: 0.3)
        XCTAssertEqual(left.fraction(of: along), 0.3, accuracy: 0.0001)
        XCTAssertEqual(left.along(of: CGPoint(x: 5, y: 5)), left.lane.lowerBound, "夹在范围里")
    }

    // MARK: 拖完吸到哪

    func testSnapToNearestEdge() {
        let dock = CGRect(x: 400, y: 0, width: 700, height: 70)
        XCTAssertEqual(DesktopPetSnap.nearest(CGPoint(x: 30, y: 500), visible: visible, dock: dock), .left)
        XCTAssertEqual(DesktopPetSnap.nearest(CGPoint(x: 1490, y: 500), visible: visible, dock: dock), .right)
        XCTAssertEqual(DesktopPetSnap.nearest(CGPoint(x: 700, y: 930), visible: visible, dock: dock), .top)
        XCTAssertEqual(DesktopPetSnap.nearest(CGPoint(x: 700, y: 90), visible: visible, dock: dock), .dock,
                       "程序坞正上方吸回程序坞")
        XCTAssertEqual(DesktopPetSnap.nearest(CGPoint(x: 200, y: 90), visible: visible, dock: dock), .bottom,
                       "程序坞旁边是屏幕下边缘")
        XCTAssertEqual(DesktopPetSnap.nearest(CGPoint(x: 700, y: 90), visible: visible, dock: nil), .bottom)
    }

    func testGlideOvershootsThenSettles() {
        XCTAssertEqual(DesktopPetSnap.glide(0), 0, accuracy: 0.0001)
        XCTAssertEqual(DesktopPetSnap.glide(1), 1, accuracy: 0.0001)
        let peak = (1...99).map { DesktopPetSnap.glide(Double($0) / 100) }.max() ?? 0
        XCTAssertGreaterThan(peak, 1, "稍微冲过一点")
        XCTAssertLessThan(peak, 1.12)
        XCTAssertEqual(DesktopPetSnap.angle(from: -90, to: 180, t: 1), -180, accuracy: 0.0001, "走近的那边")
        XCTAssertEqual(DesktopPetSnap.angle(from: 0, to: 90, t: 0.5), 45, accuracy: 0.0001)
    }

    // MARK: 贴边时的样子

    private func run(_ state: DesktopPetState, seconds: Double, lane: ClosedRange<Double>, style: DesktopPetStyle,
                     idle: TimeInterval = 0, attention: Double? = nil, random: @escaping () -> Double)
        -> (DesktopPetState, [DesktopPetActivity]) {
        var current = state
        var now = state.since
        var seen: [DesktopPetActivity] = []
        let dt = 1 / 60.0
        for _ in 0..<Int(seconds * 60) {
            now = now.addingTimeInterval(dt)
            current = DesktopPetBrain.step(current, dt: dt, now: now, lane: lane, userIdle: idle, focusing: false,
                                           style: style, attention: attention, random: random)
            if seen.last != current.activity { seen.append(current.activity) }
            XCTAssertTrue(lane.contains(current.x))
        }
        return (current, seen)
    }

    func testCurlRestsThenDoesSomethingThenCurlsAgain() {
        let lane: ClosedRange<Double> = 100...800
        let state = DesktopPetBrain.placed(at: 300, style: .curl, now: t0)
        guard case .curl = state.activity else { return XCTFail("贴边平时趴着") }
        XCTAssertEqual(DesktopPetBrain.pose(state, now: t0).image, "pet-sprite-lie-1", "趴着那套帧")
        XCTAssertFalse(DesktopPetBrain.isMoving(state, now: t0), "趴着不开显示刷新")

        // 依次掷出：探头、伸懒腰、挪几步、打哈欠。
        for (roll, expect) in [(0.1, "peek"), (0.4, "stretch"), (0.6, "walk"), (0.9, "yawn")] {
            let (_, seen) = run(state, seconds: 30, lane: lane, style: .curl, random: { roll })
            let names = seen.map { "\($0)" }
            XCTAssertTrue(names.contains { $0.hasPrefix(expect) }, "掷 \(roll) 应该 \(expect)，实际 \(names)")
            XCTAssertTrue(names.dropFirst().contains { $0.hasPrefix("curl") }, "做完趴回去，实际 \(names)")
        }
    }

    func testCurlShuffleIsShort() {
        let lane: ClosedRange<Double> = 100...800
        let state = DesktopPetState(x: 300, activity: .curl(until: t0), since: t0)
        let next = DesktopPetBrain.step(state, dt: 0.016, now: t0.addingTimeInterval(0.1), lane: lane,
                                        userIdle: 0, focusing: false, style: .curl, random: { 0.6 })
        guard case .walk(let target) = next.activity else { return XCTFail("挪几步，实际 \(next.activity)") }
        XCTAssertLessThanOrEqual(abs(target - 300), DesktopPetBrain.shuffleRange.upperBound)
        XCTAssertTrue(DesktopPetBrain.isMoving(next, now: t0.addingTimeInterval(0.1)), "走的时候开显示刷新")
    }

    func testCurlSleepsAfterThreeMinutes() {
        let state = DesktopPetBrain.placed(at: 300, style: .curl, now: t0)
        let asleep = DesktopPetBrain.step(state, dt: 0.1, now: t0, lane: 100...800, userIdle: 180, focusing: false,
                                          style: .curl, random: { 0.5 })
        guard case .sleep = asleep.activity else { return XCTFail("3 分钟没操作睡觉") }
        let pose = DesktopPetBrain.pose(asleep, now: t0.addingTimeInterval(8))
        XCTAssertTrue(pose.image.hasPrefix("pet-sprite-sleep-"), "团成一团呼吸，实际 \(pose.image)")
        XCTAssertGreaterThan(pose.zzz, 0, "头顶 Zzz")
        XCTAssertEqual(DesktopPetBrain.tickRate(asleep), DesktopPetBrain.sleepingFPS, "睡着降帧")
        let awake = DesktopPetBrain.step(asleep, dt: 0.1, now: t0.addingTimeInterval(60), lane: 100...800,
                                         userIdle: 1, focusing: false, style: .curl, random: { 0.5 })
        guard case .curl = awake.activity else { return XCTFail("醒来趴回去，实际 \(awake.activity)") }
    }

    func testPointerNearbyMakesItPeekAndLook() {
        let state = DesktopPetBrain.placed(at: 300, style: .curl, now: t0)
        let looking = DesktopPetBrain.step(state, dt: 0.1, now: t0.addingTimeInterval(0.1), lane: 100...800,
                                           userIdle: 0, focusing: false, style: .curl, attention: 200,
                                           random: { 0.5 })
        guard case .peek = looking.activity else { return XCTFail("鼠标靠近探头，实际 \(looking.activity)") }
        XCTAssertTrue(looking.facingLeft, "转向鼠标")
        XCTAssertNotNil(looking.turnedAt, "转身有过渡")
        // 鼠标一直在旁边就一直探着。
        let (still, _) = run(looking, seconds: 6, lane: 100...800, style: .curl, attention: 200, random: { 0.5 })
        guard case .peek = still.activity else { return XCTFail("鼠标在旁边一直探着") }

        // 程序坞上散步的：发呆时转头看鼠标。
        let idle = DesktopPetState(x: 300, activity: .idle(until: t0.addingTimeInterval(5)), since: t0)
        let turned = DesktopPetBrain.step(idle, dt: 0.1, now: t0.addingTimeInterval(0.1), lane: 100...800,
                                          userIdle: 0, focusing: false, attention: 500, random: { 0.5 })
        XCTAssertFalse(turned.facingLeft)
        let back = DesktopPetBrain.step(turned, dt: 0.1, now: t0.addingTimeInterval(0.2), lane: 100...800,
                                        userIdle: 0, focusing: false, attention: 100, random: { 0.5 })
        XCTAssertTrue(back.facingLeft)
    }

    func testSitStaysPut() {
        let state = DesktopPetBrain.placed(at: 640, style: .sit, now: t0)
        let (after, seen) = run(state, seconds: 40, lane: 640...640, style: .sit, random: { 0.3 })
        XCTAssertEqual(after.x, 640)
        XCTAssertFalse(seen.contains { if case .walk = $0 { true } else { false } }, "随意放的不走开")
    }

    // MARK: 拖动、落地、转身、眨眼

    func testDragFlailsThenLandsWithSquash() {
        let state = DesktopPetBrain.placed(at: 300, style: .curl, now: t0)
        var dragged = DesktopPetBrain.grabbed(state, now: t0)
        XCTAssertTrue(DesktopPetBrain.isMoving(dragged, now: t0))
        let a = DesktopPetBrain.pose(dragged, now: t0)
        let b = DesktopPetBrain.pose(dragged, now: t0.addingTimeInterval(0.1))
        XCTAssertTrue(a.image.hasPrefix("pet-sprite-drag-"), "拎着后颈那套帧")
        XCTAssertNotEqual(a.image, b.image, "四脚乱蹬")
        XCTAssertNotEqual(DesktopPetBrain.pose(dragged, now: t0.addingTimeInterval(0.12)).wobble, 0, "晃")
        // 拖着时不睡、不被点。
        XCTAssertEqual(DesktopPetBrain.poked(dragged, now: t0), dragged)
        let still = DesktopPetBrain.step(dragged, dt: 0.1, now: t0.addingTimeInterval(1), lane: 100...800,
                                         userIdle: 999, focusing: true, style: .curl, random: { 0.5 })
        XCTAssertEqual(still.activity, dragged.activity)
        dragged = DesktopPetBrain.dragging(dragged, dx: -10, now: t0)
        XCTAssertTrue(dragged.facingLeft, "往左拖朝左")

        // 转身过渡（0.16 秒）早过了才松手。
        let t1 = t0.addingTimeInterval(1)
        let landed = DesktopPetBrain.landed(dragged, at: 500, now: t1)
        XCTAssertEqual(landed.x, 500)
        let squashed = DesktopPetBrain.pose(landed, now: t1)
        XCTAssertLessThan(squashed.scaleY, 1, "落地压扁")
        XCTAssertGreaterThan(squashed.scaleX, 1)
        XCTAssertEqual(DesktopPetBrain.landSquash(1), 0, accuracy: 0.0001, "回弹到原样")
        XCTAssertLessThan((0...20).map { DesktopPetBrain.landSquash(Double($0) / 20) }.min() ?? 0, 0, "中途拉长一点")
        let settled = DesktopPetBrain.step(landed, dt: 0.1, now: t1.addingTimeInterval(1), lane: 100...800,
                                           userIdle: 0, focusing: false, style: .curl, random: { 0.5 })
        guard case .curl = settled.activity else { return XCTFail("落地后趴下，实际 \(settled.activity)") }
    }

    func testTurnHasShortTransition() {
        var state = DesktopPetState(x: 300, activity: .walk(to: 500), since: t0)
        DesktopPetBrain.turn(&state, left: true, now: t0)
        let mid = DesktopPetBrain.pose(state, now: t0.addingTimeInterval(DesktopPetBrain.turnDuration / 4))
        XCTAssertLessThan(mid.scaleX, 0.9, "转身时横着窄一下")
        let done = DesktopPetBrain.pose(state, now: t0.addingTimeInterval(DesktopPetBrain.turnDuration * 2))
        XCTAssertEqual(done.scaleX, 1, accuracy: 0.0001)
        // 同一个朝向不算转身。
        var same = DesktopPetState(x: 300, facingLeft: true, activity: .walk(to: 100), since: t0)
        DesktopPetBrain.turn(&same, left: true, now: t0)
        XCTAssertNil(same.turnedAt)
    }

    func testBlinkAndStatics() {
        let idle = DesktopPetState(x: 300, activity: .idle(until: t0.addingTimeInterval(10)), since: t0)
        let images = Set((0..<100).map { DesktopPetBrain.pose(idle, now: t0.addingTimeInterval(Double($0) * 0.05)).image })
        XCTAssertTrue(images.contains("pet-sprite-blink-1"), "坐着偶尔眨眼")
        XCTAssertGreaterThan(images.filter { $0.hasPrefix("pet-sprite-sit-") }.count, 4, "坐着慢慢呼吸")
        let looks = Set((0..<220).map { DesktopPetBrain.sittingImage(now: t0.addingTimeInterval(Double($0) * 0.05)) })
        XCTAssertTrue(looks.contains("pet-sprite-lookup-4"), "每 11 秒抬头看一眼")
        XCTAssertFalse(DesktopPetBrain.isMoving(idle, now: t0))
        let droop = DesktopPetBrain.droop(idle, now: t0)
        XCTAssertEqual(DesktopPetBrain.pose(droop, now: t0).image, "pet-sprite-droop-1", "电量低蔫蔫的")
        let yawn = DesktopPetState(x: 300, activity: .yawn(since: t0), since: t0)
        XCTAssertEqual(DesktopPetBrain.pose(yawn, now: t0).image, "pet-sprite-yawn-1")
        XCTAssertEqual(DesktopPetBrain.pose(yawn, now: t0.addingTimeInterval(DesktopPetBrain.yawnDuration * 0.99)).image,
                       "pet-sprite-yawn-8")
        let stretch = DesktopPetState(x: 300, activity: .stretch(since: t0), since: t0)
        XCTAssertEqual(DesktopPetBrain.pose(stretch, now: t0.addingTimeInterval(0.8)).image, "pet-sprite-stretch-5")
        let peek = DesktopPetState(x: 300, activity: .peek(until: t0.addingTimeInterval(3)), since: t0)
        XCTAssertEqual(DesktopPetBrain.pose(peek, now: t0.addingTimeInterval(1)).image, "pet-sprite-peek-4", "抬头停住")
        XCTAssertEqual(DesktopPetBrain.pose(peek, now: t0.addingTimeInterval(2.9)).image, "pet-sprite-peek-6", "趴回去")
        let dragged = DesktopPetState(x: 300, activity: .dragged(since: t0), since: t0)
        XCTAssertTrue(DesktopPetBrain.pose(dragged, now: t0.addingTimeInterval(0.25)).image.hasPrefix("pet-sprite-drag-"))
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Pet")
        for name in ["pet-panda-idle", "pet-panda-rest", "pet-panda-cheer", "pet-panda-hungry"] {
            XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(name + ".png").path), name)
        }
    }

    func testPluggedTurnsTowardNotchAndJumps() {
        let state = DesktopPetState(x: 300, activity: .idle(until: t0.addingTimeInterval(10)), since: t0)
        let reacted = DesktopPetBrain.plugged(state, toward: 100, now: t0)
        guard case .jump = reacted.activity else { return XCTFail("插电跳一下") }
        XCTAssertTrue(reacted.facingLeft, "看向刘海那边")
    }

    // MARK: 头顶气泡

    private func focusing(left: TimeInterval, total: TimeInterval = 1500, now: Date) -> TimerState {
        var state = TimerState()
        state.duration = total
        state.deadline = now.addingTimeInterval(left)
        return state
    }

    func testFocusNews() {
        let idle = TimerState()
        let started = focusing(left: 1500, now: t0)
        XCTAssertEqual(DesktopPetNewsDesk.focus(from: idle, at: t0, to: started, at: t0), .focusStarted(minutes: 25))
        XCTAssertEqual(DesktopPetNews.focusStarted(minutes: 25).text, "开始专注 · 25 分钟")
        // 还剩 5 分钟：跨过那一刻才说一次。
        let before = focusing(left: 301, now: t0)
        let after = before
        XCTAssertEqual(DesktopPetNewsDesk.focus(from: before, at: t0, to: after, at: t0.addingTimeInterval(2)),
                       .focusFiveLeft)
        XCTAssertNil(DesktopPetNewsDesk.focus(from: after, at: t0.addingTimeInterval(2), to: after,
                                              at: t0.addingTimeInterval(4)))
        // 短专注不说还剩 5 分钟。
        let short = focusing(left: 301, total: 400, now: t0)
        XCTAssertNil(DesktopPetNewsDesk.focus(from: short, at: t0, to: short, at: t0.addingTimeInterval(2)))
        // 完成一轮。
        let ending = focusing(left: 0, now: t0)
        if let next = FocusCycle.advanced(ending, now: t0.addingTimeInterval(1)) {
            XCTAssertEqual(DesktopPetNewsDesk.focus(from: ending, at: t0, to: next, at: t0.addingTimeInterval(1)),
                           .focusDone)
        }
        // 暂停再继续不算开始。
        var paused = started
        paused.deadline = nil
        paused.paused = 900
        let resumed = focusing(left: 900, now: t0)
        XCTAssertNil(DesktopPetNewsDesk.focus(from: paused, at: t0, to: resumed, at: t0))
    }

    func testBatteryNews() {
        XCTAssertNil(DesktopPetNewsDesk.battery(from: nil, to: DesktopPetPower(onPower: true, percent: 50)),
                     "第一次读不说")
        XCTAssertEqual(DesktopPetNewsDesk.battery(from: DesktopPetPower(onPower: false, percent: 62),
                                                  to: DesktopPetPower(onPower: true, percent: 62)),
                       .plugged(percent: 62))
        XCTAssertEqual(DesktopPetNews.plugged(percent: 62).text, "充电中 · 62%")
        XCTAssertEqual(DesktopPetNewsDesk.battery(from: DesktopPetPower(onPower: true, percent: 99),
                                                  to: DesktopPetPower(onPower: true, percent: 100)), .charged)
        XCTAssertEqual(DesktopPetNewsDesk.battery(from: DesktopPetPower(onPower: false, percent: 21),
                                                  to: DesktopPetPower(onPower: false, percent: 20)),
                       .lowBattery(percent: 20))
        XCTAssertEqual(DesktopPetNewsDesk.battery(from: DesktopPetPower(onPower: true, percent: 15),
                                                  to: DesktopPetPower(onPower: false, percent: 15)),
                       .lowBattery(percent: 15), "拔掉电源时已经低电量")
        XCTAssertNil(DesktopPetNewsDesk.battery(from: DesktopPetPower(onPower: false, percent: 18),
                                                to: DesktopPetPower(onPower: false, percent: 17)), "只说一次")
    }

    func testRadioNewsAndGate() {
        XCTAssertEqual(DesktopPetNewsDesk.radio(wasPlaying: false, oldStation: nil, playing: true, station: "中国之声"),
                       .radio("中国之声"))
        XCTAssertEqual(DesktopPetNews.radio("中国之声").text, "正在播放 · 中国之声")
        XCTAssertEqual(DesktopPetNewsDesk.radio(wasPlaying: true, oldStation: "A", playing: true, station: "B"),
                       .radio("B"), "换台")
        XCTAssertNil(DesktopPetNewsDesk.radio(wasPlaying: true, oldStation: "A", playing: true, station: "A"))
        XCTAssertNil(DesktopPetNewsDesk.radio(wasPlaying: true, oldStation: "A", playing: false, station: "A"))

        var gate = DesktopPetBubbleGate()
        XCTAssertTrue(gate.allow("power", now: t0))
        XCTAssertFalse(gate.allow("power", now: t0.addingTimeInterval(10)), "同一类 30 秒内只说一次")
        XCTAssertTrue(gate.allow("radio", now: t0.addingTimeInterval(10)), "不同类不挡")
        XCTAssertTrue(gate.allow("power", now: t0.addingTimeInterval(31)))
        XCTAssertEqual(DesktopPetNews.plugged(percent: 1).kind, DesktopPetNews.charged.kind)
    }

    // MARK: 快捷条

    func testQuickBarHitAndFocusToggle() {
        let size = DesktopPetQuickAction.barSize
        XCTAssertEqual(DesktopPetQuickAction.allCases.count, 4)
        XCTAssertGreaterThanOrEqual(DesktopPetQuickAction.buttonSize.width, 40, "点击区够大")
        XCTAssertEqual(DesktopPetQuickAction.at(x: 10, width: Double(size.width)), .todo)
        XCTAssertEqual(DesktopPetQuickAction.at(x: Double(size.width) - 10, width: Double(size.width)), .expand)
        XCTAssertNil(DesktopPetQuickAction.at(x: 1, width: Double(size.width)), "边上的内边距不算")
        XCTAssertEqual(DesktopPetQuickAction.focus.title(focusRunning: true, radioPlaying: false), "暂停专注")

        var timer = TimerState()
        timer = DesktopPetQuickAction.toggledFocus(timer, now: t0)
        XCTAssertTrue(DesktopPetQuickAction.focusRunning(timer), "开始")
        XCTAssertEqual(timer.deadline, t0.addingTimeInterval(Double(timer.minutes * 60)))
        timer = DesktopPetQuickAction.toggledFocus(timer, now: t0.addingTimeInterval(60))
        XCTAssertFalse(DesktopPetQuickAction.focusRunning(timer), "暂停")
        XCTAssertEqual(timer.paused ?? 0, Double(timer.minutes * 60) - 60, accuracy: 0.001)
        timer = DesktopPetQuickAction.toggledFocus(timer, now: t0.addingTimeInterval(600))
        XCTAssertEqual(timer.deadline, t0.addingTimeInterval(600 + Double(timer.minutes * 60) - 60), "从剩下的接着走")
    }

    func testWalkFramesFollowDistanceNotTime() {
        let step = DesktopPetBrain.walkStep
        let frames = (0..<40).map { DesktopPetBrain.walkFrame(x: 400 + Double($0) * step + step / 2) }
        for (a, b) in zip(frames, frames.dropFirst()) {
            XCTAssertEqual((b - a + 32) % 32, 1, "每走一步换下一张，32 张后接回第一张")
        }
        // 放大时步子跟着放大：同样的距离，两倍大只换了一半的帧。
        XCTAssertEqual(DesktopPetBrain.walkFrame(x: step * 10 + 0.01, scale: 1), 10)
        XCTAssertEqual(DesktopPetBrain.walkFrame(x: step * 10 + 0.01, scale: 2), 5)
        // 站着不动（时间在走、位置没变）就不换帧；身体起伏画在帧里，不另外颠。
        let state = DesktopPetState(x: 300, activity: .walk(to: 500), since: t0)
        let early = DesktopPetBrain.pose(state, now: t0)
        let later = DesktopPetBrain.pose(state, now: t0.addingTimeInterval(1.3))
        XCTAssertEqual(early.image, later.image)
        XCTAssertEqual(early.lift, 0)
    }
}
