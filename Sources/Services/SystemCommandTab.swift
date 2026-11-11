import Darwin
import Dispatch
import Foundation
import os

/// 系统自带的 ⌘Tab、⌘⇧Tab（App 切换器）开关。打开「用 ⌘Tab 打开窗口切换器」时由码头关掉，
/// 码头自己注册 ⌘Tab；关开关、退出、收到 SIGTERM / SIGINT 时还原。
///
/// 系统没有公开接口，用的是 WindowServer 的 symbolic hotkey 开关（运行时按名字找，找不到就
/// 不接管，系统 ⌘Tab 照常）：1 是 ⌘Tab，2 是 ⌘⇧Tab，⌘` 不碰。关掉的状态记在 WindowServer
/// 里，码头崩了也不会自己回来，所以启动时没在接管就先还原一次。
enum SystemCommandTab {
    private typealias SetEnabled = @convention(c) (Int32, Bool) -> Int32

    /// 1：⌘Tab；2：⌘⇧Tab。
    private static let symbolicHotKeys: [Int32] = [1, 2]

    nonisolated(unsafe) private static let setEnabled: SetEnabled? = {
        if let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSSetSymbolicHotKeyEnabled") {
            return unsafeBitCast(symbol, to: SetEnabled.self)
        }
        let skylight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        if let skylight, let symbol = dlsym(skylight, "SLSSetSymbolicHotKeyEnabled") {
            return unsafeBitCast(symbol, to: SetEnabled.self)
        }
        return nil
    }()

    private struct State {
        /// 系统 ⌘Tab 现在是码头关掉的。
        var taken = false
        var handlersInstalled = false
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())

    /// 信号源要一直留着，不然收不到。只在 `installTerminationHandlers` 里写一次。
    nonisolated(unsafe) private static var signalSources: [any DispatchSourceSignal] = []

    /// 码头这会儿关着系统 ⌘Tab。
    static var isTaken: Bool { state.withLock { $0.taken } }

    /// 关掉系统 ⌘Tab、⌘⇧Tab。找不到开关或系统不让关时还原并返回 false，保持系统 ⌘Tab。
    @discardableResult
    static func takeOver() -> Bool {
        guard let setEnabled else {
            DockLog.error(.switcher, "Command-Tab takeover unavailable: symbolic hotkey switch not found")
            return false
        }
        installTerminationHandlers()
        if isTaken { return true }
        // 先记下来再关：关到一半收到信号也会还原。
        state.withLock { $0.taken = true }
        let results = symbolicHotKeys.map { setEnabled($0, false) }
        if results.contains(where: { $0 != 0 }) {
            DockLog.error(.switcher, "Command-Tab takeover refused by the system: \(results)")
            release()
            return false
        }
        return true
    }

    /// 还原系统 ⌘Tab（只在码头关掉过时动手，不和别的 App 抢）。任何线程都能调。
    static func release() {
        let wasTaken = state.withLock { s -> Bool in
            let was = s.taken
            s.taken = false
            return was
        }
        guard wasTaken else { return }
        enableSystem()
    }

    /// 启动时没在接管就调一次：上次崩溃没来得及还原的，这里补上。
    static func restoreAtLaunch() {
        state.withLock { $0.taken = false }
        enableSystem()
    }

    private static func enableSystem() {
        guard let setEnabled else { return }
        for key in symbolicHotKeys { _ = setEnabled(key, true) }
    }

    /// SIGTERM、SIGINT 时先还原再按系统默认的方式退出；正常 `exit` 走 atexit。
    /// 信号在单独的队列上处理，主线程卡住时也能还原。
    private static func installTerminationHandlers() {
        let first = state.withLock { s -> Bool in
            guard !s.handlersInstalled else { return false }
            s.handlersInstalled = true
            return true
        }
        guard first else { return }
        atexit { SystemCommandTab.release() }
        let queue = DispatchQueue(label: "docket.system-command-tab.signals")
        var sources: [any DispatchSourceSignal] = []
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: queue)
            source.setEventHandler {
                SystemCommandTab.release()
                signal(sig, SIG_DFL)
                kill(getpid(), sig)
            }
            source.resume()
            sources.append(source)
        }
        signalSources = sources
    }
}
