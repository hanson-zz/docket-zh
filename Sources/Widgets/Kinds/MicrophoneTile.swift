import SwiftUI

/// Whether any app is using the microphone, which one it is, and its mute.
///
/// The card opens Sound settings, where the input device is chosen. The mute
/// glyph appears only when the device has a mute Core Audio can set.
struct MicrophoneTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var mic: MicrophoneMonitor { MicrophoneMonitor.shared }

    private var inUse: Bool { context.isPreview ? true : mic.inUse }
    private var muted: Bool { context.isPreview ? false : (mic.muted ?? false) }
    private var canMute: Bool { context.isPreview ? true : mic.canMute }
    private var name: String { context.isPreview ? "MacBook Pro 麦克风" : mic.deviceName }

    var body: some View {
        WidgetSurface {
            if context.position.isVertical {
                VStack(spacing: 4) {
                    badge(size: 34)
                    Text(MicrophoneText.value(inUse: inUse, muted: muted))
                        .font(WidgetStyle.caption(10))
                        .foregroundStyle(WidgetStyle.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if canMute { muteButton(size: 10) }
                }
            } else {
                HStack(spacing: 10) {
                    badge(size: 40)
                    TileReading(value: MicrophoneText.value(inUse: inUse, muted: muted),
                                caption: MicrophoneText.caption(deviceName: name))
                    Spacer(minLength: 0)
                    if canMute { muteButton(size: 12) }
                }
            }
        }
        .onAppear { if !context.isPreview { mic.start() } }
    }

    /// The glyph is the state: a red dot joins it while something records.
    private func badge(size: CGFloat) -> some View {
        TileBadge(size: size) {
            Image(systemName: muted ? "mic.slash.fill" : "mic.fill")
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundStyle(inUse && !muted ? Color(hex: PaletteColor.orange.hex) : WidgetStyle.primary)
        }
        .overlay(alignment: .topTrailing) {
            if inUse && !muted {
                Circle()
                    .fill(Color(hex: PaletteColor.orange.hex))
                    .frame(width: 8, height: 8)
                    .offset(x: 2, y: -2)
            }
        }
        .accessibilityLabel("麦克风")
        .accessibilityValue(MicrophoneText.value(inUse: inUse, muted: muted))
    }

    private func muteButton(size: CGFloat) -> some View {
        TileGlyph(symbol: muted ? "mic.fill" : "mic.slash", size: size,
                  action: context.isPreview ? nil : { mic.setMuted(!muted) })
            .help(muted ? "取消输入静音" : "输入静音")
            .accessibilityLabel(muted ? "取消输入静音" : "输入静音")
    }
}
