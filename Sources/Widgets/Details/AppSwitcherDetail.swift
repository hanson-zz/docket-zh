import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 应用切换器面板（整种 Pro）：
/// - 「固定」一行：固定的 App 没开也在（半透明），点了启动；开着的下面一个小点。
/// - 「正在运行」列表：按所选排序（最近使用 / 名称 / 固定在前），隐藏的不列；右边是窗口数
///   小角标和箭头，点箭头展开这个 App 的窗口标题，点一个跳到那个窗口。读窗口要「辅助功能」
///   权限，没给时展开处写一行说明和「去授权」，其余照常。
/// - 底部排序和「已隐藏 N 个 · 管理」。
/// - 「编辑」：固定 / 取消固定、前后挪、隐藏 / 取消隐藏、添加没开的 App。
/// 右键一行：切换、固定、不在切换器显示、隐藏、退出。
struct AppSwitcherDetail: View {
    @Environment(\.panelTint) private var panelTint
    var instance: WidgetInstance
    var context: WidgetContext

    @State private var editing = false
    @State private var expanded: String?
    @State private var windows: [AppWindows.Window] = []
    @State private var counts: [String: Int] = [:]
    @State private var trusted = false

    private var catalog: AppCatalog { AppCatalog.shared }
    private var config: WidgetConfig { instance.config }

    /// 效果图的淡紫，实心按钮上的字用深色。
    private var accent: Color { panelTint.accent(or: Color(hex: "#A7B4FF")) }
    private var ink: Color { panelTint.ink(or: Color(hex: "#0E1440")) }

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

    var body: some View {
        let shown = list
        return DetailCard {
            MeshBackdrop(color: WidgetStyle.tint(.indigo))
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                header(running: runningApps.count)
                if editing {
                    editor
                } else {
                    if !pinned.isEmpty { pinnedRow }
                    runningSection(shown)
                    sortRow
                    if !hidden.isEmpty { hiddenLine }
                }
            }
        }
        .onAppear {
            guard !context.isPreview else { return }
            catalog.refresh()
            reloadWindows()
        }
        .onChange(of: catalog.runningIDs) { _, _ in
            if expanded.map({ !catalog.isRunning(bundleID: $0) }) ?? false { expanded = nil }
            reloadWindows()
        }
    }

    // MARK: Header

    private func header(running: Int) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("应用切换器")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)
                Text(AppSwitcherList.subtitle(pinned: pinned.count, running: running))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                withAnimation(.snappy(duration: 0.25)) { editing.toggle() }
            } label: {
                Text(editing ? tr("完成") : tr("编辑"))
                    .font(.system(size: 13, weight: editing ? .bold : .semibold))
                    .foregroundStyle(editing ? ink : .white)
                    .padding(.horizontal, editing ? 15 : 13)
                    .frame(height: 28)
                    .background(Capsule().fill(editing ? accent : .white.opacity(0.1)))
                    .overlay(Capsule().strokeBorder(.white.opacity(editing ? 0 : 0.14), lineWidth: 0.8))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(context.isPreview)
        }
    }

    private func section(_ title: String, note: String? = nil) -> some View {
        HStack {
            Text(verbatim: title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.62))
            Spacer(minLength: 6)
            if let note {
                Text(verbatim: note)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }
        }
    }

    // MARK: Pinned

    private var pinnedRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            section(tr("固定", context: "section"), note: tr("没开也在，点了启动"))
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(40), spacing: 8), count: 6),
                      alignment: .leading, spacing: 10) {
                ForEach(pinned, id: \.self) { id in
                    let app = item(id)
                    Button { open(app) } label: {
                        VStack(spacing: 4) {
                            AppSwitcherIcon(app: app, size: 40)
                                .opacity(app.isRunning ? 1 : 0.45)
                            Circle()
                                .fill(.white.opacity(app.isRunning ? 0.8 : 0))
                                .frame(width: 4, height: 4)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help(app.isRunning ? app.name : tr("\(app.name)（没开，点了启动）"))
                    .accessibilityLabel(app.isRunning ? app.name : tr("\(app.name)，没开，点按启动"))
                    .contextMenu { menu(app) }
                }
            }
        }
    }

    // MARK: Running

    private func runningSection(_ shown: [AppSwitcherItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            section(tr("正在运行 · \(sort.title)"))
            if shown.isEmpty {
                Text(runningApps.isEmpty ? tr("没有正在运行的应用。") : tr("正在运行的应用都隐藏了。"))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(shown) { app in
                            row(app)
                            if expanded == app.id { windowList(app) }
                        }
                    }
                }
                .scrollIndicators(.never)
                .frame(height: listHeight(shown))
            }
        }
    }

    /// 列表的高度：每行 40，展开的窗口每个 30（说明一行 34），最高 260，再多在里面滚。
    private func listHeight(_ shown: [AppSwitcherItem]) -> CGFloat {
        var height = CGFloat(shown.count) * 40
        if let id = expanded, shown.contains(where: { $0.id == id }) {
            height += !trusted || windows.isEmpty ? 38 : CGFloat(windows.count) * 30 + 4
        }
        return min(260, height)
    }

    private func row(_ app: AppSwitcherItem) -> some View {
        let open = expanded == app.id
        return HStack(spacing: 10) {
            AppSwitcherIcon(app: app, size: 24)
            Text(verbatim: app.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if let count = counts[app.id], count > 0 {
                Text(count > 1 && open ? tr("\(count) 个窗口") : "\(count)")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(Capsule().fill(.white.opacity(0.14)))
                    .help(tr("\(count) 个窗口"))
            }
            Button {
                toggleExpand(app.id)
            } label: {
                Image(systemName: open ? "chevron.down" : "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 26, height: 26)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(context.isPreview)
            .help(open ? tr("收起窗口列表") : tr("展开窗口列表"))
            .accessibilityLabel(open ? tr("收起 \(app.name) 的窗口") : tr("展开 \(app.name) 的窗口"))
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(height: 38)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(.white.opacity(app.isActive ? 0.12 : 0.06)))
        .contentShape(.rect(cornerRadius: 11))
        .onTapGesture { self.open(app) }
        .contextMenu { menu(app) }
        .help(app.name)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(app.isActive ? tr("\(app.name)（当前）") : app.name)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func windowList(_ app: AppSwitcherItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if !trusted {
                HStack(spacing: 8) {
                    Text("列出窗口需要辅助功能权限")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Button {
                        AppWindows.requestAccess()
                    } label: {
                        Text("去授权")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(ink)
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .background(Capsule().fill(accent))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 14)
                .frame(height: 30)
            } else if windows.isEmpty {
                Text("没有打开的窗口")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.leading, 14)
                    .frame(height: 28)
            } else {
                ForEach(Array(windows.enumerated()), id: \.element.id) { index, window in
                    Button {
                        AppWindows.focus(window, bundleID: app.id)
                    } label: {
                        Text(verbatim: window.title)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(index == 0 ? 0.9 : 0.75))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .padding(.horizontal, 14)
                            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(index == 0 ? accent.opacity(0.16) : .clear))
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help(window.title)
                }
            }
        }
        .padding(.leading, 30)
        .padding(.vertical, 2)
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
                        Text(verbatim: option.title)
                            .font(.system(size: 13, weight: on ? .bold : .semibold))
                            .foregroundStyle(on ? ink : .white.opacity(0.88))
                            .lineLimit(1)
                            .padding(.horizontal, 11)
                            .frame(height: 30)
                            .background(Capsule().fill(on ? accent : .white.opacity(0.08)))
                            .overlay(Capsule().strokeBorder(.white.opacity(on ? 0 : 0.14), lineWidth: 0.6))
                            .contentShape(Capsule())
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
                Text(tr(" · 管理")).fixedSize()
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(0.62))
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
                        .foregroundStyle(.white.opacity(pins.count >= AppSwitcherList.maxPinned ? 0.4 : 0.9))
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.white.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
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
            .foregroundStyle(.white.opacity(0.62))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func editRow<Buttons: View>(_ app: AppSwitcherItem, dim: Bool = false,
                                        @ViewBuilder buttons: () -> Buttons) -> some View {
        HStack(spacing: 10) {
            AppSwitcherIcon(app: app, size: 24).opacity(dim ? 0.5 : 1)
            Text(verbatim: app.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(dim ? 0.6 : 0.95))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            buttons()
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(height: 38)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(.white.opacity(0.06)))
    }

    private func iconButton(_ symbol: String, help: String, disabled: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(disabled ? 0.3 : 0.85))
                .frame(width: 28, height: 28)
                .background(Circle().fill(.white.opacity(disabled ? 0.04 : 0.1)))
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
                Button("切换到此应用") { _ = catalog.activate(bundleID: app.id) }
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

    private func toggleExpand(_ id: String) {
        withAnimation(.snappy(duration: 0.2)) {
            expanded = expanded == id ? nil : id
        }
        reloadWindows()
    }

    /// 重新读权限、窗口数和展开那个 App 的窗口。只在打开面板、展开和 App 开关时读。
    private func reloadWindows() {
        guard !context.isPreview else { return }
        trusted = AppWindows.isTrusted
        counts = AppWindows.counts(bundleIDs: catalog.running.map(\.id).filter { !hidden.contains($0) })
        windows = expanded.map { AppWindows.windows(bundleID: $0) } ?? []
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
        if expanded == id { expanded = nil }
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
