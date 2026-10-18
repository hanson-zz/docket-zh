import AppKit
import SwiftUI

/// 应用音量：谁吵关谁。正在出声的应用每个一格，图标、名字、百分比和自己的
/// 音量条，在卡片上左右拖那一格就能调（0 到 150%，100% 是不处理，拖过去会吸住），
/// 按住图标静音。总音量和输出设备归“音量”，这里不放。
///
/// 真的能调：走 `AppVolumeService` 的系统音频接入（macOS 14.2 起的 process tap），
/// 第一次把某个应用调离 100% 时系统会要录音权限；被拒绝时卡片下面那行字换成
/// “需要录音权限”，点一下打开系统设置的对应页。点卡片别处照旧打开面板。
struct AppVolumeTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var service: AppVolumeService { AppVolumeService.shared }

    /// 正在拖的那一格：哪个应用、按下时的音量、现在的音量。
    @State private var drag: (id: String, start: Double, value: Double)?

    private struct Shown: Identifiable {
        var id: String
        var name: String
        var setting: AppVolumeSetting
        var problem: String?
    }

    private var rows: [Shown] {
        if context.isPreview {
            return [Shown(id: "com.apple.Music", name: tr("音乐"), setting: AppVolumeSetting(percent: 120)),
                    Shown(id: "com.apple.Safari", name: "Safari", setting: AppVolumeSetting(percent: 52)),
                    Shown(id: "com.tencent.xinWeChat", name: tr("微信"),
                          setting: AppVolumeSetting(percent: 100, muted: true))]
        }
        return service.rows.map { Shown(id: $0.bundleID, name: $0.name, setting: $0.setting, problem: $0.problem) }
    }

    private var permissionNeeded: Bool {
        guard !context.isPreview else { return false }
        return service.permission == .denied && service.rows.contains { !$0.setting.isDefault }
    }

    var body: some View {
        let all = rows
        let cells = AppVolumeStrip.cells(all) { !$0.setting.isDefault }
        return WidgetSurface {
            if all.isEmpty {
                empty
            } else if context.position.isVertical {
                column(cells.shown, more: cells.more)
            } else {
                strip(cells.shown, named: cells.named, more: cells.more)
            }
        }
        .onAppear { if !context.isPreview { service.start() } }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("应用音量")
    }

    // MARK: 底栏 196×62

    private func strip(_ shown: [Shown], named: Bool, more: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ForEach(shown) { app in
                    cell(app, named: named)
                }
            }
            footer(more: more)
        }
    }

    private func cell(_ app: Shown, named: Bool) -> some View {
        let percent = value(app)
        let muted = app.setting.muted
        return GeometryReader { geo in
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: named ? 5 : 3) {
                    icon(app, size: named ? 20 : 18)
                    VStack(alignment: .leading, spacing: 0) {
                        if named {
                            Text(app.name)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(WidgetStyle.primary.opacity(muted ? 0.5 : 0.9))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        Text(AppVolumeStrip.label(percent: percent, muted: muted))
                            .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                            .foregroundStyle(muted ? Color(hex: PaletteColor.red.hex) : WidgetStyle.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    }
                    Spacer(minLength: 0)
                }
                bar(app, percent: percent, width: geo.size.width)
            }
            .contentShape(.rect)
            .gesture(dragGesture(app, width: geo.size.width))
        }
        .frame(height: 30)
        .help(app.problem ?? tr("\(app.name)：左右拖调音量，按住图标静音"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(app.name)
        .accessibilityValue(AppVolumeStrip.label(percent: percent, muted: muted))
        .accessibilityAdjustableAction { direction in
            guard !context.isPreview else { return }
            let step = direction == .increment ? 10.0 : -10.0
            service.setPercent(app.setting.percent + step, for: app.id)
        }
    }

    private func bar(_ app: Shown, percent: Double, width: CGFloat) -> some View {
        let muted = app.setting.muted
        let fill = AppVolumeStrip.fraction(percent: percent, muted: muted)
        return ZStack(alignment: .leading) {
            Capsule().fill(WidgetStyle.primary.opacity(0.14))
            if muted {
                Capsule()
                    .fill(Color(hex: PaletteColor.red.hex))
                    .frame(width: max(6, width * 0.22), height: 1.5)
                    .frame(maxWidth: .infinity)
            } else {
                Capsule()
                    .fill(AppTint.color(for: app.id, preview: context.isPreview))
                    .frame(width: max(4, width * fill))
            }
            // 100% 的位置：一道小刻度，提示“回到这里就是不处理”。
            Rectangle()
                .fill(WidgetStyle.primary.opacity(0.35))
                .frame(width: 1, height: 6)
                .offset(x: width * AppVolumeStrip.unityFraction - 0.5)
        }
        .frame(height: 4)
        .frame(height: 6)
    }

    private func icon(_ app: Shown, size: CGFloat) -> some View {
        AppIconView(bundleID: app.id, preview: context.isPreview, size: size)
            .opacity(app.setting.muted ? 0.45 : 1)
            .overlay(alignment: .bottomTrailing) {
                if app.setting.muted {
                    Image(systemName: "speaker.slash.fill")
                        .font(.system(size: size * 0.36, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(1.5)
                        .background(Circle().fill(Color(hex: PaletteColor.red.hex)))
                        .offset(x: 3, y: 3)
                }
            }
            .onLongPressGesture(minimumDuration: 0.35) {
                guard !context.isPreview else { return }
                service.setMuted(!app.setting.muted, for: app.id)
            }
    }

    @ViewBuilder
    private func footer(more: Int) -> some View {
        if permissionNeeded {
            Button {
                service.openPrivacySettings()
            } label: {
                Label(tr("需要录音权限，点这里打开设置"), systemImage: "exclamationmark.triangle.fill")
                    .font(WidgetStyle.caption(9.5))
                    .foregroundStyle(Color(hex: PaletteColor.orange.hex))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .buttonStyle(.plain)
        } else {
            Text(more > 0 ? tr("左右拖调音量，按住图标静音 · 还有 \(more) 个") : tr("左右拖调音量，按住图标静音"))
                .font(WidgetStyle.caption(9.5))
                .foregroundStyle(WidgetStyle.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
    }

    // MARK: 侧边栏 76 宽

    private func column(_ shown: [Shown], more: Int) -> some View {
        VStack(spacing: 5) {
            ForEach(shown.prefix(3)) { app in
                GeometryReader { geo in
                    HStack(spacing: 4) {
                        icon(app, size: 16)
                        bar(app, percent: value(app), width: max(0, geo.size.width - 20))
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(.rect)
                    .gesture(dragGesture(app, width: max(1, geo.size.width - 20)))
                }
                .frame(height: 18)
                .help(app.name)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(app.name)
                .accessibilityValue(AppVolumeStrip.label(percent: value(app), muted: app.setting.muted))
            }
            if more + max(0, shown.count - 3) > 0 {
                Text(tr("还有 \(more + max(0, shown.count - 3)) 个"))
                    .font(WidgetStyle.caption(9))
                    .foregroundStyle(WidgetStyle.secondary)
            }
        }
    }

    private var empty: some View {
        HStack(spacing: WidgetStyle.rowSpacing) {
            TileBadge {
                Image(systemName: "slider.vertical.3")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(WidgetStyle.secondary)
            }
            if !context.position.isVertical {
                TileReading(value: AppVolumeText.value(playing: 0),
                            caption: AppVolumeText.caption(names: [], permissionNeeded: false),
                            valueSize: 16)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Dragging

    private func value(_ app: Shown) -> Double {
        if let drag, drag.id == app.id { return drag.value }
        return app.setting.percent
    }

    private func dragGesture(_ app: Shown, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { change in
                guard !context.isPreview else { return }
                let start = (drag?.id == app.id ? drag?.start : nil) ?? app.setting.percent
                let next = AppVolumeStrip.percent(start: start, dragged: change.translation.width, width: width)
                drag = (app.id, start, next)
                if app.setting.muted { service.setMuted(false, for: app.id) }
                service.setPercent(next, for: app.id)
            }
            .onEnded { _ in drag = nil }
    }
}

/// 每个应用音量条的颜色：取它图标的主色，读不出来就用应用音量的靛蓝。
@MainActor
enum AppTint {
    private static var cache: [String: Color] = [:]

    static func color(for bundleID: String, preview: Bool) -> Color {
        if preview {
            switch bundleID {
            case "com.apple.Music": return Color(hex: PaletteColor.pink.hex)
            case "com.apple.Safari": return Color(hex: PaletteColor.teal.hex)
            default: return Color(hex: PaletteColor.green.hex)
            }
        }
        if let cached = cache[bundleID] { return cached }
        let fallback = Color(hex: PaletteColor.indigo.hex)
        var color = fallback
        let icon = AppIdentity.icon(for: bundleID)
        // 取最接近 32 像素的那一层，免得为一个颜色解码 1024 的大图标。
        var rect = NSRect(x: 0, y: 0, width: 32, height: 32)
        if let cg = icon.cgImage(forProposedRect: &rect, context: nil, hints: nil),
           let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]),
           let tint = ArtworkTint.extract(data),
           tint.saturation > ArtworkTint.greyThreshold {
            color = Color(hue: tint.hue, saturation: 0.62, brightness: 0.92)
        }
        cache[bundleID] = color
        return color
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
