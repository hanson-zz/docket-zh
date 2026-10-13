import SwiftUI

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
        title.localizedStandardContains(query) || name.localizedStandardContains(query)
    }
}

/// Only self-contained kinds: the rest cannot be rendered in this build.
private let libraryCards: [LibraryCard] = WidgetCatalog.entries
    .filter(\.selfContained)
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

private func symbol(for category: WidgetCategory) -> String {
    switch category {
    case .clocks: "clock"
    case .reminders: "checklist"
    case .calendar: "calendar"
    case .notes: "note.text"
    case .media: "play.rectangle"
    case .system: "desktopcomputer"
    case .weather: "cloud.sun"
    case .business: "chart.line.uptrend.xyaxis"
    case .stocks: "chart.xyaxis.line"
    case .files: "folder"
    case .tools: "wrench.and.screwdriver"
    }
}

private enum LibrarySelection: Hashable {
    case all
    case category(WidgetCategory)
}

private enum LibraryFocus: Hashable {
    case search
    case card(String)
}

// MARK: - Library

/// The **Add Widget** browser. Sized for a sheet; the host owns presentation.
struct WidgetLibraryView: View {
    var onAdd: (WidgetInstance) -> Void
    var onClose: () -> Void

    init(onAdd: @escaping (WidgetInstance) -> Void, onClose: @escaping () -> Void) {
        self.onAdd = onAdd
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
                    row(.all, symbol: "square.grid.2x2", title: "所有小组件", enabled: true)
                    ForEach(WidgetCategory.ordered, id: \.self) { category in
                        row(.category(category), symbol: symbol(for: category),
                            title: category.displayName,
                            // Categories whose kinds all need permissions or
                            // network have nothing to show in this build.
                            enabled: libraryCards.contains { $0.category == category })
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
                     enabled: Bool) -> some View {
        let selected = selection == item
        return Button { selection = item } label: {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 12))
                    .frame(width: 16)
                Text(title).font(.system(size: 13))
                Spacer(minLength: 0)
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
        // Three categories are permanently greyed out, and used to say
        // nothing about why: Business has no widgets built yet, Calendar and
        // Reminders have them but they are not finished. A row that is dim
        // for ever with no explanation reads as a fault in the app.
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
            if flatCards.isEmpty {
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
        }
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
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
                Spacer(minLength: 2)
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
            if case .category(let c) = selection { return [c] }
            return WidgetCategory.ordered
        }()
        return categories.compactMap { category in
            let cards = libraryCards.filter { $0.category == category }
            return cards.isEmpty ? nil : (title: category.displayName, cards: cards)
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
