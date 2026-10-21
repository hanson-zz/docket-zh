import Foundation
import XCTest

/// 菜单栏 ▸ 位置：方式的读写、沿边对齐、浮动位置和换屏回退。
final class ShelfPlacementTests: XCTestCase {
    private typealias P = ShelfPlacement

    private let bounds = CGRect(x: 0, y: 0, width: 1000, height: 600)
    private let size = CGSize(width: 200, height: 60)

    private func settings(_ edit: (inout CustomDockSettings) -> Void = { _ in }) -> CustomDockSettings {
        var dock = CustomDockSettings()
        edit(&dock)
        return dock
    }

    // MARK: 旧状态

    func testOldStateDecodesWithDefaults() throws {
        let old = try JSONDecoder().decode(CustomDockSettings.self, from: Data(#"{"position": "left"}"#.utf8))
        XCTAssertEqual(old.alignment, .center)
        XCTAssertFalse(old.pinned)
        XCTAssertFalse(old.floating)
        XCTAssertEqual(old.floatingSpots, [:])
        XCTAssertNil(old.floatingDisplayID)
        XCTAssertEqual(old.position, .left)
    }

    func testUnknownAlignmentFallsBackToCenter() throws {
        let odd = try JSONDecoder().decode(CustomDockSettings.self, from: Data(#"{"alignment": "diagonal"}"#.utf8))
        XCTAssertEqual(odd.alignment, .center)
    }

    func testNewFieldsSurviveARestart() throws {
        let dock = settings {
            $0.alignment = .trailing
            $0.pinned = true
            $0.floating = true
            $0.floatingSpots = ["42": FloatingSpot(x: 10, y: 20)]
            $0.floatingDisplayID = 42
        }
        let back = try JSONDecoder().decode(CustomDockSettings.self, from: JSONEncoder().encode(dock))
        XCTAssertEqual(back, dock)
    }

    // MARK: 固定的八个位置

    func testPinsCoverEightDistinctPlaces() {
        XCTAssertEqual(ShelfPin.allCases.count, 8)
        let pairs = Set(ShelfPin.allCases.map { "\($0.edge)-\($0.alignment)" })
        XCTAssertEqual(pairs.count, 8)
        for pin in ShelfPin.allCases {
            XCTAssertEqual(ShelfPin(edge: pin.edge, alignment: pin.alignment), pin)
            XCTAssertFalse(pin.title.isEmpty)
        }
        XCTAssertEqual(ShelfPin.topLeft.edge, .top)
        XCTAssertEqual(ShelfPin.topLeft.alignment, .leading)
        XCTAssertEqual(ShelfPin.bottomRight.edge, .bottom)
        XCTAssertEqual(ShelfPin.bottomRight.alignment, .trailing)
        XCTAssertEqual(ShelfPin.leftCenter.edge, .left)
        // 竖边只有居中。
        XCTAssertNil(ShelfPin(edge: .left, alignment: .leading))
        XCTAssertNil(ShelfPin(edge: .right, alignment: .trailing))
    }

    // MARK: 读

    func testModeReadsEverySetup() {
        XCTAssertNil(P.mode(setup: .macOSDockOnly, settings: settings()))
        XCTAssertEqual(P.mode(setup: .both, settings: settings()), .beside)
        let own = settings { $0.followSystemDock = false }
        XCTAssertEqual(P.mode(setup: .both, settings: own), .beside)
        XCTAssertEqual(P.mode(setup: .both, settings: settings { $0.followSystemDock = false; $0.position = .top }), .top)
        XCTAssertEqual(P.mode(setup: .customReplacement, settings: own), .replace)
        XCTAssertEqual(P.mode(setup: .customReplacement,
                              settings: settings { $0.followSystemDock = false; $0.autoHide = true }),
                       .replaceAutoHide)
        XCTAssertEqual(P.mode(setup: .both, settings: settings { $0.floating = true }), .floating)
        XCTAssertEqual(P.mode(setup: .customReplacement, settings: settings { $0.floating = true }), .floating)
    }

    func testFollowingTheDockIsBesideWhateverIsStored() {
        let stale = settings { $0.position = .top; $0.alignment = .leading }
        XCTAssertEqual(P.mode(setup: .both, settings: stale), .beside)
        XCTAssertEqual(P.effectiveAlignment(setup: .both, settings: stale, borrowingStrut: false), .center)
    }

    func testStaleAutoHideWhileFollowingIsStillPlainReplace() {
        // 跟随程序坞时设置页不显示自动隐藏开关，存着的旧值不能把替换变成隐藏。
        let stale = settings { $0.autoHide = true }
        XCTAssertEqual(P.mode(setup: .customReplacement, settings: stale), .replace)
        XCTAssertTrue(P.wantsStrut(setup: .customReplacement, settings: stale))
    }

    func testPinnedFlagOnlyDecidesLookalikes() {
        let bottomCenter = settings { $0.followSystemDock = false; $0.position = .bottom }
        XCTAssertEqual(P.mode(setup: .both, settings: bottomCenter), .beside)
        var pinned = bottomCenter
        pinned.pinned = true
        XCTAssertEqual(P.mode(setup: .both, settings: pinned), .pinned(.bottomCenter))
        // 对齐不是居中时不看标记，一定是固定。
        let corner = settings { $0.followSystemDock = false; $0.position = .top; $0.alignment = .trailing }
        XCTAssertEqual(P.mode(setup: .both, settings: corner), .pinned(.topRight))
    }

    func testSummariesAreNotEmpty() {
        let modes: [ShelfPlacementMode] = [.beside, .top, .replace, .replaceAutoHide, .floating]
            + ShelfPin.allCases.map { .pinned($0) }
        for mode in modes { XCTAssertFalse(mode.summary.isEmpty) }
    }

    // MARK: 写

    func testEveryMenuChoiceReadsBackAsItself() {
        let modes: [ShelfPlacementMode] = [.beside, .top, .replace, .replaceAutoHide, .floating]
            + ShelfPin.allCases.map { .pinned($0) }
        let starts: [(DockSetup, CustomDockSettings)] = [
            (.both, settings()),
            (.both, settings { $0.followSystemDock = false; $0.position = .top }),
            (.customReplacement, settings { $0.followSystemDock = false; $0.autoHide = true }),
            (.both, settings { $0.floating = true }),
        ]
        for (setup, start) in starts {
            for mode in modes {
                let result = P.applying(mode, setup: setup, settings: start, currentScale: 0.5)
                XCTAssertEqual(P.mode(setup: result.setup, settings: result.settings), mode,
                               "\(mode) from \(setup)")
            }
        }
    }

    func testChoosingAnExplicitEdgeStopsFollowingAndKeepsTheSize() {
        let result = P.applying(.pinned(.topLeft), setup: .both, settings: settings(), currentScale: 0.6)
        XCTAssertFalse(result.settings.followSystemDock)
        XCTAssertEqual(result.settings.scale, 0.6)
        XCTAssertEqual(result.settings.position, .top)
        XCTAssertEqual(result.settings.alignment, .leading)
        // 并排和替换不关跟随。
        XCTAssertTrue(P.applying(.beside, setup: .both, settings: settings(), currentScale: 0.6)
            .settings.followSystemDock)
        XCTAssertTrue(P.applying(.replace, setup: .both, settings: settings(), currentScale: 0.6)
            .settings.followSystemDock)
    }

    func testReplaceLeavesTheTopEdge() {
        let top = settings { $0.followSystemDock = false; $0.position = .top }
        let result = P.applying(.replace, setup: .both, settings: top, currentScale: 0.5)
        XCTAssertEqual(result.setup, .customReplacement)
        XCTAssertEqual(result.settings.position, .bottom)
        XCTAssertTrue(P.wantsStrut(setup: result.setup, settings: result.settings))
    }

    func testReplaceAutoHideNeedsNoStrut() {
        let result = P.applying(.replaceAutoHide, setup: .both, settings: settings(), currentScale: 0.5)
        XCTAssertTrue(result.settings.autoHide)
        XCTAssertFalse(P.wantsStrut(setup: result.setup, settings: result.settings))
        XCTAssertTrue(P.autoHides(setup: result.setup, settings: result.settings, systemAutoHide: false))
    }

    func testLeavingReplaceAutoHideTurnsHidingOff() {
        let hidden = P.applying(.replaceAutoHide, setup: .both, settings: settings(), currentScale: 0.5)
        let beside = P.applying(.beside, setup: hidden.setup, settings: hidden.settings, currentScale: 0.5)
        XCTAssertFalse(beside.settings.autoHide)
        XCTAssertEqual(beside.setup, .both)
    }

    func testFloatingGoesBackToBothAndNeverHides() {
        let start = settings { $0.followSystemDock = false; $0.autoHide = true }
        let result = P.applying(.floating, setup: .customReplacement, settings: start, currentScale: 0.5)
        XCTAssertEqual(result.setup, .both)
        XCTAssertTrue(result.settings.floating)
        XCTAssertFalse(P.wantsStrut(setup: .customReplacement, settings: result.settings))
        XCTAssertFalse(P.autoHides(setup: result.setup, settings: result.settings, systemAutoHide: true))
        XCTAssertEqual(P.effectiveAlignment(setup: result.setup, settings: result.settings,
                                            borrowingStrut: false), .center)
    }

    func testEdgeChoiceKeepsReplacementAndRecentres() {
        let pinned = P.applying(.pinned(.bottomLeft), setup: .both, settings: settings(), currentScale: 0.5)
        let left = P.applyingEdge(.left, setup: pinned.setup, settings: pinned.settings, currentScale: 0.5)
        XCTAssertEqual(left.setup, .both)
        XCTAssertEqual(left.settings.position, .left)
        XCTAssertEqual(left.settings.alignment, .center)
        XCTAssertEqual(P.mode(setup: left.setup, settings: left.settings), .beside)

        let replacing = P.applyingEdge(.right, setup: .customReplacement, settings: settings(), currentScale: 0.5)
        XCTAssertEqual(replacing.setup, .customReplacement)
        XCTAssertEqual(replacing.settings.position, .right)
        // 顶部不是“贴哪条边”的选项，误传进来也回到底部。
        XCTAssertEqual(P.applyingEdge(.top, setup: .both, settings: settings(), currentScale: 0.5)
            .settings.position, .bottom)
    }

    func testResetGoesBackToBesideAtTheBottom() {
        let messy = settings {
            $0.floating = true
            $0.position = .right
            $0.alignment = .trailing
            $0.pinned = true
            $0.autoHide = true
            $0.floatingSpots = ["1": FloatingSpot(x: 5, y: 5)]
            $0.floatingDisplayID = 1
        }
        let result = P.reset(setup: .customReplacement, settings: messy, currentScale: 0.4)
        XCTAssertEqual(result.setup, .both)
        XCTAssertEqual(result.settings.position, .bottom)
        XCTAssertEqual(result.settings.alignment, .center)
        XCTAssertFalse(result.settings.floating)
        XCTAssertFalse(result.settings.pinned)
        XCTAssertFalse(result.settings.autoHide)
        XCTAssertTrue(result.settings.floatingSpots.isEmpty)
        XCTAssertNil(result.settings.floatingDisplayID)
        XCTAssertEqual(P.mode(setup: result.setup, settings: result.settings), .beside)
    }

    // MARK: 对齐

    func testCenterMatchesTheOldPlacement() {
        for edge in DockPosition.allCases {
            XCTAssertEqual(P.alignedOrigin(edge: edge, alignment: .center, size: size, bounds: bounds, inset: 6),
                           Geometry.shelfOrigin(edge: edge, size: size, bounds: bounds, inset: 6))
        }
    }

    func testHorizontalAlignmentOffsets() {
        let left = P.alignedOrigin(edge: .bottom, alignment: .leading, size: size, bounds: bounds, inset: 6)
        XCTAssertEqual(left, CGPoint(x: 6, y: 6))
        let right = P.alignedOrigin(edge: .top, alignment: .trailing, size: size, bounds: bounds, inset: 6)
        XCTAssertEqual(right, CGPoint(x: 1000 - 200 - 6, y: 600 - 60 - 6))
    }

    func testVerticalAlignmentOffsets() {
        let tall = CGSize(width: 60, height: 200)
        let top = P.alignedOrigin(edge: .left, alignment: .leading, size: tall, bounds: bounds, inset: 6)
        XCTAssertEqual(top, CGPoint(x: 6, y: 600 - 200 - 6))
        let bottom = P.alignedOrigin(edge: .right, alignment: .trailing, size: tall, bounds: bounds, inset: 6)
        XCTAssertEqual(bottom, CGPoint(x: 1000 - 60 - 6, y: 6))
    }

    func testAlignedShelfLargerThanTheScreenStaysOnIt() {
        let wide = CGSize(width: 1400, height: 60)
        let origin = P.alignedOrigin(edge: .bottom, alignment: .trailing, size: wide, bounds: bounds, inset: 6)
        XCTAssertEqual(origin.x, 0)
    }

    // MARK: 浮动

    func testFloatingDefaultIsCentredLowOnTheScreen() {
        let visible = CGRect(x: 100, y: 50, width: 1000, height: 600)
        let origin = P.floatingOrigin(saved: nil, size: size, visible: visible)
        XCTAssertEqual(origin.x, visible.midX - 100)
        XCTAssertEqual(origin.y, 50 + 120)
    }

    func testFloatingSpotIsRelativeToTheVisibleArea() {
        let visible = CGRect(x: 100, y: 50, width: 1000, height: 600)
        let spot = P.floatingSpot(origin: CGPoint(x: 400, y: 300), size: size, visible: visible)
        XCTAssertEqual(spot, FloatingSpot(x: 300, y: 250))
        XCTAssertEqual(P.floatingOrigin(saved: spot, size: size, visible: visible), CGPoint(x: 400, y: 300))
        // 同一块屏幕挪了位置（排列变了），还在它上面的同一处。
        let moved = CGRect(x: -900, y: 0, width: 1000, height: 600)
        XCTAssertEqual(P.floatingOrigin(saved: spot, size: size, visible: moved), CGPoint(x: -600, y: 250))
    }

    func testFloatingIsClampedIntoTheVisibleArea() {
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 600)
        let far = P.floatingOrigin(saved: FloatingSpot(x: 5000, y: -300), size: size, visible: visible)
        XCTAssertEqual(far, CGPoint(x: 800, y: 0))
        // 换到一块更小的屏幕，原来的偏移挂出去了，也夹回来。
        let small = CGRect(x: 0, y: 0, width: 500, height: 300)
        let shrunk = P.floatingOrigin(saved: FloatingSpot(x: 700, y: 400), size: size, visible: small)
        XCTAssertEqual(shrunk, CGPoint(x: 300, y: 240))
        // 记下来的也是夹过的。
        XCTAssertEqual(P.floatingSpot(origin: CGPoint(x: -50, y: 900), size: size, visible: visible),
                       FloatingSpot(x: 0, y: 540))
        // 写坏的数不当真。
        let broken = P.floatingOrigin(saved: FloatingSpot(x: .nan, y: 3), size: size, visible: visible)
        XCTAssertEqual(broken, P.floatingOrigin(saved: nil, size: size, visible: visible))
    }

    func testFloatingFacingFollowsTheHalfOfTheScreen() {
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 600)
        XCTAssertTrue(P.floatingFacesDown(origin: CGPoint(x: 0, y: 500), size: size, visible: visible))
        XCTAssertFalse(P.floatingFacesDown(origin: CGPoint(x: 0, y: 40), size: size, visible: visible))
        // 中心正好在中线上算下半，朝上弹。
        XCTAssertFalse(P.floatingFacesDown(origin: CGPoint(x: 0, y: 270), size: size, visible: visible))
    }

    func testFloatingDisplayFallsBackWhenTheScreenIsGone() {
        XCTAssertEqual(P.floatingDisplay(last: 2, connected: [1, 2], fallback: 1), 2)
        XCTAssertEqual(P.floatingDisplay(last: 3, connected: [1, 2], fallback: 1), 1)
        XCTAssertEqual(P.floatingDisplay(last: nil, connected: [1, 2], fallback: 2), 2)
        XCTAssertEqual(P.floatingDisplay(last: 3, connected: [5], fallback: 4), 5)
        XCTAssertNil(P.floatingDisplay(last: 3, connected: [], fallback: 4))
        XCTAssertEqual(P.spotKey(69733632), "69733632")
    }
}
