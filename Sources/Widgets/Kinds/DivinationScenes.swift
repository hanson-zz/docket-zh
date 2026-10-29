import AppKit
import SwiftUI

// MARK: - 卜卦 · 小熊猫姿势图和三个玩法的场景
//
// 小熊猫是 Resources/Divination 里的整身 3D 毛绒姿势图，每个动作一张（Core 的 `DivinationPose`），
// 照用户给的分解图一拍一张（Core 的 `beats`），拍与拍之间交叉淡入 0.18 秒，新图从 0.94 弹到 1，
// 锚点在脚底（每张图按 `anchorX` 把身子对在中线上，换图脚不左右跳），再加整张图的摇摆、起跳、
// 落地挤压。签筒、龟甲、书都画在图里；单独一层的只有铜钱、飞出来的签条、签纸和书页上的字、
// 书页金光和光点。层级：地面阴影 < 姿势 < 签纸字 / 书页光 < 铜钱、签条 < 光点。
// 每一刻换哪张图、各段多长都在 Core（StickShake、ShellToss、WorryBook），界面只照着画。
// 减少动态效果时不摇、不跳、不摔、不飞，姿势之间只做 0.15 秒淡入，结果直接出来。

// MARK: - 素材

/// 姿势图、签筒着色层、铜钱从包里取，按名字缓存。
@MainActor
enum DivinationArtwork {
    private static var cache: [String: NSImage] = [:]

    static func image(_ name: String) -> NSImage? {
        if let cached = cache[name] { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        cache[name] = image
        return image
    }
}

/// 一张图按给定宽高画；包里找不到时留空，不画占位色块。
struct DivinationArtImage: View {
    var name: String
    var width: CGFloat
    var height: CGFloat

    var body: some View {
        Group {
            if let image = DivinationArtwork.image(name) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
            } else {
                Color.clear
            }
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }
}

/// 一张姿势图：`height` 是这个玩法的基准高度，实际再乘 `heightScale`（小熊猫个头一致）。
/// 抱签筒的两张（摇一摇、仰头看签）按签筒皮肤盖一层筒身着色图（朱漆、青玉；默认竹不盖）。
struct DivinationPoseImage: View {
    var pose: DivinationPose
    var height: CGFloat

    @Environment(\.divinationSkin) private var skin

    var body: some View {
        let h = height * CGFloat(pose.heightScale)
        let w = h * CGFloat(pose.aspect)
        ZStack {
            DivinationArtImage(name: pose.imageName, width: w, height: h)
            if let overlay = DivinationArt.tubeOverlay(skin.tube, pose: pose) {
                DivinationArtImage(name: overlay, width: w, height: h)
            }
        }
        .frame(width: w, height: h)
        .accessibilityHidden(true)
    }
}

/// 姿势层：换图时旧图淡出、新图淡入并从 0.94 弹到 1（锚点在脚底，脚不漂）。每张图按 `anchorX`
/// 横向挪一点，小熊猫的身子总在中线上。frame 是 `height` 高、底对齐，宽留够最宽的那张。
struct DivinationPoseLayer: View {
    var pose: DivinationPose
    var height: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let widthRatio: CGFloat = 0.86

    var body: some View {
        ZStack(alignment: .bottom) {
            DivinationPoseImage(pose: pose, height: height)
                .offset(x: CGFloat(pose.centerOffset(poseHeight: Double(height))))
                .id(pose)
                .transition(transition)
        }
        .frame(width: height * Self.widthRatio, height: height, alignment: .bottom)
        .animation(.easeOut(duration: reduceMotion ? 0.15 : DivinationArt.crossFade), value: pose)
        .accessibilityHidden(true)
    }

    private var transition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(
                with: .scale(scale: 0.94, anchor: .bottom).animation(.spring(response: 0.34, dampingFraction: 0.62))),
            removal: .opacity)
    }
}

/// 脚下一团模糊椭圆阴影。
struct DivinationGroundShadow: View {
    var width: CGFloat

    var body: some View {
        Ellipse().fill(DivinationStyle.groundShade)
            .frame(width: width, height: max(4, width * 0.09))
            .blur(radius: 2.5)
            .accessibilityHidden(true)
    }
}

/// 铜钱：按皮肤取正反面图（银币、古铜绿锈是着色好的一套）。
struct DivinationCoin: View {
    /// true 是背面。
    var back: Bool
    var size: CGFloat

    @Environment(\.divinationSkin) private var skin

    var body: some View {
        DivinationArtImage(name: DivinationArt.coin(back: back, skin: skin.coin), width: size, height: size)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(back ? tr("背") : tr("字"))
    }
}

/// 金色四角星光点：`progress` 0…1 里先放大再缩没。深色外观也只用金色、透明度低一点，不用蓝光。
struct DivinationSparkles: View {
    var center: CGPoint
    var radius: CGFloat
    var progress: Double

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        // 每颗星的方向、大小、延迟在 Core（`DivinationArt.sparkleStars`），放不下时按它缩半径。
        let stars = DivinationArt.sparkleStars
        return ZStack(alignment: .topLeading) {
            ForEach(0..<stars.count, id: \.self) { i in
                let star = stars[i]
                let p = min(1, max(0, (progress - star.delay) / (1 - star.delay)))
                let s = sin(p * .pi)
                SparkleShape()
                    .fill(DivinationStyle.gold)
                    .frame(width: CGFloat(star.size), height: CGFloat(star.size))
                    .scaleEffect(s)
                    .opacity(s * (scheme == .dark ? 0.8 : 1))
                    .position(x: center.x + CGFloat(star.x) * radius, y: center.y + CGFloat(star.y) * radius)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 四角星。
struct SparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let k = r * 0.28
        var path = Path()
        path.move(to: CGPoint(x: c.x, y: c.y - r))
        path.addLine(to: CGPoint(x: c.x + k, y: c.y - k))
        path.addLine(to: CGPoint(x: c.x + r, y: c.y))
        path.addLine(to: CGPoint(x: c.x + k, y: c.y + k))
        path.addLine(to: CGPoint(x: c.x, y: c.y + r))
        path.addLine(to: CGPoint(x: c.x - k, y: c.y + k))
        path.addLine(to: CGPoint(x: c.x - r, y: c.y))
        path.addLine(to: CGPoint(x: c.x - k, y: c.y - k))
        path.closeSubpath()
        return path
    }
}

// MARK: - 每日一签

struct StickMotion {
    /// 从按下起算的秒数；不在动的时候是一个很大的数（算作 rest）。
    var t: Double = 99
    var sway: Double = 0
    /// 签蹦出来那一下小熊猫轻轻一跳（0…1）。
    var hop: Double = 0
}

/// 每日一签的场景，照分解图三拍：① 抱签筒摇一摇（整张图 ±8° 摆）→ ② 换「仰头看」图，一支签条
/// 从筒口蹦出来、飞到小熊猫头的右上方停在半空，它仰头看着 → ③ 换「展签」图，签条落进它手里、
/// 横着展开成那张签纸，签级写在纸上，冒几颗金色光点。`shakes` 每加一次走一遍；不在动时抽过就
/// 展签、没抽就抱着签筒。签纸太小（字会小于 13pt）时纸上不写字。
struct DivinationStickScene: View {
    var width: CGFloat
    var height: CGFloat
    /// 基准姿势高度（脚底贴着场景底边往上 4pt）。
    var poseHeight: CGFloat
    /// 今天的签（下标）；签蹦出来那一刻写进去。
    var index: Int?
    var shakes: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let timing = StickShake.normal
        let step = timing.shake / Double(StickShake.swayAngles.count)
        let angles = StickShake.swayAngles
        return KeyframeAnimator(initialValue: StickMotion(), trigger: reduceMotion ? 0 : shakes) { motion in
            scene(motion, timing: timing)
        } keyframes: { _ in
            KeyframeTrack(\.t) {
                LinearKeyframe(0, duration: 0.001)
                LinearKeyframe(timing.total, duration: timing.total)
                LinearKeyframe(99, duration: 0.001)
            }
            KeyframeTrack(\.sway) {
                CubicKeyframe(angles[0], duration: step)
                CubicKeyframe(angles[1], duration: step)
                CubicKeyframe(angles[2], duration: step)
                CubicKeyframe(angles[3], duration: step)
                CubicKeyframe(angles[4], duration: step)
            }
            KeyframeTrack(\.hop) {
                LinearKeyframe(0, duration: timing.flyStart)
                CubicKeyframe(1, duration: 0.1)
                CubicKeyframe(0, duration: 0.16)
            }
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }

    private var bottom: CGFloat { height - 4 }

    /// 姿势图上按比例的一点换成场景坐标（图的身子对在场景中线、底边贴着 `bottom`）。
    private func point(_ pose: DivinationPose, _ fx: Double, _ fy: Double) -> CGPoint {
        let p = pose.scenePoint(fx, fy, poseHeight: Double(poseHeight), centerX: Double(width / 2),
                                bottom: Double(bottom))
        return CGPoint(x: p.x, y: p.y)
    }

    private func scene(_ m: StickMotion, timing: StickShake) -> some View {
        let t = reduceMotion ? 99 : m.t
        let phase = timing.phase(at: t)
        let pose = timing.pose(at: t, drawn: index != nil)
        let slip = DivinationArt.slipRect
        let slipTop = point(.qianRead, slip.x, slip.y)
        let slipEnd = point(.qianRead, slip.x + slip.width, slip.y + slip.height)
        let slipCenter = CGPoint(x: (slipTop.x + slipEnd.x) / 2, y: (slipTop.y + slipEnd.y) / 2)
        return ZStack(alignment: .topLeading) {
            DivinationGroundShadow(width: poseHeight * 0.6 * (1 - 0.15 * CGFloat(m.hop)))
                .position(x: width / 2, y: bottom)
                .zIndex(0)
            DivinationPoseLayer(pose: pose, height: poseHeight)
                .rotationEffect(.degrees(phase == .shake ? m.sway : 0), anchor: .bottom)
                .offset(y: -4 * CGFloat(m.hop))
                .position(x: width / 2, y: bottom - poseHeight / 2)
                .zIndex(1)
            if pose == .qianRead, let index,
               let font = DivinationArt.slipFont(slipHeight: Double(slipEnd.y - slipTop.y)) {
                Text(verbatim: FortuneStick.all[index].level.title)
                    .font(.custom("Songti SC", size: CGFloat(font)).weight(.heavy))
                    .foregroundStyle(Color(hex: DivinationArt.slipLevelInkHex))
                    .lineLimit(1)
                    .fixedSize()
                    .opacity(timing.slipTextOpacity(at: t))
                    .position(slipCenter)
                    .zIndex(2)
            }
            if let stage = timing.slipStage(at: t) {
                flyingSlip(stage)
                    .zIndex(3)
            }
            if phase == .read, t >= timing.caught {
                DivinationSparkles(center: slipCenter, radius: poseHeight * 0.36,
                                   progress: (t - timing.caught) / (timing.total - timing.caught))
                    .zIndex(4)
            }
        }
        .frame(width: width, height: height)
    }

    /// 飞出来的签条：② 从筒口转着蹦到半空、停在那里轻轻浮着 → ③ 走低路线落进小熊猫手里：先在它
    /// 右边竖着往下落到脸下面，再横着滑进手里、展开成签纸那么大（Core 的 `StickShake.landFrame`，
    /// 不从脸前面过），滑的时候字淡掉，落定时和图里的签纸叠在一起淡掉（纸上的字接着写出来）。
    private func flyingSlip(_ stage: StickShake.SlipStage) -> some View {
        let mouth = point(.qianLook, DivinationArt.tubeMouth.x, DivinationArt.tubeMouth.y)
        let hoverPoint = DivinationArt.hoverCenter(sceneWidth: Double(width), sceneHeight: Double(height),
                                                   poseHeight: Double(poseHeight))
        let hover = CGPoint(x: hoverPoint.x, y: hoverPoint.y)
        let h = CGFloat(DivinationArt.flyingSlipHeight(poseHeight: Double(poseHeight)))
        let w = h * CGFloat(DivinationArt.flyingSlipAspect)
        var position = hover, angle = 0.0, size = CGSize(width: w, height: h), scale: CGFloat = 1
        var opacity = 1.0, textOpacity = 1.0
        switch stage {
        case .pop(let q):
            // 先快后慢往上蹦，转一圈半停正。
            let e = CGFloat(1 - (1 - q) * (1 - q))
            let control = CGPoint(x: (mouth.x + hover.x) / 2, y: max(h / 2, min(mouth.y, hover.y) - h * 0.7))
            position = CGPoint(x: (1 - e) * (1 - e) * mouth.x + 2 * (1 - e) * e * control.x + e * e * hover.x,
                               y: (1 - e) * (1 - e) * mouth.y + 2 * (1 - e) * e * control.y + e * e * hover.y)
            angle = Double(1 - e) * -540
            scale = 0.55 + 0.45 * e
            opacity = min(1, q / 0.12)
        case .hover(let q):
            position = CGPoint(x: hover.x, y: hover.y - 2.5 * CGFloat(sin(q * .pi)))
            angle = sin(q * 2 * .pi) * 4
        case .land(let q):
            let frame = StickShake.landFrame(q, sceneWidth: Double(width), sceneHeight: Double(height),
                                             poseHeight: Double(poseHeight))
            position = CGPoint(x: frame.x, y: frame.y)
            size = CGSize(width: frame.width, height: frame.height)
            textOpacity = min(1, max(0, 1 - (q - StickShake.dropFraction) / 0.25))
            opacity = q < 0.75 ? 1 : (1 - q) / 0.25
        }
        let level = index.map { FortuneStick.all[$0].level.title } ?? "签"
        return FlyingSlip(text: level, width: size.width, height: size.height, textOpacity: textOpacity)
            .scaleEffect(scale)
            .rotationEffect(.degrees(angle))
            .opacity(opacity)
            .position(position)
    }
}

/// 飞出来的签条：米白纸、红签头、朱红细框，签级竖着写（纸太小写不下 13pt 的字就不写）。
/// 落进手里时宽高一起变，横着展开成签纸。
struct FlyingSlip: View {
    var text: String
    var width: CGFloat
    var height: CGFloat
    var textOpacity: Double = 1

    var body: some View {
        let perChar = (height * 0.84) / CGFloat(max(1, text.count))
        let font = min(perChar, width - 2).rounded(.down)
        let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)
        ZStack(alignment: .top) {
            shape.fill(Color(hex: DivinationArt.slipPaperHex))
            Rectangle().fill(DivinationStyle.stickTip).frame(height: max(2, min(height, width) * 0.12))
            if font >= CGFloat(Divination.minimumFont), textOpacity > 0 {
                VStack(spacing: 0) {
                    ForEach(Array(text.enumerated()), id: \.offset) { _, ch in
                        Text(verbatim: String(ch))
                            .font(.custom("Songti SC", size: font).weight(.heavy))
                            .foregroundStyle(Color(hex: DivinationArt.slipLevelInkHex))
                            .frame(height: perChar * 0.98)
                    }
                }
                .padding(.top, height * 0.1)
                .fixedSize()
                .opacity(textOpacity)
            }
        }
        .frame(width: max(1, width), height: max(1, height))
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color(hex: DivinationArt.slipLevelInkHex), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        .accessibilityHidden(true)
    }
}

// MARK: - 起卦

struct TossMotion {
    var t: Double = 99
    /// ① 捧着往上轻轻一托（0…1）。
    var hold: Double = 0
    var sway: Double = 0
    /// 起跳前蹲、腾空（0…1，一摔那下按重力落回 0）。
    var crouch: Double = 0
    var jump: Double = 0
    /// 一摔触地的压扁回弹。
    var squash: Double = 0
    /// 抱回龟甲那一下的落地挤压。
    var land: Double = 0
    var dust: Double = 0
    /// 三枚铜钱：-1 在壳里看不见，0…1 在空中，1…2 落地弹两下，2 停住。
    var coin0: Double = 2
    var coin1: Double = 2
    var coin2: Double = 2
}

/// 起卦场景：`throwCount` 每加一次按 Core 的 `ShellToss` 照分解图走一遍：
/// ① 双手捧古龟甲轻轻一托 → ② 捧着左右摇（整张图 ±8° 摆）→ ③ 蹲一下、跳起来把龟甲举过头顶，
/// 在最高处停一下 → ③ 一摔：换「一摔」图越落越快落回地面，蹲着把龟甲扣在面前（触地压扁回弹、
/// 扬起一点土），三枚铜钱按落地声的间隔从壳口依次蹦出，抛物线落到小熊猫前面那排，翻着转（按纵向
/// 压缩换正反面），弹两下停住 → ④ 把龟甲抱回来，铜钱留在地上显示这一爻。
/// 面板用 `ShellToss.panelLayout`（内容宽，小熊猫在中线、铜钱在脚前错落一排）；桌面卡片中号、
/// 大号用 `DesktopCardsDivinationPlan.castLayout`（同样几拍和时长，按卡片缩小，小熊猫靠左、铜钱
/// 在它右边排成一排小号的，捡回以后留在地上显示这一爻）。
/// 减少动态效果时不动，铜钱直接躺在地上。
struct ShellTossScene: View {
    var layout: ShellToss.Layout = ShellToss.panelLayout
    /// 最近一爻三枚铜钱的正反（true 是背）；还没摇过是 nil，铜钱淡淡地摆着。
    var faces: [Bool]?
    var throwCount: Int
    var fast: Bool
    /// 起过卦（不在动时抱着龟甲笑；没起过双手捧着）。
    var tossed: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var width: CGFloat { CGFloat(layout.sceneWidth) }
    private var height: CGFloat { CGFloat(layout.sceneHeight) }
    private var poseHeight: CGFloat { CGFloat(layout.poseHeight) }
    private var coin: CGFloat { CGFloat(layout.coin) }
    private var foot: CGFloat { CGFloat(layout.footY) }
    private var pandaX: CGFloat { CGFloat(layout.pandaX) }
    private var scale: CGFloat { CGFloat(layout.scale) }

    var body: some View {
        let toss = ShellToss.timing(fast: fast)
        return KeyframeAnimator(initialValue: TossMotion(), trigger: reduceMotion ? 0 : throwCount) { motion in
            scene(motion, toss: toss)
        } keyframes: { _ in
            let t = toss
            let step = t.shake / Double(StickShake.swayAngles.count)
            let angles = StickShake.swayAngles
            KeyframeTrack(\.t) {
                LinearKeyframe(0, duration: 0.001)
                LinearKeyframe(t.total, duration: t.total)
                LinearKeyframe(99, duration: 0.001)
            }
            KeyframeTrack(\.hold) {
                CubicKeyframe(1, duration: t.hold * 0.45)
                CubicKeyframe(0, duration: t.hold * 0.45)
            }
            KeyframeTrack(\.sway) {
                LinearKeyframe(0, duration: t.shakeStart)
                CubicKeyframe(angles[0], duration: step)
                CubicKeyframe(angles[1], duration: step)
                CubicKeyframe(angles[2], duration: step)
                CubicKeyframe(angles[3], duration: step)
                CubicKeyframe(angles[4], duration: step)
            }
            KeyframeTrack(\.crouch) {
                LinearKeyframe(0, duration: t.liftStart)
                CubicKeyframe(1, duration: t.crouch)
                CubicKeyframe(0, duration: t.crouch)
            }
            // 跳起来停在最高处，一摔时按重力越落越快回到地面。
            KeyframeTrack(\.jump) {
                LinearKeyframe(0, duration: t.liftStart + t.crouch)
                CubicKeyframe(1, duration: t.rise)
                LinearKeyframe(1, duration: max(0.001, t.lift - t.crouch - t.rise))
                LinearKeyframe(0.75, duration: t.fall * 0.5)
                LinearKeyframe(0.4375, duration: t.fall * 0.25)
                LinearKeyframe(0, duration: t.fall * 0.25)
            }
            KeyframeTrack(\.squash) {
                LinearKeyframe(0, duration: t.impact)
                LinearKeyframe(1, duration: 0.05)
                CubicKeyframe(-0.35, duration: (t.squash - 0.05) / 2)
                CubicKeyframe(0, duration: (t.squash - 0.05) / 2)
            }
            KeyframeTrack(\.land) {
                LinearKeyframe(0, duration: t.pickupStart)
                LinearKeyframe(1, duration: 0.001)
                SpringKeyframe(0, duration: t.pickup, spring: .init(response: 0.34, dampingRatio: 0.62))
            }
            KeyframeTrack(\.dust) {
                LinearKeyframe(0, duration: t.impact)
                LinearKeyframe(0.02, duration: 0.001)
                LinearKeyframe(1, duration: 0.45)
                LinearKeyframe(0, duration: 0.001)
            }
            KeyframeTrack(\.coin0) {
                LinearKeyframe(-1, duration: 0.001)
                LinearKeyframe(-1, duration: t.popStart(0) - 0.001)
                LinearKeyframe(0, duration: 0.001)
                LinearKeyframe(1, duration: t.flight)
                LinearKeyframe(2, duration: t.bounce)
            }
            KeyframeTrack(\.coin1) {
                LinearKeyframe(-1, duration: 0.001)
                LinearKeyframe(-1, duration: t.popStart(1) - 0.001)
                LinearKeyframe(0, duration: 0.001)
                LinearKeyframe(1, duration: t.flight)
                LinearKeyframe(2, duration: t.bounce)
            }
            KeyframeTrack(\.coin2) {
                LinearKeyframe(-1, duration: 0.001)
                LinearKeyframe(-1, duration: t.popStart(2) - 0.001)
                LinearKeyframe(0, duration: 0.001)
                LinearKeyframe(1, duration: t.flight)
                LinearKeyframe(2, duration: t.bounce)
            }
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }

    private func landing(_ i: Int) -> CGPoint {
        let spot = layout.landing(i)
        return CGPoint(x: CGFloat(spot.x), y: CGFloat(spot.y))
    }

    private func slamPoint(_ fx: Double, _ fy: Double) -> CGPoint {
        let p = DivinationPose.castSlam.scenePoint(fx, fy, poseHeight: Double(poseHeight), centerX: layout.pandaX,
                                                   bottom: Double(foot))
        return CGPoint(x: p.x, y: p.y)
    }

    private func scene(_ m: TossMotion, toss: ShellToss) -> some View {
        let t = reduceMotion ? 99 : m.t
        let phase = toss.phase(at: t)
        let pose = toss.pose(at: t, tossed: tossed)
        let crouch = CGFloat(m.crouch), jump = CGFloat(m.jump), land = CGFloat(m.land), squash = CGFloat(m.squash)
        let sx = (1 + 0.05 * crouch) * (1 - 0.04 * jump) * (1 + 0.06 * land) * (1 + 0.06 * squash)
        let sy = (1 - 0.08 * crouch) * (1 + 0.06 * jump) * (1 - 0.1 * land) * (1 - 0.08 * squash)
        let lift = CGFloat(layout.jumpHeight) * jump + CGFloat(layout.holdLift) * CGFloat(m.hold)
        let center = layout.coinsCenter
        let sparkleCenter = CGPoint(x: CGFloat(center.x), y: CGFloat(center.y) - coin * 0.4)
        let sparkleRadius = DivinationArt.sparkleRadius(center: (Double(sparkleCenter.x), Double(sparkleCenter.y)),
                                                        preferred: Double(coin) * 2.6, width: layout.sceneWidth,
                                                        height: layout.sceneHeight)
        return ZStack(alignment: .topLeading) {
            DivinationGroundShadow(width: poseHeight * 0.58 * (1 - 0.35 * jump))
                .opacity(Double(1 - 0.5 * jump))
                .position(x: pandaX, y: foot)
                .zIndex(0)
            DivinationPoseLayer(pose: pose, height: poseHeight)
                .scaleEffect(x: sx, y: sy, anchor: .bottom)
                .rotationEffect(.degrees(phase == .shake ? m.sway : 0), anchor: .bottom)
                .offset(y: -lift)
                .position(x: pandaX, y: foot - poseHeight / 2)
                .zIndex(1)
            if m.dust > 0.01, m.dust < 0.99 { dust(m.dust).zIndex(2) }
            ForEach(0..<3, id: \.self) { i in
                coinView(i, reduceMotion ? 2 : [m.coin0, m.coin1, m.coin2][i])
            }
            .zIndex(3)
            if !reduceMotion, m.t >= toss.settled, m.t < toss.settled + 0.5 {
                DivinationSparkles(center: sparkleCenter, radius: CGFloat(sparkleRadius),
                                   progress: (m.t - toss.settled) / 0.5)
                    .zIndex(4)
            }
        }
        .frame(width: width, height: height)
    }

    /// 龟甲扣地扬起的土：从着地点往两边各散六粒、变淡（散开的距离按小熊猫大小缩，收在场景里）。
    private func dust(_ p: Double) -> some View {
        let spread = CGFloat(p)
        let contact = slamPoint(DivinationArt.slamContactX, 1)
        let size = DivinationPose.castSlam.displaySize(poseHeight: Double(poseHeight))
        let half = CGFloat(size.width * DivinationArt.slamShellWidth / 2)
        return ZStack(alignment: .topLeading) {
            ForEach(0..<12, id: \.self) { k in
                let side: CGFloat = k < 6 ? -1 : 1
                let j = CGFloat(k % 6)
                let x = min(width - 2, max(2, contact.x + side * (half + 2 * scale + j * 5 * scale * (0.4 + spread))))
                let y = foot - 2 * scale - (CGFloat((k * 7) % 5) + j * 0.6) * scale * (0.3 + spread)
                Circle().fill(DivinationStyle.dust)
                    .frame(width: 2.4 + CGFloat(k % 3) * 0.8, height: 2.4 + CGFloat(k % 3) * 0.8)
                    .opacity((1 - p) * (0.75 - Double(j) * 0.08))
                    .position(x: x, y: y)
            }
        }
    }

    /// 铜钱此刻的位置、翻面角度（绕横轴，按纵向压缩画）和平面里转的角度。
    private func coinPose(_ i: Int, _ p: Double) -> (position: CGPoint, flip: Double, spin: Double) {
        let land = landing(i)
        if p < 1 {
            // 从「一摔」图的壳口蹦出来，三枚错开一点。
            let base = slamPoint(DivinationArt.slamMouth.x, DivinationArt.slamMouth.y)
            let mouth = CGPoint(x: base.x + CGFloat(i - 1) * CGFloat(layout.mouthSpread), y: base.y)
            let arc = CGFloat(layout.coinArc(i))
            let t = CGFloat(max(0, p))
            let position = CGPoint(x: mouth.x + (land.x - mouth.x) * t,
                                   y: mouth.y + (land.y - mouth.y) * t - arc * 4 * t * (1 - t))
            return (position, Double(1 - t) * 540 * (i == 1 ? -1 : 1), Double(1 - t) * 160 * (i == 2 ? -1 : 1))
        }
        let b = min(1, p - 1)
        let hop = b < 0.55 ? sin(b / 0.55 * .pi) * 0.3 : sin((b - 0.55) / 0.45 * .pi) * 0.09
        return (CGPoint(x: land.x, y: land.y - CGFloat(hop) * coin), sin(b * .pi * 3) * (1 - b) * 25, 0)
    }

    private func coinView(_ i: Int, _ p: Double) -> some View {
        let pose = coinPose(i, p)
        let result = faces.map { $0[i] } ?? (i != 1)
        let cosine = cos(pose.flip * .pi / 180)
        // 翻过去（cos < 0）时看到的是另一面；落定时角度回到 0，正好是这一爻的正反。
        let face = cosine >= 0 ? result : !result
        let shown = p >= 0
        let rest = landing(i)
        return ZStack(alignment: .topLeading) {
            Ellipse().fill(DivinationStyle.groundShade)
                .frame(width: coin * 0.8, height: max(2.5, coin / 6))
                .blur(radius: 1.2)
                .opacity(shown ? min(1, max(0.25, p)) : 0)
                .position(x: pose.position.x, y: rest.y + coin * 0.42)
            DivinationCoin(back: face, size: coin)
                .scaleEffect(x: 1, y: max(0.08, CGFloat(abs(cosine))))
                .rotationEffect(.degrees(pose.spin))
                .opacity(shown ? (faces == nil ? 0.55 : 1) : 0)
                .position(pose.position)
        }
    }
}

// MARK: - 解忧书

struct BookMotion {
    var t: Double = 99
    var hop: Double = 0
}

/// 解忧书场景（面板，内容宽）：上面小熊猫，下面答案。`flips` 每加一次照分解图三拍：① 合掌默想 →
/// ② 双手捧书翻开（轻轻一弹）→ ③ 换成书页正对着看的图，书页泛暖金光、页上从右往左淡淡写出几列
/// 小字、冒几颗光点，书下的答案大字逐行淡入。
/// 封面深色外观藏蓝、浅色朱红。答案用宋体写在书下面（按 WorryBook.layout 一到两行，17 到 22pt），
/// 页码 13pt；没翻过时写「想好了，就翻开看看」。减少动态效果时不弹不闪，直接换图出字。
struct WorryBookScene: View {
    var width: CGFloat
    /// 翻到的答案（页下标）；还没翻过是 nil。
    var index: Int?
    var flips: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @Environment(\.panelForcedDark) private var forcedDark

    static let heroHeight: CGFloat = 214
    static let poseHeight: CGFloat = 206
    static let answerHeight: CGFloat = 90
    static var height: CGFloat { heroHeight + 6 + answerHeight }

    private var dark: Bool { scheme == .dark || forcedDark }

    var body: some View {
        KeyframeAnimator(initialValue: BookMotion(), trigger: reduceMotion ? 0 : flips) { motion in
            scene(motion)
        } keyframes: { _ in
            KeyframeTrack(\.t) {
                LinearKeyframe(0, duration: 0.001)
                LinearKeyframe(WorryBook.flipDuration, duration: WorryBook.flipDuration)
                LinearKeyframe(99, duration: 0.001)
            }
            KeyframeTrack(\.hop) {
                LinearKeyframe(0, duration: WorryBook.wishHold)
                CubicKeyframe(1, duration: 0.12)
                CubicKeyframe(0, duration: 0.22)
            }
        }
        .frame(width: width, height: Self.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
    }

    private var accessibility: String {
        guard let index else { return tr("想好了，就翻开看看") }
        return WorryBook.answers[index] + "，" + tr("第 \(index + 1) 页")
    }

    private func scene(_ m: BookMotion) -> some View {
        let t = reduceMotion ? 99 : m.t
        let phase = WorryBook.phase(at: t)
        let pose = WorryBook.pose(at: t, answered: index != nil, dark: dark)
        let answerPose = DivinationPose.bookAnswer(dark: dark)
        let bottom = Self.heroHeight - 4
        let h = Self.poseHeight
        let pages = pageRect(width: width, bottom: bottom)
        let center = CGPoint(x: pages.midX, y: pages.midY)
        let glow: Double = {
            guard pose == answerPose else { return 0 }
            let full = dark ? 0.45 : 0.7
            if phase == .answer { return full * min(1, (t - WorryBook.flipSwap) / 0.3) }
            return full
        }()
        return VStack(spacing: 6) {
            ZStack(alignment: .topLeading) {
                RadialGradient(colors: [Color(hex: "#FFD682").opacity(glow), Color(hex: "#FFD682").opacity(0)],
                               center: .center, startRadius: 0, endRadius: h * 0.42)
                    .frame(width: h * 0.95, height: h * 0.7)
                    .position(center)
                    .allowsHitTesting(false)
                    .zIndex(0)
                DivinationGroundShadow(width: h * 0.55)
                    .position(x: width / 2, y: bottom)
                    .zIndex(0)
                DivinationPoseLayer(pose: pose, height: h)
                    .offset(y: -6 * CGFloat(m.hop))
                    .position(x: width / 2, y: bottom - h / 2)
                    .zIndex(1)
                if pose == answerPose, index != nil {
                    pageGlowAndInk(pages, glow: glow, t: t)
                        .zIndex(2)
                }
                if phase == .answer, !reduceMotion {
                    DivinationSparkles(center: center, radius: h * 0.34,
                                       progress: (t - WorryBook.flipSwap) / (WorryBook.flipDuration - WorryBook.flipSwap))
                        .zIndex(4)
                }
            }
            .frame(width: width, height: Self.heroHeight)
            answer(t: t, phase: phase)
                .frame(width: width, height: Self.answerHeight)
        }
    }

    /// 答案图上两页书在场景里的位置。
    private func pageRect(width: CGFloat, bottom: CGFloat) -> CGRect {
        let pose = DivinationPose.bookAnswer(dark: dark)
        let r = DivinationArt.bookPageRect
        let h = Double(Self.poseHeight), cx = Double(width / 2), b = Double(bottom)
        let a = pose.scenePoint(r.x, r.y, poseHeight: h, centerX: cx, bottom: b)
        let z = pose.scenePoint(r.x + r.width, r.y + r.height, poseHeight: h, centerX: cx, bottom: b)
        return CGRect(x: a.x, y: a.y, width: z.x - a.x, height: z.y - a.y)
    }

    /// 书页上的暖金光，和从右往左一列列淡淡写出来的小字（竖排短笔画，只是意思，答案写在书下面）。
    /// 书页是图里的米白纸，浅色深色外观里一样，墨色固定。
    private func pageGlowAndInk(_ pages: CGRect, glow: Double, t: Double) -> some View {
        let perPage = DivinationArt.bookInkColumns
        let count = perPage * 2
        let spine = pages.minX + pages.width * CGFloat((DivinationArt.bookSpineX - DivinationArt.bookPageRect.x)
            / DivinationArt.bookPageRect.width)
        let pageWidths = [spine - pages.minX, pages.maxX - spine]
        return ZStack(alignment: .topLeading) {
            // 椭圆、羽化，不在纸面上留出方框边。
            Ellipse()
                .fill(RadialGradient(colors: [Color(hex: "#FFE3A0").opacity(glow * 0.55), Color(hex: "#FFE3A0").opacity(0)],
                                     center: .center, startRadius: 0, endRadius: pages.width * 0.5))
                .frame(width: pages.width * 0.9, height: pages.height * 0.8)
                .blur(radius: 4)
                .position(x: pages.midX, y: pages.midY)
            ForEach(0..<count, id: \.self) { k in
                let page = k / perPage
                let slot = k % perPage
                let left = page == 0 ? pages.minX : spine
                let margin = pageWidths[page] * 0.18
                let x = left + margin + (pageWidths[page] - margin * 2) * (CGFloat(slot) + 0.5) / CGFloat(perPage)
                inkColumn(seed: k, height: pages.height * 0.62)
                    .opacity(WorryBook.inkOpacity(k, of: count, at: t))
                    .position(x: x, y: pages.minY + pages.height * 0.48)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 一列淡墨：三四笔长短不一的竖笔画。
    private func inkColumn(seed: Int, height: CGFloat) -> some View {
        let strokes = 3 + seed % 2
        let unit = height / CGFloat(strokes)
        return VStack(spacing: unit * 0.28) {
            ForEach(0..<strokes, id: \.self) { j in
                Capsule()
                    .fill(Color(hex: "#5A4632").opacity(0.5))
                    .frame(width: 2.2, height: unit * (0.5 + CGFloat((seed * 5 + j * 3) % 4) * 0.08))
            }
        }
        .frame(height: height, alignment: .top)
    }

    /// 答案（宋体，一到两行，最后一行用强调红）和页码；没翻过时是提示语。翻页时旧答案先藏起来，
    /// 换成答案图以后新答案逐行淡入。
    @ViewBuilder private func answer(t: Double, phase: WorryBook.Phase) -> some View {
        if let index {
            let layout = WorryBook.layout(WorryBook.answers[index])
            VStack(spacing: 4) {
                ForEach(Array(layout.lines.enumerated()), id: \.offset) { i, line in
                    Text(verbatim: line)
                        .font(.custom("Songti SC", size: CGFloat(layout.font)).weight(.semibold))
                        .foregroundStyle(i == layout.lines.count - 1 && layout.lines.count > 1
                                         ? DivinationStyle.red : Color.panelPrimary)
                        .lineLimit(1)
                        .fixedSize()
                        .opacity(WorryBook.lineOpacity(i, at: t))
                }
                Text(tr("第 \(index + 1) 页"))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.panelSecondary)
                    .lineLimit(1)
                    .fixedSize()
                    .opacity(WorryBook.lineOpacity(layout.lines.count - 1, at: t))
            }
        } else {
            Text(tr("想好了，就翻开看看"))
                .font(.custom("Songti SC", size: 17).weight(.semibold))
                .foregroundStyle(Color.panelSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: CGFloat(WorryBook.spreadTextWidth))
                .fixedSize(horizontal: false, vertical: true)
                .opacity(phase == .rest ? 1 : 0)
        }
    }
}
