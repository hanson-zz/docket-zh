import SwiftUI

/// The apps playing sound right now, as their icons, with how many.
///
/// The card opens the panel, where each app has its own slider and mute.
/// Nothing here changes audio, so the card has no control of its own.
struct AppVolumeTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var service: AppVolumeService { AppVolumeService.shared }

    private struct Shown: Identifiable {
        var id: String
        var name: String
        var muted: Bool
        var changed: Bool
    }

    private var shown: [Shown] {
        if context.isPreview {
            return [Shown(id: "com.apple.Music", name: "音乐", muted: false, changed: false),
                    Shown(id: "com.apple.Safari", name: "Safari", muted: false, changed: true),
                    Shown(id: "com.tencent.xinWeChat", name: "微信", muted: true, changed: true)]
        }
        return service.rows.map {
            Shown(id: $0.bundleID, name: $0.name, muted: $0.setting.muted, changed: !$0.setting.isDefault)
        }
    }

    private var permissionNeeded: Bool {
        guard !context.isPreview else { return false }
        return service.permission == .denied && service.rows.contains { !$0.setting.isDefault }
    }

    var body: some View {
        let apps = shown
        return WidgetSurface {
            if context.position.isVertical {
                VStack(spacing: 4) {
                    TileBadge(size: 34) { icons(apps, size: 20) }
                    Text(AppVolumeText.value(playing: apps.count))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WidgetStyle.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            } else {
                HStack(spacing: 10) {
                    TileBadge { icons(apps, size: 24) }
                    TileReading(value: AppVolumeText.value(playing: apps.count),
                                caption: AppVolumeText.caption(names: apps.map(\.name),
                                                               permissionNeeded: permissionNeeded),
                                valueSize: 16)
                    Spacer(minLength: 0)
                }
            }
        }
        .onAppear { if !context.isPreview { service.start() } }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("应用音量")
        .accessibilityValue(AppVolumeText.caption(names: apps.map(\.name), permissionNeeded: permissionNeeded))
    }

    /// Up to three icons, fanned, the first on top. With nothing playing, the
    /// mixer glyph stands in.
    @ViewBuilder
    private func icons(_ apps: [Shown], size: CGFloat) -> some View {
        if apps.isEmpty {
            Image(systemName: "slider.vertical.3")
                .font(.system(size: size * 0.66, weight: .medium))
                .foregroundStyle(WidgetStyle.secondary)
        } else {
            let first = Array(apps.prefix(3))
            ZStack {
                ForEach(Array(first.enumerated().reversed()), id: \.element.id) { index, app in
                    AppIconView(bundleID: app.id, preview: context.isPreview, size: size)
                        .opacity(app.muted ? 0.45 : 1)
                        .scaleEffect(1 - CGFloat(index) * 0.12)
                        .offset(x: CGFloat(index) * size * 0.28 - CGFloat(first.count - 1) * size * 0.14,
                                y: CGFloat(index) * -1.5)
                        .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
                }
            }
        }
    }
}

/// An app's icon, or for the sample render a neutral stand-in, since the
/// machine making screenshots may not have the sample apps.
struct AppIconView: View {
    var bundleID: String
    var preview: Bool
    var size: CGFloat

    var body: some View {
        if preview {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(Self.sampleColor(bundleID))
                .overlay {
                    Image(systemName: Self.sampleSymbol(bundleID))
                        .font(.system(size: size * 0.5, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: size, height: size)
        } else {
            Image(nsImage: AppIdentity.icon(for: bundleID))
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        }
    }

    private static func sampleColor(_ id: String) -> Color {
        switch id {
        case "com.apple.Music": Color(hex: PaletteColor.pink.hex)
        case "com.apple.Safari": Color(hex: PaletteColor.blue.hex)
        default: Color(hex: PaletteColor.green.hex)
        }
    }

    private static func sampleSymbol(_ id: String) -> String {
        switch id {
        case "com.apple.Music": "music.note"
        case "com.apple.Safari": "safari"
        default: "message.fill"
        }
    }
}
