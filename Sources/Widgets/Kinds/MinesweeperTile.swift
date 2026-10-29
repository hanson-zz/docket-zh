import AppKit
import SwiftUI

// MARK: - 扫雷 · 扩展栏卡片
//
// 扩展栏卡片只有 58pt 高，9×9 的格子放进去每格不到 5pt，点不准，所以卡片上是这一局的
// 缩略图、剩余雷数、计时和重开键，点卡片打开面板玩；能直接点着玩的是面板和桌面卡片
// （小 160×160、中 340×160 放初级，大 340×340 放面板里选的难度，见 DesktopCardsGames）。
// 规则和存法都在 Core 的 `Minesweeper`。

struct MinesweeperTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var level: MineLevel { context.isPreview ? .beginner : Minesweeper.level(instance.config) }

    private var board: MineBoard {
        context.isPreview ? MineSamples.board : Minesweeper.board(instance.config, level: level)
    }

    private var now: Double {
        context.isPreview ? MineSamples.now : context.now.timeIntervalSince1970
    }

    var body: some View {
        let board = board
        return WidgetSurface {
            Group {
                if context.position.isVertical {
                    column(board)
                } else {
                    row(board)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tr("扫雷，\(Minesweeper.statusLine(board, now: now))"))
    }

    // MARK: 横排

    private func row(_ board: MineBoard) -> some View {
        HStack(spacing: 10) {
            thumbnail(board, side: 44)
            VStack(alignment: .leading, spacing: 3) {
                MineCountReadout(minesLeft: board.minesLeft, size: 18)
                MineReadout(symbol: "timer", value: "\(board.displaySeconds(now: now))",
                            tint: board.status == .won ? MineStyle.win : nil, size: 14)
                    .help(tr("用时（秒）"))
            }
            Spacer(minLength: 0)
            MineRestartButton(diameter: 28) { restart() }
                .disabled(context.isPreview)
        }
    }

    // MARK: 竖排（76 宽）

    private func column(_ board: MineBoard) -> some View {
        VStack(spacing: 6) {
            thumbnail(board, side: 50)
            VStack(alignment: .leading, spacing: 2) {
                MineCountReadout(minesLeft: board.minesLeft, size: 16)
                MineReadout(symbol: "timer", value: "\(board.displaySeconds(now: now))",
                            tint: board.status == .won ? MineStyle.win : nil, size: 13)
            }
        }
    }

    /// 这一局的缩略图；结束时右下角坐一只小熊猫（赢了欢呼，输了被炸成小骷髅）。
    private func thumbnail(_ board: MineBoard, side: CGFloat) -> some View {
        MineThumbnail(board: board)
            .frame(width: side, height: side)
            .overlay(alignment: .bottomTrailing) {
                if board.isOver {
                    MinePanda(status: board.status, size: side * 0.5)
                        .offset(x: side * 0.12, y: side * 0.1)
                }
            }
    }

    private func restart() {
        guard !context.isPreview else { return }
        MinePlay.restart(level, in: instance)
    }
}

// MARK: - 写回

/// 卡片、面板和桌面卡片点一下都走这里：取最新存着的那份配置，算完写回。
@MainActor
enum MinePlay {
    @discardableResult
    static func act(_ action: Minesweeper.Action, at index: Int, level: MineLevel,
                    in instance: WidgetInstance) -> Minesweeper.Outcome {
        var widget = WidgetWriter.current(instance.id) ?? instance
        let outcome = Minesweeper.apply(action, at: index, level: level, to: &widget.config,
                                        now: Date().timeIntervalSince1970)
        if outcome.changed { WidgetWriter.update(widget) }
        if let sound = outcome.sound, Minesweeper.soundOn(widget.config) { MineSoundPlayer.shared.play(sound) }
        return outcome
    }

    static func restart(_ level: MineLevel, in instance: WidgetInstance) {
        var widget = WidgetWriter.current(instance.id) ?? instance
        Minesweeper.restart(level, in: &widget.config)
        WidgetWriter.update(widget)
    }

    /// 面板上的喇叭：开关这张卡片的音效。
    static func toggleSound(in instance: WidgetInstance) {
        var widget = WidgetWriter.current(instance.id) ?? instance
        Minesweeper.setSound(!Minesweeper.soundOn(widget.config), in: &widget.config)
        WidgetWriter.update(widget)
    }

    static func select(_ level: MineLevel, in instance: WidgetInstance) {
        var widget = WidgetWriter.current(instance.id) ?? instance
        guard Minesweeper.level(widget.config) != level else { return }
        Minesweeper.select(level, in: &widget.config)
        WidgetWriter.update(widget)
    }
}

// MARK: - 颜色

/// 格子是液态玻璃小块：没揭开的浮起（浅色近白、深色白 0.16，顶上一道亮边），揭开的
/// 凹下去（淡淡的灰）。旗子小熊猫橙，踩雷的那格红。不用大面积的蓝色或发光。
enum MineStyle {
    static var flag: Color { Color(hex: ShelfColor.redPanda.hex).panelGraphic }
    static var win: Color { Color(hex: "#3FAE5A").panelGraphic }
    /// 「赢了 · 23 秒」这类字：浅色玻璃上压到正文的 4.5:1（`win` 只够图形的 3:1）。
    static var winText: Color { Color(hex: "#3FAE5A").panelReadable }
    /// 小熊猫橙实心底上的字：白字在 #E8743B 上只有约 3:1，用按底色算出的深墨。
    static var flagInk: Color { Color(hex: PaperInk.ink(on: ShelfColor.redPanda.hex)) }
    static var boom: Color { Color(hex: "#E5484D") }

    /// 剩余雷数的字色，三档各一对（深色玻璃上亮、浅色玻璃上压深），两边都过 4.5:1：
    /// 还有雷是小熊猫橙（浅色 #B4471A 在 #F4F4F6 上 4.96:1，深色 #FF9A5C），
    /// 正好插完是绿，旗插多了成负数是红（和数字 2、3 同一对）。
    static func count(_ tone: MineCountTone) -> Color {
        let (dark, light): (String, String) = switch tone {
        case .remaining: ("#FF9A5C", "#B4471A")
        case .cleared: ("#63D394", "#1D7F45")
        case .over: ("#FF7F75", "#C8352A")
        }
        return Color.panelDynamic(dark: NSColor(Color(hex: dark)), light: NSColor(Color(hex: light)))
    }

    static var hiddenFill: Color {
        Color.panelDynamic(dark: NSColor.white.withAlphaComponent(0.17),
                           light: NSColor.white.withAlphaComponent(0.92))
    }
    static var hiddenHover: Color {
        Color.panelDynamic(dark: NSColor.white.withAlphaComponent(0.27),
                           light: NSColor.white)
    }
    static var openFill: Color {
        Color.panelDynamic(dark: NSColor.black.withAlphaComponent(0.22),
                           light: NSColor.black.withAlphaComponent(0.06))
    }
    static var hiddenEdge: Color {
        Color.panelDynamic(dark: NSColor.white.withAlphaComponent(0.2),
                           light: NSColor.black.withAlphaComponent(0.08))
    }

    /// 数字颜色：深色玻璃上提亮、浅色玻璃上压深，两边都过 4.5:1；7、8 用主次文字色。
    static func number(_ n: Int) -> Color {
        let pair: (String, String)? = switch n {
        case 1: ("#7DB6FF", "#2563C9")
        case 2: ("#63D394", "#1D7F45")
        case 3: ("#FF7F75", "#C8352A")
        case 4: ("#C9A4FF", "#7140BF")
        case 5: ("#FFB36B", "#A8520F")
        case 6: ("#62D8DF", "#0D7A82")
        default: nil
        }
        guard let pair else { return n == 7 ? Color.panelPrimary : Color.panelSecondary }
        return Color.panelDynamic(dark: NSColor(Color(hex: pair.0)), light: NSColor(Color(hex: pair.1)))
    }
}

// MARK: - 一格

struct MineCell: View {
    var face: MineBoard.Face
    var size: CGFloat
    var hovered = false

    private var corner: CGFloat { max(2, size * 0.24) }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: corner, style: .continuous) }
    /// 格子里的字不小于 13pt（全仓最小字号），大格子按格子放大。
    private var digitSize: CGFloat { max(13, size * 0.6) }
    private var glyph: CGFloat { max(8, size * 0.56) }

    var body: some View {
        ZStack {
            background
            content
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder private var background: some View {
        switch face {
        case .hidden, .flagged, .wrongFlag:
            shape.fill(hovered ? MineStyle.hiddenHover : MineStyle.hiddenFill)
                .overlay { shape.strokeBorder(MineStyle.hiddenEdge, lineWidth: 0.5) }
        case .open, .mine:
            shape.fill(MineStyle.openFill)
        case .exploded:
            shape.fill(MineStyle.boom)
        }
    }

    @ViewBuilder private var content: some View {
        switch face {
        case .hidden:
            EmptyView()
        case .flagged:
            Image(systemName: "flag.fill")
                .font(.system(size: glyph, weight: .bold))
                .foregroundStyle(MineStyle.flag)
        case .wrongFlag:
            Image(systemName: "flag.fill")
                .font(.system(size: glyph, weight: .bold))
                .foregroundStyle(Color.panelTertiary)
                .overlay {
                    Image(systemName: "xmark")
                        .font(.system(size: glyph * 0.9, weight: .heavy))
                        .foregroundStyle(MineStyle.boom)
                }
        case .open(let n):
            if n > 0 {
                Text(verbatim: "\(n)")
                    .font(.system(size: digitSize, weight: .bold, design: .rounded))
                    .foregroundStyle(MineStyle.number(n))
            }
        case .mine:
            MineGlyph().fill(Color.panelPrimary).padding(size * 0.2)
        case .exploded:
            MineGlyph().fill(Color.white).padding(size * 0.2)
        }
    }
}

/// 雷：一个实心圆加八根短刺，用代码画。
struct MineGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let body = side * 0.32
        var path = Path(ellipseIn: CGRect(x: center.x - body, y: center.y - body, width: body * 2, height: body * 2))
        let spike = side * 0.5, width = max(1, side * 0.09)
        // 四根穿过圆心的刺，两头各露一截，就是八根。
        for i in 0..<4 {
            let angle = Double(i) * .pi / 4
            let dx = cos(angle), dy = sin(angle)
            let rect = CGRect(x: -width / 2, y: -spike, width: width, height: spike * 2)
            let transform = CGAffineTransform(translationX: center.x, y: center.y)
                .rotated(by: atan2(dy, dx) + .pi / 2)
            path.addPath(Path(roundedRect: rect, cornerRadius: width / 2).applying(transform))
        }
        return path
    }
}

// MARK: - 棋盘（能点）

/// 一整块棋盘。点的判断交给一层透明的 AppKit 视图：左键揭开 / 和弦，右键、⌥ 点
/// 或 ⌃ 点插旗（SwiftUI 的点按认不出右键）。
struct MineBoardView: View {
    var board: MineBoard
    var cell: CGFloat
    var interactive = true
    var onAction: (Minesweeper.Action, Int) -> Void = { _, _ in }

    @State private var hovered: Int?

    private var gap: CGFloat { CGFloat(Minesweeper.gap(cell: Double(cell))) }

    var body: some View {
        let size = Minesweeper.boardSize(rows: board.rows, columns: board.columns, cell: Double(cell))
        VStack(spacing: gap) {
            ForEach(0..<board.rows, id: \.self) { row in
                HStack(spacing: gap) {
                    ForEach(0..<board.columns, id: \.self) { column in
                        let index = board.index(row: row, column: column)
                        MineCell(face: board.face(index), size: cell,
                                 hovered: interactive && !board.isOver && hovered == index)
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay {
            if interactive {
                MineClickCatcher { point, flag in
                    guard let index = hit(point) else { return }
                    onAction(flag ? .flag : .reveal, index)
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point): hovered = hit(point)
                    case .ended: hovered = nil
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("扫雷棋盘，\(board.columns) 列 \(board.rows) 行"))
        .accessibilityValue(Minesweeper.statusLine(board, now: Date().timeIntervalSince1970))
    }

    private func hit(_ point: CGPoint) -> Int? {
        Minesweeper.hitIndex(x: Double(point.x), y: Double(point.y), rows: board.rows,
                             columns: board.columns, cell: Double(cell))
    }
}

/// 透明的点击层：报告点在哪（左上为原点）和是不是插旗。
struct MineClickCatcher: NSViewRepresentable {
    var onClick: (CGPoint, Bool) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onClick = onClick
        return view
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.onClick = onClick
    }

    final class CatcherView: NSView {
        var onClick: (CGPoint, Bool) -> Void = { _, _ in }

        override var isFlipped: Bool { true }
        // 桌面卡片、面板没在前台时第一下也要算数。
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let flag = flags.contains(.option) || flags.contains(.control)
            onClick(convert(event.locationInWindow, from: nil), flag)
        }

        override func rightMouseDown(with event: NSEvent) {
            onClick(convert(event.locationInWindow, from: nil), true)
        }
    }
}

// MARK: - 缩略图（不能点）

/// 一局的缩略图：没揭开的浅块、揭开的凹下、旗子橙点、踩雷红块。用 Canvas 画，16×16 也不卡。
struct MineThumbnail: View {
    var board: MineBoard
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { context, size in
            let dark = scheme == .dark
            let columns = CGFloat(board.columns), rows = CGFloat(board.rows)
            let pitch = min(size.width / columns, size.height / rows)
            let gap = pitch >= 4 ? max(0.6, pitch * 0.14) : 0.4
            let cell = pitch - gap
            let origin = CGPoint(x: (size.width - pitch * columns + gap) / 2,
                                 y: (size.height - pitch * rows + gap) / 2)
            let hiddenColor = dark ? Color.white.opacity(0.24) : Color.black.opacity(0.16)
            let openColor = dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)
            let flagColor = Color(hex: ShelfColor.redPanda.hex)
            for index in 0..<board.cellCount {
                let r = CGFloat(index / board.columns), c = CGFloat(index % board.columns)
                let rect = CGRect(x: origin.x + c * pitch, y: origin.y + r * pitch, width: cell, height: cell)
                let path = Path(roundedRect: rect, cornerRadius: cell * 0.25)
                let color: Color = switch board.face(index) {
                case .hidden: hiddenColor
                case .flagged, .wrongFlag: flagColor
                case .open: openColor
                case .mine: dark ? Color.white.opacity(0.7) : Color.black.opacity(0.6)
                case .exploded: MineStyle.boom
                }
                context.fill(path, with: .color(color))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 小部件

/// 图标加一个数字（剩余雷数、秒）。
struct MineReadout: View {
    var symbol: String
    var value: String
    var tint: Color?
    var size: CGFloat = 15

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: size - 3, weight: .semibold))
                .foregroundStyle(tint ?? WidgetStyle.secondary)
                .frame(width: size, alignment: .center)
            Text(verbatim: value)
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .foregroundStyle(WidgetStyle.primary)
                .monospacedDigit()
                .lineLimit(1)
                .contentTransition(.numericText())
        }
    }
}

/// 圆形玻璃重开键：逆时针箭头，深色玻璃上用主文字色画，看得清。
struct MineRestartButton: View {
    var diameter: CGFloat = 28
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: diameter * 0.46, weight: .bold))
                .foregroundStyle(Color.panelPrimary)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(hovering ? Color.panelSelected : Color.panelRaised).panelLift())
                .overlay(Circle().strokeBorder(Color.panelStroke, lineWidth: 0.5))
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(tr("重开一盘"))
        .accessibilityLabel(tr("重开一盘"))
    }
}

/// 结果小熊猫：赢了欢呼，输了「被炸」成电子宠物用过的那只小骷髅（转圈眼、抱着奶瓶，
/// 卡通不吓人），没结束时是平常的样子（Resources/Pet）。刚踩雷那一下放大再抖几下，
/// 「减少动态效果」打开时只换图不动。
struct MinePanda: View {
    var status: MineBoard.Status
    var size: CGFloat

    @MainActor private static var cache: [String: NSImage] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var blasts = 0

    private struct Blast {
        var scale: CGFloat = 1
        var angle: Double = 0
    }

    private var name: String {
        switch status {
        case .won: "pet-panda-cheer"
        case .lost: "pet-panda-skeleton"
        case .ready, .playing: "pet-panda-idle"
        }
    }

    @MainActor private static func image(_ name: String) -> NSImage? {
        if let cached = cache[name] { return cached }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        cache[name] = image
        return image
    }

    var body: some View {
        if let image = Self.image(name) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .keyframeAnimator(initialValue: Blast(), trigger: blasts) { content, value in
                    content
                        .scaleEffect(value.scale)
                        .rotationEffect(.degrees(value.angle))
                } keyframes: { _ in
                    KeyframeTrack(\.scale) {
                        CubicKeyframe(1.28, duration: 0.09)
                        SpringKeyframe(1, duration: 0.32, spring: .bouncy)
                    }
                    KeyframeTrack(\.angle) {
                        LinearKeyframe(-11, duration: 0.05)
                        LinearKeyframe(9, duration: 0.06)
                        LinearKeyframe(-6, duration: 0.06)
                        LinearKeyframe(4, duration: 0.06)
                        LinearKeyframe(0, duration: 0.06)
                    }
                }
                .onChange(of: status) { _, new in
                    if new == .lost, !reduceMotion { blasts += 1 }
                }
                .accessibilityHidden(true)
        }
    }
}

/// 剩余雷数：旗子加一个大号、粗体圆体、等宽的数字，是一局里最该一眼看到的读数。
/// 还有雷是小熊猫橙，正好插完变绿，旗插多了成负数变红并换成警示三角。
struct MineCountReadout: View {
    var minesLeft: Int
    var size: CGFloat = 22

    var body: some View {
        let tone = MineCountTone(minesLeft: minesLeft)
        let color = MineStyle.count(tone)
        HStack(spacing: max(3, size * 0.18)) {
            Image(systemName: tone == .over ? "exclamationmark.triangle.fill" : "flag.fill")
                .font(.system(size: max(12, size * 0.68), weight: .bold))
                .foregroundStyle(color)
            Text(verbatim: Minesweeper.minesLeftText(minesLeft))
                .font(.system(size: size, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .contentTransition(.numericText(value: Double(minesLeft)))
                .animation(.snappy(duration: 0.2), value: minesLeft)
        }
        .fixedSize()
        .help(tone == .over ? tr("旗插多了：比雷还多 \(-minesLeft) 面") : tr("剩余雷数"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("剩余雷数"))
        .accessibilityValue(Minesweeper.minesLeftText(minesLeft))
    }
}

/// 音效开关：玻璃小圆钮里一个喇叭，开着是 speaker.wave.2.fill，关了是 speaker.slash.fill，
/// 用主文字色画，浅色深色玻璃上都看得清。存在卡片配置（`Minesweeper.soundKey`）。
struct MineSoundToggle: View {
    var on: Bool
    var diameter: CGFloat = 28
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: on ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.system(size: diameter * 0.45, weight: .semibold))
                .foregroundStyle(on ? Color.panelPrimary : Color.panelSecondary)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(Color.panelRaised).panelLift())
                .overlay(Circle().strokeBorder(Color.panelStroke, lineWidth: 0.5))
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help(on ? tr("关闭音效") : tr("打开音效"))
        .accessibilityLabel(tr("音效"))
        .accessibilityValue(on ? tr("开") : tr("关"))
    }
}

/// 小组件库和截图里的示例：固定种子的一局初级，点开了一片、插了两面旗。
enum MineSamples {
    static let now: Double = 1_000_042

    static let board: MineBoard = {
        var board = MineBoard(level: .beginner)
        var rng = MineRandom(seed: 20261029)
        board.reveal(board.index(row: 4, column: 4), now: 1_000_000, using: &rng)
        var flags = 0
        for index in 0..<board.cellCount where flags < 2 && board.isMine(index)
            && board.neighbors(of: index).contains(where: { board.revealed[$0] }) {
            board.toggleFlag(index, now: 1_000_000)
            flags += 1
        }
        return board
    }()
}
