import AppKit
import SwiftUI

// MARK: - 钉在桌面 · 小游戏组 · 卜卦
//
// 卜卦钉在桌面（Core 的 `DesktopCardsDivinationPlan`）：
// 小 160×160：小熊猫抱签筒（抽过展签）、今日签级和签号、一句话白话，底下一行农历；没抽时一个「摇一摇」直接摇。
// 中 340×160：左边今日签（签级、签号、一句话白话、一行宜忌；没抽时宜忌加「摇一摇」），
// 右边起卦（一次起完）：起卦小场景（卦画叠在右上角），下面卦名；
// 白话不占一行，鼠标停在卦名那一行时自己画一个浮层写完整白话（桌面卡片窗口不激活，系统的
// `.help` 悬停提示可能不弹），腾出的高度让小熊猫和左边签那只一样大。左边签场景按右边起卦场景的
// 脚底线加高（Core 的 `mediumStickSceneHeight`），两只小熊猫脚底在同一条线上。
// 大 340×340：上面今日签（签级、签号、签题，签诗前两句，一句话白话，农历和宜忌），下面起卦，多一行卦辞，
// 底下留出「仅供娱乐」的余量。
// 起卦小场景和面板同一套五拍、同样的时长和声音（ShellTossScene + DivinationPlay.performToss，
// 按「一次起完」的节奏）：捧龟甲 → 摇几下 → 跳起举高 → 一摔、铜钱蹦出 → 捡回，铜钱留在地上
// 显示最后一爻；按卡片缩小（Core 的 `DesktopCardsDivinationPlan.castLayout`），铜钱在小熊猫右边
// 排成一排小号的。
// 小熊猫和面板是同一套整身姿势图（DivinationScenes）。和扩展栏卡片、面板读写同一份卡片配置
// （DivinationPlay），三边同时变。卡片底是桌面卡片自己的液态玻璃，这里只画内容。
// 减少动态效果时不摇不飞不摔，直接换图、出结果。

@MainActor
extension DesktopCardsGames {
    /// 不是卜卦返回 nil，交给下一组。
    static func divinationView(for widget: WidgetInstance, size: DesktopPinSize, now: Date) -> AnyView? {
        guard DesktopCardsDivinationPlan.handles(widget.kind) else { return nil }
        return AnyView(DeskDivinationCard(widget: widget, size: size, now: now))
    }
}

private struct DeskDivinationCard: View {
    var widget: WidgetInstance
    var size: DesktopPinSize
    var now: Date

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shakes = 0
    @State private var busy = false
    @State private var tossCount = 0
    @State private var castBusy = false

    private var inset: CGFloat { CGFloat(DesktopCardsDivinationPlan.inset(size)) }
    private var drawn: Int? { Divination.todayStick(widget.config, now: now) }
    private var today: Int? { busy ? nil : drawn }

    var body: some View {
        Group {
            switch size {
            case .small: small
            case .medium: medium
            case .large: large
            }
        }
        .padding(inset)
        .frame(width: size.size.width, height: size.size.height, alignment: .top)
        // 签筒、铜钱皮肤（Pro）和面板同一个入口。
        .divinationSkins(widget.config)
    }

    // MARK: 签

    /// 小号、中号签场景下面那几行。抽过：签级加签号一行、一句话白话（中号再加一行宜忌，小号再加农历）；
    /// 没抽：小号一行提示加「摇一摇」再加农历，中号一行宜忌加「摇一摇」。
    @ViewBuilder private func stickSummary(medium: Bool) -> some View {
        let spacing = CGFloat(DesktopCardsDivinationPlan.summaryLineSpacing)
        VStack(spacing: spacing) {
            if let index = today {
                let stick = FortuneStick.all[index]
                levelRow(stick, index: index, levelSize: medium ? 15 : 20)
                Text(verbatim: stick.localizedShort)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.panelPrimary)
                    .lineLimit(1)
                    .fixedSize()
                if medium {
                    DivinationYiJiLine(date: now, attempts: [(1, 1), (1, 0)])
                } else {
                    lunarLine
                }
            } else {
                if medium {
                    DivinationYiJiLine(date: now, attempts: [(1, 1), (1, 0)])
                } else {
                    Text(tr("今天还没抽签"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.panelPrimary)
                        .lineLimit(1)
                }
                DivinationPrimaryButton(title: tr("摇一摇"), height: 28, enabled: !busy) { shake() }
                if !medium { lunarLine }
            }
        }
    }

    /// 签级（宋体）加签号一行。
    private func levelRow(_ stick: FortuneStick, index: Int, levelSize: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(verbatim: stick.level.title)
                .font(.custom("Songti SC", size: levelSize).weight(.heavy))
                .foregroundStyle(DivinationStyle.level(stick.level))
                .fixedSize()
            Text(verbatim: Divination.shortStickNumber(index))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.panelSecondary)
                .fixedSize()
        }
        .lineLimit(1)
    }

    /// 今天的农历（九月廿一；英文 Lunar 9/21）。
    private var lunarLine: some View {
        Text(verbatim: ChineseAlmanac.day(now).shortLunar(english: L10n.isEnglish))
            .font(.system(size: 13))
            .foregroundStyle(Color.panelTertiary)
            .lineLimit(1)
            .fixedSize()
    }

    private func shake() {
        guard !busy, Divination.todayStick(widget.config, now: Date()) == nil else { return }
        if reduceMotion {
            DivinationPlay.drawStick(in: widget)
            DivinationPlay.play(.tick, for: widget)
            return
        }
        busy = true
        shakes += 1
        DivinationPlay.play(.rattle, for: widget)
        let timing = StickShake.normal
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(timing.flyStart))
            DivinationPlay.drawStick(in: widget)
            DivinationPlay.play(.tick, for: widget)
            try? await Task.sleep(for: .seconds(timing.total - timing.flyStart))
            busy = false
        }
    }

    // MARK: 起卦

    /// 桌面卡片没有问题输入框，问题为空。面板里摇到一半的那一卦不续用：总是丢掉它、
    /// 重新一次起完六爻（DivinationPlay.castFresh），面板之后显示的是这一卦。
    /// 自己在摇，或面板正在给同一个小组件摇卦（`DivinationTossLock`）：按钮变灰，免得两边写回互相盖掉。
    private var castLocked: Bool { castBusy || DivinationTossLock.shared.isBusy(widget.id) }

    private func cast() {
        guard !castLocked else { return }
        if reduceMotion {
            DivinationPlay.castFresh(in: widget, question: "")
            DivinationPlay.play(.clink, for: widget)
            return
        }
        guard DivinationTossLock.shared.begin(widget.id) else { return }
        castBusy = true
        tossCount += 1
        let id = widget.id
        Task { @MainActor in
            await DivinationPlay.performToss(in: widget, question: "", all: true, fresh: true)
            DivinationTossLock.shared.end(id)
            castBusy = false
        }
    }

    /// 最近一次起好的卦（摇到一半的不算）。
    private var latest: Casting? {
        let current = Divination.casting(widget.config)
        if current.isComplete { return current }
        return Divination.history(widget.config).first
    }

    /// 起卦块：上面一行是起卦小场景和本卦 → 变卦卦画（中号叠在场景右上角），下面卦名、（大号）卦辞
    /// 和白话，最底下按钮。中号不写白话，悬停起卦区提示完整白话。
    /// 还没起过卦时小熊猫捧着龟甲、铜钱淡淡摆着，下面一行提示。
    @ViewBuilder private func castingBlock(showJudgment: Bool) -> some View {
        if let layout = DesktopCardsDivinationPlan.castLayout(size) {
            let casting = latest
            let gap = CGFloat(DesktopCardsDivinationPlan.castSpacing(size))
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: gap) {
                    let scene = ShellTossScene(layout: layout, faces: casting?.tosses.last,
                                               throwCount: tossCount, fast: true, tossed: casting != nil)
                    if let rect = DesktopCardsDivinationPlan.figuresOverScene(size) {
                        // 中号：场景占左边，卦画叠在右上角（铜钱那排在卦画下面、脚底那条线上）。
                        ZStack(alignment: .topLeading) {
                            scene
                            if let casting, let primary = casting.primary {
                                figures(casting, primary: primary)
                                    .frame(width: CGFloat(rect.width), alignment: .leading)
                                    .offset(x: CGFloat(rect.x), y: CGFloat(rect.y))
                            }
                        }
                        .frame(width: CGFloat(DesktopCardsDivinationPlan.castBlockWidth(size)),
                               height: CGFloat(layout.sceneHeight), alignment: .topLeading)
                    } else {
                        HStack(alignment: .center, spacing: CGFloat(DesktopCardsDivinationPlan.castRowSpacing(size))) {
                            scene
                            if let casting, let primary = casting.primary {
                                // 大号卦名放在卦画下面（这一行有 186 宽）。
                                VStack(alignment: .leading, spacing: 4) {
                                    figures(casting, primary: primary)
                                    if nameBeside { name(casting, primary: primary) }
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    if let casting, let primary = casting.primary {
                        if !nameBeside {
                            name(casting, primary: primary)
                                .deskHoverNote(hoverNote(casting), width: blockWidth, enabled: !castBusy)
                        }
                        if showJudgment {
                            Text(verbatim: "\(primary.name)：\(primary.judgment)")
                                .font(.custom("Songti SC", size: 13).weight(.semibold))
                                .foregroundStyle(DivinationStyle.red)
                                .lineLimit(2)
                        }
                        if DesktopCardsDivinationPlan.showsPlain(size) {
                            Text(verbatim: primary.plain)
                                .font(.system(size: 13))
                                .foregroundStyle(Color.panelSecondary)
                                .lineLimit(2)
                        }
                    } else if DesktopCardsDivinationPlan.showsPlain(size) {
                        Text(tr("想好问题，摇六次成一卦"))
                            .font(.system(size: 13))
                            .foregroundStyle(Color.panelSecondary)
                            .lineLimit(2)
                    } else {
                        // 中号只有卦名那一行的高度：短提示一行，完整的放在悬停浮层里。
                        Text(tr("想好问题再起卦"))
                            .font(.system(size: 13))
                            .foregroundStyle(Color.panelSecondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .deskHoverNote(hoverNote(nil), width: blockWidth, enabled: !castBusy)
                    }
                }
                Spacer(minLength: gap)
                DivinationPrimaryButton(title: casting == nil ? tr("起卦") : tr("再起一卦"), height: 28,
                                        enabled: !castLocked) { cast() }
            }
        }
    }

    private var blockWidth: CGFloat { CGFloat(DesktopCardsDivinationPlan.castBlockWidth(size)) }

    /// 卦名那一行的悬停浮层：中号起过卦时是卦名和完整白话，没起过是完整的「想好问题，摇六次成一卦」；
    /// 大号这些都写在卡片上，没有浮层。
    private func hoverNote(_ casting: Casting?) -> String? {
        if DesktopCardsDivinationPlan.showsPlain(size) { return nil }
        guard let casting, let primary = casting.primary else { return tr("想好问题，摇六次成一卦") }
        let title = casting.changed.map { "\(primary.name) → \($0.name)" } ?? primary.fullName
        return "\(title)：\(primary.plain)"
    }

    private var nameBeside: Bool { DesktopCardsDivinationPlan.nameBesideFigures(size) }

    private func name(_ casting: Casting, primary: Hexagram) -> some View {
        HStack(spacing: 4) {
            Text(verbatim: casting.changed.map { "\(primary.name) → \($0.name)" } ?? primary.fullName)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(Color.panelPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.87)
            if !nameBeside {
                // 中号卡片上不写白话：卦名后面一个小气泡，告诉人停在这一行能看完整白话。
                Image(systemName: "text.bubble")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.panelTertiary)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
            }
        }
    }

    /// 本卦（标出变爻）→ 变卦（淡色）两张卦画。
    private func figures(_ casting: Casting, primary: Hexagram) -> some View {
        let width = CGFloat(DesktopCardsDivinationPlan.figureWidth(size))
        let line = CGFloat(DesktopCardsDivinationPlan.figureLineHeight(size))
        let spacing = CGFloat(DesktopCardsDivinationPlan.figureLineSpacing(size))
        return HStack(spacing: CGFloat(DesktopCardsDivinationPlan.figureGap(size))) {
            HexagramFigure(yang: primary.yang, changing: Set(casting.changingIndices),
                           width: width, lineHeight: line, spacing: spacing)
            if let changed = casting.changed {
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.panelSecondary)
                    .frame(width: CGFloat(DesktopCardsDivinationPlan.arrowWidth))
                HexagramFigure(yang: changed.yang, faded: true, width: width, lineHeight: line, spacing: spacing)
            }
        }
        .fixedSize()
    }

    // MARK: 小号

    private var small: some View {
        VStack(spacing: 2) {
            stickScene(width: 140, poseHeight: CGFloat(DesktopCardsDivinationPlan.smallPoseHeight))
            stickSummary(medium: false)
            Spacer(minLength: 0)
        }
    }

    // MARK: 中号

    private var medium: some View {
        HStack(alignment: .top, spacing: CGFloat(DesktopCardsDivinationPlan.mediumSpacing)) {
            // 签场景按右边起卦场景的脚底线加高（80，脚底在 76），两只小熊猫脚底对齐；场景底下的 4pt
            // 本来就是留给影子的，下面签号、签级紧挨着放。
            VStack(spacing: CGFloat(DesktopCardsDivinationPlan.mediumStickSummarySpacing)) {
                stickScene(width: CGFloat(DesktopCardsDivinationPlan.mediumStickWidth),
                           poseHeight: CGFloat(DesktopCardsDivinationPlan.mediumStickPoseHeight),
                           height: CGFloat(DesktopCardsDivinationPlan.mediumStickSceneHeight))
                stickSummary(medium: true)
                Spacer(minLength: 0)
            }
            .frame(width: CGFloat(DesktopCardsDivinationPlan.mediumStickWidth))
            castingBlock(showJudgment: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: 大号

    private var large: some View {
        // 340 高去掉上下 12 的边距只有 316：小熊猫压到 72、间距 8，右边签那列四行（Core 的
        // largeStickTextHeight），卦辞两行加白话两行以后底下还有几 pt，「仅供娱乐」不贴底、不被按钮挤掉。
        VStack(spacing: CGFloat(DesktopCardsDivinationPlan.largeSpacing)) {
            HStack(alignment: .center, spacing: 12) {
                stickScene(width: 72, poseHeight: CGFloat(DesktopCardsDivinationPlan.largePoseHeight))
                // 签级、签号、签题一行，签诗前两句一行，一句话白话一行，农历和宜忌一行（放不下逐个减）。
                VStack(alignment: .leading, spacing: CGFloat(DesktopCardsDivinationPlan.summaryLineSpacing)) {
                    if let index = today {
                        let stick = FortuneStick.all[index]
                        // 签题跟在签级签号后面：放不下时写到行尾加省略号（英文签题最长三十多个字母），
                        // 不再整段藏掉；13pt 不缩字，签级签号不让位（Core 的 largeTitleMinWidth 守住余量）。
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            levelRow(stick, index: index, levelSize: 20)
                                .layoutPriority(1)
                            Text(verbatim: stick.localizedTitle)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(DivinationStyle.goldText)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .accessibilityLabel(Text(verbatim: stick.localizedTitle))
                        }
                        Text(verbatim: stick.poem.prefix(2).joined(separator: "，") + "。")
                            .font(.custom("Songti SC", size: 13))
                            .foregroundStyle(Color.panelPrimary)
                            .lineLimit(1)
                            .fixedSize()
                        Text(verbatim: stick.localizedShort)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.panelSecondary)
                            .lineLimit(1)
                            .fixedSize()
                    } else {
                        Text(tr("今天还没抽签"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.panelPrimary)
                            .lineLimit(1)
                        DivinationPrimaryButton(title: tr("摇一摇"), height: 28, enabled: !busy) { shake() }
                    }
                    DivinationYiJiLine(date: now, showsLunar: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Rectangle().fill(DivinationStyle.gold.opacity(0.6)).frame(height: 1)
            castingBlock(showJudgment: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Text(tr("仅供娱乐"))
                .font(.system(size: CGFloat(Divination.disclaimerFont)))
                .foregroundStyle(Color.panelTertiary)
                .lineLimit(1)
                .fixedSize()
                .padding(.bottom, 2)
        }
    }

    /// 签的小场景：没抽时抱签筒，摇的时候整张图摆、签飞出，抽过展签（纸太小不写字）。
    /// 脚底在场景底边往上 4pt；`height` 不给时场景正好是小熊猫加 4。
    private func stickScene(width: CGFloat, poseHeight: CGFloat, height: CGFloat? = nil) -> some View {
        DivinationStickScene(width: width, height: height ?? poseHeight + 4, poseHeight: poseHeight,
                             index: drawn, shakes: shakes)
    }
}

// MARK: - 悬停浮层

/// 鼠标停在这一行时自己画的浮层：桌面卡片的窗口不激活（码头不抢前台），系统的 `.help` 悬停提示
/// 在 App 不在前台时可能不弹；卡片自己的悬停（`onHover`，卡片右上角的操作条也靠它）照常有。
/// 浮层和起卦块一样宽，从这一行的底边往上长，最多 `hoverNoteMaxLines` 行，不接点击；
/// 起卦动画进行中不出。
private struct DeskHoverNote: ViewModifier {
    var text: String?
    var width: CGFloat
    var enabled: Bool

    @State private var hovering = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .contentShape(.rect)
            .onHover { hovering = $0 }
            .overlay(alignment: .bottomLeading) {
                if hovering, enabled, let text {
                    note(text)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.12), value: hovering && enabled)
            .accessibilityHint(text ?? "")
    }

    private func note(_ text: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let padding = CGFloat(DesktopCardsDivinationPlan.hoverNotePadding)
        return Text(verbatim: text)
            .font(.system(size: 13))
            .foregroundStyle(Color.panelPrimary)
            .lineLimit(DesktopCardsDivinationPlan.hoverNoteMaxLines)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, padding)
            .padding(.vertical, 6)
            .frame(width: width, alignment: .leading)
            .background {
                if reduceTransparency {
                    shape.fill(Color.panelDynamic(dark: NSColor(white: 0.16, alpha: 1), light: NSColor(white: 0.97, alpha: 1)))
                } else {
                    // 液态玻璃上再垫一层，字压在小熊猫和铜钱上面也看得清。
                    shape.fill(Color.panelDynamic(dark: NSColor.black.withAlphaComponent(0.5),
                                                  light: NSColor.white.withAlphaComponent(0.75)))
                        .background(Color.clear.glassEffect(.regular, in: shape))
                }
            }
            .overlay(shape.strokeBorder(Color.panelStroke, lineWidth: 0.5))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private extension View {
    func deskHoverNote(_ text: String?, width: CGFloat, enabled: Bool) -> some View {
        modifier(DeskHoverNote(text: text, width: width, enabled: enabled))
    }
}
