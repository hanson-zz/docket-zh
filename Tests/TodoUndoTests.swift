import Foundation
import XCTest

/// 待办的多步撤销、全部完成后的庆祝不被“有未完成时显示”提前收起，以及首次启动时
/// “检查更新”提示框等新手引导关掉再弹。
final class TodoUndoTests: XCTestCase {
    private let base = [TodoItem(id: "a", text: "一"), TodoItem(id: "b", text: "二"),
                        TodoItem(id: "c", text: "三"), TodoItem(id: "d", text: "四", done: true)]

    // MARK: 撤销栈

    func testUndoingTwoDeletionsRestoresBothInTheirPlaces() {
        var stack = TodoUndoStack()
        var list = base
        stack.recordDeletion(of: "b", in: list)
        list = QuickTodo.removing("b", from: list)
        stack.recordDeletion(of: "a", in: list)
        list = QuickTodo.removing("a", from: list)
        XCTAssertEqual(list.map(\.id), ["c", "d"])
        XCTAssertEqual(stack.count, 2)

        list = TodoUndoStack.undoing(stack.pop()!, in: list)
        XCTAssertEqual(list.map(\.id), ["a", "c", "d"])
        list = TodoUndoStack.undoing(stack.pop()!, in: list)
        XCTAssertEqual(list.map(\.id), ["a", "b", "c", "d"], "back where it was, not appended at the end")
        XCTAssertTrue(stack.isEmpty)
        XCTAssertNil(stack.pop())
    }

    func testUndoingACompletionReopensItAtItsOldPlace() {
        var stack = TodoUndoStack()
        var list = base
        stack.recordCompletion(of: "a", in: list)
        list = QuickTodo.toggling("a", in: list)
        XCTAssertEqual(list.map(\.id), ["b", "c", "d", "a"])
        list = TodoUndoStack.undoing(stack.pop()!, in: list)
        XCTAssertEqual(list.map(\.id), ["a", "b", "c", "d"])
        XCTAssertFalse(list[0].done)
    }

    func testMixedStepsUndoInReverseOrder() {
        var stack = TodoUndoStack()
        var list = base
        stack.recordCompletion(of: "b", in: list)
        list = QuickTodo.toggling("b", in: list)
        stack.recordDeletion(of: "c", in: list)
        list = QuickTodo.removing("c", from: list)
        stack.recordDeletion(of: "d", in: list)
        list = QuickTodo.removing("d", from: list)
        XCTAssertEqual(list.map(\.id), ["a", "b"])
        XCTAssertTrue(list[1].done)

        while let step = stack.pop() { list = TodoUndoStack.undoing(step, in: list) }
        XCTAssertEqual(list, base)
    }

    func testDeletingADoneTaskComesBackAmongTheDoneOnes() {
        var stack = TodoUndoStack()
        var list = base
        stack.recordDeletion(of: "d", in: list)
        list = QuickTodo.removing("d", from: list)
        list = TodoUndoStack.undoing(stack.pop()!, in: list)
        XCTAssertEqual(list.map(\.id), ["a", "b", "c", "d"])
        XCTAssertTrue(list[3].done)
    }

    func testStackKeepsOnlyTheLastFiveSteps() {
        var stack = TodoUndoStack()
        for index in 0..<8 {
            stack.push(TodoUndoStep(kind: .deleted, item: TodoItem(id: "i\(index)", text: "\(index)"), index: 0))
        }
        XCTAssertEqual(stack.count, TodoUndoStack.capacity)
        XCTAssertEqual(TodoUndoStack.capacity, 5)
        XCTAssertEqual(stack.last?.item.id, "i7")
        XCTAssertEqual(stack.steps.first?.item.id, "i3", "the oldest steps fall off")
    }

    func testReopeningAndUnknownIDsAreNotRecorded() {
        var stack = TodoUndoStack()
        stack.recordCompletion(of: "d", in: base)
        stack.recordCompletion(of: "x", in: base)
        stack.recordDeletion(of: "x", in: base)
        XCTAssertTrue(stack.isEmpty)
    }

    func testUndoingTwiceDoesNotDuplicate() {
        let step = TodoUndoStep(kind: .deleted, item: base[1], index: 1)
        let once = TodoUndoStack.undoing(step, in: QuickTodo.removing("b", from: base))
        XCTAssertEqual(TodoUndoStack.undoing(step, in: once).map(\.id), ["a", "b", "c", "d"])
    }

    func testUndoingACompletionOfADeletedTaskDoesNotResurrectIt() {
        let step = TodoUndoStep(kind: .completed, item: base[0], index: 0)
        let list = QuickTodo.removing("a", from: base)
        XCTAssertEqual(TodoUndoStack.undoing(step, in: list).map(\.id), ["b", "c", "d"])
    }

    func testCaptions() {
        XCTAssertEqual(TodoUndoStep(kind: .deleted, item: base[0], index: 0).caption, "已删除“一”")
        XCTAssertEqual(TodoUndoStep(kind: .completed, item: base[0], index: 0).caption, "已完成“一”")
    }

    // MARK: 庆祝播完再隐藏

    private func todo(_ items: [TodoItem]) -> WidgetInstance {
        var config = WidgetConfig([WidgetVisibility.modeKey: .string("conditional")])
        QuickTodo.store(items, in: &config)
        return WidgetInstance(kind: .todo, config: config)
    }

    func testFinishedListStaysVisibleWhileCheering() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var widget = todo([TodoItem(id: "a", text: "一", done: true)])
        XCTAssertEqual(WidgetVisibility.conditionHolds(widget, .unknown, now: now), false)

        QuickTodo.startCheer(in: &widget.config, now: now)
        XCTAssertTrue(QuickTodo.isCheering(widget.config, now: now.addingTimeInterval(1)))
        XCTAssertEqual(WidgetVisibility.conditionHolds(widget, .unknown, now: now.addingTimeInterval(1)), true)
        XCTAssertEqual(WidgetVisibility.conditionHolds(widget, .unknown,
                                                      now: now.addingTimeInterval(CheerMotion.duration - 0.05)), true,
                       "still there for the whole animation")
        XCTAssertEqual(WidgetVisibility.conditionHolds(widget, .unknown,
                                                      now: now.addingTimeInterval(QuickTodo.cheerHold + 0.1)), false)

        QuickTodo.endCheer(in: &widget.config)
        XCTAssertNil(widget.config[QuickTodo.cheerKey])
        XCTAssertFalse(QuickTodo.isCheering(widget.config, now: now))
    }

    func testCheerHoldCoversTheAnimation() {
        XCTAssertGreaterThanOrEqual(QuickTodo.cheerHold, CheerMotion.duration)
    }

    func testAFarFutureMarkIsIgnored() {
        var config = WidgetConfig()
        config.set(QuickTodo.cheerKey, .number(Date(timeIntervalSince1970: 0).addingTimeInterval(3600).timeIntervalSince1970))
        XCTAssertFalse(QuickTodo.isCheering(config, now: Date(timeIntervalSince1970: 0)),
                       "a clock change cannot pin the card on the shelf")
    }

    func testOpenTasksStillShowWithoutCheer() {
        XCTAssertEqual(WidgetVisibility.conditionHolds(todo(base), .unknown), true)
    }

    // MARK: 检查更新的提示框让位给新手引导

    func testUpdatePromptWaitsForOnboarding() {
        let now = Date(timeIntervalSince1970: 5_000)
        XCTAssertFalse(Onboarding.mayPromptForUpdates(onboardingActive: true, closedAt: nil, now: now))
        XCTAssertTrue(Onboarding.mayPromptForUpdates(onboardingActive: false, closedAt: nil, now: now),
                      "no onboarding at all: ask as before")
        XCTAssertFalse(Onboarding.mayPromptForUpdates(onboardingActive: false, closedAt: now.addingTimeInterval(-0.5),
                                                      now: now), "not the instant the window closes")
        XCTAssertTrue(Onboarding.mayPromptForUpdates(onboardingActive: false,
                                                     closedAt: now.addingTimeInterval(-Onboarding.updatePromptSettle),
                                                     now: now))
    }
}
