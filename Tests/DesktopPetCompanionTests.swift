import CoreGraphics
import Foundation
import XCTest

/// 桌面伙伴 2.0：只检测系统输入的“活动时刻”，不读取任何按键内容。
final class DesktopPetCompanionTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let center = CGPoint(x: 500, y: 300)

    private func sample(_ state: inout DesktopPetCompanionState, offset: TimeInterval,
                        pointer: CGPoint? = nil, keyIdle: TimeInterval? = nil,
                        typing: Bool = false, hunt: Bool = false, reduce: Bool = false) -> Bool {
        state.observe(now: t0.addingTimeInterval(offset), pointer: pointer,
                      center: center, scale: 1, keyIdle: keyIdle,
                      typingEnabled: typing, huntEnabled: hunt, reduceMotion: reduce)
    }

    func testTypingIsOptInAndExpires() {
        var state = DesktopPetCompanionState()
        XCTAssertFalse(sample(&state, offset: 0, keyIdle: 0.05), "默认不采样打字节奏")
        XCTAssertEqual(state.typingStrength(at: t0), 0)
        XCTAssertFalse(sample(&state, offset: 0.1, keyIdle: 0.08, typing: true))
        XCTAssertGreaterThan(state.typingStrength(at: t0.addingTimeInterval(0.2)), 0)
        XCTAssertGreaterThan(state.typingStrength(at: t0.addingTimeInterval(0.6)), 0,
                             "约 1 秒内仍保持打字动作，避免一闪而过")
        XCTAssertEqual(state.typingStrength(at: t0.addingTimeInterval(1.2)), 0,
                       "停止输入约 1 秒后恢复普通动画")
        _ = sample(&state, offset: 0.7, keyIdle: 0.05, typing: true)
        _ = sample(&state, offset: 0.8, keyIdle: 100, typing: false)
        XCTAssertEqual(state.typingStrength(at: t0.addingTimeInterval(0.8)), 0)
    }

    func testRestingTickCatchesFirstKeyPress() {
        // 静止时计时器每秒 10 次：两次采样之间按下的键，下一次采样时 keyIdle 不超过 0.1 秒，
        // 只要在 0.5 秒的新鲜窗口内就算开始打字；超过窗口的旧按键不算。
        var state = DesktopPetCompanionState()
        _ = sample(&state, offset: 0, keyIdle: 0.45, typing: true)
        XCTAssertGreaterThan(state.typingStrength(at: t0), 0)
        var stale = DesktopPetCompanionState()
        _ = sample(&stale, offset: 0, keyIdle: 0.6, typing: true)
        XCTAssertEqual(stale.typingStrength(at: t0), 0)
    }

    func testInvalidIdleTimeCannotAnimate() {
        var state = DesktopPetCompanionState()
        _ = sample(&state, offset: 0, keyIdle: -1, typing: true)
        XCTAssertEqual(state.typingStrength(at: t0), 0)
        _ = sample(&state, offset: 0.1, keyIdle: .infinity, typing: true)
        XCTAssertEqual(state.typingStrength(at: t0.addingTimeInterval(0.1)), 0)
    }

    func testFastNearbyMouseTriggersOnceAndCooldown() {
        var state = DesktopPetCompanionState()
        XCTAssertFalse(sample(&state, offset: 0, pointer: center, hunt: true))
        let near = CGPoint(x: 650, y: 300)
        XCTAssertTrue(sample(&state, offset: 0.1, pointer: near, hunt: true),
                      "150pt / 0.1s = 1500pt/s，应触发")
        XCTAssertFalse(sample(&state, offset: 0.2, pointer: center, hunt: true),
                       "冷却期间不重复惊讶")
        XCTAssertFalse(sample(&state, offset: 7.5, pointer: center, hunt: true),
                       "大于采样跨度时不误判速度")
        XCTAssertTrue(sample(&state, offset: 7.6, pointer: near, hunt: true))
    }

    func testFarAwaySlowPointerAndReducedMotionNeverHunt() {
        var state = DesktopPetCompanionState()
        XCTAssertFalse(sample(&state, offset: 0, pointer: center, hunt: true))
        XCTAssertFalse(sample(&state, offset: 0.1, pointer: CGPoint(x: 520, y: 300), hunt: true),
                       "鼠标移动太慢")
        XCTAssertFalse(sample(&state, offset: 0.2, pointer: CGPoint(x: 880, y: 300), hunt: true),
                       "虽然很快但距离桌宠太远")
        state.reset()
        XCTAssertFalse(sample(&state, offset: 1, pointer: center, hunt: true))
        XCTAssertFalse(sample(&state, offset: 1.1, pointer: CGPoint(x: 650, y: 300),
                              hunt: true, reduce: true), "减弱动态效果优先")
    }

    func testMotionDecorationIsTemporaryAndRespectReducedMotion() {
        var state = DesktopPetCompanionState()
        _ = sample(&state, offset: 0, keyIdle: 0.05, typing: true)
        let pose = DesktopPetPose(image: "pet-sprite-front-sit-1")
        XCTAssertEqual(state.decorate(pose, now: t0, motion: .reduced), pose)
        XCTAssertNotEqual(state.decorate(pose, now: t0.addingTimeInterval(0.1), motion: .full), pose)
        XCTAssertEqual(state.decorate(pose, now: t0.addingTimeInterval(1.5), motion: .full), pose)
    }
    func testArticulatedGazeAndDistance() {
        let center = CGPoint(x: 500, y: 300)
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let near = DesktopPetArticulationLogic.pose(
            pointer: CGPoint(x: 620, y: 360), center: center, scale: 1,
            headTracking: true, typingStrength: 0, now: now,
            reduceMotion: false, lowPower: false)
        XCTAssertEqual(near?.headYaw, 0.5)
        XCTAssertEqual(near?.headPitch, 0.25)
        XCTAssertNil(DesktopPetArticulationLogic.pose(
            pointer: CGPoint(x: 2000, y: 360), center: center, scale: 1,
            headTracking: true, typingStrength: 0, now: now,
            reduceMotion: false, lowPower: false))
    }

    func testArticulatedPawsAlternateAndPowerModeDisablesThem() {
        let center = CGPoint(x: 500, y: 300)
        let t = Date(timeIntervalSinceReferenceDate: 800_000_000.125)
        let first = DesktopPetArticulationLogic.pose(
            pointer: nil, center: center, scale: 1, headTracking: false,
            typingStrength: 0.8, now: t, reduceMotion: false, lowPower: false)
        let second = DesktopPetArticulationLogic.pose(
            pointer: nil, center: center, scale: 1, headTracking: false,
            typingStrength: 0.8,
            now: t.addingTimeInterval(0.5 / DesktopPetArticulationLogic.typingFrequency),
            reduceMotion: false, lowPower: false)
        XCTAssertGreaterThan(first!.leftPaw, 0)
        XCTAssertEqual(first!.rightPaw, 0, accuracy: 0.001)
        XCTAssertEqual(second!.leftPaw, 0, accuracy: 0.001)
        XCTAssertGreaterThan(second!.rightPaw, 0)
        XCTAssertNil(DesktopPetArticulationLogic.pose(
            pointer: center, center: center, scale: 1, headTracking: true,
            typingStrength: 1, now: t, reduceMotion: true, lowPower: false))
        XCTAssertNil(DesktopPetArticulationLogic.pose(
            pointer: center, center: center, scale: 1, headTracking: true,
            typingStrength: 1, now: t, reduceMotion: false, lowPower: true))
    }

    func testArticulationPreferencesReadOldSettings() throws {
        let legacy = try JSONDecoder().decode(DesktopPetSettings.self, from: Data("{}".utf8))
        XCTAssertFalse(legacy.headParallax)
        let custom = DesktopPetSettings(typingCompanion: true, mouseHunt: true, headParallax: true)
        let restored = try JSONDecoder().decode(DesktopPetSettings.self,
                                                from: JSONEncoder().encode(custom))
        XCTAssertTrue(restored.headParallax)
        XCTAssertTrue(restored.typingCompanion)
        XCTAssertTrue(restored.mouseHunt)
    }


    func testLaptopOpensAfterSustainedTypingAndClosesAfterPause() {
        var state = DesktopPetCompanionState()
        for i in 0..<30 { _ = sample(&state, offset: Double(i) * 0.1, keyIdle: 0.05, typing: true) }
        XCTAssertFalse(state.laptop(at: t0.addingTimeInterval(2.9)), "不到 3 秒不拿电脑")
        for i in 30..<35 { _ = sample(&state, offset: Double(i) * 0.1, keyIdle: 0.05, typing: true) }
        XCTAssertTrue(state.laptop(at: t0.addingTimeInterval(3.4)), "连续打字 3 秒拿出电脑")
        XCTAssertTrue(state.laptop(at: t0.addingTimeInterval(8)), "停手 5 秒内保持")
        _ = sample(&state, offset: 9, keyIdle: 6, typing: true)
        XCTAssertFalse(state.laptop(at: t0.addingTimeInterval(9)), "停手超过 5 秒收起")
    }

    func testLaptopRunRestartsAfterGap() {
        var state = DesktopPetCompanionState()
        _ = sample(&state, offset: 0, keyIdle: 0.05, typing: true)
        _ = sample(&state, offset: 2, keyIdle: 0.05, typing: true)
        _ = sample(&state, offset: 3.2, keyIdle: 0.05, typing: true)
        XCTAssertFalse(state.laptop(at: t0.addingTimeInterval(3.2)), "中间停顿超过 1.5 秒重新计时")
    }
}
