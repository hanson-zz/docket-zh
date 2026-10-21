import AppKit
import Observation
import Quartz
import SwiftUI
import UniformTypeIdentifiers

/// 点扩展栏上的文件夹格子弹出的浏览小窗：在扩展栏上方（按扩展栏所在的边）
/// 列出文件夹里的东西，点子文件夹在小窗里进入，点文件用默认 App 打开。
///
/// 和分组窗口、小组件面板一样是单独的面板，同一时间三者只开一个。点小窗外面
/// 任意地方（别的 App、桌面、扩展栏其他位置）、按 Esc（搜索有字时先清空搜索）、
/// 再点一次同一个格子都会关上，见 PopupDismisser。排序、过滤、相对时间这些
/// 规则在 Core 的 `FolderBrowse`。
@MainActor
final class FolderBrowserWindow {
    static let shared = FolderBrowserWindow()

    /// 开着的是扩展栏上哪个文件夹格子，再点同一个就关。
    private(set) var openFolderID: UUID?

    private var panel: FolderBrowserPanel?
    private var hosting: FirstMouseHostingView<FolderBrowserView>?
    private let model = FolderBrowserModel()
    /// 点外面、按 Esc 就关。
    private let dismisser = PopupDismisser()
    /// 扩展栏自己的范围（没有点位时用来推算弹出位置）。
    private var host: CGRect = .zero
    /// 确认移到废纸篓的提示框开着时不算点到外面。
    private var holdOpen = false
    private let preview = QuickLookSource()
    /// 开着的是文件夹分组时，组里的操作（切换、加、移除、重排）交给扩展栏按 id 改。
    private var groupActions: FolderGroupActions?

    private init() {
        dismisser.visibleFrame = { [weak self] in
            guard let self, self.isOpen else { return nil }
            return self.panel?.frame
        }
        dismisser.window = { [weak self] in self?.panel }
        dismisser.currentID = { [weak self] in self?.openFolderID }
        dismisser.holdOpen = { [weak self] in self?.holdOpen ?? false }
        dismisser.inner = { [weak self] in !(self?.model.query.isEmpty ?? true) }
        dismisser.backOut = { [weak self] in
            // 清空并退出搜索，第二次 Esc 再收起。
            self?.model.query = ""
            _ = self?.panel?.makeFirstResponder(nil)
        }
        dismisser.dismiss = { [weak self] in self?.close() }
    }

    var isOpen: Bool { openFolderID != nil && panel?.isVisible == true }

    /// 小窗的范围（屏幕坐标）。
    func contains(_ point: CGPoint) -> Bool {
        guard isOpen, let panel else { return false }
        return panel.frame.insetBy(dx: -8, dy: -8).contains(point)
    }

    /// 打开 `folder`；已经开着同一个格子就关上。
    func toggle(id: UUID, folder: URL, anchor: CGPoint, edge: DockPosition, host: CGRect) {
        if openFolderID == id, isOpen { return close() }
        // 点外面收起它的正是点这个格子的那一下：结果是收起，不再打开。
        if dismisser.swallowsOpen(id: id) { return }
        groupActions = nil
        show(id: id, source: .folder(folder), anchor: anchor, edge: edge, host: host)
    }

    /// 打开文件夹分组：顶部多一排文件夹标签，打开上次看的那个；已经开着同一个组就关上。
    func toggleGroup(_ group: DockGroup, anchor: CGPoint, edge: DockPosition, host: CGRect,
                     actions: FolderGroupActions) {
        if openFolderID == group.id, isOpen { return close() }
        if dismisser.swallowsOpen(id: group.id) { return }
        groupActions = actions
        show(id: group.id, source: .group(group), anchor: anchor, edge: edge, host: host)
    }

    /// 扩展栏上的组变了（加了、移除了、挪了文件夹）：开着的就原地换标签，
    /// 正在看的还在就不打断。
    func refreshGroup(_ group: DockGroup) {
        guard openFolderID == group.id, model.isGroup else { return }
        model.apply(group, reopen: false)
    }

    /// 选文件夹的面板（可多选），给文件夹分组的「＋」和扩展栏右键「添加文件夹…」用。
    static func chooseFolders() -> [URL] {
        let policy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        defer { NSApp.setActivationPolicy(policy) }

        let panel = NSOpenPanel()
        panel.message = tr("选择要放进文件夹分组的文件夹")
        panel.prompt = tr("添加")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        return panel.runModal() == .OK ? panel.urls : []
    }

    /// 小窗里的「＋」：选面板开着时不算点到外面。
    private func addFolders() {
        holdOpen = true
        defer { holdOpen = false; panel?.makeKey() }
        let urls = Self.chooseFolders()
        guard !urls.isEmpty else { return }
        groupActions?.add(urls)
    }

    private func selectTab(_ id: UUID) {
        guard model.select(id) else { return }
        groupActions?.select(id)
    }

    /// 顶部扩展栏给灵动提示让位时跟着一起挪。
    func shift(by dy: CGFloat) {
        guard isOpen, let panel, dy != 0 else { return }
        panel.animator().setFrame(panel.frame.offsetBy(dx: 0, dy: dy), display: false)
        host = host.offsetBy(dx: 0, dy: dy)
    }

    func close() {
        dismisser.stop()
        guard openFolderID != nil else { return }
        openFolderID = nil
        model.stop()
        if let ql = QLPreviewPanel.sharedPreviewPanelExists() ? QLPreviewPanel.shared() : nil,
           ql.isVisible {
            ql.orderOut(nil)
        }
        guard panel?.isVisible == true else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel?.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.openFolderID == nil else { return }
                self.panel?.orderOut(nil)
                self.panel?.alphaValue = 1
            }
        }
    }

    // MARK: 打开

    /// 小窗看的是一个文件夹，还是一个文件夹分组。
    private enum Source {
        case folder(URL)
        case group(DockGroup)
    }

    private func show(id: UUID, source: Source, anchor: CGPoint, edge: DockPosition, host: CGRect) {
        // 三种弹出窗口互斥：开这个就关另外两个。
        GroupWindow.shared.close()
        WidgetDetailWindow.shared.close()
        TooltipWindow.shared.hide()

        let panel = existingOrNew()
        self.host = host
        let anchor = anchor == .zero && host != .zero
            ? DetailPanelFit.fallbackAnchor(edge: edge, shelf: host) : anchor

        let screens = NSScreen.screens
        let visible: CGRect = DetailPanelFit.screenIndex(for: anchor, screens: screens.map(\.frame))
            .map { screens[$0].visibleFrame } ?? NSScreen.main?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let isGroup: Bool = if case .group = source { true } else { false }
        let fit = FolderBrowse.layout(visible: visible.size,
                                      extra: isGroup ? FolderGroups.tabRowHeight : 0)

        model.columns = fit.columns
        model.edge = edge
        switch source {
        case .folder(let folder):
            model.leaveGroup()
            model.open(root: folder)
        case .group(let group):
            model.apply(group, reopen: true)
        }
        model.session = UUID()
        hosting?.rootView = view()
        openFolderID = id

        let origin = Geometry.popupOrigin(edge: edge, anchor: anchor, size: fit.size, gap: 10)
        let placed = CGPoint(
            x: min(max(origin.x, visible.minX + 6), max(visible.minX, visible.maxX - fit.size.width - 6)),
            y: min(max(origin.y, visible.minY + 6), max(visible.minY, visible.maxY - fit.size.height - 6)))
        panel.setFrame(CGRect(origin: placed, size: fit.size), display: true)

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        dismisser.start()
    }

    private func view() -> FolderBrowserView {
        FolderBrowserView(model: model, actions: FolderBrowserActions(
            close: { [weak self] in self?.close() },
            openFile: { [weak self] url in
                FileActions.open(url)
                self?.close()
            },
            openInFinder: { [weak self] url in
                FileActions.openFolder(url)
                self?.close()
            },
            reveal: { [weak self] url in
                FileActions.reveal([url])
                self?.close()
            },
            quickLook: { [weak self] url in self?.quickLook(url) },
            trash: { [weak self] url in self?.trash(url) },
            selectTab: { [weak self] id in self?.selectTab(id) },
            addFolders: { [weak self] in self?.addFolders() },
            dropFolders: { [weak self] urls in self?.groupActions?.drop(urls) },
            removeTab: { [weak self] id in self?.groupActions?.remove(id) },
            moveTab: { [weak self] id, index in self?.groupActions?.move(id, index) }))
    }

    // MARK: 快速查看

    /// 空格或右键「快速查看」：再按一次（同一个文件）收起。
    func quickLook(_ url: URL) {
        let ql = QLPreviewPanel.shared()
        if ql?.isVisible == true, preview.url == url {
            ql?.orderOut(nil)
            return
        }
        preview.url = url
        ql?.dataSource = preview
        ql?.reloadData()
        ql?.makeKeyAndOrderFront(nil)
    }

    fileprivate func beginPreview(_ panel: QLPreviewPanel) {
        panel.dataSource = preview
    }

    fileprivate func endPreview(_ panel: QLPreviewPanel) {
        if panel.dataSource === preview { panel.dataSource = nil }
        // 关快速查看不连带收起小窗；焦点还给小窗，Esc、空格接着能用。
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isOpen, let window = self.panel else { return }
                window.makeKey()
            }
        }
    }

    /// 空格：不在打字时（或搜索框是空的时）预览选中的那一项。
    fileprivate func space(typing: Bool) -> Bool {
        if typing, !model.query.isEmpty { return false }
        guard let url = model.selection ?? model.visible.first?.url else { return typing ? false : true }
        quickLook(url)
        return true
    }

    // MARK: 移到废纸篓

    private func trash(_ url: URL) {
        holdOpen = true
        defer { holdOpen = false; panel?.makeKey() }
        let policy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        defer { NSApp.setActivationPolicy(policy) }

        let alert = NSAlert()
        alert.messageText = tr("把「\(url.lastPathComponent)」移到废纸篓？")
        alert.informativeText = tr("可以在废纸篓里找回。")
        alert.alertStyle = .warning
        alert.addButton(withTitle: tr("移到废纸篓"))
        alert.addButton(withTitle: tr("取消"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        NSWorkspace.shared.recycle([url]) { _, _ in
            Task { @MainActor in FolderBrowserWindow.shared.model.reload() }
        }
    }

    private func existingOrNew() -> FolderBrowserPanel {
        if let panel { return panel }
        let hosting = FirstMouseHostingView(rootView: view())
        hosting.sizingOptions = []

        let panel = FolderBrowserPanel(contentRect: .zero,
                                       styleMask: [.borderless, .nonactivatingPanel],
                                       backing: .buffered, defer: false)
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        // 搜索框要打字，所以能成为 key；扩展栏本身仍然不抢焦点。
        panel.becomesKeyOnlyIfNeeded = true
        panel.worksWhenModal = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        // 比扩展栏高一层，和分组窗口一样。
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 2)
        panel.onCancel = { [weak self] in self?.close() }
        panel.onEscape = { [weak self, weak panel] in
            guard let self, let panel, self.isOpen else { return false }
            return self.dismisser.escape(in: panel)
        }
        panel.onSpace = { [weak self] typing in self?.space(typing: typing) ?? false }

        self.panel = panel
        self.hosting = hosting
        return panel
    }
}

/// 小窗的窗口：能成为 key（搜索框打字），Esc（见 PopupPanel）、Command-W 关上，
/// 空格快速查看，并且是快速查看面板的控制者（系统的快速查看要在响应链上找一个）。
final class FolderBrowserPanel: PopupPanel {
    var onCancel: (() -> Void)?
    /// 空格：参数是现在是不是在搜索框里打字；返回 true 表示已处理。
    var onSpace: ((Bool) -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers == "w" {
            onCancel?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 49,
           event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
            let typing = firstResponder is NSTextView
            if onSpace?(typing) == true { return }
        }
        super.sendEvent(event)
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        guard let panel else { return }
        FolderBrowserWindow.shared.beginPreview(panel)
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        guard let panel else { return }
        FolderBrowserWindow.shared.endPreview(panel)
    }
}

/// 快速查看的数据源：一次一个文件。
final class QuickLookSource: NSObject, QLPreviewPanelDataSource, @unchecked Sendable {
    var url: URL?

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        url == nil ? 0 : 1
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        url.map { $0 as NSURL }
    }
}

// MARK: - 数据

/// 小窗正在看的那一层：读文件夹（后台）、监听变化、排序过滤后的结果。
@MainActor @Observable
final class FolderBrowserModel {
    enum Status: Equatable {
        case loading
        case ready
        /// 系统没给读这个文件夹的权限（文件与文件夹、完全磁盘访问）。
        case denied
        /// 文件夹不在了（被删、移动、外接盘拔了）。
        case missing
        /// 文件夹分组里还没有文件夹。
        case noFolders
    }

    /// 文件夹分组顶部的一个标签。
    struct Tab: Identifiable, Equatable {
        let id: UUID
        let title: String
        let url: URL
    }

    /// 开着的是不是文件夹分组；是的话顶部有一排标签。
    private(set) var isGroup = false
    private(set) var groupName = ""
    private(set) var tabs: [Tab] = []
    private(set) var selectedTab: UUID?

    private(set) var root: URL = FileManager.default.homeDirectoryForCurrentUser
    private(set) var current: URL = FileManager.default.homeDirectoryForCurrentUser
    private(set) var entries: [FolderEntry] = []
    private(set) var status: Status = .loading
    var query = ""
    /// 排序在几次打开之间保留（这次运行内）。
    var sort: FolderSort = .defaultValue
    /// 鼠标停着或右键过的那一项，空格预览它。
    var selection: URL?
    var columns = 6
    var edge: DockPosition = .bottom
    /// 每次打开换一个，视图据此把滚动位置、搜索框清掉。
    var session = UUID()

    @ObservationIgnored private var watcher: (any DispatchSourceFileSystemObject)?
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    /// 排好序、过滤过的，网格画这些。
    var visible: [FolderEntry] {
        FolderBrowse.filter(FolderBrowse.sorted(entries, by: sort), query: query)
    }

    var trail: [String] { FolderBrowse.trail(root: root, current: current) }
    var canGoBack: Bool { FolderBrowse.parent(of: current, root: root) != nil }

    func open(root: URL) {
        self.root = root
        go(to: root)
    }

    /// 普通文件夹格子：没有标签。
    func leaveGroup() {
        isGroup = false
        groupName = ""
        tabs = []
        selectedTab = nil
    }

    /// 按扩展栏上的组换上标签，打开该看的那个（上次看的，不在了就第一个）。
    /// - Parameter reopen: 刚打开小窗时重新读一遍；组变了时正在看的还在就不动。
    func apply(_ group: DockGroup, reopen: Bool) {
        isGroup = true
        groupName = group.name
        let folders: [(id: UUID, url: URL)] = group.items.compactMap { item in
            guard case .folder(let id, let ref, _) = item else { return nil }
            return (id, ref.resolve() ?? ref.url)
        }
        let titles = FolderGroups.tabTitles(for: folders.map(\.url), parenthesize: { tr("（\($0)）") })
        tabs = folders.indices.map { Tab(id: folders[$0].id, title: titles[$0], url: folders[$0].url) }
        let wanted = FolderGroups.selected(in: group)?.id
        guard let tab = tabs.first(where: { $0.id == wanted }) ?? tabs.first else {
            showNoFolders()
            return
        }
        if reopen || selectedTab != tab.id || root != tab.url || status == .noFolders {
            selectedTab = tab.id
            open(root: tab.url)
        }
    }

    /// 点了一个标签。返回 false 表示本来就在看它。
    @discardableResult
    func select(_ id: UUID) -> Bool {
        guard id != selectedTab, let tab = tabs.first(where: { $0.id == id }) else { return false }
        selectedTab = id
        open(root: tab.url)
        return true
    }

    private func showNoFolders() {
        stop()
        selectedTab = nil
        entries = []
        query = ""
        selection = nil
        status = .noFolders
    }

    func enter(_ folder: URL) { go(to: folder) }

    func back() {
        guard let parent = FolderBrowse.parent(of: current, root: root) else { return }
        go(to: parent)
    }

    func stop() {
        watcher?.cancel()
        watcher = nil
        pending?.cancel()
        pending = nil
        generation += 1
    }

    private func go(to folder: URL) {
        stop()
        current = folder
        entries = []
        query = ""
        selection = nil
        status = .loading
        reload()
        watch(folder)
    }

    /// 后台读一遍当前这一层，读完回主线程换上。
    func reload() {
        generation += 1
        let ticket = generation
        let folder = current
        Task.detached(priority: .userInitiated) {
            let outcome = Self.read(folder)
            await MainActor.run {
                guard ticket == self.generation, folder == self.current else { return }
                switch outcome {
                case .listed(let list):
                    self.entries = list
                    self.status = .ready
                    if let picked = self.selection, !list.contains(where: { $0.url == picked }) {
                        self.selection = nil
                    }
                case .denied:
                    self.entries = []
                    self.status = .denied
                case .missing:
                    self.entries = []
                    self.status = .missing
                }
            }
        }
    }

    /// 文件夹里有东西新增、删除、改名时重读。下载中的文件会连续触发，
    /// 所以等它安静 0.3 秒再读。
    private func watch(_ folder: URL) {
        let fd = Darwin.open(folder.path(percentEncoded: false), O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete, .rename, .extend, .link], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.changed() }
        }
        source.setCancelHandler { Darwin.close(fd) }
        source.resume()
        watcher = source
    }

    private func changed() {
        pending?.cancel()
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }

    /// 拖进小窗的文件移到当前这一层。同一块盘上是移动，跨盘是拷贝（和访达一样）；
    /// 已有同名的跳过。
    func receive(_ urls: [URL]) {
        let folder = current
        let todo = FolderBrowse.movable(urls, into: folder)
        guard !todo.isEmpty else { return }
        Task.detached(priority: .userInitiated) {
            let manager = FileManager.default
            let here = try? folder.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
            for url in todo {
                let target = folder.appendingPathComponent(url.lastPathComponent)
                guard !manager.fileExists(atPath: target.path(percentEncoded: false)) else { continue }
                let there = try? url.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
                let sameVolume: Bool = {
                    guard let here, let there else { return true }
                    return here.isEqual(there)
                }()
                if sameVolume {
                    try? manager.moveItem(at: url, to: target)
                } else {
                    try? manager.copyItem(at: url, to: target)
                }
            }
            await MainActor.run { self.reload() }
        }
    }

    enum Outcome: Sendable {
        case listed([FolderEntry])
        case denied
        case missing
    }

    nonisolated static func read(_ folder: URL) -> Outcome {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isHiddenKey,
                                      .contentModificationDateKey, .fileSizeKey,
                                      .localizedTypeDescriptionKey]
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
            var list: [FolderEntry] = []
            list.reserveCapacity(urls.count)
            for url in urls {
                let values = try? url.resourceValues(forKeys: Set(keys))
                let name = url.lastPathComponent
                if FolderBrowse.isHidden(name: name, hiddenFlag: values?.isHidden ?? false) { continue }
                let isFolder = (values?.isDirectory ?? false) && !(values?.isPackage ?? false)
                list.append(FolderEntry(url: url, name: name, isFolder: isFolder,
                                        modified: values?.contentModificationDate,
                                        size: isFolder ? nil : values?.fileSize.map(Int64.init),
                                        kind: values?.localizedTypeDescription ?? ""))
            }
            return .listed(list)
        } catch {
            if !FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)) {
                return .missing
            }
            return .denied
        }
    }
}

// MARK: - 界面

struct FolderBrowserActions {
    var close: () -> Void
    var openFile: (URL) -> Void
    var openInFinder: (URL) -> Void
    var reveal: (URL) -> Void
    var quickLook: (URL) -> Void
    var trash: (URL) -> Void
    // 文件夹分组的标签栏，普通文件夹格子用不到。
    var selectTab: (UUID) -> Void = { _ in }
    var addFolders: () -> Void = {}
    var dropFolders: ([URL]) -> Void = { _ in }
    var removeTab: (UUID) -> Void = { _ in }
    var moveTab: (UUID, Int) -> Void = { _, _ in }
}

/// 文件夹分组小窗里的操作，扩展栏按组的 id 去改。
struct FolderGroupActions {
    var select: (UUID) -> Void
    /// 「＋」选好的。
    var add: ([URL]) -> Void
    /// 从访达拖进来的（锁定扩展栏时不收）。
    var drop: ([URL]) -> Void
    var remove: (UUID) -> Void
    var move: (UUID, Int) -> Void
}

struct FolderBrowserView: View {
    @Bindable var model: FolderBrowserModel
    var actions: FolderBrowserActions

    @State private var dropTargeted = false
    @FocusState private var searching: Bool

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: FolderBrowse.headerHeight)
                .padding(.horizontal, FolderBrowse.padding)
            if model.isGroup {
                FolderGroupTabs(model: model, actions: actions)
                    .frame(height: FolderGroups.tabRowHeight)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { PanelGlassSurface(cornerRadius: 20, dark: false) }
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(dropTargeted ? Color.accentColor.opacity(0.8) : Color.panelStroke,
                               lineWidth: dropTargeted ? 2 : 0.5)
        }
        .onDrop(of: FileDropDelegate.types,
                delegate: FileDropDelegate(enabled: model.status == .ready || model.status == .noFolders,
                                           update: { over, _ in dropTargeted = over },
                                           receive: { urls in
                                               // 空的文件夹分组：拖进来的文件夹收进组里。
                                               if model.status == .noFolders {
                                                   actions.dropFolders(urls)
                                               } else {
                                                   model.receive(urls)
                                               }
                                           }))
    }

    // MARK: 顶栏

    private var header: some View {
        HStack(spacing: 8) {
            if model.canGoBack {
                Button { model.back() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.panelPrimary)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(.panelFill))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(tr("返回上一层"))
                .accessibilityLabel(tr("返回上一层"))
            }
            if model.status == .noFolders {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 17))
                    .foregroundStyle(.panelSecondary)
                    .frame(width: 22, height: 22)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: model.current.path(percentEncoded: false)))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 22, height: 22)
            }
            Text(model.status == .noFolders ? model.groupName : model.trail.joined(separator: " › "))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.panelPrimary)
                .lineLimit(1)
                .truncationMode(.head)
                .layoutPriority(1)
            if model.status == .ready {
                Text(countText)
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(.panelSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.panelFill))
                    .fixedSize()
            }
            Spacer(minLength: 8)
            if model.status != .noFolders {
                sortMenu
                searchField
                iconButton("arrow.up.forward.app", help: tr("在访达中打开")) {
                    actions.openInFinder(model.current)
                }
            }
            iconButton("xmark", help: tr("关闭")) { actions.close() }
        }
    }

    private var countText: String {
        let shown = model.visible.count
        return model.query.trimmingCharacters(in: .whitespaces).isEmpty
            ? "\(model.entries.count)" : "\(shown)/\(model.entries.count)"
    }

    private var sortMenu: some View {
        Menu {
            Picker(tr("排序方式"), selection: $model.sort) {
                ForEach(FolderSort.allCases, id: \.self) { sort in
                    Text(sort.label).tag(sort)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelSecondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.panelFill))
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(tr("排序：\(model.sort.label)"))
        .accessibilityLabel(tr("排序方式"))
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(.panelTertiary)
            TextField(tr("搜索"), text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.panelPrimary)
                .focused($searching)
            if !model.query.isEmpty {
                Button { model.query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.panelTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("清除搜索"))
            }
        }
        .padding(.horizontal, 9)
        .frame(width: 150, height: 28)
        .background(Capsule().fill(.panelFill))
        .overlay {
            Capsule().strokeBorder(searching ? Color.accentColor.opacity(0.6) : .clear, lineWidth: 1)
        }
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelSecondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.panelFill))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    // MARK: 内容

    @ViewBuilder private var content: some View {
        switch model.status {
        case .loading:
            ProgressView()
                .controlSize(.small)
        case .denied:
            emptyState(tr("没有权限读取这个文件夹"),
                       detail: tr("可以在「系统设置 › 隐私与安全性 › 文件与文件夹」里允许码头访问。"),
                       finder: true)
        case .missing:
            emptyState(tr("找不到这个文件夹"), detail: tr("它可能被移动、删除，或者所在的磁盘没有连接。"),
                       finder: false)
        case .noFolders:
            noFoldersState
        case .ready:
            let items = model.visible
            if model.entries.isEmpty {
                emptyState(tr("文件夹是空的"), detail: tr("把文件拖到这里，就会移进这个文件夹。"), finder: false)
            } else if items.isEmpty {
                emptyState(tr("没有名字含「\(model.query)」的项目"), detail: nil, finder: false)
            } else {
                grid(items)
            }
        }
    }

    private func grid(_ items: [FolderEntry]) -> some View {
        let columns = Array(repeating: GridItem(.fixed(FolderBrowse.cellWidth),
                                                spacing: FolderBrowse.spacing),
                            count: model.columns)
        return ScrollView(.vertical) {
            // 一分钟刷新一次「27 分钟前」。
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                LazyVGrid(columns: columns, spacing: FolderBrowse.spacing) {
                    ForEach(items) { item in
                        FolderBrowserCell(item: item, now: timeline.date,
                                          selected: model.selection == item.url,
                                          hover: { inside in
                                              if inside { model.selection = item.url }
                                          },
                                          open: { open(item) },
                                          menu: { menu(for: item) })
                    }
                }
                .padding(.horizontal, FolderBrowse.padding)
                .padding(.bottom, FolderBrowse.padding)
            }
        }
        .scrollIndicators(.automatic)
        .id(model.current)
    }

    private func open(_ item: FolderEntry) {
        if item.isFolder {
            model.enter(item.url)
        } else {
            actions.openFile(item.url)
        }
    }

    @ViewBuilder private func menu(for item: FolderEntry) -> some View {
        Button(tr("打开")) { open(item) }
        Button(tr("在访达中显示")) { actions.reveal(item.url) }
        Button(tr("拷贝")) { FileActions.copyFile(item.url) }
        Button(tr("快速查看")) { actions.quickLook(item.url) }
        Divider()
        Button(tr("移到废纸篓"), role: .destructive) { actions.trash(item.url) }
    }

    /// 空的文件夹分组：说一句怎么加，给一个「添加文件夹」。
    private var noFoldersState: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.panelTertiary)
            Text(tr("这个分组还没有文件夹"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.panelPrimary)
            Text(tr("点「添加文件夹」选择，或从访达把文件夹拖到这里。"))
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 360)
            Button(action: actions.addFolders) {
                Text(tr("添加文件夹"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelOnPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(.panelPrimary))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(FolderBrowse.padding)
    }

    private func emptyState(_ title: String, detail: String?, finder: Bool) -> some View {
        VStack(spacing: 8) {
            Image(systemName: finder ? "lock" : "folder")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.panelTertiary)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.panelPrimary)
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 360)
            }
            if finder {
                Button { actions.openInFinder(model.current) } label: {
                    Text(tr("在访达中打开"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.panelOnPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(.panelPrimary))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .padding(FolderBrowse.padding)
    }
}

/// 网格里的一格：大图标（缩略图，文件夹用系统图标）、名字、相对时间。
private struct FolderBrowserCell<MenuContent: View>: View {
    var item: FolderEntry
    var now: Date
    var selected: Bool
    var hover: (Bool) -> Void
    var open: () -> Void
    @ViewBuilder var menu: () -> MenuContent

    @State private var hovering = false

    private let iconSide: CGFloat = 58

    var body: some View {
        VStack(spacing: 4) {
            icon
                .frame(width: iconSide, height: iconSide)
                .padding(.bottom, 2)
            Text(item.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.panelPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(item.modified.map {
                FolderBrowse.relativeText(for: $0, now: now, locale: L10n.interfaceLocale)
            } ?? " ")
                .font(.system(size: 13))
                .foregroundStyle(.panelTertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 7)
        .frame(width: FolderBrowse.cellWidth, height: FolderBrowse.cellHeight)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(hovering || selected ? Color.panelSelected : Color.panelFill)
        }
        .contentShape(.rect(cornerRadius: 12))
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.12)) { hovering = inside }
            hover(inside)
        }
        .onTapGesture(perform: open)
        .onDrag { FileActions.dragProvider(item.url) }
        .contextMenu { menu() }
        .help(item.name)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.name)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private var icon: some View {
        if item.isFolder {
            Image(nsImage: Thumbnails.shared.icon(for: item.url))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else if let thumb = Thumbnails.shared.image(for: item.url, pixels: 128) {
            Image(nsImage: thumb)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .clipShape(.rect(cornerRadius: 4))
        } else {
            Image(nsImage: Thumbnails.shared.icon(for: item.url))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        }
    }
}

// MARK: - 文件夹分组的标签栏

/// 文件夹分组小窗顶栏下面的一排文件夹标签：点了切换，最后是「＋」；
/// 拖动标签重排，右键左移、右移、在访达中显示、从分组中移除；
/// 从访达把文件夹拖到这一排上就收进组里。放不下时横向滚动。
private struct FolderGroupTabs: View {
    var model: FolderBrowserModel
    var actions: FolderBrowserActions

    /// 正在拖的标签，放下时按它挪。
    @State private var dragging: UUID?
    @State private var dropOver: UUID?
    @State private var folderDropTargeted = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(Array(model.tabs.enumerated()), id: \.element.id) { index, tab in
                        chip(tab, index: index)
                            .id(tab.id)
                    }
                    addButton
                }
                .padding(.horizontal, FolderBrowse.padding)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.never)
            .onAppear {
                if let id = model.selectedTab { proxy.scrollTo(id, anchor: .center) }
            }
            .onChange(of: model.selectedTab) { _, id in
                guard let id else { return }
                withAnimation(.snappy(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(folderDropTargeted ? Color.accentColor.opacity(0.8) : .clear, lineWidth: 1.5)
                .padding(.horizontal, FolderBrowse.padding - 4)
        }
        .onDrop(of: FileDropDelegate.types,
                delegate: FileDropDelegate(enabled: true,
                                           update: { over, _ in folderDropTargeted = over },
                                           receive: { urls in actions.dropFolders(urls) }))
    }

    private func chip(_ tab: FolderBrowserModel.Tab, index: Int) -> some View {
        let selected = model.selectedTab == tab.id
        return Button { actions.selectTab(tab.id) } label: {
            HStack(spacing: 5) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: tab.url.path(percentEncoded: false)))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
                Text(tab.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Color.panelPrimary : Color.panelSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 160)
                    .fixedSize()
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background {
                Capsule()
                    .fill(selected ? Color.panelRaised : (dropOver == tab.id ? Color.panelSelected : Color.panelFill))
                    .panelLift(selected)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(tab.url.path(percentEncoded: false))
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .onDrag {
            dragging = tab.id
            return NSItemProvider(object: tab.id.uuidString as NSString)
        }
        .onDrop(of: [.plainText], isTargeted: Binding(
            get: { dropOver == tab.id },
            set: { over in dropOver = over ? tab.id : (dropOver == tab.id ? nil : dropOver) })
        ) { _ in
            guard let moving = dragging, moving != tab.id else { return false }
            dragging = nil
            withAnimation(.snappy(duration: 0.2)) { actions.moveTab(moving, index) }
            return true
        }
        .contextMenu {
            Button(tr("在访达中显示")) { actions.reveal(tab.url) }
            Divider()
            Button(tr("向左移")) { actions.moveTab(tab.id, index - 1) }
                .disabled(index == 0)
            Button(tr("向右移")) { actions.moveTab(tab.id, index + 1) }
                .disabled(index >= model.tabs.count - 1)
            Divider()
            Button(tr("从分组中移除"), role: .destructive) { actions.removeTab(tab.id) }
        }
    }

    private var addButton: some View {
        Button(action: actions.addFolders) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelSecondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(.panelFill))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(tr("添加文件夹"))
        .accessibilityLabel(tr("添加文件夹"))
    }
}
