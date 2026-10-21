import AppKit
import SwiftUI

/// 表情符号面板：搜索、收藏、最近用过、肤色。
///
/// 两个状态：
/// - 浏览：搜索框（中英文关键词，笑、心、cat、猫都能搜到），收藏一排 8 个
///   （拖动可排序），最近用过，默认肤色一处设。点一下拷贝，双击插到光标处
///   （要辅助功能权限，没有就只拷贝并说一声），按住能另选这一个的肤色。
///   底下“已拷贝”提示和“打开系统表情面板”。
/// - 整理：右上“整理”进入。搜索结果点一下加星收藏或取消，收藏 6 列大格子，
///   左上红钮移除、拖动排序，最多 24 个；清空最近用过、恢复默认。
///
/// 收藏、最近、肤色都存在小组件自己的设置里（见 `EmojiPrefs`），卡片读同一份。
/// 最近用过在面板开着时不重排：点了的表情挪到最前，双击的第二下就会点到
/// 别的表情上，所以显示的是打开面板（或清空、切换状态）时的那一份。
struct EmojiDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private enum Area: Hashable { case favorites, recent, results, editResults, editFavorites }

    private struct Drag: Equatable {
        var area: Area
        var from: Int
        var offset: CGSize
    }

    private enum Note: Equatable { case copied, inserted, needsAccess }

    @State private var editing = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    @State private var shownRecent: [String]?
    @State private var copied: String?
    @State private var note: Note?
    /// 每拷贝一次加一，提示从这次重新计 4 秒（连着拷同一个也算）。
    @State private var copyTick = 0
    /// 正在选肤色的那个表情和它所在的格子。
    @State private var toning: (area: Area, emoji: String)?
    @State private var drag: Drag?
    @State private var fullWarning = false
    @State private var confirmRestore = false
    /// 搜索结果和“也能搜”只在搜索词变了时算一次，拖动重画时不重算。
    @State private var found: [String] = []
    @State private var hint: String?

    @Environment(\.panelTint) private var panelTint
    private var accent: Color { panelTint.accent(or: Self.gold) }
    private var accentInk: Color { panelTint.ink(or: Self.goldInk) }

    private static let gold = Color(hex: "#FFC94D")
    private static let goldInk = Color(hex: "#2A1C00")
    private static let red = Color(hex: "#FF6B5A")
    /// 拖起来的格子、肤色条的实心底：深色下原来的深灰，浅色下近白，盖住下面的格子。
    private static let solidTile = Color.panelDynamic(
        dark: NSColor(srgbRed: 0.23, green: 0.23, blue: 0.26, alpha: 1),
        light: NSColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: 1))
    private static let skins = ["#FFCC4D", "#F7DECE", "#F3D2A2", "#D5AB88", "#AF7E57", "#7C533E"]
    /// 浏览态一行 8 个 36 的格子，正好 288（320 减两边 16）。
    private static let columns = 8
    private static let cell: CGFloat = 36
    /// 整理态收藏 6 列 48，行距 54。
    private static let editColumns = 6
    private static let editCell: CGFloat = 48
    private static let editStep: CGFloat = 54
    /// 搜索结果超过这么多行就在里面滚动。
    private static let resultRows = 5

    /// 写过之后面板拿到的仍可能是打开时的那份，读最新存着的。
    private var current: WidgetInstance { WidgetWriter.current(instance.id) ?? instance }

    private var prefs: EmojiPrefs {
        if context.isPreview {
            return EmojiPrefs(favorites: ["😂", "❤️", "👍", "🙏", "🎉", "🔥", "😭", "🥹"],
                              recent: ["😊", "🤔", "👀", "✅", "💯", "😅", "🙌", "✨"])
        }
        return EmojiPrefs(current.config)
    }

    private var recentList: [String] { shownRecent ?? prefs.recent }

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        let p = prefs
        DetailCard {
            MeshBackdrop(color: Self.gold)
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, 14)
                searchField
                    .padding(.bottom, 18)
                if editing {
                    edit(p)
                } else {
                    browse(p)
                }
            }
        }
        .onAppear { shownRecent = prefs.recent }
        .task(id: copyTick) {
            // 提示留 4 秒，再拷贝一次就重新计时。
            guard note != nil else { return }
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { note = nil; copied = nil }
        }
        .task(id: fullWarning) {
            guard fullWarning else { return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            fullWarning = false
        }
        .task(id: confirmRestore) {
            guard confirmRestore else { return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            confirmRestore = false
        }
    }

    // MARK: 头部

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(editing ? tr("整理表情") : tr("表情符号"))
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.panelPrimary)
                Text(editing ? tr("星标收藏 · 拖动排序 · 红钮移除") : tr("点一下拷贝 · 双击插到光标处"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            if !context.isPreview {
                if editing {
                    Button { switchEditing(false) } label: {
                        Text(tr("完成"))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(accentInk)
                            .padding(.horizontal, 15)
                            .frame(height: 28)
                            .background(Capsule().fill(accent))
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button { switchEditing(true) } label: {
                        Text(tr("整理"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.panelPrimary)
                            .padding(.horizontal, 13)
                            .frame(height: 28)
                            .background(Capsule().fill(.panelFill))
                            .overlay { Capsule().strokeBorder(.panelStroke, lineWidth: 0.6) }
                            .contentShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .help(tr("搜索加收藏、调整顺序、移除"))
                }
            }
        }
    }

    private func switchEditing(_ on: Bool) {
        if on { WidgetDetailWindow.shared.focusField { searchFocused = true } }
        withAnimation(.snappy(duration: 0.25)) {
            editing = on
            query = ""
            toning = nil
            drag = nil
            note = nil
            copied = nil
            fullWarning = false
            confirmRestore = false
            shownRecent = prefs.recent
        }
    }

    // MARK: 搜索框

    private var searchField: some View {
        let suggestion = editing ? hint : nil
        let active = searchFocused || !query.isEmpty
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.panelSecondary)
            TextField("", text: $query, prompt: Text(tr("搜索：笑、心、cat、猫")).foregroundStyle(.panelTertiary))
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.panelPrimary)
                .focused($searchFocused)
                .onSubmit(submitSearch)
                .onChange(of: query) { _, new in
                    let q = new.trimmingCharacters(in: .whitespacesAndNewlines)
                    found = EmojiCatalog.search(q).map(\.emoji)
                    hint = EmojiCatalog.alsoTry(q)
                    toning = nil
                    // 搜完回到列表时，刚才用过的才排进最近用过。
                    if new.isEmpty { shownRecent = prefs.recent }
                }
            if let suggestion {
                Text(tr("也能搜 \(suggestion)"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.panelTertiary)
                        .frame(width: 20, height: 20)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("清除搜索"))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.panelFill))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(editing && active ? accent.opacity(0.9) : .panelStroke,
                              lineWidth: editing && active ? 1.2 : 0.6)
        }
        .contentShape(.rect)
        .onTapGesture {
            // 面板不是 key 时输入框收不到字，先让它成为 key。
            WidgetDetailWindow.shared.focusField { searchFocused = true }
        }
        .disabled(context.isPreview)
    }

    /// 回车：浏览时拷贝第一个结果，整理时给第一个结果加星或取消。
    private func submitSearch() {
        guard let first = found.first else { return }
        if editing { toggleFavorite(first) } else { copy(first) }
    }

    // MARK: 浏览

    @ViewBuilder
    private func browse(_ p: EmojiPrefs) -> some View {
        if !trimmedQuery.isEmpty {
            results(p, area: .results)
                .padding(.bottom, toning?.area == .results ? 10 : 16)
            toneStripIfNeeded(.results, p: p)
        } else {
            section(tr("收藏"), trailing: p.favorites.count > 1 ? tr("拖动可排序") : nil)
            if p.favorites.isEmpty {
                emptyLine(tr("还没有收藏。点「整理」搜索，点表情加星。"))
                    .padding(.bottom, 18)
            } else {
                grid(p.favorites, area: .favorites, p: p)
                    .padding(.bottom, toning?.area == .favorites ? 10 : 18)
                toneStripIfNeeded(.favorites, p: p)
            }
            section(tr("最近用过"), trailing: nil) {
                if !p.recent.isEmpty || !(shownRecent ?? []).isEmpty {
                    Button(tr("清空")) { clearRecent() }
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.panelSecondary)
                        .disabled(context.isPreview)
                }
            }
            let recent = recentList
            if recent.isEmpty {
                emptyLine(tr("用过的表情会排在这里。"))
                    .padding(.bottom, 16)
            } else {
                grid(Array(recent.prefix(EmojiPrefs.maxRecent)), area: .recent, p: p)
                    .padding(.bottom, toning?.area == .recent ? 10 : 16)
                toneStripIfNeeded(.recent, p: p)
            }
        }
        skinRow(p)
            .padding(.bottom, 8)
        Text(tr("单个表情按住就能换肤色"))
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.panelSecondary)
            .padding(.leading, 2)
            .padding(.bottom, 12)
        if let note, let copied {
            copiedBanner(copied, note: note, p: p)
                .padding(.bottom, 12)
                .transition(.opacity)
        }
        Button {
            guard !context.isPreview else { return }
            NSApp.activate(ignoringOtherApps: true)
            NSApp.orderFrontCharacterPalette(nil)
        } label: {
            Text(tr("更多表情：打开系统表情面板"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(Capsule().fill(.panelFill))
                .overlay { Capsule().strokeBorder(.panelStroke, lineWidth: 0.6) }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
    }

    private func skinRow(_ p: EmojiPrefs) -> some View {
        HStack(spacing: 0) {
            Text(tr("默认肤色"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.panelPrimary)
                .lineLimit(1)
                .minimumScaleFactor(13.0 / 14.0)
            Spacer(minLength: 8)
            HStack(spacing: 10) {
                ForEach(0..<EmojiTone.count, id: \.self) { tone in
                    Button {
                        guard !context.isPreview else { return }
                        save(p.settingDefaultTone(tone))
                    } label: {
                        Circle()
                            .fill(Color(hex: Self.skins[tone]))
                            .frame(width: 20, height: 20)
                            .padding(3.5)
                            .overlay {
                                if tone == p.tone {
                                    Circle().strokeBorder(.panelPrimary, lineWidth: 1.6)
                                }
                            }
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .help(Self.toneName(tone))
                    .accessibilityLabel(Self.toneName(tone))
                    .accessibilityAddTraits(tone == p.tone ? .isSelected : [])
                }
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .frame(height: 50)
        .glassPane(cornerRadius: 12)
    }

    private static func toneName(_ tone: Int) -> String {
        switch tone {
        case 1: tr("浅肤色")
        case 2: tr("中等浅肤色")
        case 3: tr("中等肤色")
        case 4: tr("中等深肤色")
        case 5: tr("深肤色")
        default: tr("默认黄色")
        }
    }

    private func copiedBanner(_ emoji: String, note: Note, p: EmojiPrefs) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(accent)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accentInk)
            }
            .frame(width: 20, height: 20)
            Text(note == .inserted ? tr("已插入") : tr("已拷贝"))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.panelPrimary)
                .fixedSize()
            Text(verbatim: p.display(emoji))
                .font(.system(size: 20))
            Text(note == .needsAccess ? tr("允许辅助功能后双击能直接插入")
                 : note == .inserted ? tr("插到了光标处") : tr("去输入框按 ⌘V 粘贴"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.panelSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 48)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.panelFill))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(accent.opacity(0.6), lineWidth: 1)
        }
    }

    // MARK: 整理

    @ViewBuilder
    private func edit(_ p: EmojiPrefs) -> some View {
        if trimmedQuery.isEmpty {
            emptyLine(tr("搜一个词（中文或英文），点结果里的表情就加星收藏。"))
                .padding(.bottom, 18)
        } else {
            results(p, area: .editResults)
                .padding(.bottom, toning?.area == .editResults ? 10 : 18)
            toneStripIfNeeded(.editResults, p: p)
        }
        section(tr("收藏 \(p.favorites.count) / \(EmojiPrefs.maxFavorites)"),
                trailing: p.favorites.count > 1 ? tr("拖动排序") : nil)
            .padding(.bottom, 2)
        editFavorites(p)
            .padding(.bottom, toning?.area == .editFavorites ? 10 : 12)
        toneStripIfNeeded(.editFavorites, p: p)
        if fullWarning {
            Text(tr("收藏最多 \(EmojiPrefs.maxFavorites) 个，先移除几个再加。"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Self.red.panelReadable)
                .padding(.bottom, 10)
        }
        HStack(spacing: 8) {
            footerButton(tr("清空最近用过"), tint: Self.red, enabled: !p.recent.isEmpty) { clearRecent() }
            footerButton(confirmRestore ? tr("再点一次恢复") : tr("恢复默认"),
                         tint: confirmRestore ? accent : .panelPrimary, enabled: true) {
                if confirmRestore {
                    confirmRestore = false
                    toning = nil
                    save(p.restoringDefaults())
                } else {
                    confirmRestore = true
                }
            }
            .help(tr("收藏回到默认的 9 个，肤色回到黄色；最近用过不动"))
        }
    }

    private func footerButton(_ title: String, tint: Color, enabled: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint.panelReadable)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(Capsule().fill(.panelFill))
                .overlay { Capsule().strokeBorder(.panelStroke, lineWidth: 0.6) }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .disabled(!enabled || context.isPreview)
        .opacity(enabled ? 1 : 0.45)
    }

    // MARK: 搜索结果

    private func results(_ p: EmojiPrefs, area: Area) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            section(tr("搜索结果 \(found.count)"),
                    trailing: found.isEmpty ? nil : (area == .editResults ? tr("点星星加收藏") : tr("点一下拷贝")))
            if found.isEmpty {
                emptyLine(tr("没有找到「\(trimmedQuery)」。换个说法，或打开系统表情面板。"))
            } else if EmojiPrefs.rows(count: found.count, columns: Self.columns) > Self.resultRows {
                ScrollView(.vertical) { grid(found, area: area, p: p) }
                    .scrollIndicators(.automatic)
                    .frame(height: CGFloat(Self.resultRows) * Self.cell)
            } else {
                grid(found, area: area, p: p)
            }
        }
    }

    // MARK: 网格

    /// 浏览态的网格：8 列 36。收藏能拖动排序，拖的那格跟着手走，别的让位。
    private func grid(_ items: [String], area: Area, p: EmojiPrefs) -> some View {
        let columns = Self.columns
        let cell = Self.cell
        let rows = EmojiPrefs.rows(count: items.count, columns: columns)
        let active = drag?.area == area ? drag : nil
        let target = active.map {
            EmojiPrefs.dropIndex(from: $0.from, dx: $0.offset.width, dy: $0.offset.height,
                                 cell: cell, rowStep: cell, columns: columns, count: items.count)
        }
        let order = active.flatMap { d in target.map { EmojiPrefs.moving(items, from: d.from, to: $0) } } ?? items
        return ZStack(alignment: .topLeading) {
            ForEach(Array(items.enumerated()), id: \.element) { index, item in
                let slot = order.firstIndex(of: item) ?? index
                let shift = shiftFor(active, index: index, slot: slot, columns: columns, cell: cell, step: cell)
                browseCell(item, index: index, area: area, p: p, lifted: shift != nil, count: items.count)
                    .position(x: CGFloat(slot % columns) * cell + cell / 2,
                              y: CGFloat(slot / columns) * cell + cell / 2)
                    .offset(shift ?? .zero)
                    .zIndex(shift == nil ? 0 : 1)
            }
        }
        .frame(width: CGFloat(columns) * cell, height: CGFloat(rows) * cell, alignment: .topLeading)
        .animation(.snappy(duration: 0.2), value: order)
    }

    /// 被拖的那格：画在它原来的位置加上手的位移（slot 已经是目标位，减回去）。
    /// 不是被拖的那格返回 nil。
    private func shiftFor(_ d: Drag?, index: Int, slot: Int, columns: Int,
                          cell: CGFloat, step: CGFloat) -> CGSize? {
        guard let d, d.from == index else { return nil }
        let dx = CGFloat(d.from % columns - slot % columns) * cell
        let dy = CGFloat(d.from / columns - slot / columns) * step
        return CGSize(width: d.offset.width + dx, height: d.offset.height + dy)
    }

    private func browseCell(_ item: String, index: Int, area: Area, p: EmojiPrefs,
                            lifted: Bool, count: Int) -> some View {
        let shown = p.display(item)
        let copiedHere = area == .favorites && copied == item
        let toningHere = toning?.area == area && toning?.emoji == item
        let highlighted = copiedHere || toningHere
        let starred = area == .editResults && p.isFavorite(item)
        return ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(highlighted ? accent.opacity(0.22) : lifted ? Self.solidTile : .panelFill)
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(highlighted || lifted ? accent : .clear, lineWidth: 1.4)
                }
                .shadow(color: .black.opacity(lifted ? 0.35 : 0), radius: 5, y: 3)
                .frame(width: Self.cell - 4, height: Self.cell - 4)
                .overlay {
                    Text(verbatim: shown)
                        .font(.system(size: 22))
                }
                .frame(width: Self.cell, height: Self.cell)
            if starred {
                Image(systemName: "star.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(accent.panelReadable)
                    .padding(2)
                    .background(Circle().fill(Self.solidTile))
                    .offset(x: 1, y: -1)
            }
        }
        .frame(width: Self.cell, height: Self.cell)
        .contentShape(.rect)
        .modifier(CellGestures(
            enabled: !context.isPreview,
            onTap: { area == .editResults ? toggleFavorite(item) : copy(item) },
            onDoubleTap: area == .editResults ? nil : { insert(item) },
            onLongPress: EmojiCatalog.isModifiable(item) ? { startToning(item, area: area) } : nil,
            drag: area == .favorites && count > 1 ? dragHandlers(area: area, index: index, count: count,
                                                                 columns: Self.columns, cell: Self.cell,
                                                                 step: Self.cell) : nil))
        .contextMenu { cellMenu(item, area: area, p: p) }
        .help(EmojiCatalog.entry(item)?.zh.first ?? shown)
        .accessibilityLabel(EmojiCatalog.entry(item)?.zh.first ?? shown)
    }

    @ViewBuilder
    private func cellMenu(_ item: String, area: Area, p: EmojiPrefs) -> some View {
        if !context.isPreview {
            Button(tr("拷贝"), systemImage: "doc.on.doc") { copy(item) }
            Button(tr("插到光标处"), systemImage: "text.cursor") { insert(item) }
            if EmojiCatalog.isModifiable(item) {
                Button(tr("选肤色"), systemImage: "hand.raised") { startToning(item, area: area) }
            }
            Divider()
            if p.isFavorite(item) {
                Button(tr("移出收藏"), systemImage: "star.slash") { toggleFavorite(item) }
            } else {
                Button(tr("加入收藏"), systemImage: "star") { toggleFavorite(item) }
                    .disabled(p.favoritesFull)
            }
        }
    }

    /// 整理态的收藏：6 列 48，左上红钮移除，拖动排序，末尾虚线“＋”去搜索。
    private func editFavorites(_ p: EmojiPrefs) -> some View {
        let items = p.favorites
        let columns = Self.editColumns
        let cell = Self.editCell
        let step = Self.editStep
        let showPlus = !p.favoritesFull
        let rows = EmojiPrefs.rows(count: items.count + (showPlus ? 1 : 0), columns: columns)
        let active = drag?.area == .editFavorites ? drag : nil
        let target = active.map {
            EmojiPrefs.dropIndex(from: $0.from, dx: $0.offset.width, dy: $0.offset.height,
                                 cell: cell, rowStep: step, columns: columns, count: items.count)
        }
        let order = active.flatMap { d in target.map { EmojiPrefs.moving(items, from: d.from, to: $0) } } ?? items
        func center(_ slot: Int) -> CGPoint {
            CGPoint(x: CGFloat(slot % columns) * cell + cell / 2, y: CGFloat(slot / columns) * step + cell / 2)
        }
        return ZStack(alignment: .topLeading) {
            if let target {
                dashedBox(accent.opacity(0.8))
                    .position(center(target))
            }
            ForEach(Array(items.enumerated()), id: \.element) { index, item in
                let slot = order.firstIndex(of: item) ?? index
                let shift = shiftFor(active, index: index, slot: slot, columns: columns, cell: cell, step: step)
                editCell(item, index: index, p: p, lifted: shift != nil, count: items.count)
                    .position(center(slot))
                    .offset(shift ?? .zero)
                    .zIndex(shift == nil ? 0 : 1)
            }
            if showPlus {
                Button {
                    WidgetDetailWindow.shared.focusField { searchFocused = true }
                } label: {
                    dashedBox(.panelQuaternary)
                        .overlay {
                            Image(systemName: "plus")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.panelSecondary)
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(tr("在上面搜索，点表情加星收藏"))
                .accessibilityLabel(tr("添加收藏"))
                .position(center(items.count))
            }
        }
        .frame(width: CGFloat(columns) * cell,
               height: rows > 0 ? CGFloat(rows - 1) * step + cell : cell, alignment: .topLeading)
        .animation(.snappy(duration: 0.2), value: order)
    }

    private func dashedBox(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(color, style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
            .frame(width: Self.editCell - 6, height: Self.editCell - 6)
    }

    private func editCell(_ item: String, index: Int, p: EmojiPrefs, lifted: Bool, count: Int) -> some View {
        let shown = p.display(item)
        let toningThis = toning?.area == .editFavorites && toning?.emoji == item
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: lifted ? 11 : 10, style: .continuous)
                .fill(lifted ? Self.solidTile : toningThis ? accent.opacity(0.22) : .panelFill)
                .overlay {
                    RoundedRectangle(cornerRadius: lifted ? 11 : 10, style: .continuous)
                        .strokeBorder(lifted || toningThis ? accent.opacity(0.9) : .clear, lineWidth: 1.4)
                }
                .shadow(color: .black.opacity(lifted ? 0.35 : 0), radius: 6, y: 4)
                .frame(width: Self.editCell - 6, height: Self.editCell - 6)
                .overlay {
                    Text(verbatim: shown).font(.system(size: lifted ? 30 : 28))
                }
                .frame(width: Self.editCell, height: Self.editCell)
                .contentShape(.rect)
                .modifier(CellGestures(
                    enabled: !context.isPreview,
                    onTap: nil,
                    onDoubleTap: nil,
                    onLongPress: EmojiCatalog.isModifiable(item) ? { startToning(item, area: .editFavorites) } : nil,
                    drag: count > 1 ? dragHandlers(area: .editFavorites, index: index, count: count,
                                                   columns: Self.editColumns, cell: Self.editCell,
                                                   step: Self.editStep) : nil))
            if !lifted {
                Button {
                    guard !context.isPreview else { return }
                    if toning?.emoji == item { toning = nil }
                    withAnimation(.snappy(duration: 0.2)) { save(p.removingFavorite(at: index)) }
                } label: {
                    ZStack {
                        Circle().fill(Self.solidTile).frame(width: 16, height: 16)
                        Circle().fill(Self.red).frame(width: 14, height: 14)
                        Capsule().fill(Color(hex: "#330B05")).frame(width: 7, height: 1.8)
                    }
                    .frame(width: 22, height: 22)
                    .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .offset(x: -4, y: -4)
                .help(tr("移除"))
                .accessibilityLabel(tr("移除\(EmojiCatalog.entry(item)?.zh.first ?? shown)"))
            }
        }
        .frame(width: Self.editCell, height: Self.editCell)
        .contextMenu {
            if !context.isPreview {
                if EmojiCatalog.isModifiable(item) {
                    Button(tr("选肤色"), systemImage: "hand.raised") { startToning(item, area: .editFavorites) }
                }
                Button(tr("移出收藏"), systemImage: "star.slash") { save(p.removingFavorite(at: index)) }
            }
        }
    }

    private func dragHandlers(area: Area, index: Int, count: Int, columns: Int,
                              cell: CGFloat, step: CGFloat) -> CellGestures.DragHandlers {
        CellGestures.DragHandlers(
            changed: { translation in
                if drag?.area != area || drag?.from != index { toning = nil }
                drag = Drag(area: area, from: index, offset: translation)
            },
            ended: { translation in
                let to = EmojiPrefs.dropIndex(from: index, dx: translation.width, dy: translation.height,
                                              cell: cell, rowStep: step, columns: columns, count: count)
                if to != index { save(prefs.movingFavorite(from: index, to: to)) }
                withAnimation(.snappy(duration: 0.2)) { drag = nil }
            })
    }

    // MARK: 肤色条

    private func startToning(_ item: String, area: Area) {
        guard !context.isPreview, EmojiCatalog.isModifiable(item) else { return }
        withAnimation(.snappy(duration: 0.2)) { toning = (area, item) }
    }

    @ViewBuilder
    private func toneStripIfNeeded(_ area: Area, p: EmojiPrefs) -> some View {
        if let toning, toning.area == area {
            toneStrip(toning.emoji, p: p)
                .padding(.bottom, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    /// 选肤色：左边是这个表情，右边气泡里 6 种。选了就记成这一个的肤色；
    /// 浏览时顺便拷贝。
    private func toneStrip(_ item: String, p: EmojiPrefs) -> some View {
        let variants = EmojiTone.variants(of: item)
        let currentTone = p.toneFor(item)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(tr("选肤色"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelSecondary)
                Spacer(minLength: 0)
                Button(tr("收起")) { withAnimation(.snappy(duration: 0.2)) { toning = nil } }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelSecondary)
            }
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(accent.opacity(0.22))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(accent, lineWidth: 1.4)
                    }
                    .frame(width: 32, height: 32)
                    .overlay { Text(verbatim: p.display(item)).font(.system(size: 22)) }
                HStack(spacing: 0) {
                    ForEach(Array(variants.enumerated()), id: \.offset) { tone, variant in
                        Button {
                            choose(tone, for: item, p: p)
                        } label: {
                            Text(verbatim: variant)
                                .font(.system(size: 22))
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                                .background {
                                    if tone == currentTone {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(.panelFillStrong)
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .strokeBorder(.panelQuaternary, lineWidth: 1)
                                            }
                                            .padding(.horizontal, 3)
                                    }
                                }
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .help(Self.toneName(tone))
                        .accessibilityLabel(Self.toneName(tone))
                    }
                }
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Self.solidTile))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.panelStroke, lineWidth: 0.6)
                }
            }
        }
    }

    private func choose(_ tone: Int, for item: String, p: EmojiPrefs) {
        guard !context.isPreview else { return }
        var next = p.choosingTone(tone, for: item)
        if !editing {
            ColorSampling.copy(next.display(item))
            next = next.recording(item)
            copied = item
            note = .copied
            copyTick += 1
        }
        save(next)
        withAnimation(.snappy(duration: 0.2)) { toning = nil }
    }

    // MARK: 小零件

    private func section(_ title: String, trailing: String?) -> some View {
        section(title, trailing: trailing) { EmptyView() }
    }

    private func section<Accessory: View>(_ title: String, trailing: String?,
                                          @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelSecondary)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
            }
            accessory()
        }
        .lineLimit(1)
        .padding(.bottom, 8)
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.panelSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPane(cornerRadius: 12)
    }

    // MARK: 动作

    private func save(_ next: EmojiPrefs) {
        guard !context.isPreview else { return }
        WidgetWriter.write(current) { next.store(in: &$0) }
    }

    private func copy(_ item: String) {
        guard !context.isPreview else { return }
        let p = prefs
        ColorSampling.copy(p.display(item))
        save(p.recording(item))
        withAnimation(.easeOut(duration: 0.15)) {
            copied = item
            note = .copied
        }
        copyTick += 1
    }

    /// 双击：拷贝，关面板，把 ⌘V 送给前台 App。面板不抢前台（非激活面板），
    /// 但打过字时它是 key，关掉的淡出要 0.14 秒，所以等 0.3 秒再按。没有辅助
    /// 功能权限就请系统弹授权，这次只拷贝，并说一声。
    private func insert(_ item: String) {
        guard !context.isPreview else { return }
        let p = prefs
        ColorSampling.copy(p.display(item))
        save(p.recording(item))
        guard AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) else {
            copied = item
            note = .needsAccess
            copyTick += 1
            return
        }
        WidgetDetailWindow.shared.close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let source = CGEventSource(stateID: .combinedSessionState)
            let v: CGKeyCode = 9
            let down = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false)
            down?.flags = .maskCommand
            up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }

    private func toggleFavorite(_ item: String) {
        guard !context.isPreview else { return }
        guard let next = prefs.togglingFavorite(item) else {
            fullWarning = true
            return
        }
        fullWarning = false
        withAnimation(.snappy(duration: 0.2)) { save(next) }
    }

    private func clearRecent() {
        guard !context.isPreview else { return }
        save(prefs.clearingRecent())
        if toning?.area == .recent { toning = nil }
        shownRecent = []
    }
}

/// 一格表情上的手势：点、双击、按住、拖动，按需挂上。
///
/// 双击和单击同时识别：单击马上拷贝，不等双击超时；双击时单击已经拷过一次，
/// 第二下再插到光标处。按住只在几乎没动时算（最多挪 4pt），挪多了就是拖动。
private struct CellGestures: ViewModifier {
    struct DragHandlers {
        var changed: (CGSize) -> Void
        var ended: (CGSize) -> Void
    }

    var enabled: Bool
    var onTap: (() -> Void)?
    var onDoubleTap: (() -> Void)?
    var onLongPress: (() -> Void)?
    var drag: DragHandlers?

    func body(content: Content) -> some View {
        content
            .onTapGesture { if enabled { onTap?() } }
            .simultaneousGesture(TapGesture(count: 2).onEnded { if enabled { onDoubleTap?() } },
                                 including: onDoubleTap == nil ? .subviews : .all)
            .onLongPressGesture(minimumDuration: 0.4, maximumDistance: 4) {
                if enabled { onLongPress?() }
            }
            .gesture(DragGesture(minimumDistance: 5, coordinateSpace: .global)
                .onChanged { value in if enabled { drag?.changed(value.translation) } }
                .onEnded { value in if enabled { drag?.ended(value.translation) } },
                     including: drag == nil ? .subviews : .all)
    }
}
