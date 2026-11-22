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
        // 指针旁一律用完整的一只，不再用身体截平的趴姿探头图。
        XCTAssertEqual(DesktopPetPointerPeek.imageCandidates(.shiba, focusing: false),
                       ["pet-sprite-shiba-sit", "focus-mascot-shiba-idle"])
        XCTAssertEqual(DesktopPetPointerPeek.imageCandidates(.panda, focusing: false),
                       ["pet-sprite-front-sit-1", "focus-mascot-panda-idle"])
        XCTAssertEqual(DesktopPetPointerPeek.imageCandidates(.panda, focusing: true),
                       ["focus-mascot-panda-focus", "pet-sprite-front-sit-1", "focus-mascot-panda-idle"])
        for mascot in FocusMascot.allCases {
            for focusing in [false, true] {
                XCTAssertFalse(DesktopPetPointerPeek.imageCandidates(mascot, focusing: focusing)
                    .contains { $0.hasSuffix("-peek") }, "\(mascot)")
            }
        }
    }

    func testSizeIsSmall() {
        XCTAssertEqual(DesktopPetPointerPeek.baseHeight, 40)
        // 柴犬坐姿 100×130：中号 40 点高、约 31 点宽，比原来趴姿 55×64 小一圈。
        let shiba = DesktopPetPointerPeek.size(imageSize: CGSize(width: 100, height: 130), scale: 1)
        XCTAssertEqual(shiba.height, 40)
        XCTAssertEqual(shiba.width, 30.77, accuracy: 0.01)
        let large = DesktopPetPointerPeek.size(imageSize: CGSize(width: 130, height: 130), scale: 1.25)
        XCTAssertEqual(large.height, 50)
        XCTAssertLessThanOrEqual(large.width, 50)
        XCTAssertEqual(DesktopPetPointerPeek.rise(reduceMotion: true), 0)
        XCTAssertGreaterThan(DesktopPetPointerPeek.rise(reduceMotion: false), 0)
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
