import Foundation

/// 打开了但没固定的 App 在扩展栏上放在哪里，或者不显示。
///
/// 横向扩展栏从左往右数，竖向从上往下数，所以“最左边”在竖向扩展栏上就是
/// 最上边，“最右边”就是最下边。
public enum RunningAppsPlacement: String, Codable, Sendable, CaseIterable {
    /// 不显示。
    case hidden
    /// 扩展栏最开头，在小组件之前。
    case start
    /// 固定 App 区之前，也就是小组件之后。
    case beforeApps
    /// 固定 App 之后。加这项设置之前的行为，所以是默认值。
    case afterApps
    /// 扩展栏最末，只在废纸篓之前：废纸篓始终最后。
    case end

    public static let defaultValue: Self = .afterApps

    /// 旧版的“显示正在运行的应用”开关换成这五档时的对应：关是不显示，开是
    /// 当时唯一的位置，固定 App 之后。
    public init(legacyShowRunningApps: Bool) {
        self = legacyShowRunningApps ? .afterApps : .hidden
    }

    /// 设置里显示的名字。竖向扩展栏把“最左边/最右边”说成“最上边/最下边”。
    public func label(vertical: Bool) -> String {
        switch self {
        case .hidden: tr("不显示", context: "running")
        case .start: vertical ? tr("最上边") : tr("最左边")
        case .beforeApps: tr("应用前")
        case .afterApps: tr("应用后")
        case .end: vertical ? tr("最下边") : tr("最右边")
        }
    }
}

extension RunningAppsPlacement: LenientChoice { public static var fallback: Self { .defaultValue } }

/// 扩展栏一行里的一格：固定项、正在运行的 App、废纸篓，以及分隔线和缩放把手。
public enum ShelfRowToken: Hashable, Sendable {
    /// 固定项，值是它在固定项里的下标。
    case pinned(Int)
    /// 正在运行（没固定）的 App，值是它在运行列表里的下标。
    case running(Int)
    case trash
    case separator
    case grip
}

/// 扩展栏一行的拼接顺序。和尺寸无关，视图拿它来排格子、量长度、算放大。
public enum ShelfRow {
    /// 正在运行的那一簇插在固定项的第几个位置（0 到 `pinnedIsWidget.count`），
    /// 不显示时是 nil。
    ///
    /// - 最左边：0。
    /// - 应用前：最后一个小组件之后，也就是缩放把手所在的那道缝；没有小组件时是 0。
    /// - 应用后：最后一个固定 App（不是小组件的固定项）之后；没有固定 App 时
    ///   退回到应用前的位置，也就是小组件之后。
    /// - 最右边：所有固定项之后。
    public static func runningInsertionIndex(pinnedIsWidget: [Bool],
                                             placement: RunningAppsPlacement) -> Int? {
        let afterLastWidget = (pinnedIsWidget.lastIndex(where: { $0 }) ?? -1) + 1
        switch placement {
        case .hidden: return nil
        case .start: return 0
        case .beforeApps: return afterLastWidget
        case .afterApps:
            if let lastApp = pinnedIsWidget.lastIndex(where: { !$0 }) { return lastApp + 1 }
            return afterLastWidget
        case .end: return pinnedIsWidget.count
        }
    }

    /// 一整行，按显示顺序。
    ///
    /// - 正在运行的一簇和两边相邻的内容之间各有一条分隔线（只在那一边有内容时）。
    /// - 废纸篓始终最后，前面有内容时带一条分隔线。
    /// - 缩放把手跟在最后一个小组件后面，它本身就在一行末尾时不放。
    public static func tokens(pinnedIsWidget: [Bool], runningCount: Int, showsTrash: Bool,
                              placement: RunningAppsPlacement) -> [ShelfRowToken] {
        // 先排内容，再插分隔线和把手。
        var entries: [ShelfRowToken] = pinnedIsWidget.indices.map { .pinned($0) }
        if runningCount > 0,
           let at = runningInsertionIndex(pinnedIsWidget: pinnedIsWidget, placement: placement) {
            entries.insert(contentsOf: (0..<runningCount).map { .running($0) }, at: at)
        }
        if showsTrash { entries.append(.trash) }

        func isRunning(_ token: ShelfRowToken) -> Bool {
            if case .running = token { return true }
            return false
        }
        func isWidget(_ token: ShelfRowToken) -> Bool {
            if case .pinned(let index) = token { return pinnedIsWidget[index] }
            return false
        }

        let lastWidget = entries.lastIndex(where: isWidget)
        var row: [ShelfRowToken] = []
        for (index, entry) in entries.enumerated() {
            let previous = index > 0 ? entries[index - 1] : nil
            if let previous {
                // 进入运行簇、离开运行簇（废纸篓自己带一条，不重复）、废纸篓前。
                let entering = isRunning(entry) && !isRunning(previous)
                let leaving = !isRunning(entry) && isRunning(previous) && entry != .trash
                if entering || leaving || entry == .trash { row.append(.separator) }
            }
            row.append(entry)
            if let lastWidget, index == lastWidget, index < entries.count - 1 {
                row.append(.grip)
            }
        }
        return row
    }
}
