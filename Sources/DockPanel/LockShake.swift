import SwiftUI

extension View {
    /// 锁定扩展栏时试图拖动的轻提示：沿扩展栏方向抖一下。`tick` 每变一次抖一次。
    /// 抖动的形状在 Core（`ShelfLock.shakeOffset`），两头都是 0，停下时正好回原位。
    func lockShake(_ tick: Int, vertical: Bool = false) -> some View {
        keyframeAnimator(initialValue: 0.0, trigger: tick) { view, progress in
            let distance = CGFloat(ShelfLock.shakeOffset(progress: progress))
            return view.offset(x: vertical ? 0 : distance, y: vertical ? distance : 0)
        } keyframes: { _ in
            KeyframeTrack {
                MoveKeyframe(0.0)
                LinearKeyframe(1.0, duration: ShelfLock.shakeDuration)
            }
        }
    }
}
