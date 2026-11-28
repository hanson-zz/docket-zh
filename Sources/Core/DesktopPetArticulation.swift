import CoreGraphics
import Foundation

/// 以已有小熊猫 PNG 为底图的微幅局部动画参数。
/// 与图片像素无关，在整个图标按比例缩放时仍然生效。
public struct DesktopPetArticulation: Equatable, Sendable {
    public let headYaw: Double
    public let headPitch: Double
    public let leftPaw: Double
    public let rightPaw: Double

    public init(headYaw: Double, headPitch: Double, leftPaw: Double, rightPaw: Double) {
        self.headYaw = headYaw
        self.headPitch = headPitch
        self.leftPaw = leftPaw
        self.rightPaw = rightPaw
    }
}

/// 只计算参数，真实遮罩和 CALayer 在 App/DesktopPetArticulatedLayers。
/// 没有匹配素材或正在拖动、睡觉、走路时，调用端直接不使用这个结果。
public enum DesktopPetArticulationLogic {
    public static let headReach: Double = 380
    public static let headFadeStart: Double = 260
    public static let typingFrequency: Double = 3.4

    /// 系统“减弱动态效果”或低电量模式下完全禁用局部 3D 变换。
    /// `headTracking` 由已有 `DesktopPetFaceState.gaze` 提供，指针静止后会归零。
    public static func pose(pointer: CGPoint?, center: CGPoint, scale: Double, headTracking: Bool,
                            typingStrength: Double, now: Date, reduceMotion: Bool,
                            lowPower: Bool, pressedMouseButtons: Int = 0,
                            mousePaws: DesktopPetMousePaws? = nil) -> DesktopPetArticulation? {
        guard !reduceMotion, !lowPower else { return nil }

        var yaw = 0.0
        var pitch = 0.0
        if headTracking, let pointer {
            let k = max(0.1, scale)
            let dx = Double(pointer.x - center.x) / k
            let dy = Double(pointer.y - center.y) / k
            if hypot(dx, dy) <= headReach {
                // 只允许极小角度变化，不能把平面 PNG 当成真正 3D 模型大幅旋转。
                // 指针越过 260pt 后平滑收回，避免从最远处突然弹回原位。
                let distance = hypot(dx, dy)
                let fade = min(1, max(0, (headReach - distance) / (headReach - headFadeStart)))
                yaw = max(-1, min(1, dx / 240)) * fade
                pitch = max(-1, min(1, dy / 240)) * fade
            }
        }

        let typing = max(0, min(1, typingStrength))
        var left = 0.0
        var right = 0.0
        if typing > 0 {
            let phase = now.timeIntervalSinceReferenceDate * 2 * Double.pi * typingFrequency
            left = max(0, sin(phase)) * typing
            right = max(0, -sin(phase)) * typing
        }

        // NSEvent.pressedMouseButtons: bit 0 = 左键、bit 1 = 右键。
        // 不引入另一套全局监听；只看当前是否按住，不记录点击地点或历史。
        left = max(left, mousePaws?.left ?? ((pressedMouseButtons & 1) != 0 ? 0.9 : 0))
        right = max(right, mousePaws?.right ?? ((pressedMouseButtons & 2) != 0 ? 0.9 : 0))

        guard abs(yaw) > 0.005 || abs(pitch) > 0.005 || left > 0.005 || right > 0.005 else {
            return nil
        }
        return DesktopPetArticulation(headYaw: yaw, headPitch: pitch, leftPaw: left, rightPaw: right)
    }
}

/// 仅由现有桌宠时钟推进；按住后停止高频更新，松手仍能平滑落爪。
public struct DesktopPetMousePaws: Equatable, Sendable {
    public private(set) var left: Double = 0
    public private(set) var right: Double = 0
    private var previous: Date?
    private var targetLeft: Double = 0
    private var targetRight: Double = 0

    public init() {}

    public var needsSmooth: Bool {
        abs(left - targetLeft) > 0.001 || abs(right - targetRight) > 0.001
    }

    public mutating func update(buttons: Int, now: Date, enabled: Bool) {
        guard enabled else { self = Self(); return }
        targetLeft = buttons & 1 != 0 ? 0.9 : 0
        targetRight = buttons & 2 != 0 ? 0.9 : 0
        let elapsed = previous.map { now.timeIntervalSince($0) } ?? 0
        previous = now
        guard elapsed.isFinite, elapsed >= 0 else {
            left = 0
            right = 0
            return
        }
        // A coalesced timer still carries freshly sampled button state. Settle
        // to that state instead of briefly dropping a held paw on every delay.
        if elapsed > 0.5 {
            left = targetLeft
            right = targetRight
            return
        }
        func advance(_ value: Double, toward target: Double) -> Double {
            let duration = target > value ? 0.06 : 0.10
            let next = target + (value - target) * exp(-elapsed / duration)
            return abs(next - target) < 0.001 ? target : next
        }
        left = advance(left, toward: targetLeft)
        right = advance(right, toward: targetRight)
    }
}
