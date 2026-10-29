import SwiftUI

// MARK: - 钉在桌面 · 小游戏组 · 卜卦
//
// 卜卦钉在桌面（Core 的 `DesktopCardsDivinationPlan`）：
// 小 160×160：小熊猫抱签筒（抽过展签）、今日签级和签号；没抽时一个「摇一摇」直接摇。
// 中 340×160：左边今日签，右边起卦（一次起完）：起卦小场景和本卦、变卦卦画一行，下面卦名、白话。
// 大 340×340：上面今日签和签诗，下面起卦，多一行卦辞，底下留出「仅供娱乐」的余量。
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

    private var stickSummary: some View {
        VStack(spacing: 2) {
            if let index = today {
                let stick = FortuneStick.all[index]
                Text(verbatim: Divination.stickNumber(index))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.panelSecondary)
                Text(verbatim: stick.level.title)
                    .font(.custom("Songti SC", size: 24).weight(.heavy))
                    .foregroundStyle(DivinationStyle.level(stick.level))
                    .lineLimit(1)
            } else {
                Text(tr("今天还没抽签"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.panelPrimary)
                    .lineLimit(1)
                DivinationPrimaryButton(title: tr("摇一摇"), height: 28, enabled: !busy) { shake() }
            }
        }
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

    private func cast() {
        guard !castBusy else { return }
        if reduceMotion {
            DivinationPlay.toss(in: widget, question: "", all: true)
            DivinationPlay.play(.clink, for: widget)
            return
        }
        castBusy = true
        tossCount += 1
        Task { @MainActor in
            await DivinationPlay.performToss(in: widget, question: "", all: true)
            castBusy = false
        }
    }

    /// 最近一次起好的卦（摇到一半的不算）。
    private var latest: Casting? {
        let current = Divination.casting(widget.config)
        if current.isComplete { return current }
        return Divination.history(widget.config).first
    }

    /// 起卦块：上面一行是起卦小场景和本卦 → 变卦卦画，下面卦名、（大号）卦辞、白话，最底下按钮。
    /// 还没起过卦时小熊猫捧着龟甲、铜钱淡淡摆着，下面一行提示。
    @ViewBuilder private func castingBlock(showJudgment: Bool) -> some View {
        if let layout = DesktopCardsDivinationPlan.castLayout(size) {
            let casting = latest
            let gap = CGFloat(DesktopCardsDivinationPlan.castSpacing(size))
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: gap) {
                    HStack(alignment: .center, spacing: CGFloat(DesktopCardsDivinationPlan.castRowSpacing(size))) {
                        ShellTossScene(layout: layout, faces: casting?.tosses.last, throwCount: tossCount, fast: true,
                                       tossed: casting != nil)
                        if let casting, let primary = casting.primary {
                            // 大号卦名放在卦画下面（这一行有 186 宽），中号放在下一行。
                            VStack(alignment: .leading, spacing: 4) {
                                figures(casting, primary: primary)
                                if nameBeside { name(casting, primary: primary) }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    if let casting, let primary = casting.primary {
                        if !nameBeside { name(casting, primary: primary) }
                        if showJudgment {
                            Text(verbatim: "\(primary.name)：\(primary.judgment)")
                                .font(.custom("Songti SC", size: 13).weight(.semibold))
                                .foregroundStyle(DivinationStyle.red)
                                .lineLimit(2)
                        }
                        Text(verbatim: primary.plain)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.panelSecondary)
                            .lineLimit(showJudgment ? 2 : 1)
                    } else {
                        Text(tr("想好问题，摇六次成一卦"))
                            .font(.system(size: 13))
                            .foregroundStyle(Color.panelSecondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: gap)
                DivinationPrimaryButton(title: casting == nil ? tr("起卦") : tr("再起一卦"), height: 28,
                                        enabled: !castBusy) { cast() }
            }
        }
    }

    private var nameBeside: Bool { DesktopCardsDivinationPlan.nameBesideFigures(size) }

    private func name(_ casting: Casting, primary: Hexagram) -> some View {
        Text(verbatim: casting.changed.map { "\(primary.name) → \($0.name)" } ?? primary.fullName)
            .font(.system(size: 15, weight: .heavy))
            .foregroundStyle(Color.panelPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.87)
    }

    /// 本卦（标出变爻）→ 变卦（淡色）两张卦画。
    private func figures(_ casting: Casting, primary: Hexagram) -> some View {
        let width = CGFloat(DesktopCardsDivinationPlan.figureWidth(size))
        let line = CGFloat(DesktopCardsDivinationPlan.figureLineHeight)
        let spacing = CGFloat(DesktopCardsDivinationPlan.figureLineSpacing)
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
        VStack(spacing: 4) {
            stickScene(width: 140, poseHeight: 70)
            stickSummary
            Spacer(minLength: 0)
        }
    }

    // MARK: 中号

    private var medium: some View {
        HStack(alignment: .top, spacing: CGFloat(DesktopCardsDivinationPlan.mediumSpacing)) {
            VStack(spacing: 4) {
                stickScene(width: CGFloat(DesktopCardsDivinationPlan.mediumStickWidth), poseHeight: 64)
                stickSummary
                Spacer(minLength: 0)
            }
            .frame(width: CGFloat(DesktopCardsDivinationPlan.mediumStickWidth))
            castingBlock(showJudgment: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: 大号

    private var large: some View {
        // 340 高去掉上下 12 的边距只有 316：小熊猫压到 72、间距 8、签级和签号并成一行，
        // 卦辞两行加白话两行以后底下还剩十几 pt，「仅供娱乐」不贴底、不被按钮挤掉。
        VStack(spacing: CGFloat(DesktopCardsDivinationPlan.largeSpacing)) {
            HStack(alignment: .center, spacing: 12) {
                stickScene(width: 72, poseHeight: CGFloat(DesktopCardsDivinationPlan.largePoseHeight))
                // 签级和签号排一行（原来上下两行加两行签诗比小熊猫高出一截，把下面整块往下挤）。
                VStack(alignment: .leading, spacing: 4) {
                    if let index = today {
                        let stick = FortuneStick.all[index]
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(verbatim: stick.level.title)
                                .font(.custom("Songti SC", size: 24).weight(.heavy))
                                .foregroundStyle(DivinationStyle.level(stick.level))
                                .lineLimit(1)
                                .fixedSize()
                            Text(verbatim: Divination.stickNumber(index))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.panelSecondary)
                                .lineLimit(1)
                        }
                        Text(verbatim: stick.poemLines.prefix(2).joined())
                            .font(.custom("Songti SC", size: 13))
                            .foregroundStyle(Color.panelPrimary)
                            .lineLimit(2)
                    } else {
                        stickSummary
                    }
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
    private func stickScene(width: CGFloat, poseHeight: CGFloat) -> some View {
        DivinationStickScene(width: width, height: poseHeight + 4, poseHeight: poseHeight,
                             index: drawn, shakes: shakes)
    }
}
