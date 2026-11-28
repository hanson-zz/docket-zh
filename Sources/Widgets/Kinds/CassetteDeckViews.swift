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

/// The clear rim and exposed hardware surround opaque, readable player controls.
struct DeckAcrylicBody<Content: View>: View {
    var theme: CassetteDeckTheme
    @ViewBuilder var content: () -> Content

    private var palette: DeckPalette { DeckPalette(theme: theme) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        content()
            .padding(.leading, 13)
            .padding(.trailing, 51)
            .padding(.top, 38)
            .padding(.bottom, 24)
            .background {
                ZStack {
                    shape.fill(LinearGradient(colors: [palette.bodyTop.opacity(0.94), palette.bodyBottom],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                    DeckCircuit().padding(7)
                    DeckHardware(theme: theme)
                }
                .clipShape(shape)
            }
            .overlay {
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.88), palette.bodyEdge.opacity(0.4),
                                                           .white.opacity(0.65), palette.orangeTop.opacity(0.6)],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2)
                    .padding(3)
                    .overlay(shape.strokeBorder(.white.opacity(0.35), lineWidth: 0.6).padding(7))
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(theme == .pearl ? 0.18 : 0.4), radius: 12, y: 7)
            .environment(\.cassetteDeckTheme, theme)
            .environment(\.colorScheme, theme == .pearl ? .light : .dark)
    }
}

/// Static mechanical layers have no timer; only the existing tape reels animate.
private struct DeckHardware: View {
    var theme: CassetteDeckTheme

    var body: some View {
        Canvas { context, size in
            let metal = CassettePalette.rgb(184, 186, 180)
            let copper = CassettePalette.rgb(204, 113, 48)
            let orange = CassettePalette.rgb(255, 139, 35)
            func disk(_ center: CGPoint, _ radius: CGFloat, _ color: Color) {
                context.fill(Path(ellipseIn: CGRect(x: center.x-radius, y: center.y-radius,
                                                   width: radius*2, height: radius*2)), with: .color(color))
            }
            func gear(_ center: CGPoint, _ radius: CGFloat, teeth: Int) {
                var path = Path()
                for i in 0..<(teeth * 4) {
                    let angle = CGFloat(i) * .pi * 2 / CGFloat(teeth * 4)
                    let r = i % 4 < 2 ? radius : radius * 0.81
                    let point = CGPoint(x: center.x + cos(angle)*r, y: center.y + sin(angle)*r)
                    if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                path.closeSubpath()
                context.fill(path, with: .linearGradient(Gradient(colors: [.white, metal, .gray]),
                             startPoint: CGPoint(x: center.x-radius, y: center.y-radius),
                             endPoint: CGPoint(x: center.x+radius, y: center.y+radius)))
                context.stroke(path, with: .color(.black.opacity(0.5)), lineWidth: 0.6)
                disk(center, radius*0.55, metal.opacity(0.65))
                disk(center, radius*0.16, .black.opacity(0.75))
            }
            let x = size.width - 27
            for i in 0..<4 {
                gear(CGPoint(x: x + (i % 2 == 0 ? -2 : 3), y: 66 + CGFloat(i)*29),
                     CGFloat(i % 2 == 0 ? 15 : 12), teeth: 12)
            }
            gear(CGPoint(x: size.width*0.26, y: 24), 24, teeth: 20)
            var belt = Path()
            belt.move(to: CGPoint(x: size.width*0.13, y: 12))
            belt.addLine(to: CGPoint(x: size.width*0.51, y: 26))
            context.stroke(belt, with: .color(.black.opacity(0.72)), lineWidth: 3)
            let tube = CGRect(x: x-10, y: 218, width: 20, height: 80)
            context.fill(Path(roundedRect: tube, cornerRadius: 9),
                         with: .linearGradient(Gradient(colors: [metal, .black.opacity(0.6), metal]),
                                               startPoint: CGPoint(x: tube.minX, y: 0), endPoint: CGPoint(x: tube.maxX, y: 0)))
            context.fill(Path(roundedRect: tube.insetBy(dx: 7, dy: 10), cornerRadius: 3), with: .color(orange))
            context.stroke(Path(roundedRect: tube.insetBy(dx: 2, dy: 2), cornerRadius: 8),
                           with: .color(.white.opacity(0.7)), lineWidth: 0.7)
            for y in stride(from: CGFloat(328), to: size.height-35, by: 52) {
                let chip = CGRect(x: x-11, y: y, width: 22, height: 27)
                context.fill(Path(roundedRect: chip, cornerRadius: 2), with: .color(CassettePalette.rgb(32, 34, 33)))
                var pins = Path()
                for j in 0..<6 {
                    let py = y + 3 + CGFloat(j)*4
                    pins.move(to: CGPoint(x: chip.minX-3, y: py)); pins.addLine(to: CGPoint(x: chip.minX+2, y: py))
                    pins.move(to: CGPoint(x: chip.maxX-2, y: py)); pins.addLine(to: CGPoint(x: chip.maxX+3, y: py))
                }
                context.stroke(pins, with: .color(copper), lineWidth: 1)
            }
            var wiring = Path()
            wiring.move(to: CGPoint(x: size.width*0.5, y: 12))
            wiring.addLine(to: CGPoint(x: size.width*0.68, y: 12))
            wiring.addQuadCurve(to: CGPoint(x: x+13, y: 33), control: CGPoint(x: x+13, y: 12))
            wiring.addLine(to: CGPoint(x: x+13, y: size.height-15))
            wiring.addLine(to: CGPoint(x: size.width*0.6, y: size.height-15))
            context.stroke(wiring, with: .color(orange.opacity(0.9)),
                           style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
            for start in [size.width*0.23, size.width*0.43] {
                for j in 0..<14 {
                    let coil = CGRect(x: start + CGFloat(j)*2, y: size.height-22, width: 2, height: 12)
                    context.fill(Path(roundedRect: coil, cornerRadius: 1),
                                 with: .linearGradient(Gradient(colors: [copper, orange, copper]),
                                                       startPoint: coil.origin, endPoint: CGPoint(x: coil.minX, y: coil.maxY)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
        let corner: CGFloat = compact ? 7 : 11
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        GeometryReader { geo in
            let h = geo.size.height
            let labelH: CGFloat = compact ? 3 : 12
            let trapH = compact ? max(5, h * 0.12) : min(28, max(12, h * 0.17))
            let reelH = max(10, h - labelH - trapH - (compact ? 1 : 6))
            VStack(spacing: 0) {
                Spacer(minLength: 0).frame(height: labelH)
                reelWindow(height: reelH)
                    .frame(height: reelH)
                Spacer(minLength: 0)
                DeckTrapezoid(compact: compact)
                    .frame(width: geo.size.width * 0.74, height: trapH)
            }
            .frame(width: geo.size.width, height: h)
        }
        .background(shape.fill(LinearGradient(colors: [palette.tapeTop, palette.tapeBottom],
                                               startPoint: .top, endPoint: .bottom)))
        .overlay(shape.strokeBorder(.white.opacity(0.06), lineWidth: 0.6))
        .clipShape(shape)
        // 光叠在磁带仓外层，不被里面的东西盖住；不拦点击、读屏不读。
        .edgeBeam(active: track.isPlaying && visible, shape: .rounded(Double(corner)), tint: palette.beam)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(deckTheme.title)
    }

    /// 转轮窗：左边 A / B 面小方块，两个转轮。
    private func reelWindow(height: CGFloat) -> some View {
        let window = RoundedRectangle(cornerRadius: compact ? 4 : 7, style: .continuous)
        return HStack(spacing: compact ? 4 : 8) {
            Text(verbatim: deckTheme.side)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.highlightInk)
                .frame(width: compact ? 16 : 22, height: compact ? 16 : 22)
                .background(RoundedRectangle(cornerRadius: 2, style: .continuous).fill(palette.highlight.opacity(0.9)))
            DeckReels(playing: track.isPlaying, visible: visible)
                .background(window.fill(palette.window))
                .overlay(window.strokeBorder(.black.opacity(0.5), lineWidth: 0.6))
                .clipShape(window)
        }
        .padding(.horizontal, compact ? 6 : 12)
    }
}

/// 两个转轮：黑色轴座里一圈浅灰带齿的轮毂，播放时转、暂停停在原地。
struct DeckReels: View {
    @Environment(\.cassetteDeckTheme) private var deckTheme
    private var palette: DeckPalette { DeckPalette(theme: deckTheme) }

    var playing: Bool
    var visible: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spins = DeckSpins()

    var body: some View {
        let fps = CassetteMotion.framesPerSecond(playing: playing, visible: visible, reduceMotion: reduceMotion)
        TimelineView(.animation(minimumInterval: 1 / (fps ?? CassetteMotion.fps), paused: fps == nil)) { timeline in
            let degrees = spins.angle(at: timeline.date.timeIntervalSinceReferenceDate, moving: fps != nil)
            Canvas { ctx, size in
                let r = max(3, min(size.height * 0.44, size.width * 0.15))
                let cy = size.height / 2
                drawReel(ctx, center: CGPoint(x: size.width * 0.27, y: cy), radius: r, degrees: degrees)
                drawReel(ctx, center: CGPoint(x: size.width * 0.73, y: cy), radius: r, degrees: degrees + 23)
            }
        }
        .accessibilityHidden(true)
    }

    private func drawReel(_ ctx: GraphicsContext, center c: CGPoint, radius r: CGFloat, degrees: Double) {
        func circle(_ radius: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
        }
        ctx.fill(circle(r), with: .color(palette.socket))
        ctx.stroke(circle(r), with: .color(.white.opacity(0.06)), lineWidth: 0.6)
        ctx.fill(circle(r * 0.72), with: .color(palette.hubRing))
        ctx.fill(circle(r * 0.5), with: .color(palette.socket))
        var teeth = Path()
        for i in 0..<6 {
            let a = CGFloat((degrees + Double(i) * 60) * .pi / 180)
            teeth.move(to: CGPoint(x: c.x + cos(a) * r * 0.46, y: c.y + sin(a) * r * 0.46))
            teeth.addLine(to: CGPoint(x: c.x + cos(a) * r * 0.74, y: c.y + sin(a) * r * 0.74))
        }
        ctx.stroke(teeth, with: .color(palette.socket), lineWidth: max(0.8, r * 0.14))
        ctx.fill(circle(max(1, r * 0.15)), with: .color(palette.hubCenter))
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
