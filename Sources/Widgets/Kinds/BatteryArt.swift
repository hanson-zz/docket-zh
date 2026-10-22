import AppKit
import SwiftUI

extension BatteryRGB {
    var swiftUI: Color { Color(red: red, green: green, blue: blue) }
}

extension ColorCode {
    /// 系统强调色（「外观 ▸ 颜色」选了跟随系统时电池用它），读不到是 nil。
    @MainActor static var systemAccent: ColorCode? {
        guard let rgb = NSColor.controlAccentColor.usingColorSpace(.sRGB) else { return nil }
        return ColorCode(red: Double(rgb.redComponent), green: Double(rgb.greenComponent),
                         blue: Double(rgb.blueComponent))
    }
}

/// What one battery gauge draws from.
struct BatteryGaugeState: Equatable {
    var level: Double
    var charging: Bool
    var present: Bool
    var lowPower = false
    var watts: Int?
    /// The Mac only: the moments the looks animate from once.
    var pluggedAt: Date?
    var fullAt: Date?
    /// The Mac only: when the adapter came out, for 液态's small slosh.
    var unpluggedAt: Date?
}

/// What sits in the middle of a gauge.
enum BatteryGaugeCenter: Equatable {
    case none
    case symbol(String)
    case percent(CGFloat)
}

/// The four animated 电池 looks (液态, 像素电池, 能量粒子, 小熊猫抱电池)
/// in a square of `diameter`. 经典 is not drawn here: the tile keeps its own
/// rings for it, untouched.
///
/// One `TimelineView` drives everything, at a rate `BatteryMotion` picks:
/// 30 fps while charging or during a flourish, about 10 fps for the slow
/// ripple on battery, and paused (a still frame) when the card is off
/// screen, 减少动态效果 is on, or the look has nothing to move.
struct BatteryGauge: View {
    var look: BatteryLook
    var state: BatteryGaugeState
    var diameter: CGFloat
    var center: BatteryGaugeCenter = .none
    var inPanel = false
    var isPreview = false
    /// 「外观 ▸ 颜色」选了颜色时的主题色（已调过可读性），默认 nil 照旧按电量上色。
    var theme: ColorCode?

    init(look: BatteryLook, state: BatteryGaugeState, diameter: CGFloat,
         center: BatteryGaugeCenter = .none, inPanel: Bool = false, isPreview: Bool = false,
         theme: ColorCode? = nil) {
        self.look = look
        self.state = state
        self.diameter = diameter
        self.center = center
        self.inPanel = inPanel
        self.isPreview = isPreview
        self.theme = theme
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    /// Bumped when a flourish ends, so the frame rate is worked out again
    /// and the timeline can drop back to its idle pace.
    @State private var flourishEnded = 0

    var body: some View {
        let _ = flourishEnded
        let tint = gaugeTint
        let visible = inPanel || ShelfVisibility.shared.cardsOnScreen
        let flourish = BatteryMotion.isFlourishing(pluggedAt: state.pluggedAt, fullAt: state.fullAt, now: .now)
            || (look == .liquid && BatteryLiquidFX.activeSlosh(pluggedAt: nil, unpluggedAt: state.unpluggedAt,
                                                               now: .now) != nil)
        let fps: Double? = isPreview || !state.present ? nil : BatteryMotion.framesPerSecond(
            look: look, charging: state.charging, pulsing: tint.pulses, flourish: flourish,
            host: inPanel ? .panel : .card(visible: visible), reduceMotion: reduceMotion)

        TimelineView(.animation(minimumInterval: 1 / (fps ?? BatteryMotion.maxFPS), paused: fps == nil)) { timeline in
            // A still frame is drawn at a fixed moment, so it is the same
            // picture every time rather than wherever the clock happened to be.
            let moving = fps != nil
            let frame = Frame(t: moving ? timeline.date.timeIntervalSinceReferenceDate : 0.8,
                              now: moving ? timeline.date : nil,
                              tint: tint, moving: moving)
            face(frame)
        }
        .frame(width: diameter, height: diameter)
        .task(id: flourishKey) { await waitOutFlourish() }
        .accessibilityHidden(true)
    }

    /// One frame's inputs.
    struct Frame {
        var t: Double
        /// Nil on a still frame: no flourish is drawn without motion.
        var now: Date?
        var tint: BatteryColorMap.Tint
        var moving: Bool

        var pulse: Double { tint.pulses && moving ? BatteryColorMap.pulse(t) : 1 }
    }

    @ViewBuilder
    private func face(_ frame: Frame) -> some View {
        switch look {
        case .pixel: pixel(frame)
        case .particles: particles(frame)
        case .panda:
            if let image = PetArt.image(.redPanda, pandaLook) {
                panda(frame, image: image)
            } else {
                liquid(frame)
            }
        case .liquid, .classic: liquid(frame)
        }
    }

    /// The band colours, except that 液态's water (and its ring) runs
    /// smoothly from red through yellow to green with the level
    /// (`BatteryLiquidFX.gaugeWaterColor`); Low Power Mode stays yellow.
    /// A colour picked in 外观 ▸ 颜色 replaces all of that, except the red
    /// of a low battery that is not charging (`BatteryTheme.gaugeTint`).
    private var gaugeTint: BatteryColorMap.Tint {
        BatteryTheme.gaugeTint(level: state.level, charging: state.charging, lowPower: state.lowPower,
                               present: state.present, liquid: look == .liquid, theme: theme)
    }

    /// 充电气泡、插电绕圈的光点、充电弧上的光点原来写死白色，深色卡片上是亮点；
    /// 面板跟着浅色外观换成浅色玻璃后，白点就看不见了。只在面板、浅色外观下
    /// 换成电量色（或主题色）压深一档（`PanelContrast.readable`，同主题色当文字），
    /// 扩展栏卡片和深色外观照旧是白。
    private func sparkColor(_ tint: BatteryColorMap.Tint) -> Color {
        guard inPanel, scheme == .light else { return .white }
        let c = tint.color
        let deep = PanelContrast.readable(ColorCode(red: c.red, green: c.green, blue: c.blue))
        return Color(red: deep.red, green: deep.green, blue: deep.blue)
    }

    // MARK: Flourishes

    private var flourishKey: String {
        "\(state.pluggedAt?.timeIntervalSince1970 ?? 0)|\(state.fullAt?.timeIntervalSince1970 ?? 0)|"
            + "\(state.unpluggedAt?.timeIntervalSince1970 ?? 0)"
    }

    private func waitOutFlourish() async {
        let now = Date.now
        var remaining = 0.0
        if let pluggedAt = state.pluggedAt {
            remaining = max(remaining, BatteryMotion.plugDuration - now.timeIntervalSince(pluggedAt))
        }
        if let fullAt = state.fullAt {
            remaining = max(remaining, BatteryMotion.fullDuration - now.timeIntervalSince(fullAt))
        }
        if look == .liquid, let unpluggedAt = state.unpluggedAt {
            remaining = max(remaining, BatteryLiquidFX.unplugSloshDuration - now.timeIntervalSince(unpluggedAt))
        }
        guard remaining > 0 else { return }
        try? await Task.sleep(for: .seconds(remaining + 0.05))
        flourishEnded += 1
    }

    /// 0...1 through the plug-in sweep, or nil outside it.
    private func plugProgress(_ frame: Frame) -> Double? {
        guard let now = frame.now, let pluggedAt = state.pluggedAt else { return nil }
        let p = now.timeIntervalSince(pluggedAt) / BatteryMotion.plugDuration
        return (0..<1).contains(p) ? p : nil
    }

    /// 0...1 through the full-charge glow, or nil outside it.
    private func fullProgress(_ frame: Frame) -> Double? {
        guard let now = frame.now, let fullAt = state.fullAt else { return nil }
        let p = now.timeIntervalSince(fullAt) / BatteryMotion.fullDuration
        return (0..<1).contains(p) ? p : nil
    }

    /// The number's little hop when the adapter goes in or the battery
    /// fills: up 18% and back over the first half second.
    private func bounce(_ frame: Frame) -> CGFloat {
        guard let now = frame.now else { return 1 }
        for start in [state.pluggedAt, state.fullAt].compactMap({ $0 }) {
            let e = now.timeIntervalSince(start)
            if e >= 0, e < 0.5 { return 1 + 0.18 * sin(.pi * e / 0.5) }
        }
        return 1
    }

    /// A comet of light dots once round the ring.
    private func sweep(_ frame: Frame, radius: CGFloat) -> some View {
        Canvas { context, size in
            guard let p = plugProgress(frame) else { return }
            let mid = CGPoint(x: size.width / 2, y: size.height / 2)
            let eased = 1 - pow(1 - p, 2.2)
            let fade = p > 0.8 ? (1 - p) / 0.2 : 1
            let spark = sparkColor(frame.tint)
            for k in 0..<8 {
                let angle = -Double.pi / 2 + 2 * .pi * eased - Double(k) * 0.13
                let point = CGPoint(x: mid.x + radius * cos(angle), y: mid.y + radius * sin(angle))
                let r = max(1, diameter * (0.055 - 0.005 * Double(k)))
                let opacity = (1 - Double(k) / 8) * fade
                context.fill(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: 2 * r, height: 2 * r)),
                             with: .color(spark.opacity(opacity)))
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: Centre

    private var percentValue: Int { BatteryColorMap.percent(state.level) }

    @ViewBuilder
    private func centerContent(_ frame: Frame) -> some View {
        switch center {
        case .none:
            EmptyView()
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: max(9, diameter * 0.32), weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 1.5)
        case .percent(let size):
            VStack(spacing: 0) {
                if state.charging, inPanel { bolt(frame, size: size * 0.42) }
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(state.present ? "\(percentValue)" : "-")
                        .font(.system(size: size, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .rollingValue(percentValue)
                    if state.present {
                        Text("%")
                            .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
                            .opacity(0.8)
                    }
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 1.5)
                .scaleEffect(bounce(frame))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
        }
    }

    /// The charging bolt, breathing: its glow swells and fades every 2.4 s.
    private func bolt(_ frame: Frame, size: CGFloat) -> some View {
        let breath = frame.moving ? 0.5 + 0.5 * sin(frame.t * 2.6) : 0.6
        return Image(systemName: "bolt.fill")
            .font(.system(size: max(7, size), weight: .heavy))
            .foregroundStyle(Color(red: 1, green: 0.92, blue: 0.35))
            .opacity(0.65 + 0.35 * breath)
            .shadow(color: Color(red: 1, green: 0.85, blue: 0.2).opacity(0.4 + 0.5 * breath),
                    radius: 1 + 4 * breath)
    }

    /// The small bolt in the corner, for gauges whose middle holds a glyph.
    /// A panel's big number carries its own bolt above it instead.
    @ViewBuilder
    private func cornerBolt(_ frame: Frame) -> some View {
        if state.charging, !(inPanel && isPercentCenter) {
            bolt(frame, size: diameter * 0.22)
                .padding(2)
                .background(Circle().fill(.black.opacity(0.35)))
                // 选了颜色时闪电的底带一层主题色，和外圈是一套颜色。
                .background(Circle().fill(frame.tint.color.swiftUI.opacity(theme == nil ? 0 : 0.45)))
                .offset(x: diameter * 0.06, y: diameter * 0.06)
        }
    }

    private var isSymbolCenter: Bool {
        if case .symbol = center { return true }
        return false
    }

    private var isPercentCenter: Bool {
        if case .percent = center { return true }
        return false
    }

    // MARK: 液态

    private func liquid(_ frame: Frame) -> some View {
        let tint = frame.tint
        let ring = max(1.5, diameter * 0.045)
        return ZStack {
            Canvas { context, size in
                drawWater(&context, size: size, inset: ring, frame: frame)
            }
            Circle()
                .strokeBorder(AngularGradient(colors: [tint.color.swiftUI, tint.highlight.swiftUI, tint.color.swiftUI],
                                              center: .center),
                              lineWidth: ring)
                .opacity(state.present ? frame.pulse : 0.3)
                .shadow(color: tint.color.swiftUI.opacity(state.present ? 0.55 * frame.pulse : 0),
                        radius: diameter * 0.07)
            centerContent(frame)
            sweep(frame, radius: diameter / 2 - ring / 2)
        }
        .overlay(alignment: .bottomTrailing) { cornerBolt(frame) }
    }

    private func drawWater(_ context: inout GraphicsContext, size: CGSize, inset: CGFloat, frame: Frame) {
        let tint = frame.tint
        let rect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
        let circle = Path(ellipseIn: rect)
        context.fill(circle, with: .color(tint.color.swiftUI.opacity(0.12)))
        guard state.present else { return }
        context.clip(to: circle)

        let level = min(max(state.level, 0), 1)
        let charge = BatteryMotion.chargeSpeed(watts: state.watts)
        let speed = state.charging ? 1.6 * charge : 0.6
        let baseY = rect.minY + rect.height * (1 - level)
        let steps = 28
        // 插拔电源那一下水面晃一波（`BatteryLiquidFX`），减少动态效果时
        // `frame.now` 是 nil，不晃。
        let slosh = frame.now.flatMap {
            BatteryLiquidFX.activeSlosh(pluggedAt: state.pluggedAt, unpluggedAt: state.unpluggedAt, now: $0)
        }
        let tilt = slosh.map { BatteryLiquidFX.slosh($0.event, elapsed: $0.elapsed) } ?? 0
        var front = Path()
        for layer in [1, 0] {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            for i in 0...steps {
                let x = Double(i) / Double(steps)
                let lift = BatteryMotion.surface(x: x, t: frame.t, level: level, layer: layer, speed: speed)
                    + BatteryLiquidFX.tiltLift(x: x, slosh: tilt) * (layer == 0 ? 1 : 0.7)
                path.addLine(to: CGPoint(x: rect.minX + x * rect.width, y: baseY - lift * rect.height))
            }
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
            if layer == 0, BatteryLiquidFX.isLow(level: level, charging: state.charging, present: state.present) {
                // 低电量：水面靠左鼓起一个圆滴，慢慢呼吸。
                let r = rect.width * 0.11 * BatteryLiquidFX.blobScale(t: frame.moving ? frame.t : nil)
                let center = CGPoint(x: rect.minX + rect.width * 0.3, y: baseY + r * 0.35)
                path = path.union(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)))
            }
            if layer == 1 {
                context.fill(path, with: .color(tint.highlight.swiftUI.opacity(0.35 * frame.pulse)))
            } else {
                front = path
                context.fill(path, with: .linearGradient(
                    Gradient(colors: [tint.highlight.swiftUI.opacity(0.95 * frame.pulse),
                                      tint.color.swiftUI.opacity(0.85 * frame.pulse)]),
                    startPoint: CGPoint(x: rect.midX, y: baseY - rect.height * 0.04),
                    endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
            }
        }

        // Bubbles rise from the bottom while charging, faster on a bigger
        // charger, and fade as they reach the surface.
        if state.charging, frame.moving {
            let count = max(4, Int(diameter / 9))
            let spark = sparkColor(tint)
            for i in 0..<count {
                let seed = Double(i) * 0.618_034
                let fx = frac(seed) * 0.7 + 0.15
                let rate = 0.32 * charge * (0.7 + 0.6 * frac(seed * 3.7))
                let p = frac(frame.t * rate + frac(seed * 5.3))
                let bottom = rect.maxY - rect.height * 0.04
                guard baseY < bottom - 2 else { continue }
                let y = bottom - (bottom - baseY) * p
                let x = rect.minX + fx * rect.width + sin(frame.t * 2 + seed * 10) * rect.width * 0.025
                let r = rect.width * (0.022 + 0.02 * frac(seed * 7.1))
                let alpha = min(1, (1 - p) * 3) * 0.7
                context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)),
                             with: .color(spark.opacity(alpha)))
            }
        }

        // 插上电源时溅起几颗小水珠，落回水面。
        if let slosh, slosh.event == .plugged, baseY > rect.minY + 3 {
            let headroom = baseY - rect.minY
            for drop in BatteryLiquidFX.droplets(.plugged, elapsed: slosh.elapsed) {
                let r = max(0.8, drop.radius * rect.width * 0.6)
                let x = rect.minX + drop.x * rect.width
                let y = baseY - drop.height * min(headroom * 0.8, rect.height * 0.22)
                let dot = Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
                context.fill(dot, with: .color(tint.highlight.swiftUI.opacity(0.85 * drop.opacity)))
            }
        }

        // Full: the surface catches a gold light that swells and fades.
        if let p = fullProgress(frame) {
            let glow = sin(.pi * p)
            let gold = Color(red: 1, green: 0.82, blue: 0.3)
            context.fill(front, with: .color(gold.opacity(0.45 * glow)))
            context.stroke(front, with: .color(gold.opacity(0.9 * glow)), lineWidth: max(1, diameter * 0.03))
        }
    }

    private func frac(_ value: Double) -> Double { value - value.rounded(.down) }

    // MARK: 像素电池

    private func pixel(_ frame: Frame) -> some View {
        let tint = frame.tint
        let hasSymbol = isSymbolCenter
        let lit = state.present ? BatteryMotion.pixelCells(level: state.level, charging: state.charging,
                                                           t: frame.moving ? frame.t : 0) : 0
        let base = state.present ? BatteryMotion.pixelCells(level: state.level, charging: false, t: 0) : 0
        return ZStack {
            Canvas { context, size in
                let w = size.width * 0.86
                let h = size.height * 0.46
                let nub = w * 0.07
                let origin = CGPoint(x: (size.width - w - nub) / 2,
                                     y: hasSymbol ? size.height * 0.46 : (size.height - h) / 2)
                let line = max(1.5, size.width * 0.045)
                let body = CGRect(x: origin.x, y: origin.y, width: w, height: h)
                context.stroke(Path(roundedRect: body.insetBy(dx: line / 2, dy: line / 2),
                                    cornerRadius: size.width * 0.04),
                               with: .color(tint.color.swiftUI.opacity(state.present ? 0.9 * frame.pulse : 0.3)),
                               lineWidth: line)
                context.fill(Path(CGRect(x: body.maxX, y: body.midY - h * 0.18, width: nub, height: h * 0.36)),
                             with: .color(tint.color.swiftUI.opacity(state.present ? 0.9 * frame.pulse : 0.3)))
                let pad = line * 1.6
                let gap = max(1, size.width * 0.03)
                let inner = body.insetBy(dx: pad, dy: pad)
                let cell = (inner.width - gap * 4) / 5
                for i in 0..<5 {
                    let r = CGRect(x: inner.minX + Double(i) * (cell + gap), y: inner.minY,
                                   width: cell, height: inner.height)
                    let on = i < lit
                    let climbing = on && i >= base
                    let color = climbing ? tint.highlight.swiftUI : tint.color.swiftUI
                    context.fill(Path(r), with: .color(on ? color.opacity(frame.pulse) : tint.color.swiftUI.opacity(0.12)))
                }
            }
            .shadow(color: tint.color.swiftUI.opacity(state.present ? 0.5 * frame.pulse : 0), radius: diameter * 0.06)

            switch center {
            case .symbol(let name):
                Image(systemName: name)
                    .font(.system(size: max(8, diameter * 0.24), weight: .semibold))
                    .foregroundStyle(WidgetStyle.primary)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, diameter * 0.08)
            case .percent(let size):
                Text(state.present ? "\(percentValue)%" : "-")
                    .font(.system(size: size * 0.55, weight: .bold, design: .monospaced))
                    .foregroundStyle(WidgetStyle.primary)
                    .scaleEffect(bounce(frame))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, diameter * 0.02)
            case .none:
                EmptyView()
            }
        }
        .overlay(alignment: .topTrailing) {
            if state.charging {
                bolt(frame, size: diameter * 0.2)
            }
        }
    }

    // MARK: 能量粒子

    private func particles(_ frame: Frame) -> some View {
        let tint = frame.tint
        let line = max(2.5, diameter * 0.09)
        let progress = state.present ? min(max(state.level, 0), 1) : 0
        return ZStack {
            Circle()
                .stroke(tint.color.swiftUI.opacity(0.16), lineWidth: line)
                .padding(line / 2)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(AngularGradient(colors: [tint.color.swiftUI, tint.highlight.swiftUI],
                                        center: .center, startAngle: .degrees(0),
                                        endAngle: .degrees(360 * max(progress, 0.01))),
                        style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(line / 2)
                .opacity(frame.pulse)
                .shadow(color: tint.color.swiftUI.opacity(0.6 * frame.pulse), radius: diameter * 0.08)
            if state.charging, frame.moving {
                Canvas { context, size in
                    let mid = CGPoint(x: size.width / 2, y: size.height / 2)
                    let radius = size.width / 2 - line / 2
                    let speed = BatteryMotion.chargeSpeed(watts: state.watts)
                    let count = 12
                    let spark = sparkColor(tint)
                    for i in 0..<count {
                        let phase = frac(frame.t * 0.3 * speed + Double(i) / Double(count))
                        let angle = -Double.pi / 2 + 2 * .pi * phase
                        let wobble = sin(frame.t * 3 + Double(i)) * line * 0.25
                        let point = CGPoint(x: mid.x + (radius + wobble) * cos(angle),
                                            y: mid.y + (radius + wobble) * sin(angle))
                        let inArc = phase <= progress
                        let r = line * (inArc ? 0.32 : 0.22)
                        let opacity = inArc ? 0.95 : 0.4
                        context.fill(Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: 2 * r, height: 2 * r)),
                                     with: .color(spark.opacity(opacity)))
                    }
                }
                .allowsHitTesting(false)
            }
            centerContent(frame)
            sweep(frame, radius: diameter / 2 - line / 2)
        }
        .overlay(alignment: .bottomTrailing) { cornerBolt(frame) }
    }

    // MARK: 小熊猫抱电池

    /// Cheering on the charger, asleep below 20%, otherwise just sitting.
    private var pandaLook: PetLook {
        if state.charging { return .cheer }
        if state.present, BatteryColorMap.percent(state.level) < 20 { return .rest }
        return .idle
    }

    private func panda(_ frame: Frame, image: NSImage) -> some View {
        let tint = frame.tint
        let hop: CGFloat = state.charging && frame.moving ? -CGFloat(abs(sin(frame.t * 3.2))) * diameter * 0.04 : 0
        let battery = CGSize(width: diameter * 0.46, height: diameter * 0.24)
        return ZStack(alignment: .bottomTrailing) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: diameter, height: diameter * 0.96, alignment: .bottom)
                .offset(y: hop)
            miniBattery(frame, size: battery, tint: tint)
                .offset(x: diameter * 0.02, y: -diameter * 0.02)
            if case .percent(let size) = center {
                Text(state.present ? "\(percentValue)%" : "-")
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.black.opacity(0.45)))
                    .scaleEffect(bounce(frame))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    /// The battery the panda holds: a SwiftUI outline, its level in the
    /// level's colour, and a bolt while charging.
    private func miniBattery(_ frame: Frame, size: CGSize, tint: BatteryColorMap.Tint) -> some View {
        let line = max(1, size.height * 0.12)
        let fill = state.present ? min(max(state.level, 0), 1) : 0
        return HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: size.height * 0.22, style: .continuous)
                    .fill(.black.opacity(0.55))
                RoundedRectangle(cornerRadius: size.height * 0.14, style: .continuous)
                    .fill(tint.color.swiftUI.opacity(frame.pulse))
                    .frame(width: max(line, (size.width - line * 3) * fill))
                    .padding(line * 1.2)
                RoundedRectangle(cornerRadius: size.height * 0.22, style: .continuous)
                    .strokeBorder(.white.opacity(0.9), lineWidth: line)
                if state.charging {
                    bolt(frame, size: size.height * 0.62)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: size.width, height: size.height)
            RoundedRectangle(cornerRadius: 1)
                .fill(.white.opacity(0.9))
                .frame(width: max(1.5, size.width * 0.06), height: size.height * 0.4)
        }
        .shadow(color: tint.color.swiftUI.opacity(0.5 * frame.pulse), radius: size.height * 0.3)
    }
}

/// The number on a card hops once when the adapter goes in or the battery
/// fills, the same beat as the sweep round the gauge. Nothing under 减少动态效果.
struct BatteryPlugBounce: ViewModifier {
    var trigger: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(trigger: Date?) {
        self.trigger = trigger
    }

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 1.0, trigger: reduceMotion ? nil : trigger) { view, scale in
            view.scaleEffect(scale, anchor: .leading)
        } keyframes: { _ in
            KeyframeTrack {
                SpringKeyframe(1.0, duration: 0.01)
                SpringKeyframe(1.16, duration: 0.18)
                SpringKeyframe(1.0, duration: 0.4)
            }
        }
    }
}

/// Today's level as a line, with the stretches spent charging shaded light
/// green behind it. Hours with no sample (asleep, Docket not running) are
/// left as gaps.
struct BatteryDayChart: View {
    var history: BatteryHistory
    var day: Date
    var now: Date

    var body: some View {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
        let segments = history.segments(from: start, to: end)
        let spans = history.chargingSpans(from: start, to: end)
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { proxy in
                let size = proxy.size
                let span = end.timeIntervalSince(start)
                let x: (Date) -> CGFloat = { CGFloat($0.timeIntervalSince(start) / span) * size.width }
                let y: (Int) -> CGFloat = { size.height * (1 - CGFloat($0) / 100) }
                ZStack(alignment: .topLeading) {
                    // 0, 50 and 100% guides.
                    ForEach([0, 50, 100], id: \.self) { mark in
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: y(mark)))
                            path.addLine(to: CGPoint(x: size.width, y: y(mark)))
                        }
                        .stroke(Color.panelSeparator.opacity(mark == 50 ? 0.8 : 1),
                                style: StrokeStyle(lineWidth: 0.5, dash: mark == 50 ? [3, 3] : []))
                    }
                    ForEach(Array(spans.enumerated()), id: \.offset) { _, interval in
                        Rectangle()
                            .fill(Color(red: 0.35, green: 0.9, blue: 0.5).opacity(0.18))
                            .frame(width: max(1, x(interval.end) - x(interval.start)), height: size.height)
                            .offset(x: x(interval.start))
                    }
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        let points = segment.map { CGPoint(x: x($0.date), y: y($0.percent)) }
                        if points.count == 1, let point = points.first {
                            Circle().fill(Color.panelPrimary).frame(width: 3, height: 3)
                                .offset(x: point.x - 1.5, y: point.y - 1.5)
                        } else {
                            Path { path in path.addLines(points) }
                                .stroke(Color.panelPrimary.opacity(0.9),
                                        style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                        }
                    }
                    // Now.
                    if now >= start, now < end {
                        Rectangle()
                            .fill(Color.panelTertiary)
                            .frame(width: 1, height: size.height)
                            .offset(x: x(now))
                    }
                }
            }
            .frame(height: 64)
            HStack {
                ForEach([tr("0 时"), tr("6 时"), tr("12 时"), tr("18 时"), tr("24 时")], id: \.self) { label in
                    Text(label)
                    if label != tr("24 时") { Spacer(minLength: 0) }
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(.panelTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("今天的电量曲线")
    }
}
