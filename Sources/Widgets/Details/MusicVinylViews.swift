import AppKit
import SwiftUI

/// 正在播放面板「黑胶模式」的唱台（V2）：一张代码画的大黑胶唱片放在带金属边和厚度
/// 的唱盘上，中心圆形标签是专辑封面（没有封面用封面主色加两道弧线），右上金属唱臂
/// 带转轴底座、配重和唱头；唱盘两侧露出一圈很淡的自然水面（细波纹加柔和倒影），
/// 左下角趴着沿用的听歌小熊猫贴纸。
///
/// 动作都在 Core `VinylMotion`：开始播放时唱臂从支架缓缓移到外圈、轻轻落针、唱片
/// 起转；暂停时唱片慢慢减速停下、唱针微抬、唱臂停在原处；继续时重新落针，从暂停的
/// 角度接着转；放完或停止时抬针、唱臂缓缓回到支架；切歌时唱针抬一下回到外圈。
/// 摆位和落针角度在 Core `MusicVinyl`。
///
/// 只在动作进行中、面板看得见（出现过并且所在窗口在屏幕上，`MediaWindowShown`）并且
/// 没开减弱动态效果时逐帧刷新；其余时候 `TimelineView` 暂停，只画静帧。减弱动态效果
/// 时唱臂和唱针直接画在终点，唱片不转、水面不动。唱片本身画好后整张转
/// （`drawingGroup` 后只改旋转）。
struct VinylStageView: View {
    var artwork: NSImage?
    var tint: ArtworkTint?
    var playing: Bool
    /// 0...1，读不到时长时是 nil（唱臂停在外圈）。
    var progress: Double?
    /// 这首放完了（停在最后）：抬针、唱臂归位。
    var ended: Bool
    /// 认歌用的键，换歌时唱针回到外圈。
    var track: String

    @State private var width: CGFloat = CGFloat(MusicVinyl.designWidth)
    @State private var visible = false
    /// 所在窗口在屏幕上、没被整个挡住。
    @State private var windowShown = true
    @State private var motion: VinylMotion?
    /// 动作还在进行（唱片在转、在加减速，或唱臂在动）。到点时由一次性任务改回 false。
    @State private var animating = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    private var stage: MusicVinyl.Stage { MusicVinyl.stage(width: Double(width)) }
    private var dark: Bool { scheme == .dark }
    private var fps: Double? {
        MusicVinyl.framesPerSecond(playing: animating,
                                   visible: MediaOnScreen.visible(appeared: visible, windowShown: windowShown),
                                   reduceMotion: reduceMotion)
    }

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
                if motion == nil {
                    motion = .settled(playing: playing && !ended, track: track, groove: groove(stage), now: Date())
                }
                refreshAnimating()
            }
            .onDisappear { visible = false }
            // 播放状态、歌和进度放在一起比：换歌时进度也同时变，要拿变之前的进度算唱臂
            // 原来在哪。
            .onChange(of: Input(playing: playing, ended: ended, track: track, progress: progress)) { old, new in
                apply(old: old, new: new)
            }
            .trackingWindowShown($windowShown)
            .task(id: animating) {
                // 动作在播完前一直逐帧画；到点（唱片停稳、唱臂到位）后停帧。
                guard animating else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(400))
                    if let motion, !motion.isAnimating(at: Date()) {
                        animating = false
                        return
                    }
                }
            }
    }

    private struct Input: Equatable {
        var playing: Bool
        var ended: Bool
        var track: String
        var progress: Double?
    }

    /// 播放状态、歌或进度变了：交给 Core 迁移。进度平常每秒走一点，Core 只在跳了一大截
    /// 时才动唱臂。
    private func apply(old: Input, new: Input) {
        let now = Date()
        let stage = stage
        let groove = MusicVinyl.armAngle(stage, progress: new.progress, playing: true)
        let before = MusicVinyl.armAngle(stage, progress: old.progress, playing: true)
        var next = motion ?? .settled(playing: false, track: old.track, groove: before, now: now)
        next.update(playing: new.playing && !new.ended, ended: new.ended, track: new.track, groove: groove,
                    previousGroove: before, now: now)
        if next != motion { motion = next }
        refreshAnimating()
    }

    private func refreshAnimating() {
        let now = motion?.isAnimating(at: Date()) ?? false
        if now != animating { animating = now }
    }

    /// 按进度算的落针角度（在放时；读不到进度停在外圈）。
    private func groove(_ stage: MusicVinyl.Stage) -> Double {
        MusicVinyl.armAngle(stage, progress: progress, playing: true)
    }

    private func currentFrame(_ stage: MusicVinyl.Stage, at date: Date) -> VinylMotion.Frame {
        let shown = self.motion
            ?? .settled(playing: playing && !ended, track: track, groove: groove(stage), now: date)
        return reduceMotion ? shown.stillFrame(at: date, groove: groove(stage))
            : shown.frame(at: date, groove: groove(stage))
    }

    private func deck(_ stage: MusicVinyl.Stage) -> some View {
        let s = CGFloat(stage.scale)
        let center = CGPoint(x: stage.center.x, y: stage.center.y)
        let r = CGFloat(stage.radius)
        let platter = CGFloat(stage.platter)
        return TimelineView(.animation(minimumInterval: 1 / (fps ?? MusicVinyl.fps), paused: fps == nil)) { tick in
            let frame = currentFrame(stage, at: tick.date)
            let t: Double? = fps == nil ? nil : tick.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .topLeading) {
                VinylWater(stage: stage, ripples: MusicVinyl.ripples(t: t, energy: frame.discSpeed), dark: dark)
                // 唱盘的厚度：往下错一点的深色圆，露出一道侧边。
                Circle()
                    .fill(LinearGradient(colors: dark ? [Color(white: 0.20), Color(white: 0.08)]
                                                      : [Color(white: 0.78), Color(white: 0.58)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: platter * 2, height: platter * 2)
                    .shadow(color: .black.opacity(dark ? 0.55 : 0.22), radius: 12 * s, y: 8 * s)
                    .position(x: center.x, y: center.y + CGFloat(stage.thickness))
                // 唱盘金属边：有写实素材用素材（拉丝金属），没有时斜向渐变加一圈高光。
                Group {
                    if let art = VinylArt.platter {
                        Image(nsImage: art)
                            .resizable()
                            .interpolation(.high)
                            .brightness(dark ? -0.12 : 0)
                    } else {
                        Circle()
                            .fill(AngularGradient(colors: platterMetal, center: .center, angle: .degrees(-35)))
                            .overlay(Circle().strokeBorder(.white.opacity(dark ? 0.22 : 0.75), lineWidth: 0.8))
                            .overlay(Circle().inset(by: 3 * s).strokeBorder(.black.opacity(dark ? 0.35 : 0.12), lineWidth: 0.6))
                    }
                }
                .frame(width: platter * 2, height: platter * 2)
                .position(center)
                VinylDisc(radius: r, label: CGFloat(stage.label), artwork: artwork,
                          labelColor: labelColor, scale: s, texture: VinylArt.disc)
                    .frame(width: r * 2, height: r * 2)
                    .rotationEffect(.degrees(frame.discAngle))
                    .position(center)
                // 唱片表面的反光跟着灯，不跟着唱片转。
                Group {
                    if let art = VinylArt.sheen {
                        Image(nsImage: art)
                            .resizable()
                            .interpolation(.high)
                            .opacity(dark ? 0.85 : 0.7)
                            .allowsHitTesting(false)
                    } else {
                        VinylSheen(radius: r, label: CGFloat(stage.label), dark: dark)
                    }
                }
                .frame(width: r * 2, height: r * 2)
                .position(center)
                // 中心轴。
                Circle()
                    .fill(RadialGradient(colors: [Color(white: 0.98), Color(white: 0.5)],
                                         center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 5 * s))
                    .frame(width: 8 * s, height: 8 * s)
                    .shadow(color: .black.opacity(0.4), radius: 1, y: 0.5)
                    .position(center)
                sticker(stage)
                VinylTonearm(stage: stage, angle: frame.armAngle, lift: frame.lift, dark: dark)
            }
            .frame(width: CGFloat(stage.width), height: CGFloat(stage.height), alignment: .topLeading)
        }
        .accessibilityHidden(true)
    }

    /// 左下角趴着的听歌小熊猫（沿用刘海音乐卡片那张），压在唱盘边上，不挡唱针走的音轨，
    /// 不拦截点击。缺图时不画。
    @ViewBuilder private func sticker(_ stage: MusicVinyl.Stage) -> some View {
        if let image = PandaStateArt.image(.scene(.listen)) {
            let box = stage.sticker
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: CGFloat(box.width), height: CGFloat(box.height), alignment: .bottom)
                .shadow(color: .black.opacity(dark ? 0.4 : 0.18), radius: 3, y: 2)
                .position(x: CGFloat(box.x + box.width / 2), y: CGFloat(box.y + box.height / 2))
                .allowsHitTesting(false)
        }
    }

    private var platterMetal: [Color] {
        dark
            ? [Color(white: 0.30), Color(white: 0.55), Color(white: 0.24), Color(white: 0.42), Color(white: 0.30)]
            : [Color(white: 0.80), Color(white: 0.98), Color(white: 0.74), Color(white: 0.92), Color(white: 0.80)]
    }

    /// 没有封面时中心标签用封面主色（读不到主色时是中性灰）。
    private var labelColor: Color {
        guard let tint else { return Color(white: 0.55) }
        let rgb = tint.glow
        return Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }
}

/// 黑胶模式的写实素材（Resources/Vinyl，用户按效果图用 ChatGPT 画的透明 PNG）。缺哪张就回退那一部分的代码画法。
/// 唱片和反光素材真机上纹路看不出、反光发雾（11-24 用户反馈），已撤掉，用代码画法；唱盘、唱臂保留素材。
@MainActor
enum VinylArt {
    static var disc: NSImage? { PandaStateArt.image("vinyl-disc") }
    static var sheen: NSImage? { PandaStateArt.image("vinyl-sheen") }
    static var platter: NSImage? { PandaStateArt.image("vinyl-platter") }
    static var tonearm: NSImage? { PandaStateArt.image("vinyl-tonearm") }
    /// 唱臂素材（170×887）里转轴圆心和唱针尖的位置，按图片宽高的比例。
    static let armPivot = (x: 0.5, y: 165.0 / 887.0)
    static let armTip = 874.0 / 887.0
    static let armAspect = 170.0 / 887.0
}

/// 唱片本身：黑色底、一圈圈细纹路和压纹、两道分轨的空白、中心圆形封面标签。
/// 整张画好后只转不重画。
private struct VinylDisc: View {
    var radius: CGFloat
    var label: CGFloat
    var artwork: NSImage?
    var labelColor: Color
    var scale: CGFloat
    /// 写实唱片素材（音轨纹理、外圈光边，中心 34% 透明），有它就不用代码画纹路。
    var texture: NSImage?

    var body: some View {
        ZStack {
            if let texture {
                Image(nsImage: texture)
                    .resizable()
                    .interpolation(.high)
                // 素材中心是空的：垫一圈深色，标签外缘和音轨之间不露底。
                Circle()
                    .fill(Color(white: 0.06))
                    .frame(width: label * 2 + 6 * scale, height: label * 2 + 6 * scale)
            } else {
                grooves
            }
            labelView
        }
        .drawingGroup()
    }

    private var grooves: some View {
            Canvas { context, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                func ring(_ r: CGFloat) -> Path {
                    Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
                }
                context.fill(ring(radius), with: .radialGradient(
                    Gradient(colors: [Color(white: 0.14), Color(white: 0.05)]),
                    center: c, startRadius: label, endRadius: radius))
                // 细纹路：间距 1.4pt，明暗交替。
                var r = label * 1.1
                var index = 0
                while r < radius * 0.96 {
                    context.stroke(ring(r), with: .color(.white.opacity(index.isMultiple(of: 2) ? 0.055 : 0.022)),
                                   lineWidth: 0.5)
                    r += 1.4 * scale
                    index += 1
                }
                // 两道分轨的空白，稍亮一点。
                for ratio: CGFloat in [0.6, 0.78] {
                    context.stroke(ring(radius * ratio), with: .color(.white.opacity(0.08)), lineWidth: 1.6 * scale)
                }
                // 外缘：一圈不带纹路的光边，再一道细高光。
                context.stroke(ring(radius - 2 * scale), with: .color(.black.opacity(0.5)), lineWidth: 3 * scale)
                context.stroke(ring(radius - 0.5), with: .color(.white.opacity(0.16)), lineWidth: 1)
                // 标签外一圈压纹。
                context.stroke(ring(label + 3 * scale), with: .color(.black.opacity(0.65)), lineWidth: 3 * scale)
                context.stroke(ring(label + 4.8 * scale), with: .color(.white.opacity(0.07)), lineWidth: 0.6)
            }
    }

    private var labelView: some View {
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
            .overlay(Circle().strokeBorder(.black.opacity(0.3), lineWidth: 0.6))
    }
}

/// 唱片上两道斜光，不转。
private struct VinylSheen: View {
    var radius: CGFloat
    var label: CGFloat
    var dark: Bool

    var body: some View {
        let strong = dark ? 0.13 : 0.11
        Circle()
            .fill(AngularGradient(stops: [
                .init(color: .white.opacity(0), location: 0),
                .init(color: .white.opacity(strong), location: 0.11),
                .init(color: .white.opacity(0), location: 0.22),
                .init(color: .white.opacity(0), location: 0.5),
                .init(color: .white.opacity(strong * 0.7), location: 0.61),
                .init(color: .white.opacity(0), location: 0.72),
                .init(color: .white.opacity(0), location: 1),
            ], center: .center, angle: .degrees(-20)))
            .mask {
                Circle()
                    .strokeBorder(.black, lineWidth: radius - label - 4)
            }
            .allowsHitTesting(false)
    }
}

/// 唱盘两侧露出来的一小片水面：唱片下面一层很淡的倒影，加几圈扁椭圆细波纹，
/// 每圈一道亮线一道暗线像水面起伏，越往外越淡。颜色是中性的灰蓝，透明度不超过
/// `MusicVinyl.rippleOpacity`，不做大面积发光。波纹只按时间和转速生成，不读音频。
private struct VinylWater: View {
    var stage: MusicVinyl.Stage
    var ripples: [MusicVinyl.Ripple]
    var dark: Bool

    var body: some View {
        Canvas { context, _ in
            let cx = stage.center.x
            let cy = stage.center.y + stage.radius * MusicVinyl.waterDrop
            let flat = MusicVinyl.waterFlatness
            // 倒影：唱盘下沿一片很淡、往外淡出的椭圆。
            let rx = stage.radius * (1 + MusicVinyl.rippleReach)
            let pool = CGRect(x: cx - rx, y: cy - rx * flat, width: rx * 2, height: rx * flat * 2)
            let tone = dark
                ? Color(.sRGB, red: 0.62, green: 0.74, blue: 0.80, opacity: 1)
                : Color(.sRGB, red: 0.42, green: 0.55, blue: 0.62, opacity: 1)
            context.fill(Path(ellipseIn: pool), with: .radialGradient(
                Gradient(colors: [tone.opacity(dark ? 0.10 : 0.08), tone.opacity(0)]),
                center: CGPoint(x: pool.midX, y: pool.midY), startRadius: 0, endRadius: rx))
            for ring in ripples where ring.opacity > 0.001 {
                let w = stage.radius * ring.scale
                let h = w * flat
                let rect = CGRect(x: cx - w, y: cy - h, width: w * 2, height: h * 2)
                // 亮线在上，暗线往下错一点，像水面一道起伏。
                context.stroke(Path(ellipseIn: rect),
                               with: .color(.white.opacity(ring.opacity * (dark ? 0.7 : 1))),
                               lineWidth: 1.4 * stage.scale)
                context.stroke(Path(ellipseIn: rect.offsetBy(dx: 0, dy: 1.6 * stage.scale)),
                               with: .color(tone.opacity(ring.opacity)), lineWidth: 1.2 * stage.scale)
            }
        }
        .frame(width: CGFloat(stage.width), height: CGFloat(stage.height))
        .allowsHitTesting(false)
    }
}

/// 金属唱臂：转轴底座（两层）、配重、细管和唱头，绕转轴转；支架画在唱臂收起时唱管
/// 搭着的地方。唱针在唱头底边中点，正好是 Core 算的落针点。`lift` 越大唱头的影子
/// 离得越远、唱臂稍稍放大，看得出抬起来了。
private struct VinylTonearm: View {
    var stage: MusicVinyl.Stage
    var angle: Double
    var lift: Double
    var dark: Bool

    var body: some View {
        let s = CGFloat(stage.scale)
        let length = CGFloat(stage.armLength)
        let top = 20 * s
        let frameWidth = 30 * s
        let frameHeight = top + length + 4 * s
        let pivot = CGPoint(x: stage.pivot.x, y: stage.pivot.y)
        let base = CGFloat(stage.pivotBase)
        let raise = CGFloat(min(1, max(0, lift)))
        ZStack(alignment: .topLeading) {
            if let art = VinylArt.tonearm {
                photoArm(art, pivot: pivot, length: length, raise: raise, s: s)
            } else {
                drawnArm(pivot: pivot, length: length, base: base, raise: raise, s: s,
                         top: top, frameWidth: frameWidth, frameHeight: frameHeight)
            }
        }
        .frame(width: CGFloat(stage.width), height: CGFloat(stage.height), alignment: .topLeading)
        .allowsHitTesting(false)
    }

    /// 写实唱臂素材：竖着画，转轴在 `VinylArt.armPivot`，唱针尖在 `VinylArt.armTip`；
    /// 按 Core 的唱臂长度缩放，让唱针尖正好落在 `MusicVinyl.stylus` 算的点上。
    @ViewBuilder
    private func photoArm(_ art: NSImage, pivot: CGPoint, length: CGFloat, raise: CGFloat, s: CGFloat) -> some View {
        let height = length / CGFloat(VinylArt.armTip - VinylArt.armPivot.y)
        let width = height * CGFloat(VinylArt.armAspect)
        let anchor = UnitPoint(x: VinylArt.armPivot.x, y: VinylArt.armPivot.y)
        // 支架：唱臂收起时搭在这里。
        Capsule()
            .fill(metal(horizontal: false))
            .frame(width: 11 * s, height: 7 * s)
            .shadow(color: .black.opacity(0.28), radius: 1.5 * s, y: 1 * s)
            .position(x: pivot.x, y: pivot.y + length * 0.68)
        Image(nsImage: art)
            .resizable()
            .interpolation(.high)
            .brightness(dark ? -0.08 : 0)
            .frame(width: width, height: height)
            .scaleEffect(1 + 0.015 * raise, anchor: anchor)
            .shadow(color: .black.opacity(0.32 - 0.1 * raise), radius: (1.5 + 2.5 * raise) * s,
                    x: (1 + 3 * raise) * s, y: (1.5 + 4 * raise) * s)
            .rotationEffect(.degrees(angle), anchor: anchor)
            .position(x: pivot.x + width * (0.5 - anchor.x), y: pivot.y + height * (0.5 - anchor.y))
    }

    /// 没有素材时的代码画法（原样保留）。
    @ViewBuilder
    private func drawnArm(pivot: CGPoint, length: CGFloat, base: CGFloat, raise: CGFloat, s: CGFloat,
                          top: CGFloat, frameWidth: CGFloat, frameHeight: CGFloat) -> some View {
            // 支架：唱臂收起时搭在这里。
            Capsule()
                .fill(metal(horizontal: false))
                .frame(width: 11 * s, height: 7 * s)
                .shadow(color: .black.opacity(0.28), radius: 1.5 * s, y: 1 * s)
                .position(x: pivot.x, y: pivot.y + length * 0.68)
            // 转轴底座：外圈一层深色座，里面一层金属。
            Circle()
                .fill(dark ? Color(white: 0.16) : Color(white: 0.82))
                .overlay(Circle().strokeBorder(.white.opacity(dark ? 0.15 : 0.7), lineWidth: 0.6))
                .frame(width: base * 2.3, height: base * 2.3)
                .shadow(color: .black.opacity(dark ? 0.5 : 0.2), radius: 5 * s, y: 3 * s)
                .position(pivot)
            Circle()
                .fill(metal(horizontal: false))
                .overlay(Circle().strokeBorder(.white.opacity(dark ? 0.2 : 0.65), lineWidth: 0.6))
                .frame(width: base * 1.6, height: base * 1.6)
                .position(pivot)
            arm(s: s, length: length, top: top)
                .frame(width: frameWidth, height: frameHeight)
                .scaleEffect(1 + 0.015 * raise, anchor: UnitPoint(x: 0.5, y: top / frameHeight))
                .shadow(color: .black.opacity(0.32 - 0.1 * raise), radius: (1.5 + 2.5 * raise) * s,
                        x: (1 + 3 * raise) * s, y: (1.5 + 4 * raise) * s)
                .rotationEffect(.degrees(angle), anchor: UnitPoint(x: 0.5, y: top / frameHeight))
                .position(x: pivot.x, y: pivot.y - top + frameHeight / 2)
            // 转轴顶盖。
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.99), Color(white: 0.58)],
                                     center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: base * 0.6))
                .frame(width: base * 0.95, height: base * 0.95)
                .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
                .position(pivot)
    }

    /// 竖着画：配重在转轴上面，细管往下，最下面是唱头，唱针在底边中点。
    private func arm(s: CGFloat, length: CGFloat, top: CGFloat) -> some View {
        VStack(spacing: 0) {
            // 配重：一段带刻线的圆柱。
            RoundedRectangle(cornerRadius: 3 * s, style: .continuous)
                .fill(metal(horizontal: true))
                .overlay(Rectangle().fill(.black.opacity(0.18)).frame(height: 0.8 * s))
                .frame(width: 13 * s, height: 14 * s)
            Spacer().frame(height: top - 14 * s)
            Capsule()
                .fill(metal(horizontal: true))
                .overlay(Capsule().strokeBorder(.white.opacity(dark ? 0.15 : 0.5), lineWidth: 0.4))
                .frame(width: 3.6 * s, height: max(0, length - 20 * s))
            // 唱头：上窄下宽的壳，前端一道指示条，底边中点是唱针。
            ZStack(alignment: .bottom) {
                UnevenRoundedRectangle(topLeadingRadius: 2 * s, bottomLeadingRadius: 3 * s,
                                       bottomTrailingRadius: 3 * s, topTrailingRadius: 2 * s, style: .continuous)
                    .fill(metal(horizontal: true))
                    .frame(width: 11 * s, height: 20 * s)
                Rectangle()
                    .fill(Color(white: dark ? 0.85 : 0.35).opacity(0.6))
                    .frame(width: 7 * s, height: 1 * s)
                    .offset(y: -12 * s)
                Rectangle()
                    .fill(Color(white: 0.18))
                    .frame(width: 2 * s, height: 3 * s)
            }
            .frame(width: 11 * s, height: 20 * s)
            Spacer(minLength: 0)
        }
    }

    private func metal(horizontal: Bool) -> LinearGradient {
        let colors = dark
            ? [Color(white: 0.50), Color(white: 0.92), Color(white: 0.40)]
            : [Color(white: 0.60), Color(white: 0.98), Color(white: 0.55)]
        return horizontal
            ? LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
            : LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
