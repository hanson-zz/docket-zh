import AppKit
import Observation
import SwiftUI

/// AI 助手的刘海入口和展开的对话面板。
///
/// 入口：有刘海的屏幕上入口就是刘海本身，不向两侧多出黑块，不占菜单栏的
/// 水平空间。点一下刘海或按用户自设的快捷键才展开。指针移到刘海上时，刘海
/// 下沿往下长出收起态胶囊「● AI 助手」，小熊猫从下沿探头，离开约 0.3 秒后收
/// 回；回答生成中胶囊里是「ChatGPT 正在思考」和三个跳动的小点。胶囊只在菜单栏
/// 下方、宽度按刘海小岛的规则（`AINotchLayout.stripWidth`），不响应鼠标。展开的
/// 对话卡片放在菜单栏下面（`AINotchLayout.panelFrame`）。没有刘海的屏幕（外接屏）
/// 在菜单栏下沿正下方放一个小胶囊。
///
/// 和拾掇共处：拾掇的悬浮暂存架在指针碰到刘海、或者拖文件到刘海时弹出。
/// 拾掇在运行时码头不在刘海上放任何入口窗口，刘海的点击和悬停都让给拾掇，
/// 入口改为快捷键和货架上 AI 卡片的小熊猫。
///
/// 和灵动提示共处：灵动提示出现在同一块屏幕时入口淡出让位，收起后恢复。消息灵动岛的
/// 卡片展开时同样让位（下沿提示条会压在卡片顶上），见 `NotchMessagePriority`。
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
    /// 快捷结果卡片（小组件用 API 提问后刘海下方那张，或备用浮窗）。
    private var quickWindow: KeyablePanel?
    let quickModel = AIQuickResultModel()
    private var quickMonitors: [Any] = []

    private init() {}

    var isOpen: Bool { panel?.isVisible == true && panelModel.isOpen }

    /// 完整对话面板开着时它在屏幕上的位置，收起时 nil。刘海小岛按它决定悬停时展不展开。
    var panelFrame: CGRect? { isOpen ? panel?.frame : nil }

    /// 快捷结果卡片显示着（刘海下或备用浮窗）。
    var isQuickOpen: Bool { quickModel.target != nil && quickWindow?.isVisible == true }

    /// 刘海这一块被码头的 AI 占着：完整对话面板，或者贴在刘海下的快捷结果卡片（备用浮窗不算，
    /// 它本来就是给刘海上的别的东西让位的）。消息卡片、输入法提示、插电动画按它让位。
    var occupiesNotch: Bool { isOpen || (isQuickOpen && quickModel.target == .notchCard) }

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
        observers.append(center.addObserver(forName: NotchMessageOccupancy.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        })
        // 刘海小岛盖在刘海上时入口让位，小岛收起后回来。
        observers.append(center.addObserver(forName: NotchIslandOccupancy.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        })
        // 插电霓虹动画开播、播完：快捷结果卡片改去备用浮窗、播完回刘海下。
        observers.append(center.addObserver(forName: BatteryNeonPlugController.didChange, object: nil, queue: .main) { [weak self] _ in
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
        let notchIsland = NotchIslandOccupancy.shared.frame
        let messageCard = NotchMessageOccupancy.shared.frame
        var placed: [UInt32: (AINotchEntry, Bool)] = [:]
        for screen in wanted {
            guard let entry = AINotchLayout.entry(for: screen, shiduoRunning: shiduoRunning) else { continue }
            let islandHere = (island.map { $0.intersects(screen.frame) } ?? false)
                || (notchIsland.map { $0.intersects(screen.frame) } ?? false)
            let cardHere = messageCard.map { $0.intersects(screen.frame) } ?? false
            placed[screen.id] = (entry, NotchMessagePriority.aiEntryVisible(enabled: settings.enabled,
                                                                            islandShowing: islandHere,
                                                                            cardExpanded: cardHere))
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
        avoidBlockersWhileOpen()
        relayoutQuick()
    }

    /// 面板开着时刘海小岛后来才出现或变高（倒计时小岛下面那条剩余时间、灵动提示）压到面板：
    /// 面板平滑往下挪到它下面，减弱动态效果时直接到位。只往下不往上（`AINotchLayout.avoidance`）。
    private func avoidBlockersWhileOpen() {
        guard isOpen, let panel else { return }
        let current = panel.frame
        let screen = NSScreen.screens.first { $0.frame.intersects(current) }?.frame ?? current
        guard let next = AINotchLayout.avoidance(current: current, screen: screen, avoiding: blockers) else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.setFrame(next, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(next, display: true)
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
    /// `serviceID` 是卡片上点的那块模型键，优先用它。
    func openFromShelf(_ instance: WidgetInstance, preferring serviceID: String? = nil) -> Bool {
        guard ProLicenseGate.canOpenAINotch(unlocked: ProAccess.isUnlocked) else { return false }
        let center = AIChatCenter.shared
        let services = AIServices.enabled(in: instance.config)
        guard let service = services.first(where: { $0.id == serviceID })
                ?? services.first(where: { $0.id == center.current?.id })
                ?? AIServices.defaultService(in: instance.config, enabled: services),
              center.mode(for: service) != .jump else { return false }
        center.select(service.id)
        WidgetDetailWindow.shared.close()
        open()
        return true
    }

    /// 刘海上正在显示、面板不能盖住的东西：刘海小岛（专注计时、下载、收音机、插电）
    /// 和灵动提示。消息卡片不算：它自己会给 AI 面板让位（`NotchMessagePriority`）。
    private var blockers: [CGRect] {
        [NotchIslandOccupancy.shared.frame, IslandOccupancy.shared.frame].compactMap { $0 }
    }

    private func show(below entry: CGRect, screen: CGRect) {
        // 完整对话打开时快捷结果卡片让位（同一个会话，结果在对话里）。
        closeQuick(animated: false)
        let panel = existingOrNewPanel()
        // 专注计时和系统活动优先：小岛正显示着时，面板挪到它下面，不压住它。
        let placement = AINotchLayout.placement(below: entry, screen: screen, avoiding: blockers)
        panel.setFrame(placement.frame, display: false)
        panelModel.isOpen = true
        panelModel.session = UUID()
        // 收起的淡出可能还在走（刚收起又点开）：顶掉它，不然停在透明度 0。
        panel.showOpaqueCancellingFade()
        panel.orderFrontRegardless()
        panel.makeKey()
        watchForDismissal()
        NotchIslandController.shared.aiPanelChanged()
    }

    func close() {
        guard panelModel.isOpen else { return }
        panelModel.isOpen = false
        AIChatCenter.shared.holdNoticeOnce = false
        stopWatching()
        NotchIslandController.shared.aiPanelChanged()
        guard let panel, panel.isVisible else { return }
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduce ? 0 : 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                // 淡出途中又打开了：不收，透明度补回 1。
                guard !self.panelModel.isOpen else {
                    self.panel?.alphaValue = 1
                    return
                }
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

    // MARK: 快捷结果卡片

    /// 指针所在屏幕（小组件面板就在那块屏幕上）的描述和刘海是不是被占着。
    /// 占着：刘海小岛（专注计时、下载、收音机、插电）、灵动提示、展开的消息卡片、正在播的插电
    /// 霓虹动画在这块屏幕上，或者拾掇在运行、这块屏幕有刘海（刘海让给拾掇）。
    private func quickScreen(id: UInt32? = nil) -> (screen: NSScreen, description: AINotchScreen, occupied: Bool)? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        let target: NSScreen
        if let id, let match = screens.first(where: { Self.describe($0, isMain: false).id == id }) {
            target = match
        } else {
            let pointer = NSEvent.mouseLocation
            target = screens.first { $0.frame.contains(pointer) } ?? screens[0]
        }
        let description = Self.describe(target, isMain: target == screens[0])
        let frame = target.frame
        let busy = [NotchIslandOccupancy.shared.frame, IslandOccupancy.shared.frame,
                    NotchMessageOccupancy.shared.frame,
                    BatteryNeonPlugController.shared.playingFrame].compactMap { $0 }.contains { $0.intersects(frame) }
        let shiduo = shiduoRunning && description.notch != nil
        return (target, description, busy || shiduo)
    }

    /// 小组件刚交过来一个 API 问题：这次结果放在哪（见 `AIQuickResult.target`）。
    func quickTarget(mode: AIOpenMode) -> AIQuickResultTarget {
        let s = AIChatCenter.shared.settings
        return AIQuickResult.target(mode: mode, unlocked: ProLicenseGate.canOpenAINotch(unlocked: ProAccess.isUnlocked),
                                    placement: s.answerPlacement, autoShow: s.autoShowResult,
                                    notchOccupied: quickScreen()?.occupied ?? false)
    }

    /// 弹出快捷结果卡片，显示这个服务最新的一问一答。已经开着就换成这一条、留在原处重新摆。
    func presentQuick(serviceID: String) {
        guard let place = quickScreen() else { return }
        if isOpen { close() }
        quickModel.serviceID = serviceID
        quickModel.screenID = place.description.id
        quickModel.pinned = false
        quickModel.hovering = false
        quickModel.target = place.occupied ? .floating : .notchCard
        quickModel.session = UUID()
        let window = existingOrNewQuickWindow()
        placeQuick(window, place: place)
        window.showOpaqueCancellingFade()
        window.orderFrontRegardless()
        panelModel.quickCard = quickModel.target == .notchCard
        watchQuickDismissal()
    }

    /// 刘海占用、屏幕、内容高度变了以后重新摆：刘海卡片和备用浮窗之间来回换，结果不丢。
    func relayoutQuick() {
        guard isQuickOpen, let window = quickWindow, let current = quickModel.target else { return }
        guard let place = quickScreen(id: quickModel.screenID) else { return }
        let next = AIQuickResult.relocated(current, notchOccupied: place.occupied)
        if next != current { quickModel.target = next }
        panelModel.quickCard = next == .notchCard
        // 刘海卡片和备用浮窗之间换位置时平滑挪过去（同一个窗口、同一条回答，不收起再弹）。
        placeQuick(window, place: place, animated: next != current)
    }

    private func placeQuick(_ window: NSWindow, place: (screen: NSScreen, description: AINotchScreen, occupied: Bool),
                            animated: Bool = false) {
        let description = place.description
        let screen = place.screen.frame
        let notchCard = quickModel.target == .notchCard
        let withMascot = notchCard && description.notch != nil
        quickModel.withMascot = withMascot
        let height = quickModel.cardHeight
        let card: CGRect
        if notchCard {
            let entry = entries[description.id].flatMap { $0.model.visible ? $0.frame : nil }
                ?? AINotchLayout.anchor(for: description, shiduoRunning: shiduoRunning)
            card = AIQuickResult.notchFrame(below: entry, screen: screen, height: height, avoiding: blockers)
        } else {
            let others = blockers + [NotchMessageOccupancy.shared.frame].compactMap { $0 }
            card = AIQuickResult.floatingFrame(screen: screen, menuBar: AINotchLayout.menuBar(of: description),
                                               entry: AINotchLayout.anchor(for: description, shiduoRunning: shiduoRunning),
                                               height: height, blockers: others,
                                               animation: BatteryNeonPlugController.shared.playingFrame)
        }
        let frame = AIQuickResult.windowFrame(card: card, withMascot: withMascot)
        guard window.frame != frame else { return }
        guard animated, window.isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            window.setFrame(frame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().setFrame(frame, display: true)
        }
    }

    /// 收起快捷结果卡片。回答挂在 `AIChatCenter` 上，收起了也照样答完，点刘海或小组件再看。
    func closeQuick(animated: Bool = true) {
        guard quickModel.target != nil else { return }
        quickModel.target = nil
        quickModel.hovering = false
        panelModel.quickCard = false
        stopQuickWatching()
        guard let window = quickWindow, window.isVisible else { return }
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard animated, !reduce else {
            window.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                // 淡出途中又弹出来了：不收，透明度补回 1。
                guard self.quickModel.target == nil else {
                    self.quickWindow?.alphaValue = 1
                    return
                }
                self.quickWindow?.orderOut(nil)
                self.quickWindow?.alphaValue = 1
            }
        }
    }

    /// 「继续追问」「展开」：收起卡片，打开完整对话（同一个服务、同一个会话）。
    /// 「继续追问」再把光标放进底部输入条。
    func expandQuick(focusInput: Bool) {
        let center = AIChatCenter.shared
        if let id = quickModel.serviceID { center.select(id) }
        closeQuick(animated: false)
        open()
        if focusInput, isOpen {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(60))
                center.requestInputFocus()
            }
        }
    }

    private func existingOrNewQuickWindow() -> KeyablePanel {
        if let quickWindow { return quickWindow }
        let size = CGSize(width: AIQuickResult.width, height: AIQuickResult.minHeight)
        let actions = AIQuickResultActions(
            close: { [weak self] in self?.closeQuick() },
            expand: { [weak self] in self?.expandQuick(focusInput: false) },
            followUp: { [weak self] in self?.expandQuick(focusInput: true) },
            resize: { [weak self] in self?.relayoutQuick() },
            settings: { [weak self] in
                self?.closeQuick(animated: false)
                guard let app = AIChatCenter.shared.app else { return }
                SettingsWindow.shared.show(app: app, tab: "AI")
            })
        let hosting = FirstMouseHostingView(rootView: AIQuickResultCard(center: AIChatCenter.shared, model: quickModel,
                                                                        actions: actions))
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        let window = KeyablePanel(contentRect: CGRect(origin: .zero, size: size),
                                  styleMask: [.borderless, .nonactivatingPanel],
                                  backing: .buffered, defer: false)
        window.onCancel = { [weak self] in self?.closeQuick() }
        window.contentView = hosting
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovable = false
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.level = .statusBar
        quickWindow = window
        return window
    }

    /// 点卡片外面收起：固定了不收；还在思考、回答时不收（见 `AIQuickResult.closesOnOutsideClick`）。
    private func watchQuickDismissal() {
        stopQuickWatching()
        let dismiss: (NSEvent) -> Void = { [weak self] event in
            guard let self, let window = self.quickWindow, window.isVisible else { return }
            let point = event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
            guard !window.frame.contains(point) else { return }
            // 菜单（「…」）开着时点的是菜单本身。
            if let clicked = event.window, clicked !== window, clicked.level.rawValue > window.level.rawValue { return }
            guard AIQuickResult.closesOnOutsideClick(phase: self.quickPhase, pinned: self.quickModel.pinned) else { return }
            self.closeQuick()
        }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: dismiss) {
            quickMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in
            dismiss(event)
            return event
        }) { quickMonitors.append(local) }
    }

    private func stopQuickWatching() {
        quickMonitors.forEach(NSEvent.removeMonitor)
        quickMonitors.removeAll()
    }

    /// 卡片上那一条回答现在的阶段。
    var quickPhase: AIQuickResultPhase {
        guard let id = quickModel.serviceID else { return .done }
        let reply = AIQuickResultModel.reply(in: AIChatCenter.shared.messages(id))
        return AIQuickResult.phase(status: reply?.status, text: reply?.text ?? "")
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
    /// 快捷结果卡片贴在刘海下面：刘海下沿那一条「正在思考」收起，由卡片自己显示。
    var quickCard = false
}

/// 快捷结果卡片的状态，SwiftUI 那边读。
@MainActor @Observable
final class AIQuickResultModel {
    /// 显示哪个服务的最新一问一答。
    var serviceID: String?
    /// 在哪：刘海卡片或备用浮窗；收起时 nil。
    var target: AIQuickResultTarget?
    /// 弹出时所在屏幕。
    var screenID: UInt32 = 0
    /// 贴在刘海下、刘海里探头的小熊猫。
    var withMascot = false
    /// 固定：不自动收起，点外面也不收。
    var pinned = false
    var hovering = false
    /// 正文量出来的高度，卡片高度跟着它在 180 到 300 之间变。
    var bodyHeight: CGFloat = 0
    /// 每弹一次换一个，SwiftUI 那边重放出现的动画。
    var session = UUID()

    var cardHeight: CGFloat { AIQuickResult.cardHeight(bodyHeight: bodyHeight, withMascot: withMascot) }

    /// 最新那一问后面的回答；问题刚交过去、回答还没建起来时 nil。
    static func reply(in messages: [AIChatMessage]) -> AIChatMessage? {
        guard let last = messages.last, last.role == .assistant else { return nil }
        return last
    }
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
