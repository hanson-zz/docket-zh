import AppKit
import SwiftUI

/// One followed repository at a time, chosen with the chips along the top:
/// its counters, what came in since it was last marked read, its latest
/// release and how often that was downloaded. Below, the list of projects
/// (add, remove, reorder) and the optional token.
struct GitHubDetail: View {
    /// 颜色面板里选的强调色，没选过是 nil，用原来的颜色（见 `PanelTint`）。
    @Environment(\.panelTint) private var panelTint
    var instance: WidgetInstance
    var context: WidgetContext

    @State private var token = ""
    /// The list as the panel has it, so an edit shows at once.
    @State private var edited: [String]?
    @State private var selected: String?
    @State private var addText = ""
    @State private var addError: String?
    @State private var adding = false
    @State private var managing = false

    private var service: GitHubService { GitHubService.shared }
    private var repos: [String] { edited ?? GitHubWatch.repos(instance.config) }

    private var current: String {
        if let selected, repos.contains(where: { GitHubWatch.key($0) == GitHubWatch.key(selected) }) {
            return selected
        }
        return repos.first ?? GitHubWatch.defaultRepo
    }

    // MARK: Data, or the library's sample

    private static let sampleStats = GitHubStats(fullName: GitHubWatch.defaultRepo, stars: 128, forks: 9,
                                                 watchers: 4, openIssuesAndPulls: 5, openPulls: 2)

    private var stats: GitHubStats? {
        context.isPreview ? Self.sampleStats : service.stats(for: current)
    }

    private var items: [GitHubFeedItem] {
        if context.isPreview {
            let now = context.now
            return [
                GitHubFeedItem(id: "c1", kind: .comment, number: 12, title: tr("#12 菜单栏图标在深色模式下看不清"),
                               author: "lin", createdAt: now.addingTimeInterval(-600), url: nil),
                GitHubFeedItem(id: "p1", kind: .pull, number: 14, title: tr("补充繁体中文翻译"),
                               author: "chen", createdAt: now.addingTimeInterval(-7200), url: nil,
                               labels: [tr("翻译")]),
                GitHubFeedItem(id: "i1", kind: .issue, number: 12, title: tr("菜单栏图标在深色模式下看不清"),
                               author: "wang", createdAt: now.addingTimeInterval(-90_000), url: nil,
                               labels: ["bug"]),
            ]
        }
        return service.state(for: current)?.items ?? []
    }

    private var release: GitHubRelease? {
        if context.isPreview {
            return GitHubRelease(id: 1, tag: "v0.6.0", name: "v0.6.0",
                                 publishedAt: context.now.addingTimeInterval(-3 * 86_400), url: nil,
                                 assets: [.init(name: "Dockling-0.6.0.dmg", downloads: 342),
                                          .init(name: "Dockling-0.6.0.zip", downloads: 57)])
        }
        return service.state(for: current)?.releases?.first
    }

    private func isUnread(_ item: GitHubFeedItem) -> Bool {
        if context.isPreview { return item.id != "i1" }
        return GitHubFeed.isUnread(item, seen: service.seenState(for: current))
    }

    private func newCount(_ slug: String) -> Int {
        context.isPreview ? (GitHubWatch.key(slug) == GitHubWatch.key(current) ? 3 : 0)
            : service.feedback(for: slug).total
    }

    // MARK: Body

    var body: some View {
        DetailCard {
            MeshBackdrop(color: WidgetStyle.tint(.purple))
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                PanelHeader(symbol: "chevron.left.forwardslash.chevron.right",
                            title: stats?.fullName ?? current,
                            subtitle: subtitle)
                if repos.count > 1 { switcher }
                if !context.isPreview, let limit = service.limitedUntil, limit > context.now {
                    limitNote(limit)
                }
                if let stats {
                    if !context.isPreview, service.isOffline(current) {
                        // 还有上次的数据，只是这次没连上：一条细横幅，可以直接重连。
                        ReconnectStateView(title: tr("离线"), detail: tr("这次没连上 GitHub，显示的是上次的数据"),
                                           loading: service.isLoading(current), style: .compact,
                                           retry: reconnect)
                    }
                    statsGrid(stats)
                    activityGrid
                    feedSection
                    if let release { releaseCard(release) }
                } else if !context.isPreview, service.isOffline(current) {
                    // 一次都没读到：共用的断网状态，插头拔着，点“重新连接”推回去。
                    ReconnectStateView(title: tr("无法连接 GitHub"),
                                       detail: tr("可能是网络断开了，或者 GitHub 暂时访问不了。"),
                                       loading: service.isLoading(current),
                                       retry: reconnect)
                } else {
                    PanelNote(symbol: "network", text: service.error(for: current) ?? tr("正在读取…")).frame(height: 90)
                }
                HStack(spacing: 8) {
                    PanelButton(title: tr("打开仓库"), symbol: "arrow.up.right", prominent: true) {
                        open("https://github.com/\(current)")
                    }
                    PanelButton(title: tr("新建议题"), symbol: "plus") {
                        open("https://github.com/\(current)/issues/new")
                    }
                    PanelButton(title: tr("刷新"), symbol: "arrow.clockwise") {
                        guard !context.isPreview else { return }
                        service.refreshAll(repos, force: true)
                    }
                }
                manageSection
                tokenSection
            }
        }
        .onAppear { if !context.isPreview { service.refreshAll(repos) } }
    }

    /// 重新连接：跳过刷新间隔，立刻再读一次。
    private func reconnect() {
        guard !context.isPreview else { return }
        service.refreshAll(repos, force: true)
    }

    private var subtitle: String {
        if context.isPreview { return tr("示例数据") }
        let feedback = service.feedback(for: current)
        if feedback.total > 0 { return tr("新反馈：") + feedback.summary }
        return service.hasToken ? tr("已使用个人访问令牌") : tr("公开数据 · 未使用令牌")
    }

    // MARK: Switcher

    private var switcher: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(repos, id: \.self) { slug in
                    let on = GitHubWatch.key(slug) == GitHubWatch.key(current)
                    Button { selected = slug } label: {
                        HStack(spacing: 4) {
                            Text(RepoSlug.parse(slug)?.repo ?? slug).lineLimit(1)
                            if let badge = GitHubWatch.badgeText(newCount(slug)) {
                                Text(badge)
                                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                                    .padding(.horizontal, 4)
                                    .frame(minWidth: 15, minHeight: 15)
                                    .foregroundStyle(.white)
                                    .background(Capsule().fill(Color.red))
                            }
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.panelPrimary)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(on ? panelTint.fill(0.45, or: Color.panelFillStrong) : Color.panelFill,
                                    in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .help(slug)
                }
            }
        }
        .scrollIndicators(.never)
    }

    private func limitNote(_ until: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(GitHubRateLimit.waitText(until: until, now: context.now), systemImage: "hourglass")
                .font(WidgetStyle.label(13))
                .foregroundStyle(.panelPrimary)
            if !service.hasToken {
                Text("未使用令牌时 GitHub 每小时只允许 60 次请求。在下方添加个人访问令牌即可提高上限。")
                    .font(WidgetStyle.caption(13))
                    .foregroundStyle(.panelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPane(cornerRadius: 10)
    }

    // MARK: Numbers

    private func statsGrid(_ stats: GitHubStats) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            StatChip(label: tr("星标"), value: GitHubStats.short(stats.stars))
            StatChip(label: tr("复刻"), value: GitHubStats.short(stats.forks))
            StatChip(label: tr("关注"), value: GitHubStats.short(stats.watchers))
            StatChip(label: tr("未解决议题"), value: GitHubStats.short(stats.openIssues ?? stats.openIssuesAndPulls))
            StatChip(label: tr("拉取请求"), value: stats.openPulls.map(GitHubStats.short) ?? "-")
            StatChip(label: tr("通知"),
                     value: context.isPreview ? "-" : service.notifications.map { "\($0)" } ?? "-")
        }
    }

    // MARK: Activity

    /// 最近五周每天来了几条议题、拉取请求和评论，画成贡献图那样的周格子：
    /// 一列一周，周一在上，那几周里最热闹的一天最深。
    private var activityGrid: some View {
        let tally = ContributionGrid.tally(items.map(\.createdAt))
        let weeks = ContributionGrid.columns(weeks: 5, today: context.now,
                                             count: { tally[$0] ?? 0 }, level: { $0 })
        let busiest = weeks.joined().map(\.count).max() ?? 0
        let leveled = weeks.map { column in
            column.map { cell in
                var cell = cell
                cell.level = cell.isFuture ? 0 : ContributionGrid.level(count: cell.count, busiest: busiest)
                return cell
            }
        }
        let total = weeks.joined().reduce(0) { $0 + $1.count }
        // GitHub 的绿是这张卡片自己的颜色，颜色面板里选了颜色就跟着换。
        let green = panelTint.accent(or: Color(hex: "39D353"))
        return HStack(alignment: .center, spacing: 12) {
            ContributionGridView(columns: leveled, color: green, cell: 11, spacing: 3, unit: tr("条"))
            VStack(alignment: .leading, spacing: 4) {
                Text("近 5 周动静")
                    .font(WidgetStyle.label(13))
                    .foregroundStyle(.panelPrimary)
                Text(total == 0 ? tr("这几周没有新的议题、拉取请求或评论。") : tr("共 \(total) 条议题、拉取请求和评论"))
                    .font(WidgetStyle.caption(13))
                    .foregroundStyle(.panelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                ContributionLegend(color: green)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .glassPane(cornerRadius: 12)
    }

    // MARK: Feedback

    private var feedSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("新反馈")
                    .font(WidgetStyle.label(13))
                    .foregroundStyle(.panelPrimary)
                Spacer()
                Button("全部标为已读") {
                    guard !context.isPreview else { return }
                    service.markAllRead(repos)
                }
                .buttonStyle(.plain)
                .font(WidgetStyle.label(13))
                .foregroundStyle(.panelPrimary.opacity(totalNew > 0 ? 0.9 : 0.4))
                .disabled(context.isPreview || totalNew == 0)
            }
            let shown = items
            if shown.isEmpty {
                Text("最近 30 天没有新的议题、拉取请求或评论。")
                    .font(WidgetStyle.caption(13))
                    .foregroundStyle(.panelSecondary)
                    .padding(.vertical, 6)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(shown) { item in row(item) }
                    }
                }
                .scrollIndicators(.never)
                .frame(height: min(220, CGFloat(shown.count) * 48))
            }
        }
    }

    private var totalNew: Int {
        context.isPreview ? 3 : service.totalFeedback(repos)
    }

    private func tint(_ kind: GitHubFeedItem.Kind) -> Color {
        switch kind {
        case .issue: Color.green.panelReadable
        case .pull: Color.purple.panelReadable
        case .comment: .panelSecondary
        }
    }

    private func row(_ item: GitHubFeedItem) -> some View {
        let unread = isUnread(item)
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: item.kind.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint(item.kind))
                .frame(width: 16)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: unread ? .semibold : .regular))
                    .foregroundStyle(.panelPrimary.opacity(unread ? 1 : 0.8))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text("\(item.kind.title) · \(item.author) · \(GitHubFeed.relativeText(item.createdAt, now: context.now))")
                        .lineLimit(1)
                    ForEach(item.labels.prefix(2), id: \.self) { label in
                        Text(label)
                            .lineLimit(1)
                            .padding(.horizontal, 5)
                            .background(Color.panelFillStrong, in: .capsule)
                    }
                }
                .font(WidgetStyle.caption(13))
                .foregroundStyle(.panelSecondary)
            }
            Spacer(minLength: 0)
            if unread {
                Circle().fill(Color.red).frame(width: 6, height: 6).padding(.top, 5)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .glassPane(cornerRadius: 9)
        .contentShape(.rect(cornerRadius: 9))
        .onTapGesture {
            guard !context.isPreview, let url = item.url else { return }
            NSWorkspace.shared.open(url)
        }
        .help(item.title)
    }

    // MARK: Release

    private func releaseCard(_ release: GitHubRelease) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                Text(tr("最新版本 \(release.tag)"))
                    .font(WidgetStyle.label(13))
                    .foregroundStyle(.panelPrimary)
                    .lineLimit(1)
                Spacer()
                Text(tr("共 \(release.downloads) 次下载"))
                    .font(WidgetStyle.label(13))
                    .foregroundStyle(.panelPrimary)
                    .monospacedDigit()
            }
            if let date = release.publishedAt {
                Text("发布于 " + date.formatted(.dateTime.year().month().day())
                     + " · " + GitHubFeed.relativeText(date, now: context.now))
                    .font(WidgetStyle.caption(13))
                    .foregroundStyle(.panelSecondary)
            }
            if release.assets.isEmpty {
                Text("这个版本没有附带安装文件。")
                    .font(WidgetStyle.caption(13))
                    .foregroundStyle(.panelSecondary)
            } else {
                ForEach(Array(release.assets.prefix(5).enumerated()), id: \.offset) { _, asset in
                    HStack {
                        Text(asset.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text("\(asset.downloads)")
                            .monospacedDigit()
                    }
                    .font(WidgetStyle.caption(13))
                    .foregroundStyle(.panelSecondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .glassPane(cornerRadius: 10)
        .contentShape(.rect(cornerRadius: 10))
        .onTapGesture {
            guard !context.isPreview, let url = release.url else { return }
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Projects

    private var manageSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { managing.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text(tr("关注的项目（\(repos.count)/\(GitHubWatch.maxRepos)）"))
                    Image(systemName: managing ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .font(WidgetStyle.label(13))
                .foregroundStyle(.panelPrimary)
            }
            .buttonStyle(.plain)
            if managing {
                ForEach(Array(repos.enumerated()), id: \.element) { index, slug in
                    HStack(spacing: 6) {
                        Text(slug)
                            .font(.system(size: 13))
                            .foregroundStyle(.panelPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                        iconButton("chevron.up", help: tr("上移"), disabled: index == 0) {
                            save(GitHubWatch.moving(slug, by: -1, in: repos))
                        }
                        iconButton("chevron.down", help: tr("下移"), disabled: index == repos.count - 1) {
                            save(GitHubWatch.moving(slug, by: 1, in: repos))
                        }
                        iconButton("xmark", help: tr("移除"), disabled: repos.count <= 1) {
                            save(GitHubWatch.removing(slug, from: repos))
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .glassPane(cornerRadius: 7)
                }
                HStack(spacing: 6) {
                    TextField("", text: $addText, prompt: Text("用户/仓库 或 GitHub 链接"))
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(.panelPrimary)
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                        .glassPane(cornerRadius: 7)
                        .onSubmit(add)
                    Button(adding ? tr("检查中…") : tr("添加"), action: add)
                        .buttonStyle(.plain)
                        .font(WidgetStyle.label(13))
                        .foregroundStyle(.panelPrimary)
                        .disabled(context.isPreview || adding || addText.isEmpty
                                  || repos.count >= GitHubWatch.maxRepos)
                }
                if let addError {
                    Text(addError)
                        .font(WidgetStyle.caption(13))
                        .foregroundStyle(Color.red.panelReadable.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func iconButton(_ symbol: String, help: String, disabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.panelPrimary.opacity(disabled ? 0.25 : 0.8))
                .frame(width: 18, height: 18)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(disabled || context.isPreview)
        .help(help)
    }

    /// Checked locally first (format, repeats, the limit), then against
    /// GitHub, so a typo or a private repository is caught here rather than
    /// becoming a chip that never loads.
    private func add() {
        guard !context.isPreview, !adding else { return }
        switch GitHubWatch.adding(addText, to: repos) {
        case .failure(let error):
            addError = error.message
        case .success:
            guard let slug = GitHubWatch.slug(from: addText) else { return }
            adding = true
            addError = nil
            Task {
                let result = await service.validate(slug)
                adding = false
                switch result {
                case .success(let canonical):
                    // GitHub's spelling, checked again: the canonical name
                    // can match an entry typed with different case.
                    if case .success(let list) = GitHubWatch.adding(canonical, to: repos) {
                        save(list)
                        selected = canonical
                        service.refresh(canonical, force: true)
                    } else {
                        addError = GitHubWatch.AddError.duplicate.message
                    }
                    addText = ""
                case .failure(let failure):
                    addError = failure.message
                }
            }
        }
    }

    private func save(_ list: [String]) {
        guard !context.isPreview else { return }
        let clean = GitHubWatch.cleaned(list)
        edited = clean
        WidgetWriter.write(instance) { config in
            config.set(GitHubWatch.reposKey, GitHubWatch.encode(clean))
            config.set(GitHubWatch.legacyRepoKey, nil)
        }
    }

    private func open(_ address: String) {
        guard !context.isPreview, let url = URL(string: address) else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: Token

    private var tokenSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("个人访问令牌（可选）")
                .font(WidgetStyle.label(13))
                .foregroundStyle(.panelPrimary)
            HStack(spacing: 6) {
                SecureField("", text: $token, prompt: Text(service.hasToken ? tr("已保存在钥匙串中") : tr("ghp_… 或 github_pat_…")))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.panelPrimary)
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .glassPane(cornerRadius: 7)
                    .onSubmit(saveToken)
                Button(service.hasToken && token.isEmpty ? tr("移除") : tr("保存")) {
                    if token.isEmpty { service.setToken(nil) } else { saveToken() }
                }
                .buttonStyle(.plain)
                .font(WidgetStyle.label(13))
                .foregroundStyle(.panelPrimary)
                .disabled(context.isPreview || (token.isEmpty && !service.hasToken))
            }
            Text(service.hasToken
                 ? tr("令牌只保存在这台 Mac 的钥匙串中，用于提高请求上限并显示未读通知数。读取通知需要令牌具有 notifications 权限。")
                 : tr("令牌只保存在这台 Mac 的钥匙串中。未使用令牌时每小时只能请求 60 次，关注的项目较多时会自动放慢检查；添加令牌后上限提高到每小时 5000 次，并显示未读通知数。"))
                .font(WidgetStyle.caption(13))
                .foregroundStyle(.panelTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func saveToken() {
        guard !context.isPreview, !token.isEmpty else { return }
        service.setToken(token)
        token = ""
        service.refreshAll(repos, force: true)
    }
}
