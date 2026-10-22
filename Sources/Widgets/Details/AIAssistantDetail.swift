import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// AI 助手的面板：迷你提问，或者管理字牌。
///
/// 提问：多行输入框，Enter 提交，Shift+Enter 换行，中文输入法选字时的
/// Enter 只确认选字。下面选发给哪个服务（默认是蓝点那个）。主按钮的字很短：
/// 装了 App 是“打开 豆包”（复制问题再开 App），没装是“去网页问”（能带问题的
/// 带进网址，不能的先复制），API 方式是“发送”；具体会做什么写在下面的提示句里。
/// App 方式不调用任何接口，也就不显示“已发送”“已回答”之类的状态，回答在那个服务里看。
///
/// 两种模式用同一个高度：面板的大小在打开时量一次，之后切换模式不会重新量。
struct AIAssistantDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var state: AIPanelState { AIPanelState.shared }
    private var config: WidgetConfig { instance.config }
    private var services: [AIService] { AIServices.enabled(in: config) }

    static let bodyHeight: CGFloat = 300

    var body: some View {
        DetailCard {
            MeshBackdrop(color: Color(hex: ShelfColor.redPanda.hex))
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                header
                Group {
                    if state.mode == .manage {
                        AIManageView(instance: instance, context: context)
                    } else {
                        AIAskView(instance: instance, context: context, services: services)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(height: Self.bodyHeight, alignment: .top)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            AIPandaAvatar(size: 28)
            if state.mode == .manage {
                Text(tr("管理字牌"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
            } else {
                // 提问时顶栏不再写「问问 AI」（输入框里已经写着「想问点什么？」），
                // 位置让给刘海对话开关。
                AINotchSwitch(isPreview: context.isPreview)
            }
            Spacer(minLength: 0)
            Button(state.mode == .manage ? tr("完成") : tr("管理字牌")) {
                state.mode = state.mode == .manage ? .ask : .manage
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.panelPrimary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(.panelFill))
            .accessibilityLabel(state.mode == .manage ? tr("完成管理，回到提问") : tr("管理字牌"))
        }
    }
}

/// 顶栏里的「在刘海里对话 Pro」开关：已解锁时切换刘海入口（设置 ▸ AI 里「在刘海
/// 显示 AI 助手」同一个键 `aiNotch.enabled`）；没解锁时开关画成关着，点了弹付费墙，
/// 不改设置（同设置页：没解锁时打开只弹付费墙）。Pro 标识固定显示。
struct AINotchSwitch: View {
    var isPreview: Bool

    @AppStorage(ProAccess.licenseKey) private var licenseUnlocked = false
    @AppStorage(Supporter.key) private var supporter = false

    private var center: AIChatCenter { AIChatCenter.shared }
    private var unlocked: Bool { ProLicenseGate.canOpenAINotch(unlocked: licenseUnlocked || supporter) }
    private var isOn: Bool { unlocked && center.settings.enabled }

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                Text("在刘海里对话")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelPrimary)
                    .lineLimit(1)
                    .fixedSize()
                ProBadge()
                AIMiniSwitch(isOn: isOn)
            }
            .padding(.leading, 10)
            .padding(.trailing, 4)
            .frame(height: 26)
            .background(Capsule().fill(.panelFill))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isPreview)
        .help(unlocked
              ? (isOn ? tr("刘海对话已打开：点一下刘海或按快捷键展开对话。再点关掉刘海入口。")
                      : tr("打开后点一下刘海或按快捷键，就在刘海下面直接对话。"))
              : tr("在刘海下面直接对话是码头 Pro 功能，点一下看看解锁。"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("在刘海里对话，码头 Pro"))
        .accessibilityValue(isOn ? tr("开") : tr("关"))
        .accessibilityAddTraits(.isToggle)
    }

    private func toggle() {
        guard !isPreview else { return }
        guard unlocked else {
            PaywallWindow.shared.show()
            return
        }
        center.updateSettings { $0.enabled.toggle() }
    }
}

/// 小号开关的样子（26 x 16）：开着是主题蓝，关着是轨道灰。只是画，点击交给外面的按钮。
private struct AIMiniSwitch: View {
    var isOn: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule().fill(isOn ? Color(hex: AIGlyph.dotHex) : Color.panelTrack)
            Circle()
                .fill(.white)
                .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
                .padding(2)
        }
        .frame(width: 26, height: 16)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isOn)
        .accessibilityHidden(true)
    }
}

// MARK: - Ask

private struct AIAskView: View {
    /// 颜色面板里选的强调色，没选过是 nil，用原来的颜色（见 `PanelTint`）。
    @Environment(\.panelTint) private var panelTint
    var instance: WidgetInstance
    var context: WidgetContext
    var services: [AIService]

    @State private var targetID: String?
    @State private var choosing = false

    private var state: AIPanelState { AIPanelState.shared }

    private var target: AIService? {
        services.first { $0.id == targetID }
            ?? AIServices.defaultService(in: instance.config, enabled: services)
    }

    private var draft: Binding<String> {
        Binding(get: { state.draft(instance.id) },
                set: { state.setDraft($0, for: instance.id) })
    }

    private var canSubmit: Bool {
        !context.isPreview && target != nil && AIAsk.question(state.draft(instance.id)) != nil
    }

    var body: some View {
        if services.isEmpty {
            empty
        } else {
            VStack(alignment: .leading, spacing: 10) {
                input
                promptBar
                // 服务选择器占剩下的宽度（名字完整显示，太窄才截尾），右边两个按钮按内容定宽。
                HStack(spacing: 8) {
                    picker
                        .frame(maxWidth: .infinity, alignment: .leading)
                    shotButton
                    Button(action: submitFromButton) {
                        Text(buttonTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 14)
                            .frame(height: 28)
                    }
                    // 可用：实心蓝（或卡片主题色）白字；空着时中性灰底 + 次级字色，见 PanelSolidButtonStyle。
                    .buttonStyle(PanelSolidButtonStyle(fill: panelTint.accent(or: Color(hex: PanelButtonLook.solidBlueHex)),
                                                       ink: panelTint.ink(or: .white)))
                    .fixedSize()
                    .disabled(!canSubmit)
                    .help(buttonHelp)
                    .accessibilityLabel(buttonTitle)
                    .accessibilityHint(buttonHelp)
                }
                if let hint = state.hint(instance.id) {
                    Text(hint)
                        .font(.system(size: 13))
                        .foregroundStyle(.panelPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.updatesFrequently)
                } else {
                    Text(target.map { AIServiceOpener.installedApp($0) != nil } == true
                         ? tr("Enter 提交，Shift+Enter 换行。会复制问题并打开 \(target?.title ?? "") App。")
                         : target?.supportsAsk == true
                         ? tr("Enter 提交，Shift+Enter 换行。会在浏览器打开 \(target?.title ?? "")。")
                         : tr("Enter 提交，Shift+Enter 换行。\(target?.title ?? tr("这个服务"))不支持带问题打开，会先复制问题。"))
                        .font(.system(size: 13))
                        .foregroundStyle(.panelTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// 「截图问 AI」：收起面板，框选屏幕上的一块，识别出的文字带进输入框，再打开面板。
    /// 截的图识别完就删，不留副本。
    private var shotButton: some View {
        Button {
            guard !context.isPreview else { return }
            let id = instance.id
            WidgetDetailWindow.shared.close()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                ShotEditor.askAIFromScreen(widget: id)
            }
        } label: {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.panelPrimary)
                .frame(width: 30, height: 28)
                .background(Capsule().fill(.panelFill))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(tr("截图问 AI：框选屏幕上的一块，识别出的文字带进输入框"))
        .accessibilityLabel(tr("截图问 AI"))
    }

    private var input: some View {
        ZStack(alignment: .topLeading) {
            AskTextEditor(text: draft, onSubmit: submit,
                          onCancel: { WidgetDetailWindow.shared.close() })
                .frame(height: 84)
                .accessibilityLabel("要问的问题")
            if state.draft(instance.id).isEmpty {
                Text("想问点什么？")
                    .font(.system(size: 14))
                    .foregroundStyle(.panelTertiary)
                    .padding(.leading, 5)
                    .padding(.top, 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .padding(10)
        .glassPane(cornerRadius: 12)
    }

    // MARK: 剪贴板接力、快捷指令和常用提示词

    /// 和刘海对话同一排按钮（`AIPromptChipBar`）。文字先取输入框，空着时取
    /// 剪贴板，套好的提示词照平时提问交给选中的服务。提示写在下面那行
    /// （`state.hint`），这一排的第二行只显示剪贴板预览。
    private var promptBar: some View {
        let center = AIChatCenter.shared
        return AIPromptChipBar(
            hasInput: true,
            clipboardPreview: context.isPreview ? nil : center.clipboardPreview,
            notice: nil,
            prompts: center.prompts,
            actionHelp: { actionHelp($0.title) },
            clipboardHelp: tr("点一下带进输入框"),
            paste: pasteClipboard,
            runAction: { run(template: $0.template) },
            runPrompt: { run(template: $0.content) },
            managePrompts: managePrompts)
            .disabled(context.isPreview)
            // 面板开着时每秒看一眼剪贴板有没有变（只比较计数，变了才读内容），
            // 和刘海对话共用同一份。
            .task {
                guard !context.isPreview else { return }
                while !Task.isCancelled {
                    center.refreshClipboard()
                    try? await Task.sleep(for: .seconds(1))
                }
            }
    }

    private func actionHelp(_ title: String) -> String {
        let name = target?.title ?? ""
        switch targetMode {
        case .api: return tr("\(title)输入框里的文字（空着时用剪贴板），在刘海对话里直接问 \(name)")
        case .web: return tr("\(title)输入框里的文字（空着时用剪贴板）：复制套好的提示词，在刘海对话里打开 \(name)")
        case .jump: return tr("\(title)输入框里的文字（空着时用剪贴板），再打开 \(name)")
        }
    }

    private func pasteClipboard() {
        guard !context.isPreview else { return }
        let center = AIChatCenter.shared
        center.refreshClipboard()
        let clip = center.clipboardText
        if clip != nil {
            state.setDraft(AIClipboard.insert(clip, into: state.draft(instance.id)), for: instance.id)
        }
        state.setHint(AIPromptStrip.pasteHint(clipboard: clip), for: instance.id)
    }

    private func run(template: String) {
        guard !context.isPreview else { return }
        let center = AIChatCenter.shared
        center.refreshClipboard()
        switch AIPromptStrip.outcome(template: template, draft: state.draft(instance.id),
                                     clipboard: center.clipboardText) {
        case .needsText:
            state.setHint(AIPromptStrip.needsTextHint, for: instance.id)
        case .ask(let prompt):
            deliver(prompt)
        }
    }

    private func managePrompts() {
        guard !context.isPreview, let app = AIChatCenter.shared.app else { return }
        WidgetDetailWindow.shared.close()
        SettingsWindow.shared.show(app: app, tab: "AI")
    }

    /// 选发给哪个服务。不用 Menu：macOS 的 Menu 标签只取第一段文字，字牌里的
    /// 「豆」被当成整个标题，后面的服务名丢了（真机截图）。改成按钮 + 弹出列表，
    /// 标签照原样画，服务名完整显示，太窄时才截尾。
    private var picker: some View {
        Button {
            choosing.toggle()
        } label: {
            HStack(spacing: 6) {
                if let target {
                    AIGlyph(initial: target.initial, size: 20, style: .panel)
                    Text(tr("发给 \(target.title)"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.panelPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.panelSecondary)
            }
            .frame(height: 28)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(context.isPreview)
        .popover(isPresented: $choosing, arrowEdge: .top) { serviceList }
        .help(tr("选择提问的服务"))
        .accessibilityLabel(tr("选择提问的服务，当前是 \(target?.title ?? tr("无"))"))
    }

    private var serviceList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(services) { service in
                Button {
                    targetID = service.id
                    choosing = false
                } label: {
                    HStack(spacing: 8) {
                        AIGlyph(initial: service.initial, size: 20, style: .panel)
                        Text(service.title)
                            .font(.system(size: 13))
                            .foregroundStyle(.panelPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 12)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.panelPrimary)
                            .opacity(service.id == target?.id ? 1 : 0)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(service.title)
                .accessibilityAddTraits(service.id == target?.id ? .isSelected : [])
            }
        }
        .padding(6)
        .frame(minWidth: 180)
    }

    private var empty: some View {
        VStack(spacing: 12) {
            PanelNote(symbol: "plus.square.dashed", text: tr("卡片上还没有 AI 字牌。"))
            Button("添加字牌") { state.mode = .manage }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("添加 AI 字牌")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 这个服务在刘海对话里的打开方式。不是 App 方式时，问题交给刘海对话。
    private var targetMode: AIOpenMode {
        target.map { AIChatCenter.shared.mode(for: $0) } ?? .jump
    }

    /// 主按钮的字要短（「打开 豆包」「去网页问」「发送」），会做什么写在下面的提示句里。
    private var buttonTitle: String {
        AIAsk.buttonTitle(mode: targetMode, service: target,
                          appInstalled: target.map { AIServiceOpener.installedApp($0) != nil } ?? false)
    }

    /// 悬停说明和读屏提示：把按钮做什么说完整。
    private var buttonHelp: String {
        let name = target?.title ?? ""
        switch targetMode {
        case .api: return tr("在刘海对话里用 API 直接问 \(name)")
        case .web: return tr("复制问题，在刘海对话里打开 \(name) 的网页")
        case .jump:
            if let target, AIServiceOpener.installedApp(target) != nil {
                return tr("复制问题，再打开 \(name) App")
            }
            return target?.supportsAsk == true
                ? tr("在浏览器打开 \(name)，问题会带过去")
                : tr("把问题复制到剪贴板，再打开 \(name)")
        }
    }

    /// 点按钮不会让输入法先确认选字，还有没确认的字时不交出去。
    private func submitFromButton() {
        guard AIAsk.canSubmit(state.draft(instance.id), hasMarkedText: AskTextView.keyWindowIsComposing) else { return }
        submit()
    }

    private func submit() { deliver(nil) }

    /// 交出去。`text` 是快捷指令或常用提示词套好的提示词，nil 时交输入框里的问题。
    private func deliver(_ text: String?) {
        guard !context.isPreview, let service = target else { return }
        let mode = targetMode
        let asked = text ?? state.draft(instance.id)
        // 网页和 API 在刘海对话里问，刘海对话是码头 Pro：没解锁时弹付费墙，问题留在框里。
        if mode != .jump, !ProLicenseGate.canOpenAINotch(unlocked: ProAccess.isUnlocked),
           AIAsk.question(asked) != nil {
            PaywallWindow.shared.show()
            return
        }
        if mode != .jump, let question = AIAsk.question(asked) {
            let center = AIChatCenter.shared
            center.select(service.id)
            center.draft = question
            state.setDraft("", for: instance.id)
            WidgetDetailWindow.shared.close()
            AINotchController.shared.open()
            if mode == .api {
                center.send()
            } else {
                // 网页里没法替用户填字，复制好让用户粘贴。
                AIServiceOpener.copy(question)
            }
            return
        }
        // 「App」方式：装了 ChatGPT、Perplexity 这类 App 时复制问题再打开 App，没装才走浏览器。
        let plan = AIAsk.plan(asked, service: service, appInstalled: AIServiceOpener.installedApp(service) != nil)
        switch plan {
        case .blocked:
            state.setHint(AIAsk.hint(after: plan, service: service), for: instance.id)
            return
        case .openWithQuestion(let url):
            guard AIServiceOpener.open(url) else {
                state.setHint(tr("没能打开 \(service.title)。"), for: instance.id)
                return
            }
        case .copyThenOpen(let question):
            AIServiceOpener.copy(question)
            guard AIServiceOpener.open(service) else {
                state.setHint(tr("已复制，但没能打开 \(service.title)。"), for: instance.id)
                return
            }
        }
        // 交出去了才清空草稿；提示留在面板上，点到别处面板自己收起。
        state.setDraft("", for: instance.id)
        state.setHint(AIAsk.hint(after: plan, service: service), for: instance.id)
    }
}

// MARK: - Manage

private struct AIManageView: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @State private var formOpen = false

    private var state: AIPanelState { AIPanelState.shared }
    private var config: WidgetConfig { instance.config }

    var body: some View {
        let enabled = AIServices.enabled(in: config)
        let enabledIDs = Set(enabled.map(\.id))
        let defaultID = AIServices.defaultService(in: config, enabled: enabled)?.id
        let custom = AIServices.custom(in: config)
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(tr("勾选的显示在卡片上，最多 \(AIServices.maxCount) 个。点“设为默认”改蓝点。"))
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !enabled.isEmpty {
                    section(tr("卡片上的顺序")) {
                        ForEach(Array(enabled.enumerated()), id: \.element.id) { index, service in
                            orderRow(service, index: index, count: enabled.count,
                                     isDefault: service.id == defaultID)
                        }
                    }
                }
                ForEach(AIService.Region.allCases, id: \.self) { region in
                    section(region.title) {
                        ForEach(AIServices.builtIn.filter { $0.region == region }) { service in
                            toggleRow(service, on: enabledIDs.contains(service.id), full: enabled.count >= AIServices.maxCount)
                        }
                    }
                }
                if !custom.isEmpty {
                    section(tr("自定义")) {
                        ForEach(custom) { service in
                            toggleRow(service, on: enabledIDs.contains(service.id),
                                      full: enabled.count >= AIServices.maxCount, removable: true)
                        }
                    }
                }
                if formOpen {
                    AICustomForm(instance: instance, context: context) { formOpen = false }
                } else {
                    Button {
                        formOpen = true
                    } label: {
                        Label("自定义…", systemImage: "plus")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.panelPrimary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("添加自定义服务")
                }
            }
            .padding(.bottom, 6)
        }
        .scrollIndicators(.never)
        .disabled(context.isPreview)
        .onAppear(perform: openFormIfAsked)
        .onChange(of: state.wantsCustomForm) { _, _ in openFormIfAsked() }
    }

    private func openFormIfAsked() {
        guard state.wantsCustomForm else { return }
        state.wantsCustomForm = false
        formOpen = true
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelTertiary)
                .padding(.bottom, 2)
                .accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPane(cornerRadius: 12)
    }

    private func toggleRow(_ service: AIService, on: Bool, full: Bool, removable: Bool = false) -> some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(get: { on }, set: { _ in change { AIServices.toggle(service.id, in: &$0) } })) {
                HStack(spacing: 8) {
                    AIGlyph(initial: service.initial, size: 20, style: .panel)
                    Text(service.title)
                        .font(.system(size: 13))
                        .foregroundStyle(.panelPrimary)
                }
            }
            .toggleStyle(.checkbox)
            .disabled(!on && full)
            .accessibilityLabel(on ? tr("\(service.title)，显示在卡片上") : tr("\(service.title)，已隐藏"))
            Spacer(minLength: 0)
            if service.supportsAsk {
                Text("可带问题")
                    .font(.system(size: 13))
                    .foregroundStyle(.panelTertiary)
            }
            if removable {
                Button("删除") { change { AIServices.removeCustom(service.id, in: &$0) } }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: PaletteColor.red.hex).panelReadable)
                    .accessibilityLabel(tr("删除 \(service.title)"))
            }
        }
        .frame(height: 24)
    }

    private func orderRow(_ service: AIService, index: Int, count: Int, isDefault: Bool) -> some View {
        HStack(spacing: 8) {
            AIGlyph(initial: service.initial, size: 20, isDefault: isDefault, style: .panel)
            Text(service.title)
                .font(.system(size: 13))
                .foregroundStyle(.panelPrimary)
            if isDefault {
                Text("默认")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: AIGlyph.dotHex).panelReadable)
            }
            Spacer(minLength: 0)
            if !isDefault {
                smallButton(tr("设为默认"), label: tr("把 \(service.title) 设为默认")) {
                    change { AIServices.setDefault(service.id, in: &$0) }
                }
            }
            iconButton("chevron.left", label: tr("\(service.title) 左移"), disabled: index == 0) {
                change { AIServices.move(service.id, by: -1, in: &$0) }
            }
            iconButton("chevron.right", label: tr("\(service.title) 右移"), disabled: index == count - 1) {
                change { AIServices.move(service.id, by: 1, in: &$0) }
            }
            iconButton("eye.slash", label: tr("隐藏 \(service.title)"), disabled: false) {
                change { AIServices.hide(service.id, in: &$0) }
            }
        }
        .frame(height: 26)
    }

    private func smallButton(_ title: String, label: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(.panelPrimary)
            .accessibilityLabel(label)
    }

    private func iconButton(_ symbol: String, label: String, disabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.panelPrimary.opacity(disabled ? 0.25 : 0.8))
                .frame(width: 20, height: 20)
                .background(Circle().fill(.panelFill))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(label)
    }

    private func change(_ edit: (inout WidgetConfig) -> Void) {
        guard !context.isPreview else { return }
        WidgetWriter.write(instance, edit)
    }
}

// MARK: - Custom form

/// “自定义…”：名字，加一个网址或者从“应用程序”里选一个 App。
///
/// 放在面板里而不是弹出的小窗里：面板外的任何一次点击都会把面板收起，
/// 弹出的小窗在面板外面。填了一半的内容存在 `AIPanelState` 里，选 App 时
/// 面板被收起也不会丢，选完自动回来。
private struct AICustomForm: View {
    var instance: WidgetInstance
    var context: WidgetContext
    var close: () -> Void

    @State private var error: String?

    private var state: AIPanelState { AIPanelState.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("自定义服务")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelTertiary)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 8) {
                field(tr("名字"), text: Binding(get: { state.form.name }, set: { state.form.name = $0 }),
                      prompt: tr("例如 秘塔"), focus: true)
                    .frame(width: 96)
                field(tr("打开地址"), text: Binding(get: { state.form.address }, set: { state.form.address = $0 }),
                      prompt: "https://metaso.cn")
            }
            HStack(spacing: 8) {
                Button("选 App…", action: chooseApp)
                    .accessibilityLabel("从应用程序文件夹选一个 App")
                if let path = state.form.appPath {
                    Text((path as NSString).lastPathComponent)
                        .font(.system(size: 13))
                        .foregroundStyle(.panelSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button {
                        state.form.appPath = nil
                        state.form.appBundleID = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.panelTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("不用这个 App")
                }
                Spacer(minLength: 0)
                Button("取消", action: cancel)
                Button("添加") {
                    // 点按钮不会让输入法先确认选字。
                    guard !AskTextView.keyWindowIsComposing else { return }
                    add()
                }
                .keyboardShortcut(.defaultAction)
            }
            if let error {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: PaletteColor.orange.hex).panelReadable)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("网址和 App 填一个就行；两个都填时装了 App 就开 App。")
                    .font(.system(size: 13))
                    .foregroundStyle(.panelTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .glassPane(cornerRadius: 12)
    }

    private func field(_ title: String, text: Binding<String>, prompt: String, focus: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(.panelTertiary)
            AIFormField(text: text, placeholder: prompt, label: title, focusOnAppear: focus,
                        onSubmit: add, onCancel: cancel)
                .frame(height: 22)
        }
    }

    /// 取消编辑：清掉填了一半的内容，收起表单，面板留着。Esc 也走这里；
    /// 表单收起后再按 Esc 就是关面板。
    private func cancel() {
        state.form = AIPanelState.Form()
        error = nil
        close()
    }

    private func add() {
        guard !context.isPreview else { return }
        let form = state.form
        let result = AIServices.custom(title: form.name, address: form.address,
                                       appPath: form.appPath, appBundleID: form.appBundleID,
                                       id: String(UUID().uuidString.prefix(8)).lowercased(),
                                       existing: AIServices.all(in: instance.config))
        switch result {
        case .failure(let failure):
            error = failure.message
        case .success(let service):
            var config = instance.config
            if let failure = AIServices.addCustom(service, in: &config) {
                error = failure.message
                return
            }
            var updated = instance
            updated.config = config
            WidgetWriter.update(updated)
            state.form = AIPanelState.Form()
            error = nil
            close()
        }
    }

    /// 选 App：系统的打开面板，从“应用程序”开始，只能选 App。码头是辅助
    /// 应用，不临时升到前台的话打开面板会出现在别的窗口后面（和选文件夹
    /// 一样的做法）。提问面板在码头的层级上，比打开面板高，开着会把它挡住，
    /// 所以先收起，选完（或取消）再请扩展栏打开回来；填了一半的在 state 里。
    ///
    /// 多显示器时打开面板可能出现在另一块屏幕上，选完指针也常停在那里；
    /// 回来时带上收起前面板的位置，由原来那块屏幕上的扩展栏打开，面板从
    /// 原来那张卡片长出来，还是管理页和展开的自定义表单。
    private func chooseApp() {
        guard !context.isPreview else { return }
        let origin = WidgetDetailWindow.shared.openCenter
        state.holdingForAppChooser = true
        WidgetDetailWindow.shared.close()
        defer { state.holdingForAppChooser = false }
        let policy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        defer { NSApp.setActivationPolicy(policy) }

        let panel = NSOpenPanel()
        panel.message = tr("选一个 AI App")
        panel.prompt = tr("选择")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let id = instance.id
        guard panel.runModal() == .OK, let url = panel.url else {
            state.requestPanel(id, mode: .manage, customForm: true, origin: origin)
            return
        }
        state.form.appPath = url.path
        state.form.appBundleID = Bundle(url: url)?.bundleIdentifier
        if state.form.name.trimmingCharacters(in: .whitespaces).isEmpty {
            state.form.name = FileManager.default.displayName(atPath: url.path)
                .replacingOccurrences(of: ".app", with: "")
        }
        state.requestPanel(id, mode: .manage, customForm: true, origin: origin)
    }
}

// MARK: - Input

/// 多行输入框。NSTextView 而不是 TextEditor：要分清 Enter 和 Shift+Enter，
/// 还要知道输入法是不是正在选字（`hasMarkedText`），这两样 TextEditor 都给不了。
struct AskTextEditor: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        let view = AskTextView(frame: .zero)
        view.delegate = context.coordinator
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.drawsBackground = false
        view.font = .systemFont(ofSize: 14)
        view.textColor = .labelColor
        view.insertionPointColor = .labelColor
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        view.textContainerInset = .zero
        view.setAccessibilityLabel(tr("要问的问题"))
        view.setAccessibilityHelp(tr("Enter 提交，Shift 加 Enter 换行"))
        view.string = text
        let coordinator = context.coordinator
        view.onSubmit = { coordinator.parent.onSubmit() }
        view.onCancel = { coordinator.parent.onCancel() }
        scroll.documentView = view
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        // 字色是 labelColor，跟着 NSView 自己的外观解析；刘海对话保持纯黑时
        // 环境是深色、窗口可能是浅色，按环境设一下，免得黑字落在黑底上。
        let appearance = NSAppearance(named: context.environment.colorScheme == .dark ? .darkAqua : .aqua)
        if scroll.appearance?.name != appearance?.name { scroll.appearance = appearance }
        guard let view = scroll.documentView as? AskTextView else { return }
        // 输入法正在选字时不要改它的字，会把候选打断。
        if view.string != text, !view.hasMarkedText() {
            view.string = text
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AskTextEditor

        init(_ parent: AskTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            parent.text = view.string
        }
    }
}

/// 回车的去向交给 `AIAsk.returnAction`：选字中放行，Shift/Option 换行，否则提交。
final class AskTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?
    private var keyObserver: NSObjectProtocol?

    /// 拿着键盘的窗口里，正在输入的框（这个输入框，或者单行输入框的字段
    /// 编辑器）还有输入法没确认的字。点按钮不会让输入法先确认选字，所以
    /// 提交按钮自己看一眼，有就不提交。
    static var keyWindowIsComposing: Bool {
        NSApp.windows.contains { window in
            window.isKeyWindow && (window.firstResponder as? NSTextView)?.hasMarkedText() == true
        }
    }

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        guard isReturn else { return super.keyDown(with: event) }
        let flags = event.modifierFlags
        switch AIAsk.returnAction(shift: flags.contains(.shift), option: flags.contains(.option),
                                  hasMarkedText: hasMarkedText()) {
        case .passThrough: super.keyDown(with: event)
        case .newline: insertNewlineIgnoringFieldEditor(nil)
        case .submit: onSubmit?()
        }
    }

    /// NSTextView 默认把 Esc 当作“补全”。这里让它关面板；输入法选字时
    /// Esc 由输入法先处理，到不了这里。
    override func cancelOperation(_ sender: Any?) {
        if hasMarkedText() { return super.cancelOperation(sender) }
        onCancel?()
    }

    /// 面板每次成为主窗口（打开）时把光标放进来，前提是没有别的控件正在输入。
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let keyObserver { NotificationCenter.default.removeObserver(keyObserver) }
        keyObserver = nil
        guard let window else { return }
        keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.focusIfIdle() }
        }
        focusIfIdle()
    }

    private func focusIfIdle() {
        guard let window, window.firstResponder === window || window.firstResponder == nil else { return }
        window.makeFirstResponder(self)
    }
}

/// 自定义表单里的单行输入框。NSTextField 而不是 SwiftUI 的 TextField：
/// 字段编辑器把 Esc 当作“补全”吃掉，到不了面板，TextField 上挂的
/// `onExitCommand` 也收不到。这里在 `doCommandBy` 里把 Esc 交给 `onCancel`，
/// 回车交给 `onSubmit`；输入法选字时 Esc 和回车都由输入法先处理，到不了这里。
struct AIFormField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var label: String
    var focusOnAppear = false
    var onSubmit: () -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.placeholderString = placeholder
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.font = .systemFont(ofSize: 13)
        field.lineBreakMode = .byTruncatingTail
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = context.coordinator
        field.setAccessibilityLabel(label)
        if focusOnAppear {
            // 下一轮再放光标：这时字段才进了窗口。别的控件正在输入时不抢。
            Task { @MainActor [weak field] in
                guard let field, let window = field.window else { return }
                if window.firstResponder === window || window.firstResponder == nil {
                    window.makeFirstResponder(field)
                }
            }
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        // 输入法正在选字时不要改它的字，会把候选打断。
        let composing = (field.currentEditor() as? NSTextView)?.hasMarkedText() == true
        if field.stringValue != text, !composing {
            field.stringValue = text
        }
        field.placeholderString = placeholder
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: AIFormField

        init(_ parent: AIFormField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if textView.hasMarkedText() { return false }
            switch selector {
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            case #selector(NSResponder.insertNewline(_:)):
                parent.text = textView.string
                parent.onSubmit()
                return true
            default:
                return false
            }
        }
    }
}
