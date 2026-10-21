import CoreGraphics
import Foundation
import XCTest

final class PopupDismissalTests: XCTestCase {

    // MARK: 按下

    func testPlainClickOutsideWaitsForRelease() {
        XCTAssertEqual(PopupDismissal.press(.init()), .dismissOnRelease)
    }

    func testRightAndOtherClickOutsideDismissAtOnce() {
        XCTAssertEqual(PopupDismissal.press(.init(button: .secondary)), .dismissNow)
        XCTAssertEqual(PopupDismissal.press(.init(button: .other)), .dismissNow)
    }

    func testClickInsidePopupIsIgnored() {
        XCTAssertEqual(PopupDismissal.press(.init(inPopup: true)), .ignore)
        XCTAssertEqual(PopupDismissal.press(.init(button: .secondary, inPopup: true)), .ignore)
    }

    func testQuickLookKeepsPopupOpen() {
        // 点快速查看的关闭按钮：不连带收起。
        XCTAssertEqual(PopupDismissal.press(.init(inQuickLook: true, quickLookOpen: true)), .ignore)
        // 快速查看开着时点桌面也不收。
        XCTAssertEqual(PopupDismissal.press(.init(quickLookOpen: true)), .ignore)
        XCTAssertEqual(PopupDismissal.press(.init(button: .secondary, quickLookOpen: true)), .ignore)
    }

    func testMenuModalAndDragKeepPopupOpen() {
        XCTAssertEqual(PopupDismissal.press(.init(menuOpen: true)), .ignore)
        XCTAssertEqual(PopupDismissal.press(.init(modalOpen: true)), .ignore)
        XCTAssertEqual(PopupDismissal.press(.init(dragging: true)), .ignore)
        XCTAssertEqual(PopupDismissal.press(.init(button: .secondary, dragging: true)), .ignore)
    }

    // MARK: 松开

    func testReleaseInPlaceDismisses() {
        let start = CGPoint(x: 100, y: 100)
        XCTAssertEqual(PopupDismissal.release(start: start, current: start, buttonDown: true), .wait)
        XCTAssertEqual(PopupDismissal.release(start: start, current: CGPoint(x: 102, y: 101),
                                              buttonDown: false), .dismiss)
    }

    func testMovingAwayIsADragNotAClick() {
        let start = CGPoint(x: 100, y: 100)
        // 从访达按住文件拖向小窗：移动超过阈值就不收。
        XCTAssertEqual(PopupDismissal.release(start: start, current: CGPoint(x: 110, y: 100),
                                              buttonDown: true), .cancel)
        XCTAssertEqual(PopupDismissal.release(start: start, current: CGPoint(x: 100, y: 95),
                                              buttonDown: false), .cancel)
        // 正好在阈值上仍算点击。
        let edge = CGPoint(x: 100 + PopupDismissal.dragThreshold, y: 100)
        XCTAssertEqual(PopupDismissal.release(start: start, current: edge, buttonDown: false), .dismiss)
    }

    func testBlockedDuringPressCancels() {
        let start = CGPoint(x: 0, y: 0)
        XCTAssertEqual(PopupDismissal.release(start: start, current: start, buttonDown: false,
                                              blocked: true), .cancel)
    }

    // MARK: Esc

    func testEscapeDismissesWhenNothingElse() {
        XCTAssertEqual(PopupDismissal.escape(.init()), .dismiss)
    }

    func testEscapeBacksOutOfSearchFirst() {
        // 第一次：清空并退出搜索；第二次（已经没有可退的了）：收起。
        XCTAssertEqual(PopupDismissal.escape(.init(inner: true)), .backOut)
        XCTAssertEqual(PopupDismissal.escape(.init(inner: false)), .dismiss)
    }

    func testEscapeClosesQuickLookBeforeAnythingInside() {
        XCTAssertEqual(PopupDismissal.escape(.init(quickLookOpen: true, inner: true)), .closeQuickLook)
        XCTAssertEqual(PopupDismissal.escape(.init(quickLookOpen: true)), .closeQuickLook)
    }

    func testEscapeLeftToInputMethodMenuAndDrag() {
        XCTAssertEqual(PopupDismissal.escape(.init(composing: true, inner: true)), .pass)
        XCTAssertEqual(PopupDismissal.escape(.init(menuOpen: true)), .pass)
        XCTAssertEqual(PopupDismissal.escape(.init(dragging: true, quickLookOpen: true)), .pass)
    }

    // MARK: 再点一次格子

    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testSameTileRightAfterOutsideDismissIsSwallowed() {
        var guardian = PopupDismissal.ReopenGuard()
        let id = UUID()
        let point = CGPoint(x: 300, y: 20)
        guardian.noteDismissed(id: id, at: t0, point: point)
        XCTAssertTrue(guardian.swallowsOpen(id: id, at: t0.addingTimeInterval(0.15),
                                            point: CGPoint(x: 302, y: 21)))
        // 只吞一次：下一次点同一个格子照常打开。
        XCTAssertFalse(guardian.swallowsOpen(id: id, at: t0.addingTimeInterval(0.3), point: point))
    }

    func testOtherTileOpensNormally() {
        var guardian = PopupDismissal.ReopenGuard()
        let point = CGPoint(x: 300, y: 20)
        guardian.noteDismissed(id: UUID(), at: t0, point: point)
        XCTAssertFalse(guardian.swallowsOpen(id: UUID(), at: t0.addingTimeInterval(0.1), point: point))
    }

    func testLateOrFarOpenIsNotSwallowed() {
        let id = UUID()
        let point = CGPoint(x: 300, y: 20)

        var late = PopupDismissal.ReopenGuard()
        late.noteDismissed(id: id, at: t0, point: point)
        XCTAssertFalse(late.swallowsOpen(id: id, at: t0.addingTimeInterval(PopupDismissal.ReopenGuard.window + 0.1),
                                         point: point))

        var far = PopupDismissal.ReopenGuard()
        far.noteDismissed(id: id, at: t0, point: point)
        XCTAssertFalse(far.swallowsOpen(id: id, at: t0.addingTimeInterval(0.1), point: CGPoint(x: 340, y: 20)))

        var earlier = PopupDismissal.ReopenGuard()
        earlier.noteDismissed(id: id, at: t0, point: point)
        XCTAssertFalse(earlier.swallowsOpen(id: id, at: t0.addingTimeInterval(-1), point: point))
    }

    func testNothingRecordedSwallowsNothing() {
        var guardian = PopupDismissal.ReopenGuard()
        XCTAssertFalse(guardian.swallowsOpen(id: UUID(), at: t0, point: .zero))
        guardian.noteDismissed(id: nil, at: t0, point: .zero)
        XCTAssertFalse(guardian.swallowsOpen(id: UUID(), at: t0, point: .zero))
    }

    // MARK: 指针离开（扩展栏自动隐藏时）

    /// 从 t0 起每 1/30 秒喂一次，喂到 `seconds`，返回第几秒收起（没收起是 nil）。
    private func run(_ timer: inout PopupDismissal.LeaveTimer, from start: TimeInterval = 0,
                     to seconds: TimeInterval,
                     away: (TimeInterval) -> PopupDismissal.Away) -> TimeInterval? {
        var t = start
        while t <= seconds + 1e-9 {
            if timer.tick(away(t), now: t0.addingTimeInterval(t)) { return t }
            t += 1.0 / 30
        }
        return nil
    }

    func testLeavingDismissesAfterHalfSecond() {
        var timer = PopupDismissal.LeaveTimer()
        let fired = run(&timer, to: 1) { _ in .init() }
        XCTAssertNotNil(fired)
        XCTAssertEqual(fired!, PopupDismissal.LeaveTimer.delay, accuracy: 1.0 / 30 + 1e-6)
    }

    func testInsideNeverDismisses() {
        var timer = PopupDismissal.LeaveTimer()
        XCTAssertNil(run(&timer, to: 3) { _ in .init(pointerInside: true) })
    }

    func testReturningCancelsTheCount() {
        var timer = PopupDismissal.LeaveTimer()
        // 出去 0.4 秒，回来，再出去：从再出去那一刻重新算 0.5 秒。
        let fired = run(&timer, to: 2) { t in .init(pointerInside: t >= 0.4 && t < 0.6) }
        XCTAssertNotNil(fired)
        XCTAssertGreaterThanOrEqual(fired!, 0.6 + PopupDismissal.LeaveTimer.delay - 1e-6)
    }

    func testBlockersHoldOpenWhileAway() {
        let blockers: [PopupDismissal.Away] = [
            .init(buttonDown: true),
            .init(dragging: true),
            .init(quickLookOpen: true),
            .init(holdOpen: true),
            .init(composing: true),
        ]
        for away in blockers {
            var timer = PopupDismissal.LeaveTimer()
            XCTAssertNil(run(&timer, to: 3) { _ in away }, "\(away)")
        }
    }

    func testCountRestartsWhenBlockerClears() {
        var timer = PopupDismissal.LeaveTimer()
        // 指针一直在外面，前 1 秒按着鼠标（从访达拖文件）：松开后再等 0.5 秒才收。
        let fired = run(&timer, to: 3) { t in .init(buttonDown: t < 1) }
        XCTAssertNotNil(fired)
        XCTAssertGreaterThanOrEqual(fired!, 1 + PopupDismissal.LeaveTimer.delay - 1e-6)
        XCTAssertLessThan(fired!, 1 + PopupDismissal.LeaveTimer.delay + 0.1)
    }

    func testQuickLookClosingRestartsCount() {
        var timer = PopupDismissal.LeaveTimer()
        let fired = run(&timer, to: 3) { t in .init(quickLookOpen: t < 2) }
        XCTAssertGreaterThanOrEqual(fired ?? 0, 2 + PopupDismissal.LeaveTimer.delay - 1e-6)
    }

    func testFiresOnlyOnce() {
        var timer = PopupDismissal.LeaveTimer()
        XCTAssertNotNil(run(&timer, to: 1) { _ in .init() })
        // 清零后下一次喂只是重新开始计时。
        XCTAssertFalse(timer.tick(.init(), now: t0.addingTimeInterval(1.05)))
    }

    func testLongGapRestartsCount() {
        var timer = PopupDismissal.LeaveTimer()
        XCTAssertFalse(timer.tick(.init(), now: t0))
        // 中间停了很久没看指针（不再自动隐藏又改回来）：不能一来就收。
        XCTAssertFalse(timer.tick(.init(), now: t0.addingTimeInterval(5)))
        XCTAssertFalse(timer.tick(.init(), now: t0.addingTimeInterval(5.2)))
        XCTAssertTrue(timer.tick(.init(), now: t0.addingTimeInterval(5.5)))
    }

    func testResetClearsCount() {
        var timer = PopupDismissal.LeaveTimer()
        XCTAssertFalse(timer.tick(.init(), now: t0))
        XCTAssertFalse(timer.tick(.init(), now: t0.addingTimeInterval(0.2)))
        timer.reset()
        XCTAssertFalse(timer.tick(.init(), now: t0.addingTimeInterval(0.4)))
        XCTAssertFalse(timer.tick(.init(), now: t0.addingTimeInterval(0.6)))
        XCTAssertFalse(timer.tick(.init(), now: t0.addingTimeInterval(0.8)))
        XCTAssertTrue(timer.tick(.init(), now: t0.addingTimeInterval(0.95)))
    }
}
