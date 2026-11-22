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
                AIPandaAvatar(size: 14)
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

/// 刘海下沿往下长出的那一块胶囊：黑色、底部圆角，和刘海连成一体。悬停时是收起态
/// 「● AI 助手」，回答生成中是「ChatGPT 正在思考」加三个跳动的小点（面板收起也照样
/// 答完），小熊猫从胶囊下沿探出头来。宽度和刘海小岛同一套规则（`AINotchLayout.stripWidth`）：
/// 放得进刘海就和刘海同宽，放不下每侧最多加 70，字再长就截断；胶囊整个在菜单栏
/// 下面，不盖住右边的菜单栏图标。打开“减少动态效果”时不做伸缩、小熊猫不升起、
/// 小点不跳，直接显示或隐藏。
struct AINotchStripView: View {
    var entry: AINotchEntryModel
    var panel: AINotchPanelModel
    var center: AIChatCenter

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let shape = UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14,
                                                      style: .continuous)
    /// 探头的小熊猫：刘海小岛收起时左边那颗小脑袋，没有图时用站着的小熊猫。
    private static let peek = Bundle.main.image(forResource: NotchHangingPanda.peekImageName)
    /// 小熊猫图的高度和顶边位置：图里的头在 31%～80% 高，放在这里头顶刚好接着字那一行，
    /// 下巴被胶囊下沿裁掉一点，像从下沿探出来。
    private static let peekHeight: CGFloat = 32
    private static let peekTop: CGFloat = 14

    var body: some View {
        let content = AINotchLayout.stripContent(visible: entry.visible, panelOpen: panel.isOpen || panel.quickCard,
                                                 hovering: entry.hovering, generating: center.isGenerating)
        let notchWidth = entry.entry.frame.width
        let width = content.map { AINotchLayout.stripWidth($0, service: center.generatingTitle, notchWidth: notchWidth) }
            ?? notchWidth
        let height = AINotchLayout.stripHeight
        return VStack(spacing: 0) {
            capsule(content)
                .frame(width: width, height: height)
                .background(Self.shape.fill(.black))
                .clipShape(Self.shape)
                .frame(height: content == nil ? 0 : height, alignment: .bottom)
                .clipped()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.84), value: content)
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.84), value: width)
        .environment(\.colorScheme, .dark)
        .accessibilityHidden(true)
    }

    private func capsule(_ content: AINotchStripContent?) -> some View {
        ZStack(alignment: .top) {
            mascot(shown: content != nil)
            HStack(spacing: content == .thinking ? AINotchLayout.stripDotsGap : AINotchLayout.stripDotGap) {
                switch content {
                case .thinking?:
                    Text(AINotchChatText.thinking(center.generatingTitle))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    AIBouncingDots(dot: 3)
                        .fixedSize()
                case .hint?:
                    Circle()
                        .fill(Color(hex: AIGlyph.dotHex))
                        .frame(width: AINotchLayout.stripDot, height: AINotchLayout.stripDot)
                    Text(AINotchChatText.entryTitle)
                        .lineLimit(1)
                case nil:
                    EmptyView()
                }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, AINotchLayout.stripPadding)
            .frame(maxWidth: .infinity)
            .frame(height: AINotchLayout.stripTextRow)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// 小熊猫从下沿升起来；减弱动态效果时直接在位。
    @ViewBuilder private func mascot(shown: Bool) -> some View {
        let rise: CGFloat = (shown || reduceMotion) ? 0 : 12
        Group {
            if let image = Self.peek {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(height: Self.peekHeight)
            } else {
                AIPandaAvatar(size: AINotchLayout.stripPandaSize)
                    .padding(.top, 6)
            }
        }
        .offset(y: Self.peekTop + rise)
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

// MARK: - 展开的对话卡片

/// 点刘海展开的对话卡片，约 400 x 520，放在菜单栏下面（和专注卡片一样空 6），
/// 不接在刘海上，也不往两侧盖住菜单栏图标。
///
/// 底色：液态玻璃，跟随设置里的浅色 / 深色，带字的底一律 `ReadableGlass`。
/// 文字用 PanelColors 语义色，读的字至少 panelSecondary。
///
/// 层级：顶上一行是小熊猫 + 「AI 助手」（下面一行小字是当前服务，几个服务时点开换）
/// + API / 网页 / App 分段控件 + 图钉、收起；中间是对话、网页或 App 方式；API 对话
/// 底部是「+」「继续追问……」「↑」输入条，「+」里是快捷指令和常用提示词。
struct AIChatPanelView: View {
    var center: AIChatCenter
    var model: AINotchPanelModel
    var close: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var choosingService = false

    /// 顶栏、网页四周统一的边距。
    static let inset: CGFloat = 14
    /// 实心蓝底白字（App 方式的按钮）：白字对比度 5.2，过 4.5。
    static let solidBlueHex = "#2563EB"

    private static let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)

    var body: some View {
        content
            .frame(width: AINotchLayout.panelSize.width, height: AINotchLayout.panelSize.height)
            .background { ReadableGlass(shape: Self.shape) }
            .clipShape(Self.shape)
            .scaleEffect(appeared ? 1 : 0.94, anchor: .top)
            .opacity(appeared ? 1 : 0)
            .onAppear(perform: enter)
            .onChange(of: model.session) { _, _ in
                appeared = false
                // 小组件刚交过来的那句（「已复制，请粘贴」）留着，其余旧提示清掉。
                if center.holdNoticeOnce {
                    center.holdNoticeOnce = false
                } else {
                    center.notice = nil
                }
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

    /// 从菜单栏下面轻轻长出来；减少动态效果时直接出现。
    private func enter() {
        if reduceMotion {
            appeared = true
        } else {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) { appeared = true }
        }
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: 0) {
            header
            Rectangle()
                .fill(.panelSeparator)
                .frame(height: 0.5)
                .padding(.horizontal, Self.inset)
            if let text = noticeText {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Self.inset)
                    .padding(.top, 8)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            Group {
                if let service = center.current {
                    switch center.mode(for: service) {
                    case .api: AIAPIChatPane(center: center, service: service, close: close)
                    case .web: AIWebPane(center: center, service: service, close: close)
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

    /// 顶栏下面那一句提示；空白的当没有。
    private var noticeText: String? {
        if case .notice(let text) = AIPromptStrip.statusLine(notice: center.notice, clipboardPreview: nil) {
            return text
        }
        return nil
    }

    private var header: some View {
        HStack(spacing: 10) {
            AIPandaAvatar(size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(tr("AI 助手"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                serviceLine
            }
            .layoutPriority(1)
            Spacer(minLength: 6)
            if let service = center.current {
                AIModeSegments(center: center, service: service)
            }
            pinButton
            headerButton("xmark", help: tr("收起"), label: tr("收起对话面板"), action: close)
        }
        .padding(.horizontal, Self.inset)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    /// 「AI 助手」下面那一行小字：当前服务；几个服务时点开换。
    @ViewBuilder private var serviceLine: some View {
        if let service = center.current {
            if AINotchPanelHeader.canSwitchService(serviceCount: center.services.count) {
                Button {
                    choosingService.toggle()
                } label: {
                    HStack(spacing: 3) {
                        Text(service.title)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if center.isGenerating(service.id) {
                            Circle().fill(Color(hex: AIGlyph.dotHex)).frame(width: 5, height: 5)
                        }
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $choosingService, arrowEdge: .bottom) { serviceList }
                .help(tr("换一个服务"))
                .accessibilityLabel(tr("当前服务 \(service.title)，点按换一个"))
            } else {
                Text(service.title)
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(1)
            }
        }
    }

    private var serviceList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(center.services) { service in
                let selected = service.id == center.current?.id
                Button {
                    center.select(service.id)
                    choosingService = false
                } label: {
                    HStack(spacing: 8) {
                        AIGlyph(initial: service.initial, size: 20, style: .panel)
                        Text(service.title)
                            .font(.system(size: 13))
                            .foregroundStyle(.panelPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 12)
                        Text(center.mode(for: service).title)
                            .font(.system(size: 13))
                            .foregroundStyle(.panelSecondary)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.panelPrimary)
                            .opacity(selected ? 1 : 0)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(selected ? tr("\(service.title)，当前") : tr("切换到 \(service.title)"))
            }
        }
        .padding(6)
        .frame(minWidth: 200)
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

/// 顶栏的 API / 网页 / App 分段控件：选中的一段是凸起的浅底，不用大面积强调色。
/// 不能选的一段（没填 API 密钥、没有网页版）字淡一档，悬停说明为什么。
private struct AIModeSegments: View {
    var center: AIChatCenter
    var service: AIService

    var body: some View {
        let current = center.mode(for: service)
        HStack(spacing: 2) {
            ForEach(center.modeOptions(for: service), id: \.mode) { option in
                let selected = option.mode == current
                Button {
                    center.setMode(option.mode, for: service)
                } label: {
                    Text(option.mode.title)
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Color.panelPrimary : Color.panelSecondary)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background {
                            if selected { Capsule().fill(.panelRaised).panelLift() }
                        }
                        .contentShape(Capsule())
                        .opacity(option.available || selected ? 1 : 0.55)
                }
                .buttonStyle(.plain)
                .disabled(!option.available)
                .help(option.available ? center.modeLabel(for: service)
                      : (AIModeChoice.unavailableReason(option.mode) ?? ""))
                .accessibilityLabel(option.mode.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(.panelFill))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tr("打开方式"))
    }
}

/// 「+」弹出的快捷指令和常用提示词（同以前顶栏下面那一排，`AIPromptChipBar`）；
/// API 对话里还有「新对话」。文字先取输入框，空着时取剪贴板。
private struct AIQuickMenuButton: View {
    var center: AIChatCenter
    var service: AIService
    var close: () -> Void

    @State private var open = false

    private var mode: AIOpenMode { center.mode(for: service) }

    var body: some View {
        Button {
            open.toggle()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelSecondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(.panelRaised))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .top) { menu }
        .help(tr("快捷指令与提示词"))
        .accessibilityLabel(tr("快捷指令和常用提示词"))
    }

    private var menu: some View {
        VStack(alignment: .leading, spacing: 10) {
            AIPromptChipBar(
                hasInput: mode != .web,
                clipboardPreview: center.clipboardPreview,
                notice: nil,
                prompts: center.prompts,
                actionHelp: { helpText($0.title) },
                clipboardHelp: mode == .web ? tr("网页模式下，快捷指令会用剪贴板里的文字") : tr("点一下带进输入框"),
                paste: { center.pasteClipboard(); open = false },
                runAction: { center.run($0); open = false },
                runPrompt: { center.run($0); open = false },
                managePrompts: {
                    open = false
                    guard let app = center.app else { return }
                    close()
                    SettingsWindow.shared.show(app: app, tab: "AI")
                })
            if mode == .api, !center.messages(service.id).isEmpty {
                Button {
                    center.clear()
                    open = false
                } label: {
                    Label(tr("新对话"), systemImage: "square.and.pencil")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.panelPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("新对话"))
            }
        }
        .padding(12)
        .frame(width: 380, alignment: .leading)
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

    @State private var focusToken = 0

    private var messages: [AIChatMessage] { center.messages(service.id) }
    private var generating: Bool { center.isGenerating(service.id) }

    /// 对话区占满中间；回答下面是复制、继续追问（和最后一条的重新生成），停止就是
    /// 发送键（生成中变成停止）。
    var body: some View {
        VStack(spacing: 0) {
            if messages.isEmpty {
                VStack(spacing: 8) {
                    Text(AINotchChatText.inputPlaceholder(hasMessages: false))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.panelPrimary)
                    Text("回答会一个字一个字流出来，每条回答下面可以复制、继续追问。")
                        .font(.system(size: 13))
                        .foregroundStyle(.panelSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 30)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                transcript
            }
            AIChatInput(center: center, service: service, generating: generating,
                        placeholder: AINotchChatText.inputPlaceholder(hasMessages: !messages.isEmpty),
                        focusToken: focusToken,
                        submit: { center.send() }, stop: { center.stop() }, close: close)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .padding(.top, 6)
        }
        // 快捷结果卡片的「继续追问」：打开这个面板后把光标放进输入条。
        .onChange(of: center.focusRequest) { _, _ in focusToken += 1 }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(messages) { message in
                        row(message, isLast: message.id == messages.last?.id).id(message.id)
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

    /// 我的提问：靠右的浅色气泡，前面一个人像头像。
    /// 回答：靠左的气泡，前面是小熊猫头像，按钮在气泡里面的底部。
    @ViewBuilder private func row(_ message: AIChatMessage, isLast: Bool) -> some View {
        switch message.role {
        case .user:
            HStack(alignment: .top, spacing: 8) {
                Spacer(minLength: 40)
                Image(systemName: "person.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelSecondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(.panelRaised).panelLift())
                    .accessibilityHidden(true)
                Text(message.text)
                    .font(.system(size: 13.5))
                    .foregroundStyle(.panelPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.panelRaised).panelLift())
                    .accessibilityLabel(tr("我：\(message.text)"))
            }
        case .assistant:
            HStack(alignment: .top, spacing: 8) {
                AIPandaAvatar(size: 28)
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)
                answer(message, isLast: isLast)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.panelFill))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.panelSeparator, lineWidth: 0.5)
                    }
            }
        }
    }

    @ViewBuilder private func answer(_ message: AIChatMessage, isLast: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if message.status == .streaming && message.text.isEmpty {
                // API 流式回答还没到第一个字：「DeepSeek 正在思考」加三个小点，收到内容就换成回答。
                HStack(spacing: 6) {
                    Text(AINotchChatText.thinking(service.title))
                        .font(.system(size: 13))
                        .foregroundStyle(.panelSecondary)
                    AIBouncingDots(dot: 4)
                }
                .accessibilityElement(children: .combine)
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
            answerActions(message, isLast: isLast)
        }
    }

    /// 回答下面的复制、继续追问、重新生成。哪些出现见 `AINotchChatText.answerActions`。
    @ViewBuilder private func answerActions(_ message: AIChatMessage, isLast: Bool) -> some View {
        let actions = AINotchChatText.answerActions(mode: .api, isLast: isLast, generating: generating,
                                                    streaming: message.status == .streaming,
                                                    hasText: !message.text.isEmpty)
        if !actions.isEmpty {
            HStack(spacing: 8) {
                ForEach(actions, id: \.self) { action in
                    switch action {
                    case .copy:
                        pill(tr("复制", context: "copy"), symbol: "doc.on.doc") { center.copy(message.text) }
                    case .followUp:
                        pill(tr("继续追问"), symbol: "bubble.left") { focusToken += 1 }
                    case .regenerate:
                        Button { center.retry() } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.panelSecondary)
                                .frame(width: 26, height: 26)
                                .background(Circle().fill(.panelRaised))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help(tr("重新生成"))
                        .accessibilityLabel(tr("重新生成"))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
    }

    private func pill(_ title: String, symbol: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Label(title, systemImage: symbol)
                .labelStyle(.titleAndIcon)
                .font(.system(size: 13))
                .foregroundStyle(.panelPrimary)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Capsule().fill(.panelRaised))
                .contentShape(Capsule())
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

/// 卡片底部的输入条：「+」（快捷指令和常用提示词）、输入框、「↑」发送。Enter 发送，
/// Shift+Enter 换行，输入法选字时 Enter 只确认选字。生成中右边的按钮变成停止。
/// `focusToken` 变了就把光标放进输入框（回答下面的「继续追问」）。
private struct AIChatInput: View {
    var center: AIChatCenter
    var service: AIService
    var generating: Bool
    var placeholder: String
    var focusToken: Int
    var submit: () -> Void
    var stop: () -> Void
    var close: () -> Void

    private var draft: Binding<String> {
        Binding(get: { center.draft }, set: { center.draft = $0 })
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            AIQuickMenuButton(center: center, service: service, close: close)
            ZStack(alignment: .topLeading) {
                AskTextEditor(text: draft, onSubmit: { if !generating { submit() } }, onCancel: close,
                              focusToken: focusToken)
                    .frame(height: 36)
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
            .padding(.top, 12)
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
                    .frame(width: 30, height: 30)
            }
            // 能发或正在生成（停止键）时实心主文字色；空着时中性灰底 + 次级字色。不用发光的强调色。
            .buttonStyle(PanelSolidButtonStyle(fill: Color.panelPrimary, ink: Color.panelOnPrimary, shape: Circle(),
                                               enabled: generating || AIAsk.question(center.draft) != nil))
            .accessibilityLabel(generating ? tr("停止生成") : tr("发送"))
        }
        .padding(.leading, 8)
        .padding(.trailing, 8)
        .frame(height: 50)
        .background(Capsule().fill(.panelFill))
        .overlay { Capsule().strokeBorder(.panelSeparator, lineWidth: 0.5) }
    }
}

// MARK: - 网页

private struct AIWebPane: View {
    var center: AIChatCenter
    var service: AIService
    var close: () -> Void

    @Environment(\.colorScheme) private var scheme

    /// 网页的圆角：卡片圆角 24 往里收一个边距，和卡片同心。
    private static let corner: CGFloat = 12

    /// 网页本身圆角内嵌；下面一行是「+」（快捷指令，复制套好的提示词到网页里粘贴）、
    /// 网页由谁提供的小字、刷新和在浏览器打开。
    var body: some View {
        VStack(spacing: 8) {
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
            HStack(spacing: 8) {
                AIQuickMenuButton(center: center, service: service, close: close)
                if let credit = AIWeb.credit(service.homeURL) {
                    Text(credit)
                        .font(.system(size: 13))
                        .foregroundStyle(.panelSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 4)
                if center.isLoading(service.id) {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 28, height: 28)
                        .accessibilityLabel(tr("网页载入中"))
                } else {
                    smallButton("arrow.clockwise", help: tr("刷新"), label: tr("刷新网页")) { center.reload(service) }
                }
                smallButton("arrow.up.right.square", help: tr("在浏览器打开"),
                            label: tr("在浏览器打开当前网页")) { center.openInBrowser(service) }
            }
        }
        .padding(.horizontal, AIChatPanelView.inset)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private func smallButton(_ symbol: String, help: String, label: String,
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
                    // 字要短（「打开 豆包」「去网页问」），会做什么写在下面的提示句里。
                    Text(AIAsk.buttonTitle(mode: .jump, service: service,
                                           appInstalled: AIServiceOpener.installedApp(service) != nil))
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                }
                // 可用实心蓝白字；空着时中性灰底 + 次级字色（PanelSolidButtonStyle）。
                .buttonStyle(PanelSolidButtonStyle(fill: Color(hex: AIChatPanelView.solidBlueHex)))
                .fixedSize()
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
