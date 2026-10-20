import AppKit
import SwiftUI

/// 麦克风与摄像头面板（效果图 panels-batch2a 第 8 列，隐私指示），两个状态：
///
/// - 浏览：头上「麦克风与摄像头」和几个 App 正在用，右上「设置」。「正在使用」
///   每个在用麦克风的 App 一行（图标、名字、麦克风小标、已用时长），摄像头开着
///   单独一行「摄像头开着」，不猜是哪个 App。下面全局静音大按钮（输入音量拉到 0，
///   再点恢复原值，快捷键默认 ⌥⌘M），静音后变红。输入设备列表点选切换默认输入，
///   输入音量滑杆，电平表点「测电平」才开（要真的取声音，见 `MicLevelMeter`）。
/// - 设置：静音大按钮、谁在用但听不到你、三个开关（有 App 开始用麦克风时提醒、
///   摄像头亮起时提醒、静音时卡片变红）、静音快捷键（录新的、按删除键清除）、
///   今天谁用过（只存在本机）。码头 Pro 可以往前看 30 天，免费只看今天；没解锁
///   时不显示以前的，记录照旧留着。
struct MicrophoneDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private enum Mode { case browse, settings }

    @State private var mode: Mode = .browse
    @State private var recorder = ShortcutKeyRecorder()
    @State private var day: Date?

    @AppStorage(ProAccess.licenseKey) private var licenseUnlocked = false
    @AppStorage(Supporter.key) private var supporter = false
    @Environment(\.panelTint) private var panelTint

    private var mic: MicrophoneMonitor { MicrophoneMonitor.shared }
    private var meter: MicLevelMeter { MicLevelMeter.shared }
    private var current: WidgetInstance { WidgetWriter.current(instance.id) ?? instance }
    private var settings: MicPrivacySettings { MicPrivacySettings(config: current.config) }
    private var unlocked: Bool { ProLicenseGate.micHistoryActive(unlocked: licenseUnlocked || supporter) }

    private var accent: Color { panelTint.accent(or: Color(hex: MicPanelStyle.accent)) }
    private var accentInk: Color { panelTint.ink(or: Color(hex: MicPanelStyle.accentInk)) }
    private let camera = Color(hex: MicPanelStyle.camera)
    private let red = Color(hex: MicPanelStyle.red)
    private let redInk = Color(hex: MicPanelStyle.redInk)
    private let green = Color(hex: MicPanelStyle.green)

    private var preview: Bool { context.isPreview }
    private var muted: Bool { preview ? false : mic.globalMuted }

    var body: some View {
        DetailCard {
            ZStack {
                Color(hex: MicPanelStyle.base)
                RadialGradient(colors: [(muted ? red : accent).opacity(0.13), .clear],
                               center: UnitPoint(x: 0.95, y: 0), startRadius: 0, endRadius: 200)
            }
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                header
                switch mode {
                case .browse: browse
                case .settings: settingsPage
                }
            }
        }
        .onAppear {
            guard !preview else { return }
            mic.panelAppeared()
        }
        .onDisappear {
            guard !preview else { return }
            mic.panelDisappeared()
            meter.stop()
            recorder.stop()
        }
    }

    // MARK: 头部

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: mode == .browse ? tr("麦克风与摄像头") : tr("麦克风设置"))
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white.opacity(0.97))
                Text(verbatim: subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            if !preview { headerButton }
        }
    }

    @ViewBuilder
    private var headerButton: some View {
        switch mode {
        case .browse:
            Button { switchTo(.settings) } label: {
                Text(verbatim: tr("设置"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.horizontal, 13)
                    .frame(height: 28)
                    .background(Capsule().fill(.white.opacity(0.12)))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.6))
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .help(tr("提醒、快捷键和使用记录"))
        case .settings:
            Button { switchTo(.browse) } label: {
                Text(verbatim: tr("完成"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(accentInk)
                    .padding(.horizontal, 15)
                    .frame(height: 28)
                    .background(Capsule().fill(accent))
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
        }
    }

    private var subtitle: String {
        if preview { return MicPrivacyText.subtitle(micApps: 2, camera: true, muted: false) }
        return MicPrivacyText.subtitle(micApps: mic.apps.count, camera: mic.cameraOn, muted: muted)
    }

    private func switchTo(_ next: Mode) {
        recorder.stop()
        withAnimation(.easeInOut(duration: 0.2)) { mode = next }
    }

    // MARK: 浏览

    private var browse: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(tr("正在使用"))
            inUseList
            muteButton
            mutedNote
            if preview || mic.hasDevice {
                sectionTitle(tr("输入设备"))
                deviceList
                volumeSection
            } else {
                noDevice
            }
        }
    }

    private func sectionTitle(_ text: String, trailing: String? = nil) -> some View {
        HStack {
            Text(verbatim: text)
            Spacer(minLength: 8)
            if let trailing {
                Text(verbatim: trailing)
                    .monospacedDigit()
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white.opacity(0.62))
        .lineLimit(1)
        .padding(.top, 2)
    }

    // MARK: 正在使用

    private struct UseRow: Identifiable {
        var id: String
        var name: String
        var url: URL?
        var bundleID: String?
        var since: Date
        var isCamera: Bool
    }

    private var useRows: [UseRow] {
        if preview {
            let now = context.now
            return [
                UseRow(id: "a", name: tr("会议软件"), since: now.addingTimeInterval(-768), isCamera: false),
                UseRow(id: "b", name: tr("语音备忘"), since: now.addingTimeInterval(-190), isCamera: false),
                UseRow(id: MicActiveUse.cameraID, name: tr("摄像头开着"), since: now.addingTimeInterval(-768),
                       isCamera: true),
            ]
        }
        var rows = mic.apps.map {
            UseRow(id: $0.id, name: $0.name, url: $0.bundleURL, bundleID: $0.id, since: $0.since, isCamera: false)
        }
        if mic.cameraOn {
            rows.append(UseRow(id: MicActiveUse.cameraID, name: tr("摄像头开着"), since: mic.cameraSince ?? .now,
                               isCamera: true))
        }
        return rows
    }

    @ViewBuilder
    private var inUseList: some View {
        let rows = useRows
        if rows.isEmpty {
            HStack(spacing: 12) {
                if let image = PandaArt.image("pet-panda-idle") {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: tr("没有 App 在用麦克风和摄像头"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.94))
                    Text(verbatim: tr("有人开始用时会出现在这里"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(pane(0.07))
        } else {
            VStack(spacing: 6) {
                ForEach(rows) { useRow($0) }
            }
        }
    }

    private func useRow(_ row: UseRow) -> some View {
        HStack(spacing: 10) {
            if row.isCamera {
                glyphSquare("video.fill", color: camera, size: 36)
            } else {
                AppIconSquare(name: row.name, url: row.url, bundleID: row.bundleID, size: 36)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: row.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if row.isCamera {
                    chip(tr("摄像头"), symbol: "video.fill", color: camera)
                } else {
                    chip(tr("麦克风"), symbol: muted ? "mic.slash.fill" : "mic.fill", color: accent)
                }
            }
            Spacer(minLength: 6)
            Text(verbatim: MicPrivacyText.clock(elapsed(since: row.since)))
                .font(.system(size: 17, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .frame(height: 60)
        .background(pane(0.07))
        .accessibilityElement(children: .combine)
    }

    private func elapsed(since: Date) -> TimeInterval {
        _ = preview ? 0 : mic.tick
        return (preview ? context.now : .now).timeIntervalSince(since)
    }

    private func chip(_ text: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
            Text(verbatim: text)
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .frame(height: 20)
        .background(Capsule().fill(color.opacity(0.18)))
        .fixedSize()
    }

    private func glyphSquare(_ symbol: String, color: Color, size: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
            .fill(color.opacity(0.22))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(color)
            }
    }

    private func pane(_ opacity: Double, radius: CGFloat = 12) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(.white.opacity(opacity))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(.white.opacity(0.11), lineWidth: 0.6))
    }

    // MARK: 全局静音

    private var canMute: Bool { preview || mic.canGlobalMute }

    private var hotKeyText: String? { settings.muteKey?.displayString }

    private var muteButton: some View {
        Button {
            guard !preview, canMute else { return }
            mic.toggleGlobalMute()
        } label: {
            HStack(spacing: 14) {
                Circle()
                    .fill(muted ? redInk.opacity(0.18) : .white.opacity(0.16))
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: muted ? "mic.slash.fill" : "mic.fill")
                            .font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(muted ? redInk : .white)
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: muted ? tr("已静音") : tr("静音麦克风"))
                        .font(.system(size: 18, weight: muted ? .heavy : .bold))
                        .foregroundStyle(muted ? redInk : .white)
                    Text(verbatim: muteCaption)
                        .font(.system(size: 13, weight: muted ? .semibold : .medium))
                        .foregroundStyle(muted ? redInk.opacity(0.85) : .white.opacity(0.62))
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 76)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(muted ? red : .white.opacity(0.10))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(muted ? 0 : 0.2), lineWidth: 0.8))
            }
            .contentShape(.rect(cornerRadius: 18))
            .opacity(canMute ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!canMute)
        .accessibilityLabel(muted ? tr("取消静音麦克风") : tr("静音麦克风"))
        .help(muted ? tr("恢复静音前的输入音量") : tr("把输入音量拉到 0，所有 App 都听不到"))
    }

    private var muteCaption: String {
        guard canMute else { return tr("这个输入设备不能静音") }
        let base = muted ? tr("点一下恢复") : tr("所有 App 都听不到")
        guard let hotKeyText else { return base }
        return base + " · " + hotKeyText
    }

    /// 静音中还有 App 在用：告诉你它听不到。
    @ViewBuilder
    private var mutedNote: some View {
        if muted, let note = MicPrivacyText.mutedNote(names: mic.apps.map(\.name)), let first = mic.apps.first {
            HStack(spacing: 10) {
                AppIconSquare(name: first.name, url: first.bundleURL, bundleID: first.id, size: 24)
                Text(verbatim: note)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(pane(0.06))
        }
    }

    // MARK: 输入设备

    private var noDevice: some View {
        Text(verbatim: tr("没有输入设备。接上麦克风或耳机后会出现在这里。"))
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(pane(0.06))
    }

    private struct DeviceRow: Identifiable {
        var id: String
        var name: String
        var selected: Bool
        var device: MicrophoneMonitor.InputDevice?
    }

    private var deviceRows: [DeviceRow] {
        if preview {
            return [DeviceRow(id: "1", name: tr("内建麦克风"), selected: true),
                    DeviceRow(id: "2", name: tr("USB 麦克风"), selected: false),
                    DeviceRow(id: "3", name: tr("蓝牙耳机"), selected: false)]
        }
        var rows = mic.devices.map {
            DeviceRow(id: $0.uid, name: $0.name, selected: $0.id == mic.deviceID, device: $0)
        }
        // 设备列表还没读到时至少列出当前这个。
        if rows.isEmpty, mic.hasDevice {
            rows = [DeviceRow(id: "current", name: mic.deviceName, selected: true)]
        }
        return rows
    }

    private var deviceList: some View {
        let rows = deviceRows
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                Button {
                    guard let device = row.device, !row.selected else { return }
                    meter.stop()
                    mic.selectDevice(device)
                } label: {
                    HStack(spacing: 10) {
                        Text(verbatim: row.name)
                            .font(.system(size: 14, weight: row.selected ? .semibold : .medium))
                            .foregroundStyle(.white.opacity(row.selected ? 1 : 0.86))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 6)
                        check(row.selected)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(row.selected ? .isSelected : [])
                if index < rows.count - 1 {
                    Rectangle().fill(.white.opacity(0.1)).frame(height: 0.6).padding(.horizontal, 14)
                }
            }
        }
        .padding(.vertical, 2)
        .background(pane(0.06))
    }

    private func check(_ on: Bool) -> some View {
        ZStack {
            if on {
                Circle().fill(accent).frame(width: 20, height: 20)
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(accentInk)
            } else {
                Circle().strokeBorder(.white.opacity(0.45), lineWidth: 1.4).frame(width: 20, height: 20)
            }
        }
    }

    // MARK: 输入音量和电平

    private var volume: Double? { preview ? 0.7 : mic.volume }

    @ViewBuilder
    private var volumeSection: some View {
        sectionTitle(tr("输入音量"), trailing: volume.map { "\(Int(($0 * 100).rounded()))%" })
        levelMeter
        if let volume, preview || mic.volumeSettable {
            Slider(value: Binding(get: { volume }, set: { if !preview { mic.setVolume($0) } }), in: 0...1)
                .tint(accent)
                .controlSize(.small)
                .padding(.horizontal, 4)
                .accessibilityLabel(tr("输入音量"))
        } else {
            Text(verbatim: tr("这个设备不能在这里调输入音量"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
        }
    }

    private var levelMeter: some View {
        let level = preview ? 0.55 : meter.level
        let lit = MicLevel.lit(level)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(0..<MicLevel.segments, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(index < lit ? (index < MicLevel.greenSegments ? green : accent) : .white.opacity(0.12))
                        .frame(height: 14)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(tr("输入电平"))
            .accessibilityValue("\(Int(level * 100))%")
            if !preview { meterControl }
        }
    }

    @ViewBuilder
    private var meterControl: some View {
        HStack(spacing: 8) {
            Button { meter.toggle() } label: {
                Text(verbatim: meter.isRunning ? tr("停止测电平") : tr("测电平"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.horizontal, 12)
                    .frame(height: 26)
                    .background(Capsule().fill(.white.opacity(0.12)))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.6))
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .help(tr("测电平要用麦克风取声音，最多一分钟，面板关上就停，什么都不录下"))
            Text(verbatim: meterNote)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private var meterNote: String {
        switch meter.status {
        case .running: return muted ? tr("静音中，电平是 0") : tr("对着麦克风说话")
        case .denied: return tr("没有麦克风权限")
        case .failed: return tr("打不开麦克风")
        case .idle: return tr("点一下才用麦克风")
        }
    }

    // MARK: 设置

    private var settingsPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            muteButton
            mutedNote
            sectionTitle(tr("提醒"))
            VStack(spacing: 6) {
                toggleRow(tr("有 App 开始用麦克风"), key: MicPrivacySettings.notifyMicKey, on: settings.notifyMic)
                toggleRow(tr("摄像头亮起时"), key: MicPrivacySettings.notifyCameraKey, on: settings.notifyCamera)
                toggleRow(tr("静音时卡片变红"), key: MicPrivacySettings.redWhenMutedKey, on: settings.redWhenMuted)
            }
            NotificationsOffNote(active: settings.notifyMic || settings.notifyCamera, preview: preview)
            sectionTitle(tr("静音快捷键"))
            hotKeyRow
            history
        }
    }

    private func toggleRow(_ title: String, key: String, on: Bool) -> some View {
        HStack(spacing: 10) {
            Text(verbatim: title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))
                .lineLimit(1)
                .minimumScaleFactor(13.0 / 14.0)
            Spacer(minLength: 6)
            Toggle("", isOn: Binding(get: { on }, set: { value in
                guard !preview else { return }
                WidgetWriter.write(current) { $0.set(key, .bool(value)) }
            }))
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(accent)
            .controlSize(.small)
            .accessibilityLabel(title)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(pane(0.06))
    }

    private var hotKeyRow: some View {
        HStack(spacing: 6) {
            if recorder.isRecording {
                Text(verbatim: recorder.rejected ? tr("须含 ⌃⌥⌘") : tr("请按快捷键…"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
            } else if let combo = settings.muteKey {
                ForEach(Array(keyCaps(combo).enumerated()), id: \.offset) { _, cap in keyCap(cap) }
            } else {
                Text(verbatim: tr("未设置"))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
            }
            Spacer(minLength: 6)
            Button {
                guard !preview else { return }
                if recorder.isRecording {
                    recorder.stop()
                } else {
                    let widget = current
                    recorder.start { combo in
                        WidgetWriter.write(WidgetWriter.current(widget.id) ?? widget) {
                            $0.set(MicPrivacySettings.muteKeyKey, .string(MicPrivacySettings.encode(combo)))
                        }
                    }
                }
            } label: {
                Text(verbatim: recorder.isRecording ? tr("取消") : tr("录新快捷键"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.horizontal, 13)
                    .frame(height: 30)
                    .background(Capsule().fill(.white.opacity(0.12)))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.6))
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .help(tr("按下组合键；按 Esc 取消，按删除键清除。"))
        }
        .frame(minHeight: 34)
    }

    /// 修饰键一个一格，最后是键名。
    private func keyCaps(_ combo: KeyCombo) -> [String] {
        combo.modifierSymbols.map { String($0) } + [combo.keyName]
    }

    private func keyCap(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(minWidth: 36, minHeight: 34)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.25), lineWidth: 0.8))
            .fixedSize()
    }

    // MARK: 今天谁用过

    private var now: Date { preview ? context.now : .now }

    private var days: [Date] {
        if preview { return [Calendar.current.startOfDay(for: now)] }
        return mic.log.days(now: now, unlocked: unlocked)
    }

    private var shownDay: Date {
        let days = days
        if let day, days.contains(day) { return day }
        return days.first ?? Calendar.current.startOfDay(for: now)
    }

    private var historyRows: [MicUsageRow] {
        if preview {
            let start = Calendar.current.startOfDay(for: now)
            return [
                MicUsageRow(app: "a", name: tr("会议软件"), source: .microphone,
                            lastStart: start.addingTimeInterval(9.5 * 3600), total: 48 * 60, active: false),
                MicUsageRow(app: "b", name: tr("语音备忘"), source: .microphone,
                            lastStart: start.addingTimeInterval(10.33 * 3600), total: 3 * 60, active: false),
                MicUsageRow(app: MicActiveUse.cameraID, name: tr("摄像头"), source: .camera,
                            lastStart: start.addingTimeInterval(9.5 * 3600), total: 45 * 60, active: false),
            ]
        }
        _ = mic.tick
        return mic.log.rows(on: shownDay, now: now)
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(MicPrivacyText.dayTitle(shownDay, now: now) == tr("今天")
                         ? tr("今天谁用过") : tr("\(MicPrivacyText.dayTitle(shownDay, now: now))谁用过"),
                         trailing: tr("只存在本机"))
            if unlocked, days.count > 1 { dayChips }
            historyList
            if !unlocked, !preview { proHint }
        }
    }

    private var dayChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(days, id: \.self) { item in
                    let selected = Calendar.current.isDate(item, inSameDayAs: shownDay)
                    Button { day = item } label: {
                        Text(verbatim: MicPrivacyText.dayTitle(item, now: now))
                            .font(.system(size: 13, weight: selected ? .bold : .semibold))
                            .foregroundStyle(selected ? accentInk : .white.opacity(0.88))
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .background(Capsule().fill(selected ? accent : .white.opacity(0.08)))
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var historyList: some View {
        let rows = historyRows
        if rows.isEmpty {
            Text(verbatim: Calendar.current.isDate(shownDay, inSameDayAs: now)
                 ? tr("今天还没有 App 用过麦克风或摄像头") : tr("这天没有记录"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.62))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(pane(0.06))
        } else {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    historyRow(row)
                    if index < rows.count - 1 {
                        Rectangle().fill(.white.opacity(0.1)).frame(height: 0.6)
                            .padding(.leading, 46).padding(.trailing, 14)
                    }
                }
            }
            .padding(.vertical, 2)
            .background(pane(0.06))
        }
    }

    private func historyRow(_ row: MicUsageRow) -> some View {
        HStack(spacing: 10) {
            if row.source == .camera {
                glyphSquare("video.fill", color: camera, size: 24)
            } else {
                AppIconSquare(name: row.name, url: nil, bundleID: row.app, size: 24)
            }
            Text(verbatim: row.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            Image(systemName: row.source == .camera ? "video.fill" : "mic.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(row.source == .camera ? camera : accent)
            Spacer(minLength: 6)
            Text(verbatim: "\(MicPrivacyText.time(row.lastStart)) · \(MicPrivacyText.duration(row.total))")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(row.active ? 0.95 : 0.72))
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .accessibilityElement(children: .combine)
    }

    private var proHint: some View {
        Button { PaywallWindow.shared.show() } label: {
            HStack(spacing: 6) {
                ProBadge()
                Text(verbatim: tr("使用记录保留 30 天，可以往前翻"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(ProFeatures.help)
    }
}

/// 面板的配色，取自效果图 panels-batch2.py 的 ACC["mic"]、ACC["cam"]。
enum MicPanelStyle {
    static let base = "#1d1d21"
    static let accent = "#FFA24C"
    static let accentInk = "#2E1500"
    static let camera = "#5BD98A"
    static let green = "#5BD98A"
    static let red = "#FF6B5A"
    static let redInk = "#330B05"
}

/// App 图标：有 App 就画它自己的图标，找不到时画首字方块。
struct AppIconSquare: View {
    var name: String
    var url: URL?
    var bundleID: String?
    var size: CGFloat

    var body: some View {
        if let icon = AppIconCache.icon(url: url, bundleID: bundleID) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
                .fill(Color(hex: MicPrivacyText.initialColor(name)))
                .frame(width: size, height: size)
                .overlay {
                    Text(verbatim: MicPrivacyText.initial(name))
                        .font(.system(size: size * 0.5, weight: .bold))
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)
        }
    }
}

/// 每秒都要画的图标，按路径或 bundle id 记住，不用每次去问 NSWorkspace。
@MainActor
enum AppIconCache {
    private static var cache: [String: NSImage] = [:]
    private static var missing: Set<String> = []

    static func icon(url: URL?, bundleID: String?) -> NSImage? {
        let key = url?.path ?? bundleID ?? ""
        guard !key.isEmpty else { return nil }
        if let image = cache[key] { return image }
        if missing.contains(key) { return nil }
        let resolved = url ?? bundleID.flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
        guard let resolved else {
            missing.insert(key)
            return nil
        }
        let image = NSWorkspace.shared.icon(forFile: resolved.path)
        if cache.count > 200 { cache.removeAll() }
        cache[key] = image
        return image
    }
}
