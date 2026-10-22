import AppKit
import Observation
import SwiftUI

/// ⌥Tab 按窗口切换（免费功能，设置 ▸ 快捷键 ▸ 窗口切换）。
///
/// - 按住 ⌥ 按 Tab：液态玻璃面板出现在鼠标所在屏幕正中，列出所有窗口（最近使用的在前），
///   选中第二个。Tab / ⇧Tab、方向键前后移，松开 ⌥ 切过去；Esc 取消；点卡片直接切。
///   按得快（松开 ⌥ 时面板还没出来）直接切到上一个窗口，不弹面板。
/// - 弹出后直接打字搜索 App 名和窗口标题（也认拼音首字母和全拼），开始搜索后松开 ⌥
///   不切换，回车切、Esc 取消。按 / 只进入搜索。
/// - 没开始搜索时 W 关窗口、M 最小化、Q 退出 App，列表原地刷新。
/// - 没屏幕录制权限时卡片画 App 大图标，不弹授权；没辅助功能权限时不注册快捷键，设置里提示。
///
/// 平时只注册一个 Carbon 快捷键；按键监听、读窗口、截图都只在弹出时发生。
/// 排序、过滤、分组、搜索、选中移动、按键含义和布局在 Core（`WindowSwitcher`、
/// `WindowSwitcherSearch`、`WindowSwitcherLayout`）。
@MainActor
final class WindowSwitcherController {
    static let shared = WindowSwitcherController()

    private enum Phase { case idle, loading, open }

    private var settings = WindowSwitcherSettings()
    private var phase: Phase = .idle
    private var trigger = WindowSwitcherSettings.defaultHotKey
    let model = WindowSwitcherModel()

    private var panel: WindowSwitcherPanel?
    private var hosting: FirstMouseHostingView<WindowSwitcherView>?

    /// 这次打开读到的窗口，键是 `Entry.id`。
    private var items: [Int: WindowCatalog.Item] = [:]
    /// 还在读窗口时按的键：前后移了几步、松开了 ⌥、按了 Esc。
    private var pendingSteps = 0
    private var pendingCommit = false
    private var pendingCancel = false

    /// 上次用切换器从哪个窗口切到哪个窗口（`Entry.key`），连按两次 ⌥Tab 回到原处用。
    private var lastSwitch: (from: String, to: String)?

    private var loadTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var idleTimer: Timer?

    /// 缩略图缓存，键是 `Entry.key`。弹出时先用旧图，后台再截新的。
    private var shots: [String: (image: CGImage, at: Date)] = [:]
    private var icons: [pid_t: NSImage] = [:]

    private init() {
        WindowSwitcherHotKey.shared.onPress = { WindowSwitcherController.shared.pressed() }
        SwitcherEventTap.shared.handler = { type, event in
            WindowSwitcherController.shared.handle(type, event)
        }
        // 码头回到前台（多半是从系统设置授权回来）时再看一眼辅助功能权限。只是一条通知。
        _ = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { WindowSwitcherController.shared.refresh() }
        }
    }

    // MARK: 设置

    func apply(_ settings: WindowSwitcherSettings) {
        self.settings = settings
        refresh()
    }

    /// 辅助功能权限可能刚在系统设置里打开或关掉：码头回到前台、设置页出现时再看一眼。
    func refresh() {
        let combo = AXIsProcessTrusted() ? settings.registrableHotKey : nil
        WindowSwitcherHotKey.shared.apply(combo)
        if combo != nil {
            AppRecency.shared.start()
        } else {
            AppRecency.shared.stop()
            if phase != .idle { finish() }
        }
    }

    // MARK: 弹出

    private func pressed() {
        guard phase == .idle else {
            move(by: 1)
            return
        }
        guard AXIsProcessTrusted(), let combo = settings.registrableHotKey else {
            refresh()
            return
        }
        trigger = combo
        // 弹出期间快捷键交给事件监听，Carbon 那边先放开，免得 Tab 被收两次。
        WindowSwitcherHotKey.shared.pause()
        guard SwitcherEventTap.shared.start() else {
            WindowSwitcherHotKey.shared.unpause()
            return
        }
        phase = .loading
        pendingSteps = 0
        pendingCommit = WindowSwitcher.released(trigger: combo.modifiers,
                                                current: SwitcherEventTap.currentModifiers)
        pendingCancel = false
        model.reset(trigger: combo)
        loadTask = Task { @MainActor in
            let found = await WindowCatalog.snapshot()
            WindowSwitcherController.shared.loaded(found)
        }
    }

    private func loaded(_ found: [WindowCatalog.Item]) {
        guard phase == .loading else { return }
        items = Dictionary(found.map { ($0.entry.id, $0) }, uniquingKeysWith: { a, _ in a })
        let entries = found.map(\.entry)
        let front = entries.first { $0.zOrder == 0 }
        var previous: String?
        if let last = lastSwitch, front?.key == last.to { previous = last.from }
        let arranged = WindowSwitcher.arrange(entries, settings: settings, previous: previous)
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let firstIsFront = arranged.first.map { $0.zOrder == 0 && $0.pid == frontPID } ?? false
        model.frontKey = firstIsFront ? arranged.first?.key : nil
        model.setEntries(arranged)
        let start = WindowSwitcher.initialSelection(count: arranged.count, firstIsFront: firstIsFront)
        model.selection = WindowSwitcher.step(start, by: pendingSteps, count: arranged.count)
        loadIcons()

        if pendingCancel { finish(); return }
        if pendingCommit {
            // 按得快：面板还没出来就松开了 ⌥，直接切。
            commit()
            return
        }
        phase = .open
        show()
        loadShots()
        touch()
    }

    private func show() {
        let panel = existingOrNew()
        place()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    /// 按卡片数算布局，放在鼠标所在屏幕的可见范围正中。
    private func place() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        model.backingScale = screen?.backingScaleFactor ?? 2
        model.layout = WindowSwitcherLayout.layout(count: model.visible.count, visible: visible.size)
        let size = model.layout.panelSize
        let origin = WindowSwitcherLayout.origin(size: size, visible: visible)
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
    }

    /// 收起，什么也不切。
    private func finish() {
        loadTask?.cancel()
        loadTask = nil
        captureTask?.cancel()
        captureTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        idleTimer?.invalidate()
        idleTimer = nil
        SwitcherEventTap.shared.stop()
        WindowSwitcherHotKey.shared.unpause()
        phase = .idle
        items = [:]
        model.session = UUID()
        if let panel, panel.isVisible {
            panel.orderOut(nil)
        }
        // 留着缩略图缓存，卡片上的图放掉。
        model.shots = [:]
    }

    /// 切到选中的窗口。
    private func commit() {
        guard let entry = model.selected, let item = items[entry.id] else {
            finish()
            return
        }
        let from = model.frontKey
        finish()
        guard let app = NSRunningApplication(processIdentifier: entry.pid), !app.isTerminated else { return }
        AppWindows.bringForward(item.element, minimized: entry.minimized, app: app)
        if let from, from != entry.key { lastSwitch = (from, entry.key) }
    }

    func pick(_ id: Int) {
        guard phase == .open, let index = model.visible.firstIndex(where: { $0.id == id }) else { return }
        model.selection = index
        commit()
    }

    // MARK: 按键

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        guard phase != .idle else { return false }
        switch type {
        case .flagsChanged:
            if !model.searching, WindowSwitcher.released(trigger: trigger.modifiers,
                                                         current: SwitcherEventTap.modifiers(event.flags)) {
                if phase == .loading { pendingCommit = true } else { commit() }
            }
            return false

        case .keyDown:
            let code = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
            let characters = NSEvent(cgEvent: event)?.charactersIgnoringModifiers ?? ""
            let action = WindowSwitcher.action(keyCode: code, characters: characters,
                                               modifiers: SwitcherEventTap.modifiers(event.flags),
                                               triggerKey: trigger.keyCode, searching: model.searching)
            if phase == .loading {
                switch action {
                case .next, .right: pendingSteps += 1
                case .previous, .left: pendingSteps -= 1
                case .cancel: pendingCancel = true
                case .commit: pendingCommit = true
                case .passThrough:
                    pendingCancel = true
                    return false
                default: break
                }
                return true
            }
            touch()
            perform(action)
            return action != .passThrough

        case .keyUp:
            return true

        case .leftMouseDown, .rightMouseDown:
            // 点到面板外面：收起，点击照常交给下面的窗口。
            if let panel, phase == .open, !panel.frame.contains(NSEvent.mouseLocation) { finish() }
            return false

        default:
            return false
        }
    }

    private func perform(_ action: WindowSwitcher.KeyAction) {
        let count = model.visible.count
        switch action {
        case .next, .right: move(by: 1)
        case .previous, .left: move(by: -1)
        case .down:
            model.selection = WindowSwitcher.vertical(model.selection, rows: 1,
                                                      columns: model.layout.columns, count: count)
        case .up:
            model.selection = WindowSwitcher.vertical(model.selection, rows: -1,
                                                      columns: model.layout.columns, count: count)
        case .commit: commit()
        case .cancel: finish()
        case .closeWindow:
            guard let item = selectedItem else { return }
            AXWindowReader.pressClose(item.element)
            reloadSoon(after: 0.35)
        case .minimizeWindow:
            guard let item = selectedItem else { return }
            AXWindowReader.minimize(item.element)
            reloadSoon(after: 0.35)
        case .quitApp:
            guard let entry = model.selected,
                  let app = NSRunningApplication(processIdentifier: entry.pid) else { return }
            app.terminate()
            reloadSoon(after: 0.6)
        case .startSearch:
            model.searching = true
        case .type(let text):
            model.searching = true
            model.setQuery(model.query + text)
            relayout()
        case .backspace:
            model.setQuery(String(model.query.dropLast()))
            relayout()
        case .ignore, .passThrough:
            if action == .passThrough { finish() }
        }
    }

    private func move(by delta: Int) {
        if phase == .loading {
            pendingSteps += delta
            return
        }
        model.selection = WindowSwitcher.step(model.selection, by: delta, count: model.visible.count)
    }

    private var selectedItem: WindowCatalog.Item? {
        model.selected.flatMap { items[$0.id] }
    }

    /// 搜索改了张数：重新算布局，面板保持在原来那块屏幕正中。
    private func relayout() {
        guard phase == .open else { return }
        place()
    }

    /// 关窗口、最小化、退出之后给 App 一点时间，再原地重读一遍，选中留在原来的位置。
    private func reloadSoon(after seconds: Double) {
        refreshTask?.cancel()
        let session = model.session
        refreshTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            let me = WindowSwitcherController.shared
            guard !Task.isCancelled, me.phase == .open, me.model.session == session else { return }
            let found = await WindowCatalog.snapshot()
            guard !Task.isCancelled, me.phase == .open, me.model.session == session else { return }
            me.reloaded(found)
        }
    }

    private func reloaded(_ found: [WindowCatalog.Item]) {
        let keep = model.selection
        items = Dictionary(found.map { ($0.entry.id, $0) }, uniquingKeysWith: { a, _ in a })
        // 刷新时不再挪动先后：已有的窗口按原来的位置，新出现的排后面。
        let old = model.all.map(\.key)
        let arranged = WindowSwitcher.arrange(found.map(\.entry), settings: settings)
        let stable = arranged.sorted { a, b in
            (old.firstIndex(of: a.key) ?? Int.max) < (old.firstIndex(of: b.key) ?? Int.max)
        }
        model.setEntries(stable)
        model.selection = model.visible.isEmpty ? 0 : min(keep, model.visible.count - 1)
        loadIcons()
        place()
        loadShots()
    }

    /// 开着超过 30 秒没碰任何键就收起，免得事件监听一直挂着。
    private func touch() {
        idleTimer?.invalidate()
        let timer = Timer(timeInterval: 30, repeats: false) { _ in
            MainActor.assumeIsolated {
                let me = WindowSwitcherController.shared
                if me.phase != .idle { me.finish() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    // MARK: 图标和缩略图

    private func loadIcons() {
        for entry in model.all where icons[entry.pid] == nil {
            icons[entry.pid] = NSRunningApplication(processIdentifier: entry.pid)?.icon
        }
        let alive = Set(model.all.map(\.pid))
        icons = icons.filter { alive.contains($0.key) }
        model.icons = icons
    }

    /// 先用缓存的图，再在后台截：选中的先截，然后按列表顺序。最小化、隐藏的不截（截不到
    /// 内容），画 App 大图标。
    private func loadShots() {
        captureTask?.cancel()
        model.canCapture = WindowPreviewSource.canCapture
        guard model.canCapture else { return }
        let keys = Set(model.all.map(\.key))
        shots = shots.filter { keys.contains($0.key) }
        for entry in model.all {
            if let hit = shots[entry.key] { model.shots[entry.id] = hit.image }
        }
        let now = Date.now
        var queue = model.visible
        if let selected = model.selected, let i = queue.firstIndex(of: selected) {
            queue.remove(at: i)
            queue.insert(selected, at: 0)
        }
        let rest = model.all.filter { !queue.contains($0) }
        queue += rest
        let box = WindowSwitcherLayout.thumbnailSize(scale: 1)
        let scale = model.backingScale
        let requests: [WindowShotRequest] = queue.compactMap { entry in
            guard !entry.dimmed, let item = items[entry.id] else { return nil }
            if let hit = shots[entry.key], now.timeIntervalSince(hit.at) < 1.5 { return nil }
            return WindowShotRequest(key: entry.id, pid: entry.pid, title: entry.title, frame: item.frame,
                                     pixelSize: WindowSwitcherLayout.captureSize(window: item.frame.size,
                                                                                 box: box, scale: scale),
                                     windowID: item.windowID)
        }
        guard !requests.isEmpty else { return }
        let session = model.session
        let keyFor = Dictionary(model.all.map { ($0.id, $0.key) }, uniquingKeysWith: { a, _ in a })
        captureTask = Task { @MainActor in
            await WindowShots.capture(requests) { id, shot in
                await MainActor.run {
                    let me = WindowSwitcherController.shared
                    guard me.model.session == session, me.phase == .open else { return }
                    me.model.shots[id] = shot.image
                    if let key = keyFor[id] { me.shots[key] = (shot.image, Date.now) }
                }
            }
        }
    }

    // MARK: 窗口

    private func existingOrNew() -> WindowSwitcherPanel {
        if let panel { return panel }
        let view = WindowSwitcherView(model: model, pick: { WindowSwitcherController.shared.pick($0) })
        let hosting = FirstMouseHostingView(rootView: view)
        hosting.sizingOptions = []
        let panel = WindowSwitcherPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                        backing: .buffered, defer: false)
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.worksWhenModal = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.level = .popUpMenu
        panel.setAccessibilityLabel(tr("窗口切换"))
        self.panel = panel
        self.hosting = hosting
        return panel
    }
}

/// 切换器的窗口：不抢焦点、不成为 key（按键由事件监听收），只接点击和悬停。
final class WindowSwitcherPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - 数据

@MainActor @Observable
final class WindowSwitcherModel {
    /// 排好的全部窗口。
    private(set) var all: [WindowSwitcher.Entry] = []
    /// 搜索后剩下的，按匹配程度排。
    private(set) var visible: [WindowSwitcher.Entry] = []
    var selection = 0
    private(set) var query = ""
    var searching = false
    var shots: [Int: CGImage] = [:]
    var icons: [pid_t: NSImage] = [:]
    var canCapture = true
    var layout = WindowSwitcherLayout.layout(count: 1, visible: CGSize(width: 1440, height: 900))
    var backingScale: CGFloat = 2
    /// 弹出时最前面那个窗口。
    var frontKey: String?
    /// 快捷键的修饰键符号，底部写「松开 ⌥」。
    var holdSymbols = "⌥"
    var session = UUID()

    @ObservationIgnored private var indexes: [WindowSwitcherSearch.Index]?

    var selected: WindowSwitcher.Entry? {
        visible.indices.contains(selection) ? visible[selection] : nil
    }

    func reset(trigger: KeyCombo) {
        all = []
        visible = []
        selection = 0
        query = ""
        searching = false
        indexes = nil
        shots = [:]
        frontKey = nil
        let symbols = KeyCombo(keyCode: trigger.keyCode,
                               modifiers: trigger.modifiers & ~KeyCombo.Modifier.shift).modifierSymbols
        holdSymbols = symbols.isEmpty ? "⌥" : symbols
        session = UUID()
    }

    func setEntries(_ entries: [WindowSwitcher.Entry]) {
        all = entries
        indexes = nil
        applyQuery()
    }

    func setQuery(_ text: String) {
        query = text
        applyQuery()
        selection = 0
    }

    private func applyQuery() {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            visible = all
            return
        }
        // 拼音只在第一次打字时算。
        if indexes == nil {
            indexes = all.map { WindowSwitcherSearch.Index(appName: $0.appName, title: $0.title) }
        }
        visible = WindowSwitcherSearch.filter(query, indexes: indexes ?? []).map { all[$0] }
    }
}
