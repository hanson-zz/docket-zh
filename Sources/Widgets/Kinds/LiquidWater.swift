import SwiftUI

/// 液态外观的水：两层波浪从底部涨到 `level`，可以是整张卡片（矩形）
/// 也可以是一个小圆杯。`golden` 时水面染金光。帧率由 `LiquidMotion` 定，
/// 看不见或减少动态效果时是一张静止的图。
struct LiquidWater: View {
    enum Shape { case rect, circle }

    var level: Double
    var tint: Color
    var shape: Shape = .rect
    var visible: Bool
    var still: Bool = false
    var golden: Bool = false
    /// 波速倍数，系统活动用占用率调。
    var speed: Double = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let fps = LiquidMotion.framesPerSecond(visible: visible, reduceMotion: reduceMotion,
                                               still: still, golden: golden)
        TimelineView(.animation(minimumInterval: 1 / (fps ?? LiquidMotion.idleFPS), paused: fps == nil)) { timeline in
            let t = fps == nil ? 0 : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                draw(&context, size: size, t: t)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, t: Double) {
        var rect = CGRect(origin: .zero, size: size)
        if shape == .circle {
            let d = min(size.width, size.height)
            rect = CGRect(x: (size.width - d) / 2, y: (size.height - d) / 2, width: d, height: d)
            let circle = Path(ellipseIn: rect)
            context.fill(circle, with: .color(tint.opacity(0.14)))
            context.stroke(circle, with: .color(tint.opacity(0.55)), lineWidth: max(1, d * 0.05))
            context.clip(to: Path(ellipseIn: rect.insetBy(dx: d * 0.05, dy: d * 0.05)))
        }
        let level = LiquidMotion.level(level)
        guard level > 0 else { return }
        // 没满时留一点空，波浪不会顶出上沿；满了水面略高过上沿，
        // 整张卡片盖住，不在顶上留一条底色的黑边（见 `LiquidLooks.cardFill`）。
        let fill = shape == .rect ? LiquidLooks.cardFill(level) : level
        let baseY = rect.minY + rect.height * (1 - fill)
        let steps = shape == .rect ? 32 : 20
        let amp = shape == .rect ? 0.6 : 1.0
        var front = Path()
        for layer in [1, 0] {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            for i in 0...steps {
                let x = Double(i) / Double(steps)
                let lift = BatteryMotion.surface(x: x, t: t, level: shape == .rect ? min(max(fill, 0.3), 1) : fill,
                                                 layer: layer, speed: 0.6 * speed)
                path.addLine(to: CGPoint(x: rect.minX + x * rect.width, y: baseY - lift * rect.height * amp))
            }
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
            if layer == 1 {
                context.fill(path, with: .color(tint.opacity(shape == .rect ? 0.12 : 0.35)))
            } else {
                front = path
                let top = shape == .rect ? 0.30 : 0.95
                let bottom = shape == .rect ? 0.14 : 0.75
                context.fill(path, with: .linearGradient(
                    Gradient(colors: [tint.opacity(top), tint.opacity(bottom)]),
                    startPoint: CGPoint(x: rect.midX, y: baseY),
                    endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
                if shape == .rect {
                    context.stroke(front, with: .color(tint.opacity(0.4)), lineWidth: 0.8)
                }
            }
        }
        if golden {
            let glow = reduceMotion || !visible ? 0.6 : 0.5 + 0.5 * sin(t * 4)
            let gold = Color(red: 1, green: 0.82, blue: 0.3)
            context.fill(front, with: .color(gold.opacity(0.35 * glow)))
            context.stroke(front, with: .color(gold.opacity(0.9 * glow)), lineWidth: 1.5)
        }
    }
}

extension LiquidWater {
    /// 铺满整张卡片：先撑满可用的地方（不然水只有中间文字那么大，左右和
    /// 上下会露出底色），再抵消 `WidgetSurface` 的左右内边距，按卡片圆角裁切。
    func fillingCard() -> some View {
        self.frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, -WidgetStyle.inset)
            .clipShape(.rect(cornerRadius: WidgetStyle.corner, style: .continuous))
    }
}
