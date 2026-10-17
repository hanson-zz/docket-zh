import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// AI 助手的面板：迷你提问，或者管理字牌。
///
/// 提问：多行输入框，Enter 提交，Shift+Enter 换行，中文输入法选字时的
/// Enter 只确认选字。下面选发给哪个服务（默认是蓝点那个）。服务正式支持
/// 把问题带进网址的，主按钮是“打开并提问”；不支持的是“复制问题并打开”，
/// 复制到剪贴板再打开服务，提示用户自己粘贴。这里不调用任何接口，也就不
/// 显示“已发送”“已回答”之类的状态，回答在那个服务里看。
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
            Text(state.mode == .manage ? tr("管理字牌") : tr("问问 AI"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            Spacer(minLength: 0)
            Button(state.mode == .manage ? tr("完成") : tr("管理字牌")) {
                state.mode = state.mode == .manage ? .ask : .manage
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(.white.opacity(0.12)))
            .accessibilityLabel(state.mode == .manage ? tr("完成管理，回到提问") : tr("管理字牌"))
        }
    }
}

// MARK: - Ask

private struct AIAskView: View {
    var instance: WidgetInstance
    var context: WidgetContext
    var services: [AIService]

    @State private var targetID: String?

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
                HStack(spacing: 8) {
                    picker
                    Spacer(minLength: 0)
                    Button(action: submitFromButton) {
                        Text(buttonTitle)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                            .background(Capsule().fill(Color(hex: AIGlyph.dotHex).opacity(canSubmit ? 1 : 0.35)))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit)
                    .help(targetMode == .api ? tr("在刘海对话里用 API 直接问 \(target?.title ?? "")")
                          : targetMode == .web ? tr("复制问题，在刘海对话里打开 \(target?.title ?? "") 的网页")
                          : target?.supportsAsk == true
                          ? tr("在浏览器打开 \(target?.title ?? "")，问题会带过去")
                          : tr("把问题复制到剪贴板，再打开 \(target?.title ?? "")"))
                    .accessibilityLabel(buttonTitle)
                }
                if let hint = state.hint(instance.id) {
                    Text(hint)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.updatesFrequently)
                } else {
                    Text(target?.supportsAsk == true
                         ? tr("Enter 提交，Shift+Enter 换行。会在浏览器打开 \(target?.title ?? "")。")
                         : tr("Enter 提交，Shift+Enter 换行。\(target?.title ?? tr("这个服务"))不支持带问题打开，会先复制问题。"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var input: some View {
        ZStack(alignment: .topLeading) {
            AskTextEditor(text: draft, onSubmit: submit,
                          onCancel: { WidgetDetailWindow.shared.close() })
                .frame(height: 112)
                .accessibilityLabel("要问的问题")
            if state.draft(instance.id).isEmpty {
                Text("想问点什么？")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.leading, 5)
                    .padding(.top, 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .padding(10)
        .glassPane(cornerRadius: 12)
    }

    private var picker: some View {
        Menu {
            ForEach(services) { service in
                Button {
                    targetID = service.id
                } label: {
                    if service.id == target?.id {
                        Label(service.title, systemImage: "checkmark")
                    } else {
                        Text(service.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if let target {
                    AIGlyph(initial: target.initial, size: 20, style: .panel)
                    Text(tr("发给 \(target.title)"))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(tr("选择提问的服务，当前是 \(target?.title ?? tr("无"))"))
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

    /// 这个服务在刘海对话里的打开方式。不是跳转时，问题交给刘海对话。
    private var targetMode: AIOpenMode {
        target.map { AIChatCenter.shared.mode(for: $0) } ?? .jump
    }

    private var buttonTitle: String {
        switch targetMode {
        case .api: tr("在刘海里问")
        case .web: tr("复制并在刘海打开")
        case .jump: AIAsk.buttonTitle(for: target)
        }
    }

    /// 点按钮不会让输入法先确认选字，还有没确认的字时不交出去。
    private func submitFromButton() {
        guard AIAsk.canSubmit(state.draft(instance.id), hasMarkedText: AskTextView.keyWindowIsComposing) else { return }
        submit()
    }

    private func submit() {
        guard !context.isPreview, let service = target else { return }
        let mode = targetMode
        if mode != .jump, let question = AIAsk.question(state.draft(instance.id)) {
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
        let plan = AIAsk.plan(state.draft(instance.id), service: service)
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
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.6))
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
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("添加自定义服务")
                }
            }
            .padding(.bottom, 6)
        }
        .scrollIndicators(.automatic)
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
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
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
                        .font(.system(size: 12.5))
                        .foregroundStyle(.white)
                }
            }
            .toggleStyle(.checkbox)
            .disabled(!on && full)
            .accessibilityLabel(on ? tr("\(service.title)，显示在卡片上") : tr("\(service.title)，已隐藏"))
            Spacer(minLength: 0)
            if service.supportsAsk {
                Text("可带问题")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.5))
            }
            if removable {
                Button("删除") { change { AIServices.removeCustom(service.id, in: &$0) } }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color(hex: PaletteColor.red.hex))
                    .accessibilityLabel(tr("删除 \(service.title)"))
            }
        }
        .frame(height: 24)
    }

    private func orderRow(_ service: AIService, index: Int, count: Int, isDefault: Bool) -> some View {
        HStack(spacing: 8) {
            AIGlyph(initial: service.initial, size: 20, isDefault: isDefault, style: .panel)
            Text(service.title)
                .font(.system(size: 12.5))
                .foregroundStyle(.white)
            if isDefault {
                Text("默认")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color(hex: AIGlyph.dotHex))
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
            .font(.system(size: 11.5))
            .foregroundStyle(.white.opacity(0.8))
            .accessibilityLabel(label)
    }

    private func iconButton(_ symbol: String, label: String, disabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(disabled ? 0.25 : 0.8))
                .frame(width: 20, height: 20)
                .background(Circle().fill(.white.opacity(0.08)))
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
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
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
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button {
                        state.form.appPath = nil
                        state.form.appBundleID = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.5))
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
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color(hex: PaletteColor.orange.hex))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("网址和 App 填一个就行；两个都填时装了 App 就开 App。")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .glassPane(cornerRadius: 12)
    }

    private func field(_ title: String, text: Binding<String>, prompt: String, focus: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.55))
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
        view.textColor = .white
        view.insertionPointColor = .white
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
        field.font = .systemFont(ofSize: 12)
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
