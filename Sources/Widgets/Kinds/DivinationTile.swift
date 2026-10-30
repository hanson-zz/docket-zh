import AppKit
import SwiftUI

// MARK: - 卜卦 · 扩展栏卡片
//
// 扩展栏卡片 188×62（竖排 76×120）：小熊猫、今日签级和签号；没抽时写「今天还没抽签」。
// 点卡片打开面板（每日一签 / 起卦 / 解忧书三页）。规则和存法都在 Core 的 `Divination`。
// 小熊猫是 Resources/Divination 里的整身姿势图（没抽时抱签筒，抽过展签），三个玩法的场景在
// DivinationScenes。这里还放共用的卦画、按钮、颜色，以及写回配置和放音效的 DivinationPlay。

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
            // 抱签筒那张图按卡片选的签筒皮肤盖色（Pro）。
            .divinationSkins(instance.config, isPreview: context.isPreview)
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
        if level == .middle {
            return Color(hex: scheme == .dark ? Divination.goldTextDarkHex : Divination.goldTextLightHex)
        }
        return WidgetStyle.primary
    }

    // MARK: 横排

    private func row(_ index: Int?) -> some View {
        HStack(spacing: 8) {
            DivinationPoseImage(pose: index == nil ? .qianShake : .qianRead, height: 46)
                .frame(width: 40, height: 46)
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
            DivinationPoseImage(pose: index == nil ? .qianShake : .qianRead, height: 50)
                .frame(width: 44, height: 50)
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

    /// 桌面卡片起卦：丢掉面板里摇到一半的那一卦，重新一次起完六爻（Core 的 `castFresh`）。
    @discardableResult
    static func castFresh(in instance: WidgetInstance, question: String) -> Casting {
        var result = Casting()
        write(instance) { config in
            var rng = SystemRandomNumberGenerator()
            result = Divination.castFresh(in: &config, question: question,
                                          now: Date().timeIntervalSince1970, using: &rng)
        }
        return result
    }

    /// 起卦动画期间的声音和写回，面板和桌面卡片同一套时间（Core 的 `ShellToss`）：开始摇时放叮当、
    /// 跳起来时停，一摔触地时记下这一爻，第一枚铜钱落地时放三声落地声，抱回龟甲后返回。
    /// `fresh`（桌面卡片）：触地时不续面板摇到一半的那一卦，重新起一个完整的新卦；节奏按一次起完。
    static func performToss(in instance: WidgetInstance, question: String, all: Bool,
                            fresh: Bool = false) async {
        let timing = ShellToss.timing(fast: all)
        try? await Task.sleep(for: .seconds(timing.shakeStart))
        play(.jingle, for: instance)
        try? await Task.sleep(for: .seconds(timing.liftStart - timing.shakeStart))
        DivinationSoundPlayer.stop(.jingle)
        try? await Task.sleep(for: .seconds(timing.impact - timing.liftStart))
        if fresh {
            castFresh(in: instance, question: question)
        } else {
            toss(in: instance, question: question, all: all)
        }
        try? await Task.sleep(for: .seconds(timing.clinkStart - timing.impact))
        play(.clink, for: instance)
        try? await Task.sleep(for: .seconds(timing.total - timing.clinkStart))
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

    /// 金色点缀（装饰线、光点），不当正文。
    static let gold = Color(hex: Divination.goldHex)

    /// 金色当字用。
    static var goldText: Color {
        Color.panelDynamic(dark: NSColor(Color(hex: Divination.goldTextDarkHex)),
                           light: NSColor(Color(hex: Divination.goldTextLightHex)))
    }

    /// 签级的字色：上签喜庆红，中签金，其余主文字色。
    static func level(_ level: StickLevel) -> Color {
        if level.isFestive { return red }
        if level == .middle { return goldText }
        return Color.panelPrimary
    }

    /// 卦画：本卦主文字色，变卦淡一档。
    static var line: Color { Color.panelPrimary }
    static var lineFaded: Color { Color.panelTertiary }

    /// 飞出来的签条的红签头。
    static let stickTip = Color(hex: "#D23A2E")

    /// 地面阴影线、落地影子：深色玻璃上压得重一点才看得见。
    static var groundShade: Color {
        Color.panelDynamic(dark: NSColor.black.withAlphaComponent(0.4), light: NSColor.black.withAlphaComponent(0.13))
    }
    static var dust: Color {
        Color.panelDynamic(dark: NSColor(Color(hex: "#AA967A")), light: NSColor(Color(hex: "#C4AA82")))
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
