import AppKit
import Observation
import SwiftUI

/// AI 助手的刘海入口和展开的对话面板。
///
/// 入口：有刘海的屏幕上入口就是刘海本身，不向两侧多出黑块，不占菜单栏的
/// 水平空间。点一下刘海或按用户自设的快捷键才展开。指针移到刘海上时，刘海
/// 下沿往下长出一条和刘海同宽的黑色小条，里面是小熊猫，离开约 0.3 秒后收
/// 回；回答生成中这条小条里是三个跳动的小点。小条只盖在菜单栏下方，不响应
/// 鼠标。没有刘海的屏幕（外接屏）在菜单栏下沿正下方放一个小胶囊。
///
/// 和拾掇共处：拾掇的悬浮暂存架在指针碰到刘海、或者拖文件到刘海时弹出。
/// 拾掇在运行时码头不在刘海上放任何入口窗口，刘海的点击和悬停都让给拾掇，
/// 入口改为快捷键和货架上 AI 卡片的小熊猫。
///
/// 和灵动提示共处：灵动提示出现在同一块屏幕时入口淡出让位，收起后恢复。
///
/// 刘海对话是码头 Pro 的功能：没解锁时入口照常显示，点刘海、按快捷键都只弹
/// 付费墙，不展开对话；货架上 AI 卡片的小熊猫退回原来的提问面板，跳转到网页
/// 或 App 照旧免费。
@MainActor
final class AINotchController {
    static let shared = AINotchController()

    private var settings = AINotchSettings()
    private var entries: [UInt32: AINotchEntryWindow] = [:]
    private var strips: [UInt32: AINotchStripWindow] = [:]
    private var panel: KeyablePanel?
    private let panelModel = AINotchPanelModel()
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private(set) var shiduoRunning = false
    private var started = false

    private init() {}

    var isOpen: Bool { panel?.isVisible == true && panelModel.isOpen }

    func apply(_ next: AINotchSettings) {
        settings = next
        startIfNeeded()
        AIHotKey.shared.update(next.usableHotKey)
        layout()
    }

    // MARK: 入口

    private func startIfNeeded() {
        guard !started else { return }
        started = true
        AIHotKey.shared.onPress = { [weak self] in self?.toggle(onScreenWithPointer: true) }
        shiduoRunning = Self.checkShiduo()

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        })
        observers.append(center.addObserver(forName: IslandOccupancy.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        })
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.shiduoMayHaveChanged() }
            })
        }
    }

    static func checkShiduo() -> Bool {
        AIShiduo.isRunning(NSWorkspace.shared.runningApplications.map(\.bundleIdentifier))
    }

    private func shiduoMayHaveChanged() {
        let running = Self.checkShiduo()
        guard running != shiduoRunning else { return }
        shiduoRunning = running
        layout()
    }

    static func describe(_ screen: NSScreen, isMain: Bool) -> AINotchScreen {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        let notch = AINotchLayout.notchRect(screen: screen.frame, topInset: screen.safeAreaInsets.top,
                                            leftArea: screen.auxiliaryTopLeftArea,
                                            rightArea: screen.auxiliaryTopRightArea)
        return AINotchScreen(id: number?.uint32Value ?? 0, frame: screen.frame, notch: notch,
                             menuBarHeight: max(0, screen.frame.maxY - screen.visibleFrame.maxY),
                             isMain: isMain)
    }

    private var described: [AINotchScreen] {
        NSScreen.screens.enumerated().map { Self.describe($0.element, isMain: $0.offset == 0) }
    }

    /// 按设置、屏幕、拾掇和灵动提示重新摆一遍入口。
    private func layout() {
        let wanted = settings.enabled ? AINotchLayout.screens(described, mainOnly: settings.mainScreenOnly) : []
        let island = IslandOccupancy.shared.frame
        var placed: [UInt32: (AINotchEntry, Bool)] = [:]
        for screen in wanted {
            guard let entry = AINotchLayout.entry(for: screen, shiduoRunning: shiduoRunning) else { continue }
            let islandHere = island.map { $0.intersects(screen.frame) } ?? false
            placed[screen.id] = (entry, AINotchLayout.isVisible(enabled: settings.enabled, islandShowing: islandHere))
        }
        for (id, window) in entries where placed[id] == nil {
            window.orderOut(nil)
            entries[id] = nil
        }
        for (id, strip) in strips {
            if case .notch = placed[id]?.0 { continue }
            strip.orderOut(nil)
            strips[id] = nil
        }
        for (id, value) in placed {
            let (entry, visible) = value
            let window = entries[id] ?? makeEntry(id)
            window.model.entry = entry
            window.model.visible = visible
            if !visible { window.model.hovering = false }
            window.ignoresMouseEvents = !visible
            if window.frame != entry.frame { window.setFrame(entry.frame, display: true) }
            window.orderFrontRegardless()
            if case .notch(_, let stripFrame) = entry {
                let strip = strips[id] ?? makeStrip(id, entry: window.model)
                if strip.frame != stripFrame { strip.setFrame(stripFrame, display: true) }
                strip.orderFrontRegardless()
            }
        }
    }

    private func makeEntry(_ id: UInt32) -> AINotchEntryWindow {
        let window = AINotchEntryWindow.make()
        window.onClick = { [weak self, weak window] in
            guard let self, let window else { return }
            self.toggle(from: window.frame)
        }
        entries[id] = window
        return window
    }

    private func makeStrip(_ id: UInt32, entry: AINotchEntryModel) -> AINotchStripWindow {
        let strip = AINotchStripWindow.make(entry: entry, panel: panelModel)
        strips[id] = strip
        return strip
    }

    // MARK: 面板

    /// 指针所在屏幕（或主屏）上入口的位置。入口关着或拾掇占着刘海时按屏幕
    /// 算一个，面板照样从刘海下面长出来（快捷键和货架上的小熊猫打开同一个
    /// 对话）。
    private func anchor(onScreenWithPointer: Bool) -> (entry: CGRect, screen: CGRect)? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        let pointer = NSEvent.mouseLocation
        let target = onScreenWithPointer
            ? (screens.first { $0.frame.contains(pointer) } ?? screens[0]) : screens[0]
        let index = screens.firstIndex(of: target) ?? 0
        let description = Self.describe(target, isMain: index == 0)
        if let window = entries[description.id], window.model.visible {
            return (window.frame, target.frame)
        }
        return (AINotchLayout.anchor(for: description, shiduoRunning: shiduoRunning), target.frame)
    }

    /// 没解锁码头 Pro 时弹付费墙并返回 false。
    private func unlockedOrPaywall() -> Bool {
        guard ProLicenseGate.canOpenAINotch(unlocked: ProAccess.isUnlocked) else {
            PaywallWindow.shared.show()
            return false
        }
        return true
    }

    func toggle(onScreenWithPointer: Bool = false) {
        if isOpen { return close() }
        guard unlockedOrPaywall() else { return }
        guard let anchor = self.anchor(onScreenWithPointer: onScreenWithPointer) else { return }
        show(below: anchor.entry, screen: anchor.screen)
    }

    private func toggle(from entryFrame: CGRect) {
        if isOpen { return close() }
        guard unlockedOrPaywall() else { return }
        let screen = NSScreen.screens.first { $0.frame.intersects(entryFrame) } ?? NSScreen.screens.first
        show(below: entryFrame, screen: screen?.frame ?? entryFrame)
    }

    /// 打开（已经开着就留着）。货架的小熊猫和旧提问面板用。
    func open() {
        if isOpen {
            panel?.makeKey()
            return
        }
        guard unlockedOrPaywall() else { return }
        guard let anchor = self.anchor(onScreenWithPointer: true) else { return }
        show(below: anchor.entry, screen: anchor.screen)
    }

    /// 货架上 AI 卡片的小熊猫：当前服务是网页或 API 时打开刘海对话（同一个
    /// 会话），是跳转时返回 false，由卡片照旧打开原来的提问面板。
    ///
    /// 没解锁码头 Pro 时也返回 false：小熊猫打开原来的提问面板，跳转照旧免费。
    func openFromShelf(_ instance: WidgetInstance) -> Bool {
        guard ProLicenseGate.canOpenAINotch(unlocked: ProAccess.isUnlocked) else { return false }
        let center = AIChatCenter.shared
        let services = AIServices.enabled(in: instance.config)
        guard let service = services.first(where: { $0.id == center.current?.id })
                ?? AIServices.defaultService(in: instance.config, enabled: services),
              center.mode(for: service) != .jump else { return false }
        center.select(service.id)
        WidgetDetailWindow.shared.close()
        open()
        return true
    }

    private func show(below entry: CGRect, screen: CGRect) {
        let panel = existingOrNewPanel()
        let frame = AINotchLayout.panelFrame(below: entry, screen: screen)
        panel.setFrame(frame, display: false)
        panelModel.hangsFromNotch = AINotchLayout.hangsFromNotch(entry)
        panelModel.notchBlend = AINotchLayout.notchBlend(entry: entry, panel: frame)
        panelModel.isOpen = true
        panelModel.session = UUID()
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        panel.makeKey()
        watchForDismissal()
    }

    func close() {
        guard panelModel.isOpen else { return }
        panelModel.isOpen = false
        stopWatching()
        guard let panel, panel.isVisible else { return }
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduce ? 0 : 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.panelModel.isOpen else { return }
                self.panel?.orderOut(nil)
                self.panel?.alphaValue = 1
            }
        }
    }

    private func existingOrNewPanel() -> KeyablePanel {
        if let panel { return panel }
        let size = AINotchLayout.panelSize
        let hosting = FirstMouseHostingView(rootView: AIChatPanelView(center: AIChatCenter.shared, model: panelModel,
                                                                      close: { [weak self] in self?.close() }))
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        let panel = KeyablePanel(contentRect: CGRect(origin: .zero, size: size),
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.onCancel = { [weak self] in self?.close() }
        panel.contentView = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.level = .statusBar
        self.panel = panel
        return panel
    }

    /// 点面板外面收起，钉住时不收。点入口本身由入口自己处理（再点一次收起）。
    private func watchForDismissal() {
        stopWatching()
        let dismiss: (NSEvent) -> Void = { [weak self] event in
            guard let self, let panel = self.panel, !AIChatCenter.shared.pinned else { return }
            let point = event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
            guard !panel.frame.contains(point),
                  !self.entries.values.contains(where: { $0.frame.contains(point) }) else { return }
            self.close()
        }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: dismiss) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in
            dismiss(event)
            return event
        }) { monitors.append(local) }
    }

    private func stopWatching() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }
}

/// 面板打开的状态，SwiftUI 那边用来重放“长出来”的动画。
@MainActor @Observable
final class AINotchPanelModel {
    var isOpen = false
    var session = UUID()
    /// 挂在刘海下面还是外接屏胶囊下面。面板都是液态玻璃、跟随浅色 / 深色；挂在
    /// 刘海下面时顶栏让出黑色过渡那一条。见 `AINotchLayout.hangsFromNotch`。
    var hangsFromNotch = true
    /// 刘海下面板顶上那条黑色过渡（面板坐标），不在刘海下时为 nil。见
    /// `AINotchLayout.notchBlend`。
    var notchBlend: CGRect?
}

// MARK: - 入口窗口

/// 入口画什么，SwiftUI 那边读。
@MainActor @Observable
final class AINotchEntryModel {
    var entry: AINotchEntry = .capsule(frame: .zero)
    var visible = true
    var hovering = false
}

/// 入口窗口：无边框、不抢焦点、在菜单栏之上，大小正好是刘海（或外接屏的
/// 小胶囊）。只认点击：不注册拖放类型，悬停只让刘海下沿长出提示条（或让
/// 胶囊完全显示），不会展开。
@MainActor
final class AINotchEntryWindow: NSPanel {
    let model = AINotchEntryModel()
    var onClick: (() -> Void)?
    private var leaveTask: Task<Void, Never>?

    /// 用继承来的 init 建好再配置：自己写指定构造器就得连 init(coder:) 一起写。
    static func make() -> AINotchEntryWindow {
        let window = AINotchEntryWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                        backing: .buffered, defer: false)
        window.configure()
        return window
    }

    private func configure() {
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let host = AINotchEntryHost(rootView: AINotchEntryView(model: model, center: AIChatCenter.shared))
        host.onClick = { [weak self] in self?.onClick?() }
        host.onHover = { [weak self] inside in self?.hover(inside) }
        host.autoresizingMask = [.width, .height]
        contentView = host
    }

    /// 进来马上显示；离开后等一小会儿再收回，指针擦过刘海边缘不会闪。
    private func hover(_ inside: Bool) {
        leaveTask?.cancel()
        leaveTask = nil
        if inside {
            set(hovering: true)
            return
        }
        leaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(AINotchLayout.stripLinger))
            guard !Task.isCancelled else { return }
            self?.set(hovering: false)
        }
    }

    private func set(hovering: Bool) {
        guard model.hovering != hovering else { return }
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(reduce ? nil : .spring(response: 0.3, dampingFraction: 0.82)) {
            model.hovering = hovering
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 入口的宿主视图：自己处理点击和指针进出，SwiftUI 只管画。
final class AINotchEntryHost: NSHostingView<AINotchEntryView> {
    var onClick: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    private var area: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// 点击总是落在宿主自己身上，不交给 SwiftUI 里面的子视图。
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let next = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(next)
        area = next
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }
        onClick?()
    }

    override func rightMouseDown(with event: NSEvent) {}
}

// MARK: - 刘海下沿的提示条

/// 刘海下沿那一条：在菜单栏下方，和刘海同宽，不响应鼠标（点击穿过去落到
/// 下面的窗口上）。悬停时显示小熊猫，回答生成中显示三个跳动的小点。
@MainActor
final class AINotchStripWindow: NSPanel {
    static func make(entry: AINotchEntryModel, panel: AINotchPanelModel) -> AINotchStripWindow {
        let window = AINotchStripWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                        backing: .buffered, defer: false)
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isMovable = false
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        let host = NSHostingView(rootView: AINotchStripView(entry: entry, panel: panel, center: AIChatCenter.shared))
        host.autoresizingMask = [.width, .height]
        window.contentView = host
        return window
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
