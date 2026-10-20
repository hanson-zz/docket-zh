import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 应用音量面板（效果图 panel-practicality-c 第 1 列「改后」）。
///
/// 标题右边「开会模式」：除会议 App 外全部降到 30%（本来更低或静音的不动），
/// 再点恢复；开着时按钮是实心的。下面每个正在出声的 App 一行（图标、名字、
/// 静音键、0 到 150% 的音量条、百分比），再下面是「＋ 添加 App」先加进来、
/// 这会儿没在出声的预设（写「没在出声 · 预设静音」这类），一样能先调好音量或静音。
/// 右键一行：静音、开会时降不降低它、从列表移除（加进来的才有）。
///
/// 100% 是应用原本的声音，不做处理；调离 100% 或静音才走系统音频接入，
/// 要录音权限，没给时面板顶上说清楚并能打开设置。
struct AppVolumeDetail: View {
    /// 颜色面板里选的强调色，没选过是 nil，用原来的颜色（见 `PanelTint`）。
    @Environment(\.panelTint) private var panelTint
    var instance: WidgetInstance
    var context: WidgetContext

    private var service: AppVolumeService { AppVolumeService.shared }
    private var preview: Bool { context.isPreview }

    /// The slider being dragged and its value, so the label follows the
    /// finger while the service is told on every step.
    @State private var dragging: (id: String, value: Double)?
    /// 加 App 没加上时的一行说明（已经在列表里、满了、不是 App）。
    @State private var addNote: String?

    private var rows: [AppVolumeService.Row] {
        if preview {
            return [
                .init(bundleID: "com.apple.Music", name: tr("音乐"), setting: AppVolumeSetting(percent: 30), problem: nil),
                .init(bundleID: "com.apple.Safari", name: tr("浏览器"), setting: AppVolumeSetting(percent: 30), problem: nil),
            ]
        }
        return service.rows
    }

    private var presets: [AppVolumeService.Row] {
        if preview {
            return [.init(bundleID: "com.tencent.xinWeChat", name: tr("微信"),
                          setting: AppVolumeSetting(percent: 100, muted: true), problem: nil)]
        }
        return service.presets
    }

    private var meeting: Bool { preview ? true : service.meeting }

    private var permissionNeeded: Bool {
        guard !preview else { return false }
        return service.permission == .denied && rows.contains { !$0.setting.isDefault }
    }

    var body: some View {
        DetailCard {
            ZStack {
                Color(hex: AppVolumePanelStyle.base)
                RadialGradient(colors: [accent.opacity(0.13), .clear],
                               center: UnitPoint(x: 0.95, y: 0), startRadius: 0, endRadius: 200)
            }
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                header

                if permissionNeeded { permissionBanner }
                if let problem = preview ? nil : service.problem {
                    note(problem)
                }

                if rows.isEmpty && presets.isEmpty {
                    note(tr("还没有应用在播放声音。开始播放后会出现在这里，也可以先添加 App 设好音量。"))
                } else {
                    VStack(spacing: 6) {
                        ForEach(rows) { row in rowView(row, idle: false) }
                        ForEach(presets) { row in rowView(row, idle: true) }
                    }
                }

                addButton
                if let addNote { note(addNote) }

                footer
            }
        }
        .onAppear { if !preview { service.start() } }
    }

    // MARK: 头部

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: tr("应用音量"))
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white.opacity(0.97))
                Text(verbatim: AppVolumeText.meetingCaption(active: meeting))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .lineLimit(2)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 6) {
                meetingButton
                if !preview, !meeting, (rows + presets).contains(where: { !$0.setting.isDefault }) {
                    Button(tr("全部复原")) { service.resetAll() }
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .help(tr("所有 App 回到原本的音量"))
                }
            }
        }
    }

    private var meetingButton: some View {
        Button {
            guard !preview else { return }
            withAnimation(.easeInOut(duration: 0.15)) { service.toggleMeeting() }
        } label: {
            Text(verbatim: tr("开会模式"))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(meeting ? accentInk : .white.opacity(0.92))
                .padding(.horizontal, 16)
                .frame(height: 30)
                .background(Capsule().fill(meeting ? accent : .white.opacity(0.12)))
                .overlay(Capsule().strokeBorder(.white.opacity(meeting ? 0 : 0.18), lineWidth: 0.6))
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help(meeting ? tr("再点一下，全部恢复") : tr("除会议 App 外降到 30%"))
        .accessibilityAddTraits(meeting ? .isSelected : [])
    }

    // MARK: 一行

    private func rowView(_ row: AppVolumeService.Row, idle: Bool) -> some View {
        let live = dragging?.id == row.bundleID ? dragging?.value ?? row.setting.percent : row.setting.percent
        let muted = row.setting.muted
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                AppIconView(bundleID: row.bundleID, preview: preview, size: 24)
                    .opacity(idle ? 0.75 : 1)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: row.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                    if idle {
                        Text(verbatim: AppVolumeText.preset(row.setting))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .lineLimit(1)
                .frame(width: idle ? nil : 76, alignment: .leading)
                if idle {
                    Spacer(minLength: 4)
                    muteChip(row)
                } else {
                    muteButton(row, live: live)
                    slider(row, live: live)
                    Text(verbatim: muted ? tr("静音") : AppVolume.percentText(live))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(muted ? Color(hex: AppVolumePanelStyle.redInk) : .white.opacity(0.8))
                        .frame(width: 42, alignment: .trailing)
                        .contentTransition(.numericText())
                }
            }
            // 预设也能先把音量调好：没静音时下面多一条音量条。
            if idle, !muted {
                HStack(spacing: 8) {
                    slider(row, live: live)
                    Text(verbatim: AppVolume.percentText(live))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 42, alignment: .trailing)
                }
                .padding(.leading, 32)
            }
            if let problem = row.problem {
                Text(verbatim: problem)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: PaletteColor.orange.hex))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(minHeight: 48)
        .background(pane(0.06, radius: 11))
        .contextMenu { if !preview { menu(row) } }
    }

    private func slider(_ row: AppVolumeService.Row, live: Double) -> some View {
        Slider(value: Binding(
            get: { live },
            set: { value in
                let snapped = AppVolume.snapped(value)
                dragging = (row.bundleID, snapped)
                if !preview { service.setPercent(snapped, for: row.bundleID) }
            }), in: AppVolume.range, onEditingChanged: { editing in
                if !editing { dragging = nil }
            })
            .controlSize(.small)
            .tint(accent)
            .disabled(preview || row.setting.muted)
            .accessibilityLabel(tr("\(row.name) 音量"))
            .accessibilityValue(AppVolume.percentText(live))
    }

    private func muteButton(_ row: AppVolumeService.Row, live: Double) -> some View {
        Button {
            guard !preview else { return }
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
        .help(row.setting.muted ? tr("取消静音") : tr("静音"))
        .accessibilityLabel(row.setting.muted ? tr("取消静音 \(row.name)") : tr("静音 \(row.name)"))
    }

    /// 预设行右边：静音时是红色「静音」，没静音时是空心「静音」，点了切换。
    private func muteChip(_ row: AppVolumeService.Row) -> some View {
        let muted = row.setting.muted
        return Button {
            guard !preview else { return }
            service.setMuted(!muted, for: row.bundleID)
        } label: {
            Text(verbatim: tr("静音"))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(muted ? Color(hex: AppVolumePanelStyle.redInk) : .white.opacity(0.82))
                .frame(width: 54, height: 24)
                .background(Capsule().fill(muted ? Color(hex: AppVolumePanelStyle.red).opacity(0.18)
                                                 : .white.opacity(0.08)))
                .overlay(Capsule().strokeBorder(.white.opacity(muted ? 0 : 0.16), lineWidth: 0.6))
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help(muted ? tr("取消静音") : tr("先设成静音"))
        .accessibilityLabel(muted ? tr("取消静音 \(row.name)") : tr("静音 \(row.name)"))
    }

    @ViewBuilder
    private func menu(_ row: AppVolumeService.Row) -> some View {
        Button(row.setting.muted ? tr("取消静音") : tr("静音")) {
            service.setMuted(!row.setting.muted, for: row.bundleID)
        }
        if service.isMeetingApp(row.bundleID) {
            Button(tr("开会时也降低")) { service.setMeetingApp(false, for: row.bundleID) }
        } else {
            Button(tr("开会时不降低（算会议 App）")) { service.setMeetingApp(true, for: row.bundleID) }
        }
        if service.pinned.contains(row.bundleID) {
            Divider()
            Button(tr("从列表移除"), role: .destructive) { service.removePreset(row.bundleID) }
        }
    }

    // MARK: 添加 App

    private var addButton: some View {
        Button {
            guard !preview else { return }
            chooseApp()
        } label: {
            Text(verbatim: tr("＋ 添加 App（先设好音量）"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(Capsule().fill(.white.opacity(0.12)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.6))
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .disabled(!preview && service.pinned.count >= AppVolumePresets.limit)
        .help(tr("没在出声的 App 也能先加进来，设好音量或静音"))
    }

    private func chooseApp() {
        addNote = nil
        guard let url = Self.pickApplication() else { return }
        guard let bundleID = Bundle(url: url)?.bundleIdentifier, !bundleID.isEmpty else {
            addNote = tr("这个不是能出声的 App，换一个试试")
            return
        }
        if bundleID == Bundle.main.bundleIdentifier {
            addNote = tr("码头自己不用加")
            return
        }
        if service.pinned.contains(where: { $0.caseInsensitiveCompare(bundleID) == .orderedSame }) {
            addNote = tr("它已经在列表里了")
            return
        }
        if !service.addPreset(bundleID) {
            addNote = tr("最多添加 \(AppVolumePresets.limit) 个")
        }
    }

    /// 选一个 App，和别的面板选文件一样先把码头提到前面。
    private static func pickApplication() -> URL? {
        let policy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        defer { NSApp.setActivationPolicy(policy) }
        let panel = NSOpenPanel()
        panel.message = tr("选一个 App，先设好它的音量")
        panel.prompt = tr("添加")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        return panel.runModal() == .OK ? panel.url : nil
    }

    // MARK: 说明和权限

    private var footer: some View {
        Text(verbatim: tr("100% 是原本的音量，不做处理；调过的 App 经系统音频接入处理。右键一行可设开会时降不降低它。"))
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.55))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var permissionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform.badge.exclamationmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(hex: PaletteColor.orange.hex))
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: tr("需要录音权限"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(verbatim: tr("在“隐私与安全性 ▸ 录屏与系统录音”中允许码头录制系统音频。"))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(tr("打开设置")) { service.openPrivacySettings() }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Capsule().fill(.white.opacity(0.2)))
        }
        .padding(10)
        .background(pane(0.1))
    }

    private func note(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 13))
            .foregroundStyle(.white.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func pane(_ opacity: Double, radius: CGFloat = 12) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(.white.opacity(opacity))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(.white.opacity(0.11), lineWidth: 0.6))
    }

    private var accent: Color {
        panelTint.accent(or: Color(hex: AppVolumePanelStyle.accent))
    }

    private var accentInk: Color {
        panelTint.ink(or: Color(hex: AppVolumePanelStyle.accentInk))
    }
}

/// 应用音量面板的颜色，照效果图 ACC["vol"]。
enum AppVolumePanelStyle {
    static let base = "#1d1d21"
    static let accent = "#C8A2FF"
    static let accentInk = "#22093A"
    static let red = "#FF6B5A"
    static let redInk = "#FFB3AA"
}
