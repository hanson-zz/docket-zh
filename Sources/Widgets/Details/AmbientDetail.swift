import SwiftUI

/// Pick the sounds to mix, set the volume and the sleep timer, play.
///
/// The choices are written to the widget's settings, so the tile, the
/// Widgets tab and this panel always show the same mix.
struct AmbientDetail: View {
    /// 颜色面板里选的强调色，没选过是 nil，用原来的颜色（见 `PanelTint`）。
    @Environment(\.panelTint) private var panelTint
    var instance: WidgetInstance
    var context: WidgetContext

    private var player: AmbientPlayer { AmbientPlayer.shared }

    /// The slider's own value while dragging, so the profile is saved once
    /// at the end of the drag rather than sixty times during it.
    @State private var dragging: Double?

    private var sounds: [AmbientSound] {
        AmbientSound.parse(instance.config.strings("sounds", default: ["rain"]))
    }
    private var volume: Double { dragging ?? instance.config.double("volume", default: 50) }
    private var playing: Bool { context.isPreview || player.isPlaying }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tick in
            content(now: tick.date)
        }
    }

    private func content(now: Date) -> some View {
        DetailCard {
            MeshBackdrop(color: accent)
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(playing ? tr("正在播放") : tr("环境音"))
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(AmbientSound.summary(sounds))
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let end = player.stopAt, player.isPlaying {
                        Text(tr("\(AmbientTimer.remaining(until: end, now: now)) 后自动停止"))
                            .font(WidgetStyle.label(12))
                            .foregroundStyle(.white.opacity(0.75))
                            .monospacedDigit()
                    }
                }

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(AmbientSound.allCases) { sound in soundButton(sound) }
                }

                HStack(spacing: 8) {
                    Image(systemName: "speaker.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                    Slider(value: Binding(
                        get: { volume },
                        set: { value in
                            dragging = value
                            if !context.isPreview { player.apply(sounds: sounds, volume: value) }
                        }), in: 0...100, onEditingChanged: { editing in
                            if !editing, let value = dragging {
                                save { $0.set("volume", .number(value.rounded())) }
                                dragging = nil
                            }
                        })
                        .controlSize(.small)
                        .disabled(context.isPreview)
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                    Text("\(Int(volume.rounded()))%")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 34, alignment: .trailing)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("定时关闭")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                    HStack(spacing: 6) {
                        ForEach(AmbientTimer.choices, id: \.self) { minutes in timerChip(minutes) }
                    }
                }

                Button {
                    guard !context.isPreview else { return }
                    player.toggle(sounds: sounds, volume: volume)
                } label: {
                    Label(playing ? tr("暂停") : tr("播放"), systemImage: playing ? "pause.fill" : "play.fill")
                        .font(WidgetStyle.label(13))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(Capsule().fill(.white.opacity(0.24)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(sounds.isEmpty)
                .accessibilityLabel(playing ? tr("暂停环境音") : tr("播放环境音"))

                BreathPacerView(isPreview: context.isPreview)
            }
        }
    }

    private func soundButton(_ sound: AmbientSound) -> some View {
        let on = sounds.contains(sound)
        return Button {
            guard !context.isPreview else { return }
            var next = sounds
            if on { next.removeAll { $0 == sound } } else { next.append(sound) }
            let names = AmbientSound.parse(next.map(\.rawValue)).map(\.rawValue)
            save { $0.set("sounds", .list(names.map { .string($0) })) }
            player.apply(sounds: AmbientSound.parse(names), volume: volume)
        } label: {
            VStack(spacing: 5) {
                Image(systemName: sound.symbol)
                    .font(.system(size: 17, weight: .medium))
                    .frame(height: 20)
                Text(sound.title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(on ? .white : .white.opacity(0.6))
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(on ? accent.opacity(0.45) : .white.opacity(0.07)))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.white.opacity(on ? 0.35 : 0.08), lineWidth: 0.5)
            }
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(sound.title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func timerChip(_ minutes: Int) -> some View {
        let on = player.timerMinutes == minutes
        return Button {
            guard !context.isPreview else { return }
            player.setTimer(minutes: minutes)
        } label: {
            Text(AmbientTimer.title(minutes))
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(on ? .white : .white.opacity(0.65))
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .background(Capsule().fill(.white.opacity(on ? 0.26 : 0.08)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func save(_ change: (inout WidgetConfig) -> Void) {
        guard !context.isPreview else { return }
        WidgetWriter.write(instance, change)
    }

    private var accent: Color {
        panelTint.accent(or: WidgetCatalog.accentHex(.ambient).map { Color(hex: $0) } ?? WidgetStyle.primary)
    }
}
