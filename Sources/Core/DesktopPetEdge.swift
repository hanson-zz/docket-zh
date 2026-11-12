import Foundation

// 桌面宠物停在哪、拖完吸到哪条边、头顶气泡说什么、快捷条有哪几个按钮。
// 都是纯逻辑，窗口和读屏幕在 `DesktopPetController`。

// MARK: - 停靠位置

/// 设置里的「停靠位置」。
public enum DesktopPetAnchor: String, Codable, CaseIterable, Sendable {
    /// 程序坞上沿：散步、发呆、睡觉（原来的样子）。
    case dock
    /// 屏幕下边缘：平时趴着，偶尔探头、伸懒腰、挪几步。
    /// 上边缘（菜单栏下方）：前爪抓着菜单栏下沿吊在那里轻轻晃。
    /// 左、右边缘：抱着屏幕边（考拉抱树），只露头和前爪，点一下爬出来，偶尔沿边爬一段。
    case left, right, top, bottom
    /// 随意：拖到哪停哪，坐在那里。
    case free

    public var title: String {
        switch self {
        case .dock: tr("程序坞上沿")
        case .left: tr("屏幕左边缘")
        case .right: tr("屏幕右边缘")
        case .top: tr("屏幕上边缘")
        case .bottom: tr("屏幕下边缘")
        case .free: tr("随意（拖到哪停哪）")
        }
    }

    /// 脚踩哪条边。程序坞和随意都是站着（脚朝下）。
    public var edge: DesktopPetEdge {
        switch self {
        case .dock, .bottom, .free: .bottom
        case .left: .left
        case .right: .right
        case .top: .top
        }
    }

    public var style: DesktopPetStyle {
        switch self {
        case .dock: .stroll
        case .free: .sit
        case .bottom: .curl
        case .top: .hang
        case .left, .right: .side
        }
    }
}

/// 小熊猫待的那条边。图一直正着画（不转）：下边脚踩着，上边吊着，左右边从屏幕边探头。
public enum DesktopPetEdge: Equatable, Sendable {
    case bottom, top, left, right

    /// “上”（离开这条边）在屏幕坐标（左下原点）里的方向。
    public var up: (dx: Double, dy: Double) {
        switch self {
        case .bottom: (0, 1)
        case .top: (0, -1)
        case .left: (1, 0)
        case .right: (-1, 0)
        }
    }

    /// 沿边坐标在左右边是纵坐标，在上下边是横坐标。
    public var vertical: Bool { self == .left || self == .right }

    /// 画的时候要不要左右翻（帧都朝右）。上下边照状态机里的朝向（朝左就翻）；
    /// 左右边抱树各有专门画的一套（右边那套本身朝左），都不翻。
    public func flipped(facingLeft: Bool) -> Bool {
        switch self {
        case .bottom, .top: facingLeft
        case .left, .right: false
        }
    }
}

/// 拖过以后记住的位置。宽松解码，读不出的字段用默认值。
public struct DesktopPetSpot: Codable, Hashable, Sendable {
    /// 哪块屏幕（CGDirectDisplayID）；找不到这块屏幕时用主屏。
    public var display: UInt32?
    /// 沿边的哪儿，0…1（随意模式是横向的比例）。
    public var along: Double
    /// 随意模式纵向的比例，0…1（从下往上）。贴边时不用。
    public var across: Double

    public init(display: UInt32? = nil, along: Double = 0.5, across: Double = 0.5) {
        self.display = display
        self.along = DesktopPetBrain.clamp(along, 0...1)
        self.across = DesktopPetBrain.clamp(across, 0...1)
    }

    private enum CodingKeys: String, CodingKey { case display, along, across }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        display = (try? c.decodeIfPresent(UInt32.self, forKey: .display)) ?? nil
        along = DesktopPetBrain.clamp((try? c.decodeIfPresent(Double.self, forKey: .along)) ?? 0.5, 0...1)
        across = DesktopPetBrain.clamp((try? c.decodeIfPresent(Double.self, forKey: .across)) ?? 0.5, 0...1)
    }
}

// MARK: - 那条边

/// 小熊猫待的那条线：脚踩在哪、沿边能走多远、平时什么样子。坐标都是屏幕坐标（左下原点）。
public struct DesktopPetTrack: Equatable, Sendable {
    public var edge: DesktopPetEdge
    public var style: DesktopPetStyle
    /// 脚踩的线：底边、上边是纵坐标，左右边是横坐标。
    public var base: Double
    /// 沿边能待的范围：底边、上边是横坐标，左右边是纵坐标。
    public var lane: ClosedRange<Double>
    /// 废纸篓在沿边坐标上的位置（只有程序坞上有）。
    public var trashX: Double?

    public init(edge: DesktopPetEdge, style: DesktopPetStyle, base: Double, lane: ClosedRange<Double>,
                trashX: Double? = nil) {
        self.edge = edge
        self.style = style
        self.base = base
        self.lane = lane
        self.trashX = trashX
    }

    /// 脚底中点在屏幕上的位置；`lift` 是离开这条边多远。下边、程序坞、随意用这个；
    /// 上边吊着见 `hangPoint`，左右边探头见 `peekFeet`。
    public func feet(along: Double, lift: Double = 0) -> CGPoint {
        let up = edge.up
        if edge.vertical {
            return CGPoint(x: base + up.dx * lift, y: along)
        }
        return CGPoint(x: along, y: base + up.dy * lift)
    }

    /// 上边缘吊着：挂点（前爪抓握线）在屏幕上的位置，就在可见区域上沿（菜单栏下沿）。
    public func hangPoint(along: Double) -> CGPoint {
        CGPoint(x: along, y: base)
    }

    /// 左右边探头：图正着画、脚踩在沿边坐标那一高度，`width` 宽的图只露出 `reveal`（0…1）
    /// 那么多在屏幕里，其余藏在边外。返回脚底中点。
    public func peekFeet(along: Double, width: Double, reveal: Double) -> CGPoint {
        let shown = width * DesktopPetSide.clampReveal(reveal)
        let x = edge == .right ? base + width / 2 - shown : base - width / 2 + shown
        return CGPoint(x: x, y: along)
    }

    /// 屏幕上某一点落在这条边的沿边坐标（夹在范围里）。
    public func along(of point: CGPoint) -> Double {
        DesktopPetBrain.clamp(Double(edge.vertical ? point.y : point.x), lane)
    }

    /// 沿边坐标换成 0…1，记住位置用。
    public func fraction(of along: Double) -> Double {
        let span = lane.upperBound - lane.lowerBound
        guard span > 0 else { return 0.5 }
        return DesktopPetBrain.clamp((along - lane.lowerBound) / span, 0...1)
    }

    public func along(fraction: Double) -> Double {
        DesktopPetBrain.lerp(lane, fraction)
    }

    /// 跑去哪救回：废纸篓，没有时最右端。
    public var rescueX: Double {
        DesktopPetBrain.clamp(trashX ?? lane.upperBound, lane)
    }
}

public enum DesktopPetTracks {
    /// 脚踩进程序坞一点点。
    public static let footSink: Double = 4

    /// 程序坞上沿那条。
    public static func dock(_ perch: DesktopPetPerch) -> DesktopPetTrack {
        DesktopPetTrack(edge: .bottom, style: .stroll, base: Double(perch.frame.maxY) - footSink,
                        lane: perch.lane, trashX: perch.trashX)
    }

    /// 屏幕某条边或随意放的那一点。`visible` 是去掉菜单栏和程序坞以后的可见区域，
    /// 左右边只在这个范围里待，不挡菜单栏和程序坞；`length` 是小熊猫沿边占多长。
    public static func edge(_ anchor: DesktopPetAnchor, visible: CGRect, length: Double,
                            spot: DesktopPetSpot?) -> DesktopPetTrack? {
        guard visible.width >= 80, visible.height >= 80 else { return nil }
        let inset = length / 2 + 4
        let horizontal = lane(Double(visible.minX) + inset, Double(visible.maxX) - inset)
        // 左右边沿边坐标是脚底高度，身子往上长：上头多留一只小熊猫的高度，不挡菜单栏。
        let sideLane = lane(Double(visible.minY) + 4, Double(visible.maxY) - length * 1.6)
        switch anchor {
        case .dock:
            return nil
        case .bottom:
            return DesktopPetTrack(edge: .bottom, style: .curl, base: Double(visible.minY), lane: horizontal)
        case .top:
            return DesktopPetTrack(edge: .top, style: .hang, base: Double(visible.maxY), lane: horizontal)
        case .left:
            return DesktopPetTrack(edge: .left, style: .side, base: Double(visible.minX), lane: sideLane)
        case .right:
            return DesktopPetTrack(edge: .right, style: .side, base: Double(visible.maxX), lane: sideLane)
        case .free:
            // 随意：一个点。没拖过时放在可见区域中间偏下。
            let spot = spot ?? DesktopPetSpot(along: 0.5, across: 0.15)
            let x = DesktopPetBrain.lerp(horizontal, spot.along)
            let top = max(Double(visible.minY), Double(visible.maxY) - length * 1.4)
            let y = DesktopPetBrain.lerp(Double(visible.minY)...top, spot.across)
            return DesktopPetTrack(edge: .bottom, style: .sit, base: y, lane: x...x)
        }
    }

    private static func lane(_ low: Double, _ high: Double) -> ClosedRange<Double> {
        let mid = (low + high) / 2
        return low <= high ? low...high : mid...mid
    }
}

// MARK: - 上边吊着、左右边探头

/// 上边缘吊着：两只前爪抓住可见区域上沿（菜单栏下沿），爪尖就是图顶，身体和尾巴垂下来，
/// 整只绕爪子做小幅钟摆（吊挂帧自己也在晃，所以摆得比拎着时小）。都按绝对时间算，换动作时晃动接得上。
public enum DesktopPetHang {
    /// 挂点在图高的哪儿（从脚底往上数）：吊挂帧的前爪抓握线就在图片上沿。
    public static let anchor: Double = 1
    /// 拖起来时指针捏的后颈在拎起帧（drag）图高的哪儿。
    public static let scruff: Double = 0.9
    /// 平时 6 帧来回晃的循环每秒 6 帧（一秒晃一个来回）。
    public static let fps: Double = 6
    /// 鼠标靠近、被点时加快到每秒 12 帧，靠近时只快 1 秒再回落。
    public static let alertFPS: Double = 12
    public static let alertKick: TimeInterval = 1
    /// 睡着闭眼呼吸：2 帧，每秒 1 帧。
    public static let sleepFPS: Double = 1
    /// 钟摆：平时 ±2.5°、2.6 秒一个来回。
    public static let amplitude: Double = 2.5
    public static let period: Double = 2.6
    /// 鼠标靠近、被点时晃大一点（欢呼再多 1°）。
    public static let alertAmplitude: Double = 5
    /// 沿边横着挪的时候多晃一点。
    public static let walkAmplitude: Double = 4
    /// 睡着：更慢更小。
    public static let sleepAmplitude: Double = 1
    public static let sleepPeriod: Double = 4.2
    /// 吊着没人理（鼠标没靠近、没点没拖）这么多秒就闭眼打盹（hang-sleep），鼠标一靠近就醒。
    public static let dozeAfter: TimeInterval = 20
    /// 换幅度时 0.6 秒过渡；入睡 3 秒过渡。
    public static let blend: TimeInterval = 0.6
    public static let sleepBlend: TimeInterval = 3

    /// 吊挂循环在 `time` 秒时是第几帧（从 0 数，`imageName` 自己绕回）；`boost` 是加快时多走的帧数。
    public static func frame(time: Double, boost: Double = 0) -> Int {
        Int((time * fps + boost).rounded(.down))
    }

    /// 钟摆角度（度，顺时针为正）：`time` 秒时的正弦摆。
    public static func swing(time: Double, amplitude: Double = amplitude, period: Double = period) -> Double {
        guard period > 0 else { return 0 }
        return amplitude * sin(2 * .pi * time / period)
    }

    /// 从平时的摆慢慢过渡到另一种摆：`elapsed` 是进这个动作多久，`over` 秒内混过去。
    public static func blended(time: Double, elapsed: Double, over: Double, amplitude: Double,
                               period: Double = period) -> Double {
        let k = over > 0 ? min(1, max(0, elapsed / over)) : 1
        let calm = swing(time: time)
        return calm + (swing(time: time, amplitude: amplitude, period: period) - calm) * k
    }

    /// 吊着时计时器每秒几次：晃动要顺，30 次；睡着晃得慢，12 次。
    public static func tickRate(sleeping: Bool) -> Double { sleeping ? 12 : 30 }
}

/// 左右边探头：身子露出多少（图宽的比例），其余藏在屏幕边外。
public enum DesktopPetSide {
    /// 平时趴着露一半。
    public static let rest: Double = 0.5
    /// 坐起来看看。
    public static let sit: Double = 0.65
    /// 探出来。
    public static let peek: Double = 0.75
    /// 被点了一下，探得最多。
    public static let poke: Double = 0.85
    /// 睡着缩回去，只露耳朵和脸。
    public static let sleep: Double = 0.3
    /// 坐着隔多久回去趴着（秒）。
    public static let sitRange: ClosedRange<Double> = 3...6

    public static func clampReveal(_ reveal: Double) -> Double { min(1, max(0, reveal)) }
}

// MARK: - 拖完吸到哪

public enum DesktopPetSnap {
    /// 按住移动超过这么多点才算拖，不然是单击。
    public static let dragThreshold: Double = 4
    /// 吸到边上的过渡多久。
    public static let glideDuration: TimeInterval = 0.28

    /// 松手的位置离哪条边最近。程序坞在这块屏幕底边看得见、松手的位置在程序坞上方
    /// 一段里时吸回程序坞上沿。
    public static func nearest(_ point: CGPoint, visible: CGRect, dock: CGRect?) -> DesktopPetAnchor {
        let distances: [(DesktopPetAnchor, Double)] = [
            (.left, Double(point.x - visible.minX)),
            (.right, Double(visible.maxX - point.x)),
            (.bottom, Double(point.y - visible.minY)),
            (.top, Double(visible.maxY - point.y)),
        ]
        let best = distances.min { $0.1 < $1.1 }?.0 ?? .bottom
        if best == .bottom, let dock, point.x >= dock.minX, point.x <= dock.maxX {
            return .dock
        }
        return best
    }

    /// 松手后记住的位置。`point` 是小熊猫脚底，`track` 是要去的那条边（随意模式算比例）。
    public static func spot(for point: CGPoint, track: DesktopPetTrack, visible: CGRect, display: UInt32?,
                            length: Double) -> DesktopPetSpot {
        if track.style == .sit {
            let inset = length / 2 + 4
            let width = Double(visible.width) - inset * 2
            let along = width > 0 ? (Double(point.x) - Double(visible.minX) - inset) / width : 0.5
            let top = max(Double(visible.minY), Double(visible.maxY) - length * 1.4)
            let height = top - Double(visible.minY)
            let across = height > 0 ? (Double(point.y) - Double(visible.minY)) / height : 0
            return DesktopPetSpot(display: display, along: along, across: across)
        }
        return DesktopPetSpot(display: display, along: track.fraction(of: track.along(of: point)), across: 0.5)
    }

    /// 吸过去的过渡：先快后慢、最后稍微冲过一点再回来。0…1 → 0…约 1.05 → 1。
    public static func glide(_ t: Double) -> Double {
        let t = min(1, max(0, t))
        let c1 = 1.2
        let c3 = c1 + 1
        let u = t - 1
        return 1 + c3 * u * u * u + c1 * u * u
    }

    /// 两个角度之间走近的那一边（-90 到 180 这种跨过去时不绕远）。
    public static func angle(from start: Double, to end: Double, t: Double) -> Double {
        var delta = (end - start).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return start + delta * min(1, max(0, t))
    }
}

// MARK: - 头顶气泡

/// 码头已有的状态，用小熊猫头顶的短气泡说一句。
public enum DesktopPetNews: Equatable, Sendable {
    case focusStarted(minutes: Int)
    case focusFiveLeft
    case focusDone
    case radio(String)
    case plugged(percent: Int)
    case unplugged(percent: Int)
    case charged
    case lowBattery(percent: Int)
    case water

    /// 同一类 30 秒内只说一次。
    public var kind: String {
        switch self {
        case .focusStarted, .focusFiveLeft, .focusDone: "focus"
        case .radio: "radio"
        case .plugged, .charged: "power"
        case .unplugged: "unplug"
        case .lowBattery: "low"
        case .water: "water"
        }
    }

    public var text: String {
        switch self {
        case .focusStarted(let minutes): tr("开始专注 · \(minutes) 分钟")
        case .focusFiveLeft: tr("专注还剩 5 分钟")
        case .focusDone: tr("专注完成，休息一下吧")
        case .radio(let name): tr("正在播放 · \(name)")
        case .plugged(let percent): tr("充电中 · \(percent)%")
        case .unplugged(let percent): tr("拔掉电源了 · \(percent)%")
        case .charged: tr("充满了")
        case .lowBattery(let percent): tr("电量低 · \(percent)%，记得充电")
        case .water: tr("该喝水啦")
        }
    }

    /// 气泡停几秒。
    public var duration: TimeInterval { self == .focusDone ? 5 : 3.5 }
}

/// 电池的一次读数。
public struct DesktopPetPower: Equatable, Sendable {
    public var onPower: Bool
    public var percent: Int

    public init(onPower: Bool, percent: Int) {
        self.onPower = onPower
        self.percent = percent
    }
}

public enum DesktopPetNewsDesk {
    /// 低电量的线：不插电、20% 及以下。
    public static let lowBattery = 20

    /// 专注计时两次读数之间：开始了、还剩 5 分钟、完成了一轮。`then` 是上一次读的时刻。
    public static func focus(from old: TimerState, at then: Date, to new: TimerState, at now: Date) -> DesktopPetNews? {
        if FocusPandaClimb.event(from: old, to: new, now: now) == .cheer { return .focusDone }
        guard new.phase == .focus, let deadline = new.deadline else { return nil }
        if !FocusPandaClimb.isActive(old) || old.phase != .focus {
            let total = new.duration ?? deadline.timeIntervalSince(now)
            return .focusStarted(minutes: max(1, Int((total / 60).rounded())))
        }
        guard let oldDeadline = old.deadline else { return nil }
        let total = new.duration ?? Double(new.minutes * 60)
        let before = oldDeadline.timeIntervalSince(then)
        let left = deadline.timeIntervalSince(now)
        if total >= 600, before > 300, left <= 300, left > 0 { return .focusFiveLeft }
        return nil
    }

    /// 电池两次读数之间：插上电、拔掉电、充满、掉到低电量。第一次读（`old` 是 nil）什么都不说。
    /// 拔电时已经是低电量就只说低电量。
    public static func battery(from old: DesktopPetPower?, to new: DesktopPetPower) -> DesktopPetNews? {
        guard let old else { return nil }
        if new.onPower, !old.onPower { return .plugged(percent: new.percent) }
        if new.onPower, new.percent >= 100, old.percent < 100 { return .charged }
        if !new.onPower, new.percent <= lowBattery, old.onPower || old.percent > lowBattery {
            return .lowBattery(percent: new.percent)
        }
        if !new.onPower, old.onPower { return .unplugged(percent: new.percent) }
        return nil
    }

    /// 收音机：开始播放或者换了台。
    public static func radio(wasPlaying: Bool, oldStation: String?, playing: Bool, station: String?) -> DesktopPetNews? {
        guard playing, let station, !station.isEmpty else { return nil }
        if !wasPlaying || oldStation != station { return .radio(station) }
        return nil
    }
}

/// 同一类气泡 30 秒内只说一次（插电这一类和刘海的插电动画同样是 30 秒）。
public struct DesktopPetBubbleGate: Equatable, Sendable {
    public static let window: TimeInterval = 30
    public private(set) var last: [String: Date] = [:]

    public init() {}

    public mutating func allow(_ kind: String, now: Date) -> Bool {
        if let previous = last[kind], now >= previous, now.timeIntervalSince(previous) < Self.window { return false }
        last[kind] = now
        return true
    }
}

// MARK: - 快捷条

/// 小熊猫旁边浮出来的胶囊快捷条：四个码头已有的动作。
public enum DesktopPetQuickAction: String, CaseIterable, Sendable {
    case todo, focus, radio, expand

    /// 每个按钮的点击区。
    public static let buttonSize = CGSize(width: 44, height: 40)
    public static let padding: Double = 4
    /// 指针离开小熊猫和快捷条多久收起。
    public static let lingerAfterLeave: TimeInterval = 2.5
    /// 单击、快捷键唤出时至少显示多久。
    public static let shownAfterClick: TimeInterval = 5

    public static var barSize: CGSize {
        CGSize(width: Double(buttonSize.width) * Double(allCases.count) + padding * 2,
               height: Double(buttonSize.height) + padding * 2)
    }

    /// 快捷条里某一点落在哪个按钮上。
    public static func at(x: Double, width: Double) -> DesktopPetQuickAction? {
        let inner = x - padding
        let span = width - padding * 2
        guard inner >= 0, inner < span, span > 0 else { return nil }
        let index = Int(inner / (span / Double(allCases.count)))
        return allCases.indices.contains(index) ? allCases[index] : nil
    }

    public func symbol(focusRunning: Bool, radioPlaying: Bool) -> String {
        switch self {
        case .todo: "square.and.pencil"
        case .focus: focusRunning ? "pause.fill" : "timer"
        case .radio: radioPlaying ? "pause.circle" : "radio"
        case .expand: "chevron.up.circle"
        }
    }

    public func title(focusRunning: Bool, radioPlaying: Bool) -> String {
        switch self {
        case .todo: tr("新建快速待办")
        case .focus: focusRunning ? tr("暂停专注") : tr("开始专注")
        case .radio: radioPlaying ? tr("暂停收音机") : tr("播放收音机")
        case .expand: tr("展开码头")
        }
    }

    /// 专注计时开始 / 暂停，和专注计时卡片上的按钮一样：暂停时记下还剩多少，
    /// 继续从剩下的接着走；已经到 0 的重新开始。
    public static func toggledFocus(_ state: TimerState, now: Date) -> TimerState {
        var state = state
        let total = max(1, state.duration ?? Double(state.minutes * 60))
        let left: TimeInterval
        if let paused = state.paused {
            left = max(0, min(paused, total))
        } else if let deadline = state.deadline {
            left = max(0, min(deadline.timeIntervalSince(now), total))
        } else {
            left = total
        }
        if left <= 0 {
            state.duration = total
            state.deadline = now.addingTimeInterval(total)
            state.paused = nil
        } else if state.deadline == nil {
            state.duration = total
            state.deadline = now.addingTimeInterval(left)
            state.paused = nil
        } else {
            state.paused = left
            state.deadline = nil
        }
        return state
    }

    /// 专注计时是不是正在走（不算暂停）。
    public static func focusRunning(_ state: TimerState) -> Bool {
        state.deadline != nil && state.paused == nil
    }
}
