import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Cards

/// One library card: a (kind, variant) pair. A kind without declared variants
/// contributes exactly one card carrying the catalog name.
private struct LibraryCard: Identifiable {
    var id: String
    var kind: WidgetKind
    /// Variant title, or the catalog name when the kind has no variants.
    var title: String
    /// Catalog name - searched even when a variant supplies the title.
    var name: String
    var category: WidgetCategory
    var overrides: [String: WidgetConfig.Value]
    /// Stable instance for the live preview, so the tile keeps its identity
    /// across re-renders. Adding always mints a fresh one.
    var preview: WidgetInstance

    func matches(_ query: String) -> Bool {
        WidgetSearch.matches(query, names: [title, name], kind: kind.rawValue)
    }
}

/// Only self-contained kinds: the rest cannot be rendered in this build.
/// Sorted by `WidgetLibraryGroups.displayOrder`, so each category lists its
/// widgets in the order the categories were drawn up in; the sort is stable,
/// so a kind's variants keep their own order.
private let libraryCards: [LibraryCard] = WidgetCatalog.entries
    .filter(\.selfContained)
    .enumerated()
    .sorted { (WidgetLibraryGroups.rank($0.element.kind), $0.offset) < (WidgetLibraryGroups.rank($1.element.kind), $1.offset) }
    .map(\.element)
    .flatMap { entry -> [LibraryCard] in
        let variants = entry.variants.isEmpty
            ? [(title: entry.name, overrides: [String: WidgetConfig.Value]())]
            : entry.variants
        return variants.enumerated().compactMap { index, variant in
            guard let preview = WidgetCatalog.make(entry.kind, overrides: variant.overrides) else { return nil }
            return LibraryCard(id: "\(entry.kind.rawValue)#\(index)",
                               kind: entry.kind,
                               title: variant.title,
                               name: entry.name,
                               category: entry.category,
                               overrides: variant.overrides,
                               preview: preview)
        }
    }

/// How many widgets (not variants) a set of cards holds.
private func widgetCount(_ cards: [LibraryCard]) -> Int {
    WidgetLibraryGroups.kindCount(cards.map(\.kind))
}

/// 推荐：精选加标“新”的，每个小组件只放第一张卡片（默认样式）。
private let recommendedCards: [LibraryCard] = {
    let kinds = WidgetLibraryGroups.recommended(available: libraryCards.map(\.kind))
    return kinds.compactMap { kind in libraryCards.first { $0.kind == kind } }
}()

/// Categories with at least one widget, in sidebar order. 应用和文件夹 has
/// its own row, so it is left out here.
private let sidebarCategories: [WidgetCategory] =
    WidgetLibraryGroups.visibleCategories(libraryCards.map(\.category), alwaysShown: [])
        .filter { $0 != .appsAndFolders }

/// 一个分区里的一组卡片。分类里每种小组件一组，带小标题；搜索结果和推荐
/// 不分组，整个分区是一组，`kind` 为 nil，不画小标题。
private struct LibraryGroup: Identifiable {
    var id: String
    var kind: WidgetKind?
    var cards: [LibraryCard]
}

private enum LibrarySelection: Hashable {
    case all
    case recommended
    case appsAndFolders
    case category(WidgetCategory)
}

private enum LibraryFocus: Hashable {
    case search
    case card(String)
}

// MARK: - Apps and folders

/// A common app or folder offered in the library, so the shelf can be filled
/// without dragging from Finder. `url == nil` is the "more" tile that opens a
/// file picker.
private struct LibraryShortcut: Identifiable {
    var id: String
    var title: String
    var url: URL?
    var isFolder: Bool

    var item: DockItem? {
        guard let url else { return nil }
        return Self.item(for: url)
    }

    static func item(for url: URL) -> DockItem {
        if url.pathExtension == "app" {
            return .app(id: UUID(), bundleID: Bundle(url: url)?.bundleIdentifier ?? "", ref: .capture(url))
        }
        return .folder(id: UUID(), ref: .capture(url), icon: FolderIcon())
    }

    func matches(_ query: String) -> Bool {
        guard url != nil else { return false }
        let english = url?.deletingPathExtension().lastPathComponent ?? ""
        return WidgetSearch.matches(query, names: [title, english], kind: "")
    }

    /// Apps without their ".app", and the home folder as 个人 rather than
    /// the account's short name.
    private static func named(_ url: URL, folder: Bool) -> LibraryShortcut {
        let system = FileManager.default.displayName(atPath: url.path)
        let title = folder
            ? WidgetLibraryGroups.folderTitle(path: url.path, systemName: system,
                                              homePath: FileManager.default.homeDirectoryForCurrentUser.path)
            : WidgetLibraryGroups.appTitle(system)
        return LibraryShortcut(id: url.path, title: title, url: url, isFolder: folder)
    }

    static let apps: [LibraryShortcut] = {
        let paths = [
            "/System/Library/CoreServices/Finder.app",
            "/Applications/Safari.app",
            "/System/Applications/Mail.app",
            "/System/Applications/Messages.app",
            "/System/Applications/Notes.app",
            "/System/Applications/Calendar.app",
            "/System/Applications/Music.app",
            "/System/Applications/Photos.app",
            "/System/Applications/App Store.app",
            "/System/Applications/System Settings.app",
        ]
        return paths.map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map { named($0, folder: false) }
            + [LibraryShortcut(id: "more-apps", title: tr("更多应用…"), url: nil, isFolder: false)]
    }()

    static let folders: [LibraryShortcut] = {
        let fm = FileManager.default
        let dirs: [FileManager.SearchPathDirectory] = [
            .applicationDirectory, .downloadsDirectory, .documentDirectory, .desktopDirectory,
            .picturesDirectory, .moviesDirectory, .musicDirectory,
        ]
        var urls = dirs.compactMap { dir -> URL? in
            dir == .applicationDirectory
                ? fm.urls(for: dir, in: .localDomainMask).first
                : fm.urls(for: dir, in: .userDomainMask).first
        }
        urls.append(fm.homeDirectoryForCurrentUser)
        return urls.filter { fm.fileExists(atPath: $0.path) }
            .map { named($0, folder: true) }
            + [LibraryShortcut(id: "more-folders", title: tr("更多文件夹…"), url: nil, isFolder: true)]
    }()

    static var all: [LibraryShortcut] { apps + folders }
}

// MARK: - Library

/// The **Add Widget** browser. Sized for a sheet; the host owns presentation.
struct WidgetLibraryView: View {
    var onAdd: (WidgetInstance) -> Void
    var onAddItem: (DockItem) -> Void
    /// 「应用分组」：在扩展栏上放一个空组并打开它。
    var onAddGroup: () -> Void
    /// 「文件夹分组」：在扩展栏上放一个空的文件夹分组并打开它。
    var onAddFolderGroup: () -> Void
    /// Widgets sitting directly on the active shelf, read in `body` so the
    /// library's minus buttons follow additions and removals as they happen.
    var placed: () -> [WidgetInstance]
    var onRemove: (UUID) -> Void
    var onClose: () -> Void

    /// - Parameter initialCategory: the sidebar row the sheet opens on; nil
    ///   is 所有小组件, which is what the app always uses. The README's
    ///   screenshot tool opens it on a category instead.
    init(onAdd: @escaping (WidgetInstance) -> Void,
         onAddItem: @escaping (DockItem) -> Void = { _ in },
         onAddGroup: @escaping () -> Void = {},
         onAddFolderGroup: @escaping () -> Void = {},
         placed: @escaping () -> [WidgetInstance] = { [] },
         onRemove: @escaping (UUID) -> Void = { _ in },
         onClose: @escaping () -> Void,
         initialCategory: WidgetCategory? = nil) {
        self.onAdd = onAdd
        self.onAddItem = onAddItem
        self.onAddGroup = onAddGroup
        self.onAddFolderGroup = onAddFolderGroup
        self.placed = placed
        self.onRemove = onRemove
        self.onClose = onClose
        _selection = State(initialValue: initialCategory.map { LibrarySelection.category($0) } ?? .all)
    }

    private static let sidebarWidth: CGFloat = 175
    private static let cardWidth: CGFloat = 168
    /// 底栏留够两行 13pt 名字的高度，长名字换行而不是截成「…」。
    private static let cardFooterHeight: CGFloat = 34
    /// 卡片顶边的角标行（Pro、「新」），没有角标的卡片空着，见 `BadgeStrip`。
    private static var cardBadgeHeight: CGFloat { BadgeStrip.height(compact: false) }
    /// 10 + 角标行 20 + 4 + 预览 62 + 6 + 底栏 34 + 10。
    private static let cardHeight: CGFloat = 146
    private static let columns = 3

    @State private var selection: LibrarySelection = .all
    @State private var search = ""
    @FocusState private var focus: LibraryFocus?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            browser
        }
        .frame(width: 760, height: 470)
        .background(.regularMaterial)
        .onExitCommand(perform: onClose)
        .defaultFocus($focus, .search)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            searchField
                .padding(10)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    // Counts are widgets, not variants: 时钟 is one widget
                    // however many faces it offers.
                    row(.all, symbol: "square.grid.2x2", title: tr("所有小组件"),
                        count: widgetCount(libraryCards), enabled: true)
                    if !recommendedCards.isEmpty {
                        row(.recommended, symbol: "star", title: tr("推荐"),
                            count: recommendedCards.count, enabled: true)
                    }
                    row(.appsAndFolders, symbol: WidgetCategory.appsAndFolders.symbol,
                        title: WidgetCategory.appsAndFolders.displayName,
                        count: LibraryShortcut.all.filter { $0.url != nil }.count + 2
                            + widgetCount(libraryCards.filter { $0.category == .appsAndFolders }),
                        enabled: true)
                    // A category with nothing in it is not listed at all.
                    ForEach(sidebarCategories, id: \.self) { category in
                        row(.category(category), symbol: category.symbol,
                            title: category.displayName,
                            count: widgetCount(libraryCards.filter { $0.category == category }),
                            enabled: true)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
            }
        }
        .frame(width: Self.sidebarWidth)
        .background(.quaternary.opacity(0.35))
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索", text: $search)
                .textFieldStyle(.plain)
                .focused($focus, equals: .search)
                .onKeyPress(.downArrow) {
                    guard let first = flatCards.first else { return .ignored }
                    focus = .card(first.id)
                    return .handled
                }
                .onSubmit {
                    if let first = flatCards.first { add(first) }
                }
            if !search.isEmpty {
                Button {
                    search = ""
                    focus = .search
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.background.secondary))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.quaternary))
    }

    private func row(_ item: LibrarySelection, symbol: String, title: String,
                     count: Int, enabled: Bool) -> some View {
        let selected = selection == item
        return Button { selection = item } label: {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 12))
                    .frame(width: 16)
                Text(title).font(.system(size: 13))
                Spacer(minLength: 0)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(selected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
                }
            }
            .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(enabled ? .primary : .tertiary))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.clear))
            }
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        // Empty categories are no longer listed, so every row is enabled
        // today; the explanation stays for any row that ever is not.
        .help(enabled ? "" : tr("这里还没有小组件。"))
        .accessibilityHint(enabled ? "" : tr("此类别中还没有小组件。"))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Browser

    private var browser: some View {
        VStack(spacing: 0) {
            // The panel carries no system title bar, so this header is the
            // only chrome - it has to hold the title and the way out.
            HStack(spacing: 8) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("添加小组件").font(.system(size: 14, weight: .semibold))
                Text("\(widgetCount(libraryCards))")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(.quaternary))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            Divider()
            if flatCards.isEmpty && visibleShortcuts.isEmpty && !showsGroupShortcut && !showsFolderGroupShortcut {
                empty
            } else {
                grid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 22))
            Text("没有匹配的小组件").font(.system(size: 13))
            Text("也可以试试拼音、首字母或英文，比如 tianqi、tq、weather")
                .font(.system(size: 13))
        }
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if !visibleShortcuts.isEmpty || showsGroupShortcut || showsFolderGroupShortcut {
                        shortcutsSection
                    }
                    ForEach(sections, id: \.title) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(section.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            // 分类里每种小组件一组：小标题是种类名，组与组之间一条细线，
                            // 一眼能看出这个分类里有几种小组件、每种有几个样式。
                            ForEach(Array(section.groups.enumerated()), id: \.element.id) { index, group in
                                VStack(alignment: .leading, spacing: 8) {
                                    if index > 0, group.kind != nil {
                                        Divider()
                                            .padding(.top, 4)
                                            .padding(.bottom, 2)
                                    }
                                    if let kind = group.kind {
                                        groupHeader(kind, styles: group.cards.count)
                                    }
                                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.cardWidth), spacing: 12),
                                                             count: Self.columns),
                                              alignment: .leading, spacing: 12) {
                                        ForEach(group.cards) { card in
                                            cardView(card, grouped: group.kind != nil)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .onChange(of: focus) { _, new in
                if case .card(let id) = new { withAnimation { proxy.scrollTo(id, anchor: .center) } }
            }
        }
    }

    /// 一组的小标题：种类名称，整种是 Pro 时带 Pro 角标，有多个样式时后面
    /// 标样式个数，有说明的再跟一句（提醒事项“和系统提醒事项同步”）。
    private func groupHeader(_ kind: WidgetKind, styles: Int) -> some View {
        let name = WidgetCatalog.entry(kind)?.name ?? kind.rawValue
        return HStack(spacing: 5) {
            Text(name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.85))
                .accessibilityAddTraits(.isHeader)
            if ProFeatures.isProKind(kind) {
                ProBadge()
            }
            if styles > 1 {
                Text(tr("\(styles) 种样式"))
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            if let note = WidgetLibraryGroups.note(kind) {
                Text(note)
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
            }
            if let hint = WidgetLibraryGroups.proHint(kind) {
                proHintButton(hint)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// 小标题旁的「也能在刘海里用 Pro」：已解锁时打开设置 ▸ AI（刘海入口开关在那），
    /// 没解锁时弹付费墙。只是一句提示，不是新的库样式。
    private func proHintButton(_ hint: String) -> some View {
        Button {
            if ProLicenseGate.canOpenAINotch(unlocked: ProAccess.isUnlocked),
               let app = AIChatCenter.shared.app {
                SettingsWindow.shared.show(app: app, tab: "AI")
            } else {
                PaywallWindow.shared.show()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                Text(hint)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .fixedSize()
                ProBadge()
            }
            .foregroundStyle(Color.accentColor)
            .padding(.leading, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(ProAccess.isUnlocked
              ? tr("AI 助手的对话也能挂在刘海下面：点一下打开设置 ▸ AI")
              : tr("AI 助手的对话也能挂在刘海下面，码头 Pro 功能：点一下看看解锁"))
        .accessibilityLabel(tr("\(hint)，码头 Pro"))
    }

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("应用和文件夹")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            // 底对齐：带 Pro 角标的分组入口比别的格子多一行角标，图标和名字仍和同排对齐。
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76, maximum: 84), spacing: 8, alignment: .bottom)],
                      alignment: .leading, spacing: 10) {
                if showsGroupShortcut {
                    groupShortcutView
                }
                if showsFolderGroupShortcut {
                    folderGroupShortcutView
                }
                ForEach(visibleShortcuts) { shortcut in
                    shortcutView(shortcut)
                }
            }
        }
    }

    private func shortcutView(_ shortcut: LibraryShortcut) -> some View {
        Button { add(shortcut) } label: {
            VStack(spacing: 5) {
                Group {
                    if let url = shortcut.url {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable()
                            .interpolation(.high)
                    } else {
                        Image(systemName: shortcut.isFolder ? "folder.badge.plus" : "plus.app")
                            .font(.system(size: 22))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 40, height: 40)
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(shortcut.url == nil ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear)))
                Text(shortcut.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(width: 76)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .contextMenu {
            // 添加 App 时顺手换显示图标（Pro）。没解锁时弹付费墙，不添加；直接点照旧免费添加。
            if !shortcut.isFolder {
                Button(DockAppIconPicker.menuTitle(tr("添加并更换图标…"))) { addChangingIcon(shortcut) }
            }
        }
        .help(shortcut.url == nil ? tr("选择其他\(shortcut.isFolder ? tr("文件夹") : tr("应用"))") : tr("添加到扩展栏"))
        .accessibilityLabel(shortcut.url == nil ? shortcut.title : tr("添加“\(shortcut.title)”"))
    }

    /// 「应用分组」：一个空组的样子（虚线框加「＋」），点一下在扩展栏上放一个
    /// 空组并打开它，再往里加 App。Pro：没解锁时弹付费墙，不新建。
    private var groupShortcutView: some View {
        groupShortcut(group: DockGroup(name: "", keepsEmpty: true),
                      title: tr("应用分组"),
                      help: tr("在扩展栏上放一个空分组，再把几个 App 收进去"),
                      label: tr("添加应用分组"),
                      action: onAddGroup)
    }

    /// 「文件夹分组」：空的文件夹分组（虚线框加文件夹＋），点一下在扩展栏上放一个，
    /// 再往里加几个常用文件夹，点开在浏览小窗里切换着看。Pro，同上。
    private var folderGroupShortcutView: some View {
        groupShortcut(group: DockGroup(name: "", keepsEmpty: true, kind: .folders),
                      title: tr("文件夹分组"),
                      help: tr("在扩展栏上放一个文件夹分组，收几个常用文件夹，点开切换着看"),
                      label: tr("添加文件夹分组"),
                      action: onAddFolderGroup)
    }

    /// 两种分组入口共用的样子：顶边一行 Pro 角标（固定显示，不随解锁变；在格子以内、
    /// 不压空组图标，见 `FeatureBadges` 的规则）、空组格子、名字。
    private func groupShortcut(group: DockGroup, title: String, help: String, label: String,
                               action: @escaping () -> Void) -> some View {
        Button {
            guard ProLicenseGate.canCreateShelfGroup(unlocked: ProAccess.isUnlocked) else {
                PaywallWindow.shared.show()
                return
            }
            action()
        } label: {
            VStack(spacing: 5) {
                BadgeStrip(pro: true, new: false)
                GroupTile(group: group, side: 40)
                    .frame(width: 52, height: 52)
                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(width: 76)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(label)
        .accessibilityHint(ProFeatures.label)
    }

    /// 搜「文件夹分组」「folder group」也能找到它。
    private var showsFolderGroupShortcut: Bool {
        let query = search.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            return WidgetSearch.matches(query, names: [tr("文件夹分组"), "Folder Group", "folders", "tabs"],
                                        kind: "")
        }
        switch selection {
        case .all, .appsAndFolders: return true
        case .category, .recommended: return false
        }
    }

    /// 搜「分组」「group」「fenzu」也能找到它。
    private var showsGroupShortcut: Bool {
        let query = search.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            return WidgetSearch.matches(query, names: [tr("应用分组"), "App Group", "folder", "stack"],
                                        kind: "")
        }
        switch selection {
        case .all, .appsAndFolders: return true
        case .category, .recommended: return false
        }
    }

    private var visibleShortcuts: [LibraryShortcut] {
        let query = search.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty { return LibraryShortcut.all.filter { $0.matches(query) } }
        switch selection {
        case .all, .appsAndFolders: return LibraryShortcut.all
        case .category, .recommended: return []
        }
    }

    private func add(_ shortcut: LibraryShortcut, changingIcon: Bool = false) {
        if let item = shortcut.item {
            onAddItem(item)
            if changingIcon { changeIcon(of: [item]) }
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = !shortcut.isFolder
        panel.canChooseDirectories = shortcut.isFolder
        panel.allowsMultipleSelection = true
        panel.prompt = tr("添加")
        // 选 App 时面板底部多一个勾选框「添加后更换图标」（Pro）。
        var iconBox: NSButton?
        if !shortcut.isFolder {
            panel.allowedContentTypes = [.applicationBundle]
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
            let box = NSButton(checkboxWithTitle: DockAppIconPicker.menuTitle(tr("添加后更换图标")),
                               target: nil, action: nil)
            box.font = .systemFont(ofSize: 13)
            box.state = changingIcon ? .on : .off
            box.sizeToFit()
            let holder = NSView(frame: NSRect(x: 0, y: 0, width: box.frame.width + 32, height: box.frame.height + 16))
            box.setFrameOrigin(NSPoint(x: 16, y: 8))
            holder.addSubview(box)
            panel.accessoryView = holder
            panel.isAccessoryViewDisclosed = true
            iconBox = box
        }
        guard panel.runModal() == .OK else { return }
        let items = panel.urls.map { LibraryShortcut.item(for: $0) }
        for item in items { onAddItem(item) }
        if iconBox?.state == .on { changeIcon(of: items) }
    }

    /// 右键「添加并更换图标…」：没解锁弹付费墙，不添加；解锁后先添加，再选图标。
    private func addChangingIcon(_ shortcut: LibraryShortcut) {
        guard DockAppIconPicker.unlocked else {
            PaywallWindow.shared.show()
            return
        }
        add(shortcut, changingIcon: true)
    }

    /// 刚添加的 App 一个个选图标（选了几个就弹几次，取消一个不影响下一个）。没解锁时
    /// （「更多应用…」面板里勾了勾选框）App 照旧添加，再弹付费墙。
    private func changeIcon(of items: [DockItem]) {
        let apps: [(String, FileRef)] = items.compactMap { item in
            if case .app(_, let bundleID, let ref) = item, !bundleID.isEmpty { return (bundleID, ref) }
            return nil
        }
        guard !apps.isEmpty else { return }
        Task { @MainActor in
            for (bundleID, ref) in apps {
                DockAppIconPicker.choose(bundleID: bundleID, ref: ref)
                if !DockAppIconPicker.unlocked { break }
            }
        }
    }

    /// 一张库卡片。顶边一行放 Pro 和「新」角标（靠右、在卡片边框以内、不压预览，
    /// 以前压在预览右上角再往外顶出卡片边），中间是预览，底栏只放名字和 −/+：名字
    /// 最多两行、不缩到 13pt 以下，不和角标抢一行（以前「AI 任意门（横版）」加角标
    /// 和两个按钮只剩「AI 任意…」）。`grouped` 为 false（搜索结果、推荐）
    /// 时名字前面带上种类名，见 `WidgetLibraryGroups.cardTitle`。
    private func cardView(_ card: LibraryCard, grouped: Bool) -> some View {
        let focused = focus == .card(card.id)
        let title = WidgetLibraryGroups.cardTitle(variant: card.title, kindName: card.name, grouped: grouped)
        return VStack(spacing: 0) {
            BadgeStrip(pro: ProFeatures.isPro(card.kind, overrides: card.overrides),
                       new: WidgetCatalog.isNew(card.kind))
                .frame(height: Self.cardBadgeHeight)
                .padding(.bottom, 4)
            LibraryPreview(instance: card.preview)
                .padding(.bottom, 6)
            HStack(alignment: .center, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
                // 需要系统权限的不再画小锁（像是锁住不能用），第一次用到时
                // 再请求；是哪项权限写在整张卡片的悬停说明里。
                let onShelf = placedInstances(for: card)
                if !onShelf.isEmpty {
                    Button { remove(card) } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(.quaternary))
                    }
                    .buttonStyle(.plain)
                    .help(onShelf.count > 1
                          ? tr("扩展栏上有 \(onShelf.count) 个，移除最后添加的那个")
                          : tr("从扩展栏移除"))
                    .accessibilityLabel(tr("移除“\(card.title)”"))
                    if onShelf.count > 1 {
                        Text("\(onShelf.count)")
                            .font(.system(size: 13, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                }
                Button { add(card) } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(.quaternary))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("添加“\(card.title)”"))
            }
            .frame(height: Self.cardFooterHeight)
        }
        .padding(10)
        .frame(width: Self.cardWidth, height: Self.cardHeight)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.background.secondary))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(focused ? Color.accentColor : Color.primary.opacity(0.1),
                              lineWidth: focused ? 2 : 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .help(WidgetLibraryGroups.cardHelp(card.kind))
        .onTapGesture { add(card) }
        .focusable()
        .focused($focus, equals: .card(card.id))
        .onKeyPress(.return) { add(card); return .handled }
        .onKeyPress(.space) { add(card); return .handled }
        .onKeyPress(.leftArrow) { move(from: card, by: -1) }
        .onKeyPress(.rightArrow) { move(from: card, by: 1) }
        .onKeyPress(.upArrow) { moveVertically(from: card, by: -1) }
        .onKeyPress(.downArrow) { moveVertically(from: card, by: 1) }
        .id(card.id)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(card.name), \(card.title)")
        .accessibilityHint("将此小组件添加到程序坞")
    }

    // MARK: Data

    private var sections: [(title: String, groups: [LibraryGroup])] {
        let query = search.trimmingCharacters(in: .whitespaces)
        // Searching flattens the category grouping into one list.
        guard query.isEmpty else {
            let found = libraryCards.filter { $0.matches(query) }
            return [(title: tr("搜索结果"), groups: [LibraryGroup(id: "search", kind: nil, cards: found)])]
        }
        let categories: [WidgetCategory] = {
            switch selection {
            case .category(let c): return [c]
            case .appsAndFolders: return [.appsAndFolders]
            case .recommended: return []
            case .all: return WidgetCategory.ordered
            }
        }()
        if selection == .recommended {
            return [(title: tr("推荐"), groups: [LibraryGroup(id: "recommended", kind: nil, cards: recommendedCards)])]
        }
        return categories.compactMap { category in
            let cards = libraryCards.filter { $0.category == category }
            // The shortcuts above already carry the 应用和文件夹 heading.
            let title = category == .appsAndFolders ? tr("应用小组件") : category.displayName
            let groups = WidgetLibraryGroups.groupedByKind(cards, kind: \.kind).map { run in
                LibraryGroup(id: "\(category.rawValue)/\(run[0].id)", kind: run[0].kind, cards: run)
            }
            return cards.isEmpty ? nil : (title: title, groups: groups)
        }
    }

    /// Visible cards in reading order - the basis for arrow-key navigation.
    private var flatCards: [LibraryCard] { sections.flatMap { $0.groups.flatMap(\.cards) } }

    /// 左右方向键沿整个列表走；上下方向键按画出来的行走，每组从新的一行开始，
    /// 跨组时落到上一组或下一组同一列（那一行短时落到最后一张）。
    private func move(from card: LibraryCard, by delta: Int) -> KeyPress.Result {
        let cards = flatCards
        guard let index = cards.firstIndex(where: { $0.id == card.id }) else { return .ignored }
        let target = index + delta
        guard cards.indices.contains(target) else { return .ignored }
        focus = .card(cards[target].id)
        return .handled
    }

    private func moveVertically(from card: LibraryCard, by delta: Int) -> KeyPress.Result {
        let cards = flatCards
        guard let index = cards.firstIndex(where: { $0.id == card.id }) else { return .ignored }
        let sizes = sections.flatMap { $0.groups.map(\.cards.count) }
        let rows = WidgetLibraryGroups.gridRows(groupSizes: sizes, columns: Self.columns)
        guard let target = WidgetLibraryGroups.verticalMove(from: index, rows: rows, by: delta),
              cards.indices.contains(target) else { return .ignored }
        focus = .card(cards[target].id)
        return .handled
    }

    /// The shelf's widgets that came from this card, oldest first. A widget
    /// belongs to the card of its kind whose overrides it matches most
    /// specifically, so a variant's minus never removes a sibling variant.
    /// Widgets inside groups are left alone: removing from a group is done
    /// on the group itself.
    private func placedInstances(for card: LibraryCard) -> [WidgetInstance] {
        let siblings = libraryCards.filter { $0.kind == card.kind }
        func fits(_ c: LibraryCard, _ w: WidgetInstance) -> Bool {
            c.overrides.allSatisfy { w.config[$0.key] == $0.value }
        }
        return placed().filter { widget in
            guard widget.kind == card.kind, fits(card, widget) else { return false }
            let best = siblings.filter { fits($0, widget) }.max { $0.overrides.count < $1.overrides.count }
            return best?.id == card.id
        }
    }

    private func remove(_ card: LibraryCard) {
        guard let last = placedInstances(for: card).last else { return }
        onRemove(last.id)
    }

    private func add(_ card: LibraryCard) {
        // 没解锁时点 Pro 卡片（整种 Pro 或 Pro 样式）弹付费墙，不添加。
        if !ProLicenseGate.canAdd(card.kind, overrides: card.overrides, unlocked: ProAccess.isUnlocked) {
            PaywallWindow.shared.show()
            return
        }
        guard let instance = WidgetCatalog.make(card.kind, overrides: card.overrides) else { return }
        onAdd(instance)
    }
}

// MARK: - Preview thumbnail

/// A live tile scaled down to fit the card's thumbnail well.
private struct LibraryPreview: View {
    var instance: WidgetInstance

    /// 卡片里预览的那一格。高 62 正好是预览里卡片的最高（`WidgetTile` 横放时不超过 62），
    /// 角标挪到卡片顶边自己的一行以后不再压在这一格上。
    static let box = CGSize(width: 148, height: 62)

    var body: some View {
        // Matches what WidgetTile lays out for a bottom shelf.
        let natural = WidgetCatalog.naturalSize(instance)
        let size = CGSize(width: natural.width, height: min(natural.height, 62))
        let scale = min(1, min(Self.box.width / size.width, Self.box.height / size.height))
        WidgetTile(instance: instance, context: WidgetContext(isPreview: true))
            .frame(width: size.width, height: size.height)
            .scaleEffect(scale)
            .frame(width: Self.box.width, height: Self.box.height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
