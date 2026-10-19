import SwiftUI

/// 电池格（横向或竖向电池）液态外观里的那截水。和 `LiquidWater` 的矩形
/// 水一样是两层波浪、同样的透明度，另外多三样（规则都在
/// `BatteryLiquidFX`）：
///
/// - 插上电源时水面晃一波（约 1.2 秒衰减），溅起几颗小水珠落回；拔掉轻晃一下。
/// - 20% 及以下、没在充电时水变红，水面靠一侧鼓起一个圆滴，慢慢呼吸。
/// - 水色随电量从红经黄到绿平滑过渡；低电量模式黄、充电绿的优先级照旧。
///   在「外观 ▸ 颜色」里选了颜色时水换成所选颜色，只有低电量报警时仍是红
///   （`BatteryTheme.cellWaterColor`）。
///
/// 只在卡片看得见时动：平时 10 帧，晃的那一秒多 30 帧，晃完自己降回去；
/// 减少动态效果时是一张静止的图，只换颜色。
struct BatteryLiquidCell: View {
    /// 电量 0...1（没连上是 0）。
    var fill: Double
    var vertical: Bool
    var charging: Bool
    var present: Bool
    var lowPower = false
    var pluggedAt: Date?
    var unpluggedAt: Date?
    var visible: Bool
    var corner: CGFloat
    /// 选了颜色时的主题色（已调过可读性），默认是 nil，水照旧按电量上色。
    var theme: ColorCode?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 晃完时加一，让帧率重新算一遍，降回平时的 10 帧。
    @State private var sloshEnded = 0

    var body: some View {
        let _ = sloshEnded
        let sloshing = BatteryLiquidFX.activeSlosh(pluggedAt: pluggedAt, unpluggedAt: unpluggedAt, now: .now) != nil
        let fps = BatteryLiquidFX.framesPerSecond(visible: visible, reduceMotion: reduceMotion, sloshing: sloshing)
        TimelineView(.animation(minimumInterval: 1 / (fps ?? BatteryMotion.idleFPS), paused: fps == nil)) { timeline in
            let moving = fps != nil
            Canvas { context, size in
                draw(&context, size: size,
                     t: moving ? timeline.date.timeIntervalSinceReferenceDate : 0,
                     now: moving ? timeline.date : nil)
            }
        }
        .task(id: sloshKey) { await waitOutSlosh() }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: 晃荡的计时

    private var sloshKey: String {
        "\(pluggedAt?.timeIntervalSince1970 ?? 0)|\(unpluggedAt?.timeIntervalSince1970 ?? 0)"
    }

    private func waitOutSlosh() async {
        guard let active = BatteryLiquidFX.activeSlosh(pluggedAt: pluggedAt, unpluggedAt: unpluggedAt, now: .now)
        else { return }
        let remaining = BatteryLiquidFX.sloshDuration(active.event) - active.elapsed
        try? await Task.sleep(for: .seconds(remaining + 0.05))
        sloshEnded += 1
    }

    // MARK: 画

    private func color(_ rgb: BatteryRGB) -> Color { Color(red: rgb.red, green: rgb.green, blue: rgb.blue) }

    private func draw(_ context: inout GraphicsContext, size: CGSize, t: Double, now: Date?) {
        let inner = CGRect(origin: .zero, size: size)
        let level = present && fill.isFinite ? min(max(fill, 0), 1) : 0
        guard level > 0 else { return }
        context.clip(to: Path(roundedRect: inner, cornerRadius: corner, style: .continuous))

        // 这一刻在晃吗；减少动态效果或看不见时 `now` 是 nil，不晃不溅。
        let active = now.flatMap { BatteryLiquidFX.activeSlosh(pluggedAt: pluggedAt, unpluggedAt: unpluggedAt, now: $0) }
        let tilt = active.map { BatteryLiquidFX.slosh($0.event, elapsed: $0.elapsed) } ?? 0

        // 颜色：晃的那一下从插拔前的颜色过渡到现在的，平时直接是现在的。
        let target = BatteryTheme.cellWaterColor(level: level, charging: charging, lowPower: lowPower,
                                                 present: present, theme: theme)
        var rgb = target
        if let active {
            let before = BatteryTheme.cellWaterColor(level: level, charging: active.event == .unplugged,
                                                     lowPower: lowPower, present: present, theme: theme)
            rgb = before.mixed(with: target, BatteryLiquidFX.colorBlend(active.event, elapsed: active.elapsed))
        }
        let tint = color(rgb)

        // 竖电池水位就是电量；横电池是从左往右一截，里面的水装到 88%。
        let water = vertical ? inner : CGRect(x: 0, y: 0, width: inner.width * level, height: inner.height)
        let height = vertical ? level : 0.88
        let fillFraction = LiquidLooks.cardFill(height)
        let baseY = water.minY + water.height * (1 - fillFraction)
        let steps = 24

        var front = Path()
        for layer in [1, 0] {
            var path = Path()
            path.move(to: CGPoint(x: water.minX, y: water.maxY))
            for i in 0...steps {
                let x = Double(i) / Double(steps)
                let wave = BatteryMotion.surface(x: x, t: t, level: min(max(fillFraction, 0.3), 1),
                                                 layer: layer, speed: 0.6) * 0.6
                let lean = BatteryLiquidFX.tiltLift(x: x, slosh: tilt) * (layer == 0 ? 1 : 0.7)
                path.addLine(to: CGPoint(x: water.minX + x * water.width,
                                         y: baseY - (wave + lean) * water.height))
            }
            path.addLine(to: CGPoint(x: water.maxX, y: water.maxY))
            path.closeSubpath()
            // 横电池那截水的右边也带圆角，和原来裁成圆角矩形的一截一样。
            let shaped = path.intersection(Path(roundedRect: water, cornerRadius: corner, style: .continuous))
            if layer == 1 {
                context.fill(shaped, with: .color(tint.opacity(0.12)))
            } else {
                front = shaped
            }
        }

        // 低电量的圆滴：横电池鼓在水那一截的前沿，竖电池鼓在水面靠左。
        if BatteryLiquidFX.isLow(level: level, charging: charging, present: present) {
            let scale = BatteryLiquidFX.blobScale(t: now == nil ? nil : t)
            let short = min(inner.width, inner.height)
            let r = max(1.5, short * BatteryLiquidFX.blobRadius * scale)
            let center = vertical
                ? CGPoint(x: water.minX + water.width * 0.28, y: baseY + r * 0.35)
                : CGPoint(x: water.maxX, y: water.minY + water.height * 0.6)
            let blob = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
            front = front.union(blob)
        }

        context.fill(front, with: .linearGradient(
            Gradient(colors: [tint.opacity(0.30), tint.opacity(0.14)]),
            startPoint: CGPoint(x: water.midX, y: baseY),
            endPoint: CGPoint(x: water.midX, y: water.maxY)))
        context.stroke(front, with: .color(tint.opacity(0.4)), lineWidth: 0.8)

        // 插上电源溅起的水珠：从水面溅起，落回水面，只在水面上方的空当里。
        if let active, active.event == .plugged {
            let headroom = baseY - inner.minY
            guard headroom > 1.5 else { return }
            let origin = vertical ? 0.5 : max(0.1, (water.maxX - inner.height * 0.3) / max(inner.width, 1))
            let short = min(inner.width, inner.height)
            for drop in BatteryLiquidFX.droplets(.plugged, elapsed: active.elapsed, origin: origin) {
                let r = max(0.8, drop.radius * short)
                let x = inner.minX + drop.x * inner.width
                let y = baseY - drop.height * (headroom - r)
                let dot = Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
                context.fill(dot, with: .color(tint.opacity(0.55 * drop.opacity)))
                context.stroke(dot, with: .color(.white.opacity(0.5 * drop.opacity)), lineWidth: 0.6)
            }
        }
    }
}
