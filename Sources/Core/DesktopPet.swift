import Foundation

// 桌面宠物：小熊猫贴在程序坞上沿散步，或者蜷在屏幕某条边上，也可以拖到任意位置。
//
// 这里只有纯逻辑：设置、动作帧、走路发呆睡觉蜷着的状态机、废纸篓救回挑哪几项、
// 程序坞上沿和屏幕边缘的可待范围（`DesktopPetTrack`，见 DesktopPetEdge.swift）。
// 窗口、显示刷新、拖动、读程序坞位置和放回原处在 App 和 Services 里，
// 见 `DesktopPetController`。

// MARK: - 设置

/// 设置 ▸ 小组件 ▸ 桌面宠物。总开关和救回默认关。
public struct DesktopPetSettings: Codable, Hashable, Sendable {
    /// 总开关。
    public var enabled: Bool = false
    /// 废纸篓救回：刚拖进废纸篓的文件，小熊猫跑过去叼回来放回原处。单独默认关，
    /// 第一次打开时先说明要的权限。
    public var trashRescue: Bool = false
    /// 停在哪：程序坞上沿（默认，散步）、屏幕四条边（蜷着）或随意（拖到哪停哪）。
    public var anchor: DesktopPetAnchor = .dock
    /// 大小。
    public var size: DesktopPetSize = .medium
    /// 头顶气泡：专注、收音机、电池、喝水这些状态用小气泡说一句。默认开。
    public var bubbles: Bool = true
    /// 唤出小熊猫并显示快捷条的全局快捷键，默认不设。
    public var hotKey: KeyCombo?
    /// 拖过以后记住的位置：哪块屏幕、沿边的哪儿。没拖过是 nil。
    public var spot: DesktopPetSpot?

    public init(enabled: Bool = false, trashRescue: Bool = false, anchor: DesktopPetAnchor = .dock,
                size: DesktopPetSize = .medium, bubbles: Bool = true, hotKey: KeyCombo? = nil,
                spot: DesktopPetSpot? = nil) {
        self.enabled = enabled
        self.trashRescue = trashRescue
        self.anchor = anchor
        self.size = size
        self.bubbles = bubbles
        self.hotKey = hotKey
        self.spot = spot
    }

    /// 救回真正在不在工作：总开关和子开关都开着。
    public var rescueActive: Bool { enabled && trashRescue }

    private enum CodingKeys: String, CodingKey { case enabled, trashRescue, anchor, size, bubbles, hotKey, spot }

    /// 宽松解码：老状态文件没有这一组或缺新加的键、以后多了认不出的键或值，都照常读。
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? false
        trashRescue = (try? c.decodeIfPresent(Bool.self, forKey: .trashRescue)) ?? false
        anchor = ((try? c.decodeIfPresent(String.self, forKey: .anchor)) ?? nil)
            .flatMap(DesktopPetAnchor.init(rawValue:)) ?? .dock
        size = ((try? c.decodeIfPresent(String.self, forKey: .size)) ?? nil)
            .flatMap(DesktopPetSize.init(rawValue:)) ?? .medium
        bubbles = (try? c.decodeIfPresent(Bool.self, forKey: .bubbles)) ?? true
        hotKey = (try? c.decodeIfPresent(KeyCombo.self, forKey: .hotKey)) ?? nil
        spot = (try? c.decodeIfPresent(DesktopPetSpot.self, forKey: .spot)) ?? nil
    }
}

/// 大小：小、中、大，按动作帧原本的大小缩放。
public enum DesktopPetSize: String, Codable, CaseIterable, Sendable {
    case small, medium, large

    public var scale: Double {
        switch self {
        case .small: 0.8
        case .medium: 1
        case .large: 1.25
        }
    }

    public var title: String {
        switch self {
        case .small: tr("小")
        case .medium: tr("中")
        case .large: tr("大")
        }
    }
}

// MARK: - 动作帧

/// 一套动作帧：Resources/Pet/sprites/pet-sprite-<动作>-<1…n>.png，同一只小熊猫、
/// 同一个比例（@2x，走路那张约 105px 高），都朝右；往左时整张左右翻过来。
public enum DesktopPetStrip: String, CaseIterable, Sendable {
    case walk, run, jump, carry, sleep

    public var frameCount: Int {
        switch self {
        case .walk: return 32
        case .carry: return 4
        default: return 3
        }
    }

    /// 第几帧（从 0 数，超出时绕回）对应的图片名，不带扩展名。
    public func imageName(_ frame: Int) -> String {
        let count = frameCount
        let index = ((frame % count) + count) % count
        return "pet-sprite-\(rawValue)-\(index + 1)"
    }
}

/// 某一刻画哪张图、离脚下那条边多远、怎么压扁拉长、要不要翻过来。
/// 都在小熊猫自己的坐标里：“上”是离开那条边的方向，贴在左右边时由窗口转 90°。
public struct DesktopPetPose: Equatable, Sendable {
    /// 图片名（不带扩展名）：动作帧，或 Resources/Pet 里现成的 pet-panda-idle / rest / cheer / hungry。
    public var image: String
    /// 脚离那条边多高（跳起来、走路一颠一颠时大于 0），点。
    public var lift: Double
    /// 朝“左”：图左右翻过来。贴边时的“左”是沿边往回的方向，见 `DesktopPetEdge`。
    public var facingLeft: Bool
    /// 显示高度，点。动作帧按图片自己的大小（像素 / 2），静态图给一个固定高度。
    public var height: Double?
    /// 横向、纵向缩放（转身、落地压扁回弹、伸懒腰），1 是原样。以脚底中点为准。
    public var scaleX: Double
    public var scaleY: Double
    /// 被拖起来时左右晃的角度（度，顺时针），平时 0。
    public var wobble: Double
    /// 睡着时头顶的 Zzz：0 不显示，1…3 是几个 z。
    public var zzz: Int

    public init(image: String, lift: Double = 0, facingLeft: Bool = false, height: Double? = nil,
                scaleX: Double = 1, scaleY: Double = 1, wobble: Double = 0, zzz: Int = 0) {
        self.image = image
        self.lift = lift
        self.facingLeft = facingLeft
        self.height = height
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.wobble = wobble
        self.zzz = zzz
    }
}

// MARK: - 状态机

/// 小熊猫在做什么。时间都是绝对时刻，所以帧号和位置都能从“现在”算出来。
public enum DesktopPetActivity: Equatable, Sendable {
    /// 停下发呆（坐着），到点再走。
    case idle(until: Date)
    /// 沿着那条边走到某处（程序坞上散步，或者贴边时挪几步）。
    case walk(to: Double)
    /// 睡觉（先打哈欠，再趴下，再团成一团）。
    case sleep(since: Date)
    /// 跳一下（被点、插上电源），之后回去歇着。
    case jump(since: Date)
    /// 专注计时进行中：坐着陪，不乱跑。
    case sit
    /// 欢呼（专注完成一轮、救回了文件）。
    case cheer(until: Date)
    /// 废纸篓救回的一整段。
    case rescue(DesktopPetRescueStep)
    /// 贴在边上趴着歇。
    case curl(until: Date)
    /// 从边上探出头来（坐起来看看），到点再趴回去。
    case peek(until: Date)
    /// 伸个懒腰。
    case stretch(since: Date)
    /// 打个哈欠。
    case yawn(since: Date)
    /// 被鼠标拖着：四脚乱蹬。
    case dragged(since: Date)
    /// 松手落下：压扁再弹回来。
    case land(since: Date)
    /// 电量低：蔫蔫的。
    case droop(until: Date)
}

/// 救回的几步：跑到废纸篓、叼起来、叼着跑回原来的地方、放下。
public enum DesktopPetRescueStep: Equatable, Sendable {
    case toTrash(trashX: Double, homeX: Double)
    case pickUp(since: Date, homeX: Double)
    case back(homeX: Double)
    /// 到家了，等放回原处的结果。
    case arrived(since: Date)
}

/// 平时是散步、蜷着还是坐着：程序坞上散步，屏幕边缘蜷着，随意放的地方坐着。
public enum DesktopPetStyle: Equatable, Sendable {
    case stroll, curl, sit
}

public struct DesktopPetState: Equatable, Sendable {
    /// 小熊猫在那条边上的位置（屏幕坐标，点）：底边和上边是横坐标，左右边是纵坐标。
    public var x: Double
    /// 朝沿边坐标变小的方向。
    public var facingLeft: Bool
    public var activity: DesktopPetActivity
    /// 这个动作从什么时候开始，算帧号用。
    public var since: Date
    /// 上一次掉头的时刻，转身的短过渡用。
    public var turnedAt: Date?

    public init(x: Double, facingLeft: Bool = false, activity: DesktopPetActivity, since: Date,
                turnedAt: Date? = nil) {
        self.x = x
        self.facingLeft = facingLeft
        self.activity = activity
        self.since = since
        self.turnedAt = turnedAt
    }
}

/// 散步、发呆、睡觉、跳、坐、欢呼、蜷着、探头、伸懒腰、拖动、救回的规则。
/// 所有随机都从外面传进来，测试可以定住。
public enum DesktopPetBrain {
    /// 动作帧率：每秒 12 帧。位置和缩放另外按显示刷新（60 帧）算，见 `isMoving`。
    public static let fps: Double = 12
    /// 静止时（坐着、趴着）的计时器：每秒 10 次，够看见眨眼。
    public static let restingFPS: Double = 10
    /// 睡着以后计时器放慢到每秒 2 次。
    public static let sleepingFPS: Double = 2
    /// 用户多久没碰键盘鼠标就睡觉。
    public static let sleepAfter: TimeInterval = 180
    /// 散步、跑、叼着跑的速度（点 / 秒）。散步配四脚走路帧：每秒约 39 张、一个循环约 0.8 秒。
    public static let walkSpeed: Double = 18
    public static let runSpeed: Double = 190
    public static let carrySpeed: Double = 120
    /// 跑去废纸篓最多花几秒：程序坞很长时跑快一点。
    public static let maxRunTime: TimeInterval = 2.6
    /// 跳一下多久、多高。
    public static let jumpDuration: TimeInterval = 0.75
    public static let jumpHeight: Double = 26
    /// 叼起来那几帧多久。
    public static let pickUpDuration: TimeInterval = 0.9
    /// 欢呼多久。
    public static let cheerDuration: TimeInterval = 2.5
    /// 发呆几秒（下限、上限）。
    public static let idleRange: ClosedRange<Double> = 3...9
    /// 一次散步最远走多远。
    public static let strollRange: ClosedRange<Double> = 40...220
    /// 贴边时一次挪几步。
    public static let shuffleRange: ClosedRange<Double> = 16...56
    /// 贴边趴着歇几秒。
    public static let curlRange: ClosedRange<Double> = 7...16
    /// 探头看一眼多久；鼠标在旁边时一直探着。
    public static let peekDuration: TimeInterval = 2.4
    public static let stretchDuration: TimeInterval = 1.6
    public static let yawnDuration: TimeInterval = 1.4
    /// 落地压扁回弹多久。
    public static let landDuration: TimeInterval = 0.42
    /// 转身的短过渡多久。
    public static let turnDuration: TimeInterval = 0.16
    /// 电量低时蔫多久。
    public static let droopDuration: TimeInterval = 8
    /// 静态图（发呆、坐、欢呼）显示多高。
    public static let sittingHeight: Double = 62
    /// 四脚走路 32 帧一个循环，身体起伏画在帧里。帧跟着走过的路换，不跟时间换：
    /// 着地那只脚在图里每帧往后挪约 0.46 点（原图 4.8 像素 × 缩放），换帧距离和它一样，脚就钉在地上不打滑。
    /// 一个循环约 14.7 点。大小设置放大时步子跟着放大。
    public static let walkStep: Double = 0.46

    /// 走到横坐标 x 时该放第几张走路帧（从 0 数）；`scale` 是设置里的大小。
    public static func walkFrame(x: Double, scale: Double = 1) -> Int {
        let step = Int((abs(x) / (walkStep * max(scale, 0.1))).rounded(.down))
        return step % DesktopPetStrip.walk.frameCount
    }

    /// 刚出现：在可走范围中间偏左一点发呆。
    public static func initial(lane: ClosedRange<Double>, now: Date) -> DesktopPetState {
        let x = lane.lowerBound + (lane.upperBound - lane.lowerBound) * 0.35
        return DesktopPetState(x: x, activity: .idle(until: now.addingTimeInterval(4)), since: now)
    }

    /// 在某个位置出现，按平时的样子歇着（拖过以后记住的位置、换了停靠方式）。
    public static func placed(at x: Double, style: DesktopPetStyle, now: Date) -> DesktopPetState {
        DesktopPetState(x: x, activity: rest(style, now: now, random: { 0.5 }), since: now)
    }

    /// 往前走一步。`dt` 是距上一步的秒数；`userIdle` 是用户多久没操作；
    /// `focusing` 是专注计时正在走（而且能用专注陪伴）；`style` 是平时散步、蜷着还是坐着；
    /// `attention` 是鼠标靠近时它在沿边坐标上的位置（离远了是 nil）；
    /// `random` 是 0…1 的随机数来源。
    public static func step(_ state: DesktopPetState, dt: TimeInterval, now: Date,
                            lane: ClosedRange<Double>, userIdle: TimeInterval, focusing: Bool,
                            style: DesktopPetStyle = .stroll, attention: Double? = nil,
                            random: () -> Double) -> DesktopPetState {
        var next = state
        next.x = clamp(state.x, lane)
        let dt = max(0, min(dt, 1))

        // 救回、跳、欢呼、拖着、落地正在演的，演完再说；其余的按专注和睡觉打断。
        switch state.activity {
        case .rescue(let step):
            return rescueStep(next, step: step, dt: dt, now: now, lane: lane)
        case .dragged:
            return next
        case .jump(let since):
            if now.timeIntervalSince(since) < jumpDuration { return next }
            return settle(next, now: now, focusing: focusing, style: style, random: random)
        case .land(let since):
            if now.timeIntervalSince(since) < landDuration { return next }
            return settle(next, now: now, focusing: focusing, style: style, random: random)
        case .cheer(let until):
            if now < until { return next }
            return settle(next, now: now, focusing: focusing, style: style, random: random)
        case .droop(let until):
            if now < until { return next }
            return settle(next, now: now, focusing: focusing, style: style, random: random)
        default:
            break
        }

        if focusing {
            if next.activity != .sit { next.activity = .sit; next.since = now }
            return next
        }
        if userIdle >= sleepAfter {
            if case .sleep = next.activity { return next }
            next.activity = .sleep(since: now)
            next.since = now
            return next
        }

        switch next.activity {
        case .sit, .sleep:
            // 专注结束、或用户回来了：醒过来歇一会儿。
            next.activity = rest(style, now: now, random: random)
            next.since = now
        case .idle(let until):
            if let attention { face(&next, toward: attention, now: now) }
            guard now >= until else { return next }
            if attention != nil {
                // 鼠标在旁边：多看一会儿，不走开。
                next.activity = .idle(until: now.addingTimeInterval(idleRange.lowerBound))
                next.since = now
                return next
            }
            next = afterIdle(next, now: now, lane: lane, style: style, random: random)
        case .curl(let until):
            if let attention {
                face(&next, toward: attention, now: now)
                next.activity = .peek(until: now.addingTimeInterval(1.5))
                next.since = now
                return next
            }
            guard now >= until else { return next }
            next = afterCurl(next, now: now, lane: lane, random: random)
        case .peek(let until):
            if let attention {
                face(&next, toward: attention, now: now)
                if until < now.addingTimeInterval(1.5) { next.activity = .peek(until: now.addingTimeInterval(1.5)) }
                return next
            }
            guard now >= until else { return next }
            next.activity = rest(style, now: now, random: random)
            next.since = now
        case .stretch(let since):
            guard now.timeIntervalSince(since) >= stretchDuration else { return next }
            next.activity = rest(style, now: now, random: random)
            next.since = now
        case .yawn(let since):
            guard now.timeIntervalSince(since) >= yawnDuration else { return next }
            next.activity = rest(style, now: now, random: random)
            next.since = now
        case .walk(let target):
            let goal = clamp(target, lane)
            let moved = move(next.x, toward: goal, by: walkSpeed * dt)
            next.x = moved
            turn(&next, left: goal < state.x, now: now)
            if moved == goal {
                next.activity = rest(style, now: now, random: random)
                next.since = now
            }
        default:
            break
        }
        return next
    }

    /// 被点了一下：跳起来（睡着的也醒过来跳）。救回途中、拖着时不理会。
    public static func poked(_ state: DesktopPetState, now: Date) -> DesktopPetState {
        switch state.activity {
        case .rescue, .jump, .dragged: return state
        default: break
        }
        var next = state
        next.activity = .jump(since: now)
        next.since = now
        return next
    }

    /// 插上电源：转头朝刘海那边（`toward` 是刘海在沿边坐标上的位置），开心跳一下。
    public static func plugged(_ state: DesktopPetState, toward: Double?, now: Date) -> DesktopPetState {
        var next = poked(state, now: now)
        if let toward, next.activity == .jump(since: now) { face(&next, toward: toward, now: now) }
        return next
    }

    /// 电量低：蔫一会儿。救回、拖着、跳着时不打断。
    public static func droop(_ state: DesktopPetState, now: Date) -> DesktopPetState {
        switch state.activity {
        case .rescue, .dragged, .jump: return state
        default: break
        }
        var next = state
        next.activity = .droop(until: now.addingTimeInterval(droopDuration))
        next.since = now
        return next
    }

    /// 欢呼（专注完成一轮）。救回途中、拖着时不打断。
    public static func cheer(_ state: DesktopPetState, now: Date) -> DesktopPetState {
        switch state.activity {
        case .rescue, .dragged: return state
        default: break
        }
        var next = state
        next.activity = .cheer(until: now.addingTimeInterval(cheerDuration))
        next.since = now
        return next
    }

    /// 被鼠标抓起来。救回途中也可以抓（救回就此放弃，由外面另外处理）。
    public static func grabbed(_ state: DesktopPetState, now: Date) -> DesktopPetState {
        var next = state
        next.activity = .dragged(since: now)
        next.since = now
        return next
    }

    /// 拖着时朝拖的方向：横着往左拖就朝左。
    public static func dragging(_ state: DesktopPetState, dx: Double, now: Date) -> DesktopPetState {
        guard case .dragged = state.activity, abs(dx) >= 1.5 else { return state }
        var next = state
        turn(&next, left: dx < 0, now: now)
        return next
    }

    /// 落到新位置：压扁回弹一下，之后按平时的样子歇着。
    public static func landed(_ state: DesktopPetState, at x: Double, now: Date) -> DesktopPetState {
        var next = state
        next.x = x
        next.activity = .land(since: now)
        next.since = now
        return next
    }

    /// 开始救回：从现在的位置跑去废纸篓。
    public static func startRescue(_ state: DesktopPetState, trashX: Double, lane: ClosedRange<Double>,
                                   now: Date) -> DesktopPetState {
        var next = state
        let trash = clamp(trashX, lane)
        next.activity = .rescue(.toTrash(trashX: trash, homeX: clamp(state.x, lane)))
        next.facingLeft = trash < state.x
        next.since = now
        return next
    }

    /// 放回原处有了结果：成功就欢呼，失败就回去发呆（气泡由外面另外弹）。
    public static func finishRescue(_ state: DesktopPetState, succeeded: Bool, now: Date) -> DesktopPetState {
        var next = state
        next.facingLeft = false
        next.since = now
        next.activity = succeeded
            ? .cheer(until: now.addingTimeInterval(cheerDuration))
            : .idle(until: now.addingTimeInterval(idleRange.upperBound))
        return next
    }

    /// 救回走到了“到家”这一步、正等着放回原处。
    public static func awaitingPutBack(_ state: DesktopPetState) -> Bool {
        if case .rescue(.arrived) = state.activity { return true }
        return false
    }

    /// 位置、缩放这一刻还在变：要按显示刷新（60 帧）跟着画。静止、睡觉时是 false，
    /// 只用慢计时器换帧（`tickRate`）。
    public static func isMoving(_ state: DesktopPetState, now: Date) -> Bool {
        if let turnedAt = state.turnedAt, now.timeIntervalSince(turnedAt) < turnDuration { return true }
        switch state.activity {
        case .walk, .jump, .land, .dragged: return true
        case .rescue(let step):
            switch step {
            case .toTrash, .back: return true
            case .pickUp, .arrived: return false
            }
        case .stretch(let since): return now.timeIntervalSince(since) < stretchDuration
        default: return false
        }
    }

    /// 这一刻画什么。
    public static func pose(_ state: DesktopPetState, now: Date, scale: Double = 1) -> DesktopPetPose {
        let elapsed = max(0, now.timeIntervalSince(state.since))
        let frame = Int(elapsed * fps)
        let left = state.facingLeft
        var pose: DesktopPetPose
        switch state.activity {
        case .idle, .sit, .peek:
            pose = DesktopPetPose(image: blinking(now: now) ? "pet-panda-rest" : "pet-panda-idle",
                                  facingLeft: left, height: sittingHeight)
        case .cheer:
            pose = DesktopPetPose(image: "pet-panda-cheer", height: sittingHeight + 4)
        case .droop:
            pose = DesktopPetPose(image: "pet-panda-hungry", height: sittingHeight - 2)
        case .curl:
            pose = DesktopPetPose(image: DesktopPetStrip.sleep.imageName(1), facingLeft: left)
        case .walk:
            pose = DesktopPetPose(image: DesktopPetStrip.walk.imageName(walkFrame(x: state.x, scale: scale)),
                                  facingLeft: left)
        case .jump:
            let t = min(1, elapsed / jumpDuration)
            let index = t < 0.2 ? 0 : (t < 0.8 ? 1 : 2)
            pose = DesktopPetPose(image: DesktopPetStrip.jump.imageName(index),
                                  lift: jumpLift(t), facingLeft: left)
            // 起跳前蹲一下、落地压一下。
            let squash = t < 0.18 ? sin(t / 0.18 * .pi) : (t > 0.86 ? sin((t - 0.86) / 0.14 * .pi) : 0)
            pose.scaleX = 1 + 0.08 * squash
            pose.scaleY = 1 - 0.1 * squash
        case .stretch(let since):
            let t = min(1, now.timeIntervalSince(since) / stretchDuration)
            if t < 0.45 {
                // 前爪往前一伸、屁股撅起来：跳之前蹲下那一帧。
                pose = DesktopPetPose(image: DesktopPetStrip.jump.imageName(0), facingLeft: left)
                pose.scaleX = 1 + 0.06 * sin(t / 0.45 * .pi)
            } else {
                // 坐起来往上一抻。
                pose = DesktopPetPose(image: "pet-panda-idle", facingLeft: left, height: sittingHeight)
                pose.scaleY = 1 + 0.07 * sin((t - 0.45) / 0.55 * .pi)
                pose.scaleX = 1 - 0.03 * sin((t - 0.45) / 0.55 * .pi)
            }
        case .yawn:
            pose = DesktopPetPose(image: DesktopPetStrip.sleep.imageName(0), facingLeft: left,
                                  height: sittingHeight + 8)
        case .sleep(let since):
            let asleep = now.timeIntervalSince(since)
            let index = asleep < 1.6 ? 0 : (asleep < 4 ? 1 : 2)
            pose = DesktopPetPose(image: DesktopPetStrip.sleep.imageName(index), facingLeft: left)
            if index == 2 { pose.zzz = 1 + Int(asleep * 1.5) % 3 }
        case .dragged(let since):
            // 四脚乱蹬：跳起来那两帧来回换，身子左右晃。
            let t = now.timeIntervalSince(since)
            pose = DesktopPetPose(image: DesktopPetStrip.jump.imageName(1 + Int(t * 10) % 2), facingLeft: left)
            pose.wobble = 7 * sin(t * 13)
        case .land(let since):
            let t = min(1, now.timeIntervalSince(since) / landDuration)
            pose = DesktopPetPose(image: "pet-panda-idle", facingLeft: left, height: sittingHeight)
            let squash = landSquash(t)
            pose.scaleX = 1 + 0.14 * squash
            pose.scaleY = 1 - 0.2 * squash
        case .rescue(let step):
            switch step {
            case .toTrash:
                pose = DesktopPetPose(image: DesktopPetStrip.run.imageName(frame), facingLeft: left)
            case .pickUp(let since, _):
                let t = min(1, now.timeIntervalSince(since) / pickUpDuration)
                let index = t < 0.4 ? 0 : (t < 0.75 ? 1 : 2)
                pose = DesktopPetPose(image: DesktopPetStrip.carry.imageName(index), facingLeft: left)
            case .back:
                // 叼着跑：第 4 帧，按跑过的路一颠一颠。
                pose = DesktopPetPose(image: DesktopPetStrip.carry.imageName(3),
                                      lift: 3 * abs(sin(state.x * .pi / 18)), facingLeft: left)
            case .arrived:
                pose = DesktopPetPose(image: DesktopPetStrip.carry.imageName(2))
            }
        }
        // 刚掉头：横着从窄到宽弹开，像转了个身。
        if let turnedAt = state.turnedAt {
            let t = now.timeIntervalSince(turnedAt) / turnDuration
            if t >= 0, t < 1 { pose.scaleX *= 0.3 + 0.7 * (1 - (1 - t) * (1 - t)) }
        }
        return pose
    }

    /// 不在动时慢计时器每秒几次：睡着 2 次，其余 10 次（够看见眨眼）。
    public static func tickRate(_ state: DesktopPetState) -> Double {
        if case .sleep = state.activity { return sleepingFPS }
        return restingFPS
    }

    /// 眨眼：每 4.3 秒闭一下眼，约 0.18 秒。按绝对时间算，不用存状态。
    public static func blinking(now: Date) -> Bool {
        let t = now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 4.3)
        return t >= 0 && t < 0.18
    }

    /// 落地压扁回弹：0 时压得最扁（1），中途回弹拉长一点（负数），最后回到 0。
    public static func landSquash(_ t: Double) -> Double {
        let t = min(1, max(0, t))
        return (1 - t) * (1 - t) * cos(t * 3 * .pi)
    }

    // MARK: 内部

    static func jumpLift(_ t: Double) -> Double {
        let t = min(1, max(0, t))
        return 4 * jumpHeight * t * (1 - t)
    }

    /// 平时歇着的样子：散步、坐着的是发呆，贴边的是趴着。
    static func rest(_ style: DesktopPetStyle, now: Date, random: () -> Double) -> DesktopPetActivity {
        switch style {
        case .stroll, .sit: .idle(until: now.addingTimeInterval(lerp(idleRange, random())))
        case .curl: .curl(until: now.addingTimeInterval(lerp(curlRange, random())))
        }
    }

    /// 发呆完：散步的去走一段（偶尔打个哈欠），坐着的打哈欠、伸懒腰或者换个朝向。
    private static func afterIdle(_ state: DesktopPetState, now: Date, lane: ClosedRange<Double>,
                                  style: DesktopPetStyle, random: () -> Double) -> DesktopPetState {
        var next = state
        next.since = now
        let roll = random()
        if roll < 0.12 {
            next.activity = .yawn(since: now)
            return next
        }
        switch style {
        case .stroll:
            let target = strollTarget(from: next.x, lane: lane, random: random)
            if abs(target - next.x) < 4 {
                next.activity = .idle(until: now.addingTimeInterval(lerp(idleRange, random())))
            } else {
                next.activity = .walk(to: target)
                turn(&next, left: target < next.x, now: now)
            }
        case .sit:
            if roll < 0.24 {
                next.activity = .stretch(since: now)
            } else {
                if roll > 0.7 { turn(&next, left: !next.facingLeft, now: now) }
                next.activity = .idle(until: now.addingTimeInterval(lerp(idleRange, random())))
            }
        case .curl:
            next.activity = .curl(until: now.addingTimeInterval(lerp(curlRange, random())))
        }
        return next
    }

    /// 趴够了：探头看一眼、伸个懒腰、沿边挪几步，或者打个哈欠。
    private static func afterCurl(_ state: DesktopPetState, now: Date, lane: ClosedRange<Double>,
                                  random: () -> Double) -> DesktopPetState {
        var next = state
        next.since = now
        let roll = random()
        if roll < 0.32 {
            next.activity = .peek(until: now.addingTimeInterval(peekDuration))
        } else if roll < 0.52 {
            next.activity = .stretch(since: now)
        } else if roll < 0.8 {
            let distance = lerp(shuffleRange, random())
            let goLeft = random() < 0.5
            var target = goLeft ? next.x - distance : next.x + distance
            if target < lane.lowerBound || target > lane.upperBound {
                target = goLeft ? next.x + distance : next.x - distance
            }
            target = clamp(target, lane)
            if abs(target - next.x) < 4 {
                next.activity = .peek(until: now.addingTimeInterval(peekDuration))
            } else {
                next.activity = .walk(to: target)
                turn(&next, left: target < next.x, now: now)
            }
        } else {
            next.activity = .yawn(since: now)
        }
        return next
    }

    /// 朝向某处（鼠标、刘海）。差得很近时不动，免得来回抖。
    static func face(_ state: inout DesktopPetState, toward target: Double, now: Date) {
        guard abs(target - state.x) > 6 else { return }
        turn(&state, left: target < state.x, now: now)
    }

    /// 掉头：朝向真的变了才记下掉头的时刻。
    static func turn(_ state: inout DesktopPetState, left: Bool, now: Date) {
        guard state.facingLeft != left else { return }
        state.facingLeft = left
        state.turnedAt = now
    }

    private static func settle(_ state: DesktopPetState, now: Date, focusing: Bool, style: DesktopPetStyle,
                               random: () -> Double) -> DesktopPetState {
        var next = state
        next.since = now
        next.activity = focusing ? .sit : rest(style, now: now, random: random)
        return next
    }

    private static func rescueStep(_ state: DesktopPetState, step: DesktopPetRescueStep, dt: TimeInterval,
                                   now: Date, lane: ClosedRange<Double>) -> DesktopPetState {
        var next = state
        switch step {
        case .toTrash(let trashX, let homeX):
            let distance = abs(trashX - homeX)
            let speed = max(runSpeed, distance / maxRunTime)
            next.x = move(state.x, toward: trashX, by: speed * dt)
            next.facingLeft = trashX < state.x
            if next.x == trashX {
                next.activity = .rescue(.pickUp(since: now, homeX: homeX))
                next.since = now
            }
        case .pickUp(let since, let homeX):
            if now.timeIntervalSince(since) >= pickUpDuration {
                next.activity = .rescue(.back(homeX: clamp(homeX, lane)))
                next.facingLeft = homeX < state.x
                next.since = now
            }
        case .back(let homeX):
            next.x = move(state.x, toward: homeX, by: carrySpeed * dt)
            next.facingLeft = homeX < state.x
            if next.x == homeX {
                next.activity = .rescue(.arrived(since: now))
                next.since = now
            }
        case .arrived:
            break
        }
        return next
    }

    static func strollTarget(from x: Double, lane: ClosedRange<Double>, random: () -> Double) -> Double {
        let distance = lerp(strollRange, random())
        let goLeft = random() < 0.5
        var target = goLeft ? x - distance : x + distance
        // 走不出去就掉头。
        if target < lane.lowerBound || target > lane.upperBound {
            target = goLeft ? x + distance : x - distance
        }
        return clamp(target, lane)
    }

    static func move(_ x: Double, toward target: Double, by step: Double) -> Double {
        if abs(target - x) <= step { return target }
        return x + (target > x ? step : -step)
    }

    static func clamp(_ x: Double, _ lane: ClosedRange<Double>) -> Double {
        min(lane.upperBound, max(lane.lowerBound, x))
    }

    static func lerp(_ range: ClosedRange<Double>, _ t: Double) -> Double {
        range.lowerBound + (range.upperBound - range.lowerBound) * min(1, max(0, t))
    }
}

// MARK: - 站在哪

/// 小熊猫站的那条程序坞：屏幕坐标（左下原点）里的矩形，废纸篓在哪。
public struct DesktopPetPerch: Equatable, Sendable {
    public var frame: CGRect
    /// 废纸篓图标中心的横坐标；拿不到时是 nil，用程序坞最右端。
    public var trashX: Double?

    public init(frame: CGRect, trashX: Double? = nil) {
        self.frame = frame
        self.trashX = trashX
    }

    /// 小熊猫中心能走到的范围：两头各留半只小熊猫。
    public var lane: ClosedRange<Double> {
        let inset: Double = min(36, Double(frame.width) / 4)
        let low = Double(frame.minX) + inset
        let high = max(low, Double(frame.maxX) - inset)
        return low...high
    }

    /// 跑去哪：废纸篓，没有时程序坞最右端。
    public var rescueX: Double {
        DesktopPetBrain.clamp(trashX ?? lane.upperBound, lane)
    }
}

/// 跟系统程序坞还是码头扩展栏，以及什么时候不显示。
public enum DesktopPetPlacement {
    /// 系统程序坞的读数。
    public struct SystemDock: Equatable, Sendable {
        public var frame: CGRect?
        public var trashX: Double?
        public var atBottom: Bool
        public var autoHide: Bool

        public init(frame: CGRect?, trashX: Double? = nil, atBottom: Bool, autoHide: Bool) {
            self.frame = frame
            self.trashX = trashX
            self.atBottom = atBottom
            self.autoHide = autoHide
        }
    }

    /// 码头扩展栏的读数。
    public struct Shelf: Equatable, Sendable {
        public var frame: CGRect?
        public var atBottom: Bool
        /// 自动隐藏滑到屏幕外。
        public var tucked: Bool

        public init(frame: CGRect?, atBottom: Bool, tucked: Bool) {
            self.frame = frame
            self.atBottom = atBottom
            self.tucked = tucked
        }
    }

    /// 站在哪条程序坞上，nil 是这会儿不显示：全屏 App 在前、程序坞自动隐藏、
    /// 两条都不在底边。系统程序坞在底边、看得见时跟它；否则跟在底边、没收起来的扩展栏。
    public static func perch(system: SystemDock, shelf: Shelf, fullScreen: Bool) -> DesktopPetPerch? {
        guard !fullScreen else { return nil }
        if system.atBottom, !system.autoHide, let frame = system.frame, usable(frame) {
            return DesktopPetPerch(frame: frame, trashX: system.trashX)
        }
        if shelf.atBottom, !shelf.tucked, let frame = shelf.frame, usable(frame) {
            return DesktopPetPerch(frame: frame, trashX: nil)
        }
        return nil
    }

    /// 读不到程序坞的位置（没有辅助功能权限）时按屏幕估一个：可见区域底下空出来的
    /// 就是程序坞的高度，宽度按图标个数估，居中。
    public static func estimatedDock(screen: CGRect, visible: CGRect, tileSize: Double, tiles: Int) -> CGRect? {
        let height = Double(visible.minY - screen.minY)
        guard height > 8 else { return nil }
        let fitted: Double = max(160, (Double(tiles) + 2) * (tileSize + 4) + 24)
        let width: Double = min(Double(screen.width) * 0.9, fitted)
        return CGRect(x: Double(screen.midX) - width / 2, y: Double(screen.minY), width: width, height: height)
    }

    /// 一个窗口算不算铺满了这块屏幕（全屏 App）：差几个点也算。
    public static func coversScreen(_ window: CGRect, screen: CGRect) -> Bool {
        abs(window.minX - screen.minX) <= 2 && abs(window.minY - screen.minY) <= 2
            && abs(window.width - screen.width) <= 2 && abs(window.height - screen.height) <= 2
    }

    private static func usable(_ frame: CGRect) -> Bool {
        frame.width >= 80 && frame.height >= 20
    }
}

// MARK: - 废纸篓救回

public enum DesktopPetRescue {
    /// 只认这么多秒内拖进去的。
    public static let freshWindow: TimeInterval = 10
    /// 一次最多叼回几个；多了不自动放回，只弹气泡让人自己点。
    public static let maxItems = 3

    /// 刚扔进来、还没处理过的几项。`seen` 是打开开关时已经在废纸篓里的和处理过的；
    /// 清空废纸篓、放回原处只会让项目变少，不会出现在这里。
    public static func fresh(_ items: [TrashedItem], seen: Set<String>, now: Date) -> [TrashedItem] {
        items.filter { item in
            !seen.contains(item.trashName)
                && item.date <= now.addingTimeInterval(2)
                && now.timeIntervalSince(item.date) <= freshWindow
        }
    }

    /// 自动放回原处，还是只给一个气泡按钮：项目太多、或这一下扔进去的比列出来的多
    /// （废纸篓面板只列最近几个，后面的看不到）时只给按钮。
    public static func autoPutBack(fresh: Int, added: Int) -> Bool {
        fresh > 0 && fresh <= maxItems && added <= fresh
    }

    /// 气泡上的字。
    public static func bubbleTitle(count: Int) -> String {
        count > 1 ? tr("放回原处（\(count) 项）") : tr("放回原处")
    }

    /// 交给访达的 AppleScript：把废纸篓里的这一项移回原来的文件夹，名字改回原名。
    /// 路径和名字从参数传进去，不拼进脚本。
    public static let finderScript = """
        on run argv
            set src to (POSIX file (item 1 of argv)) as alias
            set dest to (POSIX file (item 2 of argv)) as alias
            set wanted to item 3 of argv
            tell application "Finder"
                set moved to move src to dest
                if name of moved is not wanted then set name of moved to wanted
            end tell
        end run
        """
}

// MARK: - 专注陪伴（码头 Pro）

/// 专注计时面板里顺着竹竿往上爬的小熊猫，和桌面宠物专注时坐着陪、结束时欢呼。
public enum FocusPandaClimb {
    /// 中途手动结束或重置：滑下来；完成一轮：到顶欢呼。
    public enum Event: Equatable, Sendable {
        case slide, cheer
    }

    /// 专注环节开始了（走着或暂停着）。
    public static func isActive(_ state: TimerState) -> Bool {
        state.phase == .focus && (state.deadline != nil || state.paused != nil)
    }

    /// 专注进度 0…1：0 在竹竿底，1 到顶。没开始时是 0。
    public static func progress(_ state: TimerState, now: Date) -> Double {
        guard state.phase == .focus else { return 0 }
        let total = max(1, state.duration ?? Double(max(1, state.minutes) * 60))
        let left: TimeInterval
        if let paused = state.paused {
            left = paused
        } else if let deadline = state.deadline {
            left = deadline.timeIntervalSince(now)
        } else {
            return 0
        }
        return min(1, max(0, 1 - left / total))
    }

    /// 两次读数之间发生了什么。`now` 用来分辨“合盖很久回来、计时器自己回到开头”，
    /// 那不是手动结束，不滑。
    public static func event(from old: TimerState, to new: TimerState, now: Date) -> Event? {
        guard isActive(old) else { return nil }
        if new.phase != .focus, new.completed != old.completed {
            if let deadline = old.deadline, now.timeIntervalSince(deadline) > FocusCycle.staleAfter { return nil }
            return .cheer
        }
        if new.phase == .focus, !isActive(new) {
            if let deadline = old.deadline, deadline <= now { return nil }
            return .slide
        }
        return nil
    }

    /// 小熊猫离竹竿底多高：`travel` 是能爬的高度（竹竿高减去小熊猫高）。
    public static func climbOffset(progress: Double, travel: Double) -> Double {
        max(0, travel) * min(1, max(0, progress))
    }
}

/// 专注陪伴是码头 Pro：免费用户在竹竿旁看到一只静态的小熊猫。
public extension ProLicenseGate {
    static func canUseFocusPanda(unlocked: Bool) -> Bool {
        canUse(.focusPanda, unlocked: unlocked)
    }
}
