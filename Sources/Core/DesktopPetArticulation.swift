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
    public static let typingFrequency: Double = 3.4

    /// 系统“减弱动态效果”或低电量模式下完全禁用局部 3D 变换。
    /// `headTracking` 由已有 `DesktopPetFaceState.gaze` 提供，指针静止后会归零。
    public static func pose(pointer: CGPoint?, center: CGPoint, scale: Double, headTracking: Bool,
                            typingStrength: Double, now: Date, reduceMotion: Bool,
                            lowPower: Bool) -> DesktopPetArticulation? {
        guard !reduceMotion, !lowPower else { return nil }

        var yaw = 0.0
        var pitch = 0.0
        if headTracking, let pointer {
            let k = max(0.1, scale)
            let dx = Double(pointer.x - center.x) / k
            let dy = Double(pointer.y - center.y) / k
            if hypot(dx, dy) <= headReach {
                // 只允许极小角度变化，不能把平面 PNG 当成真正 3D 模型大幅旋转。
                yaw = max(-1, min(1, dx / 240))
                pitch = max(-1, min(1, dy / 240))
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

        guard abs(yaw) > 0.005 || abs(pitch) > 0.005 || left > 0.005 || right > 0.005 else {
            return nil
        }
        return DesktopPetArticulation(headYaw: yaw, headPitch: pitch, leftPaw: left, rightPaw: right)
    }
}
