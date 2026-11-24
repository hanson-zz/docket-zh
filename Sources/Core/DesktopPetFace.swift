import CoreGraphics
import Foundation

// 灵动小熊猫（第一阶段）：小熊猫正面坐着时，眼睛跟着指针看，被点、被摸、连戳、开心、犯困时换表情。
//
// - 只管小熊猫（`FocusMascot.panda`），而且只在程序坞上或随意放的地方正面坐着（front-sit 那几帧）时；
//   走、跑、侧面、吊边、抱边、睡觉照旧用原来的帧。其余五只吉祥物不变。
// - 素材：Resources/Pet/sprites/pet-sprite-lively-<名字>.png，和 front-sit 同尺寸（116×129，@2x），
//   脚底贴图底、左右居中，九张按同一个裁切框和同一个缩放出图，换帧时大小位置不跳。
//   look-left / look-right / look-up / look-down 是看向四个方向（左右按屏幕方向），
//   emote-surprise / shy / dizzy / happy / sleepy 是五个表情。
//   正视 `lively-center` 和闭眼 `lively-blink` 已补齐（若缺图仍回退）：缺正视时正视就画原来的 front-sit 帧（原样眨眼），
//   缺闭眼时不另外眨眼；缺任何一张都退回原来的样子，不崩。
// - 看向：按指针相对桌宠中心的方向挑一张，带死区和滞回，换了方向至少停一小会儿，免得抖；
//   指针静止一阵或离得很远时回正视。只用这一刻的指针位置，不记录、不存盘。
//   指针位置复用桌宠原来的计时器读（静止时每秒 10 次），不另开刷新。
// - 表情：单击 surprise；摸头 shy；短时间连点 4 下 dizzy（有冷却）；欢呼时 happy；快睡着前 sleepy。
//   演完回到看向或正视。「减弱动态效果」时不跟指针、表情只换静帧，不加动效。
//
// 窗口、指针、设置开关在 `DesktopPetController`；这里只有纯逻辑。

/// 看向哪边。左右按屏幕方向：指针在桌宠左边就是 `.left`。
public enum DesktopPetGaze: String, CaseIterable, Sendable {
    case center, left, right, up, down
}

/// 表情。
public enum DesktopPetEmote: String, CaseIterable, Sendable {
    case surprise, shy, dizzy, happy, sleepy

    /// 演多久（秒）。happy 跟着欢呼、sleepy 跟着犯困，由外面的状态决定，这里给个参考值。
    public var duration: TimeInterval {
        switch self {
        case .surprise: 1.0
        case .shy: 1.6
        case .dizzy: 2.0
        case .happy: 1.5
        case .sleepy: 10
        }
    }
}

public enum DesktopPetFace {
    /// 图名前缀。
    public static let prefix = "pet-sprite-lively-"
    /// 正视、闭眼两张以后补。
    public static let centerImage = "pet-sprite-lively-center"
    public static let blinkImage = "pet-sprite-lively-blink"

    /// 看向那张图。正视是 `centerImage`。
    public static func imageName(_ gaze: DesktopPetGaze) -> String {
        gaze == .center ? centerImage : prefix + "look-" + gaze.rawValue
    }

    public static func imageName(_ emote: DesktopPetEmote) -> String {
        prefix + "emote-" + emote.rawValue
    }

    /// 现在就有的九张。
    public static var shippedImages: [String] {
        DesktopPetGaze.allCases.filter { $0 != .center }.map { imageName($0) }
            + DesktopPetEmote.allCases.map { imageName($0) }
    }

    /// 全部十一张（含以后补的正视、闭眼）。
    public static var allImages: [String] { shippedImages + [centerImage, blinkImage] }

    // MARK: 参数（点，按「中」号大小算，外面先除掉大小缩放）

    /// 指针离中心这么近算在身上，回正视；从正视转出去要超过 `deadZoneOut`。
    public static let deadZone: Double = 28
    public static let deadZoneOut: Double = 40
    /// 指针离得比这远就不看了；回来时要进到 `farReach - farBand` 以内才再看。
    public static let farReach: Double = 900
    public static let farBand: Double = 80
    /// 还在原方向的扇区里就不换：另一方向要比这个方向大出 1 / keepRatio 倍才换。
    public static let keepRatio: Double = 0.7
    /// 换了方向以后至少停这么久。
    public static let minHold: TimeInterval = 0.3
    /// 指针挪动不到这么多点算没动；静止这么久回正视。
    public static let stillJitter: Double = 2
    public static let stillAfter: TimeInterval = 5
    /// 这么多秒内点满 `dizzyTaps` 下就晕；晕过以后冷却 `dizzyCooldown` 秒。
    public static let tapWindow: TimeInterval = 2.5
    public static let dizzyTaps = 4
    public static let dizzyCooldown: TimeInterval = 8
    /// 快睡着前这么多秒先犯困。
    public static let sleepyLead: TimeInterval = 10

    // MARK: 什么时候生效

    /// 设置开着、是小熊猫、在程序坞上或随意放的地方、大脑这一刻画的是正面坐着（或正面挥手，给欢呼换 happy）。
    /// `image` 是大脑算出来、还没叠小动作的那张。
    public static func applies(enabled: Bool, mascot: FocusMascot, style: DesktopPetStyle, image: String) -> Bool {
        guard enabled, mascot == .panda, style == .stroll || style == .sit else { return false }
        return isFrontSit(image) || isFrontWave(image)
    }

    static func isFrontSit(_ image: String) -> Bool { image.hasPrefix("pet-sprite-front-sit-") }
    static func isFrontWave(_ image: String) -> Bool { image.hasPrefix("pet-sprite-front-wave-") }

    /// 快睡着了：用户没操作的时间进了入睡前最后 `sleepyLead` 秒。
    public static func drowsy(userIdle: TimeInterval, night: Bool) -> Bool {
        let sleepAt = DesktopPetRhythm.sleepAfter(night: night)
        return userIdle >= sleepAt - sleepyLead && userIdle < sleepAt
    }

    // MARK: 看向

    /// 指针在中心的 (`dx`, `dy`)（点，y 朝上）时看哪边，`current` 是现在看的方向（滞回用）。
    public static func gaze(dx: Double, dy: Double, current: DesktopPetGaze) -> DesktopPetGaze {
        let distance = hypot(dx, dy)
        let near = current == .center ? deadZoneOut : deadZone
        if distance < near { return .center }
        let far = current == .center ? farReach - farBand : farReach
        if distance > far { return .center }
        let ax = abs(dx), ay = abs(dy)
        switch current {
        case .left where dx < 0 && ax >= ay * keepRatio: return .left
        case .right where dx > 0 && ax >= ay * keepRatio: return .right
        case .up where dy > 0 && ay >= ax * keepRatio: return .up
        case .down where dy < 0 && ay >= ax * keepRatio: return .down
        default: break
        }
        if ax >= ay { return dx < 0 ? .left : .right }
        return dy > 0 ? .up : .down
    }

    // MARK: 叠到样子上

    /// 在大脑和小动作算好的样子上换成灵动帧。`base` 是大脑这一刻画的图（叠小动作前），
    /// `pose` 是叠完的；`exists` 告诉哪张图在包里。不生效、缺图时原样返回。
    public static func overlay(_ pose: DesktopPetPose, base: String, state: DesktopPetState,
                               face: DesktopPetFaceState, now: Date, drowsy: Bool,
                               motion: DesktopPetMotion, exists: (String) -> Bool) -> DesktopPetPose {
        if let emote = emote(base: base, state: state, face: face, now: now, drowsy: drowsy) {
            let name = imageName(emote)
            guard exists(name) else { return pose }
            var out = pose
            out.image = name
            out.facingLeft = false
            out.height = nil
            out.wobble = 0
            out.lift = 0
            if motion == .full {
                let since = face.emoteSince(now: now) ?? state.since
                animate(emote, elapsed: max(0, now.timeIntervalSince(since)), pose: &out)
            }
            return out
        }
        // 正面挥手（打招呼、小动作扭一下）和被小动作换掉的帧照旧。
        guard isFrontSit(base), isFrontSit(pose.image) else { return pose }
        let gaze = face.gaze
        // 缺正视时正视就是原来的坐姿（自带眨眼），不混用两套画。
        if gaze == .center, !exists(centerImage) { return pose }
        var name = imageName(gaze)
        let blinkNow = DesktopPetBrain.blinking(now: now) || base == DesktopPetStrip.frontSit.imageName(2)
        if blinkNow, exists(blinkImage) { name = blinkImage }
        guard exists(name) else { return pose }
        var out = pose
        out.image = name
        out.facingLeft = false
        out.height = nil
        return out
    }

    /// 这一刻演哪个表情：点、摸、连戳的优先，其次欢呼（happy）、犯困（sleepy）。
    static func emote(base: String, state: DesktopPetState, face: DesktopPetFaceState, now: Date,
                      drowsy: Bool) -> DesktopPetEmote? {
        if let active = face.activeEmote(now: now) { return active }
        switch state.activity {
        case .cheer, .celebrate:
            if isFrontWave(base) { return .happy }
        case .idle:
            if drowsy, isFrontSit(base) { return .sleepy }
        default:
            break
        }
        return nil
    }

    /// 表情的小动效：惊一下往上一弹，害羞歪头，晕乎乎转圈晃，开心一颠一颠，犯困慢慢点头。
    static func animate(_ emote: DesktopPetEmote, elapsed t: Double, pose: inout DesktopPetPose) {
        switch emote {
        case .surprise:
            if t < 0.3 { pose.lift += 5 * sin(.pi * t / 0.3) }
        case .shy:
            let k = min(1, t / 0.25)
            pose.wobble -= 4 * k
        case .dizzy:
            pose.wobble += 5 * sin(2 * .pi * t * 1.6)
        case .happy:
            pose.lift += 2.5 * abs(sin(2 * .pi * t * 1.5))
        case .sleepy:
            pose.wobble += 2 * sin(2 * .pi * t / 3)
        }
    }

    /// 这一刻要不要按显示刷新画：正在演带动效的表情，而且不减弱动态效果。
    public static func needsSmooth(_ face: DesktopPetFaceState, now: Date, motion: DesktopPetMotion) -> Bool {
        guard motion == .full, let emote = face.activeEmote(now: now) else { return false }
        return emote != .sleepy
    }
}

/// 灵动小熊猫这一会儿的状态：看哪边、正在演的表情、最近几次点击。只在内存里，不存盘。
public struct DesktopPetFaceState: Equatable, Sendable {
    public private(set) var gaze: DesktopPetGaze = .center
    public private(set) var gazeAt: Date?
    public private(set) var emote: DesktopPetEmote?
    public private(set) var emoteStart: Date?
    public private(set) var emoteUntil: Date?
    public private(set) var taps: [Date] = []
    public private(set) var dizzyAt: Date?
    private var lastPointer: CGPoint?
    private var movedAt: Date?

    public init() {}

    /// 跟着指针：`pointer` 是这一刻的指针（屏幕坐标），nil 是不跟（关了、减弱动态效果、不在正面坐着）；
    /// `center` 是桌宠中心，`scale` 是大小设置的缩放。
    public mutating func follow(pointer: CGPoint?, center: CGPoint, scale: Double, now: Date) {
        guard let pointer else {
            lastPointer = nil
            movedAt = nil
            settle(.center, now: now)
            return
        }
        if let last = lastPointer, hypot(Double(pointer.x - last.x), Double(pointer.y - last.y)) < DesktopPetFace.stillJitter {
            // 没怎么动：不更新上次位置，慢慢挪也算动。
        } else {
            lastPointer = pointer
            movedAt = now
        }
        if let movedAt, now.timeIntervalSince(movedAt) >= DesktopPetFace.stillAfter {
            settle(.center, now: now)
            return
        }
        let k = max(0.1, scale)
        let next = DesktopPetFace.gaze(dx: Double(pointer.x - center.x) / k, dy: Double(pointer.y - center.y) / k,
                                       current: gaze)
        settle(next, now: now)
    }

    private mutating func settle(_ next: DesktopPetGaze, now: Date) {
        guard next != gaze else { return }
        if let gazeAt, now >= gazeAt, now.timeIntervalSince(gazeAt) < DesktopPetFace.minHold { return }
        gaze = next
        gazeAt = now
    }

    /// 单击一下：返回演哪个（surprise，或者短时间连点满 4 下且过了冷却时 dizzy）。
    @discardableResult
    public mutating func tapped(now: Date) -> DesktopPetEmote {
        taps = taps.filter { now >= $0 && now.timeIntervalSince($0) <= DesktopPetFace.tapWindow } + [now]
        let cooled = dizzyAt.map { now < $0 || now.timeIntervalSince($0) >= DesktopPetFace.dizzyCooldown } ?? true
        if taps.count >= DesktopPetFace.dizzyTaps, cooled {
            taps = []
            dizzyAt = now
            play(.dizzy, now: now)
            return .dizzy
        }
        // 晕着时再点不打断。
        if emote == .dizzy, let emoteUntil, now < emoteUntil { return .dizzy }
        play(.surprise, now: now)
        return .surprise
    }

    /// 演一个表情 `duration` 那么久。
    public mutating func play(_ next: DesktopPetEmote, now: Date) {
        emote = next
        emoteStart = now
        emoteUntil = now.addingTimeInterval(next.duration)
    }

    /// 这一刻正在演的表情（到点了是 nil）。
    public func activeEmote(now: Date) -> DesktopPetEmote? {
        guard let emote, let emoteStart, let emoteUntil, now >= emoteStart, now < emoteUntil else { return nil }
        return emote
    }

    /// 正在演的表情从什么时候开始。
    public func emoteSince(now: Date) -> Date? {
        activeEmote(now: now) == nil ? nil : emoteStart
    }

    /// 停掉表情、回正视（换了吉祥物、拖走、关了开关）。
    public mutating func reset() {
        self = DesktopPetFaceState()
    }
}
