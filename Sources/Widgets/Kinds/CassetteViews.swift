import AppKit
import SwiftUI

// 「复古卡带」小组件（`CassetteWidget`）共用的实物零件：配色、转轮、磁带外壳、
// 喇叭和玻璃键帽。卡片在 CassetteTile.swift，面板在 Details/CassetteDetail.swift。
//
// 机身是放在玻璃上的实物，颜色写死，不随浅深色变；底板、按键和字跟着浅色 / 深色
// （`GlassKeyStyle`、面板语义色）。只印小熊猫小标，不出现任何品牌名。
//
// 动画：转轮和收录机纸盆各用一个 `TimelineView`，只在「在播 + 看得见 + 没开减少
// 动态效果」时走（`CassetteMotion.framesPerSecond`），其余时刻和预览都静止；没有
// 常驻的 repeatForever。收录机的喇叭网罩画一次就缓存，播放时每帧只给纸盆做缩放。

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

    // 玻璃键帽里的珊瑚播放键（不发光，只有实色渐变和底边投影）。
    static let coralTop = rgb(240, 120, 82)
    static let coralBottom = rgb(214, 84, 48)
    /// 调台条的红指针、紧凑卡片和列表行的珊瑚小竖条。
    static let needle = rgb(222, 70, 46)

    /// 没有封面时标签贴纸上的暮色渐变。
    static let dusk = LinearGradient(colors: [rgb(255, 186, 102), rgb(238, 108, 112), rgb(120, 58, 140)],
                                     startPoint: .top, endPoint: .bottom)
}

/// 小熊猫小标（现成的 Resources/Pet 素材）。
struct PandaMark: View {
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
struct CoverFill: View {
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

/// 细细一条进度。
struct ThinBar: View {
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

/// 磁带外壳，按效果图 154×96 的坐标画，再整体缩放到给定的框里。外壳上不印字。
struct CassetteShell: View {
    var track: CassetteTrack
    var visible: Bool
    /// 精简：紧凑卡片和外观缩略图用，只留外壳、封面标签、小窗里的两个转轮和磁头口，
    /// 不画螺丝、手写线和小熊猫（缩到 0.5 倍以下时这些只剩噪点）。
    var simplified = false
    /// 面板的大磁带：标签上沿留一条干净的白，歌名和时间由外面按实际字号盖上去
    /// （`labelStrip`），不画手写线和小方块。
    var labeled = false

    static let size = CGSize(width: 154, height: 96)
    /// 标签上沿那条白在 154×96 坐标里的位置（左上角 7,6，宽 140，高 18）。
    static let labelStrip = CGRect(x: 7, y: 6, width: 140, height: 18)

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
            if !simplified {
                ForEach([57.0, 97.0], id: \.self) { cx in
                    Circle().stroke(CassettePalette.rgb(60, 36, 20, 0.24), lineWidth: 0.8)
                        .frame(width: 54, height: 54)
                        .position(x: cx, y: 44)
                }
            }
            if simplified {
                // 精简标签：整张就是封面，上沿一条留白。
                ZStack(alignment: .topLeading) {
                    CassettePalette.label
                    CoverFill(image: track.artwork)
                        .frame(width: 140, height: 46)
                        .clipped()
                        .offset(y: 10)
                }
                .frame(width: 140, height: 56)
                .clipShape(label)
                .offset(x: 7, y: 6)
            } else {
                // 标签贴纸：上面一条留白（两道手写线），下面是封面。
                ZStack(alignment: .topLeading) {
                    CassettePalette.label
                    CoverFill(image: track.artwork)
                        .frame(width: 140, height: 38)
                        .clipped()
                        .offset(y: 18)
                    Rectangle().fill(CassettePalette.rgb(60, 40, 30, 0.35)).frame(width: 140, height: 0.5).offset(y: 18)
                    if !labeled {
                        RoundedRectangle(cornerRadius: 3).fill(CassettePalette.rgb(60, 44, 36))
                            .frame(width: 13, height: 13).offset(x: 3, y: 2.5)
                        Capsule().fill(CassettePalette.rgb(40, 30, 60, 0.55)).frame(width: 52, height: 1.6).offset(x: 22, y: 7)
                        Capsule().fill(CassettePalette.rgb(40, 30, 60, 0.35)).frame(width: 34, height: 1.4).offset(x: 22, y: 12)
                    }
                }
                .frame(width: 140, height: 56)
                .clipShape(label)
                .offset(x: 7, y: 6)
            }
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
            if !simplified { shellDetails }
        }
    }

    /// 磁头口的孔、四角螺丝和小熊猫小标，精简版不画。
    private var shellDetails: some View {
        ZStack(alignment: .topLeading) {
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
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
    }
}

/// 铜圈喇叭：网罩加中心纸盆，播放时纸盆小幅胀缩（不读音量）。
///
/// 网罩（几百个小孔）和铜圈不随时间变，画一次就合成一层缓存（`drawingGroup`），
/// 不进 `TimelineView`；每帧只重算纸盆的缩放，纸盆本身也只画一次，缩放是渲染变换。
struct Speaker: View {
    var diameter: CGFloat
    var playing: Bool
    var visible: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let fps = CassetteMotion.framesPerSecond(playing: playing, visible: visible, reduceMotion: reduceMotion)
        ZStack {
            SpeakerGrille(diameter: diameter)
                .equatable()
                .drawingGroup()
            TimelineView(.animation(minimumInterval: 1 / (fps ?? CassetteMotion.fps), paused: fps == nil)) { timeline in
                let scale = CassetteMotion.coneScale(t: timeline.date.timeIntervalSinceReferenceDate,
                                                     animating: fps != nil)
                SpeakerCone(radius: SpeakerGrille.coneRadius(diameter))
                    .equatable()
                    .scaleEffect(CGFloat(scale))
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }
}

/// 喇叭不动的部分：外圈、网罩小孔、铜圈和高光。输入只有直径，`Equatable` 让
/// 卡片每次读到新进度时也不重画。
private struct SpeakerGrille: View, Equatable {
    var diameter: CGFloat

    nonisolated static func == (a: SpeakerGrille, b: SpeakerGrille) -> Bool { a.diameter == b.diameter }

    /// 网罩半径（铜圈内沿）。
    static func radius(_ diameter: CGFloat) -> CGFloat { diameter / 2 - 1.5 }
    /// 纸盆静止时的半径。
    static func coneRadius(_ diameter: CGFloat) -> CGFloat { radius(diameter) * 0.34 }

    var body: some View {
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
            ctx.stroke(circle(r + 0.2), with: .color(CassettePalette.copper), lineWidth: 2.2)
            var glint = Path()
            glint.addArc(center: c, radius: r - 0.6, startAngle: .degrees(200), endAngle: .degrees(300),
                         clockwise: false)
            ctx.stroke(glint, with: .color(CassettePalette.rgb(255, 230, 170, 0.63)), lineWidth: 0.8)
        }
        .frame(width: diameter, height: diameter)
    }
}

/// 中心纸盆，按静止半径画一次；胀缩由外面的 `scaleEffect` 做。
private struct SpeakerCone: View, Equatable {
    var radius: CGFloat

    nonisolated static func == (a: SpeakerCone, b: SpeakerCone) -> Bool { a.radius == b.radius }

    var body: some View {
        let cone = radius
        ZStack {
            Circle().fill(CassettePalette.rgb(30, 30, 28, 0.9)).frame(width: (cone + 1.5) * 2, height: (cone + 1.5) * 2)
            Circle().fill(CassettePalette.rgb(58, 56, 52)).frame(width: cone * 2, height: cone * 2)
            Circle().fill(CassettePalette.rgb(24, 24, 22)).frame(width: cone * 0.84, height: cone * 0.84)
            // 左上角一点高光。
            Circle().fill(.white.opacity(0.2))
                .frame(width: cone * 0.28, height: cone * 0.28)
                .offset(x: -cone * 0.15, y: -cone * 0.18)
        }
        .frame(width: (cone + 1.5) * 2, height: (cone + 1.5) * 2)
    }
}

// MARK: - 玻璃键帽

/// 玻璃键帽：抬起时是一块亮一点的玻璃加底边投影，按下（或播放键在播时锁住）
/// 下沉 1pt、投影收短。珊瑚色只给播放键，是实色渐变，不发光。浅色、深色各一套，
/// 卡片和面板共用；字跟着外观走（浅色近黑、深色白），珊瑚键上是白字形。
struct GlassKeyStyle: ButtonStyle {
    var coral = false
    /// 播放键在播时锁住在下沉的位置。
    var latched = false
    /// 随机、循环开着时字形用珊瑚色（浅色下加深到能读）。
    var lit = false
    var corner: CGFloat = 10

    func makeBody(configuration: Configuration) -> some View {
        GlassKeyCap(label: configuration.label, coral: coral, down: latched || configuration.isPressed,
                    lit: lit, corner: corner)
    }
}

private struct GlassKeyCap<Label: View>: View {
    var label: Label
    var coral: Bool
    var down: Bool
    var lit: Bool
    var corner: CGFloat

    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        let light = scheme == .light
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        let fill: LinearGradient = coral
            ? LinearGradient(colors: [CassettePalette.coralTop.mix(with: .black, by: down ? 0.08 : 0),
                                      CassettePalette.coralBottom.mix(with: .black, by: down ? 0.1 : 0)],
                             startPoint: .top, endPoint: .bottom)
            : LinearGradient(colors: light
                             ? [.white.opacity(down ? 0.62 : 0.9), .white.opacity(down ? 0.5 : 0.66)]
                             : [.white.opacity(down ? 0.1 : 0.18), .white.opacity(down ? 0.06 : 0.09)],
                             startPoint: .top, endPoint: .bottom)
        let rim = LinearGradient(colors: coral
                                 ? [.white.opacity(0.45), .white.opacity(0.05)]
                                 : (light ? [.white, .white.opacity(0.35)] : [.white.opacity(0.28), .white.opacity(0.04)]),
                                 startPoint: .top, endPoint: .bottom)
        let ink: Color = coral ? .white
            // 开着的随机、循环：浅色下珊瑚压深（近白玻璃上约 5:1），深色下提亮（深玻璃上约 5:1），
            // 13pt 的字都过 4.5。
            : (lit ? (light ? CassettePalette.coralBottom.mix(with: .black, by: 0.18) : CassettePalette.rgb(255, 158, 128))
                   : (light ? Color(.sRGB, red: 0.094, green: 0.086, blue: 0.11) : .white))
        return label
            .foregroundStyle(ink.opacity(enabled ? 1 : 0.38))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                shape.fill(fill)
                    .overlay(shape.strokeBorder(rim, lineWidth: 0.7))
                    .overlay(shape.strokeBorder(.black.opacity(light ? 0.06 : 0.25), lineWidth: 0.5).padding(-0.5))
                    .shadow(color: .black.opacity(down ? (light ? 0.08 : 0.25) : (light ? 0.16 : 0.4)),
                            radius: down ? 0.8 : 2, y: down ? 0.5 : 1.6)
            }
            .offset(y: down ? 1 : 0)
            .contentShape(shape)
            .animation(.easeOut(duration: 0.08), value: down)
    }
}

/// 一个玻璃键：SF Symbol 或一两个字。
struct GlassKey: View {
    var symbol: String?
    var text: String?
    var label: String
    var coral = false
    var latched = false
    var lit = false
    var glyph: CGFloat = 15
    var corner: CGFloat = 10
    var action: (() -> Void)?

    var body: some View {
        Button(action: { action?() }) {
            Group {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: glyph, weight: .bold))
                        .contentTransition(.symbolEffect(.replace))
                } else if let text {
                    Text(text)
                        .font(.system(size: max(13, glyph - 1), weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }
            }
        }
        .buttonStyle(GlassKeyStyle(coral: coral, latched: latched, lit: lit, corner: corner))
        .disabled(action == nil)
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: - 和正在播放共用的读数

/// 复古卡带读正在播放同一个「当前显示来源」（服务的 `display`，Core `MusicDisplay.pick`），
/// 卡片、面板和正在播放显示的是同一首；控制也调同一套服务。
@MainActor
enum MusicNow {
    static func playing(browsersEnabled: Bool) -> Playing? {
        switch MusicService.shared.display {
        case .native(let source): return MusicService.shared.track(for: source).map(Playing.init(native:))
        case .browser: return browserTrack(browsersEnabled: browsersEnabled)
        case .none: return nil
        }
    }

    static func browserTrack(browsersEnabled: Bool) -> Playing? {
        guard browsersEnabled else { return nil }
        return BrowserMedia.shared.track.map {
            Playing(browser: $0, artwork: BrowserMedia.shared.artwork,
                    icon: BrowserMedia.shared.siteIcon, tint: BrowserMedia.shared.tint)
        }
    }

    static func needsPermission(browsersEnabled: Bool) -> Bool {
        MusicService.shared.needsAutomationPermission
            || (browsersEnabled && BrowserMedia.shared.needsPermission)
    }

    /// 只弹系统的「自动化」授权，并且只在用户点了「连接」时。
    static func requestPermission(browsersEnabled: Bool) {
        MusicService.shared.requestAutomationPermission()
        if browsersEnabled { BrowserMedia.shared.requestPermission() }
    }

    /// 播放暂停：网页标签页交给浏览器，播放器交给它自己的来源。
    static func toggle(_ track: Playing) {
        if track.isBrowser { BrowserMedia.shared.playPause() }
        else if let source = track.source { MusicService.shared.playPause(on: source) }
        else { MusicService.shared.playPause() }
    }

    /// 来源的小图标：浏览器是站点图标，其余是 App 图标。
    static func icon(_ track: Playing) -> NSImage? {
        track.icon ?? AppCatalog.shared.icon(forBundleID: track.sourceBundleID)
    }

    /// 卡片上画的这首；没在播放时机身照样摆着，写「未在播放」，转轮停在开头。
    static func cassetteTrack(_ track: Playing?, preview: Bool) -> CassetteTrack {
        guard let track else {
            return CassetteTrack(title: tr("未在播放"), artist: "", isPlaying: false, progress: 0,
                                 elapsed: 0, duration: 0, artwork: nil, sourceIcon: nil, showsTime: false)
        }
        return CassetteTrack(title: track.title, artist: track.artist, isPlaying: track.isPlaying,
                             progress: track.progress, elapsed: track.elapsed, duration: track.duration,
                             artwork: preview ? nil : track.artwork, sourceIcon: preview ? nil : icon(track),
                             showsTime: track.duration > 0)
    }

    /// 三个键：和正在播放卡片一样的媒体控制；网页视频只有播放暂停，设置里关掉的
    /// 上一首、下一首按不动。
    static func actions(_ track: Playing?, config: WidgetConfig, preview: Bool) -> CassetteActions {
        guard !preview, let track else { return CassetteActions() }
        let source = track.source
        let skips = track.hasSkipControls && source != nil
        return CassetteActions(
            previous: skips && config.bool("previous", default: true)
                ? { if let source { MusicService.shared.previous(on: source) } } : nil,
            toggle: { toggle(track) },
            next: skips && config.bool("next", default: true)
                ? { if let source { MusicService.shared.next(on: source) } } : nil)
    }
}
