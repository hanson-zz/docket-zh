import Foundation
import XCTest

/// 指针旁探头：什么时候出来、放哪、用哪张图、两个新开关的默认值和老状态文件。
final class DesktopPetPointerPeekTests: XCTestCase {
    func testWanted() {
        XCTAssertFalse(DesktopPetPointerPeek.wanted(pointerIdle: 10, keyIdle: 60, quiet: false, pressed: false))
        XCTAssertTrue(DesktopPetPointerPeek.wanted(pointerIdle: 25, keyIdle: 60, quiet: false, pressed: false))
        // 正在打字、要安静、按着鼠标都不出来。
        XCTAssertFalse(DesktopPetPointerPeek.wanted(pointerIdle: 25, keyIdle: 2, quiet: false, pressed: false))
        XCTAssertFalse(DesktopPetPointerPeek.wanted(pointerIdle: 25, keyIdle: 60, quiet: true, pressed: false))
        XCTAssertFalse(DesktopPetPointerPeek.wanted(pointerIdle: 25, keyIdle: 60, quiet: false, pressed: true))
        // 人走开了收起；一直打字、刚停下（鼠标静止很久）还是出来。
        XCTAssertFalse(DesktopPetPointerPeek.wanted(pointerIdle: 400, keyIdle: 400, quiet: false, pressed: false))
        XCTAssertTrue(DesktopPetPointerPeek.wanted(pointerIdle: 400, keyIdle: 8, quiet: false, pressed: false))
    }

    func testMoved() {
        XCTAssertFalse(DesktopPetPointerPeek.moved(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 102, y: 101)))
        XCTAssertTrue(DesktopPetPointerPeek.moved(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 110, y: 100)))
    }

    func testFrame() {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let size = CGSize(width: 54, height: 64)
        let normal = DesktopPetPointerPeek.frame(pointer: CGPoint(x: 500, y: 400), size: size, bounds: bounds)
        XCTAssertEqual(normal.maxX, 490)
        XCTAssertEqual(normal.maxY, 390)
        // 左下角放不下：翻到右边和上面。
        let corner = DesktopPetPointerPeek.frame(pointer: CGPoint(x: 10, y: 20), size: size, bounds: bounds)
        XCTAssertEqual(corner.minX, 20)
        XCTAssertEqual(corner.minY, 30)
        XCTAssertTrue(bounds.contains(corner))
    }

    func testImageCandidates() {
        XCTAssertEqual(DesktopPetPointerPeek.imageCandidates(.shiba), ["desk-shiba-peek", "pet-sprite-shiba-sit"])
        XCTAssertEqual(DesktopPetPointerPeek.imageCandidates(.panda), ["desk-panda-peek", "pet-sprite-front-sit-1"])
        XCTAssertEqual(DesktopPetPointerPeek.cut(forImage: "desk-cat-peek", mascot: .cat), DesktopPetPointerPeek.cut(.cat))
        XCTAssertEqual(DesktopPetPointerPeek.cut(forImage: "pet-sprite-cat-sit", mascot: .cat), DesktopPetPointerPeek.uncut)
    }

    /// 扒边探头：六只的耳朵尖和前爪压边线对齐到同一行（遮罩边在图底上面一点），头约占露出来那截的四分之三。
    func testCutsKeepHeadPawsAndALittleChest() {
        for mascot in FocusMascot.allCases {
            let cut = DesktopPetPointerPeek.cut(mascot)
            XCTAssertEqual(cut.top, 2.0 / 192, accuracy: 0.0001, "\(mascot) 耳朵尖露全")
            XCTAssertEqual(cut.edge, 184.0 / 192, accuracy: 0.0001, "\(mascot) 压边线六只同一高度")
            XCTAssertGreaterThan(cut.edge, 0.92, "\(mascot) 边在前爪下沿，不切在身子中段")
            XCTAssertLessThanOrEqual(cut.edge, 0.97, "\(mascot) 爪子圆底藏到边后面")
            XCTAssertGreaterThan(cut.chin, cut.top)
            XCTAssertLessThan(cut.chin, cut.edge - 0.1, "\(mascot) 下巴下面还有爪子和一点胸口")
            XCTAssertEqual(cut.headShare, 0.76, accuracy: 0.05, "\(mascot) 头约占四分之三")
        }
        XCTAssertEqual(DesktopPetPointerPeek.cut(.cat).chin, 146.0 / 192, accuracy: 0.0001)
        XCTAssertEqual(DesktopPetPointerPeek.cut(.otter).chin, 138.0 / 192, accuracy: 0.0001)
    }

    /// 可见高度六只统一，比原来整张 64 点小；宽度按新图（@2x 都是 192 像素高）。
    func testVisibleHeightIsUniform() {
        XCTAssertEqual(DesktopPetPointerPeek.visibleHeight, 40)
        let sizes: [FocusMascot: CGSize] = [.cat: CGSize(width: 218, height: 192), .octopus: CGSize(width: 212, height: 192),
                                            .otter: CGSize(width: 258, height: 192), .panda: CGSize(width: 244, height: 192),
                                            .penguin: CGSize(width: 244, height: 192), .shiba: CGSize(width: 216, height: 192)]
        for (mascot, size) in sizes {
            let layout = DesktopPetPointerPeek.layout(imageSize: size, cut: DesktopPetPointerPeek.cut(mascot), scale: 1)
            XCTAssertEqual(layout.visible.height, 40, accuracy: 0.001, "\(mascot)")
            // 最宽的水獭约 57 点。
            XCTAssertLessThanOrEqual(layout.visible.width, 58, "\(mascot)")
            // 图底下一截在边下面（y < 0），图顶比露出来那截的顶高一点点（耳朵尖上面留的 2 行）。
            XCTAssertLessThan(layout.image.minY, 0)
            XCTAssertEqual(layout.image.maxY, 40, accuracy: 0.6)
            XCTAssertEqual(layout.panel.height, 40 + DesktopPetPointerPeek.margin * 2, accuracy: 0.001)
        }
        let large = DesktopPetPointerPeek.layout(imageSize: CGSize(width: 216, height: 192),
                                                 cut: DesktopPetPointerPeek.cut(.shiba), scale: 1.25)
        XCTAssertEqual(large.visible.height, 50, accuracy: 0.001)
    }

    func testLeanTowardsPointer() {
        XCTAssertGreaterThanOrEqual(DesktopPetPointerPeek.tiltDegrees, 3)
        XCTAssertLessThanOrEqual(DesktopPetPointerPeek.tiltDegrees, 5)
        XCTAssertEqual(DesktopPetPointerPeek.lean(pointerOnRight: true), DesktopPetPointerPeek.tiltDegrees)
        XCTAssertEqual(DesktopPetPointerPeek.lean(pointerOnRight: false), -DesktopPetPointerPeek.tiltDegrees)
    }

    /// 出场三段：从边下升起 6 到 10 点，停住压一下，轻轻回弹落定；减弱动态效果时直接出现。
    func testEntrance() {
        XCTAssertTrue(DesktopPetPointerPeek.entrance(reduceMotion: true).isEmpty)
        let frames = DesktopPetPointerPeek.entrance(reduceMotion: false)
        XCTAssertEqual(frames.first?.time, 0)
        XCTAssertEqual(frames.last?.time, 1)
        XCTAssertEqual(frames.map(\.time), frames.map(\.time).sorted())
        let start = -(frames.first?.rise ?? 0)
        XCTAssertGreaterThanOrEqual(start, 6)
        XCTAssertLessThanOrEqual(start, 10)
        XCTAssertTrue(frames.contains { $0.rise == 0 && $0.squash < 1 }, "停住时压一下")
        XCTAssertTrue(frames.contains { $0.rise > 0 }, "轻微回弹")
        XCTAssertLessThanOrEqual(frames.map(\.rise).max() ?? 0, 3)
        XCTAssertEqual(frames.last?.rise, 0)
        XCTAssertEqual(frames.last?.squash, 1)
    }

    func testSettingsDefaultsAndLegacy() throws {
        let fresh = DesktopPetSettings()
        XCTAssertFalse(fresh.pointerPeek)
        XCTAssertTrue(fresh.quietInCalls)
        let legacy = try JSONDecoder().decode(DesktopPetSettings.self, from: Data(#"{"enabled":true}"#.utf8))
        XCTAssertFalse(legacy.pointerPeek)
        XCTAssertTrue(legacy.quietInCalls)
        let changed = DesktopPetSettings(enabled: true, pointerPeek: true, quietInCalls: false)
        let round = try JSONDecoder().decode(DesktopPetSettings.self, from: JSONEncoder().encode(changed))
        XCTAssertEqual(round, changed)
    }
}
