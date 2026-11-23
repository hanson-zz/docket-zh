import SwiftUI

// MARK: - 柴犬翻翻乐 · 面板
//
// 液态玻璃，浅色、深色两版跟随系统。面板 340 宽，里面按卡片真实内容宽（ShibaMatch.panelContentWidth，
// 266）排：顶上柴犬小头、「柴犬翻翻乐」和副标题（未开始 / 进行中 · 已配对 3/6 / 完成 · 14 步），
// 右边重新开始和音效两个圆形玻璃键；中间 3 行 4 列的牌（行列来自 `ShibaBoardSpec`，以后换规格
// 不用改这里）；底部左边趴着的柴犬（自己占一列，不挡牌、不拦点击），右边「用时」「步数」「最佳」
// 三个玻璃胶囊。全部配完时牌桌上盖一张玻璃结果卡：举爪的柴犬、步数和用时、是否新纪录、「再来一盘」。
// 面板底不铺固定深色：玻璃上一层很淡的暖橙到雾粉和几只很淡的爪印。高度不自己定，交给通用面板
// 容器（DetailPanelFit）。计时只在面板开着、这盘进行中时每秒走一次。

struct ShibaMatchDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 进行中点了一下重新开始：键变成对勾，副标题提示「再点一次重新开始」，3 秒后恢复。
    @State private var confirmingRestart = false

    private static let spec = ShibaBoardSpec.standard
    private static let layout = ShibaMatch.panelLayout(spec)

    private var game: ShibaMatchGame {
        context.isPreview ? ShibaSamples.game : ShibaMatch.game(instance.config, spec: Self.spec)
    }

    private var best: ShibaRecord? {
        context.isPreview ? ShibaRecord(moves: 9, seconds: 41, date: 0) : ShibaMatch.best(instance.config, spec: Self.spec)
    }

    private var soundOn: Bool { context.isPreview ? true : ShibaMatch.soundOn(instance.config) }

    private func isRecord(_ game: ShibaMatchGame) -> Bool {
        !context.isPreview && ShibaMatch.isRecord(game, in: instance.config)
    }

    var body: some View {
        let game = game
        let showsResult = game.isWon && !context.isPreview
        return DetailCard {
            ShibaWarmBackdrop()
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                header(game)
                ShibaBoardView(game: game, layout: Self.layout,
                               interactive: !context.isPreview && !game.isWon, keyboard: true,
                               onFlip: { index in ShibaPlay.flip(index, in: instance) })
                    .overlay {
                        if showsResult {
                            resultCard(game)
                                .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.opacity.combined(with: .scale(scale: 0.94)))
                        }
                    }
                    .frame(maxWidth: .infinity)
                footer(game)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.25), value: showsResult)
    }

    // MARK: 顶上

    private func header(_ game: ShibaMatchGame) -> some View {
        HStack(alignment: .center, spacing: 10) {
            ShibaArtImage(name: ShibaMatchArt.avatar)
                .padding(3)
                .frame(width: 42, height: 42)
                .background(Circle().fill(Color(hex: ShibaMatch.accentHex).opacity(0.18)))
                .overlay(Circle().strokeBorder(Color.panelStroke, lineWidth: 0.5))
            VStack(alignment: .leading, spacing: 2) {
                Text(ShibaMatch.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.panelPrimary)
                    .lineLimit(1)
                Text(subtitle(game))
                    .font(.system(size: 13, weight: confirmingRestart || game.isWon ? .semibold : .regular))
                    .foregroundStyle(subtitleColor(game))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            ShibaRestartButton(game: game, confirming: $confirmingRestart, diameter: 32) {
                guard !context.isPreview else { return }
                ShibaPlay.restart(in: instance)
            }
            ShibaGlassButton(symbol: soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill",
                             help: soundOn ? tr("音效：开") : tr("音效：关")) {
                guard !context.isPreview else { return }
                ShibaPlay.toggleSound(in: instance)
            }
        }
    }

    private func subtitle(_ game: ShibaMatchGame) -> String {
        if confirmingRestart { return tr("再点一次重新开始") }
        let line = ShibaMatch.statusLine(game)
        return isRecord(game) ? tr("\(line) · 新纪录") : line
    }

    private func subtitleColor(_ game: ShibaMatchGame) -> Color {
        if confirmingRestart { return ShibaStyle.accentText }
        return game.isWon ? ShibaStyle.winText : Color.panelSecondary
    }

    // MARK: 底部

    private func footer(_ game: ShibaMatchGame) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            ShibaArtImage(name: ShibaMatchArt.lying, alignment: .bottomLeading)
                .frame(width: CGFloat(ShibaMatch.panelLyingShibaWidth),
                       height: CGFloat(ShibaMatch.panelLyingShibaHeight), alignment: .bottomLeading)
                .allowsHitTesting(false)
            Spacer(minLength: 0)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    timePill(game)
                    movesPill(game)
                    bestPill(game)
                }
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 6) {
                        timePill(game)
                        movesPill(game)
                    }
                    bestPill(game)
                }
                VStack(alignment: .trailing, spacing: 6) {
                    timePill(game)
                    movesPill(game)
                    bestPill(game)
                }
            }
        }
        .frame(minHeight: CGFloat(ShibaMatch.panelLyingShibaHeight))
    }

    /// 用时只在进行中每秒刷新一次；没开始、完成后不动。
    private func timePill(_ game: ShibaMatchGame) -> some View {
        TimelineView(.periodic(from: .now, by: game.status == .playing ? 1 : 3600)) { timeline in
            let now = context.isPreview ? ShibaSamples.now : timeline.date.timeIntervalSince1970
            ShibaPill(symbol: "timer", text: ShibaMatch.timeText(game, now: now))
        }
    }

    private func movesPill(_ game: ShibaMatchGame) -> some View {
        ShibaPill(symbol: "hand.tap", text: ShibaMatch.movesText(game.moves))
            .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: game.moves)
    }

    private func bestPill(_ game: ShibaMatchGame) -> some View {
        ShibaPill(symbol: "trophy.fill", text: ShibaMatch.bestText(best), highlighted: isRecord(game))
            .help(ShibaMatch.bestDetail(best))
    }

    // MARK: 完成

    private func resultCard(_ game: ShibaMatchGame) -> some View {
        let record = isRecord(game)
        return VStack(spacing: 6) {
            ShibaArtImage(name: ShibaMatchArt.cheer)
                .frame(width: 76, height: 76)
            Text(ShibaMatch.resultTitle(newRecord: record))
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(record ? ShibaStyle.accentText : Color.panelPrimary)
            Text(ShibaMatch.resultDetail(game))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.panelSecondary)
                .monospacedDigit()
            if !record {
                Text(ShibaMatch.bestText(best))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.panelTertiary)
            }
            Button {
                ShibaPlay.restart(in: instance)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .bold))
                    Text(tr("再来一盘"))
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(ShibaStyle.accentInk)
                .padding(.horizontal, 14)
                .frame(minHeight: 28)
                .background(Capsule().fill(ShibaStyle.accentFill))
                .contentShape(.capsule)
                .fixedSize()
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .readableGlass(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.panelStroke, lineWidth: 0.5))
        .accessibilityElement(children: .contain)
    }
}

// MARK: - 小部件

/// 底部读数胶囊：图标加一行字，带字玻璃。`highlighted` 时（刚破纪录）字用柴犬橙。
struct ShibaPill: View {
    var symbol: String
    var text: String
    var highlighted = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(highlighted ? ShibaStyle.accentText : Color.panelSecondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(highlighted ? ShibaStyle.accentText : Color.panelPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 28)
        .fixedSize()
        .readableGlass(in: Capsule())
        .overlay(Capsule().strokeBorder(Color.panelStroke, lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }
}

/// 圆形玻璃按钮（重新开始、音效）：带字玻璃同款底，32pt 好点。
struct ShibaGlassButton: View {
    var symbol: String
    var diameter: CGFloat = 32
    var help: String
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: diameter * 0.42, weight: .semibold))
                .foregroundStyle(Color.panelPrimary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: diameter, height: diameter)
                .readableGlass(in: Circle())
                .overlay(Circle().fill(Color.panelPrimary.opacity(hovering ? 0.07 : 0)))
                .overlay(Circle().strokeBorder(Color.panelStroke, lineWidth: 0.5))
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

/// 重新开始键：没开始或已完成时一下就重开；进行中第一下变成对勾（「再点一次重新开始」），
/// 3 秒内再点才重开，过了恢复原样。
struct ShibaRestartButton: View {
    var game: ShibaMatchGame
    @Binding var confirming: Bool
    var diameter: CGFloat = 32
    var onRestart: () -> Void

    @State private var token = 0

    var body: some View {
        ShibaGlassButton(symbol: confirming ? "checkmark" : "arrow.counterclockwise", diameter: diameter,
                         help: confirming ? tr("再点一次重新开始") : tr("重新开始")) {
            tapped()
        }
        .onChange(of: game.status) { _, _ in confirming = false }
    }

    private func tapped() {
        if confirming || !ShibaMatch.restartNeedsConfirm(game) {
            confirming = false
            onRestart()
            return
        }
        confirming = true
        token += 1
        let mine = token
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(ShibaMatch.restartConfirmWindow))
            if token == mine { confirming = false }
        }
    }
}

// MARK: - 面板底

/// 玻璃上一层很淡的暖橙到雾粉（深色外观深一点），四周几只很淡的爪印。不铺实心底色。
struct ShibaWarmBackdrop: View {
    @Environment(\.colorScheme) private var scheme

    /// 爪印的位置（卡片宽高的比例）、大小和转角，固定不随机，重画时不跳。
    private static let paws: [(x: CGFloat, y: CGFloat, size: CGFloat, angle: Double)] = [
        (0.92, 0.08, 18, 18), (0.06, 0.42, 16, -16), (0.95, 0.62, 20, 12), (0.5, 0.97, 14, -24),
    ]

    var body: some View {
        let light = scheme == .light
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: light
                               ? [Color(hex: "#FFD9A8").opacity(0.22), Color(hex: "#F6CFE0").opacity(0.12)]
                               : [Color(hex: "#9A5420").opacity(0.24), Color(hex: "#5A3466").opacity(0.18)],
                               startPoint: .top, endPoint: .bottom)
                ForEach(Self.paws.indices, id: \.self) { i in
                    let paw = Self.paws[i]
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: paw.size))
                        .foregroundStyle(Color.panelPrimary.opacity(light ? 0.05 : 0.07))
                        .rotationEffect(.degrees(paw.angle))
                        .position(x: geo.size.width * paw.x, y: geo.size.height * paw.y)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
