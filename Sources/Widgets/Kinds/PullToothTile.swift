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

/// 牙和小熊猫是固定的角色配色（浅色、深色玻璃上都一样），不铺背景、不发光；只有大数字用强调色。
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
    /// 拔掉的牙在牙床上留下的坑。
    static let pit = Color(hex: "#B83A55").opacity(0.55)

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

// MARK: - 小熊猫

/// 张着大嘴的小熊猫「圆圆」：身子是用户画的素材（tooth-panda-*.png，正方形），嘴里的牙用代码画，
/// 按 `ToothLayout` 的比例摆；`.mouth` 只画嘴附近那一块。能点时上面盖一层透明的 AppKit 点击层
/// （面板、桌面卡片没在前台时第一下也算数），按 `ToothLayout.hitIndex` 认是哪颗牙。
/// 平时张嘴；鼠标停在一颗牙上时闭眼忍着；拔到疼牙换成合嘴含泪那张再抖两下；赢了换成欢呼那张。
/// 「减少动态效果」打开时直接换图，不抖、不飞。
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

    private var artName: String {
        switch game.status {
        case .bitten: "tooth-panda-bite"
        case .won: "tooth-panda-cheer"
        case .ready, .playing:
            hovered != nil && interactive ? "tooth-panda-open-2" : "tooth-panda-open-1"
        }
    }

    var body: some View {
        let amplitude = W * 0.025
        ZStack(alignment: .topLeading) {
            art
            if game.status == .ready || game.status == .playing {
                ForEach(0..<PullTooth.toothCount, id: \.self) { index in
                    toothSlot(index, upper: index < PullTooth.perRow)
                }
            }
            if showsOuch && closed { ouchBubble }
        }
        .frame(width: W, height: CGFloat(layout.height), alignment: .topLeading)
        .clipped()
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
                        let index = layout.hitIndex(x: Double(point.x), y: Double(point.y))
                        hovered = index.flatMap { game.isInMouth($0) ? $0 : nil }
                    case .ended:
                        hovered = nil
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("小熊猫圆圆，\(PullTooth.statusLine(game))"))
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

    /// 整张素材按 `layout.artSide` 画，`.mouth` 时往左上挪，框外的裁掉。
    @ViewBuilder private var art: some View {
        let side = CGFloat(layout.artSide)
        let origin = layout.artOrigin
        if let image = ToothArtImages.image(artName) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: side, height: side)
                .offset(x: CGFloat(origin.x), y: CGFloat(origin.y))
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
                                       removal: AnyTransition.offset(y: upper ? CGFloat(layout.closeTravel)
                                                                              : -CGFloat(layout.closeTravel))
                                           .combined(with: .opacity)
                                           .combined(with: .scale(scale: 1.25)))
        ZStack(alignment: .topLeading) {
            // 拔掉的地方在牙床上留一个小坑。
            if !game.isInMouth(index) {
                Ellipse()
                    .fill(ToothStyle.pit)
                    .frame(width: CGFloat(box.width) * 0.6, height: max(2, u(0.018)))
                    .offset(x: CGFloat(box.x + box.width * 0.2),
                            y: upper ? CGFloat(box.y) + u(0.004) : CGFloat(box.maxY) - u(0.022))
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
                    .shadow(color: .black.opacity(0.12), radius: max(0.5, u(0.006)), y: upper ? 1 : -1)
                    .frame(width: CGFloat(box.width), height: CGFloat(box.height))
                    .offset(x: CGFloat(box.x),
                            y: CGFloat(box.y) + (lifted ? (upper ? u(0.01) : -u(0.01)) : 0))
                    .transition(pullTransition)
            }
        }
    }

    private var line: CGFloat { max(0.5, u(0.005)) }

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

/// 拔牙小熊猫的四张素材，读一次存着。
@MainActor
enum ToothArtImages {
    private static var cache: [String: NSImage] = [:]

    static func image(_ name: String) -> NSImage? {
        if let hit = cache[name] { return hit }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        cache[name] = image
        return image
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
