import SwiftUI

// MARK: - 钉在桌面 · 小游戏组
//
// 扫雷钉在桌面时三档都能直接玩：小 160×160 和中 340×160 放初级（9×9），大 340×340 放
// 面板里选的难度。和扩展栏卡片、面板读写同一份卡片配置（MinePlay → WidgetWriter），
// 三边同时变。卡片底是桌面卡片自己的液态玻璃，这里只画内容，颜色用面板语义色。
// 重开键放在左边：悬停时右上角会浮出桌面卡片的操作条。每档格子多大在 Core 的
// `DesktopCardsGamesPlan`（小号 13pt、中号 14pt，大号初级 28pt、中级 16pt）。

@MainActor
enum DesktopCardsGames {
    /// 不是本组的小组件返回 nil，走原来的通用逻辑。
    static func view(for widget: WidgetInstance, size: DesktopPinSize, now: Date) -> AnyView? {
        guard DesktopCardsGamesPlan.handles(widget.kind) else { return nil }
        switch widget.kind {
        case .minesweeper: return AnyView(DeskMinesweeperCard(widget: widget, size: size))
        default: return nil
        }
    }
}

private struct DeskMinesweeperCard: View {
    var widget: WidgetInstance
    var size: DesktopPinSize

    private var level: MineLevel {
        DesktopCardsGamesPlan.level(for: size, chosen: Minesweeper.level(widget.config))
    }

    private var inset: CGFloat { CGFloat(DesktopCardsGamesPlan.inset(size)) }

    var body: some View {
        let level = level
        let board = Minesweeper.board(widget.config, level: level)
        let cell = CGFloat(DesktopCardsGamesPlan.cell(for: size, level: level))
        Group {
            switch size {
            case .small: small(board, level: level, cell: cell)
            case .medium: medium(board, level: level, cell: cell)
            case .large: large(board, level: level, cell: cell)
            }
        }
        .padding(inset)
        .frame(width: size.size.width, height: size.size.height, alignment: .top)
    }

    private func boardView(_ board: MineBoard, level: MineLevel, cell: CGFloat) -> some View {
        MineBoardView(board: board, cell: cell) { action, index in
            _ = MinePlay.act(action, at: index, level: level, in: widget)
        }
    }

    /// 剩余雷数和计时；进行中每秒走。
    private func readouts(_ board: MineBoard, size font: CGFloat) -> some View {
        TimelineView(.periodic(from: .now, by: board.status == .playing ? 1 : 60)) { timeline in
            HStack(spacing: 10) {
                MineReadout(symbol: "flag.fill", value: "\(board.minesLeft)", tint: MineStyle.flag, size: font)
                MineReadout(symbol: "timer", value: "\(board.displaySeconds(now: timeline.date.timeIntervalSince1970))",
                            tint: board.status == .won ? MineStyle.win : nil, size: font)
            }
        }
    }

    // MARK: 小号

    private func small(_ board: MineBoard, level: MineLevel, cell: CGFloat) -> some View {
        VStack(spacing: CGFloat(DesktopCardsGamesPlan.headerSpacing(size))) {
            HStack(spacing: 8) {
                MineRestartButton(diameter: 16) { MinePlay.restart(level, in: widget) }
                readouts(board, size: 13)
                Spacer(minLength: 0)
                if board.isOver { MinePanda(status: board.status, size: 16) }
            }
            .frame(height: CGFloat(DesktopCardsGamesPlan.headerHeight(size)))
            boardView(board, level: level, cell: cell)
        }
    }

    // MARK: 中号

    private func medium(_ board: MineBoard, level: MineLevel, cell: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 12) {
            boardView(board, level: level, cell: cell)
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("扫雷 · \(level.title)"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.panelPrimary)
                    .lineLimit(1)
                HStack(alignment: .top, spacing: 6) {
                    Text(Minesweeper.statusLine(board, now: Date().timeIntervalSince1970))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.panelSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if board.isOver { MinePanda(status: board.status, size: 30) }
                }
                Spacer(minLength: 0)
                readouts(board, size: 15)
                HStack(spacing: 8) {
                    MineRestartButton(diameter: 28) { MinePlay.restart(level, in: widget) }
                    Text(tr("最佳 \(Minesweeper.bestText(Minesweeper.best(widget.config, level: level)))"))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.panelTertiary)
                        .lineLimit(1)
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: 大号

    private func large(_ board: MineBoard, level: MineLevel, cell: CGFloat) -> some View {
        VStack(spacing: CGFloat(DesktopCardsGamesPlan.headerSpacing(size))) {
            HStack(spacing: 10) {
                MineRestartButton(diameter: 28) { MinePlay.restart(level, in: widget) }
                readouts(board, size: 15)
                Spacer(minLength: 0)
                Text(level.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.panelSecondary)
                MinePanda(status: board.status, size: 28)
            }
            .frame(height: CGFloat(DesktopCardsGamesPlan.headerHeight(size)))
            boardView(board, level: level, cell: cell)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
