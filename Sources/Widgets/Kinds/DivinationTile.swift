import AppKit
import SwiftUI

// MARK: - 卜卦 · 扩展栏卡片
//
// 扩展栏卡片 188×62（竖排 76×120）：小熊猫、今日签级和签号；没抽时写「今天还没抽签」。
// 点卡片打开面板（每日一签 / 起卦 / 解忧书三页）。规则和存法都在 Core 的 `Divination`。
// 这里还放三个界面共用的部件：小熊猫和它的爪子、签筒、古龟甲、铜钱、卦画、解忧书，全部原创、代码画
// （小熊猫用 Resources/Pet 里码头自己的小熊猫图），以及写回配置和放音效的 DivinationPlay。

struct DivinationTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @Environment(\.colorScheme) private var scheme

    private var todayIndex: Int? {
        context.isPreview ? 36 : Divination.todayStick(instance.config, now: context.now)
    }

    var body: some View {
        let index = todayIndex
        return WidgetSurface {
            Group {
                if context.position.isVertical {
                    column(index)
                } else {
                    row(index)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibility(index))
    }

    private func accessibility(_ index: Int?) -> String {
        guard let index else { return tr("卜卦，今天还没抽签") }
        let stick = FortuneStick.all[index]
        return tr("卜卦，今日\(stick.level.title)，\(Divination.stickNumber(index))")
    }

    private func levelColor(_ level: StickLevel) -> Color {
        if level.isFestive { return Color(hex: scheme == .dark ? Divination.redDarkHex : Divination.redLightHex) }
        if level == .good {
            return Color(hex: scheme == .dark ? Divination.goldTextDarkHex : Divination.goldTextLightHex)
        }
        return WidgetStyle.primary
    }

    // MARK: 横排

    private func row(_ index: Int?) -> some View {
        HStack(spacing: 8) {
            DivinationPanda(name: index == nil ? "pet-panda-idle" : "pet-panda-cheer", size: 44)
            VStack(alignment: .leading, spacing: 1) {
                if let index {
                    let stick = FortuneStick.all[index]
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(tr("今日"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(WidgetStyle.primary)
                        Text(verbatim: stick.level.title)
                            .font(.system(size: 17, weight: .heavy))
                            .foregroundStyle(levelColor(stick.level))
                    }
                    .minimumScaleFactor(0.87)
                    Text(verbatim: Divination.stickNumber(index))
                        .font(.system(size: 13))
                        .foregroundStyle(WidgetStyle.secondary)
                } else {
                    Text(tr("今天还没抽签"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WidgetStyle.primary)
                        .minimumScaleFactor(0.87)
                    Text(tr("点开摇一摇"))
                        .font(.system(size: 13))
                        .foregroundStyle(WidgetStyle.secondary)
                }
            }
            // 13pt 的小字不缩（最小 13pt），只有上面 15、17pt 的大字放不下时缩到 13。
            .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    // MARK: 竖排（76 宽）

    private func column(_ index: Int?) -> some View {
        VStack(spacing: 4) {
            DivinationPanda(name: index == nil ? "pet-panda-idle" : "pet-panda-cheer", size: 48)
            if let index {
                let stick = FortuneStick.all[index]
                Text(verbatim: stick.level.title)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(levelColor(stick.level))
                    .lineLimit(1)
                    .minimumScaleFactor(0.87)
                // 竖条内容只有 56 宽，「第三十七签」13pt 要 65，原来缩到 10pt 多；这里写阿拉伯数字。
                Text(verbatim: Divination.shortStickNumber(index))
                    .font(.system(size: 13))
                    .foregroundStyle(WidgetStyle.secondary)
                    .lineLimit(1)
            } else {
                Text(tr("未抽签"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WidgetStyle.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
    }
}

// MARK: - 写回和音效

/// 卡片、面板和桌面卡片的每一下都走这里：取最新存着的那份配置，算完写回，按开关放音效。
@MainActor
enum DivinationPlay {
    static func config(_ instance: WidgetInstance) -> WidgetConfig {
        (WidgetWriter.current(instance.id) ?? instance).config
    }

    private static func write(_ instance: WidgetInstance, _ change: (inout WidgetConfig) -> Void) {
        var widget = WidgetWriter.current(instance.id) ?? instance
        change(&widget.config)
        WidgetWriter.update(widget)
    }

    /// 摇签：今天抽过就返回那支（不重抽）。
    @discardableResult
    static func drawStick(in instance: WidgetInstance) -> Divination.Draw {
        var result = Divination.Draw(index: 0, isNew: false)
        write(instance) { config in
            result = Divination.drawStick(in: &config, now: Date(), salt: instance.id.uuidString)
        }
        return result
    }

    @discardableResult
    static func toss(in instance: WidgetInstance, question: String, all: Bool) -> Casting {
        var result = Casting()
        write(instance) { config in
            var rng = SystemRandomNumberGenerator()
            result = Divination.toss(in: &config, question: question, all: all,
                                     now: Date().timeIntervalSince1970, using: &rng)
        }
        return result
    }

    static func resetCasting(in instance: WidgetInstance) {
        write(instance) { Divination.resetCasting(in: &$0) }
    }

    static func clearHistory(in instance: WidgetInstance) {
        write(instance) { Divination.clearHistory(in: &$0) }
    }

    @discardableResult
    static func turnPage(in instance: WidgetInstance) -> Int {
        var page = 0
        write(instance) { config in
            var rng = SystemRandomNumberGenerator()
            page = Divination.turnPage(in: &config, using: &rng)
        }
        return page
    }

    static func setPage(_ page: DivinationPage, in instance: WidgetInstance) {
        guard Divination.page(config(instance)) != page else { return }
        write(instance) { Divination.setPage(page, in: &$0) }
    }

    static func toggleSound(in instance: WidgetInstance) {
        let on = !Divination.soundOn(config(instance))
        write(instance) { Divination.setSound(on, in: &$0) }
        // 摇签筒、铜钱叮当正响着时点静音：马上停，不等它放完。
        if !on { DivinationSoundPlayer.stopAll() }
    }

    /// 按卡片上的开关放一个音效。
    static func play(_ sound: DivinationSound, for instance: WidgetInstance) {
        guard Divination.soundOn(config(instance)) else { return }
        DivinationSoundPlayer.play(sound)
    }
}

/// 五个合成音效，各做一次 NSSound 缓存着。
@MainActor
enum DivinationSoundPlayer {
    private static var cache: [DivinationSound: NSSound] = [:]

    static func play(_ sound: DivinationSound) {
        let player: NSSound
        if let cached = cache[sound] {
            player = cached
        } else {
            guard let made = NSSound(data: DivinationSoundSynth.wav(sound)) else { return }
            cache[sound] = made
            player = made
        }
        if player.isPlaying { player.stop() }
        player.volume = 0.7
        player.play()
    }

    static func stop(_ sound: DivinationSound) {
        cache[sound]?.stop()
    }

    static func stopAll() {
        for player in cache.values where player.isPlaying { player.stop() }
    }
}

// MARK: - 颜色

/// 浅色深红、深色亮珊瑚红配金点缀。不铺大面积背景色、不发光。
enum DivinationStyle {
    /// 主色红（文字、卦辞、变爻红点）：浅色 #B3261E、深色 #FF7B6B，都过 4.5:1。
    static var red: Color {
        Color.panelDynamic(dark: NSColor(Color(hex: Divination.redDarkHex)),
                           light: NSColor(Color(hex: Divination.redLightHex)))
    }

    /// 实心主按钮的底：浅色深红；深色用稍深的珊瑚红，白字仍过 4.5:1。
    static var buttonFill: Color {
        Color.panelDynamic(dark: NSColor(Color(hex: "#C8352A")), light: NSColor(Color(hex: Divination.redLightHex)))
    }

    /// 金色点缀（装饰线、铜钱、签筒），不当正文。
    static let gold = Color(hex: Divination.goldHex)
    static let goldDeep = Color(hex: "#A87A1E")
    static let goldLight = Color(hex: "#F3D684")

    /// 金色当字用。
    static var goldText: Color {
        Color.panelDynamic(dark: NSColor(Color(hex: Divination.goldTextDarkHex)),
                           light: NSColor(Color(hex: Divination.goldTextLightHex)))
    }

    /// 签级的字色：上上、上吉喜庆红，中吉金，其余主文字色。
    static func level(_ level: StickLevel) -> Color {
        if level.isFestive { return red }
        if level == .good { return goldText }
        return Color.panelPrimary
    }

    /// 卦画：本卦主文字色，变卦淡一档。
    static var line: Color { Color.panelPrimary }
    static var lineFaded: Color { Color.panelTertiary }

    // 签筒是固定的角色配色（浅色、深色玻璃上都一样）。
    static let tubeBody = Color(hex: "#C98A3A")
    static let tubeShade = Color(hex: "#A86E28")
    static let tubeBand = Color(hex: "#8A5418")
    static let stick = Color(hex: "#E9C98A")
    static let stickTip = Color(hex: "#D23A2E")
    static let label = Color(hex: "#C8382E")

    // 古龟甲：暖棕、赭黄底，深棕描边（浅色、深色玻璃上都一样）。
    static let shellBase = Color(hex: "#B98543")
    static let shellLight = Color(hex: "#DEB068")
    static let shellDeep = Color(hex: "#7A4E22")
    static let shellLine = Color(hex: "#4A2C12")
    static let shellMouth = Color(hex: "#2E1A0B")

    // 小熊猫的毛色（取自 Resources/Pet 的小熊猫图）：橙棕毛、深一档的描边、深棕爪尖、亮部。
    static let fur = Color(hex: "#C9632B")
    static let furShade = Color(hex: "#8E3812")
    static let furTip = Color(hex: "#4E1E08")
    static let furHighlight = Color(hex: "#E99750")

    /// 地面阴影线、落地影子：深色玻璃上压得重一点才看得见。
    static var groundShade: Color {
        Color.panelDynamic(dark: NSColor.black.withAlphaComponent(0.4), light: NSColor.black.withAlphaComponent(0.13))
    }
    static var dust: Color {
        Color.panelDynamic(dark: NSColor(Color(hex: "#AA967A")), light: NSColor(Color(hex: "#C4AA82")))
    }

    // 解忧书：封皮深红薄边；纸张浅色米白，深色外观换成暖灰米色、降低亮度（Core 里的色值，测过对比度）。
    static var cover: Color {
        Color.panelDynamic(dark: NSColor(Color(hex: "#6A2428")), light: NSColor(Color(hex: "#8E1F26")))
    }
    static var coverEdge: Color {
        Color.panelDynamic(dark: NSColor(Color(hex: "#461519")), light: NSColor(Color(hex: "#64141A")))
    }
    static var bookPaper: Color { book(Divination.bookPaperDarkHex, Divination.bookPaperLightHex) }
    static var bookGutter: Color { book(Divination.bookGutterDarkHex, Divination.bookGutterLightHex) }
    static var bookInk: Color { book(Divination.bookInkDarkHex, Divination.bookInkLightHex) }
    static var bookRed: Color { book(Divination.bookRedDarkHex, Divination.bookRedLightHex) }
    static var bookPageNumber: Color { book(Divination.bookPageNumberDarkHex, Divination.bookPageNumberLightHex) }
    static var bookEdge: Color { book("#A89C84", "#E2D6BE") }
    static var bookShadow: Color {
        Color.panelDynamic(dark: NSColor.black.withAlphaComponent(0.5), light: NSColor.black.withAlphaComponent(0.3))
    }
    static let grain = Color(hex: "#5A4628")

    private static func book(_ dark: String, _ light: String) -> Color {
        Color.panelDynamic(dark: NSColor(Color(hex: dark)), light: NSColor(Color(hex: light)))
    }
}

// MARK: - 小熊猫

/// 码头自己的小熊猫（Resources/Pet），按名字取、缓存着。
struct DivinationPanda: View {
    var name: String
    var size: CGFloat

    @MainActor private static var cache: [String: NSImage] = [:]

    @MainActor private static func image(_ name: String) -> NSImage? {
        if let cached = cache[name] { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        cache[name] = image
        return image
    }

    var body: some View {
        Group {
            if let image = Self.image(name) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Circle().fill(Color(hex: "#E8743B").opacity(0.4))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - 签筒

/// 代码画的签筒：圆筒、两道箍、红签牌「签」字，上面露出几支红头竹签。
/// `drop` 为 true 时多一支签斜着飞出筒外（摇出来的那支）。
struct StickTube: View {
    var width: CGFloat
    var drop = false

    /// 签筒皮肤（Pro，默认竹）：配色从共享的皮肤入口读，见 DivinationDailyExtras。
    @Environment(\.divinationSkin) private var skin
    private var colors: DivinationTubeColors { DivinationTubeColors(skin.tube) }

    private var height: CGFloat { width * 1.15 }
    private func u(_ f: CGFloat) -> CGFloat { f * width }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 竹签。
            ForEach(Array([0.26, 0.38, 0.5, 0.62, 0.72].enumerated()), id: \.offset) { i, x in
                let h = u(0.42 + CGFloat(i % 2) * 0.08)
                stickShape(height: h)
                    .rotationEffect(.degrees(Double(i - 2) * 5), anchor: .bottom)
                    .offset(x: u(x) - u(0.035), y: u(0.36) - h)
            }
            if drop {
                stickShape(height: u(0.6))
                    .rotationEffect(.degrees(58), anchor: .bottom)
                    .offset(x: u(0.78), y: u(0.05))
                    .transition(.opacity)
            }
            // 筒身。
            RoundedRectangle(cornerRadius: u(0.1), style: .continuous)
                .fill(LinearGradient(colors: [colors.shade, colors.body, colors.shade],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: u(0.8), height: u(0.78))
                .offset(x: u(0.1), y: u(0.34))
            // 筒口。
            Ellipse()
                .fill(colors.shade)
                .overlay(Ellipse().strokeBorder(colors.band, lineWidth: max(1, u(0.02))))
                .frame(width: u(0.8), height: u(0.16))
                .offset(x: u(0.1), y: u(0.27))
            // 两道箍。
            ForEach([0.46, 0.98], id: \.self) { y in
                Capsule()
                    .fill(colors.band)
                    .frame(width: u(0.8), height: max(1.5, u(0.035)))
                    .offset(x: u(0.1), y: u(y))
            }
            // 红签牌。
            RoundedRectangle(cornerRadius: u(0.04), style: .continuous)
                .fill(colors.label)
                .overlay(
                    RoundedRectangle(cornerRadius: u(0.04), style: .continuous)
                        .strokeBorder(colors.labelInk, lineWidth: max(0.8, u(0.015)))
                )
                .overlay(
                    Text(verbatim: "签")
                        .font(.system(size: max(8, u(0.17)), weight: .heavy))
                        .foregroundStyle(colors.labelInk)
                )
                .frame(width: u(0.26), height: u(0.26))
                .offset(x: u(0.37), y: u(0.6))
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private func stickShape(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            Capsule().fill(DivinationStyle.stickTip).frame(height: height * 0.18)
            Rectangle().fill(DivinationStyle.stick)
        }
        .frame(width: u(0.07), height: height)
        .clipShape(Capsule())
    }
}

private enum StickStyleGradient {
    static var body: LinearGradient {
        LinearGradient(colors: [DivinationStyle.tubeShade, DivinationStyle.tubeBody, DivinationStyle.tubeShade],
                       startPoint: .leading, endPoint: .trailing)
    }
}

/// 小熊猫抱着签筒：签筒盖在小熊猫肚子前面。`shakes` 每加一次抖一阵（减少动态效果时不抖）。
struct PandaWithTube: View {
    var size: CGFloat
    var shakes: Int
    var drop: Bool
    var cheering: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            DivinationPanda(name: cheering ? "pet-panda-cheer" : "pet-panda-idle", size: size)
            StickTube(width: size * 0.46, drop: drop)
                .offset(x: size * 0.04, y: size * 0.02)
                .keyframeAnimator(initialValue: 0.0, trigger: reduceMotion ? 0 : shakes) { view, angle in
                    view.rotationEffect(.degrees(angle), anchor: .bottom)
                } keyframes: { _ in
                    KeyframeTrack {
                        LinearKeyframe(-12.0, duration: 0.08)
                        LinearKeyframe(12.0, duration: 0.14)
                        LinearKeyframe(-10.0, duration: 0.14)
                        LinearKeyframe(10.0, duration: 0.14)
                        LinearKeyframe(-8.0, duration: 0.14)
                        LinearKeyframe(8.0, duration: 0.14)
                        LinearKeyframe(0.0, duration: 0.08)
                    }
                }
        }
        .frame(width: size, height: size * 1.08, alignment: .bottom)
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.6), value: drop)
    }
}

// MARK: - 古龟甲

/// 代码画的古旧占卜龟甲（背甲，俯视略带透视）：赭黄底、中间一列三块脊甲、两侧肋甲、外圈缘甲，
/// 深棕描边，磨损高光和几道细裂纹；前沿一道深色壳口，铜钱从这里蹦出来。宽高比 1 : 0.72。
struct TurtleShell: View {
    var width: CGFloat

    nonisolated static let aspect: CGFloat = 0.72
    private var height: CGFloat { width * Self.aspect }

    var body: some View {
        Canvas { context, size in
            Self.draw(in: &context, size: size)
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }

    /// 裂纹（按宽高的比例）。
    nonisolated private static let cracks: [[CGPoint]] = [
        [CGPoint(x: 0.3, y: 0.28), CGPoint(x: 0.33, y: 0.33), CGPoint(x: 0.3, y: 0.38), CGPoint(x: 0.34, y: 0.43)],
        [CGPoint(x: 0.68, y: 0.5), CGPoint(x: 0.71, y: 0.55), CGPoint(x: 0.69, y: 0.6), CGPoint(x: 0.73, y: 0.66)],
        [CGPoint(x: 0.41, y: 0.6), CGPoint(x: 0.38, y: 0.65), CGPoint(x: 0.42, y: 0.7)],
    ]

    nonisolated private static func draw(in context: inout GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * w, y: y * h) }
        let line = GraphicsContext.Shading.color(DivinationStyle.shellLine)
        let lineWidth = max(0.8, w * 0.017)

        // 壳口：前沿下面一道深色月牙（外壳盖住上半）。
        context.fill(Path(ellipseIn: CGRect(x: 0.3 * w, y: 0.8 * h, width: 0.4 * w, height: 0.2 * h)),
                     with: .color(DivinationStyle.shellMouth))
        // 外壳：径向渐变，左上亮、四周深。
        let outer = Path(ellipseIn: CGRect(x: 0, y: 0, width: w, height: 0.94 * h))
        context.fill(outer, with: .radialGradient(
            Gradient(colors: [DivinationStyle.shellLight, DivinationStyle.shellBase, DivinationStyle.shellDeep]),
            center: pt(0.42, 0.36), startRadius: 0, endRadius: 0.62 * w))
        // 缘甲：内圈 + 一圈短格线。
        let inner = CGRect(x: 0.11 * w, y: 0.11 * h, width: 0.78 * w, height: 0.7 * h)
        context.stroke(Path(ellipseIn: inner), with: line, lineWidth: lineWidth)
        var rim = Path()
        for i in 0..<18 {
            let t = 2 * CGFloat.pi * (CGFloat(i) + 0.5) / 18
            rim.move(to: pt(0.5 + 0.39 * cos(t), 0.46 + 0.35 * sin(t)))
            rim.addLine(to: pt(0.5 + 0.5 * cos(t), 0.47 + 0.47 * sin(t)))
        }
        context.stroke(rim, with: line, lineWidth: lineWidth * 0.75)
        // 脊甲：中间一列三块六边形。
        for (cy, hx, hy) in [(0.24, 0.09, 0.1), (0.46, 0.1, 0.11), (0.68, 0.09, 0.1)] as [(CGFloat, CGFloat, CGFloat)] {
            var hex = Path()
            hex.move(to: pt(0.5 - hx * 0.6, cy - hy))
            hex.addLine(to: pt(0.5 + hx * 0.6, cy - hy))
            hex.addLine(to: pt(0.5 + hx, cy))
            hex.addLine(to: pt(0.5 + hx * 0.6, cy + hy))
            hex.addLine(to: pt(0.5 - hx * 0.6, cy + hy))
            hex.addLine(to: pt(0.5 - hx, cy))
            hex.closeSubpath()
            context.fill(hex, with: .color(DivinationStyle.shellLight.opacity(0.3)))
            context.stroke(hex, with: line, lineWidth: lineWidth)
        }
        // 肋甲：从脊甲两侧拉到内圈。
        var ribs = Path()
        for side in [CGFloat(-1), 1] {
            for (y0, y1) in [(0.13, 0.2), (0.35, 0.33), (0.57, 0.6), (0.79, 0.76)] as [(CGFloat, CGFloat)] {
                let t = asin(max(-1, min(1, (y1 - 0.46) / 0.35)))
                ribs.move(to: pt(0.5 + side * 0.06, y0))
                ribs.addLine(to: pt(0.5 + side * 0.39 * cos(t), y1))
            }
        }
        context.stroke(ribs, with: line, lineWidth: lineWidth)
        // 细裂纹。
        var crack = Path()
        for points in cracks {
            crack.addLines(points.map { pt($0.x, $0.y) })
        }
        context.stroke(crack, with: .color(DivinationStyle.shellLine.opacity(0.6)), lineWidth: max(0.5, lineWidth * 0.5))
        // 磨损高光：左上一片柔光、右上一道擦痕。
        context.drawLayer { layer in
            layer.clip(to: outer)
            layer.addFilter(.blur(radius: max(0.8, w * 0.025)))
            layer.fill(Path(ellipseIn: CGRect(x: 0.16 * w, y: 0.08 * h, width: 0.34 * w, height: 0.22 * h)),
                       with: .color(Color.white.opacity(0.32)))
            var scratch = Path()
            scratch.move(to: pt(0.6, 0.14))
            scratch.addLine(to: pt(0.72, 0.22))
            layer.stroke(scratch, with: .color(Color.white.opacity(0.45)), lineWidth: max(0.8, w * 0.014))
        }
        context.stroke(outer, with: line, lineWidth: lineWidth * 1.15)
    }
}

// MARK: - 小熊猫的爪子

/// 代码画的小熊猫爪子，配色取 Resources/Pet 里小熊猫的橙棕毛、深一档的描边和深棕爪尖。
/// 叠在书页、龟甲上面，压住边缘，形成前后遮挡。
struct PandaPaw: View {
    var width: CGFloat

    var body: some View {
        let height = width * 0.78
        ZStack {
            Ellipse().fill(DivinationStyle.furShade)
                .frame(width: width + 1.6, height: height + 1.6)
            Ellipse().fill(DivinationStyle.fur)
                .frame(width: width, height: height)
            Ellipse().fill(DivinationStyle.furHighlight.opacity(0.6))
                .frame(width: width * 0.34, height: height * 0.34)
                .offset(x: -width * 0.12, y: -height * 0.2)
            HStack(spacing: width * 0.16) {
                ForEach(0..<3, id: \.self) { _ in
                    Capsule().fill(DivinationStyle.furTip)
                        .frame(width: max(1, width * 0.08), height: height * 0.34)
                }
            }
            .offset(y: height * 0.26)
        }
        .frame(width: width + 2, height: height + 2)
        .accessibilityHidden(true)
    }
}

/// 前臂：从肩膀拉到爪子的一段粗圆头线（坐标是所在场景里的绝对坐标）。
struct PandaArm: View {
    var from: CGPoint
    var to: CGPoint
    var thickness: CGFloat

    var body: some View {
        let path = Path { p in
            p.move(to: from)
            p.addLine(to: to)
        }
        ZStack {
            path.stroke(DivinationStyle.furShade, style: StrokeStyle(lineWidth: thickness + 1.5, lineCap: .round))
            path.stroke(DivinationStyle.fur, style: StrokeStyle(lineWidth: thickness, lineCap: .round))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 小熊猫捧龟甲的骨架：按小熊猫尺寸算龟甲在胸前的位置、肩膀和两只爪子。
struct ShellRig {
    var size: CGFloat
    /// 小熊猫图上沿在场景里的 y、中心 x。
    var top: CGFloat
    var centerX: CGFloat

    var shellWidth: CGFloat { size * 0.76 }
    var shellHeight: CGFloat { shellWidth * TurtleShell.aspect }
    var pawWidth: CGFloat { size * 0.18 }
    var armThickness: CGFloat { size * 0.13 }
    /// 捧在胸前时龟甲中心的 y。
    var holdY: CGFloat { top + size * 0.66 }
    /// 举高多少。
    var liftHeight: CGFloat { size * 0.24 }

    func shoulder(_ side: CGFloat, lean: CGFloat) -> CGPoint {
        CGPoint(x: centerX + side * size * 0.19, y: top + size * 0.52 + lean * size * 0.05)
    }

    /// 爪子捏在龟甲两侧：`center` 是龟甲中心，跟着 `angle`（度）一起转。
    func paw(_ side: CGFloat, center: CGPoint, angle: Double) -> CGPoint {
        let dx = side * (shellWidth / 2 - size * 0.05)
        let dy = -size * 0.02
        let r = CGFloat(angle * .pi / 180)
        return CGPoint(x: center.x + dx * cos(r) - dy * sin(r), y: center.y + dx * sin(r) + dy * cos(r))
    }
}

/// 小熊猫双爪捧着古龟甲（桌面卡片用）：`shakes` 每加一次左右摇一阵，龟甲和爪子一起晃；
/// 减少动态效果时不晃。
struct PandaWithShell: View {
    var size: CGFloat
    var shakes: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        KeyframeAnimator(initialValue: 0.0, trigger: reduceMotion ? 0 : shakes) { sway in
            held(sway)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(-1.0, duration: 0.1)
                CubicKeyframe(1.0, duration: 0.16)
                CubicKeyframe(-1.0, duration: 0.16)
                CubicKeyframe(1.0, duration: 0.16)
                CubicKeyframe(0.0, duration: 0.1)
            }
        }
        .frame(width: size, height: size * 1.04)
        .accessibilityHidden(true)
    }

    private func held(_ sway: Double) -> some View {
        let rig = ShellRig(size: size, top: size * 0.04, centerX: size / 2)
        let angle = sway * 10
        let center = CGPoint(x: size / 2 + CGFloat(sway) * size * 0.05, y: rig.holdY)
        let left = rig.paw(-1, center: center, angle: angle)
        let right = rig.paw(1, center: center, angle: angle)
        return ZStack(alignment: .topLeading) {
            DivinationPanda(name: "pet-panda-idle", size: size)
                .rotationEffect(.degrees(sway * 3), anchor: .bottom)
                .position(x: size / 2, y: rig.top + size / 2)
            PandaArm(from: rig.shoulder(-1, lean: 0), to: left, thickness: rig.armThickness)
            PandaArm(from: rig.shoulder(1, lean: 0), to: right, thickness: rig.armThickness)
            TurtleShell(width: rig.shellWidth)
                .rotationEffect(.degrees(angle))
                .position(center)
            PandaPaw(width: rig.pawWidth).position(left)
            PandaPaw(width: rig.pawWidth).position(right)
        }
        .frame(width: size, height: size * 1.04)
    }
}

/// 起卦场景（面板，内容宽）：小熊猫双爪捧古龟甲；地面一条浅阴影线，上面躺着三枚铜钱。
/// `throwCount` 每加一次按 Core 的 `ShellToss` 走一遍：捧着摇 → 举高 → 摔到地上（越落越快，
/// 触地压扁回弹，扬起一点土）→ 三枚铜钱从壳口依次蹦出、抛物线落地、弹两下转着停下，
/// 显示正反面 → 小熊猫把龟甲捡回手里。减少动态效果时不动，铜钱直接躺在地上。
struct ShellTossScene: View {
    var width: CGFloat
    /// 最近一爻三枚铜钱的正反（true 是背）；还没摇过是 nil，铜钱淡淡地摆着。
    var faces: [Bool]?
    var throwCount: Int
    var fast: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let height: CGFloat = 146
    private let pandaSize: CGFloat = 88
    private let coin: CGFloat = 30
    private let ground: CGFloat = 132

    private var rig: ShellRig { ShellRig(size: pandaSize, top: 8, centerX: width / 2) }

    var body: some View {
        let toss = ShellToss.timing(fast: fast)
        return KeyframeAnimator(initialValue: TossMotion(), trigger: reduceMotion ? 0 : throwCount) { motion in
            scene(motion)
        } keyframes: { _ in
            let t = toss
            let s = t.shake
            KeyframeTrack(\.sway) {
                CubicKeyframe(-1, duration: s * 0.15)
                CubicKeyframe(1, duration: s * 0.23)
                CubicKeyframe(-1, duration: s * 0.23)
                CubicKeyframe(1, duration: s * 0.23)
                CubicKeyframe(0, duration: s * 0.16)
            }
            KeyframeTrack(\.lift) {
                LinearKeyframe(0, duration: s)
                CubicKeyframe(1, duration: t.lift)
                LinearKeyframe(1, duration: t.fall)
                LinearKeyframe(0, duration: 0.001)
            }
            KeyframeTrack(\.pawLift) {
                LinearKeyframe(0, duration: s)
                CubicKeyframe(1, duration: t.lift)
                LinearKeyframe(1, duration: t.fall * 0.6)
                CubicKeyframe(0, duration: 0.25)
            }
            // 往下摔：越落越快（按重力分三段）。
            KeyframeTrack(\.drop) {
                LinearKeyframe(0, duration: t.fallStart)
                LinearKeyframe(0.25, duration: t.fall * 0.5)
                LinearKeyframe(0.5625, duration: t.fall * 0.25)
                LinearKeyframe(1, duration: t.fall * 0.25)
                LinearKeyframe(1, duration: t.pickupStart - t.impact)
                CubicKeyframe(-0.06, duration: t.pickup * 0.75)
                CubicKeyframe(0, duration: t.pickup * 0.25)
            }
            KeyframeTrack(\.squash) {
                LinearKeyframe(0, duration: t.impact)
                LinearKeyframe(1, duration: 0.05)
                CubicKeyframe(-0.35, duration: (t.squash - 0.05) / 2)
                CubicKeyframe(0, duration: (t.squash - 0.05) / 2)
            }
            KeyframeTrack(\.dust) {
                LinearKeyframe(0, duration: t.impact)
                LinearKeyframe(0.02, duration: 0.001)
                LinearKeyframe(1, duration: 0.45)
                LinearKeyframe(0, duration: 0.001)
            }
            KeyframeTrack(\.lean) {
                LinearKeyframe(0, duration: t.fallStart)
                CubicKeyframe(1, duration: t.fall)
                CubicKeyframe(0, duration: 0.25)
                LinearKeyframe(0, duration: max(0.001, t.pickupStart - t.impact - 0.25))
                CubicKeyframe(1, duration: t.pickup * 0.5)
                CubicKeyframe(0, duration: t.pickup * 0.5)
            }
            // 三枚铜钱：-1 在壳里看不见，0…1 在空中，1…2 落地弹两下，2 停住。
            KeyframeTrack(\.coin0) {
                LinearKeyframe(-1, duration: 0.001)
                LinearKeyframe(-1, duration: t.popStart(0) - 0.001)
                LinearKeyframe(0, duration: 0.001)
                LinearKeyframe(1, duration: t.flight)
                LinearKeyframe(2, duration: t.bounce)
            }
            KeyframeTrack(\.coin1) {
                LinearKeyframe(-1, duration: 0.001)
                LinearKeyframe(-1, duration: t.popStart(1) - 0.001)
                LinearKeyframe(0, duration: 0.001)
                LinearKeyframe(1, duration: t.flight)
                LinearKeyframe(2, duration: t.bounce)
            }
            KeyframeTrack(\.coin2) {
                LinearKeyframe(-1, duration: 0.001)
                LinearKeyframe(-1, duration: t.popStart(2) - 0.001)
                LinearKeyframe(0, duration: 0.001)
                LinearKeyframe(1, duration: t.flight)
                LinearKeyframe(2, duration: t.bounce)
            }
        }
        .frame(width: width, height: Self.height)
        .accessibilityHidden(true)
    }

    private func landing(_ i: Int) -> CGPoint {
        let spot = ShellToss.landings[i]
        return CGPoint(x: width / 2 + CGFloat(spot.x) * coin, y: ground - coin / 2 + CGFloat(spot.y) * coin)
    }

    private func scene(_ m: TossMotion) -> some View {
        let rig = self.rig
        let lean = CGFloat(m.lean)
        let held = CGFloat(1 - min(1, max(0, m.drop)))
        let groundY = ground - rig.shellHeight / 2 + 2
        let liftedY = rig.holdY - rig.liftHeight * CGFloat(m.lift) + lean * 4 * held
        let shellY = liftedY + (groundY - liftedY) * CGFloat(m.drop)
        let angle = m.sway * 10
        let center = CGPoint(x: width / 2 + CGFloat(m.sway) * pandaSize * 0.05, y: shellY)
        let pawCenter = CGPoint(x: center.x, y: rig.holdY - rig.liftHeight * CGFloat(m.pawLift) + lean * 5)
        let left = rig.paw(-1, center: m.drop < 0.02 ? center : pawCenter, angle: angle)
        let right = rig.paw(1, center: m.drop < 0.02 ? center : pawCenter, angle: angle)
        let squash = CGFloat(m.squash)
        return ZStack(alignment: .topLeading) {
            // 地面浅阴影线。
            Ellipse().fill(DivinationStyle.groundShade)
                .frame(width: width - 20, height: 7)
                .blur(radius: 2.5)
                .position(x: width / 2, y: ground)
            DivinationPanda(name: "pet-panda-idle", size: pandaSize)
                .rotationEffect(.degrees(m.sway * 3), anchor: .bottom)
                .offset(y: lean * 4)
                .position(x: width / 2, y: rig.top + pandaSize / 2)
            PandaArm(from: rig.shoulder(-1, lean: lean), to: left, thickness: rig.armThickness)
            PandaArm(from: rig.shoulder(1, lean: lean), to: right, thickness: rig.armThickness)
            // 龟甲落地的影子。
            Ellipse().fill(DivinationStyle.groundShade)
                .frame(width: rig.shellWidth * 1.1, height: 7)
                .blur(radius: 2)
                .opacity(max(0, min(1, m.drop)))
                .position(x: width / 2, y: ground)
            TurtleShell(width: rig.shellWidth)
                .scaleEffect(x: 1 + 0.1 * squash, y: 1 - 0.14 * squash, anchor: .bottom)
                .rotationEffect(.degrees(angle))
                .position(center)
            PandaPaw(width: rig.pawWidth).position(left)
            PandaPaw(width: rig.pawWidth).position(right)
            if m.dust > 0.01, m.dust < 0.99 { dust(m.dust) }
            ForEach(0..<3, id: \.self) { i in
                coinView(i, [m.coin0, m.coin1, m.coin2][i], shellTop: groundY - rig.shellHeight * 0.1)
            }
        }
        .frame(width: width, height: Self.height)
    }

    /// 触地扬起的土：两边各六粒，往外散开、变淡。
    private func dust(_ p: Double) -> some View {
        let spread = CGFloat(p)
        return ZStack(alignment: .topLeading) {
            ForEach(0..<12, id: \.self) { k in
                let side: CGFloat = k < 6 ? -1 : 1
                let j = CGFloat(k % 6)
                let x = width / 2 + side * (rig.shellWidth / 2 + 4 + j * 5 * (0.4 + spread))
                let y = ground - 2 - (CGFloat((k * 7) % 5) + j * 0.6) * (0.3 + spread)
                Circle().fill(DivinationStyle.dust)
                    .frame(width: 2.4 + CGFloat(k % 3) * 0.8, height: 2.4 + CGFloat(k % 3) * 0.8)
                    .opacity((1 - p) * (0.75 - Double(j) * 0.08))
                    .position(x: x, y: y)
            }
        }
    }

    /// 铜钱此刻的位置、绕横轴翻的角度和平面里转的角度。
    private func coinPose(_ i: Int, _ p: Double, shellTop: CGFloat) -> (position: CGPoint, flip: Double, spin: Double) {
        let land = landing(i)
        if p < 1 {
            let mouth = CGPoint(x: width / 2 + CGFloat(i - 1) * 6, y: shellTop + rig.shellHeight * 0.45)
            let arc: CGFloat = 52 + CGFloat(i) * 10
            let t = CGFloat(max(0, p))
            let position = CGPoint(x: mouth.x + (land.x - mouth.x) * t,
                                   y: mouth.y + (land.y - mouth.y) * t - arc * 4 * t * (1 - t))
            return (position, Double(1 - t) * 540 * (i == 1 ? -1 : 1), Double(1 - t) * 160 * (i == 2 ? -1 : 1))
        }
        let b = min(1, p - 1)
        let hop = b < 0.55 ? sin(b / 0.55 * .pi) * 0.3 : sin((b - 0.55) / 0.45 * .pi) * 0.09
        return (CGPoint(x: land.x, y: land.y - CGFloat(hop) * coin), sin(b * .pi * 3) * (1 - b) * 25, 0)
    }

    private func coinView(_ i: Int, _ p: Double, shellTop: CGFloat) -> some View {
        let pose = coinPose(i, p, shellTop: shellTop)
        let face = faces.map { $0[i] } ?? (i != 1)
        let shown = p >= 0
        return ZStack(alignment: .topLeading) {
            Ellipse().fill(DivinationStyle.groundShade)
                .frame(width: coin * 0.8, height: 5)
                .blur(radius: 1.2)
                .opacity(shown ? min(1, max(0.25, p)) : 0)
                .position(x: pose.position.x, y: ground + 1)
            CoinView(back: face, size: coin)
                .rotation3DEffect(.degrees(pose.flip), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
                .rotationEffect(.degrees(pose.spin))
                .opacity(shown ? (faces == nil ? 0.55 : 1) : 0)
                .position(pose.position)
        }
    }
}

struct TossMotion {
    var sway: Double = 0
    var lift: Double = 0
    var pawLift: Double = 0
    var drop: Double = 0
    var squash: Double = 0
    var dust: Double = 0
    var lean: Double = 0
    var coin0: Double = 2
    var coin1: Double = 2
    var coin2: Double = 2
}

// MARK: - 铜钱

/// 代码画的铜钱：外圆内方，金边。字面四个字（原创钱文「卜卦通宝」），背面两点星纹。
struct CoinView: View {
    /// true 是背面。
    var back: Bool
    var size: CGFloat

    /// 铜钱皮肤（Pro，默认铜钱）：配色从共享的皮肤入口读，见 DivinationDailyExtras。
    @Environment(\.divinationSkin) private var skin
    private var colors: DivinationCoinColors { DivinationCoinColors(skin.coin) }

    /// 钱文按上下右左读成「卜卦通宝」（原创）；数组按上、右、下、左摆。
    private static let legend = ["卜", "通", "卦", "宝"]
    private static let places: [CGPoint] = [CGPoint(x: 0, y: -1), CGPoint(x: 1, y: 0),
                                            CGPoint(x: 0, y: 1), CGPoint(x: -1, y: 0)]

    var body: some View {
        ZStack {
            Circle().fill(colors.face)
            Circle().strokeBorder(colors.deep, lineWidth: max(1, size * 0.07))
            Circle().strokeBorder(colors.deep.opacity(0.55), lineWidth: max(0.6, size * 0.025))
                .padding(size * 0.13)
            RoundedRectangle(cornerRadius: size * 0.03)
                .fill(colors.deep)
                .frame(width: size * 0.26, height: size * 0.26)
            RoundedRectangle(cornerRadius: size * 0.02)
                .strokeBorder(colors.light, lineWidth: max(0.6, size * 0.03))
                .frame(width: size * 0.34, height: size * 0.34)
            if back {
                ForEach([CGFloat(-1), CGFloat(1)], id: \.self) { side in
                    Circle().fill(colors.deep)
                        .frame(width: size * 0.09, height: size * 0.09)
                        .offset(x: side * size * 0.29)
                }
            } else if size >= 26 {
                ForEach(0..<4, id: \.self) { i in
                    Text(verbatim: Self.legend[i])
                        .font(.system(size: size * 0.2, weight: .heavy))
                        .foregroundStyle(colors.deep)
                        .offset(x: Self.places[i].x * size * 0.29, y: Self.places[i].y * size * 0.29)
                }
            } else {
                ForEach(0..<4, id: \.self) { i in
                    Capsule().fill(colors.deep)
                        .frame(width: size * 0.12, height: size * 0.06)
                        .offset(x: Self.places[i].x * size * 0.29, y: Self.places[i].y * size * 0.29)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(back ? tr("背") : tr("字"))
    }
}

// MARK: - 卦画

/// 卦画：上爻在最上面。阳爻一整条，阴爻中间断开；变爻左边一个红点。
/// 只摇了几爻时没摇到的位置画成淡淡的虚线占位。
struct HexagramFigure: View {
    /// 自下而上；可以不满六爻。
    var yang: [Bool]
    var changing: Set<Int> = []
    var faded = false
    var width: CGFloat
    var lineHeight: CGFloat
    var spacing: CGFloat

    var body: some View {
        VStack(spacing: spacing) {
            ForEach((0..<6).reversed(), id: \.self) { i in
                HStack(spacing: 4) {
                    Circle()
                        .fill(changing.contains(i) ? DivinationStyle.red : Color.clear)
                        .frame(width: lineHeight * 0.9, height: lineHeight * 0.9)
                    line(i)
                }
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private func line(_ i: Int) -> some View {
        let color = faded ? DivinationStyle.lineFaded : DivinationStyle.line
        if i < yang.count {
            if yang[i] {
                RoundedRectangle(cornerRadius: lineHeight * 0.25).fill(color)
                    .frame(width: width, height: lineHeight)
            } else {
                HStack(spacing: width * 0.16) {
                    RoundedRectangle(cornerRadius: lineHeight * 0.25).fill(color)
                    RoundedRectangle(cornerRadius: lineHeight * 0.25).fill(color)
                }
                .frame(width: width, height: lineHeight)
            }
        } else {
            RoundedRectangle(cornerRadius: lineHeight * 0.25)
                .strokeBorder(Color.panelQuaternary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .frame(width: width, height: lineHeight)
        }
    }
}

// MARK: - 解忧书

/// 解忧书场景（面板，内容宽）：小熊猫趴在书后探头，两只爪子搭在书页上沿、压住页边；
/// 答案用宋体大字跨两页居中写在书页上，页码小字在右页页脚，左页一枚淡淡的「解忧」印和竹叶。
/// `flips` 每加一次：右爪掀起右页，右页沿书脊 3D 翻过去，小熊猫身子跟着往前倾一下，
/// 翻完小幅歪头。减少动态效果时不翻不倾，只换字。
struct WorryBookScene: View {
    var width: CGFloat
    /// 书页上的答案（页下标）；还没翻过是 nil，书页上写提示语。
    var index: Int?
    /// 翻页前半段旧字淡出、翻到一半换成新字。
    var textVisible: Bool
    var flips: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let height: CGFloat = 238
    private let pandaSize: CGFloat = 90
    private let bookTop: CGFloat = 64
    private let pageHeight: CGFloat = 150
    private var bookWidth: CGFloat { width - 8 }
    private var pageWidth: CGFloat { bookWidth / 2 }
    private var bookX: CGFloat { (width - bookWidth) / 2 }
    private var spine: CGFloat { width / 2 }

    var body: some View {
        KeyframeAnimator(initialValue: BookMotion(), trigger: reduceMotion ? 0 : flips) { motion in
            scene(motion)
        } keyframes: { _ in
            let d = WorryBook.flipDuration
            KeyframeTrack(\.angle) {
                LinearKeyframe(0, duration: 0.001)
                CubicKeyframe(-180, duration: d)
                LinearKeyframe(0, duration: 0.001)
            }
            KeyframeTrack(\.leaf) {
                LinearKeyframe(1, duration: 0.001)
                LinearKeyframe(1, duration: d)
                LinearKeyframe(0, duration: 0.001)
            }
            KeyframeTrack(\.follow) {
                CubicKeyframe(1, duration: 0.12)
                LinearKeyframe(1, duration: d * 0.45)
                CubicKeyframe(0, duration: 0.22)
            }
            KeyframeTrack(\.lean) {
                CubicKeyframe(1, duration: 0.16)
                LinearKeyframe(1, duration: d * 0.4)
                CubicKeyframe(0, duration: 0.26)
            }
            KeyframeTrack(\.tilt) {
                LinearKeyframe(0, duration: d)
                CubicKeyframe(1, duration: 0.14)
                CubicKeyframe(0, duration: 0.3)
            }
        }
        .frame(width: width, height: Self.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
    }

    private var accessibility: String {
        guard let index else { return tr("想好了，就翻开看看") }
        return WorryBook.answers[index] + "，" + tr("第 \(index + 1) 页")
    }

    private func scene(_ m: BookMotion) -> some View {
        let top = bookTop
        let lean = CGFloat(m.lean)
        return ZStack(alignment: .topLeading) {
            // 小熊猫在书后面，只露出头和上半身。
            DivinationPanda(name: "pet-panda-idle", size: pandaSize)
                .rotationEffect(.degrees(-4 * m.lean + 4 * m.tilt), anchor: .bottom)
                .offset(x: 2 * lean, y: 4 * lean)
                .position(x: spine, y: pandaSize / 2)
            // 书底下的柔和投影。
            Ellipse().fill(DivinationStyle.bookShadow)
                .frame(width: bookWidth * 0.92, height: 12)
                .blur(radius: 5)
                .position(x: spine, y: top + pageHeight + 10)
            // 封皮：薄薄一圈边。
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(DivinationStyle.cover)
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(DivinationStyle.coverEdge, lineWidth: 0.6))
                .frame(width: bookWidth + 6, height: pageHeight + 8)
                .position(x: spine, y: top - 1 + (pageHeight + 8) / 2)
            BookmarkRibbon()
                .fill(DivinationStyle.cover)
                .frame(width: 7, height: 17)
                .position(x: bookX + bookWidth - 26, y: top + pageHeight + 13)
            pageEdges
            BookPaperPage(left: true)
                .frame(width: pageWidth, height: pageHeight)
                .position(x: bookX + pageWidth / 2, y: top + pageHeight / 2)
            BookPaperPage(left: false)
                .frame(width: pageWidth, height: pageHeight)
                .position(x: spine + pageWidth / 2, y: top + pageHeight / 2)
            BookPageDecor(pageHeight: pageHeight)
                .frame(width: pageWidth, height: pageHeight)
                .position(x: bookX + pageWidth / 2, y: top + pageHeight / 2)
            Rectangle().fill(DivinationStyle.bookGutter)
                .frame(width: 0.8, height: pageHeight - 4)
                .position(x: spine, y: top + 2 + (pageHeight - 4) / 2)
            if m.leaf > 0.5, m.angle < -0.5 { leaf(m) }
            pageText
                .opacity(textVisible ? 1 : 0)
            arms(m)
        }
        .frame(width: width, height: Self.height)
    }

    /// 书页下沿露出的两道纸边（书的厚度）。
    private var pageEdges: some View {
        Path { p in
            for k in [CGFloat(2), 4] {
                let y = bookTop + pageHeight + k
                p.move(to: CGPoint(x: bookX + 2, y: y))
                p.addLine(to: CGPoint(x: spine - 3, y: y - 0.6))
                p.move(to: CGPoint(x: spine + 3, y: y - 0.6))
                p.addLine(to: CGPoint(x: bookX + bookWidth - 2, y: y))
            }
        }
        .stroke(DivinationStyle.bookEdge, lineWidth: 0.9)
    }

    /// 字：答案（宋体，一到两行，最后一行用强调红）和页码；没翻过时是提示语。
    @ViewBuilder private var pageText: some View {
        let center = CGPoint(x: spine, y: bookTop + pageHeight * 0.5)
        if let index {
            let layout = WorryBook.layout(WorryBook.answers[index])
            VStack(spacing: 6) {
                ForEach(Array(layout.lines.enumerated()), id: \.offset) { i, line in
                    Text(verbatim: line)
                        .font(.custom("Songti SC", size: CGFloat(layout.font)).weight(.semibold))
                        .foregroundStyle(i == layout.lines.count - 1 ? DivinationStyle.bookRed : DivinationStyle.bookInk)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .position(center)
            Text(tr("第 \(index + 1) 页"))
                .font(.system(size: 13))
                .foregroundStyle(DivinationStyle.bookPageNumber)
                .lineLimit(1)
                .fixedSize()
                .frame(width: pageWidth - 24, alignment: .trailing)
                .position(x: spine + pageWidth / 2, y: bookTop + pageHeight - 15)
        } else {
            Text(tr("想好了，就翻开看看"))
                .font(.custom("Songti SC", size: 17).weight(.semibold))
                .foregroundStyle(DivinationStyle.bookPageNumber)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: CGFloat(WorryBook.spreadTextWidth))
                .fixedSize(horizontal: false, vertical: true)
                .position(center)
        }
    }

    /// 翻起来的右页：正面是空白纸，过了 90° 看到的是背面（就是翻过去以后的新左页）。
    private func leaf(_ m: BookMotion) -> some View {
        let back = m.angle < -90
        let shade = sin(abs(m.angle) * .pi / 180) * 0.14
        return ZStack {
            if back {
                ZStack {
                    BookPaperPage(left: true)
                    BookPageDecor(pageHeight: pageHeight)
                }
                .scaleEffect(x: -1, y: 1)
            } else {
                BookPaperPage(left: false)
            }
            BookPageShape(left: false)
                .fill(Color.black.opacity(shade))
        }
        .frame(width: pageWidth, height: pageHeight)
        .shadow(color: Color.black.opacity(shade), radius: 4)
        .rotation3DEffect(.degrees(m.angle), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 0.45)
        .position(x: spine + pageWidth / 2, y: bookTop + pageHeight / 2)
    }

    /// 两条前臂从书后伸过上沿，爪子压在页边上；翻页时右爪先挪到右页外角、跟着纸角掀起来。
    private func arms(_ m: BookMotion) -> some View {
        let top = bookTop
        let sink = 3 * CGFloat(m.lean)
        let left = CGPoint(x: spine - 36, y: top + 7 + sink)
        let rest = CGPoint(x: spine + 36, y: top + 7 + sink)
        let theta = -m.angle * .pi / 180
        let corner = CGPoint(x: spine + pageWidth * 0.62 * CGFloat(cos(theta)), y: top - 4 - 14 * CGFloat(sin(theta)))
        let f = CGFloat(m.follow)
        let right = CGPoint(x: rest.x + (corner.x - rest.x) * f, y: rest.y + (corner.y - rest.y) * f)
        let shoulderY = top - 10 + sink
        return ZStack(alignment: .topLeading) {
            PandaArm(from: CGPoint(x: spine - 17, y: shoulderY), to: CGPoint(x: left.x + 2, y: left.y - 3),
                     thickness: 13)
            PandaArm(from: CGPoint(x: spine + 17 + 2 * CGFloat(m.lean), y: shoulderY),
                     to: CGPoint(x: right.x - 2, y: right.y - 3), thickness: 13)
            PandaPaw(width: 17).position(left)
            PandaPaw(width: 17).position(right)
        }
    }
}

struct BookMotion {
    var angle: Double = 0
    var leaf: Double = 0
    var follow: Double = 0
    var lean: Double = 0
    var tilt: Double = 0
}

/// 一页纸：靠书脊一侧渐深（书脊阴影），外侧米白，上沿往书脊微微陷下去，带一层很淡的纸纹。
struct BookPaperPage: View {
    var left: Bool

    var body: some View {
        let shape = BookPageShape(left: left)
        shape
            .fill(LinearGradient(stops: [.init(color: DivinationStyle.bookGutter, location: 0),
                                         .init(color: DivinationStyle.bookPaper, location: 0.32)],
                                 startPoint: left ? .trailing : .leading, endPoint: left ? .leading : .trailing))
            .overlay(PaperGrain(seed: left ? 7 : 11).clipShape(shape))
            .accessibilityHidden(true)
    }
}

/// 页的轮廓：上沿从外侧往书脊陷下 4pt。
struct BookPageShape: Shape {
    var left: Bool

    func path(in rect: CGRect) -> Path {
        let dip: CGFloat = 4
        let spineX = left ? rect.maxX : rect.minX
        let outerX = left ? rect.minX : rect.maxX
        var path = Path()
        path.move(to: CGPoint(x: outerX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: spineX, y: rect.minY + dip),
                          control: CGPoint(x: outerX + (spineX - outerX) * 0.75, y: rect.minY))
        path.addLine(to: CGPoint(x: spineX, y: rect.maxY))
        path.addLine(to: CGPoint(x: outerX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// 纸纹：固定种子的细点和短纤维，很淡，只让纸面不死白。
struct PaperGrain: View {
    var seed: UInt64

    var body: some View {
        let grain = DivinationStyle.grain
        let seed = seed
        return Canvas { context, size in
            var state = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            func next() -> CGFloat {
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return CGFloat((state >> 33) % 10_000) / 10_000
            }
            let dots = Int(size.width * size.height / 40)
            for _ in 0..<dots {
                let rect = CGRect(x: next() * size.width, y: next() * size.height, width: 0.7, height: 0.7)
                context.fill(Path(rect), with: .color(grain.opacity(0.05 + 0.05 * Double(next()))))
            }
            var fibers = Path()
            for _ in 0..<max(1, dots / 22) {
                let x = next() * size.width, y = next() * size.height
                let length = 2 + next() * 4, angle = next() * .pi
                fibers.move(to: CGPoint(x: x, y: y))
                fibers.addLine(to: CGPoint(x: x + length * cos(angle), y: y + length * sin(angle)))
            }
            context.stroke(fibers, with: .color(grain.opacity(0.06)), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 左页装饰：左上角一枚淡淡的「解忧」印，左下角一小簇竹叶。纯装饰，读屏跳过。
struct BookPageDecor: View {
    var pageHeight: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                Text(verbatim: "解")
                Text(verbatim: "忧")
            }
            .font(.custom("Songti SC", size: 14).weight(.bold))
            .foregroundStyle(DivinationStyle.bookRed)
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(DivinationStyle.bookRed, lineWidth: 1.2))
            .opacity(0.28)
            .offset(x: 10, y: 12)
            BambooSprig()
                .fill(DivinationStyle.bookRed.opacity(0.2))
                .frame(width: 26, height: 26)
                .offset(x: 12, y: pageHeight - 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 三片竹叶，从下沿中间往上散开。
struct BambooSprig: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let base = CGPoint(x: rect.midX, y: rect.maxY)
        for (degrees, length) in [(-28.0, 0.85), (-8.0, 1.0), (14.0, 0.78)] {
            let r = CGFloat((degrees - 90) * .pi / 180)
            let len = rect.height * CGFloat(length)
            let tip = CGPoint(x: base.x + len * cos(r), y: base.y + len * sin(r))
            let mid = CGPoint(x: (base.x + tip.x) / 2, y: (base.y + tip.y) / 2)
            let n = CGPoint(x: -sin(r) * rect.width * 0.12, y: cos(r) * rect.width * 0.12)
            path.move(to: base)
            path.addQuadCurve(to: tip, control: CGPoint(x: mid.x + n.x, y: mid.y + n.y))
            path.addQuadCurve(to: base, control: CGPoint(x: mid.x - n.x, y: mid.y - n.y))
        }
        return path
    }
}

/// 书签带：下端剪成燕尾。
struct BookmarkRibbon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - rect.width * 0.6))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - 小部件

/// 实心红主按钮（白字），整宽胶囊。
struct DivinationPrimaryButton: View {
    var title: String
    var height: CGFloat = 36
    var enabled = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                // 最小 13pt：15 × 0.87。
                .minimumScaleFactor(0.87)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(Capsule().fill(DivinationStyle.buttonFill).opacity(enabled ? 1 : 0.45))
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// 玻璃胶囊次按钮（主文字色）。
struct DivinationGlassButton: View {
    var title: String
    var height: CGFloat = 36
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.panelPrimary)
                .lineLimit(1)
                // 最小 13pt：14 × 0.93。
                .minimumScaleFactor(0.93)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(Capsule().fill(Color.panelRaised).panelLift())
                .overlay(Capsule().strokeBorder(Color.panelStroke, lineWidth: 0.5))
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

/// 两边带金色小圆点细线的签级大字（细线、圆点、签级、圆点、细线）。
struct StickLevelBanner: View {
    var level: StickLevel
    var size: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            ornament(leading: true)
            Text(verbatim: level.title)
                .font(.custom("Songti SC", size: size).weight(.heavy))
                .foregroundStyle(DivinationStyle.level(level))
                .lineLimit(1)
                .fixedSize()
            ornament(leading: false)
        }
    }

    private func ornament(leading: Bool) -> some View {
        HStack(spacing: 0) {
            if !leading { Circle().fill(DivinationStyle.gold).frame(width: 5, height: 5) }
            Rectangle().fill(DivinationStyle.gold).frame(width: size * 0.9, height: 1)
            if leading { Circle().fill(DivinationStyle.gold).frame(width: 5, height: 5) }
        }
    }
}
