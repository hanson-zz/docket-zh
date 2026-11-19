import XCTest

/// 刘海小岛跟随所选吉祥物的图名和回退规则，以及专注面板道具图的规则。
final class NotchMascotArtTests: XCTestCase {

    /// 现有的倒挂小熊猫五张图都在，新素材一张都没有（现在仓库里的样子）。
    private let pandaOnly: Set<String> = [
        "notch-panda-hang", "notch-panda-blink", "notch-panda-sleep", "notch-panda-done", "notch-panda-peek",
    ]

    private func has(_ names: Set<String>) -> (String) -> Bool { { names.contains($0) } }

    // MARK: 样子

    func testPoseFollowsMascotState() {
        XCTAssertEqual(NotchMascotPose.of(.focus), .focus)
        XCTAssertEqual(NotchMascotPose.of(.idle), .sleep, "暂停或等开始是打盹")
        XCTAssertEqual(NotchMascotPose.of(.done), .done)
        XCTAssertEqual(NotchMascotPose.of(.break), .done, "休息也是开心那张")
    }

    // MARK: 图名

    func testImageNames() {
        XCTAssertEqual(NotchMascotArt.imageName(.shiba, .peek), "notch-shiba-peek")
        XCTAssertEqual(NotchMascotArt.imageName(.octopus, .focus), "notch-octopus-focus")
        XCTAssertEqual(NotchMascotArt.imageName(.cat, .sleep), "notch-cat-sleep")
        XCTAssertEqual(NotchMascotArt.imageName(.otter, .done), "notch-otter-done")
        XCTAssertEqual(NotchMascotArt.imageName(.panda, .sleep), NotchHangingPanda.Pose.sleep.imageName,
                       "小熊猫的 sleep 就是现有那张")
    }

    func testPandaFallbackNames() {
        XCTAssertEqual(NotchMascotArt.pandaFallback(.peek), "notch-panda-peek")
        XCTAssertEqual(NotchMascotArt.pandaFallback(.focus), "notch-panda-hang", "focus 回退成 hang")
        XCTAssertEqual(NotchMascotArt.pandaFallback(.focus, blinking: true), "notch-panda-blink")
        XCTAssertEqual(NotchMascotArt.pandaFallback(.sleep, blinking: true), "notch-panda-sleep", "只有 focus 眨眼")
        XCTAssertEqual(NotchMascotArt.pandaFallback(.done), "notch-panda-done")
    }

    func testCandidatesOwnFirstThenPandaWithoutDuplicates() {
        XCTAssertEqual(NotchMascotArt.candidates(.penguin, .focus), ["notch-penguin-focus", "notch-panda-hang"])
        XCTAssertEqual(NotchMascotArt.candidates(.panda, .done), ["notch-panda-done"])
        XCTAssertEqual(NotchMascotArt.candidates(.panda, .focus, blinking: true),
                       ["notch-panda-focus", "notch-panda-blink"])
    }

    // MARK: 展开时取图

    func testMissingArtFallsBackToPanda() {
        for mascot in FocusMascot.allCases {
            XCTAssertEqual(NotchMascotArt.resolve(mascot, .focus, exists: has(pandaOnly)), "notch-panda-hang")
            XCTAssertEqual(NotchMascotArt.resolve(mascot, .sleep, exists: has(pandaOnly)), "notch-panda-sleep")
            XCTAssertEqual(NotchMascotArt.resolve(mascot, .done, exists: has(pandaOnly)), "notch-panda-done")
            XCTAssertTrue(NotchMascotArt.usesPandaFallback(mascot, .focus, exists: has(pandaOnly)))
        }
    }

    func testBlinkOnlyWhenFallingBackToPanda() {
        XCTAssertEqual(NotchMascotArt.resolve(.shiba, .focus, blinking: true, exists: has(pandaOnly)),
                       "notch-panda-blink")
        let withShiba = pandaOnly.union(["notch-shiba-focus"])
        XCTAssertEqual(NotchMascotArt.resolve(.shiba, .focus, blinking: true, exists: has(withShiba)),
                       "notch-shiba-focus", "有自己的图就不眨眼")
        XCTAssertFalse(NotchMascotArt.usesPandaFallback(.shiba, .focus, exists: has(withShiba)))
        let withPandaFocus = pandaOnly.union(["notch-panda-focus"])
        XCTAssertEqual(NotchMascotArt.resolve(.panda, .focus, blinking: true, exists: has(withPandaFocus)),
                       "notch-panda-focus")
    }

    func testOwnArtWinsPerPose() {
        let some = pandaOnly.union(["notch-cat-done"])
        XCTAssertEqual(NotchMascotArt.resolve(.cat, .done, exists: has(some)), "notch-cat-done")
        XCTAssertEqual(NotchMascotArt.resolve(.cat, .sleep, exists: has(some)), "notch-panda-sleep",
                       "只补了一张时，其余样子仍回退")
    }

    func testNothingAtAllIsNil() {
        XCTAssertNil(NotchMascotArt.resolve(.otter, .focus, exists: { _ in false }))
        XCTAssertFalse(NotchMascotArt.usesPandaFallback(.otter, .focus, exists: { _ in false }))
    }

    func testLockedProMascotShowsPandaArt() {
        var state = TimerState()
        state.mascot = "octopus"
        let shown = FocusMascot.of(state, unlocked: false)
        XCTAssertEqual(shown, .panda, "没解锁时刘海和面板一样只能是小熊猫")
        let all = pandaOnly.union(["notch-octopus-focus"])
        XCTAssertEqual(NotchMascotArt.resolve(shown, .focus, exists: has(all)), "notch-panda-hang")
        XCTAssertEqual(NotchMascotArt.resolve(FocusMascot.of(state, unlocked: true), .focus, exists: has(all)),
                       "notch-octopus-focus")
    }

    // MARK: 收起时的小头

    func testPeek() {
        XCTAssertEqual(NotchMascotArt.peek(.panda, exists: has(pandaOnly)), .image("notch-panda-peek"))
        XCTAssertEqual(NotchMascotArt.peek(.shiba, exists: has(pandaOnly)), .panelStill,
                       "别的吉祥物没有小头时照旧用面板状态图")
        XCTAssertEqual(NotchMascotArt.peek(.shiba, exists: has(pandaOnly.union(["notch-shiba-peek"]))),
                       .image("notch-shiba-peek"))
        XCTAssertEqual(NotchMascotArt.peek(.panda, exists: { _ in false }), .panelStill)
    }

    // MARK: 道具

    func testPropNames() {
        XCTAssertNil(FocusMascotProp.imageName(.panda), "小熊猫用竹竿")
        XCTAssertEqual(FocusMascotProp.imageName(.shiba), "prop-shiba")
        XCTAssertEqual(FocusMascotProp.imageName(.octopus), "prop-octopus")
        for mascot in FocusMascot.allCases where mascot != .panda {
            XCTAssertNotNil(FocusMascotProp.imageName(mascot))
        }
    }

    func testPropMissingDrawsNothing() {
        XCTAssertNil(FocusMascotProp.resolve(.cat, exists: { _ in false }))
        XCTAssertEqual(FocusMascotProp.resolve(.cat, exists: { $0 == "prop-cat" }), "prop-cat")
        XCTAssertNil(FocusMascotProp.resolve(.panda, exists: { _ in true }))
    }

    func testPropBobRespectsReduceMotion() {
        XCTAssertEqual(FocusMascotProp.bob(at: 0.75, running: true, reduceMotion: true), 0)
        XCTAssertEqual(FocusMascotProp.bob(at: 0.75, running: false, reduceMotion: false), 0)
        XCTAssertLessThanOrEqual(abs(FocusMascotProp.bob(at: 0.75, running: true, reduceMotion: false)),
                                 FocusMascotProp.bobAmplitude + 0.0001)
        XCTAssertNotEqual(FocusMascotProp.bob(at: 0.75, running: true, reduceMotion: false), 0)
    }
}
