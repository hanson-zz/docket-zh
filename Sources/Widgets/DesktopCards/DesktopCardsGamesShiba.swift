import SwiftUI

// MARK: - 钉在桌面 · 小游戏组 · 柴犬翻翻乐
//
// 小号 160×160 只显示状态：柴犬、未开始 / 进行中 / 完成、已配对几对和步数。中号 340×160 左边
// 3 行 4 列的牌能直接玩，右边名字、状态、步数、重新开始和音效；大号 340×340 顶上一行键和读数，
// 下面整块牌桌。每档多大在 Core 的 `DesktopCardsShibaPlan`，牌的点击区都至少 24pt。和面板读写
// 同一份卡片配置（ShibaPlay），两边同时变。桌面卡片上不放走秒的用时，不高频刷新。
// 卡片底是桌面卡片自己的液态玻璃，这里只画内容。重开键放在左边：悬停时右上角会浮出操作条。

@MainActor
extension DesktopCardsGames {
    /// 不是柴犬翻翻乐返回 nil，交给下一组。
    static func shibaView(for widget: WidgetInstance, size: DesktopPinSize, now: Date) -> AnyView? {
        guard DesktopCardsShibaPlan.handles(widget.kind) else { return nil }
        return AnyView(DeskShibaMatchCard(widget: widget, size: size))
    }
}

private struct DeskShibaMatchCard: View {
    var widget: WidgetInstance
    var size: DesktopPinSize

    @Environment(\.colorScheme) private var scheme
    @State private var confirmingRestart = false

    private var inset: CGFloat { CGFloat(DesktopCardsShibaPlan.inset(size)) }

    var body: some View {
        let game = ShibaMatch.game(widget.config)
        Group {
            if let layout = DesktopCardsShibaPlan.layout(for: size) {
                if size == .medium {
                    medium(game, layout: layout)
                } else {
                    large(game, layout: layout)
                }
            } else {
                small(game)
            }
        }
        .padding(inset)
        .frame(width: size.size.width, height: size.size.height, alignment: .top)
    }

    private func board(_ game: ShibaMatchGame, layout: ShibaBoardLayout) -> some View {
        ShibaBoardView(game: game, layout: layout, interactive: !game.isWon,
                       onFlip: { index in ShibaPlay.flip(index, in: widget) })
            .frame(width: CGFloat(layout.width), height: CGFloat(layout.height))
    }

    private func restart(_ diameter: CGFloat, game: ShibaMatchGame) -> some View {
        ShibaRestartButton(game: game, confirming: $confirmingRestart, diameter: diameter) {
            ShibaPlay.restart(in: widget)
        }
    }

    private func sound(_ diameter: CGFloat) -> some View {
        let on = ShibaMatch.soundOn(widget.config)
        return ShibaGlassButton(symbol: on ? "speaker.wave.2.fill" : "speaker.slash.fill", diameter: diameter,
                                help: on ? tr("音效：开") : tr("音效：关")) {
            ShibaPlay.toggleSound(in: widget)
        }
    }

    private func statusText(_ game: ShibaMatchGame) -> String {
        confirmingRestart ? tr("再点一次重新开始") : ShibaMatch.statusLine(game)
    }

    // MARK: 小号：只看状态

    private func small(_ game: ShibaMatchGame) -> some View {
        VStack(spacing: 4) {
            ShibaArtImage(name: ShibaMatchArt.tile(game.status))
                .frame(width: 64, height: 64)
            Text(ShibaMatch.statusWord(game))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.panelSecondary)
            Text(verbatim: ShibaMatch.progressText(game))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(ShibaStyle.accentText)
                .monospacedDigit()
            Text(ShibaMatch.movesText(game.moves))
                .font(.system(size: 13))
                .foregroundStyle(Color.panelTertiary)
                .monospacedDigit()
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("柴犬翻翻乐，\(ShibaMatch.statusLine(game))"))
    }

    // MARK: 中号

    private func medium(_ game: ShibaMatchGame, layout: ShibaBoardLayout) -> some View {
        HStack(alignment: .top, spacing: CGFloat(DesktopCardsShibaPlan.mediumSpacing)) {
            board(game, layout: layout)
            VStack(alignment: .leading, spacing: 4) {
                Text(ShibaMatch.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.panelPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(statusText(game))
                    .font(.system(size: 13))
                    .foregroundStyle(confirmingRestart ? ShibaStyle.accentText
                                     : (game.isWon ? ShibaStyle.winText : Color.panelSecondary))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(ShibaMatch.movesText(game.moves))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.panelPrimary)
                    .monospacedDigit()
                HStack(spacing: 6) {
                    restart(26, game: game)
                    sound(26)
                }
            }
            .frame(width: CGFloat(DesktopCardsShibaPlan.mediumSideWidth))
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: 大号

    private func large(_ game: ShibaMatchGame, layout: ShibaBoardLayout) -> some View {
        VStack(spacing: CGFloat(DesktopCardsShibaPlan.headerSpacing)) {
            HStack(spacing: 8) {
                restart(28, game: game)
                sound(28)
                Text(statusText(game))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(confirmingRestart ? ShibaStyle.accentText
                                     : (game.isWon ? ShibaStyle.winText : Color.panelSecondary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                Text(ShibaMatch.movesText(game.moves))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.panelPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .frame(height: CGFloat(DesktopCardsShibaPlan.headerHeight))
            board(game, layout: layout)
                .frame(maxWidth: .infinity)
        }
    }
}
