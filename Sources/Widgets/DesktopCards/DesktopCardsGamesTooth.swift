import SwiftUI

// MARK: - 钉在桌面 · 小游戏组 · 拔牙
//
// 拔牙钉在桌面时三档都能直接玩，河马按卡片大小缩放（Core 的 `DesktopCardsToothPlan`）：
// 小 160×160 顶上一行重开、已拔几颗和最高连拔，下面河马（下排牙点击区约 14×27pt）；
// 中 340×160 左边河马、右边名字、状态、大数字、重开和音效；大 340×340 顶上一行读数，
// 下面整只大河马，合嘴时冒「啊呜！」。和扩展栏卡片、面板读写同一份卡片配置（ToothPlay），
// 三边同时变。卡片底是桌面卡片自己的液态玻璃，这里只画内容。重开键放在左边：悬停时
// 右上角会浮出桌面卡片的操作条。

@MainActor
extension DesktopCardsGames {
    /// 不是拔牙返回 nil，交给下一组。
    static func toothView(for widget: WidgetInstance, size: DesktopPinSize, now: Date) -> AnyView? {
        guard DesktopCardsToothPlan.handles(widget.kind) else { return nil }
        return AnyView(DeskPullToothCard(widget: widget, size: size))
    }
}

private struct DeskPullToothCard: View {
    var widget: WidgetInstance
    var size: DesktopPinSize

    private var inset: CGFloat { CGFloat(DesktopCardsToothPlan.inset(size)) }

    var body: some View {
        let game = PullTooth.game(widget.config)
        let layout = DesktopCardsToothPlan.layout(for: size)
        Group {
            switch size {
            case .small: small(game, layout: layout)
            case .medium: medium(game, layout: layout)
            case .large: large(game, layout: layout)
            }
        }
        .padding(inset)
        .frame(width: size.size.width, height: size.size.height, alignment: .top)
    }

    private func hippo(_ game: ToothGame, layout: ToothLayout, ouch: Bool = false) -> some View {
        HippoArt(game: game, layout: layout, interactive: true,
                 onPull: { index in _ = ToothPlay.pull(index, in: widget) }, showsOuch: ouch)
            .frame(width: CGFloat(layout.width), height: CGFloat(layout.height))
    }

    /// 「5/11」：已拔几颗用强调色。
    private func count(_ game: ToothGame, size font: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(verbatim: "\(game.pulledCount)")
                .font(.system(size: font, weight: .bold, design: .rounded))
                .foregroundStyle(ToothStyle.accent)
                .monospacedDigit()
            Text(verbatim: "/\(game.maxPulls)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.panelTertiary)
                .monospacedDigit()
        }
        .lineLimit(1)
        .help(tr("这局已拔"))
    }

    private var best: some View {
        HStack(spacing: 3) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.panelSecondary)
            Text(verbatim: "\(PullTooth.best(widget.config))")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.panelPrimary)
                .monospacedDigit()
        }
        .lineLimit(1)
        .help(tr("最高连拔"))
    }

    private func restart(_ diameter: CGFloat) -> some View {
        ToothRoundButton(symbol: "arrow.counterclockwise", diameter: diameter, help: tr("重开一局")) {
            ToothPlay.restart(in: widget)
        }
    }

    private func sound(_ diameter: CGFloat) -> some View {
        let on = PullTooth.soundOn(widget.config)
        return ToothRoundButton(symbol: on ? "speaker.wave.2.fill" : "speaker.slash.fill", diameter: diameter,
                                help: on ? tr("音效：开") : tr("音效：关")) {
            ToothPlay.toggleSound(in: widget)
        }
    }

    // MARK: 小号

    private func small(_ game: ToothGame, layout: ToothLayout) -> some View {
        VStack(spacing: CGFloat(DesktopCardsToothPlan.headerSpacing(size))) {
            HStack(spacing: 6) {
                restart(18)
                count(game, size: 15)
                Spacer(minLength: 0)
                best
            }
            .frame(height: CGFloat(DesktopCardsToothPlan.headerHeight(size)))
            hippo(game, layout: layout)
        }
    }

    // MARK: 中号

    private func medium(_ game: ToothGame, layout: ToothLayout) -> some View {
        HStack(alignment: .top, spacing: CGFloat(DesktopCardsToothPlan.mediumSpacing)) {
            hippo(game, layout: layout)
            VStack(alignment: .leading, spacing: 4) {
                Text(PullTooth.animalName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.panelPrimary)
                    .lineLimit(1)
                Text(PullTooth.statusLine(game))
                    .font(.system(size: 13))
                    .foregroundStyle(game.status == .bitten ? ToothStyle.ouchText
                                     : (game.status == .won ? ToothStyle.winText : Color.panelSecondary))
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                count(game, size: 28)
                HStack(spacing: 6) {
                    restart(26)
                    sound(26)
                    Spacer(minLength: 0)
                    best
                }
            }
            .frame(width: CGFloat(DesktopCardsToothPlan.mediumSideWidth))
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: 大号

    private func large(_ game: ToothGame, layout: ToothLayout) -> some View {
        VStack(spacing: CGFloat(DesktopCardsToothPlan.headerSpacing(size))) {
            HStack(spacing: 8) {
                restart(28)
                sound(28)
                count(game, size: 22)
                Spacer(minLength: 0)
                Text(PullTooth.recordLine(best: PullTooth.best(widget.config), wins: PullTooth.wins(widget.config)))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.panelSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(height: CGFloat(DesktopCardsToothPlan.headerHeight(size)))
            hippo(game, layout: layout, ouch: true)
                .frame(maxWidth: .infinity)
        }
    }
}
