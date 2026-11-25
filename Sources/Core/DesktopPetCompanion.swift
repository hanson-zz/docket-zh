import CoreGraphics
import Foundation

/// 桌面伙伴 2.0 的轻量输入节奏状态。只处理鼠标位置/速度和“距离上次按键过去几秒”，
/// 不建立键盘事件监听、不接收实际按键、不存储按键或鼠标轨迹。
///
/// 与 DesktopPetFace 的既有视线跟随和睡眠行为互补：本类只负责掠过触发和打字节奏。
public struct DesktopPetCompanionState: Sendable {
    /// 只有打字节奏开关开启时才会有值，保留不超过短暂动画时间。
    private var lastTypingAt: Date?
    private var previousPointer: CGPoint?
    private var previousPointerAt: Date?
    private var lastHuntAt: Date?

    public static let typingWindow: TimeInterval = 0.42
    public static let keyFreshWindow: TimeInterval = 0.18
    public static let huntCooldown: TimeInterval = 7
    public static let huntReach: Double = 240
    public static let huntSpeed: Double = 1050

    public init() {}

    public mutating func reset() { self = Self() }

    /// 按桌宠原有时钟采样（静止时约 10Hz），避免全局键盘监听和额外计时器。
    /// 返回 true 代表鼠标快速掠过小熊猫且冷却完成，可触发已有的 surprise 表情。
    /// `keyIdle` 来自 CGEventSource 的“距上次 keyDown 时间”，绝不包含按键身份或文本。
    public mutating func observe(now: Date, pointer: CGPoint?, center: CGPoint, scale: Double,
                                 keyIdle: TimeInterval?, typingEnabled: Bool, huntEnabled: Bool,
                                 reduceMotion: Bool) -> Bool {
        defer {
            previousPointer = pointer
            previousPointerAt = pointer == nil ? nil : now
        }
        if !typingEnabled || reduceMotion {
            lastTypingAt = nil
        } else if let keyIdle, keyIdle.isFinite, keyIdle >= 0, keyIdle <= Self.keyFreshWindow {
            lastTypingAt = now
        }

        guard huntEnabled, !reduceMotion, let pointer,
              let previousPointer, let previousPointerAt else { return false }
        let dt = now.timeIntervalSince(previousPointerAt)
        guard dt >= 0.025, dt <= 0.5 else { return false }
        let distance = Double(hypot(pointer.x - center.x, pointer.y - center.y))
        guard distance <= Self.huntReach * max(0.1, scale) else { return false }
        let speed = Double(hypot(pointer.x - previousPointer.x, pointer.y - previousPointer.y)) / dt
        guard speed >= Self.huntSpeed else { return false }
        if let lastHuntAt, now.timeIntervalSince(lastHuntAt) < Self.huntCooldown { return false }
        lastHuntAt = now
        return true
    }

    /// 由最新按键活动驱动短暂的呼吸/轻点头节奏，停止输入后自动衰减，不需要新的素材。
    public func typingStrength(at now: Date) -> Double {
        guard let lastTypingAt else { return 0 }
        let age = now.timeIntervalSince(lastTypingAt)
        guard age >= 0, age < Self.typingWindow else { return 0 }
        return 1 - age / Self.typingWindow
    }

    public func needsSmooth(at now: Date) -> Bool {
        typingStrength(at: now) > 0
    }

    /// 轻量动效，不改原来的 PNG、脸型、尺寸锚点，也不覆盖已有的点按/摸头表情。
    public func decorate(_ pose: DesktopPetPose, now: Date, motion: DesktopPetMotion) -> DesktopPetPose {
        guard motion == .full else { return pose }
        let strength = typingStrength(at: now)
        guard strength > 0 else { return pose }
        var result = pose
        let beat = sin(now.timeIntervalSinceReferenceDate * 21)
        result.wobble += 1.2 * strength * beat
        result.lift += 0.65 * strength * abs(beat)
        result.scaleY *= 1 - 0.012 * strength * (1 + beat) / 2
        return result
    }
}
