import Foundation

// 让桌宠看着是活的：在已有的帧上叠一层很轻的程序化动效，六只吉祥物（小熊猫和其余五只）都一样。
//
// - 呼吸：坐着、发呆、趴着时身子按一条慢慢起伏的曲线纵向轻轻涨缩（约 3.4 秒一次，幅度不到 2%）。
// - 发呆时的小动作（`DesktopPetFidget`）：左右张望、歪头、点头、原地小跳、开心扭一下。
//   什么时候做哪个按绝对时间切成的「时间槽」算出来（同一槽算几次都一样），不用存状态，
//   测试也能定住。约一半的槽里有一个小动作，间隔就短而随机。
// - 减弱动态效果（`DesktopPetMotion.reduced`）：不呼吸、不转不跳，只换朝向、换姿势。
// - 专注陪伴（`.sit`）时只呼吸，不做小动作；睡着、走路、拖着、吊着、抱树的照旧。
//
// 窗口、计时器、读系统设置在 `DesktopPetController`；这里只有纯逻辑。

/// 动效要不要减弱：系统「减弱动态效果」打开时是 `.reduced`。
public enum DesktopPetMotion: Sendable {
    case full, reduced
}

/// 发呆时穿插的小动作。
public enum DesktopPetFidget: String, CaseIterable, Sendable {
    /// 左右张望：中段换个朝向看另一边，再转回来。
    case look
    /// 歪头：身子往后一侧轻轻歪一下再回正。
    case tilt
    /// 点头：往前点两下。
    case nod
    /// 原地小跳：蹲一下、蹦起来一点、落地压扁。
    case hop
    /// 开心扭一下：换成欢呼（挥手）那几帧。
    case wiggle

    /// 演多久（秒）。
    public var duration: TimeInterval {
        switch self {
        case .look: 1.8
        case .tilt: 1.3
        case .nod: 0.9
        case .hop: 0.55
        case .wiggle: 1.0
        }
    }

    /// 挑中的权重：张望、歪头、点头这些安静的多，跳和欢呼少一点。
    public var weight: Double {
        switch self {
        case .look: 0.3
        case .tilt: 0.22
        case .nod: 0.2
        case .hop: 0.16
        case .wiggle: 0.12
        }
    }

    /// 减弱动态效果时还能做：只换朝向、换姿势，不转、不跳。
    public var calm: Bool {
        self == .look || self == .wiggle
    }

    /// 要不要按显示刷新画才顺：转、跳的要；只换图的不要。
    public var smooth: Bool {
        self != .wiggle
    }
}

public enum DesktopPetLively {
    /// 呼吸一次多久（秒）。
    public static let breathPeriod: TimeInterval = 3.4
    /// 呼吸时纵向涨缩多少（比例）；横向反着缩一点点，看着像肚子在动。
    public static let breathDepth: Double = 0.018
    public static let breathWidth: Double = 0.006
    /// 时间槽多长（秒）；一个槽里最多一个小动作。
    public static let slot: TimeInterval = 6.5
    /// 一个槽里有小动作的机会。
    public static let fidgetChance: Double = 0.5
    /// 刚换到发呆以后先安静这么久，再开始做小动作，免得一坐下就动。
    public static let settle: TimeInterval = 1.0
    /// 歪头、点头、张望时转多少度；小跳多高（点）。
    public static let tiltAngle: Double = 6
    public static let nodAngle: Double = 5
    public static let lookAngle: Double = 3.5
    public static let hopHeight: Double = 9

    // MARK: 呼吸

    /// 呼吸曲线：-1…1，`breathPeriod` 一个来回。吸气略快、呼气略慢（加一点二次谐波），
    /// 按绝对时间算，换动作时接得上。
    public static func breath(time: Double, period: Double = breathPeriod) -> Double {
        guard period > 0 else { return 0 }
        let phase = time / period * 2 * .pi
        let raw = sin(phase) + 0.2 * sin(2 * phase)
        return max(-1, min(1, raw / 1.1))
    }

    /// 这一刻呼吸带来的横、纵缩放。
    public static func breathScale(time: Double) -> (x: Double, y: Double) {
        let b = breath(time: time)
        return (1 - breathWidth * b, 1 + breathDepth * b)
    }

    /// 这个动作时会呼吸：坐着发呆、专注陪着、趴着歇、走到头停一下。
    public static func breathes(_ activity: DesktopPetActivity) -> Bool {
        switch activity {
        case .idle, .sit, .curl, .edgePause: true
        default: false
        }
    }

    /// 这个动作时会穿插小动作：只在发呆时（专注陪伴 `.sit` 不做）。
    public static func fidgets(_ activity: DesktopPetActivity) -> Bool {
        if case .idle = activity { return true }
        return false
    }

    /// 这种待法用不用这层动效：站着的（程序坞上、随意放的）和底边蜷着的用；吊着、抱树的有自己的晃法。
    public static func applies(to style: DesktopPetStyle) -> Bool {
        style == .stroll || style == .sit || style == .curl
    }

    // MARK: 小动作排期

    /// 按权重挑一个小动作。`roll` 是 0…1。
    public static func pick(roll: Double) -> DesktopPetFidget {
        let total = DesktopPetFidget.allCases.reduce(0) { $0 + $1.weight }
        var left = min(0.999_999, max(0, roll)) * total
        for fidget in DesktopPetFidget.allCases {
            if left < fidget.weight { return fidget }
            left -= fidget.weight
        }
        return .look
    }

    /// 第 `index` 个时间槽里有没有小动作：有的话是哪个、从哪一刻（绝对秒数）开始。
    /// 小动作整段都在这个槽里。
    public static func scheduled(slot index: Int64) -> (fidget: DesktopPetFidget, start: Double)? {
        guard unit(index, salt: 0x51) < fidgetChance else { return nil }
        let fidget = pick(roll: unit(index, salt: 0xA7))
        let room = max(0, slot - fidget.duration)
        return (fidget, Double(index) * slot + unit(index, salt: 0x3D) * room)
    }

    /// `time` 这一刻（绝对秒数）正在做的小动作和进度（0…1）。`since` 是这段发呆开始的时刻，
    /// 开始后 `settle` 秒内的不算；减弱动态效果时只留 `calm` 的。
    public static func fidget(at time: Double, since: Double,
                              motion: DesktopPetMotion = .full) -> (fidget: DesktopPetFidget, progress: Double)? {
        let index = Int64((time / slot).rounded(.down))
        guard let planned = scheduled(slot: index), planned.start >= since + settle else { return nil }
        let t = (time - planned.start) / planned.fidget.duration
        guard t >= 0, t < 1 else { return nil }
        if motion == .reduced, !planned.fidget.calm { return nil }
        return (planned.fidget, t)
    }

    /// 这一刻要不要按显示刷新画：正在做转、跳的小动作（而且不减弱动态效果）。
    public static func needsSmooth(_ state: DesktopPetState, now: Date, style: DesktopPetStyle,
                                   motion: DesktopPetMotion) -> Bool {
        guard motion == .full, style == .stroll || style == .sit, fidgets(state.activity),
              let current = fidget(at: now.timeIntervalSinceReferenceDate,
                                   since: state.since.timeIntervalSinceReferenceDate, motion: motion) else {
            return false
        }
        return current.fidget.smooth
    }

    // MARK: 叠到样子上

    /// 在大脑算好的样子上叠呼吸和小动作。按小熊猫的帧名算，之后再换吉祥物（`DesktopPetSkin.apply`）。
    public static func decorate(_ pose: DesktopPetPose, state: DesktopPetState, now: Date,
                                style: DesktopPetStyle, motion: DesktopPetMotion) -> DesktopPetPose {
        guard applies(to: style) else { return pose }
        // 正在掉头的那一下不叠，免得和转身过渡打架。
        if let turnedAt = state.turnedAt {
            let t = now.timeIntervalSince(turnedAt)
            if t >= 0, t < DesktopPetBrain.turnDuration { return pose }
        }
        var out = pose
        let time = now.timeIntervalSinceReferenceDate
        if motion == .full, breathes(state.activity) {
            let scale = breathScale(time: time)
            out.scaleX *= scale.x
            out.scaleY *= scale.y
        }
        guard style != .curl, fidgets(state.activity),
              let current = fidget(at: time, since: state.since.timeIntervalSinceReferenceDate, motion: motion) else {
            return out
        }
        apply(current.fidget, progress: current.progress, to: &out, motion: motion)
        return out
    }

    /// 把小动作的第 `t`（0…1）那一刻叠到样子上。顺时针为正，朝右时「往前」是顺时针。
    static func apply(_ fidget: DesktopPetFidget, progress t: Double, to pose: inout DesktopPetPose,
                      motion: DesktopPetMotion) {
        let t = min(1, max(0, t))
        let forward: Double = pose.facingLeft ? -1 : 1
        let full = motion == .full
        switch fidget {
        case .look:
            // 中段看另一边。
            if t >= 0.35, t < 0.75 { pose.facingLeft.toggle() }
            if full { pose.wobble += lookAngle * sin(2 * .pi * t) }
        case .tilt:
            if full { pose.wobble -= forward * tiltAngle * bell(t) }
        case .nod:
            if full { pose.wobble += forward * nodAngle * abs(sin(2 * .pi * t)) }
        case .hop:
            guard full else { break }
            pose.lift += hopLift(t)
            let squash = hopSquash(t)
            pose.scaleY *= 1 - 0.08 * squash
            pose.scaleX *= 1 + 0.05 * squash
        case .wiggle:
            if pose.image.hasPrefix("pet-sprite-front-") {
                pose.image = DesktopPetStrip.frontWave.imageName(Int(t * 4))
            } else {
                pose.image = DesktopPetStrip.cheer.imageName(min(DesktopPetStrip.cheer.frameCount - 1, Int(t * 6)))
            }
            if full { pose.wobble += 2.5 * sin(4 * .pi * t) }
        }
    }

    /// 0…1…0 的钟形（缓入缓出）。
    static func bell(_ t: Double) -> Double {
        let s = sin(.pi * min(1, max(0, t)))
        return s * s
    }

    /// 小跳离地多高：前后各 20% 蹲着不离地，中间一段抛物线。
    public static func hopLift(_ t: Double) -> Double {
        let air = (t - 0.2) / 0.6
        guard air > 0, air < 1 else { return 0 }
        return 4 * hopHeight * air * (1 - air)
    }

    /// 小跳的蹲、落地压扁：0 不压，1 压得最扁。
    public static func hopSquash(_ t: Double) -> Double {
        if t < 0.2 { return sin(t / 0.2 * .pi) }
        if t > 0.8 { return sin((t - 0.8) / 0.2 * .pi) }
        return 0
    }

    // MARK: 随意放的附近走走

    /// 随意放的地方附近能走多远（点，单边）：按小熊猫身长，至少 40。
    public static func wanderRadius(length: Double) -> Double {
        max(40, length * 1.2)
    }

    /// 随意放在 `home` 时附近能走的范围：以 `home` 为中、两边一样长，夹在 `bounds` 里
    /// （可见区域里能站的横向范围，不出屏幕、不压程序坞）。所以范围的中点总是记住的那一点。
    public static func wanderLane(home: Double, radius: Double, bounds: ClosedRange<Double>) -> ClosedRange<Double> {
        let room = max(0, min(radius, home - bounds.lowerBound, bounds.upperBound - home))
        return (home - room)...(home + room)
    }

    /// 随意放的发呆完去哪：不在原处就走回原处（范围中点），在原处就往一边走一小段。
    /// 范围太窄（贴着屏幕边）或走不了几步返回 nil。
    public static func wanderTarget(from x: Double, lane: ClosedRange<Double>, random: () -> Double) -> Double? {
        guard lane.upperBound - lane.lowerBound >= 16 else { return nil }
        let home = (lane.lowerBound + lane.upperBound) / 2
        if abs(x - home) > 6 { return home }
        let half = (lane.upperBound - lane.lowerBound) / 2
        let distance = half * (0.5 + 0.5 * random())
        let target = DesktopPetBrain.clamp(random() < 0.5 ? x - distance : x + distance, lane)
        return abs(target - x) >= 4 ? target : nil
    }

    // MARK: 内部

    /// 0…1 的确定性随机数：同一个槽、同一个盐永远一样。
    static func unit(_ index: Int64, salt: UInt64) -> Double {
        var z = UInt64(bitPattern: index) &+ salt &* 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(UInt64(1) << 53)
    }
}
