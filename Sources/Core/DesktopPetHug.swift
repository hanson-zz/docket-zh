import Foundation

// 桌面宠物：左右边缘「考拉抱树」、程序坞闲置轮换、作息、连戳和摸头。都是纯逻辑，
// 窗口和鼠标在 `DesktopPetController`。

// MARK: - 抱树

/// 左右边缘抱着屏幕边：图正着画，原图里屏幕边那条线对齐屏幕边，线外的身子在屏幕外（窗口裁掉），
/// 平时只露头和两只前爪。左右各一套专门画的帧（右边不翻转）。
public enum DesktopPetHug {
    /// 左套（hug、hug-out、hug-sleep、hug-climb）屏幕边那条线在图宽的哪儿（从左数）：
    /// 原图 x≈300，768 画布缩放 0.344 后整套统一裁切框 61…174。
    public static let leftEdgeLine: Double = 0.3735
    /// 右套（hug-r …）：原图 x≈468，裁切框 89…212。
    public static let rightEdgeLine: Double = 0.5853

    /// 屏幕里露出图宽的多少：左边是线右边那块，右边是线左边那块。
    public static func inside(_ edge: DesktopPetEdge) -> Double {
        edge == .right ? rightEdgeLine : 1 - leftEdgeLine
    }

    /// 爬出来（hug-out 6 帧）每秒 8 帧。
    public static let outFPS: Double = 8
    public static var outDuration: TimeInterval { Double(DesktopPetStrip.hugOut.frameCount) / outFPS }
    /// 缩回去：从露全身那帧（第 5 帧）倒放到第 1 帧。
    public static var inDuration: TimeInterval { 5 / outFPS }
    /// 爬出来以后挥手多久，之后露全身待着。
    public static let waveHold: TimeInterval = 1.2
    /// 爬出来以后没人理（鼠标没在它上面、没点）这么多秒就缩回去。
    public static let retractAfter: TimeInterval = 5
    /// 抱着隔多久沿边爬一段（秒）。
    public static let climbEvery: ClosedRange<Double> = 30...90
    /// 一次爬多远（点）、多快（点 / 秒）、climb 帧每秒几帧。
    public static let climbRange: ClosedRange<Double> = 24...72
    public static let climbSpeed: Double = 16
    public static let climbFPS: Double = 6
    /// 鼠标靠近头时抖耳朵多久。
    public static let earFlick: TimeInterval = 0.9
    /// 抱着呼吸：每 0.8 秒换一帧（hug-1、hug-2 交替），偶尔眨眼（hug-3）、抖耳（hug-4）。
    public static let breath: TimeInterval = 0.8
    /// 打盹闭眼呼吸 2 帧，每秒 1 帧。
    public static let sleepFPS: Double = 1

    /// 那条边用哪一套帧。
    public static func idleStrip(_ edge: DesktopPetEdge) -> DesktopPetStrip { edge == .right ? .hugR : .hug }
    public static func outStrip(_ edge: DesktopPetEdge) -> DesktopPetStrip { edge == .right ? .hugOutR : .hugOut }
    public static func sleepStrip(_ edge: DesktopPetEdge) -> DesktopPetStrip { edge == .right ? .hugSleepR : .hugSleep }
    public static func climbStrip(_ edge: DesktopPetEdge) -> DesktopPetStrip { edge == .right ? .hugClimbR : .hugClimb }

    /// 抱着待机在 `time` 秒时是第几帧（从 0 数）：呼吸为主，眨眼、抖耳按时间段的散列偶尔出现，没有固定节奏。
    public static func idleFrame(time: Double) -> Int {
        let slot = Int64((time / breath).rounded(.down))
        let into = time - Double(slot) * breath
        let roll = noise(slot)
        if roll < 0.08, into < 0.18 { return 2 }
        if roll >= 0.08, roll < 0.12, into < 0.4 { return 3 }
        return Int(((slot % 2) + 2) % 2)
    }

    /// 打盹多久后醒来沿边爬一段（30～90 秒，按入睡时刻散列，不用另存）。
    public static func napLength(since: Date) -> TimeInterval {
        DesktopPetBrain.lerp(climbEvery, noise(Int64(since.timeIntervalSinceReferenceDate.rounded(.down))))
    }

    /// 爬出来那一段第几帧：6 帧爬出，挥手（第 6 帧）停一会儿，再露全身（第 5 帧）待着。
    public static func outFrame(elapsed: Double) -> Int {
        if elapsed < outDuration { return min(5, max(0, Int(elapsed * outFPS))) }
        return elapsed - outDuration < waveHold ? 5 : 4
    }

    /// 0…1 的散列（splitmix64），同一个数每次一样。
    static func noise(_ n: Int64) -> Double {
        var z = UInt64(bitPattern: n) &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(UInt64(1) << 53)
    }
}

// MARK: - 作息

public enum DesktopPetRhythm {
    /// 本地 23:00～6:00 算夜里：入睡时间缩短一半。
    public static func isNight(hour: Int) -> Bool { hour >= 23 || hour < 6 }

    public static func sleepAfter(night: Bool) -> TimeInterval { DesktopPetBrain.sleepAfter * (night ? 0.5 : 1) }
    public static func dozeAfter(night: Bool) -> TimeInterval { DesktopPetHang.dozeAfter * (night ? 0.5 : 1) }

    /// 「一天」从早上 5 点算起：熬夜过了 0 点不算新的一天。
    public static let dayStartsAt = 5

    public static func greetingDay(_ now: Date, calendar: Calendar = .current) -> String {
        let shifted = now.addingTimeInterval(-Double(dayStartsAt) * 3600)
        let c = calendar.dateComponents([.year, .month, .day], from: shifted)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// 今天还没打过招呼（每天第一次唤醒或出现时伸懒腰说「早」）。
    public static func shouldGreet(lastDay: String?, now: Date, calendar: Calendar = .current) -> Bool {
        lastDay != greetingDay(now, calendar: calendar)
    }

    /// 早上的招呼：「早」/ "Morning"。
    public static var morningText: String { tr("早") }
}

// MARK: - 连戳、摸头、经过、靠近

/// 鼠标和小熊猫之间的小互动，都带冷却，不打扰太频繁。
public struct DesktopPetMood: Equatable, Sendable {
    /// 10 秒内连续单击 3 次：不高兴，耷拉耳朵约 3 秒。
    public static let pokeWindow: TimeInterval = 10
    public static let pokeCount = 3
    public static let sulkDuration: TimeInterval = 3
    /// 鼠标在它身上来回划（不按键）：2 秒内 3 次方向变化算摸头，开心一下，冷却 30 秒。
    public static let rubWindow: TimeInterval = 2
    public static let rubTurns = 3
    public static let rubCooldown: TimeInterval = 30
    /// 小于这么多点的抖动不算换方向。
    public static let rubJitter: Double = 2
    /// 底边姿势：鼠标从旁边（80 点内）移动经过时抬头看一眼，冷却 20 秒。
    public static let glanceReach: Double = 80
    public static let glanceSpeed: Double = 40
    public static let glanceCooldown: TimeInterval = 20
    /// 抱树：鼠标靠近头（60 点内）时抖耳朵看过来，冷却 12 秒。
    public static let earReach: Double = 60
    public static let earCooldown: TimeInterval = 12

    public private(set) var clicks: [Date] = []
    public private(set) var turns: [Date] = []
    public private(set) var lastRub: Date?
    public private(set) var lastGlance: Date?
    public private(set) var lastEar: Date?
    private var lastX: Double?
    private var lastSign = 0
    private var near = false

    public init() {}

    /// 单击一次。返回 true：10 秒内第 3 次，该耷拉耳朵了（之后重新数）。
    public mutating func clicked(now: Date) -> Bool {
        clicks = clicks.filter { now >= $0 && now.timeIntervalSince($0) <= Self.pokeWindow } + [now]
        guard clicks.count >= Self.pokeCount else { return false }
        clicks = []
        return true
    }

    /// 鼠标在它身上移动（`x` 是横坐标；不在身上是 nil）。返回 true：摸头了。
    public mutating func rubbed(x: Double?, pressed: Bool, now: Date) -> Bool {
        guard let x, !pressed else {
            lastX = nil
            lastSign = 0
            turns = []
            return false
        }
        guard let last = lastX else {
            lastX = x
            return false
        }
        guard abs(x - last) >= Self.rubJitter else { return false }
        lastX = x
        let sign = x > last ? 1 : -1
        if lastSign != 0, sign != lastSign { turns.append(now) }
        lastSign = sign
        turns = turns.filter { now >= $0 && now.timeIntervalSince($0) <= Self.rubWindow }
        guard turns.count >= Self.rubTurns else { return false }
        if let lastRub, now >= lastRub, now.timeIntervalSince(lastRub) < Self.rubCooldown { return false }
        lastRub = now
        turns = []
        return true
    }

    /// 鼠标离小熊猫 `distance` 点、每秒移动 `speed` 点。返回 true：抬头看一眼。
    public mutating func passedBy(distance: Double, speed: Double, now: Date) -> Bool {
        guard distance <= Self.glanceReach, speed >= Self.glanceSpeed else { return false }
        if let lastGlance, now >= lastGlance, now.timeIntervalSince(lastGlance) < Self.glanceCooldown { return false }
        lastGlance = now
        return true
    }

    /// 鼠标离头 `distance` 点。刚进 60 点内、过了冷却时返回 true：抖耳朵看过来。
    public mutating func neared(distance: Double, now: Date) -> Bool {
        let inside = distance <= Self.earReach
        defer { near = inside }
        guard inside, !near else { return false }
        if let lastEar, now >= lastEar, now.timeIntervalSince(lastEar) < Self.earCooldown { return false }
        lastEar = now
        return true
    }
}

// MARK: - 程序坞闲置轮换

/// 程序坞上沿闲着时做什么：以趴着为主，夹杂坐起张望、打哈欠、伸懒腰、偶尔散步。
public enum DesktopPetIdleAct: String, CaseIterable, Sendable {
    case lie, look, yawn, stretch, walk

    public var weight: Double {
        switch self {
        case .lie: 0.42
        case .look: 0.22
        case .yawn: 0.1
        case .stretch: 0.1
        case .walk: 0.16
        }
    }

    /// 趴着、坐着张望各多久（秒）。
    public static let lieRange: ClosedRange<Double> = 8...20
    public static let lookRange: ClosedRange<Double> = 3...7

    /// 按权重挑下一个，不和上一个重复。`roll` 是 0…1。
    public static func pick(after last: DesktopPetIdleAct?, roll: Double) -> DesktopPetIdleAct {
        let options = allCases.filter { $0 != last }
        let total = options.reduce(0) { $0 + $1.weight }
        var left = min(0.999_999, max(0, roll)) * total
        for act in options {
            if left < act.weight { return act }
            left -= act.weight
        }
        return options.last ?? .lie
    }
}

// MARK: - 动作

extension DesktopPetBrain {
    /// 程序坞上沿闲着：挑下一个动作（不连续重复），时长随机。
    static func nextIdle(_ state: DesktopPetState, now: Date, lane: ClosedRange<Double>,
                         random: () -> Double) -> DesktopPetState {
        var next = state
        next.since = now
        var act = DesktopPetIdleAct.pick(after: state.lastIdle, roll: random())
        if act == .walk {
            let target = strollTarget(from: next.x, lane: lane, random: random)
            if abs(target - next.x) >= 4 {
                next.activity = .walk(to: target)
                turn(&next, left: target < next.x, now: now)
                next.lastIdle = .walk
                return next
            }
            act = state.lastIdle == .look ? .lie : .look
        }
        switch act {
        case .lie: next.activity = .curl(until: now.addingTimeInterval(lerp(DesktopPetIdleAct.lieRange, random())))
        case .look: next.activity = .idle(until: now.addingTimeInterval(lerp(DesktopPetIdleAct.lookRange, random())))
        case .yawn: next.activity = .yawn(since: now)
        case .stretch: next.activity = .stretch(since: now)
        case .walk: break
        }
        next.lastIdle = act
        return next
    }

    /// 抱着歇：隔 30～90 秒爬一段。
    static func hugRest(now: Date, random: () -> Double) -> DesktopPetActivity {
        .curl(until: now.addingTimeInterval(lerp(DesktopPetHug.climbEvery, random())))
    }

    /// 沿边上下爬一小段，夹在可待范围里（不越过菜单栏和程序坞）；爬不动就接着抱着。
    static func hugClimb(_ state: DesktopPetState, now: Date, lane: ClosedRange<Double>,
                         random: () -> Double) -> DesktopPetState {
        var next = state
        next.since = now
        let distance = lerp(DesktopPetHug.climbRange, random())
        let up = random() < 0.5
        var target = up ? next.x + distance : next.x - distance
        if abs(clamp(target, lane) - next.x) < 4 { target = up ? next.x - distance : next.x + distance }
        target = clamp(target, lane)
        next.activity = abs(target - next.x) < 4 ? hugRest(now: now, random: random) : .hugClimb(to: target)
        return next
    }

    /// 左右边抱树的一步：爬出、缩回、爬边、打盹、抖耳。
    static func hugStep(_ state: DesktopPetState, dt: TimeInterval, now: Date, lane: ClosedRange<Double>,
                        userIdle: TimeInterval, focusing: Bool, quiet: TimeInterval, touchQuiet: TimeInterval,
                        night: Bool, random: () -> Double) -> DesktopPetState {
        var next = state
        let elapsed = max(0, now.timeIntervalSince(state.since))
        switch state.activity {
        case .hugOut(let since):
            if now.timeIntervalSince(since) >= DesktopPetHug.outDuration, touchQuiet >= DesktopPetHug.retractAfter {
                next.activity = .hugIn(since: now)
                next.since = now
            }
            return next
        case .hugIn(let since):
            if now.timeIntervalSince(since) >= DesktopPetHug.inDuration {
                next.activity = hugRest(now: now, random: random)
                next.since = now
            }
            return next
        case .hugClimb(let target):
            let goal = clamp(target, lane)
            next.x = move(next.x, toward: goal, by: DesktopPetHug.climbSpeed * dt)
            if next.x == goal {
                next.activity = hugRest(now: now, random: random)
                next.since = now
            }
            return next
        default:
            break
        }
        if focusing {
            if next.activity != .sit { next.activity = .sit; next.since = now }
            return next
        }
        let sleepy = userIdle >= DesktopPetRhythm.sleepAfter(night: night)
        let doze = DesktopPetRhythm.dozeAfter(night: night)
        switch next.activity {
        case .sleep(let since):
            if sleepy { return next }
            guard quiet >= doze else {
                // 鼠标靠近、被点：醒来接着抱着。
                next.activity = hugRest(now: now, random: random)
                next.since = now
                return next
            }
            // 没人理：打个盹就醒来换个高度。
            if now.timeIntervalSince(since) >= DesktopPetHug.napLength(since: since) {
                return hugClimb(next, now: now, lane: lane, random: random)
            }
        case .curl(let until):
            if sleepy || (quiet >= doze && elapsed >= doze) {
                next.activity = .sleep(since: now)
                next.since = now
                return next
            }
            if now >= until { return hugClimb(next, now: now, lane: lane, random: random) }
        case .peek(let until):
            if now >= until {
                next.activity = hugRest(now: now, random: random)
                next.since = now
            }
        default:
            // 坐着陪完、或别处来的动作（发呆、哈欠……）抱树这边没有：抱回去。
            next.activity = hugRest(now: now, random: random)
            next.since = now
        }
        return next
    }

    /// 抱树这一刻画什么：屏幕里只露 `DesktopPetHug.inside` 那么多。
    static func hugPose(_ state: DesktopPetState, now: Date, edge: DesktopPetEdge) -> DesktopPetPose {
        let elapsed = max(0, now.timeIntervalSince(state.since))
        let time = now.timeIntervalSinceReferenceDate
        let idle = DesktopPetHug.idleStrip(edge)
        let out = DesktopPetHug.outStrip(edge)
        var pose = DesktopPetPose(image: idle.imageName(DesktopPetHug.idleFrame(time: time)))
        pose.reveal = DesktopPetHug.inside(edge)
        switch state.activity {
        case .hugOut(let since):
            pose.image = out.imageName(DesktopPetHug.outFrame(elapsed: max(0, now.timeIntervalSince(since))))
        case .jump, .cheer, .celebrate:
            // 被点、欢呼、专注完成：爬出来挥手，演完由 `step` 倒放缩回。
            pose.image = out.imageName(DesktopPetHug.outFrame(elapsed: elapsed))
        case .hugIn(let since):
            pose.image = out.imageName(max(0, 4 - Int(max(0, now.timeIntervalSince(since)) * DesktopPetHug.outFPS)))
        case .hugClimb(let target):
            let step = Int(elapsed * DesktopPetHug.climbFPS)
            pose.image = DesktopPetHug.climbStrip(edge).imageName(target >= state.x ? step : -1 - step)
        case .sleep(let since):
            let asleep = max(0, now.timeIntervalSince(since))
            pose.image = DesktopPetHug.sleepStrip(edge).imageName(Int(time * DesktopPetHug.sleepFPS))
            if asleep >= 1.5 { pose.zzz = 1 + Int(asleep * 1.5) % 3 }
        case .peek:
            // 抖耳朵看过来：hug-4 和 hug-1 快速换两下。
            pose.image = idle.imageName(Int(elapsed / 0.15) % 2 == 0 ? 3 : 0)
        case .droop:
            // 不高兴：缩着低头闭眼。
            pose.image = DesktopPetHug.sleepStrip(edge).imageName(0)
        default:
            break
        }
        return pose
    }

    /// 抱树时爬出来露着全身（挥手或待着），这时单击按平时的点击处理。
    public static func hugIsOut(_ state: DesktopPetState, now: Date) -> Bool {
        switch state.activity {
        case .hugOut(let since): return now.timeIntervalSince(since) >= DesktopPetHug.outDuration
        case .cheer, .celebrate: return true
        default: return false
        }
    }

    /// 抱树时单击（或来了事）：抱着的爬出来；已经露着的再挥一下手。
    public static func hugTapped(_ state: DesktopPetState, now: Date) -> DesktopPetState {
        switch state.activity {
        case .rescue, .dragged: return state
        default: break
        }
        var next = state
        let start = hugIsOut(state, now: now) ? now.addingTimeInterval(-DesktopPetHug.outDuration) : now
        next.activity = .hugOut(since: start)
        next.since = start
        return next
    }

    /// 底边姿势被鼠标经过：抬头看一眼（站着、坐着的抬头，趴着的抬头探看）。只在闲着时。
    public static func glanced(_ state: DesktopPetState, now: Date) -> DesktopPetState {
        switch state.activity {
        case .idle, .curl, .sit: break
        default: return state
        }
        var next = state
        next.activity = .peek(until: now.addingTimeInterval(1.4))
        next.since = now
        return next
    }

    /// 抱树时鼠标靠近头：抖耳朵看过来。只在抱着歇的时候。
    public static func earFlicked(_ state: DesktopPetState, now: Date) -> DesktopPetState {
        guard case .curl = state.activity else { return state }
        var next = state
        next.activity = .peek(until: now.addingTimeInterval(DesktopPetHug.earFlick))
        next.since = now
        return next
    }

    /// 连戳 3 次：耷拉耳朵约 3 秒。
    public static func sulked(_ state: DesktopPetState, now: Date) -> DesktopPetState {
        switch state.activity {
        case .rescue, .dragged: return state
        default: break
        }
        var next = state
        next.activity = .droop(until: now.addingTimeInterval(DesktopPetMood.sulkDuration))
        next.since = now
        return next
    }

    /// 摸头：开心一下。抱树的爬出来挥手，别处欢呼。
    public static func petted(_ state: DesktopPetState, style: DesktopPetStyle, now: Date) -> DesktopPetState {
        style == .side ? hugTapped(state, now: now) : cheer(state, now: now)
    }

    /// 每天第一次唤醒或出现：伸个懒腰（吊着的晃一下、抱树的爬出来挥手）。
    public static func greeted(_ state: DesktopPetState, style: DesktopPetStyle, now: Date) -> DesktopPetState {
        switch state.activity {
        case .rescue, .dragged, .fileDelivery: return state
        default: break
        }
        switch style {
        case .side: return hugTapped(state, now: now)
        case .hang: return noticed(state, style: style, now: now)
        default:
            var next = state
            next.activity = .stretch(since: now)
            next.since = now
            return next
        }
    }
}
