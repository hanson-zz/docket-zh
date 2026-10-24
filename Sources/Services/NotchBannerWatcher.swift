import AppKit
import ApplicationServices

/// 消息灵动岛的来源：用辅助功能观察「通知中心」进程里的通知横幅。
///
/// 只读不改：不拦截、不关掉、不改系统通知，只在横幅出现、排版变化时读一遍那一小棵
/// AX 树，抄成 `NotchBannerNode` 交给 Core 的 `NotchBannerParser` 解析。横幅的结构不是
/// 公开接口：读不到、认不出就什么都不报，绝不崩溃。macOS 26 上第一条横幅出现时是
/// AXWindowCreated，后面追加进同一个窗口的只有 AXLayoutChanged，所以几种都听。
///
/// 读 AX 在后台串行队列上做（每个元素最多等 `timeout` 秒），结果回主线程。没给
/// 辅助功能权限时不做事，每隔几秒看一眼权限，给了就自动开始。
@MainActor
final class NotchBannerWatcher {
    /// 读到的一条新消息（还没去重），带能替用户点一下的横幅元素。
    struct Found: @unchecked Sendable {
        var incoming: NotchIncoming
        /// 横幅元素；一摞的、找不回的为 nil。只在主线程用来 AXPress。
        var element: AXUIElement?
    }

    /// 读到横幅时调用（主线程）。`priming` 为 true 时是刚开始观察时屏幕上已经有的，
    /// 只该记下来不弹。
    var onFound: ((_ found: [Found], _ priming: Bool) -> Void)?

    private(set) var isRunning = false
    private var enabled: [NotchMessageApp] = []
    private var observer: AXObserver?
    private var appElement: AXUIElement?
    private var observedPID: pid_t = 0
    private var observedWindows: [AXUIElement] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var trustTimer: Timer?
    private var scanPending = false
    private var scanGeneration = 0

    private nonisolated static let queue = DispatchQueue(label: "com.docket-zh.notch-message.ax", qos: .userInitiated)
    /// 每个 AX 元素最多等多久。
    private nonisolated static let timeout: Float = 0.2
    /// 一次读最多花多久，通知中心卡住时不让后台队列越积越多。
    private nonisolated static let readBudget: TimeInterval = 1.5
    /// 一次最多读多少个元素、多深，防一个反常的树。
    private nonisolated static let maxNodes = 400
    private nonisolated static let maxDepth = NotchBannerParser.maxDepth
    /// 事件来了等一小会儿再读，几个事件并成一次。
    private static let debounce: Duration = .milliseconds(120)

    private static let events: [String] = [
        kAXWindowCreatedNotification as String, "AXLayoutChanged",
        kAXCreatedNotification as String, kAXUIElementDestroyedNotification as String,
    ]

    func start(apps: [NotchMessageApp]) {
        enabled = apps
        guard !isRunning else { return }
        isRunning = true
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard app?.bundleIdentifier == NotchBannerParser.notificationCenterBundleID else { return }
                MainActor.assumeIsolated { self?.attach() }
            })
        }
        attach()
    }

    func update(apps: [NotchMessageApp]) { enabled = apps }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        detach()
        trustTimer?.invalidate()
        trustTimer = nil
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(workspace.removeObserver)
        workspaceObservers.removeAll()
    }

    // MARK: 接上通知中心

    private func attach() {
        detach()
        guard isRunning else { return }
        guard AXIsProcessTrusted() else {
            waitForTrust()
            return
        }
        trustTimer?.invalidate()
        trustTimer = nil
        guard let process = NSRunningApplication.runningApplications(
            withBundleIdentifier: NotchBannerParser.notificationCenterBundleID).first else { return }
        let pid = process.processIdentifier
        var created: AXObserver?
        guard AXObserverCreate(pid, notchBannerObserverCallback, &created) == .success, let created else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, Self.timeout)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for event in Self.events {
            AXObserverAddNotification(created, app, event as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        observer = created
        appElement = app
        observedPID = pid
        scan(priming: true)
    }

    private func detach() {
        if let observer, let appElement {
            for event in Self.events {
                AXObserverRemoveNotification(observer, appElement, event as CFString)
            }
            for window in observedWindows {
                for event in Self.events { AXObserverRemoveNotification(observer, window, event as CFString) }
            }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        appElement = nil
        observedWindows = []
        observedPID = 0
    }

    /// 没权限时每 5 秒看一眼，给了就接上。
    private func waitForTrust() {
        guard trustTimer == nil else { return }
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isRunning, AXIsProcessTrusted() else { return }
                self.attach()
            }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        trustTimer = timer
    }

    /// 新窗口也挂上同样的事件：追加进已有窗口的横幅只在窗口上报 AXLayoutChanged。
    private func observeWindows(_ windows: [AXUIElement]) {
        guard let observer else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for window in windows where !observedWindows.contains(where: { CFEqual($0, window) }) {
            for event in Self.events {
                AXObserverAddNotification(observer, window, event as CFString, refcon)
            }
            observedWindows.append(window)
        }
        // 不在了的窗口去掉，免得越积越多。
        observedWindows.removeAll { old in !windows.contains { CFEqual($0, old) } }
    }

    // MARK: 读

    fileprivate func scheduleScan() {
        guard isRunning, !scanPending else { return }
        scanPending = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard let self else { return }
            self.scanPending = false
            self.scan(priming: false)
        }
    }

    private struct Box: @unchecked Sendable { var element: AXUIElement }

    /// 读到的一个窗口：Core 用的快照，和同样形状的元素树（按位置找回横幅元素）。
    private final class ElementTree: @unchecked Sendable {
        let element: AXUIElement
        var children: [ElementTree] = []
        init(_ element: AXUIElement) { self.element = element }
    }

    private struct ScanResult: @unchecked Sendable {
        var windows: [AXUIElement]
        var found: [Found]
    }

    private func scan(priming: Bool) {
        guard isRunning, let appElement else { return }
        scanGeneration += 1
        let generation = scanGeneration
        let app = Box(element: appElement)
        let apps = enabled
        Self.queue.async {
            let result = Self.read(app: app.element, enabled: apps)
            Task { @MainActor [weak self] in
                guard let self, self.isRunning, self.scanGeneration == generation else { return }
                self.observeWindows(result.windows)
                guard !result.found.isEmpty else { return }
                self.onFound?(result.found, priming)
            }
        }
    }

    /// 在后台队列上读通知中心的所有窗口。任何一步读不到都当没有。
    private nonisolated static func read(app: AXUIElement, enabled: [NotchMessageApp]) -> ScanResult {
        var windows: [AXUIElement] = []
        if let list = copy(app, kAXWindowsAttribute) as? [AXUIElement] { windows = list }
        if windows.isEmpty, let children = copy(app, kAXChildrenAttribute) as? [AXUIElement] {
            windows = children.filter { (copy($0, kAXRoleAttribute) as? String) == (kAXWindowRole as String) }
        }
        var found: [Found] = []
        var budget = maxNodes
        let deadline = Date().addingTimeInterval(readBudget)
        for window in windows {
            let tree = ElementTree(window)
            let snapshot = node(window, tree: tree, depth: 0, budget: &budget, deadline: deadline)
            for located in NotchBannerParser.located(incomingIn: snapshot, enabled: enabled) {
                var element: AXUIElement?
                if located.pressable {
                    var walk: ElementTree? = tree
                    for index in located.path {
                        guard let current = walk, index < current.children.count else { walk = nil; break }
                        walk = current.children[index]
                    }
                    element = walk?.element
                }
                found.append(Found(incoming: located.incoming, element: element))
            }
            if budget <= 0 || Date() >= deadline { break }
        }
        return ScanResult(windows: windows, found: found)
    }

    private nonisolated static func node(_ element: AXUIElement, tree: ElementTree, depth: Int,
                                         budget: inout Int, deadline: Date) -> NotchBannerNode {
        budget -= 1
        AXUIElementSetMessagingTimeout(element, timeout)
        var result = NotchBannerNode(role: string(element, kAXRoleAttribute),
                                     subrole: string(element, kAXSubroleAttribute),
                                     identifier: string(element, "AXIdentifier"),
                                     description: string(element, kAXDescriptionAttribute),
                                     title: string(element, kAXTitleAttribute),
                                     value: string(element, kAXValueAttribute))
        guard depth < maxDepth, budget > 0, Date() < deadline,
              let children = copy(element, kAXChildrenAttribute) as? [AXUIElement] else { return result }
        for child in children {
            guard budget > 0 else { break }
            let sub = ElementTree(child)
            tree.children.append(sub)
            result.children.append(node(child, tree: sub, depth: depth + 1, budget: &budget, deadline: deadline))
        }
        return result
    }

    private nonisolated static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private nonisolated static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        guard let raw = copy(element, attribute) else { return nil }
        if let text = raw as? String { return text }
        if let attributed = raw as? NSAttributedString { return attributed.string }
        return nil
    }

    // MARK: 替用户点一下横幅

    /// 点「打开」时先替用户点那条横幅（系统会打开 App 并定位到那个聊天）；横幅已经
    /// 消失、点不了时返回 false，由调用方直接打开 App。
    static func press(_ element: AXUIElement?) -> Bool {
        guard let element, AXIsProcessTrusted() else { return false }
        AXUIElementSetMessagingTimeout(element, timeout)
        return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }
}

/// AX 事件的回调（C 函数指针，不能带上下文）：`refcon` 是观察者自己。事件源挂在主线程
/// 的 run loop 上，所以回调在主线程。
private func notchBannerObserverCallback(_ observer: AXObserver, _ element: AXUIElement,
                                         _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let watcher = Unmanaged<NotchBannerWatcher>.fromOpaque(refcon).takeUnretainedValue()
    MainActor.assumeIsolated { watcher.scheduleScan() }
}
