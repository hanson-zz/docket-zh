import AppKit
import Quartz

/// 扩展栏弹出小窗（分组窗口、文件夹小窗，以及复用文件夹小窗的其他弹窗）
/// 通用的收起方式：点窗口外任意地方（别的 App、桌面、扩展栏其他位置）、
/// 按 Esc 收起；再点一次格子仍是收起，不会收起后立刻又打开。扩展栏自动隐藏时，
/// 指针离开小窗和扩展栏 0.5 秒也收起（按着鼠标、快速查看、菜单或提示框、
/// 输入法组字时不算，见 `pointerTick`）。
///
/// 拖拽进出、快速查看开着、菜单或提示框开着时不收。点外面的那一下照常
/// 交给被点的东西：这里只看不拦。什么时候收、什么时候忽略的判断在 Core 的
/// `PopupDismissal`，这里只负责听鼠标和键盘。
@MainActor
final class PopupDismisser {
    /// 小窗看得见的那块（屏幕坐标）。分组窗口四周有一圈透明的拖拽余量，不算里面。
    var visibleFrame: () -> CGRect? = { nil }
    /// 小窗本身，点在它的子窗口里也算里面。
    var window: () -> NSWindow? = { nil }
    /// 开着的是哪个格子，用来防「再点一次格子」时收起后又打开。
    var currentID: () -> UUID? = { nil }
    /// 小窗自己要求先别收（比如确认移到废纸篓的提示框开着）。
    var holdOpen: () -> Bool = { false }
    /// 小窗里有能先退一步的东西（搜索有字、改名改了一半、展开的选择列表）。
    var inner: () -> Bool = { false }
    /// 指针算在小窗里的范围（屏幕坐标），比看得见的那块宽一点，从格子过去的
    /// 空隙不算离开。不给就用 `visibleFrame` 四周放宽 12 点。
    var hoverFrame: () -> CGRect? = { nil }
    /// Esc 先退一步时做什么。
    var backOut: () -> Void = {}
    /// 收起。
    var dismiss: () -> Void = {}

    private var monitors: [Any] = []
    private var pending: (start: CGPoint, timer: Timer)?
    private var reopen = PopupDismissal.ReopenGuard()
    private var leave = PopupDismissal.LeaveTimer()

    /// 小窗打开时调用：开始看点击。重复调用会先清掉上一轮。
    func start() {
        stop()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.pressed(event) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.pressed(event)
            return event
        }) {
            monitors.append(local)
        }
    }

    /// 小窗关上时调用。
    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        cancelPending()
        leave.reset()
    }

    // MARK: 指针离开

    /// 扩展栏自动隐藏时，扩展栏每次看指针（约 30 次每秒）调用一次：`overShelf`
    /// 是指针在扩展栏上，`holding` 是扩展栏自己的菜单开着。指针离开小窗和扩展栏
    /// 连续 0.5 秒就收起；鼠标键按着（拖拽，含从访达或别的 App 拖进来）、
    /// 快速查看、菜单、提示框、选择面板、输入法组字时不算，条件解除后从头计时。
    /// 扩展栏固定显示时不调用，只靠点外面和 Esc。判断在 Core 的
    /// `PopupDismissal.LeaveTimer`。
    func pointerTick(_ point: CGPoint, overShelf: Bool, holding: Bool = false) {
        guard let panel = window(), panel.isVisible else { return leave.reset() }
        let away = PopupDismissal.Away(
            pointerInside: overShelf || hovering(point, panel: panel),
            buttonDown: NSEvent.pressedMouseButtons != 0,
            dragging: Self.dragging,
            quickLookOpen: Self.quickLook?.isVisible == true,
            holdOpen: holding || MenuTracking.isOpen || blockedByModal,
            composing: (panel.firstResponder as? NSTextView)?.hasMarkedText() == true)
        guard leave.tick(away, now: Date()) else { return }
        cancelPending()
        dismiss()
    }

    private func hovering(_ point: CGPoint, panel: NSWindow) -> Bool {
        let frame = hoverFrame() ?? visibleFrame()?.insetBy(dx: -12, dy: -12)
        if frame?.contains(point) == true { return true }
        // 小窗弹出的子窗口（比如附着的小面板）上也算在里面。
        return panel.childWindows?.contains { $0.isVisible && $0.frame.contains(point) } == true
    }

    /// 格子要打开 `id`：是刚才点外面收起它的那一下带出来的，就吞掉。
    func swallowsOpen(id: UUID) -> Bool {
        reopen.swallowsOpen(id: id, at: Date(), point: NSEvent.mouseLocation)
    }

    /// 小窗收到 Esc。返回 true 表示已处理，false 交给系统（输入法组字、菜单）。
    func escape(in panel: NSWindow) -> Bool {
        let editor = panel.firstResponder as? NSTextView
        let decision = PopupDismissal.escape(.init(
            composing: editor?.hasMarkedText() == true,
            menuOpen: MenuTracking.isOpen,
            dragging: Self.dragging,
            quickLookOpen: Self.quickLook?.isVisible == true,
            inner: inner()))
        switch decision {
        case .pass:
            return false
        case .closeQuickLook:
            Self.quickLook?.orderOut(nil)
            return true
        case .backOut:
            backOut()
            return true
        case .dismiss:
            dismiss()
            return true
        }
    }

    // MARK: 点击

    private func pressed(_ event: NSEvent) {
        let point = event.window.map { $0.convertPoint(toScreen: event.locationInWindow) }
            ?? NSEvent.mouseLocation
        let ql = Self.quickLook
        let qlOpen = ql?.isVisible == true
        let press = PopupDismissal.Press(
            button: event.type == .leftMouseDown ? .primary
                : event.type == .rightMouseDown ? .secondary : .other,
            inPopup: inside(event.window, point),
            inQuickLook: event.window is QLPreviewPanel || (qlOpen && ql?.frame.contains(point) == true),
            quickLookOpen: qlOpen,
            menuOpen: MenuTracking.isOpen,
            modalOpen: blockedByModal,
            dragging: Self.dragging)
        switch PopupDismissal.press(press) {
        case .ignore:
            return
        case .dismissNow:
            cancelPending()
            // 右键、中键不会触发格子的「再点一次」，不用防重开。
            dismiss()
        case .dismissOnRelease:
            waitForRelease(from: point)
        }
    }

    private func inside(_ clicked: NSWindow?, _ point: CGPoint) -> Bool {
        if let clicked, let panel = window(), clicked !== panel {
            var parent = clicked.parent
            while let current = parent {
                if current === panel { return true }
                parent = current.parent
            }
        }
        return visibleFrame()?.contains(point) == true
    }

    /// 左键按下：等松开再决定，按住拖走的是拖拽，不收。看按键状态和指针位置
    /// 而不是等松开事件，因为别的 App 的菜单会把松开那一下吃掉。
    private func waitForRelease(from start: CGPoint) {
        cancelPending()
        let timer = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkRelease() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pending = (start, timer)
    }

    private func checkRelease() {
        guard let pending else { return }
        let blocked = MenuTracking.isOpen || Self.quickLook?.isVisible == true
            || blockedByModal || Self.dragging
        let decision = PopupDismissal.release(start: pending.start, current: NSEvent.mouseLocation,
                                              buttonDown: NSEvent.pressedMouseButtons & 1 != 0,
                                              blocked: blocked)
        switch decision {
        case .wait:
            return
        case .cancel:
            cancelPending()
        case .dismiss:
            cancelPending()
            dismissed(at: pending.start)
        }
    }

    private func cancelPending() {
        pending?.timer.invalidate()
        pending = nil
    }

    private func dismissed(at point: CGPoint) {
        reopen.noteDismissed(id: currentID(), at: Date(), point: point)
        dismiss()
    }

    private var blockedByModal: Bool {
        if holdOpen() || NSApp.modalWindow != nil { return true }
        // 小窗自己弹出的子窗口或附着的提示框开着。
        if let panel = window(), panel.attachedSheet != nil { return true }
        return false
    }

    /// 正把扩展栏或分组里的图标拖着走。从访达拖文件进来靠「按下后移动」识别。
    private static var dragging: Bool { DragOut.shared.item != nil || ShelfResize.isDragging }

    static var quickLook: QLPreviewPanel? {
        QLPreviewPanel.sharedPreviewPanelExists() ? QLPreviewPanel.shared() : nil
    }
}

/// 弹出小窗的窗口：能成为 key（搜索框、改名框要打字），Esc 交给
/// `PopupDismisser` 判断是先退一步还是收起。在 sendEvent 里接，这样搜索框
/// 正在输入时也能先清空搜索，而不是被输入框吞掉或者直接关窗。
class PopupPanel: NSPanel {
    /// 返回 true 表示 Esc 已处理。
    var onEscape: (() -> Bool)?

    override var canBecomeKey: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53,
           event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
           onEscape?() == true {
            return
        }
        super.sendEvent(event)
    }

    override func cancelOperation(_ sender: Any?) {
        _ = onEscape?()
    }
}
