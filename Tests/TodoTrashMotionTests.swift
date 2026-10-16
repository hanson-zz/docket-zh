import Foundation
import XCTest

final class TodoTrashMotionTests: XCTestCase {
    func testCheckingTheLastOpenTaskFinishesAll() {
        let items = [TodoItem(id: "a", text: "一"), TodoItem(id: "b", text: "二", done: true)]
        XCTAssertTrue(QuickTodo.finishesAll(toggling: "a", in: items))
        XCTAssertFalse(QuickTodo.finishesAll(toggling: "b", in: items), "reopening is not finishing")
    }

    func testCheckingOneOfSeveralDoesNotFinishAll() {
        let items = [TodoItem(id: "a", text: "一"), TodoItem(id: "b", text: "二")]
        XCTAssertFalse(QuickTodo.finishesAll(toggling: "a", in: items))
        XCTAssertFalse(QuickTodo.finishesAll(toggling: "x", in: []))
    }

    func testRestoringPutsTheTaskBackWhereItWas() {
        let items = [TodoItem(id: "a", text: "一"), TodoItem(id: "b", text: "二"),
                     TodoItem(id: "c", text: "三", done: true)]
        let removed = QuickTodo.removing("b", from: items)
        let back = QuickTodo.restoring(items[1], at: 1, in: removed)
        XCTAssertEqual(back.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(QuickTodo.restoring(items[1], at: 1, in: back).map(\.id), ["a", "b", "c"],
                       "a second undo changes nothing")
    }

    func testRestoringPastTheEndAppends() {
        let back = QuickTodo.restoring(TodoItem(id: "z", text: "末"), at: 9, in: [TodoItem(id: "a", text: "一")])
        XCTAssertEqual(back.map(\.id), ["a", "z"])
    }

    func testCheerPopsAndFadesAway() {
        XCTAssertEqual(CheerMotion.pandaScale(0), 0)
        XCTAssertEqual(CheerMotion.pandaScale(10), 1, accuracy: 0.0001)
        XCTAssertGreaterThan(CheerMotion.pandaScale(0.3), 1, "overshoots before settling")
        XCTAssertEqual(CheerMotion.opacity(CheerMotion.duration), 0)
        XCTAssertEqual(CheerMotion.opacity(1), 1)
        XCTAssertEqual(CheerMotion.hop(0.2), 0)
        XCTAssertEqual(CheerMotion.hop(5), 0)
    }

    func testSparksFlyOutAndAreGoneAtTheEnd() {
        for index in 0..<CheerMotion.sparks {
            let early = CheerMotion.spark(index: index, t: 0.3)
            let late = CheerMotion.spark(index: index, t: 1.0)
            XCTAssertGreaterThan(hypot(late.x, late.y), hypot(early.x, early.y))
            XCTAssertEqual(CheerMotion.spark(index: index, t: CheerMotion.duration).opacity, 0)
        }
    }

    func testSwipeDeletesOnlyFarEnoughLeft() {
        XCTAssertTrue(SwipeDelete.shouldDelete(offset: -150, predicted: -160, width: 300))
        XCTAssertFalse(SwipeDelete.shouldDelete(offset: -60, predicted: -70, width: 300))
        XCTAssertTrue(SwipeDelete.shouldDelete(offset: -60, predicted: -400, width: 300), "a flick counts")
        XCTAssertFalse(SwipeDelete.shouldDelete(offset: 10, predicted: 400, width: 300))
        XCTAssertLessThan(SwipeDelete.offset(for: 500), 18, "right is a short rubber band")
        XCTAssertEqual(SwipeDelete.offset(for: -40), -40)
        XCTAssertEqual(SwipeDelete.progress(offset: -300, width: 300), 1)
    }

    func testSheetsFallIntoTheMouthAndTheBinSettles() {
        let start = SwallowMotion.sheet(index: 0, t: 0.05)
        let end = SwallowMotion.sheet(index: 0, t: 0.55)
        XCTAssertLessThan(start.y, end.y, "falls downward toward the mouth")
        XCTAssertLessThan(end.scale, start.scale, "shrinks as it goes in")
        for index in 0..<SwallowMotion.sheets {
            XCTAssertEqual(SwallowMotion.sheet(index: index, t: SwallowMotion.duration).opacity, 0)
        }
        XCTAssertEqual(SwallowMotion.gulpAmount(0), 0)
        XCTAssertEqual(SwallowMotion.gulpAmount(SwallowMotion.duration), 0)
        XCTAssertGreaterThan(SwallowMotion.gulpAmount(0.75), 0)
        XCTAssertLessThanOrEqual(SwallowMotion.gulpAmount(0.9), 0.12)
    }
}
