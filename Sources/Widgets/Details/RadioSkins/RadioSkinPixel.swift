import SwiftUI

// 收音机外观：掌机像素（Pro）。
//
// 反射式红色液晶屏：左边像素大数字写频道号，右边一只手画的像素小熊猫头，底部 5 格调谐条，
// 倒三角指着当前台。暗色是红字黑屏，浅色是黑字红屏，收藏当前行用爱心（RadioDetail 画）。
// 设计稿 design/radio-skins2.png 第 4 列，配色和尺寸见 design/radio-skins2.py 的 skin_pixel / tile_pixel
// （面板按 1.25 倍、卡片按 264 × 62 画，卡片落到 212 × 62 时按比例收窄）。
//
// 面板一律用暗色版（用户定的），所以面板上半部分和底都固定取掌机像素的暗色调色板和暗色液晶；
// 卡片跟扩展栏深浅走 `model.tone`。
//
// 数字和小熊猫都是自己用点阵画的，不用外部字体。动画只有两处，都很省：播放中小熊猫隔几秒眨一下眼，
// 连接中倒三角一闪一闪；都用 TimelineView 按每秒 5 帧刷新，暂停、预览、减少动态效果时停住不刷新，
// 面板关上就停。暂停时小熊猫闭眼，旁边一个像素“Z”。

/// 掌机像素自己的装饰色和点阵。
private enum PixelLook {
    /// 液晶一版的颜色：屏底、点亮的像素、没点亮的像素不透明度、外壳。
    struct Screen {
        var glass: Color
        var pixel: Color
        var unlit: Double
        var bezel: Color
    }

    static func screen(_ tone: RadioSkinTone) -> Screen {
        switch tone {
        case .dark:
            Screen(glass: Color(hex: "#2A0806"), pixel: Color(hex: "#FF4B3A"), unlit: 0.07, bezel: Color(hex: "#2C2729"))
        case .light:
            Screen(glass: Color(hex: "#E8513F"), pixel: Color(hex: "#3B0905"), unlit: 0.10, bezel: Color(hex: "#D9D3CE"))
        }
    }

    /// 面板固定用暗色版：把模型换成暗色那组颜色。
    static func dark(_ model: RadioSkinModel) -> RadioSkinModel {
        guard model.tone != .dark, let palette = RadioSkinPalette.palette(.pixel, tone: .dark) else { return model }
        var dark = model
        dark.tone = .dark
        dark.palette = palette
        return dark
    }

    /// 像素小熊猫头 15 × 12，照设计稿 PANDA_ROWS：X 毛色（亮），. 白色脸斑（不亮），o 眼睛和鼻子（亮）。
    static let pandaRows = [
        ".XX.........XX.",
        "XXXX.......XXXX",
        "XX.XXXXXXXXX.XX",
        "XXXXXXXXXXXXXXX",
        "XX...XXXXX...XX",
        "X..o..XXX..o..X",
        "X.....XXX.....X",
        "XX...........XX",
        "XXX....o....XXX",
        ".XXX.......XXX.",
        "..XXXX...XXXX..",
        "....XXXXXXX....",
    ]
    static let pandaCols = 15
    static let pandaRowCount = 12
    /// 两只眼睛（列、行）。
    static let eyes = [Cell(col: 3, row: 5), Cell(col: 11, row: 5)]

    /// 小熊猫头点亮的格子；`eyesOpen` 为 false 时眼睛不点，由调用方画成一道横线。
    static func pandaCells(eyesOpen: Bool) -> [Cell] {
        var cells: [Cell] = []
        for (row, line) in pandaRows.enumerated() {
            for (col, ch) in line.enumerated() where ch == "X" || ch == "o" {
                let cell = Cell(col: col, row: row)
                if !eyesOpen, eyes.contains(cell) { continue }
                cells.append(cell)
            }
        }
        return cells
    }

    /// 5 × 7 点阵字，照设计稿 FONT，补了 6 到 9 和“-”。
    static let font: [Character: [String]] = [
        "0": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
        "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
        "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
        "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
        "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
        "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
        "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
        "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
        "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
        "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
        "-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
    ]

    /// 暂停时小熊猫旁边的像素“Z”。
    static let snore = ["1111", "0010", "0100", "1111"]

    struct Cell: Hashable {
        var col: Int
        var row: Int
    }

    /// 文字点亮的格子，从 (dx, dy) 起，每个点放大 `scale` 倍，字间隔 1 个点（也放大）。
    static func glyphCells(_ text: String, scale: Int, dx: Int, dy: Int) -> [Cell] {
        var cells: [Cell] = []
        var x = 0
        for ch in text {
            let rows = font[ch] ?? font["-"] ?? []
            for (ry, row) in rows.enumerated() {
                for (rx, bit) in row.enumerated() where bit == "1" {
                    for sy in 0..<scale {
                        for sx in 0..<scale {
                            cells.append(Cell(col: dx + x + rx * scale + sx, row: dy + ry * scale + sy))
                        }
                    }
                }
            }
            x += 6 * scale
        }
        return cells
    }

    // MARK: 大屏布局（格子数按设计稿 82 × 50，屏幕尺寸变了就按格子数重排）

    /// 每格的边长（pt），设计稿 3.2。
    static let pitch: CGFloat = 3.2
    /// 调谐条：5 格，每格 13 列宽、4 行高，格间 2 列，从第 3 列起，离底 7 行。
    static let segmentWidth = 13
    static let segmentGap = 2
    static let segmentLeft = 3

    static func segmentRange(_ slot: Int) -> ClosedRange<Int> {
        let x0 = segmentLeft + slot * (segmentWidth + segmentGap)
        return x0...(x0 + segmentWidth - 1)
    }

    /// 屏上第几格对应哪个收藏：收藏不超过 5 台时一格一台；多了就取围着当前台的 5 台。
    static func slots(_ model: RadioSkinModel) -> [Int?] {
        let around = model.favouritesAround(rows: 5).map(\.offset)
        return (0..<5).map { $0 < around.count ? around[$0] : nil }
    }

    /// 屏上三档：点亮、半亮（空着的调谐格边框）、其余不亮。
    struct Frame {
        var lit: Set<Cell> = []
        var dim: Set<Cell> = []
    }

    static func frame(digits: String, cols: Int, rows: Int, slots: [Int?], current: Int?,
                      eyesOpen: Bool, snoring: Bool, pointerOn: Bool) -> Frame {
        var frame = Frame()
        // 大号频道号：5 × 7 放大 3 倍，从第 3 列第 5 行起。
        for cell in glyphCells(digits, scale: 3, dx: 3, dy: 5) { frame.lit.insert(cell) }
        // 小熊猫：每个点 2 × 2 格，靠右上。
        let px0 = cols - pandaCols * 2 - 3
        let py0 = 4
        func paint(_ cell: Cell) {
            for a in 0..<2 {
                for b in 0..<2 { frame.lit.insert(Cell(col: px0 + cell.col * 2 + a, row: py0 + cell.row * 2 + b)) }
            }
        }
        pandaCells(eyesOpen: eyesOpen).forEach(paint)
        if !eyesOpen {
            // 闭眼：眼睛那块的下面一行画一道 4 格横线。
            for eye in eyes {
                for dx in -1...2 { frame.lit.insert(Cell(col: px0 + eye.col * 2 + dx, row: py0 + eye.row * 2 + 1)) }
            }
        }
        if snoring {
            let zx = px0 - 6
            for (ry, row) in snore.enumerated() {
                for (rx, bit) in row.enumerated() where bit == "1" { frame.lit.insert(Cell(col: zx + rx, row: 3 + ry)) }
            }
        }
        // 调谐条：当前格实心，有台的格空框，空位半亮空框。
        let top = rows - 7
        for slot in 0..<5 {
            let range = segmentRange(slot)
            let filled = current != nil && current == slot
            let used = slots[slot] != nil
            for col in range {
                for row in top..<(top + 4) {
                    let edge = row == top || row == top + 3 || col == range.lowerBound || col == range.upperBound
                    let cell = Cell(col: col, row: row)
                    if filled || (edge && used) {
                        frame.lit.insert(cell)
                    } else if edge {
                        frame.dim.insert(cell)
                    }
                }
            }
        }
        // 倒三角指着当前格。
        if let current, pointerOn {
            let range = segmentRange(current)
            let tip = range.lowerBound + segmentWidth / 2
            for (k, width) in [5, 3, 1].enumerated() {
                for col in (tip - width / 2)...(tip + width / 2) { frame.lit.insert(Cell(col: col, row: top - 4 + k)) }
            }
        }
        frame.lit = frame.lit.filter { $0.col >= 0 && $0.col < cols && $0.row >= 0 && $0.row < rows }
        return frame
    }

    /// 一块方像素液晶：没点亮的很淡，点亮的实心，空调谐格半亮。
    static func draw(_ ctx: inout GraphicsContext, size: CGSize, cols: Int, rows: Int, pitch: CGFloat,
                     frame: Frame, screen: Screen, gap: CGFloat) {
        let ox = (size.width - CGFloat(cols) * pitch) / 2
        let oy = (size.height - CGFloat(rows) * pitch) / 2
        var off = Path()
        var on = Path()
        var dim = Path()
        for row in 0..<rows {
            for col in 0..<cols {
                let rect = CGRect(x: ox + CGFloat(col) * pitch + gap, y: oy + CGFloat(row) * pitch + gap,
                                  width: pitch - gap * 2, height: pitch - gap * 2)
                let cell = Cell(col: col, row: row)
                if frame.lit.contains(cell) {
                    on.addRect(rect)
                } else if frame.dim.contains(cell) {
                    dim.addRect(rect)
                } else {
                    off.addRect(rect)
                }
            }
        }
        ctx.fill(off, with: .color(screen.pixel.opacity(screen.unlit)))
        ctx.fill(dim, with: .color(screen.pixel.opacity(0.32)))
        ctx.fill(on, with: .color(screen.pixel))
    }
}

// MARK: - 面板

/// 掌机像素：面板上半部分（头一行、主视觉、台名、走带键、音量），宽 288pt。
struct RadioSkinPixelPanel: RadioSkinPanelFace {
    var model: RadioSkinModel

    /// 整张面板卡片的底：固定暗色版。
    static func backdrop(_ model: RadioSkinModel) -> some View {
        RadioSkinBackdrop(model: PixelLook.dark(model))
    }

    var body: some View {
        let dark = PixelLook.dark(model)
        VStack(alignment: .leading, spacing: 12) {
            RadioSkinHeader(model: dark)
            PixelHandheld(model: dark)
                .frame(height: 184)
                .padding(.bottom, 2)
            RadioSkinReadout(model: dark)
            PixelTransport(model: dark)
                .padding(.vertical, 2)
            PixelVolume(model: dark)
        }
        .environment(\.colorScheme, .dark)
    }
}

/// 掌机外壳加红色液晶屏。
private struct PixelHandheld: View {
    var model: RadioSkinModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var screen: PixelLook.Screen { PixelLook.screen(.dark) }
    /// 播放中眨眼：正在出声、不在缓冲、不是预览、没开减少动态效果。
    private var blinking: Bool { model.playing && !model.buffering && !model.isPreview && !reduceMotion && model.canPlay }
    /// 连接中倒三角一闪一闪（减少动态效果时常亮）。
    private var flashing: Bool { model.buffering && !model.isPreview && !reduceMotion }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        ZStack {
            shape.fill(screen.bezel)
            shape.strokeBorder(Color.black.opacity(0.25), lineWidth: 0.8)
            shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 1).offset(y: 0.6).clipShape(shape)
            lcd.padding(12)
        }
    }

    private var lcd: some View {
        let slots = PixelLook.slots(model)
        let current = model.canPlay ? slots.firstIndex(where: { $0 == model.index }) : nil
        let digits = model.channelText
        let paused = !model.isPreview && !model.playing
        let screen = self.screen
        return GeometryReader { proxy in
            let pitch = PixelLook.pitch
            let cols = max(1, Int(proxy.size.width / pitch))
            let rows = max(1, Int(proxy.size.height / pitch))
            TimelineView(.animation(minimumInterval: 0.2, paused: !(blinking || flashing))) { tick in
                let t = tick.date.timeIntervalSinceReferenceDate
                let eyesOpen = model.canPlay && !paused && !(blinking && t.truncatingRemainder(dividingBy: 4.2) < 0.22)
                let pointerOn = !flashing || Int((t * 2.5).rounded(.down)) % 2 == 0
                let frame = PixelLook.frame(digits: digits, cols: cols, rows: rows, slots: slots, current: current,
                                            eyesOpen: eyesOpen, snoring: paused || !model.canPlay,
                                            pointerOn: pointerOn)
                Canvas { ctx, size in
                    PixelLook.draw(&ctx, size: size, cols: cols, rows: rows, pitch: pitch, frame: frame,
                                   screen: screen, gap: 0.3)
                }
            }
            .contentShape(.rect)
            .onTapGesture(coordinateSpace: .local) { point in
                tap(point, size: proxy.size, cols: cols, rows: rows, slots: slots)
            }
        }
        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(screen.glass))
        .overlay(alignment: .top) {
            // 屏幕上沿一道反光。
            UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .frame(height: 10)
                .allowsHitTesting(false)
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.black.opacity(0.55)))
        .padding(-2)
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: "\(model.stationName) · \(model.channelOfTotal)"))
    }

    /// 点调谐条上的格子换到那一台。
    private func tap(_ point: CGPoint, size: CGSize, cols: Int, rows: Int, slots: [Int?]) {
        guard !model.isPreview else { return }
        let pitch = PixelLook.pitch
        let ox = (size.width - CGFloat(cols) * pitch) / 2
        let oy = (size.height - CGFloat(rows) * pitch) / 2
        let col = Int(((point.x - ox) / pitch).rounded(.down))
        let row = Int(((point.y - oy) / pitch).rounded(.down))
        let top = rows - 7
        // 调谐条和上面的三角那几行都算，手指不用点得那么准。
        guard row >= top - 4, row <= top + 4 else { return }
        for slot in 0..<5 where PixelLook.segmentRange(slot).contains(col) {
            if let target = slots[slot], target != model.index { model.onTune(target) }
            return
        }
    }
}

/// 上一台、播放、下一台：两侧 34pt 方钮（外壳色），中间 48pt 实心红方钮，图标深色。
private struct PixelTransport: View {
    var model: RadioSkinModel

    var body: some View {
        HStack(spacing: 15) {
            Spacer(minLength: 0)
            key("backward.end.fill", main: false, label: tr("上一个电台"), action: model.onPrevious)
                .disabled(!model.canStep)
            key(model.playing ? "pause.fill" : "play.fill", main: true,
                label: model.playing ? tr("暂停") : tr("收听"), action: model.onToggle)
                .disabled(!model.canPlay)
            key("forward.end.fill", main: false, label: tr("下一个电台"), action: model.onNext)
                .disabled(!model.canStep)
            Spacer(minLength: 0)
        }
    }

    private func key(_ symbol: String, main: Bool, label: String, action: @escaping () -> Void) -> some View {
        let colors = model.colors
        let size: CGFloat = main ? 48 : 34
        let corner: CGFloat = main ? 5 : 4
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        return Button(action: action) {
            Image(systemName: symbol)
                .playPauseMorph(symbol, enabled: main)
                .font(.system(size: main ? 18 : 13, weight: .bold))
                .foregroundStyle(main ? colors.ink : colors.text)
                .frame(width: size, height: size)
                .background(shape.fill(main ? colors.accent : PixelLook.screen(.dark).bezel))
                .overlay(shape.strokeBorder(Color.black.opacity(0.2), lineWidth: 0.8))
                .background(shape.fill(Color.black.opacity(0.35)).offset(y: main ? 3.5 : 3))
                .contentShape(shape)
        }
        .buttonStyle(RadioRetroPress())
        .help(label)
        .accessibilityLabel(label)
    }
}

/// 音量：喇叭、红色填充的条和方形滑块、百分比。拖动时只调播放器，松手才存。
private struct PixelVolume: View {
    var model: RadioSkinModel

    var body: some View {
        let colors = model.colors
        let value = model.volume
        HStack(spacing: 10) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 13))
                .foregroundStyle(colors.text.opacity(0.7))
            GeometryReader { proxy in
                let width = proxy.size.width
                let x = width * CGFloat(min(max(value / 100, 0), 1))
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(colors.text.opacity(0.14)).frame(height: 6)
                    RoundedRectangle(cornerRadius: 3).fill(colors.fill).frame(width: max(0, x), height: 6)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(colors.accent)
                        .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color.black.opacity(0.3), lineWidth: 0.8))
                        .frame(width: 12, height: 16)
                        .offset(x: min(max(0, x - 6), max(0, width - 12)))
                }
                .frame(height: proxy.size.height)
                .contentShape(.rect)
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard !model.isPreview, width > 0 else { return }
                        model.onVolume((Double(min(max(drag.location.x / width, 0), 1)) * 100).rounded())
                    }
                    .onEnded { _ in if !model.isPreview { model.onVolumeEnd() } })
            }
            .frame(height: 28)
            .accessibilityElement()
            .accessibilityLabel(tr("音量"))
            .accessibilityValue("\(Int(value.rounded()))%")
            .accessibilityAdjustableAction { direction in
                guard !model.isPreview else { return }
                switch direction {
                case .increment: model.onVolume(min(100, value + 10)); model.onVolumeEnd()
                case .decrement: model.onVolume(max(0, value - 10)); model.onVolumeEnd()
                @unknown default: break
                }
            }
            Text(verbatim: "\(Int(value.rounded()))%")
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundStyle(colors.text)
                .frame(width: 44, alignment: .trailing)
        }
    }
}

// MARK: - 卡片

/// 掌机像素：212 × 62 卡片的内容；`vertical` 时是侧边竖排的小卡片。
struct RadioSkinPixelCard: RadioSkinCardFace {
    var model: RadioSkinModel
    var vertical: Bool

    var body: some View {
        if vertical {
            VStack(spacing: 4) {
                PixelBadge(tone: model.tone)
                    .frame(width: 32, height: 32)
                Text(verbatim: model.stationName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(model.colors.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 2) {
                    playButton(size: 24)
                    nextButton(size: 12)
                }
            }
        } else {
            HStack(spacing: 9) {
                PixelBadge(tone: model.tone)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: model.stationName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(model.colors.text)
                        .minimumScaleFactor(13.0 / 15.0)
                    Text(verbatim: model.caption)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(model.detailIsProblem ? model.colors.accentText : model.colors.secondary)
                        .monospacedDigit()
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                HStack(spacing: 2) {
                    playButton(size: 26)
                    nextButton(size: 12)
                }
            }
        }
    }

    private func playButton(size: CGFloat) -> some View {
        let colors = model.colors
        let symbol = model.playing ? "pause.fill" : "play.fill"
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        return Button {
            guard !model.isPreview else { return }
            model.onToggle()
        } label: {
            Image(systemName: symbol)
                .playPauseMorph(symbol)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(colors.ink)
                .frame(width: size, height: size)
                .background(shape.fill(colors.accent))
                .contentShape(shape)
        }
        .buttonStyle(RadioRetroPress())
        .allowsHitTesting(!model.isPreview && model.canPlay)
        .opacity(model.canPlay ? 1 : 0.45)
        .help(model.playing ? tr("暂停") : tr("收听"))
        .accessibilityLabel(model.playing ? tr("暂停收音机") : tr("收听 \(model.stationName)"))
    }

    private func nextButton(size: CGFloat) -> some View {
        TileGlyph(symbol: "forward.end.fill", size: size, tint: model.colors.text,
                  action: model.isPreview || !model.canStep ? nil : model.onNext)
            .opacity(model.canStep ? 1 : 0.45)
            .help(tr("下一个电台"))
            .accessibilityLabel(tr("下一个电台"))
    }
}

/// 卡片左边的小液晶：外壳里一块红屏，满屏 15 × 12 像素，点亮的是小熊猫头；不动。
private struct PixelBadge: View {
    var tone: RadioSkinTone

    var body: some View {
        let screen = PixelLook.screen(tone)
        let lit = Set(PixelLook.pandaCells(eyesOpen: true))
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let inset = side * 4 / 46
            let inner = side - inset * 2
            let pitch = (inner - inner * 4 / 38) / CGFloat(PixelLook.pandaCols)
            Canvas { ctx, size in
                PixelLook.draw(&ctx, size: size, cols: PixelLook.pandaCols, rows: PixelLook.pandaRowCount,
                               pitch: pitch, frame: PixelLook.Frame(lit: lit), screen: screen,
                               gap: max(0.15, pitch * 0.09))
            }
            .background(RoundedRectangle(cornerRadius: side * 3 / 46, style: .continuous).fill(screen.glass))
            .padding(inset)
            .background(RoundedRectangle(cornerRadius: side * 8 / 46, style: .continuous).fill(screen.bezel))
        }
        .accessibilityHidden(true)
    }
}
