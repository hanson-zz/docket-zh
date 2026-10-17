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
struct AIChatPanelView: View {
    var center: AIChatCenter
    var model: AINotchPanelModel
    var close: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private static let shape = UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 26,
                                                      bottomTrailingRadius: 26, topTrailingRadius: 12,
                                                      style: .continuous)

    var body: some View {
        content
            .frame(width: AINotchLayout.panelSize.width, height: AINotchLayout.panelSize.height)
            .background(Self.shape.fill(.black))
            .overlay(Self.shape.stroke(.white.opacity(0.08), lineWidth: 0.5))
            .clipShape(Self.shape)
            .scaleEffect(x: appeared ? 1 : 0.55, y: appeared ? 1 : 0.08, anchor: .top)
            .opacity(appeared ? 1 : 0)
            .environment(\.colorScheme, .dark)
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
            if !center.services.isEmpty {
                chips
            }
            Rectangle().fill(.white.opacity(0.1)).frame(height: 0.5).padding(.horizontal, 14)
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
                              text: "还没有 AI 字牌。在货架的 AI 助手卡片上点“＋”添加。")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            AIPandaAvatar(size: 28)
            Text("小熊猫")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
            Spacer(minLength: 8)
            if let service = center.current {
                Text(center.modeLabel(for: service))
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Button {
                center.pinned.toggle()
            } label: {
                Image(systemName: center.pinned ? "pin.fill" : "pin")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(center.pinned ? 0.95 : 0.55))
                    .rotationEffect(.degrees(center.pinned ? 0 : 35))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(.white.opacity(center.pinned ? 0.16 : 0.06)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(center.pinned ? "已钉住：点面板外面不会收起" : "钉住：点面板外面不收起")
            .accessibilityLabel(center.pinned ? "取消钉住" : "钉住面板")
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

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
                                .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                            if center.isGenerating(service.id) {
                                Circle().fill(Color(hex: AIGlyph.dotHex)).frame(width: 5, height: 5)
                            }
                        }
                        .foregroundStyle(.white.opacity(selected ? 1 : 0.75))
                        .padding(.horizontal, 11)
                        .frame(height: 26)
                        .background(Capsule().fill(.white.opacity(selected ? 0.2 : 0.06)))
                        .overlay(Capsule().strokeBorder(.white.opacity(selected ? 0.35 : 0.12), lineWidth: 0.75))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(selected ? "\(service.title)，当前" : "切换到 \(service.title)")
                }
            }
            .padding(.horizontal, 14)
        }
        .padding(.bottom, 10)
    }
}

// MARK: - 剪贴板接力、快捷指令和常用提示词

/// 服务字牌下面的一排：剪贴板接力、翻译、总结、润色、解释和“常用”菜单，
/// 下面一行是剪贴板预览或者刚才做了什么。
///
/// 文字先取输入框，空着时取剪贴板。API 直接发出去流式回答；网页模式没有
/// 输入框，复制套好的提示词，到网页里粘贴；跳转和平时提问一样。
private struct AIPromptBar: View {
    var center: AIChatCenter
    var service: AIService
    var close: () -> Void

    private var mode: AIOpenMode { center.mode(for: service) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                if mode != .web {
                    chip("剪贴板", symbol: "doc.on.clipboard", enabled: center.clipboardText != nil,
                         help: center.clipboardPreview.map { "带进输入框：\($0)" } ?? "剪贴板里没有文字",
                         label: "把剪贴板文字带进输入框") {
                        center.pasteClipboard()
                    }
                }
                ForEach(AIQuickAction.allCases, id: \.self) { action in
                    chip(action.title, symbol: nil, enabled: true,
                         help: helpText(action.title), label: "\(action.title)输入框或剪贴板里的文字") {
                        guard !AskTextView.keyWindowIsComposing else { return }
                        center.run(action)
                    }
                }
                Spacer(minLength: 0)
                promptMenu
            }
            statusLine
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    @ViewBuilder private var statusLine: some View {
        if let notice = center.notice {
            Text(notice)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.updatesFrequently)
        } else if let preview = center.clipboardPreview {
            Button {
                if mode != .web { center.pasteClipboard() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.clipboard")
                    Text("剪贴板：\(preview)")
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(mode == .web)
            .help(mode == .web ? "网页模式下，快捷指令会用剪贴板里的文字" : "点一下带进输入框")
            .accessibilityLabel("剪贴板预览：\(preview)")
        }
    }

    private var promptMenu: some View {
        Menu {
            if center.prompts.isEmpty {
                Text("还没有常用提示词")
            }
            ForEach(center.prompts) { prompt in
                Button(prompt.name) {
                    guard !AskTextView.keyWindowIsComposing else { return }
                    center.run(prompt)
                }
            }
            Divider()
            Button("管理常用提示词…") {
                guard let app = center.app else { return }
                close()
                SettingsWindow.shared.show(app: app, tab: "AI")
            }
        } label: {
            HStack(spacing: 3) {
                Text("常用")
                    .font(.system(size: 11.5, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.75))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("常用提示词：内容里的 {文本} 换成输入框或剪贴板里的文字")
        .accessibilityLabel("常用提示词")
    }

    private func helpText(_ title: String) -> String {
        switch mode {
        case .api: "\(title)输入框里的文字（空着时用剪贴板），直接发给 \(service.title)"
        case .web: "\(title)剪贴板里的文字：复制套好的提示词，到网页里粘贴"
        case .jump: "\(title)输入框里的文字（空着时用剪贴板），再打开 \(service.title)"
        }
    }

    private func chip(_ title: String, symbol: String?, enabled: Bool, help: String, label: String,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                }
                Text(title).font(.system(size: 11.5))
            }
            .foregroundStyle(.white.opacity(enabled ? 0.85 : 0.35))
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Capsule().fill(.white.opacity(0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(label)
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
                        .foregroundStyle(.white.opacity(0.9))
                    Text("回答会一个字一个字流出来，可以停、重试、复制、接着问。")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
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
                        placeholder: messages.isEmpty ? "问点什么… Enter 发送，Shift+Enter 换行"
                                                      : "继续问… Enter 发送，Shift+Enter 换行",
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
            .scrollIndicators(.automatic)
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
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: "#3B82F6")))
                    .accessibilityLabel("我：\(message.text)")
            }
        case .assistant:
            VStack(alignment: .leading, spacing: 6) {
                if !message.text.isEmpty || message.status == .streaming {
                    AIAnswerText(text: message.text, streaming: message.status == .streaming)
                }
                switch message.status {
                case .failed(let reason):
                    Label(reason, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: PaletteColor.orange.hex))
                        .fixedSize(horizontal: false, vertical: true)
                case .stopped:
                    Text(message.text.isEmpty ? "（已停止）" : "（已停止生成）")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.45))
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
                action("停止生成", symbol: "stop.circle") { center.stop() }
            } else {
                if !last.text.isEmpty {
                    action("复制", symbol: "doc.on.doc") { center.copy(last.text) }
                }
                action("重试", symbol: "arrow.clockwise") { center.retry() }
                action("新对话", symbol: "square.and.pencil") { center.clear() }
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
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.6))
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
                        .foregroundStyle(.white.opacity(0.92))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                case .code(let language, let body):
                    VStack(alignment: .leading, spacing: 4) {
                        if !language.isEmpty {
                            Text(language)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(body + (streaming && isLast ? "▍" : ""))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.9))
                                .textSelection(.enabled)
                                .fixedSize()
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.08)))
                }
            }
            if blocks.isEmpty && streaming {
                Text("▍")
                    .font(.system(size: 13.5))
                    .foregroundStyle(.white.opacity(0.8))
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
                        .foregroundStyle(.white.opacity(0.4))
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
                    .foregroundStyle(.black)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(.white.opacity(generating || AIAsk.question(center.draft) != nil ? 1 : 0.35)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(generating ? "停止生成" : "发送")
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .frame(height: 56)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.white.opacity(0.08)))
    }
}

// MARK: - 网页

private struct AIWebPane: View {
    var center: AIChatCenter
    var service: AIService

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(service.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                if center.isLoading(service.id) {
                    ProgressView().controlSize(.mini)
                }
                Spacer(minLength: 0)
                Button {
                    center.reload(service)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("刷新")
                .accessibilityLabel("刷新网页")
                Button {
                    center.openInBrowser(service)
                } label: {
                    Text("在浏览器打开 ↗")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("在浏览器打开当前网页")
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            if center.showsGoogleWarning(service.id) {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(AIWeb.googleWarning).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button("用浏览器打开") { center.openInBrowser(service) }
                        .buttonStyle(.plain)
                        .underline()
                }
                .font(.system(size: 11.5))
                .foregroundStyle(Color(hex: PaletteColor.orange.hex))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(hex: PaletteColor.orange.hex).opacity(0.12))
            }
            AIWebHost(center: center, service: service)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(white: 0.13)))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .overlay(alignment: .bottom) {
            if let credit = AIWeb.credit(service.homeURL) {
                Text(credit)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.35))
                    .padding(.bottom, 4)
            }
        }
        .padding(.bottom, 22)
    }
}

/// 把服务自己的 WKWebView 放进来。网页由 `AIChatCenter` 留着，换服务时只
/// 换挂上去的那一个，不重载。
private struct AIWebHost: NSViewRepresentable {
    var center: AIChatCenter
    var service: AIService

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard let web = center.webView(for: service) else {
            container.subviews.forEach { $0.removeFromSuperview() }
            return
        }
        guard web.superview !== container else { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        web.removeFromSuperview()
        web.frame = container.bounds
        web.autoresizingMask = [.width, .height]
        container.addSubview(web)
    }
}

// MARK: - 跳转

/// 跳转模式：和原来的提问面板一样，能带问题的带着问题开浏览器，其余复制
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
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.08)))
            HStack(spacing: 10) {
                Button("只打开 \(service.title)") { center.openService() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.65))
                Spacer(minLength: 0)
                Button {
                    guard !AskTextView.keyWindowIsComposing else { return }
                    center.jump()
                } label: {
                    Text(AIAsk.buttonTitle(for: service))
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(Capsule().fill(Color(hex: AIGlyph.dotHex)
                            .opacity(AIAsk.question(center.draft) != nil ? 1 : 0.35)))
                }
                .buttonStyle(.plain)
                .disabled(AIAsk.question(center.draft) == nil)
            }
            Text(center.jumpHint ?? (service.supportsAsk
                 ? "跳转：Enter 提交，会在浏览器打开 \(service.title) 并带上问题。"
                 : "跳转：Enter 提交，\(service.title) 不支持带问题打开，会先复制问题。"))
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(center.jumpHint == nil ? 0.5 : 0.8))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text("想直接在这里对话：到“设置 ▸ AI”把它改成网页或 API。")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
    }
}
