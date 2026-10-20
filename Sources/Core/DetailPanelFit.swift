import Foundation

/// 小组件详情面板放在哪、多大。
///
/// 面板原来按打开那一刻量到的高度定尺寸，只把原点夹进屏幕：内容比屏幕
/// 还高时顶上一截出了屏幕，异步读到的日程、提醒、行情让内容变高时窗口
/// 也不跟着变。这里统一算：高度随内容变，上限是所在屏幕的 visibleFrame
/// 减去边距（横排扩展栏再只算扩展栏开口那一侧的空间），超出时由面板容器
/// 改成可滚动，位置整个夹在屏幕里。
///
/// 只按屏幕算时，内容多的面板能占到屏幕的三分之二，所以再加一道统一的
/// 上限（`cap(visible:)`）：含尾巴最高 560pt，且不超过屏幕可见高度的 60%，
/// 取小的那个，但不低于 `minimumHeight`。日历规划和 AI 对话豁免，见
/// `isCapExempt(_:)`。
///
/// 坐标是 AppKit 的屏幕坐标，y 向上。不依赖 AppKit，方便测试。
public enum DetailPanelFit {
    /// 面板离屏幕边缘至少留这么多。
    public static let margin: CGFloat = 8
    /// 尾巴尖和小组件之间的空隙，和原来一样。
    public static let gap: CGFloat = 2
    /// 扩展栏开口那一侧剩下的空间比这还小时（小组件贴着屏幕另一头），
    /// 改用整块屏幕的高度，让面板盖到扩展栏上，而不是挤成一条缝。
    public static let minimumHeight: CGFloat = 160
    /// 面板（含尾巴）统一最高这么高。
    public static let maximumHeight: CGFloat = 560
    /// 面板最多占所在屏幕可见高度的这么多。
    public static let screenShare: CGFloat = 0.6

    /// 统一上限：`maximumHeight` 和屏幕可见高度的 `screenShare` 取小的，
    /// 但不低于 `minimumHeight`（矮屏上也留得下一屏可用的内容）。
    public static func cap(visible: CGRect) -> CGFloat {
        max(minimumHeight, min(maximumHeight, (visible.height * screenShare).rounded(.down)))
    }

    /// 不受统一上限约束、仍按屏幕算的小组件：
    ///
    /// - 日历、本周（日历规划）：月历格加上当天的时间轴，时间轴本身就在面板里
    ///   滚动，外层再限高就成了滚动里套滚动，排日程时拖不动、看不全一天。
    /// - AI 助手：对话区下面是输入框和附件条，限高后输入框会被挤到滚动区底下，
    ///   要先滚到底才能打字。
    public static func isCapExempt(_ kind: WidgetKind) -> Bool {
        switch kind {
        case .calendar, .week, .aiAssistant: true
        default: false
        }
    }

    public struct Placement: Equatable, Sendable {
        /// 面板窗口的 frame，屏幕坐标。
        public var frame: CGRect
        /// 内容比 frame 高，面板要滚动。
        public var overflows: Bool

        public init(frame: CGRect, overflows: Bool) {
            self.frame = frame
            self.overflows = overflows
        }
    }

    /// 面板该开在哪块屏幕上：包含小组件那个点的屏幕；都不包含时（点正好
    /// 落在两块屏幕之间的缝里）取最近的一块。原来按面板原点找屏幕，原点
    /// 一旦落到屏幕外面就退回主屏，面板会跑到另一块显示器上或被切一半。
    public static func screenIndex(for anchor: CGPoint, screens: [CGRect]) -> Int? {
        guard !screens.isEmpty else { return nil }
        if let hit = screens.firstIndex(where: { $0.contains(anchor) }) { return hit }
        var best = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (index, frame) in screens.enumerated() {
            let dx = max(frame.minX - anchor.x, 0, anchor.x - frame.maxX)
            let dy = max(frame.minY - anchor.y, 0, anchor.y - frame.maxY)
            let distance = dx * dx + dy * dy
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        return best
    }

    /// 不知道是哪个小组件被点时（没有悬停位置）用扩展栏开口那一侧的中点，
    /// 而不是屏幕坐标原点，那会把面板甩到主屏左下角。
    public static func fallbackAnchor(edge: DockPosition, shelf: CGRect) -> CGPoint {
        switch edge {
        case .bottom: CGPoint(x: shelf.midX, y: shelf.maxY)
        case .top: CGPoint(x: shelf.midX, y: shelf.minY)
        case .left: CGPoint(x: shelf.maxX, y: shelf.midY)
        case .right: CGPoint(x: shelf.minX, y: shelf.midY)
        }
    }

    /// 面板最高能有多高（含尾巴）。`capped` 为 true 时再受统一上限约束，
    /// 豁免的小组件传 false。
    public static func heightLimit(edge: DockPosition, anchor: CGPoint, visible: CGRect,
                                   capped: Bool = true,
                                   gap: CGFloat = gap, margin: CGFloat = margin) -> CGFloat {
        let screen = screenLimit(edge: edge, anchor: anchor, visible: visible, gap: gap, margin: margin)
        return capped ? min(screen, cap(visible: visible)) : screen
    }

    /// 只按屏幕算的上限：所在屏幕的可用高度减边距，横排扩展栏只算开口那一侧。
    private static func screenLimit(edge: DockPosition, anchor: CGPoint, visible: CGRect,
                                    gap: CGFloat, margin: CGFloat) -> CGFloat {
        let whole = max(0, visible.height - 2 * margin)
        let room: CGFloat
        switch edge {
        case .bottom: room = visible.maxY - margin - (anchor.y + gap)
        case .top: room = (anchor.y - gap) - (visible.minY + margin)
        // 竖排扩展栏：面板在小组件旁边上下居中，能用整块屏幕的高度。
        case .left, .right: room = whole
        }
        return room >= minimumHeight ? min(room, whole) : whole
    }

    /// 按内容的自然尺寸算出面板的 frame。
    ///
    /// 宽度不改：每种小组件的面板宽度是定的，最宽 400pt，任何屏幕都放得下；
    /// 放不下时也只把位置夹住，从左边对齐。
    public static func place(edge: DockPosition, anchor: CGPoint, natural: CGSize,
                             visible: CGRect, capped: Bool = true, gap: CGFloat = gap,
                             margin: CGFloat = margin) -> Placement {
        let limit = heightLimit(edge: edge, anchor: anchor, visible: visible, capped: capped,
                                gap: gap, margin: margin)
        let height = min(natural.height.rounded(.up), limit)
        let size = CGSize(width: natural.width.rounded(.up), height: max(0, height))
        let origin = Geometry.popupOrigin(edge: edge, anchor: anchor, size: size, gap: gap)
        let placed = CGPoint(
            x: clamp(origin.x, low: visible.minX + margin, high: visible.maxX - margin - size.width),
            y: clamp(origin.y, low: visible.minY + margin, high: visible.maxY - margin - size.height))
        return Placement(frame: CGRect(origin: placed, size: size),
                         overflows: natural.height > size.height + 0.5)
    }

    /// 滚动区域的高度：面板高度减去尾巴占的那一截（只有横排扩展栏的尾巴
    /// 在上下方向占高度）。
    public static func viewportHeight(panelHeight: CGFloat, edge: DockPosition,
                                      tailDepth: CGFloat) -> CGFloat {
        max(0, panelHeight - (edge.isHorizontal ? tailDepth : 0))
    }

    /// 内容高度变了多少才值得重新摆一次窗口；小于半个点的抖动不理。
    public static func needsRefit(old: CGFloat, new: CGFloat) -> Bool {
        abs(old - new) >= 0.5
    }

    /// 上限比下限还小（屏幕比面板还窄）时贴着下限，也就是左边。高度已经被
    /// heightLimit 限住，竖直方向到不了这一步。
    private static func clamp(_ value: CGFloat, low: CGFloat, high: CGFloat) -> CGFloat {
        guard high >= low else { return low }
        return min(max(value, low), high)
    }
}
