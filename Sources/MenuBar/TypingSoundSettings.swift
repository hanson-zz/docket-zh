import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 设置 ▸ 打字音效，照效果图 design/typing-sounds-light.png / -dark.png：
///
/// - 头图：键帽图标、标题、一句说明、总开关（默认关），右边三颗键帽的小示意；
/// - 「输入监控」：授权状态、去授权，写清楚只听键码、不记录内容、输入密码时静音；
/// - 「声音」：七款卡片（青轴免费，其余带 Pro 标，录音的标「录音」），点卡片选并试听一下；
///   免费用户点 Pro 款弹升级页，不改选择；
/// - 「Mechvibes 声音包」（Pro）：导入 .zip 或文件夹、列表、删除；
/// - 「音量」：相对音量滑杆和试听。
///
/// 液态玻璃分组表单，跟随浅色 / 深色，不用大面积蓝色发光，字至少 13pt。
struct TypingSoundSettingsPane: View {
    @Binding var settings: TypingSoundSettings

    @AppStorage(ProAccess.licenseKey) private var licenseUnlocked = false
    @AppStorage(Supporter.key) private var supporter = false

    @State private var permitted = TypingSoundPermission.granted
    @State private var importing = false
    @State private var pendingDelete: TypingSoundPackRecord?

    private var unlocked: Bool { licenseUnlocked || supporter }
    private var effective: TypingSoundChoice { TypingSoundGate.effectiveChoice(settings, unlocked: unlocked) }

    var body: some View {
        Form {
            Section {
                TypingSoundHero(enabled: $settings.enabled)
                    .listRowInsets(EdgeInsets())
            }
            permissionSection
            stylesSection
            packsSection
            volumeSection
        }
        .formStyle(.grouped)
        .task {
            // 用户可能开着设置去系统设置里给权限：隔两秒再看一眼（看一次很便宜）。
            while !Task.isCancelled {
                permitted = TypingSoundPermission.granted
                try? await Task.sleep(for: .seconds(2))
            }
        }
        .confirmationDialog(tr("删除这个声音包？"), isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), presenting: pendingDelete) { pack in
            Button(tr("删除"), role: .destructive) { delete(pack) }
        } message: { pack in
            Text(tr("「\(pack.name)」会从这台 Mac 上删掉，要用时再导入一次。"))
        }
    }

    // MARK: 权限

    private var permissionSection: some View {
        Section {
            LabeledContent {
                if permitted {
                    Label(tr("已授权"), systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.green)
                } else {
                    Button(tr("去授权")) { TypingSoundPermission.request() }
                        .controlSize(.regular)
                }
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("输入监控权限"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(tr("只用来知道按了哪个键好放对应的声音：不读、不存、不上传你打的任何内容。输入密码时自动静音。"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if settings.enabled && !permitted {
                Label {
                    Text(tr("还没授权，打字时不会出声。在系统设置 ▸ 隐私与安全性 ▸ 输入监控里打开「码头」；打开后仍没声音时，退出码头再打开一次。"))
                        .font(.system(size: 13))
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            Text(tr("权限"))
        }
    }

    // MARK: 七款

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 12)]

    private var stylesSection: some View {
        Section {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(TypingSoundStyle.allCases, id: \.self) { style in
                    TypingStyleCard(style: style, selected: settings.selected == .style(style),
                                    locked: !TypingSoundGate.canChoose(.style(style), unlocked: unlocked)) {
                        choose(.style(style))
                    }
                }
            }
            .padding(.vertical, 4)
            if settings.selected.isPro, !TypingSoundGate.canChoose(settings.selected, unlocked: unlocked) {
                Text(tr("选着的是 Pro 声音，解锁前先用青轴。"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(tr("声音"))
        } footer: {
            Text(tr("回车、空格、删除各有自己的声音，其余键在几个变体里随机，音高也略有起伏。按住不放连发时最多每 0.15 秒响一声。"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    private func choose(_ choice: TypingSoundChoice) {
        guard TypingSoundGate.canChoose(choice, unlocked: unlocked) else {
            PaywallWindow.shared.show()
            return
        }
        withAnimation(.smooth(duration: 0.2)) { settings.choice = choice.raw }
        var next = settings
        next.choice = choice.raw
        TypingSoundController.shared.preview(next)
    }

    // MARK: Mechvibes 声音包

    private var packsSection: some View {
        Section {
            if settings.packs.isEmpty {
                Text(tr("支持 Mechvibes 声音包：选 .zip 或解压后的文件夹（config.json 加声音文件）。只在本机读，不联网，存在码头自己的文件夹里，随时能删。"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(settings.packs) { pack in
                TypingPackRow(pack: pack, selected: settings.selected == .pack(pack.id),
                              locked: !TypingSoundGate.canImport(unlocked: unlocked),
                              choose: { choose(.pack(pack.id)) },
                              delete: { pendingDelete = pack })
            }
        } header: {
            HStack(spacing: 8) {
                Text(tr("Mechvibes 声音包"))
                ProBadge()
                Spacer()
                Button {
                    importPack()
                } label: {
                    if importing {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(tr("正在导入…")).font(.system(size: 13, weight: .semibold))
                        }
                    } else {
                        Label(tr("导入 Mechvibes 声音包…"), systemImage: "square.and.arrow.down")
                            .font(.system(size: 13, weight: .semibold))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(importing)
            }
        }
    }

    private func importPack() {
        guard TypingSoundGate.canImport(unlocked: unlocked) else {
            PaywallWindow.shared.show()
            return
        }
        let panel = NSOpenPanel()
        panel.title = tr("导入 Mechvibes 声音包")
        panel.prompt = tr("导入")
        panel.message = tr("选声音包的 .zip，或解压后带 config.json 的文件夹")
        panel.allowedContentTypes = [.zip, .folder]
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importing = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result(catching: { try TypingSoundPackStore.importPack(from: url) })
            }.value
            importing = false
            switch result {
            case .success(let record):
                withAnimation(.smooth(duration: 0.2)) {
                    settings.packs.append(record)
                    settings.choice = TypingSoundChoice.pack(record.id).raw
                }
                TypingSoundController.shared.preview(settings)
            case .failure(let error):
                let alert = NSAlert()
                alert.messageText = tr("没能导入这个声音包")
                alert.informativeText = (error as? TypingSoundPackStore.ImportError)?.message ?? error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }

    private func delete(_ pack: TypingSoundPackRecord) {
        withAnimation(.smooth(duration: 0.2)) { settings.removePack(pack.id) }
        let id = pack.id
        Task.detached(priority: .utility) { TypingSoundPackStore.remove(id) }
    }

    // MARK: 音量

    private var volumeSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Slider(value: Binding(get: { settings.clampedVolume },
                                      set: { settings.volume = $0 }), in: 0...1) {
                    Text(tr("音量"))
                }
                .labelsHidden()
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(verbatim: "\(Int((settings.clampedVolume * 100).rounded()))%")
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
                Button {
                    TypingSoundController.shared.preview(settings)
                } label: {
                    Label(tr("试听"), systemImage: "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.bordered)
            }
        } header: {
            Text(tr("音量"))
        } footer: {
            Text(tr("相对音量，和系统音量叠在一起：系统静音或没有输出设备时不出声。"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 头图

private struct TypingSoundHero: View {
    @Binding var enabled: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(hex: ShelfColor.redPanda.hex)))
                        .accessibilityHidden(true)
                    Text(tr("打字音效"))
                        .font(.system(size: 26, weight: .bold))
                }
                Text(tr("敲键盘时听见机械键盘或打字机的声音"))
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Toggle(tr("打字音效"), isOn: $enabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                    Text(enabled ? tr("已开启") : tr("已关闭"))
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            KeycapTrio()
                .frame(width: 190, height: 96)
                .accessibilityHidden(true)
        }
        .padding(18)
    }
}

/// 头图右边三颗键帽：中间那颗按下去，上面两道声波。静态。
private struct KeycapTrio: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TypingKeycap(label: "A", pressed: false, tint: nil)
            ZStack(alignment: .top) {
                TypingKeycap(label: "S", pressed: true, tint: Color(hex: ShelfColor.redPanda.hex))
                Image(systemName: "waveform")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .offset(y: -24)
            }
            TypingKeycap(label: "D", pressed: false, tint: nil)
        }
        .padding(.top, 22)
    }
}

/// 一颗键帽：顶面加一圈侧边，浅色深色各一套。
private struct TypingKeycap: View {
    var label: String
    var pressed: Bool
    var tint: Color?
    var size: CGFloat = 52

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let side = tint.map { $0.opacity(0.75) } ?? (scheme == .dark ? Color(hex: "#2A2A2E") : Color(hex: "#C9C9CF"))
        let top = tint ?? (scheme == .dark ? Color(hex: "#3A3A40") : Color(hex: "#F4F4F6"))
        let lift = pressed ? size * 0.05 : size * 0.12
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                .fill(side)
                .frame(width: size, height: size)
            RoundedRectangle(cornerRadius: size * 0.17, style: .continuous)
                .fill(top)
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.17, style: .continuous)
                        .strokeBorder(.white.opacity(scheme == .dark ? 0.08 : 0.6), lineWidth: 0.8)
                }
                .overlay {
                    Text(label)
                        .font(.system(size: max(13, size * 0.3), weight: .semibold))
                        .foregroundStyle(tint == nil ? Color.primary.opacity(0.75) : .white)
                }
                .frame(width: size * 0.82, height: size - lift - size * 0.04)
                .padding(.top, size * 0.03)
        }
        .frame(width: size, height: size)
        .offset(y: pressed ? size * 0.05 : 0)
    }
}

// MARK: - 款式卡片

private struct TypingStyleCard: View {
    let style: TypingSoundStyle
    let selected: Bool
    let locked: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    /// 每款一颗代表色的小键帽（轴体颜色的意思），不是品牌色。
    private var tint: Color {
        switch style {
        case .blue: Color(hex: "#3B82C4")
        case .brown: Color(hex: "#8B5E3C")
        case .typewriter: Color(hex: "#3F3F46")
        case .red: Color(hex: "#D9443F")
        case .black: Color(hex: "#27272A")
        case .capacitive: Color(hex: "#7C6AA8")
        case .quiet: Color(hex: "#9CA3AF")
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                TypingKeycap(label: style == .typewriter ? "T" : "", pressed: selected, tint: tint, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(style.title)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                        if style.isPro { ProBadge(compact: false) }
                    }
                    Text(style.caption)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(style.isRecording ? tr("真实录音") : tr("原创合成"))
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : .primary.opacity(0.08), lineWidth: selected ? 2 : 1)
            }
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .padding(7)
                } else if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(8)
                }
            }
            .contentShape(.rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .help(locked ? ProFeatures.help : style.caption)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - 导入的包

private struct TypingPackRow: View {
    let pack: TypingSoundPackRecord
    let selected: Bool
    let locked: Bool
    let choose: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: choose) {
                HStack(spacing: 10) {
                    Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(selected ? Color.accentColor : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pack.name)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Text(detail)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if locked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Button(role: .destructive, action: delete) {
                Image(systemName: "trash")
                    .font(.system(size: 13))
            }
            .buttonStyle(.borderless)
            .help(tr("删除这个声音包"))
            .accessibilityLabel(tr("删除这个声音包"))
        }
    }

    private var detail: String {
        let keys = tr("\(pack.keyCount) 个键")
        return pack.author.isEmpty ? keys : "\(pack.author) · \(keys)"
    }
}
