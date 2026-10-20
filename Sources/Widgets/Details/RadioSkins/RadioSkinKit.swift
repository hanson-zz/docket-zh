import SwiftUI

// 收音机五款新外观（烟晶、灯阵、瓷白圆盘、掌机像素、墨白直尺）共用的接口。
//
// 面板（RadioDetail）和卡片（RadioTile）把当前台、播放状态、音量和各种回调装进
// 一个 `RadioSkinModel`，再按 `skin` 分发到 RadioSkins/ 下各皮肤自己的文件：
//
//     RadioSkinSmoke.swift      烟晶       RadioSkinSmokePanel / RadioSkinSmokeCard
//     RadioSkinLED.swift        灯阵       RadioSkinLEDPanel / RadioSkinLEDCard
//     RadioSkinPorcelain.swift  瓷白圆盘   RadioSkinPorcelainPanel / RadioSkinPorcelainCard
//     RadioSkinPixel.swift      掌机像素   RadioSkinPixelPanel / RadioSkinPixelCard
//     RadioSkinRuler.swift      墨白直尺   RadioSkinRulerPanel / RadioSkinRulerCard
//
// 每套皮肤只改自己的文件：
// - `…Panel` 画面板上半部分：头一行、主视觉、台名和说明、走带键、音量（宽 288pt，
//   面板 320 减两边 16）。下面的定时关闭、收藏/搜索、收藏列表由 RadioDetail 画，
//   收藏当前行的标法跟 `RadioSkinPalette.rowStyle` 走，颜色跟调色板走。
// - `…Panel.backdrop(_:)` 画面板底（整张深色卡片的背景），默认 `RadioSkinBackdrop`。
// - `…Card` 画 212 × 62 卡片里的内容（横排）或侧边竖排时的内容（`vertical`）。
//   卡片外面的底板由 WidgetSurface 画，卡片上除两个按钮外的点击属于扩展栏（打开面板），
//   所以按钮只占自己那么大。
//
// 颜色一律从 `model.colors` 取（暗色、浅色两版由 `model.tone` 决定，已经选好）；
// 皮肤自己的装饰色写在自己的文件里，浅色版不同就按 `model.tone` 分。字最小 13pt，
// 实心按钮上的图标用 `colors.ink`。预览（添加小组件面板）里 `model.isPreview` 为
// true，回调什么也不做，动画应停住；“减少动态效果”请各自读环境值。
//
// 第一版五个文件都先用 `RadioSkinBasicPanel` / `RadioSkinBasicCard`（经典的布局
// 换上各自配色），保证可选、可播放，后续再各自照设计稿 design/radio-skins2.png 重画。

/// 新外观拿到的全部数据和回调。
struct RadioSkinModel {
    var skin: RadioSkin
    /// 当前内容是深色还是浅色；`palette` 已按它选好。
    var tone: RadioSkinTone
    var palette: RadioSkinPalette
    /// 全部收藏（预览里是预置电台）。
    var stations: [RadioStation]
    /// 调到的那一台在 `stations` 里的位置，列表为空时是 0。
    var index: Int
    /// 这张卡片调到的台正在出声（预览里总是 true）。
    var playing: Bool
    /// 正在连接或缓冲。
    var buffering: Bool
    /// 头一行右边的状态：“正在收听”“已暂停”“正在连接…”。
    var status: String
    /// 台名下面那一行：“MP3 · 64 kbps · 频道 03 / 05”，播放中出错或有节目名时换成那一句。
    var detail: String
    /// `detail` 是连接问题，用 `colors.accentText` 标出来。
    var detailIsProblem: Bool
    /// 卡片第二行：节目名、“已暂停”“正在连接…”等。
    var caption: String
    /// 0 到 100。
    var volume: Double
    var isPreview: Bool

    /// 换到第 `index` 个收藏（保持原来的播放状态）。
    var onTune: (Int) -> Void
    var onPrevious: () -> Void
    var onNext: () -> Void
    /// 播放 / 暂停。
    var onToggle: () -> Void
    /// 拖动音量时连续调用（只调播放器），松手时调 `onVolumeEnd` 才存。
    var onVolume: (Double) -> Void
    var onVolumeEnd: () -> Void

    var colors: RadioSkinColors { RadioSkinColors(palette) }
    var count: Int { stations.count }
    var station: RadioStation? { stations.isEmpty ? nil : stations[RadioDial.clamp(index, count: count)] }
    var stationName: String { station?.name ?? tr("还没有电台") }
    var canPlay: Bool { station != nil }
    var canStep: Bool { count > 1 }
    /// “03”。
    var channelText: String { station == nil ? "--" : RadioDial.channelText(index) }
    /// “05”：收藏总数，和频道号一样两位。
    var totalText: String { RadioDial.channelText(max(0, count - 1)) }
    /// “频道 03 / 05”。
    var channelOfTotal: String { RadioDial.channelOfTotal(index, count: count) }
    /// 按收藏顺序排的 FM 位置（见 `RadioDial.frequency`）。
    var frequency: Double { RadioDial.frequency(index, count: count) }
    /// 收藏的前 `limit` 台，带各自的位置，用来画预设键、小格子。
    func favourites(limit: Int) -> [(offset: Int, station: RadioStation)] {
        Array(stations.prefix(max(0, limit)).enumerated()).map { (offset: $0.offset, station: $0.element) }
    }
    /// 围着当前台的几行（比如设计稿里的 02、03、04），不够时靠边取。
    func favouritesAround(rows: Int) -> [(offset: Int, station: RadioStation)] {
        guard count > 0, rows > 0 else { return [] }
        let shown = min(rows, count)
        let start = min(max(0, index - shown / 2), count - shown)
        return (start..<(start + shown)).map { (offset: $0, station: stations[$0]) }
    }
}

/// 调色板换成 SwiftUI 颜色。
struct RadioSkinColors {
    var background: Color
    var text: Color
    /// 次要字：`text` 按调色板的不透明度。
    var secondary: Color
    var accent: Color
    var accentText: Color
    /// 实心强调上的图标，一律深色。
    var ink: Color
    /// 分隔线基色，用时配很低的不透明度。
    var line: Color
    /// 音量条这类填充：强调色压在底色上太淡（墨白直尺浅色版的浅灰）时换成正文色。
    var fill: Color

    init(_ palette: RadioSkinPalette) {
        background = Color(code: palette.background)
        text = Color(code: palette.text)
        secondary = Color(code: palette.text).opacity(palette.secondaryOpacity)
        accent = Color(code: palette.accent)
        accentText = Color(code: palette.accentText)
        ink = Color(code: palette.ink)
        line = Color(code: palette.line)
        fill = WidgetTint.contrastRatio(palette.accent, palette.background) >= 1.25
            ? Color(code: palette.accent) : Color(code: palette.text)
    }
}

// MARK: - 每套皮肤要实现的两个结构

/// 面板上半部分。`backdrop` 是整张面板卡片的底。
protocol RadioSkinPanelFace: View {
    associatedtype Backdrop: View
    init(model: RadioSkinModel)
    @MainActor @ViewBuilder static func backdrop(_ model: RadioSkinModel) -> Backdrop
}

/// 卡片内容。`vertical` 为 true 时是侧边扩展栏的竖排小卡片。
protocol RadioSkinCardFace: View {
    init(model: RadioSkinModel, vertical: Bool)
}

// MARK: - 分发

/// 面板上半部分，按皮肤分发。
struct RadioModernPanel: View {
    var model: RadioSkinModel

    var body: some View {
        switch model.skin {
        case .smoke: RadioSkinSmokePanel(model: model)
        case .led: RadioSkinLEDPanel(model: model)
        case .porcelain: RadioSkinPorcelainPanel(model: model)
        case .pixel: RadioSkinPixelPanel(model: model)
        case .ruler: RadioSkinRulerPanel(model: model)
        default: EmptyView()
        }
    }
}

/// 面板底，按皮肤分发。
struct RadioModernBackdrop: View {
    var model: RadioSkinModel

    var body: some View {
        switch model.skin {
        case .smoke: RadioSkinSmokePanel.backdrop(model)
        case .led: RadioSkinLEDPanel.backdrop(model)
        case .porcelain: RadioSkinPorcelainPanel.backdrop(model)
        case .pixel: RadioSkinPixelPanel.backdrop(model)
        case .ruler: RadioSkinRulerPanel.backdrop(model)
        default: RadioSkinBackdrop(model: model)
        }
    }
}

/// 卡片内容，按皮肤分发。
struct RadioModernCard: View {
    var model: RadioSkinModel
    var vertical: Bool

    var body: some View {
        switch model.skin {
        case .smoke: RadioSkinSmokeCard(model: model, vertical: vertical)
        case .led: RadioSkinLEDCard(model: model, vertical: vertical)
        case .porcelain: RadioSkinPorcelainCard(model: model, vertical: vertical)
        case .pixel: RadioSkinPixelCard(model: model, vertical: vertical)
        case .ruler: RadioSkinRulerCard(model: model, vertical: vertical)
        default: EmptyView()
        }
    }
}

// MARK: - 共用零件（各皮肤可以直接用，也可以自己画）

/// 纯色面板底。
struct RadioSkinBackdrop: View {
    var model: RadioSkinModel

    var body: some View {
        Rectangle().fill(model.colors.background)
    }
}

/// 头一行：左“网络电台”，右边状态点和状态字。
struct RadioSkinHeader: View {
    var model: RadioSkinModel

    var body: some View {
        let colors = model.colors
        HStack(spacing: 6) {
            Text(verbatim: tr("网络电台"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(colors.text.opacity(min(1, model.palette.secondaryOpacity + 0.08)))
            Spacer()
            Circle()
                .fill(model.playing ? colors.accentText : colors.text.opacity(0.35))
                .frame(width: 6.4, height: 6.4)
            Text(verbatim: model.status)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(colors.text.opacity(model.playing ? 0.88 : 0.6))
        }
    }
}

/// 台名（22pt）和下面一行说明（13pt）。
struct RadioSkinReadout: View {
    var model: RadioSkinModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: model.stationName)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(model.colors.text)
                .lineLimit(1)
                .minimumScaleFactor(13.0 / 22.0)
            Text(verbatim: model.detail)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(model.detailIsProblem ? model.colors.accentText : model.colors.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 上一台、播放、下一台：两侧 38pt 浅底圆钮，中间 54pt 实心强调圆钮，图标深色。
struct RadioSkinTransport: View {
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
                .background(Circle().fill(main ? colors.accent : colors.text.opacity(0.08)))
                .overlay(Circle().strokeBorder(main ? colors.ink.opacity(model.palette.accent.isLight ? 0.25 : 0)
                                                    : colors.text.opacity(0.12), lineWidth: main ? 1.2 : 0.6))
                .contentShape(Circle())
        }
        .buttonStyle(RadioRetroPress())
        .help(label)
        .accessibilityLabel(label)
    }
}

/// 音量：喇叭、强调色填充的条和圆钮、百分比。拖动时只调播放器，松手才存。
struct RadioSkinVolume: View {
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
                    Capsule().fill(colors.text.opacity(0.14)).frame(height: 6)
                    Capsule().fill(colors.fill).frame(width: max(0, x), height: 6)
                    Circle()
                        .fill(colors.background)
                        .overlay(Circle().strokeBorder(colors.accentText, lineWidth: 2))
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

/// 第一版的面板上半部分：经典的布局（大频道号、半圆刻度）换上皮肤配色。
struct RadioSkinBasicPanel: View {
    var model: RadioSkinModel

    var body: some View {
        let colors = model.colors
        VStack(alignment: .leading, spacing: 12) {
            RadioSkinHeader(model: model)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(verbatim: model.channelText)
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(colors.text)
                    .contentTransition(.numericText())
                    .animation(model.isPreview ? nil : .snappy, value: model.index)
                Text(verbatim: "/ \(model.totalText)")
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    .foregroundStyle(colors.secondary)
                Spacer(minLength: 0)
            }
            RadioArcDial(count: model.count, index: model.index, accent: colors.accentText,
                         needle: colors.accentText, ink: colors.text) { target in
                guard !model.isPreview else { return }
                model.onTune(target)
            }
            .frame(height: 92)
            RadioSkinReadout(model: model)
            RadioSkinTransport(model: model)
            RadioSkinVolume(model: model)
        }
    }
}

/// 第一版的卡片：左边圆角方块里写频道号，中间台名和说明，右边实心播放键和下一台。
struct RadioSkinBasicCard: View {
    var model: RadioSkinModel
    var vertical: Bool

    var body: some View {
        if vertical {
            VStack(spacing: 4) {
                art(size: 32)
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
                Spacer(minLength: 0)
                HStack(spacing: 2) {
                    playButton(size: 26)
                    nextButton(size: 12)
                }
            }
        }
    }

    private func art(size: CGFloat) -> some View {
        let colors = model.colors
        return Text(verbatim: model.channelText)
            .font(.system(size: size * 0.5, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(colors.accentText)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(colors.accent.opacity(0.16)))
            .overlay(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .strokeBorder(colors.text.opacity(0.12), lineWidth: 0.6))
            .accessibilityHidden(true)
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
                .overlay(Circle().strokeBorder(colors.ink.opacity(model.palette.accent.isLight ? 0.25 : 0),
                                               lineWidth: 1))
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
