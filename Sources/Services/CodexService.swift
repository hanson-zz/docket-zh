import AppKit
import Foundation
import Observation
@preconcurrency import UserNotifications

/// Codex's rate limits and what it is doing right now.
///
/// Limits are asked of Codex's own `codex app-server` first
/// (`account/rateLimits/read`, see CodexAppServerClient). When no codex
/// binary is found, or it fails or takes too long, the widget falls back to
/// the older path below.
///
/// The fallback's limits come from the same backend Codex's own `/status` asks, with the
/// ChatGPT sign-in Codex keeps in `~/.codex/auth.json`. The file is only ever
/// read: Codex refreshes that token itself, and Docket never writes it, so a
/// widget can not sign Codex out. The token goes to chatgpt.com and nowhere
/// else.
///
/// Activity is read from the end of Codex's recent session logs every few
/// seconds; nothing is sent anywhere for it. Every session written to in the
/// last hour is read, so the panel can list each one that is working, waiting
/// for you or just finished, and the card shows the most urgent of them.
///
/// Endpoints and file layouts learned from Codenotch (MIT); see NOTICE.md.
@MainActor @Observable
final class CodexService {
    static let shared = CodexService()

    enum Problem: Equatable {
        case notSignedIn
        case expired
        case offline
        case rateLimited(until: Date)
        case server(Int)
        case unreadable

        var message: String {
            switch self {
            case .notSignedIn: tr("没有找到 Codex 的 ChatGPT 登录。请在终端运行 codex login，或打开 Codex 应用登录。")
            case .expired: tr("Codex 的登录已过期。打开 Codex 用一次即可自动续期。")
            case .offline: tr("无法连接 chatgpt.com。国内网络需要代理，可在详情面板里填写代理地址。")
            case .rateLimited(let until): tr("请求太频繁，\(CodexPace.duration(until.timeIntervalSinceNow))后再试。")
            case .server(let code): tr("chatgpt.com 返回错误 \(code)，可能是接口有变动。")
            case .unreadable: tr("读不懂 chatgpt.com 的返回内容，可能是接口有变动。")
            }
        }
    }

    private(set) var report: CodexUsageReport?
    private(set) var problem: Problem?
    private(set) var loading = false
    private(set) var email: String?
    private(set) var activity: CodexActivity = .idle
    /// The lead session's working folder, when its log names one.
    private(set) var activityProject: String?
    /// 正在运行的会话（等你确认、工作中、刚完成），等你的排最前。
    private(set) var sessions: [CodexSession] = []
    /// 今天和本周的会话数、时长、token，读本机会话记录；还没读过是 nil。
    private(set) var stats: (today: CodexStatBucket, week: CodexStatBucket)?
    /// 最近一次读到会话记录的时间（面板底部的「1 分钟前」）。
    private(set) var scannedAt: Date?
    /// 声音设置，卡片上的小喇叭也读它。
    private(set) var chime = CodexChimeSettings()

    @ObservationIgnored private var lastAttempt: Date?
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var blockedUntil: Date?
    @ObservationIgnored private var activityTimer: Timer?
    @ObservationIgnored private var lastAlerted: [String: Double] = [:]
    @ObservationIgnored private var notifyDone = true
    @ObservationIgnored private var alertFirst = 80
    @ObservationIgnored private var notifyQuota = true
    @ObservationIgnored private var includeExtras = false
    @ObservationIgnored private var askedPermission = false
    @ObservationIgnored private let presenter = BannerPresenter()
    @ObservationIgnored private var previousStates: [String: CodexActivity]?
    @ObservationIgnored private var gate = CodexChimeGate()
    @ObservationIgnored private var scanning = false
    @ObservationIgnored private var statsLoading = false
    @ObservationIgnored private var statsAt: Date?
    @ObservationIgnored private var statsCache: [String: CodexStatsCacheEntry] = [:]

    private static let cacheKey = "codex.lastReport"
    static let proxyKey = "codex.proxy"
    /// Five minutes: the windows move in percent per hour, and the backend
    /// is not ours to hammer.
    static let interval: TimeInterval = 300

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.cacheKey),
           let cached = try? JSONDecoder().decode(CodexUsageReport.self, from: data) {
            report = cached
            for w in cached.windows { lastAlerted[w.id] = w.usedFraction }
        }
    }

    // MARK: Settings from the widget

    /// The widget's own options. Several widgets share one service; the last
    /// one drawn wins, which only matters if two disagree.
    func configure(_ config: WidgetConfig) {
        notifyQuota = config.bool("notify", default: true)
        notifyDone = config.bool("notifyDone", default: true)
        alertFirst = config.int("alertAt", default: 80)
        let sound = CodexChimeSettings(config: config)
        if sound != chime { chime = sound }
        let extras = config.bool("extras", default: false)
        if extras != includeExtras {
            includeExtras = extras
            lastAttempt = nil
        }
    }

    var proxyText: String {
        get { UserDefaults.standard.string(forKey: Self.proxyKey) ?? "" }
    }

    /// Saves the proxy, or clears it when the text is empty. Returns false
    /// for text that is not a proxy address, which is then not saved.
    @discardableResult
    func setProxy(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.proxyKey)
        } else {
            guard let proxy = CodexProxy.parse(trimmed) else { return false }
            UserDefaults.standard.set(proxy.display, forKey: Self.proxyKey)
        }
        failures = 0
        blockedUntil = nil
        refresh(force: true)
        return true
    }

    // MARK: Limits

    nonisolated static var home: URL {
        if let env = ProcessInfo.processInfo.environment["CODEX_HOME"], !env.isEmpty {
            return URL(fileURLWithPath: (env as NSString).expandingTildeInPath)
        }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex")
    }

    /// Fetches unless the last try was under five minutes ago, or a failure
    /// asked for a longer wait. `force` skips the five minutes, never a
    /// server's own Retry-After.
    func refresh(force: Bool = false) {
        let now = Date.now
        if let blockedUntil, blockedUntil > now { return }
        if !force, let lastAttempt, now.timeIntervalSince(lastAttempt) < Self.interval { return }
        guard !loading else { return }
        lastAttempt = now
        loading = true
        let extras = includeExtras
        let session = Self.session()
        let proxy = UserDefaults.standard.string(forKey: Self.proxyKey).flatMap(CodexProxy.parse)
        Task {
            let outcome = await Self.fetch(session: session, includeExtras: extras, proxy: proxy)
            loading = false
            apply(outcome)
        }
    }

    private enum Outcome {
        case ok(CodexUsageReport, email: String?)
        case failed(Problem, retryAfter: TimeInterval?)
    }

    private func apply(_ outcome: Outcome) {
        switch outcome {
        case .ok(let fresh, let mail):
            failures = 0
            blockedUntil = nil
            problem = nil
            email = mail
            alertIfNeeded(fresh)
            report = fresh
            if let data = try? JSONEncoder().encode(fresh) {
                UserDefaults.standard.set(data, forKey: Self.cacheKey)
            }
        case .failed(let p, let retryAfter):
            failures += 1
            let wait = CodexBackoff.delay(failures: failures, retryAfter: retryAfter)
            // Signing in again is the user's move; checking every few
            // minutes for it costs one file read.
            if p != .notSignedIn, p != .expired {
                blockedUntil = Date.now.addingTimeInterval(wait)
            }
            if case .rateLimited = p {
                problem = .rateLimited(until: Date.now.addingTimeInterval(wait))
            } else {
                problem = p
            }
        }
    }

    private static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        if let text = UserDefaults.standard.string(forKey: proxyKey), let proxy = CodexProxy.parse(text) {
            switch proxy.kind {
            case .http:
                config.connectionProxyDictionary = [
                    kCFNetworkProxiesHTTPEnable as String: 1,
                    kCFNetworkProxiesHTTPProxy as String: proxy.host,
                    kCFNetworkProxiesHTTPPort as String: proxy.port,
                    kCFNetworkProxiesHTTPSEnable as String: 1,
                    kCFNetworkProxiesHTTPSProxy as String: proxy.host,
                    kCFNetworkProxiesHTTPSPort as String: proxy.port,
                ]
            case .socks:
                config.connectionProxyDictionary = [
                    kCFNetworkProxiesSOCKSEnable as String: 1,
                    kCFNetworkProxiesSOCKSProxy as String: proxy.host,
                    kCFNetworkProxiesSOCKSPort as String: proxy.port,
                ]
            }
        }
        return URLSession(configuration: config)
    }

    /// The official app-server first, then the web endpoint the widget has
    /// always used. The report says which one answered.
    nonisolated private static func fetch(session: URLSession, includeExtras: Bool,
                                          proxy: CodexProxy?) async -> Outcome {
        if case .success(let official) = await CodexAppServerClient.read(includeExtras: includeExtras, proxy: proxy) {
            return await completed(official, session: session)
        }
        return await fetchWeb(session: session, includeExtras: includeExtras)
    }

    /// Adds what only the web side knows (the daily token chart, the email,
    /// a plan the server left out) to an app-server reading. Any of it
    /// failing leaves the reading as it was.
    nonisolated private static func completed(_ official: CodexUsageReport, session: URLSession) async -> Outcome {
        var report = official
        guard let data = try? Data(contentsOf: home.appendingPathComponent("auth.json")),
              let credential = try? CodexAuth.credential(from: data) else {
            return .ok(report, email: nil)
        }
        if report.plan == nil { report.plan = credential.plan }
        if let (body, response) = await get("profiles/me", credential, session), response.statusCode == 200 {
            report.daily = CodexUsageParser.daily(from: body)
        }
        return .ok(report, email: credential.email)
    }

    nonisolated private static func fetchWeb(session: URLSession, includeExtras: Bool) async -> Outcome {
        let credential: CodexAuth.Credential
        do {
            let data = try Data(contentsOf: home.appendingPathComponent("auth.json"))
            credential = try CodexAuth.credential(from: data)
        } catch CodexUsageError.expired {
            return .failed(.expired, retryAfter: nil)
        } catch {
            return .failed(.notSignedIn, retryAfter: nil)
        }

        guard let (data, response) = await get("usage", credential, session) else {
            return .failed(.offline, retryAfter: nil)
        }
        switch response.statusCode {
        case 200..<300: break
        case 401, 403: return .failed(.expired, retryAfter: nil)
        case 429:
            return .failed(.rateLimited(until: .now),
                           retryAfter: CodexBackoff.retryAfter(response.value(forHTTPHeaderField: "Retry-After"), now: .now))
        default: return .failed(.server(response.statusCode), retryAfter: nil)
        }
        let windows: [CodexLimitWindow]
        do {
            windows = try CodexUsageParser.windows(from: data, includeExtras: includeExtras)
        } catch {
            return .failed(.unreadable, retryAfter: nil)
        }

        // Both are extras on the panel; either failing leaves the rings.
        async let profile = get("profiles/me", credential, session)
        async let credits = get("rate-limit-reset-credits", credential, session, beta: true)
        let daily = await profile.flatMap { $0.1.statusCode == 200 ? CodexUsageParser.daily(from: $0.0) : nil } ?? []
        let resets = await credits.flatMap { $0.1.statusCode == 200 ? CodexUsageParser.resetCredits(from: $0.0) : nil }

        let report = CodexUsageReport(windows: windows,
                                      plan: CodexUsageParser.plan(from: data) ?? credential.plan,
                                      resetCredits: resets, daily: daily, fetchedAt: .now, source: .web)
        return .ok(report, email: credential.email)
    }

    nonisolated private static func get(_ path: String, _ c: CodexAuth.Credential, _ session: URLSession,
                                        beta: Bool = false) async -> (Data, HTTPURLResponse)? {
        guard let url = URL(string: "https://chatgpt.com/backend-api/wham/\(path)") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(c.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(c.accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")
        if beta { request.setValue("codex-1", forHTTPHeaderField: "OpenAI-Beta") }
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return nil }
        return (data, http)
    }

    // MARK: Activity

    /// Starts watching the session log, once.
    func startActivity() {
        guard activityTimer == nil else { return }
        scanActivity()
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scanActivity() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        activityTimer = timer
    }

    private func scanActivity() {
        guard !scanning else { return }
        scanning = true
        Task {
            let list = await Task.detached(priority: .utility) { Self.readSessions(now: .now) }.value
            scanning = false
            apply(sessions: list)
        }
    }

    private func apply(sessions list: [CodexSession]) {
        let states = Dictionary(list.map { ($0.id, $0.state) }, uniquingKeysWith: { first, _ in first })
        for change in CodexChime.events(previous: previousStates, current: states) {
            remind(change.event, session: list.first { $0.id == change.session })
        }
        previousStates = states
        scannedAt = .now
        if list != sessions { sessions = list }
        let overall = CodexSessionList.overall(list)
        if overall != activity { activity = overall }
        let project = CodexSessionList.lead(list)?.project
        if project != activityProject { activityProject = project }
    }

    /// 一个会话进入等你确认或做完一轮：按横幅开关和声音设置发一条系统通知。
    private func remind(_ event: CodexChime.Event, session: CodexSession?) {
        let delivery = CodexChime.delivery(event, banner: notifyDone, settings: chime)
        let now = Date.now
        guard delivery.post, gate.allow("\(session?.id ?? "-").\(event.rawValue)", at: now) else { return }
        let sound = delivery.sound && gate.allowSound(at: now)
        let project = session?.project
        switch event {
        case .waiting:
            let what = session?.doing?.text ?? tr("有一条命令或修改需要你批准。")
            post(id: "docket.codex.waiting.\(session?.id ?? "")", title: tr("Codex 在等你确认"),
                 body: project.map { "\($0) · \(what)" } ?? what, sound: sound)
        case .done:
            post(id: "docket.codex.done.\(session?.id ?? "")", title: tr("Codex 已完成"),
                 body: project.map { tr("\($0) 里的任务已经完成。") } ?? tr("当前任务已经完成。"), sound: sound)
        case .quota:
            break
        }
    }

    /// 卡片上原来只看最新一个会话；现在是总状态和排第一的会话的项目名。
    nonisolated static func readActivity(now: Date) -> (state: CodexActivity, project: String?) {
        let list = readSessions(now: now)
        return (CodexSessionList.overall(list), CodexSessionList.lead(list)?.project)
    }

    /// 今天和昨天的文件夹里，最近一小时写过的会话记录，每个读开头和末尾。
    nonisolated static func readSessions(now: Date) -> [CodexSession] {
        let fm = FileManager.default
        let sessionsDir = home.appendingPathComponent("sessions")
        var list: [CodexSession] = []
        for folder in CodexRollout.dayFolders(now: now) {
            let dir = sessionsDir.appendingPathComponent(folder)
            guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for name in names where name.hasSuffix(".jsonl") {
                let url = dir.appendingPathComponent(name)
                guard let modified = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date,
                      now.timeIntervalSince(modified) < CodexSessionList.recentWindow else { continue }
                let meta = CodexRollout.meta(inHead: head(url, bytes: 64 * 1024))
                let tail = CodexRollout.summary(inTail: tail(url, bytes: 512 * 1024))
                if let session = CodexSession.make(id: name, meta: meta, tail: tail, modified: modified, now: now) {
                    list.append(session)
                }
            }
        }
        return CodexSessionList.sorted(list)
    }

    /// The end of a log that can run to hundreds of megabytes.
    nonisolated private static func tail(_ url: URL, bytes: UInt64) -> Data {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return Data() }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd() else { return Data() }
        let start = end > bytes ? end - bytes : 0
        guard (try? handle.seek(toOffset: start)) != nil else { return Data() }
        return (try? handle.readToEnd()) ?? Data()
    }

    nonisolated private static func head(_ url: URL, bytes: Int) -> Data {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return Data() }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: bytes)) ?? Data()
    }

    // MARK: Stats

    /// 读今天和本周的统计，五分钟一次（面板开着时才叫）。
    func loadStats(force: Bool = false) {
        let now = Date.now
        if !force, let statsAt, now.timeIntervalSince(statsAt) < 300 { return }
        guard !statsLoading else { return }
        statsLoading = true
        statsAt = now
        let cache = statsCache
        Task {
            let result = await Task.detached(priority: .utility) { Self.readStats(now: now, cache: cache) }.value
            statsLoading = false
            statsCache = result.cache
            stats = CodexStats.buckets(result.records, now: now)
        }
    }

    /// 本周每个主会话一条记录。按路径缓存，文件大小和修改时间都没变就不重读。
    /// 超过 64 MB 的记录不数时长（读起来太久），这一格的时长就不显示。
    nonisolated static func readStats(now: Date, cache: [String: CodexStatsCacheEntry])
        -> (records: [CodexSessionRecord], cache: [String: CodexStatsCacheEntry]) {
        let fm = FileManager.default
        let sessionsDir = home.appendingPathComponent("sessions")
        var records: [CodexSessionRecord] = []
        var next: [String: CodexStatsCacheEntry] = [:]
        for folder in CodexStats.weekFolders(now: now) {
            let dir = sessionsDir.appendingPathComponent(folder)
            guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for name in names where name.hasSuffix(".jsonl") {
                let url = dir.appendingPathComponent(name)
                guard let attrs = try? fm.attributesOfItem(atPath: url.path),
                      let modified = attrs[.modificationDate] as? Date else { continue }
                let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
                if let hit = cache[url.path], hit.size == size, hit.modified == modified {
                    next[url.path] = hit
                    if let record = hit.record { records.append(record) }
                    continue
                }
                let meta = CodexRollout.meta(inHead: head(url, bytes: 64 * 1024))
                var record: CodexSessionRecord?
                if meta?.isSubagent != true {
                    let started = meta?.startedAt ?? (attrs[.creationDate] as? Date) ?? modified
                    let seconds = size <= 64 * 1024 * 1024
                        ? (try? Data(contentsOf: url, options: .mappedIfSafe)).flatMap(CodexRollout.activeSeconds(inLog:))
                        : nil
                    let tokens = CodexRollout.summary(inTail: tail(url, bytes: 256 * 1024)).totalTokens
                    // 一轮都没开始的会话（开了就关）不算。
                    if seconds != nil || tokens != nil {
                        record = CodexSessionRecord(startedAt: started, activeSeconds: seconds, tokens: tokens)
                    }
                }
                next[url.path] = CodexStatsCacheEntry(size: size, modified: modified, record: record)
                if let record { records.append(record) }
            }
        }
        return (records, next)
    }

    // MARK: Terminal

    /// 「打开终端」「去终端」：把开着这个会话的终端（或编辑器、Codex 应用）叫到
    /// 前台；都没开着时打开系统「终端」。Codex 不让别的程序替你点允许。
    func openTerminal(for session: CodexSession? = nil) {
        let running = NSWorkspace.shared.runningApplications
        let id = CodexTerminal.target(host: CodexTerminal.host(originator: session?.originator),
                                      running: running.compactMap(\.bundleIdentifier))
        if let app = running.first(where: { $0.bundleIdentifier == id }) {
            app.activate()
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// 设置里「允许通知」：还没问过时请系统弹一次授权框。
    func requestNotificationPermission() {
        askedPermission = true
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            await NotificationAccessMonitor.shared.refresh()
        }
    }

    // MARK: Notifications

    private func alertIfNeeded(_ fresh: CodexUsageReport) {
        for w in fresh.ringWindows {
            defer { lastAlerted[w.id] = w.usedFraction }
            guard let hit = CodexChime.quota(previous: lastAlerted[w.id], current: w.usedFraction,
                                             bannerOn: notifyQuota, alertAt: alertFirst, soundOn: chime.quota)
            else { continue }
            let key = "quota.\(w.id).\(Int((hit.hit * 100).rounded()))"
            guard gate.allow(key, at: .now) else { continue }
            let reset = w.resetsAt.map { tr("，\(CodexPace.duration($0.timeIntervalSinceNow))后重置") } ?? ""
            let title = hit.hit >= 1 ? tr("Codex \(w.label)已用完") : tr("Codex \(w.label)已用 \(Int((hit.hit * 100).rounded()))%")
            post(id: "docket.codex.quota.\(w.id)", title: title,
                 body: tr("剩余 \(GaugeReading.percent(w.remainingFraction))\(reset)。"),
                 sound: hit.sound && gate.allowSound(at: .now))
        }
    }

    /// 发一条系统通知。`sound` 为真时带上设置里选的 macOS 提示音，勿扰和专注
    /// 模式由系统自己挡；为假时不出声。
    private func post(id: String, title: String, body: String, sound: Bool) {
        let center = UNUserNotificationCenter.current()
        if center.delegate == nil { center.delegate = presenter }
        let ask = !askedPermission
        askedPermission = true
        let tone = chime.tone
        Task {
            if ask { _ = try? await center.requestAuthorization(options: [.alert, .sound]) }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            if sound { content.sound = Self.notificationSound(tone) }
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        }
    }

    /// 系统通知只认本应用目录、~/Library/Sounds 和应用包里的声音文件，读不到
    /// /System/Library/Sounds。所以把选中的那个系统提示音复制一份到
    /// ~/Library/Sounds/Dockling-<名字>.aiff（不打包、不改系统文件），换了提示音
    /// 就删掉旧的那份。复制不成时用系统默认提示音。
    private static func notificationSound(_ tone: String) -> UNNotificationSound {
        let fm = FileManager.default
        let dir = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Sounds")
        let name = "Dockling-\(tone).aiff"
        let dest = dir.appendingPathComponent(name)
        if !fm.fileExists(atPath: dest.path) {
            let source = URL(fileURLWithPath: "/System/Library/Sounds/\(tone).aiff")
            guard fm.fileExists(atPath: source.path) else { return .default }
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            guard (try? fm.copyItem(at: source, to: dest)) != nil else { return .default }
            for old in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
            where old.hasPrefix("Dockling-") && old.hasSuffix(".aiff") && old != name {
                try? fm.removeItem(at: dir.appendingPathComponent(old))
            }
        }
        return UNNotificationSound(named: UNNotificationSoundName(name))
    }
}

/// 统计缓存的一条：文件大小、修改时间都没变就直接用上次读的结果。
struct CodexStatsCacheEntry: Sendable {
    var size: UInt64
    var modified: Date
    var record: CodexSessionRecord?
}
