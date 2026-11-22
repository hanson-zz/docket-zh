import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// AI 助手的面板：迷你提问，或者「助手设置」二级页。
///
/// 提问页从上到下（同竖版效果图）：顶栏是小 App 图标和「码头 · AI 助手」，右边齿轮里是
/// 「刘海对话 Pro」开关和设置；空闲时是欢迎区（左下大字「你好」和一句「今天想让 AI 帮你做
/// 什么？」，右上笔记本场景小熊猫）和 2×2 快捷操作玻璃块（可在设置页里换，「更多」里是其余
/// 快捷操作和常用提示词）；下面是伸缩输入框（Enter 提交，Shift+Enter 换行，中文输入法选字时的
/// Enter 只确认选字，右下角字数「24 / 2000」）、整行宽的主按钮「开始提问」，最底下「使用模型：」
/// 下拉（服务、打开方式、回答位置）。API 方式这个服务正在回答时，欢迎区和快捷操作换成
/// 「AI 正在思考…」卡片；答完换成「已完成」结果卡片（复制、再试一次、继续提问），点「继续
/// 提问」或关掉后回到欢迎区。
///
/// 当前服务和刘海对话共用（`AIChatCenter.current`）。API 方式的问题挂在 `AIChatCenter` 上，
/// 面板收起，按「回答显示位置」在刘海下方弹快捷结果卡片（刘海被占着时用备用浮窗），或者打开
/// 刘海里的完整对话；网页方式复制问题，在刘海对话的网页里粘贴发送。App 方式只负责跳转，
/// 不显示「已发送」「已回答」之类的状态，回答在那个服务里看。
///
/// 字牌、服务的打开方式和 API 密钥这些不常改的，收在设置页里。提问页不自设高度，交给通用
/// 面板容器（`DetailPanelFit`），内容多时在面板里滚动；设置页里是滚动列表，固定 `bodyHeight` 高。
struct AIAssistantDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var state: AIPanelState { AIPanelState.shared }
    private var config: WidgetConfig { instance.config }
    private var services: [AIService] { AIServices.enabled(in: config) }

    static let bodyHeight: CGFloat = 318

    var body: some View {
        DetailCard {
            MeshBackdrop(color: Color(hex: ShelfColor.redPanda.hex))
        } content: {
            if state.mode == .manage {
                VStack(alignment: .leading, spacing: 12) {
                    settingsHeader
                    AIManageView(instance: instance, context: context)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .frame(height: Self.bodyHeight, alignment: .top)
            } else {
                AIAskView(instance: instance, context: context, services: services)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private var settingsHeader: some View {
        HStack(spacing: 8) {
            AIPandaAvatar(size: 24)
            Text(tr("助手设置"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.panelPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button(tr("完成")) { state.mode = .ask }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.panelPrimary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Capsule().fill(.panelFill))
                .accessibilityLabel(tr("完成设置，回到提问"))
        }
    }
}

/// 顶栏里的「刘海对话 Pro」开关：已解锁时切换刘海入口（设置 ▸ AI 里「在刘海
/// 显示 AI 助手」同一个键 `aiNotch.enabled`）；没解锁时画一把小锁，点了弹付费墙，
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
            HStack(spacing: 5) {
                ProBadge()
                Text("刘海对话")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelPrimary)
                    .lineLimit(1)
                    .fixedSize()
                if unlocked {
                    AIMiniSwitch(isOn: isOn)
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.panelSecondary)
                        .frame(width: 16, height: 16)
                        .accessibilityHidden(true)
                }
            }
            .padding(.leading, 4)
            .padding(.trailing, unlocked ? 4 : 8)
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
        .accessibilityValue(unlocked ? (isOn ? tr("开") : tr("关")) : tr("未解锁"))
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var instance: WidgetInstance
    var context: WidgetContext
    var services: [AIService]

    /// 这张卡片上选的服务。刘海对话的服务列表里有它时同时切过去（两边共用当前
    /// 服务）；没有时（另一张 AI 卡片）只在这里记着。
    @State private var targetID: String?
    @State private var showingMore = false
    /// 服务胶囊的弹出列表开着没有。
    @State private var choosingService = false
    /// 顶栏小熊猫的短暂表态：答完庆祝一下、出错举爪提醒一下，几秒后回常态。
    @State private var pandaPulse: PandaPulse?
    /// 「继续提问」把光标放回输入框（`AskTextEditor.focusToken`）。
    @State private var focusToken = 0
    /// 刚点了「复制」的那条回答：按钮短暂显示「已复制」。
    @State private var copiedID: UUID?

    private var state: AIPanelState { AIPanelState.shared }
    private var center: AIChatCenter { AIChatCenter.shared }

    private var target: AIService? {
        if let targetID, let picked = services.first(where: { $0.id == targetID }) { return picked }
        let shared = center.current?.id
        return services.first { $0.id == shared }
            ?? AIServices.defaultService(in: instance.config, enabled: services)
    }

    private var draft: Binding<String> {
        Binding(get: { state.draft(instance.id) },
                set: { state.setDraft($0, for: instance.id) })
    }

    private var canSubmit: Bool {
        let draft = state.draft(instance.id)
        return !context.isPreview && target != nil && AIAsk.question(draft) != nil && AIAskLimit.withinLimit(draft)
    }

    private var chips: [AIDockChip] { AIDockChips.resolved(center.settings.panelChips) }

    var body: some View {
        let phase = context.isPreview ? nil : center.pandaPhase(target)
        let result = shownResult(phase)
        VStack(alignment: .leading, spacing: 12) {
            header
            if services.isEmpty {
                empty
            } else {
                if let result {
                    stateSection(result)
                } else {
                    welcome(phase)
                    quickActions
                }
                input
                statusLine
                primaryButton
                modeLine
                modelRow
            }
        }
        // 状态提示出现、淡出，生成中和结果卡片出现时一起过渡（面板高度也跟着变）。
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: state.hintToken(instance.id))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: result?.key)
        .onChange(of: phase) { old, new in
            if let pulse = PandaStateResolver.aiPulse(from: old, to: new, at: .now) { pandaPulse = pulse }
        }
        .task(id: copiedID) {
            guard copiedID != nil else { return }
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            copiedID = nil
        }
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

    // MARK: 生成中、结果

    /// 面板上要画的状态卡片：API 方式这个服务最后一条回答。生成中一直显示；答完或失败的
    /// 显示到用户点「继续提问」或关掉（`AIPanelState.dismissResult`），下次打开也不再出现。
    /// 网页、App 方式码头拿不到回答，不显示。
    private struct ShownResult {
        var serviceID: String
        var message: AIChatMessage
        var phase: AIQuickResultPhase
        /// 过渡动画用：换了一条回答或换了阶段才算变。
        var key: String { "\(message.id.uuidString)-\(phase.title)" }
    }

    private func shownResult(_ phase: AIQuickResultPhase?) -> ShownResult? {
        guard let phase, let service = target,
              let last = center.messages(service.id).last, last.role == .assistant else { return nil }
        if phase.isFinished, state.isResultDismissed(last.id, for: instance.id) { return nil }
        return ShownResult(serviceID: service.id, message: last, phase: phase)
    }

    /// 生成中：笔记本场景小熊猫（抬头等回答）加「AI 正在思考…」玻璃卡；答完：小熊猫短暂庆祝，
    /// 「已完成」结果卡片，下面复制、再试一次、继续提问。
    private func stateSection(_ result: ShownResult) -> some View {
        VStack(spacing: -10) {
            PandaStateView(pose: PandaStateResolver.aiPose(result.phase, typing: !state.draft(instance.id).isEmpty),
                           pulse: pandaPulse, size: 84,
                           fallbackSymbol: "bubble.left.and.text.bubble.right.fill")
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
                .zIndex(0)
            Group {
                if result.phase.isFinished {
                    resultCard(result)
                } else {
                    thinkingCard(result)
                }
            }
            .zIndex(1)
        }
        .transition(.opacity)
    }

    private func thinkingCard(_ result: ShownResult) -> some View {
        let answering = result.phase == .answering
        let preview = String(result.message.text.suffix(90))
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return VStack(spacing: 8) {
            Group {
                if reduceMotion {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.panelSecondary)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(height: 22)
            .accessibilityHidden(true)
            Text(answering ? tr("AI 正在回答…") : tr("AI 正在思考…"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.panelPrimary)
                .lineLimit(1)
            Text(answering && !preview.isEmpty ? preview : tr("正在为你整理内容，请稍候…"))
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if center.current?.id == result.serviceID {
                Button { center.stop() } label: {
                    Text(tr("停止生成"))
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                }
                .buttonStyle(PanelChipButtonStyle())
                .disabled(context.isPreview)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) {
            // 一道很淡的静态色带，不做波浪、不发光。
            LinearGradient(colors: [Color(hex: PaletteColor.indigo.hex), Color(hex: PaletteColor.purple.hex),
                                    Color(hex: ShelfColor.redPanda.hex)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 3)
                .clipShape(Capsule())
                .opacity(0.35)
                .padding(.horizontal, 20)
                .padding(.bottom, 6)
                .accessibilityHidden(true)
        }
        .readableGlass(in: shape)
    }

    private func resultCard(_ result: ShownResult) -> some View {
        let failed: String? = { if case .failed(let reason) = result.phase { return reason } else { return nil } }()
        let text = result.message.text
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        let hasQuestion = center.messages(result.serviceID).contains { $0.role == .user }
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: failed == nil ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(hex: failed == nil ? PaletteColor.green.hex : PaletteColor.orange.hex).panelReadable)
                        .accessibilityHidden(true)
                    Text(failed == nil ? tr("已完成") : tr("失败"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: failed == nil ? PaletteColor.green.hex : PaletteColor.orange.hex).panelReadable)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    smallIconButton("arrow.up.left.and.arrow.down.right", label: tr("在完整对话中打开")) {
                        WidgetDetailWindow.shared.close()
                        AINotchController.shared.open()
                    }
                    smallIconButton("xmark", label: tr("关闭")) { dismiss(result) }
                }
                Text(failed ?? text)
                    .font(.system(size: 14))
                    .foregroundStyle(.panelPrimary)
                    .lineLimit(8)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(12)
            .readableGlass(in: shape)
            HStack(spacing: 8) {
                if failed == nil, !text.isEmpty {
                    resultButton(copiedID == result.message.id ? tr("已复制") : tr("复制", context: "copy"),
                                 symbol: copiedID == result.message.id ? "checkmark" : "doc.on.doc") {
                        center.copy(text)
                        copiedID = result.message.id
                    }
                }
                if hasQuestion {
                    resultButton(tr("再试一次"), symbol: "arrow.clockwise") {
                        center.retry(result.serviceID)
                    }
                }
                Button {
                    dismiss(result)
                    focusToken += 1
                } label: {
                    Label(tr("继续提问"), systemImage: "bubble.left")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                }
                .buttonStyle(PanelSolidButtonStyle(fill: panelTint.accent(or: Color(hex: ShelfColor.redPanda.hex))))
                .help(tr("接着这次对话再问一句"))
            }
            .disabled(context.isPreview)
        }
        .transition(.opacity)
    }

    private func resultButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
        }
        .buttonStyle(PanelChipButtonStyle())
        .accessibilityLabel(title)
    }

    private func smallIconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.panelSecondary)
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(context.isPreview)
        .help(label)
        .accessibilityLabel(label)
    }

    private func dismiss(_ result: ShownResult) {
        state.dismissResult(result.message.id, for: instance.id)
    }

    // MARK: 欢迎区

    /// 空闲时：左下大字「你好」和一句「今天想让 AI 帮你做什么？」，右上笔记本场景小熊猫
    /// （输入框有字时对着笔记本打字，其余待机；答完短暂庆祝、失败短暂提醒）。
    private func welcome(_ phase: AIQuickResultPhase?) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("你好"))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.panelPrimary)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Text(tr("今天想让 AI 帮你做什么？"))
                    .font(.system(size: 14))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 2)
            Spacer(minLength: 0)
            PandaStateView(pose: PandaStateResolver.aiPose(phase, typing: !state.draft(instance.id).isEmpty),
                           pulse: pandaPulse, size: 104,
                           fallbackSymbol: "bubble.left.and.text.bubble.right.fill")
                .accessibilityHidden(true)
        }
        .transition(.opacity)
    }

    // MARK: 状态提示

    /// 做完一下之后的一句话（「已复制，到豆包里粘贴即可。」「剪贴板里没有文字」），
    /// 对应刚才那一下和当时选的服务；`AIPanelState.hintLifetime` 后淡出，换服务、
    /// 改问题、关面板也清掉。没有提示时不占地方。
    @ViewBuilder private var statusLine: some View {
        let token = state.hintToken(instance.id)
        Group {
            if let hint = state.hint(instance.id) {
                Text(hint)
                    .font(.system(size: 13))
                    .foregroundStyle(.panelPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .task(id: token) {
            guard let token else { return }
            try? await Task.sleep(for: AIPanelState.hintLifetime)
            guard !Task.isCancelled else { return }
            state.expireHint(token, for: instance.id)
        }
    }

    // MARK: 顶栏

    /// 小 App 图标和「码头 · AI 助手」，右边齿轮：刘海对话开关、助手设置、AI 设置
    /// （原来「…」里的那几样，没有新功能）。小熊猫挪到下面的欢迎区和状态卡片。
    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)
            Text(tr("码头 · AI 助手"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.panelPrimary)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 4)
            Button {
                showingMore.toggle()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelSecondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(.panelFill))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showingMore, arrowEdge: .bottom) { moreMenu }
            .help(tr("刘海对话、助手设置"))
            .accessibilityLabel(tr("设置"))
        }
    }

    /// 「…」里：刘海对话 Pro 开关、助手设置（快捷操作、字牌）、设置 ▸ AI（打开方式、API 密钥）。
    private var moreMenu: some View {
        VStack(alignment: .leading, spacing: 10) {
            AINotchSwitch(isPreview: context.isPreview)
            Button {
                showingMore = false
                state.mode = .manage
            } label: {
                Label(tr("助手设置"), systemImage: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelPrimary)
            }
            .buttonStyle(.plain)
            .help(tr("助手设置：快捷操作、字牌、打开方式和 API 密钥"))
            Button {
                showingMore = false
                openAISettings()
            } label: {
                Label(tr("打开 AI 设置…"), systemImage: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelPrimary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(minWidth: 200, alignment: .leading)
        .disabled(context.isPreview)
    }

    // MARK: 输入框

    private var input: some View {
        ZStack(alignment: .topLeading) {
            AskTextEditor(text: draft, onSubmit: submit,
                          onCancel: { WidgetDetailWindow.shared.close() },
                          focusToken: focusToken)
                .padding(.bottom, 20)
                .accessibilityLabel("要问的问题")
            if state.draft(instance.id).isEmpty {
                Text(tr("向 AI 提问…"))
                    .font(.system(size: 15))
                    .foregroundStyle(.panelSecondary)
                    .padding(.leading, 5)
                    .padding(.top, 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        // 默认放得下 3 行（约 100 点），字多了跟着长，到 200 点后在框里滚动（`AIAsk.inputHeight`）。
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: max(0, CGFloat(AIAsk.inputHeight(state.draft(instance.id), width: Self.textWidth)) - 24),
               alignment: .topLeading)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15),
                   value: AIAsk.inputHeight(state.draft(instance.id), width: Self.textWidth))
        .overlay(alignment: .bottom) {
            // 左边快捷键提示，右下角字数「24 / 2000」；超过 2000 字不提交（不截断，免得打断输入法选字），
            // 字数换成橙色提醒。
            let draft = state.draft(instance.id)
            let within = AIAskLimit.withinLimit(draft)
            HStack(spacing: 8) {
                Text("Enter 提交 · Shift+Enter 换行")
                    .lineLimit(1)
                    .accessibilityHidden(true)
                Spacer(minLength: 4)
                Text(verbatim: AIAskLimit.label(draft))
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundStyle(within ? Color.panelSecondary : Color(hex: PaletteColor.orange.hex).panelReadable)
                    .accessibilityLabel(tr("已输入 \(AIAskLimit.count(draft)) 字，最多 \(AIAskLimit.maxLength) 字"))
            }
            .font(.system(size: 13))
            .foregroundStyle(.panelSecondary)
            .padding(.horizontal, 5)
            .allowsHitTesting(false)
        }
        .padding(12)
        .readableGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// 输入框里一行文字能用的宽度：面板 380 减两边各 16 的边距和框里各 12 的留白，再让一点给光标。
    private static let textWidth: Double = 320

    // MARK: 快捷操作

    /// 2×2 的快捷操作玻璃块：设置页里勾选的那几个（最多四个，默认截图提问、剪贴板总结、
    /// 翻译、润色），每块一个彩色小图标。上面一行右边是「更多」：其余快捷操作、常用提示词、
    /// 调整快捷操作。文字先取输入框，空着时取剪贴板，套好的提示词照平时提问交给选中的服务。
    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(tr("快捷操作"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                moreChipsMenu
            }
            if !chips.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
                          spacing: 8) {
                    ForEach(chips, id: \.self) { chip in
                        chipButton(chip)
                    }
                }
            }
        }
        .disabled(context.isPreview)
        .transition(.opacity)
    }

    /// 「更多」：没摆在一排上的快捷操作、常用提示词，最后进助手设置调整一排上放哪几个。
    private var moreChipsMenu: some View {
        let rest = AIDockChip.allCases.filter { !chips.contains($0) }
        return Menu {
            ForEach(rest, id: \.self) { chip in
                Button {
                    run(chip)
                } label: {
                    Label(Self.gridTitle(chip), systemImage: chip.symbol)
                }
                .disabled(chip.usesClipboardOnly && center.clipboardPreview == nil)
            }
            if !center.prompts.isEmpty {
                Divider()
                ForEach(center.prompts) { prompt in
                    Button(prompt.name) {
                        guard !AskTextView.keyWindowIsComposing else { return }
                        run(template: prompt.content)
                    }
                }
            }
            Divider()
            Button(tr("调整快捷操作…")) { state.mode = .manage }
            Button(tr("管理常用提示词…"), action: openAISettings)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                Text(tr("更多"))
                    .font(.system(size: 13))
            }
            .foregroundStyle(.panelPrimary)
            .padding(.horizontal, 7)
            .frame(height: 28)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(tr("更多快捷操作和常用提示词"))
        .accessibilityLabel(tr("更多快捷操作"))
    }

    /// 剪贴板空时「剪贴板总结」块画成灰的，但不用 `.disabled`：禁用的按钮在 macOS 上
    /// 不出悬停说明，用户只看到一块灰的不知道为什么。悬停写「剪贴板里没有文字」，
    /// 点了也在状态行说这一句。
    private func chipButton(_ chip: AIDockChip) -> some View {
        let clipboardEmpty = chip.usesClipboardOnly && center.clipboardPreview == nil
        let tint = Color(hex: Self.chipTint(chip).hex)
        return Button {
            run(chip)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: chip.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(clipboardEmpty ? Color.panelTertiary : tint.panelReadable)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tint.opacity(clipboardEmpty ? 0.08 : 0.18)))
                    .accessibilityHidden(true)
                Text(Self.gridTitle(chip))
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(AIQuickTileStyle(dimmed: clipboardEmpty))
        .help(chipHelp(chip))
        .accessibilityLabel(Self.gridTitle(chip))
        .accessibilityHint(clipboardEmpty ? tr("剪贴板里没有文字") : "")
    }

    /// 玻璃块上的名字，按效果图写得完整一点；做的事和设置页里同名的快捷操作一样。
    static func gridTitle(_ chip: AIDockChip) -> String {
        switch chip {
        case .screenshot: tr("截图提问")
        case .clipboardSummary: tr("总结剪贴板")
        case .clipboard: tr("处理剪贴板")
        case .translate: tr("翻译内容")
        case .summarize: tr("总结内容")
        case .polish: tr("写作优化")
        case .explain: tr("解释内容")
        }
    }

    /// 每块小图标的颜色。
    static func chipTint(_ chip: AIDockChip) -> PaletteColor {
        switch chip {
        case .screenshot: .graphite
        case .clipboardSummary: .purple
        case .clipboard: .teal
        case .translate: .blue
        case .summarize: .indigo
        case .polish: .orange
        case .explain: .green
        }
    }

    private func chipHelp(_ chip: AIDockChip) -> String {
        switch chip {
        case .screenshot:
            return tr("截图问 AI：框选屏幕上的一块，识别出的文字带进输入框")
        case .clipboard:
            return center.clipboardPreview.map { tr("带进输入框：\($0)") } ?? tr("剪贴板里没有文字")
        case .clipboardSummary:
            return center.clipboardPreview.map { tr("总结剪贴板里的文字：\($0)") } ?? tr("剪贴板里没有文字")
        default:
            return actionHelp(chip.title)
        }
    }

    private func run(_ chip: AIDockChip) {
        guard !context.isPreview else { return }
        switch chip {
        case .screenshot: askFromScreen()
        case .clipboard: pasteClipboard()
        case .clipboardSummary:
            // 只用剪贴板里的文字，不看输入框；输入框里写了一半的字留着。
            center.refreshClipboard()
            switch AIPromptStrip.outcome(template: AIQuickAction.summarize.template, draft: "",
                                         clipboard: center.clipboardText) {
            case .needsText: state.setHint(tr("剪贴板里没有文字"), for: instance.id)
            case .ask(let prompt): deliver(prompt, keepsDraft: true)
            }
        default:
            // 点按钮不会让输入法先确认选字，还有没确认的字时不交出去。
            guard !AskTextView.keyWindowIsComposing, let action = chip.quickAction else { return }
            run(template: action.template)
        }
    }

    /// 「截图提问」：收起面板，框选屏幕上的一块，识别出的文字带进输入框，再打开面板。
    /// 截的图识别完就删，不留副本。
    private func askFromScreen() {
        let id = instance.id
        WidgetDetailWindow.shared.close()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            ShotEditor.askAIFromScreen(widget: id)
        }
    }

    private func actionHelp(_ title: String) -> String {
        let name = target?.title ?? ""
        switch targetMode {
        case .api: return tr("\(title)输入框里的文字（空着时用剪贴板），在刘海对话里直接问\(name)")
        case .web: return tr("\(title)输入框里的文字（空着时用剪贴板）：复制套好的提示词，在刘海对话里打开\(name)")
        case .jump: return tr("\(title)输入框里的文字（空着时用剪贴板），再打开\(name)")
        }
    }

    private func pasteClipboard() {
        guard !context.isPreview else { return }
        center.refreshClipboard()
        let clip = center.clipboardText
        if clip != nil {
            state.setDraft(AIClipboard.insert(clip, into: state.draft(instance.id)), for: instance.id)
        }
        state.setHint(AIPromptStrip.pasteHint(clipboard: clip), for: instance.id)
    }

    private func run(template: String) {
        guard !context.isPreview else { return }
        center.refreshClipboard()
        switch AIPromptStrip.outcome(template: template, draft: state.draft(instance.id),
                                     clipboard: center.clipboardText) {
        case .needsText:
            state.setHint(AIPromptStrip.needsTextHint, for: instance.id)
        case .ask(let prompt):
            deliver(prompt)
        }
    }

    private func openAISettings() {
        guard !context.isPreview, let app = center.app else { return }
        WidgetDetailWindow.shared.close()
        SettingsWindow.shared.show(app: app, tab: "AI")
    }

    // MARK: 底栏

    /// 最底下一行「使用模型：」加服务下拉（服务、打开方式、API 方式的回答位置都在里面，
    /// 和原来底栏的下拉同一套）。放不下时依次：去掉打开方式、服务名截断、去掉「使用模型：」。
    private var modelRow: some View {
        ViewThatFits(in: .horizontal) {
            modelRowContent(service: .full, label: true)
            modelRowContent(service: .name, label: true)
            modelRowContent(service: .truncated, label: true)
            modelRowContent(service: .truncated, label: false)
        }
    }

    private enum ServiceLabel { case full, name, truncated }

    private func modelRowContent(service: ServiceLabel, label: Bool) -> some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            if label {
                Text(tr("使用模型："))
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            serviceButton(service)
            Spacer(minLength: 0)
        }
    }

    /// 网页、App 方式码头拿不到回答，主按钮下面一句说明这次怎么处理；API 方式不占地方。
    @ViewBuilder private var modeLine: some View {
        if targetMode != .api, let target {
            Text(AIHandoff.modeAction(targetMode, appInstalled: AIServiceOpener.installedApp(target) != nil,
                                      supportsAsk: target.supportsAsk))
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .help(AIAsk.modeLine(mode: targetMode, appInstalled: AIServiceOpener.installedApp(target) != nil,
                                     supportsAsk: target.supportsAsk))
        }
    }

    /// 服务胶囊：服务图标加完整名字，点开是服务和打开方式的列表。
    ///
    /// 不用 `Menu`：macOS 上 `.borderlessButton` 样式的菜单只取标签里的第一段字和第一张图，
    /// 胶囊底、图标都被丢掉，真机上只剩字牌里的一个「D」「豆」。这里是普通按钮加弹出框，
    /// 标签画成什么样就是什么样。
    private func serviceButton(_ label: ServiceLabel) -> some View {
        Button {
            choosingService.toggle()
        } label: {
            HStack(spacing: 6) {
                if let target {
                    AIGlyph(initial: target.initial, size: 20, style: .panel)
                        .accessibilityHidden(true)
                    Group {
                        if label == .full {
                            Text(verbatim: "\(target.title) · \(targetMode.title)")
                        } else {
                            Text(verbatim: target.title)
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: label != .truncated, vertical: false)
                    .frame(maxWidth: label == .truncated ? 96 : nil, alignment: .leading)
                } else {
                    Text(tr("服务"))
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.panelSecondary)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.panelPrimary)
            .padding(.leading, 6)
            .padding(.trailing, 10)
            .frame(height: 32)
            .readableGlass(in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: label != .truncated, vertical: true)
        .popover(isPresented: $choosingService, arrowEdge: .top) { serviceList }
        .disabled(context.isPreview)
        .help(target.map { tr("当前服务：\($0.title)，\(center.modeLabel(for: $0))。点一下换服务或打开方式") } ?? "")
        .accessibilityLabel(target.map { tr("服务\($0.title)，打开方式\(AIModeChoice.capsuleTitle(targetMode))") } ?? tr("服务"))
    }

    /// 服务胶囊弹出的列表：上半是服务（当前的带勾），下半是这个服务的打开方式
    /// API / 网页 / App，不能选的灰掉并写原因（和设置 ▸ AI 里改的是同一个键）。
    private var serviceList: some View {
        VStack(alignment: .leading, spacing: 2) {
            listHeader(tr("服务"))
            ForEach(services) { service in
                listRow(selected: service.id == target?.id) {
                    pick(service)
                    choosingService = false
                } label: {
                    AIGlyph(initial: service.initial, size: 20, style: .panel)
                        .accessibilityHidden(true)
                    Text(verbatim: service.title)
                        .font(.system(size: 13))
                        .foregroundStyle(.panelPrimary)
                        .lineLimit(1)
                }
            }
            if let target {
                Divider().padding(.vertical, 4)
                listHeader(tr("打开方式"))
                ForEach(center.modeOptions(for: target), id: \.mode) { option in
                    listRow(selected: option.mode == targetMode) {
                        center.setMode(option.mode, for: target)
                        choosingService = false
                    } label: {
                        Text(AIModeChoice.capsuleTitle(option.mode))
                            .font(.system(size: 13))
                            .foregroundStyle(option.available ? Color.panelPrimary : Color.panelTertiary)
                            .lineLimit(1)
                        if !option.available, let reason = AIModeChoice.unavailableReason(option.mode) {
                            Text(reason)
                                .font(.system(size: 13))
                                .foregroundStyle(.panelTertiary)
                                .lineLimit(1)
                        }
                    }
                    .disabled(!option.available)
                }
                if targetMode == .api {
                    // 原来底栏中间的「回答位置」下拉挪到这里：回答显示在刘海下方的结果卡片，还是完整对话。
                    Divider().padding(.vertical, 4)
                    listHeader(tr("回答位置"))
                    let placement = center.settings.answerPlacement
                    ForEach(AIAnswerPlacement.allCases, id: \.self) { option in
                        listRow(selected: option == placement) {
                            center.updateSettings { $0.answerPlacement = option }
                            choosingService = false
                        } label: {
                            Text(option.title)
                                .font(.system(size: 13))
                                .foregroundStyle(.panelPrimary)
                                .lineLimit(1)
                        }
                    }
                }
            }
        }
        .padding(8)
        .frame(minWidth: 220, alignment: .leading)
    }

    private func listHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.panelSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .accessibilityAddTraits(.isHeader)
    }

    private func listRow<RowLabel: View>(selected: Bool, action: @escaping () -> Void,
                                      @ViewBuilder label: () -> RowLabel) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                label()
                Spacer(minLength: 12)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                    .opacity(selected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// 唯一的主按钮，整行宽的小熊猫橙实色胶囊：API「开始提问」；App 和网页方式照实写
    /// 「复制并打开豆包」「去网页提问」。白字不够 4.5 时 `PanelSolidButtonStyle` 自动加深
    /// （见 `PanelButtonLook.solid`），设了主题色按主题色；不发光。
    private var primaryButton: some View {
        Button(action: submitFromButton) {
            HStack(spacing: 6) {
                Image(systemName: targetMode == .api ? "ellipsis.bubble" : "arrow.up.forward.app")
                    .font(.system(size: 14, weight: .semibold))
                    .accessibilityHidden(true)
                Text(buttonTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
        }
        .buttonStyle(PanelSolidButtonStyle(fill: panelTint.accent(or: Color(hex: ShelfColor.redPanda.hex))))
        .disabled(!canSubmit)
        .help(buttonHelp)
        .accessibilityLabel(buttonTitle)
        .accessibilityHint(buttonHelp)
    }

    private func pick(_ service: AIService) {
        targetID = service.id
        // 上一句提示说的是原来那个服务，换了就不再挂着。
        state.setHint(nil, for: instance.id)
        // 和刘海对话共用当前服务；刘海那边没有这个服务时 select 不改。
        center.select(service.id)
    }

    private var empty: some View {
        VStack(spacing: 12) {
            PanelNote(symbol: "plus.square.dashed", text: tr("卡片上还没有 AI 字牌。"))
            Button("添加字牌") { state.mode = .manage }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("添加 AI 字牌")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    /// 这个服务的打开方式。不是 App 方式时，问题交给刘海对话。
    private var targetMode: AIOpenMode {
        target.map { center.mode(for: $0) } ?? .jump
    }

    /// 主按钮的字要短（「复制并打开豆包」「去网页提问」「提问」），会做什么写在左边那一句里。
    private var buttonTitle: String {
        if targetMode == .api { return tr("开始提问") }
        return AIAsk.buttonTitle(mode: targetMode, service: target,
                          appInstalled: target.map { AIServiceOpener.installedApp($0) != nil } ?? false)
    }

    /// 悬停说明和读屏提示：把按钮做什么说完整。
    private var buttonHelp: String {
        let name = target?.title ?? ""
        switch targetMode {
        case .api:
            return center.settings.answerPlacement == .notch
                ? tr("用 API 直接问\(name)，回答显示在刘海下方的结果卡片")
                : tr("用 API 直接问\(name)，回答显示在刘海对话")
        case .web: return tr("复制问题，在刘海对话里打开\(name)的网页")
        case .jump:
            if let target, AIServiceOpener.installedApp(target) != nil {
                return tr("复制问题，再打开\(name) App")
            }
            return target?.supportsAsk == true
                ? tr("在浏览器打开\(name)，问题会带过去")
                : tr("把问题复制到剪贴板，再打开\(name)")
        }
    }

    // MARK: 提交

    /// 点按钮不会让输入法先确认选字，还有没确认的字时不交出去。
    private func submitFromButton() {
        guard AIAsk.canSubmit(state.draft(instance.id), hasMarkedText: AskTextView.keyWindowIsComposing) else { return }
        submit()
    }

    private func submit() { deliver(nil) }

    /// 交出去。`text` 是快捷指令或常用提示词套好的提示词，nil 时交输入框里的问题。
    /// 交给谁见 `AIHandoff.plan`。
    private func deliver(_ text: String?, keepsDraft: Bool = false) {
        guard !context.isPreview, let service = target else { return }
        let asked = text ?? state.draft(instance.id)
        guard AIAskLimit.withinLimit(asked) else {
            state.setHint(AIAskLimit.overLimitHint, for: instance.id)
            return
        }
        let handoff = AIHandoff.plan(asked, mode: targetMode,
                                     notchUnlocked: ProLicenseGate.canOpenAINotch(unlocked: ProAccess.isUnlocked))
        switch handoff {
        case .blocked:
            state.setHint(AIAsk.hint(after: .blocked, service: service), for: instance.id)
        case .paywall:
            // 刘海对话是码头 Pro：没解锁时弹付费墙，问题留在框里。
            PaywallWindow.shared.show()
        case .notchAPI(let question), .notchWeb(let question):
            // API 的结果放在哪（刘海卡片、备用浮窗、完整对话、只在刘海下沿显示进度），交出去之前定好。
            let quick: AIQuickResultTarget = targetMode == .api
                ? AINotchController.shared.quickTarget(mode: .api) : .none
            switch center.receive(question, for: service) {
            case .accepted:
                // 交过去了才清空草稿（剪贴板总结不动输入框）。先收起这个面板，再从刘海长出结果，不叠两个窗口。
                if !keepsDraft { state.setDraft("", for: instance.id) }
                WidgetDetailWindow.shared.close()
                showResultAfterPanelCloses(quick, serviceID: service.id)
            case .busy:
                state.setHint(tr("还在回答，先停止或等它答完。"), for: instance.id)
            case .unavailable:
                state.setHint(tr("\(service.title)不在刘海对话的服务里：刘海对话用第一张 AI 卡片的字牌。"), for: instance.id)
            }
        case .app:
            jump(asked, service: service, keepsDraft: keepsDraft)
        }
    }

    /// 等小组件面板收起的淡出走完再显示结果；减弱动态效果时马上显示。
    /// - 刘海卡片、备用浮窗：弹快捷结果卡片（流式回答一边来一边显示）。
    /// - 完整对话：原来的做法，打开刘海对话面板（网页方式也是它，在那里粘贴发送）。
    /// - 只显示进度：什么都不弹，刘海下沿「正在思考」，点刘海看回答。
    private func showResultAfterPanelCloses(_ quick: AIQuickResultTarget, serviceID: String) {
        let wait = reduceMotion ? 0 : 160
        Task { @MainActor in
            if wait > 0 { try? await Task.sleep(for: .milliseconds(wait)) }
            switch quick {
            case .notchCard, .floating: AINotchController.shared.presentQuick(serviceID: serviceID)
            case .quiet: break
            case .fullPanel, .none: AINotchController.shared.open()
            }
        }
    }

    /// 「App」方式：装了 ChatGPT、Perplexity 这类 App 时复制问题再打开 App，没装才走浏览器。
    private func jump(_ asked: String, service: AIService, keepsDraft: Bool = false) {
        let plan = AIAsk.plan(asked, service: service, appInstalled: AIServiceOpener.installedApp(service) != nil)
        switch plan {
        case .blocked:
            state.setHint(AIAsk.hint(after: plan, service: service), for: instance.id)
            return
        case .openWithQuestion(let url):
            guard AIServiceOpener.open(url) else {
                state.setHint(tr("没能打开\(service.title)。"), for: instance.id)
                return
            }
        case .copyThenOpen(let question):
            AIServiceOpener.copy(question)
            guard AIServiceOpener.open(service) else {
                state.setHint(tr("已复制，但没能打开\(service.title)。"), for: instance.id)
                return
            }
        }
        // 交出去了才清空草稿；提示留在面板上，点到别处面板自己收起。
        if !keepsDraft { state.setDraft("", for: instance.id) }
        state.setHint(AIAsk.hint(after: plan, service: service), for: instance.id)
    }
}

/// 快捷操作玻璃块：可读玻璃底，按下时盖一层选中色；`dimmed` 时字变淡但还能点、还能悬停出说明
/// （剪贴板空时的「总结剪贴板」）。点击区就是整块（至少 44 高）。
private struct AIQuickTileStyle: ButtonStyle {
    var dimmed = false

    func makeBody(configuration: Configuration) -> some View {
        AIQuickTileBody(configuration: configuration, dimmed: dimmed)
    }
}

private struct AIQuickTileBody: View {
    var configuration: ButtonStyleConfiguration
    var dimmed: Bool
    @Environment(\.isEnabled) private var enabled

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 12, style: .continuous) }

    var body: some View {
        configuration.label
            .foregroundStyle(enabled && !dimmed ? Color.panelPrimary : Color.panelTertiary)
            .readableGlass(in: shape)
            .overlay {
                if configuration.isPressed && enabled && !dimmed {
                    shape.fill(Color.panelSelected)
                }
            }
            .contentShape(shape)
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
                chipSection
                serviceSettingsSection
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

    /// 提问页输入框下面显示哪几个快捷操作，存在刘海对话的设置里（两边共用一份 AI 设置）。
    private var chipSection: some View {
        let center = AIChatCenter.shared
        let raw = center.settings.panelChips
        let shown = Set(AIDockChips.resolved(raw))
        return section(tr("快捷操作")) {
            Text(tr("显示在输入框下面，最多 \(AIDockChips.maxCount) 个。"))
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(AIDockChip.allCases, id: \.self) { chip in
                let on = shown.contains(chip)
                Toggle(isOn: Binding(get: { on }, set: { _ in
                    guard !context.isPreview else { return }
                    center.updateSettings { $0.panelChips = AIDockChips.toggled(chip, in: $0.panelChips) }
                })) {
                    Label(Self.gridTitle(chip), systemImage: chip.symbol)
                        .font(.system(size: 13))
                        .foregroundStyle(.panelPrimary)
                }
                .toggleStyle(.checkbox)
                .disabled(!AIDockChips.canToggle(chip, in: raw))
                .frame(height: 24)
                .accessibilityLabel(on ? tr("\(chip.title)，已显示") : tr("\(chip.title)，已隐藏"))
            }
        }
    }

    /// 打开方式（网页、API、App）、API 密钥和常用提示词在设置 ▸ AI 里，不在面板里重做一遍。
    private var serviceSettingsSection: some View {
        section(tr("服务与 API 密钥")) {
            Text(tr("每个服务用网页、API 还是 App，API 密钥和常用提示词，都在设置 ▸ AI 里改。"))
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                guard !context.isPreview, let app = AIChatCenter.shared.app else { return }
                WidgetDetailWindow.shared.close()
                SettingsWindow.shared.show(app: app, tab: "AI")
            } label: {
                Label(tr("打开 AI 设置…"), systemImage: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelPrimary)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
            .accessibilityLabel(tr("打开设置里的 AI 页"))
        }
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
    /// 变了就把光标放进来（刘海对话回答下面的「继续追问」）。0 是不动。
    var focusToken: Int = 0

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
        if focusToken != context.coordinator.focusToken {
            context.coordinator.focusToken = focusToken
            if focusToken > 0 {
                Task { @MainActor [weak view] in
                    guard let view else { return }
                    view.window?.makeKey()
                    view.window?.makeFirstResponder(view)
                    view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
                }
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AskTextEditor
        var focusToken = 0

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
