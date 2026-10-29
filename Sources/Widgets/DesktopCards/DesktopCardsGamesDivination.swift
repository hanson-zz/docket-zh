import SwiftUI

// MARK: - 钉在桌面 · 小游戏组 · 卜卦
//
// 卜卦钉在桌面（Core 的 `DesktopCardsDivinationPlan`）：
// 小 160×160：小熊猫抱签筒、今日签级和签号；没抽时一个「摇一摇」直接摇。
// 中 340×160：左边今日签，右边起卦（一次起完）：本卦和变卦卦画、卦名、白话。
// 大 340×340：上面今日签和签诗，下面起卦，多一行卦辞。
// 和扩展栏卡片、面板读写同一份卡片配置（DivinationPlay），三边同时变。卡片底是桌面卡片
// 自己的液态玻璃，这里只画内容。减少动态效果时签筒不抖、龟壳不晃。

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
    @State private var shellShakes = 0
    @State private var castBusy = false

    private var inset: CGFloat { CGFloat(DesktopCardsDivinationPlan.inset(size)) }
    private var today: Int? { busy ? nil : Divination.todayStick(widget.config, now: now) }

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
    }

    // MARK: 签

    private func stickSummary(compact: Bool) -> some View {
        VStack(spacing: compact ? 2 : 4) {
            if let index = today {
                let stick = FortuneStick.all[index]
                Text(verbatim: Divination.stickNumber(index))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.panelSecondary)
                Text(verbatim: stick.level.title)
                    .font(.custom("Songti SC", size: compact ? 24 : 28).weight(.heavy))
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
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(860))
            DivinationPlay.play(.tick, for: widget)
            DivinationPlay.drawStick(in: widget)
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
        shellShakes += 1
        DivinationPlay.play(.jingle, for: widget)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(560))
            DivinationSoundPlayer.stop(.jingle)
            DivinationPlay.toss(in: widget, question: "", all: true)
            DivinationPlay.play(.clink, for: widget)
            castBusy = false
        }
    }

    /// 最近一次起好的卦（摇到一半的不算）。
    private var latest: Casting? {
        let current = Divination.casting(widget.config)
        if current.isComplete { return current }
        return Divination.history(widget.config).first
    }

    private func castingBlock(showJudgment: Bool) -> some View {
        let casting = latest
        return VStack(alignment: .leading, spacing: 6) {
            if let casting, let primary = casting.primary {
                HStack(spacing: 8) {
                    HexagramFigure(yang: primary.yang, changing: Set(casting.changingIndices),
                                   width: 30, lineHeight: 5, spacing: 3)
                    if let changed = casting.changed {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.panelSecondary)
                        HexagramFigure(yang: changed.yang, faded: true, width: 30, lineHeight: 5, spacing: 3)
                    }
                    Spacer(minLength: 0)
                }
                Text(verbatim: casting.changed.map { "\(primary.name) → \($0.name)" } ?? primary.fullName)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Color.panelPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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
                HStack {
                    PandaWithShell(size: 58, phase: castBusy ? .shaking : .idle, shakes: shellShakes)
                    Spacer(minLength: 0)
                }
                Text(tr("想好问题，摇六次成一卦"))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.panelSecondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            DivinationPrimaryButton(title: latest == nil ? tr("起卦") : tr("再起一卦"), height: 28,
                                    enabled: !castBusy) { cast() }
        }
    }

    // MARK: 小号

    private var small: some View {
        VStack(spacing: 4) {
            PandaWithTube(size: 70, shakes: shakes, drop: false, cheering: today != nil)
            stickSummary(compact: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: 中号

    private var medium: some View {
        HStack(alignment: .top, spacing: CGFloat(DesktopCardsDivinationPlan.mediumSpacing)) {
            VStack(spacing: 4) {
                PandaWithTube(size: 64, shakes: shakes, drop: false, cheering: today != nil)
                stickSummary(compact: true)
                Spacer(minLength: 0)
            }
            .frame(width: CGFloat(DesktopCardsDivinationPlan.mediumStickWidth))
            castingBlock(showJudgment: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: 大号

    private var large: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                PandaWithTube(size: 80, shakes: shakes, drop: false, cheering: today != nil)
                VStack(alignment: .leading, spacing: 4) {
                    stickSummary(compact: false)
                    if let index = today {
                        Text(verbatim: FortuneStick.all[index].poemLines.prefix(2).joined())
                            .font(.custom("Songti SC", size: 13))
                            .foregroundStyle(Color.panelPrimary)
                            .lineLimit(2)
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
        }
    }
}
