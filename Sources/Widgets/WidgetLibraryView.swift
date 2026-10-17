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

    /// The permission this widget cannot work without, if any.
    var permission: String? { WidgetSearch.permissions[kind.rawValue] }
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
            + [LibraryShortcut(id: "more-apps", title: "更多应用…", url: nil, isFolder: false)]
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
            + [LibraryShortcut(id: "more-folders", title: "更多文件夹…", url: nil, isFolder: true)]
    }()

    static var all: [LibraryShortcut] { apps + folders }
}

// MARK: - Library

/// The **Add Widget** browser. Sized for a sheet; the host owns presentation.
struct WidgetLibraryView: View {
    var onAdd: (WidgetInstance) -> Void
    var onAddItem: (DockItem) -> Void
    /// Widgets sitting directly on the active shelf, read in `body` so the
    /// library's minus buttons follow additions and removals as they happen.
    var placed: () -> [WidgetInstance]
    var onRemove: (UUID) -> Void
    var onClose: () -> Void

    init(onAdd: @escaping (WidgetInstance) -> Void,
         onAddItem: @escaping (DockItem) -> Void = { _ in },
         placed: @escaping () -> [WidgetInstance] = { [] },
         onRemove: @escaping (UUID) -> Void = { _ in },
         onClose: @escaping () -> Void) {
        self.onAdd = onAdd
        self.onAddItem = onAddItem
        self.placed = placed
        self.onRemove = onRemove
        self.onClose = onClose
    }

    private static let sidebarWidth: CGFloat = 175
    private static let cardWidth: CGFloat = 168
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
                    row(.all, symbol: "square.grid.2x2", title: "所有小组件",
                        count: widgetCount(libraryCards), enabled: true)
                    if !recommendedCards.isEmpty {
                        row(.recommended, symbol: "star", title: "推荐",
                            count: recommendedCards.count, enabled: true)
                    }
                    row(.appsAndFolders, symbol: WidgetCategory.appsAndFolders.symbol,
                        title: WidgetCategory.appsAndFolders.displayName,
                        count: LibraryShortcut.all.filter { $0.url != nil }.count
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
                        .font(.system(size: 11).monospacedDigit())
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
        .help(enabled ? "" : "这里还没有小组件。")
        .accessibilityHint(enabled ? "" : "此类别中还没有小组件。")
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
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
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
            if flatCards.isEmpty && visibleShortcuts.isEmpty {
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
                .font(.system(size: 11))
        }
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if !visibleShortcuts.isEmpty {
                        shortcutsSection
                    }
                    ForEach(sections, id: \.title) { section in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(section.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.cardWidth), spacing: 12),
                                                     count: Self.columns),
                                      alignment: .leading, spacing: 12) {
                                ForEach(section.cards) { card in
                                    cardView(card)
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

    private var shortcutsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("应用和文件夹")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76, maximum: 84), spacing: 8)],
                      alignment: .leading, spacing: 10) {
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
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(width: 76)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(shortcut.url == nil ? "选择其他\(shortcut.isFolder ? "文件夹" : "应用")" : "添加到扩展栏")
        .accessibilityLabel(shortcut.url == nil ? shortcut.title : "添加“\(shortcut.title)”")
    }

    private var visibleShortcuts: [LibraryShortcut] {
        let query = search.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty { return LibraryShortcut.all.filter { $0.matches(query) } }
        switch selection {
        case .all, .appsAndFolders: return LibraryShortcut.all
        case .category, .recommended: return []
        }
    }

    private func add(_ shortcut: LibraryShortcut) {
        if let item = shortcut.item {
            onAddItem(item)
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = !shortcut.isFolder
        panel.canChooseDirectories = shortcut.isFolder
        panel.allowsMultipleSelection = true
        panel.prompt = "添加"
        if !shortcut.isFolder {
            panel.allowedContentTypes = [.applicationBundle]
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
        }
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { onAddItem(LibraryShortcut.item(for: url)) }
    }

    private func cardView(_ card: LibraryCard) -> some View {
        let focused = focus == .card(card.id)
        return VStack(spacing: 8) {
            LibraryPreview(instance: card.preview)
            HStack(spacing: 4) {
                Text(card.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if WidgetCatalog.isSupporterOnly(card.overrides) {
                    Text("赞助者专属")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color(hex: ShelfColor.redPanda.hex)))
                        .fixedSize()
                }
                if WidgetCatalog.isNew(card.kind) {
                    Text("新")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color.accentColor))
                        .fixedSize()
                        .help("近期新增的小组件")
                        .accessibilityLabel("新")
                }
                if let permission = card.permission {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .help("需要“\(permission)”权限，第一次用到时会请求。")
                        .accessibilityLabel("需要\(permission)权限")
                }
                Spacer(minLength: 2)
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
                          ? "扩展栏上有 \(onShelf.count) 个，移除最后添加的那个"
                          : "从扩展栏移除")
                    .accessibilityLabel("移除“\(card.title)”")
                    if onShelf.count > 1 {
                        Text("\(onShelf.count)")
                            .font(.system(size: 10, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                Button { add(card) } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(.quaternary))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("添加“\(card.title)”")
            }
        }
        .padding(10)
        .frame(width: Self.cardWidth, height: 116)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.background.secondary))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(focused ? Color.accentColor : Color.primary.opacity(0.1),
                              lineWidth: focused ? 2 : 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture { add(card) }
        .focusable()
        .focused($focus, equals: .card(card.id))
        .onKeyPress(.return) { add(card); return .handled }
        .onKeyPress(.space) { add(card); return .handled }
        .onKeyPress(.leftArrow) { move(from: card, by: -1) }
        .onKeyPress(.rightArrow) { move(from: card, by: 1) }
        .onKeyPress(.upArrow) { move(from: card, by: -Self.columns) }
        .onKeyPress(.downArrow) { move(from: card, by: Self.columns) }
        .id(card.id)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(card.name), \(card.title)")
        .accessibilityHint("将此小组件添加到程序坞")
    }

    // MARK: Data

    private var sections: [(title: String, cards: [LibraryCard])] {
        let query = search.trimmingCharacters(in: .whitespaces)
        // Searching flattens the category grouping into one list.
        guard query.isEmpty else {
            return [(title: "搜索结果", cards: libraryCards.filter { $0.matches(query) })]
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
            return [(title: "推荐", cards: recommendedCards)]
        }
        return categories.compactMap { category in
            let cards = libraryCards.filter { $0.category == category }
            // The shortcuts above already carry the 应用和文件夹 heading.
            let title = category == .appsAndFolders ? "应用小组件" : category.displayName
            return cards.isEmpty ? nil : (title: title, cards: cards)
        }
    }

    /// Visible cards in reading order - the basis for arrow-key navigation.
    private var flatCards: [LibraryCard] { sections.flatMap(\.cards) }

    // ponytail: arrow keys walk the flat list, so a vertical hop across a
    // section boundary lands near, not exactly above/below. Track per-section
    // rows if that ever reads wrong.
    private func move(from card: LibraryCard, by delta: Int) -> KeyPress.Result {
        let cards = flatCards
        guard let index = cards.firstIndex(where: { $0.id == card.id }) else { return .ignored }
        let target = index + delta
        guard cards.indices.contains(target) else { return .ignored }
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
        if WidgetCatalog.isSupporterOnly(card.overrides), !Supporter.isUnlocked {
            SponsorWindow.shared.show()
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

    private static let box = CGSize(width: 148, height: 66)

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
