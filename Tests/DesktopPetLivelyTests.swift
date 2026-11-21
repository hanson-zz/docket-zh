import XCTest

final class DesktopPetLivelyTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    // MARK: 呼吸

    func testBreathIsGentleAndPeriodic() {
        var low = 1.0, high = -1.0
        for i in 0..<400 {
            let time = Double(i) * 0.05
            let b = DesktopPetLively.breath(time: time)
            XCTAssertLessThanOrEqual(abs(b), 1)
            XCTAssertEqual(b, DesktopPetLively.breath(time: time + DesktopPetLively.breathPeriod), accuracy: 1e-9,
                           "一个周期后接得上")
            low = min(low, b)
            high = max(high, b)
        }
        XCTAssertGreaterThan(high, 0.8, "真的在起伏")
        XCTAssertLessThan(low, -0.8)
        let scale = DesktopPetLively.breathScale(time: 1.234)
        XCTAssertEqual(scale.y, 1, accuracy: 0.02, "幅度不到 2%")
        XCTAssertEqual(scale.x, 1, accuracy: 0.01)
    }

    func testBreathOnlyWhenRestingAndMotionAllowed() {
        let idle = DesktopPetState(x: 300, activity: .idle(until: t0.addingTimeInterval(9)), since: t0)
        let pose = DesktopPetPose(image: "pet-sprite-front-sit-1")
        // 找一个呼吸不在中线的时刻。
        let now = t0.addingTimeInterval(0.4)
        let breathing = DesktopPetLively.decorate(pose, state: idle, now: now, style: .sit, motion: .full)
        let expected = DesktopPetLively.breathScale(time: now.timeIntervalSinceReferenceDate)
        XCTAssertEqual(breathing.scaleY, expected.y, accuracy: 1e-9)

        let reduced = DesktopPetLively.decorate(pose, state: idle, now: now, style: .sit, motion: .reduced)
        XCTAssertEqual(reduced.scaleY, 1, "减弱动态效果不呼吸")

        let hanging = DesktopPetLively.decorate(pose, state: idle, now: now, style: .hang, motion: .full)
        XCTAssertEqual(hanging, pose, "吊着的有自己的晃法")

        let walking = DesktopPetState(x: 300, activity: .walk(to: 500), since: t0)
        XCTAssertEqual(DesktopPetLively.decorate(pose, state: walking, now: now, style: .sit, motion: .full), pose)

        XCTAssertTrue(DesktopPetLively.breathes(.sit), "专注陪着也呼吸")
        XCTAssertFalse(DesktopPetLively.fidgets(.sit), "专注陪着不做小动作")
        XCTAssertTrue(DesktopPetLively.fidgets(.idle(until: t0)))
        XCTAssertFalse(DesktopPetLively.breathes(.sleep(since: t0)))
    }

    // MARK: 小动作排期

    func testScheduleIsDeterministicAndFitsInSlot() {
        var count = 0
        var kinds = Set<DesktopPetFidget>()
        for index in Int64(1_000)..<Int64(1_400) {
            let a = DesktopPetLively.scheduled(slot: index)
            let b = DesktopPetLively.scheduled(slot: index)
            XCTAssertEqual(a?.fidget, b?.fidget, "同一槽算几次都一样")
            XCTAssertEqual(a?.start, b?.start)
            guard let a else { continue }
            count += 1
            kinds.insert(a.fidget)
            let slotStart = Double(index) * DesktopPetLively.slot
            XCTAssertGreaterThanOrEqual(a.start, slotStart)
            XCTAssertLessThanOrEqual(a.start + a.fidget.duration, slotStart + DesktopPetLively.slot + 1e-9,
                                     "整段在槽里")
        }
        XCTAssertGreaterThan(count, 120, "大约一半的槽有小动作")
        XCTAssertLessThan(count, 280)
        XCTAssertEqual(kinds, Set(DesktopPetFidget.allCases), "每种都会出现")
    }

    func testPickFollowsWeights() {
        XCTAssertEqual(DesktopPetLively.pick(roll: 0), .look)
        XCTAssertEqual(DesktopPetLively.pick(roll: 1), .wiggle)
        XCTAssertEqual(DesktopPetFidget.allCases.reduce(0) { $0 + $1.weight }, 1, accuracy: 1e-9)
        XCTAssertEqual(DesktopPetFidget.allCases.count, 5)
        XCTAssertTrue(DesktopPetFidget.look.calm)
        XCTAssertFalse(DesktopPetFidget.hop.calm)
    }

    /// 找一段有某个小动作的槽，返回它的开始时刻。
    private func firstSlot(with fidget: DesktopPetFidget) -> Double? {
        for index in Int64(1_000)..<Int64(3_000) {
            if let planned = DesktopPetLively.scheduled(slot: index), planned.fidget == fidget { return planned.start }
        }
        return nil
    }

    func testFidgetWaitsAfterSettlingAndRespectsReducedMotion() throws {
        let start = try XCTUnwrap(firstSlot(with: .hop))
        let mid = start + DesktopPetFidget.hop.duration / 2
        let found = try XCTUnwrap(DesktopPetLively.fidget(at: mid, since: start - 5))
        XCTAssertEqual(found.fidget, .hop)
        XCTAssertEqual(found.progress, 0.5, accuracy: 1e-9)
        XCTAssertNil(DesktopPetLively.fidget(at: mid, since: start - 0.2), "刚坐下先安静一会儿")
        XCTAssertNil(DesktopPetLively.fidget(at: mid, since: start - 5, motion: .reduced), "减弱动态效果不跳")

        let look = try XCTUnwrap(firstSlot(with: .look))
        let still = DesktopPetLively.fidget(at: look + 0.1, since: look - 5, motion: .reduced)
        XCTAssertEqual(still?.fidget, .look, "张望只换朝向，减弱时也留着")
    }

    func testHopLiftsAndLookTurnsAround() throws {
        let hop = try XCTUnwrap(firstSlot(with: .hop))
        let state = DesktopPetState(x: 300, activity: .idle(until: Date(timeIntervalSinceReferenceDate: hop + 60)),
                                    since: Date(timeIntervalSinceReferenceDate: hop - 5))
        let base = DesktopPetPose(image: "pet-sprite-front-sit-1")
        let top = Date(timeIntervalSinceReferenceDate: hop + DesktopPetFidget.hop.duration / 2)
        let up = DesktopPetLively.decorate(base, state: state, now: top, style: .sit, motion: .full)
        XCTAssertEqual(up.lift, DesktopPetLively.hopHeight, accuracy: 0.01, "跳到最高")
        XCTAssertTrue(DesktopPetLively.needsSmooth(state, now: top, style: .sit, motion: .full), "跳的时候画顺")
        XCTAssertFalse(DesktopPetLively.needsSmooth(state, now: top, style: .sit, motion: .reduced))
        XCTAssertEqual(DesktopPetLively.hopLift(0), 0)
        XCTAssertEqual(DesktopPetLively.hopLift(1), 0)
        XCTAssertGreaterThan(DesktopPetLively.hopSquash(0.1), 0, "起跳先蹲")

        let look = try XCTUnwrap(firstSlot(with: .look))
        let looking = DesktopPetState(x: 300, activity: .idle(until: Date(timeIntervalSinceReferenceDate: look + 60)),
                                      since: Date(timeIntervalSinceReferenceDate: look - 5))
        let side = DesktopPetPose(image: "pet-sprite-sit-1", facingLeft: false)
        let other = DesktopPetLively.decorate(side, state: looking,
                                              now: Date(timeIntervalSinceReferenceDate: look + 0.5 * 1.8),
                                              style: .stroll, motion: .reduced)
        XCTAssertTrue(other.facingLeft, "中段看另一边")
        XCTAssertEqual(other.wobble, 0, "减弱时不转")
    }

    func testWiggleSwapsToCheerFramesForBothViews() {
        var front = DesktopPetPose(image: "pet-sprite-front-sit-1")
        DesktopPetLively.apply(.wiggle, progress: 0.3, to: &front, motion: .reduced)
        XCTAssertTrue(front.image.hasPrefix("pet-sprite-front-wave-"))
        var side = DesktopPetPose(image: "pet-sprite-sit-3")
        DesktopPetLively.apply(.wiggle, progress: 0.99, to: &side, motion: .full)
        XCTAssertTrue(side.image.hasPrefix("pet-sprite-cheer-"))
        XCTAssertEqual(DesktopPetSkin.action(forPandaImage: side.image), .cheer, "别的吉祥物换成欢呼那张")
    }

    // MARK: 随意放的附近走走

    func testWanderLaneIsCenteredOnHomeAndStaysOnScreen() {
        let lane = DesktopPetLively.wanderLane(home: 500, radius: 60, bounds: 100...1000)
        XCTAssertEqual(lane, 440...560)
        let nearEdge = DesktopPetLively.wanderLane(home: 120, radius: 60, bounds: 100...1000)
        XCTAssertEqual(nearEdge, 100...140, "贴近屏幕边时两边一起收窄，中点还是原处")
        XCTAssertEqual(DesktopPetLively.wanderRadius(length: 10), 40)

        XCTAssertNil(DesktopPetLively.wanderTarget(from: 120, lane: 115...125, random: { 0.5 }), "太窄不走")
        XCTAssertEqual(DesktopPetLively.wanderTarget(from: 470, lane: 440...560, random: { 0.9 }), 500, "走开了就回原处")
        let away = DesktopPetLively.wanderTarget(from: 500, lane: 440...560, random: { 0.9 })
        XCTAssertNotNil(away)
        XCTAssertTrue((440...560).contains(away ?? 0))
    }

    func testFreeTrackHasWanderAroundSpot() throws {
        let visible = CGRect(x: 0, y: 70, width: 1512, height: 879)
        let spot = DesktopPetSpot(display: 1, along: 0.5, across: 0)
        let free = try XCTUnwrap(DesktopPetTracks.edge(.free, visible: visible, length: 56, spot: spot))
        let wander = try XCTUnwrap(free.wander)
        XCTAssertEqual((wander.lowerBound + wander.upperBound) / 2, free.lane.lowerBound, accuracy: 0.001)
        XCTAssertGreaterThan(wander.upperBound - wander.lowerBound, 60)
        XCTAssertEqual(free.roam, wander)
        let bottom = try XCTUnwrap(DesktopPetTracks.edge(.bottom, visible: visible, length: 56, spot: nil))
        XCTAssertNil(bottom.wander)
        XCTAssertEqual(bottom.roam, bottom.lane)
    }

    func testFreePetWalksNearbyAndComesBack() {
        let lane = 560.0...720.0
        var state = DesktopPetBrain.placed(at: 640, style: .sit, now: t0)
        var now = t0
        var walked = false
        var farthest = 0.0
        let rolls = [0.4, 0.3, 0.9, 0.6]
        var i = 0
        let random: () -> Double = {
            defer { i += 1 }
            return rolls[i % rolls.count]
        }
        for _ in 0..<1200 {
            now = now.addingTimeInterval(0.1)
            state = DesktopPetBrain.step(state, dt: 0.1, now: now, lane: lane, userIdle: 0, focusing: false,
                                         style: .sit, random: random)
            if case .walk = state.activity { walked = true }
            farthest = max(farthest, abs(state.x - 640))
            XCTAssertTrue(lane.contains(state.x), "不出附近那一段")
        }
        XCTAssertTrue(walked, "随意放的也会走几步")
        XCTAssertGreaterThan(farthest, 10)
    }

    // MARK: 别的吉祥物用变换补动作

    func testSkinGesturesForSingleFrameMascots() {
        let stretch = DesktopPetSkin.apply(DesktopPetPose(image: "pet-sprite-stretch-4"), mascot: .shiba)
        XCTAssertEqual(stretch.image, "pet-sprite-shiba-sit")
        XCTAssertGreaterThan(stretch.scaleY, 1.05, "伸懒腰往上拉长")
        let front = DesktopPetSkin.apply(DesktopPetPose(image: "pet-sprite-front-stretch-4"), mascot: .cat)
        XCTAssertEqual(front.scaleY, 1 + DesktopPetSkin.stretchLift, accuracy: 1e-9)

        let yawnRight = DesktopPetSkin.apply(DesktopPetPose(image: "pet-sprite-yawn-4"), mascot: .penguin)
        XCTAssertLessThan(yawnRight.wobble, 0, "朝右时往后仰是逆时针")
        let yawnLeft = DesktopPetSkin.apply(DesktopPetPose(image: "pet-sprite-yawn-4", facingLeft: true),
                                            mascot: .penguin)
        XCTAssertGreaterThan(yawnLeft.wobble, 0)

        let droop = DesktopPetSkin.apply(DesktopPetPose(image: "pet-sprite-droop-1"), mascot: .otter)
        XCTAssertLessThan(droop.scaleY, 1)
        let sit = DesktopPetSkin.apply(DesktopPetPose(image: "pet-sprite-sit-1"), mascot: .octopus)
        XCTAssertEqual(sit.scaleY, 1)
        XCTAssertEqual(sit.wobble, 0)
        // 小熊猫有真帧，不叠变换。
        let panda = DesktopPetPose(image: "pet-sprite-stretch-4")
        XCTAssertEqual(DesktopPetSkin.apply(panda, mascot: .panda), panda)
    }

    func testLowPowerHalvesRestingRate() {
        let idle = DesktopPetState(x: 300, activity: .idle(until: t0), since: t0)
        XCTAssertEqual(DesktopPetBrain.tickRate(idle, style: .sit, lowPower: true), DesktopPetBrain.restingFPS / 2)
        XCTAssertEqual(DesktopPetBrain.tickRate(idle, style: .sit, lowPower: false), DesktopPetBrain.restingFPS)
        let asleep = DesktopPetState(x: 300, activity: .sleep(since: t0), since: t0)
        XCTAssertEqual(DesktopPetBrain.tickRate(asleep, lowPower: true), DesktopPetBrain.sleepingFPS)
    }
}
