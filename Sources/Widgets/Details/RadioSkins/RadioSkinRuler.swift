import SwiftUI

// 收音机外观：墨白直尺。
//
// 纯黑白排版，红指针固定在中间，左右拖刻度换台；只用黑、白、一点红，字号拉开层级，当前行用细线标出。
// 设计稿 design/radio-skins2.png 第 5 列，配色和尺寸见 design/radio-skins2.py 的 skin_mono / tile_mono
// （面板按 1.25 倍、卡片按 264 × 62 画，卡片落到 212 × 62 时按比例收窄）。
//
// 只改这个文件。数据和回调都在 `RadioSkinModel`（见 RadioSkinKit.swift）。
// 面板一律用暗色版（用户定的），卡片跟扩展栏深浅走 `model.tone`。

/// 墨白直尺自己的装饰色：指针、音量钮的红。
private enum RulerInk {
    static func red(_ tone: RadioSkinTone) -> Color {
        tone == .dark ? Color(hex: "#FF4433") : Color(hex: "#D7261A")
    }

    /// 面板固定用暗色版：把模型换成暗色那组颜色。
    static func darkModel(_ model: RadioSkinModel) -> RadioSkinModel {
        guard model.tone != .dark, let palette = RadioSkinPalette.palette(.ruler, tone: .dark) else { return model }
        var dark = model
        dark.tone = .dark
        dark.palette = palette
        return dark
    }
}

// MARK: - 面板

/// 墨白直尺：面板上半部分（头一行、主视觉、台名、走带键、音量），宽 288pt。
struct RadioSkinRulerPanel: RadioSkinPanelFace {
    var model: RadioSkinModel

    init(model: RadioSkinModel) {
        self.model = model
    }

    /// 整张面板卡片的底：和上半部分一样固定暗色。
    static func backdrop(_ model: RadioSkinModel) -> some View {
        RadioSkinBackdrop(model: RulerInk.darkModel(model))
    }

    var body: some View {
        let model = RulerInk.darkModel(self.model)
        VStack(alignment: .leading, spacing: 12) {
            RulerHeader(model: model)
            RulerHero(model: model)
                .padding(.bottom, 10)
            RadioSkinReadout(model: model)
            RulerTransport(model: model)
                .padding(.vertical, 2)
            RulerVolume(model: model)
        }
        .environment(\.colorScheme, .dark)
    }
}

/// 头一行：左“网络电台”，右边红点和状态字（暂停时点变灰）。
private struct RulerHeader: View {
    var model: RadioSkinModel

    var body: some View {
        let colors = model.colors
        HStack(spacing: 6) {
            Text(verbatim: tr("网络电台"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(colors.text.opacity(min(1, model.palette.secondaryOpacity + 0.08)))
            Spacer()
            Circle()
                .fill(model.playing ? RulerInk.red(model.tone) : colors.text.opacity(0.35))
                .frame(width: 6.4, height: 6.4)
            Text(verbatim: model.status)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(colors.text.opacity(model.playing ? 0.88 : 0.6))
                .lineLimit(1)
        }
    }
}

/// 大号频道数字 + 横向卷尺刻度。红指针固定在中间，拖刻度左右走，松手吸附到最近的收藏；
/// 点一下刻度也能直接调到那一台。拖动时大数字跟着指针下那一台变。
private struct RulerHero: View {
    var model: RadioSkinModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 拖动或吸附途中刻度的位置（按台计，可以带小数）；nil 时跟 `model.index`。
    @State private var dragPosition: Double?
    /// 这次拖动开始时的位置。
    @State private var dragStart: Double?
    /// 每吸附一次加一，用来在吸附后把 `dragPosition` 收回去。
    @State private var settleToken = 0

    private var interactive: Bool { !model.isPreview && model.count > 0 }
    private var lastIndex: Int { max(0, model.count - 1) }
    private var position: Double { dragPosition ?? Double(RadioDial.clamp(model.index, count: model.count)) }
    /// 指针下最近的那一台。
    private var nearest: Int { RadioDial.clamp(Int(position.rounded()), count: model.count) }
    private var snap: Animation? {
        reduceMotion || model.isPreview ? nil : .spring(duration: 0.34, bounce: 0.12)
    }

    var body: some View {
        let colors = model.colors
        VStack(alignment: .leading, spacing: -14) {
            numberRow(colors)
            ruler(colors)
        }
    }

    // MARK: 大数字

    private func numberRow(_ colors: RadioSkinColors) -> some View {
        let number = model.count == 0 ? "--" : RadioDial.channelText(nearest)
        return HStack(alignment: .lastTextBaseline, spacing: 10) {
            Text(verbatim: number)
                .font(.system(size: 92, weight: .bold))
                .tracking(-4)
                .monospacedDigit()
                .foregroundStyle(colors.text)
                .lineLimit(1)
                .contentTransition(.numericText(value: Double(nearest)))
                .animation(reduceMotion || model.isPreview ? nil : .snappy(duration: 0.22), value: nearest)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: tr("频道"))
                    .font(.system(size: 13, weight: .semibold))
                Text(verbatim: "/ \(model.totalText)")
                    .font(.system(size: 20, weight: .medium).monospacedDigit())
            }
            .foregroundStyle(colors.secondary)
            .lineLimit(1)
            .alignmentGuide(.lastTextBaseline) { $0[.lastTextBaseline] + 14 }
            Spacer(minLength: 0)
            if model.count > 1 {
                Text(verbatim: tr("拖动刻度换台"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(colors.secondary)
                    .lineLimit(1)
                    .alignmentGuide(.lastTextBaseline) { $0[.lastTextBaseline] + 38 }
            }
        }
        .padding(.leading, -3)
    }

    // MARK: 刻度

    private func ruler(_ colors: RadioSkinColors) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                RulerTape(position: position, count: model.count, current: nearest, ink: colors.text)
                    .animation(snap, value: model.index)
                    .mask {
                        // 设计稿：离指针每远 150pt 淡掉 75%，两头再渐隐到底色。
                        LinearGradient(stops: [.init(color: .clear, location: 0),
                                               .init(color: .black.opacity(0.54), location: 0.18),
                                               .init(color: .black, location: 0.5),
                                               .init(color: .black.opacity(0.54), location: 0.82),
                                               .init(color: .clear, location: 1)],
                                       startPoint: .leading, endPoint: .trailing)
                    }
                RulerNeedle(color: RulerInk.red(model.tone),
                            pulsing: model.buffering && !model.isPreview && !reduceMotion)
                    .frame(width: 12, height: RulerScale.lineY + 38)
                    .offset(x: width / 2 - 6)
                    .allowsHitTesting(false)
            }
            .contentShape(.rect)
            .gesture(drag(width: width), including: interactive ? .all : .subviews)
        }
        .frame(height: RulerScale.height)
        .sensoryFeedback(.alignment, trigger: nearest) { _, _ in dragStart != nil }
        .task(id: settleToken) {
            // 吸附动画走完后交回 `model.index`；换台没成功时刻度也会回到原来那一台。
            guard settleToken > 0 else { return }
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, dragStart == nil else { return }
            withAnimation(snap) { dragPosition = nil }
        }
        .onChange(of: model.index) { _, _ in
            if dragStart == nil, let held = dragPosition, Int(held.rounded()) == model.index {
                dragPosition = nil
            }
        }
        .accessibilityElement()
        .accessibilityLabel(tr("调台"))
        .accessibilityValue(model.count == 0 ? model.stationName : "\(model.channelOfTotal) \(model.stationName)")
        .accessibilityAdjustableAction { direction in
            guard interactive else { return }
            switch direction {
            case .increment: if model.index < lastIndex { model.onTune(model.index + 1) }
            case .decrement: if model.index > 0 { model.onTune(model.index - 1) }
            @unknown default: break
            }
        }
        .help(model.count > 1 ? tr("拖动刻度换台") : "")
    }

    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                guard interactive else { return }
                let start = dragStart ?? position
                if dragStart == nil { dragStart = start }
                let raw = start - Double(drag.translation.width / RulerScale.stationStep)
                dragPosition = rubberBand(raw)
            }
            .onEnded { drag in
                guard interactive else { return }
                let start = dragStart ?? position
                dragStart = nil
                let landing: Double
                if abs(drag.translation.width) < 3 {
                    // 点一下：调到点的那根刻度对应的台。
                    landing = start + Double((drag.location.x - width / 2) / RulerScale.stationStep)
                } else {
                    landing = start - Double(drag.translation.width / RulerScale.stationStep)
                }
                settle(to: RadioDial.clamp(Int(landing.rounded()), count: model.count))
            }
    }

    /// 拖过两头时只走三成，松手弹回。
    private func rubberBand(_ raw: Double) -> Double {
        let top = Double(lastIndex)
        if raw < 0 { return raw * 0.3 }
        if raw > top { return top + (raw - top) * 0.3 }
        return raw
    }

    private func settle(to target: Int) {
        withAnimation(snap) { dragPosition = Double(target) }
        if target != model.index { model.onTune(target) }
        settleToken += 1
    }
}

/// 刻度的尺寸：每台之间 12 小格，每格 4.2pt；底线在顶上往下 18pt（上面留给指针的小三角）。
private enum RulerScale {
    static let tick: CGFloat = 4.2
    static let ticksPerStation = 12
    static let stationStep: CGFloat = tick * CGFloat(ticksPerStation)
    static let lineY: CGFloat = 18
    static let height: CGFloat = 76

    enum Kind: Sendable {
        /// 每台一根，30pt，写台号。
        case major
        /// 每 6 小格一根，18pt。
        case mid
        /// 其余小格，11pt。
        case minor
    }
}

/// 一种刻度（长、中、短）连同底线以外的部分，`position` 可动画。
private struct RulerTicks: Shape {
    var position: Double
    var count: Int
    var kind: RulerScale.Kind

    var animatableData: Double {
        get { position }
        set { position = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let tick = RulerScale.tick
        let perStation = RulerScale.ticksPerStation
        let center = rect.midX
        let lineY = RulerScale.lineY
        let centerTick = position * Double(perStation)
        let reach = Double(rect.width / 2 / tick) + 2
        let low = Int((centerTick - reach).rounded(.down))
        let high = Int((centerTick + reach).rounded(.up))
        var path = Path()
        guard low <= high else { return path }
        for k in low...high {
            let x = center + CGFloat(Double(k) - centerTick) * tick
            guard x >= rect.minX - 1, x <= rect.maxX + 1 else { continue }
            let major = k >= 0 && k % perStation == 0 && k / perStation < count
            let mid = !major && k % (perStation / 2) == 0
            let this: RulerScale.Kind = major ? .major : (mid ? .mid : .minor)
            guard this == kind else { continue }
            let length: CGFloat = major ? 30 : (mid ? 18 : 11)
            path.move(to: CGPoint(x: x, y: lineY))
            path.addLine(to: CGPoint(x: x, y: lineY + length))
        }
        return path
    }
}

/// 卷尺本身：底线、每台 12 小格（每 6 格一根中刻度，每台一根长刻度并写台号）。
/// 离指针越远越淡由外面的渐变遮罩做。刻度是可动画的 Shape、台号是跟着位置偏移的字，
/// 所以吸附、上一台下一台都是滑过去的，不用定时器。
private struct RulerTape: View {
    var position: Double
    var count: Int
    var current: Int
    var ink: Color

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let lineY = RulerScale.lineY
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(ink.opacity(0.35))
                    .frame(width: width, height: 0.8)
                    .offset(y: lineY - 0.4)
                RulerTicks(position: position, count: count, kind: .minor)
                    .stroke(ink.opacity(0.4), lineWidth: 0.8)
                RulerTicks(position: position, count: count, kind: .mid)
                    .stroke(ink.opacity(0.4), lineWidth: 0.8)
                RulerTicks(position: position, count: count, kind: .major)
                    .stroke(ink.opacity(0.9), lineWidth: 1.4)
                ForEach(visibleStations(width: width), id: \.self) { station in
                    let isCurrent = station == current
                    Text(verbatim: RadioDial.channelText(station))
                        .font(.system(size: isCurrent ? 15 : 13, weight: isCurrent ? .bold : .medium).monospacedDigit())
                        .foregroundStyle(ink.opacity(isCurrent ? 1 : 0.7))
                        .fixedSize()
                        .frame(width: 40, height: 20)
                        .position(x: width / 2 + CGFloat(Double(station) - position) * RulerScale.stationStep,
                                  y: lineY + 44)
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// 指针两边各一屏多一点的台，60 个收藏时也只画七八个字。
    private func visibleStations(width: CGFloat) -> [Int] {
        guard count > 0 else { return [] }
        let reach = Double(width / 2 / RulerScale.stationStep) + 1.5
        let low = max(0, Int((position - reach).rounded(.down)))
        let high = min(count - 1, Int((position + reach).rounded(.up)))
        return low <= high ? Array(low...high) : []
    }
}

/// 固定在中间的红色细指针，顶上一个小三角；连接、缓冲时慢慢一明一暗（读“减少动态效果”时不动）。
private struct RulerNeedle: View {
    var color: Color
    var pulsing: Bool

    var body: some View {
        if pulsing {
            PhaseAnimator([1.0, 0.35]) { phase in
                shape.opacity(phase)
            } animation: { _ in
                .easeInOut(duration: 0.7)
            }
        } else {
            shape
        }
    }

    private var shape: some View {
        Canvas { context, size in
            let mid = size.width / 2
            let lineY = RulerScale.lineY
            var head = Path()
            head.move(to: CGPoint(x: mid - 5, y: lineY - 18))
            head.addLine(to: CGPoint(x: mid + 5, y: lineY - 18))
            head.addLine(to: CGPoint(x: mid, y: lineY - 11))
            head.closeSubpath()
            context.fill(head, with: .color(color))
            var stem = Path()
            stem.move(to: CGPoint(x: mid, y: lineY - 14))
            stem.addLine(to: CGPoint(x: mid, y: lineY + 38))
            context.stroke(stem, with: .color(color), lineWidth: 2)
        }
        .accessibilityHidden(true)
    }
}

/// 上一台、播放、下一台：两侧 38pt 描边圆钮，中间 54pt 实心圆钮（暗色白底黑图标；
/// 浅色浅灰底加黑描边）。
private struct RulerTransport: View {
    var model: RadioSkinModel

    var body: some View {
        HStack(spacing: 10) {
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
        let size: CGFloat = main ? 54 : 38
        let light = model.palette.isLight
        return Button(action: action) {
            Image(systemName: symbol)
                .playPauseMorph(symbol, enabled: main)
                .font(.system(size: size * (main ? 0.36 : 0.34), weight: .bold))
                .foregroundStyle(main ? colors.ink : colors.text)
                .frame(width: size, height: size)
                .background(Circle().fill(main ? colors.accent : Color.clear))
                .overlay(Circle().strokeBorder(main ? colors.text.opacity(light ? 1 : 0) : colors.text.opacity(0.35),
                                               lineWidth: main ? 2 : 1.2))
                .contentShape(Circle())
        }
        .buttonStyle(RadioRetroPress())
        .help(label)
        .accessibilityLabel(label)
    }
}

/// 音量：喇叭、细条（底 14% 正文色，填充正文色）、一根红色竖钮、百分比。拖动时只调播放器，松手才存。
private struct RulerVolume: View {
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
                    Capsule().fill(colors.text.opacity(model.palette.isLight ? 0.12 : 0.14)).frame(height: 6)
                    Capsule().fill(colors.text).frame(width: max(0, x), height: 6)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(RulerInk.red(model.tone))
                        .frame(width: 3, height: 18)
                        .offset(x: min(max(0, x - 1.5), max(0, width - 3)))
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

/// 墨白直尺：212 × 62 卡片的内容；`vertical` 时是侧边竖排的小卡片。
/// 左边大号频道数字，下面一小段刻度和红指针；中间台名和“频道 03 / 05”；右边实心播放键和下一台。
struct RadioSkinRulerCard: RadioSkinCardFace {
    var model: RadioSkinModel
    var vertical: Bool

    var body: some View {
        if vertical {
            VStack(spacing: 4) {
                art(numberSize: 22, width: 36)
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
            HStack(spacing: 8) {
                art(numberSize: 28, width: 42)
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

    /// 频道号和下面 9 根小刻度（第 1、5、9 根长），红指针在正中。
    private func art(numberSize: CGFloat, width: CGFloat) -> some View {
        let colors = model.colors
        let red = RulerInk.red(model.tone)
        return VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: model.channelText)
                .font(.system(size: numberSize, weight: .bold))
                .tracking(-1.5)
                .monospacedDigit()
                .foregroundStyle(colors.text)
                .lineLimit(1)
                .fixedSize()
                .frame(height: numberSize * 1.05)
            Canvas { context, size in
                let step = size.width / 8
                for k in 0...8 {
                    let x = CGFloat(k) * step + 0.4
                    var mark = Path()
                    mark.move(to: CGPoint(x: x, y: 4))
                    mark.addLine(to: CGPoint(x: x, y: 4 + (k % 4 == 0 ? 6 : 3.5)))
                    context.stroke(mark, with: .color(colors.text.opacity(0.5)), lineWidth: 0.8)
                }
                var needle = Path()
                needle.move(to: CGPoint(x: size.width / 2, y: 0))
                needle.addLine(to: CGPoint(x: size.width / 2, y: size.height))
                context.stroke(needle, with: .color(red), lineWidth: 1.6)
            }
            .frame(width: width * 0.86, height: 12)
        }
        .frame(width: width, alignment: .leading)
        .accessibilityHidden(true)
    }

    private func playButton(size: CGFloat) -> some View {
        let colors = model.colors
        let symbol = model.playing ? "pause.fill" : "play.fill"
        let light = model.palette.isLight
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
                .overlay(Circle().strokeBorder(colors.text.opacity(light ? 1 : 0), lineWidth: 1.6))
                .contentShape(Circle())
        }
        .buttonStyle(RadioRetroPress())
        .allowsHitTesting(!model.isPreview && model.canPlay)
        .help(model.playing ? tr("暂停") : tr("收听"))
        .accessibilityLabel(model.playing ? tr("暂停收音机") : tr("收听 \(model.stationName)"))
    }

    private func nextButton(size: CGFloat) -> some View {
        TileGlyph(symbol: "forward.end.fill", size: size, tint: model.colors.text,
                  action: model.isPreview || !model.canStep ? nil : model.onNext)
            .help(tr("下一个电台"))
            .accessibilityLabel(tr("下一个电台"))
    }
}
