import SwiftUI

/// Every app playing sound, each with its own slider from 0 to 150 percent
/// and a mute.
///
/// 100 percent is the app's normal sound, untouched; the slider snaps there.
/// Moving off it, or muting, needs the system audio recording permission,
/// and the panel says so in place of failing quietly.
struct AppVolumeDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var service: AppVolumeService { AppVolumeService.shared }

    /// The slider being dragged and its value, so the label follows the
    /// finger while the service is told on every step.
    @State private var dragging: (id: String, value: Double)?

    private var rows: [AppVolumeService.Row] {
        if context.isPreview {
            return [
                .init(bundleID: "com.apple.Music", name: "音乐", setting: AppVolumeSetting(), problem: nil),
                .init(bundleID: "com.apple.Safari", name: "Safari", setting: AppVolumeSetting(percent: 60), problem: nil),
                .init(bundleID: "com.tencent.xinWeChat", name: "微信",
                      setting: AppVolumeSetting(percent: 100, muted: true), problem: nil),
            ]
        }
        return service.rows
    }

    private var permissionNeeded: Bool {
        guard !context.isPreview else { return false }
        return service.permission == .denied && rows.contains { !$0.setting.isDefault }
    }

    var body: some View {
        DetailCard {
            MeshBackdrop(color: accent)
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("应用音量")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(.white.opacity(0.7))
                        Text(AppVolumeText.value(playing: rows.count))
                            .font(.system(size: 24, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    Spacer(minLength: 0)
                    if rows.contains(where: { !$0.setting.isDefault }) {
                        Button("全部复原") {
                            guard !context.isPreview else { return }
                            service.resetAll()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Capsule().fill(.white.opacity(0.14)))
                    }
                }

                if permissionNeeded { permissionBanner }
                if let problem = context.isPreview ? nil : service.problem {
                    note(problem)
                }

                if rows.isEmpty {
                    note("还没有应用在播放声音。开始播放后，它会出现在这里。")
                } else {
                    VStack(spacing: 8) {
                        ForEach(rows) { row in rowView(row) }
                    }
                }

                Text("100% 是应用原本的音量，不做任何处理。调高、调低或静音时，码头会通过系统的音频接入处理这个应用的声音。")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { if !context.isPreview { service.start() } }
    }

    private func rowView(_ row: AppVolumeService.Row) -> some View {
        let live = dragging?.id == row.bundleID ? dragging?.value ?? row.setting.percent : row.setting.percent
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                AppIconView(bundleID: row.bundleID, preview: context.isPreview, size: 22)
                Text(row.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(row.setting.muted ? "已静音" : AppVolume.percentText(live))
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.75))
                    .contentTransition(.numericText())
            }
            HStack(spacing: 8) {
                Button {
                    guard !context.isPreview else { return }
                    service.setMuted(!row.setting.muted, for: row.bundleID)
                } label: {
                    Image(systemName: AppVolume.symbol(percent: live, muted: row.setting.muted))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(row.setting.muted ? Color.white.opacity(0.5) : Color.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(.white.opacity(row.setting.muted ? 0.08 : 0.16)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(row.setting.muted ? "取消静音" : "静音")
                .accessibilityLabel(row.setting.muted ? "取消静音 \(row.name)" : "静音 \(row.name)")

                Slider(value: Binding(
                    get: { live },
                    set: { value in
                        let snapped = AppVolume.snapped(value)
                        dragging = (row.bundleID, snapped)
                        if !context.isPreview { service.setPercent(snapped, for: row.bundleID) }
                    }), in: AppVolume.range, onEditingChanged: { editing in
                        if !editing { dragging = nil }
                    })
                    .controlSize(.small)
                    .disabled(context.isPreview)
                    .accessibilityLabel("\(row.name) 音量")
                    .accessibilityValue(AppVolume.percentText(live))
            }
            if let problem = row.problem {
                Text(problem)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(hex: PaletteColor.orange.hex))
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.07)))
    }

    private var permissionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.badge.exclamationmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: PaletteColor.orange.hex))
            VStack(alignment: .leading, spacing: 1) {
                Text("需要录音权限")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Text("在“隐私与安全性 ▸ 录屏与系统录音”中允许码头录制系统音频。")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button("打开设置") { service.openPrivacySettings() }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Capsule().fill(.white.opacity(0.2)))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.1)))
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.white.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var accent: Color {
        WidgetCatalog.accentHex(.appVolume).map { Color(hex: $0) } ?? WidgetStyle.primary
    }
}
