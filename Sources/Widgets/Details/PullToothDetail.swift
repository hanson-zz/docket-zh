import SwiftUI

// MARK: - 拔牙 · 面板
//
// 按效果图改版（液态玻璃，浅色、深色两版跟随系统）。面板 380 宽，里面的东西都按卡片真实
// 内容宽（PullTooth.panelContentWidth，380 是 306）排，不会把整列撑宽、被面板裁掉右边：
// 顶上牙齿徽章、「小熊猫圆圆」和一行副标题（没开局时是玩法，开局后是状态），右上音效和重开
// 两个圆形玻璃键；下面一条玻璃信息卡，左边「安全拔牙 N / 11」（大数字粉色，浅色下过 4.5:1），
// 竖分隔，右边奖杯「最高纪录 N 颗 · 赢 N 局」；中间是大大的小熊猫脸，张着嘴，牙画在嘴里，
// 每颗点击区至少 24pt；最底下一条玻璃提示条「点一颗牙，试试手气！ | 12 颗牙中有 1 颗疼牙」，
// 结束后左边换成「再来一局」。面板底不铺固定深色：玻璃上一层淡紫雾（深色下深一点，浅色下很浅）
// 和几只很淡的爪印。高度不自己定、不另套滚动，交给通用面板容器（DetailPanelFit）。

struct PullToothDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var game: ToothGame {
        context.isPreview ? ToothSamples.game : PullTooth.game(instance.config)
    }

    private var best: Int { context.isPreview ? 7 : PullTooth.best(instance.config) }
    private var wins: Int { context.isPreview ? 2 : PullTooth.wins(instance.config) }
    private var soundOn: Bool { context.isPreview ? true : PullTooth.soundOn(instance.config) }

    private static let layout = PullTooth.panelArtLayout

    var body: some View {
        let game = game
        return DetailCard {
            ToothMistBackdrop()
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                header(game)
                scoreCard(game)
                ToothPandaArt(game: game, layout: Self.layout, interactive: !context.isPreview,
                              onPull: { index in _ = ToothPlay.pull(index, in: instance) },
                              showsOuch: true, softEdges: true)
                    .frame(width: CGFloat(Self.layout.width), height: CGFloat(Self.layout.height))
                    .frame(maxWidth: .infinity)
                hintBar(game)
            }
        }
    }

    // MARK: 顶上

    private func header(_ game: ToothGame) -> some View {
        HStack(alignment: .center, spacing: 10) {
            ToothBadge(side: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(PullTooth.animalName)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color.panelPrimary)
                    .lineLimit(1)
                Text(subtitle(game))
                    .font(.system(size: 13, weight: game.isOver ? .semibold : .regular))
                    .foregroundStyle(subtitleColor(game))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ToothGlassButton(symbol: soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill",
                             help: soundOn ? tr("音效：开") : tr("音效：关")) {
                guard !context.isPreview else { return }
                ToothPlay.toggleSound(in: instance)
            }
            ToothGlassButton(symbol: "arrow.counterclockwise", help: tr("重开一局")) {
                guard !context.isPreview else { return }
                ToothPlay.restart(in: instance)
            }
        }
    }

    private func subtitle(_ game: ToothGame) -> String {
        let line = PullTooth.subtitle(game)
        guard !context.isPreview, PullTooth.isRecord(game, in: instance.config) else { return line }
        return tr("\(line) · 新纪录")
    }

    private func subtitleColor(_ game: ToothGame) -> Color {
        switch game.status {
        case .won: ToothStyle.winText
        case .bitten: ToothStyle.ouchText
        case .ready, .playing: Color.panelSecondary
        }
    }

    // MARK: 信息卡

    private func scoreCard(_ game: ToothGame) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(tr("安全拔牙"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.panelSecondary)
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: "\(game.pulledCount)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(ToothStyle.accent)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(verbatim: "/ \(game.maxPulls)")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.panelTertiary)
                        .monospacedDigit()
                }
                .lineLimit(1)
            }
            .frame(width: 104, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tr("安全拔牙"))
            .accessibilityValue(Text(verbatim: "\(game.pulledCount) / \(game.maxPulls)"))

            Rectangle()
                .fill(Color.panelSeparator)
                .frame(width: 0.5, height: 40)

            HStack(spacing: 8) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ToothStyle.trophy)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.panelFill))
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("最高纪录"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.panelSecondary)
                        .lineLimit(1)
                    Text(PullTooth.recordValue(best: best, wins: wins))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.panelPrimary)
                        .monospacedDigit()
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.leading, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .readableGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.panelStroke, lineWidth: 0.5))
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: game.pulledCount)
    }

    // MARK: 底部提示条

    /// 一行放得下就左右两段加竖分隔；放不下（英文、大字号）就上下两行。
    private func hintBar(_ game: ToothGame) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                hintLeft(game)
                Rectangle().fill(Color.panelSeparator).frame(width: 0.5, height: 16)
                ruleText
            }
            .fixedSize()
            .frame(maxWidth: .infinity)
            VStack(spacing: 6) {
                hintLeft(game)
                ruleText
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 40)
        .readableGlass(in: Capsule())
        .overlay(Capsule().strokeBorder(Color.panelStroke, lineWidth: 0.5))
    }

    @ViewBuilder private func hintLeft(_ game: ToothGame) -> some View {
        if game.isOver {
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
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(minHeight: 26)
                .background(Capsule().fill(ToothStyle.accentFill))
                .contentShape(.capsule)
                .fixedSize()
            }
            .buttonStyle(.plain)
            .help(tr("重开一局"))
        } else {
            HStack(spacing: 5) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ToothStyle.accent)
                    .accessibilityHidden(true)
                Text(PullTooth.hintLine(game))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.panelPrimary)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
        }
    }

    private var ruleText: some View {
        HStack(spacing: 5) {
            Image(systemName: "bolt.heart.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ToothStyle.ouchText)
                .accessibilityHidden(true)
            Text(PullTooth.ruleLine())
                .font(.system(size: 13))
                .foregroundStyle(Color.panelSecondary)
                .lineLimit(1)
        }
    }
}

// MARK: - 面板底

/// 玻璃上一层淡紫雾：深色外观深一点的紫到梅，浅色外观很浅的薰衣草到粉；小熊猫身后一团更亮的光，
/// 四周几只很淡的爪印。不铺实心底色，玻璃仍透出身后；「降低透明度」时由卡片换成实心底，这层照旧很淡。
struct ToothMistBackdrop: View {
    @Environment(\.colorScheme) private var scheme

    /// 爪印的位置（卡片宽高的比例）、大小和转角，固定不随机，重画时不跳。
    private static let paws: [(x: CGFloat, y: CGFloat, size: CGFloat, angle: Double)] = [
        (0.07, 0.30, 26, -18), (0.93, 0.36, 22, 16), (0.10, 0.70, 20, 12),
        (0.90, 0.74, 26, -14), (0.80, 0.22, 16, 24), (0.18, 0.52, 14, -30),
    ]

    var body: some View {
        let light = scheme == .light
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: light
                               ? [Color(hex: "#C9B8F2").opacity(0.22), Color(hex: "#F3C6DE").opacity(0.14)]
                               : [Color(hex: "#5B3FA8").opacity(0.32), Color(hex: "#8E3F86").opacity(0.2)],
                               startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [(light ? Color(hex: "#E4D9FF") : Color(hex: "#7C5CD6"))
                                            .opacity(light ? 0.45 : 0.3), .clear],
                               center: UnitPoint(x: 0.5, y: 0.58), startRadius: 0,
                               endRadius: max(geo.size.width, 1) * 0.62)
                ForEach(Self.paws.indices, id: \.self) { i in
                    let paw = Self.paws[i]
                    PawPrint()
                        .fill(Color.panelPrimary.opacity(light ? 0.05 : 0.07))
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

/// 一只爪印：一个大肉垫加四个小趾垫。
struct PawPrint: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        path.addEllipse(in: CGRect(x: rect.minX + w * 0.24, y: rect.minY + h * 0.44, width: w * 0.52, height: h * 0.44))
        let toes: [(CGFloat, CGFloat)] = [(0.08, 0.3), (0.28, 0.1), (0.52, 0.1), (0.72, 0.3)]
        for (x, y) in toes {
            path.addEllipse(in: CGRect(x: rect.minX + w * x, y: rect.minY + h * y, width: w * 0.2, height: h * 0.24))
        }
        return path
    }
}

// MARK: - 头部小部件

/// 头部的牙齿徽章：粉色圆角方块里一颗白色大牙。
struct ToothBadge: View {
    var side: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: side * 0.3, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: PullTooth.accentHex), ToothStyle.accentFill],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                MolarShape()
                    .fill(.white)
                    .frame(width: side * 0.56, height: side * 0.58)
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
            }
            .overlay(RoundedRectangle(cornerRadius: side * 0.3, style: .continuous)
                .strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}

/// 一颗大牙（臼齿）：圆鼓鼓的牙冠，下面两条牙根。
struct MolarShape: Shape {
    func path(in r: CGRect) -> Path {
        let w = r.width, h = r.height, x = r.minX, y = r.minY
        func p(_ a: CGFloat, _ b: CGFloat) -> CGPoint { CGPoint(x: x + w * a, y: y + h * b) }
        var path = Path()
        path.move(to: p(0.5, 0.12))
        path.addCurve(to: p(0.08, 0.18), control1: p(0.35, 0), control2: p(0.16, 0.02))
        path.addCurve(to: p(0.2, 0.92), control1: p(-0.02, 0.42), control2: p(0.1, 0.7))
        path.addCurve(to: p(0.38, 0.86), control1: p(0.26, 1.04), control2: p(0.34, 0.98))
        path.addCurve(to: p(0.62, 0.86), control1: p(0.42, 0.62), control2: p(0.58, 0.62))
        path.addCurve(to: p(0.8, 0.92), control1: p(0.66, 0.98), control2: p(0.74, 1.04))
        path.addCurve(to: p(0.92, 0.18), control1: p(0.9, 0.7), control2: p(1.02, 0.42))
        path.addCurve(to: p(0.5, 0.12), control1: p(0.84, 0.02), control2: p(0.65, 0))
        path.closeSubpath()
        return path
    }
}

/// 圆形玻璃按钮（面板头部的音效、重开）：带字玻璃同款底（readableGlass），32pt 好点。
struct ToothGlassButton: View {
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
