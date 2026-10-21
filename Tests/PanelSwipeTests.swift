import Foundation
import XCTest
@testable import Docket

/// 两指滑动开关面板：方向映射、门槛、一次手势只触发一次。
final class PanelSwipeTests: XCTestCase {

    // MARK: 方向

    func testPanelOpensTowardsTheInsideOfTheScreen() {
        XCTAssertTrue(PanelSwipe.openDirection(edge: .bottom) == (0, 1))
        XCTAssertTrue(PanelSwipe.openDirection(edge: .top) == (0, -1))
        XCTAssertTrue(PanelSwipe.openDirection(edge: .left) == (1, 0))
        XCTAssertTrue(PanelSwipe.openDirection(edge: .right) == (-1, 0))
    }

    /// 自然滚动开着：手指往上 dy 为负，往右 dx 为正。关着时反过来。
    /// 两种情况下手指往上都是往上。
    func testFingerMotionIgnoresNaturalScrolling() {
        XCTAssertTrue(PanelSwipe.fingerMotion(dx: 0, dy: -5, inverted: true) == (0, 5))
        XCTAssertTrue(PanelSwipe.fingerMotion(dx: 0, dy: 5, inverted: false) == (0, 5))
        XCTAssertTrue(PanelSwipe.fingerMotion(dx: 5, dy: 0, inverted: true) == (5, 0))
        XCTAssertTrue(PanelSwipe.fingerMotion(dx: -5, dy: 0, inverted: false) == (5, 0))
    }

    func testComponentsPerEdge() {
        // 底部：手指往上是打开方向，左右是长轴。
        var parts = PanelSwipe.components(dx: 3, dy: -10, inverted: true, edge: .bottom)
        XCTAssertEqual(parts.along, 10)
        XCTAssertEqual(parts.across, 3)
        // 顶部：手指往上是收起。
        parts = PanelSwipe.components(dx: 0, dy: -10, inverted: true, edge: .top)
        XCTAssertEqual(parts.along, -10)
        // 左边：手指往右打开，上下是长轴。
        parts = PanelSwipe.components(dx: 10, dy: 4, inverted: true, edge: .left)
        XCTAssertEqual(parts.along, 10)
        XCTAssertEqual(parts.across, 4)
        // 右边：手指往左打开。
        parts = PanelSwipe.components(dx: -10, dy: 0, inverted: true, edge: .right)
        XCTAssertEqual(parts.along, 10)
    }

    func testOnlyStickyNotesKeepTheirScroll() {
        XCTAssertTrue(PanelSwipe.contentScrolls(.notes))
        XCTAssertFalse(PanelSwipe.contentScrolls(.weather))
        XCTAssertFalse(PanelSwipe.contentScrolls(.calendar))
    }

    // MARK: 手势

    /// 自然滚动下手指往上：dy 为负。
    private func up(_ points: Double, at time: TimeInterval, began: Bool = false) -> PanelSwipe.Event {
        PanelSwipe.Event(dx: 0, dy: -points, began: began, time: time)
    }

    private func down(_ points: Double, at time: TimeInterval, began: Bool = false) -> PanelSwipe.Event {
        PanelSwipe.Event(dx: 0, dy: points, began: began, time: time)
    }

    /// 把一串事件喂进去，返回每次的结果。
    private func run(_ events: [PanelSwipe.Event], edge: DockPosition = .bottom,
                     target: Bool = true, enabled: Bool = true,
                     gesture: inout PanelSwipeGesture) -> [PanelSwipeGesture.Outcome] {
        events.map { gesture.feed($0, edge: edge, target: target, enabled: enabled) }
    }

    private func fires(_ outcomes: [PanelSwipeGesture.Outcome]) -> [PanelSwipe.Action] {
        outcomes.compactMap { if case .fire(let action) = $0 { action } else { nil } }
    }

    func testSwipeUpOnBottomShelfOpensOnce() {
        var gesture = PanelSwipeGesture()
        let events = [up(0, at: 0, began: true)] + (1...10).map { up(8, at: Double($0) * 0.01) }
        let outcomes = run(events, gesture: &gesture)
        XCTAssertEqual(fires(outcomes), [.open])
        // 开头没判断归属之前交回去，判断以后全吞。
        XCTAssertEqual(outcomes.first, .pass)
        XCTAssertEqual(outcomes.last, .consume)
    }

    func testSwipeDownOnBottomShelfCloses() {
        var gesture = PanelSwipeGesture()
        let events = [down(0, at: 0, began: true)] + (1...6).map { down(8, at: Double($0) * 0.01) }
        XCTAssertEqual(fires(run(events, gesture: &gesture)), [.close])
    }

    func testTopShelfIsReversed() {
        var gesture = PanelSwipeGesture()
        let events = [down(0, at: 0, began: true)] + (1...6).map { down(8, at: Double($0) * 0.01) }
        XCTAssertEqual(fires(run(events, edge: .top, gesture: &gesture)), [.open])
    }

    func testSideShelvesUseTheHorizontalAxis() {
        var gesture = PanelSwipeGesture()
        // 自然滚动下手指往右：dx 为正。左边扩展栏往右是打开。
        var events = [PanelSwipe.Event(dx: 0, dy: 0, began: true, time: 0)]
            + (1...6).map { PanelSwipe.Event(dx: 8, dy: 0, time: Double($0) * 0.01) }
        XCTAssertEqual(fires(run(events, edge: .left, gesture: &gesture)), [.open])
        gesture = PanelSwipeGesture()
        XCTAssertEqual(fires(run(events, edge: .right, gesture: &gesture)), [.close])
        // 左边扩展栏上下滑是长轴，不归这里。
        gesture = PanelSwipeGesture()
        events = [up(0, at: 0, began: true)] + (1...6).map { up(8, at: Double($0) * 0.01) }
        let outcomes = run(events, edge: .left, gesture: &gesture)
        XCTAssertTrue(outcomes.allSatisfy { $0 == .pass })
    }

    func testWithoutNaturalScrollingFingersStillMeanTheSame() {
        var gesture = PanelSwipeGesture()
        // 关着自然滚动时手指往上 dy 为正。
        let events = [PanelSwipe.Event(dx: 0, dy: 0, inverted: false, began: true, time: 0)]
            + (1...6).map { PanelSwipe.Event(dx: 0, dy: 8, inverted: false, time: Double($0) * 0.01) }
        XCTAssertEqual(fires(run(events, gesture: &gesture)), [.open])
    }

    /// 门槛以内不触发，刚到门槛触发。
    func testThreshold() {
        var gesture = PanelSwipeGesture()
        let short = PanelSwipeGesture.threshold - 1
        var outcomes = run([up(0, at: 0, began: true), up(short, at: 0.01)], gesture: &gesture)
        XCTAssertTrue(fires(outcomes).isEmpty)
        outcomes = run([up(1, at: 0.02)], gesture: &gesture)
        XCTAssertEqual(fires(outcomes), [.open])
    }

    /// 短轴要至少是长轴的两倍，斜着滑整个手势交回去。
    func testDiagonalSwipeIsNotClaimed() {
        var gesture = PanelSwipeGesture()
        let events = [PanelSwipe.Event(dx: 0, dy: 0, began: true, time: 0)]
            + (1...10).map { PanelSwipe.Event(dx: 6, dy: -8, time: Double($0) * 0.01) }
        let outcomes = run(events, gesture: &gesture)
        XCTAssertTrue(outcomes.allSatisfy { $0 == .pass })
    }

    /// 一开始左右滑，中途转成上下：归属在开头定了，不会半路被抢走。
    func testClaimIsDecidedAtTheStart() {
        var gesture = PanelSwipeGesture()
        let events = [PanelSwipe.Event(dx: 0, dy: 0, began: true, time: 0),
                      PanelSwipe.Event(dx: 8, dy: 0, time: 0.01)]
            + (2...10).map { up(10, at: Double($0) * 0.01) }
        XCTAssertTrue(run(events, gesture: &gesture).allSatisfy { $0 == .pass })
    }

    /// 惯性尾巴吞掉但不再触发，下一次手势重新算。
    func testMomentumIsSwallowedButNeverFires() {
        var gesture = PanelSwipeGesture()
        var outcomes = run([up(0, at: 0, began: true)] + (1...6).map { up(8, at: Double($0) * 0.01) },
                           gesture: &gesture)
        XCTAssertEqual(fires(outcomes), [.open])
        let tail = (1...20).map {
            PanelSwipe.Event(dx: 0, dy: -30, momentum: true, phased: false, time: 0.06 + Double($0) * 0.01)
        }
        outcomes = run(tail, gesture: &gesture)
        XCTAssertTrue(outcomes.allSatisfy { $0 == .consume })
        // 惯性里反过来也不收起。
        outcomes = run([PanelSwipe.Event(dx: 0, dy: 80, momentum: true, phased: false, time: 0.3)],
                       gesture: &gesture)
        XCTAssertEqual(outcomes, [.consume])
        // 新的手势可以收起。
        outcomes = run([down(0, at: 1, began: true)] + (1...6).map { down(8, at: 1 + Double($0) * 0.01) },
                       gesture: &gesture)
        XCTAssertEqual(fires(outcomes), [.close])
    }

    /// 同一次手势来回滑也只触发一次。
    func testOneGestureFiresOnlyOnce() {
        var gesture = PanelSwipeGesture()
        let events = [up(0, at: 0, began: true)]
            + (1...6).map { up(8, at: Double($0) * 0.01) }
            + (7...20).map { down(8, at: Double($0) * 0.01) }
            + (21...40).map { up(8, at: Double($0) * 0.01) }
        XCTAssertEqual(fires(run(events, gesture: &gesture)), [.open])
    }

    /// 普通滚轮：不精确、没有阶段，从来不归这里。
    func testMouseWheelNeverFires() {
        var gesture = PanelSwipeGesture()
        let events = (0..<10).map {
            PanelSwipe.Event(dx: 0, dy: -10, precise: false, phased: false, time: Double($0) * 0.05)
        }
        XCTAssertTrue(run(events, gesture: &gesture).allSatisfy { $0 == .pass })
        // 精确但没有阶段也不算（有的鼠标驱动这样报）。
        let unphased = (0..<10).map {
            PanelSwipe.Event(dx: 0, dy: -10, phased: false, time: 1 + Double($0) * 0.05)
        }
        XCTAssertTrue(run(unphased, gesture: &gesture).allSatisfy { $0 == .pass })
    }

    func testNothingHappensWithoutATargetOrWhenOff() {
        let events = [up(0, at: 0, began: true)] + (1...10).map { up(8, at: Double($0) * 0.01) }
        var gesture = PanelSwipeGesture()
        XCTAssertTrue(run(events, target: false, gesture: &gesture).allSatisfy { $0 == .pass })
        gesture = PanelSwipeGesture()
        XCTAssertTrue(run(events, enabled: false, gesture: &gesture).allSatisfy { $0 == .pass })
    }

    /// 按着 Command 是切换布局，不归这里。
    func testCommandScrollIsLeftForLayouts() {
        var gesture = PanelSwipeGesture()
        let events = [PanelSwipe.Event(dx: 0, dy: 0, began: true, command: true, time: 0)]
            + (1...10).map { PanelSwipe.Event(dx: 0, dy: -8, command: true, time: Double($0) * 0.01) }
        XCTAssertTrue(run(events, gesture: &gesture).allSatisfy { $0 == .pass })
    }

    /// 没收到 began 也能靠停顿分开两次手势。
    func testPauseStartsANewGesture() {
        var gesture = PanelSwipeGesture()
        var outcomes = run((0...6).map { up(8, at: Double($0) * 0.01) }, gesture: &gesture)
        XCTAssertEqual(fires(outcomes), [.open])
        outcomes = run((0...6).map { down(8, at: 1 + Double($0) * 0.01) }, gesture: &gesture)
        XCTAssertEqual(fires(outcomes), [.close])
    }

    func testSettingDefaultsOnAndDecodesFromOlderState() throws {
        XCTAssertTrue(CustomDockSettings().swipeOpensPanels)
        let json = #"{"version":1,"customDock":{"position":"left"}}"#
        let state = try JSONDecoder().decode(PersistedState.self, from: Data(json.utf8))
        XCTAssertTrue(state.customDock.swipeOpensPanels)
        var settings = CustomDockSettings()
        settings.swipeOpensPanels = false
        let back = try JSONDecoder().decode(CustomDockSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertFalse(back.swipeOpensPanels)
    }
}
