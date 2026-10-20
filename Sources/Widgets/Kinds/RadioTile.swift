import AppKit
import SwiftUI

/// 收音机：the tuned station with play and next on the card.
///
/// The favourites and the tuned channel are the widget's own contents
/// (`stations`, `index`, see RadioDial); the volume is its setting. Playback
/// is the one shared `RadioPlayer`, so the button always tells the truth
/// about the speaker, and a tile only shows itself as playing when the
/// station coming out of it is the one it is tuned to.
///
/// A click anywhere else on the card belongs to the shelf and opens the
/// panel, so the two controls are `TileGlyph`s the size of themselves.
struct RadioTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    /// 颜色面板里选的主题色，选过颜色时播放中的暖光跟着换。
    @Environment(\.widgetTint) private var theme
    @Environment(\.colorScheme) private var scheme
    // 和喝水一样读 @AppStorage：购买或试用到期时皮肤马上换，不用等下次重绘。
    @AppStorage(ProAccess.licenseKey) private var licenseUnlocked = false
    @AppStorage(Supporter.key) private var supporterUnlocked = false

    private var player: RadioPlayer { RadioPlayer.shared }

    private var unlocked: Bool { licenseUnlocked || supporterUnlocked || context.isPreview }
    /// 实际画的皮肤：经典以外都是 Pro，没解锁时画回经典，不盖锁，配置不改写。
    private var skin: RadioSkin { ProLicenseGate.radioSkin(config: instance.config, unlocked: unlocked) }

    private var stations: [RadioStation] { RadioDial.stations(instance.config) }
    private var index: Int { RadioDial.index(instance.config, count: stations.count) }
    private var station: RadioStation? { stations.isEmpty ? nil : stations[index] }
    private var volume: Double { instance.config.double("volume", default: 60) }

    private var playing: Bool { context.isPreview ? true : player.plays(station) }

    private var caption: String {
        if context.isPreview { return tr("正在收听") }
        guard station != nil else { return tr("在面板中添加电台") }
        guard playing else { return tr("已暂停") }
        if player.problem != nil { return tr("正在重新连接") }
        if player.isBuffering { return tr("正在连接…") }
        return player.nowTitle ?? tr("正在收听")
    }

    var body: some View {
        WidgetSurface {
            if station == nil {
                PandaEmptyTile(empty: .radio, title: tr("搜索电台"), instance: instance, context: context)
            } else if let model = skinModel {
                // 五款新外观：内容画在 RadioSkins/ 下各自的文件里，深浅跟着扩展栏走。
                RadioModernCard(model: model, vertical: context.position.isVertical)
            } else if skin.isRetro {
                retro
            } else if context.position.isVertical {
                VStack(spacing: 4) {
                    RadioIcon(size: 34, playing: playing, animated: !context.isPreview)
                    columnName
                    HStack(spacing: 2) {
                        playButton(size: 9)
                        nextButton(size: 8)
                    }
                }
            } else {
                HStack(spacing: 9) {
                    RadioIcon(size: 40, playing: playing, animated: !context.isPreview)
                    // 不用通用的 TileReading（第二行 11pt、整块可缩到 0.6）：
                    // 台名 15pt 最多缩到 13pt，第二行 13pt，放不下截断。
                    VStack(alignment: .leading, spacing: 2) {
                        Text(station?.name ?? tr("收音机"))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(WidgetStyle.primary)
                            .minimumScaleFactor(13.0 / 15.0)
                        Text(caption)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(WidgetStyle.secondary)
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                    HStack(spacing: 2) {
                        playButton(size: 11)
                        nextButton(size: 9)
                    }
                }
            }
        }
        .onChange(of: volume) { _, now in
            if !context.isPreview, player.plays(station) { player.setVolume(now) }
        }
    }

    // MARK: 新外观

    /// 交给新外观的数据和回调（见 RadioSkinKit.swift），经典和复古皮肤是 nil。
    /// 卡片的深浅读扩展栏当前的外观：白底、浅色玻璃是浅色，黑底、深色玻璃是深色，
    /// 其余跟系统（见 `ShelfLook.forcedAppearance`）。
    private var skinModel: RadioSkinModel? {
        let tone = RadioSkinTone(darkContent: scheme == .dark)
        guard skin.isModern, let palette = RadioSkinPalette.palette(skin, tone: tone) else { return nil }
        let preview = context.isPreview
        return RadioSkinModel(
            skin: skin, tone: tone, palette: palette, stations: stations, index: index,
            playing: playing, buffering: !preview && playing && player.isBuffering,
            status: caption,
            detail: station.map { "\($0.detail) · \(RadioDial.channelOfTotal(index, count: stations.count))" } ?? caption,
            detailIsProblem: !preview && playing && player.problem != nil,
            caption: modernCaption, volume: volume, isPreview: preview,
            onTune: { target in
                guard !preview else { return }
                RadioRemote.tune(instance, to: target)
            },
            onPrevious: {
                guard !preview, stations.count > 1 else { return }
                RadioRemote.tune(instance, to: RadioDial.previous(index, count: stations.count))
            },
            onNext: {
                guard !preview, stations.count > 1 else { return }
                RadioRemote.tune(instance, to: RadioDial.next(index, count: stations.count))
            },
            onToggle: {
                guard !preview, let station else { return }
                player.toggle(station, volume: volume, stations: stations, owner: instance.id)
            },
            onVolume: { value in
                guard !preview else { return }
                player.setVolume(value)
            },
            onVolumeEnd: {})
    }

    /// 新外观卡片第二行：照设计稿写“频道 03 / 05”；暂停、连接中、出错时写状态。
    private var modernCaption: String {
        let channel = RadioDial.channelOfTotal(index, count: stations.count)
        if context.isPreview { return channel }
        guard playing, player.problem == nil, !player.isBuffering else { return caption }
        return channel
    }

    // MARK: 复古皮肤

    /// 横排照设计稿：左边迷你机身，中间台名和 FM 数字（卡座写状态），右边实心
    /// 播放键和下一台。竖排把机身缩小放在上面。
    @ViewBuilder private var retro: some View {
        if context.position.isVertical {
            VStack(spacing: 4) {
                RadioRetroTileArt(skin: skin, count: stations.count, index: index, playing: playing,
                                  height: skin == .deck ? 28 : 32)
                columnName
                // 两个键都给足 24pt 点击区。
                HStack(spacing: 2) {
                    retroPlayButton(size: 24)
                    nextButton(size: 12)
                }
            }
        } else {
            HStack(spacing: 9) {
                RadioRetroTileArt(skin: skin, count: stations.count, index: index, playing: playing,
                                  height: skin == .deck ? 40 : 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(station?.name ?? tr("收音机"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(WidgetStyle.primary)
                        .minimumScaleFactor(13.0 / 15.0)
                    Text(retroCaption)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(WidgetStyle.secondary)
                        .monospacedDigit()
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                // 下一台的圆盘 24pt，和播放键一起都够 24pt 点击区。
                HStack(spacing: 2) {
                    retroPlayButton(size: 26)
                    nextButton(size: 12)
                }
            }
        }
    }

    /// 侧边竖排卡片只放电台名：13pt 起，最多两行，放不下截断，不再缩字。
    private var columnName: some View {
        Text(station?.name ?? tr("收音机"))
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(WidgetStyle.primary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 木壳和晶体管写“FM 98.0”，卡座的段码屏已经有频率，写状态；暂停、
    /// 连接中这些状态三款都照写。
    private var retroCaption: String {
        if skin == .deck { return caption }
        let fm = RadioDial.fmText(index, count: stations.count)
        if context.isPreview { return fm }
        guard playing, player.problem == nil, !player.isBuffering else { return caption }
        return fm
    }

    private func retroPlayButton(size: CGFloat) -> some View {
        Button {
            guard !context.isPreview, let station else { return }
            player.toggle(station, volume: volume, stations: stations, owner: instance.id)
        } label: {
            RadioRetroTilePlay(skin: skin, playing: playing, size: size)
                .contentShape(skin == .deck ? AnyShape(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
                                            : AnyShape(Circle()))
        }
        .buttonStyle(RadioRetroPress())
        .allowsHitTesting(!context.isPreview)
        .help(playing ? tr("暂停") : tr("收听"))
        .accessibilityLabel(playing ? tr("暂停收音机") : tr("收听 \(station?.name ?? tr("电台"))"))
    }

    private func playButton(size: CGFloat) -> some View {
        TileGlyph(symbol: playing ? "pause.fill" : "play.fill", size: size,
                  tint: playing ? theme.chosen(or: RadioIcon.glow, dark: scheme == .dark).mix(with: WidgetStyle.primary, by: 0.2)
                                : WidgetStyle.primary,
                  morphs: true,
                  action: context.isPreview || station == nil ? nil : {
            if let station { player.toggle(station, volume: volume, stations: stations, owner: instance.id) }
        })
        .help(playing ? tr("暂停") : tr("收听"))
        .accessibilityLabel(playing ? tr("暂停收音机") : tr("收听 \(station?.name ?? tr("电台"))"))
    }

    private func nextButton(size: CGFloat) -> some View {
        TileGlyph(symbol: "forward.end.fill", size: size,
                  action: context.isPreview || stations.count < 2 ? nil : {
            RadioRemote.tune(instance, to: RadioDial.next(index, count: stations.count))
        })
        .help("下一个电台")
        .accessibilityLabel("下一个电台")
    }
}

/// Tuning shared by the tile and the panel.
@MainActor
enum RadioRemote {
    /// Moves the dial to `index` and saves it. Keeps playing when the radio
    /// was playing, or starts when `play` says so.
    static func tune(_ instance: WidgetInstance, to index: Int, play: Bool = false) {
        let stations = RadioDial.stations(instance.config)
        guard !stations.isEmpty else { return }
        let target = RadioDial.clamp(index, count: stations.count)
        let wasPlaying = RadioPlayer.shared.isPlaying
        WidgetWriter.write(instance) { config in
            // An untouched widget reads the presets; writing the list down
            // keeps the index pointing at the station it was moved to.
            if config[RadioDial.stationsKey] == nil { RadioDial.store(stations, in: &config) }
            RadioDial.setIndex(target, in: &config)
        }
        if play || wasPlaying {
            RadioPlayer.shared.play(stations[target],
                                    volume: instance.config.double("volume", default: 60), stations: stations,
                                    owner: instance.id)
        }
    }

    /// Rewrites the favourites (and the dial with them) in one save.
    static func edit(_ instance: WidgetInstance,
                     _ change: (_ stations: inout [RadioStation], _ index: inout Int) -> Void) {
        var saved: [RadioStation] = []
        WidgetWriter.write(instance) { config in
            var stations = RadioDial.stations(config)
            var index = RadioDial.index(config, count: stations.count)
            change(&stations, &index)
            RadioDial.store(stations, in: &config)
            RadioDial.setIndex(RadioDial.clamp(index, count: stations.count), in: &config)
            saved = stations
        }
        // 播放器的换台列表跟着收藏走，删掉的电台不会再被媒体键播到。
        RadioPlayer.shared.syncPlaylist(saved, owner: instance.id)
    }
}

/// The cat-eared retro radio from meowRadio (MIT, see NOTICE.md), with a
/// warm glow and a small level meter while a station plays.
struct RadioIcon: View {
    var size: CGFloat
    var playing: Bool
    /// Off in previews and screenshots: the meter sits still at a level.
    var animated: Bool = true

    static let glow = Color(hex: "#FF9F2E")

    /// 卡片上读卡片的主题色，面板里读面板的强调色，都没选过就是原来的暖橙。
    @Environment(\.widgetTint) private var theme
    @Environment(\.panelTint) private var panelTint
    @Environment(\.colorScheme) private var scheme

    private var shownGlow: Color {
        panelTint.accent(or: theme.chosen(or: Self.glow, dark: scheme == .dark))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            art
                .frame(width: size * 0.9, height: size * 0.9)
                .clipShape(.rect(cornerRadius: size * 0.22, style: .continuous))
                .shadow(color: shownGlow.opacity(playing ? 0.75 : 0), radius: playing ? size * 0.16 : 0)
                .frame(width: size, height: size)
                .background {
                    RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                        .fill(shownGlow.opacity(playing ? 0.14 : 0))
                }
                .animation(.easeInOut(duration: 0.6), value: playing)
            if playing {
                RadioBars(active: animated, color: shownGlow, barWidth: max(1.5, size * 0.05),
                          height: size * 0.26)
                    .padding(size * 0.05)
                    .background(Capsule().fill(.black.opacity(0.45)))
                    .offset(x: size * 0.06, y: size * 0.04)
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var art: some View {
        if let image = RadioArt.image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "radio.fill")
                .font(.system(size: size * 0.48, weight: .medium))
                .foregroundStyle(playing ? shownGlow : WidgetStyle.primary)
        }
    }
}

@MainActor
enum RadioArt {
    /// A loose PNG in the bundle's Resources, like the sponsor codes.
    static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "RadioMeow", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()
}

/// Four bars bouncing like a level meter. Still, at a fixed level, when not
/// `active`.
struct RadioBars: View {
    var active: Bool
    var color: Color
    var barWidth: CGFloat = 2
    var height: CGFloat = 10

    /// 打开“减少动态效果”时柱子不跳，停在静止的高度。
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let phases: [Double] = [0, 1.7, 0.6, 2.4]
    private static let still: [Double] = [0.55, 0.9, 0.4, 0.7]

    var body: some View {
        let active = self.active && !reduceMotion
        TimelineView(.animation(minimumInterval: 1.0 / 12, paused: !active)) { tick in
            let t = tick.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: barWidth * 0.7) {
                ForEach(0..<4, id: \.self) { bar in
                    let level = active
                        ? 0.3 + 0.7 * abs(sin(t * (2.1 + Double(bar) * 0.45) + Self.phases[bar]))
                        : Self.still[bar]
                    Capsule()
                        .fill(color)
                        .frame(width: barWidth, height: max(barWidth, height * level))
                }
            }
            .frame(height: height, alignment: .bottom)
        }
    }
}
