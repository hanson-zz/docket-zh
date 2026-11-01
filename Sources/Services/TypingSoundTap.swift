import AppKit
import Carbon.HIToolbox
import CoreGraphics

// 打字音效的键盘监听：会话级、只听（listen-only）的事件监听，只订 keyDown。
//
// - 只听不拦：事件原样回到系统，不改、不吞，所以不需要辅助功能权限，只要「输入监控」。
// - 只看键码和是不是自动连发，不读字符、不记录、不存、不上传任何键入的内容。
// - 安全输入（密码框）开着时不出声；那时系统本来也不会把按键交给监听。
// - 跑在自己的线程和 run loop 上，主线程忙（设置窗口在画、扩展栏在动）时也不耽误出声。
// 写法同 MediaKeyTap.swift、QuickActions.swift 的 KeyboardBlocker，只是 options 为 listenOnly。

/// 输入监控权限（kTCCServiceListenEvent）。
enum TypingSoundPermission {
    static var granted: Bool { CGPreflightListenEventAccess() }

    /// 第一次调用会弹系统的授权框；之后（已经拒绝过）只能去系统设置里打开，所以顺手把那一页打开。
    @MainActor static func request() {
        if CGRequestListenEventAccess() { return }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// 键盘监听。`start` / `stop` 在主线程调；回调在监听线程上，只把键码交给 `TypingSoundEngine`。
@MainActor
final class TypingSoundTap {
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var thread: Thread?

    var isRunning: Bool { port != nil }

    /// 已经在听时直接返回 true。没有输入监控权限时系统不给建，返回 false。
    func start() -> Bool {
        if port != nil { return true }
        let mask = CGEventMask(1) << CGEventMask(CGEventType.keyDown.rawValue)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap,
                                           options: .listenOnly, eventsOfInterest: mask,
                                           callback: TypingSoundTapBridge.callback, userInfo: nil),
              let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else { return false }
        TypingSoundTapBridge.setPort(port)
        nonisolated(unsafe) let runSource = source
        let thread = Thread {
            let loop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(loop, runSource, .commonModes)
            TypingSoundTapBridge.setLoop(loop)
            CFRunLoopRun()
        }
        thread.name = "Dockling typing sounds"
        thread.qualityOfService = .userInteractive
        thread.start()
        CGEvent.tapEnable(tap: port, enable: true)
        self.port = port
        self.source = source
        self.thread = thread
        return true
    }

    /// 撤掉监听，让监听线程退出。App 退出、关掉打字音效、权限被撤销时调。
    func stop() {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        CFMachPortInvalidate(port)
        if let loop = TypingSoundTapBridge.takeLoop() {
            if let source { CFRunLoopRemoveSource(loop, source, .commonModes) }
            CFRunLoopStop(loop)
        }
        TypingSoundTapBridge.setPort(nil)
        self.port = nil
        source = nil
        thread = nil
    }

    /// 系统把监听停了（回调太慢、或权限刚被撤销）又没重新打开时是 false。
    var isEnabled: Bool { port.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }
}

/// C 回调什么都捕获不了，要用的放这里。端口和 run loop 由锁保护：主线程写，监听线程读。
enum TypingSoundTapBridge {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var port: CFMachPort?
    nonisolated(unsafe) private static var loop: CFRunLoop?

    static func setPort(_ value: CFMachPort?) {
        lock.lock(); defer { lock.unlock() }
        port = value
    }

    static func setLoop(_ value: CFRunLoop?) {
        lock.lock(); defer { lock.unlock() }
        loop = value
    }

    /// 取走监听线程的 run loop（停的时候用）。线程还没跑起来时等一小会儿。
    static func takeLoop() -> CFRunLoop? {
        for _ in 0..<50 {
            lock.lock()
            if let value = loop {
                loop = nil
                lock.unlock()
                return value
            }
            lock.unlock()
            usleep(2_000)
        }
        return nil
    }

    private static var currentPort: CFMachPort? {
        lock.lock(); defer { lock.unlock() }
        return port
    }

    nonisolated(unsafe) static let callback: CGEventTapCallBack = { _, type, event, _ in
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // 系统嫌回调慢把它停了：重新打开。权限被撤销时打不开，控制器的定时检查会收拾。
            if let port = TypingSoundTapBridge.currentPort { CGEvent.tapEnable(tap: port, enable: true) }
        case .keyDown:
            let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            TypingSoundEngine.shared.keyDown(keyCode: keyCode, isRepeat: isRepeat,
                                             secureInput: IsSecureEventInputEnabled())
        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }
}
