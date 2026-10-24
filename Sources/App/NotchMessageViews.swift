import AppKit
import SwiftUI

// MARK: - 消息卡

/// 刘海下的液态玻璃消息卡，照效果图 design/notch-message-*.png：
///
/// - 顶上一行 App 图标、App 名，右边「还有 N 条」（关了预览时写时间）；
/// - 头像（拿不到用名字第一个字的彩色圆）、发件人、时间、两行预览；关了预览时头像
///   换成 App 的大图标，写「收到一条消息」和一句说明；
/// - 按钮「回复 / 稍后 / 打开 ↗」，WhatsApp、微信的回复是跳转，写「回复 ↗」；关了预览
///   只有「稍后 / 打开 ↗」；
/// - 信息点「回复」在卡片里展开输入框，回车发送、Esc 收起；
/// - 底下一行小熊猫和一句话：下一条是谁、怎么打开预览、回复的提示或没发出去的原因。
///
/// 卡片跟随浅色 / 深色（液态玻璃，字用 PanelColors 语义色，读的字至少 panelSecondary）。
/// 接在刘海下面时顶上留一条和刘海同宽、向下渐隐的黑色接住硬件刘海（同 AI 刘海对话）。
/// 多条时后面露出两道叠着的玻璃边。
struct NotchMessageCardView: View {
    @Bindable var model: NotchMessageModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            if model.expanded, let message = model.inbox.current {
                NotchMessageCard(model: model, message: message)
                    .padding(.horizontal, NotchMessageController.sideInset)
                    .scaleEffect(x: appeared ? 1 : 0.62, y: appeared ? 1 : 0.12, anchor: .top)
                    .opacity(appeared ? 1 : 0)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear(perform: enter)
        .onChange(of: model.session) { _, _ in
            appeared = false
            Task { @MainActor in enter() }
        }
        .onChange(of: model.expanded) { _, expanded in
            if expanded { return }
            withAnimation(reduceMotion ? nil : .easeIn(duration: 0.18)) { appeared = false }
        }
    }

    /// 从刘海往下长出来；减少动态效果时直接出现。
    private func enter() {
        guard model.expanded else { return }
        if reduceMotion {
            appeared = true
        } else {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.8)) { appeared = true }
        }
    }
}

private struct NotchMessageCard: View {
    @Bindable var model: NotchMessageModel
    var message: NotchMessage

    @Environment(\.colorScheme) private var scheme
    @FocusState private var fieldFocused: Bool

    /// 实心蓝底白字（发送钮）：白字对比度 5.2。
    private static let solidBlue = Color(hex: "#2563EB")

    private var shape: UnevenRoundedRectangle {
        let top: CGFloat = model.fromNotch ? 12 : 22
        return UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: 26,
                                      bottomTrailingRadius: 26, topTrailingRadius: top, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if message.previewHidden { hiddenBody } else { senderBody }
            buttons.padding(.top, 14)
            if model.replying, message.canReplyInline { replyField.padding(.top, 10) }
            if let footer = footerText { footerRow(footer).padding(.top, 12) }
        }
        .padding(.top, model.fromNotch ? AINotchLayout.notchBlendHeight + 8 : 14)
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
        .frame(width: NotchMessagePlacement.cardWidth, alignment: .leading)
        .background(alignment: .bottom) { stack }
        .background { surface }
        .contentShape(shape)
        .onHover { inside in model.hover?(inside) }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
            model.heightChanged?(height)
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: 底

    private var surface: some View {
        ZStack(alignment: .topLeading) {
            NotchMessageGlass(shape: shape)
            if let blend = model.notchBlend {
                NotchMessageBlend()
                    .frame(width: blend.width, height: blend.height)
                    .offset(x: blend.minX, y: blend.minY)
            }
        }
        .clipShape(shape)
        .overlay { shape.stroke(Color.panelStroke, lineWidth: 0.6) }
        .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.16), radius: 18, y: 8)
    }

    /// 后面叠着的一两张：往下错开、变窄，露出玻璃边。
    @ViewBuilder private var stack: some View {
        let count = min(2, model.inbox.remainingCount)
        if count > 0 {
            ZStack(alignment: .bottom) {
                if count > 1 {
                    NotchMessageGlass(shape: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .frame(height: 50)
                        .padding(.horizontal, 32)
                        .offset(y: 20)
                }
                NotchMessageGlass(shape: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .frame(height: 50)
                    .padding(.horizontal, 16)
                    .offset(y: 10)
            }
            .shadow(color: .black.opacity(scheme == .dark ? 0.3 : 0.12), radius: 10, y: 4)
            .accessibilityHidden(true)
        }
    }

    // MARK: 顶上一行

    private var header: some View {
        HStack(spacing: 8) {
            NotchAppIcon(app: message.app, size: 22)
            Text(message.app.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelSecondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let remaining = NotchMessageText.remaining(model.inbox.remainingCount) {
                Text(remaining)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.panelPrimary)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Capsule().fill(.panelFill))
                    .fixedSize()
            } else if message.previewHidden {
                timeText
            }
        }
    }

    private var timeText: some View {
        TimelineView(.periodic(from: .now, by: 30)) { tick in
            Text(NotchMessageText.time(message.date, now: tick.date))
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(.panelSecondary)
                .fixedSize()
        }
    }

    // MARK: 发件人和预览

    private var senderBody: some View {
        HStack(alignment: .top, spacing: 12) {
            NotchAvatar(message: message, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(message.sender ?? "")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.panelPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 6)
                    timeText
                }
                Text(message.preview ?? "")
                    .font(.system(size: 14))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 12)
    }

    private var hiddenBody: some View {
        HStack(alignment: .center, spacing: 12) {
            NotchAppIcon(app: message.app, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(NotchMessageText.hiddenTitle)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.panelPrimary)
                Text(NotchMessageText.hiddenDetail(message.app))
                    .font(.system(size: 14))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 12)
    }

    // MARK: 按钮

    private struct Choice: Identifiable {
        var id: String { title }
        var title: String
        var action: NotchMessageAction
        var selected = false
    }

    private var choices: [Choice] {
        let later = Choice(title: tr("稍后", context: "later"), action: .later)
        let open = Choice(title: NotchMessageText.jump(tr("打开")), action: .open)
        if message.previewHidden { return [later, open] }
        if message.canReplyInline {
            return [Choice(title: tr("回复"), action: .reply, selected: model.replying), later, open]
        }
        return [Choice(title: NotchMessageText.jump(tr("回复")), action: .reply), later, open]
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            ForEach(choices) { choice in
                Button { model.act?(choice.action) } label: {
                    Text(choice.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.panelPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(Capsule().fill(choice.selected ? Color.panelSelected : Color.panelFill))
                        .overlay(Capsule().strokeBorder(Color.panelStroke, lineWidth: 0.5))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: 回复框

    private var replyStroke: Color {
        scheme == .dark ? Color(red: 140 / 255, green: 170 / 255, blue: 1).opacity(0.6)
            : Self.solidBlue.opacity(0.6)
    }

    private var canSend: Bool {
        !model.sending && NotchMessageReply.normalized(model.draft) != nil
    }

    private var replyField: some View {
        HStack(spacing: 8) {
            TextField(tr("回复\(message.sender ?? "")"), text: $model.draft)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(.panelPrimary)
                .focused($fieldFocused)
                .disabled(model.sending)
                .onSubmit { model.act?(.send) }
            Button { model.act?(.send) } label: {
                ZStack {
                    Circle().fill(Self.solidBlue.opacity(canSend || model.sending ? 1 : 0.45))
                    if model.sending {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel(tr("发送"))
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .frame(height: 40)
        .background(Capsule().fill(.panelRaised).panelLift())
        .overlay(Capsule().strokeBorder(replyStroke, lineWidth: 1.2))
        .onAppear {
            Task { @MainActor in fieldFocused = true }
        }
    }

    // MARK: 底下一行

    private var footerText: String? {
        if let notice = model.notice { return notice }
        if model.replying, message.canReplyInline {
            return model.showPermissionHint ? NotchMessageReply.permissionHint : tr("回车发送，Esc 收起")
        }
        if message.previewHidden { return NotchMessageText.hiddenHint(message.app) }
        if model.inbox.remainingCount > 0, let next = model.inbox.next { return NotchMessageText.nextLine(next) }
        return nil
    }

    private func footerRow(_ text: String) -> some View {
        HStack(alignment: .center, spacing: 6) {
            NotchPanda(size: 22)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            if model.replying, model.notice == nil {
                Text(tr("码头 Pro"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelSecondary)
                    .fixedSize()
            }
        }
    }
}

// MARK: - 零件

/// 液态玻璃底，系统「降低透明度」时换成实心底（同 AI 刘海对话面板）。
private struct NotchMessageGlass<S: Shape>: View {
    var shape: S

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

/// 刘海下那条黑色过渡：顶边是和刘海一样的纯黑，往下淡到透明。
private struct NotchMessageBlend: View {
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

/// App 自己的图标；没装时画一个绿色圆角方块加 SF Symbol。
struct NotchAppIcon: View {
    var app: NotchMessageApp
    var size: CGFloat

    var body: some View {
        if let icon = NotchMessageOpener.icon(app) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(Color(hex: app == .wechat ? "#07A35A" : "#1F9D4C"))
                .overlay {
                    Image(systemName: Self.symbol(app))
                        .font(.system(size: size * 0.5, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }

    static func symbol(_ app: NotchMessageApp) -> String {
        switch app {
        case .messages: "message.fill"
        case .whatsapp: "phone.bubble.fill"
        case .wechat: "bubble.left.and.bubble.right.fill"
        }
    }
}

/// 头像：名字第一个字的彩色圆（同一个名字总是同一种颜色），没名字时是 App 图标。
/// 六种底色都够深，白色粗体大字过 3:1（大字标准）。
private struct NotchAvatar: View {
    var message: NotchMessage
    var size: CGFloat

    private static let palette: [(String, String)] = [
        ("#C8553D", "#9E3D5A"), ("#3E73C4", "#2C4F9E"), ("#23875C", "#196646"),
        ("#7E52C2", "#5D3A9E"), ("#B8691C", "#8F4D12"), ("#1F7F91", "#155F6E"),
    ]

    var body: some View {
        if let initial = message.initial {
            let colors = Self.palette[message.avatarHue % Self.palette.count]
            Circle()
                .fill(LinearGradient(colors: [Color(hex: colors.0), Color(hex: colors.1)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    Text(verbatim: initial)
                        .font(.system(size: size * 0.45, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            NotchAppIcon(app: message.app, size: size)
        }
    }
}

/// 底下一行的小熊猫（Resources/Pet/pet-panda-idle.png）。
private struct NotchPanda: View {
    var size: CGFloat

    @MainActor private static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "pet-panda-idle", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        if let image = Self.image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - 收起态

/// 收起态：刘海两侧的耳朵（黑色，看起来像刘海往两边长了一点）或刘海旁的黑色小胶囊，
/// 每个 App 一个小图标加未读数，点一个展开它最新的消息。它们就是刘海本身的一部分，
/// 浅色深色都保持黑底白字（同灵动提示的小胶囊）。
struct NotchIndicatorView: View {
    var kind: NotchIndicatorKind
    var model: NotchMessageModel

    private struct Item: Identifiable {
        var app: NotchMessageApp
        var count: Int
        var id: String { app.rawValue }
    }

    private var items: [Item] {
        let all = model.inbox.unreadCounts.map { Item(app: $0.app, count: $0.count) }
        switch kind {
        case .leftEar: return Array(all.prefix(1))
        case .rightEar: return Array(all.dropFirst())
        case .capsule: return all
        }
    }

    private var shape: UnevenRoundedRectangle {
        switch kind {
        case .leftEar:
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 10, bottomTrailingRadius: 0,
                                   topTrailingRadius: 0, style: .continuous)
        case .rightEar:
            UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 10,
                                   topTrailingRadius: 0, style: .continuous)
        case .capsule:
            UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12, bottomTrailingRadius: 12,
                                   topTrailingRadius: 12, style: .continuous)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                HStack(spacing: 6) {
                    NotchAppIcon(app: item.app, size: 18)
                    Text(verbatim: item.count > 99 ? "99+" : "\(item.count)")
                        .font(.system(size: 14, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .fixedSize()
                }
                .frame(width: NotchMessagePlacement.earItemWidth)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { model.act?(.expand(item.app)) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(tr("\(item.app.title) \(item.count) 条未读"))
                .accessibilityAddTraits(.isButton)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            shape.fill(.black)
                .overlay { if kind == .capsule { shape.stroke(.white.opacity(0.14), lineWidth: 0.5) } }
        }
        .environment(\.colorScheme, .dark)
    }
}
