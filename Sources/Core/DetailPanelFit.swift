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
/// 取小的那个，但不低于 `minimumHeight`。日历规划和 AI 对话豁免，扫雷大师按实例豁免，见
/// `isCapExempt(_:)`、`isCapExempt(_:config:)`。
///
/// 坐标是 AppKit 的屏幕坐标，y 向上。不依赖 AppKit，方便测试。
public enum DetailPanelFit {
    /// 面板离屏幕可用区域边缘至少留这么多（上面是菜单栏，下面是程序坞或
    /// 扩展栏）。原来是 8，贴着菜单栏太近，面板顶边看着像被菜单栏压住。
    public static let margin: CGFloat = 12
    /// 底部钉住的“外观”栏放不下时，上面的滚动区域至少留这么高（面板矮于
    /// 两倍时取一半），外观栏自己再滚。
    public static let minimumScroll: CGFloat = 120
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

    /// 按这张卡片的配置判断：整种豁免的照旧；扫雷只有选了大师时豁免（32×32 的棋盘本身
    /// 就有 638 高，限在 560 里只看得到半盘），初级、中级仍受统一上限。豁免后仍不超过
    /// 所在屏幕的可见区，放不下在面板里滚动。
    public static func isCapExempt(_ kind: WidgetKind, config: WidgetConfig) -> Bool {
        if isCapExempt(kind) { return true }
        return kind == .minesweeper && Minesweeper.panelIsCapExempt(config)
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

    /// 把一个已经摆好的面板 frame 夹回屏幕可用区域（减 `margin`）：太高就压到
    /// 可用高度，再把整个面板挪进来。已经在里面时原样返回。宽度不动。
    public static func contain(_ frame: CGRect, in visible: CGRect,
                               margin: CGFloat = margin) -> CGRect {
        let inner = visible.insetBy(dx: margin, dy: margin)
        guard inner.width > 0, inner.height > 0 else { return frame }
        var out = frame
        if out.height > inner.height {
            // 压高度时保住顶边以下那部分的位置不乱跳：从可用区顶上往下排。
            out.size.height = inner.height.rounded(.down)
        }
        out.origin.y = clamp(out.origin.y, low: inner.minY, high: inner.maxY - out.height)
        out.origin.x = clamp(out.origin.x, low: inner.minX, high: inner.maxX - out.width)
        return out
    }

    /// 面板能用的屏幕区域：系统给的 visibleFrame，顶上再确保让出菜单栏。
    ///
    /// 菜单栏设成自动隐藏时，visibleFrame 会一直伸到屏幕顶边；面板的窗口层级
    /// 在菜单栏下面，菜单栏一滑出来就把面板顶上一截盖住。`menuBar` 传菜单栏
    /// 高度（有刘海的屏幕取刘海那一条的高度），这块屏幕没有菜单栏时传 0。
    public static func usableArea(visible: CGRect, screen: CGRect, menuBar: CGFloat) -> CGRect {
        guard menuBar > 0 else { return visible }
        let top = min(visible.maxY, screen.maxY - menuBar)
        guard top > visible.minY else { return visible }
        return CGRect(x: visible.minX, y: visible.minY, width: visible.width, height: top - visible.minY)
    }

    /// 滚动区域和底部钉住的“外观”栏各分多高。
    public struct Viewports: Equatable, Sendable {
        /// 上面能滚的内容区。
        public var scroll: CGFloat
        /// 底部钉住的外观栏；比它的自然高度小时，外观栏自己滚。
        public var footer: CGFloat

        public init(scroll: CGFloat, footer: CGFloat) {
            self.scroll = scroll
            self.footer = footer
        }
    }

    /// 面板（含尾巴）高 `panelHeight` 时，滚动区和外观栏各给多少。
    ///
    /// 外观栏优先按自然高度给全，不随内容滚走；只有面板矮到连滚动区的最低
    /// 高度（`minimumScroll`，面板矮于两倍时取一半）都留不下时才压它。
    /// 没有外观栏的面板传 0，滚动区就是去掉尾巴后的整块。
    public static func viewports(panelHeight: CGFloat, edge: DockPosition, tailDepth: CGFloat,
                                 footer: CGFloat) -> Viewports {
        let body = viewportHeight(panelHeight: panelHeight, edge: edge, tailDepth: tailDepth)
        let footer = max(0, footer)
        let keep = min(minimumScroll, body / 2)
        let pinned = min(footer, max(0, body - keep))
        return Viewports(scroll: max(0, body - pinned), footer: pinned)
    }

    /// 滚动区两头要不要淡出：上面有被滚上去的内容时顶边淡出，下面还有时
    /// 底边淡出。滚动条不画，靠这两道淡出提示还能滚。
    public static func fades(offset: CGFloat, container: CGFloat,
                             content: CGFloat) -> (top: Bool, bottom: Bool) {
        guard content > container + 0.5 else { return (false, false) }
        return (offset > 0.5, offset + container < content - 0.5)
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
