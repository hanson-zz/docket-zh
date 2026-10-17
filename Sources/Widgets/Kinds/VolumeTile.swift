import SwiftUI

/// The output device and its volume, with a slider that moves it.
///
/// The slider is the one control on the card and takes the drag only where
/// it sits; the speaker glyph mutes. The card around them opens Sound
/// settings, where the output is chosen.
struct VolumeTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var audio: AudioOutput { AudioOutput.shared }

    private var level: Double? { context.isPreview ? 0.58 : audio.volume }
    private var name: String { context.isPreview ? tr("MacBook Pro 扬声器") : audio.deviceName }

    var body: some View {
        let column = context.position.isVertical
        return WidgetSurface {
            VStack(alignment: .leading, spacing: column ? 4 : 5) {
                HStack(spacing: 5) {
                    Image(systemName: "hifispeaker")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WidgetStyle.secondary)
                    Text(name.isEmpty ? tr("无输出设备") : name)
                        .font(WidgetStyle.label(column ? 10 : 12))
                        .foregroundStyle(WidgetStyle.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    if !column, let level {
                        Text("\(Int((level * 100).rounded()))%")
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundStyle(WidgetStyle.secondary)
                    }
                }
                HStack(spacing: 6) {
                    Button {
                        guard !context.isPreview else { return }
                        audio.setMuted(!audio.muted)
                    } label: {
                        Image(systemName: speaker)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(WidgetStyle.primary)
                            .frame(width: 16, height: 16)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(audio.muted ? tr("取消静音") : tr("静音"))
                    if let level {
                        Slider(value: Binding(
                            get: { level },
                            set: { if !context.isPreview { audio.set(volume: $0) } }),
                               in: 0...1)
                            .controlSize(.mini)
                            .disabled(context.isPreview)
                    } else {
                        Text("此设备不支持调节音量")
                            .font(WidgetStyle.caption(10))
                            .foregroundStyle(WidgetStyle.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
        }
        .onAppear { if !context.isPreview { audio.start() } }
    }

    private var speaker: String {
        guard let level, !(audio.muted && !context.isPreview) else { return "speaker.slash.fill" }
        switch level {
        case 0: return "speaker.fill"
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }
}
