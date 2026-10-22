import AppKit
import SwiftUI

// 「正在播放」中卡的三种卡带外观：磁带、随身听、收录机（`CassetteLook`）。
//
// 中卡在扩展栏上是 404×58（和 Codex 用量的中卡一样），效果图 404×104 的比例
// 按 58 高重新排过：字最小 13pt，所以机身上的小字（磁带标签上的 A 面、歌名）
// 不再印，歌名歌手放在旁边的正文或液晶上。
//
// 机身是实物质感，颜色写死，不随浅深色变；磁带外观的卡片底还是普通玻璃卡片，
// 旁边的字跟着外观走。只印小熊猫小标，不出现任何品牌名。
//
// 动画：转轮和收录机纸盆各用一个 `TimelineView`，只在「在播 + 扩展栏卡片看得见
// + 没开减少动态效果」时走（`CassetteMotion.framesPerSecond`），其余时刻和预览
// 都静止；没有常驻的 repeatForever。

/// 卡带卡片要画的一首歌，和来源无关。
struct CassetteTrack {
    var title: String
    var artist: String
    var isPlaying: Bool
    var progress: Double
    var elapsed: TimeInterval
    var duration: TimeInterval
    var artwork: NSImage?
    var sourceIcon: NSImage?
    /// 有时长才画进度和时间（直播、读不到时长的网页视频没有）。
    var showsTime: Bool
}

/// 三个键调用的媒体控制；nil 的键画成按不动的样子。
struct CassetteActions {
    var previous: (() -> Void)?
    var toggle: (() -> Void)?
    var next: (() -> Void)?
}

/// 中卡上的卡带外观。`look` 不会是 `.plain`（默认样式由 `MusicTile` 自己画）。
struct CassetteCard: View {
    var look: CassetteLook
    var track: CassetteTrack
    var actions: CassetteActions
    /// 扩展栏卡片看得见、而且不是预览：转轮才可能转。
    var visible: Bool

    var body: some View {
        switch look {
        case .tape, .plain:
            WidgetSurface { TapeFace(track: track, actions: actions, visible: visible) }
        case .portable:
            WidgetSurface(fill: CassettePalette.creamBottom) {
                PortableFace(track: track, actions: actions, visible: visible)
            }
        case .boombox:
            WidgetSurface(fill: CassettePalette.oliveBottom) {
                BoomboxFace(track: track, actions: actions, visible: visible)
            }
        }
    }
}

// MARK: - 配色（按效果图脚本 design/cassette-player.py）

enum CassettePalette {
    static func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> Color {
        Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: a)
    }

    // 磁带外壳
    static let shellTop = rgb(176, 122, 70, 0.89)
    static let shellBottom = rgb(112, 72, 40, 0.93)
    static let shellEdge = rgb(58, 36, 20)
    static let label = rgb(244, 236, 218)
    static let tape = rgb(78, 46, 30)
    static let hub = rgb(236, 228, 210)
    static let hubHole = rgb(34, 26, 22)

    // 随身听
    static let creamTop = rgb(246, 239, 226)
    static let creamBottom = rgb(224, 214, 196)
    static let coral = rgb(228, 98, 58)
    static let lcdTop = rgb(196, 200, 172)
    static let lcdBottom = rgb(176, 182, 152)
    static let lcdInk = rgb(34, 40, 28)

    // 收录机
    static let oliveTop = rgb(122, 134, 94)
    static let oliveBottom = rgb(84, 94, 62)
    static let olivePlate = rgb(48, 54, 34)
    static let strip = rgb(239, 228, 204)
    static let stripInk = rgb(40, 36, 26)
    static let copper = rgb(205, 170, 104)
    static let amber = rgb(236, 150, 72)

    /// 没有封面时标签贴纸上的暮色渐变。
    static let dusk = LinearGradient(colors: [rgb(255, 186, 102), rgb(238, 108, 112), rgb(120, 58, 140)],
                                     startPoint: .top, endPoint: .bottom)
}

/// 小熊猫小标（现成的 Resources/Pet 素材）。
private struct PandaMark: View {
    var height: CGFloat

    var body: some View {
        Group {
            if let image = PandaArt.image("pet-panda-idle") {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            } else {
                Color.clear
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// 封面（或暮色渐变）铺满给定的框。
private struct CoverFill: View {
    var image: NSImage?

    var body: some View {
        if let image {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
        } else {
            CassettePalette.dusk
        }
    }
}

// MARK: - 转轮

/// 一对转轮：磁带量随进度从左轮走到右轮，转速随卷径变。
struct ReelPair: View {
    var progress: Double
    var minRadius: CGFloat
    var maxRadius: CGFloat
    var hubRadius: CGFloat
    /// 两个轮心的距离。
    var spacing: CGFloat
    var playing: Bool
    var visible: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 两个轮子的累计角度：换档、暂停再播放都从当前角度接着转（`CassetteMotion.Spin`）。
    @State private var spins = ReelSpins()

    var body: some View {
        let fps = CassetteMotion.framesPerSecond(playing: playing, visible: visible, reduceMotion: reduceMotion)
        TimelineView(.animation(minimumInterval: 1 / (fps ?? CassetteMotion.fps), paused: fps == nil)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let rl = CGFloat(CassetteMotion.packRadius(min: Double(minRadius), max: Double(maxRadius),
                                                       progress: progress, left: true))
            let rr = CGFloat(CassetteMotion.packRadius(min: Double(minRadius), max: Double(maxRadius),
                                                       progress: progress, left: false))
            let angles = spins.angles(at: t, moving: fps != nil,
                                      left: CassetteMotion.degreesPerSecond(fraction: Double(rl / max(maxRadius, 0.1))),
                                      right: CassetteMotion.degreesPerSecond(fraction: Double(rr / max(maxRadius, 0.1))))
            Canvas { ctx, size in
                let cy = size.height / 2
                let left = CGPoint(x: size.width / 2 - spacing / 2, y: cy)
                let right = CGPoint(x: size.width / 2 + spacing / 2, y: cy)
                // 两卷之间底下那一段带子。
                var tape = Path()
                tape.move(to: CGPoint(x: left.x, y: cy + rl))
                tape.addLine(to: CGPoint(x: right.x, y: cy + rr))
                ctx.stroke(tape, with: .color(CassettePalette.tape.opacity(0.8)), lineWidth: 0.6)
                drawReel(ctx, center: left, pack: rl, hub: hubRadius, degrees: angles.left)
                drawReel(ctx, center: right, pack: rr, hub: hubRadius, degrees: angles.right)
            }
        }
        .accessibilityHidden(true)
    }

    private func drawReel(_ ctx: GraphicsContext, center c: CGPoint, pack: CGFloat, hub: CGFloat, degrees: Double) {
        func circle(_ r: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        }
        ctx.fill(circle(pack), with: .color(CassettePalette.tape))
        ctx.stroke(circle(pack), with: .color(CassettePalette.rgb(120, 76, 50, 0.8)), lineWidth: 0.5)
        ctx.fill(circle(hub), with: .color(CassettePalette.hub))
        ctx.fill(circle(hub * 0.58), with: .color(CassettePalette.hubHole))
        var spokes = Path()
        for i in 0..<6 {
            let a = CGFloat((degrees + Double(i) * 60) * .pi / 180)
            spokes.move(to: CGPoint(x: c.x + cos(a) * hub * 0.6, y: c.y + sin(a) * hub * 0.6))
            spokes.addLine(to: CGPoint(x: c.x + cos(a) * hub * 0.3, y: c.y + sin(a) * hub * 0.3))
        }
        ctx.stroke(spokes, with: .color(CassettePalette.hub), lineWidth: max(0.8, hub * 0.18))
    }
}

/// 一对转轮的角度，存在 `@State` 里跨帧累计。只在 TimelineView 取帧时改，
/// 不参与 SwiftUI 的依赖追踪（普通类，不是 Observable），改它不会引起重画。
private final class ReelSpins {
    private var left = CassetteMotion.Spin(phase: 8)
    private var right = CassetteMotion.Spin(phase: 38)

    func angles(at t: Double, moving: Bool, left dpsL: Double, right dpsR: Double) -> (left: Double, right: Double) {
        guard moving else {
            left.pause(at: t)
            right.pause(at: t)
            return (left.restingAngle, right.restingAngle)
        }
        return (left.angle(at: t, degreesPerSecond: dpsL), right.angle(at: t, degreesPerSecond: dpsR))
    }
}

// MARK: - 实体按键

/// 实体按键：抬起有底边投影，按下（或播放键锁住在播时）下沉、颜色压暗。
private struct PhysicalKey: View {
    var symbol: String
    var face: Color
    var ink: Color
    var latched: Bool
    var corner: CGFloat
    var glyph: CGFloat
    var label: String
    var action: (() -> Void)?

    var body: some View {
        Button(action: { action?() }) { EmptyView() }
            .buttonStyle(KeyStyle(symbol: symbol, face: face, ink: ink, latched: latched,
                                  corner: corner, glyph: glyph))
            .disabled(action == nil)
            .accessibilityLabel(label)
    }
}

private struct KeyStyle: ButtonStyle {
    var symbol: String
    var face: Color
    var ink: Color
    var latched: Bool
    var corner: CGFloat
    var glyph: CGFloat
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let down = latched || configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        return GeometryReader { geo in
            let depth: CGFloat = 2.2
            let h = geo.size.height - depth
            ZStack(alignment: .top) {
                if !down {
                    shape.fill(face.mix(with: .black, by: 0.38))
                        .frame(height: h)
                        .offset(y: depth)
                }
                shape
                    .fill(LinearGradient(colors: [face.mix(with: .white, by: down ? 0 : 0.12),
                                                  face.mix(with: .black, by: down ? 0.14 : 0)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(shape.strokeBorder(.black.opacity(0.2), lineWidth: 0.5))
                    .overlay(alignment: .top) {
                        if !down {
                            Capsule().fill(.white.opacity(0.45))
                                .frame(height: 0.6)
                                .padding(.horizontal, corner)
                                .padding(.top, 0.8)
                        }
                    }
                    .overlay {
                        Image(systemName: symbol)
                            .font(.system(size: glyph, weight: .bold))
                            .foregroundStyle(ink.opacity(enabled ? 1 : 0.4))
                    }
                    .frame(height: h)
                    .offset(y: down ? 1.6 : 0)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.08), value: down)
    }
}

/// 上一首、播放暂停、下一首三个实体键。
private struct KeyRow: View {
    var track: CassetteTrack
    var actions: CassetteActions
    var face: Color
    var ink: Color
    var playFace: Color
    var playInk: Color
    var spacing: CGFloat
    var corner: CGFloat
    var glyph: CGFloat

    var body: some View {
        HStack(spacing: spacing) {
            PhysicalKey(symbol: "backward.end.fill", face: face, ink: ink, latched: false, corner: corner,
                        glyph: glyph, label: tr("上一首"), action: actions.previous)
            PhysicalKey(symbol: "playpause.fill", face: playFace, ink: playInk, latched: track.isPlaying,
                        corner: corner, glyph: glyph, label: track.isPlaying ? tr("暂停") : tr("播放"),
                        action: actions.toggle)
            PhysicalKey(symbol: "forward.end.fill", face: face, ink: ink, latched: false, corner: corner,
                        glyph: glyph, label: tr("下一首"), action: actions.next)
        }
    }
}

/// 细细一条进度。
private struct ThinBar: View {
    var progress: Double
    var track: Color
    var fill: Color
    var height: CGFloat = 3

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(fill).frame(width: max(0, geo.size.width * min(max(progress, 0), 1)))
            }
        }
        .frame(height: height)
    }
}

// MARK: - 1. 磁带

/// 普通玻璃卡片上放一盒茶色半透明磁带，旁边是歌名、歌手、控制和进度。
private struct TapeFace: View {
    var track: CassetteTrack
    var actions: CassetteActions
    var visible: Bool

    var body: some View {
        HStack(spacing: 10) {
            CassetteShell(track: track, visible: visible)
                .frame(width: 88, height: 55)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 8) {
                    Text(track.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WidgetStyle.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    transport
                }
                HStack(spacing: 5) {
                    if let icon = track.sourceIcon {
                        Image(nsImage: icon).resizable().interpolation(.high).scaledToFit()
                            .frame(width: 15, height: 15)
                            .accessibilityHidden(true)
                    }
                    Text(track.artist)
                        .font(WidgetStyle.caption(13))
                        .foregroundStyle(WidgetStyle.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if track.showsTime {
                    HStack(spacing: 7) {
                        clock(track.elapsed)
                        ThinBar(progress: track.progress, track: WidgetStyle.secondary.opacity(0.3),
                                fill: WidgetStyle.primary, height: 4)
                        clock(track.duration)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func clock(_ seconds: TimeInterval) -> some View {
        Text(MusicTime.clock(seconds))
            .font(WidgetStyle.caption(13))
            .monospacedDigit()
            .foregroundStyle(WidgetStyle.secondary)
            .lineLimit(1)
            .fixedSize()
    }

    private var transport: some View {
        HStack(spacing: 9) {
            glyph("backward.end.fill", size: 13, label: tr("上一首"), action: actions.previous)
            Button(action: { actions.toggle?() }) {
                ZStack {
                    Circle().fill(WidgetStyle.primary)
                    Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                        .playPauseMorph(track.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.background)
                        .offset(x: track.isPlaying ? 0 : 1)
                }
                .frame(width: 22, height: 22)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(actions.toggle == nil)
            .accessibilityLabel(track.isPlaying ? tr("暂停") : tr("播放"))
            glyph("forward.end.fill", size: 13, label: tr("下一首"), action: actions.next)
        }
    }

    private func glyph(_ symbol: String, size: CGFloat, label: String, action: (() -> Void)?) -> some View {
        Button(action: { action?() }) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(WidgetStyle.primary.opacity(action == nil ? 0.35 : 1))
                .frame(minWidth: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .accessibilityLabel(label)
    }
}

/// 磁带外壳，按效果图 154×96 的坐标画，再整体缩放到给定的框里。外壳上不印字。
private struct CassetteShell: View {
    var track: CassetteTrack
    var visible: Bool

    private static let size = CGSize(width: 154, height: 96)

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / Self.size.width, geo.size.height / Self.size.height)
            shell
                .frame(width: Self.size.width, height: Self.size.height)
                .scaleEffect(s, anchor: .topLeading)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .shadow(color: .black.opacity(0.28), radius: 3, y: 2)
        .accessibilityHidden(true)
    }

    private var shell: some View {
        let casing = RoundedRectangle(cornerRadius: 7, style: .continuous)
        let label = RoundedRectangle(cornerRadius: 4, style: .continuous)
        let window = Capsule(style: .continuous)
        return ZStack(alignment: .topLeading) {
            casing.fill(LinearGradient(colors: [CassettePalette.shellTop, CassettePalette.shellBottom],
                                     startPoint: .top, endPoint: .bottom))
            casing.strokeBorder(CassettePalette.shellEdge, lineWidth: 0.8)
            RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                .strokeBorder(CassettePalette.rgb(255, 226, 190, 0.27), lineWidth: 0.6)
                .padding(2.2)
            // 透出来的两卷带盘外圈。
            ForEach([57.0, 97.0], id: \.self) { cx in
                Circle().stroke(CassettePalette.rgb(60, 36, 20, 0.24), lineWidth: 0.8)
                    .frame(width: 54, height: 54)
                    .position(x: cx, y: 44)
            }
            // 标签贴纸：上面一条留白（两道手写线），下面是封面。
            ZStack(alignment: .topLeading) {
                CassettePalette.label
                CoverFill(image: track.artwork)
                    .frame(width: 140, height: 38)
                    .clipped()
                    .offset(y: 18)
                Rectangle().fill(CassettePalette.rgb(60, 40, 30, 0.35)).frame(width: 140, height: 0.5).offset(y: 18)
                RoundedRectangle(cornerRadius: 3).fill(CassettePalette.rgb(60, 44, 36))
                    .frame(width: 13, height: 13).offset(x: 3, y: 2.5)
                Capsule().fill(CassettePalette.rgb(40, 30, 60, 0.55)).frame(width: 52, height: 1.6).offset(x: 22, y: 7)
                Capsule().fill(CassettePalette.rgb(40, 30, 60, 0.35)).frame(width: 34, height: 1.4).offset(x: 22, y: 12)
            }
            .frame(width: 140, height: 56)
            .clipShape(label)
            .offset(x: 7, y: 6)
            // 小窗：茶色透明，里面两个转轮。
            ZStack {
                CassettePalette.rgb(36, 24, 18, 0.84)
                ReelPair(progress: track.progress, minRadius: 6.5, maxRadius: 15.5, hubRadius: 5.4,
                         spacing: 40, playing: track.isPlaying, visible: visible)
                    .frame(width: 80, height: 28)
                Capsule().fill(.white.opacity(0.24)).frame(width: 20, height: 1).offset(x: -20, y: -10)
            }
            .frame(width: 80, height: 28)
            .clipShape(window)
            .overlay(window.strokeBorder(CassettePalette.rgb(30, 20, 14), lineWidth: 0.8))
            .offset(x: 37, y: 30)
            // 下方磁头口。
            Path { p in
                p.move(to: CGPoint(x: 32, y: 68)); p.addLine(to: CGPoint(x: 122, y: 68))
                p.addLine(to: CGPoint(x: 132, y: 94.5)); p.addLine(to: CGPoint(x: 22, y: 94.5)); p.closeSubpath()
            }
            .fill(CassettePalette.rgb(92, 58, 32, 0.82))
            ForEach([50.0, 104.0], id: \.self) { hx in
                Circle().fill(CassettePalette.rgb(28, 18, 12)).frame(width: 6.8, height: 6.8).position(x: hx, y: 82)
            }
            ForEach([68.0, 82.0], id: \.self) { hx in
                RoundedRectangle(cornerRadius: 1).fill(CassettePalette.rgb(28, 18, 12))
                    .frame(width: 5, height: 8).position(x: hx + 2.5, y: 82)
            }
            ForEach(Array([(7.0, 7.0), (147.0, 7.0), (7.0, 89.0), (147.0, 89.0), (77.0, 74.0)].enumerated()),
                    id: \.offset) { _, point in
                Circle().fill(CassettePalette.rgb(200, 196, 188)).frame(width: 4.4, height: 4.4)
                    .position(x: point.0, y: point.1)
            }
            PandaMark(height: 13).offset(x: 12, y: 72)
        }
    }
}

// MARK: - 2. 随身听

/// 奶油色机身：左边小窗看得见转轮，中间灰绿反射式液晶写歌名和进度，右边三个实体键。
private struct PortableFace: View {
    var track: CassetteTrack
    var actions: CassetteActions
    var visible: Bool

    var body: some View {
        HStack(spacing: 10) {
            window.frame(width: 96, height: 46)
            lcd.frame(maxWidth: .infinity).frame(height: 46)
            KeyRow(track: track, actions: actions, face: CassettePalette.rgb(232, 224, 210),
                   ink: CassettePalette.rgb(60, 52, 46), playFace: CassettePalette.coral,
                   playInk: CassettePalette.rgb(255, 248, 240), spacing: 4, corner: 5, glyph: 11)
                .frame(width: 98, height: 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                LinearGradient(colors: [CassettePalette.creamTop, CassettePalette.creamBottom],
                               startPoint: .top, endPoint: .bottom)
                RoundedRectangle(cornerRadius: WidgetStyle.corner - 1.5, style: .continuous)
                    .strokeBorder(.white.opacity(0.43), lineWidth: 0.6)
                    .padding(1.5)
            }
            .padding(.horizontal, -WidgetStyle.inset)
        }
    }

    private var window: some View {
        let inner = RoundedRectangle(cornerRadius: 9, style: .continuous)
        return ZStack(alignment: .top) {
            CassettePalette.rgb(40, 32, 28)
            CoverFill(image: track.artwork)
                .frame(height: 15)
                .clipped()
                .opacity(0.55)
                .padding(.horizontal, 6)
                .padding(.top, 4)
            Capsule().fill(CassettePalette.rgb(26, 20, 18))
                .frame(height: 16)
                .padding(.horizontal, 5)
                .offset(y: 21)
            ReelPair(progress: track.progress, minRadius: 5.2, maxRadius: 13.5, hubRadius: 4.4,
                     spacing: 40, playing: track.isPlaying, visible: visible)
                .frame(height: 30)
                .offset(y: 14)
            Path { p in
                p.move(to: CGPoint(x: 53, y: 0)); p.addLine(to: CGPoint(x: 69, y: 0))
                p.addLine(to: CGPoint(x: 38, y: 46)); p.addLine(to: CGPoint(x: 22, y: 46)); p.closeSubpath()
            }
            .fill(.white.opacity(0.09))
        }
        .clipShape(inner)
        .padding(2.5)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(CassettePalette.rgb(70, 60, 52)))
        .accessibilityHidden(true)
    }

    private var lcd: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(track.title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(CassettePalette.lcdInk)
                    .lineLimit(1)
                    .layoutPriority(1)
                Text(track.artist)
                    .font(WidgetStyle.caption(13))
                    .foregroundStyle(CassettePalette.lcdInk.opacity(0.75))
                    .lineLimit(1)
                Spacer(minLength: 0)
                PandaMark(height: 14)
            }
            if track.showsTime {
                HStack(spacing: 6) {
                    clock(track.elapsed, opacity: 1)
                    ThinBar(progress: track.progress, track: CassettePalette.lcdInk.opacity(0.24),
                            fill: CassettePalette.lcdInk)
                    clock(track.duration, opacity: 0.67)
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(LinearGradient(colors: [CassettePalette.lcdTop, CassettePalette.lcdBottom],
                                 startPoint: .top, endPoint: .bottom)))
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(CassettePalette.rgb(96, 86, 74)))
    }

    private func clock(_ seconds: TimeInterval, opacity: Double) -> some View {
        Text(MusicTime.clock(seconds))
            .font(WidgetStyle.caption(13))
            .monospacedDigit()
            .foregroundStyle(CassettePalette.lcdInk.opacity(opacity))
            .lineLimit(1)
            .fixedSize()
    }
}

// MARK: - 3. 收录机

/// 苔绿色横机身：左右两个铜圈喇叭，中间调台条写歌名，下面磁带仓和三个键。
private struct BoomboxFace: View {
    var track: CassetteTrack
    var actions: CassetteActions
    var visible: Bool

    var body: some View {
        HStack(spacing: 8) {
            Speaker(diameter: 50, playing: track.isPlaying, visible: visible)
            VStack(spacing: 4) {
                strip
                HStack(spacing: 8) {
                    deck.frame(width: 96, height: 26)
                    VStack(spacing: 4) {
                        KeyRow(track: track, actions: actions, face: CassettePalette.rgb(214, 206, 186),
                               ink: CassettePalette.rgb(50, 46, 36), playFace: CassettePalette.amber,
                               playInk: CassettePalette.rgb(255, 248, 238), spacing: 4, corner: 4, glyph: 9)
                            .frame(height: 18)
                        if track.showsTime {
                            ThinBar(progress: track.progress, track: CassettePalette.rgb(30, 34, 20, 0.55),
                                    fill: CassettePalette.rgb(255, 196, 120))
                        }
                    }
                }
            }
            .padding(.top, 6)
            Speaker(diameter: 50, playing: track.isPlaying, visible: visible)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack(alignment: .top) {
                LinearGradient(colors: [CassettePalette.oliveTop, CassettePalette.oliveBottom],
                               startPoint: .top, endPoint: .bottom)
                RoundedRectangle(cornerRadius: WidgetStyle.corner - 1.5, style: .continuous)
                    .strokeBorder(CassettePalette.rgb(220, 230, 190, 0.27), lineWidth: 0.6)
                    .padding(1.5)
                // 提手。
                Capsule().fill(CassettePalette.olivePlate)
                    .frame(width: 120, height: 4)
                    .padding(.top, 1.5)
            }
            .padding(.horizontal, -WidgetStyle.inset)
        }
    }

    private var strip: some View {
        HStack(spacing: 6) {
            Text(track.title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(CassettePalette.stripInk)
                .lineLimit(1)
                .layoutPriority(1)
            Text(track.artist)
                .font(WidgetStyle.caption(13))
                .foregroundStyle(CassettePalette.stripInk.opacity(0.69))
                .lineLimit(1)
            Spacer(minLength: 2)
            if track.showsTime {
                Text(MusicTime.clock(track.elapsed))
                    .font(WidgetStyle.caption(13))
                    .monospacedDigit()
                    .foregroundStyle(CassettePalette.stripInk.opacity(0.8))
                    .lineLimit(1)
                    .fixedSize()
            }
            PandaMark(height: 13)
        }
        .padding(.horizontal, 7)
        .frame(height: 20)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(CassettePalette.strip))
    }

    private var deck: some View {
        let inner = RoundedRectangle(cornerRadius: 5, style: .continuous)
        return ZStack(alignment: .top) {
            CassettePalette.rgb(34, 30, 26)
            CoverFill(image: track.artwork)
                .frame(height: 7)
                .clipped()
                .opacity(0.5)
                .padding(.horizontal, 4)
                .padding(.top, 2)
            ReelPair(progress: track.progress, minRadius: 4, maxRadius: 9.5, hubRadius: 3.4,
                     spacing: 40, playing: track.isPlaying, visible: visible)
                .frame(height: 22)
                .offset(y: 5)
        }
        .clipShape(inner)
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(CassettePalette.rgb(44, 48, 32)))
        .accessibilityHidden(true)
    }
}

/// 铜圈喇叭：网罩加中心纸盆，播放时纸盆小幅胀缩（不读音量）。
private struct Speaker: View {
    var diameter: CGFloat
    var playing: Bool
    var visible: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let fps = CassetteMotion.framesPerSecond(playing: playing, visible: visible, reduceMotion: reduceMotion)
        TimelineView(.animation(minimumInterval: 1 / (fps ?? CassetteMotion.fps), paused: fps == nil)) { timeline in
            let scale = CassetteMotion.coneScale(t: timeline.date.timeIntervalSinceReferenceDate,
                                                 animating: fps != nil)
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let r = min(size.width, size.height) / 2 - 1.5
                func circle(_ radius: CGFloat) -> Path {
                    Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
                }
                ctx.fill(circle(r + 1.5), with: .color(CassettePalette.rgb(52, 58, 38)))
                ctx.fill(circle(r), with: .color(CassettePalette.rgb(40, 40, 36)))
                // 网罩上的小孔。
                let step = max(2.6, r / 9)
                let dot = step * 0.24
                var holes = Path()
                var row = 0
                var y = c.y - r
                while y <= c.y + r {
                    var x = c.x - r + (row % 2 == 1 ? step / 2 : 0)
                    while x <= c.x + r {
                        if (x - c.x) * (x - c.x) + (y - c.y) * (y - c.y) < (r - 2.5) * (r - 2.5) {
                            holes.addEllipse(in: CGRect(x: x - dot, y: y - dot, width: dot * 2, height: dot * 2))
                        }
                        x += step
                    }
                    y += step * 0.87
                    row += 1
                }
                ctx.fill(holes, with: .color(CassettePalette.rgb(86, 84, 76)))
                let cone = r * 0.34 * CGFloat(scale)
                ctx.fill(circle(cone + 1.5), with: .color(CassettePalette.rgb(30, 30, 28, 0.9)))
                ctx.fill(circle(cone), with: .color(CassettePalette.rgb(58, 56, 52)))
                ctx.fill(circle(cone * 0.42), with: .color(CassettePalette.rgb(24, 24, 22)))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - cone * 0.29, y: c.y - cone * 0.32,
                                                width: cone * 0.28, height: cone * 0.28)),
                         with: .color(.white.opacity(0.2)))
                ctx.stroke(circle(r + 0.2), with: .color(CassettePalette.copper), lineWidth: 2.2)
                var glint = Path()
                glint.addArc(center: c, radius: r - 0.6, startAngle: .degrees(200), endAngle: .degrees(300),
                             clockwise: false)
                ctx.stroke(glint, with: .color(CassettePalette.rgb(255, 230, 170, 0.63)), lineWidth: 0.8)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}
