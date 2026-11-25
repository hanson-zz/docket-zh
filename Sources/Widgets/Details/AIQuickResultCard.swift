import AppKit
import SwiftUI

/// 快捷结果卡片上的按钮交给控制器做的事。
struct AIQuickResultActions {
    var close: @MainActor () -> Void
    var expand: @MainActor () -> Void
    var followUp: @MainActor () -> Void
    /// 正文高度变了，窗口跟着改高（180 到 300）。
    var resize: @MainActor () -> Void
    var settings: @MainActor () -> Void
}

/// 小组件里用 API 提问后，刘海下方自动长出的快捷结果卡片（备用浮窗也是它，只是不带探头）。
///
/// 照效果图：约 420 宽，Liquid Glass（`ReadableGlass`），浅深两套，不铺固定深色底。
/// 贴在刘海下时，用户选的吉祥物（没解锁 Pro 时是小熊猫）从刘海里探出头，趴在卡片上沿，
/// 减弱动态效果时直接在位。头部：服务字牌 + 服务名 + 状态胶囊（正在思考 / 正在回答 /
/// 已完成 / 失败），右边固定、「…」、关闭三个圆按钮。正文是一块浅一档的圆角玻璃，回答
/// 第一行是标题时加粗；流式回答一边来一边显示，长了在卡片里滚动。底部三个等宽胶囊：
/// 复制回答、继续追问、展开；失败时是重试、展开。
struct AIQuickResultCard: View {
    var center: AIChatCenter
    var model: AIQuickResultModel
    var actions: AIQuickResultActions

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    private static let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
    private static let bodyShape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    private var serviceID: String { model.serviceID ?? "" }
    private var service: AIService? { center.service(serviceID) }
    private var title: String { service?.title ?? "AI" }
    private var reply: AIChatMessage? { AIQuickResultModel.reply(in: center.messages(serviceID)) }
    private var phase: AIQuickResultPhase {
        AIQuickResult.phase(status: reply?.status, text: reply?.text ?? "")
    }
    private var text: String { reply?.text ?? "" }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                if model.withMascot { Color.clear.frame(height: AINotchLayout.cardGap) }
                card
                    .frame(height: model.cardHeight)
                    .scaleEffect(appeared ? 1 : 0.94, anchor: .top)
                    .opacity(appeared ? 1 : 0)
                Spacer(minLength: 0)
            }
            if model.withMascot {
                mascot
            }
        }
        .frame(width: AIQuickResult.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear(perform: enter)
        .onChange(of: model.session) { _, _ in
            appeared = false
            Task { @MainActor in enter() }
        }
        .onChange(of: model.cardHeight) { _, _ in actions.resize() }
        // 答完后按设置倒计时自动收起；固定、指针在卡片上、失败时不倒计时（指针离开后重新计）。
        .task(id: collapseKey) {
            guard let delay = AIQuickResult.collapseDelay(center.settings.afterAnswer, phase: phase,
                                                          pinned: model.pinned, hovering: model.hovering)
            else { return }
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            actions.close()
        }
    }

    private var collapseKey: String {
        "\(model.session)|\(phase.title)|\(model.pinned)|\(model.hovering)|\(center.settings.afterAnswer.rawValue)"
    }

    /// 从刘海下面轻轻长出来；减弱动态效果时直接出现。
    private func enter() {
        if reduceMotion {
            appeared = true
        } else {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) { appeared = true }
        }
    }

    // MARK: 卡片

    private var card: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, model.withMascot ? AIQuickResult.mascotInset : 0)
            Rectangle()
                .fill(.panelSeparator)
                .frame(height: 0.5)
                .padding(.horizontal, 16)
            answerArea
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .frame(maxHeight: .infinity, alignment: .top)
            footer
        }
        .background { ReadableGlass(shape: Self.shape) }
        .clipShape(Self.shape)
        // 生成中（思考、回答中）沿边流光，答完或失败时淡出。叠在玻璃和裁切外层。
        .edgeBeam(active: !phase.isFinished, shape: .rounded(24))
        .contentShape(Self.shape)
        .onHover { model.hovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tr("\(title) 的回答"))
    }

    // MARK: 头部

    private var header: some View {
        HStack(spacing: 10) {
            AIGlyph(initial: service?.initial ?? "AI", size: 28, style: .panel)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.panelPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .accessibilityAddTraits(.isHeader)
            statusPill
            Spacer(minLength: 6)
            pinButton
            moreMenu
            circleButton("xmark", label: tr("关闭"), action: actions.close)
        }
        .padding(.horizontal, 16)
        .frame(height: AIQuickResult.headerHeight)
    }

    private var statusPill: some View {
        let (ink, fill): (Color, Color) = {
            switch phase {
            case .done:
                let green = Color(hex: PaletteColor.green.hex)
                return (green.panelReadable, green.opacity(0.14))
            case .failed:
                let red = Color(hex: PaletteColor.red.hex)
                return (red.panelReadable, red.opacity(0.14))
            case .thinking, .answering:
                return (Color.panelSecondary, Color.panelFill)
            }
        }()
        return HStack(spacing: 5) {
            switch phase {
            case .done:
                Image(systemName: "checkmark.circle.fill").font(.system(size: 12, weight: .semibold))
            case .failed:
                Image(systemName: "xmark.circle.fill").font(.system(size: 12, weight: .semibold))
            case .thinking, .answering:
                AIBouncingDots(dot: 3).fixedSize()
            }
            Text(phase.title)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(Capsule().fill(fill))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(phase.title)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var pinButton: some View {
        Button {
            model.pinned.toggle()
        } label: {
            Image(systemName: model.pinned ? "pin.fill" : "pin")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(model.pinned ? Color.panelPrimary : Color.panelSecondary)
                .rotationEffect(.degrees(model.pinned ? 0 : 35))
                .frame(width: 28, height: 28)
                .background(Circle().fill(model.pinned ? Color.panelSelected : Color.panelFill))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(model.pinned ? tr("已固定：不自动收起，点外面也不收") : tr("固定：不自动收起，点外面也不收"))
        .accessibilityLabel(model.pinned ? tr("取消固定") : tr("固定"))
    }

    /// 「…」：复制、重新生成、在完整对话中打开、设置。
    private var moreMenu: some View {
        Menu {
            Button(tr("复制", context: "copy")) { center.copy(text) }
                .disabled(text.isEmpty || !phase.isFinished)
            Button(tr("重新生成")) { center.retry(serviceID) }
                .disabled(center.isGenerating(serviceID))
            Button(tr("在完整对话中打开")) { actions.expand() }
            Divider()
            Button(tr("设置…")) { actions.settings() }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelSecondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.panelFill))
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(tr("更多"))
        .accessibilityLabel(tr("更多"))
    }

    private func circleButton(_ symbol: String, label: String, action: @escaping @MainActor () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelSecondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.panelFill))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    // MARK: 正文

    /// 正文在一块浅一档的圆角玻璃里，量出来的高度交给控制器定卡片高度；超过 300 的卡片
    /// 高度时在里面滚动，流式回答跟着往下走。
    private var answerArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    answerContent
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    model.bodyHeight = height
                }
            }
            .scrollIndicators(.automatic)
            .background { ReadableGlass(shape: Self.bodyShape) }
            .clipShape(Self.bodyShape)
            .onChange(of: text) { _, _ in
                guard phase == .answering else { return }
                proxy.scrollTo("end", anchor: .bottom)
            }
        }
    }

    @ViewBuilder private var answerContent: some View {
        switch phase {
        case .thinking:
            // 还没出第一个字：「ChatGPT 正在思考」加三个小点（减弱动态效果时不跳）。
            HStack(spacing: 6) {
                Text(AINotchChatText.thinking(service?.title))
                    .font(.system(size: 14))
                    .foregroundStyle(.panelSecondary)
                AIBouncingDots(dot: 4)
                    .fixedSize()
            }
            .accessibilityElement(children: .combine)
        case .failed(let reason):
            VStack(alignment: .leading, spacing: 6) {
                Label(reason, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: PaletteColor.red.hex).panelReadable)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !text.isEmpty {
                    AIAnswerText(text: text, streaming: false)
                }
            }
        case .answering, .done:
            let parts = AIQuickResult.splitTitle(text)
            if let heading = parts.title {
                Text(heading)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.panelPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .accessibilityAddTraits(.isHeader)
            }
            AIAnswerText(text: parts.body, streaming: phase == .answering)
        }
    }

    // MARK: 底部

    /// 三个等宽胶囊。答完：复制回答、继续追问、展开；失败：重试、展开；生成中只有展开能点。
    private var footer: some View {
        HStack(spacing: 10) {
            if case .failed = phase {
                pill(tr("重试"), symbol: "arrow.clockwise", enabled: !center.isGenerating(serviceID)) {
                    center.retry(serviceID)
                }
            } else {
                pill(tr("复制回答"), symbol: "doc.on.doc", enabled: phase == .done && !text.isEmpty) {
                    center.copy(text)
                }
                pill(tr("继续追问"), symbol: "bubble.left", enabled: phase.isFinished, action: actions.followUp)
            }
            pill(tr("展开"), symbol: "arrow.up.left.and.arrow.down.right", enabled: true, action: actions.expand)
        }
        .padding(.horizontal, 14)
        .frame(height: AIQuickResult.footerHeight)
    }

    private func pill(_ label: String, symbol: String, enabled: Bool,
                      action: @escaping @MainActor () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .accessibilityHidden(true)
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(enabled ? Color.panelPrimary : Color.panelSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(Capsule().fill(.panelFill))
            .overlay { Capsule().strokeBorder(.panelSeparator, lineWidth: 0.5) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    // MARK: 探头的吉祥物

    /// 用户选的吉祥物（没解锁 Pro 时是小熊猫）从刘海里探出头，趴在卡片上沿。用的是刘海小岛
    /// 收起时那颗小头（`NotchMascotArt.peek`）；没有这张图时用小熊猫头像。减弱动态效果时不升起。
    @ViewBuilder private var mascot: some View {
        let chosen = FocusMascot.of(TimerStateProvider.shared.state, unlocked: ProAccess.isUnlocked)
        let rise: CGFloat = (appeared || reduceMotion) ? 0 : -14
        Group {
            if case .image(let name) = NotchMascotArt.peek(chosen, exists: { NotchIslandHanging.exists($0) }),
               let image = NotchIslandHanging.image(named: name) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(height: AIQuickResult.mascotHeight)
            } else {
                AIPandaAvatar(size: 30)
                    .padding(.top, 4)
            }
        }
        .offset(y: rise - 6)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
