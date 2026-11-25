import AppKit
import QuartzCore

/// 把同一张正面 PNG 在 GPU 上复用为头部、左前爪、右前爪三个小遮罩。
///
/// 这是很轻的视觉增强，不是重新画一只小熊猫：原图永远完整留在底层，
//  局部遮罩只移动不到 2pt，避免透明缝隙或毛绒质感变化。
/// 只处理正面坐姿 lively 素材；没有图、换姿势和减弱动态效果都会关闭图层。
@MainActor
final class DesktopPetArticulatedLayers {
    private let head = CALayer()
    private let leftPaw = CALayer()
    private let rightPaw = CALayer()
    private let headMask = CAShapeLayer()
    private let leftMask = CAShapeLayer()
    private let rightMask = CAShapeLayer()

    private var lastName: String?
    private var lastSize: CGSize = .zero
    private var lastPose: DesktopPetArticulation?

    init(parent: CALayer) {
        for (part, mask) in [(head, headMask), (leftPaw, leftMask), (rightPaw, rightMask)] {
            part.contentsGravity = .resize
            part.minificationFilter = .linear
            part.magnificationFilter = .linear
            part.isHidden = true
            part.mask = mask
            mask.fillColor = NSColor.white.cgColor
            parent.addSublayer(part)
        }
    }

    func setBackingScale(_ scale: CGFloat) {
        for part in [head, leftPaw, rightPaw] { part.contentsScale = scale }
    }

    func update(name: String, image: CGImage?, size: CGSize,
                pose: DesktopPetArticulation?, contentsScale: CGFloat) {
        guard let pose, let image, name.hasPrefix("pet-sprite-lively-"),
              size.width > 0, size.height > 0 else {
            hide()
            return
        }
        if lastName == name, lastSize == size, lastPose == pose { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if lastName != name {
            for part in [head, leftPaw, rightPaw] { part.contents = image }
            lastName = name
        }
        if lastSize != size {
            layout(size)
            lastSize = size
        }
        for part in [head, leftPaw, rightPaw] { part.contentsScale = contentsScale }

        let isTurning = abs(pose.headYaw) > 0.005 || abs(pose.headPitch) > 0.005
        head.isHidden = !isTurning
        if isTurning {
            var transform = CATransform3DIdentity
            transform.m34 = -1 / 450
            transform = CATransform3DRotate(transform, CGFloat(pose.headPitch) * -.pi / 45, 1, 0, 0)
            transform = CATransform3DRotate(transform, CGFloat(pose.headYaw) * .pi / 45, 0, 1, 0)
            transform = CATransform3DTranslate(transform, CGFloat(pose.headYaw) * 0.65,
                                              CGFloat(pose.headPitch) * 0.45, 0)
            head.transform = transform
        }

        applyPaw(leftPaw, tap: pose.leftPaw, left: true)
        applyPaw(rightPaw, tap: pose.rightPaw, left: false)
        lastPose = pose
        CATransaction.commit()
    }

    private func applyPaw(_ layer: CALayer, tap: Double, left: Bool) {
        layer.isHidden = tap < 0.005
        guard !layer.isHidden else { return }
        // 前爪只抬 1.5pt 左右，左右交替，幅度随最后一次按键逐渐变小。
        let angle = CGFloat(left ? -1 : 1) * CGFloat(tap) * .pi / 110
        var transform = CATransform3DMakeRotation(angle, 0, 0, 1)
        transform = CATransform3DTranslate(transform, 0, CGFloat(tap) * 1.3, 0)
        layer.transform = transform
    }

    private func hide() {
        if lastPose == nil && head.isHidden && leftPaw.isHidden && rightPaw.isHidden { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for part in [head, leftPaw, rightPaw] { part.isHidden = true }
        lastPose = nil
        CATransaction.commit()
    }

    private func layout(_ size: CGSize) {
        let w = size.width, h = size.height
        for part in [head, leftPaw, rightPaw] {
            part.bounds = CGRect(origin: .zero, size: size)
        }

        // 头部图层包含原有耳朵、脸颊和白色眉斑。路径宽松留边，
        // 小幅运动时底图仍在下面，避免剪切空洞。
        head.anchorPoint = CGPoint(x: 0.5, y: 0.62)
        head.position = CGPoint(x: w * 0.5, y: h * 0.62)
        let silhouette = CGMutablePath()
        silhouette.addEllipse(in: CGRect(x: w * 0.055, y: h * 0.35, width: w * 0.89, height: h * 0.55))
        silhouette.addEllipse(in: CGRect(x: w * 0.07, y: h * 0.69, width: w * 0.27, height: h * 0.30))
        silhouette.addEllipse(in: CGRect(x: w * 0.66, y: h * 0.69, width: w * 0.27, height: h * 0.30))

        leftPaw.anchorPoint = CGPoint(x: 0.29, y: 0.14)
        leftPaw.position = CGPoint(x: w * 0.29, y: h * 0.14)
        rightPaw.anchorPoint = CGPoint(x: 0.71, y: 0.14)
        rightPaw.position = CGPoint(x: w * 0.71, y: h * 0.14)

        let leftShape = CGPath(ellipseIn: CGRect(x: w * 0.135, y: h * 0.01,
                                                width: w * 0.32, height: h * 0.255), transform: nil)
        let rightShape = CGPath(ellipseIn: CGRect(x: w * 0.545, y: h * 0.01,
                                                 width: w * 0.32, height: h * 0.255), transform: nil)
        for (mask, path) in [(headMask, silhouette as CGPath),
                             (leftMask, leftShape), (rightMask, rightShape)] {
            mask.frame = CGRect(origin: .zero, size: size)
            mask.path = path
        }
    }
}
