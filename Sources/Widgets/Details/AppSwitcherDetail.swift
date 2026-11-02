import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 应用切换器面板（整种 Pro），v2 效果图 design/app-switcher-v2.py：
/// - 标题和 Pro 角标、「固定 N 个 · 运行中 N 个」、右上「编辑」。
/// - 「固定」「正在运行」两块是只有图标的自适应网格（每格至少 52，图标 44），网格里不写名字，
///   悬停提示名字；固定的没开时半透明，点了启动，开着的下面一个小点；正在运行的窗口数大于 1 时
///   右上角一个实心数字角标。高度按行数算，正在运行最多摊开 4 行，再多在网格里滚。
/// - 点一个图标：垫中性浅色高亮块，在那块网格下面展开名字、「当前 · N 个窗口」、「切到前台」，
///   下面一排窗口缩略图（窄时横向滚动），点缩略图跳到那个窗口；再点同一个图标收起。
///   缩略图要「屏幕录制」权限，没给时列窗口标题和「去授权」；读窗口要「辅助功能」，没给时沿用原来的说明。
/// - 悬停时浅色块跟着鼠标；方向键移动选中、回车切换、空格展开收起、Esc 收起。
/// - 底部排序胶囊（选中的是中性浅色块）和「已隐藏 N 个 · 管理」。
/// - 「编辑」：沿用列表编辑器，固定 / 取消固定、前后挪、隐藏 / 取消隐藏、添加没开的 App。
/// 右键一个图标：切换、固定、不在切换器显示、隐藏、退出。
struct AppSwitcherDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private typealias Position = AppSwitcherLayout.Position

    /// 一格认 App 不认序号：App 开关、列表重排后选中的还是那个 App。
    private struct Slot: Equatable {
        var section: Int
        var id: String
    }

    @State private var editing = false
    /// 选中的那一格（点的、键盘走到的）；`expanded` 时在它那块网格下面展开。
    @State private var cursor: Slot?
    @State private var expanded = false
    /// 键盘走过或展开过：选中块画出来。点同一个图标收起、Esc 后不画。
    @State private var showsCursor = false
    @State private var hovered: Slot?
    @State private var windows: [AppWindows.Window] = []
    /// `windows` 是哪个 App 的。
    @State private var windowsFor: String?
    @State private var counts: [String: Int] = [:]
    @State private var trusted = false
    @State private var canCapture = false
    /// 内容区宽度（320 面板 288，尾巴在侧边时 280），按它算网格列数。
    @State private var contentWidth: CGFloat = 288
    @FocusState private var focused: Bool

    private var catalog: AppCatalog { AppCatalog.shared }
    private var thumbnails: AppWindowThumbnails { AppWindowThumbnails.shared }
    private var config: WidgetConfig { instance.config }

    private var sort: AppSwitcherList.Sort { AppSwitcherList.sort(config) }
    private var pinned: [String] {
        context.isPreview ? AppSwitcherItem.samples.prefix(3).map(\.id) : AppSwitcherList.pinned(config)
    }
    private var hidden: [String] { context.isPreview ? [] : AppSwitcherList.hidden(config) }

    private var runningApps: [AppSwitcherList.App] {
        if context.isPreview {
            return AppSwitcherItem.samples.map { .init(id: $0.id, name: $0.name, isActive: $0.isActive) }
        }
        return catalog.running.map { .init(id: $0.id, name: $0.name, isActive: $0.isActive) }
    }

    /// 「正在运行」列表，按排序、去掉隐藏的。
    private var list: [AppSwitcherItem] {
        AppSwitcherList.running(runningApps, recent: catalog.recentIDs, pinned: pinned, hidden: hidden, sort: sort)
            .map { item($0.id) }
    }

    /// 两块网格：0 固定，1 正在运行。
    private var sections: [[AppSwitcherItem]] { [pinned.map { item($0) }, list] }

    /// 网格两边各让 3pt，角标往外探一点不被裁。
    private var gridInset: CGFloat { 3 }
    private var columns: Int { AppSwitcherLayout.columns(width: Double(contentWidth - gridInset * 2)) }

    private func app(at position: Position?, in sections: [[AppSwitcherItem]]) -> AppSwitcherItem? {
        guard let position, sections.indices.contains(position.section),
              sections[position.section].indices.contains(position.index) else { return nil }
        return sections[position.section][position.index]
    }

    private func position(_ slot: Slot?, in sections: [[AppSwitcherItem]]) -> Position? {
        guard let slot, sections.indices.contains(slot.section),
              let index = sections[slot.section].firstIndex(where: { $0.id == slot.id }) else { return nil }
        return Position(section: slot.section, index: index)
    }

    private func slot(_ position: Position?, in sections: [[AppSwitcherItem]]) -> Slot? {
        guard let position, let app = app(at: position, in: sections) else { return nil }
        return Slot(section: position.section, id: app.id)
    }

    private func app(for slot: Slot?, in sections: [[AppSwitcherItem]]) -> AppSwitcherItem? {
        app(at: position(slot, in: sections), in: sections)
    }

    var body: some View {
        let all = sections
        let selected = expanded ? app(for: cursor, in: all) : nil
        return DetailCard {
            Color.clear
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                header(running: runningApps.count)
                if editing {
                    editor
                } else {
                    if !all[0].isEmpty { pinnedSection(all, selected: selected) }
                    runningSection(all, selected: selected)
                    sortRow
                    if !hidden.isEmpty { hiddenLine }
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                if abs(width - contentWidth) > 0.5 { contentWidth = width }
            }
        }
        .focusable(!editing && !context.isPreview)
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow, .return, .space, .escape]) { press in
            handleKey(press.key)
        }
        .onAppear {
            guard !context.isPreview else { return }
            catalog.refresh()
            reloadCounts()
            focused = true
        }
        .onChange(of: catalog.runningIDs) { _, _ in
            // 展开的那个 App 退出了（或从列表里没了）就收起。
            if expanded, app(for: cursor, in: sections)?.isRunning != true { collapse() }
            reloadCounts()
            if expanded { reloadWindows() }
        }
        // 切到别的 App（比如去系统设置授权再回来）时重新看一眼权限，变了就重读。
        .onChange(of: catalog.running.first(where: \.isActive)?.id) { _, _ in
            guard !context.isPreview else { return }
            let nowTrusted = AppWindows.isTrusted, nowCapture = AppWindows.canCapture
            guard nowTrusted != trusted || nowCapture != canCapture else { return }
            if !nowCapture { thumbnails.clear() }
            reloadCounts()
            if expanded { reloadWindows() }
        }
        .task(id: expanded ? selected?.id : nil) {
            guard expanded else { return }
            // 方向键连着按时不挨个读，停一下再读。
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            reloadWindows()
        }
        .onChange(of: editing) { _, now in
            if now { collapse() }
        }
    }

    // MARK: Header

    private func header(running: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("应用切换器")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(.panelPrimary)
                        .lineLimit(1)
                        .fixedSize()
                    ProBadge()
                }
                Text(AppSwitcherList.subtitle(pinned: pinned.count, running: running))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                withAnimation(.snappy(duration: 0.25)) { editing.toggle() }
            } label: {
                AppSwitcherChipLabel(title: editing ? tr("完成") : tr("编辑"), on: editing, height: 28)
                    .fixedSize()
            }
            .buttonStyle(.plain)
            .disabled(context.isPreview)
        }
    }

    private func section(_ title: String, note: String? = nil) -> some View {
        HStack {
            Text(verbatim: title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelSecondary)
                .lineLimit(1)
            Spacer(minLength: 6)
            if let note {
                Text(verbatim: note)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: Grids

    private func pinnedSection(_ all: [[AppSwitcherItem]], selected: AppSwitcherItem?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            section(tr("固定", context: "section"), note: tr("没开也在，点了启动"))
            grid(all[0], section: 0)
            if expanded, cursor?.section == 0, let selected { expansion(selected) }
        }
    }

    private func runningSection(_ all: [[AppSwitcherItem]], selected: AppSwitcherItem?) -> some View {
        let shown = all[1]
        let rows = AppSwitcherLayout.rows(count: shown.count, columns: columns)
        return VStack(alignment: .leading, spacing: 8) {
            section(tr("正在运行 · \(sort.title)"))
            if shown.isEmpty {
                Text(runningApps.isEmpty ? tr("没有正在运行的应用。") : tr("正在运行的应用都隐藏了。"))
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else if rows > AppSwitcherLayout.panelMaxRows {
                ScrollViewReader { proxy in
                    ScrollView {
                        grid(shown, section: 1)
                            .padding(.vertical, gridInset)
                    }
                    .scrollIndicators(.never)
                    .frame(height: CGFloat(AppSwitcherLayout.gridHeight(count: shown.count, columns: columns,
                                                                        maxRows: AppSwitcherLayout.panelMaxRows))
                           + gridInset * 2)
                    .onChange(of: cursor) { _, now in
                        guard let now, now.section == 1 else { return }
                        withAnimation(.snappy(duration: 0.2)) { proxy.scrollTo(now.id) }
                    }
                }
            } else {
                grid(shown, section: 1)
            }
            if expanded, cursor?.section == 1, let selected { expansion(selected) }
        }
    }

    /// 一块图标网格：`GridItem(.adaptive(minimum: 52))`，列数和 `columns` 同一个算法。
    private func grid(_ apps: [AppSwitcherItem], section: Int) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: CGFloat(AppSwitcherLayout.panelCell)),
                                     spacing: CGFloat(AppSwitcherLayout.panelColumnSpacing))],
                  spacing: CGFloat(AppSwitcherLayout.panelRowSpacing)) {
            ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                cell(app, at: Position(section: section, index: index))
                    .id(app.id)
            }
        }
        .padding(.horizontal, gridInset)
    }

    private func cell(_ app: AppSwitcherItem, at position: Position) -> some View {
        let here = Slot(section: position.section, id: app.id)
        let isCursor = cursor == here && (showsCursor || expanded)
        let isPinnedSection = position.section == 0
        let count = counts[app.id] ?? 0
        return Button { tap(app, at: position) } label: {
            AppSwitcherIcon(app: app, size: CGFloat(AppSwitcherLayout.panelIcon),
                            plate: CGFloat(AppSwitcherLayout.panelCell),
                            selected: isCursor, hovered: !isCursor && hovered == here,
                            dot: isPinnedSection && app.isRunning,
                            badge: isPinnedSection ? nil : count, dimsWhenOff: true)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside {
                hovered = here
            } else if hovered == here {
                hovered = nil
            }
        }
        .help(app.isRunning ? app.name : tr("\(app.name)（没开，点了启动）"))
        .accessibilityLabel(app.isActive ? tr("\(app.name)（当前）")
                            : app.isRunning ? app.name : tr("\(app.name)，没开，点按启动"))
        .accessibilityAddTraits(isCursor ? .isSelected : [])
        .contextMenu { menu(app) }
    }

    // MARK: Expansion

    private func expansion(_ app: AppSwitcherItem) -> some View {
        let count: Int? = windowsFor == app.id && trusted ? windows.count : nil
        let status = AppSwitcherLayout.status(isActive: app.isActive, isRunning: app.isRunning, windows: count)
        let nameRow = HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(verbatim: app.name)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.panelPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            if !status.isEmpty {
                Text(verbatim: status)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        let button = Button { open(app) } label: {
            AppSwitcherButtonLabel(title: app.isRunning ? tr("切到前台") : tr("打开"))
        }
        .buttonStyle(.plain)
        .disabled(context.isPreview)
        return VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 8) {
                    nameRow
                    Spacer(minLength: 8)
                    button
                }
                VStack(alignment: .leading, spacing: 8) {
                    nameRow
                    button
                }
            }
            if app.isRunning, !context.isPreview {
                if windowsFor == app.id {
                    AppSwitcherWindowStrip(app: app, windows: windows, trusted: trusted, canCapture: canCapture,
                                           style: .panel, width: max(0, contentWidth - 24)) { window in
                        AppWindows.focus(window, bundleID: app.id)
                    }
                } else {
                    Color.clear.frame(height: 28)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.panelFill))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Color.panelStroke, lineWidth: 0.8))
        .transition(.opacity)
    }

    // MARK: Sort and hidden

    private var sortRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            section(tr("排序"))
            HStack(spacing: 6) {
                ForEach(AppSwitcherList.Sort.allCases) { option in
                    let on = option == sort
                    Button {
                        guard !context.isPreview else { return }
                        WidgetWriter.write(instance) { $0.set(AppSwitcherList.sortKey, .string(option.rawValue)) }
                    } label: {
                        AppSwitcherChipLabel(title: option.title, on: on)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }

    private var hiddenLine: some View {
        let names = hidden.map { item($0).name }.joined(separator: tr("、"))
        return Button {
            withAnimation(.snappy(duration: 0.25)) { editing = true }
        } label: {
            HStack(spacing: 0) {
                Text(tr("已隐藏 \(hidden.count) 个（\(names)）"))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.panelSecondary)
                Text(tr(" · 管理"))
                    .fontWeight(.semibold)
                    .foregroundStyle(.panelPrimary)
                    .fixedSize()
            }
            .font(.system(size: 13, weight: .medium))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(names)
    }

    // MARK: Editing

    private var editor: some View {
        let pins = pinned
        let hides = hidden
        let others = list.filter { !pins.contains($0.id) }
        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                section(tr("固定", context: "section"), note: "\(pins.count) / \(AppSwitcherList.maxPinned)")
                if pins.isEmpty {
                    editNote(tr("还没有固定的 App。在下面点图钉，或添加一个没开的 App。"))
                }
                ForEach(Array(pins.enumerated()), id: \.element) { index, id in
                    editRow(item(id)) {
                        iconButton("chevron.up", help: tr("往前挪"), disabled: index == 0) { movePin(id, by: -1) }
                        iconButton("chevron.down", help: tr("往后挪"), disabled: index == pins.count - 1) {
                            movePin(id, by: 1)
                        }
                        iconButton("pin.slash", help: tr("取消固定")) { togglePin(id) }
                    }
                }
                Button { addApp() } label: {
                    Label(tr("添加 App…"), systemImage: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(pins.count >= AppSwitcherList.maxPinned ? Color.panelTertiary : Color.panelPrimary)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.panelQuaternary, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .disabled(pins.count >= AppSwitcherList.maxPinned)
                .help(pins.count >= AppSwitcherList.maxPinned
                      ? tr("最多固定 \(AppSwitcherList.maxPinned) 个") : tr("从「应用程序」里选一个 App 固定"))

                if !others.isEmpty {
                    section(tr("正在运行")).padding(.top, 6)
                    ForEach(others) { app in
                        editRow(app) {
                            iconButton("pin", help: tr("固定"), disabled: pins.count >= AppSwitcherList.maxPinned) {
                                togglePin(app.id)
                            }
                            iconButton("eye.slash", help: tr("不在切换器显示")) { toggleHide(app.id) }
                        }
                    }
                }

                if !hides.isEmpty {
                    section(tr("已隐藏")).padding(.top, 6)
                    ForEach(hides, id: \.self) { id in
                        editRow(item(id), dim: true) {
                            iconButton("eye", help: tr("重新显示")) { toggleHide(id) }
                        }
                    }
                }
            }
        }
        .scrollIndicators(.never)
        .frame(height: editorHeight(pins: pins.count, others: others.count, hidden: hides.count))
    }

    /// 编辑页高度：小标题 24、每行 46、添加按钮 40，最高 440，再多在里面滚。
    private func editorHeight(pins: Int, others: Int, hidden: Int) -> CGFloat {
        var height: CGFloat = 24 + 40 + (pins == 0 ? 44 : CGFloat(pins) * 46)
        if others > 0 { height += 30 + CGFloat(others) * 46 }
        if hidden > 0 { height += 30 + CGFloat(hidden) * 46 }
        return min(440, height)
    }

    private func editNote(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 13))
            .foregroundStyle(.panelSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func editRow<Buttons: View>(_ app: AppSwitcherItem, dim: Bool = false,
                                        @ViewBuilder buttons: () -> Buttons) -> some View {
        HStack(spacing: 10) {
            AppSwitcherIcon(app: app, size: 24).opacity(dim ? 0.5 : 1)
            Text(verbatim: app.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(dim ? Color.panelSecondary : Color.panelPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            buttons()
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(height: 38)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.panelFill))
    }

    private func iconButton(_ symbol: String, help: String, disabled: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(disabled ? Color.panelQuaternary : Color.panelPrimary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.panelFill))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled || context.isPreview)
        .help(help)
        .accessibilityLabel(help)
    }

    // MARK: Menu

    @ViewBuilder
    private func menu(_ app: AppSwitcherItem) -> some View {
        if !context.isPreview {
            if app.isRunning {
                Button("切换到此应用") { catalog.bringForward(bundleID: app.id, savedURL: nil) }
            } else {
                Button("打开") { open(app) }
            }
            Button(pinned.contains(app.id) ? tr("取消固定") : tr("固定")) { togglePin(app.id) }
                .disabled(!pinned.contains(app.id) && pinned.count >= AppSwitcherList.maxPinned)
            if !pinned.contains(app.id) {
                Button("不在切换器显示") { toggleHide(app.id) }
            }
            if app.isRunning {
                Divider()
                Button(tr("隐藏", context: "verb")) { _ = AppWindows.process(bundleID: app.id)?.hide() }
                Button("退出") { _ = AppWindows.process(bundleID: app.id)?.terminate() }
            }
        }
    }

    // MARK: Data

    /// 一个 App 的名字和图标：开着的从运行列表读，没开的从磁盘上的 .app 读，找不到时显示 bundle id。
    private func item(_ id: String) -> AppSwitcherItem {
        if context.isPreview, let sample = AppSwitcherItem.samples.first(where: { $0.id == id }) { return sample }
        if let app = catalog.running.first(where: { $0.id == id }) {
            return AppSwitcherItem(id: app.id, name: app.name, url: app.url, isActive: app.isActive)
        }
        return AppSwitcherItem.notRunning(id)
    }

    private func open(_ app: AppSwitcherItem) {
        guard !context.isPreview else { return }
        catalog.open(WidgetTarget.app(bundleID: app.id))
    }

    // MARK: Selection

    /// 点一个图标：没开的固定 App 直接启动；开着的展开，展开着的再点收起。
    private func tap(_ app: AppSwitcherItem, at position: Position) {
        guard !context.isPreview else { return }
        focused = true
        let here = Slot(section: position.section, id: app.id)
        if !app.isRunning {
            cursor = here
            showsCursor = false
            collapse()
            open(app)
            return
        }
        if expanded, cursor == here {
            collapse()
            showsCursor = false
            return
        }
        withAnimation(.snappy(duration: 0.2)) {
            cursor = here
            showsCursor = true
            expanded = true
        }
    }

    private func collapse() {
        guard expanded else { return }
        withAnimation(.snappy(duration: 0.2)) { expanded = false }
    }

    /// 方向键移动选中（展开着的跟着换），回车切换，空格展开收起，Esc 收起（没展开时再按交给面板）。
    private func handleKey(_ key: KeyEquivalent) -> KeyPress.Result {
        guard !editing, !context.isPreview else { return .ignored }
        let all = sections
        let sizes = all.map(\.count)
        let current = position(cursor, in: all)
        switch key {
        case .leftArrow, .rightArrow, .upArrow, .downArrow:
            let move: AppSwitcherLayout.Move = key == .leftArrow ? .left : key == .rightArrow ? .right
                : key == .upArrow ? .up : .down
            // 第一次按（还没画选中块）：落在当前的 App 上（它在列表里时），否则第一格。
            let next: Position?
            if let current, showsCursor || expanded {
                next = AppSwitcherLayout.move(current, move, sections: sizes, columns: columns)
            } else {
                next = activePosition(in: all)
            }
            guard let next else { return .ignored }
            withAnimation(.snappy(duration: 0.15)) {
                cursor = slot(next, in: all)
                showsCursor = true
                // 展开着时选中没开的 App 就收起（没窗口可看）。
                if expanded, app(at: next, in: all)?.isRunning != true { expanded = false }
            }
            return .handled
        case .return:
            guard let target = app(at: current, in: all), showsCursor || expanded else { return .ignored }
            open(target)
            return .handled
        case .space:
            let target = current ?? activePosition(in: all)
            guard let target, let picked = app(at: target, in: all) else { return .ignored }
            let pickedSlot = slot(target, in: all)
            if expanded, cursor == pickedSlot {
                collapse()
            } else if picked.isRunning {
                withAnimation(.snappy(duration: 0.2)) {
                    cursor = pickedSlot
                    showsCursor = true
                    expanded = true
                }
            } else {
                cursor = pickedSlot
                showsCursor = true
            }
            return .handled
        case .escape:
            if expanded {
                collapse()
                return .handled
            }
            if showsCursor {
                showsCursor = false
                return .handled
            }
            return .ignored
        default:
            return .ignored
        }
    }

    /// 当前 App 在「正在运行」里的位置；不在时第一格。
    private func activePosition(in all: [[AppSwitcherItem]]) -> Position? {
        if let index = all[1].firstIndex(where: \.isActive) { return Position(section: 1, index: index) }
        return AppSwitcherLayout.move(nil, .right, sections: all.map(\.count), columns: columns)
    }

    // MARK: Windows

    /// 窗口数角标：只在打开面板和 App 开关、权限变了时读一遍，不轮询。
    private func reloadCounts() {
        guard !context.isPreview else { return }
        trusted = AppWindows.isTrusted
        canCapture = AppWindows.canCapture
        counts = AppWindows.counts(bundleIDs: catalog.running.map(\.id).filter { !hidden.contains($0) })
    }

    /// 展开那个 App 的窗口（截缩略图用的那份，带系统窗口号）。只在展开、换了展开的 App、
    /// App 开关和权限变了时读；缩略图由 `AppSwitcherWindowStrip` 按窗口列表要，重画不截。
    private func reloadWindows() {
        guard !context.isPreview, expanded, let target = app(for: cursor, in: sections), target.isRunning else {
            windows = []
            windowsFor = nil
            return
        }
        trusted = AppWindows.isTrusted
        canCapture = AppWindows.canCapture
        windows = AppWindows.thumbnailWindows(bundleID: target.id)
        windowsFor = target.id
        if trusted { counts[target.id] = windows.count }
    }

    /// 按存着的最新列表改，再整个写回（文件面板回来后面板里的副本可能已经旧了）。
    private func writeLists(_ change: ([String], [String]) -> (pinned: [String], hidden: [String])) {
        guard !context.isPreview else { return }
        WidgetWriter.write(WidgetWriter.current(instance.id) ?? instance) { config in
            let next = change(AppSwitcherList.pinned(config), AppSwitcherList.hidden(config))
            config.set(AppSwitcherList.pinnedKey, .list(next.pinned.map { .string($0) }))
            config.set(AppSwitcherList.hiddenKey, .list(next.hidden.map { .string($0) }))
        }
    }

    private func togglePin(_ id: String) {
        writeLists { AppSwitcherList.togglePin(id, pinned: $0, hidden: $1) }
    }

    private func toggleHide(_ id: String) {
        if expanded, app(for: cursor, in: sections)?.id == id { collapse() }
        writeLists { AppSwitcherList.toggleHide(id, pinned: $0, hidden: $1) }
    }

    private func movePin(_ id: String, by step: Int) {
        writeLists { (AppSwitcherList.move(id, by: step, in: $0), $1) }
    }

    /// 从「应用程序」里选一个 App 固定（没开的也行）。
    /// 面板会在打开文件面板时收起，选好的照样写回小组件（和摸鱼时钟选背景图一样）。
    private func addApp() {
        guard !context.isPreview else { return }
        let policy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        defer { NSApp.setActivationPolicy(policy) }

        let panel = NSOpenPanel()
        panel.message = tr("选一个 App 固定到应用切换器")
        panel.prompt = tr("固定")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier else { return }
        writeLists { pins, hides in
            pins.contains(id) ? (pins, hides) : AppSwitcherList.togglePin(id, pinned: pins, hidden: hides)
        }
    }
}
