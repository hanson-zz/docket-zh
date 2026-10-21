import Foundation

/// 悬停扩展栏时浮出的布局名小标签：什么时候出现、页码点怎么画、什么时候淡出。
///
/// 窗口和画法在 `Sources/DockPanel/LayoutLabelWindow.swift`；这里只放规则，
/// 好在测试里查。
public enum LayoutLabel {
    /// 切换布局后标签亮多久。
    public static let flashDuration: TimeInterval = 1.5
    /// 指针离开扩展栏（和标签本身）后再留多久才淡出。
    public static let lingerAfterLeave: TimeInterval = 0.8
    /// 点多于这个数就改成「3 / 12」这样的文字，免得胶囊比扩展栏还长。
    public static let maxDots = 8

    /// 开关开着、扩展栏布局多于一个时才有标签：只有一个布局时没东西可切。
    public static func isAvailable(enabled: Bool, layoutCount: Int) -> Bool {
        enabled && layoutCount > 1
    }

    /// 胶囊里布局名后面那一段。
    public enum Pages: Equatable, Sendable {
        /// 每个布局一个点，`true` 是当前的。
        case dots([Bool])
        /// 布局太多：第几个（从 1 数）/ 一共几个。当前布局不在列表里时第几个是 0。
        case counter(Int, Int)
    }

    /// 当前布局在列表里的位置，不在列表里（删了、没选过）时为 nil。
    public static func pages(ids: [UUID], current: UUID?, maxDots: Int = maxDots) -> Pages {
        let index = current.flatMap { ids.firstIndex(of: $0) }
        if ids.count > maxDots {
            return .counter(index.map { $0 + 1 } ?? 0, ids.count)
        }
        return .dots(ids.indices.map { $0 == index })
    }
}

/// 标签什么时候看得见。
///
/// 三件事让它亮着：指针在扩展栏上、指针在标签上（要去点里面的点和箭头），
/// 刚切换过布局的 1.5 秒。指针离开后再留 0.8 秒，好让它从扩展栏挪到标签上
/// 的路上不消失。时间用调用方给的秒数（单调时钟），这里不读时钟。
public struct LayoutLabelVisibility: Equatable, Sendable {
    public private(set) var onShelf = false
    public private(set) var onLabel = false
    /// 最后一次离开扩展栏或标签的时刻。
    public private(set) var leftAt: TimeInterval?
    /// 闪现到这个时刻为止。
    public private(set) var flashUntil: TimeInterval?

    public init() {}

    public mutating func pointer(onShelf inside: Bool, at time: TimeInterval) {
        if onShelf && !inside { leftAt = time }
        onShelf = inside
    }

    public mutating func pointer(onLabel inside: Bool, at time: TimeInterval) {
        if onLabel && !inside { leftAt = time }
        onLabel = inside
    }

    /// 切换了布局：从现在起亮 `LayoutLabel.flashDuration`。
    public mutating func flash(at time: TimeInterval) {
        flashUntil = time + LayoutLabel.flashDuration
    }

    /// 扩展栏收起或关掉开关：立刻全部清掉。
    public mutating func reset() {
        self = LayoutLabelVisibility()
    }

    public var isPinned: Bool { onShelf || onLabel }

    public func isVisible(at time: TimeInterval) -> Bool {
        if isPinned { return true }
        if let leftAt, time < leftAt + LayoutLabel.lingerAfterLeave { return true }
        if let flashUntil, time < flashUntil { return true }
        return false
    }

    /// 下一次需要重新判断的时刻：现在看得见、又没有指针压着时，它会在这一刻
    /// 变成看不见。压着或已经看不见时为 nil，不用排定时器。
    public func hideDeadline(at time: TimeInterval) -> TimeInterval? {
        guard !isPinned, isVisible(at: time) else { return nil }
        let ends = [leftAt.map { $0 + LayoutLabel.lingerAfterLeave }, flashUntil]
            .compactMap { $0 }
            .filter { $0 > time }
        return ends.max()
    }
}
