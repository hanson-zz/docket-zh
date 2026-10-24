import SwiftUI

/// 电池格经典和液态外观画的沙漏：上下两个玻璃泡、上下两块托，下泡的沙面高度就是
/// 电量（`BatteryHourglass.sandHeight`）。充电时上泡装着待充的沙，中间凹成
/// 漏斗，一道细流和几粒沙往下落，落点溅起两三粒，右下角一个闪电角标；不充电
/// 时上泡空、沙面平整。
///
/// 只在充电、卡片看得见时动，20 帧（`BatteryHourglass.framesPerSecond`）；
/// 减少动态效果时是一张静止的图。颜色规则在 `BatteryHourglass.sandColor`。
struct BatteryHourglassCell: View {
    var level: Double
    var present: Bool
    var charging: Bool
    var lowPower = false
    /// 卡片在屏幕上时沙才流。
    var visible: Bool
    /// 「外观 ▸ 颜色」选了颜色时的主题色（已调过可读性），默认 nil。
    var theme: ColorCode?
    /// 右下角的闪电角标；很小的沙漏（竖排扩展栏的多台设备）不画，免得糊成一团。
    var showsBolt = true
    /// 面板头部的大沙漏：浅色外观下沙色压到 3 : 1（`BatteryHourglassPanel.heroSand`），
    /// 闪电角标换成白底；深色和卡片一样。
    var panel = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let fps = BatteryHourglass.framesPerSecond(charging: charging, present: present, visible: visible,
                                                   reduceMotion: reduceMotion)
        TimelineView(.animation(minimumInterval: 1 / (fps ?? BatteryHourglass.framesPerSecond),
                                paused: fps == nil)) { timeline in
            // 取余免得时间戳太大让虚线相位失真；十分钟跳一次，看不出来。
            let t = fps == nil ? 0 : timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 600)
            Canvas { context, size in
                draw(&context, size: size, t: t)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: 形状

    private struct Outline {
        var cx: CGFloat, y0: CGFloat, h: CGFloat, w: CGFloat
        var cap: CGFloat, ya: CGFloat, yb: CGFloat, ym: CGFloat
        var bw: CGFloat, nw: CGFloat, hh: CGFloat

        /// 沙漏高宽比约 1 : 0.64，按放得下的最大尺寸居中。要画闪电角标时右边
        /// 多留出角标伸出去的那一块（总宽约 0.76 个高），角标出现、消失时
        /// 沙漏大小不跳。
        init(size: CGSize, badge: Bool) {
            let span: CGFloat = badge ? 0.76 : 0.64
            let h = min(size.height, size.width / span)
            self.h = h
            w = h * 0.64
            cx = (size.width - span * h) / 2 + 0.32 * h
            y0 = (size.height - h) / 2
            cap = h * 0.075
            ya = y0 + cap + h * 0.01
            yb = y0 + h - cap - h * 0.01
            ym = (ya + yb) / 2
            bw = w * 0.42
            nw = max(w * 0.035, 0.6)
            hh = ym - ya
        }

        /// 左上一段轮廓（顶到颈）的四个控制点；其余三段按左右、上下镜像。
        func curve(sign: CGFloat, top: Bool) -> [CGPoint] {
            let base: [(CGFloat, CGFloat)] = [(bw, ya), (bw * 1.02, ya + hh * 0.80), (nw, ym - hh * 0.13), (nw, ym)]
            return base.map { dx, y in
                CGPoint(x: cx + sign * dx, y: top ? y : 2 * ym - y)
            }
        }

        var topBulb: Path {
            let l = curve(sign: -1, top: true), r = curve(sign: 1, top: true)
            var p = Path()
            p.move(to: l[0])
            p.addCurve(to: l[3], control1: l[1], control2: l[2])
            p.addLine(to: r[3])
            p.addCurve(to: r[0], control1: r[2], control2: r[1])
            p.closeSubpath()
            return p
        }

        var bottomBulb: Path {
            let l = curve(sign: -1, top: false), r = curve(sign: 1, top: false)
            var p = Path()
            p.move(to: l[3])
            p.addCurve(to: l[0], control1: l[2], control2: l[1])
            p.addLine(to: r[0])
            p.addCurve(to: r[3], control1: r[1], control2: r[2])
            p.closeSubpath()
            return p
        }

        var glass: Path {
            let lt = curve(sign: -1, top: true), rt = curve(sign: 1, top: true)
            let lb = curve(sign: -1, top: false), rb = curve(sign: 1, top: false)
            var p = Path()
            p.move(to: lt[0])
            p.addCurve(to: lt[3], control1: lt[1], control2: lt[2])
            p.addCurve(to: lb[0], control1: lb[2], control2: lb[1])
            p.addLine(to: rb[0])
            p.addCurve(to: rb[3], control1: rb[1], control2: rb[2])
            p.addCurve(to: rt[0], control1: rt[2], control2: rt[1])
            p.closeSubpath()
            return p
        }
    }

    // MARK: 画

    private func draw(_ context: inout GraphicsContext, size: CGSize, t: Double) {
        let s = Outline(size: size, badge: showsBolt)
        guard s.h > 4 else { return }
        let rgb = panel
            ? BatteryHourglassPanel.heroSand(level: level, charging: charging, lowPower: lowPower, present: present,
                                             theme: theme, dark: scheme == .dark)
            : BatteryHourglass.sandColor(level: level, charging: charging, lowPower: lowPower, present: present,
                                         theme: theme)
        let sand = rgb.swiftUI
        let sandHi = rgb.mixed(with: .white, 0.28).swiftUI
        let sandLo = rgb.mixed(with: BatteryRGB(0, 0, 0), 0.28).swiftUI
        let ink: Color = scheme == .dark ? .white : .black
        let flowing = present && charging

        // 玻璃底：很淡的一层。
        context.fill(s.glass, with: .color(ink.opacity(0.05)))

        // 下泡的沙堆。
        let height = CGFloat(BatteryHourglass.sandHeight(level: level, present: present))
        let mound = s.h * CGFloat(BatteryHourglass.moundHeight(charging: flowing))
        let sy = s.yb - (s.yb - s.ym) * height
        let peakY = sy - mound * 0.9
        if height > 0 {
            var bottom = context
            bottom.clip(to: s.bottomBulb)
            let edge = sy + mound * 0.6
            var pile = Path()
            pile.move(to: CGPoint(x: s.cx - s.w, y: edge))
            pile.addLine(to: CGPoint(x: s.cx - s.w * 0.42, y: edge))
            pile.addQuadCurve(to: CGPoint(x: s.cx + s.w * 0.42, y: edge),
                              control: CGPoint(x: s.cx, y: sy - mound * 1.6))
            pile.addLine(to: CGPoint(x: s.cx + s.w, y: edge))
            pile.addLine(to: CGPoint(x: s.cx + s.w, y: s.yb + 2))
            pile.addLine(to: CGPoint(x: s.cx - s.w, y: s.yb + 2))
            pile.closeSubpath()
            bottom.fill(pile, with: .linearGradient(Gradient(colors: [sandHi, sand]),
                                                    startPoint: CGPoint(x: s.cx, y: sy - mound),
                                                    endPoint: CGPoint(x: s.cx, y: s.yb)))
            // 沙粒纹理：固定位置的深浅小点，沙漏够大才画。
            if s.h >= 28 {
                grains(&bottom, count: 12, seed: 7, x: s.cx, half: s.w * 0.42, top: sy + mound, bottom: s.yb,
                       radius: s.h * 0.009, colors: [sandHi, sandLo])
            }
            var surface = Path()
            surface.move(to: CGPoint(x: s.cx - s.w * 0.42, y: edge))
            surface.addQuadCurve(to: CGPoint(x: s.cx + s.w * 0.42, y: edge),
                                 control: CGPoint(x: s.cx, y: sy - mound * 1.6))
            bottom.stroke(surface, with: .color(.white.opacity(0.35)), lineWidth: max(s.h * 0.012, 0.5))
        }

        if flowing {
            // 上泡：待充的沙，中间凹成漏斗。
            let topFrac = CGFloat(BatteryHourglass.topSand(level: level, charging: charging, present: present))
            let ty = s.ym - (s.ym - s.ya) * (0.25 + 0.7 * topFrac)
            // 漏斗随时间极慢地加深一点点，看得出沙在往下走。
            let dip = s.h * (0.055 + 0.01 * CGFloat(sin(t * 1.3)))
            var top = context
            top.clip(to: s.topBulb)
            var upper = Path()
            upper.move(to: CGPoint(x: s.cx - s.w, y: ty))
            upper.addLine(to: CGPoint(x: s.cx - s.w * 0.4, y: ty))
            upper.addQuadCurve(to: CGPoint(x: s.cx + s.w * 0.4, y: ty),
                               control: CGPoint(x: s.cx, y: ty + dip * 2.2))
            upper.addLine(to: CGPoint(x: s.cx + s.w, y: ty))
            upper.addLine(to: CGPoint(x: s.cx + s.w, y: s.ym + 1))
            upper.addLine(to: CGPoint(x: s.cx - s.w, y: s.ym + 1))
            upper.closeSubpath()
            top.fill(upper, with: .linearGradient(Gradient(colors: [sandHi, sand]),
                                                  startPoint: CGPoint(x: s.cx, y: ty),
                                                  endPoint: CGPoint(x: s.cx, y: s.ym)))

            // 细流：颈口到峰顶，虚线往下走，看起来是一粒粒在流。
            let streamWidth = max(s.h * 0.016, 0.8)
            var stream = Path()
            stream.move(to: CGPoint(x: s.cx, y: s.ym - s.h * 0.02))
            stream.addLine(to: CGPoint(x: s.cx, y: peakY))
            let dash = max(s.h * 0.03, 1.2)
            context.stroke(stream, with: .color(sandHi),
                           style: StrokeStyle(lineWidth: streamWidth, lineCap: .round,
                                              dash: [dash, dash * 0.6],
                                              dashPhase: -CGFloat(t * Double(s.h) * 0.9)))

            // 下落的颗粒：三粒错开相位，从颈口落到峰顶，左右轻轻摆。
            let fall = peakY - s.ym
            let r = max(s.h * 0.011, 0.6)
            if fall > r * 2 {
                for k in 0..<3 {
                    let phase = frac(t * 1.4 + Double(k) / 3)
                    let y = s.ym + fall * CGFloat(phase * phase * 0.7 + phase * 0.3)
                    let x = s.cx + s.h * 0.022 * CGFloat(sin((phase + Double(k)) * .pi * 2))
                    context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                                 with: .color(sandHi))
                }
                // 峰顶溅起的两三粒：每一轮从落点弹起再落回。
                let splash: [(CGFloat, CGFloat, Double)] = [(-0.09, 0.03, 0.0), (0.1, 0.045, 0.33), (0.06, 0.08, 0.66)]
                for (dx, lift, offset) in splash {
                    let p = frac(t * 1.1 + offset)
                    let arc = CGFloat(sin(p * .pi))
                    let x = s.cx + dx * s.h * CGFloat(0.5 + 0.5 * p)
                    let y = peakY - lift * s.h * arc
                    let rr = r * 0.8
                    context.fill(Path(ellipseIn: CGRect(x: x - rr, y: y - rr, width: rr * 2, height: rr * 2)),
                                 with: .color(sandHi.opacity(0.9 * Double(arc) + 0.1)))
                }
            }
        }

        // 玻璃轮廓和左侧一道高光。
        let line = max(s.h * 0.028, 0.9)
        context.stroke(s.glass, with: .color(ink.opacity(present ? 0.62 : 0.3)),
                       style: StrokeStyle(lineWidth: line, lineJoin: .round))
        var gloss = Path()
        gloss.move(to: CGPoint(x: s.cx - s.bw * 0.7, y: s.ya + s.hh * 0.12))
        gloss.addCurve(to: CGPoint(x: s.cx - s.bw * 0.22, y: s.ya + s.hh * 0.8),
                       control1: CGPoint(x: s.cx - s.bw * 0.72, y: s.ya + s.hh * 0.45),
                       control2: CGPoint(x: s.cx - s.bw * 0.35, y: s.ya + s.hh * 0.7))
        context.stroke(gloss, with: .color(.white.opacity(0.28)),
                       style: StrokeStyle(lineWidth: line * 0.9, lineCap: .round))

        // 上下两块托。
        for y in [s.y0, s.y0 + s.h - s.cap] {
            let rect = CGRect(x: s.cx - s.w / 2, y: y, width: s.w, height: s.cap)
            context.fill(Path(roundedRect: rect, cornerRadius: s.cap / 2),
                         with: .color(ink.opacity(present ? 0.78 : 0.35)))
        }

        // 闪电角标：深色小圆、沙色细边、沙色闪电。
        if flowing, showsBolt {
            let br = s.h * 0.17
            let center = CGPoint(x: s.cx + s.w * 0.42, y: s.yb - br * 0.55)
            let disc = Path(ellipseIn: CGRect(x: center.x - br, y: center.y - br, width: br * 2, height: br * 2))
            // 面板浅色下白底：深色小圆压在浅玻璃上太重。
            let lightDisc = panel && scheme == .light
            context.fill(disc, with: .color(lightDisc ? Color.white.opacity(0.96)
                                            : Color(red: 0x16 / 255, green: 0x16 / 255, blue: 0x1A / 255).opacity(0.92)))
            context.stroke(disc, with: .color(sand.opacity(lightDisc ? 0.7 : 0.55)), lineWidth: max(s.h * 0.012, 0.6))
            context.fill(boltPath(center: center, radius: br * 1.05), with: .color(sand))
        }
    }

    private func frac(_ value: Double) -> Double { value - value.rounded(.down) }

    /// 固定种子的小点，每帧位置一样，不闪。
    private func grains(_ context: inout GraphicsContext, count: Int, seed: UInt64, x: CGFloat, half: CGFloat,
                        top: CGFloat, bottom: CGFloat, radius: CGFloat, colors: [Color]) {
        guard bottom > top else { return }
        var state = seed &* 6364136223846793005 &+ 1442695040888963407
        func next() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(Double(state >> 33) / Double(1 << 31))
        }
        for i in 0..<count {
            let gx = x - half + next() * half * 2
            let gy = top + next() * (bottom - top)
            let gr = max(radius * (0.7 + next() * 0.6), 0.4)
            context.fill(Path(ellipseIn: CGRect(x: gx - gr, y: gy - gr, width: gr * 2, height: gr * 2)),
                         with: .color(colors[i % colors.count].opacity(0.75)))
        }
    }

    private func boltPath(center: CGPoint, radius: CGFloat) -> Path {
        let points: [(CGFloat, CGFloat)] = [(0.12, -0.6), (-0.38, 0.08), (-0.04, 0.08), (-0.14, 0.6),
                                            (0.38, -0.1), (0.04, -0.1)]
        var p = Path()
        for (i, (px, py)) in points.enumerated() {
            let point = CGPoint(x: center.x + px * radius, y: center.y + py * radius)
            if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
        }
        p.closeSubpath()
        return p
    }
}
