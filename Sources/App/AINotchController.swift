import AppKit
import Observation
import SwiftUI

/// AI 助手的刘海入口和展开的对话面板。
///
/// 入口：有刘海的屏幕上贴着刘海，左边小熊猫、右边当前服务的字牌，黑色和
/// 刘海连成一体；没有刘海的屏幕（外接屏）在顶部正中放一个小胶囊。指针
/// 移过去只是轻微变宽，不会展开；点一下或按用户自设的快捷键才展开。
///
/// 和拾掇共处：拾掇的悬浮暂存架在指针碰到刘海、或者拖文件到刘海时弹出。
/// 入口窗口不注册任何拖放类型、不因悬停做任何事；拾掇在运行时入口干脆
/// 离开刘海，改成刘海右边隔一段距离的小胶囊，不和刘海重叠。
///
/// 和灵动提示共处：灵动提示出现在同一块屏幕时入口淡出让位，收起后恢复。
@MainActor
final class AINotchController {
    static let shared = AINotchController()

    private var settings = AINotchSettings()
    private var entries: [UInt32: AINotchEntryWindow] = [:]
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
        let ids = Set(wanted.map(\.id))
        for (id, window) in entries where !ids.contains(id) {
            window.orderOut(nil)
            entries[id] = nil
        }
        let island = IslandOccupancy.shared.frame
        for screen in wanted {
            let entry = AINotchLayout.entry(for: screen, shiduoRunning: shiduoRunning)
            let islandHere = island.map { $0.intersects(screen.frame) } ?? false
            let visible = AINotchLayout.isVisible(enabled: settings.enabled, islandShowing: islandHere)
            let window = entries[screen.id] ?? makeEntry(screen.id)
            window.model.entry = entry
            window.model.visible = visible
            window.ignoresMouseEvents = !visible
            if window.frame != entry.frame { window.setFrame(entry.frame, display: true) }
            window.orderFrontRegardless()
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

    // MARK: 面板

    /// 指针所在屏幕（或主屏）上入口的位置。入口关着时按设置算一个，面板
    /// 照样从那里长出来（货架上的小熊猫也能打开同一个对话）。
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
        let entry = AINotchLayout.entry(for: description, shiduoRunning: shiduoRunning)
        return (entry.frame, target.frame)
    }

    func toggle(onScreenWithPointer: Bool = false) {
        if isOpen { return close() }
        guard let anchor = self.anchor(onScreenWithPointer: onScreenWithPointer) else { return }
        show(below: anchor.entry, screen: anchor.screen)
    }

    private func toggle(from entryFrame: CGRect) {
        if isOpen { return close() }
        let screen = NSScreen.screens.first { $0.frame.intersects(entryFrame) } ?? NSScreen.screens.first
        show(below: entryFrame, screen: screen?.frame ?? entryFrame)
    }

    /// 打开（已经开着就留着）。货架的小熊猫和旧提问面板用。
    func open() {
        if isOpen {
            panel?.makeKey()
            return
        }
        guard let anchor = self.anchor(onScreenWithPointer: true) else { return }
        show(below: anchor.entry, screen: anchor.screen)
    }

    /// 货架上 AI 卡片的小熊猫：当前服务是网页或 API 时打开刘海对话（同一个
    /// 会话），是跳转时返回 false，由卡片照旧打开原来的提问面板。
    func openFromShelf(_ instance: WidgetInstance) -> Bool {
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
}

// MARK: - 入口窗口

/// 入口画什么，SwiftUI 那边读。
@MainActor @Observable
final class AINotchEntryModel {
    var entry: AINotchEntry = .capsule(frame: .zero, aside: false)
    var visible = true
    var hovering = false
}

/// 入口窗口：无边框、不抢焦点、在菜单栏之上。只认点击：不注册拖放类型，
/// 悬停只让黑色部分轻微变宽。
@MainActor
final class AINotchEntryWindow: NSPanel {
    let model = AINotchEntryModel()
    var onClick: (() -> Void)?

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
        host.onHover = { [weak self] inside in
            guard let self else { return }
            let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            withAnimation(reduce ? nil : .spring(response: 0.28, dampingFraction: 0.8)) {
                self.model.hovering = inside
            }
        }
        host.autoresizingMask = [.width, .height]
        contentView = host
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
