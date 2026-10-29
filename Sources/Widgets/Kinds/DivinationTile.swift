import AppKit
import SwiftUI

// MARK: - 卜卦 · 扩展栏卡片
//
// 扩展栏卡片 188×62（竖排 76×120）：小熊猫、今日签级和签号；没抽时写「今天还没抽签」。
// 点卡片打开面板（每日一签 / 起卦 / 解忧书三页）。规则和存法都在 Core 的 `Divination`。
// 这里还放三个界面共用的部件：小熊猫、签筒、龟壳、铜钱、卦画、书，全部原创、代码画
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

    // 签筒、龟壳、书是固定的角色配色（浅色、深色玻璃上都一样）。
    static let tubeBody = Color(hex: "#C98A3A")
    static let tubeShade = Color(hex: "#A86E28")
    static let tubeBand = Color(hex: "#8A5418")
    static let stick = Color(hex: "#E9C98A")
    static let stickTip = Color(hex: "#D23A2E")
    static let label = Color(hex: "#C8382E")
    static let shell = Color(hex: "#6F8F4E")
    static let shellPlate = Color(hex: "#8DAE62")
    static let shellEdge = Color(hex: "#4C6A33")
    static let shellRim = Color(hex: "#C9A86A")
    static let cover = Color(hex: "#9E2128")
    static let paper = Color(hex: "#FBF6EA")
    static let paperShade = Color(hex: "#EAE2CF")
    static let paperLine = Color(hex: "#D9D0BC")
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
                .fill(StickStyleGradient.body)
                .frame(width: u(0.8), height: u(0.78))
                .offset(x: u(0.1), y: u(0.34))
            // 筒口。
            Ellipse()
                .fill(DivinationStyle.tubeShade)
                .overlay(Ellipse().strokeBorder(DivinationStyle.tubeBand, lineWidth: max(1, u(0.02))))
                .frame(width: u(0.8), height: u(0.16))
                .offset(x: u(0.1), y: u(0.27))
            // 两道箍。
            ForEach([0.46, 0.98], id: \.self) { y in
                Capsule()
                    .fill(DivinationStyle.tubeBand)
                    .frame(width: u(0.8), height: max(1.5, u(0.035)))
                    .offset(x: u(0.1), y: u(y))
            }
            // 红签牌。
            RoundedRectangle(cornerRadius: u(0.04), style: .continuous)
                .fill(DivinationStyle.label)
                .overlay(
                    RoundedRectangle(cornerRadius: u(0.04), style: .continuous)
                        .strokeBorder(DivinationStyle.goldLight, lineWidth: max(0.8, u(0.015)))
                )
                .overlay(
                    Text(verbatim: "签")
                        .font(.system(size: max(8, u(0.17)), weight: .heavy))
                        .foregroundStyle(DivinationStyle.goldLight)
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

// MARK: - 龟壳

/// 代码画的龟壳：半圆拱顶，上面一圈六边形甲片，底边一道浅色壳沿。倒扣时整只翻过来。
struct TurtleShell: View {
    var width: CGFloat

    private var height: CGFloat { width * 0.62 }

    var body: some View {
        ZStack {
            ShellDome()
                .fill(DivinationStyle.shell)
                .overlay(ShellDome().stroke(DivinationStyle.shellEdge, lineWidth: max(1, width * 0.025)))
            // 甲片。
            ForEach(Self.plates, id: \.self) { plate in
                Hexagon()
                    .fill(DivinationStyle.shellPlate)
                    .overlay(Hexagon().stroke(DivinationStyle.shellEdge, lineWidth: max(0.8, width * 0.015)))
                    .frame(width: width * plate.size, height: width * plate.size * 0.86)
                    .position(x: width * plate.x, y: height * plate.y)
            }
            // 壳沿。
            Capsule()
                .fill(DivinationStyle.shellRim)
                .overlay(Capsule().stroke(DivinationStyle.shellEdge, lineWidth: max(0.8, width * 0.015)))
                .frame(width: width, height: height * 0.16)
                .position(x: width / 2, y: height * 0.92)
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }

    struct Plate: Hashable {
        var x: CGFloat
        var y: CGFloat
        var size: CGFloat
    }

    static let plates: [Plate] = [
        Plate(x: 0.5, y: 0.34, size: 0.24),
        Plate(x: 0.27, y: 0.56, size: 0.2),
        Plate(x: 0.73, y: 0.56, size: 0.2),
        Plate(x: 0.5, y: 0.7, size: 0.18),
        Plate(x: 0.11, y: 0.78, size: 0.1),
        Plate(x: 0.89, y: 0.78, size: 0.1),
    ]
}

struct ShellDome: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY * 0.9))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.maxY * 0.9),
                      control1: CGPoint(x: rect.minX + rect.width * 0.02, y: rect.minY - rect.height * 0.15),
                      control2: CGPoint(x: rect.maxX - rect.width * 0.02, y: rect.minY - rect.height * 0.15))
        path.closeSubpath()
        return path
    }
}

struct Hexagon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        path.move(to: CGPoint(x: rect.minX + w * 0.25, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.75, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.75, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.25, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        _ = h
        return path
    }
}

/// 小熊猫双手捧着龟壳。`phase` 摇时左右晃，倒扣时龟壳翻过来往下一甩。
struct PandaWithShell: View {
    enum Phase: Equatable { case idle, shaking, pouring }

    var size: CGFloat
    var phase: Phase
    var shakes: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottom) {
            DivinationPanda(name: phase == .pouring ? "pet-panda-cheer" : "pet-panda-idle", size: size)
            TurtleShell(width: size * 0.62)
                .rotationEffect(.degrees(phase == .pouring && !reduceMotion ? 180 : 0))
                .offset(y: phase == .pouring && !reduceMotion ? -size * 0.02 : size * 0.02)
                .keyframeAnimator(initialValue: 0.0, trigger: reduceMotion ? 0 : shakes) { view, x in
                    view.offset(x: x * size * 0.06).rotationEffect(.degrees(x * 9))
                } keyframes: { _ in
                    KeyframeTrack {
                        CubicKeyframe(-1.0, duration: 0.1)
                        CubicKeyframe(1.0, duration: 0.16)
                        CubicKeyframe(-1.0, duration: 0.16)
                        CubicKeyframe(1.0, duration: 0.16)
                        CubicKeyframe(0.0, duration: 0.1)
                    }
                }
        }
        .frame(width: size, height: size * 1.04, alignment: .bottom)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: phase)
        .accessibilityHidden(true)
    }
}

// MARK: - 铜钱

/// 代码画的铜钱：外圆内方，金边。字面四个字（原创钱文「卜卦通宝」），背面两点星纹。
struct CoinView: View {
    /// true 是背面。
    var back: Bool
    var size: CGFloat

    /// 钱文按上下右左读成「卜卦通宝」（原创）；数组按上、右、下、左摆。
    private static let legend = ["卜", "通", "卦", "宝"]
    private static let places: [CGPoint] = [CGPoint(x: 0, y: -1), CGPoint(x: 1, y: 0),
                                            CGPoint(x: 0, y: 1), CGPoint(x: -1, y: 0)]

    var body: some View {
        ZStack {
            Circle().fill(DivinationStyle.gold)
            Circle().strokeBorder(DivinationStyle.goldDeep, lineWidth: max(1, size * 0.07))
            Circle().strokeBorder(DivinationStyle.goldDeep.opacity(0.55), lineWidth: max(0.6, size * 0.025))
                .padding(size * 0.13)
            RoundedRectangle(cornerRadius: size * 0.03)
                .fill(DivinationStyle.goldDeep)
                .frame(width: size * 0.26, height: size * 0.26)
            RoundedRectangle(cornerRadius: size * 0.02)
                .strokeBorder(DivinationStyle.goldLight, lineWidth: max(0.6, size * 0.03))
                .frame(width: size * 0.34, height: size * 0.34)
            if back {
                ForEach([CGFloat(-1), CGFloat(1)], id: \.self) { side in
                    Circle().fill(DivinationStyle.goldDeep)
                        .frame(width: size * 0.09, height: size * 0.09)
                        .offset(x: side * size * 0.29)
                }
            } else if size >= 26 {
                ForEach(0..<4, id: \.self) { i in
                    Text(verbatim: Self.legend[i])
                        .font(.system(size: size * 0.2, weight: .heavy))
                        .foregroundStyle(DivinationStyle.goldDeep)
                        .offset(x: Self.places[i].x * size * 0.29, y: Self.places[i].y * size * 0.29)
                }
            } else {
                ForEach(0..<4, id: \.self) { i in
                    Capsule().fill(DivinationStyle.goldDeep)
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

/// 三枚铜钱落桌：`drops` 每加一次，三枚按 Core 的错开时间从上面摔下来、弹两下停住。
/// 减少动态效果时直接停在桌上。
struct CoinRow: View {
    var faces: [Bool]?
    var size: CGFloat
    var drops: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: size * 0.35) {
            ForEach(0..<3, id: \.self) { i in
                let face = faces.map { $0[i] } ?? (i != 1)
                CoinView(back: face, size: size)
                    .opacity(faces == nil ? 0.55 : 1)
                    .keyframeAnimator(initialValue: CoinFall(), trigger: reduceMotion ? 0 : drops) { view, value in
                        view.offset(y: value.y * size).rotationEffect(.degrees(value.spin))
                            .opacity(value.opacity)
                    } keyframes: { _ in
                        let delay = DivinationSoundSynth.clinkOffsets[i]
                        KeyframeTrack(\.y) {
                            LinearKeyframe(-2.4, duration: 0.001)
                            LinearKeyframe(-2.4, duration: max(0.001, delay))
                            CubicKeyframe(0, duration: 0.2)
                            CubicKeyframe(-0.35, duration: 0.1)
                            CubicKeyframe(0, duration: 0.1)
                            CubicKeyframe(-0.1, duration: 0.06)
                            CubicKeyframe(0, duration: 0.06)
                        }
                        KeyframeTrack(\.spin) {
                            LinearKeyframe(-90, duration: 0.001)
                            LinearKeyframe(-90, duration: max(0.001, delay))
                            CubicKeyframe(0, duration: 0.3)
                        }
                        KeyframeTrack(\.opacity) {
                            LinearKeyframe(0, duration: 0.001)
                            LinearKeyframe(0, duration: max(0.001, delay))
                            LinearKeyframe(1, duration: 0.05)
                        }
                    }
            }
        }
        .frame(height: size)
    }
}

struct CoinFall {
    var y: Double = 0
    var spin: Double = 0
    var opacity: Double = 1
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

// MARK: - 书

/// 代码画的书：红封皮、两页米色纸、细横线、红书签带。`flips` 每加一次右页翻一下
/// （绕书脊转过去），减少动态效果时不翻。
struct OpenBook: View {
    var width: CGFloat
    var flips: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var height: CGFloat { width * 0.58 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // 封皮。
            RoundedRectangle(cornerRadius: width * 0.03, style: .continuous)
                .fill(DivinationStyle.cover)
                .frame(width: width, height: height * 0.94)
                .offset(y: height * 0.06)
            // 书签带。
            BookmarkRibbon()
                .fill(DivinationStyle.cover.opacity(0.95))
                .frame(width: width * 0.04, height: height * 0.14)
                .offset(x: width * 0.84, y: height * 0.94)
            HStack(spacing: 0) {
                page(left: true)
                page(left: false)
                    .keyframeAnimator(initialValue: 0.0, trigger: reduceMotion ? 0 : flips) { view, angle in
                        view.rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), anchor: .leading,
                                              perspective: 0.5)
                    } keyframes: { _ in
                        KeyframeTrack {
                            LinearKeyframe(0.0, duration: 0.001)
                            CubicKeyframe(-178.0, duration: 0.32)
                            LinearKeyframe(0.0, duration: 0.001)
                        }
                    }
            }
            .frame(width: width * 0.94, height: height * 0.9)
            .offset(x: width * 0.03, y: 0)
            // 书脊阴影。
            Rectangle()
                .fill(LinearGradient(colors: [DivinationStyle.paperShade.opacity(0), DivinationStyle.paperShade,
                                              DivinationStyle.paperShade.opacity(0)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: width * 0.05, height: height * 0.9)
                .offset(x: width * 0.475)
        }
        .frame(width: width, height: height + height * 0.1, alignment: .topLeading)
        .accessibilityHidden(true)
    }

    private func page(left: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            PageShape(left: left)
                .fill(DivinationStyle.paper)
            VStack(alignment: .leading, spacing: height * 0.11) {
                ForEach(0..<6, id: \.self) { i in
                    Capsule().fill(DivinationStyle.paperLine)
                        .frame(width: width * (i == 5 ? 0.2 : 0.34), height: 1)
                }
            }
            .padding(.top, height * 0.16)
            .padding(.leading, width * 0.06)
        }
        .frame(width: width * 0.47, height: height * 0.9)
    }
}

/// 一页纸：外侧上角往上翘一点。
struct PageShape: Shape {
    var left: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let lift = rect.height * 0.04
        if left {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + lift),
                              control: CGPoint(x: rect.midX, y: rect.minY - lift * 0.4))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - lift * 0.5))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY + lift))
            path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                              control: CGPoint(x: rect.midX, y: rect.minY - lift * 0.4))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - lift * 0.5))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}

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
