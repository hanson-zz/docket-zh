import AppKit
import ApplicationServices

/// 消息灵动岛的来源：用辅助功能观察「通知中心」进程里的通知横幅。
///
/// 只读：不拦截、不改系统通知，只在横幅出现、排版变化时读一遍那一小棵 AX 树，抄成
/// `NotchBannerNode` 交给 Core 的 `NotchBannerParser` 解析。唯一的例外是用户在设置里
/// 打开了「卡片弹出后关掉系统横幅」：卡片展开后执行横幅自己带的「关闭」动作或按它的
/// 关闭按钮（`close(_:)`），和用户自己点横幅上的关闭一样，横幅没有这两样时什么都不做。横幅的结构不是
/// 公开接口：读不到、认不出就什么都不报，绝不崩溃。macOS 26 上第一条横幅出现时是
/// AXWindowCreated，后面追加进同一个窗口的只有 AXLayoutChanged，所以几种都听。事件来了
/// 先等一小会儿读一遍，再过一会儿补读一遍（横幅刚出现时字可能还没填上）。
///
/// 读 AX 在后台串行队列上做（每个元素最多等 `timeout` 秒），结果回主线程。
///
/// 每 `healthInterval` 秒看一次：辅助功能权限（没给时不做事，给了就自动接上，中途被收回
/// 就断开）；通知中心进程换没换（它是后台进程，NSWorkspace 不发它的启动、退出通知，
/// 重启后 pid 变了要重新挂观察器）；通知中心的窗口和窗口里的横幅有没有变（macOS 27 上
/// 横幅所在的窗口一直开着、里面还挂着小组件层，新横幅加进去时窗口不变，系统也未必报事件，
/// 所以除了比窗口，还轻读一遍各窗口里横幅元素的标识和辅助说明长度，变了就读一遍）。读到的情况写进 `NotchMessageStatus`，设置里的
/// 状态几行就是看它。
@MainActor
final class NotchBannerWatcher {
    /// 读到的一条新消息（还没去重），带能替用户点一下的横幅元素。
    struct Found: @unchecked Sendable {
        var incoming: NotchIncoming
        /// 横幅元素；一摞的、找不回的为 nil。只在主线程用来 AXPress。
        var element: AXUIElement?
        /// 关掉这条横幅的办法；横幅没有「关闭」动作或关闭按钮时为 nil。
        var close: CloseHandle?
    }

    /// 关横幅：对哪个元素执行哪个动作（「关闭」动作原样的名字，或按钮的 AXPress）。
    struct CloseHandle: @unchecked Sendable {
        var element: AXUIElement
        var action: String
    }

    /// 读到横幅时调用（主线程）。`priming` 为 true 时是刚开始观察时屏幕上已经有的，
    /// 只该记下来不弹。
    var onFound: ((_ found: [Found], _ priming: Bool) -> Void)?

    private(set) var isRunning = false
    private var enabled: [NotchMessageApp] = []
    /// 认 App 名的名字表：内置的加上从装着的 App 包里读到的本地化显示名。
    private var names = NotchAppNames.builtIn
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
    var probeToken: String? {
        didSet {
            guard let probeToken, !recentProbeTokens.contains(probeToken) else { return }
            recentProbeTokens.append(probeToken)
            if recentProbeTokens.count > 3 { recentProbeTokens.removeFirst() }
        }
    }
    /// 最近发过的几个暗号：测试横幅读到以后暗号就清掉了，横幅还会在屏幕上停几秒，
    /// 诊断里靠这个仍把它记成测试横幅，不混进真实横幅的记录。
    private var recentProbeTokens: [String] = []
    /// 上一次轻读到的横幅摘要（各窗口里横幅元素的标识和辅助说明长度），nil 是还没读过。
    private var lastSignature: [String]?
    private var followUpPending = false
    private var pendingTrigger: NotchScanTrigger = .event
    /// 最近 20 秒程序坞角标的记录（每秒一次，横幅出现时再立刻读一次）。
    private var dockHistory = NotchDockBadgeHistory()
    private var dockSampling = false
    /// 见过的横幅（按 `identityKey`）：第一次读到的时间、认成了哪个 App、是否已经排过
    /// 角标补读。认角标时拿第一次读到的时间比，别的横幅认走的个数从涨幅里扣掉。
    private var seenBanners: [String: NotchSeenBanner] = [:]
    /// 有认不出的横幅在等角标时，到这个时间为止，每秒记角标发现涨了就再读一遍横幅。
    private var dockPendingUntil: Date?

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
    /// 事件之后再补读一遍的时间（横幅刚出现时字可能还没填上）。
    private static let followUp: Duration = .milliseconds(900)
    /// 多久看一次权限、通知中心进程、窗口和窗口里的横幅。横幅只停五秒左右，两秒一看
    /// 可能只赶上尾巴，所以一秒一看；轻读只读几个属性，不读字。
    private static let healthInterval: TimeInterval = 1
    /// 轻读最多看多少个元素。
    private nonisolated static let signatureBudget = 160

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
        reloadNames()
    }

    func update(apps: [NotchMessageApp]) { enabled = apps }

    /// 在后台读一遍装着的 App 的显示名（开始观察时；微信更新后重新打开灵动岛就会读到新名字）。
    func reloadNames() {
        Self.queue.async {
            let loaded = NotchAppNameCatalog.load()
            Task { @MainActor [weak self] in
                self?.names = loaded
                NotchMessageStatus.shared.recordNames(loaded.summary)
            }
        }
    }

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
        lastSignature = nil
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
        sampleDock()
    }

    /// 每秒记一次程序坞角标（只读三个 App 那一项的角标）。有认不出的横幅在等、角标刚涨了，
    /// 就再读一遍横幅。
    private func sampleDock() {
        guard !dockSampling, !enabled.isEmpty else { return }
        dockSampling = true
        NotchDockBadgeReader.queue.async {
            let sample = NotchDockBadgeReader.shared.sample()
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.dockSampling = false
                guard self.isRunning, let sample else { return }
                self.dockHistory.append(sample)
                NotchMessageStatus.shared.recordDockSample(sample)
                if self.dockHistory.lastStepRose, let until = self.dockPendingUntil, sample.at <= until {
                    self.scheduleScan(.dockRecheck)
                }
            }
        }
    }

    /// 兜底，不靠 AX 事件：通知中心的窗口和上次读到的不一样（多了、少了、换了），或者窗口
    /// 里横幅元素的标识、辅助说明长度变了（一直开着的窗口里加了一条横幅），就读一遍。
    private func pollWindows() {
        guard let appElement else { return }
        guard !polling, !scanPending, scansInFlight == 0 else {
            NotchMessageStatus.shared.recordPoll(skipped: true)
            return
        }
        polling = true
        let app = Box(element: appElement)
        let known = observedWindows.map { Box(element: $0) }
        let previous = lastSignature
        Self.queue.async {
            let windows = Self.windows(of: app.element)
            let windowsChanged = windows.count != known.count
                || windows.contains { window in !known.contains { CFEqual($0.element, window) } }
            // 横幅所在的窗口先读；每个窗口单独算预算，小组件窗口排在前面时也轮得到横幅那个窗口。
            let dialogs = windows.filter { Self.string($0, kAXSubroleAttribute) == "AXSystemDialog" }
            let ordered = dialogs + windows.filter { window in !dialogs.contains { CFEqual($0, window) } }
            var signature: [String] = []
            for window in ordered.prefix(12) {
                var budget = Self.signatureBudget
                Self.signature(window, depth: 0, budget: &budget, into: &signature)
            }
            let bannersChanged = previous != nil && previous != signature
            let entries = signature.count
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.polling = false
                self.lastSignature = signature
                let changed = windowsChanged || bannersChanged
                NotchMessageStatus.shared.recordPoll(skipped: false, changed: changed, banners: entries)
                if changed { self.scheduleScan(.poll) }
            }
        }
    }

    /// 轻读：只认横幅元素，记下它的标识和辅助说明的长度（不读字的内容），桌面小组件不往里走。
    private nonisolated static func signature(_ element: AXUIElement, depth: Int, budget: inout Int,
                                              into parts: inout [String]) {
        budget -= 1
        AXUIElementSetMessagingTimeout(element, timeout)
        let values = multiple(element, [kAXSubroleAttribute, "AXIdentifier", kAXChildrenAttribute])
        let subrole = values[0] as? String
        let identifier = values[1] as? String
        guard !NotchBannerParser.isDesktopWidget(identifier: identifier) else { return }
        if let subrole, NotchBannerParser.bannerSubroles.contains(subrole) {
            let length = string(element, kAXDescriptionAttribute)?.count ?? -1
            parts.append("\(subrole):\(identifier ?? "-"):\(length)")
            // 一摞里面的单条也算；单条横幅里面不再往下读。
            guard subrole == "AXNotificationCenterAlertStack" else { return }
        }
        guard depth < maxDepth, budget > 0, let children = values[2] as? [AXUIElement] else { return }
        for child in children {
            guard budget > 0 else { break }
            signature(child, depth: depth + 1, budget: &budget, into: &parts)
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

    /// AX 事件来了（主线程）：记个数，等一小会儿读一遍，再过一会儿补读一遍。
    fileprivate func axEvent(_ name: String) {
        guard isRunning else { return }
        NotchMessageStatus.shared.recordEvent(name)
        scheduleScan(.event)
        scheduleFollowUp()
    }

    private func scheduleScan(_ trigger: NotchScanTrigger) {
        guard isRunning, !scanPending else { return }
        scanPending = true
        pendingTrigger = trigger
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard let self else { return }
            self.scanPending = false
            self.scan(priming: false, trigger: self.pendingTrigger)
        }
    }

    /// 事件之后补读一遍：有的横幅先出现一个空壳、字随后才填上，第一遍读到的是空的。
    private func scheduleFollowUp() {
        guard isRunning, !followUpPending else { return }
        followUpPending = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.followUp)
            guard let self else { return }
            self.followUpPending = false
            guard self.isRunning, !self.scanPending else { return }
            self.scan(priming: false, trigger: .followUp)
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
        /// 每条横幅的分析记录（不含消息内容）和认它用的键。
        var analyses: [(key: String, analysis: NotchBannerAnalysis)] = []
        /// 这次读横幅时立刻读的程序坞角标。
        var dockSample: NotchDockSample?
        /// 这次读到的每条横幅（第一次读到的时间、认成的 App）。
        var seen: [String: NotchSeenBanner] = [:]
        /// 认不出 App、要等角标再读的横幅。
        var unresolved: [String] = []
    }

    private func scan(priming: Bool, trigger: NotchScanTrigger = .priming) {
        guard isRunning, let appElement else { return }
        scanGeneration += 1
        let generation = scanGeneration
        let app = Box(element: appElement)
        let apps = enabled
        let token = probeToken
        let tokens = recentProbeTokens
        let table = names
        let history = dockHistory
        let seen = seenBanners
        scansInFlight += 1
        Self.queue.async {
            let result = Self.read(app: app.element, enabled: apps, probeToken: token, testTokens: tokens, names: table,
                                   dock: history, seen: seen, now: Date())
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.scansInFlight = max(0, self.scansInFlight - 1)
                guard self.isRunning, self.scanGeneration == generation else { return }
                self.observeWindows(result.windows)
                self.absorbDock(result, priming: priming)
                let status = NotchMessageStatus.shared
                let realBanners = result.analyses.filter { $0.analysis.outcome != .test }.count
                status.recordScan(result.report, windows: result.windows.count, banners: result.bannerCount,
                                  realBanners: realBanners, trigger: priming ? .priming : trigger)
                status.recordBanners(result.analyses.map { item in
                    var analysis = item.analysis
                    analysis.priming = priming
                    return (key: item.key, analysis: analysis)
                })
                if result.bannerCount > 0 { status.sawBanner(app: result.bannerApp) }
                guard !result.found.isEmpty else { return }
                self.onFound?(result.found, priming)
            }
        }
    }

    /// 一次读完后：记下立刻读的角标和见过的横幅；有新的认不出的横幅时，0.5 秒、1.5 秒后各补读
    /// 一遍（那时角标多半已经涨了），并在之后 3 秒里每秒记角标时盯着涨没涨。
    private func absorbDock(_ result: ScanResult, priming: Bool) {
        if let sample = result.dockSample {
            dockHistory.append(sample)
            NotchMessageStatus.shared.recordDockSample(sample)
        }
        let now = Date()
        for (key, seen) in result.seen {
            var merged = seen
            merged.rechecked = seenBanners[key]?.rechecked ?? false
            seenBanners[key] = merged
        }
        seenBanners = seenBanners.filter { now.timeIntervalSince($0.value.at) < 60 }
        guard !priming else { return }
        var schedule = false
        for key in result.unresolved {
            guard var seen = seenBanners[key], !seen.rechecked,
                  now.timeIntervalSince(seen.at) <= NotchDockBadgeHistory.window else { continue }
            seen.rechecked = true
            seenBanners[key] = seen
            schedule = true
            let until = seen.at.addingTimeInterval(NotchDockBadgeHistory.window)
            dockPendingUntil = max(dockPendingUntil ?? until, until)
        }
        guard schedule else { return }
        for delay in Self.dockRechecks {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: delay)
                guard let self, self.isRunning, !self.scanPending else { return }
                self.scan(priming: false, trigger: .dockRecheck)
            }
        }
    }

    /// 认不出的横幅出现后什么时候补读角标。
    private static let dockRechecks: [Duration] = [.milliseconds(500), .milliseconds(1500)]

    /// 通知中心的窗口：先读 AXWindows，读不到时从孩子里挑窗口。
    private nonisolated static func windows(of app: AXUIElement) -> [AXUIElement] {
        if let list = copy(app, kAXWindowsAttribute) as? [AXUIElement], !list.isEmpty { return list }
        guard let children = copy(app, kAXChildrenAttribute) as? [AXUIElement] else { return [] }
        return children.filter { (copy($0, kAXRoleAttribute) as? String) == (kAXWindowRole as String) }
    }

    /// 在后台队列上读通知中心的所有窗口。任何一步读不到都当没有。
    private nonisolated static func read(app: AXUIElement, enabled: [NotchMessageApp],
                                         probeToken: String?, testTokens: [String],
                                         names: NotchAppNames, dock: NotchDockBadgeHistory,
                                         seen: [String: NotchSeenBanner], now: Date) -> ScanResult {
        let windows = windows(of: app)
        var result = ScanResult(windows: windows, found: [])
        let deadline = Date().addingTimeInterval(readBudget)
        // 横幅所在的窗口（macOS 26 上是 AXSystemDialog「通知中心」）先读，桌面小组件的窗口后读。
        let dialogs = windows.filter { string($0, kAXSubroleAttribute) == "AXSystemDialog" }
        let ordered = dialogs + windows.filter { window in !dialogs.contains { CFEqual($0, window) } }
        var reports: [String] = []
        // 程序坞角标只在有认不出的横幅时立刻读一次，和每秒的记录合在一起比。
        var history = dock
        var dockRead = false
        let allTokens = [probeToken].compactMap { $0 } + testTokens
        for window in ordered {
            guard Date() < deadline else {
                reports.append("window skipped: out of time")
                break
            }
            let tree = ElementTree(window)
            var budget = maxNodesPerWindow
            let snapshot = node(window, tree: tree, depth: 0, budget: &budget, deadline: deadline)
            reports.append(NotchBannerParser.report(snapshot, enabled: enabled, probeToken: probeToken,
                                                    testTokens: testTokens, names: names)
                           + (budget <= 0 ? "\n  (node budget used up)" : ""))
            for entry in NotchBannerParser.located(in: snapshot) {
                result.bannerCount += 1
                let banner = entry.banner
                let key = NotchBannerParser.identityKey(banner)
                let bannerAt = seen[key]?.at ?? result.seen[key]?.at ?? now
                let explicit = NotchBannerParser.recognise(banner, names: names)
                let isTest = explicit == nil && allTokens.contains { NotchMessageProbe.matches(banner, token: $0) }
                // 原来的认法认不出时比角标：横幅第一次读到的前后 3 秒里哪个 App 的角标涨了，
                // 别的横幅已经认走的个数扣掉。一摞的不比（里面的单条会各自比）。
                var attribution: NotchDockAttribution?
                if explicit == nil, !isTest, !banner.stacked {
                    if !dockRead {
                        dockRead = true
                        if let fresh = NotchDockBadgeReader.queue.sync(execute: { NotchDockBadgeReader.shared.sample(now: now) }) {
                            history.append(fresh)
                            result.dockSample = fresh
                        }
                    }
                    var claims: [NotchMessageApp: Int] = [:]
                    for (other, item) in seen.merging(result.seen, uniquingKeysWith: { _, new in new })
                    where other != key && item.claims && abs(item.at.timeIntervalSince(bannerAt)) <= NotchDockBadgeHistory.window {
                        if let app = item.app { claims[app, default: 0] += 1 }
                    }
                    attribution = history.attribution(at: bannerAt).excluding(claims)
                }
                var analysis = NotchBannerParser.analyse(banner, path: entry.path, enabled: enabled,
                                                         testTokens: allTokens, names: names, dock: attribution)
                if explicit == nil, !isTest { analysis.dock = result.dockSample?.summary ?? history.latest?.summary }
                result.analyses.append((key: key, analysis: analysis))
                let resolved = isTest ? nil : NotchBannerParser.resolve(banner, names: names, dock: attribution)
                result.seen[key] = NotchSeenBanner(
                    at: bannerAt, app: resolved?.app,
                    claims: resolved != nil && (resolved?.inferred == false || banner.identifier != nil))
                if resolved == nil, !isTest, !banner.stacked { result.unresolved.append(key) }
                if result.bannerApp == nil {
                    result.bannerApp = NotchBannerParser.appLabel(banner, names: names) ?? resolved?.app.title
                }
                var incoming = isTest ? nil : NotchBannerParser.incoming(banner, enabled: enabled, names: names,
                                                                         dock: attribution)
                if incoming == nil, let probeToken {
                    incoming = NotchMessageProbe.incoming(entry.banner, token: probeToken)
                }
                guard let incoming else { continue }
                var element: AXUIElement?
                var close: CloseHandle?
                if !entry.banner.stacked, let bannerTree = descend(tree, entry.path) {
                    element = bannerTree.element
                    switch entry.banner.close {
                    case .action(let name)?:
                        close = CloseHandle(element: bannerTree.element, action: name)
                    case .button(let path)?:
                        if let button = descend(bannerTree, path) {
                            close = CloseHandle(element: button.element, action: kAXPressAction as String)
                        }
                    case nil:
                        break
                    }
                }
                result.found.append(Found(incoming: incoming, element: element, close: close))
            }
        }
        result.report = reports.joined(separator: "\n")
        return result
    }

    /// 按位置从读到的元素树往下找。
    private nonisolated static func descend(_ tree: ElementTree, _ path: [Int]) -> ElementTree? {
        var walk = tree
        for index in path {
            guard index < walk.children.count else { return nil }
            walk = walk.children[index]
        }
        return walk
    }

    private nonisolated static func node(_ element: AXUIElement, tree: ElementTree, depth: Int,
                                         budget: inout Int, deadline: Date) -> NotchBannerNode {
        budget -= 1
        AXUIElementSetMessagingTimeout(element, timeout)
        // 七个属性和孩子一次读回来（一次跨进程），比一个一个读快得多。
        let values = multiple(element, nodeAttributes)
        var result = NotchBannerNode(role: values[0] as? String,
                                     subrole: values[1] as? String,
                                     identifier: values[2] as? String,
                                     description: text(values[3]),
                                     title: text(values[4]),
                                     value: text(values[5]),
                                     help: text(values[6]))
        // 动作名只给横幅元素读（关横幅、诊断用），别的元素不多花一次跨进程。
        if let subrole = result.subrole, NotchBannerParser.bannerSubroles.contains(subrole) {
            var actionList: CFArray?
            if AXUIElementCopyActionNames(element, &actionList) == .success, let list = actionList as? [String] {
                result.actions = list
            }
            // 属性名（诊断用），不常见的属性读一下字，只用来找 bundle id。
            var names: CFArray?
            if AXUIElementCopyAttributeNames(element, &names) == .success, let list = names as? [String] {
                result.attributes = list
                for name in list.prefix(40) where !NotchBannerParser.isCommonAttribute(name) {
                    if name == "AXAttributedDescription" {
                        readAttributedDescription(element, into: &result)
                        if let text = result.attributedDescription { result.attributeTexts.append(text) }
                    } else if let text = string(element, name) {
                        result.attributeTexts.append(text)
                    }
                }
            }
        }
        // 桌面小组件不往里读。
        guard !NotchBannerParser.isDesktopWidget(identifier: result.identifier) else { return result }
        guard depth < maxDepth, budget > 0, Date() < deadline,
              let children = values[7] as? [AXUIElement] else { return result }
        for child in children {
            guard budget > 0 else { break }
            let sub = ElementTree(child)
            tree.children.append(sub)
            result.children.append(node(child, tree: sub, depth: depth + 1, budget: &budget, deadline: deadline))
        }
        return result
    }

    /// 读横幅元素的 AXAttributedDescription：字本身（找 App 名、bundle id，诊断只写长度），
    /// 出现过的属性键名（诊断用），和字体、颜色以外的字符串、链接属性值（找 bundle id 用）。
    private nonisolated static func readAttributedDescription(_ element: AXUIElement, into node: inout NotchBannerNode) {
        guard let raw = copy(element, "AXAttributedDescription") else { return }
        if let attributed = raw as? NSAttributedString {
            node.attributedDescription = attributed.string
            var keys: [String] = []
            var values: [String] = []
            let whole = NSRange(location: 0, length: attributed.length)
            attributed.enumerateAttributes(in: whole, options: []) { attributes, _, stop in
                for (key, value) in attributes {
                    if !keys.contains(key.rawValue) { keys.append(key.rawValue) }
                    let text = (value as? String) ?? (value as? URL)?.absoluteString
                    if let text, !text.isEmpty, values.count < 20, !values.contains(text) { values.append(text) }
                }
                if keys.count > 30 { stop.pointee = true }
            }
            node.attributedKeys = keys.sorted()
            node.attributedValues = values
        } else if let text = raw as? String {
            node.attributedDescription = text
        }
    }

    private nonisolated static let nodeAttributes: [String] = [
        kAXRoleAttribute, kAXSubroleAttribute, "AXIdentifier", kAXDescriptionAttribute,
        kAXTitleAttribute, kAXValueAttribute, kAXHelpAttribute, kAXChildrenAttribute,
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

    /// 关掉一条系统横幅（设置里「卡片弹出后关掉系统横幅」打开时）：执行横幅自己的「关闭」
    /// 动作或按它的关闭按钮，在后台队列上做；横幅已经不在了就是失败，什么都不发生。
    nonisolated static func close(_ handle: CloseHandle) {
        queue.async {
            guard AXIsProcessTrusted() else { return }
            AXUIElementSetMessagingTimeout(handle.element, timeout)
            _ = AXUIElementPerformAction(handle.element, handle.action as CFString)
        }
    }
}

/// 一次读通知中心是谁触发的，诊断里分开计数。
enum NotchScanTrigger: String, CaseIterable, Sendable {
    /// 刚接上通知中心时读一遍。
    case priming
    /// AX 事件之后。
    case event
    /// 事件之后的补读。
    case followUp = "follow-up"
    /// 定时轻读发现窗口或横幅变了。
    case poll
    /// 有认不出的横幅，角标补读（横幅出现后 0.5 秒、1.5 秒，或每秒记角标时发现涨了）。
    case dockRecheck = "dock-recheck"
}

/// 见过的一条横幅：第一次读到的时间、认成的 App，认 App 用的是不是稳定的办法。
struct NotchSeenBanner: Sendable {
    var at: Date
    var app: NotchMessageApp?
    /// 这条认走的个数能不能从别的横幅的角标涨幅里扣：原来的认法认出的都算；靠角标、线索推断
    /// 的只有系统标识稳定的才算（没标识的横幅字填上前后键会变，同一条会被算成两条）。
    var claims: Bool
    /// 已经排过角标补读。
    var rechecked = false
}

/// 读程序坞上三个 App（信息、WhatsApp、微信）的角标。macOS 27 的横幅上没有 App 名，
/// 横幅出现前后哪个 App 的角标涨了，就是它的消息（判断在 Core 的 `NotchDockBadgeHistory`）。
///
/// 每秒读一次，所以记住三个 App 在程序坞里的那一项，只读它们的 AXStatusLabel（三次跨进程）；
/// 每 20 秒、或读失败、程序坞换了进程时重新走一遍程序坞找它们。只在 `queue` 上用。
final class NotchDockBadgeReader: @unchecked Sendable {
    static let shared = NotchDockBadgeReader()
    /// 读程序坞单独一条队列：读通知中心一次最多 2.5 秒，不让每秒的角标记录排在它后面。
    nonisolated static let queue = DispatchQueue(label: "com.docket-zh.notch-message.dock", qos: .userInitiated)
    private static let refreshInterval: TimeInterval = 20

    private var items: [NotchMessageApp: AXUIElement] = [:]
    private var dockPID: pid_t = 0
    private var lastRefresh: Date?

    /// 读一次（在 `queue` 上调）。程序坞没在运行时为 nil。
    func sample(now: Date = Date()) -> NotchDockSample? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
            .first(where: { !$0.isTerminated }) else { return nil }
        let pid = dock.processIdentifier
        if pid != dockPID || lastRefresh.map({ now.timeIntervalSince($0) > Self.refreshInterval }) ?? true {
            refresh(pid: pid, now: now)
        }
        var badges: [NotchMessageApp: NotchDockBadge] = [:]
        var failed = false
        for (app, item) in items {
            AXUIElementSetMessagingTimeout(item, 0.2)
            var label: CFTypeRef?
            switch AXUIElementCopyAttributeValue(item, "AXStatusLabel" as CFString, &label) {
            case .success:
                badges[app] = NotchDockBadge.parse(label as? String)
            case .noValue, .attributeUnsupported:
                badges[app] = NotchDockBadge.none
            default:
                // 那一项没了（App 退出、从程序坞拿掉）：这次当不在，下次重新找。
                failed = true
            }
        }
        if failed { lastRefresh = nil }
        return NotchDockSample(at: now, badges: badges)
    }

    /// 走一遍程序坞，记下三个 App 各自那一项。
    private func refresh(pid: pid_t, now: Date) {
        dockPID = pid
        lastRefresh = now
        items = [:]
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.2)
        var lists: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &lists) == .success,
              let children = lists as? [AXUIElement] else { return }
        for list in children {
            var raw: CFTypeRef?
            guard AXUIElementCopyAttributeValue(list, kAXChildrenAttribute as CFString, &raw) == .success,
                  let entries = raw as? [AXUIElement] else { continue }
            for item in entries.prefix(80) {
                AXUIElementSetMessagingTimeout(item, 0.2)
                var url: CFTypeRef?
                guard AXUIElementCopyAttributeValue(item, kAXURLAttribute as CFString, &url) == .success,
                      let bundleURL = url as? URL,
                      let found = NotchMessageApp.match(bundleID: Bundle(url: bundleURL)?.bundleIdentifier),
                      items[found] == nil else { continue }
                items[found] = item
            }
        }
    }
}

/// AX 事件的回调（C 函数指针，不能带上下文）：`refcon` 是观察者自己。事件源挂在主线程
/// 的 run loop 上，所以回调在主线程。
private func notchBannerObserverCallback(_ observer: AXObserver, _ element: AXUIElement,
                                         _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let watcher = Unmanaged<NotchBannerWatcher>.fromOpaque(refcon).takeUnretainedValue()
    let name = notification as String
    MainActor.assumeIsolated { watcher.axEvent(name) }
}
