import AppKit
import SwiftUI

/// 邮件面板：收件箱最近几封未读，点开跳到「邮件」里那一封。
///
/// 两个状态：
/// - 浏览：顶部账户筛选（两个以上账户时出现，Pro），每行发件人、账户小圆点、
///   时间、主题、一行摘要；悬停时时间换成「标已读」。底部「全部标为已读」
///   （点两次才动）和「打开邮件 App」。全部读完时是小熊猫。
/// - 设置：右上「设置」进入。每个账户一个开关、每次显示 3 / 5 / 10 封、
///   摘要开关、点开后自动标已读。
///
/// 列表用 AppleScript 读（`MailService.loadList`），只在面板开着时读，每 30 秒
/// 一次，「邮件」没开时不读也不把它打开。挑哪几封、怎么写时间在 `MailInbox`。
struct MailDetail: View {
    @Environment(\.panelTint) private var panelTint
    var instance: WidgetInstance
    var context: WidgetContext

    private enum Mode { case browse, settings }

    @State private var mode: Mode = .browse
    /// 每写一次加一，面板跟着重读存着的配置。
    @State private var revision = 0
    @State private var hovered: String?
    /// 点了一次「全部标为已读」，等第二次确认。
    @State private var confirmAll = false
    @State private var notice: String?

    private var mail: MailService { MailService.shared }

    private static let accentHex = "#8DB8FF"
    private static let inkHex = "#0A1B3A"
    private var accent: Color { panelTint.accent(or: Color(hex: Self.accentHex)) }
    private var accentInk: Color { panelTint.ink(or: Color(hex: Self.inkHex)) }

    // MARK: 读

    private var current: WidgetInstance {
        _ = revision
        return WidgetWriter.current(instance.id) ?? instance
    }
    private var config: WidgetConfig { current.config }
    private var unlocked: Bool { ProAccess.isUnlocked || context.isPreview }
    private var hidden: Set<String> { MailInbox.hidden(config) }
    private var limit: Int { MailInbox.limit(config) }
    private var showsSummary: Bool { MailInbox.showsSummary(config) }
    private var storedFilter: String? {
        let raw = config.string(MailInbox.filterKey)
        return raw.isEmpty ? nil : raw
    }

    private var listState: MailListState { context.isPreview ? .loaded : mail.listState }
    private var snapshot: MailSnapshot { context.isPreview ? Self.sample(now: context.now) : (mail.snapshot ?? MailSnapshot()) }
    private var filter: String? {
        MailInbox.effectiveFilter(storedFilter, accounts: snapshot.accounts, hidden: hidden, unlocked: unlocked)
    }
    private var visible: [MailMessage] {
        MailInbox.visible(snapshot, hidden: hidden, filter: storedFilter, unlocked: unlocked, limit: limit)
    }
    private var unread: Int {
        MailInbox.unreadTotal(snapshot, hidden: hidden, filter: storedFilter, unlocked: unlocked)
    }

    var body: some View {
        DetailCard {
            MeshBackdrop(color: Color(hex: Self.accentHex))
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                header
                switch mode {
                case .browse: browse
                case .settings: settings
                }
            }
        }
        .task(id: showsSummary) { await poll() }
        // 三秒内没点第二次就收回去；再点或关上面板时这个等待随之取消。
        .task(id: confirmAll) {
            guard confirmAll else { return }
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { confirmAll = false }
        }
    }

    /// 面板开着时每 30 秒读一次；「邮件」没开或还没读到时 5 秒一次，
    /// 刚点了「打开邮件 App」也能很快接上。面板关上任务就取消，不留定时器。
    private func poll() async {
        guard !context.isPreview else { return }
        while !Task.isCancelled {
            await mail.loadList(summary: showsSummary)
            let wait: Double = mail.listState == .loaded ? 30 : 5
            try? await Task.sleep(for: .seconds(wait))
        }
    }

    // MARK: 头部

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(mode == .browse ? tr("邮件") : tr("邮件设置"))
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white.opacity(0.97))
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .monospacedDigit()
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
            if !context.isPreview { modeButton }
        }
    }

    private var subtitle: String {
        if mode == .settings { return tr("选账户 · 显示几封 · 点开后怎样") }
        switch listState {
        case .loaded:
            return unread == 0 ? tr("没有未读邮件") : tr("\(unread) 封未读 · 点开跳到那一封")
        case .notRunning: return tr("「邮件」没开")
        case .denied: return tr("需要允许码头读取「邮件」")
        case .failed: return tr("暂时无法读取")
        case .idle, .loading: return tr("正在读取未读邮件…")
        }
    }

    @ViewBuilder
    private var modeButton: some View {
        if mode == .browse {
            Button { switchTo(.settings) } label: {
                Text(tr("设置"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(.horizontal, 13)
                    .frame(height: 28)
                    .background(Capsule().fill(.white.opacity(0.12)))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.6))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(tr("选账户、显示几封、点开后是否标已读"))
        } else {
            Button { switchTo(.browse) } label: {
                Text(tr("完成"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(accentInk)
                    .padding(.horizontal, 15)
                    .frame(height: 28)
                    .background(Capsule().fill(accent))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    private func switchTo(_ next: Mode) {
        withAnimation(.snappy(duration: 0.25)) {
            mode = next
            hovered = nil
            confirmAll = false
        }
    }

    // MARK: 浏览

    @ViewBuilder
    private var browse: some View {
        switch listState {
        case .notRunning:
            statusCard(title: tr("「邮件」没开"), detail: tr("打开它就能在这里看未读，不会自动打开"),
                       action: tr("打开邮件 App"), primary: true) { mail.openMail() }
        case .denied:
            permissionCard
        case .failed:
            statusCard(title: tr("暂时无法读取"), detail: tr("「邮件」没有回应，稍后会再试"),
                       action: tr("重试"), primary: false) {
                Task { await mail.loadList(summary: showsSummary) }
            }
        case .idle, .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(tr("正在读取未读邮件…"))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.62))
            }
            .frame(maxWidth: .infinity, minHeight: 80)
        case .loaded:
            loaded
        }
    }

    @ViewBuilder
    private var loaded: some View {
        if MailInbox.showsFilterChips(snapshot.accounts, hidden: hidden) {
            filterRow
        }
        if MailInbox.allAccountsHidden(snapshot.accounts, hidden: hidden) {
            Text(tr("账户都关掉了，在「设置」里打开要看的账户。"))
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 6)
        } else if visible.isEmpty {
            allRead
        } else {
            VStack(spacing: 6) {
                ForEach(visible) { message in
                    row(message)
                }
            }
        }
        if let notice {
            Text(notice)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.62))
                .lineLimit(2)
        }
        footer
    }

    // MARK: 账户筛选（Pro）

    private var filterRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                chip(nil, title: tr("全部 \(MailInbox.unreadTotal(snapshot, hidden: hidden, filter: nil, unlocked: unlocked))"),
                     dot: nil)
                ForEach(MailInbox.shownAccounts(snapshot.accounts, hidden: hidden)) { account in
                    chip(account.name, title: "\(account.name) \(account.unread)",
                         dot: Color(hex: MailInbox.accountHex(account.name, in: snapshot.accounts)))
                }
                if !unlocked { ProBadge() }
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.never)
    }

    private func chip(_ name: String?, title: String, dot: Color?) -> some View {
        let on = filter == name
        return Button {
            choose(name)
        } label: {
            HStack(spacing: 6) {
                if let dot {
                    Circle().fill(on ? accentInk : dot).frame(width: 8, height: 8)
                }
                Text(verbatim: title)
                    .font(.system(size: 13, weight: on ? .bold : .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .foregroundStyle(on ? accentInk : .white.opacity(0.88))
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Capsule().fill(on ? accent : .white.opacity(0.08)))
            .overlay(Capsule().strokeBorder(.white.opacity(on ? 0 : 0.14), lineWidth: 0.6))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// 选「全部」免费；选某个账户是 Pro，没解锁弹付费墙，存着的筛选不动。
    private func choose(_ name: String?) {
        guard !context.isPreview else { return }
        if name != nil, !MailInbox.canFilter(unlocked: unlocked) {
            PaywallWindow.shared.show()
            return
        }
        // 没解锁时点「全部」也不改写存着的筛选，解锁后回来。
        guard unlocked || name != nil else { return }
        WidgetWriter.write(current) { $0.set(MailInbox.filterKey, name.map { .string($0) }) }
        withAnimation(.snappy(duration: 0.2)) { revision += 1 }
    }

    // MARK: 一封

    private func row(_ message: MailMessage) -> some View {
        let hover = hovered == message.id
        let name = message.senderName
        return HStack(alignment: .top, spacing: 0) {
            Circle().fill(accent).frame(width: 7, height: 7)
                .padding(.top, 15)
                .frame(width: 18)
            ZStack {
                Circle().fill(Color(hex: MailInbox.avatarHex(name)))
                Text(verbatim: MailInbox.initial(name))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 28, height: 28)
            .padding(.top, 4)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(verbatim: name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Circle()
                        .fill(Color(hex: MailInbox.accountHex(message.account, in: snapshot.accounts)))
                        .frame(width: 7, height: 7)
                        .help(message.account)
                    Spacer(minLength: 6)
                    if hover, !context.isPreview {
                        markReadButton(message)
                    } else {
                        Text(MailInbox.timeLabel(message.received, now: context.now))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.62))
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .frame(height: 26)
                Text(verbatim: message.subject.isEmpty ? tr("（无主题）") : message.subject)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if showsSummary, !message.summary.isEmpty {
                    Text(verbatim: message.summary)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.leading, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 4)
        .padding(.bottom, 10)
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(hover ? 0.12 : 0.06))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(hover ? 0.22 : 0.10), lineWidth: 0.6)
                }
        }
        .contentShape(.rect(cornerRadius: 12))
        .onHover { inside in
            if inside { hovered = message.id } else if hovered == message.id { hovered = nil }
        }
        .onTapGesture { open(message) }
        .help(tr("在「邮件」中打开"))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text(tr("标已读"))) { markRead(message) }
    }

    private func markReadButton(_ message: MailMessage) -> some View {
        Button { markRead(message) } label: {
            Text(tr("标已读"))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(accentInk)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Capsule().fill(accent))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func open(_ message: MailMessage) {
        guard !context.isPreview else { return }
        mail.open(message)
        if MailInbox.marksReadOnOpen(config) { markRead(message) }
    }

    private func markRead(_ message: MailMessage) {
        guard !context.isPreview else { return }
        withAnimation(.snappy(duration: 0.25)) { hovered = nil }
        Task {
            let ok = await mail.markRead(message)
            notice = ok ? nil : tr("没能标为已读，稍后会再读一次")
            await mail.loadList(summary: showsSummary)
        }
    }

    // MARK: 底部

    private var footer: some View {
        HStack(spacing: 8) {
            let targets = MailInbox.accountsToMarkAll(snapshot, hidden: hidden, filter: storedFilter, unlocked: unlocked)
            Button {
                guard !context.isPreview, !targets.isEmpty else { return }
                if confirmAll {
                    confirmAll = false
                    Task {
                        let ok = await mail.markAllRead(targets)
                        notice = ok ? nil : tr("没能标为已读，稍后会再读一次")
                        await mail.loadList(summary: showsSummary)
                    }
                } else {
                    withAnimation(.snappy(duration: 0.2)) { confirmAll = true }
                }
            } label: {
                Text(confirmAll ? tr("再点一次：\(unread) 封") : tr("全部标为已读"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(targets.isEmpty ? 0.4 : 0.95))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(Capsule().fill(.white.opacity(confirmAll ? 0.2 : 0.12)))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.6))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(targets.isEmpty)
            primaryButton(tr("打开邮件 App")) { if !context.isPreview { mail.openMail() } }
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(accentInk)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(Capsule().fill(accent))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: 空状态和提示

    /// 全部读完：小熊猫欢呼，和效果图一样。
    private var allRead: some View {
        HStack(spacing: 12) {
            Group {
                if let image = PandaArt.image("pet-panda-cheer") {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "envelope.open.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(accent)
                }
            }
            .frame(width: 76, height: 76)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(tr("读完了！"))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                Text(tr("没有未读邮件，歇会儿"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPane(cornerRadius: 14)
    }

    private var permissionCard: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(tr("第一次要允许码头"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))
                Text(tr("读取和控制「邮件」"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
            Button { mail.openAutomationSettings() } label: {
                Text(tr("去允许"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .fixedSize()
                    .padding(.horizontal, 14)
                    .frame(height: 28)
                    .background(Capsule().fill(.white.opacity(0.12)))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.6))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(context.isPreview)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPane(cornerRadius: 12)
    }

    private func statusCard(title: String, detail: String, action: String, primary: Bool,
                            perform: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if primary {
                primaryButton(action, action: perform)
            } else {
                Button(action: perform) {
                    Text(action)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(Capsule().fill(.white.opacity(0.12)))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.6))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPane(cornerRadius: 12)
    }

    // MARK: 设置

    @ViewBuilder
    private var settings: some View {
        sectionLabel(tr("账户"))
        if snapshot.accounts.isEmpty {
            Text(listState == .notRunning ? tr("打开「邮件」后这里列出账户") : tr("还没有读到账户"))
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.62))
                .padding(.vertical, 4)
        } else {
            VStack(spacing: 6) {
                ForEach(snapshot.accounts) { account in accountRow(account) }
            }
        }
        HStack(spacing: 10) {
            sectionLabel(tr("每次显示"))
                .fixedSize()
            segment
        }
        .padding(.top, 6)
        toggleRow(tr("显示一行摘要"), sub: nil, on: showsSummary) { set(MailInbox.summaryKey, $0) }
        toggleRow(tr("点开后自动标已读"), sub: tr("关着时要点「标已读」"), on: MailInbox.marksReadOnOpen(config)) {
            set(MailInbox.markReadKey, $0)
        }
        sectionLabel(tr("全部读完时"))
            .padding(.top, 4)
        allRead
        if listState == .denied || listState == .failed || listState == .idle {
            permissionCard
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(0.62))
    }

    private func accountRow(_ account: MailAccount) -> some View {
        let on = !hidden.contains(account.name)
        return HStack(spacing: 10) {
            Circle()
                .fill(Color(hex: MailInbox.accountHex(account.name, in: snapshot.accounts)))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(verbatim: account.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(on ? 1 : 0.7))
                        .lineLimit(1)
                    Text(tr("\(account.unread) 封"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .monospacedDigit()
                        .fixedSize()
                }
                if !account.address.isEmpty {
                    Text(verbatim: account.address)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 6)
            MailSwitch(on: on, accent: accent) {
                guard !context.isPreview else { return }
                let next = MailInbox.toggling(account.name, shown: !on, hidden: hidden)
                WidgetWriter.write(current) { $0.set(MailInbox.hiddenKey, .list(next.map { .string($0) })) }
                withAnimation(.snappy(duration: 0.2)) { revision += 1 }
            }
            .accessibilityLabel(account.name)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 52)
        .glassPane(cornerRadius: 12)
    }

    private var segment: some View {
        HStack(spacing: 0) {
            ForEach(MailInbox.limitChoices, id: \.self) { value in
                let on = value == limit
                Button {
                    guard !context.isPreview else { return }
                    WidgetWriter.write(current) { $0.set(MailInbox.limitKey, .string("\(value)")) }
                    withAnimation(.snappy(duration: 0.2)) { revision += 1 }
                } label: {
                    Text(tr("\(value) 封"))
                        .font(.system(size: 13, weight: on ? .bold : .semibold))
                        .foregroundStyle(on ? accentInk : .white.opacity(0.82))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .background(Capsule().fill(on ? accent : .clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Capsule().fill(.white.opacity(0.07)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.6))
    }

    private func toggleRow(_ title: String, sub: String?, on: Bool, change: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.94))
                if let sub {
                    Text(sub)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            Spacer(minLength: 6)
            MailSwitch(on: on, accent: accent) {
                guard !context.isPreview else { return }
                change(!on)
            }
            .accessibilityLabel(title)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: sub == nil ? 44 : 56)
        .glassPane(cornerRadius: 12)
    }

    private func set(_ key: String, _ value: Bool) {
        WidgetWriter.write(current) { $0.set(key, .bool(value)) }
        withAnimation(.snappy(duration: 0.2)) { revision += 1 }
    }

    // MARK: 示例

    /// 小组件库和截图里用的示例，取自效果图。
    static func sample(now: Date) -> MailSnapshot {
        let work = tr("工作"), home = tr("个人")
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        return MailSnapshot(
            accounts: [MailAccount(name: work, address: "zhou@work.example", unread: 3),
                       MailAccount(name: home, address: "me@home.example", unread: 2)],
            messages: [
                MailMessage(account: work, mailID: 1, messageID: "", sender: tr("周岚"),
                            subject: tr("第二批面板评审"), summary: tr("周四下午可以吗？我先把稿子发你"), received: ago(11)),
                MailMessage(account: home, mailID: 2, messageID: "", sender: tr("物业服务中心"),
                            subject: tr("本周六停水通知"), summary: tr("10 月 24 日 9:00 至 15:00 停水"), received: ago(43)),
                MailMessage(account: work, mailID: 3, messageID: "", sender: tr("陈一凡"),
                            subject: tr("合同第二版"), summary: tr("改了付款节点，附件在最下面"), received: ago(60 * 26)),
                MailMessage(account: home, mailID: 4, messageID: "", sender: tr("设计周刊"),
                            subject: tr("本周灵感 12 则"), summary: tr("深色界面里怎么做层次"), received: ago(60 * 30)),
                MailMessage(account: work, mailID: 5, messageID: "", sender: tr("李老师"),
                            subject: tr("下周家长会"), summary: tr("时间定在周五晚上七点"), received: ago(60 * 50)),
            ])
    }
}

/// 设置里的开关：40 × 24，开着是主题色，和效果图一样（系统开关的颜色跟系统强调色走）。
private struct MailSwitch: View {
    var on: Bool
    var accent: Color
    var toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            ZStack(alignment: on ? .trailing : .leading) {
                Capsule().fill(on ? accent : .white.opacity(0.18))
                Circle().fill(.white).frame(width: 19, height: 19).padding(2.5)
            }
            .frame(width: 40, height: 24)
            .animation(.snappy(duration: 0.18), value: on)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityValue(on ? Text(tr("开")) : Text(tr("关")))
        .accessibilityAddTraits(.isToggle)
    }
}
