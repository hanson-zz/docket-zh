import Foundation
import XCTest

/// 锁定扩展栏：锁住时只停改布局的操作，打开和悬停照常；旧配置不锁。
final class ShelfLockTests: XCTestCase {
    private let layoutActions: [ShelfLockAction] = [
        .reorder, .combine, .dragOutOfGroup, .dropIn, .moveFloatingShelf,
        .remove, .ungroup, .addToGroup, .addSpacer, .keepInDock,
    ]
    private let useActions: [ShelfLockAction] = [
        .open, .hover, .magnify, .contextOpen, .widgetSettings,
    ]

    func testEveryActionIsClassified() {
        XCTAssertEqual(Set(layoutActions + useActions), Set(ShelfLockAction.allCases))
        XCTAssertTrue(layoutActions.allSatisfy(\.changesLayout))
        XCTAssertFalse(useActions.contains(where: \.changesLayout))
    }

    func testUnlockedAllowsEverything() {
        for action in ShelfLockAction.allCases {
            XCTAssertTrue(ShelfLock.allows(action, locked: false), action.rawValue)
        }
    }

    func testLockedStopsLayoutChanges() {
        for action in layoutActions {
            XCTAssertFalse(ShelfLock.allows(action, locked: true), action.rawValue)
        }
    }

    func testLockedKeepsUsing() {
        for action in useActions {
            XCTAssertTrue(ShelfLock.allows(action, locked: true), action.rawValue)
        }
    }

    func testReadsTheSetting() {
        var settings = CustomDockSettings()
        XCTAssertTrue(ShelfLock.allows(.reorder, settings: settings))
        settings.locked = true
        XCTAssertFalse(ShelfLock.allows(.reorder, settings: settings))
        XCTAssertTrue(ShelfLock.allows(.open, settings: settings))
    }

    // MARK: 配置

    func testOldStateIsUnlocked() throws {
        let old = try JSONDecoder().decode(CustomDockSettings.self, from: Data(#"{"position": "left"}"#.utf8))
        XCTAssertFalse(old.locked)
        XCTAssertFalse(CustomDockSettings().locked)
    }

    func testOddValueFallsBackToUnlocked() throws {
        let odd = try JSONDecoder().decode(CustomDockSettings.self, from: Data(#"{"locked": "yes"}"#.utf8))
        XCTAssertFalse(odd.locked)
    }

    func testLockSurvivesARestart() throws {
        var settings = CustomDockSettings()
        settings.locked = true
        let data = try JSONEncoder().encode(settings)
        XCTAssertTrue(try JSONDecoder().decode(CustomDockSettings.self, from: data).locked)
    }

    // MARK: 抖动提示

    func testShakeStartsAndEndsAtRest() {
        XCTAssertEqual(ShelfLock.shakeOffset(progress: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(ShelfLock.shakeOffset(progress: 1), 0, accuracy: 1e-9)
        // 超出范围按两头算，不会停在半路。
        XCTAssertEqual(ShelfLock.shakeOffset(progress: 1.4), 0, accuracy: 1e-9)
        XCTAssertEqual(ShelfLock.shakeOffset(progress: -0.2), 0, accuracy: 1e-9)
    }

    func testShakeIsLightAndActuallyMoves() {
        let samples = stride(from: 0.0, through: 1.0, by: 0.01).map { ShelfLock.shakeOffset(progress: $0) }
        // 轻轻一抖：不超过 4pt，整段不到半秒。
        XCTAssertTrue(samples.allSatisfy { abs($0) <= ShelfLock.shakeAmplitude })
        XCTAssertGreaterThan(samples.map(abs).max() ?? 0, 1)
        XCTAssertTrue(samples.contains { $0 < 0 } && samples.contains { $0 > 0 })
        XCTAssertLessThan(ShelfLock.shakeDuration, 0.5)
    }

    func testShakeOncePerGesture() {
        XCTAssertTrue(ShelfLock.shouldShake(locked: true, alreadyNudged: false))
        XCTAssertFalse(ShelfLock.shouldShake(locked: true, alreadyNudged: true))
        XCTAssertFalse(ShelfLock.shouldShake(locked: false, alreadyNudged: false))
    }
}
