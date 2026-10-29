import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 书签面板：四列网格图标加标题，面板里直接加、改、删、排。
///
/// 两个状态：
/// - 浏览：顶部分组标签（Pro）、“粘贴网址，回车添加”，网格里点一个用默认
///   浏览器打开；右键拷贝网址、刷新预览、小宇宙链接“加到播客”、删除。最下面一个
///   虚线框提示把链接拖到卡片上就能加入，拖到面板上也一样。
/// - 编辑：右上“编辑”进入。点名字改名，拖左边把手排序，红色减号滑出“删除”
///   再点才删；点一行选中后在底部“移到分组”（Pro）。
///
/// 粘贴的网址先读网页标题和图标（`LinkPreviewFetcher`，和卡片上自动读的是
/// 同一套），读到后出一张预览，点“添加”才加进去。
///
/// 右上“添加”打开添加书签表单（`BookmarkEditorForm`）：网址、名称和图标（网站
/// 图标 / 文字 / 上传图片）；右键“编辑名称和图标…”或编辑态点图标，用同一张表单改。
/// 选的图标存在 `icons`（见 `BookmarkIcons`），没选过的照原来画。
///
/// 列表照旧存在 `links`（见 `Bookmark`、`BookmarkList`），分组存在 `groups`
/// （见 `BookmarkGroups`）。没解锁 Pro 时只显示“全部”，分组照旧存着。
struct BookmarksDetail: View {
    /// 颜色面板里选的强调色，没选过是 nil，用原来的颜色（见 `PanelTint`）。
    @Environment(\.panelTint) private var panelTint
    var instance: WidgetInstance
    var context: WidgetContext

    private enum Mode { case browse, edit }
    private enum Field: Hashable { case add, rename, group }

    /// 粘贴进来、正在读或读好了标题和图标、还没点“添加”的那条。
    private struct Pending: Equatable {
        var text: String
        var url: URL
        var preview: LinkPreview?
        var loading: Bool
    }

    @State private var mode: Mode = .browse
    /// 选中的分组标签，nil 是“全部”。
    @State private var tab: String?
    @State private var newLink = ""
    @State private var pending: Pending?
    /// 添加框下面的一行提示（认不出网址、重复、放满）。
    @State private var notice: String?
    /// 每写一次加一，面板跟着重读存着的配置。
    @State private var revision = 0
    @State private var refreshing: Set<String> = []
    @State private var podcastStatus: String?
    @State private var addingPodcast: Set<String> = []
    /// 正在改名的那一行（网址）和输入的名字。
    @State private var renaming: String?
    @State private var renameText = ""
    /// 点了红色减号、正露出“删除”的那一行。
    @State private var pendingDelete: String?
    /// 正在拖的那一行和它的位移。
    @State private var dragging: String?
    @State private var dragOffset: CGFloat = 0
    /// 编辑态选中、准备移到分组的那一行。
    @State private var selected: String?
    /// 正在输入新分组的名字；nil 是没在新建。
    @State private var newGroup: String?
    /// 拖着链接停在面板上。
    @State private var targeted = false
    @FocusState private var focus: Field?

    private static let accentHex = "#FF9F43"
    private static let inkHex = "#2A1500"
    private var accent: Color { panelTint.accent(or: Color(hex: Self.accentHex)) }
    private var accentInk: Color { panelTint.ink(or: Color(hex: Self.inkHex)) }
    private static let red = Color(red: 1, green: 0.42, blue: 0.35)

    private static let rowHeight: CGFloat = 52
    private static let deleteWidth: CGFloat = 64
    private static let cellHeight: CGFloat = 84

    // MARK: 读

    /// 写过之后面板拿到的仍可能是打开时的那份，读最新存着的。
    private var current: WidgetInstance {
        _ = revision
        return WidgetWriter.current(instance.id) ?? instance
    }
    private var entries: [String] { current.config.strings("links") }
    private var links: [Bookmark] { Bookmark.list(entries) }
    private var previews: [String: LinkPreview] { LinkPreview.stored(current.config) }
    private var icons: [String: BookmarkIcon] { BookmarkIcons.stored(current.config) }
    private var form: BookmarkFormState { BookmarkFormState.shared }
    private var groups: [BookmarkGroup] { BookmarkGroups.groups(current.config) }
    private var unlocked: Bool { ProAccess.isUnlocked || context.isPreview }
    private var shownTab: String? { BookmarkGroups.selectedTab(tab, groups: groups, unlocked: unlocked) }
    private var visible: [Bookmark] {
        BookmarkGroups.visible(links, tab: tab, groups: groups, unlocked: unlocked)
    }

    var body: some View {
        DetailCard {
            MeshBackdrop(color: WidgetStyle.tint(.orange))
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                if form.isOpen(for: instance.id) {
                    BookmarkEditorForm(instance: current, context: context, accent: accent, accentInk: accentInk,
                                       group: shownTab, unlocked: unlocked) { revision += 1 }
                        .transition(.opacity)
                } else {
                    header
                    switch mode {
                    case .browse: browse
                    case .edit: edit
                    }
                }
            }
            // 改名框失去焦点（点了别处）也算改好了。
            .onChange(of: focus) { old, new in
                if old == .rename, new != .rename { commitRename() }
            }
        }
        // 拖链接到面板上：和卡片同一个虚线框，松手加在最后，标题由链接预览取。
        .dropTargetOutline(targeted, corner: DetailCard<EmptyView, EmptyView>.corner, prompt: .bookmark)
        .onDrop(of: [.url, .plainText], delegate: ContentDropDelegate(
            types: [.url, .plainText],
            enabled: !context.isPreview,
            targeted: { targeted = $0 },
            receive: { things in
                withAnimation(.snappy(duration: 0.3)) {
                    BookmarkDrop.add(things, to: current)
                    revision += 1
                }
            }))
        .task(id: pendingFetch) {
            let urls = pendingFetch
            guard !urls.isEmpty else { return }
            let fetched = await LinkPreviewFetcher.fetch(urls)
            guard !Task.isCancelled, !fetched.isEmpty else { return }
            BookmarkPreviews.save(fetched, in: current)
            revision += 1
        }
    }

    /// 还没读过标题和图标的网页，面板打开时补读（卡片上也会读，同一时间不重复）。
    private var pendingFetch: [URL] {
        guard !context.isPreview else { return [] }
        let stored = previews
        var seen = Set<String>()
        return links.map(\.url).filter { url in
            seen.insert(url.absoluteString).inserted
                && LinkPreview.needsFetch(url, stored: stored[url.absoluteString], now: context.now)
        }
    }

    // MARK: 头部

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(mode == .browse ? tr("书签") : tr("编辑书签"))
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.panelPrimary)
                Text(mode == .browse ? tr("\(links.count) 个网址") : tr("拖动排序 · 点名字改名"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
                    .monospacedDigit()
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
            if !context.isPreview {
                if mode == .browse, !links.isEmpty { refreshButton }
                if mode == .browse { addButton }
                modeButton
            }
        }
    }

    private var refreshButton: some View {
        Button {
            refresh(links)
        } label: {
            Group {
                if refreshing.isEmpty {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.panelSecondary)
                } else {
                    ProgressView().controlSize(.mini)
                }
            }
            .frame(width: 28, height: 28)
            .glassPane(cornerRadius: 14)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!refreshing.isEmpty)
        .help(tr("刷新全部预览"))
        .accessibilityLabel(tr("刷新全部预览"))
    }

    /// 打开添加书签表单。
    private var addButton: some View {
        Button { openForm(nil) } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                Text(tr("添加"))
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(accentInk)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Capsule().fill(accent))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(tr("添加书签：网址、名称和图标"))
        .accessibilityLabel(tr("添加书签"))
    }

    /// 打开表单：`link` 为 nil 是新加（带上添加框里已经粘贴的网址），否则编辑那一个。
    private func openForm(_ link: Bookmark?) {
        guard !context.isPreview else { return }
        commitRename()
        withAnimation(.snappy(duration: 0.2)) {
            if let link {
                let key = link.url.absoluteString
                form.startEditing(in: instance.id, link: link, preview: previews[key],
                                  icon: BookmarkIcons.icon(for: link.url, in: icons))
            } else {
                let typed = newLink.trimmingCharacters(in: .whitespacesAndNewlines)
                form.startAdding(in: instance.id, address: Bookmark.parseAddress(typed)?.absoluteString ?? "")
            }
            pending = nil
        }
    }

    @ViewBuilder
    private var modeButton: some View {
        if mode == .browse {
            Button { switchTo(.edit) } label: {
                Text(tr("编辑"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                    .padding(.horizontal, 13)
                    .frame(height: 28)
                    .background(Capsule().fill(.panelFill))
                    .overlay(Capsule().strokeBorder(.panelStroke, lineWidth: 0.6))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(tr("改名、删除、调整顺序"))
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
        commitRename()
        withAnimation(.snappy(duration: 0.25)) {
            mode = next
            pendingDelete = nil
            dragging = nil
            dragOffset = 0
            selected = nil
            newGroup = nil
        }
    }

    // MARK: 浏览

    @ViewBuilder
    private var browse: some View {
        tabsRow
        addField
        pendingCard
        if links.isEmpty {
            PandaEmptyState(empty: .bookmarks, title: tr("添加书签"), panel: true) {
                openForm(nil)
            }
            .frame(height: 120)
        } else if visible.isEmpty {
            Text(tr("这个分组还没有书签。点“编辑”，选中书签后移到分组。"))
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 8)
        } else {
            grid
        }
        if let podcastStatus {
            Text(podcastStatus)
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
                .lineLimit(2)
        }
        if !context.isPreview { dropHint }
    }

    // MARK: 分组标签

    private var tabsRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                if newGroup != nil, mode == .browse {
                    newGroupField
                } else {
                    tabChip(nil, title: tr("全部"))
                    ForEach(BookmarkGroups.tabs(groups, unlocked: unlocked), id: \.self) { name in
                        tabChip(name, title: name)
                            .contextMenu {
                                Button(tr("删除分组"), role: .destructive) { deleteGroup(name) }
                            }
                    }
                    if !context.isPreview {
                        Button { startNewGroup() } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.panelPrimary)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(.panelFill))
                                .overlay(Circle().strokeBorder(.panelStroke, lineWidth: 0.6))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help(tr("新建分组"))
                        .accessibilityLabel(tr("新建分组"))
                    }
                    ProBadge()
                }
            }
            .padding(.vertical, 1)
        }
        .scrollIndicators(.never)
    }

    private func tabChip(_ name: String?, title: String) -> some View {
        let on = shownTab == name
        return Button {
            withAnimation(.snappy(duration: 0.2)) { tab = name }
        } label: {
            Text(verbatim: title)
                .font(.system(size: 13, weight: on ? .bold : .semibold))
                .foregroundStyle(on ? accentInk : .panelPrimary)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Capsule().fill(on ? accent : .panelFill))
                .overlay(Capsule().strokeBorder(on ? Color.clear : Color.panelStroke, lineWidth: 0.6))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var newGroupField: some View {
        HStack(spacing: 6) {
            TextField("", text: Binding(get: { newGroup ?? "" }, set: { newGroup = $0 }),
                      prompt: Text(tr("分组名，回车新建")))
                .focused($focus, equals: .group)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.panelPrimary)
                .onSubmit { createGroup() }
                .padding(.horizontal, 12)
                .frame(width: 180, height: 30)
                .background(Capsule().fill(.panelFill))
                .overlay(Capsule().strokeBorder(accent.opacity(0.9), lineWidth: 1.2))
            Button(tr("取消")) { withAnimation(.snappy(duration: 0.2)) { newGroup = nil } }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.panelPrimary)
        }
    }

    /// “＋”：没解锁弹付费墙，解锁后输入分组名。
    private func startNewGroup() {
        guard ProLicenseGate.canUseBookmarkGroups(unlocked: unlocked) else {
            PaywallWindow.shared.show()
            return
        }
        WidgetDetailWindow.shared.focusField { focus = .group }
        withAnimation(.snappy(duration: 0.2)) { newGroup = "" }
    }

    private func createGroup() {
        let raw = newGroup ?? ""
        guard ProLicenseGate.canUseBookmarkGroups(unlocked: unlocked),
              let name = BookmarkGroups.cleanName(raw),
              var next = BookmarkGroups.adding(raw, to: groups) else {
            NSSound.beep()
            return
        }
        // 编辑态选中了一行时，新建的分组顺手把它放进去。
        if mode == .edit, let selected, let url = URL(string: selected) {
            next = BookmarkGroups.moving(url, to: name, in: next)
        }
        write { BookmarkGroups.write(next, into: &$0) }
        withAnimation(.snappy(duration: 0.2)) {
            newGroup = nil
            if mode == .browse { tab = name }
        }
    }

    private func deleteGroup(_ name: String) {
        guard ProLicenseGate.canUseBookmarkGroups(unlocked: unlocked) else { return }
        let next = BookmarkGroups.removing(name, from: groups)
        write { BookmarkGroups.write(next, into: &$0) }
        if tab == name { tab = nil }
    }

    // MARK: 添加

    private var addField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelSecondary)
                TextField("", text: $newLink, prompt: Text(tr("粘贴网址，回车添加")))
                    .focused($focus, equals: .add)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: newLink.isEmpty ? .regular : .medium))
                    .foregroundStyle(.panelPrimary)
                    .onSubmit { readLink() }
                    .onChange(of: newLink) { notice = nil }
                    .disabled(context.isPreview)
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.panelFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(focus == .add ? accent.opacity(0.9) : .panelStroke,
                                  lineWidth: focus == .add ? 1.2 : 0.6)
            }
            if let notice {
                Text(notice)
                    .font(.system(size: 13))
                    .foregroundStyle(Self.red)
            }
        }
    }

    /// 回车：认出网址后先读标题和图标，出一张预览等“添加”。
    private func readLink() {
        guard !context.isPreview else { return }
        let text = newLink.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // 预览已经出来了，再按一次回车就是“添加”。
        if let pending, pending.text == text {
            if !pending.loading { commitPending() }
            return
        }
        switch BookmarkList.adding(text, to: entries) {
        case .invalid:
            notice = tr("认不出网址，试试 example.com 或 https://…")
        case .duplicate:
            notice = tr("已经在书签里了")
        case .full:
            notice = tr("最多 \(Bookmark.maxCount) 个书签，先删掉几个")
        case .added:
            guard let link = Bookmark(parsing: text) else { return }
            let web = LinkPreview.needsFetch(link.url, stored: nil)
            notice = nil
            withAnimation(.snappy(duration: 0.2)) {
                pending = Pending(text: text, url: link.url, preview: nil, loading: web)
            }
            guard web else { return }
            Task {
                let fetched = await LinkPreviewFetcher.fetch([link.url]).first
                guard pending?.url == link.url else { return }
                pending?.preview = fetched ?? LinkPreview.failure(link.url)
                pending?.loading = false
            }
        }
    }

    @ViewBuilder
    private var pendingCard: some View {
        if let pending {
            let link = Bookmark(parsing: pending.text) ?? Bookmark(title: Bookmark.shortHost(pending.url), url: pending.url)
            let title = link.displayTitle(pending.preview)
            HStack(spacing: 10) {
                BookmarkSquare(link: Bookmark(title: title, url: pending.url), icon: nil,
                               pageIcon: pending.preview?.icon, size: 32, autoFetch: !pending.loading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.panelPrimary)
                    Text(pendingStatus(pending))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.panelSecondary)
                }
                .lineLimit(1)
                Spacer(minLength: 4)
                if pending.loading { ProgressView().controlSize(.small) }
                Button { commitPending() } label: {
                    Text(tr("添加"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(accentInk)
                        .padding(.horizontal, 16)
                        .frame(height: 30)
                        .background(Capsule().fill(accent))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                Button {
                    withAnimation(.snappy(duration: 0.2)) { self.pending = nil }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.panelSecondary)
                        .frame(width: 22, height: 30)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(tr("取消"))
                .accessibilityLabel(tr("取消"))
            }
            .padding(.horizontal, 12)
            .frame(height: 56)
            .glassPane(cornerRadius: 12)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private func pendingStatus(_ pending: Pending) -> String {
        if pending.loading { return tr("正在读取标题和图标…") }
        guard let preview = pending.preview else { return Bookmark.shortHost(pending.url) }
        if preview.failed || !preview.hasContent { return tr("没读到标题，先用网址") }
        return preview.icon == nil ? tr("已读到标题") : tr("已读到标题和图标")
    }

    /// 点“添加”：加在最后，读到的预览一起存；在某个分组下加的也放进那个分组。
    private func commitPending() {
        guard let pending, !context.isPreview else { return }
        let latest = entries
        guard case .added(let next) = BookmarkList.adding(pending.text, to: latest) else {
            notice = tr("已经在书签里了")
            self.pending = nil
            return
        }
        let into = shownTab
        let groupsNow = groups
        write { config in
            config.set("links", .list(next.map { .string($0) }))
            if let preview = pending.preview { LinkPreview.store([preview], in: &config) }
            if let into {
                BookmarkGroups.write(BookmarkGroups.moving(pending.url, to: into, in: groupsNow), into: &config)
            }
        }
        withAnimation(.snappy(duration: 0.2)) {
            self.pending = nil
            newLink = ""
        }
    }

    // MARK: 网格

    private var grid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 4)
        let rows = (visible.count + 3) / 4
        let cells = LazyVGrid(columns: columns, spacing: 0) {
            ForEach(visible, id: \.url) { link in cell(link) }
        }
        return Group {
            if rows > 4 {
                ScrollView { cells }
                    .scrollIndicators(.never)
                    .frame(height: Self.cellHeight * 4)
            } else {
                cells
            }
        }
    }

    private func cell(_ link: Bookmark) -> some View {
        let key = link.url.absoluteString
        let preview = previews[key]
        let title = link.displayTitle(preview)
        let summary = preview?.hasContent == true ? preview?.summary : nil
        return Button {
            guard !context.isPreview else { return }
            NSWorkspace.shared.open(link.url)
        } label: {
            VStack(spacing: 7) {
                ZStack(alignment: .topTrailing) {
                    BookmarkSquare(link: Bookmark(title: title, url: link.url),
                                   icon: BookmarkIcons.icon(for: link.url, in: icons),
                                   pageIcon: preview?.icon, size: 48,
                                   autoFetch: !LinkPreview.needsFetch(link.url, stored: preview))
                    if refreshing.contains(key) {
                        ProgressView().controlSize(.mini).offset(x: 6, y: -6)
                    }
                }
                Text(verbatim: title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.cellHeight, alignment: .top)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help([title, summary, key].compactMap { $0 }.joined(separator: "\n"))
        .accessibilityLabel(tr("打开 \(title)"))
        .contextMenu { menu(link) }
    }

    @ViewBuilder
    private func menu(_ link: Bookmark) -> some View {
        let key = link.url.absoluteString
        Button(tr("打开")) { NSWorkspace.shared.open(link.url) }
        if !context.isPreview {
            Button(tr("编辑名称和图标…")) { openForm(link) }
        }
        Button(tr("拷贝网址")) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(key, forType: .string)
        }
        if LinkPreview.needsFetch(link.url, stored: nil) {
            Button(tr("刷新预览")) { refresh([link]) }
        }
        if let xyz = link.xiaoyuzhou {
            if PodcastService.shared.isSubscribed(xyz) {
                Button(tr("已在播客中")) {}.disabled(true)
            } else {
                Button(tr("加到播客")) { addToPodcast(xyz, key: key) }
                    .disabled(context.isPreview || addingPodcast.contains(key))
            }
        }
        if unlocked, !groups.isEmpty, !context.isPreview {
            Menu(tr("移到分组")) { moveMenu(link.url) }
        }
        if !context.isPreview {
            Divider()
            Button(tr("删除"), role: .destructive) { delete(link) }
        }
    }

    @ViewBuilder
    private func moveMenu(_ url: URL) -> some View {
        let now = BookmarkGroups.group(of: url, in: groups)
        ForEach(groups.map(\.name), id: \.self) { name in
            Button(name) { move(url, to: name) }.disabled(name == now)
        }
        if now != nil {
            Divider()
            Button(tr("移出分组")) { move(url, to: nil) }
        }
    }

    /// 虚线框：拖到卡片（或这个面板）上就能加入。
    private var dropHint: some View {
        HStack(spacing: 14) {
            Image(systemName: "arrow.down")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(accent.panelReadable)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("把链接拖到卡片上就能加入"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                Text(tr("浏览器地址栏、聊天里的链接都行"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.panelFill)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(accent.opacity(0.6), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
        }
    }

    // MARK: 编辑

    @ViewBuilder
    private var edit: some View {
        addField
        pendingCard
        Text(tr("\(shownTab ?? tr("全部")) · \(visible.count) 个"))
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.panelSecondary)
            .padding(.top, 2)
        if visible.isEmpty {
            Text(tr("这里还没有书签"))
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
        } else {
            editList
        }
        moveBar
    }

    private var editList: some View {
        let list = visible
        let from = dragging.flatMap { id in list.firstIndex { $0.url.absoluteString == id } }
        let target = from.map {
            WorldClockList.dropIndex(from: $0, translation: dragOffset, rowHeight: Self.rowHeight, count: list.count)
        }
        let rows = VStack(spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.element.url) { index, link in
                editRow(link, index: index, list: list)
                    .offset(y: rowShift(index, from: from, target: target))
                    .zIndex(link.url.absoluteString == dragging ? 1 : 0)
            }
        }
        return Group {
            if list.count > 7 {
                ScrollView { rows }
                    .scrollIndicators(.never)
                    .frame(height: Self.rowHeight * 7)
            } else {
                rows
            }
        }
    }

    /// 拖动时：被拖的那行跟着手走，经过的行让开一格。
    private func rowShift(_ index: Int, from: Int?, target: Int?) -> CGFloat {
        guard let from, let target else { return 0 }
        if index == from { return dragOffset }
        if from < target, (from + 1...target).contains(index) { return -Self.rowHeight }
        if target < from, (target..<from).contains(index) { return Self.rowHeight }
        return 0
    }

    private func editRow(_ link: Bookmark, index: Int, list: [Bookmark]) -> some View {
        let key = link.url.absoluteString
        let preview = previews[key]
        let title = link.displayTitle(preview)
        let lifted = dragging == key
        let revealing = pendingDelete == key
        let chosen = selected == key
        let group = unlocked ? BookmarkGroups.group(of: link.url, in: groups) : nil
        // 露出的“删除”放在行的上面一层，而且行的点按区域跟着行一起左移（先 contentShape
        // 再 offset）：之前 contentShape 写在 offset 后面，点按区域还是整行，盖住了右边
        // 露出的“删除”，一点就被行的点按吃掉，只是收起，删不掉。
        return ZStack(alignment: .trailing) {
            HStack(spacing: 10) {
                handle(link, index: index, list: list, lifted: lifted)
                Button { openForm(link) } label: {
                    BookmarkSquare(link: Bookmark(title: title, url: link.url),
                                   icon: BookmarkIcons.icon(for: link.url, in: icons),
                                   pageIcon: preview?.icon, size: 28,
                                   autoFetch: !LinkPreview.needsFetch(link.url, stored: preview))
                }
                .buttonStyle(.plain)
                .help(tr("换图标"))
                .accessibilityLabel(tr("编辑\(title)的名称和图标"))
                VStack(alignment: .leading, spacing: 2) {
                    if renaming == key {
                        TextField("", text: $renameText, prompt: Text(verbatim: title))
                            .focused($focus, equals: .rename)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.panelPrimary)
                            .onSubmit { commitRename() }
                            .padding(.horizontal, 6)
                            .frame(height: 24)
                            .background(RoundedRectangle(cornerRadius: 7).fill(.panelFill))
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(accent.opacity(0.9), lineWidth: 1.2))
                    } else {
                        Text(verbatim: title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.panelPrimary)
                            .contentShape(.rect)
                            .onTapGesture { startRename(link, title: title) }
                            .help(tr("点名字改名"))
                    }
                    Text(verbatim: [Bookmark.shortHost(link.url), group].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.panelSecondary)
                }
                .lineLimit(1)
                Spacer(minLength: 4)
                if !revealing {
                    Button {
                        withAnimation(.snappy(duration: 0.22)) { pendingDelete = key }
                    } label: {
                        ZStack {
                            Circle().fill(Self.red.opacity(0.18))
                            Capsule().fill(Self.red).frame(width: 10, height: 2)
                        }
                        .frame(width: 22, height: 22)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help(tr("删除这个书签"))
                    .accessibilityLabel(tr("删除 \(title)"))
                }
            }
            .padding(.leading, 6)
            .padding(.trailing, revealing ? 8 : 10)
            .frame(height: Self.rowHeight - 4)
            .contentShape(.rect)
            .onTapGesture {
                withAnimation(.snappy(duration: 0.2)) {
                    if pendingDelete != nil {
                        pendingDelete = nil
                    } else {
                        selected = chosen ? nil : key
                    }
                }
            }
            .offset(x: revealing ? -Self.deleteWidth : 0)
            if revealing {
                Button { delete(link) } label: {
                    Text(tr("删除"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: Self.deleteWidth, height: Self.rowHeight - 4)
                        .background(Color(red: 0.85, green: 0.18, blue: 0.13))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("删除 \(title)"))
                .transition(.move(edge: .trailing))
                .zIndex(1)
            }
        }
        .frame(height: Self.rowHeight - 4)
        .clipShape(.rect(cornerRadius: 12, style: .continuous))
        .background { rowBackground(lifted: lifted) }
        .overlay { rowBorder(lifted: lifted, chosen: chosen) }
        .offset(x: lifted ? 8 : 0)
        .frame(height: Self.rowHeight)
        .contextMenu { menu(link) }
    }

    private func rowBackground(lifted: Bool) -> some View {
        // 拖起来的那一行要盖住下面的行，用实心底，跟着浅色/深色走。
        let fill: Color = lifted
            ? Color.panelDynamic(dark: NSColor(srgbRed: 0.23, green: 0.23, blue: 0.25, alpha: 1),
                                 light: NSColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: 1))
            : Color.panelFill
        let shadow: Color = Color.black.opacity(lifted ? 0.35 : 0)
        return RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(fill)
            .shadow(color: shadow, radius: 6, y: 4)
    }

    private func rowBorder(lifted: Bool, chosen: Bool) -> some View {
        let marked = lifted || chosen
        let colour: Color = marked ? accent.opacity(lifted ? 0.7 : 0.9) : Color.panelStroke
        return RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(colour, lineWidth: marked ? 1 : 0.6)
    }

    /// 左边把手：按住拖动排序，松手时落到最近的一格。
    private func handle(_ link: Bookmark, index: Int, list: [Bookmark], lifted: Bool) -> some View {
        let key = link.url.absoluteString
        let urls = list.map(\.url)
        return Image(systemName: "line.3.horizontal")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.panelPrimary.opacity(lifted ? 0.85 : 0.5))
            .frame(width: 24, height: Self.rowHeight - 4)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { value in
                        if dragging != key {
                            commitRename()
                            dragging = key
                            pendingDelete = nil
                        }
                        dragOffset = value.translation.height
                    }
                    .onEnded { value in
                        let to = WorldClockList.dropIndex(from: index, translation: value.translation.height,
                                                          rowHeight: Self.rowHeight, count: list.count)
                        saveLinks(BookmarkList.moving(from: index, to: to, visible: urls, in: entries))
                        withAnimation(.snappy(duration: 0.2)) {
                            dragging = nil
                            dragOffset = 0
                        }
                    }
            )
            .help(tr("拖动调整顺序"))
            .accessibilityLabel(tr("调整\(link.title)的顺序"))
            .accessibilityAction(named: tr("上移")) {
                saveLinks(BookmarkList.moving(from: index, to: index - 1, visible: urls, in: entries))
            }
            .accessibilityAction(named: tr("下移")) {
                saveLinks(BookmarkList.moving(from: index, to: index + 1, visible: urls, in: entries))
            }
    }

    // MARK: 移到分组（Pro）

    private var moveBar: some View {
        let chosenURL = selected.flatMap { URL(string: $0) }
        let now = chosenURL.flatMap { BookmarkGroups.group(of: $0, in: groups) }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(tr("移到分组"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                Spacer(minLength: 0)
                ProBadge()
            }
            if newGroup != nil, mode == .edit {
                newGroupField
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        if unlocked {
                            ForEach(groups.map(\.name).filter { $0 != now }, id: \.self) { name in
                                movePill(name, enabled: chosenURL != nil) {
                                    if let chosenURL { move(chosenURL, to: name) }
                                }
                            }
                            if now != nil {
                                movePill(tr("移出分组"), enabled: true) {
                                    if let chosenURL { move(chosenURL, to: nil) }
                                }
                            }
                        }
                        movePill(tr("新建"), enabled: true) { startNewGroup() }
                    }
                }
                .scrollIndicators(.never)
            }
            if unlocked, chosenURL == nil, newGroup == nil {
                Text(tr("先点一行选中书签"))
                    .font(.system(size: 13))
                    .foregroundStyle(.panelTertiary)
            }
        }
        .padding(12)
        .glassPane(cornerRadius: 12)
    }

    private func movePill(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelPrimary.opacity(enabled ? 0.92 : 0.4))
                .lineLimit(1)
                .padding(.horizontal, 13)
                .frame(height: 28)
                .background(Capsule().fill(.panelFill))
                .overlay(Capsule().strokeBorder(.panelStroke, lineWidth: 0.6))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func move(_ url: URL, to name: String?) {
        guard ProLicenseGate.canUseBookmarkGroups(unlocked: unlocked) else {
            PaywallWindow.shared.show()
            return
        }
        let next = BookmarkGroups.moving(url, to: name, in: groups)
        write { BookmarkGroups.write(next, into: &$0) }
    }

    // MARK: 改名、删除

    private func startRename(_ link: Bookmark, title: String) {
        guard !context.isPreview else { return }
        commitRename()
        renameText = title
        renaming = link.url.absoluteString
        pendingDelete = nil
        WidgetDetailWindow.shared.focusField { focus = .rename }
    }

    private func commitRename() {
        guard let key = renaming, let url = URL(string: key) else { return }
        renaming = nil
        let next = BookmarkList.renaming(url, to: renameText, in: entries)
        if next != entries { saveLinks(next) }
    }

    private func delete(_ link: Bookmark) {
        guard !context.isPreview else { return }
        let key = link.url.absoluteString
        if renaming == key { renaming = nil }
        withAnimation(.snappy(duration: 0.22)) {
            saveLinks(BookmarkList.removing(link.url, from: entries))
            pendingDelete = nil
            if selected == key { selected = nil }
        }
    }

    // MARK: 写回

    private func write(_ change: (inout WidgetConfig) -> Void) {
        guard !context.isPreview else { return }
        BookmarkConfigWriter.write(current, change)
        revision += 1
    }

    /// 写回书签列表，顺手清掉已经删掉的书签的预览和图标（上传的图片文件一起删）；解锁时也清掉分组里的旧网址
    /// （没解锁时分组一个字不动）。
    private func saveLinks(_ next: [String]) {
        let prune = unlocked
        let groupsNow = groups
        write { config in
            config.set("links", .list(next.map { .string($0) }))
            LinkPreview.store([], in: &config)
            BookmarkIcons.prune(&config)
            if prune, !groupsNow.isEmpty {
                BookmarkGroups.write(BookmarkGroups.pruned(groupsNow, links: Bookmark.list(next)), into: &config)
            }
        }
    }

    // MARK: 播客

    private func addToPodcast(_ link: XiaoyuzhouLink, key: String) {
        addingPodcast.insert(key)
        podcastStatus = tr("正在加到播客…")
        Task {
            let result = await PodcastService.shared.add(link)
            addingPodcast.remove(key)
            switch result {
            case .success(let show):
                podcastStatus = tr("已加入「\(show.title)」")
            case .failure(let failure):
                podcastStatus = failure.message
            }
        }
    }

    // MARK: 刷新

    private func refresh(_ chosen: [Bookmark]) {
        let urls = chosen.map(\.url).filter { LinkPreview.needsFetch($0, stored: nil) }
        guard !urls.isEmpty, !context.isPreview else { return }
        for url in urls { refreshing.insert(url.absoluteString) }
        Task {
            let fetched = await LinkPreviewFetcher.fetch(urls)
            for url in urls { refreshing.remove(url.absoluteString) }
            // A refresh that failed keeps what was read before.
            let stored = LinkPreview.stored(current.config)
            let kept = fetched.filter { !$0.failed || stored[$0.url]?.hasContent != true }
            if !kept.isEmpty {
                BookmarkPreviews.save(kept, in: current)
                revision += 1
            }
        }
    }
}

/// 网格里的网站图标：圆角方块。画法见 `BookmarkGlyph`：选过的文字图标、上传
/// 的图片；没选过时有本地缓存的网站图标就放在白色底板上，没有是首字加按域名取的颜色。
struct BookmarkSquare: View {
    var link: Bookmark
    var icon: BookmarkIcon?
    var pageIcon: String?
    var size: CGFloat
    var autoFetch: Bool = true

    var body: some View {
        BookmarkGlyph(link: link, icon: icon, pageIcon: pageIcon, size: size, round: false, autoFetch: autoFetch)
    }
}
