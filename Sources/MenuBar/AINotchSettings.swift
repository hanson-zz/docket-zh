import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 设置 ▸ AI：刘海入口的开关、快捷键（在“快捷键”页录制）、拾掇的说明，以及每个
/// 服务的打开方式（网页 / API / App）、API 的密钥、地址、模型，以及 App 方式打开哪个 Mac App。
struct AINotchSettingsSection: View {
    @Binding var state: PersistedState

    @State private var shiduoRunning = AINotchController.checkShiduo()
    @AppStorage(ProAccess.licenseKey) private var licenseUnlocked = false
    @AppStorage(Supporter.key) private var supporter = false

    /// 刘海对话是码头 Pro 功能。
    private var unlocked: Bool {
        ProLicenseGate.canUse(.aiNotch, unlocked: licenseUnlocked || supporter)
    }

    private var center: AIChatCenter { AIChatCenter.shared }

    var body: some View {
        Section {
            if !unlocked {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label(tr("刘海对话是码头 Pro 功能。没有解锁时点刘海或按快捷键只会打开付费墙；AI 卡片跳转到网页或 App 照旧免费。"),
                          systemImage: "lock.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button(tr("解锁码头 Pro…")) { PaywallWindow.shared.show() }
                }
            }
            // 没解锁时打开开关只弹付费墙；关掉不拦。
            Toggle("在刘海显示 AI 助手", isOn: Binding(
                get: { state.aiNotch.enabled },
                set: { on in
                    if on, !unlocked {
                        PaywallWindow.shared.show()
                        return
                    }
                    state.aiNotch.enabled = on
                }))
                .help("点一下刘海展开对话，刘海两侧不多出任何东西；没有刘海的屏幕在菜单栏下方正中放一个小胶囊。")
            Toggle("只在主屏显示", isOn: $state.aiNotch.mainScreenOnly)
                .disabled(!state.aiNotch.enabled)
                .help("关掉时每块屏幕都有入口；打开后只在带菜单栏的那块屏幕上显示。")
            // 快捷键本身在“设置 ▸ 快捷键”里录制，这里只说现在是什么。
            LabeledContent("展开对话的快捷键") {
                Button(state.aiNotch.hotKey?.displayString ?? tr("未设置")) {
                    SettingsSelection.shared.current = "Shortcuts"
                }
                .buttonStyle(.link)
                .help("到“快捷键”页录制或清除。")
            }
            if shiduoRunning {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Label(AIShiduo.explanation, systemImage: "rectangle.on.rectangle")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if state.aiNotch.hotKey == nil {
                        Spacer(minLength: 0)
                        ShortcutRecorder(combo: nil) { state.aiNotch.hotKey = $0 }
                            .help("还没设快捷键：拾掇运行时刘海上没有入口，设一个快捷键就能随时展开对话。")
                    }
                }
            }
            // 长说明放在表格里而不是表尾：分组表的表尾在窄窗口里会被裁掉。
            Text("入口就是刘海本身，不占菜单栏的地方：指针移到刘海上，刘海下面会长出一小条显示小熊猫，点一下刘海或按快捷键才展开；回答生成中那一小条里是三个跳动的小点。外接屏的入口是菜单栏下方正中的小胶囊，平时半透明。「拾掇」在运行时刘海让给拾掇，码头不在刘海上放入口，请用快捷键或货架上 AI 卡片的小熊猫。灵动提示出现时入口暂时让位。货架上 AI 卡片的小熊猫打开的是同一个对话。")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } header: {
            ProLabel(title: tr("AI 助手"), isPro: true)
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            shiduoRunning = AINotchController.checkShiduo()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            shiduoRunning = AINotchController.checkShiduo()
        }

        Section {
            AIOpenModeNotes()
            ForEach(center.allServices) { service in
                AIServiceModeRow(service: service, settings: $state.aiNotch)
            }
        } header: {
            Text("AI 助手的打开方式")
        }

        AIPromptsSection(prompts: $state.aiNotch.prompts)
    }
}

/// 打开方式表最上面的三行短说明：每种方式一行，13pt，不放在会被裁切的表尾。
private struct AIOpenModeNotes: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(AIOpenMode.allCases, id: \.self) { mode in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(mode.title)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(minWidth: 40, alignment: .leading)
                    Text(AIAPISetup.modeNote(mode))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, 2)
    }
}

/// 设置表的一行：字牌、名字、“已填密钥”、三选一和展开按钮；展开后是 API
/// （接口地址、密钥、模型、获取密钥、测试连接）和 App（会打开什么、选择 App…）。
///
/// API 段总能点：差东西时把选择记下，展开这一行，焦点放到缺的那一格，旁边写
/// 「填入密钥后生效」；密钥存好后发一个最小请求校验，通过就改用 API。
private struct AIServiceModeRow: View {
    var service: AIService
    @Binding var settings: AINotchSettings

    @State private var expanded = false
    @State private var keyText = ""
    @State private var note: String?
    @State private var checking = false
    @State private var endpointEdited = false
    @FocusState private var focus: AIAPISetup.Field?

    private var center: AIChatCenter { AIChatCenter.shared }
    private var hasKey: Bool { center.hasKey(service.id) }
    private var saved: AIOpenMode { settings.modes[service.id] ?? AIOpenModes.defaultMode(service) }
    private var readiness: AIAPISetup.Readiness {
        AIAPISetup.readiness(serviceID: service.id, override: settings.endpoints[service.id], hasKey: hasKey)
    }

    var body: some View {
        let effective = AIOpenModes.mode(for: service, settings: settings, hasKey: hasKey)
        let pending = saved == .api && effective != .api
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
                    .lineLimit(1)
                if hasKey {
                    Text("已填密钥")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                segments(effective: effective)
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
                } label: {
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("接口地址、密钥、模型和 Mac App")
                .accessibilityLabel(expanded ? tr("收起 \(service.title) 的设置") : tr("展开 \(service.title) 的设置"))
            }
            if pending, let hint = AIAPISetup.pendingHint(readiness, serviceID: service.id) {
                Label(tr("API \(hint)，现在先用\(effective.title)"), systemImage: "info.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 34)
            }
            if expanded {
                details
            }
        }
        .padding(.vertical, 2)
        .onChange(of: focus) { old, _ in
            // 改完地址或模型、焦点离开时，选的是 API 且已经齐了就校验一次。
            guard old == .baseURL || old == .model, endpointEdited, saved == .api, readiness == .ready else { return }
            endpointEdited = false
            check(intent: .api)
        }
    }

    // MARK: 三选一

    private func segments(effective: AIOpenMode) -> some View {
        HStack(spacing: 2) {
            ForEach(AIOpenMode.allCases, id: \.self) { mode in
                let look = AIAPISetup.segment(mode, saved: saved, effective: effective, hasWeb: service.homeURL != nil)
                Button {
                    tap(mode)
                } label: {
                    Text(mode.title)
                        .font(.system(size: 13, weight: look == .current ? .semibold : .regular))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 9)
                        .frame(minWidth: 44, minHeight: 22)
                        .background {
                            let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
                            switch look {
                            case .current: shape.fill(Color.accentColor.opacity(0.85))
                            case .pending: shape.strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                            default: Color.clear
                            }
                        }
                        .foregroundStyle(segmentColor(look))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(look == .unavailable)
                .help(modeHelp(mode, look: look))
                .accessibilityLabel(tr("\(service.title) 用\(mode.title)\(look == .current ? tr("，当前") : "")"))
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
    }

    private func segmentColor(_ look: AIAPISetup.Segment) -> Color {
        switch look {
        case .current: .white
        case .pending: .accentColor
        case .normal: .primary
        case .unavailable: Color.secondary.opacity(0.5)
        }
    }

    private func modeHelp(_ mode: AIOpenMode, look: AIAPISetup.Segment) -> String {
        switch mode {
        case .web:
            return look == .unavailable ? tr("这个服务没有网址。") : tr("在面板里打开 \(service.title) 的网页，用你自己的账号。")
        case .api:
            if look == .pending, let hint = AIAPISetup.pendingHint(readiness, serviceID: service.id) { return hint }
            return readiness == .ready ? tr("用 API 在面板里对话。") : tr("点一下展开，填好密钥就能用 API。")
        case .jump: return tr("打开 Mac App，没装就用浏览器。")
        }
    }

    private func tap(_ mode: AIOpenMode) {
        note = nil
        guard mode == .api else {
            settings.modes[service.id] = mode
            return
        }
        settings.modes[service.id] = .api
        switch AIAPISetup.tapAPI(readiness) {
        case .select:
            break
        case .expand(let field):
            withAnimation(.easeOut(duration: 0.15)) { expanded = true }
            // 展开的那一帧输入框还没出现，下一轮再给焦点。
            Task { @MainActor in focus = field }
        }
    }

    // MARK: 展开区

    private var endpoint: Binding<AIEndpoint> {
        Binding(get: { settings.endpoints[service.id] ?? AIEndpoint() },
                set: { value in
                    endpointEdited = true
                    if value.baseURL.trimmingCharacters(in: .whitespaces).isEmpty
                        && value.model.trimmingCharacters(in: .whitespaces).isEmpty {
                        settings.endpoints[service.id] = nil
                    } else {
                        settings.endpoints[service.id] = value
                    }
                })
    }

    private var modelPrompt: String {
        if AIEndpoints.requiresModel(service.id) { return tr("接入点 ID（ep- 开头）") }
        if let model = AIEndpoints.defaults[service.id]?.model, !model.isEmpty { return model }
        return tr("模型名")
    }

    @ViewBuilder private var details: some View {
        let fallback = AIEndpoints.defaults[service.id]
        VStack(alignment: .leading, spacing: 10) {
            Text(verbatim: "API")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    fieldLabel(tr("接口地址"))
                    TextField("接口地址", text: endpoint.baseURL, prompt: Text(fallback?.baseURL ?? "https://…/v1"))
                        .textFieldStyle(.roundedBorder)
                        .focused($focus, equals: .baseURL)
                        .accessibilityLabel(tr("\(service.title) 的接口地址"))
                }
                GridRow {
                    fieldLabel(tr("密钥"))
                    HStack(spacing: 8) {
                        SecureField("密钥", text: $keyText,
                                    prompt: Text(hasKey ? tr("已保存，粘贴新的密钥可替换") : tr("粘贴 API 密钥")))
                            .textFieldStyle(.roundedBorder)
                            .focused($focus, equals: .key)
                            .onSubmit(saveKey)
                            .accessibilityLabel(tr("\(service.title) 的 API 密钥"))
                        Button("保存", action: saveKey)
                            .disabled(keyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if hasKey {
                            Button("删除密钥", role: .destructive, action: deleteKey)
                        }
                    }
                }
                GridRow {
                    fieldLabel(AIEndpoints.requiresModel(service.id) ? tr("接入点 ID") : tr("模型"))
                    TextField("模型", text: endpoint.model, prompt: Text(modelPrompt))
                        .textFieldStyle(.roundedBorder)
                        .focused($focus, equals: .model)
                        .accessibilityLabel(tr("\(service.title) 的模型名"))
                }
            }
            HStack(spacing: 12) {
                if let page = AIAPISetup.keyPage(service.id) {
                    Link(destination: page) {
                        Label("获取密钥", systemImage: "arrow.up.right.square")
                    }
                    .font(.system(size: 13))
                    .help(page.absoluteString)
                }
                Button("测试连接") { check(intent: settings.modes[service.id]) }
                    .disabled(readiness != .ready || checking)
                    .help("发一个最小的请求，看密钥、地址和模型对不对。")
                if checking {
                    ProgressView().controlSize(.small)
                    Text("正在测试…")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Text(note ?? detailHint(fallback))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            appSection
        }
        .padding(.leading, 34)
        .padding(.top, 2)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize()
            .gridColumnAlignment(.trailing)
    }

    private func detailHint(_ fallback: AIEndpoint?) -> String {
        var lines: [String] = []
        if let provider = AIAPISetup.providerNote(service.id) { lines.append(provider) }
        if fallback == nil {
            lines.append(tr("填兼容 OpenAI 的接口地址（会接上 /chat/completions）和模型名。"))
        } else if fallback?.model.isEmpty == false {
            lines.append(tr("地址和模型留空就用默认值。"))
        } else {
            lines.append(tr("地址留空就用默认值。"))
        }
        lines.append(tr("密钥只存在这台 Mac 的钥匙串里。"))
        return lines.joined(separator: " ")
    }

    // MARK: App

    @ViewBuilder private var appSection: some View {
        let target = AIServiceOpener.target(for: service)
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: "App")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Label(AIAppMatch.describe(target), systemImage: target == .web || target == .nothing ? "safari" : "app.badge.checkmark")
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("选择 App…", action: chooseApp)
                if settings.appPaths[service.id] != nil {
                    Button("改回自动查找") { settings.appPaths[service.id] = nil }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = tr("选择")
        panel.message = tr("选一个 Mac App，「App」方式会打开它。")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.appPaths[service.id] = url.path
    }

    // MARK: 密钥和校验

    private func saveKey() {
        let input = AIAPISetup.normalizedKey(keyText)
        guard case .ok(let key) = input else {
            note = input.message
            return
        }
        guard AIKeyStore.write(key, for: service.id) else {
            note = tr("没能存进钥匙串，再试一次。")
            return
        }
        keyText = ""
        let now = AIAPISetup.readiness(serviceID: service.id, override: settings.endpoints[service.id], hasKey: true)
        if now == .ready {
            check(intent: .api)
        } else {
            // 还差地址或模型：先记下要用 API，焦点移到缺的那一格。
            settings.modes[service.id] = .api
            note = [tr("密钥已存进钥匙串。"), AIAPISetup.pendingHint(now, serviceID: service.id)]
                .compactMap { $0 }.joined(separator: " ")
            if case .expand(let field) = AIAPISetup.tapAPI(now) { focus = field }
        }
    }

    private func deleteKey() {
        AIKeyStore.delete(service.id)
        let wasAPI = settings.modes[service.id] == .api
        settings.modes[service.id] = AIAPISetup.modeAfterKeyDeleted(settings.modes[service.id])
        note = wasAPI ? tr("密钥已删除，已改回网页。") : tr("密钥已删除。")
    }

    /// 发最小请求校验，按结果决定用不用 API。`intent` 是用户想要的方式。
    private func check(intent: AIOpenMode?) {
        guard !checking, let endpoint = center.endpoint(for: service), let key = AIKeyStore.read(service.id) else { return }
        checking = true
        note = nil
        let id = service.id
        Task { @MainActor in
            let verdict = await AIChatClient.check(endpoint: endpoint, key: key)
            checking = false
            let mode = AIAPISetup.modeAfterCheck(verdict, intent: intent)
            settings.modes[id] = mode
            note = AIAPISetup.checkNote(verdict, mode: mode)
        }
    }
}
