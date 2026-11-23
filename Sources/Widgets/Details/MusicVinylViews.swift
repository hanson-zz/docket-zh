import AppKit
import SwiftUI

/// 正在播放面板「黑胶模式」的唱台：左边真实封面的玻璃卡，后面一张代码画的黑胶
/// 唱片（细纹路，中心标签用封面图，没有封面用封面主色），右上金属唱臂，唱片下方
/// 很淡的水波纹。
///
/// 播放时唱片匀速慢转、唱臂落在唱片上并按进度从外圈慢慢移向内圈，水波纹缓慢
/// 扩散；暂停时唱片停在当时的角度、唱臂抬回支架、水波纹静止。减弱动态效果时
/// 不转不扩散，只画静帧和唱臂该在的位置。转动只在面板看得见并在播放时跑
/// （`TimelineView` 暂停），唱片本身画好后整张转（`drawingGroup` 后只改旋转）。
/// 「看得见」既看 onAppear / onDisappear，也看所在窗口：面板关上只是 orderOut，
/// 视图不会消失，靠窗口状态停帧（`MediaWindowShown`）。
/// 摆位、落针角度、转速和水波纹都在 Core `MusicVinyl`。
struct VinylStageView<Cover: View>: View {
    var artwork: NSImage?
    var tint: ArtworkTint?
    var playing: Bool
    /// 0...1，读不到时长时是 nil（唱臂停在外圈）。
    var progress: Double?
    @ViewBuilder var cover: (CGFloat) -> Cover

    @State private var width: CGFloat = CGFloat(MusicVinyl.designWidth)
    @State private var visible = false
    /// 所在窗口在屏幕上、没被整个挡住。
    @State private var windowShown = true
    /// 上次停下时唱片的角度，和开始转的时刻（停着时是 nil）。
    @State private var spinBase: Double = 0
    @State private var spinSince: Date?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    private var stage: MusicVinyl.Stage { MusicVinyl.stage(width: Double(width)) }
    private var fps: Double? {
        MusicVinyl.framesPerSecond(playing: playing,
                                   visible: MediaOnScreen.visible(appeared: visible, windowShown: windowShown),
                                   reduceMotion: reduceMotion)
    }
    private var spinning: Bool { fps != nil }

    var body: some View {
        let stage = stage
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: CGFloat(stage.height))
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { new in
                width = new
            }
            .overlay(alignment: .top) {
                deck(stage)
                    .frame(width: CGFloat(stage.width), height: CGFloat(stage.height))
            }
            .onAppear {
                visible = true
                updateSpin(spinning)
            }
            .onDisappear {
                updateSpin(false)
                visible = false
            }
            .onChange(of: spinning) { _, now in updateSpin(now) }
            .trackingWindowShown($windowShown)
    }

    /// 开始转时记下时刻，停下时把转到的角度存起来，下次从这里接着转。
    private func updateSpin(_ on: Bool) {
        let now = Date()
        if on {
            if spinSince == nil { spinSince = now }
        } else if let since = spinSince {
            spinBase = MusicVinyl.discAngle(base: spinBase, since: since, now: now)
            spinSince = nil
        }
    }

    private func deck(_ stage: MusicVinyl.Stage) -> some View {
        let s = CGFloat(stage.scale)
        let center = CGPoint(x: stage.center.x, y: stage.center.y)
        let r = CGFloat(stage.radius)
        return ZStack(alignment: .topLeading) {
            TimelineView(.animation(minimumInterval: 1 / (fps ?? MusicVinyl.fps), paused: fps == nil)) { tick in
                let t: Double? = spinning ? tick.date.timeIntervalSinceReferenceDate : nil
                let angle = MusicVinyl.discAngle(base: spinBase, since: spinning ? spinSince : nil,
                                                 now: tick.date)
                ZStack(alignment: .topLeading) {
                    VinylRipples(stage: stage, ripples: MusicVinyl.ripples(t: t), dark: scheme == .dark)
                    // 唱盘：唱片底下一圈金属边，不转。
                    Circle()
                        .fill(LinearGradient(colors: platterColors, startPoint: .topLeading,
                                             endPoint: .bottomTrailing))
                        .overlay(Circle().strokeBorder(.white.opacity(scheme == .dark ? 0.12 : 0.5),
                                                       lineWidth: 0.6))
                        .frame(width: (r + 5 * s) * 2, height: (r + 5 * s) * 2)
                        .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.18), radius: 10 * s, y: 6 * s)
                        .position(center)
                    VinylDisc(radius: r, label: CGFloat(stage.label), artwork: artwork,
                              labelColor: labelColor, scale: s)
                        .frame(width: r * 2, height: r * 2)
                        .rotationEffect(.degrees(angle))
                        .position(center)
                    // 唱片表面的反光跟着灯，不跟着唱片转。
                    VinylSheen(radius: r, label: CGFloat(stage.label))
                        .frame(width: r * 2, height: r * 2)
                        .position(center)
                    // 中心轴。
                    Circle()
                        .fill(LinearGradient(colors: [Color(white: 0.95), Color(white: 0.55)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 7 * s, height: 7 * s)
                        .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
                        .position(center)
                }
            }
            .accessibilityHidden(true)

            cover(CGFloat(stage.cover.width))
                .frame(width: CGFloat(stage.cover.width), height: CGFloat(stage.cover.height))
                .position(x: CGFloat(stage.cover.x + stage.cover.width / 2),
                          y: CGFloat(stage.cover.y + stage.cover.height / 2))

            VinylTonearm(stage: stage, angle: MusicVinyl.armAngle(stage, progress: progress, playing: playing),
                         dark: scheme == .dark)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.9), value: playing)
                .animation(reduceMotion || !playing ? nil : .linear(duration: MusicTile.pollInterval),
                           value: progress)
                .accessibilityHidden(true)
        }
    }

    private var platterColors: [Color] {
        scheme == .dark
            ? [Color(white: 0.34), Color(white: 0.16)]
            : [Color(white: 0.93), Color(white: 0.70)]
    }

    /// 没有封面时中心标签用封面主色（读不到主色时是中性灰）。
    private var labelColor: Color {
        guard let tint else { return Color(white: 0.55) }
        let rgb = tint.glow
        return Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }
}

/// 唱片本身：黑色底、一圈圈细纹路、两道分轨的空白、中心标签。整张画好后
/// 只转不重画。
private struct VinylDisc: View {
    var radius: CGFloat
    var label: CGFloat
    var artwork: NSImage?
    var labelColor: Color
    var scale: CGFloat

    var body: some View {
        ZStack {
            Canvas { context, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                func ring(_ r: CGFloat) -> Path {
                    Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                }
                context.fill(ring(radius), with: .radialGradient(
                    Gradient(colors: [Color(white: 0.13), Color(white: 0.06)]),
                    center: c, startRadius: label, endRadius: radius))
                // 细纹路：间距 1.6pt，明暗交替。
                var r = label * 1.08
                var index = 0
                while r < radius * 0.97 {
                    context.stroke(ring(r), with: .color(.white.opacity(index.isMultiple(of: 2) ? 0.05 : 0.025)),
                                   lineWidth: 0.5)
                    r += 1.6 * scale
                    index += 1
                }
                // 两道分轨的空白，稍亮一点。
                for ratio: CGFloat in [0.62, 0.8] {
                    context.stroke(ring(radius * ratio), with: .color(.white.opacity(0.09)), lineWidth: 1.4 * scale)
                }
                context.stroke(ring(radius - 0.5), with: .color(.white.opacity(0.14)), lineWidth: 1)
                // 标签外一圈压纹。
                context.stroke(ring(label + 2 * scale), with: .color(.black.opacity(0.6)), lineWidth: 2 * scale)
            }
            Group {
                if let artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                } else {
                    // 纯色标签上两道弧线，转起来看得出在转。
                    labelColor
                        .overlay {
                            Circle()
                                .trim(from: 0.05, to: 0.3)
                                .stroke(.white.opacity(0.45), style: StrokeStyle(lineWidth: 1.5 * scale, lineCap: .round))
                                .padding(label * 0.3)
                        }
                        .overlay {
                            Circle()
                                .trim(from: 0.55, to: 0.7)
                                .stroke(.black.opacity(0.25), style: StrokeStyle(lineWidth: 1.5 * scale, lineCap: .round))
                                .padding(label * 0.45)
                        }
                }
            }
            .frame(width: label * 2, height: label * 2)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.black.opacity(0.25), lineWidth: 0.5))
        }
        .drawingGroup()
    }
}

/// 唱片上的一道斜光，不转。
private struct VinylSheen: View {
    var radius: CGFloat
    var label: CGFloat

    var body: some View {
        Circle()
            .fill(AngularGradient(stops: [
                .init(color: .white.opacity(0), location: 0),
                .init(color: .white.opacity(0.10), location: 0.12),
                .init(color: .white.opacity(0), location: 0.25),
                .init(color: .white.opacity(0), location: 0.5),
                .init(color: .white.opacity(0.07), location: 0.62),
                .init(color: .white.opacity(0), location: 0.75),
                .init(color: .white.opacity(0), location: 1),
            ], center: .center))
            .mask {
                Circle()
                    .strokeBorder(.black, lineWidth: radius - label - 2)
            }
            .allowsHitTesting(false)
    }
}

/// 唱片下方很淡的水波纹：扁椭圆一圈圈往外扩，越往外越淡。浅色外观淡蓝灰、
/// 深色外观深蓝灰，透明度不超过 `MusicVinyl.rippleOpacity`。
private struct VinylRipples: View {
    var stage: MusicVinyl.Stage
    var ripples: [MusicVinyl.Ripple]
    var dark: Bool

    var body: some View {
        Canvas { context, _ in
            let tone = dark
                ? Color(.sRGB, red: 0.30, green: 0.42, blue: 0.58, opacity: 1)
                : Color(.sRGB, red: 0.50, green: 0.60, blue: 0.74, opacity: 1)
            let cx = stage.center.x
            let cy = stage.center.y + stage.radius * 0.55
            for ring in ripples where ring.opacity > 0.001 {
                let w = stage.radius * ring.scale
                let h = w * 0.3
                let rect = CGRect(x: cx - w, y: cy - h, width: w * 2, height: h * 2)
                context.stroke(Path(ellipseIn: rect), with: .color(tone.opacity(ring.opacity)),
                               lineWidth: 1.2 * stage.scale)
            }
        }
        .frame(width: CGFloat(stage.width), height: CGFloat(stage.height))
        .allowsHitTesting(false)
    }
}

/// 金属唱臂：转轴底座、配重、细管和唱头，绕转轴转；支架画在唱臂收起时唱管
/// 搭着的地方。
private struct VinylTonearm: View {
    var stage: MusicVinyl.Stage
    var angle: Double
    var dark: Bool

    var body: some View {
        let s = CGFloat(stage.scale)
        let length = CGFloat(stage.armLength)
        let top = 18 * s
        let frameWidth = 30 * s
        let frameHeight = top + length + 4 * s
        let pivot = CGPoint(x: stage.pivot.x, y: stage.pivot.y)
        let base = CGFloat(stage.pivotBase)
        ZStack(alignment: .topLeading) {
            // 支架：唱臂收起时搭在这里。
            RoundedRectangle(cornerRadius: 2 * s, style: .continuous)
                .fill(metal(horizontal: false))
                .frame(width: 10 * s, height: 6 * s)
                .shadow(color: .black.opacity(0.25), radius: 1.5 * s, y: 1 * s)
                .position(x: pivot.x, y: pivot.y + length * 0.66)
            // 转轴底座。
            Circle()
                .fill(metal(horizontal: false))
                .overlay(Circle().strokeBorder(.white.opacity(dark ? 0.18 : 0.6), lineWidth: 0.6))
                .frame(width: base * 2, height: base * 2)
                .shadow(color: .black.opacity(dark ? 0.5 : 0.22), radius: 4 * s, y: 2 * s)
                .position(pivot)
            arm(s: s, length: length, top: top)
                .frame(width: frameWidth, height: frameHeight)
                .rotationEffect(.degrees(angle), anchor: UnitPoint(x: 0.5, y: top / frameHeight))
                .position(x: pivot.x, y: pivot.y - top + frameHeight / 2)
            // 转轴顶盖。
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.98), Color(white: 0.6)],
                                     center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: base * 0.6))
                .frame(width: base * 1.05, height: base * 1.05)
                .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
                .position(pivot)
        }
        .frame(width: CGFloat(stage.width), height: CGFloat(stage.height), alignment: .topLeading)
    }

    /// 竖着画：配重在转轴上面，细管往下，最下面是唱头，唱针在底边中点。
    private func arm(s: CGFloat, length: CGFloat, top: CGFloat) -> some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 3 * s, style: .continuous)
                .fill(metal(horizontal: true))
                .frame(width: 12 * s, height: 13 * s)
            Spacer().frame(height: top - 13 * s)
            Capsule()
                .fill(metal(horizontal: true))
                .frame(width: 3.5 * s, height: max(0, length - 18 * s))
                .shadow(color: .black.opacity(0.3), radius: 1.5 * s, x: 1 * s, y: 1.5 * s)
            RoundedRectangle(cornerRadius: 2.5 * s, style: .continuous)
                .fill(metal(horizontal: true))
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color(white: 0.2)).frame(width: 2 * s, height: 3 * s)
                }
                .frame(width: 10 * s, height: 18 * s)
                .shadow(color: .black.opacity(0.35), radius: 2 * s, x: 1 * s, y: 2 * s)
            Spacer(minLength: 0)
        }
    }

    private func metal(horizontal: Bool) -> LinearGradient {
        let colors = dark
            ? [Color(white: 0.55), Color(white: 0.9), Color(white: 0.45)]
            : [Color(white: 0.62), Color(white: 0.97), Color(white: 0.58)]
        return horizontal
            ? LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
            : LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
