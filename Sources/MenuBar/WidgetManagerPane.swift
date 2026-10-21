import SwiftUI

/// 设置 ▸ 小组件管理。
///
/// 上半是当前扩展栏布局里的小组件：拖动排序、开关显示（关掉只是隐藏，设置保留）。
/// 中间一个搜索框，按名字同时筛上下两半。下半是还没放上去的小组件，按小组件库的
/// 分类折叠，打开开关就用库里同一套默认样式放到扩展栏末尾，它随即出现在上半。
///
/// 列表、分组、搜索和折叠的判断都在 Core 的 `WidgetManagement` 里；这里只画。
struct WidgetManagerPane: View {
    @Binding var state: PersistedState
    /// 把小组件放到当前扩展栏末尾，和小组件库的“添加”走同一条路（`AppState.addItem`）。
    var onAdd: (WidgetInstance) -> Void

    @State private var query = ""
    /// 用户点过的分类展开状态；没点过的按默认（只展开第一类）。
    @State private var choices: [WidgetCategory: Bool] = [:]
    /// 点过“还有 N 个”的分类。
    @State private var showingAll: Set<WidgetCategory> = []

    private var activeProfileIndex: Int? {
        guard let id = state.customDock.profileID else { return nil }
        return state.profiles.firstIndex { $0.id == id }
    }

    private var activeItems: [DockItem] {
        guard let index = activeProfileIndex else { return [] }
        return state.profiles[index].items
    }

    private var searching: Bool { WidgetManagement.hasQuery(query) }

    var body: some View {
        if state.setup == .macOSDockOnly {
            ContentUnavailableView("扩展栏已关闭", systemImage: "rectangle.bottomthird.inset.filled",
                                   description: Text("打开扩展栏后，这里会列出上面的小组件。"))
        } else {
            list
        }
    }

    private var list: some View {
        let placed = WidgetManagement.widgets(activeItems)
        let shown = WidgetManagement.filter(placed, query: query) { WidgetNames.all(for: $0.kind) }
        let unadded = WidgetManagement.unadded(WidgetNames.candidates, placed: placed.map(\.kind))
        let sections = WidgetManagement.sections(unadded, query: query)
        let unaddedCount = sections.reduce(0) { $0 + $1.items.count }
        return List {
            Section {
                if placed.isEmpty {
                    Text("当前布局里还没有小组件，在下面打开开关添加。")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                } else if shown.isEmpty {
                    Text("扩展栏上没有匹配的小组件。")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                ForEach(shown) { widget in
                    placedRow(widget)
                }
                // 筛选时下标对不上布局里的顺序，先不让拖。
                .onMove(perform: searching ? nil : { source, destination in move(source, destination) })
            } header: {
                HStack {
                    Text(tr("\(state.activeCustomProfile?.name ?? tr("扩展栏")) · 在扩展栏上 \(placed.count) 个"))
                    Spacer(minLength: 8)
                    if !placed.isEmpty, !searching {
                        Text("拖动排序")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("关掉只是从扩展栏隐藏，设置保留。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                searchField
            }

            Section {
                if sections.isEmpty {
                    Text(searching ? tr("没有匹配的未添加小组件。") : tr("小组件库里的都已经放上去了。"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                ForEach(sections) { section in
                    categoryRows(section, in: sections)
                }
            } header: {
                HStack {
                    Text(tr("未添加 · \(unaddedCount) 个"))
                    Spacer(minLength: 8)
                    Text("打开即放到扩展栏末尾")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.inset)
    }

    // MARK: 上半

    private func move(_ source: IndexSet, _ destination: Int) {
        guard let index = activeProfileIndex else { return }
        withAnimation(.smooth(duration: 0.2)) {
            state.profiles[index].items = WidgetManagement.move(
                widgetsAt: source, to: destination, in: state.profiles[index].items)
        }
    }

    private func placedRow(_ widget: WidgetInstance) -> some View {
        let mode = WidgetVisibility.mode(widget.config)
        return HStack(spacing: 9) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .opacity(searching ? 0.3 : 1)
                .help("拖动排序")
            kindIcon
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(WidgetNames.name(widget.kind))
                        .lineLimit(1)
                    // 整种是 Pro，或现在用的外观是 Pro（液态、Pro 表盘等）。
                    if ProFeatures.isPro(widget) { ProBadge() }
                }
                if mode == .conditional,
                   let condition = WidgetVisibility.conditionTitle(widget.kind, config: widget.config) {
                    Text(condition)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Toggle("显示", isOn: Binding(
                get: { WidgetManagement.isShown(widget) },
                set: { on in
                    guard let index = activeProfileIndex else { return }
                    state.profiles[index].items = WidgetManagement.setShown(
                        on, id: widget.id, in: state.profiles[index].items)
                }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
        .padding(.vertical, 2)
    }

    // MARK: 搜索

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            TextField("搜索小组件", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("清除搜索")
                .accessibilityLabel(tr("清除搜索"))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.quaternary.opacity(0.6)))
        .moveDisabled(true)
    }

    // MARK: 下半

    @ViewBuilder
    private func categoryRows(_ section: WidgetManagement.Section,
                              in sections: [WidgetManagement.Section]) -> some View {
        let expanded = WidgetManagement.isExpanded(section.category, in: sections,
                                                   query: query, choices: choices)
        Button {
            // 搜索时匹配的分类都展开，点了也不收。
            guard !searching else { return }
            withAnimation(.smooth(duration: 0.2)) { choices[section.category] = !expanded }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: 14)
                Text(section.category.displayName)
                    .font(.system(size: 13, weight: .semibold))
                Text(verbatim: "\(section.items.count)")
                    .font(.system(size: 13))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr("\(section.category.displayName)，未添加 \(section.items.count) 个"))
        .accessibilityValue(expanded ? tr("已展开") : tr("已收起"))
        .moveDisabled(true)

        if expanded {
            let visible = WidgetManagement.visible(section.items,
                                                   showAll: searching || showingAll.contains(section.category))
            ForEach(visible.shown) { candidate in
                unaddedRow(candidate)
            }
            if visible.more > 0 {
                Button {
                    withAnimation(.smooth(duration: 0.2)) { _ = showingAll.insert(section.category) }
                } label: {
                    Text(tr("还有 \(visible.more) 个 ›"))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .padding(.leading, 21)
                .moveDisabled(true)
            }
        }
    }

    private func unaddedRow(_ candidate: WidgetManagement.Candidate) -> some View {
        HStack(spacing: 9) {
            kindIcon
            HStack(spacing: 5) {
                Text(candidate.name)
                    .lineLimit(1)
                if ProFeatures.isPro(candidate.kind, overrides: candidate.overrides) { ProBadge() }
            }
            Spacer(minLength: 8)
            // 永远是关着的：打开就加到扩展栏，这一行随即移到上半（可放多个的留在这里）。
            Toggle("添加", isOn: Binding(get: { false }, set: { on in if on { add(candidate) } }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .accessibilityLabel(tr("添加“\(candidate.name)”"))
        }
        .padding(.leading, 21)
        .padding(.vertical, 2)
        .moveDisabled(true)
    }

    /// 和小组件库点卡片一样：Pro 没解锁时弹付费墙、不添加；否则用库里第一张卡片的
    /// 默认尺寸和配置做一个新的，放到扩展栏末尾。锁定扩展栏时库不拦，这里也不拦。
    private func add(_ candidate: WidgetManagement.Candidate) {
        if !ProLicenseGate.canAdd(candidate.kind, overrides: candidate.overrides,
                                  unlocked: ProAccess.isUnlocked) {
            PaywallWindow.shared.show()
            return
        }
        guard let instance = WidgetCatalog.make(candidate.kind, overrides: candidate.overrides) else { return }
        withAnimation(.smooth(duration: 0.22)) { onAdd(instance) }
    }

    private var kindIcon: some View {
        // 和原来的列表一样：小组件没有文件图标，统一画小组件符号。
        Image(systemName: "square.grid.2x2")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .frame(width: 20, height: 20)
    }
}

/// 小组件的中文名和英文名，搜索时两种都能找到。
///
/// 目录里的名字是按界面语言查过表的；另一种语言从 String Catalog 的英文表里取：
/// 中文界面查英文译文，英文界面反查中文原文。表在第一次用到时读一次。
enum WidgetNames {
    /// 下半用的目录，带好别名。目录不会在运行时变，算一次。
    static let candidates: [WidgetManagement.Candidate] =
        WidgetManagement.catalogCandidates { other($0) }

    static func name(_ kind: WidgetKind) -> String {
        WidgetCatalog.entry(kind)?.name ?? kind.rawValue
    }

    static func all(for kind: WidgetKind) -> [String] {
        let shown = name(kind)
        return [shown] + other(shown)
    }

    /// 另一种语言的名字，查不到就是空的。
    static func other(_ shown: String) -> [String] {
        if L10n.isEnglish {
            return reverse[shown].map { [$0] } ?? []
        }
        guard let english = english[shown], english != shown else { return [] }
        return [english]
    }

    /// 英文表：中文原文到英文译文。
    private static let english: [String: String] = {
        guard let path = Bundle.main.path(forResource: "Localizable", ofType: "strings",
                                          inDirectory: nil, forLocalization: "en"),
              let table = NSDictionary(contentsOfFile: path) as? [String: String] else { return [:] }
        return table
    }()

    /// 反过来：英文译文到中文原文。同一个英文对应好几条时留第一条看到的。
    private static let reverse: [String: String] = {
        var map: [String: String] = [:]
        for (key, value) in english where map[value] == nil { map[value] = key }
        return map
    }()
}
