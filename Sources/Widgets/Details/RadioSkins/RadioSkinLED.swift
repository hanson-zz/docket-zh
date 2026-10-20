import SwiftUI

// 收音机外观：灯阵（Pro）。
//
// 黑底圆点 LED 屏，暖黄点阵数字和随播放跳动的频谱；屏下 5 个预设键，当前台亮灯。浅色版只换外壳，LED 窗保持黑色。
// 设计稿 design/radio-skins2.png 第 2 列，配色和尺寸见 design/radio-skins2.py 的 skin_led / tile_led
// （面板按 1.25 倍、卡片按 264 × 62 画，卡片落到 212 × 62 时按比例收窄）。
//
// 面板一律用暗色版（用户定的），所以面板上半部分和底都固定取灯阵的暗色调色板；
// 卡片跟扩展栏深浅走 `model.tone`。
//
// 频谱不是真的读音频，是一组伪随机柱：只在正在播放、不在预览、没开“减少动态效果”时
// 用 TimelineView 按每秒 10 帧刷新，暂停、预览、减少动态效果时静止，面板关上就停。

/// 灯阵自己的装饰色和点阵字。
private enum LEDLook {
    /// LED 暖黄，暗色、浅色两版一样。
    static let lamp = Color(hex: "#FFC845")
    /// LED 窗：两版都是黑的。
    static let window = Color(hex: "#070608")
    /// 暗色外壳。
    static let chassis = Color(hex: "#0D0C0E")

    /// 面板固定用暗色版。
    static func dark(_ model: RadioSkinModel) -> RadioSkinModel {
        guard model.tone != .dark, let palette = RadioSkinPalette.palette(.led, tone: .dark) else { return model }
        var dark = model
        dark.tone = .dark
        dark.palette = palette
        return dark
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

    /// 文字点亮的格子（列、行），从 (dx, dy) 起，每个点放大 `scale` 倍，字间隔 1 个点。
    /// 返回点亮格子和占的列数。
    static func glyphCells(_ text: String, scale: Int, dx: Int, dy: Int) -> (cells: [Cell], width: Int) {
        var cells: [Cell] = []
        var x = 0
        for ch in text {
            let rows = font[ch] ?? font["-"]!
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
        return (cells, max(0, x - scale))
    }

    struct Cell: Hashable {
        var col: Int
        var row: Int
    }

    /// 设计稿里那组频谱高度，静止时就画它。
    static let restingBars = [6, 9, 13, 10, 7, 12, 15, 11, 8, 5, 9, 12]

    /// 便宜的伪随机数（0 到 1），同一个 bar 和 step 永远同一个值。
    static func noise(_ bar: Int, _ step: Int) -> Double {
        var h = UInt64(truncatingIfNeeded: bar &* 73_856_093) ^ UInt64(truncatingIfNeeded: step &* 19_349_663)
        h = (h ^ (h >> 13)) &* 0x5BD1_E995
        h ^= h >> 15
        return Double(h & 0xFFFF) / 65_535
    }

    /// 播放中第 `bar` 根柱在时间 `t` 的高度：相邻两步伪随机数插值，再乘上这根柱自己的包络。
    static func liveBar(_ bar: Int, t: TimeInterval, maxHeight: Int) -> Int {
        let speed = 6.0
        let pos = t * speed
        let step = Int(pos.rounded(.down))
        let frac = pos - Double(step)
        let smooth = frac * frac * (3 - 2 * frac)
        let value = noise(bar, step) + (noise(bar, step + 1) - noise(bar, step)) * smooth
        let envelope = Double(restingBars[bar % restingBars.count]) / 15
        let level = (0.22 + 0.78 * value) * (0.55 + 0.45 * envelope)
        return max(1, min(maxHeight, Int((Double(maxHeight) * level).rounded())))
    }

    enum BarMode {
        /// 设计稿那组高度（预览、减少动态效果）。
        case resting
        /// 伪随机跳动。
        case live
        /// 压平，亮点来回扫。
        case scanning
        /// 压平（暂停、没有电台）。
        case flat
    }

    static func litCells(digits: String, cols: Int, rows: Int, mode: BarMode, t: TimeInterval) -> Set<Cell> {
        // 大号频道号：5 × 7 放大 2 倍，从第 2 列第 3 行起（设计稿）。
        let glyph = glyphCells(digits, scale: 2, dx: 2, dy: 3)
        var lit = Set(glyph.cells.filter { $0.col < cols && $0.row < rows })
        // 频谱：数字右边空 2 列起，每隔一列一根，底下留 2 行。
        let bottom = rows - 2
        let maxHeight = max(1, bottom - 2)
        let firstCol = 2 + glyph.width + 2
        let columns = Array(stride(from: firstCol, to: cols, by: 2))
        let bars = columns.count
        let sweep = bars > 0 ? Int((t * 8).rounded(.down)) % max(1, bars * 2 - 2) : 0
        let lead = sweep < bars ? sweep : bars * 2 - 2 - sweep
        for (k, col) in columns.enumerated() {
            let height: Int
            switch mode {
            case .resting: height = min(maxHeight, restingBars[k % restingBars.count])
            case .live: height = liveBar(k, t: t, maxHeight: maxHeight)
            case .scanning: height = k == lead ? 3 : 1
            case .flat: height = 1
            }
            for row in max(0, bottom - height)..<max(0, bottom) {
                lit.insert(Cell(col: col, row: row))
            }
        }
        return lit
    }

    /// 一块圆点 LED：未点亮的点很淡，点亮的点暖黄，大屏上带一圈柔光。
    static func draw(_ ctx: inout GraphicsContext, size: CGSize, cols: Int, rows: Int, pitch: CGFloat,
                     lit: Set<Cell>, dot: CGFloat, unlit: Double, halo: Bool) {
        let ox = (size.width - CGFloat(cols) * pitch) / 2
        let oy = (size.height - CGFloat(rows) * pitch) / 2
        var off = Path()
        var on = Path()
        var glow = Path()
        for row in 0..<rows {
            for col in 0..<cols {
                let cx = ox + CGFloat(col) * pitch + pitch / 2
                let cy = oy + CGFloat(row) * pitch + pitch / 2
                let rect = CGRect(x: cx - dot, y: cy - dot, width: dot * 2, height: dot * 2)
                if lit.contains(Cell(col: col, row: row)) {
                    on.addEllipse(in: rect)
                    if halo {
                        let r = dot * 1.9
                        glow.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
                    }
                } else {
                    off.addEllipse(in: rect)
                }
            }
        }
        ctx.fill(off, with: .color(lamp.opacity(unlit)))
        if halo { ctx.fill(glow, with: .color(lamp.opacity(0.16))) }
        ctx.fill(on, with: .color(lamp))
    }
}

// MARK: - 面板

/// 灯阵：面板上半部分（头一行、主视觉、台名、走带键、音量），宽 288pt。
struct RadioSkinLEDPanel: RadioSkinPanelFace {
    var model: RadioSkinModel

    /// 整张面板卡片的底：固定暗色版。
    static func backdrop(_ model: RadioSkinModel) -> some View {
        RadioSkinBackdrop(model: LEDLook.dark(model))
    }

    var body: some View {
        let dark = LEDLook.dark(model)
        VStack(alignment: .leading, spacing: 12) {
            RadioSkinHeader(model: dark)
            VStack(spacing: 10) {
                LEDScreen(model: dark)
                    .frame(height: 118)
                LEDPresetRow(model: dark)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(LEDLook.chassis))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8))
            .padding(.bottom, 2)
            RadioSkinReadout(model: dark)
            RadioSkinTransport(model: dark)
                .background(
                    Circle()
                        .fill(LEDLook.lamp.opacity(dark.playing ? 0.30 : 0.12))
                        .frame(width: 60, height: 60)
                        .blur(radius: 9)
                        .allowsHitTesting(false))
            RadioSkinVolume(model: dark)
        }
    }
}

/// 黑色 LED 窗：左边大号点阵频道号，右边频谱。
private struct LEDScreen: View {
    var model: RadioSkinModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let pitch: CGFloat = 5.5

    /// 频谱要不要跳：正在出声、不在缓冲、不是预览、没开减少动态效果。
    private var live: Bool { model.playing && !model.buffering && !model.isPreview && !reduceMotion && model.canPlay }
    /// 连接中：频谱压平，一个亮点来回扫（减少动态效果时不扫）。
    private var scanning: Bool { model.buffering && !model.isPreview && !reduceMotion }

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: !(live || scanning))) { tick in
            let t = tick.date.timeIntervalSinceReferenceDate
            let mode = barMode
            let digits = model.channelText
            let pitch = Self.pitch
            Canvas { ctx, size in
                let cols = max(1, Int((size.width - 8) / pitch))
                let rows = max(1, Int((size.height - 8) / pitch))
                let lit = LEDLook.litCells(digits: digits, cols: cols, rows: rows, mode: mode, t: t)
                LEDLook.draw(&ctx, size: size, cols: cols, rows: rows, pitch: pitch, lit: lit,
                             dot: pitch * 0.36, unlit: 0.09, halo: true)
            }
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(LEDLook.window))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.black.opacity(0.6), lineWidth: 1))
        .accessibilityElement()
        .accessibilityLabel(Text(verbatim: "\(model.stationName) · \(model.channelOfTotal)"))
    }

    private var barMode: LEDLook.BarMode {
        guard model.canPlay else { return .flat }
        if model.isPreview { return .resting }
        if model.buffering { return scanning ? .scanning : .flat }
        guard model.playing else { return .flat }
        return reduceMotion ? .resting : .live
    }
}

/// 屏下 5 个预设键：对应收藏前 5 台，当前台亮灯；收藏不够 5 台时空位变暗、点不动。
private struct LEDPresetRow: View {
    var model: RadioSkinModel

    var body: some View {
        let favourites = model.favourites(limit: 5)
        HStack(spacing: 6) {
            ForEach(0..<5, id: \.self) { slot in
                let entry = slot < favourites.count ? favourites[slot] : nil
                key(slot: slot, name: entry?.station.name)
            }
        }
        .frame(height: 30)
    }

    private func key(slot: Int, name: String?) -> some View {
        let current = name != nil && slot == model.index
        let enabled = name != nil && !model.isPreview
        return Button {
            guard enabled, !current else { return }
            model.onTune(slot)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
                HStack(spacing: 0) {
                    ZStack {
                        if current {
                            Circle().fill(LEDLook.lamp.opacity(0.2)).frame(width: 13, height: 13)
                        }
                        Circle()
                            .fill(current ? LEDLook.lamp : Color.white.opacity(0.18))
                            .frame(width: 6.8, height: 6.8)
                    }
                    .frame(width: 24)
                    Text(verbatim: RadioDial.channelText(slot))
                        .font(.system(size: 15, weight: current ? .bold : .medium).monospacedDigit())
                        .foregroundStyle(model.colors.text.opacity(name == nil ? 0.3 : (current ? 1 : 0.75)))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                    Spacer(minLength: 6)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(RadioRetroPress())
        .allowsHitTesting(enabled)
        .help(name ?? "")
        .accessibilityLabel(Text(verbatim: name ?? RadioDial.channelText(slot)))
        .accessibilityAddTraits(current ? .isSelected : [])
    }
}

// MARK: - 卡片

/// 灯阵：212 × 62 卡片的内容；`vertical` 时是侧边竖排的小卡片。
struct RadioSkinLEDCard: RadioSkinCardFace {
    var model: RadioSkinModel
    var vertical: Bool

    var body: some View {
        if vertical {
            VStack(spacing: 4) {
                LEDBadge(digits: model.channelText)
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
                LEDBadge(digits: model.channelText)
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
        return Button {
            guard !model.isPreview else { return }
            model.onToggle()
        } label: {
            Image(systemName: symbol)
                .playPauseMorph(symbol)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(colors.ink)
                .frame(width: size, height: size)
                .background(Circle().fill(colors.accent))
                .contentShape(Circle())
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

/// 卡片左边的小 LED 窗：13 × 13 个点，写频道号，不带柔光、不动。
private struct LEDBadge: View {
    var digits: String

    var body: some View {
        let lit = Set(LEDLook.glyphCells(digits, scale: 1, dx: 1, dy: 3).cells)
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let pitch = (side - side * 0.07) / 13
            Canvas { ctx, size in
                LEDLook.draw(&ctx, size: size, cols: 13, rows: 13, pitch: pitch, lit: lit,
                             dot: pitch * 0.38, unlit: 0.10, halo: false)
            }
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(LEDLook.window))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.black.opacity(0.5), lineWidth: 1))
        .accessibilityHidden(true)
    }
}
