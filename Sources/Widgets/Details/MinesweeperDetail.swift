import SwiftUI

// MARK: - 扫雷 · 面板
//
// 液态玻璃面板，按效果图精修（玩法不变）：
// - 顶上：小熊猫（六状态图：准备、游戏中待机，踩雷举爪提醒，赢了举爪庆祝）、「扫雷」和一行
//   副标题，右上小熊猫橙「再来一盘」胶囊。
// - 难度：一条分段条，初级 / 中级，只写名字；「9×9 · 10 雷」放在悬停提示和读屏里
//   （两段各 128 宽，带上它中级和英文会挤掉，两段写法不一致）。
// - 读数：「剩余 N 雷」（数字最大最醒目，橙 / 绿 / 红三档）、计时「00:05」，右边音效圆钮
//   （扫雷没有别的设置入口，不放齿轮）。
// - 棋盘：初级、中级在 340 宽的面板里一样宽（换难度不跳）。悬停的格子提亮并描一圈橙边，插旗时小旗轻弹一下，
//   踩到的那格红底。结束后棋盘上盖一张玻璃结果卡（小熊猫、一句话、「查看棋盘」「再来一盘」），
//   赢了冒一小把彩纸（只在刚赢时，减弱动态效果时不动）。
// - 本机纪录：默认折叠成一行「本机纪录 初级 · 最佳 00:28」，点开看前五，这一局刚进榜时自动展开。
// - 首次提示一行，玩完一局（赢或输）后不再显示（`Minesweeper.showsHint`）。
// 左键揭开，右键、⌥ 点或 ⌃ 点插旗，点数字揭开周围（和弦）。每个难度各存一局和本机纪录。
// 底是很淡的暖橙到雾紫，棋盘外两只低透明度爪印；棋盘后面不画炸弹、星星，不发光。
// 高度不自己定，交给通用面板容器（DetailPanelFit）。

struct MinesweeperDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var level: MineLevel { context.isPreview ? .beginner : Minesweeper.level(instance.config) }

    private var board: MineBoard {
        context.isPreview ? MineSamples.board : Minesweeper.board(instance.config, level: level)
    }

    /// 本机纪录展开着。默认收起；这一局刚进榜时自动展开。
    @State private var showsRecords = false
    /// 点了「查看棋盘」：结果卡收起，露出整盘。新开一局时复位。
    @State private var reviewing = false

    var body: some View {
        let board = board
        let level = level
        let side = CGFloat(Minesweeper.panelBoardWidth)
        let cell = CGFloat(Minesweeper.panelCell(for: level))
        let showsResult = board.isOver && !reviewing && !context.isPreview
        return DetailCard {
            MineWarmBackdrop()
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                header(board, level: level)
                picker(level)
                TimelineView(.periodic(from: .now, by: board.status == .playing ? 1 : 60)) { timeline in
                    counters(board, now: context.isPreview ? MineSamples.now : timeline.date.timeIntervalSince1970)
                }
                MineBoardView(board: board, cell: cell,
                              interactive: !context.isPreview && !showsResult) { action, index in
                    _ = MinePlay.act(action, at: index, level: level, in: instance)
                }
                .help(tr("左键揭开，右键或按住 ⌥ 点插旗，点数字揭开周围"))
                .frame(width: side, height: side)
                .overlay {
                    if showsResult {
                        resultCard(board, level: level, width: side)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
                .frame(maxWidth: .infinity)
                records(board, level: level)
                if !context.isPreview, Minesweeper.showsHint(instance.config) {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 13, weight: .medium))
                        Text(tr("左键揭开 · 右键插旗 · 找出所有安全格子"))
                            .font(.system(size: 13))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(Color.panelTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                }
            }
        }
        .animation(.snappy(duration: 0.22), value: showsResult)
        .onChange(of: rank(board, level: level)) { _, rank in
            if rank != nil { withAnimation(.snappy(duration: 0.25)) { showsRecords = true } }
        }
        .onChange(of: board.status) { _, status in
            if status == .ready || status == .playing { reviewing = false }
        }
        .onChange(of: level) { _, _ in reviewing = false }
    }

    // MARK: 顶上

    private func header(_ board: MineBoard, level: MineLevel) -> some View {
        HStack(alignment: .center, spacing: 10) {
            PandaStateView(Minesweeper.pandaState(board.status), size: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(tr("扫雷"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color.panelPrimary)
                Text(tr("找出所有地雷，挑战你的观察力！"))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.panelSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)
            .accessibilityElement(children: .combine)
            .accessibilityValue(statusText(board, level: level))
            Spacer(minLength: 6)
            MineOrangeButton(title: tr("再来一盘")) {
                guard !context.isPreview else { return }
                reviewing = false
                MinePlay.restart(level, in: instance)
            }
            .fixedSize()
            .help(tr("重开一盘"))
        }
    }

    private func statusText(_ board: MineBoard, level: MineLevel) -> String {
        let now = context.isPreview ? MineSamples.now : Date().timeIntervalSince1970
        guard board.status == .won else { return Minesweeper.statusLine(board, now: now) }
        return Minesweeper.wonLine(seconds: board.displaySeconds(now: now), rank: rank(board, level: level))
    }

    /// 刚赢的这局在本机纪录里第几名（按赢下的时间认那一局；平了的排在原来那条后面）。
    private func rank(_ board: MineBoard, level: MineLevel) -> Int? {
        context.isPreview ? nil : Minesweeper.rank(board, level: level, in: instance.config)
    }

    // MARK: 难度分段条

    private func picker(_ selected: MineLevel) -> some View {
        let count = CGFloat(MineLevel.allCases.count)
        let inner = CGFloat(Minesweeper.panelContentWidth) - 6
        let segment = max(40, ((inner - 3 * (count - 1)) / count).rounded(.down))
        return HStack(spacing: 3) {
            ForEach(MineLevel.allCases, id: \.self) { item in
                let on = item == selected
                Button {
                    guard !context.isPreview else { return }
                    withAnimation(.snappy(duration: 0.2)) { MinePlay.select(item, in: instance) }
                } label: {
                    segmentLabel(item, on: on)
                    .frame(width: segment, height: 30)
                    .background {
                        if on {
                            Capsule().fill(Color.clear)
                                .readableGlass(in: Capsule())
                                .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                        }
                    }
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .help(item.detail)
                .accessibilityLabel(item.title)
                .accessibilityValue(item.detail)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.panelFill))
    }

    private func segmentLabel(_ item: MineLevel, on: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(on ? MineStyle.flag : Color.panelTertiary)
            Text(item.title)
                .font(.system(size: 14, weight: on ? .bold : .semibold))
                .foregroundStyle(on ? Color.panelPrimary : Color.panelSecondary)
        }
        .lineLimit(1)
        .fixedSize()
    }

    // MARK: 读数

    /// 「剩余 10 雷」（数字 24pt 粗圆体，三档颜色）、计时「00:05」、音效圆钮。
    private func counters(_ board: MineBoard, now: Double) -> some View {
        let tone = MineCountTone(minesLeft: board.minesLeft)
        let color = MineStyle.count(tone)
        let parts = Minesweeper.minesLeftParts()
        return HStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: tone == .over ? "exclamationmark.triangle.fill" : "flag.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(color)
                if !parts.before.isEmpty {
                    Text(parts.before.trimmingCharacters(in: .whitespaces))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.panelSecondary)
                }
                Text(verbatim: Minesweeper.minesLeftText(board.minesLeft))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(board.minesLeft)))
                    .animation(.snappy(duration: 0.2), value: board.minesLeft)
                if !parts.after.isEmpty {
                    Text(parts.after.trimmingCharacters(in: .whitespaces))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.panelSecondary)
                }
            }
            .lineLimit(1)
            .fixedSize()
            .help(tone == .over ? tr("旗插多了：比雷还多 \(-board.minesLeft) 面") : tr("剩余雷数"))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tr("剩余雷数"))
            .accessibilityValue(Minesweeper.minesLeftText(board.minesLeft))
            Spacer(minLength: 6)
            HStack(spacing: 5) {
                Image(systemName: "stopwatch")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(board.status == .won ? MineStyle.win : Color.panelSecondary)
                Text(verbatim: Minesweeper.clockText(board, now: now))
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.panelPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .lineLimit(1)
            .fixedSize()
            .help(tr("用时"))
            Spacer(minLength: 6)
            MineSoundToggle(on: context.isPreview || Minesweeper.soundOn(instance.config), diameter: 30) {
                guard !context.isPreview else { return }
                MinePlay.toggleSound(in: instance)
            }
        }
        .padding(.leading, 4)
    }

    // MARK: 结果卡

    /// 盖在棋盘上的玻璃卡：小熊猫表情、一句话、「查看棋盘」「再来一盘」。
    private func resultCard(_ board: MineBoard, level: MineLevel, width: CGFloat) -> some View {
        let now = Date().timeIntervalSince1970
        let won = board.status == .won
        let fresh = won && (board.endedAt.map { now - $0 < 3 } ?? false)
        return VStack(spacing: 8) {
            ZStack {
                if won { MineConfetti(animated: fresh) }
                PandaStateView(Minesweeper.pandaState(board.status), size: 76)
            }
            .frame(height: 80)
            if let title = Minesweeper.resultTitle(board.status) {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(won ? MineStyle.winText : Color.panelPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let detail = Minesweeper.resultDetail(board, rank: rank(board, level: level), now: now) {
                Text(detail)
                    .font(.system(size: 13, weight: won ? .semibold : .regular))
                    .foregroundStyle(Color.panelSecondary)
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                MineGlassButton(title: tr("查看棋盘")) {
                    withAnimation(.snappy(duration: 0.22)) { reviewing = true }
                }
                MineOrangeButton(title: tr("再来一盘")) {
                    reviewing = false
                    MinePlay.restart(level, in: instance)
                }
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(width: min(width - 24, 280))
        .readableGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .accessibilityElement(children: .contain)
    }

    // MARK: 本机纪录

    /// 一条可展开的玻璃小区块：折叠时一行「本机纪录 初级 · 最佳 00:28」，展开后是前 5 名
    /// （名次、用时、日期），这一局刚进榜的那行小熊猫橙描边高亮、写「本局」。
    private func records(_ board: MineBoard, level: MineLevel) -> some View {
        let scores = context.isPreview ? [] : Minesweeper.leaderboard(instance.config, level: level)
        let mine = rank(board, level: level)
        return VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.snappy(duration: 0.25)) { showsRecords.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MineStyle.flag)
                    Text(tr("本机纪录"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.panelPrimary)
                        .layoutPriority(1)
                    Text(context.isPreview ? level.title : Minesweeper.recordSummary(instance.config, level: level))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.panelTertiary)
                        .monospacedDigit()
                        .truncationMode(.middle)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.panelTertiary)
                        .rotationEffect(.degrees(showsRecords ? 180 : 0))
                }
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(showsRecords ? tr("收起本机纪录") : tr("展开本机纪录"))
            .accessibilityAddTraits(showsRecords ? .isSelected : [])

            if showsRecords {
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
        .readableGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(.rect(cornerRadius: 14, style: .continuous))
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
}

// MARK: - 按钮

/// 小熊猫橙实心胶囊：逆时针箭头加字，字用按底色算出的深墨（白字在 #E8743B 上只有约 3:1）。
struct MineOrangeButton: View {
    var title: String
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 12, weight: .bold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .lineLimit(1)
            .foregroundStyle(MineStyle.flagInk)
            .padding(.horizontal, 13)
            .frame(height: 32)
            .background {
                Capsule().fill(Color(hex: ShelfColor.redPanda.hex))
                    .brightness(hovering ? 0.05 : 0)
            }
            .overlay { Capsule().strokeBorder(.white.opacity(0.28), lineWidth: 0.5) }
            .shadow(color: Color(hex: ShelfColor.redPanda.hex).opacity(0.25), radius: 4, y: 2)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// 带字的玻璃胶囊（结果卡上的「查看棋盘」）。
struct MineGlassButton: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.panelPrimary)
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .readableGlass(in: Capsule())
                .overlay { Capsule().strokeBorder(Color.panelStroke, lineWidth: 0.5) }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 彩纸

/// 赢了时小熊猫身边一小把彩纸（9 片，位置固定不随机）。刚赢时往下飘一下再淡出，只出现一次；
/// 减弱动态效果或不是刚赢时静止地停在原处。
struct MineConfetti: View {
    var animated: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fallen = false

    private static let pieces: [(x: CGFloat, y: CGFloat, w: CGFloat, angle: Double, hex: String)] = [
        (-62, -26, 8, 24, "#E8743B"), (-44, 6, 6, -30, "#7DB6FF"), (-70, 22, 6, 50, "#F4C542"),
        (58, -30, 8, -20, "#C9A4FF"), (70, 0, 6, 36, "#63D394"), (48, 26, 7, -48, "#FF7F75"),
        (-24, -36, 5, 12, "#63D394"), (28, -38, 6, -64, "#F4C542"), (0, -42, 5, 40, "#FF7F75"),
    ]

    var body: some View {
        let moving = animated && !reduceMotion
        ZStack {
            ForEach(Self.pieces.indices, id: \.self) { i in
                let piece = Self.pieces[i]
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color(hex: piece.hex))
                    .frame(width: piece.w, height: piece.w * 1.8)
                    .rotationEffect(.degrees(piece.angle + (fallen ? 90 : 0)))
                    .offset(x: piece.x, y: piece.y + (fallen ? 26 : 0))
                    .opacity(moving && fallen ? 0 : 0.9)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            guard moving else { return }
            withAnimation(.easeIn(duration: 1.4).delay(0.15)) { fallen = true }
        }
    }
}

// MARK: - 面板底

/// 玻璃上一层很淡的暖橙到雾紫，棋盘外两只低透明度爪印（右下、左上，落在卡片边距里）。
/// 不铺实心底色、不发光；「降低透明度」时卡片换实心底，这层照旧很淡。
struct MineWarmBackdrop: View {
    @Environment(\.colorScheme) private var scheme

    private static let paws: [(x: CGFloat, y: CGFloat, size: CGFloat, angle: Double)] = [
        (0.968, 0.86, 13, 18), (0.032, 0.30, 11, -16),
    ]

    var body: some View {
        let light = scheme == .light
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: light
                               ? [Color(hex: "#FFD7BF").opacity(0.24), Color(hex: "#DCD2F4").opacity(0.18)]
                               : [Color(hex: "#9A4E2A").opacity(0.2), Color(hex: "#4A3C82").opacity(0.2)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                ForEach(Self.paws.indices, id: \.self) { i in
                    let paw = Self.paws[i]
                    PawPrint()
                        .fill(Color.panelPrimary.opacity(light ? 0.06 : 0.08))
                        .frame(width: paw.size, height: paw.size)
                        .rotationEffect(.degrees(paw.angle))
                        .position(x: geo.size.width * paw.x, y: geo.size.height * paw.y)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
