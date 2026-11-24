import XCTest

/// 黑胶模式 V2 的唱机动作（Core `VinylMotion`）和 Pro 门控（`ProLicenseGate.musicPanelStyle`）。
final class VinylMotionTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 10_000)
    private let groove = 30.0

    private func at(_ seconds: Double) -> Date { t0.addingTimeInterval(seconds) }

    // MARK: 开始播放

    func testStartPlayingMovesArmThenDropsThenSpins() {
        var motion = VinylMotion.settled(playing: false, track: "a", groove: groove, now: t0)
        XCTAssertEqual(motion.mode, .rest)
        XCTAssertFalse(motion.isAnimating(at: t0), "停着时不逐帧刷新")
        motion.update(playing: true, ended: false, track: "a", groove: groove, now: t0)
        XCTAssertEqual(motion.mode, .playing)

        let start = motion.frame(at: t0, groove: groove)
        XCTAssertEqual(start.armAngle, MusicVinyl.restAngle, accuracy: 0.001, "从支架出发")
        XCTAssertEqual(start.lift, 1, accuracy: 0.001)
        XCTAssertEqual(start.discSpeed, 0, accuracy: 0.001)

        let moving = motion.frame(at: at(0.6), groove: groove)
        XCTAssertGreaterThan(moving.armAngle, 0, "唱臂缓缓移向外圈")
        XCTAssertLessThan(moving.armAngle, groove)
        XCTAssertEqual(moving.lift, 1, accuracy: 0.001, "移动时唱针抬着")
        XCTAssertEqual(moving.discSpeed, 0, accuracy: 0.001, "落针前唱片不转")

        let dropping = motion.frame(at: at(VinylMotion.armMove + 0.15), groove: groove)
        XCTAssertEqual(dropping.armAngle, groove, accuracy: 0.001, "到了外圈再落针")
        XCTAssertGreaterThan(dropping.lift, 0)
        XCTAssertLessThan(dropping.lift, 1, "轻轻落下")
        XCTAssertEqual(dropping.discSpeed, 0, accuracy: 0.001)

        let landed = VinylMotion.armMove + VinylMotion.drop
        let spinning = motion.frame(at: at(landed + VinylMotion.spinUp / 2), groove: groove)
        XCTAssertEqual(spinning.lift, 0, accuracy: 0.001)
        XCTAssertEqual(spinning.discSpeed, 0.5, accuracy: 0.01, "落针后唱片逐渐起转")
        XCTAssertEqual(motion.frame(at: at(landed + 5), groove: groove).discSpeed, 1, accuracy: 0.001)
        XCTAssertTrue(motion.isAnimating(at: at(landed + 5)), "在放时唱片一直转")
    }

    func testOpeningPanelWhilePlayingSkipsTheCue() {
        let motion = VinylMotion.settled(playing: true, track: "a", groove: groove, now: t0)
        let frame = motion.frame(at: t0, groove: groove)
        XCTAssertEqual(frame.armAngle, groove, accuracy: 0.001)
        XCTAssertEqual(frame.lift, 0, accuracy: 0.001)
        XCTAssertEqual(frame.discSpeed, 1, accuracy: 0.001)
        XCTAssertEqual(motion.frame(at: at(1), groove: 31).armAngle, 31, accuracy: 0.001, "唱臂跟着进度走")
    }

    // MARK: 暂停、继续

    func testPauseSlowsDiscLiftsNeedleAndKeepsArm() {
        var motion = VinylMotion.settled(playing: true, track: "a", groove: groove, now: t0)
        motion.update(playing: false, ended: false, track: "a", groove: groove, now: at(10))
        XCTAssertEqual(motion.mode, .paused)
        XCTAssertEqual(motion.frame(at: at(10), groove: groove).discSpeed, 1, accuracy: 0.001)
        XCTAssertEqual(motion.frame(at: at(10 + VinylMotion.spinDown / 2), groove: groove).discSpeed, 0.5,
                       accuracy: 0.01, "逐渐减速")
        let stopped = motion.frame(at: at(10 + VinylMotion.spinDown + 0.01), groove: groove)
        XCTAssertEqual(stopped.discSpeed, 0, accuracy: 0.001)
        let later = motion.frame(at: at(60), groove: 35)
        XCTAssertEqual(later.discAngle, stopped.discAngle, accuracy: 0.001, "停稳后不再转")
        XCTAssertEqual(later.armAngle, groove, accuracy: 0.001, "唱臂停在原处，不归位")
        XCTAssertEqual(later.lift, MusicVinyl.pausedLift, accuracy: 0.001, "唱针微抬")
        XCTAssertGreaterThan(later.lift, 0)
        XCTAssertLessThan(later.lift, 1)
        XCTAssertFalse(motion.isAnimating(at: at(60)), "停稳后不再逐帧刷新")
    }

    func testResumeDropsNeedleAndContinuesFromPausedAngle() {
        var motion = VinylMotion.settled(playing: true, track: "a", groove: groove, now: t0)
        motion.update(playing: false, ended: false, track: "a", groove: groove, now: at(10))
        let paused = motion.frame(at: at(20), groove: groove).discAngle
        motion.update(playing: true, ended: false, track: "a", groove: groove, now: at(20))
        XCTAssertEqual(motion.mode, .playing)
        XCTAssertEqual(motion.frame(at: at(20), groove: groove).discAngle, paused, accuracy: 0.001,
                       "从暂停时的角度接着转，不跳")
        XCTAssertEqual(motion.frame(at: at(20.1), groove: groove).discAngle, paused, accuracy: 0.001,
                       "先落针，再起转")
        let after = motion.frame(at: at(25), groove: groove)
        XCTAssertEqual(after.lift, 0, accuracy: 0.001, "重新落针")
        XCTAssertEqual(after.discSpeed, 1, accuracy: 0.001)
        XCTAssertNotEqual(after.discAngle, paused, "又转起来了")
    }

    func testQuickResumeWhileSlowingDoesNotFreeze() {
        var motion = VinylMotion.settled(playing: true, track: "a", groove: groove, now: t0)
        motion.update(playing: false, ended: false, track: "a", groove: groove, now: at(10))
        motion.update(playing: true, ended: false, track: "a", groove: groove, now: at(10.3))
        let a = motion.frame(at: at(10.3), groove: groove)
        let b = motion.frame(at: at(10.4), groove: groove)
        XCTAssertGreaterThan(a.discSpeed, 0, "还在减速时继续，从当前转速加回去")
        XCTAssertNotEqual(a.discAngle, b.discAngle)
    }

    // MARK: 放完、停止

    func testEndLiftsNeedleAndReturnsArmSlowly() {
        var motion = VinylMotion.settled(playing: true, track: "a", groove: groove, now: t0)
        motion.update(playing: false, ended: true, track: "a", groove: groove, now: at(5))
        XCTAssertEqual(motion.mode, .rest)
        let lifting = motion.frame(at: at(5.1), groove: groove)
        XCTAssertEqual(lifting.armAngle, groove, accuracy: 0.001, "先抬针，唱臂还没动")
        XCTAssertGreaterThan(lifting.lift, 0)
        let returning = motion.frame(at: at(5 + VinylMotion.raise + VinylMotion.armReturn / 2), groove: groove)
        XCTAssertGreaterThan(returning.armAngle, 0, "唱臂缓缓回去")
        XCTAssertLessThan(returning.armAngle, groove)
        XCTAssertEqual(returning.lift, 1, accuracy: 0.001)
        let done = motion.frame(at: at(10), groove: groove)
        XCTAssertEqual(done.armAngle, MusicVinyl.restAngle, accuracy: 0.001, "回到支架")
        XCTAssertEqual(done.discSpeed, 0, accuracy: 0.001)
        XCTAssertFalse(motion.isAnimating(at: at(10)))
    }

    func testPausedThenEndedReturnsToRest() {
        var motion = VinylMotion.settled(playing: true, track: "a", groove: groove, now: t0)
        motion.update(playing: false, ended: false, track: "a", groove: groove, now: at(5))
        motion.update(playing: false, ended: true, track: "a", groove: groove, now: at(8))
        XCTAssertEqual(motion.mode, .rest)
        XCTAssertEqual(motion.frame(at: at(15), groove: groove).armAngle, MusicVinyl.restAngle, accuracy: 0.001)
    }

    func testEndedNeedsALengthAndTheLastSecond() {
        XCTAssertTrue(VinylMotion.ended(playing: false, elapsed: 179.5, duration: 180))
        XCTAssertFalse(VinylMotion.ended(playing: true, elapsed: 180, duration: 180), "还在放不算")
        XCTAssertFalse(VinylMotion.ended(playing: false, elapsed: 60, duration: 180), "中途暂停不算")
        XCTAssertFalse(VinylMotion.ended(playing: false, elapsed: 0, duration: 0), "直播流读不到时长不算")
        XCTAssertFalse(VinylMotion.ended(playing: false, elapsed: .nan, duration: 180))
    }

    // MARK: 切歌

    func testTrackChangeWhilePlayingKeepsSpinningAndReturnsToOuterGroove() {
        var motion = VinylMotion.settled(playing: true, track: "a", groove: 44, now: t0)
        let outer = 22.0
        motion.update(playing: true, ended: false, track: "b", groove: outer, previousGroove: 44, now: at(5))
        XCTAssertEqual(motion.frame(at: at(5), groove: outer).armAngle, 44, accuracy: 0.001,
                       "从屏幕上原来的位置出发，不瞬移")
        var peak = 0.0
        for step in 0...30 {
            let frame = motion.frame(at: at(5 + Double(step) * 0.1), groove: outer)
            XCTAssertEqual(frame.discSpeed, 1, accuracy: 0.001, "切歌时唱片不停")
            peak = max(peak, frame.lift)
        }
        XCTAssertGreaterThan(peak, 0.3, "唱针抬一下")
        let settled = motion.frame(at: at(8), groove: outer)
        XCTAssertEqual(settled.armAngle, outer, accuracy: 0.001, "回到新歌的外圈")
        XCTAssertEqual(settled.lift, 0, accuracy: 0.001, "再落下")
    }

    func testSeekWithinTrackGlidesInsteadOfJumping() {
        var motion = VinylMotion.settled(playing: true, track: "a", groove: 40, now: t0)
        motion.update(playing: true, ended: false, track: "a", groove: 25, previousGroove: 40, now: at(5))
        XCTAssertEqual(motion.frame(at: at(5), groove: 25).armAngle, 40, accuracy: 0.001)
        XCTAssertEqual(motion.frame(at: at(8), groove: 25).armAngle, 25, accuracy: 0.001)
        XCTAssertEqual(motion.frame(at: at(8), groove: 25).lift, 0, accuracy: 0.001)
        // 正常走一秒的进度不算跳。
        var steady = VinylMotion.settled(playing: true, track: "a", groove: 30, now: t0)
        steady.update(playing: true, ended: false, track: "a", groove: 30.1, previousGroove: 30, now: at(5))
        XCTAssertEqual(steady.frame(at: at(5), groove: 30.1).lift, 0, accuracy: 0.001)
        XCTAssertFalse(steady.frame(at: at(5.2), groove: 30.1).lift > 0.001)
    }

    func testTrackChangeWhilePausedMovesArmButStaysLifted() {
        var motion = VinylMotion.settled(playing: true, track: "a", groove: 44, now: t0)
        motion.update(playing: false, ended: false, track: "a", groove: 44, now: at(5))
        motion.update(playing: false, ended: false, track: "b", groove: 22, now: at(10))
        XCTAssertEqual(motion.mode, .paused)
        let frame = motion.frame(at: at(15), groove: 22)
        XCTAssertEqual(frame.armAngle, 22, accuracy: 0.001)
        XCTAssertEqual(frame.lift, MusicVinyl.pausedLift, accuracy: 0.001)
        XCTAssertEqual(frame.discSpeed, 0, accuracy: 0.001)
    }

    // MARK: 减弱动态效果

    func testStillFrameJumpsToTheEndAndDoesNotSpin() {
        var motion = VinylMotion.settled(playing: false, track: "a", groove: groove, now: t0)
        motion.update(playing: true, ended: false, track: "a", groove: groove, now: t0)
        let still = motion.stillFrame(at: at(0.1), groove: groove)
        XCTAssertEqual(still.armAngle, groove, accuracy: 0.001, "直接画在终点")
        XCTAssertEqual(still.lift, 0, accuracy: 0.001)
        XCTAssertEqual(still.discSpeed, 0, "不转")
        XCTAssertEqual(motion.stillFrame(at: at(9), groove: groove).discAngle,
                       motion.frame(at: at(9), groove: groove).discAngle, accuracy: 0.001)
    }

    func testDiscAngleStaysInRange() {
        let motion = VinylMotion.settled(playing: true, track: "a", groove: groove, now: t0)
        for step in 0..<50 {
            let angle = motion.frame(at: at(Double(step) * 3.7), groove: groove).discAngle
            XCTAssertGreaterThanOrEqual(angle, 0)
            XCTAssertLessThan(angle, 360)
        }
    }

    func testRippleEnergyStaysFaint() {
        for energy in [0.0, 0.5, 1, 3, -1, .nan] {
            for ring in MusicVinyl.ripples(t: 2.5, energy: energy) {
                XCTAssertLessThanOrEqual(ring.opacity, MusicVinyl.rippleOpacity, "不做大面积发光")
                XCTAssertGreaterThanOrEqual(ring.opacity, 0)
            }
        }
        let calm = MusicVinyl.ripples(t: 2.5, energy: 0).map(\.opacity).reduce(0, +)
        let busy = MusicVinyl.ripples(t: 2.5, energy: 1).map(\.opacity).reduce(0, +)
        XCTAssertLessThan(calm, busy, "唱片停下时水面更静")
    }

    // MARK: 免费

    func testVinylIsFreeAndTheDefault() {
        let vinyl: [String: WidgetConfig.Value] = [MusicPanelStyle.key: .string("vinyl")]
        let standard: [String: WidgetConfig.Value] = [MusicPanelStyle.key: .string("standard")]
        XCTAssertFalse(ProFeatures.isKindProStyle(.music, vinyl), "黑胶 11-24 起免费")
        XCTAssertFalse(ProFeatures.isKindProStyle(.music, standard))
        XCTAssertFalse(ProFeatures.isProKind(.music))
        XCTAssertTrue(ProLicenseGate.canChoose(.music, vinyl, unlocked: false))
        XCTAssertTrue(ProLicenseGate.canChoose(.music, standard, unlocked: false))
        let config = MusicPanelStyle.choosing(.vinyl, in: WidgetConfig())
        XCTAssertEqual(ProLicenseGate.musicPanelStyle(config: config, unlocked: false), .vinyl)
        XCTAssertEqual(ProLicenseGate.musicPanelStyle(config: WidgetConfig(), unlocked: false), .vinyl)
        let instance = WidgetInstance(kind: .music, config: config)
        XCTAssertFalse(ProLicenseGate.needsLockOverlay(instance, unlocked: false))
        XCTAssertFalse(ProFeatures.isPro(instance), "设置里不再标 Pro")
    }
}
