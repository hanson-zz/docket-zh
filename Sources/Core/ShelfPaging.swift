import Foundation

/// 扩展栏用触控板两指翻页（切换布局）的方向。
public enum ShelfPageDirection: String, Codable, Sendable, CaseIterable {
    /// 左右轻扫翻页（原来的做法，免费）。
    case horizontal
    /// 上下滑翻页（码头 Pro）：上滑下一页、下滑上一页，左右滑留给滚动放不下的扩展栏。
    case vertical

    public static let defaultValue: Self = .horizontal

    public var label: String {
        switch self {
        case .horizontal: tr("左右")
        case .vertical: tr("上下")
        }
    }
}

/// 两指滑动在扩展栏上归不归翻页、往哪翻。纯函数，测试用。
///
/// 上下翻页只用在横着的扩展栏（底部、顶部、浮动）上；竖着的扩展栏上下本来就是长轴，
/// 留给滚动，照旧左右翻。上下翻页时：
/// - 指针停在能用滑动打开面板的格子上：交给开面板（`PanelSwipe`），这里不碰；
/// - 停在 App 或空白处：竖向为主的滑动翻页，手指往上是下一页、往下是上一页，
///   开不开「自然滚动」都按手指的方向；
/// - 左右滑不再翻页，扩展栏放不下时用来滚动。
/// ⌘ + 滚轮始终翻页，和以前一样。
public enum ShelfPaging {

    public enum Route: Equatable, Sendable {
        /// 不归翻页，照旧滚动或交给别人。
        case pass
        /// 归翻页，把这个增量喂给 `LayoutGesture`（负数是下一页）。
        case page(Double)
    }

    /// 竖向为主，留出斜着拖的余量，和 `LayoutGesture.isSideways` 对称。
    public static func isUpright(dx: Double, dy: Double) -> Bool {
        abs(dy) > abs(dx) * 1.5
    }

    /// 上下翻页在这条扩展栏上生不生效：选了上下（且已解锁，调用方先判断）且扩展栏是横的。
    public static func verticalApplies(direction: ShelfPageDirection, shelfIsVertical: Bool) -> Bool {
        direction == .vertical && !shelfIsVertical
    }

    /// 把竖向的滚动增量换成 `LayoutGesture` 的增量：手指往上（下一页）为负。
    public static func verticalDelta(dy: Double, inverted: Bool) -> Double {
        let fingerUp = PanelSwipe.fingerMotion(dx: 0, dy: dy, inverted: inverted).y
        return -fingerUp
    }

    /// 一次滚动事件归不归翻页。
    /// - Parameters:
    ///   - vertical: 上下翻页在这条扩展栏上生效（见 `verticalApplies`）。
    ///   - overPanelTarget: 指针下的格子能用两指滑动打开面板，且那个开关开着。
    public static func route(dx: Double, dy: Double, precise: Bool, inverted: Bool,
                             command: Bool, overflowing: Bool,
                             vertical: Bool, overPanelTarget: Bool) -> Route {
        if command {
            return .page(abs(dx) > abs(dy) ? dx : dy)
        }
        guard precise else { return .pass }
        if vertical {
            guard !overPanelTarget, isUpright(dx: dx, dy: dy) else { return .pass }
            return .page(verticalDelta(dy: dy, inverted: inverted))
        }
        guard !overflowing, LayoutGesture.isSideways(dx: dx, dy: dy) else { return .pass }
        return .page(dx)
    }

    /// 翻页后新的一页从哪边滑进来（点，SwiftUI 坐标，正数是从下方）。
    /// 下一页从下方上来，上一页从上方下来；不是手势翻的（快捷键、菜单）不滑。
    public static let slideDistance = 18.0

    public static func entryOffset(step: Int, reduceMotion: Bool) -> Double {
        guard !reduceMotion, step != 0 else { return 0 }
        return step > 0 ? slideDistance : -slideDistance
    }
}

/// 一次两指手势翻过页之后，同一手势剩下的事件和惯性尾巴都归翻页、吞掉。
///
/// 翻页后扩展栏换成了新布局，指针下的格子（能不能滑开面板）和放不放得下都按新布局算，
/// 逐个事件重新判断归属会把剩下的滑动和惯性交给滚动，新布局跟着滚一截。手指在翻页那一刻
/// 已经决定了，这次手势剩下的部分不再重新判断；下一次手势（began / mayBegin）重新开始。
/// 普通滚轮没有阶段也没有惯性，从来不拦。
public struct ShelfPagingTail: Sendable {
    private var paged = false

    public init() {}

    /// 手指刚放上，新的一次手势。
    public mutating func begin() { paged = false }

    /// 这次手势翻了一页。
    public mutating func didPage() { paged = true }

    /// 归属判断说不归翻页的事件，还要不要当成这次翻页手势的一部分吞掉。
    public func swallows(phased: Bool, momentum: Bool) -> Bool {
        paged && (phased || momentum)
    }
}
