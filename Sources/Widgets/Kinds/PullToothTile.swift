import AppKit
import SwiftUI

// MARK: - 拔牙 · 扩展栏卡片
//
// 扩展栏卡片只有 58pt 高，12 颗牙放进去每颗不到 7pt，点不准，所以卡片上是河马缩略图、
// 这局已拔几颗、最高连拔和重开键，点卡片打开面板玩；能直接点着玩的是面板和桌面卡片
// （小 / 中 / 大三档，见 DesktopCardsGamesTooth）。规则和存法都在 Core 的 `PullTooth`。

struct PullToothTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @Environment(\.colorScheme) private var scheme

    private var game: ToothGame {
        context.isPreview ? ToothSamples.game : PullTooth.game(instance.config)
    }

    private var best: Int { context.isPreview ? 7 : PullTooth.best(instance.config) }

    var body: some View {
        let game = game
        return WidgetSurface {
            Group {
                if context.position.isVertical {
                    column(game)
                } else {
                    row(game)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tr("拔牙，\(PullTooth.statusLine(game))"))
    }

    // MARK: 横排

    private func row(_ game: ToothGame) -> some View {
        HStack(spacing: 8) {
            HippoArt(game: game, layout: ToothLayout(width: 52), interactive: false)
            VStack(alignment: .leading, spacing: 1) {
                pulledCount(game, size: 20)
                bestReadout(size: 13)
            }
            Spacer(minLength: 0)
            ToothRoundButton(symbol: "arrow.counterclockwise", diameter: 28, help: tr("重开一局")) { restart() }
                .disabled(context.isPreview)
        }
    }

    // MARK: 竖排（76 宽）

    private func column(_ game: ToothGame) -> some View {
        VStack(spacing: 4) {
            HippoArt(game: game, layout: ToothLayout(width: 60), interactive: false)
            pulledCount(game, size: 17)
            bestReadout(size: 13)
        }
    }

    /// 「5 / 11」：已拔几颗用强调色。
    private func pulledCount(_ game: ToothGame, size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(verbatim: "\(game.pulledCount)")
                .font(.system(size: size, weight: .bold, design: .rounded))
                .foregroundStyle(ToothStyle.tileAccent(dark: scheme == .dark))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(verbatim: "/\(game.maxPulls)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(WidgetStyle.secondary)
                .monospacedDigit()
        }
        .lineLimit(1)
        .help(tr("这局已拔"))
    }

    /// 奖杯加最高连拔。
    private func bestReadout(size: CGFloat) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "trophy.fill")
                .font(.system(size: size - 2, weight: .semibold))
                .foregroundStyle(WidgetStyle.secondary)
            Text(verbatim: "\(best)")
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .foregroundStyle(WidgetStyle.primary)
                .monospacedDigit()
        }
        .lineLimit(1)
        .help(tr("最高连拔"))
    }

    private func restart() {
        guard !context.isPreview else { return }
        ToothPlay.restart(in: instance)
    }
}

// MARK: - 写回

/// 卡片、面板和桌面卡片点一下都走这里：取最新存着的那份配置，算完写回，按开关放音效。
@MainActor
enum ToothPlay {
    @discardableResult
    static func pull(_ index: Int, in instance: WidgetInstance) -> PullTooth.Outcome {
        var widget = WidgetWriter.current(instance.id) ?? instance
        let outcome = PullTooth.apply(pull: index, to: &widget.config, now: Date().timeIntervalSince1970)
        guard outcome.result != .ignored else { return outcome }
        WidgetWriter.update(widget)
        if PullTooth.soundOn(widget.config), let sound = outcome.sound {
            ToothSoundPlayer.play(sound)
        }
        return outcome
    }

    static func restart(in instance: WidgetInstance) {
        var widget = WidgetWriter.current(instance.id) ?? instance
        PullTooth.restart(in: &widget.config)
        WidgetWriter.update(widget)
    }

    static func toggleSound(in instance: WidgetInstance) {
        var widget = WidgetWriter.current(instance.id) ?? instance
        PullTooth.setSound(!PullTooth.soundOn(widget.config), in: &widget.config)
        WidgetWriter.update(widget)
    }
}

/// 三个合成音效，各做一次 NSSound 缓存着。
@MainActor
enum ToothSoundPlayer {
    private static var cache: [ToothSound: NSSound] = [:]

    static func play(_ sound: ToothSound) {
        let player: NSSound
        if let cached = cache[sound] {
            player = cached
        } else {
            guard let made = NSSound(data: ToothSoundSynth.wav(sound)) else { return }
            cache[sound] = made
            player = made
        }
        if player.isPlaying { player.stop() }
        player.volume = 0.7
        player.play()
    }
}

// MARK: - 颜色

/// 河马是固定的角色配色（浅色、深色玻璃上都一样），不铺背景、不发光；只有大数字用强调色。
enum ToothStyle {
    static let body = Color(hex: "#B9A8E6")
    static let bodyShade = Color(hex: "#A592DA")
    static let edge = Color(hex: "#8471C4")
    static let earInner = Color(hex: "#F2A6BE")
    static let mouth = Color(hex: "#7A2A4C")
    static let tongue = Color(hex: "#EE7F9C")
    static let gum = Color(hex: "#F4A0B6")
    static let tooth = Color(hex: "#FFFFFF")
    static let toothHover = Color(hex: "#FFF3D6")
    static let toothEdge = Color(hex: "#CFC4E3")
    static let sore = Color(hex: "#FFD5DC")
    static let eye = Color(hex: "#2A2340")
    static let nostril = Color(hex: "#8A76C8")
    static let cheek = Color(hex: "#F58FB0")
    static let ouch = Color(hex: "#E5484D")

    /// 大数字：浅色玻璃上压深到 4.5:1 以上，深色玻璃上提亮（Core 的 PullTooth.accent*）。
    static var accent: Color {
        Color.panelDynamic(dark: NSColor(Color(hex: PullTooth.accentDarkHex)),
                           light: NSColor(Color(hex: PullTooth.accentLightHex)))
    }

    /// 扩展栏卡片按卡片自己的外观取。
    static func tileAccent(dark: Bool) -> Color {
        Color(hex: dark ? PullTooth.accentDarkHex : PullTooth.accentLightHex)
    }

    static var winText: Color { Color(hex: "#3FAE5A").panelReadable }
    static var ouchText: Color { Color(hex: "#E5484D").panelReadable }
}

// MARK: - 河马

/// 张着大嘴的小河马「圆圆」，全用代码画，按 `ToothLayout` 的比例摆。能点时上面盖一层透明的
/// AppKit 点击层（面板、桌面卡片没在前台时第一下也算数），按 `ToothLayout.hitIndex` 认是哪颗牙。
/// 拔到疼牙时上半边往下合嘴再抖两下；「减少动态效果」打开时直接换成合嘴，不抖、不飞。
struct HippoArt: View {
    var game: ToothGame
    var layout: ToothLayout
    var interactive = false
    var onPull: (Int) -> Void = { _ in }
    /// 拔到疼牙时头顶冒「啊呜！」（太小的卡片不冒）。
    var showsOuch = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered: Int?

    private var closed: Bool { game.status == .bitten }
    private var W: CGFloat { CGFloat(layout.width) }
    private func u(_ fraction: Double) -> CGFloat { CGFloat(layout.value(fraction)) }

    var body: some View {
        let drop = closed ? CGFloat(layout.closeTravel) : 0
        let amplitude = W * 0.025
        ZStack(alignment: .topLeading) {
            lowerJaw
            mouth(drop: drop)
            lowerTeeth
            upperHalf
                .offset(y: drop)
            if showsOuch && closed { ouchBubble }
        }
        .frame(width: W, height: CGFloat(layout.height), alignment: .topLeading)
        .animation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.62), value: closed)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: game.pulled)
        .keyframeAnimator(initialValue: 0.0, trigger: shakeTrigger) { view, x in
            view.offset(x: CGFloat(x) * amplitude)
        } keyframes: { _ in
            KeyframeTrack {
                LinearKeyframe(0.0, duration: 0.14)
                LinearKeyframe(-1.0, duration: 0.05)
                LinearKeyframe(1.0, duration: 0.07)
                LinearKeyframe(-0.7, duration: 0.07)
                LinearKeyframe(0.4, duration: 0.06)
                LinearKeyframe(0.0, duration: 0.05)
            }
        }
        .overlay(alignment: .topLeading) {
            if interactive && !game.isOver {
                ToothClickCatcher { point in
                    if let index = layout.hitIndex(x: Double(point.x), y: Double(point.y)),
                       game.isInMouth(index) {
                        onPull(index)
                    }
                }
                .frame(width: W, height: CGFloat(layout.height))
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        hovered = layout.hitIndex(x: Double(point.x), y: Double(point.y))
                    case .ended:
                        hovered = nil
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("河马圆圆，\(PullTooth.statusLine(game))"))
        .accessibilityValue(tr("这局已拔 \(game.pulledCount) 颗"))
        .accessibilityAction(named: Text(tr("拔一颗牙"))) {
            guard interactive, !game.isOver,
                  let index = (0..<game.count).first(where: { game.isInMouth($0) }) else { return }
            onPull(index)
        }
    }

    /// 合嘴后抖两下：keyframe 走 -1...1，乘宽的 2.5%。每次合嘴（结束时间不同）抖一次。
    private var shakeTrigger: Double {
        guard !reduceMotion, closed else { return 0 }
        return game.endedAt ?? 1
    }

    // MARK: 下巴和嘴里

    private var lowerJaw: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: u(0.15), style: .continuous)
                .fill(ToothStyle.body)
                .overlay {
                    RoundedRectangle(cornerRadius: u(0.15), style: .continuous)
                        .strokeBorder(ToothStyle.edge, lineWidth: line)
                }
                .frame(width: u(0.84), height: u(0.32))
                .offset(x: u(0.08), y: u(0.50))
            // 腮红。
            ForEach([0.09, 0.79], id: \.self) { x in
                Ellipse()
                    .fill(ToothStyle.cheek.opacity(0.55))
                    .frame(width: u(0.12), height: u(0.045))
                    .offset(x: u(x), y: u(0.765))
            }
        }
    }

    private func mouth(drop: CGFloat) -> some View {
        let top = u(0.38) + drop
        let bottom = u(0.765)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: u(0.1), style: .continuous)
                .fill(ToothStyle.mouth)
                .frame(width: u(0.70), height: max(u(0.04), bottom - top))
                .offset(x: u(0.15), y: top)
            Ellipse()
                .fill(ToothStyle.tongue)
                .frame(width: u(0.40), height: u(0.10))
                .offset(x: u(0.30), y: u(0.64))
                .opacity(closed ? 0 : 1)
            // 下牙床。
            Capsule()
                .fill(ToothStyle.gum)
                .frame(width: u(0.64), height: u(0.06))
                .offset(x: u(0.18), y: u(0.685))
        }
    }

    private var lowerTeeth: some View {
        ZStack(alignment: .topLeading) {
            ForEach(PullTooth.perRow..<PullTooth.toothCount, id: \.self) { index in
                toothSlot(index, upper: false)
            }
        }
    }

    // MARK: 上半边（合嘴时一起往下）

    private var upperHalf: some View {
        ZStack(alignment: .topLeading) {
            // 耳朵。
            ForEach([0.17, 0.70], id: \.self) { x in
                Ellipse()
                    .fill(ToothStyle.body)
                    .overlay { Ellipse().strokeBorder(ToothStyle.edge, lineWidth: line) }
                    .overlay {
                        Ellipse().fill(ToothStyle.earInner)
                            .frame(width: u(0.07), height: u(0.055))
                    }
                    .frame(width: u(0.13), height: u(0.11))
                    .offset(x: u(x), y: u(0.02))
            }
            // 头：上牙床和鼻子。
            RoundedRectangle(cornerRadius: u(0.17), style: .continuous)
                .fill(ToothStyle.body)
                .overlay {
                    RoundedRectangle(cornerRadius: u(0.17), style: .continuous)
                        .strokeBorder(ToothStyle.edge, lineWidth: line)
                }
                .frame(width: u(0.92), height: u(0.34))
                .offset(x: u(0.04), y: u(0.08))
            // 头顶两个眼包。
            ForEach([0.255, 0.575], id: \.self) { x in
                Circle()
                    .fill(ToothStyle.body)
                    .overlay {
                        Circle().trim(from: 0.5, to: 1).stroke(ToothStyle.edge, lineWidth: line)
                    }
                    .frame(width: u(0.17), height: u(0.17))
                    .offset(x: u(x), y: u(0.035))
            }
            eyes
            // 鼻孔。
            ForEach([0.365, 0.565], id: \.self) { x in
                Ellipse()
                    .fill(ToothStyle.nostril)
                    .frame(width: u(0.07), height: u(0.045))
                    .offset(x: u(x), y: u(0.24))
            }
            // 上牙床。
            Capsule()
                .fill(ToothStyle.gum)
                .frame(width: u(0.66), height: u(0.06))
                .offset(x: u(0.17), y: u(0.385))
            ForEach(0..<PullTooth.perRow, id: \.self) { index in
                toothSlot(index, upper: true)
            }
        }
    }

    @ViewBuilder private var eyes: some View {
        let size = u(0.075)
        ForEach([0.34, 0.66], id: \.self) { cx in
            Group {
                switch game.status {
                case .bitten:
                    // 用力合嘴：眯成「> <」。
                    SquintEye(left: cx < 0.5)
                        .stroke(ToothStyle.eye, style: StrokeStyle(lineWidth: max(1.2, u(0.016)), lineCap: .round,
                                                                   lineJoin: .round))
                case .won:
                    // 笑眯眯：弯弯的眼。
                    HappyEye()
                        .stroke(ToothStyle.eye, style: StrokeStyle(lineWidth: max(1.2, u(0.016)), lineCap: .round))
                case .ready, .playing:
                    Circle().fill(ToothStyle.eye)
                        .overlay(alignment: .topTrailing) {
                            Circle().fill(Color.white)
                                .frame(width: size * 0.36, height: size * 0.36)
                                .offset(x: -size * 0.12, y: size * 0.12)
                        }
                }
            }
            .frame(width: size, height: size)
            .offset(x: u(cx) - size / 2, y: u(0.12) - size / 2)
        }
    }

    // MARK: 牙

    @ViewBuilder private func toothSlot(_ index: Int, upper: Bool) -> some View {
        let box = layout.tooth(index)
        let isSore = game.revealedSore == index
        let lifted = hovered == index && interactive && !game.isOver
        let pullTransition: AnyTransition = reduceMotion
            ? AnyTransition.opacity
            : AnyTransition.asymmetric(insertion: AnyTransition.scale(scale: 0.6).combined(with: .opacity),
                                       removal: AnyTransition.offset(y: upper ? u(0.08) : -u(0.08))
                                           .combined(with: .opacity)
                                           .combined(with: .scale(scale: 1.25)))
        ZStack(alignment: .topLeading) {
            // 拔掉的地方留一个小坑。
            if !game.isInMouth(index) {
                Ellipse()
                    .fill(ToothStyle.mouth.opacity(0.55))
                    .frame(width: CGFloat(box.width) * 0.6, height: u(0.022))
                    .offset(x: CGFloat(box.x + box.width * 0.2),
                            y: upper ? u(0.41) : u(0.69))
            }
            if game.isInMouth(index) {
                ToothShape(upper: upper)
                    .fill(isSore ? ToothStyle.sore : (lifted ? ToothStyle.toothHover : ToothStyle.tooth))
                    .overlay { ToothShape(upper: upper).stroke(ToothStyle.toothEdge, lineWidth: line) }
                    .overlay {
                        if isSore {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: max(6, CGFloat(box.width) * 0.55), weight: .bold))
                                .foregroundStyle(ToothStyle.ouch)
                        }
                    }
                    .frame(width: CGFloat(box.width), height: CGFloat(box.height))
                    .offset(x: CGFloat(box.x),
                            y: CGFloat(box.y) + (lifted ? (upper ? u(0.012) : -u(0.012)) : 0))
                    .transition(pullTransition)
            }
        }
    }

    private var line: CGFloat { max(0.5, u(0.006)) }

    // MARK: 啊呜

    private var ouchBubble: some View {
        Text(tr("啊呜！"))
            .font(.system(size: max(13, u(0.06)), weight: .heavy, design: .rounded))
            .foregroundStyle(ToothStyle.ouchText)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.panelRaised).panelLift())
            .overlay(Capsule().strokeBorder(Color.panelStroke, lineWidth: 0.5))
            .fixedSize()
            .frame(width: W, alignment: .topTrailing)
            .transition(reduceMotion
                        ? AnyTransition.opacity
                        : AnyTransition.scale(scale: 0.5, anchor: .bottomLeading).combined(with: .opacity))
    }
}

/// 一颗牙：上牙根部方、牙尖圆（朝下），下牙反过来。
struct ToothShape: Shape {
    var upper: Bool

    func path(in rect: CGRect) -> Path {
        let root = min(rect.width, rect.height) * 0.18
        let tip = min(rect.width, rect.height) * 0.48
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: upper ? root : tip,
            bottomLeadingRadius: upper ? tip : root,
            bottomTrailingRadius: upper ? tip : root,
            topTrailingRadius: upper ? root : tip,
            style: .continuous)
        return shape.path(in: rect)
    }
}

/// 眯着的眼：左眼「>」、右眼「<」。
struct SquintEye: Shape {
    var left: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let near = left ? rect.minX : rect.maxX
        let far = left ? rect.maxX : rect.minX
        path.move(to: CGPoint(x: near, y: rect.minY + rect.height * 0.1))
        path.addLine(to: CGPoint(x: far, y: rect.midY))
        path.addLine(to: CGPoint(x: near, y: rect.maxY - rect.height * 0.1))
        return path
    }
}

/// 笑着的眼：一道往上弯的弧。
struct HappyEye: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.2))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY + rect.height * 0.2),
                          control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.3))
        return path
    }
}

/// 透明的点击层：只认左键，报告点在哪（左上为原点）。
struct ToothClickCatcher: NSViewRepresentable {
    var onClick: (CGPoint) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onClick = onClick
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onClick = onClick
    }

    final class CatcherView: NSView {
        var onClick: (CGPoint) -> Void = { _ in }

        override var isFlipped: Bool { true }
        // 桌面卡片、面板没在前台时第一下也要算数。
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            onClick(convert(event.locationInWindow, from: nil))
        }
    }
}

// MARK: - 小部件

/// 圆形玻璃按钮（重开、音效开关）。
struct ToothRoundButton: View {
    var symbol: String
    var diameter: CGFloat = 28
    var help: String
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: diameter * 0.44, weight: .bold))
                .foregroundStyle(Color.panelPrimary)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(hovering ? Color.panelSelected : Color.panelRaised).panelLift())
                .overlay(Circle().strokeBorder(Color.panelStroke, lineWidth: 0.5))
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// 小组件库和截图里的示例：固定种子的一局，拔了 4 颗还在拔。
enum ToothSamples {
    static let game: ToothGame = {
        var game = ToothGame.fixed(sore: 9, startedAt: 1_000_000)
        for index in [0, 3, 7, 10] { game.pull(index, now: 1_000_010) }
        return game
    }()
}
