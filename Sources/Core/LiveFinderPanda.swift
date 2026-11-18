import Foundation

// 动态图标里的小熊猫访达：瞳孔往哪看、怎么平滑地跟过去、指针停下多久回正、
// 什么时候眨眼、多久问一次指针和画多快。不碰 AppKit 和 SwiftUI，全部能在测试里跑。
// 坐标约定：原画是 1024×1024 的画布，y 向下；屏幕坐标（NSEvent.mouseLocation、
// 窗口换算出的图标位置）是 y 向上，换算只在 pupilTarget(iconScreenFrame:...) 里做一次。

/// 原画上量出来的尺寸（design/finder-panda 里 base.png，用白色眼眶的连通区域实测）。
public enum LiveFinderFace {
    public static let canvas = 1024.0

    /// 原画里一个点：x 向右，y 向下，单位是原画像素。
    public struct Point: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
        public static let zero = Point(x: 0, y: 0)
    }

    /// 左眼白色眼眶中心（实测外接框 x 332...430，y 481...603）。
    public static let leftEye = Point(x: 381, y: 542)
    /// 右眼白色眼眶中心（实测外接框 x 587...682，y 483...603）。
    public static let rightEye = Point(x: 634.5, y: 543)
    /// 两只眼眶里较小的那只的半轴（右眼 96×121 的一半，往下取整）。
    public static let socketRadius = Point(x: 48, y: 60)
    /// 瞳孔半径（原画直径约 50 像素）。
    public static let pupilRadius = 25.0
    /// 瞳孔小图对应原画的边长（以瞳孔为中心裁 52×52）。
    public static let pupilCrop = 52.0
    /// 瞳孔中心能走的椭圆半轴。瞳孔边缘离眼眶至少还留 5 像素（横）、7 像素（竖），不出眶。
    public static let travel = Point(x: 18, y: 28)
    /// 指针离眼睛多远（屏幕点）时瞳孔走到头；更近时按比例少走一点，指针在眼前时几乎不动。
    public static let reach = 240.0

    /// 把一个偏移收进 travel 椭圆里（超出时按比例缩回边上）。
    public static func clampToTravel(_ p: Point) -> Point {
        guard p.x.isFinite, p.y.isFinite else { return .zero }
        let k = (p.x / travel.x) * (p.x / travel.x) + (p.y / travel.y) * (p.y / travel.y)
        guard k > 1 else { return p }
        let s = 1 / k.squareRoot()
        return Point(x: p.x * s, y: p.y * s)
    }

    /// 指针相对眼睛的位移（屏幕点，y 向下为正）对应的瞳孔偏移（原画像素）。
    public static func pupilTarget(dx: Double, dy: Double) -> Point {
        guard dx.isFinite, dy.isFinite else { return .zero }
        let distance = (dx * dx + dy * dy).squareRoot()
        guard distance > 0.5 else { return .zero }
        let m = min(1, distance / reach)
        // 缓出：离开一点点就明显转过去，远了慢慢贴到边。
        let eased = 1 - (1 - m) * (1 - m)
        let p = Point(x: dx / distance * eased * travel.x, y: dy / distance * eased * travel.y)
        return clampToTravel(p)
    }

    /// 眼睛在屏幕上的位置。iconFrame 是图标格在屏幕上的矩形（y 向上），画布铺满这个矩形。
    public static func eyeOnScreen(_ eye: Point, iconFrame: CGRect) -> CGPoint {
        let k = Double(min(iconFrame.width, iconFrame.height)) / canvas
        return CGPoint(x: Double(iconFrame.minX) + eye.x * k, y: Double(iconFrame.maxY) - eye.y * k)
    }

    /// 屏幕上的指针（y 向上）对应这只眼睛的瞳孔偏移（原画像素，y 向下）。
    public static func pupilTarget(eye: Point, iconFrame: CGRect, pointer: CGPoint) -> Point {
        let center = eyeOnScreen(eye, iconFrame: iconFrame)
        return pupilTarget(dx: Double(pointer.x - center.x), dy: Double(center.y - pointer.y))
    }
}

/// 二维临界阻尼弹簧：跟得上又不来回晃。
public struct LiveFinderSpring: Equatable, Sendable {
    public var position = LiveFinderFace.Point.zero
    public var velocity = LiveFinderFace.Point.zero

    public init() {}

    /// 往 target 走 dt 秒。一步太长时拆小步，避免数值发散。
    public mutating func step(toward target: LiveFinderFace.Point, dt: Double, omega: Double) {
        guard dt.isFinite, dt > 0, omega.isFinite, omega > 0 else { return }
        var remaining = min(dt, 0.25)
        let h = 1.0 / 120
        while remaining > 0 {
            let t = min(h, remaining)
            let ax = omega * omega * (target.x - position.x) - 2 * omega * velocity.x
            let ay = omega * omega * (target.y - position.y) - 2 * omega * velocity.y
            velocity.x += ax * t
            velocity.y += ay * t
            position.x += velocity.x * t
            position.y += velocity.y * t
            remaining -= t
        }
    }

    /// 离目标不到 0.05 原画像素且几乎不动：算停稳了，可以不再刷新。
    public func isSettled(at target: LiveFinderFace.Point) -> Bool {
        abs(position.x - target.x) < 0.05 && abs(position.y - target.y) < 0.05
            && abs(velocity.x) < 0.5 && abs(velocity.y) < 0.5
    }

    public mutating func snap(to target: LiveFinderFace.Point) {
        position = target
        velocity = .zero
    }
}

/// 两颗瞳孔看向哪里：指针动了就跟（快弹簧），指针停下 3 秒后慢慢回正（慢弹簧）。
public struct LiveFinderGaze: Equatable, Sendable {
    /// 指针静止多久后回正。
    public static let idleDelay = 3.0
    /// 跟指针的弹簧角频率（约 0.25 秒跟上）。
    public static let followOmega = 16.0
    /// 回正的弹簧角频率（约 1 秒慢慢回来）。
    public static let returnOmega = 4.0
    /// 指针挪动不到这么多屏幕点不算动，免得抖。
    public static let moveThreshold = 0.5

    public private(set) var left = LiveFinderSpring()
    public private(set) var right = LiveFinderSpring()
    public private(set) var leftTarget = LiveFinderFace.Point.zero
    public private(set) var rightTarget = LiveFinderFace.Point.zero
    public private(set) var lastPointer: CGPoint?
    public private(set) var lastMove: Date?
    public private(set) var lastStep: Date?

    public init() {}

    /// 指针停下够久（或从没动过）：瞳孔该回正。
    public func isIdle(at now: Date) -> Bool {
        guard let lastMove else { return true }
        return now.timeIntervalSince(lastMove) >= Self.idleDelay
    }

    /// 现在瞳孔该去的地方：闲着时回正。
    public func goals(at now: Date) -> (left: LiveFinderFace.Point, right: LiveFinderFace.Point) {
        isIdle(at: now) ? (.zero, .zero) : (leftTarget, rightTarget)
    }

    /// 记下一次轮询读到的指针和图标位置。返回指针这次有没有动（动了才需要重算、刷新）。
    @discardableResult
    public mutating func observe(pointer: CGPoint, iconFrame: CGRect, at now: Date) -> Bool {
        guard pointer.x.isFinite, pointer.y.isFinite else { return false }
        if let last = lastPointer {
            let dx = Double(pointer.x - last.x), dy = Double(pointer.y - last.y)
            guard (dx * dx + dy * dy).squareRoot() >= Self.moveThreshold else { return false }
        }
        let first = lastPointer == nil
        lastPointer = pointer
        leftTarget = LiveFinderFace.pupilTarget(eye: LiveFinderFace.leftEye, iconFrame: iconFrame, pointer: pointer)
        rightTarget = LiveFinderFace.pupilTarget(eye: LiveFinderFace.rightEye, iconFrame: iconFrame, pointer: pointer)
        // 第一次读到只当基准，不算「动了」，刚出现时眼睛先居中。
        if !first { lastMove = now }
        return !first
    }

    /// 走到 now 这一帧，返回两颗瞳孔的偏移（原画像素）。
    /// 停了很久再恢复时，第一步最多走 1/15 秒，不会一下跳过去。
    public mutating func step(at now: Date) -> (left: LiveFinderFace.Point, right: LiveFinderFace.Point) {
        let dt = lastStep.map { min(max(0, now.timeIntervalSince($0)), 1.0 / 15) } ?? 1.0 / 30
        lastStep = now
        let goal = goals(at: now)
        let omega = isIdle(at: now) ? Self.returnOmega : Self.followOmega
        left.step(toward: goal.left, dt: dt, omega: omega)
        right.step(toward: goal.right, dt: dt, omega: omega)
        if left.isSettled(at: goal.left) { left.snap(to: goal.left) }
        if right.isSettled(at: goal.right) { right.snap(to: goal.right) }
        return (LiveFinderFace.clampToTravel(left.position), LiveFinderFace.clampToTravel(right.position))
    }

    /// 两颗瞳孔都停在该去的地方：可以暂停刷新。
    public func isSettled(at now: Date) -> Bool {
        let goal = goals(at: now)
        return left.isSettled(at: goal.left) && right.isSettled(at: goal.right)
    }

    /// 暂停后重新开始时调用，下一步不拿很久以前的时间算。
    public mutating func pause() { lastStep = nil }

    /// 回到居中、静止，忘掉指针（开关重开、减弱动态效果打开时）。
    public mutating func reset() { self = LiveFinderGaze() }
}

/// 一次眨眼的安排：先等 wait 秒，再闭眼 closed[0] 秒；偶尔连眨两下，中间睁眼 gap 秒。
public struct LiveFinderBlink: Equatable, Sendable {
    public static let interval: ClosedRange<Double> = 3...7
    public static let closedDuration: ClosedRange<Double> = 0.12...0.15
    public static let gapDuration: ClosedRange<Double> = 0.10...0.14
    /// 连眨两下的概率。
    public static let doubleChance = 0.2

    public var wait: Double
    public var closed: [Double]
    public var gap: Double

    public init(wait: Double, closed: [Double], gap: Double) {
        self.wait = wait
        self.closed = closed
        self.gap = gap
    }

    public static func next<R: RandomNumberGenerator>(using rng: inout R) -> LiveFinderBlink {
        let wait = Double.random(in: interval, using: &rng)
        let double = Double.random(in: 0..<1, using: &rng) < doubleChance
        let first = Double.random(in: closedDuration, using: &rng)
        let gap = Double.random(in: gapDuration, using: &rng)
        let closed = double ? [first, Double.random(in: closedDuration, using: &rng)] : [first]
        return LiveFinderBlink(wait: wait, closed: closed, gap: gap)
    }
}

/// 刷新节奏：指针最多每秒问 30 次，画面最多每秒 30 帧；低电量明显降频；
/// 指针好几秒没动、眼睛也停稳时问得更慢。减弱动态效果时根本不问（瞳孔居中、不眨眼）。
public enum LiveFinderMotion {
    public static func frameInterval(lowPower: Bool) -> Double {
        lowPower ? 1.0 / 12 : 1.0 / 30
    }

    public static func pollInterval(lowPower: Bool, active: Bool) -> Double {
        switch (lowPower, active) {
        case (false, true): return 1.0 / 30
        case (false, false): return 1.0 / 10
        case (true, true): return 1.0 / 10
        case (true, false): return 1.0 / 4
        }
    }
}
