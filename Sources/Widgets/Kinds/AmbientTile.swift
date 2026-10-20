import SwiftUI

/// Rain, waves, wind, a fire or plain noise, with play and pause on the card.
///
/// The mix and the volume are the widget's settings (`sounds`, `volume`);
/// the panel picks them, each sound's level (`levels`), the saved mixes
/// (`mixes`, also on the card's right-click menu) and the sleep timer. Playback is one shared
/// `AmbientPlayer`, so the button always tells the truth about the speaker.
struct AmbientTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var player: AmbientPlayer { AmbientPlayer.shared }

    private var sounds: [AmbientSound] { AmbientSound.parse(instance.config.strings("sounds", default: ["rain"])) }
    private var volume: Double { instance.config.double("volume", default: 50) }
    private var levels: [AmbientSound: Int] { AmbientLevels.parse(instance.config.strings(AmbientLevels.key, default: [])) }
    /// 正在用的组合的名字，没有对上哪个组合时是声音的摘要。
    private var title: String {
        let mixes = AmbientMixes.all(instance.config.strings(AmbientMixes.key, default: []))
        return AmbientMixes.matching(sounds: sounds, levels: levels, in: mixes)?.name ?? AmbientSound.summary(sounds)
    }

    private var playing: Bool { context.isPreview ? true : player.isPlaying }

    private var caption: String {
        if context.isPreview { return tr("24:13 后停止") }
        guard player.isPlaying else { return sounds.isEmpty ? tr("在设置中选择声音") : tr("已暂停") }
        if let end = player.stopAt { return tr("\(AmbientTimer.remaining(until: end, now: context.now)) 后停止") }
        return tr("正在播放")
    }

    var body: some View {
        let symbol = sounds.first?.symbol ?? "speaker.wave.2"
        return WidgetSurface {
            if context.position.isVertical {
                VStack(spacing: 4) {
                    TileBadge(size: WidgetStyle.badgeCompact) { mark(symbol, size: 14) }
                    Text(sounds.first?.title ?? tr("环境音"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WidgetStyle.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    playButton(size: 10)
                }
            } else {
                HStack(spacing: WidgetStyle.rowSpacing) {
                    TileBadge { mark(symbol, size: 17) }
                    TileReading(value: title, caption: caption, valueSize: 16)
                    Spacer(minLength: 0)
                    playButton(size: 12)
                }
            }
        }
        .onAppear { if !context.isPreview { player.apply(sounds: sounds, levels: levels, volume: volume) } }
        .onChange(of: sounds) { _, now in
            if !context.isPreview { player.apply(sounds: now, levels: levels, volume: volume) }
        }
        .onChange(of: levels) { _, now in
            if !context.isPreview { player.apply(sounds: sounds, levels: now, volume: volume) }
        }
        .onChange(of: volume) { _, now in
            if !context.isPreview { player.apply(sounds: sounds, levels: levels, volume: now) }
        }
    }

    private func mark(_ symbol: String, size: CGFloat) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(playing ? tint : WidgetStyle.primary)
            .symbolEffect(.variableColor.iterative, options: .repeating, isActive: playing && !context.isPreview)
    }

    private var tint: Color {
        Color(hex: PaletteColor.teal.hex).mix(with: WidgetStyle.primary, by: 0.25)
    }

    private func playButton(size: CGFloat) -> some View {
        TileGlyph(symbol: playing ? "pause.fill" : "play.fill", size: size,
                  action: context.isPreview || sounds.isEmpty ? nil : {
            player.toggle(sounds: sounds, levels: levels, volume: volume)
        })
        .help(playing ? tr("暂停") : tr("播放"))
        .accessibilityLabel(playing ? tr("暂停环境音") : tr("播放环境音"))
    }
}
