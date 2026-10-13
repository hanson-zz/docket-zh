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
/// Activity is read from the end of Codex's newest session log every few
/// seconds; nothing is sent anywhere for it.
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
            case .notSignedIn: "没有找到 Codex 的 ChatGPT 登录。请在终端运行 codex login，或打开 Codex 应用登录。"
            case .expired: "Codex 的登录已过期。打开 Codex 用一次即可自动续期。"
            case .offline: "无法连接 chatgpt.com。国内网络需要代理，可在详情面板里填写代理地址。"
            case .rateLimited(let until): "请求太频繁，\(CodexPace.duration(until.timeIntervalSinceNow))后再试。"
            case .server(let code): "chatgpt.com 返回错误 \(code)，可能是接口有变动。"
            case .unreadable: "读不懂 chatgpt.com 的返回内容，可能是接口有变动。"
            }
        }
    }

    private(set) var report: CodexUsageReport?
    private(set) var problem: Problem?
    private(set) var loading = false
    private(set) var email: String?
    private(set) var activity: CodexActivity = .idle
    /// The newest session's working folder, when its log names one.
    private(set) var activityProject: String?

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
        let read = Self.readActivity(now: .now)
        if read.state == .done, activity == .working || activity == .waiting, notifyDone {
            post(id: "docket.codex.done", title: "Codex 已完成", body: read.project.map { "\($0) 里的任务已经完成。" } ?? "当前任务已经完成。")
        }
        if read.state == .waiting, activity != .waiting, notifyDone {
            post(id: "docket.codex.waiting", title: "Codex 在等你确认", body: "有一条命令或修改需要你批准。")
        }
        if read.state != activity { activity = read.state }
        if read.project != activityProject { activityProject = read.project }
    }

    nonisolated static func readActivity(now: Date) -> (state: CodexActivity, project: String?) {
        let fm = FileManager.default
        let sessions = home.appendingPathComponent("sessions")
        var newest: (url: URL, modified: Date)?
        for folder in CodexRollout.dayFolders(now: now) {
            let dir = sessions.appendingPathComponent(folder)
            guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for name in names where name.hasSuffix(".jsonl") {
                let url = dir.appendingPathComponent(name)
                guard let date = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date else { continue }
                if newest == nil || date > newest!.modified { newest = (url, date) }
            }
        }
        guard let newest else { return (.idle, nil) }
        let event = CodexRollout.lastEvent(inTail: tail(newest.url, bytes: 512 * 1024))
        let state = CodexRollout.state(lastEvent: event, modified: newest.modified, now: now)
        return (state, project(newest.url))
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

    /// The folder name from the log's first line (`session_meta.cwd`).
    nonisolated private static func project(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 64 * 1024),
              let line = head.split(separator: UInt8(ascii: "\n")).first,
              let record = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
              let payload = record["payload"] as? [String: Any],
              let cwd = payload["cwd"] as? String, !cwd.isEmpty else { return nil }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    // MARK: Notifications

    private func alertIfNeeded(_ fresh: CodexUsageReport) {
        let thresholds = CodexAlert.thresholds(first: alertFirst)
        for w in fresh.ringWindows {
            defer { lastAlerted[w.id] = w.usedFraction }
            guard notifyQuota,
                  let hit = CodexAlert.crossed(previous: lastAlerted[w.id], current: w.usedFraction,
                                               thresholds: thresholds) else { continue }
            let reset = w.resetsAt.map { "，\(CodexPace.duration($0.timeIntervalSinceNow))后重置" } ?? ""
            let title = hit >= 1 ? "Codex \(w.label)已用完" : "Codex \(w.label)已用 \(Int((hit * 100).rounded()))%"
            post(id: "docket.codex.quota.\(w.id)", title: title, body: "剩余 \(GaugeReading.percent(w.remainingFraction))\(reset)。")
        }
    }

    private func post(id: String, title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        if center.delegate == nil { center.delegate = presenter }
        let ask = !askedPermission
        askedPermission = true
        Task {
            if ask { _ = try? await center.requestAuthorization(options: [.alert, .sound]) }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        }
    }
}
