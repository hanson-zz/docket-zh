import AppKit
import SwiftUI
import WebKit

// MARK: - 刘海入口

/// 入口窗口里画的东西。贴刘海时是一块和刘海重合的纯黑（刘海本身就是入口，
/// 提示在下沿那一条里）；外接屏是菜单栏下方的小胶囊，平时半透明，指针移上去或回答
/// 生成中完全显示。
struct AINotchEntryView: View {
    var model: AINotchEntryModel
    var center: AIChatCenter

    var body: some View {
        Group {
            switch model.entry {
            case .notch:
                // 和刘海一样的纯黑，看起来就是刘海本身。不能用全透明：窗口服务器
                // 会让点击穿过透明的像素，刘海就点不到了。
                UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8, style: .continuous)
                    .fill(.black)
            case .capsule(let frame):
                capsule(size: frame.size)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(model.visible ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: model.visible)
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("AI 助手")
        .accessibilityHint("点按展开对话")
        .accessibilityAddTraits(.isButton)
        .help("AI 助手：点一下展开对话")
    }

    private func capsule(size: CGSize) -> some View {
        let generating = center.isGenerating
        return ZStack {
            if generating {
                AIBouncingDots(dot: 3)
            } else {
                AIPandaAvatar(size: AINotchLayout.stripPandaSize)
            }
        }
        .frame(width: size.width, height: size.height)
        .background {
            Capsule(style: .continuous)
                .fill(.black)
                .overlay { Capsule(style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 0.5) }
        }
        .opacity(AINotchLayout.capsuleOpacity(hovering: model.hovering, generating: generating))
    }
}

/// 刘海下沿往下长出的那一条：和刘海同宽、底部圆角，悬停时是小熊猫，回答
/// 生成中是三个跳动的小点。打开“减少动态效果”时不做伸缩，直接显示或隐藏。
struct AINotchStripView: View {
    var entry: AINotchEntryModel
    var panel: AINotchPanelModel
    var center: AIChatCenter

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let shape = UnevenRoundedRectangle(bottomLeadingRadius: 9, bottomTrailingRadius: 9,
                                                      style: .continuous)

    var body: some View {
        let content = AINotchLayout.stripContent(visible: entry.visible, panelOpen: panel.isOpen,
                                                 hovering: entry.hovering, generating: center.isGenerating)
        let height = AINotchLayout.stripHeight
        return VStack(spacing: 0) {
            ZStack {
                if content == .dots {
                    AIBouncingDots(dot: 3)
                } else if content == .panda {
                    AIPandaAvatar(size: AINotchLayout.stripPandaSize)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Self.shape.fill(.black))
            .frame(height: content == nil ? 0 : height, alignment: .bottom)
            .clipped()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85), value: content)
        .environment(\.colorScheme, .dark)
        .accessibilityHidden(true)
    }
}

/// 三个跳动的小点。减少动态效果时不跳。
struct AIBouncingDots: View {
    var dot: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: dot * 0.7) {
                ForEach(0 ..< 3, id: \.self) { index in
                    Circle()
                        .fill(Color(hex: AIGlyph.dotHex))
                        .frame(width: dot, height: dot)
                        .offset(y: reduceMotion ? 0 : -abs(sin(t * 5 - Double(index) * 0.7)) * dot * 0.9)
                }
            }
        }
        .accessibilityLabel("正在回答")
    }
}

// MARK: - 展开的面板

/// 刘海下面长出来的对话面板，约 420 x 520。
///
/// 底色：一律是液态玻璃，跟随设置里的浅色 / 深色，刘海下面和外接屏胶囊下面
/// 一样（以前刘海下面是纯黑，用户真机觉得黑色体验不好）。挂在刘海下面时，为了
/// 和硬件刘海接上不出黑白硬缝，面板顶上正对刘海留一条和刘海同宽的黑色，从刘海
/// 下沿往下约 12pt 渐隐到玻璃（`AIChatNotchBlend`），顶栏往下让出这一条；顶边
/// 12 的圆角不变。内容、网页一律跟随面板深浅色，文字用 PanelColors 语义色，
/// 读的字至少 panelSecondary（浅色玻璃上 panelTertiary 不到 4.5）。
///
/// 层级：顶上一行是小熊猫 + 服务名（几个服务时是切换胶囊）+ 网页模式的刷新、
/// 在浏览器打开 + 图钉，下面一排提示词，再下面是对话、网页或 App 方式。服务名只写
/// 一遍，见 `AINotchPanelHeader`。
struct AIChatPanelView: View {
    var center: AIChatCenter
    var model: AINotchPanelModel
    var close: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    /// 顶栏、提示词、网页四周统一的边距。
    static let inset: CGFloat = 12
    /// 实心蓝底白字（我的提问气泡、App 方式的按钮）：白字对比度 5.2，过 4.5；原来的
    /// #3B82F6 只有 3.7，小熊猫的 #4C9BFF 只有 2.8。
    static let solidBlueHex = "#2563EB"

    private static let shape = UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 26,
                                                      bottomTrailingRadius: 26, topTrailingRadius: 12,
                                                      style: .continuous)

    var body: some View {
        content
            .frame(width: AINotchLayout.panelSize.width, height: AINotchLayout.panelSize.height)
            .background {
                ZStack(alignment: .topLeading) {
                    AIChatPanelSurface(shape: Self.shape)
                    if let blend = model.notchBlend {
                        AIChatNotchBlend()
                            .frame(width: blend.width, height: blend.height)
                            .offset(x: blend.minX, y: blend.minY)
                    }
                }
            }
            .clipShape(Self.shape)
            .scaleEffect(x: appeared ? 1 : 0.55, y: appeared ? 1 : 0.08, anchor: .top)
            .opacity(appeared ? 1 : 0)
            .onAppear(perform: enter)
            .onChange(of: model.session) { _, _ in
                appeared = false
                center.notice = nil
                Task { @MainActor in enter() }
            }
            // 面板开着时每秒看一眼剪贴板有没有变（只比较计数，变了才读内容），
            // 收起时不读。
            .task(id: model.isOpen) {
                guard model.isOpen else { return }
                while !Task.isCancelled {
                    center.refreshClipboard()
                    try? await Task.sleep(for: .seconds(1))
                }
            }
    }

    /// 从刘海往下长出来；减少动态效果时直接出现。
    private func enter() {
        if reduceMotion {
            appeared = true
        } else {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { appeared = true }
        }
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: 0) {
            header
            if let service = center.current {
                AIPromptBar(center: center, service: service, close: close)
            }
            Group {
                if let service = center.current {
                    switch center.mode(for: service) {
                    case .api: AIAPIChatPane(center: center, service: service, close: close)
                    case .web: AIWebPane(center: center, service: service)
                    case .jump: AIJumpPane(center: center, service: service, close: close)
                    }
                } else {
                    PanelNote(symbol: "plus.square.dashed",
                              text: tr("还没有 AI 字牌。在货架的 AI 助手卡片上点“＋”添加。"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            AIPandaAvatar(size: 26)
            if AINotchPanelHeader.showsServiceChips(serviceCount: center.services.count) {
                chips
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                title
                Spacer(minLength: 6)
            }
            if let service = center.current, AINotchPanelHeader.showsWebControls(center.mode(for: service)) {
                reloadButton(service)
                headerButton("arrow.up.right.square", help: tr("在浏览器打开"),
                             label: tr("在浏览器打开当前网页")) { center.openInBrowser(service) }
            }
            pinButton
        }
        .padding(.horizontal, Self.inset)
        .padding(.top, AINotchLayout.headerTopPadding(hangsFromNotch: model.hangsFromNotch))
        .padding(.bottom, 8)
    }

    /// 只有一个服务（或还没有服务）时：服务名，同一行后面跟一句小字写打开方式
    /// （「网页 · 你的账号」「API · deepseek-chat」）。
    @ViewBuilder private var title: some View {
        if let service = center.current {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(service.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                    .lineLimit(1)
                    .layoutPriority(1)
                Text(center.modeLabel(for: service))
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .help(center.modeLabel(for: service))
            .accessibilityElement(children: .combine)
        } else {
            Text("小熊猫")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.panelPrimary)
        }
    }

    /// 几个服务时顶上那一行就是切换胶囊，选中的那个就是标题，不再另写服务名。
    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(center.services) { service in
                    let selected = service.id == center.current?.id
                    Button {
                        center.select(service.id)
                    } label: {
                        HStack(spacing: 4) {
                            Text(service.title)
                                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                                .lineLimit(1)
                                .fixedSize()
                            if center.isGenerating(service.id) {
                                Circle().fill(Color(hex: AIGlyph.dotHex)).frame(width: 5, height: 5)
                            }
                        }
                        .foregroundStyle(selected ? Color.panelPrimary : Color.panelSecondary)
                        .padding(.horizontal, 11)
                        .frame(height: 26)
                        .background {
                            if selected {
                                Capsule().fill(.panelRaised).panelLift()
                            } else {
                                Capsule().fill(.panelFill)
                            }
                        }
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(center.modeLabel(for: service))
                    .accessibilityLabel(selected ? tr("\(service.title)，当前") : tr("切换到 \(service.title)"))
                }
            }
            .padding(.vertical, 2)
        }
    }

    /// 刷新；网页在载入时换成转圈，位置不变，顶栏不跳。
    @ViewBuilder private func reloadButton(_ service: AIService) -> some View {
        if center.isLoading(service.id) {
            ProgressView()
                .controlSize(.small)
                .frame(width: 28, height: 28)
                .accessibilityLabel(tr("网页载入中"))
        } else {
            headerButton("arrow.clockwise", help: tr("刷新"), label: tr("刷新网页")) { center.reload(service) }
        }
    }

    private func headerButton(_ symbol: String, help: String, label: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelSecondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.panelFill))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(label)
    }

    private var pinButton: some View {
        Button {
            center.pinned.toggle()
        } label: {
            Image(systemName: center.pinned ? "pin.fill" : "pin")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(center.pinned ? Color.panelPrimary : Color.panelSecondary)
                .rotationEffect(.degrees(center.pinned ? 0 : 35))
                .frame(width: 28, height: 28)
                .background(Circle().fill(center.pinned ? Color.panelSelected : Color.panelFill))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(center.pinned ? tr("已钉住：点面板外面不会收起") : tr("钉住：点面板外面不收起"))
        .accessibilityLabel(center.pinned ? tr("取消钉住") : tr("钉住面板"))
    }
}

/// 面板底：液态玻璃，系统「降低透明度」时换成实心底（同 `PanelGlassSurface`，
/// 那个只认圆角矩形，这里上下圆角不一样）。
private struct AIChatPanelSurface: View {
    var shape: UnevenRoundedRectangle

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            shape.fill(scheme == .dark ? Color(hex: "#1C1C1E") : Color(hex: "#F4F4F6"))
        } else {
            Color.clear.glassEffect(.regular, in: shape)
        }
    }
}

/// 刘海下面板顶上那条黑色过渡：顶边是和刘海一样的纯黑，往下先慢后快再慢地
/// 淡到透明，露出下面的玻璃，深色玻璃上几乎看不出，浅色玻璃上像刘海的影子
/// 收进面板里，不是一条黑白硬缝。两侧不做羽化，和刘海的两条竖边对齐。
private struct AIChatNotchBlend: View {
    var body: some View {
        LinearGradient(stops: [
            .init(color: .black, location: 0),
            .init(color: .black.opacity(0.85), location: 0.25),
            .init(color: .black.opacity(0.45), location: 0.55),
            .init(color: .black.opacity(0.12), location: 0.82),
            .init(color: .black.opacity(0), location: 1),
        ], startPoint: .top, endPoint: .bottom)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - 剪贴板接力、快捷指令和常用提示词

/// 服务字牌下面的一排，画法和迷你提问面板共用（`AIPromptChipBar`）。
///
/// 文字先取输入框，空着时取剪贴板。API 直接发出去流式回答；网页模式没有
/// 输入框，复制套好的提示词，到网页里粘贴；App 方式和平时提问一样。
private struct AIPromptBar: View {
    var center: AIChatCenter
    var service: AIService
    var close: () -> Void

    private var mode: AIOpenMode { center.mode(for: service) }

    var body: some View {
        AIPromptChipBar(
            hasInput: mode != .web,
            clipboardPreview: center.clipboardPreview,
            notice: center.notice,
            prompts: center.prompts,
            actionHelp: { helpText($0.title) },
            clipboardHelp: mode == .web ? tr("网页模式下，快捷指令会用剪贴板里的文字") : tr("点一下带进输入框"),
            paste: { center.pasteClipboard() },
            runAction: { center.run($0) },
            runPrompt: { center.run($0) },
            managePrompts: {
                guard let app = center.app else { return }
                close()
                SettingsWindow.shared.show(app: app, tab: "AI")
            })
            .padding(.horizontal, AIChatPanelView.inset)
            .padding(.top, 2)
    }

    private func helpText(_ title: String) -> String {
        switch mode {
        case .api: tr("\(title)输入框里的文字（空着时用剪贴板），直接发给 \(service.title)")
        case .web: tr("\(title)剪贴板里的文字：复制套好的提示词，到网页里粘贴")
        case .jump: tr("\(title)输入框里的文字（空着时用剪贴板），再打开 \(service.title)")
        }
    }
}

// MARK: - API 对话

private struct AIAPIChatPane: View {
    var center: AIChatCenter
    var service: AIService
    var close: () -> Void

    private var messages: [AIChatMessage] { center.messages(service.id) }
    private var generating: Bool { center.isGenerating(service.id) }

    var body: some View {
        VStack(spacing: 0) {
            if messages.isEmpty {
                VStack(spacing: 8) {
                    Text("想问点什么？")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.panelPrimary)
                    Text("回答会一个字一个字流出来，可以停、重试、复制、接着问。")
                        .font(.system(size: 13))
                        .foregroundStyle(.panelSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 30)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                transcript
            }
            if let last = messages.last(where: { $0.role == .assistant }) {
                actions(last)
            }
            AIChatInput(center: center, generating: generating,
                        placeholder: messages.isEmpty ? tr("问点什么… Enter 发送，Shift+Enter 换行")
                                                      : tr("继续问… Enter 发送，Shift+Enter 换行"),
                        submit: { center.send() }, stop: { center.stop() }, close: close)
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
                .padding(.top, 6)
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(messages) { message in
                        row(message).id(message.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .scrollIndicators(.never)
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: messages.last?.text) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    @ViewBuilder private func row(_ message: AIChatMessage) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 48)
                Text(message.text)
                    .font(.system(size: 13.5))
                    .foregroundStyle(.white)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: AIChatPanelView.solidBlueHex)))
                    .accessibilityLabel(tr("我：\(message.text)"))
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 6) {
                if message.status == .streaming && message.text.isEmpty {
                    // API 流式回答还没到第一个字：先写一句占位，收到内容就换成回答。
                    Text(tr("正在思考…"))
                        .font(.system(size: 13))
                        .foregroundStyle(.panelSecondary)
                        .accessibilityAddTraits(.updatesFrequently)
                } else if !message.text.isEmpty || message.status == .streaming {
                    AIAnswerText(text: message.text, streaming: message.status == .streaming)
                }
                switch message.status {
                case .failed(let reason):
                    Label(reason, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(hex: PaletteColor.orange.hex).panelReadable)
                        .fixedSize(horizontal: false, vertical: true)
                case .stopped:
                    Text(message.text.isEmpty ? tr("（已停止）") : tr("（已停止生成）"))
                        .font(.system(size: 13))
                        .foregroundStyle(.panelSecondary)
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func actions(_ last: AIChatMessage) -> some View {
        HStack(spacing: 14) {
            if generating {
                action(tr("停止生成"), symbol: "stop.circle") { center.stop() }
            } else {
                if !last.text.isEmpty {
                    action(tr("复制", context: "copy"), symbol: "doc.on.doc") { center.copy(last.text) }
                }
                action(tr("重试"), symbol: "arrow.clockwise") { center.retry() }
                action(tr("新对话"), symbol: "square.and.pencil") { center.clear() }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private func action(_ title: String, symbol: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Label(title, systemImage: symbol)
                .labelStyle(.titleAndIcon)
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// 一段回答：普通段落用 Markdown（粗体、斜体、行内代码、链接，保留换行），
/// 代码块等宽显示。还在流的时候末尾带一个光标。
struct AIAnswerText: View {
    var text: String
    var streaming: Bool

    var body: some View {
        let blocks = AIMarkdown.blocks(text)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                let isLast = index == blocks.count - 1
                switch block {
                case .text(let paragraph):
                    Text(Self.attributed(paragraph, cursor: streaming && isLast))
                        .font(.system(size: 13.5))
                        .foregroundStyle(.panelPrimary)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                case .code(let language, let body):
                    VStack(alignment: .leading, spacing: 4) {
                        if !language.isEmpty {
                            Text(language)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.panelSecondary)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(body + (streaming && isLast ? "▍" : ""))
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(.panelPrimary)
                                .textSelection(.enabled)
                                .fixedSize()
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.panelFill))
                }
            }
            if blocks.isEmpty && streaming {
                Text("▍")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.panelPrimary)
            }
        }
    }

    static func attributed(_ text: String, cursor: Bool) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace,
                                                              failurePolicy: .returnPartiallyParsedIfPossible)
        var result = (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
        if cursor { result.append(AttributedString("▍")) }
        return result
    }
}

/// 面板底部的输入框：Enter 发送，Shift+Enter 换行，输入法选字时 Enter
/// 只确认选字。生成中右边的按钮变成停止。
private struct AIChatInput: View {
    var center: AIChatCenter
    var generating: Bool
    var placeholder: String
    var submit: () -> Void
    var stop: () -> Void
    var close: () -> Void

    private var draft: Binding<String> {
        Binding(get: { center.draft }, set: { center.draft = $0 })
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            ZStack(alignment: .topLeading) {
                AskTextEditor(text: draft, onSubmit: { if !generating { submit() } }, onCancel: close)
                    .frame(height: 40)
                    .accessibilityLabel("要问的问题")
                if center.draft.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 13.5))
                        .foregroundStyle(.panelSecondary)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .padding(.top, 10)
            Button {
                if generating {
                    stop()
                } else if AIAsk.canSubmit(center.draft, hasMarkedText: AskTextView.keyWindowIsComposing) {
                    // 输入法还有没确认的字时不发：点按钮不会让输入法先确认选字。
                    submit()
                }
            } label: {
                Image(systemName: generating ? "stop.fill" : "arrow.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.panelOnPrimary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(.panelPrimary.opacity(generating || AIAsk.question(center.draft) != nil ? 1 : 0.35)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(generating ? tr("停止生成") : tr("发送"))
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(height: 56)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.panelFill))
    }
}

// MARK: - 网页

private struct AIWebPane: View {
    var center: AIChatCenter
    var service: AIService

    @Environment(\.colorScheme) private var scheme

    /// 网页的圆角：面板底角 26 往里收一个边距，和面板同心。
    private static let corner: CGFloat = 14

    /// 服务名、刷新、在浏览器打开都在面板顶栏，这里只剩网页本身：圆角内嵌，
    /// 四周和顶栏、提示词同一个边距，下面一行小字写网页由谁提供。
    var body: some View {
        VStack(spacing: 6) {
            if center.showsGoogleWarning(service.id) {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(AIWeb.googleWarning).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("用浏览器打开") { center.openInBrowser(service) }
                        .buttonStyle(.plain)
                        .underline()
                }
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: PaletteColor.orange.hex).panelReadable)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(hex: PaletteColor.orange.hex).opacity(0.12)))
            }
            AIWebHost(center: center, service: service, dark: scheme == .dark, corner: Self.corner)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: Self.corner, style: .continuous).fill(.panelFill))
                .clipShape(RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Self.corner, style: .continuous)
                        .strokeBorder(.panelSeparator, lineWidth: 0.5)
                        .allowsHitTesting(false)
                }
            if let credit = AIWeb.credit(service.homeURL) {
                Text(credit)
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, AIChatPanelView.inset)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }
}

/// 把服务自己的 WKWebView 放进来。网页由 `AIChatCenter` 留着，换服务时只
/// 换挂上去的那一个，不重载。网页的外观跟着面板（刘海下面也一样）：深色玻璃上
/// 是 darkAqua，网页按 prefers-color-scheme 换深色；浅色玻璃上是 aqua。圆角在
/// 容器的图层上裁，WKWebView 是 AppKit 视图，SwiftUI 的 clipShape 不一定裁得到。
private struct AIWebHost: NSViewRepresentable {
    var center: AIChatCenter
    var service: AIService
    var dark: Bool
    var corner: CGFloat

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = corner
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        if container.appearance?.name != appearance?.name { container.appearance = appearance }
        guard let web = center.webView(for: service) else {
            container.subviews.forEach { $0.removeFromSuperview() }
            return
        }
        // 网页可能先挂在过别的容器里，外观直接设在网页上，不靠继承。
        if web.appearance?.name != appearance?.name { web.appearance = appearance }
        guard web.superview !== container else { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        web.removeFromSuperview()
        web.frame = container.bounds
        web.autoresizingMask = [.width, .height]
        container.addSubview(web)
    }
}

// MARK: - App 方式

/// App 方式：和原来的提问面板一样，能带问题的带着问题开浏览器，其余复制
/// 问题再打开 App 或网页。
private struct AIJumpPane: View {
    var center: AIChatCenter
    var service: AIService
    var close: () -> Void

    private var draft: Binding<String> {
        Binding(get: { center.draft }, set: { center.draft = $0; center.jumpHint = nil })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                AskTextEditor(text: draft, onSubmit: { center.jump() }, onCancel: close)
                    .frame(height: 150)
                    .accessibilityLabel("要问的问题")
                if center.draft.isEmpty {
                    Text("想问点什么？")
                        .font(.system(size: 14))
                        .foregroundStyle(.panelSecondary)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.panelFill))
            HStack(spacing: 10) {
                Button(tr("只打开 \(service.title)")) { center.openService() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
                Spacer(minLength: 0)
                Button {
                    guard !AskTextView.keyWindowIsComposing else { return }
                    center.jump()
                } label: {
                    Text(AIAsk.buttonTitle(for: service))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(Capsule().fill(Color(hex: AIChatPanelView.solidBlueHex)
                            .opacity(AIAsk.question(center.draft) != nil ? 1 : 0.35)))
                }
                .buttonStyle(.plain)
                .disabled(AIAsk.question(center.draft) == nil)
            }
            Text(center.jumpHint ?? (AIServiceOpener.installedApp(service) != nil
                 ? tr("App：Enter 提交，会复制问题并打开 \(service.title) App。")
                 : service.supportsAsk
                 ? tr("App：Enter 提交，会在浏览器打开 \(service.title) 并带上问题。")
                 : tr("App：Enter 提交，\(service.title) 不支持带问题打开，会先复制问题。")))
                .font(.system(size: 13))
                .foregroundStyle(center.jumpHint == nil ? Color.panelSecondary : Color.panelPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text("想直接在这里对话：到“设置 ▸ AI”把它改成网页或 API。")
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AIChatPanelView.inset)
    }
}
