import AppKit
import SwiftUI

private struct CassetteDeckThemeKey: EnvironmentKey {
    static let defaultValue: CassetteDeckTheme = .mechanical
}

extension EnvironmentValues {
    var cassetteDeckTheme: CassetteDeckTheme {
        get { self[CassetteDeckThemeKey.self] }
        set { self[CassetteDeckThemeKey.self] = newValue }
    }
}

/// Separate chassis and tape-shell images contain no UI or transport controls.
@MainActor
enum DeckArtwork {
    private static var cache: [String: NSImage] = [:]

    static func image(_ part: String, theme: CassetteDeckTheme) -> NSImage? {
        let name = "deck-\(part)-\(theme.rawValue)"
        if let cached = cache[name] { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        cache[name] = image
        return image
    }
}

/// The chassis keeps the reference's 3:4 proportions. Its central opening is
/// transparent; the tape, rotating reels and player controls are separate layers.
struct DeckAcrylicBody<Content: View>: View {
    var theme: CassetteDeckTheme
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if let chassis = DeckArtwork.image("chassis", theme: theme) {
                    Image(nsImage: chassis).resizable().interpolation(.high)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                content()
                    .frame(width: geo.size.width * 0.718, height: geo.size.height * 0.748,
                           alignment: .top)
                    .offset(x: geo.size.width * 0.074, y: geo.size.height * 0.146)
            }
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .shadow(color: .black.opacity(theme == .pearl ? 0.2 : 0.4), radius: 10, y: 6)
        .environment(\.cassetteDeckTheme, theme)
        .environment(\.colorScheme, theme == .pearl ? .light : .dark)
    }
}

/// The lower plate is independent of the photographic chassis, so resizing,
/// text and every hit target remain native SwiftUI content.
struct DeckPlayerPlate<Content: View>: View {
    var theme: CassetteDeckTheme
    @ViewBuilder var content: () -> Content

    var body: some View {
        let palette = DeckPalette(theme: theme)
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        content()
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(shape.fill(LinearGradient(colors: [palette.tapeTop, palette.tapeBottom],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.85), .white.opacity(0.05), .black.opacity(0.3)],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
    }
}

/// Physical round keys match both themes without changing playback routing.
struct DeckTransportStyle: ButtonStyle {
    var theme: CassetteDeckTheme
    var primary = false
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        let palette = DeckPalette(theme: theme)
        return configuration.label
            .foregroundStyle(primary ? .white : active ? palette.orangeTop : palette.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                Circle().fill(LinearGradient(colors: primary ? [Color(red: 1, green: 0.59, blue: 0.2), palette.orangeBottom] : [palette.tapeTop, palette.tapeBottom],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(Circle().strokeBorder(.white.opacity(theme == .pearl ? 0.8 : 0.25), lineWidth: 0.8).padding(0.8))
                    .overlay(Circle().strokeBorder(.black.opacity(0.2), lineWidth: 0.5))
            }
            .shadow(color: primary ? palette.orangeTop.opacity(0.25) : .black.opacity(0.18), radius: primary ? 7 : 2, y: 2)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// Only the handle position changes; dragging uses the panel's existing seek handler.
struct DeckSlider: View {
    var value: Double
    var theme: CassetteDeckTheme

    var body: some View {
        GeometryReader { geo in
            let progress = min(1, max(0, value))
            let palette = DeckPalette(theme: theme)
            ZStack(alignment: .leading) {
                Capsule().fill(palette.ink.opacity(0.18)).frame(height: 3)
                    .overlay(Capsule().strokeBorder(.black.opacity(0.15), lineWidth: 0.5))
                Capsule().fill(LinearGradient(colors: [palette.orangeBottom, palette.orangeTop],
                                             startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, geo.size.width * progress), height: 3)
                Circle().fill(LinearGradient(colors: [.white, Color(white: 0.77)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 0.6))
                    .shadow(color: .black.opacity(0.22), radius: 1.5, y: 1)
                    .frame(width: 10, height: 10)
                    .offset(x: max(0, geo.size.width - 10) * progress)
            }
            .frame(height: 14)
            .contentShape(Rectangle())
        }
        .frame(height: 14)
    }
}

// 「复古卡带」第四种机型「机芯卡座」（`CassetteModel.deck`）的零件：深炭黑哑光机身、
// 露出来的电路板走线和小螺丝、圆旋钮、橙色拨动开关、三个圆玻璃键，中间一盒黑磁带
// （A/B 面小方块、两个转轮、下沿梯形带竖纹和四个小孔），曲目只放在操作区。
//
// 机身是实物，颜色写死，不随浅深色变（整块按深色画，沿边流光也按深色的样子画）。
// 转轮只在「在播 + 看得见 + 没开减少动态效果」时转（`CassetteMotion.framesPerSecond`）；
// 沿边流光播放时绕、暂停时淡出，减弱动态效果时只留一道静止的光（`.edgeBeam`）。
// 最小字 13pt；A/B 外观由对应小组件的配置决定。

/// 机芯卡座的配色：全是低对比的深灰，只有拨动开关是橙色。
struct DeckPalette {
    var theme: CassetteDeckTheme
    var bodyTop: Color { theme == .pearl ? CassettePalette.rgb(237, 233, 226) : CassettePalette.rgb(38, 38, 40) }
    var bodyBottom: Color { theme == .pearl ? CassettePalette.rgb(202, 200, 194) : CassettePalette.rgb(25, 25, 27) }
    var bodyEdge: Color { theme == .pearl ? CassettePalette.rgb(132, 132, 129) : CassettePalette.rgb(10, 10, 11) }
    var trace: Color { theme == .pearl ? CassettePalette.rgb(175, 103, 53) : CassettePalette.rgb(56, 56, 60) }
    var pad: Color { theme == .pearl ? CassettePalette.rgb(203, 139, 74) : CassettePalette.rgb(68, 68, 72) }
    var chip: Color { theme == .pearl ? CassettePalette.rgb(62, 65, 65) : CassettePalette.rgb(46, 46, 49) }
    var screw: Color { theme == .pearl ? CassettePalette.rgb(193, 195, 192) : CassettePalette.rgb(62, 62, 66) }
    var screwSlot: Color { theme == .pearl ? CassettePalette.rgb(61, 65, 65) : CassettePalette.rgb(26, 26, 28) }
    var tapeTop: Color { theme == .pearl ? CassettePalette.rgb(249, 246, 240) : CassettePalette.rgb(24, 24, 26) }
    var tapeBottom: Color { theme == .pearl ? CassettePalette.rgb(220, 214, 204) : CassettePalette.rgb(15, 15, 16) }
    var window: Color { theme == .pearl ? CassettePalette.rgb(73, 71, 68) : CassettePalette.rgb(30, 30, 32) }
    var socket: Color { theme == .pearl ? CassettePalette.rgb(25, 26, 28) : CassettePalette.rgb(18, 18, 19) }
    var hubRing: Color { theme == .pearl ? CassettePalette.rgb(202, 204, 199) : CassettePalette.rgb(156, 156, 152) }
    var hubCenter: Color { theme == .pearl ? CassettePalette.rgb(235, 233, 225) : CassettePalette.rgb(206, 206, 200) }
    var ink: Color { theme == .pearl ? CassettePalette.rgb(37, 39, 40) : CassettePalette.rgb(204, 204, 198) }
    var highlight: Color { theme == .pearl ? CassettePalette.rgb(69, 71, 71) : CassettePalette.rgb(226, 224, 216) }
    var highlightInk: Color { theme == .pearl ? CassettePalette.rgb(248, 245, 237) : CassettePalette.rgb(14, 14, 14) }
    var orangeTop: Color { CassettePalette.rgb(242, 126, 44) }
    var orangeBottom: Color { CassettePalette.rgb(214, 96, 24) }
    var beam: Color { theme == .pearl ? CassettePalette.rgb(255, 148, 55) : CassettePalette.rgb(240, 238, 230) }
}

// MARK: - 整台机器

/// 一台机芯卡座。
/// - `strip`：扩展栏横排、桌面中号那种矮条：左边旋钮和拨动开关上下摆，中间一盒磁带
///   （标签一行），右边三个玻璃键（`actions` 为 nil 时不画键）。
/// - `full`：面板、桌面大号：顶上一排旋钮、拨动开关、三个玻璃键，下面整盒磁带。
struct DeckMachine: View {
    var theme: CassetteDeckTheme = .mechanical
    private var palette: DeckPalette { DeckPalette(theme: theme) }

    enum Layout { case strip, full }

    var track: CassetteTrack
    var lines: [CassetteDeck.Line]
    var layout: Layout
    var visible: Bool
    var actions: CassetteActions?
    /// 顶上（或右边）玻璃键的直径。
    var keySize: CGFloat = 30
    /// `full` 时磁带的高度；nil 时占满剩下的高度（外面给了框）。
    var tapeHeight: CGFloat?
    var corner: CGFloat = 12

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        Group {
            switch layout {
            case .strip: strip
            case .full: full
            }
        }
        .background(DeckCircuit().clipShape(shape))
        .background(shape.fill(LinearGradient(colors: [palette.bodyTop, palette.bodyBottom],
                                               startPoint: .top, endPoint: .bottom)))
        .overlay(shape.strokeBorder(.white.opacity(0.07), lineWidth: 0.6).padding(1))
        .overlay(shape.strokeBorder(palette.bodyEdge, lineWidth: 0.8))
        .shadow(color: .black.opacity(0.3), radius: 3, y: 1.5)
        .environment(\.cassetteDeckTheme, theme)
        .environment(\.colorScheme, theme == .pearl ? .light : .dark)
    }

    private var strip: some View {
        HStack(spacing: 8) {
            VStack(spacing: 5) {
                DeckKnob(diameter: 18)
                DeckSwitch(on: track.isPlaying, width: 26)
            }
            .padding(.leading, 2)
            DeckTape(track: track, lines: lines, compact: true, visible: visible)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let actions {
                DeckKeys(track: track, actions: actions, size: keySize, spacing: 4)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
    }

    private var full: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                DeckKnob(diameter: min(26, keySize * 0.8))
                DeckSwitch(on: track.isPlaying, width: 38)
                Spacer(minLength: 6)
                if let actions {
                    DeckKeys(track: track, actions: actions, size: keySize, spacing: 6)
                }
            }
            .frame(height: keySize)
            .padding(.horizontal, 2)
            DeckTape(track: track, lines: lines, compact: false, visible: visible)
                .frame(maxWidth: .infinity)
                .frame(height: tapeHeight)
                .frame(maxHeight: tapeHeight == nil ? CGFloat.infinity : nil)
        }
        .padding(10)
    }
}

/// 扩展栏在左右两侧的竖条：一小块卡座机身（两个转轮、A 面小方块）、歌名一行、圆玻璃播放键。
struct DeckColumnFace: View {
    var theme: CassetteDeckTheme = .mechanical
    private var palette: DeckPalette { DeckPalette(theme: theme) }

    var track: CassetteTrack
    var actions: CassetteActions
    var visible: Bool

    var body: some View {
        VStack(spacing: 5) {
            mini
                .frame(width: 60, height: 34)
            Text(track.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WidgetStyle.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            DeckGlassButton(symbol: track.isPlaying ? "pause.fill" : "play.fill",
                            label: track.isPlaying ? tr("暂停") : tr("播放"), size: 28, action: actions.toggle)
        }
        .padding(.vertical, 4)
        .environment(\.cassetteDeckTheme, theme)
    }

    private var mini: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let window = RoundedRectangle(cornerRadius: 5, style: .continuous)
        return DeckReels(playing: track.isPlaying, visible: visible)
            .background(window.fill(palette.window))
            .clipShape(window)
            .padding(4)
            .background(DeckCircuit().clipShape(shape))
            .background(shape.fill(LinearGradient(colors: [palette.bodyTop, palette.bodyBottom],
                                                  startPoint: .top, endPoint: .bottom)))
            .overlay(shape.strokeBorder(palette.bodyEdge, lineWidth: 0.8))
            .edgeBeam(active: track.isPlaying && visible, shape: .rounded(8), tint: palette.beam)
            .environment(\.cassetteDeckTheme, theme)
        .environment(\.colorScheme, theme == .pearl ? .light : .dark)
            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            .accessibilityHidden(true)
    }
}

// MARK: - 磁带

/// 磁带本体只保留面标识、双卷轴和机械装饰，不绘制曲目信息。
/// 下沿梯形带竖纹和四个小孔。沿边一道细白光叠在最外层，播放时流动、暂停时淡出。
struct DeckTape: View {
    @Environment(\.cassetteDeckTheme) private var deckTheme
    private var palette: DeckPalette { DeckPalette(theme: deckTheme) }

    var track: CassetteTrack
    var lines: [CassetteDeck.Line]
    /// 矮条（扩展栏、桌面中号）：梯形压得很扁。
    var compact: Bool
    var visible: Bool


    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .topLeading) {
                if let shell = DeckArtwork.image("shell", theme: deckTheme) {
                    Image(nsImage: shell).resizable().interpolation(.high)
                } else {
                    RoundedRectangle(cornerRadius: compact ? 5 : 10)
                        .fill(palette.tapeTop)
                }
                DeckReels(playing: track.isPlaying, visible: visible, tapeVisible: true)
                    .frame(width: w * 0.63, height: h * 0.30)
                    .offset(x: w * 0.225, y: h * 0.30)
                Text(verbatim: deckTheme.side)
                    .font(.system(size: compact ? 9 : max(13, w * 0.065), weight: .medium))
                    .foregroundStyle(palette.highlightInk)
                    .frame(width: w * 0.085, height: w * 0.10)
                    .background(RoundedRectangle(cornerRadius: 2).fill(palette.highlight))
                    .offset(x: w * 0.105, y: h * 0.20)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(deckTheme.title)
    }

}

/// 两个转轮：黑色轴座里一圈浅灰带齿的轮毂，播放时转、暂停停在原地。
struct DeckReels: View {
    @Environment(\.cassetteDeckTheme) private var deckTheme
    private var palette: DeckPalette { DeckPalette(theme: deckTheme) }

    var playing: Bool
    var visible: Bool
    var tapeVisible = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spins = DeckSpins()

    var body: some View {
        let fps = CassetteMotion.framesPerSecond(playing: playing, visible: visible, reduceMotion: reduceMotion)
        TimelineView(.animation(minimumInterval: 1 / (fps ?? CassetteMotion.fps), paused: fps == nil)) { timeline in
            let degrees = spins.angle(at: timeline.date.timeIntervalSinceReferenceDate, moving: fps != nil)
            Canvas { ctx, size in
                let r = max(3, min(size.height * 0.49, size.width * 0.19))
                let cy = size.height / 2
                if tapeVisible {
                    let tape = CGRect(x: size.width * 0.39, y: size.height * 0.16,
                                      width: size.width * 0.22, height: size.height * 0.68)
                    ctx.fill(Path(roundedRect: tape, cornerRadius: 2),
                             with: .linearGradient(Gradient(colors: [Color(red: 0.17, green: 0.10, blue: 0.07), Color(red: 0.37, green: 0.21, blue: 0.12), Color(red: 0.12, green: 0.10, blue: 0.09)]),
                                                   startPoint: tape.origin, endPoint: CGPoint(x: tape.maxX, y: tape.minY)))
                    var bands = Path()
                    for x in stride(from: tape.minX + 1, to: tape.maxX, by: 2) {
                        bands.move(to: CGPoint(x: x, y: tape.minY)); bands.addLine(to: CGPoint(x: x, y: tape.maxY))
                    }
                    ctx.stroke(bands, with: .color(.black.opacity(0.16)), lineWidth: 0.4)
                }
                drawReel(ctx, center: CGPoint(x: size.width * 0.18, y: cy), radius: r, degrees: degrees)
                drawReel(ctx, center: CGPoint(x: size.width * 0.82, y: cy), radius: r, degrees: degrees + 23)
            }
        }
        .accessibilityHidden(true)
    }

    private func drawReel(_ ctx: GraphicsContext, center c: CGPoint, radius r: CGFloat, degrees: Double) {
        func circle(_ radius: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
        }
        let edge = Gradient(colors: [Color(white: 0.18), Color(white: 0.78), Color(white: 0.3), Color(white: 0.94), Color(white: 0.18)])
        ctx.fill(circle(r), with: .linearGradient(edge,
                 startPoint: CGPoint(x: c.x-r, y: c.y-r), endPoint: CGPoint(x: c.x+r, y: c.y+r)))
        ctx.fill(circle(r * 0.88), with: .color(Color(white: 0.055)))
        ctx.fill(circle(r * 0.77), with: .linearGradient(Gradient(colors: [Color(white: 0.96), Color(white: 0.48), Color(white: 0.82)]),
                 startPoint: CGPoint(x: c.x-r, y: c.y-r), endPoint: CGPoint(x: c.x+r, y: c.y+r)))
        ctx.fill(circle(r * 0.55), with: .color(Color(white: 0.045)))
        var teeth = Path()
        for i in 0..<8 {
            let a = CGFloat((degrees + Double(i) * 45) * .pi / 180)
            teeth.move(to: CGPoint(x: c.x + cos(a) * r * 0.53, y: c.y + sin(a) * r * 0.53))
            teeth.addLine(to: CGPoint(x: c.x + cos(a) * r * 0.79, y: c.y + sin(a) * r * 0.79))
        }
        ctx.stroke(teeth, with: .color(Color(white: 0.045)), lineWidth: max(1, r * 0.16))
        ctx.fill(circle(r * 0.19), with: .linearGradient(Gradient(colors: [.white, Color(white: 0.52)]),
                 startPoint: CGPoint(x: c.x, y: c.y-r), endPoint: CGPoint(x: c.x, y: c.y+r)))
        ctx.stroke(circle(r * 0.19), with: .color(.black.opacity(0.5)), lineWidth: 0.5)

    }
}

/// 转轮的累计角度（两个轮子一起转），只在 TimelineView 取帧时改，不引起重画。
private final class DeckSpins {
    private var spin = CassetteMotion.Spin(phase: 12)
    private let rate = 150.0

    func angle(at t: Double, moving: Bool) -> Double {
        guard moving else {
            spin.pause(at: t)
            return spin.restingAngle
        }
        return spin.angle(at: t, degreesPerSecond: rate)
    }
}

/// 磁带下沿的梯形：竖纹和四个小孔（外面两个低一点）。
private struct DeckTrapezoid: View {
    @Environment(\.cassetteDeckTheme) private var deckTheme
    private var palette: DeckPalette { DeckPalette(theme: deckTheme) }

    var compact: Bool

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let inset = min(w * 0.08, h * 0.9)
            var shape = Path()
            shape.move(to: CGPoint(x: inset, y: 0))
            shape.addLine(to: CGPoint(x: w - inset, y: 0))
            shape.addLine(to: CGPoint(x: w, y: h))
            shape.addLine(to: CGPoint(x: 0, y: h))
            shape.closeSubpath()
            ctx.fill(shape, with: .color(palette.tapeBottom))
            ctx.stroke(shape, with: .color(.white.opacity(0.05)), lineWidth: 0.6)
            if h >= 8 {
                var ribs = Path()
                var x = inset * 0.5 + 2
                while x < w - 2 {
                    ribs.move(to: CGPoint(x: x, y: 1))
                    ribs.addLine(to: CGPoint(x: x, y: h - 1))
                    x += 3
                }
                ctx.drawLayer { layer in
                    layer.clip(to: shape)
                    layer.stroke(ribs, with: .color(.black.opacity(0.35)), lineWidth: 0.7)
                }
            }
            let hole = max(1.2, min(h * 0.2, 4))
            let spots: [(CGFloat, CGFloat)] = [(0.2, 0.62), (0.36, 0.48), (0.64, 0.48), (0.8, 0.62)]
            for (fx, fy) in spots {
                let c = CGPoint(x: w * fx, y: h * fy)
                let outer = Path(ellipseIn: CGRect(x: c.x - hole * 1.5, y: c.y - hole * 1.5,
                                                   width: hole * 3, height: hole * 3))
                let inner = Path(ellipseIn: CGRect(x: c.x - hole, y: c.y - hole, width: hole * 2, height: hole * 2))
                if !compact { ctx.fill(outer, with: .color(palette.socket)) }
                ctx.fill(inner, with: .color(CassettePalette.rgb(120, 120, 118)))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 机身上的零件

/// 露出来的电路板：几道走线、焊盘、小芯片和四颗小螺丝，低对比深灰，只当底纹。
struct DeckCircuit: View {
    @Environment(\.cassetteDeckTheme) private var deckTheme
    private var palette: DeckPalette { DeckPalette(theme: deckTheme) }

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: w * x, y: h * y) }
            let runs: [[(CGFloat, CGFloat)]] = [
                [(0.02, 0.32), (0.07, 0.32), (0.11, 0.16), (0.30, 0.16)],
                [(0.20, 0.07), (0.34, 0.07), (0.38, 0.13), (0.56, 0.13)],
                [(0.58, 0.05), (0.70, 0.05), (0.74, 0.11), (0.80, 0.11)],
                [(0.975, 0.22), (0.975, 0.58), (0.94, 0.66), (0.94, 0.92)],
                [(0.025, 0.46), (0.025, 0.78), (0.055, 0.84), (0.055, 0.96)],
                [(0.30, 0.975), (0.52, 0.975), (0.56, 0.955), (0.72, 0.955)],
            ]
            var traces = Path()
            var pads = Path()
            for run in runs {
                guard let first = run.first, let last = run.last else { continue }
                traces.move(to: p(first.0, first.1))
                for point in run.dropFirst() { traces.addLine(to: p(point.0, point.1)) }
                for end in [first, last] {
                    let c = p(end.0, end.1)
                    pads.addRect(CGRect(x: c.x - 1.5, y: c.y - 1.5, width: 3, height: 3))
                }
            }
            ctx.stroke(traces, with: .color(palette.trace), lineWidth: 0.8)
            ctx.fill(pads, with: .color(palette.pad))
            // 小芯片和贴片元件。
            let chips: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
                (0.42, 0.04, 8, 6), (0.86, 0.06, 5, 4), (0.015, 0.6, 4, 7), (0.965, 0.75, 4, 6), (0.64, 0.965, 7, 3),
            ]
            for chip in chips {
                let c = p(chip.0, chip.1)
                let rect = CGRect(x: c.x - chip.2 / 2, y: c.y - chip.3 / 2, width: chip.2, height: chip.3)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(palette.chip))
                ctx.stroke(Path(roundedRect: rect, cornerRadius: 1), with: .color(palette.trace), lineWidth: 0.5)
            }
            // 四角小螺丝。
            let inset: CGFloat = 5
            for c in [CGPoint(x: inset, y: inset), CGPoint(x: w - inset, y: inset),
                      CGPoint(x: inset, y: h - inset), CGPoint(x: w - inset, y: h - inset)] {
                let r: CGFloat = 2.4
                let head = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                ctx.fill(head, with: .color(palette.screw))
                ctx.stroke(head, with: .color(palette.screwSlot), lineWidth: 0.5)
                var slot = Path()
                slot.move(to: CGPoint(x: c.x - r * 0.6, y: c.y - r * 0.6))
                slot.addLine(to: CGPoint(x: c.x + r * 0.6, y: c.y + r * 0.6))
                ctx.stroke(slot, with: .color(palette.screwSlot), lineWidth: 0.7)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 左上角的圆旋钮（只是样子，不能拧）。
struct DeckKnob: View {
    @Environment(\.cassetteDeckTheme) private var deckTheme
    private var palette: DeckPalette { DeckPalette(theme: deckTheme) }

    var diameter: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(palette.bodyEdge)
            Circle()
                .fill(RadialGradient(colors: [palette.hubCenter, palette.screw],
                                     center: UnitPoint(x: 0.4, y: 0.32), startRadius: 0, endRadius: diameter * 0.6))
                .padding(1.5)
            Circle().strokeBorder(.white.opacity(0.08), lineWidth: 0.6).padding(2)
            Circle().fill(CassettePalette.rgb(22, 22, 24)).frame(width: diameter * 0.56, height: diameter * 0.56)
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: .black.opacity(0.45), radius: 1.2, y: 0.8)
        .accessibilityHidden(true)
    }
}

/// 橙色拨动开关：播放中拨到开（橙色、拨块在右），暂停拨到关（深灰、拨块在左）。只是指示。
struct DeckSwitch: View {
    @Environment(\.cassetteDeckTheme) private var deckTheme
    private var palette: DeckPalette { DeckPalette(theme: deckTheme) }

    var on: Bool
    var width: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let height = width * 0.5
        ZStack(alignment: on ? .trailing : .leading) {
            Capsule()
                .fill(LinearGradient(colors: on ? [palette.orangeTop, palette.orangeBottom]
                                                : [CassettePalette.rgb(64, 64, 68), CassettePalette.rgb(44, 44, 47)],
                                     startPoint: .top, endPoint: .bottom))
            Capsule().strokeBorder(.black.opacity(0.45), lineWidth: 0.6)
            Circle()
                .fill(LinearGradient(colors: [CassettePalette.rgb(238, 238, 234), CassettePalette.rgb(186, 186, 182)],
                                     startPoint: .top, endPoint: .bottom))
                .padding(height * 0.12)
                .frame(width: height, height: height)
                .shadow(color: .black.opacity(0.35), radius: 0.8, y: 0.5)
        }
        .frame(width: width, height: height)
        .padding(2)
        .background(Capsule().fill(palette.bodyEdge))
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: on)
        .accessibilityHidden(true)
    }
}

/// 三个圆玻璃键：上一首、播放暂停、下一首。nil 的键画成按不动的样子。
struct DeckKeys: View {
    var track: CassetteTrack
    var actions: CassetteActions
    var size: CGFloat
    var spacing: CGFloat = 5

    var body: some View {
        HStack(spacing: spacing) {
            DeckGlassButton(symbol: "backward.end.fill", label: tr("上一首"), size: size, action: actions.previous)
            DeckGlassButton(symbol: track.isPlaying ? "pause.fill" : "play.fill",
                            label: track.isPlaying ? tr("暂停") : tr("播放"), size: size, action: actions.toggle)
            DeckGlassButton(symbol: "forward.end.fill", label: tr("下一首"), size: size, action: actions.next)
        }
    }
}

/// 一个圆玻璃键：黑色外圈、深色玻璃面、上沿一道弧形高光，按下微微缩小。
struct DeckGlassButton: View {
    @Environment(\.cassetteDeckTheme) private var deckTheme
    private var palette: DeckPalette { DeckPalette(theme: deckTheme) }

    var symbol: String
    var label: String
    var size: CGFloat
    var action: (() -> Void)?

    var body: some View {
        Button(action: { action?() }) {
            Image(systemName: symbol)
                .font(.system(size: max(10, size * 0.36), weight: .bold))
                .foregroundStyle(palette.ink)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(DeckGlassStyle())
        .disabled(action == nil)
        .help(label)
        .accessibilityLabel(label)
    }
}

private struct DeckGlassStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        DeckGlassCap(label: configuration.label, down: configuration.isPressed)
    }
}

private struct DeckGlassCap<Label: View>: View {
    @Environment(\.cassetteDeckTheme) private var deckTheme
    private var palette: DeckPalette { DeckPalette(theme: deckTheme) }

    var label: Label
    var down: Bool

    @Environment(\.isEnabled) private var enabled

    var body: some View {
        label
            .background {
                ZStack {
                    Circle().fill(palette.bodyEdge)
                    Circle()
                        .fill(RadialGradient(colors: [palette.tapeTop, palette.tapeBottom],
                                             center: UnitPoint(x: 0.5, y: 0.28), startRadius: 0, endRadius: 22))
                        .padding(2.5)
                }
            }
            .overlay {
                ZStack {
                    // 上沿弧形高光和下沿一点反光：玻璃的样子。
                    Circle().trim(from: 0.6, to: 0.9)
                        .stroke(.white.opacity(down ? 0.18 : 0.34), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                        .padding(5)
                    Circle().trim(from: 0.15, to: 0.35)
                        .stroke(.white.opacity(0.12), style: StrokeStyle(lineWidth: 0.8, lineCap: .round))
                        .padding(4)
                    Circle().strokeBorder(.white.opacity(0.1), lineWidth: 0.6).padding(2.5)
                }
                .allowsHitTesting(false)
            }
            .scaleEffect(down ? 0.95 : 1)
            .opacity(enabled ? 1 : 0.45)
            .shadow(color: .black.opacity(0.4), radius: down ? 0.5 : 1.5, y: down ? 0.3 : 1)
            .animation(.snappy(duration: 0.12), value: down)
    }
}

// MARK: - 标签读数

@MainActor
enum DeckLabel {
    /// 标签上的几行：正在放的一行，`limit` 大于 1 时再接「接下来」（只有 Apple 音乐读得到，
    /// 随机播放时没有固定顺序，不列）。预览用样例。
    static func lines(_ track: Playing?, deck: CassetteTrack, preview: Bool, limit: Int) -> [CassetteDeck.Line] {
        if preview {
            let sample = [CassetteDeck.Entry(title: tr("晚风轻拂"), artist: tr("林间乐队")),
                          CassetteDeck.Entry(title: tr("退潮"), artist: tr("林间乐队"))]
            return CassetteDeck.lines(title: deck.title, artist: deck.artist, upNext: sample, limit: limit,
                                      startNumber: 4)
        }
        var next: [CassetteDeck.Entry] = []
        if limit > 1, let track, !track.isBrowser, let source = track.source, source.hasUpNext,
           let native = track.native, MusicUpNext.visible(shuffle: native.shuffle ?? false) {
            next = (MusicService.shared.upNext?.items ?? []).map {
                CassetteDeck.Entry(title: $0.title, artist: $0.artist)
            }
        }
        return CassetteDeck.lines(title: deck.title, artist: deck.artist, upNext: next, limit: limit)
    }
}
