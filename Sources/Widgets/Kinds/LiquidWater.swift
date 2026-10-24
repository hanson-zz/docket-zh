import SwiftUI

/// 液态外观的水：两层波浪从底部涨到 `level`，可以是整张卡片（矩形）
/// 也可以是一个小圆杯。`golden` 时水面染金光。帧率由 `LiquidMotion` 定，
/// 看不见或减少动态效果时是一张静止的图。
///
/// 喝水另外用三样（别的小组件不传，样子不变）：`density` 让水更浓；
/// `sloshAt`（喝水的 loggedAt）后约 1.2 秒水面晃一下、溅几颗水珠，复用电池
/// 液态的 `BatteryLiquidFX`；`fullHighlight` 满了时顶上一道高光。
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
    /// 水面一道亮线（时间进度的液态用）。
    var shine: Bool = false
    /// 水里慢慢往上冒的气泡数，0 不画。位置由 `LiquidMotion.bubbles` 算。
    var bubbles: Int = 0
    /// 水体浓度，nil 是原来的淡水（`LiquidLooks.standardDensity`）。只对矩形有用。
    var density: LiquidDensity? = nil
    /// 这一刻起水面晃一下、溅几颗水珠（喝水点 + 时的 loggedAt）。只对矩形有用。
    var sloshAt: Date? = nil
    /// 水珠从水面哪里溅起（0...1）。
    var splashOrigin: Double = 0.5
    /// 满了时顶上一道高光。
    var fullHighlight: Bool = false
    /// 浮在水上的字（喝水液态用，别的不传）：画两遍，参数是“在水里”。水面上方
    /// 那一遍按这一帧的前浪挖掉水里的部分，水里那一遍只留前浪里面，两种字色
    /// 刚好在水面接上（见 `WaterLiquidInk`）。和水同一个时间轴，浪动字的分界跟着动。
    /// 只对矩形有用；整张卡片大小，字的内边距由传进来的视图自己留。
    var ink: ((_ underwater: Bool) -> AnyView)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 晃完时加一，让帧率重新算一遍，降回平时的 10 帧。
    @State private var sloshEnded = 0

    private func activeSlosh(_ now: Date) -> TimeInterval? {
        guard shape == .rect, let sloshAt,
              let active = BatteryLiquidFX.activeSlosh(pluggedAt: sloshAt, unpluggedAt: nil, now: now)
        else { return nil }
        return active.elapsed
    }

    var body: some View {
        let _ = sloshEnded
        let sloshing = activeSlosh(.now) != nil
        let fps = LiquidMotion.framesPerSecond(visible: visible, reduceMotion: reduceMotion,
                                               still: still, golden: golden || sloshing)
        TimelineView(.animation(minimumInterval: 1 / (fps ?? LiquidMotion.idleFPS), paused: fps == nil)) { timeline in
            let moving = fps != nil
            let t = moving ? timeline.date.timeIntervalSinceReferenceDate : 0
            let now = moving ? timeline.date : nil
            ZStack {
                Canvas { context, size in
                    draw(&context, size: size, t: t, now: now)
                }
                if let ink, shape == .rect {
                    ink(false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .mask {
                            Canvas { context, size in
                                let rect = CGRect(origin: .zero, size: size)
                                context.fill(Path(rect), with: .color(.black))
                                if let front = frontShape(in: rect, t: t, now: now) {
                                    context.blendMode = .destinationOut
                                    context.fill(front, with: .color(.black))
                                }
                            }
                        }
                    ink(true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .mask {
                            Canvas { context, size in
                                if let front = frontShape(in: CGRect(origin: .zero, size: size), t: t, now: now) {
                                    context.fill(front, with: .color(.black))
                                }
                            }
                        }
                }
            }
        }
        .task(id: sloshAt) { await waitOutSlosh() }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func waitOutSlosh() async {
        guard let elapsed = activeSlosh(.now) else { return }
        let remaining = BatteryLiquidFX.sloshDuration(.plugged) - elapsed
        try? await Task.sleep(for: .seconds(remaining + 0.05))
        sloshEnded += 1
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize, t: Double, now: Date?) {
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
        let baseY = waterlineY(in: rect)
        // 点 + 后的晃荡和水珠；静止（减少动态效果、看不见）时 `now` 是 nil，不晃不溅。
        let sloshElapsed = now.flatMap { activeSlosh($0) }
        let tilt = sloshElapsed.map { BatteryLiquidFX.slosh(.plugged, elapsed: $0) } ?? 0
        let look = shape == .rect ? (density ?? LiquidLooks.standardDensity) : nil
        var front = Path()
        var surface = Path()
        for layer in [1, 0] {
            let (path, line) = wave(layer: layer, in: rect, t: t, tilt: tilt)
            if layer == 0 { surface = line }
            if layer == 1 {
                context.fill(path, with: .color(tint.opacity(look?.back ?? 0.35)))
            } else {
                front = path
                let top = look?.top ?? 0.95
                let bottom = look?.bottom ?? 0.75
                context.fill(path, with: .linearGradient(
                    Gradient(colors: [tint.opacity(top), tint.opacity(bottom)]),
                    startPoint: CGPoint(x: rect.midX, y: baseY),
                    endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
                if shape == .rect {
                    context.stroke(front, with: .color(tint.opacity(0.4)), lineWidth: 0.8)
                }
            }
        }
        if bubbles > 0, baseY < rect.maxY - 6 {
            // 气泡只在水里：从底边冒到水面下一点，快到水面时淡掉。
            var water = context
            water.clip(to: front)
            let depth = rect.maxY - baseY
            for bubble in LiquidMotion.bubbles(count: bubbles, t: t) {
                let r = max(1.2, bubble.radius * rect.height)
                let y = rect.maxY - r - bubble.rise * max(0, depth - 2 * r)
                let x = rect.minX + bubble.x * rect.width
                let fade = bubble.rise > 0.8 ? (1 - bubble.rise) / 0.2 : min(1, bubble.rise / 0.1 + 0.2)
                let dot = Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
                water.fill(dot, with: .color(.white.opacity(0.18 * fade)))
                water.stroke(dot, with: .color(.white.opacity(0.55 * fade)), lineWidth: 0.7)
            }
        }
        if shine, level < 1 {
            context.stroke(surface, with: .color(.white.opacity(0.7)), lineWidth: 1.2)
        }
        if fullHighlight, level >= 1 {
            // 满了：顶上一抹白光渐隐下去，再加一道细亮线，看得出水到顶了。
            var water = context
            water.clip(to: front)
            water.fill(Path(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.4)),
                       with: .linearGradient(Gradient(colors: [.white.opacity(0.22), .white.opacity(0)]),
                                             startPoint: CGPoint(x: rect.midX, y: rect.minY),
                                             endPoint: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.4)))
            var line = Path()
            line.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY + 3))
            line.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.minY + 3))
            water.stroke(line, with: .color(.white.opacity(0.45)),
                         style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        }
        if let sloshElapsed, baseY > rect.minY + 1.5 {
            // 点 + 溅起的水珠：从水面溅起、落回水面，只在水面上方的空当里。
            let headroom = baseY - rect.minY
            let short = min(rect.width, rect.height)
            for drop in BatteryLiquidFX.droplets(.plugged, elapsed: sloshElapsed, origin: splashOrigin) {
                let r = max(0.8, drop.radius * short)
                let x = rect.minX + drop.x * rect.width
                let y = baseY - drop.height * max(0, headroom - r)
                let dot = Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
                context.fill(dot, with: .color(tint.opacity(0.7 * drop.opacity)))
                context.stroke(dot, with: .color(.white.opacity(0.55 * drop.opacity)), lineWidth: 0.6)
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
    /// 水面的基准高度：没满时留一点空，波浪不会顶出上沿；满了水面略高过上沿，
    /// 整张卡片盖住，不在顶上留一条底色的黑边（见 `LiquidLooks.cardFill`）。
    fileprivate func waterlineY(in rect: CGRect) -> CGFloat {
        let level = LiquidMotion.level(level)
        let fill = shape == .rect ? LiquidLooks.cardFill(level) : level
        return rect.minY + rect.height * (1 - fill)
    }

    /// 一道浪这一帧的形状（layer 0 前浪、1 后浪）和它的水面线。
    fileprivate func wave(layer: Int, in rect: CGRect, t: Double, tilt: Double) -> (Path, Path) {
        let level = LiquidMotion.level(level)
        let fill = shape == .rect ? LiquidLooks.cardFill(level) : level
        let baseY = waterlineY(in: rect)
        let steps = shape == .rect ? 32 : 20
        let amp = shape == .rect ? 0.6 : 1.0
        var path = Path()
        var surface = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        for i in 0...steps {
            let x = Double(i) / Double(steps)
            let lift = BatteryMotion.surface(x: x, t: t, level: shape == .rect ? min(max(fill, 0.3), 1) : fill,
                                             layer: layer, speed: 0.6 * speed)
            let lean = BatteryLiquidFX.tiltLift(x: x, slosh: tilt) * (layer == 0 ? 1 : 0.7)
            let point = CGPoint(x: rect.minX + x * rect.width, y: baseY - (lift * amp + lean) * rect.height)
            path.addLine(to: point)
            if i == 0 { surface.move(to: point) } else { surface.addLine(to: point) }
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return (path, surface)
    }

    /// 前浪这一帧的形状，字按它分水面上下（`ink`）。没水时是 nil。
    fileprivate func frontShape(in rect: CGRect, t: Double, now: Date?) -> Path? {
        guard LiquidMotion.level(level) > 0 else { return nil }
        let tilt = now.flatMap { activeSlosh($0) }.map { BatteryLiquidFX.slosh(.plugged, elapsed: $0) } ?? 0
        return wave(layer: 0, in: rect, t: t, tilt: tilt).0
    }
}

extension View {
    /// 铺满整张卡片：先撑满可用的地方（不然水只有中间文字那么大，左右和
    /// 上下会露出底色），按卡片圆角裁切，再抵消 `WidgetSurface` 的左右内边距。
    ///
    /// 顺序不能反：原来先抵消内边距再裁切，裁切按的是抵消前那块（左右各缩进
    /// 10pt）的大小，水左右各少 10pt、四个角按缩进后的圆角切掉，露出一圈卡片
    /// 底色（浅色外观下是奶白的厚边）。喝水、时间进度、小熊猫竹篮的液态都用它；
    /// 放在 `View` 上，喝水液态的水和字整组（ZStack）也能直接用。
    func fillingCard() -> some View {
        self.frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(.rect(cornerRadius: WidgetStyle.corner, style: .continuous))
            .padding(.horizontal, -WidgetStyle.inset)
    }

    /// 浮在液态水上的字离卡片左右边至少 `LiquidLooks.liquidTextInset`（12pt）：
    /// `WidgetSurface` 已经留了 10pt，这里补差的那 2pt。水铺满到卡片边，字不贴水边。
    func liquidTextInset() -> some View {
        padding(.horizontal, max(0, CGFloat(LiquidLooks.liquidTextInset) - WidgetStyle.inset))
    }
}
