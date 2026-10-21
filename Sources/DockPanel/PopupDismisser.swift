import AppKit
import Quartz

/// 扩展栏弹出小窗（分组窗口、文件夹小窗，以及复用文件夹小窗的其他弹窗）
/// 通用的收起方式：点窗口外任意地方（别的 App、桌面、扩展栏其他位置）、
/// 按 Esc 收起；再点一次格子仍是收起，不会收起后立刻又打开。
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
    /// Esc 先退一步时做什么。
    var backOut: () -> Void = {}
    /// 收起。
    var dismiss: () -> Void = {}

    private var monitors: [Any] = []
    private var pending: (start: CGPoint, timer: Timer)?
    private var reopen = PopupDismissal.ReopenGuard()

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
