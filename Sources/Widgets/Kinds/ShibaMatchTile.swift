import AppKit
import SwiftUI

// MARK: - 柴犬翻翻乐 · 扩展栏卡片
//
// 扩展栏卡片只是入口：柴犬（未开始打盹、进行中睁眼、完成举爪）、状态（未开始 / 进行中 3/6 / 完成）
// 和一个「继续游戏」样子的胶囊，不在卡片上玩；点卡片打开 340 宽的面板玩。卡片上没有计时，
// 不高频刷新。规则和存法都在 Core 的 `ShibaMatch`。

struct ShibaMatchTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @Environment(\.colorScheme) private var scheme

    private var game: ShibaMatchGame {
        context.isPreview ? ShibaSamples.game : ShibaMatch.game(instance.config)
    }

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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("柴犬翻翻乐，\(ShibaMatch.statusLine(game))"))
        .accessibilityHint(ShibaMatch.entryTitle(game))
    }

    // MARK: 横排

    private func row(_ game: ShibaMatchGame) -> some View {
        HStack(spacing: 8) {
            ShibaArtImage(name: ShibaMatchArt.tile(game.status))
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                statusRow(game)
                ShibaEntryPill(title: ShibaMatch.entryTitle(game), dark: scheme == .dark)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: 竖排（76 宽）

    private func column(_ game: ShibaMatchGame) -> some View {
        VStack(spacing: 4) {
            ShibaArtImage(name: ShibaMatchArt.tile(game.status))
                .frame(width: 48, height: 48)
            Group {
                if game.status == .playing {
                    progress(game, size: 15)
                } else {
                    Text(ShibaMatch.statusWord(game))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WidgetStyle.primary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.9)
            // 英文这类放不下两个字的语言只画播放图标。
            ViewThatFits(in: .horizontal) {
                ShibaEntryPill(title: ShibaMatch.entryShortTitle(game), dark: scheme == .dark, showsIcon: false)
                ShibaEntryPill(title: nil, dark: scheme == .dark)
            }
        }
    }

    /// 「进行中 3/6」「未开始」「完成 14 步」。
    private func statusRow(_ game: ShibaMatchGame) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(ShibaMatch.statusWord(game))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(game.status == .playing ? WidgetStyle.secondary : WidgetStyle.primary)
            switch game.status {
            case .playing:
                progress(game, size: 15)
            case .won:
                Text(tr("\(game.moves) 步"))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(WidgetStyle.secondary)
                    .monospacedDigit()
            case .ready:
                EmptyView()
            }
        }
        .lineLimit(1)
    }

    /// 「3/6」：已配对几对用柴犬橙。
    private func progress(_ game: ShibaMatchGame, size: CGFloat) -> some View {
        Text(verbatim: ShibaMatch.progressText(game))
            .font(.system(size: size, weight: .bold, design: .rounded))
            .foregroundStyle(ShibaStyle.tileAccent(dark: scheme == .dark))
            .monospacedDigit()
            .contentTransition(.numericText())
            .help(tr("已配对"))
    }
}

/// 卡片上「继续游戏」样子的胶囊：只是提示，不拦点击（点卡片本身打开面板）。柴犬橙实心底，
/// 字用按底色算出的深墨（白字在这个橙上不到 4.5:1）。
struct ShibaEntryPill: View {
    /// nil 时只画播放图标。
    var title: String?
    var dark: Bool
    var showsIcon = true

    var body: some View {
        HStack(spacing: 3) {
            if showsIcon || title == nil {
                Image(systemName: "play.fill")
                    .font(.system(size: title == nil ? 11 : 9, weight: .bold))
            }
            if let title {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(ShibaStyle.accentInk)
        .padding(.horizontal, showsIcon || title == nil ? 9 : 8)
        .frame(height: 22)
        .background(Capsule().fill(ShibaStyle.accentFill))
        .fixedSize()
        .allowsHitTesting(false)
    }
}

// MARK: - 写回

/// 面板和桌面卡片点一下都走这里：取最新存着的那份配置，算完写回，按开关放音效。
/// 没配上时约 0.8 秒后把两张翻回去（和视图在不在都无关，不会卡在翻开的样子）。
@MainActor
enum ShibaPlay {
    static func flip(_ index: Int, in instance: WidgetInstance) {
        var widget = WidgetWriter.current(instance.id) ?? instance
        let outcome = ShibaMatch.apply(flip: index, to: &widget.config, now: Date().timeIntervalSince1970)
        guard outcome.result != .ignored else { return }
        WidgetWriter.update(widget)
        if ShibaMatch.soundOn(widget.config), let sound = outcome.sound {
            ShibaSoundPlayer.play(sound)
        }
        if outcome.needsSettle {
            let id = instance.id
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(ShibaMatchGame.mismatchDelay))
                settle(id)
            }
        }
    }

    /// 把等够了的两张翻回去；这期间重开了或已经翻回去了就什么都不做。
    static func settle(_ id: UUID) {
        guard var widget = WidgetWriter.current(id) else { return }
        // 多给 0.05 秒，免得睡醒时差一点点没到 0.8 秒。
        guard ShibaMatch.settle(in: &widget.config, now: Date().timeIntervalSince1970 + 0.05) else { return }
        WidgetWriter.update(widget)
    }

    static func restart(in instance: WidgetInstance) {
        var widget = WidgetWriter.current(instance.id) ?? instance
        ShibaMatch.restart(in: &widget.config)
        WidgetWriter.update(widget)
    }

    static func toggleSound(in instance: WidgetInstance) {
        var widget = WidgetWriter.current(instance.id) ?? instance
        ShibaMatch.setSound(!ShibaMatch.soundOn(widget.config), in: &widget.config)
        WidgetWriter.update(widget)
    }
}

/// 系统自带的三个轻音效（Tink、Pop、Glass），各做一次 NSSound 缓存着。
@MainActor
enum ShibaSoundPlayer {
    private static var cache: [ShibaSound: NSSound] = [:]

    static func play(_ sound: ShibaSound) {
        let player: NSSound
        if let cached = cache[sound] {
            player = cached
        } else {
            guard let made = NSSound(named: NSSound.Name(sound.systemName))?.copy() as? NSSound else { return }
            cache[sound] = made
            player = made
        }
        if player.isPlaying { player.stop() }
        player.volume = 0.6
        player.play()
    }
}

// MARK: - 颜色

/// 只有翻开的牌面有多色；牌背是磨砂玻璃加一个淡爪印，不用大面积蓝色或发光。
enum ShibaStyle {
    /// 实心胶囊底（入口、再来一盘）。
    static var accentFill: Color { Color(hex: ShibaMatch.accentHex) }
    /// 实心胶囊上的字：按底色算出的深墨。
    static var accentInk: Color { Color(hex: PaperInk.ink(on: ShibaMatch.accentHex)) }

    /// 柴犬橙的字：浅色玻璃上压深，深色玻璃上提亮（Core 的 ShibaMatch.accent*）。
    static var accentText: Color {
        Color.panelDynamic(dark: NSColor(Color(hex: ShibaMatch.accentDarkHex)),
                           light: NSColor(Color(hex: ShibaMatch.accentLightHex)))
    }

    /// 扩展栏卡片按卡片自己的外观取。
    static func tileAccent(dark: Bool) -> Color {
        Color(hex: dark ? ShibaMatch.accentDarkHex : ShibaMatch.accentLightHex)
    }

    /// 牌面暖色浅底（浅色、深色玻璃上都是浅的，像一张真的牌；深色下稍暗一点不刺眼）。
    static var faceFill: Color {
        Color.panelDynamic(dark: NSColor(Color(hex: "#EEDCC2")), light: NSColor(Color(hex: "#FFF6E8")))
    }
    static var faceEdge: Color { Color(hex: "#E8C99B") }
    /// 这一轮第一张翻开时的描边（暖金）。
    static var selectedEdge: Color { Color(hex: "#F2B544") }
    /// 没配上的两张：淡红描边。
    static var wrongEdge: Color { Color(hex: "#E5484D") }
    /// 配上的：淡绿描边。
    static var matchedEdge: Color { Color(hex: "#6DBE45") }

    /// 牌背上的爪印。
    static var backPaw: Color { Color.panelPrimary.opacity(0.16) }
    static var backPawHover: Color { Color.panelPrimary.opacity(0.28) }

    /// 键盘焦点框。
    static var focusRing: Color { Color(hex: "#F2B544") }

    static var winText: Color { Color(hex: "#3FAE5A").panelReadable }
}

// MARK: - 素材

/// 按名字从 Bundle 读图（带 @2x），读过的缓存，缺的记下来不再找。
@MainActor
enum ShibaImages {
    private static var cache: [String: NSImage] = [:]
    private static var missing: Set<String> = []

    static func image(_ name: String) -> NSImage? {
        if let cached = cache[name] { return cached }
        guard !missing.contains(name) else { return nil }
        guard let image = Bundle.main.image(forResource: name) else {
            missing.insert(name)
            return nil
        }
        cache[name] = image
        return image
    }
}

/// 一张柴犬母版图，按比例放进框里；缺图时画一个柴犬橙的 dog.fill，保证不空。
struct ShibaArtImage: View {
    var name: String
    var alignment: Alignment = .center

    var body: some View {
        Group {
            if let image = ShibaImages.image(name) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Image(systemName: "dog.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color(hex: ShibaMatch.accentHex))
                    .padding(4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        .accessibilityHidden(true)
    }
}

/// 牌面图案：先用作者画的 match-<图案>.png；柴犬脸缺图时用仓库的柴犬母版小头；
/// 其余缺图时用系统彩色 emoji。
struct ShibaFaceArt: View {
    var face: ShibaFace
    var side: CGFloat

    var body: some View {
        if let image = ShibaImages.image(face.imageName)
            ?? (face == .shiba ? ShibaImages.image(ShibaMatch.faceFallbackImage) : nil) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: side, height: side)
        } else {
            Text(verbatim: face.emoji)
                .font(.system(size: side * 0.82))
                .frame(width: side, height: side)
        }
    }
}

// MARK: - 一张牌

/// 一张牌：背面磨砂玻璃上一个淡爪印（pawprint.fill），正面暖色浅底加图案。翻牌是绕竖轴的 3D 翻转，
/// 转到一半换面；「减少动态效果」时只淡入淡出。配上时轻轻弹一下。点击由棋盘统一处理。
struct ShibaCardView: View {
    var face: ShibaFace
    var state: ShibaMatchGame.CardState
    var width: CGFloat
    var height: CGFloat
    var hovered = false
    var focused = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pop = false

    private var showing: Bool { state != .hidden }
    private var corner: CGFloat { min(width, height) * 0.2 }
    private static let flipDuration = 0.34

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        ZStack {
            front(shape)
                .opacity(showing ? 1 : 0)
                .animation(swap, value: showing)
                .rotation3DEffect(.degrees(reduceMotion ? 0 : (showing ? 0 : -180)),
                                  axis: (x: 0, y: 1, z: 0), perspective: 0.45)
            back(shape)
                .opacity(showing ? 0 : 1)
                .animation(swap, value: showing)
                .rotation3DEffect(.degrees(reduceMotion ? 0 : (showing ? 180 : 0)),
                                  axis: (x: 0, y: 1, z: 0), perspective: 0.45)
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: Self.flipDuration), value: showing)
        .scaleEffect(pop ? 1.07 : 1)
        .overlay {
            if focused {
                shape.inset(by: -3).strokeBorder(ShibaStyle.focusRing, lineWidth: 2)
            }
        }
        .frame(width: width, height: height)
        .onChange(of: state == .matched) { _, matched in
            guard matched, !reduceMotion else { return }
            Task { @MainActor in
                // 等翻面转完再弹。
                try? await Task.sleep(for: .seconds(Self.flipDuration * 0.6))
                withAnimation(.spring(response: 0.22, dampingFraction: 0.45)) { pop = true }
                try? await Task.sleep(for: .seconds(0.16))
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { pop = false }
            }
        }
    }

    /// 转到一半时换面：翻转期间先藏着，过半一下子显出来。
    private var swap: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .linear(duration: 0.01).delay(Self.flipDuration / 2)
    }

    private func front(_ shape: RoundedRectangle) -> some View {
        ZStack {
            shape.fill(ShibaStyle.faceFill)
            ShibaFaceArt(face: face, side: min(width, height) * 0.62)
        }
        .overlay(shape.strokeBorder(frontEdge, lineWidth: state == .faceUp || state == .wrong ? 2 : 1))
        .opacity(state == .matched ? 0.92 : 1)
    }

    private var frontEdge: Color {
        switch state {
        case .faceUp: ShibaStyle.selectedEdge
        case .wrong: ShibaStyle.wrongEdge
        case .matched: ShibaStyle.matchedEdge.opacity(0.7)
        case .hidden: ShibaStyle.faceEdge
        }
    }

    private func back(_ shape: RoundedRectangle) -> some View {
        ZStack {
            Color.clear.readableGlass(in: shape)
            Image(systemName: "pawprint.fill")
                .font(.system(size: min(width, height) * 0.34, weight: .semibold))
                .foregroundStyle(hovered ? ShibaStyle.backPawHover : ShibaStyle.backPaw)
        }
        .overlay(shape.strokeBorder(Color.panelStroke, lineWidth: 0.5))
        .overlay(shape.fill(Color.panelPrimary.opacity(hovered ? 0.05 : 0)))
    }
}

// MARK: - 一块棋盘

/// 一整块牌桌：按 `ShibaBoardLayout` 排。点击交给一层透明的 AppKit 视图（面板、桌面卡片没在前台时
/// 第一下也算数），按 `ShibaBoardLayout.hitIndex` 认是哪张。读屏下每张牌是一个按钮（能按）。
/// `keyboard` 打开时（面板）牌桌能拿键盘焦点：方向键移动焦点框、空格或回车翻牌。
struct ShibaBoardView: View {
    var game: ShibaMatchGame
    var layout: ShibaBoardLayout
    var interactive = true
    var keyboard = false
    var onFlip: (Int) -> Void = { _ in }

    @State private var hovered: Int?
    @State private var cursor = 0
    @FocusState private var focused: Bool

    var body: some View {
        let columns = layout.spec.columns
        VStack(spacing: CGFloat(layout.gap)) {
            ForEach(0..<layout.spec.rows, id: \.self) { row in
                HStack(spacing: CGFloat(layout.gap)) {
                    ForEach(0..<columns, id: \.self) { column in
                        card(row * columns + column)
                    }
                }
            }
        }
        .frame(width: CGFloat(layout.width), height: CGFloat(layout.height))
        .overlay {
            if interactive {
                ShibaClickCatcher { point in
                    guard let index = layout.hitIndex(x: Double(point.x), y: Double(point.y)) else { return }
                    cursor = index
                    onFlip(index)
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point): hovered = layout.hitIndex(x: Double(point.x), y: Double(point.y))
                    case .ended: hovered = nil
                    }
                }
                .accessibilityHidden(true)
            }
        }
        .focusable(keyboard && interactive)
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .space, .return]) { press in
            guard keyboard, interactive else { return .ignored }
            switch press.key {
            case .upArrow: cursor = layout.move(cursor, row: -1, column: 0)
            case .downArrow: cursor = layout.move(cursor, row: 1, column: 0)
            case .leftArrow: cursor = layout.move(cursor, row: 0, column: -1)
            case .rightArrow: cursor = layout.move(cursor, row: 0, column: 1)
            default: onFlip(cursor)
            }
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tr("牌桌，\(layout.spec.rows) 行 \(layout.spec.columns) 列"))
    }

    private func card(_ index: Int) -> some View {
        let state = game.state(index)
        return ShibaCardView(face: game.face(index) ?? .paw, state: state,
                             width: CGFloat(layout.cardWidth), height: CGFloat(layout.cardHeight),
                             hovered: interactive && state == .hidden && hovered == index,
                             focused: keyboard && focused && cursor == index)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ShibaMatch.cardLabel(game, index: index))
            .accessibilityAddTraits(state == .hidden && interactive ? .isButton : [])
            .accessibilityAction {
                guard interactive else { return }
                cursor = index
                onFlip(index)
            }
    }
}

/// 透明的点击层：报告点在哪（左上为原点）。
struct ShibaClickCatcher: NSViewRepresentable {
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

// MARK: - 预览用的一盘

/// 小组件库预览：已配对 3/6、翻着一张，用时 00:28。
enum ShibaSamples {
    static let now: Double = 1_000_028

    static var game: ShibaMatchGame {
        let deck: [ShibaFace] = [.shiba, .paw, .bone, .paw,
                                 .house, .ball, .house, .bowl,
                                 .ball, .shiba, .bone, .bowl]
        guard var game = ShibaMatchGame.fixed(cards: deck) else { return ShibaMatchGame() }
        let base = now - 28
        game.flip(0, now: base)
        game.flip(9, now: base + 2)
        game.flip(1, now: base + 5)
        game.flip(2, now: base + 6)
        game.settle(now: base + 8)
        game.flip(4, now: base + 10)
        game.flip(6, now: base + 12)
        game.flip(5, now: base + 15)
        game.flip(8, now: base + 17)
        game.flip(10, now: base + 20)
        return game
    }
}
