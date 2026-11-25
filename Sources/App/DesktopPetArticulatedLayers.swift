import AppKit
import QuartzCore

/// 小熊猫正面 PNG 的轻量局部动画。
/// 底图通过 even-odd 遮罩挖掉当前正在运动的区域，三个局部图层再把原图相同像素画回。
/// 这样运动时不会把头和前爪重复画在完整图片上；不运动时直接显示原图。
@MainActor
final class DesktopPetArticulatedLayers {
    private let base = CALayer()
    private let baseMask = CAShapeLayer()
    private let head = CALayer()
    private let leftPaw = CALayer()
    private let rightPaw = CALayer()
    private let headMask = CAShapeLayer()
    private let leftMask = CAShapeLayer()
    private let rightMask = CAShapeLayer()

    private var headPath: CGPath?
    private var leftPath: CGPath?
    private var rightPath: CGPath?
    private var maskedParts: (head: Bool, left: Bool, right: Bool)?
    private var lastName: String?
    private var lastSize: CGSize = .zero
    private var lastPose: DesktopPetArticulation?

    init(parent: CALayer) {
        base.contentsGravity = .resize
        base.minificationFilter = .linear
        base.magnificationFilter = .linear
        baseMask.fillColor = NSColor.white.cgColor
        baseMask.fillRule = .evenOdd
        parent.addSublayer(base)

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
        for part in [base, head, leftPaw, rightPaw] { part.contentsScale = scale }
        for mask in [baseMask, headMask, leftMask, rightMask] { mask.contentsScale = scale }
    }

    /// `image` 始终传入完整 PNG，不论有没有局部动作。
    /// 动画停下或素材缺失时，原底图继续可见，不留下空洞。
    func update(name: String, image: CGImage?, size: CGSize,
                pose: DesktopPetArticulation?, contentsScale: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        if let image, name != lastName {
            base.contents = image
            for part in [head, leftPaw, rightPaw] { part.contents = image }
            lastName = name
            lastPose = nil
        }
        guard lastName != nil, size.width > 0, size.height > 0 else {
            hide()
            return
        }
        if lastSize != size {
            // 尺寸发生变化时，必须重建挖空路径；上一帧的姿态缓存不能沿用。
            base.mask = nil
            layout(size)
            lastSize = size
            maskedParts = nil
            lastPose = nil
        }
        setBackingScale(contentsScale)

        guard let pose, name.hasPrefix("pet-sprite-lively-"), image != nil else {
            hide()
            return
        }
        if lastPose == pose { return }

        let movingHead = abs(pose.headYaw) > 0.005 || abs(pose.headPitch) > 0.005
        let movingLeft = pose.leftPaw > 0.005
        let movingRight = pose.rightPaw > 0.005
        updateKnockout(head: movingHead, left: movingLeft, right: movingRight)

        head.isHidden = !movingHead
        if movingHead {
            var transform = CATransform3DIdentity
            transform.m34 = -1 / 500
            transform = CATransform3DRotate(transform, CGFloat(pose.headPitch) * -.pi / 80, 1, 0, 0)
            transform = CATransform3DRotate(transform, CGFloat(pose.headYaw) * .pi / 80, 0, 1, 0)
            transform = CATransform3DTranslate(transform, CGFloat(pose.headYaw) * 0.35,
                                              CGFloat(pose.headPitch) * 0.3, 0)
            head.transform = transform
        }
        applyPaw(leftPaw, tap: pose.leftPaw, left: true)
        applyPaw(rightPaw, tap: pose.rightPaw, left: false)
        lastPose = pose
    }

    private func updateKnockout(head: Bool, left: Bool, right: Bool) {
        if let previous = maskedParts, previous.head == head,
           previous.left == left, previous.right == right { return }
        maskedParts = (head, left, right)
        guard head || left || right else {
            base.mask = nil
            return
        }
        // 使用与活动层完全一致的裁切路径；when off -> mask=nil，底图是原始 PNG。
        let shape = CGMutablePath()
        shape.addRect(CGRect(origin: .zero, size: lastSize))
        if head, let headPath { shape.addPath(headPath) }
        if left, let leftPath { shape.addPath(leftPath) }
        if right, let rightPath { shape.addPath(rightPath) }
        baseMask.frame = CGRect(origin: .zero, size: lastSize)
        baseMask.path = shape
        base.mask = baseMask
    }

    private func applyPaw(_ layer: CALayer, tap: Double, left: Bool) {
        layer.isHidden = tap < 0.005
        guard !layer.isHidden else { return }
        let angle = CGFloat(left ? -1 : 1) * CGFloat(tap) * .pi / 160
        var transform = CATransform3DMakeRotation(angle, 0, 0, 1)
        transform = CATransform3DTranslate(transform, 0, CGFloat(tap) * 1.0, 0)
        layer.transform = transform
    }

    private func hide() {
        if lastPose == nil && maskedParts == nil { return }
        for part in [head, leftPaw, rightPaw] { part.isHidden = true }
        base.mask = nil
        maskedParts = nil
        lastPose = nil
    }

    private func layout(_ size: CGSize) {
        let w = size.width, h = size.height
        base.frame = CGRect(origin: .zero, size: size)
        for part in [head, leftPaw, rightPaw] {
            part.bounds = CGRect(origin: .zero, size: size)
        }
        head.anchorPoint = CGPoint(x: 0.5, y: 0.62)
        head.position = CGPoint(x: w * 0.5, y: h * 0.62)

        // 采用一个连续的头部区域，避免 even-odd 规则把重叠耳朵误挖回来。
        // 轻微移动时有原始 PNG 作为像素来源，不会重绘脸部细节。
        headPath = CGPath(roundedRect: CGRect(x: w * 0.02, y: h * 0.33,
                                               width: w * 0.96, height: h * 0.665),
                          cornerWidth: w * 0.17, cornerHeight: h * 0.15, transform: nil)

        leftPaw.anchorPoint = CGPoint(x: 0.29, y: 0.14)
        leftPaw.position = CGPoint(x: w * 0.29, y: h * 0.14)
        rightPaw.anchorPoint = CGPoint(x: 0.71, y: 0.14)
        rightPaw.position = CGPoint(x: w * 0.71, y: h * 0.14)
        leftPath = CGPath(ellipseIn: CGRect(x: w * 0.135, y: h * 0.01,
                                           width: w * 0.32, height: h * 0.255), transform: nil)
        rightPath = CGPath(ellipseIn: CGRect(x: w * 0.545, y: h * 0.01,
                                            width: w * 0.32, height: h * 0.255), transform: nil)
        for (mask, path) in [(headMask, headPath), (leftMask, leftPath), (rightMask, rightPath)] {
            mask.frame = CGRect(origin: .zero, size: size)
            mask.path = path
        }
    }
}
