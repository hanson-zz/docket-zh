import Foundation
import XCTest

/// 左右边抱树（爬出、5 秒缩回、打盹、爬边不越界、抖耳）、程序坞闲置轮换、作息、连戳和摸头。
final class DesktopPetHugTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let lane: ClosedRange<Double> = 100...800

    private func step(_ state: DesktopPetState, at seconds: Double, dt: Double = 0.1, quiet: Double = 0,
                      touchQuiet: Double = 0, idle: Double = 0, night: Bool = false, style: DesktopPetStyle = .side,
                      random: Double = 0.5) -> DesktopPetState {
        DesktopPetBrain.step(state, dt: dt, now: t0.addingTimeInterval(seconds), lane: lane, userIdle: idle,
                             focusing: false, style: style, hangQuiet: quiet, touchQuiet: touchQuiet,
                             night: night, random: { random })
    }

    func testHugRestsWithHeadAndPawsShowing() throws {
        let resting = DesktopPetBrain.placed(at: 300, style: .side, now: t0)
        guard case .curl = resting.activity else { return XCTFail("平时抱着") }
        let left = DesktopPetBrain.pose(resting, now: t0, style: .side, edge: .left)
        XCTAssertTrue(left.image.hasPrefix("pet-sprite-hug-"), left.image)
        XCTAssertFalse(left.image.contains("-r-"))
        XCTAssertEqual(left.reveal, 1 - DesktopPetHug.leftEdgeLine, accuracy: 0.0001)
        let right = DesktopPetBrain.pose(resting, now: t0, style: .side, edge: .right)
        XCTAssertTrue(right.image.hasPrefix("pet-sprite-hug-r-"), "右边单独一套，实际 \(right.image)")
        XCTAssertEqual(right.reveal, DesktopPetHug.rightEdgeLine, accuracy: 0.0001)
        // 屏幕边那条线对齐屏幕边：左边图左端在屏幕外 edgeLine 那么多。
        let track = try XCTUnwrap(DesktopPetTracks.edge(.left, visible: CGRect(x: 0, y: 70, width: 1512, height: 879),
                                                        length: 56, spot: nil))
        let feet = track.peekFeet(along: 300, width: 100, reveal: left.reveal)
        XCTAssertEqual(feet.x - 50, -100 * DesktopPetHug.leftEdgeLine, accuracy: 0.0001)
        // 呼吸为主，偶尔眨眼抖耳，节奏不固定。
        let frames = (0..<3000).map { DesktopPetHug.idleFrame(time: 1000 + Double($0) * 0.05) }
        XCTAssertEqual(Set(frames), [0, 1, 2, 3])
        XCTAssertGreaterThan(frames.filter { $0 < 2 }.count, frames.count * 8 / 10, "大部分时间在呼吸")
        var gaps: [Int] = []
        var lastBlink: Int?
        for (i, f) in frames.enumerated() where f == 2 {
            if let lastBlink, i - lastBlink > 2 { gaps.append(i - lastBlink) }
            lastBlink = i
        }
        XCTAssertGreaterThan(Set(gaps).count, 1, "眨眼间隔不一样")
    }

    func testTapClimbsOutThenRetractsAfterFiveQuietSeconds() {
        let resting = DesktopPetBrain.placed(at: 300, style: .side, now: t0)
        let out = DesktopPetBrain.hugTapped(resting, now: t0)
        XCTAssertEqual(out.activity, .hugOut(since: t0))
        XCTAssertFalse(DesktopPetBrain.hugIsOut(out, now: t0.addingTimeInterval(0.3)), "还在爬")
        XCTAssertTrue(DesktopPetBrain.hugIsOut(out, now: t0.addingTimeInterval(DesktopPetHug.outDuration)))
        XCTAssertEqual(DesktopPetBrain.pose(out, now: t0, style: .side).image, "pet-sprite-hug-out-1")
        XCTAssertEqual(DesktopPetBrain.pose(out, now: t0.addingTimeInterval(0.8), style: .side).image,
                       "pet-sprite-hug-out-6", "最后挥手")
        XCTAssertEqual(DesktopPetBrain.pose(out, now: t0.addingTimeInterval(3), style: .side).image,
                       "pet-sprite-hug-out-5", "露全身待着")
        // 有人理（鼠标在上面）就一直露着；没人理满 5 秒缩回。
        XCTAssertEqual(step(out, at: 6, touchQuiet: 1).activity, out.activity)
        XCTAssertEqual(step(out, at: 6, touchQuiet: 4.9).activity, out.activity)
        let back = step(out, at: 6, touchQuiet: DesktopPetHug.retractAfter)
        XCTAssertEqual(back.activity, .hugIn(since: t0.addingTimeInterval(6)))
        XCTAssertEqual(DesktopPetBrain.pose(back, now: t0.addingTimeInterval(6), style: .side).image,
                       "pet-sprite-hug-out-5", "倒放从露全身开始")
        let hugging = step(back, at: 6.7)
        guard case .curl = hugging.activity else { return XCTFail("缩回抱着，实际 \(hugging.activity)") }
        // 露着再点：挥一下手，不再爬。
        let wave = DesktopPetBrain.hugTapped(out, now: t0.addingTimeInterval(4))
        XCTAssertEqual(DesktopPetBrain.pose(wave, now: t0.addingTimeInterval(4), style: .side).image, "pet-sprite-hug-out-6")
        // 拖到左右边吸上去：hug-out 倒放。
        XCTAssertEqual(DesktopPetBrain.landed(resting, at: 400, now: t0, style: .side).activity, .hugIn(since: t0))
        // 状态助手来了事：先爬出来。
        XCTAssertEqual(DesktopPetBrain.noticed(resting, style: .side, now: t0).activity, .hugOut(since: t0))
        XCTAssertEqual(DesktopPetBrain.wokeUp(resting, style: .side, now: t0).activity, .hugOut(since: t0))
        // 欢呼完缩回去。
        let cheering = DesktopPetBrain.cheer(resting, now: t0)
        XCTAssertTrue(DesktopPetBrain.pose(cheering, now: t0.addingTimeInterval(1), style: .side).image
            .hasPrefix("pet-sprite-hug-out-"))
        XCTAssertEqual(step(cheering, at: 10).activity, .hugIn(since: t0.addingTimeInterval(10)))
    }

    func testDozesAfterTwentyQuietSecondsAndWakesWhenPointerNear() {
        let resting = DesktopPetState(x: 300, activity: .curl(until: t0.addingTimeInterval(80)), since: t0)
        guard case .curl = step(resting, at: 19, quiet: 19).activity else { return XCTFail("还没到 20 秒") }
        let asleep = step(resting, at: 20, quiet: 20)
        XCTAssertEqual(asleep.activity, .sleep(since: t0.addingTimeInterval(20)))
        let pose = DesktopPetBrain.pose(asleep, now: t0.addingTimeInterval(23), style: .side, edge: .right)
        XCTAssertTrue(pose.image.hasPrefix("pet-sprite-hug-sleep-r-"), pose.image)
        XCTAssertGreaterThan(pose.zzz, 0)
        // 鼠标靠近（quiet 归零）就醒，接着抱着。
        guard case .curl = step(asleep, at: 30, quiet: 0).activity else { return XCTFail("醒来抱着") }
        // 没人理：打个盹醒来换个高度。
        let nap = DesktopPetHug.napLength(since: t0.addingTimeInterval(20))
        XCTAssertTrue(DesktopPetHug.climbEvery.contains(nap))
        guard case .hugClimb = step(asleep, at: 20 + nap + 0.1, quiet: 200).activity else { return XCTFail("盹醒了爬一段") }
        // 用户离开了（3 分钟没操作）就一直睡。
        guard case .sleep = step(asleep, at: 20 + nap + 0.1, quiet: 200, idle: 999).activity else { return XCTFail() }
    }

    func testClimbsAlongTheEdgeWithinTheLane() {
        for (x, roll) in [(300.0, 0.2), (300, 0.8), (102, 0.9), (798, 0.1), (100, 0.4), (800, 0.6)] {
            let due = DesktopPetState(x: x, activity: .curl(until: t0), since: t0)
            var state = step(due, at: 0.1, random: roll)
            guard case .hugClimb(let target) = state.activity else { return XCTFail("到点爬一段，实际 \(state.activity)") }
            XCTAssertTrue(lane.contains(target), "不越出可见区域上下边")
            XCTAssertLessThanOrEqual(abs(target - x), DesktopPetHug.climbRange.upperBound)
            XCTAssertTrue(DesktopPetBrain.isMoving(state, now: t0))
            var t = 0.1
            for _ in 0..<600 {
                t += 1 / 60
                state = step(state, at: t, dt: 1 / 60, random: roll)
                XCTAssertTrue(lane.contains(state.x))
                if case .hugClimb = state.activity {} else { break }
            }
            XCTAssertEqual(state.x, target, accuracy: 0.001)
            guard case .curl(let until) = state.activity else { return XCTFail("爬完接着抱着") }
            XCTAssertTrue((30.0...90).contains(until.timeIntervalSince(t0.addingTimeInterval(t))), "30～90 秒后再爬")
        }
        // 往上爬正放，往下倒放。
        let up = DesktopPetState(x: 300, activity: .hugClimb(to: 350), since: t0)
        let down = DesktopPetState(x: 300, activity: .hugClimb(to: 250), since: t0)
        XCTAssertEqual(DesktopPetBrain.pose(up, now: t0, style: .side).image, "pet-sprite-hug-climb-1")
        XCTAssertEqual(DesktopPetBrain.pose(down, now: t0, style: .side).image, "pet-sprite-hug-climb-4")
    }

    func testEarFlickNearHeadWithCooldown() {
        var mood = DesktopPetMood()
        XCTAssertFalse(mood.neared(distance: 100, now: t0))
        XCTAssertTrue(mood.neared(distance: 50, now: t0.addingTimeInterval(1)))
        XCTAssertFalse(mood.neared(distance: 40, now: t0.addingTimeInterval(2)), "一直在旁边不重复")
        XCTAssertFalse(mood.neared(distance: 100, now: t0.addingTimeInterval(3)))
        XCTAssertFalse(mood.neared(distance: 50, now: t0.addingTimeInterval(5)), "冷却中")
        XCTAssertFalse(mood.neared(distance: 100, now: t0.addingTimeInterval(13)))
        XCTAssertTrue(mood.neared(distance: 50, now: t0.addingTimeInterval(14)))
        let resting = DesktopPetState(x: 300, activity: .curl(until: t0.addingTimeInterval(60)), since: t0)
        let flick = DesktopPetBrain.earFlicked(resting, now: t0)
        XCTAssertEqual(DesktopPetBrain.pose(flick, now: t0, style: .side).image, "pet-sprite-hug-4")
        guard case .curl = step(flick, at: 1).activity else { return XCTFail("抖完接着抱着") }
    }

    // MARK: 程序坞闲置

    func testDockIdleRotatesWithoutRepeating() {
        XCTAssertEqual(DesktopPetIdleAct.pick(after: nil, roll: 0.1), .lie, "以趴着为主")
        XCTAssertGreaterThan(DesktopPetIdleAct.lie.weight, DesktopPetIdleAct.allCases.filter { $0 != .lie }
            .map(\.weight).max() ?? 1)
        for last in DesktopPetIdleAct.allCases {
            for i in 0...20 {
                XCTAssertNotEqual(DesktopPetIdleAct.pick(after: last, roll: Double(i) / 20), last)
            }
        }
        // 一路走下来不连续重复，几种都出现，时长不一。
        var state = DesktopPetState(x: 400, activity: .idle(until: t0), since: t0)
        var acts: [DesktopPetIdleAct] = []
        let rolls = [0.13, 0.71, 0.42, 0.95, 0.05, 0.6, 0.33, 0.88, 0.2, 0.5, 0.77, 0.1]
        var i = 0
        var t = 0.0
        var prevSince = state.since
        var prevActivity = state.activity
        while t < 600 {
            t += 0.25
            state = DesktopPetBrain.step(state, dt: 0.25, now: t0.addingTimeInterval(t), lane: lane, userIdle: 0,
                                         focusing: false, random: {
                                             i += 1
                                             return rolls[i % rolls.count]
                                         })
            if state.since != prevSince, let act = state.lastIdle {
                var pause = false
                if case .edgePause = state.activity { pause = true }
                if case .edgePause = prevActivity { pause = true }
                if !pause { acts.append(act) }
            }
            prevSince = state.since
            prevActivity = state.activity
        }
        XCTAssertGreaterThan(acts.count, 10)
        for (a, b) in zip(acts, acts.dropFirst()) {
            XCTAssertNotEqual(a, b, "\(acts)")
        }
        XCTAssertGreaterThanOrEqual(Set(acts).count, 4, "\(acts)")
    }

    func testPassingPointerGlancesWithCooldown() {
        var mood = DesktopPetMood()
        XCTAssertFalse(mood.passedBy(distance: 120, speed: 300, now: t0), "太远")
        XCTAssertFalse(mood.passedBy(distance: 50, speed: 5, now: t0), "没在动")
        XCTAssertTrue(mood.passedBy(distance: 50, speed: 300, now: t0))
        XCTAssertFalse(mood.passedBy(distance: 50, speed: 300, now: t0.addingTimeInterval(19)), "冷却 20 秒")
        XCTAssertTrue(mood.passedBy(distance: 50, speed: 300, now: t0.addingTimeInterval(20)))
        let lying = DesktopPetState(x: 300, activity: .curl(until: t0.addingTimeInterval(9)), since: t0)
        let look = DesktopPetBrain.glanced(lying, now: t0)
        XCTAssertTrue(DesktopPetBrain.pose(look, now: t0.addingTimeInterval(0.5), style: .stroll).image
            .hasPrefix("pet-sprite-lookup-"))
        let walking = DesktopPetState(x: 300, activity: .walk(to: 400), since: t0)
        XCTAssertEqual(DesktopPetBrain.glanced(walking, now: t0), walking, "走着不打断")
    }

    // MARK: 作息

    func testSleepsFasterAtNightAndGreetsOncePerDay() {
        XCTAssertTrue(DesktopPetRhythm.isNight(hour: 23))
        XCTAssertTrue(DesktopPetRhythm.isNight(hour: 3))
        XCTAssertFalse(DesktopPetRhythm.isNight(hour: 6))
        XCTAssertFalse(DesktopPetRhythm.isNight(hour: 22))
        XCTAssertEqual(DesktopPetRhythm.sleepAfter(night: true), DesktopPetBrain.sleepAfter / 2)
        XCTAssertEqual(DesktopPetRhythm.dozeAfter(night: true), DesktopPetHang.dozeAfter / 2)
        let sitting = DesktopPetState(x: 300, activity: .idle(until: t0.addingTimeInterval(9)), since: t0)
        guard case .idle = step(sitting, at: 1, idle: 100, style: .stroll).activity else { return XCTFail("白天还不睡") }
        guard case .sleep = step(sitting, at: 1, idle: 100, night: true, style: .stroll).activity else {
            return XCTFail("夜里入睡快一半")
        }
        let hanging = DesktopPetState(x: 300, activity: .curl(until: t0.addingTimeInterval(9)), since: t0)
        guard case .sleep = step(hanging, at: 1, quiet: 10, night: true, style: .hang).activity else {
            return XCTFail("吊着夜里 10 秒就打盹")
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let morning = calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 8))!
        let lateNight = calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 1))!
        XCTAssertEqual(DesktopPetRhythm.greetingDay(morning, calendar: calendar), "2026-11-12")
        XCTAssertEqual(DesktopPetRhythm.greetingDay(lateNight, calendar: calendar), "2026-11-11", "熬夜过 0 点不算新的一天")
        XCTAssertTrue(DesktopPetRhythm.shouldGreet(lastDay: "2026-11-11", now: morning, calendar: calendar))
        XCTAssertFalse(DesktopPetRhythm.shouldGreet(lastDay: "2026-11-12", now: morning, calendar: calendar))
        XCTAssertEqual(DesktopPetRhythm.morningText, "早")
        XCTAssertEqual(DesktopPetBrain.greeted(sitting, style: .stroll, now: t0).activity, .stretch(since: t0), "先伸懒腰")
        XCTAssertEqual(DesktopPetBrain.greeted(sitting, style: .side, now: t0).activity, .hugOut(since: t0))
    }

    // MARK: 连戳、摸头

    func testThreePokesInTenSecondsDroop() {
        var mood = DesktopPetMood()
        XCTAssertFalse(mood.clicked(now: t0))
        XCTAssertFalse(mood.clicked(now: t0.addingTimeInterval(4)))
        XCTAssertTrue(mood.clicked(now: t0.addingTimeInterval(8)), "10 秒内第 3 次")
        XCTAssertFalse(mood.clicked(now: t0.addingTimeInterval(9)), "重新数")
        XCTAssertFalse(mood.clicked(now: t0.addingTimeInterval(25)))
        XCTAssertFalse(mood.clicked(now: t0.addingTimeInterval(36)), "隔太久不算")
        let sitting = DesktopPetState(x: 300, activity: .idle(until: t0.addingTimeInterval(9)), since: t0)
        let sulk = DesktopPetBrain.sulked(sitting, now: t0)
        XCTAssertEqual(sulk.activity, .droop(until: t0.addingTimeInterval(DesktopPetMood.sulkDuration)))
        XCTAssertTrue(DesktopPetBrain.pose(sulk, now: t0, style: .stroll).image.hasPrefix("pet-sprite-droop-"))
        XCTAssertTrue(DesktopPetBrain.pose(sulk, now: t0, style: .side).image.hasPrefix("pet-sprite-hug-sleep-"))
        guard case .idle = step(sulk, at: 3.1, style: .stroll).activity else { return XCTFail("约 3 秒后恢复") }
    }

    func testRubbingHeadCheersWithCooldown() {
        var mood = DesktopPetMood()
        var t = 0.0
        func rub(_ xs: [Double], pressed: Bool = false) -> Bool {
            var hit = false
            for x in xs {
                t += 0.1
                if mood.rubbed(x: x, pressed: pressed, now: t0.addingTimeInterval(t)) { hit = true }
            }
            return hit
        }
        XCTAssertFalse(rub([100, 110, 120, 130]), "单向划过不算")
        XCTAssertFalse(rub([120, 110, 120, 110], pressed: true), "按着键不算")
        XCTAssertTrue(rub([100, 110, 100, 110, 100]), "来回划 3 次方向变化")
        XCTAssertFalse(rub([110, 100, 110, 100, 110]), "冷却 30 秒")
        t += 30
        XCTAssertFalse(rub([100, 101, 100, 101, 100]), "小抖动不算")
        XCTAssertTrue(rub([100, 110, 100, 110, 100]))
        _ = mood.rubbed(x: nil, pressed: false, now: t0)
        XCTAssertTrue(mood.turns.isEmpty, "离开就重来")

        let sitting = DesktopPetState(x: 300, activity: .idle(until: t0.addingTimeInterval(9)), since: t0)
        XCTAssertEqual(DesktopPetBrain.petted(sitting, style: .stroll, now: t0).activity,
                       .cheer(until: t0.addingTimeInterval(DesktopPetBrain.cheerDuration)))
        XCTAssertEqual(DesktopPetBrain.petted(sitting, style: .side, now: t0).activity, .hugOut(since: t0), "抱树的爬出来挥手")
    }
}
