import SwiftUI

// 收音机外观：烟晶（Pro）。
//
// 磨砂玻璃叠层，背后透出香槟和玫瑰色光斑；大频道号做渐变字，旁边一组电平小柱，玻璃频道条直接点 01 到 05 换台。
// 设计稿 design/radio-skins2.png 第 1 列，配色和尺寸见 design/radio-skins2.py 的 skin_glass / tile_glass
// （面板按 1.25 倍、卡片按 264 × 62 画，卡片落到 212 × 62 时按比例收窄）。
//
// 只改这个文件。数据和回调都在 `RadioSkinModel`（见 RadioSkinKit.swift）。
// 面板一律用暗色版（用户已定），所以面板和面板底都把调色板固定成暗色；卡片跟扩展栏深浅走 `model.tone`。
//
// 动画：播放中光斑缓慢漂移、电平小柱起伏，都用暂停得了的 TimelineView（低帧率），
// 暂停、连接中、预览、打开“减少动态效果”时停住不跑。光斑最浓 30%，不用蓝光。

/// 烟晶自己的装饰色。
private enum Smoke {
    static let champagne = Color(hex: "#F4C27A")
    static let rose = Color(hex: "#E98AA0")
    /// 大频道号和电平小柱的渐变两端（暗色版）。
    static let numberTop = Color(hex: "#FFE1A8")
    static let numberBottom = Color(hex: "#F08AA0")
    /// 小熊猫贴纸的白边。
    static let stickerEdge = Color(hex: "#FBF7EF")
    /// 电平小柱静止时的高度（0 到 1），照设计稿。
    static let levels: [Double] = [0.35, 0.6, 0.9, 0.7, 0.5, 0.8, 0.45, 0.65, 0.3]

    /// 面板固定用暗色版：换成暗色调色板，其余数据和回调原样。
    static func dark(_ model: RadioSkinModel) -> RadioSkinModel {
        guard model.tone != .dark, let palette = RadioSkinPalette.palette(model.skin, tone: .dark) else { return model }
        var copy = model
        copy.tone = .dark
        copy.palette = palette
        return copy
    }

    /// 光斑和电平该不该动。
    static func animates(_ model: RadioSkinModel, reduceMotion: Bool) -> Bool {
        model.playing && !model.buffering && !model.isPreview && !reduceMotion && model.canPlay
    }

    /// “/ 05”；一个收藏也没有时写“/ 00”，不写成“/ 01”。
    static func total(_ model: RadioSkinModel) -> String {
        model.count == 0 ? "00" : model.totalText
    }
}

// MARK: - 面板

/// 烟晶：面板上半部分（头一行、主视觉、台名、走带键、音量），宽 288pt。
struct RadioSkinSmokePanel: RadioSkinPanelFace {
    var model: RadioSkinModel

    /// 整张面板卡片的底：暗色底上两团被玻璃压住的暖色光斑。
    static func backdrop(_ model: RadioSkinModel) -> some View {
        RadioSkinSmokeBackdrop(model: Smoke.dark(model))
    }

    var body: some View {
        let model = Smoke.dark(self.model)
        VStack(alignment: .leading, spacing: 14) {
            RadioSkinHeader(model: model)
                .padding(.bottom, -2)
            RadioSkinSmokeHero(model: model)
            RadioSkinReadout(model: model)
            RadioSkinSmokeTransport(model: model)
                .padding(.vertical, 2)
            RadioSkinSmokeVolume(model: model)
        }
        .environment(\.colorScheme, .dark)
    }
}

/// 面板底：纯色底加两团光斑，播放中慢慢漂移。
struct RadioSkinSmokeBackdrop: View {
    var model: RadioSkinModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let live = Smoke.animates(model, reduceMotion: reduceMotion)
        ZStack(alignment: .topLeading) {
            Rectangle().fill(model.colors.background)
            TimelineView(.animation(minimumInterval: 1.0 / 12, paused: !live)) { context in
                let t = live ? context.date.timeIntervalSinceReferenceDate : 0
                ZStack(alignment: .topLeading) {
                    blob(Smoke.champagne, opacity: 0.30)
                        .position(x: 250 + 16 * sin(t * 2 * .pi / 23), y: 70 + 12 * cos(t * 2 * .pi / 29))
                    blob(Smoke.rose, opacity: 0.24)
                        .position(x: 70 + 14 * cos(t * 2 * .pi / 31), y: 190 + 16 * sin(t * 2 * .pi / 37))
                }
            }
            .allowsHitTesting(false)
        }
        .clipped()
        .accessibilityHidden(true)
    }

    /// 软光斑：径向渐变圆，代替模糊。
    private func blob(_ color: Color, opacity: Double) -> some View {
        Circle()
            .fill(RadialGradient(stops: [
                .init(color: color.opacity(opacity), location: 0),
                .init(color: color.opacity(opacity * 0.45), location: 0.55),
                .init(color: color.opacity(0), location: 1),
            ], center: .center, startRadius: 0, endRadius: 120))
            .frame(width: 240, height: 240)
    }
}

/// 主视觉：一块磨砂玻璃，上面“频道”、渐变大号、电平小柱，下面玻璃频道条。
private struct RadioSkinSmokeHero: View {
    var model: RadioSkinModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let colors = model.colors
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: tr("频道"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(colors.secondary)
                .padding(.leading, 6)
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text(verbatim: model.channelText)
                    .font(.system(size: 72, weight: .bold))
                    .monospacedDigit()
                    .tracking(-2)
                    .foregroundStyle(LinearGradient(colors: [Smoke.numberTop, Smoke.numberBottom],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                    .contentTransition(.numericText())
                    .animation(model.isPreview || reduceMotion ? nil : .snappy, value: model.index)
                    .lineLimit(1)
                    .fixedSize()
                Text(verbatim: "/ \(Smoke.total(model))")
                    .font(.system(size: 20, weight: .medium).monospacedDigit())
                    .foregroundStyle(colors.secondary)
                    .padding(.leading, 10)
                    .fixedSize()
                Spacer(minLength: 8)
                RadioSkinSmokeLevels(model: model)
                    .alignmentGuide(.lastTextBaseline) { $0[.bottom] }
            }
            .padding(.top, -6)
            .padding(.leading, 2)
            .padding(.trailing, 13)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.channelOfTotal)
            Spacer(minLength: 6)
            RadioSkinSmokeStrip(model: model)
        }
        .padding(.top, 18)
        .padding(.horizontal, 12)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 184)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.04)],
                                     startPoint: .topLeading, endPoint: UnitPoint(x: 0.3, y: 1)))
                .overlay(alignment: .top) {
                    // 玻璃顶上一道柔光。
                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                        .fill(.white.opacity(0.06))
                        .frame(height: 30)
                        .padding(1)
                }
                .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.28), lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
            sticker.padding(.top, 10).padding(.trailing, 18)
        }
    }

    /// 玻璃右上角的小熊猫贴纸。
    @ViewBuilder private var sticker: some View {
        if let image = PandaArt.image("pet-panda-idle") {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 20, height: 26)
                .padding(.horizontal, 3)
                .padding(.vertical, 2.5)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Smoke.stickerEdge))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(.black.opacity(0.25), lineWidth: 0.6))
                .rotationEffect(.degrees(9))
                .accessibilityHidden(true)
        }
    }
}

/// 电平小柱：装饰，播放中起伏，暂停时停在设计稿的高度并变淡。
private struct RadioSkinSmokeLevels: View {
    var model: RadioSkinModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let live = Smoke.animates(model, reduceMotion: reduceMotion)
        // 只有正在出声时是满色；暂停、连接中变淡。预览总在“播放”，按满色画。
        let lit = model.playing && !model.buffering
        TimelineView(.animation(minimumInterval: 1.0 / 15, paused: !live)) { context in
            let t = live ? context.date.timeIntervalSinceReferenceDate : 0
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Smoke.levels.indices, id: \.self) { i in
                    Capsule()
                        .fill(i % 2 == 1 ? Smoke.numberTop : Smoke.numberBottom)
                        .opacity(lit ? 0.85 : 0.4)
                        .frame(width: 5, height: 8 + height(i, t: t, live: live) * 46)
                }
            }
            .frame(height: 54, alignment: .bottom)
        }
        .accessibilityHidden(true)
    }

    /// 播放中按两条慢正弦叠出来的起伏，停住时用设计稿的高度。
    private func height(_ i: Int, t: TimeInterval, live: Bool) -> Double {
        let base = Smoke.levels[i]
        guard live else { return base }
        let d = Double(i)
        let wave = 0.5 + 0.3 * sin(t * (2.1 + d * 0.37) + d * 1.3) + 0.2 * sin(t * (3.3 + d * 0.21) + d * 0.7)
        return min(1, max(0.08, base * 0.45 + wave * 0.55))
    }
}

/// 玻璃频道条：最多 5 个频道号，点哪个换到哪台；收藏多于 5 个时取当前台前后 5 个。
private struct RadioSkinSmokeStrip: View {
    var model: RadioSkinModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let pill: CGFloat = 44.8

    var body: some View {
        let colors = model.colors
        HStack(spacing: 6) {
            if model.count == 0 {
                Text(verbatim: model.stationName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(colors.secondary)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(model.favouritesAround(rows: 5).map(\.offset), id: \.self) { offset in
                    pill(offset, name: model.stations[offset].name)
                }
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: 46)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.black.opacity(0.22)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(.white.opacity(0.16), lineWidth: 0.8))
    }

    private func pill(_ offset: Int, name: String) -> some View {
        let colors = model.colors
        let current = offset == RadioDial.clamp(model.index, count: model.count)
        return Button {
            guard !model.isPreview, !current else { return }
            model.onTune(offset)
        } label: {
            Text(verbatim: RadioDial.channelText(offset))
                .font(.system(size: 15, weight: current ? .bold : .medium).monospacedDigit())
                .foregroundStyle(current ? colors.ink : colors.text.opacity(0.8))
                .frame(width: Self.pill, height: 32)
                .background {
                    if current {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(colors.accent)
                            .overlay(alignment: .top) {
                                Rectangle().fill(.white.opacity(0.25)).frame(height: 14)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .animation(model.isPreview || reduceMotion ? nil : .snappy(duration: 0.22), value: current)
        }
        .buttonStyle(RadioRetroPress())
        .help(name)
        .accessibilityLabel(tr("收听 \(name)"))
        .accessibilityAddTraits(current ? .isSelected : [])
    }
}

/// 上一台、播放、下一台：两侧玻璃圆钮，中间香槟实心钮带一圈克制的柔光，图标深色。
private struct RadioSkinSmokeTransport: View {
    var model: RadioSkinModel

    var body: some View {
        HStack(spacing: 18) {
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
        return Button(action: action) {
            Image(systemName: symbol)
                .playPauseMorph(symbol, enabled: main)
                .font(.system(size: size * (main ? 0.36 : 0.34), weight: .bold))
                .foregroundStyle(main ? colors.ink : colors.text)
                .frame(width: size, height: size)
                .background {
                    if main {
                        Circle()
                            .fill(colors.accent)
                            .overlay {
                                // 左上一点高光，像玻璃珠。
                                Circle().fill(.white.opacity(0.22))
                                    .frame(width: size * 0.5, height: size * 0.5)
                                    .offset(x: -size * 0.1, y: -size * 0.175)
                            }
                            .clipShape(Circle())
                            .shadow(color: colors.accent.opacity(model.playing ? 0.3 : 0.15), radius: 8, y: 3)
                    } else {
                        Circle().fill(.white.opacity(0.10))
                    }
                }
                .overlay(Circle().strokeBorder(.white.opacity(main ? 0 : 0.25), lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(RadioRetroPress())
        .help(label)
        .accessibilityLabel(label)
    }
}

/// 音量：喇叭、香槟色填充的条、白色圆钮、百分比。拖动时只调播放器，松手才存。
private struct RadioSkinSmokeVolume: View {
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
                    Capsule().fill(.white.opacity(0.14)).frame(height: 6)
                    Capsule().fill(colors.accent).frame(width: max(0, x), height: 6)
                    Circle()
                        .fill(.white)
                        .overlay(Circle().strokeBorder(.black.opacity(0.15), lineWidth: 0.6))
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                        .frame(width: 16, height: 16)
                        .offset(x: x - 8)
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

/// 烟晶：212 × 62 卡片的内容；`vertical` 时是侧边竖排的小卡片。
/// 卡片跟扩展栏深浅：左边一块小玻璃，里面透出两团光斑和频道号；中间台名和说明；右边实心播放键和下一台。
struct RadioSkinSmokeCard: RadioSkinCardFace {
    var model: RadioSkinModel
    var vertical: Bool

    var body: some View {
        if vertical {
            VStack(spacing: 4) {
                art(size: 34)
                Text(verbatim: model.stationName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(model.colors.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 2) {
                    playButton(size: 24)
                    nextButton(size: 12)
                }
            }
        } else {
            HStack(spacing: 9) {
                art(size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: model.stationName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(model.colors.text)
                        .minimumScaleFactor(13.0 / 15.0)
                    Text(verbatim: model.caption)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(model.colors.secondary)
                        .monospacedDigit()
                }
                .lineLimit(1)
                .truncationMode(.tail)
                Spacer(minLength: 0)
                HStack(spacing: 2) {
                    playButton(size: 28)
                    nextButton(size: 12)
                }
            }
        }
    }

    private var dark: Bool { model.tone == .dark }

    /// 小玻璃块：暗色是深紫灰底、白字，浅色是暖纸色底、深棕字。
    private func art(size: CGFloat) -> some View {
        let radius = size * 0.26
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return ZStack {
            shape.fill(Color(hex: dark ? "#2A2530" : "#F6EEE6"))
            spot(Smoke.champagne, opacity: 0.7, size: size)
                .offset(x: size * 0.35, y: -size * 0.39)
            spot(Smoke.rose, opacity: 0.6, size: size)
                .offset(x: -size * 0.35, y: size * 0.39)
            shape.fill(.white.opacity(dark ? 0.12 : 0.4))
            Text(verbatim: model.channelText)
                .font(.system(size: size * 0.48, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Color(hex: dark ? "#FFFFFF" : "#5A2E14"))
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(dark ? 0.4 : 1), lineWidth: 1))
        .accessibilityHidden(true)
    }

    private func spot(_ color: Color, opacity: Double, size: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(stops: [
                .init(color: color.opacity(opacity), location: 0),
                .init(color: color.opacity(opacity * 0.45), location: 0.55),
                .init(color: color.opacity(0), location: 1),
            ], center: .center, startRadius: 0, endRadius: size * 0.65))
            .frame(width: size * 1.3, height: size * 1.3)
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
                .overlay(Circle().strokeBorder(colors.ink.opacity(model.palette.accent.isLight ? 0.18 : 0),
                                               lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(RadioRetroPress())
        .allowsHitTesting(!model.isPreview && model.canPlay)
        .opacity(model.canPlay ? 1 : 0.5)
        .help(model.playing ? tr("暂停") : tr("收听"))
        .accessibilityLabel(model.playing ? tr("暂停收音机") : tr("收听 \(model.stationName)"))
    }

    private func nextButton(size: CGFloat) -> some View {
        TileGlyph(symbol: "forward.end.fill", size: size, tint: model.colors.text,
                  action: model.isPreview || !model.canStep ? nil : model.onNext)
            .opacity(model.canStep ? 1 : 0.4)
            .help(tr("下一个电台"))
            .accessibilityLabel(tr("下一个电台"))
    }
}
