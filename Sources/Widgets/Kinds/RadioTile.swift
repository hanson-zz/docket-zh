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

    private var player: RadioPlayer { RadioPlayer.shared }

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
            if context.position.isVertical {
                VStack(spacing: 4) {
                    RadioIcon(size: 34, playing: playing, animated: !context.isPreview)
                    Text(station?.name ?? tr("收音机"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WidgetStyle.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    HStack(spacing: 2) {
                        playButton(size: 9)
                        nextButton(size: 8)
                    }
                }
            } else {
                HStack(spacing: 9) {
                    RadioIcon(size: 40, playing: playing, animated: !context.isPreview)
                    TileReading(value: station?.name ?? tr("收音机"), caption: caption, valueSize: 15)
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

    private func playButton(size: CGFloat) -> some View {
        TileGlyph(symbol: playing ? "pause.fill" : "play.fill", size: size,
                  tint: playing ? RadioIcon.glow.mix(with: WidgetStyle.primary, by: 0.2) : WidgetStyle.primary,
                  morphs: true,
                  action: context.isPreview || station == nil ? nil : {
            if let station { player.toggle(station, volume: volume) }
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
                                    volume: instance.config.double("volume", default: 60))
        }
    }

    /// Rewrites the favourites (and the dial with them) in one save.
    static func edit(_ instance: WidgetInstance,
                     _ change: (_ stations: inout [RadioStation], _ index: inout Int) -> Void) {
        WidgetWriter.write(instance) { config in
            var stations = RadioDial.stations(config)
            var index = RadioDial.index(config, count: stations.count)
            change(&stations, &index)
            RadioDial.store(stations, in: &config)
            RadioDial.setIndex(RadioDial.clamp(index, count: stations.count), in: &config)
        }
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

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            art
                .frame(width: size * 0.9, height: size * 0.9)
                .clipShape(.rect(cornerRadius: size * 0.22, style: .continuous))
                .shadow(color: Self.glow.opacity(playing ? 0.75 : 0), radius: playing ? size * 0.16 : 0)
                .frame(width: size, height: size)
                .background {
                    RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                        .fill(Self.glow.opacity(playing ? 0.14 : 0))
                }
                .animation(.easeInOut(duration: 0.6), value: playing)
            if playing {
                RadioBars(active: animated, color: Self.glow, barWidth: max(1.5, size * 0.05),
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
                .foregroundStyle(playing ? Self.glow : WidgetStyle.primary)
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
