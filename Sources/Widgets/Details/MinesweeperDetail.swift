import SwiftUI

// MARK: - 扫雷 · 面板
//
// 液态玻璃面板 340 宽：顶上小熊猫、名字和一句状态，右边重开；下面初级 / 中级两段，
// 每段写各自的最佳成绩；再下面剩余雷数、难度和计时；然后是棋盘（两个难度一样宽，
// 换难度面板不跳）。左键揭开，右键、⌥ 点或 ⌃ 点插旗，点数字揭开周围（和弦）。
// 每个难度各存一局，换难度不丢另一局；最佳成绩存在卡片配置（Minesweeper.bestKey）。
// 不铺背景色、不发光，颜色只在旗子、数字和结果上。

struct MinesweeperDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var level: MineLevel { context.isPreview ? .beginner : Minesweeper.level(instance.config) }

    private var board: MineBoard {
        context.isPreview ? MineSamples.board : Minesweeper.board(instance.config, level: level)
    }

    private static let boardSide = CGFloat(Minesweeper.panelBoardWidth)

    var body: some View {
        let board = board
        let level = level
        return DetailCard {
            Color.clear
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                header(board, level: level)
                picker(level)
                TimelineView(.periodic(from: .now, by: board.status == .playing ? 1 : 60)) { timeline in
                    counters(board, level: level, now: context.isPreview ? MineSamples.now : timeline.date.timeIntervalSince1970)
                }
                MineBoardView(board: board,
                              cell: CGFloat(Minesweeper.cellSize(columns: board.columns,
                                                                 side: Minesweeper.panelBoardWidth)),
                              interactive: !context.isPreview) { action, index in
                    _ = MinePlay.act(action, at: index, level: level, in: instance)
                }
                .frame(width: Self.boardSide, height: Self.boardSide)
                .frame(maxWidth: .infinity)
                Text(tr("左键揭开，右键或按住 ⌥ 点插旗，点数字揭开周围"))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.panelTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: 顶上

    private func header(_ board: MineBoard, level: MineLevel) -> some View {
        HStack(spacing: 10) {
            MinePanda(status: board.status, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("扫雷"))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.panelPrimary)
                Text(statusText(board, level: level))
                    .font(.system(size: 13, weight: board.isOver ? .semibold : .regular))
                    .foregroundStyle(statusColor(board))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
            Spacer(minLength: 8)
            restartButton(over: board.isOver, level: level)
        }
    }

    private func statusText(_ board: MineBoard, level: MineLevel) -> String {
        let now = context.isPreview ? MineSamples.now : Date().timeIntervalSince1970
        guard board.status == .won else { return Minesweeper.statusLine(board, now: now) }
        let seconds = board.displaySeconds(now: now)
        return isRecord(board, level: level) ? tr("赢了 · \(seconds) 秒 · 新纪录") : tr("赢了 · \(seconds) 秒")
    }

    /// 刚赢的这局就是最佳成绩（存的时候四舍五入到 0.1 秒）。
    private func isRecord(_ board: MineBoard, level: MineLevel) -> Bool {
        guard board.status == .won, let best = Minesweeper.best(instance.config, level: level) else { return false }
        let time = (board.elapsed(now: 0) * 10).rounded() / 10
        return abs(best - time) < 0.05
    }

    private func statusColor(_ board: MineBoard) -> Color {
        switch board.status {
        case .won: MineStyle.win
        case .lost: MineStyle.boom.panelReadable
        case .ready, .playing: Color.panelSecondary
        }
    }

    /// 平时是玻璃胶囊「重开」；结束后换成小熊猫橙的实心「再来一盘」。
    private func restartButton(over: Bool, level: MineLevel) -> some View {
        Button {
            guard !context.isPreview else { return }
            MinePlay.restart(level, in: instance)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 12, weight: .bold))
                Text(over ? tr("再来一盘") : tr("重开"))
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(over ? Color.white : Color.panelPrimary)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background {
                if over {
                    Capsule().fill(Color(hex: ShelfColor.redPanda.hex))
                } else {
                    Capsule().fill(Color.panelRaised).panelLift()
                }
            }
            .overlay { if !over { Capsule().strokeBorder(Color.panelStroke, lineWidth: 0.5) } }
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help(tr("重开一盘"))
    }

    // MARK: 难度

    private func picker(_ selected: MineLevel) -> some View {
        HStack(spacing: 4) {
            ForEach(MineLevel.allCases, id: \.self) { item in
                let on = item == selected
                Button {
                    guard !context.isPreview else { return }
                    withAnimation(.snappy(duration: 0.2)) { MinePlay.select(item, in: instance) }
                } label: {
                    VStack(spacing: 1) {
                        Text(item.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(on ? Color.panelPrimary : Color.panelSecondary)
                        Text(tr("最佳 \(Minesweeper.bestText(Minesweeper.best(instance.config, level: item)))"))
                            .font(.system(size: 13))
                            .foregroundStyle(Color.panelTertiary)
                            .monospacedDigit()
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background {
                        if on {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.panelRaised).panelLift()
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(item.detail)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.panelFill))
    }

    // MARK: 读数

    private func counters(_ board: MineBoard, level: MineLevel, now: Double) -> some View {
        HStack {
            MineReadout(symbol: "flag.fill", value: "\(board.minesLeft)", tint: MineStyle.flag, size: 15)
                .help(tr("剩余雷数"))
            Spacer(minLength: 8)
            Text(level.detail)
                .font(.system(size: 13))
                .foregroundStyle(Color.panelTertiary)
            Spacer(minLength: 8)
            MineReadout(symbol: "timer", value: "\(board.displaySeconds(now: now))",
                        tint: board.status == .won ? MineStyle.win : nil, size: 15)
                .help(tr("用时（秒）"))
        }
        .padding(.horizontal, 4)
    }
}
