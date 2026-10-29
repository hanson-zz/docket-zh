import AppKit
import SwiftUI

// MARK: - 卜卦 · 小熊猫姿势图和三个玩法的场景
//
// 小熊猫是 Resources/Divination 里的整身 3D 毛绒姿势图，每个动作一张（Core 的 `DivinationPose`），
// 动画就是在姿势之间交叉淡入（0.18 秒，新图从 0.94 弹到 1，锚点在脚底），再加整张图的摇摆、
// 起跳、落地挤压。签筒、龟甲、书都画在图里；单独一层的只有扣在地上的龟甲、铜钱、飞出来的签条、
// 签纸上的字和金色光点。层级：地面阴影 < 姿势 < 扣地龟甲 < 铜钱 < 光点。
// 每一刻换哪张图、各段多长都在 Core（StickShake、ShellToss、WorryBook），界面只照着画。
// 减少动态效果时不摇、不跳、不摔、不飞，姿势之间只做 0.15 秒淡入，结果直接出来。

// MARK: - 素材

/// 姿势图、铜钱、扣地龟甲从包里取，按名字缓存。
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
/// 「摇一摇」那张按签筒皮肤盖一层筒身着色图（朱漆、青玉；默认竹不盖）。
struct DivinationPoseImage: View {
    var pose: DivinationPose
    var height: CGFloat

    @Environment(\.divinationSkin) private var skin

    var body: some View {
        let h = height * CGFloat(pose.heightScale)
        let w = h * CGFloat(pose.aspect)
        ZStack {
            DivinationArtImage(name: pose.imageName, width: w, height: h)
            if pose == .qianShake, let overlay = DivinationArt.tubeOverlay(skin.tube) {
                DivinationArtImage(name: overlay, width: w, height: h)
            }
        }
        .frame(width: w, height: h)
        .accessibilityHidden(true)
    }
}

/// 姿势层：换图时旧图淡出、新图淡入并从 0.94 弹到 1（锚点在脚底，脚不漂）。`pose` 为 nil 时
/// 什么也不画（起卦一摔那一下）。frame 是 `height` 高、底对齐，宽留够最宽的那张。
struct DivinationPoseLayer: View {
    var pose: DivinationPose?
    var height: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let widthRatio: CGFloat = 0.86

    var body: some View {
        ZStack(alignment: .bottom) {
            if let pose {
                DivinationPoseImage(pose: pose, height: height)
                    .id(pose)
                    .transition(transition)
            }
        }
        .frame(width: height * Self.widthRatio, height: height, alignment: .bottom)
        .animation(.easeOut(duration: reduceMotion ? 0.15 : 0.18), value: pose)
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

    /// 每颗星相对中心的方向（单位圆上）、大小和起始延迟（按进度算）。
    private static let stars: [(x: CGFloat, y: CGFloat, size: CGFloat, delay: Double)] = [
        (-1, -0.55, 9, 0), (0.95, -0.7, 11, 0.08), (1.1, 0.35, 7, 0.16), (-1.05, 0.45, 8, 0.12), (0.15, -1.1, 7, 0.22),
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<Self.stars.count, id: \.self) { i in
                let star = Self.stars[i]
                let p = min(1, max(0, (progress - star.delay) / (1 - star.delay)))
                let s = sin(p * .pi)
                SparkleShape()
                    .fill(DivinationStyle.gold)
                    .frame(width: star.size, height: star.size)
                    .scaleEffect(s)
                    .opacity(s * (scheme == .dark ? 0.8 : 1))
                    .position(x: center.x + star.x * radius, y: center.y + star.y * radius)
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
}

/// 每日一签的场景：抱签筒摇一摇（整张图 ±8° 摆）→ 换「举签」图，一支签条从筒口沿弧线飞出 →
/// 换「展签」图，签级写在签纸上，冒几颗金色光点。`shakes` 每加一次走一遍；不在动时抽过就展签、
/// 没抽就抱着签筒。签纸太小（字会小于 13pt）时纸上不写字。
struct DivinationStickScene: View {
    var width: CGFloat
    var height: CGFloat
    /// 基准姿势高度（脚底贴着场景底边往上 4pt）。
    var poseHeight: CGFloat
    /// 今天的签（下标）；签飞出来那一刻写进去。
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
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }

    private var bottom: CGFloat { height - 4 }

    /// 姿势图上按比例的一点换成场景坐标（图底边中点贴在场景中线、`bottom`）。
    private func point(_ pose: DivinationPose, _ fx: Double, _ fy: Double) -> CGPoint {
        let h = poseHeight * CGFloat(pose.heightScale)
        let w = h * CGFloat(pose.aspect)
        return CGPoint(x: width / 2 + (CGFloat(fx) - 0.5) * w, y: bottom - (1 - CGFloat(fy)) * h)
    }

    private func scene(_ m: StickMotion, timing: StickShake) -> some View {
        let phase: StickShake.Phase = reduceMotion ? .rest : timing.phase(at: m.t)
        let pose = reduceMotion ? timing.pose(at: 99, drawn: index != nil) : timing.pose(at: m.t, drawn: index != nil)
        let slip = DivinationArt.slipRect
        let slipTop = point(.qianRead, slip.x, slip.y)
        let slipEnd = point(.qianRead, slip.x + slip.width, slip.y + slip.height)
        let slipCenter = CGPoint(x: (slipTop.x + slipEnd.x) / 2, y: (slipTop.y + slipEnd.y) / 2)
        let textOpacity = phase == .read ? min(1, (m.t - timing.readStart) / 0.2) : 1
        return ZStack(alignment: .topLeading) {
            DivinationGroundShadow(width: poseHeight * 0.6)
                .position(x: width / 2, y: bottom)
                .zIndex(0)
            DivinationPoseLayer(pose: pose, height: poseHeight)
                .rotationEffect(.degrees(phase == .shake ? m.sway : 0), anchor: .bottom)
                .position(x: width / 2, y: bottom - poseHeight / 2)
                .zIndex(1)
            if pose == .qianRead, let index,
               let font = DivinationArt.slipFont(slipHeight: Double(slipEnd.y - slipTop.y)) {
                Text(verbatim: FortuneStick.all[index].level.title)
                    .font(.custom("Songti SC", size: CGFloat(font)).weight(.heavy))
                    .foregroundStyle(Color(hex: DivinationArt.slipLevelInkHex))
                    .lineLimit(1)
                    .fixedSize()
                    .opacity(textOpacity)
                    .position(slipCenter)
                    .zIndex(2)
            }
            if phase == .fly {
                flyingSlip((m.t - timing.flyStart) / timing.fly, to: slipCenter)
                    .zIndex(3)
            }
            if phase == .read {
                DivinationSparkles(center: slipCenter, radius: poseHeight * 0.36,
                                   progress: (m.t - timing.readStart) / timing.reveal)
                    .zIndex(4)
            }
        }
        .frame(width: width, height: height)
    }

    /// 飞出来的签条：从筒口往右上抛，转着落到小熊猫胸前（换成展签图前淡掉）。
    private func flyingSlip(_ progress: Double, to end: CGPoint) -> some View {
        let p = CGFloat(min(1, max(0, progress)))
        let start = point(.qianShake, DivinationArt.tubeMouth.x, DivinationArt.tubeMouth.y)
        let control = CGPoint(x: min(width - 14, start.x + poseHeight * 0.5), y: max(10, start.y - poseHeight * 0.55))
        let x = (1 - p) * (1 - p) * start.x + 2 * (1 - p) * p * control.x + p * p * end.x
        let y = (1 - p) * (1 - p) * start.y + 2 * (1 - p) * p * control.y + p * p * end.y
        let level = index.map { FortuneStick.all[$0].level.title } ?? "签"
        return FlyingSlip(text: level, height: max(24, poseHeight * 0.26))
            .rotationEffect(.degrees(Double(-24 + 24 * p) + Double(p) * 300))
            .opacity(p < 0.8 ? 1 : Double((1 - p) / 0.2))
            .position(x: x, y: y)
    }
}

/// 飞出来的签条：米白纸、红签头、朱红细框，签级竖着写（纸太小写不下 13pt 的字就不写）。
struct FlyingSlip: View {
    var text: String
    var height: CGFloat

    var body: some View {
        let width = max(10, height * 0.34)
        let perChar = (height * 0.84) / CGFloat(max(1, text.count))
        let font = min(perChar, width - 2).rounded(.down)
        let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)
        ZStack(alignment: .top) {
            shape.fill(Color(hex: DivinationArt.slipPaperHex))
            Rectangle().fill(DivinationStyle.stickTip).frame(height: height * 0.08)
            if font >= CGFloat(Divination.minimumFont) {
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
            }
        }
        .frame(width: width, height: height)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color(hex: DivinationArt.slipLevelInkHex), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        .accessibilityHidden(true)
    }
}

// MARK: - 起卦

struct TossMotion {
    var t: Double = 99
    var sway: Double = 0
    /// 起跳前蹲、腾空（0…1）。
    var crouch: Double = 0
    var jump: Double = 0
    /// 摔下去的龟甲：0 还举在头顶，1 扣在地上。
    var drop: Double = 0
    var squash: Double = 0
    /// 抱回龟甲那一下的落地挤压。
    var land: Double = 0
    var dust: Double = 0
    /// 三枚铜钱：-1 在壳里看不见，0…1 在空中，1…2 落地弹两下，2 停住。
    var coin0: Double = 2
    var coin1: Double = 2
    var coin2: Double = 2
}

/// 起卦场景（面板，内容宽）：`throwCount` 每加一次按 Core 的 `ShellToss` 走一遍：
/// 双手捧古龟甲左右摇（整张图 ±8° 摆）→ 先蹲一下、跳起来把龟甲举过头顶 → 一摔：熊猫不出现，
/// 龟甲越落越快扣在地上、压扁回弹、扬起一点土 → 三枚铜钱按落地声的间隔从壳口依次蹦出，
/// 抛物线落到地上左中右错开，翻着转（按纵向压缩换正反面），弹两下停住 → 熊猫跳回来把龟甲抱走。
/// 减少动态效果时不动，铜钱直接躺在地上。
struct ShellTossScene: View {
    var width: CGFloat
    /// 最近一爻三枚铜钱的正反（true 是背）；还没摇过是 nil，铜钱淡淡地摆着。
    var faces: [Bool]?
    var throwCount: Int
    var fast: Bool
    /// 起过卦（不在动时抱着龟甲笑；没起过双手捧着）。
    var tossed: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let height: CGFloat = 178
    private let poseHeight: CGFloat = 148
    private let coin: CGFloat = 30
    private let ground: CGFloat = 168
    private let domeWidth: CGFloat = 118
    private var domeHeight: CGFloat { domeWidth / CGFloat(DivinationArt.shellDomeAspect) }

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
            KeyframeTrack(\.sway) {
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
            KeyframeTrack(\.jump) {
                LinearKeyframe(0, duration: t.liftStart + t.crouch)
                CubicKeyframe(1, duration: t.lift - t.crouch)
                LinearKeyframe(1, duration: t.fall)
                LinearKeyframe(0, duration: 0.001)
            }
            // 往下摔：越落越快（按重力分三段）。
            KeyframeTrack(\.drop) {
                LinearKeyframe(0, duration: t.fallStart)
                LinearKeyframe(0.25, duration: t.fall * 0.5)
                LinearKeyframe(0.5625, duration: t.fall * 0.25)
                LinearKeyframe(1, duration: t.fall * 0.25)
                LinearKeyframe(1, duration: t.pickupStart - t.impact)
                LinearKeyframe(0, duration: 0.001)
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
        .frame(width: width, height: Self.height)
        .accessibilityHidden(true)
    }

    private func landing(_ i: Int) -> CGPoint {
        let spot = ShellToss.landings[i]
        return CGPoint(x: width / 2 + CGFloat(spot.x) * coin, y: ground - coin / 2 + CGFloat(spot.y) * coin)
    }

    private func scene(_ m: TossMotion, toss: ShellToss) -> some View {
        let phase: ShellToss.Phase = reduceMotion ? .rest : toss.phase(at: m.t)
        let pose = reduceMotion ? toss.pose(at: 99, tossed: tossed) : toss.pose(at: m.t, tossed: tossed)
        let crouch = CGFloat(m.crouch), jump = CGFloat(m.jump), land = CGFloat(m.land)
        let sx = (1 + 0.05 * crouch) * (1 - 0.04 * jump) * (1 + 0.06 * land)
        let sy = (1 - 0.08 * crouch) * (1 + 0.06 * jump) * (1 - 0.1 * land)
        let lift = 14 * jump
        // 摔下去的龟甲：从举在头顶的位置越落越快扣到地上，举着时略小（和图里一样大）。
        let raisedBottom = ground - lift - poseHeight * CGFloat(1 - DivinationArt.raisedShellBottom)
        let drop = CGFloat(min(1, max(0, m.drop)))
        let domeBottom = raisedBottom + (ground + 2 - raisedBottom) * drop
        let domeScale = 0.8 + 0.2 * drop
        let squash = CGFloat(m.squash)
        let domeOpacity: Double = switch phase {
        case .thrown: min(1, (m.t - toss.fallStart) / 0.05)
        case .pickup: max(0, 1 - (m.t - toss.pickupStart) / 0.15)
        default: 0
        }
        return ZStack(alignment: .topLeading) {
            DivinationGroundShadow(width: poseHeight * 0.58 * (1 - 0.35 * jump))
                .opacity(pose == nil ? 0 : Double(1 - 0.5 * jump))
                .position(x: width / 2, y: ground)
                .zIndex(0)
            DivinationGroundShadow(width: domeWidth * 1.05)
                .opacity(domeOpacity * Double(drop))
                .position(x: width / 2, y: ground)
                .zIndex(0)
            DivinationPoseLayer(pose: pose, height: poseHeight)
                .scaleEffect(x: sx, y: sy, anchor: .bottom)
                .rotationEffect(.degrees(phase == .shake ? m.sway : 0), anchor: .bottom)
                .offset(y: -lift)
                .position(x: width / 2, y: ground - poseHeight / 2)
                .zIndex(1)
            if domeOpacity > 0 {
                DivinationArtImage(name: DivinationArt.shellDome, width: domeWidth, height: domeHeight)
                    .scaleEffect(domeScale, anchor: .bottom)
                    .scaleEffect(x: 1 + 0.1 * squash, y: 1 - 0.14 * squash, anchor: .bottom)
                    .opacity(domeOpacity)
                    .position(x: width / 2, y: domeBottom - domeHeight / 2)
                    .zIndex(2)
            }
            if m.dust > 0.01, m.dust < 0.99 { dust(m.dust).zIndex(2) }
            ForEach(0..<3, id: \.self) { i in
                coinView(i, reduceMotion ? 2 : [m.coin0, m.coin1, m.coin2][i])
            }
            .zIndex(3)
            if !reduceMotion, m.t >= toss.settled, m.t < toss.settled + 0.5 {
                DivinationSparkles(center: CGPoint(x: width / 2, y: ground - coin), radius: coin * 2.6,
                                   progress: (m.t - toss.settled) / 0.5)
                    .zIndex(4)
            }
        }
        .frame(width: width, height: Self.height)
    }

    /// 触地扬起的土：两边各六粒，往外散开、变淡。
    private func dust(_ p: Double) -> some View {
        let spread = CGFloat(p)
        return ZStack(alignment: .topLeading) {
            ForEach(0..<12, id: \.self) { k in
                let side: CGFloat = k < 6 ? -1 : 1
                let j = CGFloat(k % 6)
                let x = width / 2 + side * (domeWidth / 2 + 2 + j * 5 * (0.4 + spread))
                let y = ground - 2 - (CGFloat((k * 7) % 5) + j * 0.6) * (0.3 + spread)
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
            // 壳口在扣地龟甲的前沿偏右，三枚错开一点出来。
            let mouth = CGPoint(x: width / 2 + domeWidth * 0.16 + CGFloat(i - 1) * 6, y: ground - domeHeight * 0.32)
            let arc: CGFloat = 52 + CGFloat(i) * 10
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
        return ZStack(alignment: .topLeading) {
            Ellipse().fill(DivinationStyle.groundShade)
                .frame(width: coin * 0.8, height: 5)
                .blur(radius: 1.2)
                .opacity(shown ? min(1, max(0.25, p)) : 0)
                .position(x: pose.position.x, y: ground + 1)
            DivinationCoin(back: face, size: coin)
                .scaleEffect(x: 1, y: max(0.08, CGFloat(abs(cosine))))
                .rotationEffect(.degrees(pose.spin))
                .opacity(shown ? (faces == nil ? 0.55 : 1) : 0)
                .position(pose.position)
        }
    }
}

/// 小熊猫双手捧着古龟甲（桌面卡片用）：`shakes` 每加一次整张图左右摇一阵；减少动态效果时不摇。
struct DivinationShellSway: View {
    var height: CGFloat
    var shakes: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        DivinationPoseImage(pose: .castHold, height: height)
            .keyframeAnimator(initialValue: 0.0, trigger: reduceMotion ? 0 : shakes) { view, angle in
                view.rotationEffect(.degrees(angle), anchor: .bottom)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(-8.0, duration: 0.09)
                    CubicKeyframe(8.0, duration: 0.11)
                    CubicKeyframe(-6.0, duration: 0.11)
                    CubicKeyframe(6.0, duration: 0.11)
                    CubicKeyframe(0.0, duration: 0.09)
                }
            }
            .frame(height: height, alignment: .bottom)
            .accessibilityHidden(true)
    }
}

// MARK: - 解忧书

struct BookMotion {
    var t: Double = 99
    var hop: Double = 0
}

/// 解忧书场景（面板，内容宽）：上面小熊猫，下面答案。`flips` 每加一次：合掌默想 → 双手捧书翻开
/// （轻轻一弹）→ 换成书页正对着看的图、书页暖金光、冒几颗光点，答案大字逐行淡入。
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
        let bottom = Self.heroHeight - 4
        let h = Self.poseHeight
        // 书页中心（答案图上书页在胸前、偏下）。
        let pages = CGPoint(x: width / 2, y: bottom - h * 0.4)
        let glow: Double = {
            guard pose == DivinationPose.bookAnswer(dark: dark) else { return 0 }
            let full = dark ? 0.45 : 0.7
            if phase == .answer { return full * min(1, (t - WorryBook.flipSwap) / 0.3) }
            return full
        }()
        return VStack(spacing: 6) {
            ZStack(alignment: .topLeading) {
                RadialGradient(colors: [Color(hex: "#FFD682").opacity(glow), Color(hex: "#FFD682").opacity(0)],
                               center: .center, startRadius: 0, endRadius: h * 0.42)
                    .frame(width: h * 0.95, height: h * 0.7)
                    .position(pages)
                    .allowsHitTesting(false)
                    .zIndex(0)
                DivinationGroundShadow(width: h * 0.55)
                    .position(x: width / 2, y: bottom)
                    .zIndex(0)
                DivinationPoseLayer(pose: pose, height: h)
                    .offset(y: -6 * CGFloat(m.hop))
                    .position(x: width / 2, y: bottom - h / 2)
                    .zIndex(1)
                if phase == .answer, !reduceMotion {
                    DivinationSparkles(center: pages, radius: h * 0.34,
                                       progress: (t - WorryBook.flipSwap) / (WorryBook.flipDuration - WorryBook.flipSwap))
                        .zIndex(4)
                }
            }
            .frame(width: width, height: Self.heroHeight)
            answer(t: t, phase: phase)
                .frame(width: width, height: Self.answerHeight)
        }
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
