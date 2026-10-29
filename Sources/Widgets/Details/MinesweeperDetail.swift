import SwiftUI

// MARK: - 扫雷 · 面板
//
// 液态玻璃面板 340 宽：顶上小熊猫、名字和一句状态，右边重开；下面初级 / 中级两段，
// 每段写各自的最佳成绩；再下面剩余雷数、难度和计时；然后是棋盘（两个难度一样宽，
// 换难度面板不跳，宽度按卡片真实内容宽 `Minesweeper.panelBoardWidth` 算，左右边距
// 和其他面板一样）；棋盘下面一条可展开的排行榜（当前难度前 5 名，刚进榜那行高亮，
// 默认收起，这一局进榜时自动展开）；最后一行操作提示。
// 左键揭开，右键、⌥ 点或 ⌃ 点插旗，点数字揭开周围（和弦）。剩余雷数是最大的读数；
// 读数行右端是音效开关（喇叭，存卡片配置，默认开）。踩雷时小熊猫换成小骷髅并抖一下。
// 每个难度各存一局，换难度不丢另一局；排行榜存在卡片配置（Minesweeper.topKey，
// 第一名同时写进 bestKey）。
// 不铺背景色、不发光，颜色只在旗子、数字和结果上。

struct MinesweeperDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var level: MineLevel { context.isPreview ? .beginner : Minesweeper.level(instance.config) }

    private var board: MineBoard {
        context.isPreview ? MineSamples.board : Minesweeper.board(instance.config, level: level)
    }

    private static let boardSide = CGFloat(Minesweeper.panelBoardWidth)

    /// 排行榜展开着。默认收起，面板不高；这一局刚进榜时自动展开。
    @State private var showsBoard = false

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
                leaderboard(board, level: level)
                Text(tr("左键揭开，右键或按住 ⌥ 点插旗，点数字揭开周围"))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.panelTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
        }
        .onChange(of: rank(board, level: level)) { _, rank in
            if rank != nil { withAnimation(.snappy(duration: 0.25)) { showsBoard = true } }
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
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            restartButton(over: board.isOver, level: level)
                .fixedSize()
        }
    }

    private func statusText(_ board: MineBoard, level: MineLevel) -> String {
        let now = context.isPreview ? MineSamples.now : Date().timeIntervalSince1970
        guard board.status == .won else { return Minesweeper.statusLine(board, now: now) }
        return Minesweeper.wonLine(seconds: board.displaySeconds(now: now), rank: rank(board, level: level))
    }

    /// 刚赢的这局在排行榜上第几名（按赢下的时间认那一局；平了的排在原来那条后面）。
    private func rank(_ board: MineBoard, level: MineLevel) -> Int? {
        context.isPreview ? nil : Minesweeper.rank(board, level: level, in: instance.config)
    }

    private func statusColor(_ board: MineBoard) -> Color {
        switch board.status {
        case .won: MineStyle.winText
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
            .foregroundStyle(over ? MineStyle.flagInk : Color.panelPrimary)
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

    // MARK: 排行榜

    /// 一条可展开的玻璃小区块：标题行（奖杯、「排行榜」、第一名用时、箭头），展开后是
    /// 前 5 名（名次、用时、日期），这一局刚进榜的那行小熊猫橙描边高亮、写「本局」。
    private func leaderboard(_ board: MineBoard, level: MineLevel) -> some View {
        let scores = context.isPreview ? [] : Minesweeper.leaderboard(instance.config, level: level)
        let mine = rank(board, level: level)
        return VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.snappy(duration: 0.25)) { showsBoard.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MineStyle.flag)
                    Text(tr("排行榜"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.panelPrimary)
                    Text(level.title)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.panelTertiary)
                    Spacer(minLength: 6)
                    if !showsBoard, let first = scores.first {
                        Text(Minesweeper.scoreText(first.seconds))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.panelSecondary)
                            .monospacedDigit()
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.panelTertiary)
                        .rotationEffect(.degrees(showsBoard ? 180 : 0))
                }
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(showsBoard ? tr("收起排行榜") : tr("展开排行榜"))
            .accessibilityAddTraits(showsBoard ? .isSelected : [])

            if showsBoard {
                Group {
                    if scores.isEmpty {
                        Text(tr("还没有成绩"))
                            .font(.system(size: 13))
                            .foregroundStyle(Color.panelTertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 2) {
                            ForEach(Array(scores.enumerated()), id: \.offset) { index, score in
                                scoreRow(score, rank: index + 1, highlighted: mine == index + 1)
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.panelFill))
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
    }

    private func scoreRow(_ score: MineScore, rank: Int, highlighted: Bool) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: "\(rank)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(rank == 1 ? MineStyle.flagInk : Color.panelSecondary)
                .frame(width: 22, height: 22)
                .background {
                    if rank == 1 { Circle().fill(Color(hex: ShelfColor.redPanda.hex)) }
                }
            Text(Minesweeper.scoreText(score.seconds))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.panelPrimary)
                .monospacedDigit()
            if highlighted {
                Text(tr("本局"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: ShelfColor.redPanda.hex).panelReadable)
            }
            Spacer(minLength: 6)
            Text(dateText(score))
                .font(.system(size: 13))
                .foregroundStyle(Color.panelTertiary)
                .monospacedDigit()
        }
        .lineLimit(1)
        .padding(.horizontal, 6)
        .frame(height: 30)
        .background {
            if highlighted {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.panelRaised).panelLift()
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(MineStyle.flag, lineWidth: 1.5)
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("第 \(rank) 名 · \(Minesweeper.scoreText(score.seconds)) · \(dateText(score))"))
    }

    /// 「10月29日」；不是今年的带上年份；旧配置迁移来、不知道哪天的写「早前」。
    private func dateText(_ score: MineScore) -> String {
        guard score.hasDate else { return tr("早前") }
        let date = Date(timeIntervalSince1970: score.date)
        let sameYear = Calendar.current.isDate(date, equalTo: Date(), toGranularity: .year)
        let style = Date.FormatStyle(locale: L10n.interfaceLocale)
        return sameYear ? date.formatted(style.month(.abbreviated).day())
                        : date.formatted(style.year().month(.abbreviated).day())
    }

    // MARK: 读数

    /// 剩余雷数最大最醒目（24pt 粗圆体，橙 / 绿 / 红三档），中间难度，右边计时和音效开关。
    private func counters(_ board: MineBoard, level: MineLevel, now: Double) -> some View {
        HStack(spacing: 6) {
            MineCountReadout(minesLeft: board.minesLeft, size: 24)
            Spacer(minLength: 4)
            Text(level.detail)
                .font(.system(size: 13))
                .foregroundStyle(Color.panelTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
            Spacer(minLength: 4)
            MineReadout(symbol: "timer", value: "\(board.displaySeconds(now: now))",
                        tint: board.status == .won ? MineStyle.win : nil, size: 15)
                .fixedSize()
                .help(tr("用时（秒）"))
            MineSoundToggle(on: context.isPreview || Minesweeper.soundOn(instance.config), diameter: 28) {
                guard !context.isPreview else { return }
                MinePlay.toggleSound(in: instance)
            }
        }
        .padding(.leading, 4)
    }
}
