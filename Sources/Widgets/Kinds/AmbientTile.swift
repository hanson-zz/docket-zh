import SwiftUI

/// Rain, waves, wind, a fire or plain noise, with play and pause on the card.
///
/// The mix and the volume are the widget's settings (`sounds`, `volume`);
/// the panel picks them and the sleep timer. Playback is one shared
/// `AmbientPlayer`, so the button always tells the truth about the speaker.
struct AmbientTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var player: AmbientPlayer { AmbientPlayer.shared }

    private var sounds: [AmbientSound] { AmbientSound.parse(instance.config.strings("sounds", default: ["rain"])) }
    private var volume: Double { instance.config.double("volume", default: 50) }

    private var playing: Bool { context.isPreview ? true : player.isPlaying }

    private var caption: String {
        if context.isPreview { return "24:13 后停止" }
        guard player.isPlaying else { return sounds.isEmpty ? "在设置中选择声音" : "已暂停" }
        if let end = player.stopAt { return "\(AmbientTimer.remaining(until: end, now: context.now)) 后停止" }
        return "正在播放"
    }

    var body: some View {
        let symbol = sounds.first?.symbol ?? "speaker.wave.2"
        return WidgetSurface {
            if context.position.isVertical {
                VStack(spacing: 4) {
                    TileBadge(size: 34) { mark(symbol, size: 14) }
                    Text(sounds.first?.title ?? "环境音")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WidgetStyle.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    playButton(size: 10)
                }
            } else {
                HStack(spacing: 10) {
                    TileBadge { mark(symbol, size: 17) }
                    TileReading(value: AmbientSound.summary(sounds), caption: caption, valueSize: 16)
                    Spacer(minLength: 0)
                    playButton(size: 12)
                }
            }
        }
        .onAppear { if !context.isPreview { player.apply(sounds: sounds, volume: volume) } }
        .onChange(of: sounds) { _, now in if !context.isPreview { player.apply(sounds: now, volume: volume) } }
        .onChange(of: volume) { _, now in if !context.isPreview { player.apply(sounds: sounds, volume: now) } }
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
            player.toggle(sounds: sounds, volume: volume)
        })
        .help(playing ? "暂停" : "播放")
        .accessibilityLabel(playing ? "暂停环境音" : "播放环境音")
    }
}
