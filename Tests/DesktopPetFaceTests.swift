import CoreGraphics
import XCTest

final class DesktopPetFaceTests: XCTestCase {
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let sit = "pet-sprite-front-sit-1"
    private let shipped = Set(DesktopPetFace.shippedImages)

    private func idle(_ since: Date? = nil) -> DesktopPetState {
        DesktopPetState(x: 300, activity: .idle(until: t0.addingTimeInterval(9)), since: since ?? t0)
    }

    /// 眼睛睁着的时刻（不在眨眼的 0.18 秒里）。
    private func openEyes(after start: Date) -> Date {
        var now = start
        while DesktopPetBrain.blinking(now: now) { now = now.addingTimeInterval(0.2) }
        return now
    }

    // MARK: 素材

    func testImageNamesAndShippedFilesExist() {
        XCTAssertEqual(DesktopPetFace.imageName(.left), "pet-sprite-lively-look-left")
        XCTAssertEqual(DesktopPetFace.imageName(.center), "pet-sprite-lively-center")
        XCTAssertEqual(DesktopPetFace.imageName(.dizzy), "pet-sprite-lively-emote-dizzy")
        XCTAssertEqual(DesktopPetFace.blinkImage, "pet-sprite-lively-blink")
        XCTAssertEqual(DesktopPetFace.shippedImages.count, 9)
        XCTAssertEqual(DesktopPetFace.allImages.count, 11)
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Pet/sprites")
        for name in DesktopPetFace.shippedImages {
            XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent(name + ".png").path), name)
        }
    }

    // MARK: 什么时候生效

    func testAppliesOnlyToFrontSittingPanda() {
        XCTAssertTrue(DesktopPetFace.applies(enabled: true, mascot: .panda, style: .stroll, image: sit))
        XCTAssertTrue(DesktopPetFace.applies(enabled: true, mascot: .panda, style: .sit, image: sit))
        XCTAssertTrue(DesktopPetFace.applies(enabled: true, mascot: .panda, style: .sit, image: "pet-sprite-front-wave-1"))
        XCTAssertFalse(DesktopPetFace.applies(enabled: false, mascot: .panda, style: .sit, image: sit), "关了不生效")
        for mascot in FocusMascot.allCases where mascot != .panda {
            XCTAssertFalse(DesktopPetFace.applies(enabled: true, mascot: mascot, style: .sit, image: sit))
        }
        for style in [DesktopPetStyle.hang, .side, .curl] {
            XCTAssertFalse(DesktopPetFace.applies(enabled: true, mascot: .panda, style: style, image: sit))
        }
        XCTAssertFalse(DesktopPetFace.applies(enabled: true, mascot: .panda, style: .stroll, image: "pet-sprite-walk-3"),
                       "走路照旧")
        XCTAssertFalse(DesktopPetFace.applies(enabled: true, mascot: .panda, style: .stroll,
                                              image: "pet-sprite-front-sleep-1"), "睡觉照旧")
    }

    // MARK: 看向

    func testGazeDirectionsDeadZoneAndFar() {
        XCTAssertEqual(DesktopPetFace.gaze(dx: -200, dy: 10, current: .center), .left)
        XCTAssertEqual(DesktopPetFace.gaze(dx: 200, dy: -10, current: .center), .right)
        XCTAssertEqual(DesktopPetFace.gaze(dx: 20, dy: 300, current: .center), .up)
        XCTAssertEqual(DesktopPetFace.gaze(dx: 20, dy: -300, current: .center), .down)
        XCTAssertEqual(DesktopPetFace.gaze(dx: 10, dy: 10, current: .left), .center, "在身上回正视")
        XCTAssertEqual(DesktopPetFace.gaze(dx: 2000, dy: 0, current: .right), .center, "很远回正视")
        // 死区的滞回：从正视出去要超过 40，看着时到 28 以内才回来。
        XCTAssertEqual(DesktopPetFace.gaze(dx: -34, dy: 0, current: .center), .center)
        XCTAssertEqual(DesktopPetFace.gaze(dx: -34, dy: 0, current: .left), .left)
        // 远处的滞回。
        XCTAssertEqual(DesktopPetFace.gaze(dx: 860, dy: 0, current: .center), .center)
        XCTAssertEqual(DesktopPetFace.gaze(dx: 860, dy: 0, current: .right), .right)
    }

    func testGazeHysteresisOnDiagonal() {
        // 斜一点：已经看左时不换成看上，从正视来按大的那边。
        XCTAssertEqual(DesktopPetFace.gaze(dx: -100, dy: 120, current: .left), .left)
        XCTAssertEqual(DesktopPetFace.gaze(dx: -100, dy: 120, current: .center), .up)
        XCTAssertEqual(DesktopPetFace.gaze(dx: -100, dy: 120, current: .up), .up)
        XCTAssertEqual(DesktopPetFace.gaze(dx: -100, dy: 160, current: .left), .up, "明显往上了才换")
    }

    func testFollowHoldsThenSettlesWhenStill() {
        var face = DesktopPetFaceState()
        let center = CGPoint(x: 500, y: 100)
        face.follow(pointer: CGPoint(x: 300, y: 110), center: center, scale: 1, now: t0)
        XCTAssertEqual(face.gaze, .left)
        // 刚换过方向，0.1 秒内不再换。
        face.follow(pointer: CGPoint(x: 700, y: 110), center: center, scale: 1, now: t0.addingTimeInterval(0.1))
        XCTAssertEqual(face.gaze, .left)
        face.follow(pointer: CGPoint(x: 701, y: 110), center: center, scale: 1, now: t0.addingTimeInterval(0.5))
        XCTAssertEqual(face.gaze, .right)
        // 指针停着 5 秒以上回正视。
        face.follow(pointer: CGPoint(x: 701, y: 110), center: center, scale: 1, now: t0.addingTimeInterval(6))
        XCTAssertEqual(face.gaze, .center)
        // 不跟（关了、减弱动态效果）也是正视。
        face.follow(pointer: CGPoint(x: 300, y: 110), center: center, scale: 1, now: t0.addingTimeInterval(7))
        XCTAssertEqual(face.gaze, .left)
        face.follow(pointer: nil, center: center, scale: 1, now: t0.addingTimeInterval(8))
        XCTAssertEqual(face.gaze, .center)
    }

    func testFollowScalesBySize() {
        var face = DesktopPetFaceState()
        // 大号（1.25 倍）时 45 点只算 36，还在死区里。
        face.follow(pointer: CGPoint(x: 455, y: 100), center: CGPoint(x: 500, y: 100), scale: 1.25, now: t0)
        XCTAssertEqual(face.gaze, .center)
    }

    // MARK: 点击和表情

    func testTapSurpriseThenDizzyWithCooldown() {
        var face = DesktopPetFaceState()
        XCTAssertEqual(face.tapped(now: t0), .surprise)
        XCTAssertEqual(face.activeEmote(now: t0.addingTimeInterval(0.5)), .surprise)
        XCTAssertNil(face.activeEmote(now: t0.addingTimeInterval(1.1)), "约 1 秒")
        XCTAssertEqual(face.tapped(now: t0.addingTimeInterval(0.3)), .surprise)
        XCTAssertEqual(face.tapped(now: t0.addingTimeInterval(0.6)), .surprise)
        XCTAssertEqual(face.tapped(now: t0.addingTimeInterval(0.9)), .dizzy, "连点第 4 下")
        XCTAssertEqual(face.activeEmote(now: t0.addingTimeInterval(2.5)), .dizzy, "约 2 秒")
        XCTAssertNil(face.activeEmote(now: t0.addingTimeInterval(3.0)))
        // 冷却里再连点 4 下只是吃惊。
        var last = DesktopPetEmote.surprise
        for i in 0..<4 { last = face.tapped(now: t0.addingTimeInterval(3.2 + Double(i) * 0.2)) }
        XCTAssertEqual(last, .surprise)
        // 冷却过了又能晕。
        for i in 0..<3 { face.tapped(now: t0.addingTimeInterval(10 + Double(i) * 0.2)) }
        XCTAssertEqual(face.tapped(now: t0.addingTimeInterval(10.6)), .dizzy)
    }

    func testSlowTapsNeverDizzy() {
        var face = DesktopPetFaceState()
        for i in 0..<8 {
            XCTAssertEqual(face.tapped(now: t0.addingTimeInterval(Double(i) * 1.5)), .surprise)
        }
    }

    func testDrowsyWindowBeforeSleep() {
        let sleepAt = DesktopPetBrain.sleepAfter
        XCTAssertFalse(DesktopPetFace.drowsy(userIdle: sleepAt - 20, night: false))
        XCTAssertTrue(DesktopPetFace.drowsy(userIdle: sleepAt - 5, night: false))
        XCTAssertFalse(DesktopPetFace.drowsy(userIdle: sleepAt, night: false), "睡着以后走原来的入睡")
        XCTAssertTrue(DesktopPetFace.drowsy(userIdle: sleepAt / 2 - 5, night: true), "夜里入睡减半")
    }

    // MARK: 叠到样子上

    func testOverlayLooksAndFallsBackWhenArtMissing() {
        var face = DesktopPetFaceState()
        let now = openEyes(after: t0)
        face.follow(pointer: CGPoint(x: 100, y: 100), center: CGPoint(x: 500, y: 100), scale: 1, now: now)
        let pose = DesktopPetPose(image: sit, scaleY: 1.01)
        let looked = DesktopPetFace.overlay(pose, base: sit, state: idle(), face: face, now: now, drowsy: false,
                                           motion: .full, exists: { self.shipped.contains($0) })
        XCTAssertEqual(looked.image, "pet-sprite-lively-look-left")
        XCTAssertEqual(looked.scaleY, 1.01, "呼吸照旧")
        XCTAssertFalse(looked.facingLeft, "正面不翻")
        // 缺图：原样。
        let missing = DesktopPetFace.overlay(pose, base: sit, state: idle(), face: face, now: now, drowsy: false,
                                            motion: .full, exists: { _ in false })
        XCTAssertEqual(missing, pose)
        // 正视、缺正视帧：照旧画 front-sit。
        let centered = DesktopPetFace.overlay(pose, base: sit, state: idle(), face: DesktopPetFaceState(), now: now,
                                             drowsy: false, motion: .full, exists: { self.shipped.contains($0) })
        XCTAssertEqual(centered, pose)
        // 补了正视帧以后用它。
        let withCenter = DesktopPetFace.overlay(pose, base: sit, state: idle(), face: DesktopPetFaceState(), now: now,
                                               drowsy: false, motion: .full,
                                               exists: { self.shipped.contains($0) || $0 == DesktopPetFace.centerImage })
        XCTAssertEqual(withCenter.image, DesktopPetFace.centerImage)
    }

    func testBlinkUsesBlinkFrameOnlyWhenPresent() {
        var face = DesktopPetFaceState()
        var now = t0
        while !DesktopPetBrain.blinking(now: now) { now = now.addingTimeInterval(0.05) }
        face.follow(pointer: CGPoint(x: 900, y: 100), center: CGPoint(x: 500, y: 100), scale: 1, now: now)
        let pose = DesktopPetPose(image: sit)
        let noBlink = DesktopPetFace.overlay(pose, base: sit, state: idle(), face: face, now: now, drowsy: false,
                                            motion: .full, exists: { self.shipped.contains($0) })
        XCTAssertEqual(noBlink.image, "pet-sprite-lively-look-right", "缺闭眼帧不另外眨眼")
        let blink = DesktopPetFace.overlay(pose, base: sit, state: idle(), face: face, now: now, drowsy: false,
                                          motion: .full,
                                          exists: { self.shipped.contains($0) || $0 == DesktopPetFace.blinkImage })
        XCTAssertEqual(blink.image, DesktopPetFace.blinkImage)
    }

    func testEmotesOverrideAndReducedMotionIsStatic() {
        var face = DesktopPetFaceState()
        face.tapped(now: t0)
        let pose = DesktopPetPose(image: sit, wobble: 3)
        let at = t0.addingTimeInterval(0.15)
        let full = DesktopPetFace.overlay(pose, base: sit, state: idle(), face: face, now: at, drowsy: false,
                                         motion: .full, exists: { self.shipped.contains($0) })
        XCTAssertEqual(full.image, "pet-sprite-lively-emote-surprise")
        XCTAssertGreaterThan(full.lift, 0, "吃惊往上一弹")
        XCTAssertTrue(DesktopPetFace.needsSmooth(face, now: at, motion: .full))
        let calm = DesktopPetFace.overlay(pose, base: sit, state: idle(), face: face, now: at, drowsy: false,
                                         motion: .reduced, exists: { self.shipped.contains($0) })
        XCTAssertEqual(calm.image, "pet-sprite-lively-emote-surprise")
        XCTAssertEqual(calm.lift, 0, "减弱动态效果只换图")
        XCTAssertEqual(calm.wobble, 0)
        XCTAssertFalse(DesktopPetFace.needsSmooth(face, now: at, motion: .reduced))
        // 演完回到正视（缺正视帧就是原来的坐姿）。
        let after = DesktopPetFace.overlay(pose, base: sit, state: idle(), face: face, now: openEyes(after: t0.addingTimeInterval(1.2)),
                                          drowsy: false, motion: .full, exists: { self.shipped.contains($0) })
        XCTAssertEqual(after.image, sit)
        // 表情缺图时原样。
        let missing = DesktopPetFace.overlay(pose, base: sit, state: idle(), face: face, now: at, drowsy: false,
                                            motion: .full, exists: { _ in false })
        XCTAssertEqual(missing, pose)
    }

    func testShyHappyAndSleepy() {
        var face = DesktopPetFaceState()
        face.play(.shy, now: t0)
        let pose = DesktopPetPose(image: sit)
        XCTAssertEqual(DesktopPetFace.overlay(pose, base: sit, state: idle(), face: face, now: t0.addingTimeInterval(0.5),
                                              drowsy: false, motion: .full, exists: { self.shipped.contains($0) }).image,
                       "pet-sprite-lively-emote-shy")
        // 欢呼（正面挥手）时开心。
        let cheering = DesktopPetState(x: 300, activity: .cheer(until: t0.addingTimeInterval(2.5)), since: t0)
        let wave = "pet-sprite-front-wave-1"
        XCTAssertEqual(DesktopPetFace.overlay(DesktopPetPose(image: wave), base: wave, state: cheering,
                                              face: DesktopPetFaceState(), now: t0.addingTimeInterval(0.3), drowsy: false,
                                              motion: .full, exists: { self.shipped.contains($0) }).image,
                       "pet-sprite-lively-emote-happy")
        // 打招呼（探头挥手）不是欢呼，照旧挥手。
        let peeking = DesktopPetState(x: 300, activity: .peek(until: t0.addingTimeInterval(1.4)), since: t0)
        XCTAssertEqual(DesktopPetFace.overlay(DesktopPetPose(image: wave), base: wave, state: peeking,
                                              face: DesktopPetFaceState(), now: t0.addingTimeInterval(0.3), drowsy: false,
                                              motion: .full, exists: { self.shipped.contains($0) }).image, wave)
        // 快睡着前犯困。
        XCTAssertEqual(DesktopPetFace.overlay(pose, base: sit, state: idle(), face: DesktopPetFaceState(),
                                              now: t0.addingTimeInterval(1), drowsy: true, motion: .full,
                                              exists: { self.shipped.contains($0) }).image,
                       "pet-sprite-lively-emote-sleepy")
    }

    func testFidgetWiggleIsKept() {
        // 发呆小动作把图换成了挥手：没有表情时照旧挥手。
        var face = DesktopPetFaceState()
        face.follow(pointer: CGPoint(x: 100, y: 100), center: CGPoint(x: 500, y: 100), scale: 1, now: t0)
        let wiggle = DesktopPetPose(image: "pet-sprite-front-wave-2")
        XCTAssertEqual(DesktopPetFace.overlay(wiggle, base: sit, state: idle(), face: face, now: t0, drowsy: false,
                                              motion: .full, exists: { self.shipped.contains($0) }), wiggle)
    }

    func testSettingsDefaultOn() throws {
        XCTAssertTrue(DesktopPetSettings().livelyFace)
        let legacy = try JSONDecoder().decode(DesktopPetSettings.self, from: Data(#"{"enabled":true}"#.utf8))
        XCTAssertTrue(legacy.livelyFace, "老设置默认开")
        let off = DesktopPetSettings(enabled: true, livelyFace: false)
        let round = try JSONDecoder().decode(DesktopPetSettings.self, from: JSONEncoder().encode(off))
        XCTAssertFalse(round.livelyFace)
        XCTAssertEqual(round, off)
    }
}
