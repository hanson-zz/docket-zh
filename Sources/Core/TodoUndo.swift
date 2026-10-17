import Foundation

/// 待办面板里能撤销的一步：删掉了一项，或者勾掉了一项。
///
/// 记下的是改动之前的那一项和它在清单里的位置（`QuickTodo.ordered` 之后的
/// 索引），撤销时按原样放回原位，而不是追加到末尾。
public struct TodoUndoStep: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case deleted
        case completed
    }

    public var kind: Kind
    /// 改动之前的样子。
    public var item: TodoItem
    /// 改动之前在清单里的位置。
    public var index: Int

    public init(kind: Kind, item: TodoItem, index: Int) {
        self.kind = kind
        self.item = item
        self.index = index
    }

    /// 撤销条上的一句话。
    public var caption: String {
        switch kind {
        case .deleted: "已删除“\(item.text)”"
        case .completed: "已完成“\(item.text)”"
        }
    }
}

/// 最近几步删除和完成，按先后叠起来，撤销一次退一步。
///
/// A small stack rather than a single slot: deleting two tasks in a row and
/// then pressing undo used to bring back only the second. Capped so the panel
/// never holds an old history the user has forgotten about.
public struct TodoUndoStack: Equatable, Sendable {
    public static let capacity = 5

    public private(set) var steps: [TodoUndoStep] = []

    public init(steps: [TodoUndoStep] = []) {
        self.steps = Array(steps.suffix(Self.capacity))
    }

    public var isEmpty: Bool { steps.isEmpty }
    public var count: Int { steps.count }
    /// 下一次撤销会退回的那一步。
    public var last: TodoUndoStep? { steps.last }

    /// 记下一步。超过上限时丢掉最早的一步。
    public mutating func push(_ step: TodoUndoStep) {
        steps.append(step)
        if steps.count > Self.capacity {
            steps.removeFirst(steps.count - Self.capacity)
        }
    }

    /// 记下“要删掉 `id`”这一步，位置取自改动之前的清单。找不到这一项时什么也不记。
    public mutating func recordDeletion(of id: String, in items: [TodoItem]) {
        let list = QuickTodo.ordered(items)
        guard let index = list.firstIndex(where: { $0.id == id }) else { return }
        push(TodoUndoStep(kind: .deleted, item: list[index], index: index))
    }

    /// 记下“要勾掉 `id`”这一步。已经完成的项再点是重新打开，不记。
    public mutating func recordCompletion(of id: String, in items: [TodoItem]) {
        let list = QuickTodo.ordered(items)
        guard let index = list.firstIndex(where: { $0.id == id }), !list[index].done else { return }
        push(TodoUndoStep(kind: .completed, item: list[index], index: index))
    }

    /// 取出最近的一步，没有时为 nil。
    public mutating func pop() -> TodoUndoStep? {
        steps.popLast()
    }

    public mutating func clear() { steps.removeAll() }

    /// 把一步撤回到清单上：删掉的放回原位；勾掉的重新打开，也放回原位。
    ///
    /// The item is taken out first and put back as it was, so undoing a
    /// completion lands it at its old place among the open tasks rather than
    /// at the end of them, and pressing undo for a step whose item has since
    /// been changed again simply restores the recorded version.
    public static func undoing(_ step: TodoUndoStep, in items: [TodoItem]) -> [TodoItem] {
        switch step.kind {
        case .deleted:
            return QuickTodo.restoring(step.item, at: step.index, in: items)
        case .completed:
            // 撤销完成时这一项要是已经被删了，就不凭空变回来：那是另一步的事。
            guard items.contains(where: { $0.id == step.item.id }) else { return QuickTodo.ordered(items) }
            let rest = items.filter { $0.id != step.item.id }
            return QuickTodo.restoring(step.item, at: step.index, in: rest)
        }
    }
}

extension QuickTodo {
    /// 全部完成后庆祝动效播到什么时候（自 1970 年起的秒数）。
    ///
    /// 设成“有未完成的待办时显示”时，勾掉最后一项本来会让卡片立刻从扩展栏上
    /// 消失，小熊猫还没跳出来就没了。勾掉的同一次写入里记下这个时刻，在它之前
    /// 卡片仍算“满足条件”，动效播完后卡片自己把它清掉，扩展栏随即把卡片收起。
    public static let cheerKey = "cheerUntil"

    /// 庆祝要播多久之后才允许隐藏，比动效本身略长一点，让最后的淡出播完。
    public static let cheerHold: Double = CheerMotion.duration + 0.2

    /// 记下庆祝的截止时刻。
    public static func startCheer(in config: inout WidgetConfig, now: Date = Date()) {
        config.set(cheerKey, .number(now.addingTimeInterval(cheerHold).timeIntervalSince1970))
    }

    /// 庆祝播完，清掉记号。
    public static func endCheer(in config: inout WidgetConfig) {
        config.set(cheerKey, nil)
    }

    /// 是否还在庆祝。时间已过、没有记号或记号离谱地远（时钟被调过）都算不在。
    public static func isCheering(_ config: WidgetConfig, now: Date = Date()) -> Bool {
        guard case .number(let until) = config[cheerKey] else { return false }
        let left = until - now.timeIntervalSince1970
        return left > 0 && left <= cheerHold + 1
    }
}
