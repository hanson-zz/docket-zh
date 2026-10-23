import SwiftUI

// 纪念日的沙漏、事件小图标和当天的彩纸。卡片、面板、多个面板的高亮行共用。
//
// - 两种沙漏（`AnniversaryLook`）：线条沙漏单色描边、平涂沙；玻璃沙漏是半透明玻璃泡、
//   左侧弧形高光、两根立柱和带亮边的端盖，端盖用事件色。沙一律是自然沙色，临近时变暖橙。
// - 沙量和形状都来自 Core（`AnniversarySand`、`HourglassGeometry`），这里只按数画。
// - 沙流：平常是一根静止细线；临近时三颗沙粒往下落（`Anniversary.flowDots`），
//   只在 `animate` 为真（卡片看得见、没开减少动态效果）时走 `TimelineView`，
//   其余时候三颗沙粒停在固定位置。没有常驻的 repeatForever。

/// 沙的颜色：自然沙色，临近时暖橙。
enum AnniversarySandColor {
    static let sand = Color(hex: "#D8B47A")
    static let sandDeep = Color(hex: "#BC9256")
    static let sandDark = Color(hex: "#E2C08A")
    static let sandDeepDark = Color(hex: "#C49C62")
    static let warm = Color(hex: "#FF8024")
    static let warmDeep = Color(hex: "#E8541E")

    static func fill(near: Bool, dark: Bool) -> Color {
        near ? warm : (dark ? sandDark : sand)
    }

    static func deep(near: Bool, dark: Bool) -> Color {
        near ? warmDeep : (dark ? sandDeepDark : sandDeep)
    }

    /// 暖橙写成字：浅色底上加深（#B4400A 在近白上约 5.4），深色底上提亮。
    static func warmInk(dark: Bool) -> Color {
        dark ? Color(hex: "#FFA25C") : Color(hex: "#B4400A")
    }

    /// 进度条、细线用的沙色：浅色下深一档才看得清。
    static func bar(near: Bool, dark: Bool) -> Color {
        near ? warmDeep : (dark ? sandDark : sandDeep)
    }
}

/// 一只沙漏。尺寸由外面给（宽高比约 0.55 到 0.6 好看）。
struct AnniversaryHourglass: View {
    var look: AnniversaryLook
    var sand: AnniversarySand
    /// 玻璃沙漏端盖的颜色（事件色）；线条沙漏不用。
    var cap: Color
    /// 临近时沙粒能不能落：卡片看得见、没开减少动态效果。
    var animate: Bool

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let near = sand.mood == .near
        let glass = look == .glass
        ZStack {
            Canvas { context, size in
                HourglassPainter(size: size, sand: sand, glass: glass, dark: dark, cap: cap)
                    .draw(in: &context)
            }
            if sand.flows, near {
                if animate {
                    TimelineView(.animation(minimumInterval: 1 / 15)) { timeline in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        Canvas { context, size in
                            HourglassPainter(size: size, sand: sand, glass: glass, dark: dark, cap: cap)
                                .drawDots(Anniversary.flowDots(t: t), in: &context)
                        }
                    }
                } else {
                    Canvas { context, size in
                        HourglassPainter(size: size, sand: sand, glass: glass, dark: dark, cap: cap)
                            .drawDots([0.25, 0.5, 0.75], in: &context)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// 按 `HourglassGeometry` 画沙漏，比例和效果图一致。
private struct HourglassPainter {
    var size: CGSize
    var sand: AnniversarySand
    var glass: Bool
    var dark: Bool
    var cap: Color

    private let samples = 24

    private var w: Double { Double(size.width) }
    private var h: Double { Double(size.height) }
    private var cx: Double { w / 2 }
    private var capH: Double { max(2.4, h * 0.07) }
    private var y0: Double { capH }
    private var y1: Double { h - capH }
    private var mid: Double { (y0 + y1) / 2 }
    private var half: Double { w / 2 - max(1.5, w * (glass ? 0.1 : 0.06)) }
    private var neck: Double { max(0.9, w * 0.045) }

    private func hw(_ t: Double) -> Double { HourglassGeometry.halfWidth(t: t, half: half, neck: neck) }

    /// 上半泡：t 为 0 在上端口，1 在细腰。
    private func upperY(_ t: Double) -> Double { y0 + (mid - y0) * t }
    /// 下半泡：t 为 0 在下端口，1 在细腰。
    private func lowerY(_ t: Double) -> Double { y1 - (y1 - mid) * t }

    private var near: Bool { sand.mood == .near }
    private var sandFill: Color { AnniversarySandColor.fill(near: near, dark: dark) }
    private var sandDeep: Color { AnniversarySandColor.deep(near: near, dark: dark) }

    private var outline: Path {
        var path = Path()
        for i in 0...samples {
            let t = Double(i) / Double(samples)
            let p = CGPoint(x: cx - hw(t), y: upperY(t))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        for i in stride(from: samples, through: 0, by: -1) {
            let t = Double(i) / Double(samples)
            path.addLine(to: CGPoint(x: cx - hw(t), y: lowerY(t)))
        }
        for i in 0...samples {
            let t = Double(i) / Double(samples)
            path.addLine(to: CGPoint(x: cx + hw(t), y: lowerY(t)))
        }
        for i in stride(from: samples, through: 0, by: -1) {
            let t = Double(i) / Double(samples)
            path.addLine(to: CGPoint(x: cx + hw(t), y: upperY(t)))
        }
        path.closeSubpath()
        return path
    }

    /// 下半沙堆顶（沙流落到的地方），没有沙时是底。
    private var pileTop: Double {
        let filled = HourglassGeometry.lowerHeight(filled: sand.lower)
        guard filled > 0 else { return y1 - 1 }
        let edge = lowerY(filled)
        return max(mid + 1, edge - min(h * 0.09, (y1 - mid) * 0.22))
    }

    func draw(in context: inout GraphicsContext) {
        let shape = outline
        if glass {
            context.fill(shape, with: .color(.white.opacity(dark ? 0.08 : 0.32)))
        }
        drawUpperSand(in: &context)
        drawLowerSand(in: &context)
        if sand.flows {
            var stream = Path()
            stream.move(to: CGPoint(x: cx, y: mid))
            stream.addLine(to: CGPoint(x: cx, y: pileTop))
            context.stroke(stream, with: .color(sandDeep), lineWidth: max(0.7, w * 0.03))
        }
        if glass {
            drawGlass(shape, in: &context)
        } else {
            drawLine(shape, in: &context)
        }
    }

    private func drawUpperSand(in context: inout GraphicsContext) {
        let t0 = HourglassGeometry.upperSurface(remain: sand.upper)
        guard t0 < 1 else { return }
        var path = Path()
        let inset = 0.3
        let surfaceY = upperY(t0)
        let dip = min(2.2, h * 0.04) * (1 - t0)
        // 沙面：中间微凹。
        let w0 = hw(t0) - inset
        path.move(to: CGPoint(x: cx - w0, y: surfaceY))
        path.addQuadCurve(to: CGPoint(x: cx + w0, y: surfaceY), control: CGPoint(x: cx, y: surfaceY + dip * 2))
        for i in 0...samples {
            let t = t0 + (1 - t0) * Double(i) / Double(samples)
            path.addLine(to: CGPoint(x: cx + hw(t) - inset, y: upperY(t)))
        }
        for i in stride(from: samples, through: 0, by: -1) {
            let t = t0 + (1 - t0) * Double(i) / Double(samples)
            path.addLine(to: CGPoint(x: cx - hw(t) + inset, y: upperY(t)))
        }
        path.closeSubpath()
        context.fill(path, with: .color(sandFill))
    }

    private func drawLowerSand(in context: inout GraphicsContext) {
        let filled = HourglassGeometry.lowerHeight(filled: sand.lower)
        guard filled > 0 else { return }
        let inset = 0.3
        let edgeY = lowerY(filled)
        let edgeW = hw(filled) - inset
        var path = Path()
        path.move(to: CGPoint(x: cx - edgeW, y: edgeY))
        path.addQuadCurve(to: CGPoint(x: cx + edgeW, y: edgeY), control: CGPoint(x: cx, y: pileTop - (edgeY - pileTop)))
        for i in 0...samples {
            let t = filled * (1 - Double(i) / Double(samples))
            path.addLine(to: CGPoint(x: cx + hw(t) - inset, y: lowerY(t)))
        }
        for i in stride(from: samples, through: 0, by: -1) {
            let t = filled * (1 - Double(i) / Double(samples))
            path.addLine(to: CGPoint(x: cx - hw(t) + inset, y: lowerY(t)))
        }
        path.closeSubpath()
        context.fill(path, with: .color(sandFill))
        // 沙堆顶一小块深一点的影子，看得出是一堆。
        var shade = Path()
        shade.move(to: CGPoint(x: cx - edgeW * 0.5, y: edgeY))
        shade.addLine(to: CGPoint(x: cx, y: pileTop + 0.5))
        shade.addLine(to: CGPoint(x: cx + edgeW * 0.5, y: edgeY))
        shade.addLine(to: CGPoint(x: cx, y: edgeY + (edgeY - pileTop) * 0.3))
        shade.closeSubpath()
        context.fill(shade, with: .color(sandDeep.opacity(0.4)))
    }

    private func drawLine(_ shape: Path, in context: inout GraphicsContext) {
        let ink = Color.primary.opacity(dark ? 0.7 : 0.62)
        let stroke = max(1, w * 0.05)
        context.stroke(shape, with: .color(ink), style: StrokeStyle(lineWidth: stroke, lineJoin: .round))
        for y in [0.0, h - capH] {
            let bar = Path(roundedRect: CGRect(x: 0, y: y + capH * 0.2, width: w, height: max(1.2, capH * 0.6)),
                           cornerRadius: capH * 0.3)
            context.fill(bar, with: .color(ink))
        }
    }

    private func drawGlass(_ shape: Path, in context: inout GraphicsContext) {
        context.stroke(shape, with: .color(.white.opacity(dark ? 0.5 : 0.85)), lineWidth: max(0.8, w * 0.03))
        context.stroke(shape, with: .color(.black.opacity(dark ? 0.35 : 0.16)), lineWidth: 0.5)
        // 左侧一道弧形高光，上泡亮、下泡淡一点。
        var top = Path()
        var bottom = Path()
        for i in 3..<(samples - 5) {
            let t = Double(i) / Double(samples)
            let a = CGPoint(x: cx - hw(t) * 0.62, y: upperY(t))
            let b = CGPoint(x: cx - hw(t) * 0.62, y: lowerY(t))
            if i == 3 {
                top.move(to: a)
                bottom.move(to: b)
            } else {
                top.addLine(to: a)
                bottom.addLine(to: b)
            }
        }
        context.stroke(top, with: .color(.white.opacity(0.8)),
                       style: StrokeStyle(lineWidth: max(0.8, w * 0.05), lineCap: .round))
        context.stroke(bottom, with: .color(.white.opacity(0.55)),
                       style: StrokeStyle(lineWidth: max(0.7, w * 0.04), lineCap: .round))
        // 两根立柱。
        let pillar = max(0.8, w * 0.035)
        for x in [w * 0.06, w - w * 0.06 - pillar] {
            context.fill(Path(CGRect(x: x, y: capH, width: pillar, height: h - capH * 2)),
                         with: .color(cap.opacity(dark ? 0.55 : 0.45)))
        }
        // 端盖：事件色，顶上一道亮边。
        let capColor = cap.mix(with: dark ? .black : .gray, by: 0.25)
        for y in [0.0, h - capH] {
            let rect = CGRect(x: 0, y: y, width: w, height: capH)
            context.fill(Path(roundedRect: rect, cornerRadius: capH / 2), with: .color(capColor))
            var shine = Path()
            shine.move(to: CGPoint(x: capH / 2, y: y + capH * 0.3))
            shine.addLine(to: CGPoint(x: w - capH / 2, y: y + capH * 0.3))
            context.stroke(shine, with: .color(.white.opacity(0.45)), lineWidth: max(0.5, capH * 0.18))
        }
    }

    /// 临近时沙流上的沙粒，`positions` 是 0（细腰）到 1（沙堆顶）。
    func drawDots(_ positions: [Double], in context: inout GraphicsContext) {
        let r = max(0.7, w * 0.035)
        for (index, f) in positions.enumerated() {
            let y = mid + (pileTop - mid) * f
            let x = cx + (index % 2 == 0 ? -0.9 : 0.9)
            context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                         with: .color(sandDeep))
        }
    }
}

/// 事件小图标：事件色的小圆，里面一个白色符号（`AnniversaryIcon`）。
struct AnniversaryIconChip: View {
    var event: AnniversaryEvent
    var diameter: CGFloat
    /// 外面一圈白边，压在时间轴线上时用。
    var ring = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Circle()
            .fill(AnniversaryTile.base(event))
            .frame(width: diameter, height: diameter)
            .overlay {
                Image(systemName: AnniversaryIcon.symbol(for: event))
                    .font(.system(size: diameter * 0.52, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(ring ? 1.5 : 0)
            .background {
                if ring {
                    Circle().fill(.white.opacity(scheme == .dark ? 0.55 : 0.92))
                }
            }
            .accessibilityHidden(true)
    }
}

/// 当天小熊猫旁边的几片彩纸。静态的，不动。
struct AnniversaryConfetti: View {
    private static let pieces: [(x: CGFloat, y: CGFloat, angle: Double, hex: String, round: Bool)] = [
        (0.06, 0.55, -30, "#FFD36B", false), (0.18, 0.12, 25, "#FF7AA2", true), (0.36, 0.02, -10, "#6FDC9A", false),
        (0.58, 0.1, 35, "#7FC4E8", true), (0.78, 0.0, -25, "#FFD36B", false), (0.94, 0.5, 15, "#FF7AA2", false),
    ]

    var body: some View {
        GeometryReader { proxy in
            ForEach(Self.pieces.indices, id: \.self) { index in
                let piece = Self.pieces[index]
                Group {
                    if piece.round {
                        Circle().fill(Color(hex: piece.hex)).frame(width: 3, height: 3)
                    } else {
                        Capsule().fill(Color(hex: piece.hex)).frame(width: 1.8, height: 4.5)
                    }
                }
                .rotationEffect(.degrees(piece.angle))
                .position(x: piece.x * proxy.size.width, y: piece.y * proxy.size.height)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
