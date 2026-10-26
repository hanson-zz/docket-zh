import Foundation
import Observation
@preconcurrency import UserNotifications

/// The repositories the GitHub widgets follow: their numbers, their newest
/// issues, pull requests and comments, their latest releases, and what is new
/// since each was last marked read. With a token in the keychain, also the
/// signed-in user's unread notifications.
///
/// Unauthenticated, api.github.com allows 60 requests an hour per address,
/// and a `304 Not Modified` only goes uncounted for an authorised request. So
/// every response is cached on disk with its ETag and asked for again with
/// `If-None-Match` (cheap, and free with a token), releases and the open pull
/// request count are read at most every two hours without a token, and the
/// interval is stretched when many projects are followed
/// (`GitHubWatch.effectiveInterval`). A 403 or 429 for the rate stops every
/// request until GitHub says to try again.
///
/// What was last seen of each repository is the user's own state, so it is
/// kept in Application Support rather than with the disposable cache, keyed
/// by repository: two widgets following one repository share it.
@MainActor @Observable
final class GitHubService {
    static let shared = GitHubService()
    nonisolated static let tokenAccount = "github-token"

    struct RepoState: Equatable {
        var stats: GitHubStats?
        var issues: [GitHubFeedItem] = []
        var comments: [GitHubFeedItem] = []
        var releases: [GitHubRelease]?
        var error: String?
        /// 最近一次读这个仓库时没连上 GitHub（断网或请求失败）。有旧数据时照常显示，
        /// 面板据此在上面加一条“离线”的插头横幅。
        var offline = false
        var updated: Date?

        var items: [GitHubFeedItem] { GitHubFeed.merged([issues, comments]) }
    }

    struct Failure: Error, Equatable { var message: String }

    private(set) var states: [String: RepoState] = [:]
    private(set) var seen: [String: GitHubSeen] = [:]
    private(set) var notifications: Int?
    /// 只看钥匙串里有没有这一项，不读内容，启动时不会弹钥匙串授权框。
    private(set) var hasToken = KeychainStore.exists(GitHubService.tokenAccount)
    private(set) var loading: Set<String> = []
    /// Set while GitHub has refused for the rate; nothing is asked before it.
    private(set) var limitedUntil: Date?

    @ObservationIgnored private var plan = GitHubWatch.Plan()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastFetch: [String: Date] = [:]
    @ObservationIgnored private var lastSlow: [String: Date] = [:]
    /// The newest item already notified about, per repository. Set by the
    /// first read in this session, so a launch never announces old news.
    @ObservationIgnored private var watermark: [String: Date] = [:]
    @ObservationIgnored private var cache: [String: CachedResponse] = [:]
    @ObservationIgnored private var cacheLoaded = false
    @ObservationIgnored private var queue: [String] = []
    @ObservationIgnored private var draining = false
    @ObservationIgnored private var askedPermission = false
    @ObservationIgnored private let presenter = BannerPresenter()

    private init() {
        seen = Self.readSeen()
    }

    // MARK: Token

    func setToken(_ token: String?) {
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            KeychainStore.delete(Self.tokenAccount)
            notifications = nil
        } else {
            KeychainStore.write(trimmed, for: Self.tokenAccount)
            // A token is a different identity with its own limit.
            limitedUntil = nil
        }
        hasToken = !trimmed.isEmpty
        lastFetch = [:]
        lastSlow = [:]
    }

    // MARK: Schedule

    /// What the shelf's GitHub widgets follow, set whenever it changes.
    /// Checks run on this service's own clock rather than the tiles', so a
    /// widget hidden until there is new feedback still finds out there is.
    func schedule(_ plan: GitHubWatch.Plan) {
        let added = plan.repos.filter { states[GitHubWatch.key($0)] == nil }
        self.plan = plan
        if !plan.notifyKeys.isEmpty { askPermissionOnce() }
        guard !plan.isEmpty else {
            timer?.invalidate()
            timer = nil
            return
        }
        for repo in added { refresh(repo) }
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        for repo in plan.repos { refresh(repo) }
    }

    /// Minutes between checks of one repository right now.
    private var intervalMinutes: Int {
        GitHubWatch.effectiveInterval(minutes: plan.isEmpty ? GitHubWatch.defaultInterval : plan.interval,
                                      repoCount: max(1, plan.repos.count), authenticated: hasToken)
    }

    /// Queues `slug` unless it was read within the interval. Requests go one
    /// at a time, as GitHub asks of anything polling it.
    func refresh(_ slug: String, force: Bool = false) {
        guard let parsed = GitHubWatch.slug(from: slug) else { return }
        let key = GitHubWatch.key(parsed)
        let now = Date.now
        if !force, let last = lastFetch[key],
           now.timeIntervalSince(last) < Double(intervalMinutes * 60) { return }
        guard !loading.contains(key), !queue.contains(parsed) else { return }
        lastFetch[key] = now
        queue.append(parsed)
        drain(forceSlow: force)
    }

    func refreshAll(_ slugs: [String], force: Bool = false) {
        for slug in slugs { refresh(slug, force: force) }
    }

    private func drain(forceSlow: Bool) {
        guard !draining else { return }
        draining = true
        Task {
            while !queue.isEmpty {
                let slug = queue.removeFirst()
                await load(slug, forceSlow: forceSlow)
            }
            await loadNotifications()
            draining = false
        }
    }

    // MARK: Reading a repository

    private func load(_ slug: String, forceSlow: Bool) async {
        let key = GitHubWatch.key(slug)
        loading.insert(key)
        defer { loading.remove(key) }
        let token = KeychainStore.read(Self.tokenAccount)
        var state = states[key] ?? RepoState()

        switch await fetch("https://api.github.com/repos/\(slug)", token: token) {
        case .data(let data):
            guard var stats = GitHubStats.parseRepository(data) else {
                state.error = tr("GitHub 返回的数据无法读取")
                states[key] = state
                return
            }
            stats.openPulls = state.stats?.openPulls
            state.stats = stats
            state.error = nil
            state.offline = false
        case .failed(let status):
            state.offline = false
            state.error = switch status {
            case 404: tr("找不到这个仓库（或它是私有仓库）")
            case 401: tr("令牌无效")
            default: tr("GitHub 返回错误 \(status)")
            }
            states[key] = state
            return
        case .limited(let until):
            state.offline = false
            state.error = GitHubRateLimit.waitText(until: until, now: .now)
            states[key] = state
            return
        case .offline:
            state.offline = true
            state.error = state.stats == nil ? tr("无法连接 GitHub") : nil
            states[key] = state
            return
        }

        if case .data(let data) = await fetch(
            "https://api.github.com/repos/\(slug)/issues?state=all&sort=created&direction=desc&per_page=30",
            token: token), let issues = GitHubFeed.parseIssues(data) {
            state.issues = issues
        }

        // A month back from what was last seen, rounded to the day, so the
        // address (and with it the ETag) only changes when it is marked read.
        let from = Calendar(identifier: .gregorian).startOfDay(
            for: (seen[key]?.at ?? .now).addingTimeInterval(-30 * 86_400))
        let since = from.formatted(.iso8601)
        if case .data(let data) = await fetch(
            "https://api.github.com/repos/\(slug)/issues/comments?sort=created&direction=desc&per_page=30&since=\(since)",
            token: token) {
            let titles = Dictionary(state.issues.compactMap { item in item.number.map { ($0, item.title) } },
                                    uniquingKeysWith: { a, _ in a })
            if let comments = GitHubFeed.parseComments(data, titles: titles) { state.comments = comments }
        }

        let slowDue = forceSlow || token != nil || state.releases == nil
            || Date.now.timeIntervalSince(lastSlow[key] ?? .distantPast) > 2 * 3600
        if slowDue {
            lastSlow[key] = .now
            if case .data(let data) = await fetch("https://api.github.com/repos/\(slug)/releases?per_page=5",
                                                  token: token),
               let releases = GitHubFeed.parseReleases(data) {
                state.releases = releases
            }
            let query = "repo:\(slug) type:pr state:open"
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if case .data(let data) = await fetch("https://api.github.com/search/issues?q=\(query)&per_page=1",
                                                  token: token),
               let total = GitHubStats.parseSearchTotal(data) {
                state.stats?.openPulls = total
            }
        }

        state.updated = .now
        states[key] = state
        settleSeen(key, state)
        notifyIfNew(slug, key: key, state: state)
    }

    /// The first read of a repository is the baseline: nothing in it is new.
    /// Downloads join the baseline the first time releases are known.
    private func settleSeen(_ key: String, _ state: RepoState) {
        if var existing = seen[key] {
            guard existing.downloads == nil, let releases = state.releases else { return }
            existing.downloads = GitHubFeed.totalDownloads(releases)
            seen[key] = existing
        } else {
            seen[key] = GitHubFeed.seen(at: .now, stats: state.stats, releases: state.releases)
        }
        Self.writeSeen(seen)
    }

    private func notifyIfNew(_ slug: String, key: String, state: RepoState) {
        let items = state.items
        let newest = items.map(\.createdAt).max() ?? .now
        guard let mark = watermark[key] else {
            // First read in this session: remember where it stands, say nothing.
            watermark[key] = max(newest, .now)
            return
        }
        let fresh = GitHubFeed.toNotify(items, after: mark, seen: seen[key])
        watermark[key] = max(mark, newest)
        guard plan.notifyKeys.contains(key),
              let text = GitHubFeed.notificationText(repo: state.stats?.fullName ?? slug, items: fresh)
        else { return }
        post(key: key, title: text.title, body: text.body, url: fresh.first?.url)
    }

    private func loadNotifications() async {
        guard let token = KeychainStore.read(Self.tokenAccount) else {
            notifications = nil
            return
        }
        switch await fetch("https://api.github.com/notifications?per_page=50", token: token) {
        case .data(let data): notifications = GitHubStats.parseNotificationCount(data)
        case .failed: notifications = nil
        case .limited, .offline: break
        }
    }

    // MARK: Adding

    /// Whether a repository exists and can be read, before it is added.
    /// The name comes back as GitHub spells it.
    func validate(_ slug: String) async -> Result<String, Failure> {
        let token = KeychainStore.read(Self.tokenAccount)
        switch await fetch("https://api.github.com/repos/\(slug)", token: token) {
        case .data(let data):
            guard let stats = GitHubStats.parseRepository(data) else {
                return .failure(Failure(message: tr("GitHub 返回的数据无法读取")))
            }
            var state = states[GitHubWatch.key(stats.fullName)] ?? RepoState()
            state.stats = stats
            states[GitHubWatch.key(stats.fullName)] = state
            return .success(stats.fullName)
        case .failed(let status):
            let message = switch status {
            case 404: tr("找不到这个仓库（或它是私有仓库）")
            case 401: tr("令牌无效，请在下方更换或移除")
            default: tr("GitHub 返回错误 \(status)")
            }
            return .failure(Failure(message: message))
        case .limited(let until):
            return .failure(Failure(message: GitHubRateLimit.waitText(until: until, now: .now)))
        case .offline:
            return .failure(Failure(message: tr("无法连接 GitHub，请检查网络")))
        }
    }

    // MARK: Reading back

    func state(for slug: String) -> RepoState? {
        GitHubWatch.slug(from: slug).flatMap { states[GitHubWatch.key($0)] }
    }

    func stats(for slug: String) -> GitHubStats? { state(for: slug)?.stats }

    func error(for slug: String) -> String? {
        guard GitHubWatch.slug(from: slug) != nil else { return tr("仓库格式应为“用户/仓库”") }
        if let limitedUntil, limitedUntil > .now, state(for: slug)?.stats == nil {
            return GitHubRateLimit.waitText(until: limitedUntil, now: .now)
        }
        return state(for: slug)?.error
    }

    /// 最近一次读这个仓库时没连上 GitHub。
    func isOffline(_ slug: String) -> Bool {
        state(for: slug)?.offline == true
    }

    /// 这个仓库正在读或排在队里。
    func isLoading(_ slug: String) -> Bool {
        guard let parsed = GitHubWatch.slug(from: slug) else { return false }
        return loading.contains(GitHubWatch.key(parsed)) || queue.contains(parsed)
    }

    func seenState(for slug: String) -> GitHubSeen? {
        GitHubWatch.slug(from: slug).flatMap { seen[GitHubWatch.key($0)] }
    }

    func feedback(for slug: String) -> GitHubFeedback {
        let state = self.state(for: slug)
        return GitHubFeed.feedback(items: state?.items ?? [], stats: state?.stats,
                                   releases: state?.releases, seen: seenState(for: slug))
    }

    func totalFeedback(_ slugs: [String]) -> Int {
        slugs.reduce(0) { $0 + feedback(for: $1).total }
    }

    /// New feedback per repository read so far, for the display condition.
    var feedbackCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for (key, state) in states where state.stats != nil {
            counts[key] = GitHubFeed.feedback(items: state.items, stats: state.stats,
                                              releases: state.releases, seen: seen[key]).total
        }
        return counts
    }

    var isLimited: Bool { (limitedUntil ?? .distantPast) > .now }

    // MARK: Marking read

    func markRead(_ slug: String) {
        guard let parsed = GitHubWatch.slug(from: slug) else { return }
        let key = GitHubWatch.key(parsed)
        let state = states[key]
        seen[key] = GitHubFeed.seen(at: .now, stats: state?.stats, releases: state?.releases,
                                    previous: seen[key])
        Self.writeSeen(seen)
        let id = "docket.github.\(key)"
        Task {
            let center = UNUserNotificationCenter.current()
            let delivered = await center.deliveredNotifications()
            let ids = delivered.filter { $0.request.content.threadIdentifier == id }.map(\.request.identifier)
            center.removeDeliveredNotifications(withIdentifiers: ids)
        }
    }

    func markAllRead(_ slugs: [String]) {
        for slug in slugs { markRead(slug) }
    }

    // MARK: Notifications

    private func askPermissionOnce() {
        guard !askedPermission else { return }
        askedPermission = true
        let center = UNUserNotificationCenter.current()
        if center.delegate == nil { center.delegate = presenter }
        Task { _ = try? await center.requestAuthorization(options: [.alert, .sound]) }
    }

    /// One banner per repository per check, grouped by repository.
    private func post(key: String, title: String, body: String, url: URL?) {
        let center = UNUserNotificationCenter.current()
        if center.delegate == nil { center.delegate = presenter }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = "docket.github.\(key)"
        if let url { content.userInfo = ["url": url.absoluteString] }
        let request = UNNotificationRequest(identifier: "docket.github.\(key).\(Int(Date.now.timeIntervalSince1970))",
                                            content: content, trigger: nil)
        Task { try? await center.add(request) }
    }

    // MARK: Requests

    private enum Fetched {
        case data(Data)
        case failed(Int)
        case limited(Date)
        case offline
    }

    struct CachedResponse: Codable {
        var etag: String
        var body: Data
    }

    /// A GET with the cached ETag. A 304 answers with the cached body.
    private func fetch(_ address: String, token: String?) async -> Fetched {
        if let limitedUntil, limitedUntil > .now { return .limited(limitedUntil) }
        guard let url = URL(string: address) else { return .failed(0) }
        loadCacheOnce()
        // Cached per identity: a token can see what anonymous requests cannot.
        let cacheKey = (token == nil ? "anon " : "auth ") + address
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Dockling (https://github.com/hanson-zz/docket-zh)", forHTTPHeaderField: "User-Agent")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let cached = cache[cacheKey] { request.setValue(cached.etag, forHTTPHeaderField: "If-None-Match") }

        guard let response = await Self.send(request) else { return .offline }
        switch response.status {
        case 200:
            if let etag = response.headers["etag"] {
                cache[cacheKey] = CachedResponse(etag: etag, body: response.data)
                Self.writeCache(cache)
            }
            return .data(response.data)
        case 304:
            if let cached = cache[cacheKey] { return .data(cached.body) }
            return .failed(304)
        default:
            if let until = GitHubRateLimit.retryAt(status: response.status, headers: response.headers, now: .now) {
                limitedUntil = until
                return .limited(until)
            }
            return .failed(response.status)
        }
    }

    /// No shared URL cache: the ETags are handled here, and a cache that
    /// answered 304s itself would hide them.
    private nonisolated static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    /// The status and headers (names lowercased) come back as plain values,
    /// so nothing that is not Sendable crosses back to the main actor.
    private struct Response: Sendable {
        var data: Data
        var status: Int
        var headers: [String: String]
    }

    private nonisolated static func send(_ request: URLRequest) async -> Response? {
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return nil }
        var headers: [String: String] = [:]
        for (name, value) in http.allHeaderFields {
            if let name = name as? String { headers[name.lowercased()] = "\(value)" }
        }
        return Response(data: data, status: http.statusCode, headers: headers)
    }

    // MARK: Disk

    private static var cacheURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("com.docket-zh.app", isDirectory: true)
            .appendingPathComponent("github-responses.json")
    }

    private static var seenURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("com.docket-zh.app", isDirectory: true)
            .appendingPathComponent("github-seen.json")
    }

    private func loadCacheOnce() {
        guard !cacheLoaded else { return }
        cacheLoaded = true
        guard let url = Self.cacheURL, let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: CachedResponse].self, from: data) else { return }
        cache = decoded
    }

    private static func writeCache(_ cache: [String: CachedResponse]) {
        write(cache, to: cacheURL, dates: false)
    }

    private static func readSeen() -> [String: GitHubSeen] {
        guard let url = seenURL, let data = try? Data(contentsOf: url) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: GitHubSeen].self, from: data)) ?? [:]
    }

    private static func writeSeen(_ seen: [String: GitHubSeen]) {
        write(seen, to: seenURL, dates: true)
    }

    private static func write<T: Encodable>(_ value: T, to url: URL?, dates: Bool) {
        guard let url else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        if dates { encoder.dateEncodingStrategy = .iso8601 }
        if let data = try? encoder.encode(value) { try? data.write(to: url, options: .atomic) }
    }
}
