import AppKit
import ApplicationServices

/// 消息灵动岛的来源：用辅助功能观察「通知中心」进程里的通知横幅。
///
/// 只读不改：不拦截、不关掉、不改系统通知，只在横幅出现、排版变化时读一遍那一小棵
/// AX 树，抄成 `NotchBannerNode` 交给 Core 的 `NotchBannerParser` 解析。横幅的结构不是
/// 公开接口：读不到、认不出就什么都不报，绝不崩溃。macOS 26 上第一条横幅出现时是
/// AXWindowCreated，后面追加进同一个窗口的只有 AXLayoutChanged，所以几种都听。
///
/// 读 AX 在后台串行队列上做（每个元素最多等 `timeout` 秒），结果回主线程。
///
/// 每 `healthInterval` 秒看一次：辅助功能权限（没给时不做事，给了就自动接上，中途被收回
/// 就断开）；通知中心进程换没换（它是后台进程，NSWorkspace 不发它的启动、退出通知，
/// 重启后 pid 变了要重新挂观察器）；通知中心的窗口有没有变（万一这个版本的系统不报
/// AXWindowCreated，靠这个兜底读一遍）。读到的情况写进 `NotchMessageStatus`，设置里的
/// 状态几行就是看它。
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
    private var healthTimer: Timer?
    private var scanPending = false
    private var scanGeneration = 0
    /// 后台队列上还没读完的扫描数。读的时候 `observedWindows` 还是旧的，这时轮询比对
    /// 会误以为窗口变了、再排一次扫描，所以有扫描在读就不轮询。
    private var scansInFlight = 0
    private var polling = false
    /// 设置里「发一条测试通知」的暗号，读到带它的横幅就当测试消息报上去。
    var probeToken: String?

    private nonisolated static let queue = DispatchQueue(label: "com.docket-zh.notch-message.ax", qos: .userInitiated)
    /// 每个 AX 元素最多等多久。
    private nonisolated static let timeout: Float = 0.2
    /// 一次读最多花多久，通知中心卡住时不让后台队列越积越多。
    private nonisolated static let readBudget: TimeInterval = 2.5
    /// 每个窗口最多读多少个元素、多深，防一个反常的树。按窗口算：通知中心进程里还挂着
    /// 桌面小组件的窗口，以前几个窗口合用 400 个，小组件排在前面时轮不到横幅那个窗口。
    private nonisolated static let maxNodesPerWindow = 600
    private nonisolated static let maxDepth = NotchBannerParser.maxDepth
    /// 事件来了等一小会儿再读，几个事件并成一次。
    private static let debounce: Duration = .milliseconds(120)
    /// 多久看一次权限、通知中心进程和窗口。
    private static let healthInterval: TimeInterval = 2

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
        startHealthTimer()
    }

    func update(apps: [NotchMessageApp]) { enabled = apps }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        detach()
        healthTimer?.invalidate()
        healthTimer = nil
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(workspace.removeObserver)
        workspaceObservers.removeAll()
    }

    // MARK: 接上通知中心

    /// 通知中心现在的进程（退出了的不算）。
    private static func notificationCenterPID() -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: NotchBannerParser.notificationCenterBundleID)
            .first { !$0.isTerminated }?.processIdentifier
    }

    private func attach() {
        detach()
        guard isRunning else { return }
        let status = NotchMessageStatus.shared
        let trusted = AXIsProcessTrusted()
        status.updateTrust(trusted)
        guard trusted else { return }
        guard let pid = Self.notificationCenterPID() else {
            status.setNotificationCenterRunning(false)
            return
        }
        status.setNotificationCenterRunning(true)
        var created: AXObserver?
        guard AXObserverCreate(pid, notchBannerObserverCallback, &created) == .success, let created else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, Self.timeout)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var registered = 0
        for event in Self.events {
            let result = AXObserverAddNotification(created, app, event as CFString, refcon)
            if result == .success || result == .notificationAlreadyRegistered { registered += 1 }
        }
        // 一个都没挂上（权限其实没生效、进程正在退出）：不留半截观察器，下一轮再试。
        guard registered > 0 else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
        observer = created
        appElement = app
        observedPID = pid
        status.setConnected(true)
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
        // 断开前已经在后台读的那次作废：结果属于旧的进程和窗口，不能再报上来、挂观察器。
        scanGeneration += 1
        NotchMessageStatus.shared.setConnected(false)
    }

    private func startHealthTimer() {
        guard healthTimer == nil else { return }
        let timer = Timer(timeInterval: Self.healthInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkHealth() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        healthTimer = timer
    }

    /// 定时看一眼：权限给了或收回、通知中心重启（pid 变了）都重新接；接着的时候看窗口变没变。
    private func checkHealth() {
        guard isRunning else { return }
        let status = NotchMessageStatus.shared
        let trusted = AXIsProcessTrusted()
        status.updateTrust(trusted)
        guard trusted else {
            if observer != nil { detach() }
            return
        }
        guard let pid = Self.notificationCenterPID() else {
            status.setNotificationCenterRunning(false)
            if observer != nil { detach() }
            return
        }
        status.setNotificationCenterRunning(true)
        guard observer != nil, pid == observedPID else {
            attach()
            return
        }
        pollWindows()
    }

    /// 兜底：通知中心的窗口和上次读到的不一样（多了、少了、换了）就读一遍，不靠 AX 事件。
    private func pollWindows() {
        guard !polling, !scanPending, scansInFlight == 0, let appElement else { return }
        polling = true
        let app = Box(element: appElement)
        let known = observedWindows.map { Box(element: $0) }
        Self.queue.async {
            let windows = Self.windows(of: app.element)
            let changed = windows.count != known.count
                || windows.contains { window in !known.contains { CFEqual($0.element, window) } }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.polling = false
                if changed { self.scheduleScan() }
            }
        }
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
        // 不在了的窗口去掉（连同挂在上面的事件），免得越积越多。
        let gone = observedWindows.filter { old in !windows.contains { CFEqual($0, old) } }
        for window in gone {
            for event in Self.events { AXObserverRemoveNotification(observer, window, event as CFString) }
        }
        observedWindows.removeAll { old in gone.contains { CFEqual($0, old) } }
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
        /// 读到几条横幅（不管哪个 App），和第一条上的 App 名，给设置里的自查用。
        var bannerCount = 0
        var bannerApp: String?
        /// 每个窗口的结构摘要（不含消息内容），设置里「复制诊断信息」用。
        var report: String = ""
    }

    private func scan(priming: Bool) {
        guard isRunning, let appElement else { return }
        scanGeneration += 1
        let generation = scanGeneration
        let app = Box(element: appElement)
        let apps = enabled
        let token = probeToken
        scansInFlight += 1
        Self.queue.async {
            let result = Self.read(app: app.element, enabled: apps, probeToken: token)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.scansInFlight = max(0, self.scansInFlight - 1)
                guard self.isRunning, self.scanGeneration == generation else { return }
                self.observeWindows(result.windows)
                NotchMessageStatus.shared.recordScan(result.report, windows: result.windows.count, banners: result.bannerCount)
                if result.bannerCount > 0 { NotchMessageStatus.shared.sawBanner(app: result.bannerApp) }
                guard !result.found.isEmpty else { return }
                self.onFound?(result.found, priming)
            }
        }
    }

    /// 通知中心的窗口：先读 AXWindows，读不到时从孩子里挑窗口。
    private nonisolated static func windows(of app: AXUIElement) -> [AXUIElement] {
        if let list = copy(app, kAXWindowsAttribute) as? [AXUIElement], !list.isEmpty { return list }
        guard let children = copy(app, kAXChildrenAttribute) as? [AXUIElement] else { return [] }
        return children.filter { (copy($0, kAXRoleAttribute) as? String) == (kAXWindowRole as String) }
    }

    /// 在后台队列上读通知中心的所有窗口。任何一步读不到都当没有。
    private nonisolated static func read(app: AXUIElement, enabled: [NotchMessageApp],
                                         probeToken: String?) -> ScanResult {
        let windows = windows(of: app)
        var result = ScanResult(windows: windows, found: [])
        let deadline = Date().addingTimeInterval(readBudget)
        // 横幅所在的窗口（macOS 26 上是 AXSystemDialog「通知中心」）先读，桌面小组件的窗口后读。
        let dialogs = windows.filter { string($0, kAXSubroleAttribute) == "AXSystemDialog" }
        let ordered = dialogs + windows.filter { window in !dialogs.contains { CFEqual($0, window) } }
        var reports: [String] = []
        for window in ordered {
            guard Date() < deadline else {
                reports.append("window skipped: out of time")
                break
            }
            let tree = ElementTree(window)
            var budget = maxNodesPerWindow
            let snapshot = node(window, tree: tree, depth: 0, budget: &budget, deadline: deadline)
            reports.append(NotchBannerParser.report(snapshot, enabled: enabled, probeToken: probeToken)
                           + (budget <= 0 ? "\n  (node budget used up)" : ""))
            for entry in NotchBannerParser.located(in: snapshot) {
                result.bannerCount += 1
                if result.bannerApp == nil { result.bannerApp = NotchBannerParser.appLabel(entry.banner) }
                var incoming = NotchBannerParser.incoming(entry.banner, enabled: enabled)
                if incoming == nil, let probeToken {
                    incoming = NotchMessageProbe.incoming(entry.banner, token: probeToken)
                }
                guard let incoming else { continue }
                var element: AXUIElement?
                if !entry.banner.stacked {
                    var walk: ElementTree? = tree
                    for index in entry.path {
                        guard let current = walk, index < current.children.count else { walk = nil; break }
                        walk = current.children[index]
                    }
                    element = walk?.element
                }
                result.found.append(Found(incoming: incoming, element: element))
            }
        }
        result.report = reports.joined(separator: "\n")
        return result
    }

    private nonisolated static func node(_ element: AXUIElement, tree: ElementTree, depth: Int,
                                         budget: inout Int, deadline: Date) -> NotchBannerNode {
        budget -= 1
        AXUIElementSetMessagingTimeout(element, timeout)
        // 六个属性和孩子一次读回来（一次跨进程），比一个一个读快得多。
        let values = multiple(element, nodeAttributes)
        var result = NotchBannerNode(role: values[0] as? String,
                                     subrole: values[1] as? String,
                                     identifier: values[2] as? String,
                                     description: text(values[3]),
                                     title: text(values[4]),
                                     value: text(values[5]))
        // 桌面小组件不往里读。
        guard !NotchBannerParser.isDesktopWidget(identifier: result.identifier) else { return result }
        guard depth < maxDepth, budget > 0, Date() < deadline,
              let children = values[6] as? [AXUIElement] else { return result }
        for child in children {
            guard budget > 0 else { break }
            let sub = ElementTree(child)
            tree.children.append(sub)
            result.children.append(node(child, tree: sub, depth: depth + 1, budget: &budget, deadline: deadline))
        }
        return result
    }

    private nonisolated static let nodeAttributes: [String] = [
        kAXRoleAttribute, kAXSubroleAttribute, "AXIdentifier", kAXDescriptionAttribute,
        kAXTitleAttribute, kAXValueAttribute, kAXChildrenAttribute,
    ]

    /// 一次读几个属性，读不到的位置是 nil（不会因为一个属性不支持整个失败）。
    private nonisolated static func multiple(_ element: AXUIElement, _ attributes: [String]) -> [Any?] {
        var raw: CFArray?
        let names = attributes as CFArray
        guard AXUIElementCopyMultipleAttributeValues(element, names, [], &raw) == .success,
              let list = raw as? [AnyObject], list.count == attributes.count else {
            return attributes.map { copy(element, $0) as Any? }
        }
        // 读不到的那一项是一个 AXValue 包着的错误码，当没有。
        return list.map { item -> Any? in
            if CFGetTypeID(item) == AXValueGetTypeID(),
               AXValueGetType(unsafeBitCast(item, to: AXValue.self)) == .axError { return nil }
            return item
        }
    }

    private nonisolated static func text(_ raw: Any?) -> String? {
        if let text = raw as? String { return text }
        if let attributed = raw as? NSAttributedString { return attributed.string }
        return nil
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
