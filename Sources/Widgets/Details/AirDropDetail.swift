import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 「隔空投送」面板，照第三批效果图（M6）：整块面板就是拖放区，文件拖进来
/// 松手直接调起系统的隔空投送；中间「选择文件发送…」挑文件发；下面「最近发过」
/// 列码头经手、发送成功的 5 个，点「再发一次」重发，文件不在了就提示。
///
/// 标题下面一行写接收模式（仅限联系人 / 所有人 / 接收关闭），点它打开系统设置；
/// 右上「打开隔空投送」是访达的隔空投送窗口，附近设备只在那里列出。
///
/// What is deliberately absent: nearby devices, other apps' transfer history,
/// and a mode picker. `sharingd` discovers peers over AWDL for its own UI and
/// publishes none of it to unprivileged apps, and `DiscoverableMode` is
/// readable but not ours to write. The footnote says so plainly.
///
/// The mode is read once, when the panel opens. It changes only when the user
/// goes and changes it - in Control Centre, in Finder, or in Settings - and
/// all three mean leaving this panel, which dismisses it.
struct AirDropDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @Environment(\.panelTint) private var panelTint

    /// `nil` covers both "not read yet" and "sharingd has no answer", because
    /// the panel says the same honest thing in either case.
    @State private var mode: Discoverability?
    @State private var dragging = false
    @State private var dragged = 0
    @State private var notice: String?
    @State private var noticeID = 0

    private var palette: FilePanelPalette {
        FilePanelPalette(accent: panelTint.accent(or: Color(hex: "#8DB8FF")),
                         ink: panelTint.ink(or: Color(hex: "#0A1B3A")))
    }

    private var available: Bool { context.isPreview || AirDropSender.available }

    private var state: AirDropDrop.State {
        AirDropDrop.state(available: available, dragging: dragging, files: dragged)
    }

    private var recent: [AirDropHistory.Entry] {
        context.isPreview ? [] : AirDropHistory.read(instance.config)
    }

    var body: some View {
        // 角上一抹模式色：联系人蓝、所有人橙、关闭灰，面积很小。
        DetailCard {
            MeshBackdrop(color: ground, fixed: true)
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                header
                dropZone
                if let notice {
                    Text(verbatim: notice)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                recentSection
                Text(verbatim: tr("接收模式仍在控制中心或系统设置里改"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onDrop(of: [.fileURL, .item], delegate: AirDropDropDelegate(
            enabled: !context.isPreview && AirDropSender.available,
            update: { inside, count in
                dragging = inside
                dragged = count
            },
            send: { [id = instance.id] urls in _ = AirDropSender.send(urls, recordInto: id) }))
        .onAppear(perform: read)
        .task(id: noticeID) {
            guard notice != nil else { return }
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { notice = nil }
        }
    }

    private var ground: Color {
        switch mode {
        case .contacts: Self.blue
        case .everyone: Color(red: 0.85, green: 0.5, blue: 0.1)
        case .off, nil: Color(white: 0.32)
        }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: tr("隔空投送"))
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white.opacity(0.97))
                Button(action: openSettings) {
                    Text(verbatim: "\(mode?.title ?? tr("无法获取设置")) · \(tr("设置")) ›")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(mode?.detail ?? tr("macOS 未报告可被发现模式。"))
            }
            Spacer(minLength: 0)
            Button(action: openWindow) {
                Text(verbatim: tr("打开隔空投送"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .padding(.horizontal, 13)
                    .frame(height: 28)
                    .background(Capsule().fill(.white.opacity(0.12)))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.6))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(tr("访达的隔空投送窗口，附近的设备在那里"))
        }
    }

    /// 虚线框：平时写「把文件拖到这里发送」和「选择文件发送…」；拖着文件停在
    /// 面板上换成「发送给附近设备 / N 个文件 · 松手选设备」；用不了时灰掉说明。
    private var dropZone: some View {
        let lit = state.highlighted
        return VStack(spacing: 10) {
            Text(verbatim: lit ? state.title : (state.disabled ? state.caption : tr("把文件拖到这里发送")))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(state.disabled ? 0.55 : 0.95))
                .lineLimit(1)
            if lit {
                Text(verbatim: state.caption)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.accent)
                    .monospacedDigit()
                    .frame(height: 30)
            } else {
                Button {
                    guard !context.isPreview else { return }
                    AirDropSender.chooseAndSend(recordInto: instance.id)
                } label: {
                    Text(verbatim: tr("选择文件发送…"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                        .padding(.horizontal, 18)
                        .frame(height: 30)
                        .background(Capsule().fill(palette.accent))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!available)
                .opacity(available ? 1 : 0.45)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 92)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(lit ? 0.07 : 0.03))
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(lit ? palette.accent.opacity(0.95) : palette.accent.opacity(0.6),
                              style: StrokeStyle(lineWidth: lit ? 1.6 : 1.2, dash: [5, 4]))
        }
        .dockAnimation(.snappy(duration: 0.18), value: state)
    }

    @ViewBuilder
    private var recentSection: some View {
        let entries = recent
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(verbatim: tr("最近发过"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
                Spacer(minLength: 0)
                Text(verbatim: tr("码头经手的"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
            }
            if entries.isEmpty {
                Text(verbatim: tr("从卡片或这里发出去的文件会列在这里，点一下再发一次。"))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 4) {
                    ForEach(entries, id: \.path) { entry in recentRow(entry) }
                }
            }
        }
    }

    private func recentRow(_ entry: AirDropHistory.Entry) -> some View {
        let url = URL(fileURLWithPath: entry.path)
        let exists = FileManager.default.fileExists(atPath: entry.path)
        return HStack(spacing: 10) {
            FileTypeBadgeView(file: ListedFile(url: url, date: entry.sent, isDirectory: Self.isFolder(url)), size: 24)
                .opacity(exists ? 1 : 0.4)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: entry.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(exists ? 0.95 : 0.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(verbatim: AirDropHistory.caption(entry, exists: exists, now: context.now))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(exists ? Color.white.opacity(0.55) : Color(hex: "#FFB3AA"))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                resend(entry)
            } label: {
                Text(verbatim: tr("再发一次"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(exists ? 0.92 : 0.5))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Capsule().fill(.white.opacity(0.12)))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.6))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!available)
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 0.6))
        }
        .contextMenu {
            if exists {
                Button(tr("在访达中显示")) { FileActions.reveal([url]) }
            }
            Button(tr("从列表移除")) { forget(entry) }
        }
        .help(entry.path)
    }

    private static func isFolder(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return values?.isDirectory == true && values?.isPackage != true
    }

    private func resend(_ entry: AirDropHistory.Entry) {
        guard !context.isPreview else { return }
        guard FileManager.default.fileExists(atPath: entry.path) else {
            NSSound.beep()
            say(AirDropHistory.goneNotice(entry.name))
            return
        }
        _ = AirDropSender.send([URL(fileURLWithPath: entry.path)], recordInto: instance.id)
    }

    private func forget(_ entry: AirDropHistory.Entry) {
        let current = WidgetWriter.current(instance.id) ?? instance
        WidgetWriter.write(current) { config in
            AirDropHistory.write(AirDropHistory.removing(entry.path, from: AirDropHistory.read(config)), into: &config)
        }
    }

    private func say(_ text: String) {
        withAnimation(.easeOut(duration: 0.2)) { notice = text }
        noticeID += 1
    }

    // MARK: Data

    private static let blue = Color(hex: "#0A7CFF")

    private func read() {
        guard !context.isPreview else {
            mode = .contacts
            return
        }
        // `sharingd` owns this preference and writes it whenever the user
        // flips the mode somewhere else entirely; cfprefsd keeps handing us a
        // cached copy until it is told to look again, which is all the
        // synchronise does. Public domain, undocumented schema - same footing
        // as the Dock's own preferences, so the read is a lenient match rather
        // than a switch over exact strings.
        _ = CFPreferencesAppSynchronize(Self.domain as CFString)
        let raw = CFPreferencesCopyAppValue("DiscoverableMode" as CFString,
                                            Self.domain as CFString) as? String
        mode = raw.flatMap(Discoverability.init(preference:))
    }

    private static let domain = "com.apple.sharingd"

    // MARK: Actions

    /// Finder's own AirDrop window - the only place peers are ever listed.
    private func openWindow() {
        guard !context.isPreview, let url = URL(string: "nwnode://domain-AirDrop") else { return }
        NSWorkspace.shared.open(url)
    }

    private func openSettings() {
        guard !context.isPreview,
              let url = WidgetTarget.settings("com.apple.AirDrop-Handoff-Settings.extension").settingsURL
        else { return }
        NSWorkspace.shared.open(url)
    }

    /// The three modes `sharingd` stores, with what each one costs the user.
    enum Discoverability {
        case off, contacts, everyone

        init?(preference: String) {
            switch preference.lowercased() {
            case let value where value.contains("everyone"): self = .everyone
            case let value where value.contains("contact"): self = .contacts
            case let value where value.contains("off"): self = .off
            default: return nil
            }
        }

        var title: String {
            switch self {
            case .off: tr("接收关闭")
            case .contacts: tr("仅限联系人")
            case .everyone: tr("所有人")
            }
        }

        /// Who can see this Mac, which is the question the mode answers.
        var detail: String {
            switch self {
            case .off: tr("附近的人都看不到这台 Mac。")
            case .contacts: tr("仅限你通讯录中已登录 iCloud 的联系人。")
            case .everyone: tr("附近的任何人都能看到这台 Mac。")
            }
        }

        /// Off is grey rather than red: it is a sensible way to leave a Mac,
        /// not a fault. Everyone is the one worth a warm colour.
        var tint: Color {
            switch self {
            case .off: Color.secondary.opacity(0.5)
            case .contacts: AirDropDetail.blue
            case .everyone: Color(hex: "#FF9F0A")
            }
        }
    }
}
