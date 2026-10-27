import AppKit
import Observation
import SwiftUI

/// 桌面卡片界面上的临时状态：排列模式、正在拖哪张、网格上的空位。
@MainActor @Observable
final class DesktopPinUI {
    /// 排列桌面卡片：顶上横条 + 完成，卡片左上角「−」，整张卡片能拖。
    var editing = false
    /// 正在拖的那张（拖的时候不露操作条）。
    var draggingPin: UUID?
    /// 码头 Pro 解锁了没有（没解锁只显示第一张，大号按中号画）。
    var unlocked = ProAccess.isUnlocked
    /// 网格窗口里的橙色虚线空位（网格窗口坐标，左上原点）。
    var slot: CGRect?
    var slotSize: DesktopPinSize = .medium
    /// 从扩展栏拖出来的新卡片：空位上写「松手钉在这里」。
    var slotIsNew = false
}

/// 钉在桌面：每张卡片一个窗口，层级沿用扩展栏「置于窗口之后」的那一层（桌面图标之上一层），
/// 在所有窗口之后。窗口、拖动、网格、排列模式、被窗口盖住时自动隐藏、键盘交还都在这里；
/// 位置和上限的计算在 Core 的 `DesktopPinLayout`、`DesktopPinGate`。
///
/// 「显示桌面时浮到前面」这一版不做：系统没有公开的「正在显示桌面」通知，靠猜手势和触发角
/// 容易误判，先不冒这个险。
@MainActor
final class DesktopPinController {
    static let shared = DesktopPinController()

    weak var app: AppState?
    let ui = DesktopPinUI()

    private var cards: [UUID: KeyablePanel] = [:]
    private var observers: [NSObjectProtocol] = []
    private var gridPanel: NSPanel?
    private var gridScreen: NSScreen?
    private var arrangeBar: NSPanel?
    private var coverTimer: Timer?
    private var covered: Set<UUID> = []

    private struct MoveSession {
        var pinID: UUID
        var startMouse: CGPoint
        var startOrigin: CGPoint
        var size: CGSize
    }
    private var move: MoveSession?
    /// 从扩展栏拖出来、还没松手的那张。
    private var incoming: (widget: UUID, size: DesktopPinSize)?
    /// 拖动中盯着松开鼠标。SwiftUI 的拖动手势在发起它的视图被移走时（操作条收起、自动隐藏的
    /// 扩展栏滑走）直接作废、不调 onEnded，网格和橙色虚线空位就一直留在桌面上、卡片也停在
    /// 半路。这里另外看一眼鼠标松开，手势没收尾就替它收尾。
    private var releaseMonitors: [Any] = []

    /// 和扩展栏「置于窗口之后」同一层：桌面图标之上一层，在所有普通窗口之后。
    static var desktopLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }

    private init() {}

    private var settings: DesktopPinSettings { app?.state.desktopPins ?? DesktopPinSettings() }

    // MARK: 启动和同步

    func start(app: AppState) {
        self.app = app
        guard observers.isEmpty else { return apply(app.state.desktopPins) }
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                            object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { DesktopPinController.shared.reapply() }
        })
        // 试用开始或结束、激活码生效：显示几张、大号能不能画跟着变。
        observers.append(center.addObserver(forName: UserDefaults.didChangeNotification,
                                            object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                let controller = DesktopPinController.shared
                if controller.ui.unlocked != ProAccess.isUnlocked { controller.reapply() }
            }
        })
        apply(app.state.desktopPins)
    }

    private func reapply() {
        guard let app else { return }
        apply(app.state.desktopPins)
    }

    /// 设置或已钉的卡片变了（AppState 每次改 `desktopPins` 都调）。
    func apply(_ incoming: DesktopPinSettings) {
        guard let app else { return }
        ui.unlocked = ProAccess.isUnlocked
        // 小组件删掉了、便签那张撕掉了：卡片跟着取消钉。写回后照清理过的接着摆
        // （写回可能再进来一次，摆窗口本身重复做也没关系）。
        var settings = incoming
        let widgets = Set(app.allWidgets.map(\.id))
        if settings.removeOrphans(widgets: widgets, sheetExists: { widget, sheet in
            app.widgetAnywhere(widget).map { StickyStack.pile($0.config).index(ofSheet: sheet) != nil } ?? false
        }) {
            app.state.desktopPins = settings
        }
        let shown = settings.enabled ? DesktopPinGate.shown(settings.pins, unlocked: ui.unlocked) : []
        let wanted = Set(shown.map(\.id))
        for (id, panel) in cards where !wanted.contains(id) {
            panel.orderOut(nil)
            cards[id] = nil
            covered.remove(id)
        }
        let screens = desktopScreens()
        for pin in shown {
            let panel = cards[pin.id] ?? makePanel(pin.id)
            configure(panel, settings)
            let size = drawnSize(pin)
            if move?.pinID != pin.id, let frame = DesktopPinLayout.frame(for: pin, size: size, screens: screens),
               panel.frame != frame {
                panel.setFrame(frame, display: panel.isVisible)
            }
            if !panel.isVisible { panel.orderFrontRegardless() }
        }
        if shown.isEmpty, ui.editing { setEditing(false) }
        watchCovering(settings.covered == .autoHide && !shown.isEmpty)
    }

    private func makePanel(_ id: UUID) -> KeyablePanel {
        guard let app else { fatalError("DesktopPinController used before start") }
        let hosting = FirstMouseHostingView(rootView: DesktopCardHost(pinID: id, app: app, ui: ui))
        hosting.autoresizingMask = [.width, .height]
        // 窗口大小只由这里定（尺寸档 + 网格位置），不让 SwiftUI 内容的大小反过来约束窗口，
        // 免得改尺寸、拖动时窗口和内容各是各的大小。
        hosting.sizingOptions = []
        let panel = KeyablePanel(contentRect: CGRect(x: 0, y: 0, width: 160, height: 160),
                                     styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: false)
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        // 点卡片上任何地方都拿键盘（输入框、便签直接能写），但不激活码头。
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.level = Self.desktopLevel
        // Esc（和 ⌘W）把键盘交还给原来的 App，不收卡片。
        panel.onCancel = { [weak self] in self?.releaseFocus() }
        cards[id] = panel
        return panel
    }

    /// 所有桌面 / 仅当前桌面、外观。不带 fullScreenAuxiliary：全屏 App 的桌面上不出现。
    private func configure(_ panel: KeyablePanel, _ settings: DesktopPinSettings) {
        let behavior: NSWindow.CollectionBehavior = settings.spaces == .all
            ? [.canJoinAllSpaces, .stationary, .ignoresCycle]
            : [.stationary, .ignoresCycle]
        if panel.collectionBehavior != behavior { panel.collectionBehavior = behavior }
        let appearance: NSAppearance? = switch settings.appearance {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
        if panel.appearance?.name != appearance?.name { panel.appearance = appearance }
        if panel.level != Self.desktopLevel { panel.level = Self.desktopLevel }
    }

    private func desktopScreens() -> [DesktopScreen] {
        NSScreen.screens.map { DesktopScreen(id: $0.displayID ?? 0, visible: $0.visibleFrame) }
    }

    private func nsScreen(for id: UInt32) -> NSScreen? {
        NSScreen.screens.first { $0.displayID == id } ?? NSScreen.screens.first
    }

    /// 某块屏幕上其余卡片占着的地方。
    private func occupied(on screen: DesktopScreen, except: UUID?) -> [CGRect] {
        let screens = desktopScreens()
        return DesktopPinGate.shown(settings.pins, unlocked: ui.unlocked).compactMap { pin in
            guard pin.id != except, DesktopPinLayout.screen(for: pin, screens: screens)?.id == screen.id else { return nil }
            return DesktopPinLayout.frame(for: pin, size: drawnSize(pin),
                                          screens: screens)
        }
    }

    // MARK: 能不能钉

    func mode(for kind: WidgetKind) -> DesktopPinSupport.Mode {
        DesktopPinSupport.mode(kind, hasDetail: WidgetDetail.exists(for: kind),
                               panelWidth: Double(WidgetDetail.width(kind)))
    }

    func offers(_ widget: WidgetInstance) -> Bool { mode(for: widget.kind) != .none }

    /// 这张卡片能选哪几档：小号要放大的扩展栏卡片在 160×160 里不缩小就放得下
    /// （便签、时钟、算的小号是专门的布局，总能放下）。
    func sizes(for widget: WidgetInstance) -> [DesktopPinSize] {
        let mode = mode(for: widget.kind)
        let special: Set<WidgetKind> = [.notes, .clock, .calculator]
        let smallFits = special.contains(widget.kind) || DesktopCardLayouts.kinds.contains(widget.kind)
            || DesktopTileFit.fit(widget, box: DesktopPinSize.small.size).readable
        return DesktopPinSupport.sizes(mode, smallFits: smallFits)
    }

    /// 卡片画多大：没解锁时大号按中号，这张卡片不提供的那档按中号（见 `DesktopPinSupport.drawnSize`）。
    func drawnSize(_ pin: DesktopPin) -> DesktopPinSize {
        let offered = app?.widgetAnywhere(pin.widgetID).map { sizes(for: $0) } ?? []
        return DesktopPinSupport.drawnSize(pin.size, unlocked: ui.unlocked, offered: offered)
    }

    func isPinned(_ widget: WidgetInstance) -> Bool { settings.hasPins(widget: widget.id) }

    /// 便签某一张的标识（还没钉过就是空）。
    private func sheetID(_ widget: WidgetInstance, index: Int) -> String? {
        let pile = StickyStack.pile(widget.config)
        guard pile.sheets.indices.contains(index) else { return nil }
        let id = pile.sheets[index].id
        return id.isEmpty ? nil : id
    }

    func isPinned(_ widget: WidgetInstance, sheet index: Int) -> Bool {
        guard let id = sheetID(widget, index: index) else { return false }
        return settings.pin(widget: widget.id, sheet: id) != nil
    }

    // MARK: 钉上、改尺寸、取消钉

    /// 钉一张：右键菜单、便签面板「把这张钉在桌面」、从扩展栏拖出来松手。
    /// `at` 给了就放在离它最近的空位（卡片中心对着它），不给就放第一个空位。
    /// 便签按 `sheet` 那一张（默认最上面那张），先给那张纸一个标识。
    /// 没解锁时第二张起或大号弹付费墙。同一个已经钉着就只改尺寸。
    func pin(_ widget: WidgetInstance, sheet index: Int? = nil, size: DesktopPinSize, at point: CGPoint? = nil) {
        guard let app else { return }
        let mode = mode(for: widget.kind)
        guard mode != .none else { return }
        let size = sizes(for: widget).contains(size) ? size : DesktopPinSupport.defaultSize(mode)
        let unlocked = ProAccess.isUnlocked

        var sheet: String?
        if widget.kind == .notes {
            let latest = WidgetWriter.current(widget.id) ?? widget
            let pile = StickyStack.pile(latest.config)
            let target = index ?? pile.page
            // 已经有标识的直接用；钉之前先看能不能钉，免得弹了付费墙还改了便签。
            if let existing = sheetID(latest, index: target) {
                sheet = existing
            } else {
                let verdict = DesktopPinGate.canPin(existing: settings.pins.count, size: size, unlocked: unlocked)
                guard verdict == .allowed else { return PaywallWindow.shared.show() }
                guard let named = pile.identifying(at: target, newID: UUID().uuidString) else { return }
                WidgetWriter.write(latest) { StickyStack.store(named.pile, in: &$0) }
                sheet = named.id
            }
        }

        if let existing = settings.pin(widget: widget.id, sheet: sheet) {
            if !settings.enabled { app.state.desktopPins.enabled = true }
            return resize(existing.id, to: size)
        }
        switch DesktopPinGate.canPin(existing: settings.pins.count, size: size, unlocked: unlocked) {
        case .allowed: break
        case .needsProForCount, .needsProForSize: return PaywallWindow.shared.show()
        }

        let screens = desktopScreens()
        let anchor = point ?? NSEvent.mouseLocation
        guard let screen = DesktopPinLayout.screen(containing: anchor, screens: screens) else { return }
        let others = occupied(on: screen, except: nil)
        let origin: CGPoint = point.map {
            DesktopPinLayout.nearestFree(to: CGPoint(x: $0.x - size.width / 2, y: $0.y - size.height / 2),
                                         size: size.size, occupied: others, in: screen.visible)
        } ?? DesktopPinLayout.firstFree(size: size.size, occupied: others, in: screen.visible)
        let rel = DesktopPinLayout.relative(origin, size: size.size, in: screen.visible)
        var next = app.state.desktopPins
        next.enabled = true
        next.add(DesktopPin(widgetID: widget.id, sheetID: sheet, size: size, displayID: screen.id,
                            x: rel.x, y: rel.y))
        app.state.desktopPins = next
    }

    /// 改尺寸：左上角不动，压到别的卡片就挪到最近的空位。大号没解锁弹付费墙。
    func resize(_ id: UUID, to size: DesktopPinSize) {
        guard let app, let pin = settings.pin(id) else { return }
        guard DesktopPinGate.canResize(to: size, unlocked: ProAccess.isUnlocked) == .allowed else {
            return PaywallWindow.shared.show()
        }
        let screens = desktopScreens()
        guard let screen = DesktopPinLayout.screen(for: pin, screens: screens),
              let current = DesktopPinLayout.frame(for: pin, size: drawnSize(pin),
                                                   screens: screens) else { return }
        let wanted = CGPoint(x: current.minX, y: current.maxY - size.height)
        let origin = DesktopPinLayout.nearestFree(to: wanted, size: size.size,
                                                  occupied: occupied(on: screen, except: id), in: screen.visible)
        let rel = DesktopPinLayout.relative(origin, size: size.size, in: screen.visible)
        if let panel = cards[id] {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                panel.animator().setFrame(CGRect(origin: origin, size: size.size), display: true)
            }
        }
        app.state.desktopPins.update(id) {
            $0.size = size
            $0.displayID = screen.id
            $0.x = rel.x
            $0.y = rel.y
        }
    }

    func unpin(_ id: UUID) {
        app?.state.desktopPins.remove(id)
    }

    /// 取消这个小组件钉在桌面的所有卡片（右键菜单里的「取消钉在桌面」）。
    func unpin(widget: WidgetInstance) {
        app?.state.desktopPins.pins.removeAll { $0.widgetID == widget.id }
    }

    func unpinAll() {
        app?.state.desktopPins.removeAll()
    }

    func openSettings() {
        guard let app else { return }
        SettingsWindow.shared.show(app: app, tab: "Widgets")
    }

    // MARK: 键盘

    /// 点卡片外面时系统自己把键盘交给被点的 App；按 Esc 时这里交还：卡片不再是 key，
    /// 前台 App（码头从没被激活，它一直是前台）重新拿到键盘。
    func releaseFocus() {
        for panel in cards.values where panel.isKeyWindow {
            panel.makeFirstResponder(nil)
            panel.resignKey()
        }
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            front.activate(options: [])
        }
    }

    // MARK: 拖动卡片

    /// 卡片右上角的拖动键、排列模式里的整张卡片：拖着走，松手吸到最近的空位。
    func moveGesture(_ id: UUID) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { _ in DesktopPinController.shared.moveChanged(id) }
            .onEnded { _ in DesktopPinController.shared.moveEnded(id) }
    }

    private func moveChanged(_ id: UUID) {
        guard let panel = cards[id], let pin = settings.pin(id) else { return }
        let mouse = NSEvent.mouseLocation
        if move?.pinID != id {
            move = MoveSession(pinID: id, startMouse: mouse, startOrigin: panel.frame.origin, size: panel.frame.size)
            ui.draggingPin = id
            watchRelease { DesktopPinController.shared.moveEnded(id) }
        }
        guard let session = move else { return }
        let origin = CGPoint(x: session.startOrigin.x + mouse.x - session.startMouse.x,
                             y: session.startOrigin.y + mouse.y - session.startMouse.y)
        panel.setFrameOrigin(origin)
        let size = drawnSize(pin)
        showSlot(for: origin, size: size, around: mouse, except: id, isNew: false, above: panel)
    }

    private func moveEnded(_ id: UUID) {
        // 手势和鼠标松开各来一次，只收一次尾。
        guard move?.pinID == id else { return }
        stopWatchingRelease()
        defer {
            move = nil
            ui.draggingPin = nil
            if !ui.editing { hideGrid() } else { ui.slot = nil }
        }
        guard let app, let panel = cards[id], let session = move, session.pinID == id,
              let pin = settings.pin(id) else { return }
        let size = drawnSize(pin)
        let mouse = NSEvent.mouseLocation
        let screens = desktopScreens()
        guard let screen = DesktopPinLayout.screen(containing: mouse, screens: screens) else { return }
        let origin = DesktopPinLayout.nearestFree(to: panel.frame.origin, size: size.size,
                                                  occupied: occupied(on: screen, except: id), in: screen.visible)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().setFrame(CGRect(origin: origin, size: size.size), display: true)
        }
        // 没解锁时存的是大号也照大号的尺寸算相对坐标，解锁后在同一个地方。
        let rel = DesktopPinLayout.relative(origin, size: pin.size.size, in: screen.visible)
        app.state.desktopPins.update(id) {
            $0.displayID = screen.id
            $0.x = rel.x
            $0.y = rel.y
        }
    }

    // MARK: 从扩展栏拖出来

    /// 扩展栏上的卡片被拖离扩展栏：显示网格和橙色虚线空位，跟着指针走。
    func shelfDragChanged(_ widget: WidgetInstance) {
        let mode = mode(for: widget.kind)
        guard mode != .none else { return }
        let size = settings.pin(widget: widget.id, sheet: widget.kind == .notes ? frontSheetID(widget) : nil)?.size
            ?? DesktopPinSupport.defaultSize(mode)
        incoming = (widget.id, size)
        let mouse = NSEvent.mouseLocation
        let origin = CGPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height / 2)
        showSlot(for: origin, size: size, around: mouse, except: nil, isNew: true, above: nil)
        if releaseMonitors.isEmpty {
            let carried = widget
            watchRelease {
                let controller = DesktopPinController.shared
                guard controller.incoming?.widget == carried.id else { return }
                controller.shelfDragEnded(WidgetWriter.current(carried.id) ?? carried)
            }
        }
    }

    /// 拖回扩展栏上：收起网格，照常排序。
    func shelfDragCancelled() {
        guard incoming != nil else { return }
        incoming = nil
        stopWatchingRelease()
        hideGrid()
    }

    /// 在扩展栏外松手：钉在空位上。返回 true 表示这次拖动是钉到桌面（扩展栏不排序）。
    @discardableResult
    func shelfDragEnded(_ widget: WidgetInstance) -> Bool {
        guard let carried = incoming, carried.widget == widget.id else { return false }
        incoming = nil
        stopWatchingRelease()
        hideGrid()
        pin(widget, size: carried.size, at: NSEvent.mouseLocation)
        return true
    }

    var isCarryingFromShelf: Bool { incoming != nil }

    /// 鼠标松开时调 `done`：码头自己的窗口里松开（本地）和别的 App 上松开（全局）都算。
    /// 收尾只做一次（`moveEnded`、`shelfDragEnded` 自己会判断），手势的 onEnded 晚一步再来也没事。
    private func watchRelease(_ done: @escaping () -> Void) {
        stopWatchingRelease()
        let fire: (NSEvent) -> Void = { _ in done() }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: fire) {
            releaseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp, handler: { event in
            fire(event)
            return event
        }) {
            releaseMonitors.append(local)
        }
    }

    private func stopWatchingRelease() {
        for monitor in releaseMonitors { NSEvent.removeMonitor(monitor) }
        releaseMonitors.removeAll()
    }

    private func frontSheetID(_ widget: WidgetInstance) -> String? {
        let pile = StickyStack.pile(widget.config)
        return pile.front.id.isEmpty ? nil : pile.front.id
    }

    // MARK: 网格

    /// 在指针所在的屏幕上铺网格，空位画成橙色虚线。拖卡片时网格在卡片下面（桌面那一层），
    /// 从扩展栏拖出来时网格浮在窗口上面，不然被窗口挡住看不见。
    private func showSlot(for origin: CGPoint, size: DesktopPinSize, around mouse: CGPoint,
                          except: UUID?, isNew: Bool, above card: NSPanel?) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let desktop = DesktopScreen(id: screen.displayID ?? 0, visible: screen.visibleFrame)
        let spot = DesktopPinLayout.nearestFree(to: origin, size: size.size,
                                                occupied: occupied(on: desktop, except: except),
                                                in: screen.visibleFrame)
        let grid = gridWindow(on: screen, floating: isNew)
        if let card {
            grid.order(.below, relativeTo: card.windowNumber)
        } else if !grid.isVisible {
            grid.orderFrontRegardless()
        }
        let frame = screen.frame
        ui.slot = CGRect(x: spot.x - frame.minX, y: frame.maxY - (spot.y + size.height),
                         width: size.width, height: size.height)
        ui.slotSize = size
        ui.slotIsNew = isNew
    }

    private func gridWindow(on screen: NSScreen, floating: Bool) -> NSPanel {
        let panel: NSPanel
        if let existing = gridPanel {
            panel = existing
        } else {
            panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.animationBehavior = .none
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            gridPanel = panel
        }
        panel.level = floating ? .floating : Self.desktopLevel
        panel.appearance = cards.values.first?.appearance
        if gridScreen != screen || panel.contentView == nil {
            gridScreen = screen
            panel.setFrame(screen.frame, display: false)
            let frame = screen.frame
            let visible = screen.visibleFrame
            let local = CGRect(x: visible.minX - frame.minX, y: frame.maxY - visible.maxY,
                               width: visible.width, height: visible.height)
            panel.contentView = NSHostingView(rootView: DesktopPinGridView(ui: ui, visible: local))
        }
        return panel
    }

    private func hideGrid() {
        ui.slot = nil
        gridPanel?.orderOut(nil)
    }

    // MARK: 排列模式

    func setEditing(_ on: Bool) {
        guard ui.editing != on || (on && arrangeBar?.isVisible != true) else { return }
        if on, cards.isEmpty { return }
        ui.editing = on
        if on {
            showArrangeBar()
            if let screen = cards.values.first?.screen ?? NSScreen.main {
                let grid = gridWindow(on: screen, floating: false)
                grid.orderFrontRegardless()
                if let card = cards.values.first { grid.order(.below, relativeTo: card.windowNumber) }
            }
        } else {
            arrangeBar?.orderOut(nil)
            hideGrid()
        }
    }

    private func showArrangeBar() {
        let panel: NSPanel
        if let arrangeBar {
            panel = arrangeBar
        } else {
            let size = DesktopPinArrangeBar.size
            let hosting = FirstMouseHostingView(rootView: DesktopPinArrangeBar())
            hosting.frame = CGRect(origin: .zero, size: size)
            hosting.autoresizingMask = [.width, .height]
            let bar = KeyablePanel(contentRect: CGRect(origin: .zero, size: size),
                                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            bar.onCancel = { DesktopPinController.shared.setEditing(false) }
            bar.contentView = hosting
            bar.isOpaque = false
            bar.backgroundColor = .clear
            bar.hasShadow = true
            bar.isMovable = false
            bar.hidesOnDeactivate = false
            bar.isReleasedWhenClosed = false
            bar.animationBehavior = .none
            bar.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            bar.level = .statusBar
            arrangeBar = bar
            panel = bar
        }
        panel.appearance = cards.values.first?.appearance
        guard let screen = NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let size = DesktopPinArrangeBar.size
        panel.setFrame(CGRect(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 12,
                              width: size.width, height: size.height), display: false)
        panel.orderFrontRegardless()
    }

    // MARK: 被窗口盖住时自动隐藏

    private func watchCovering(_ on: Bool) {
        if on {
            guard coverTimer == nil else { return }
            let timer = Timer(timeInterval: 1.2, repeats: true) { _ in
                MainActor.assumeIsolated { DesktopPinController.shared.checkCovered() }
            }
            timer.tolerance = 0.4
            RunLoop.main.add(timer, forMode: .common)
            coverTimer = timer
            checkCovered()
        } else {
            coverTimer?.invalidate()
            coverTimer = nil
            for id in covered { reveal(id, true) }
            covered.removeAll()
        }
    }

    /// 读屏幕上普通窗口的位置（不用屏幕录制权限），盖住卡片四分之一以上就把卡片收起，
    /// 窗口挪开或最小化（不再在屏幕上）后再出现。拖动、排列时不收。
    private func checkCovered() {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                   kCGNullWindowID) as? [[String: Any]],
              let primary = NSScreen.screens.first?.frame else { return }
        let me = ProcessInfo.processInfo.processIdentifier
        let windows: [CGRect] = list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? Int32) != me,
                  ((info[kCGWindowAlpha as String] as? Double) ?? 1) > 0.05,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            // CG 的原点在主屏左上，换成 AppKit 的左下。
            return CGRect(x: rect.minX, y: primary.maxY - rect.maxY, width: rect.width, height: rect.height)
        }
        for (id, panel) in cards {
            let frame = panel.frame
            let area = frame.width * frame.height
            let hidden = !ui.editing && ui.draggingPin != id && windows.contains { window in
                let overlap = window.intersection(frame)
                return !overlap.isNull && overlap.width * overlap.height >= area * 0.25
            }
            if hidden != covered.contains(id) {
                if hidden { covered.insert(id) } else { covered.remove(id) }
                reveal(id, !hidden)
            }
        }
    }

    private func reveal(_ id: UUID, _ visible: Bool) {
        guard let panel = cards[id] else { return }
        panel.ignoresMouseEvents = !visible
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = visible ? 1 : 0
        }
    }
}
