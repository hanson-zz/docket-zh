import AppKit
import CoreGraphics
import Foundation
import Observation
import os

private let timeInsightsLog = Logger(subsystem: "com.docket-zh.app", category: "time-insights")

/// 时间洞察的采集器：看着前台 App、空闲秒数、锁屏休眠和切换用户，喂给 Core 的
/// `TimeInsightsRecorder`，把结束的段写进本机 SQLite（`TimeInsightsDatabase`），
/// 再算出今日汇总给卡片和面板。
///
/// - 只有扩展栏的某个布局里放着时间洞察卡片时才记（`widgets` 由 DocketApp 接上），
///   拿掉卡片就停；暂停也是一样，暂停、排除、清空、导出全部免费。
/// - 前台切换用 `NSWorkspace.didActivateApplicationNotification`；空闲秒数每 10 秒读
///   一次 `CGEventSource`（距上次输入多少秒，不读按键内容，不需要权限）；休眠、显示器
///   睡眠、切换用户用 NSWorkspace 通知，锁屏和屏保用分布式通知，和久坐提醒的离开检测一样。
/// - 开着的那段每 30 秒存一次心跳，崩溃或强退后下次启动按最后一次心跳收尾，
///   进程没在跑的时间不算。
/// - 窗口标题和前台网站域名分别需要 Pro 与独立授权；日志只写错误码。
@MainActor @Observable
final class TimeInsightsTracker {
    static let shared = TimeInsightsTracker()

    /// 今天的汇总，包括还开着的那段（算到现在）。
    private(set) var today: TimeInsightsDay = .empty
    /// 昨天的汇总（启动和跨天时从库里读一次）。昨天没有任何记录时 nil，面板就不写较昨日。
    private(set) var yesterday: TimeInsightsDay?
    /// 现在开着的那一段从什么时候开始（「当前记录」卡片的本段时长）；没在记时 nil。
    private(set) var currentSegmentStart: Date?
    private(set) var status: TimeInsightsStatus = .starting
    /// 现在在前台、正被记着的 App；暂停、锁屏、排除时是 nil。
    private(set) var currentApp: TimeInsightsRecorder.App?
    private(set) var currentCategory: TimeInsightsCategory = .uncategorized
    /// 最近一个在前台的、不是码头自己的 App，面板里「排除这个应用」用。
    private(set) var lastOtherApp: TimeInsightsRecorder.App?
    /// 数据库打不开时给用户看的一句话。
    private(set) var storageProblem: String?
    private(set) var settings: TimeInsightsSettings
    private(set) var browserStates: [String: BrowserBridgeState] = [:]
    /// Only publish the browser identity, never a URL, for recording status UI.
    private(set) var currentWebsiteBrowserID: String?
    @ObservationIgnored private let browserBridge = TimeInsightsChromiumBridge()
    @ObservationIgnored private var browserTimer: Timer?
    /// macOS 原生窗口标题来源：只有主动同意、Pro 解锁且系统辅助功能授权后调用。
    @ObservationIgnored private let titleSource = NativeTimeInsightsWindowTitleSource()
    var accessibilityTrusted: Bool { titleSource.isConnected }

    /// 每个布局里的每个小组件。DocketApp 接上。
    @ObservationIgnored var widgets: @MainActor () -> [WidgetInstance] = { [] }
    /// 打开 设置 ▸ 时间洞察（面板上的「隐私与设置」）。DocketApp 接上。
    @ObservationIgnored var openSettings: @MainActor () -> Void = {}
    /// 打开「完整统计」窗口。DocketApp 接上。
    @ObservationIgnored var openStats: @MainActor () -> Void = {}

    @ObservationIgnored private var recorder: TimeInsightsRecorder
    @ObservationIgnored private var database: TimeInsightsDatabase?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var workspaceObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var distributedObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var placed = true
    @ObservationIgnored private var lastCheckpoint = Date.distantPast
    @ObservationIgnored private var checkpointID: String?
    /// 今天已经写进库里的段（启动和跨天时从库里读，之后随写随加）。
    @ObservationIgnored private var todaySessions: [ActivitySession] = []
    @ObservationIgnored private var todayStart = Date.distantPast

    static let sampleInterval: TimeInterval = 10
    static let checkpointInterval: TimeInterval = 30

    private init() {
        let stored = TimeInsightsSettings.decode(UserDefaults.standard.data(forKey: TimeInsightsSettings.defaultsKey))
        settings = stored
        // App Nap 可能把 10 秒的定时器拖到一两分钟，心跳断开的判断放宽到 150 秒。
        recorder = TimeInsightsRecorder(idleAfter: stored.idleThreshold, excluded: Set(stored.excludedBundleIDs),
                                        rules: ProAccess.isUnlocked ? stored.customRules : [], heartbeatGap: 150)
    }

    // MARK: 启停

    func start() {
        guard timer == nil else { return }
        openDatabase()
        let now = Date.now
        if settings.paused { feed(.blocked(.paused), at: now) }
        placed = isPlaced
        if !placed { feed(.blocked(.notPlaced), at: now) }
        if let front = NSWorkspace.shared.frontmostApplication.flatMap(Self.app) {
            noteOther(front)
            feed(.foreground(front), at: now)
        }
        observe()
        browserBridge.onRequest = { [weak self] report in self?.receiveBrowserReport(report) }
        browserBridge.start()
        let browserTimer = Timer(timeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated { TimeInsightsTracker.shared.checkBrowser() }
        }
        browserTimer.tolerance = 0.1
        RunLoop.main.add(browserTimer, forMode: .common)
        self.browserTimer = browserTimer
        let timer = Timer(timeInterval: Self.sampleInterval, repeats: true) { _ in
            MainActor.assumeIsolated { TimeInsightsTracker.shared.sample() }
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// 退出时：开着的那段在这一刻结束、写盘，清掉心跳。
    func stop() {
        let now = Date.now
        settleWebsiteIdle(at: now)
        synchronizeBrowser(at: now)
        persist(recorder.flush(at: now))
        try? database?.saveOpen(nil)
        checkpointID = nil
    }

    private func observe() {
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                        object: nil, queue: .main) { note in
            let running = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let app = running.flatMap(TimeInsightsTracker.app)
            MainActor.assumeIsolated {
                if let app { TimeInsightsTracker.shared.noteOther(app) }
                TimeInsightsTracker.shared.feed(.foreground(app))
            }
        })
        let pairs: [(Notification.Name, TimeInsightsRecorder.Event)] = [
            (NSWorkspace.willSleepNotification, .blocked(.asleep)),
            (NSWorkspace.didWakeNotification, .unblocked(.asleep)),
            (NSWorkspace.screensDidSleepNotification, .blocked(.displayOff)),
            (NSWorkspace.screensDidWakeNotification, .unblocked(.displayOff)),
            (NSWorkspace.sessionDidResignActiveNotification, .blocked(.userSwitched)),
            (NSWorkspace.sessionDidBecomeActiveNotification, .unblocked(.userSwitched)),
        ]
        for (name, event) in pairs {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { TimeInsightsTracker.shared.feed(event) }
            })
        }
        let distributed = DistributedNotificationCenter.default()
        let named: [(String, TimeInsightsRecorder.Event)] = [
            ("com.apple.screenIsLocked", .blocked(.locked)),
            ("com.apple.screenIsUnlocked", .unblocked(.locked)),
            ("com.apple.screensaver.didstart", .blocked(.screensaver)),
            ("com.apple.screensaver.didstop", .unblocked(.screensaver)),
        ]
        for (name, event) in named {
            distributedObservers.append(distributed.addObserver(forName: Notification.Name(name), object: nil,
                                                                queue: .main) { _ in
                MainActor.assumeIsolated { TimeInsightsTracker.shared.feed(event) }
            })
        }
    }

    nonisolated private static func app(_ running: NSRunningApplication) -> TimeInsightsRecorder.App? {
        guard let id = running.bundleIdentifier, !id.isEmpty else { return nil }
        return TimeInsightsRecorder.App(bundleID: id, name: running.localizedName ?? id)
    }

    private func noteOther(_ app: TimeInsightsRecorder.App) {
        if app.bundleID != Bundle.main.bundleIdentifier { lastOtherApp = app }
    }

    // MARK: 采样

    private var isPlaced: Bool { widgets().contains { $0.kind == .timeInsights } }

    private func sample() {
        let now = Date.now
        let nowPlaced = isPlaced
        if nowPlaced != placed {
            placed = nowPlaced
            feed(nowPlaced ? .unblocked(.notPlaced) : .blocked(.notPlaced), at: now)
        }
        feed(.idle(Self.idleSeconds()), at: now)
        refreshTitleAndRules(at: now)
    }

    /// 授权与采样都由用户控制；未授权时不调用辅助功能 API 读取窗口。
    private func refreshTitleAndRules(at now: Date) {
        let rules = ProAccess.isUnlocked ? settings.customRules : []
        if recorder.rules != rules { recorder.rules = rules }
        guard let segment = recorder.segment, !segment.idle,
              let app = recorder.eligibleApp,
              !(TimeInsightsBrowserSamplePolicy.chromiumBrowsers.contains(app.bundleID) && recorder.hasWebsiteSlices)
        else { return }
        let permitted = TimeInsightsPro.collectsWindowTitles(settings, unlocked: ProAccess.isUnlocked)
            && titleSource.isConnected && TimeInsightsTitlePrivacy.allows(bundleID: app.bundleID)
        let title: String?
        if permitted, let running = NSWorkspace.shared.frontmostApplication,
           running.bundleIdentifier == app.bundleID {
            title = titleSource.title(forProcess: running.processIdentifier)
        } else {
            title = nil
        }
        persist(recorder.updateWindowTitle(title, at: now))
        checkpoint(now)
        publish(now)
    }

    private func feed(_ event: TimeInsightsRecorder.Event, at now: Date = .now) {
        switch event {
        case .foreground, .blocked:
            settleWebsiteIdle(at: now)
            synchronizeBrowser(at: now)
        default:
            break
        }
        persist(recorder.handle(event, at: now))
        synchronizeBrowser(at: now)
        checkpoint(now)
        publish(now)
    }

    private func settleWebsiteIdle(at now: Date) {
        let seconds = Self.idleSeconds()
        let browserResumed = recorder.isIdle && seconds < recorder.idleAfter
            && TimeInsightsPro.collectsWebsites(settings, unlocked: ProAccess.isUnlocked)
            && TimeInsightsBrowserSamplePolicy.chromiumBrowsers.contains(recorder.eligibleApp?.bundleID ?? "")
        guard recorder.hasWebsiteSlices || browserResumed else { return }
        persist(recorder.handle(.idle(seconds), at: now))
    }

    private func synchronizeBrowser(at now: Date) {
        let bundleID = recorder.eligibleApp?.bundleID
        let unlocked = ProAccess.isUnlocked
        let eligible = TimeInsightsPro.collectsWebsites(settings, unlocked: unlocked)
            && isPlaced && recorder.segment != nil && !recorder.isIdle
            && Self.idleSeconds() < recorder.idleAfter
            && bundleID == NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            && TimeInsightsBrowserSamplePolicy.chromiumBrowsers.contains(bundleID ?? "")
        let observation = bundleID.flatMap { browserBridge.lastObservation(for: $0) }
        browserBridge.authorize(eligible ? bundleID : nil)
        guard let bundleID, TimeInsightsBrowserSamplePolicy.chromiumBrowsers.contains(bundleID) else { return }
        let tab = browserBridge.currentTab(for: bundleID)
        guard tab != nil || recorder.hasWebsiteSlices else { return }
        // When the bridge expires, fall back from the last verified sample.
        // Consent and foreground changes otherwise take effect at the system event.
        let expired = observation.map { now.timeIntervalSince($0) > TimeInsightsChromiumBridge.expiry } ?? false
        let edge = eligible || expired ? (observation ?? now) : now
        recorder.updateWebsite(tab?.domain, at: edge, observedAt: now)
    }

    private func receiveBrowserReport(_ report: TimeInsightsChromiumBridge.Report) -> UUID? {
        let now = Date.now
        // Check the macOS state before granting access or accepting a sample.
        checkBrowser(at: now)
        let grant = browserBridge.ingest(report, now: now, settings: settings, unlocked: ProAccess.isUnlocked)
        if report.status != "ready" { checkBrowser(at: now) }
        return grant
    }

    private func checkBrowser(at now: Date = .now) {
        let next = Dictionary(uniqueKeysWithValues: TimeInsightsBrowserSamplePolicy.chromiumBrowsers.map {
            ($0, browserBridge.state(for: $0, now: now))
        })
        if next != browserStates { browserStates = next }
        let before = recorder.segment
        settleWebsiteIdle(at: now)
        synchronizeBrowser(at: now)
        if before?.id != recorder.segment?.id {
            checkpoint(now)
            publish(now)
        }
    }

    // MARK: 存储

    private func openDatabase() {
        let url = TimeInsightsDatabase.defaultURL()
        do {
            let db = try TimeInsightsDatabase(url: url)
            database = db
            storageProblem = nil
            recoverOpenSegment(db)
            try? db.prune(endingBefore: Date.now.addingTimeInterval(-Double(settings.retentionDays) * 86_400))
            reloadToday(Date.now)
            if recorder.blocks.contains(.storage) { feed(.unblocked(.storage)) }
        } catch let failure as TimeInsightsDatabase.Failure {
            database = nil
            switch failure {
            case .tooNew:
                storageProblem = tr("本机数据来自更新版本的码头，为免覆盖已停止记录。原文件保留不动。")
            case .cannotOpen(let code), .sql(let code, _):
                timeInsightsLog.error("time insights storage unavailable, code \(code, privacy: .public)")
                storageProblem = tr("本机数据文件打不开，已停止记录。可以在面板里清空数据后重新开始。")
            }
            feed(.blocked(.storage))
        } catch {
            database = nil
            storageProblem = tr("本机数据文件打不开，已停止记录。可以在面板里清空数据后重新开始。")
            feed(.blocked(.storage))
        }
    }

    /// 上次退出或崩溃时开着的那段：按最后一次心跳收尾写进去。
    private func recoverOpenSegment(_ db: TimeInsightsDatabase) {
        guard let segment = try? db.loadOpen() else { return }
        let sessions = TimeInsightsRecorder.recoverCheckpoint(segment, now: .now)
        try? db.insert(sessions.flatMap { TimeInsightsMath.splitByDay($0) })
        try? db.saveOpen(nil)
    }

    private func persist(_ sessions: [ActivitySession]) {
        guard !sessions.isEmpty else { return }
        let parts = sessions.flatMap { TimeInsightsMath.splitByDay($0) }
        guard let database else { return }
        do {
            try database.insert(parts)
        } catch {
            timeInsightsLog.error("time insights write failed")
            return
        }
        let day = DateInterval(start: todayStart, duration: 86_400 * 2)
        todaySessions += parts.filter { $0.end > day.start }
    }

    private func checkpoint(_ now: Date) {
        guard let database else { return }
        let segment = recorder.checkpoint
        guard segment?.id != checkpointID || now.timeIntervalSince(lastCheckpoint) >= Self.checkpointInterval else { return }
        try? database.saveOpen(segment)
        checkpointID = segment?.id
        lastCheckpoint = now
    }

    private func reloadToday(_ now: Date) {
        let interval = TimeInsightsMath.dayInterval(now)
        todayStart = interval.start
        todaySessions = (try? database?.sessions(overlapping: interval)) ?? []
        let before = interval.start.addingTimeInterval(-1)
        let previous = TimeInsightsMath.dayInterval(before)
        let past = (try? database?.sessions(overlapping: previous)) ?? []
        let day = TimeInsightsDay.make(categorized(past), day: before)
        yesterday = day.active > 0 ? day : nil
    }

    // MARK: 汇总

    private func publish(_ now: Date) {
        if Calendar.current.startOfDay(for: now) != todayStart { reloadToday(now) }
        var sessions = todaySessions
        sessions += recorder.provisionalSessions(now: now).flatMap { TimeInsightsMath.splitByDay($0) }
        let day = TimeInsightsDay.make(categorized(sessions), day: now)
        if day != today { today = day }
        let nextStatus = recorder.status
        if nextStatus != status { status = nextStatus }
        let app = recorder.segment.flatMap { _ in recorder.eligibleApp }
        if app != currentApp { currentApp = app }
        let category = recorder.segment?.classification ?? .uncategorized
        if category != currentCategory { currentCategory = category }
        let segmentStart = app == nil ? nil : recorder.segment?.start
        if segmentStart != currentSegmentStart { currentSegmentStart = segmentStart }
        let websiteBrowser = nextStatus == .recording && recorder.segment?.domain != nil ? app?.bundleID : nil
        if websiteBrowser != currentWebsiteBrowserID { currentWebsiteBrowserID = websiteBrowser }
    }

    // MARK: 用户操作（全部免费）

    func websiteConnection(for bundleID: String) -> TimeInsightsWebsiteConnection {
        .resolve(bridge: browserStates[bundleID] ?? .notConnected, status: status,
                 enabled: ProAccess.isUnlocked && settings.websitesOptIn, placed: isPlaced,
                 excluded: settings.isExcluded(bundleID), foreground: currentApp?.bundleID == bundleID,
                 hasWebsite: currentWebsiteBrowserID == bundleID)
    }

    func refreshBrowserConnections() {
        sample()
        checkBrowser()
    }

    func update(_ change: (inout TimeInsightsSettings) -> Void) {
        var next = settings
        change(&next)
        guard next != settings else { return }
        let wasPaused = settings.paused
        settings = next
        UserDefaults.standard.set(next.encoded(), forKey: TimeInsightsSettings.defaultsKey)
        recorder.idleAfter = next.idleThreshold
        recorder.excluded = Set(next.excludedBundleIDs)
        recorder.rules = ProAccess.isUnlocked ? next.customRules : []
        if next.paused != wasPaused {
            feed(next.paused ? .blocked(.paused) : .unblocked(.paused))
        } else {
            feed(.tick)
        }
        refreshTitleAndRules(at: .now)
    }

    /// 历史分类按当前规则重新计算，只影响显示，不改原始时间和数据库记录。
    private func categorized(_ sessions: [ActivitySession]) -> [ActivitySession] {
        TimeInsightsClassifier.reclassify(
            sessions, rules: ProAccess.isUnlocked ? settings.customRules : []
        )
    }

    func setPaused(_ paused: Bool) { update { $0.paused = paused } }

    func exclude(_ bundleID: String) { update { $0.exclude(bundleID) } }

    func include(_ bundleID: String) { update { $0.include(bundleID) } }

    /// 删掉本机全部记录，从现在重新开始。数据库打不开时把旧文件改名放到一边再建新的。
    func clearAll() {
        let now = Date.now
        _ = recorder.flush(at: now)
        if let database {
            do {
                try database.deleteAll()
            } catch {
                timeInsightsLog.error("time insights clear failed")
            }
        } else {
            let url = TimeInsightsDatabase.defaultURL()
            let stamp = Int(now.timeIntervalSince1970)
            let aside = url.deletingPathExtension().appendingPathExtension("\(stamp).bak")
            try? FileManager.default.moveItem(at: url, to: aside)
            for suffix in ["-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + suffix))
            }
            openDatabase()
        }
        todaySessions = []
        checkpointID = nil
        feed(.tick, at: now)
    }

    /// 独立统计窗口读取一段时间的真实会话，追加尚未写盘的当前活动段。
    /// 返回 nil 表示数据库不可用；不能把读取失败伪装成 0 分钟。
    func sessions(overlapping interval: DateInterval) -> [ActivitySession]? {
        guard storageProblem == nil, let database,
              let finished = try? database.sessions(overlapping: interval) else { return nil }
        var snapshot = finished
        snapshot += recorder.provisionalSessions(now: .now)
            .filter { $0.end > interval.start && $0.start < interval.end }
            .flatMap { TimeInsightsMath.splitByDay($0) }
        return categorized(snapshot)
    }

    /// 基础 CSV（免费）：时间、App、分类和来源，不含窗口标题和域名。
    func exportCSV(to url: URL) throws {
        var sessions = (try database?.allSessions()) ?? []
        sessions += recorder.provisionalSessions(now: .now)
        try TimeInsightsCSV.make(sessions).write(to: url, atomically: true, encoding: .utf8)
    }

    /// 本机数据文件在哪（面板里「在访达中显示」）。
    var storageURL: URL { TimeInsightsDatabase.defaultURL() }

    // MARK: 空闲

    /// 距上次键盘、鼠标、触控板输入多少秒（`CGEventSource`，不读内容，不需要权限）。
    private static func idleSeconds() -> TimeInterval {
        if let any = CGEventType(rawValue: ~0) {
            return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)
        }
        let kinds: [CGEventType] = [.keyDown, .mouseMoved, .leftMouseDown, .rightMouseDown,
                                    .scrollWheel, .leftMouseDragged, .flagsChanged]
        return kinds.map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? 0
    }
}
