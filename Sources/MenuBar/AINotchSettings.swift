import AppKit
import SwiftUI

/// 设置 ▸ 通用 ▸ AI 助手：刘海入口的开关、快捷键、拾掇的说明，以及每个
/// 服务的打开方式（网页 / API / 跳转）和 API 的密钥、地址、模型。
struct AINotchSettingsSection: View {
    @Binding var state: PersistedState

    @State private var shiduoRunning = AINotchController.checkShiduo()

    private var center: AIChatCenter { AIChatCenter.shared }

    var body: some View {
        Section {
            Toggle("在刘海显示 AI 助手", isOn: $state.aiNotch.enabled)
                .help("点一下刘海展开对话，刘海两侧不多出任何东西；没有刘海的屏幕在菜单栏下方正中放一个小胶囊。")
            Toggle("只在主屏显示", isOn: $state.aiNotch.mainScreenOnly)
                .disabled(!state.aiNotch.enabled)
                .help("关掉时每块屏幕都有入口；打开后只在带菜单栏的那块屏幕上显示。")
            LabeledContent {
                HStack(spacing: 6) {
                    ShortcutRecorder(combo: state.aiNotch.hotKey) { state.aiNotch.hotKey = $0 }
                    if state.aiNotch.hotKey != nil {
                        Button("清除") { state.aiNotch.hotKey = nil }
                            .controlSize(.small)
                    }
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("展开对话的快捷键")
                    Text("默认不设。建议避开 ChatGPT 桌面版的 Option+空格。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let warning = AIHotKeyAdvice.warning(for: state.aiNotch.hotKey) {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if shiduoRunning {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label(AIShiduo.explanation, systemImage: "rectangle.on.rectangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if state.aiNotch.hotKey == nil {
                        Spacer(minLength: 0)
                        ShortcutRecorder(combo: nil) { state.aiNotch.hotKey = $0 }
                            .help("还没设快捷键：拾掇运行时刘海上没有入口，设一个快捷键就能随时展开对话。")
                    }
                }
            }
        } header: {
            Text("AI 助手")
        } footer: {
            Text("入口就是刘海本身，不占菜单栏的地方：指针移到刘海上，刘海下面会长出一小条显示小熊猫，点一下刘海或按快捷键才展开；回答生成中那一小条里是三个跳动的小点。外接屏的入口是菜单栏下方正中的小胶囊，平时半透明。「拾掇」在运行时刘海让给拾掇，码头不在刘海上放入口，请用快捷键或货架上 AI 卡片的小熊猫。灵动提示出现时入口暂时让位。货架上 AI 卡片的小熊猫打开的是同一个对话。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            shiduoRunning = AINotchController.checkShiduo()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            shiduoRunning = AINotchController.checkShiduo()
        }

        Section {
            ForEach(center.allServices) { service in
                AIServiceModeRow(service: service, settings: $state.aiNotch)
            }
        } header: {
            Text("AI 助手的打开方式")
        } footer: {
            Text("网页：在面板里打开官方网页，用你自己的账号，登录一次会记住。API：填了密钥后可选，兼容 OpenAI 的 /chat/completions 流式接口，密钥存在钥匙串里。跳转：打开 Mac App 或浏览器，和以前一样。豆包的 API 要填火山方舟的接入点 ID 作为模型名。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 设置表的一行：字牌、名字、“已填密钥”、三选一，展开后填密钥、地址和模型。
private struct AIServiceModeRow: View {
    var service: AIService
    @Binding var settings: AINotchSettings

    @State private var expanded = false
    @State private var keyText = ""
    @State private var note: String?

    private var center: AIChatCenter { AIChatCenter.shared }
    private var hasKey: Bool { center.hasKey(service.id) }

    var body: some View {
        let current = AIOpenModes.mode(for: service, settings: settings, hasKey: hasKey)
        let available = AIOpenModes.available(for: service, settings: settings, hasKey: hasKey)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.3), lineWidth: 1)
                    .frame(width: 24, height: 24)
                    .overlay {
                        Text(service.initial)
                            .font(.system(size: service.initial.count > 1 ? 9 : 11, weight: .semibold, design: .rounded))
                    }
                    .accessibilityHidden(true)
                Text(service.title)
                if hasKey {
                    Text("已填密钥")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                HStack(spacing: 2) {
                    ForEach(AIOpenMode.allCases, id: \.self) { mode in
                        let on = mode == current
                        let enabled = available.contains(mode)
                        Button {
                            settings.modes[service.id] = mode
                        } label: {
                            Text(mode.title)
                                .font(.system(size: 12, weight: on ? .semibold : .regular))
                                .frame(width: 42, height: 22)
                                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(on ? Color.accentColor.opacity(0.85) : Color.clear))
                                .foregroundStyle(on ? Color.white : (enabled ? Color.primary : Color.secondary.opacity(0.5)))
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .disabled(!enabled)
                        .help(modeHelp(mode, enabled: enabled))
                        .accessibilityLabel("\(service.title) 用\(mode.title)\(on ? "，当前" : "")")
                    }
                }
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
                Button {
                    expanded.toggle()
                } label: {
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("密钥、接口地址和模型")
                .accessibilityLabel(expanded ? "收起 \(service.title) 的接口设置" : "展开 \(service.title) 的接口设置")
            }
            if expanded {
                details
            }
        }
        .padding(.vertical, 2)
    }

    private func modeHelp(_ mode: AIOpenMode, enabled: Bool) -> String {
        switch mode {
        case .web: enabled ? "在面板里打开 \(service.title) 的网页，用你自己的账号。" : "这个服务没有网址。"
        case .api: enabled ? "用 API 在面板里对话。" : "先展开这一行填好密钥（以及接口地址和模型）。"
        case .jump: "打开 Mac App 或浏览器（原来的做法）。"
        }
    }

    private var endpoint: Binding<AIEndpoint> {
        Binding(get: { settings.endpoints[service.id] ?? AIEndpoint() },
                set: { value in
                    if value.baseURL.trimmingCharacters(in: .whitespaces).isEmpty
                        && value.model.trimmingCharacters(in: .whitespaces).isEmpty {
                        settings.endpoints[service.id] = nil
                    } else {
                        settings.endpoints[service.id] = value
                    }
                })
    }

    @ViewBuilder private var details: some View {
        let fallback = AIEndpoints.defaults[service.id]
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SecureField(hasKey ? "已保存，粘贴新的密钥可替换" : "粘贴 API 密钥", text: $keyText)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("\(service.title) 的 API 密钥")
                Button("保存") { saveKey() }
                    .disabled(keyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if hasKey {
                    Button("删除密钥", role: .destructive) { deleteKey() }
                }
            }
            HStack(spacing: 8) {
                TextField("接口地址", text: endpoint.baseURL,
                          prompt: Text(fallback?.baseURL ?? "https://…/v1"))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("\(service.title) 的接口地址")
                TextField("模型", text: endpoint.model,
                          prompt: Text(AIEndpoints.requiresModel(service.id)
                                       ? "接入点 ID" : (fallback?.model.isEmpty == false ? fallback!.model : "模型名")))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                    .accessibilityLabel("\(service.title) 的模型名")
            }
            Text(note ?? detailHint(fallback))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 34)
    }

    private func detailHint(_ fallback: AIEndpoint?) -> String {
        if AIEndpoints.requiresModel(service.id) {
            return "豆包要在火山方舟控制台创建接入点，把接入点 ID（ep- 开头）填进“模型”。密钥只存在这台 Mac 的钥匙串里。"
        }
        if fallback == nil {
            return "填兼容 OpenAI 的接口地址（会接上 /chat/completions）和模型名。密钥只存在这台 Mac 的钥匙串里。"
        }
        return "地址和模型留空就用默认值。密钥只存在这台 Mac 的钥匙串里。"
    }

    private func saveKey() {
        guard AIKeyStore.write(keyText, for: service.id) else {
            note = "没能存进钥匙串，再试一次。"
            return
        }
        keyText = ""
        if AIEndpoints.resolved(service.id, override: settings.endpoints[service.id]) != nil {
            settings.modes[service.id] = .api
            note = "密钥已存进钥匙串，已改用 API。"
        } else {
            note = "密钥已存进钥匙串。再填好接口地址和模型就能选 API。"
        }
    }

    private func deleteKey() {
        AIKeyStore.delete(service.id)
        if settings.modes[service.id] == .api { settings.modes[service.id] = nil }
        note = "密钥已删除。"
    }
}
