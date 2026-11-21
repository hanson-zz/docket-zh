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
        XCTAssertEqual(normal.maxX, 486)
        XCTAssertEqual(normal.maxY, 386)
        // 左下角放不下：翻到右边和上面。
        let corner = DesktopPetPointerPeek.frame(pointer: CGPoint(x: 10, y: 20), size: size, bounds: bounds)
        XCTAssertEqual(corner.minX, 24)
        XCTAssertEqual(corner.minY, 34)
        XCTAssertTrue(bounds.contains(corner))
    }

    func testImageCandidates() {
        XCTAssertEqual(DesktopPetPointerPeek.imageCandidates(.shiba, focusing: false),
                       ["desk-shiba-peek", "focus-mascot-shiba-idle"])
        XCTAssertEqual(DesktopPetPointerPeek.imageCandidates(.panda, focusing: true),
                       ["desk-panda-peek", "focus-mascot-panda-focus"])
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
