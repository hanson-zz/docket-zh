import CoreGraphics
import Foundation
import XCTest

/// 分组窗口、文件夹小窗「点了不弹」的几条边角（beta.32 真机反馈）。
final class PopupToggleTests: XCTestCase {

    private final class Counter { var value = 0 }

    private let a = UUID()
    private let b = UUID()
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000)
    private let tile = CGPoint(x: 500, y: 40)

    private func decide(_ requested: UUID, open: UUID?, visible: Bool,
                        repeatOfOpen: Bool = false, swallows: Bool = false,
                        asked: Counter? = nil) -> PopupToggle.Decision {
        PopupToggle.decide(requested: requested, openID: open, visible: visible,
                           repeatOfOpen: repeatOfOpen,
                           swallow: { asked?.value += 1; return swallows })
    }

    // MARK: 开还是关

    func testClosedTileOpens() {
        XCTAssertEqual(decide(a, open: nil, visible: false), .open)
    }

    func testOpenTileClickedAgainCloses() {
        XCTAssertEqual(decide(a, open: a, visible: true), .close)
    }

    func testOtherTileOpensInstead() {
        XCTAssertEqual(decide(b, open: a, visible: true), .open)
    }

    /// 记着开着但窗口没在显示（摆位置失败、被系统收走）：以前当成「再点一次关掉」，
    /// 关一个看不见的窗口，之后一直点不开。现在直接打开。
    func testStaleOpenIDWithHiddenWindowOpens() {
        XCTAssertEqual(decide(a, open: a, visible: false), .open)
    }

    func testStaleOpenIDStillHonoursReopenGuard() {
        XCTAssertEqual(decide(a, open: a, visible: false, swallows: true), .ignore)
    }

    /// 双击格子的第二下：不关。
    func testRepeatClickRightAfterOpenIsIgnored() {
        XCTAssertEqual(decide(a, open: a, visible: true, repeatOfOpen: true), .ignore)
    }

    func testSwallowedOpenIsIgnored() {
        XCTAssertEqual(decide(a, open: nil, visible: false, swallows: true), .ignore)
    }

    /// 防重开只在真要打开时问（问了就用掉），收起时不能把它用掉。
    func testSwallowAskedOnlyWhenOpening() {
        let asked = Counter()
        _ = decide(a, open: a, visible: true, asked: asked)
        XCTAssertEqual(asked.value, 0)
        _ = decide(a, open: a, visible: true, repeatOfOpen: true, asked: asked)
        XCTAssertEqual(asked.value, 0)
        _ = decide(b, open: a, visible: true, asked: asked)
        XCTAssertEqual(asked.value, 1)
    }

    // MARK: 连点宽限

    func testGraceWindowClampedToDoubleClickRange() {
        XCTAssertEqual(PopupToggle.OpenGrace.window(doubleClickInterval: 0.1), 0.25)
        XCTAssertEqual(PopupToggle.OpenGrace.window(doubleClickInterval: 0.4), 0.4)
        XCTAssertEqual(PopupToggle.OpenGrace.window(doubleClickInterval: 5), 0.5)
        XCTAssertEqual(PopupToggle.OpenGrace.window(doubleClickInterval: 0), 0.25)
        XCTAssertEqual(PopupToggle.OpenGrace.window(doubleClickInterval: .nan), 0.25)
    }

    func testSecondClickOfDoubleClickIsRepeat() {
        var grace = PopupToggle.OpenGrace()
        grace.noteOpened(id: a, at: t0, point: tile, doubleClickInterval: 0.4)
        XCTAssertTrue(grace.isRepeat(id: a, at: t0.addingTimeInterval(0.2),
                                     point: CGPoint(x: 503, y: 42)))
        XCTAssertTrue(grace.isRepeat(at: t0.addingTimeInterval(0.2), point: tile))
    }

    func testLaterClickIsNotRepeat() {
        var grace = PopupToggle.OpenGrace()
        grace.noteOpened(id: a, at: t0, point: tile, doubleClickInterval: 0.4)
        XCTAssertFalse(grace.isRepeat(id: a, at: t0.addingTimeInterval(0.6), point: tile))
    }

    func testFarClickIsNotRepeat() {
        var grace = PopupToggle.OpenGrace()
        grace.noteOpened(id: a, at: t0, point: tile, doubleClickInterval: 0.4)
        XCTAssertFalse(grace.isRepeat(at: t0.addingTimeInterval(0.1), point: CGPoint(x: 560, y: 40)))
    }

    func testOtherTileIsNotRepeat() {
        var grace = PopupToggle.OpenGrace()
        grace.noteOpened(id: a, at: t0, point: tile, doubleClickInterval: 0.4)
        XCTAssertFalse(grace.isRepeat(id: b, at: t0.addingTimeInterval(0.1), point: tile))
    }

    func testClockGoingBackwardsIsNotRepeat() {
        var grace = PopupToggle.OpenGrace()
        grace.noteOpened(id: a, at: t0, point: tile, doubleClickInterval: 0.4)
        XCTAssertFalse(grace.isRepeat(at: t0.addingTimeInterval(-0.1), point: tile))
    }

    func testClearedGraceIsNotRepeat() {
        var grace = PopupToggle.OpenGrace()
        grace.noteOpened(id: a, at: t0, point: tile, doubleClickInterval: 0.4)
        grace.clear()
        XCTAssertFalse(grace.isRepeat(at: t0.addingTimeInterval(0.1), point: tile))
    }

    /// 双击的第二下按下不算「点外面」，不收起。
    func testRepeatPressIsNotOutsideClick() {
        XCTAssertEqual(PopupDismissal.press(.init(repeatOfOpen: true)), .ignore)
        XCTAssertEqual(PopupDismissal.press(.init(button: .secondary, repeatOfOpen: true)), .ignore)
        XCTAssertEqual(PopupDismissal.press(.init(repeatOfOpen: false)), .dismissOnRelease)
    }

    /// 双击格子整套走一遍：第一下打开，第二下按下不收、松开不关，窗口留着。
    func testDoubleClickEndsOpen() {
        var grace = PopupToggle.OpenGrace()
        var guardian = PopupDismissal.ReopenGuard()
        XCTAssertEqual(PopupToggle.decide(requested: a, openID: nil, visible: false, repeatOfOpen: false,
                                          swallow: { guardian.swallowsOpen(id: a, at: t0, point: tile) }),
                       .open)
        grace.noteOpened(id: a, at: t0, point: tile, doubleClickInterval: 0.5)
        let second = t0.addingTimeInterval(0.18)
        XCTAssertEqual(PopupDismissal.press(.init(repeatOfOpen: grace.isRepeat(at: second, point: tile))),
                       .ignore)
        XCTAssertEqual(PopupToggle.decide(requested: a, openID: a, visible: true,
                                          repeatOfOpen: grace.isRepeat(id: a, at: second, point: tile),
                                          swallow: { guardian.swallowsOpen(id: a, at: second, point: tile) }),
                       .ignore)
    }

    /// 打开后过一会儿再点同一个格子：照常关掉。
    func testSlowSecondClickCloses() {
        var grace = PopupToggle.OpenGrace()
        grace.noteOpened(id: a, at: t0, point: tile, doubleClickInterval: 0.5)
        let later = t0.addingTimeInterval(1.2)
        XCTAssertEqual(decide(a, open: a, visible: true,
                              repeatOfOpen: grace.isRepeat(id: a, at: later, point: tile)), .close)
    }

    // MARK: 淡出

    func testFadeFinishingNormallyOrdersOut() {
        var fade = PopupToggle.Fade()
        let token = fade.begin()
        XCTAssertEqual(fade.finish(token, isOpen: false), .orderOut)
    }

    /// 淡出中途又打开（连点、从一个组直接点另一个组）：不收，透明度补回 1。
    func testFadeInterruptedByReopenRestores() {
        var fade = PopupToggle.Fade()
        let token = fade.begin()
        fade.cancel()
        XCTAssertEqual(fade.finish(token, isOpen: true), .restore)
    }

    /// 号对得上但记着开着（打开时没来得及作废号）也补回 1，不收走开着的窗口。
    func testFadeWithOpenStateNeverOrdersOut() {
        var fade = PopupToggle.Fade()
        let token = fade.begin()
        XCTAssertEqual(fade.finish(token, isOpen: true), .restore)
    }

    /// 开了又关：旧淡出走完时新淡出还在跑，旧的不管，交给新的收。
    func testStaleFadeLeavesNewerFadeAlone() {
        var fade = PopupToggle.Fade()
        let first = fade.begin()
        fade.cancel()
        let second = fade.begin()
        XCTAssertEqual(fade.finish(first, isOpen: false), .nothing)
        XCTAssertEqual(fade.finish(second, isOpen: false), .orderOut)
    }

    func testFadeGenerationWrapsWithoutTrapping() {
        var fade = PopupToggle.Fade()
        for _ in 0..<5 { fade.cancel() }
        let token = fade.begin()
        XCTAssertEqual(fade.finish(token, isOpen: false), .orderOut)
    }

    // MARK: 摆位置

    func testPlacementRetriesOnceThenGivesUp() {
        XCTAssertEqual(PopupToggle.Placement.afterFailure(attempt: 1), .retry)
        XCTAssertEqual(PopupToggle.Placement.afterFailure(attempt: 2), .giveUp)
        XCTAssertEqual(PopupToggle.Placement.afterFailure(attempt: 9), .giveUp)
    }
}
