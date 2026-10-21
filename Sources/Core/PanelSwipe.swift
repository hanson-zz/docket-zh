import Foundation

/// 指针停在扩展栏的小组件（或分组、文件夹）上，触控板两指沿面板弹出的方向滑一下
/// 打开它的面板，反方向滑收起开着的面板。
///
/// 只用扩展栏的短轴：长轴方向的滑动已经用来切换布局和滚动放不下的扩展栏
/// （`LayoutGesture`、`ScrollRelay`），这里一点不碰。
public enum PanelSwipe {
    /// 一次手势的结果。
    public enum Action: Equatable, Sendable {
        case open, close
    }

    /// 面板从这条边的扩展栏往哪边长出来，屏幕坐标（x 向右、y 向上）的单位向量。
    /// 底部往上，顶部往下，左边往右，右边往左，都是朝屏幕内侧。浮动扩展栏按
    /// `effectivePosition` 当作顶部或底部，面板也照那个方向弹，所以同一张表就够。
    public static func openDirection(edge: DockPosition) -> (x: Double, y: Double) {
        switch edge {
        case .bottom: (0, 1)
        case .top: (0, -1)
        case .left: (1, 0)
        case .right: (-1, 0)
        }
    }

    /// 把一次滚动的增量换成手指实际移动的方向（x 向右、y 向上）。
    ///
    /// 系统的“自然滚动”会把增量反过来（`isDirectionInvertedFromDevice`）。用户说
    /// “往上滑”说的是手指，所以不管开没开自然滚动，手指往上都是往上。
    /// 开着自然滚动时内容跟着手指走：手指往下 dy 为正，手指往右 dx 为正。
    public static func fingerMotion(dx: Double, dy: Double, inverted: Bool) -> (x: Double, y: Double) {
        inverted ? (dx, -dy) : (-dx, dy)
    }

    /// 手指移动沿面板弹出方向的分量（正为打开方向）和沿扩展栏长轴的分量大小。
    public static func components(dx: Double, dy: Double, inverted: Bool,
                                  edge: DockPosition) -> (along: Double, across: Double) {
        let finger = fingerMotion(dx: dx, dy: dy, inverted: inverted)
        let direction = openDirection(edge: edge)
        let along = finger.x * direction.x + finger.y * direction.y
        let across = edge.isVertical ? abs(finger.y) : abs(finger.x)
        return (along, across)
    }

    /// 卡片自己要用滚动的小组件：滚动交给卡片，不拿来开面板。便签多于一张时
    /// 卡片上的滚动是翻页（`StickyScrollPager`），只有一张时也不开，免得同一张
    /// 卡片时而翻页时而开面板。
    public static func contentScrolls(_ kind: WidgetKind) -> Bool {
        kind == .notes
    }

    /// 一次滚动事件里手势用得到的部分，从 `NSEvent` 抄过来，好在 Core 里测试。
    public struct Event: Sendable {
        public var dx: Double
        public var dy: Double
        /// 触控板和妙控鼠标给的是逐点的精确增量；普通滚轮一格一格，不算。
        public var precise: Bool
        /// 系统设置里开着“自然滚动”。
        public var inverted: Bool
        /// 手指刚放上（`phase` 含 began 或 mayBegin）。
        public var began: Bool
        /// 手指离开后系统补的惯性尾巴（`momentumPhase` 非空）。
        public var momentum: Bool
        /// 带手势阶段（`phase` 非空）。滚轮事件没有阶段，也没有惯性。
        public var phased: Bool
        /// 按着 Command：那是切换布局。
        public var command: Bool
        public var time: TimeInterval

        public init(dx: Double, dy: Double, precise: Bool = true, inverted: Bool = true,
                    began: Bool = false, momentum: Bool = false, phased: Bool = true,
                    command: Bool = false, time: TimeInterval) {
            self.dx = dx
            self.dy = dy
            self.precise = precise
            self.inverted = inverted
            self.began = began
            self.momentum = momentum
            self.phased = phased
            self.command = command
            self.time = time
        }
    }
}

/// 一次两指滑动从开始到惯性结束，决定它归不归开面板、什么时候触发。
///
/// 手势开头那几点决定归属：指针在能开面板的格子上、短轴分量至少是长轴的两倍，
/// 这次手势就归这里，之后的事件（包括惯性尾巴）全吞掉，扩展栏不会跟着滚；否则
/// 整个手势原样交回去，切换布局和滚动照旧。归这里的手势沿短轴累计够 `threshold`
/// 点触发一次，同一次手势不再触发，惯性只吞不算。
public struct PanelSwipeGesture: Sendable {
    /// 触发要走的点数。和切换布局差不多远，碰一下不算。
    public static let threshold = 36.0
    /// 累计到这么多点再判断方向，开头一两点的抖动不作数。
    public static let decideAfter = 4.0
    /// 短轴分量至少是长轴的几倍才算沿短轴滑。
    public static let dominance = 2.0
    /// 停这么久说明手指已经抬起，即使没收到阶段。
    public static let idleReset: TimeInterval = 0.3

    /// 这次事件怎么处理。
    public enum Outcome: Equatable, Sendable {
        /// 不归这里，交给原来的滚动和切换布局。
        case pass
        /// 归这里，吞掉，不触发。
        case consume
        /// 归这里，吞掉，并打开或收起面板。
        case fire(PanelSwipe.Action)
    }

    private enum Claim: Sendable { case undecided, mine, notMine }

    private var claim = Claim.undecided
    private var travelled = 0.0
    private var seenAlong = 0.0
    private var seenAcross = 0.0
    private var spent = false
    private var lastEvent: TimeInterval = -.greatestFiniteMagnitude

    public init() {}

    /// 手指刚放上，新的一次手势。
    public mutating func begin() {
        claim = .undecided
        travelled = 0
        seenAlong = 0
        seenAcross = 0
        spent = false
    }

    /// 一次滚动事件。`target` 是指针下的格子有没有能用滑动打开的面板，
    /// `enabled` 是设置里的开关。
    public mutating func feed(_ event: PanelSwipe.Event, edge: DockPosition,
                              target: Bool, enabled: Bool) -> Outcome {
        guard enabled else {
            claim = .notMine
            return .pass
        }
        if event.began {
            begin()
        } else if !event.momentum, event.time - lastEvent > Self.idleReset {
            begin()
        }
        lastEvent = event.time

        // 普通滚轮：一格一格、没有阶段也没有惯性，从来不开面板。
        guard event.precise, event.phased || event.momentum else { return .pass }

        // 惯性尾巴：手指已经决定了，归这里就吞掉别让扩展栏滚，但不算数。
        if event.momentum { return claim == .mine ? .consume : .pass }

        switch claim {
        case .notMine:
            return .pass
        case .undecided:
            guard target, !event.command else {
                claim = .notMine
                return .pass
            }
            let parts = PanelSwipe.components(dx: event.dx, dy: event.dy,
                                              inverted: event.inverted, edge: edge)
            travelled += parts.along
            seenAlong += abs(parts.along)
            seenAcross += parts.across
            guard seenAlong + seenAcross >= Self.decideAfter else { return .pass }
            guard seenAlong >= seenAcross * Self.dominance else {
                claim = .notMine
                return .pass
            }
            claim = .mine
            return fireIfDue()
        case .mine:
            let parts = PanelSwipe.components(dx: event.dx, dy: event.dy,
                                              inverted: event.inverted, edge: edge)
            travelled += parts.along
            return fireIfDue()
        }
    }

    private mutating func fireIfDue() -> Outcome {
        guard !spent, abs(travelled) >= Self.threshold else { return .consume }
        spent = true
        return .fire(travelled > 0 ? .open : .close)
    }
}
