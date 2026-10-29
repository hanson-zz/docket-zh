import SwiftUI

// MARK: - 拔牙 · 面板
//
// 液态玻璃面板 340 宽（和同组的扫雷一样），里面的东西都按卡片真实内容宽
// （PullTooth.panelContentWidth，340 是 266）排，不会把整列撑宽、被面板裁掉右边。
// 顶上河马的名字和一句状态，右边音效开关和重开；下面大数字写这局已拔几颗（强调色，
// 浅色玻璃上过 4.5:1），右边最高连拔和赢了几局；再下面是河马，点牙拔；最后一行玩法。
// 不铺背景色、不发光，颜色只在河马、大数字和结果上。

struct PullToothDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var game: ToothGame {
        context.isPreview ? ToothSamples.game : PullTooth.game(instance.config)
    }

    private var best: Int { context.isPreview ? 7 : PullTooth.best(instance.config) }
    private var wins: Int { context.isPreview ? 2 : PullTooth.wins(instance.config) }
    private var soundOn: Bool { context.isPreview ? true : PullTooth.soundOn(instance.config) }

    private static let layout = ToothLayout(width: PullTooth.panelArtWidth)

    var body: some View {
        let game = game
        return DetailCard {
            Color.clear
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                header(game)
                score(game)
                HippoArt(game: game, layout: Self.layout, interactive: !context.isPreview,
                         onPull: { index in _ = ToothPlay.pull(index, in: instance) },
                         showsOuch: true)
                    .frame(width: CGFloat(Self.layout.width), height: CGFloat(Self.layout.height))
                    .frame(maxWidth: .infinity)
                Text(tr("点一颗牙拔下来，拔到疼牙河马就合嘴；其余的牙都拔光就赢"))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.panelTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: 顶上

    private func header(_ game: ToothGame) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(PullTooth.animalName)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.panelPrimary)
                    .lineLimit(1)
                Text(statusText(game))
                    .font(.system(size: 13, weight: game.isOver ? .semibold : .regular))
                    .foregroundStyle(statusColor(game))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ToothRoundButton(symbol: soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill",
                             diameter: 30, help: soundOn ? tr("音效：开") : tr("音效：关")) {
                guard !context.isPreview else { return }
                ToothPlay.toggleSound(in: instance)
            }
            restartButton(over: game.isOver)
        }
    }

    private func statusText(_ game: ToothGame) -> String {
        let line = PullTooth.statusLine(game)
        guard !context.isPreview, PullTooth.isRecord(game, in: instance.config) else { return line }
        return tr("\(line) · 新纪录")
    }

    private func statusColor(_ game: ToothGame) -> Color {
        switch game.status {
        case .won: ToothStyle.winText
        case .bitten: ToothStyle.ouchText
        case .ready, .playing: Color.panelSecondary
        }
    }

    /// 平时是圆形玻璃重开键；结束后换成写着「再来一局」的玻璃胶囊。
    @ViewBuilder private func restartButton(over: Bool) -> some View {
        if over {
            Button {
                guard !context.isPreview else { return }
                ToothPlay.restart(in: instance)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .bold))
                    Text(tr("再来一局"))
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(ToothStyle.accent)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Capsule().fill(Color.panelRaised).panelLift())
                .overlay(Capsule().strokeBorder(Color.panelStroke, lineWidth: 0.5))
                .contentShape(.capsule)
                .fixedSize()
            }
            .buttonStyle(.plain)
            .help(tr("重开一局"))
        } else {
            ToothRoundButton(symbol: "arrow.counterclockwise", diameter: 30, help: tr("重开一局")) {
                guard !context.isPreview else { return }
                ToothPlay.restart(in: instance)
            }
        }
    }

    // MARK: 大数字和纪录

    private func score(_ game: ToothGame) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(tr("这局已拔"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.panelSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: "\(game.pulledCount)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(ToothStyle.accent)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(tr("/ \(game.maxPulls) 颗"))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.panelTertiary)
                        .monospacedDigit()
                }
                .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.panelSecondary)
                    Text(tr("最高连拔"))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.panelSecondary)
                }
                Text(PullTooth.recordLine(best: best, wins: wins))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.panelPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .accessibilityElement(children: .combine)
            .padding(.bottom, 6)
        }
        .animation(.snappy(duration: 0.2), value: game.pulledCount)
    }
}
