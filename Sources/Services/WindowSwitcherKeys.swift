import AppKit
import Carbon.HIToolbox

/// ⌥Tab 窗口切换器的全局快捷键。和截图、快速待办一个写法：Carbon 的
/// `RegisterEventHotKey`，平时只占一个快捷键，不监听任何按键。签名“DkWs”。
///
/// 切换器弹出期间先放开（`pause`），后面的 Tab、⇧Tab 和松开 ⌥ 都由 `SwitcherEventTap`
/// 收，收起后再注册回来。设置里录快捷键时也放开（`suspend`）。
@MainActor
final class WindowSwitcherHotKey {
    static let shared = WindowSwitcherHotKey()

    /// 按下时调。
    var onPress: (@MainActor () -> Void)?

    private var combo: KeyCombo?
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var suspended = false
    private var paused = false

    nonisolated private static let signature: OSType = 0x446B_5773

    private init() {}

    /// 要注册的快捷键；nil 是不注册（没设、没辅助功能权限）。
    func apply(_ wanted: KeyCombo?) {
        guard wanted != combo else { return }
        combo = wanted
        reregister()
    }

    func suspend() {
        guard !suspended else { return }
        suspended = true
        reregister()
    }

    func resume() {
        guard suspended else { return }
        suspended = false
        reregister()
    }

    func pause() {
        guard !paused else { return }
        paused = true
        reregister()
    }

    func unpause() {
        guard paused else { return }
        paused = false
        reregister()
    }

    private func reregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        guard !suspended, !paused, let combo else { return }
        installHandlerIfNeeded()
        var out: EventHotKeyRef?
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers,
                                         EventHotKeyID(signature: Self.signature, id: 1),
                                         GetApplicationEventTarget(), 0, &out)
        // 别的 App 已经占了这个组合时注册失败，等用户换一个。
        if status == noErr { ref = out }
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr, hotKeyID.signature == WindowSwitcherHotKey.signature else {
                return OSStatus(eventNotHandledErr)
            }
            MainActor.assumeIsolated { WindowSwitcherHotKey.shared.onPress?() }
            return noErr
        }, 1, &spec, nil, &handler)
    }
}

/// 切换器弹出期间的键盘和鼠标：一个会话级事件监听（要辅助功能权限），只在弹出时打开，
/// 收起就关掉，平时不收任何事件。在主线程的 run loop 上回调。
///
/// 返回 true 的事件被吞掉，前台 App 收不到（Tab、W、打字这些）；修饰键变化和点击照常
/// 往下传。
@MainActor
final class SwitcherEventTap {
    static let shared = SwitcherEventTap()

    /// 弹出期间每个事件先交给它，返回要不要吞掉。
    var handler: (@MainActor (CGEventType, CGEvent) -> Bool)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var active = false

    private init() {}

    /// 打开监听。第一次时建，之后只是开关。没辅助功能权限时建不出来，返回 false。
    func start() -> Bool {
        if tap == nil { create() }
        guard let tap else { return false }
        active = true
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        active = false
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
    }

    private func create() {
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .rightMouseDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << CGEventMask($1.rawValue)) }
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, _ in
                let consumed: Bool = MainActor.assumeIsolated {
                    let me = SwitcherEventTap.shared
                    // 系统嫌回调太慢、或用户输入密码时会关掉监听，切换器还开着就再打开。
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        if let tap = me.tap, me.active { CGEvent.tapEnable(tap: tap, enable: true) }
                        return false
                    }
                    guard me.active else { return false }
                    return me.handler?(type, event) ?? false
                }
                return consumed ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: nil)
        else { return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: false)
        tap = port
        self.source = source
    }

    /// 事件里的修饰键换成 Carbon 的位（`KeyCombo.Modifier`）。
    static func modifiers(_ flags: CGEventFlags) -> UInt32 {
        KeyCombo.modifiers(control: flags.contains(.maskControl), option: flags.contains(.maskAlternate),
                           shift: flags.contains(.maskShift), command: flags.contains(.maskCommand))
    }

    /// 此刻按着的修饰键。
    static var currentModifiers: UInt32 {
        modifiers(CGEventSource.flagsState(.combinedSessionState))
    }
}
