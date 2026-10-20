import SwiftUI

/// Whether any app is using the microphone, which one it is, and its mute.
///
/// 点卡片打开麦克风与摄像头面板。卡片上的小钮是全局静音（输入音量拉到 0，
/// 再点恢复，和面板、快速开关同一份），设备既没有可调音量也没有静音开关时不出现。
/// 静音中且设置里开着「静音时卡片变红」时卡片底变红；摄像头开着时右下角一个绿点。
struct MicrophoneTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var mic: MicrophoneMonitor { MicrophoneMonitor.shared }

    private var inUse: Bool { context.isPreview ? true : mic.inUse || !mic.apps.isEmpty }
    private var muted: Bool { context.isPreview ? false : mic.globalMuted }
    private var canMute: Bool { context.isPreview ? true : mic.canGlobalMute }
    private var cameraOn: Bool { context.isPreview ? false : mic.cameraOn }
    private var name: String {
        if context.isPreview { return tr("MacBook Pro 麦克风") }
        return MicrophoneText.caption(deviceName: mic.deviceName, apps: mic.apps.map(\.name))
    }
    private var red: Bool {
        muted && MicPrivacySettings(config: instance.config).redWhenMuted
    }

    var body: some View {
        WidgetSurface(fill: red ? Color(hex: MicPanelStyle.red).opacity(0.62) : nil) {
            if context.position.isVertical {
                VStack(spacing: 4) {
                    badge(size: WidgetStyle.badgeCompact)
                    Text(MicrophoneText.value(inUse: inUse, muted: muted))
                        .font(WidgetStyle.caption(10))
                        .foregroundStyle(WidgetStyle.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if canMute { muteButton(size: 10) }
                }
            } else {
                HStack(spacing: WidgetStyle.rowSpacing) {
                    badge(size: WidgetStyle.badge)
                    TileReading(value: MicrophoneText.value(inUse: inUse, muted: muted),
                                caption: name)
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
                .foregroundStyle(inUse && !muted && !red ? Color(hex: PaletteColor.orange.hex) : WidgetStyle.primary)
        }
        .overlay(alignment: .topTrailing) {
            if inUse && !muted {
                Circle()
                    .fill(Color(hex: PaletteColor.orange.hex))
                    .frame(width: 8, height: 8)
                    .offset(x: 2, y: -2)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if cameraOn {
                Circle()
                    .fill(Color(hex: MicPanelStyle.camera))
                    .frame(width: 8, height: 8)
                    .offset(x: 2, y: 2)
                    .accessibilityLabel(tr("摄像头开着"))
            }
        }
        .accessibilityLabel("麦克风")
        .accessibilityValue(MicrophoneText.value(inUse: inUse, muted: muted))
    }

    private func muteButton(size: CGFloat) -> some View {
        TileGlyph(symbol: muted ? "mic.fill" : "mic.slash", size: size,
                  action: context.isPreview ? nil : { mic.toggleGlobalMute() })
            .help(muted ? tr("取消静音麦克风") : tr("静音麦克风"))
            .accessibilityLabel(muted ? tr("取消静音麦克风") : tr("静音麦克风"))
    }
}
