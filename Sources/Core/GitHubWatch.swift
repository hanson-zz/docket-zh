import Foundation

// MARK: - The list of projects

/// The GitHub widget's list of followed repositories, and everything about
/// "what is new since I last looked" that can be worked out without a network.
///
/// The widget used to follow one repository under `repo`. It now follows up to
/// `maxRepos` under `repos`; a saved widget still carrying `repo` is moved
/// across once, when it is decoded (see `migratingRepo`).
public enum GitHubWatch {
    public static let defaultRepo = "hanson-zz/docket-zh"
    public static let maxRepos = 8
    public static let reposKey = "repos"
    public static let legacyRepoKey = "repo"
    public static let notifyKey = "notify"
    public static let intervalKey = "interval"
    /// Minutes between checks, offered in the settings.
    public static let intervalChoices = [15, 30, 60]
    public static let defaultInterval = 30

    /// "owner/repo" from anything a person might paste: the slug itself, a
    /// github.com URL to the repository or to one of its issues, pull
    /// requests or releases, a clone URL, or an api.github.com URL. Nil for
    /// anything that does not name a repository on GitHub.
    public static func slug(from text: String) -> String? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://", "http://", "git@github.com:"] where s.lowercased().hasPrefix(prefix) {
            s.removeFirst(prefix.count)
        }
        if s.lowercased().hasPrefix("api.github.com/repos/") {
            s.removeFirst("api.github.com/repos/".count)
        }
        // Another host is not GitHub. GitHub user names cannot contain a dot,
        // so a first part with one in it is a host, and only GitHub's own
        // host may come before the owner.
        if let first = s.split(separator: "/").first, first.contains("."),
           !["github.com", "www.github.com"].contains(first.lowercased()) {
            return nil
        }
        guard let parsed = RepoSlug.parse(s), !parsed.owner.contains(".") else { return nil }
        return "\(parsed.owner)/\(parsed.repo)"
    }

    /// The key two spellings of one repository share: GitHub ignores case.
    public static func key(_ slug: String) -> String { slug.lowercased() }

    /// The repositories a widget follows, in its order, without repeats, at
    /// most `maxRepos`. A widget with none (or none that parse) follows the
    /// default, so the tile never has nothing to show.
    public static func repos(_ config: WidgetConfig) -> [String] {
        let raw: [String]
        if case .list = config.values[reposKey] {
            raw = config.strings(reposKey)
        } else if case .string(let one) = config.values[legacyRepoKey] {
            raw = [one]
        } else {
            raw = []
        }
        let list = cleaned(raw)
        return list.isEmpty ? [defaultRepo] : list
    }

    /// Parsed, deduplicated ignoring case, and cut to the limit.
    public static func cleaned(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for text in raw {
            guard let parsed = Self.slug(from: text), seen.insert(key(parsed)).inserted else { continue }
            out.append(parsed)
            if out.count == maxRepos { break }
        }
        return out
    }

    public static func encode(_ repos: [String]) -> WidgetConfig.Value {
        .list(cleaned(repos).map { .string($0) })
    }

    /// The one-time move from `repo` to `repos`. A config that already has
    /// `repos` is left as it is; one without either is left for the catalog
    /// default to fill.
    public static func migratingRepo(_ config: WidgetConfig) -> WidgetConfig {
        var copy = config
        guard case .string(let old) = copy.values[legacyRepoKey] else { return copy }
        if copy.values[reposKey] == nil {
            let parsed = cleaned([old])
            copy.set(reposKey, encode(parsed.isEmpty ? [defaultRepo] : parsed))
        }
        copy.set(legacyRepoKey, nil)
        return copy
    }

    public enum AddError: Error, Equatable, Sendable {
        case invalid, duplicate, full

        public var message: String {
            switch self {
            case .invalid: tr("请输入“用户/仓库”或 GitHub 链接")
            case .duplicate: tr("这个项目已经在列表中")
            case .full: tr("最多关注 \(GitHubWatch.maxRepos) 个项目")
            }
        }
    }

    /// The list with `text` added at the end, or why it cannot be.
    /// Checked before the network is asked whether the repository exists.
    public static func adding(_ text: String, to repos: [String]) -> Result<[String], AddError> {
        guard let parsed = Self.slug(from: text) else { return .failure(.invalid) }
        if repos.contains(where: { key($0) == key(parsed) }) { return .failure(.duplicate) }
        if repos.count >= maxRepos { return .failure(.full) }
        return .success(repos + [parsed])
    }

    /// The list without one entry. The last one cannot be removed: a widget
    /// following nothing would silently fall back to the default.
    public static func removing(_ slug: String, from repos: [String]) -> [String] {
        let rest = repos.filter { key($0) != key(slug) }
        return rest.isEmpty ? repos : rest
    }

    /// One entry moved one place towards the start (`by: -1`) or end (`1`).
    public static func moving(_ slug: String, by offset: Int, in repos: [String]) -> [String] {
        guard let from = repos.firstIndex(where: { key($0) == key(slug) }) else { return repos }
        let to = min(max(from + offset, 0), repos.count - 1)
        guard to != from else { return repos }
        var copy = repos
        copy.swapAt(from, to)
        return copy
    }

    public static func notifies(_ config: WidgetConfig) -> Bool {
        config.bool(notifyKey, default: false)
    }

    /// Minutes between checks; anything not offered reads as the default.
    public static func interval(_ config: WidgetConfig) -> Int {
        let raw = Int(config.string(intervalKey, default: "\(defaultInterval)")) ?? defaultInterval
        return intervalChoices.contains(raw) ? raw : defaultInterval
    }

    /// What every request costs per repository per check, unauthenticated.
    /// The repository, its newest issues and its newest comments; releases
    /// and the open pull request count are fetched less often.
    public static let requestsPerRepo = 3
    /// What a check may spend of GitHub's 60 an hour without a token, with
    /// room left for the update check and the slow endpoints.
    public static let hourlyBudget = 45

    /// The interval actually used. With a token GitHub allows 5,000 an hour
    /// and the choice stands; without one, many projects at a short interval
    /// would run out, so the checks are spread out instead.
    public static func effectiveInterval(minutes: Int, repoCount: Int, authenticated: Bool) -> Int {
        guard !authenticated, repoCount > 0 else { return minutes }
        let perHour = requestsPerRepo * repoCount
        let needed = Int((Double(perHour) * 60 / Double(hourlyBudget)).rounded(.up))
        return max(minutes, needed)
    }

    /// What the shelf as a whole asks the service to keep fresh: every
    /// repository any GitHub widget follows, at the shortest interval any of
    /// them asks for, with notifications for the repositories whose widget
    /// has them on.
    public struct Plan: Equatable, Sendable {
        public var repos: [String]
        public var interval: Int
        public var notifyKeys: Set<String>

        public init(repos: [String] = [], interval: Int = GitHubWatch.defaultInterval,
                    notifyKeys: Set<String> = []) {
            self.repos = repos
            self.interval = interval
            self.notifyKeys = notifyKeys
        }

        public var isEmpty: Bool { repos.isEmpty }
    }

    public static func plan(_ instances: [WidgetInstance]) -> Plan {
        var plan = Plan()
        var keys = Set<String>()
        var intervals: [Int] = []
        for instance in instances where instance.kind == .github {
            let followed = Self.repos(instance.config)
            intervals.append(Self.interval(instance.config))
            for repo in followed where keys.insert(key(repo)).inserted { plan.repos.append(repo) }
            if notifies(instance.config) { plan.notifyKeys.formUnion(followed.map { key($0) }) }
        }
        plan.interval = intervals.min() ?? defaultInterval
        return plan
    }

    /// "docket-zh" for one project, "3 个项目" for several.
    public static func tileTitle(_ repos: [String]) -> String {
        guard repos.count != 1 else { return RepoSlug.parse(repos[0])?.repo ?? repos[0] }
        return tr("\(repos.count) 个项目")
    }

    /// The red badge: nothing at zero, "99+" past ninety-nine.
    public static func badgeText(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return count > 99 ? "99+" : "\(count)"
    }
}

// MARK: - What came in

/// An issue, a pull request, or a comment on either.
public struct GitHubFeedItem: Equatable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Sendable {
        case issue, pull, comment

        public var symbol: String {
            switch self {
            case .issue: "smallcircle.filled.circle"
            case .pull: "arrow.triangle.pull"
            case .comment: "text.bubble"
            }
        }

        public var title: String {
            switch self {
            case .issue: tr("议题")
            case .pull: tr("拉取请求")
            case .comment: tr("评论")
            }
        }
    }

    public var id: String
    public var kind: Kind
    /// The issue or pull request number; for a comment, the one it is on.
    public var number: Int?
    public var title: String
    public var author: String
    public var createdAt: Date
    public var url: URL?
    public var labels: [String]

    public init(id: String, kind: Kind, number: Int?, title: String, author: String,
                createdAt: Date, url: URL?, labels: [String] = []) {
        self.id = id
        self.kind = kind
        self.number = number
        self.title = title
        self.author = author
        self.createdAt = createdAt
        self.url = url
        self.labels = labels
    }
}

/// A published release and how often its files were downloaded.
public struct GitHubRelease: Equatable, Sendable, Identifiable {
    public struct Asset: Equatable, Sendable {
        public var name: String
        public var downloads: Int

        public init(name: String, downloads: Int) {
            self.name = name
            self.downloads = downloads
        }
    }

    public var id: Int
    public var tag: String
    public var name: String
    public var publishedAt: Date?
    public var url: URL?
    public var assets: [Asset]

    public init(id: Int, tag: String, name: String, publishedAt: Date?, url: URL?, assets: [Asset]) {
        self.id = id
        self.tag = tag
        self.name = name
        self.publishedAt = publishedAt
        self.url = url
        self.assets = assets
    }

    public var downloads: Int { assets.reduce(0) { $0 + max(0, $1.downloads) } }
}

/// What the user had seen of a repository when they last marked it read:
/// when, and the counters at that moment, so stars, forks and downloads can
/// be told as a difference.
public struct GitHubSeen: Codable, Equatable, Sendable {
    public var at: Date
    public var stars: Int
    public var forks: Int
    /// Nil until the releases have been read once: releases are fetched
    /// less often than the rest, and counting every download ever made as
    /// new would be wrong.
    public var downloads: Int?

    public init(at: Date, stars: Int = 0, forks: Int = 0, downloads: Int? = nil) {
        self.at = at
        self.stars = stars
        self.forks = forks
        self.downloads = downloads
    }
}

/// The new things in one repository since `GitHubSeen`.
public struct GitHubFeedback: Equatable, Sendable {
    public var issues = 0
    public var pulls = 0
    public var comments = 0
    public var stars = 0
    public var forks = 0
    public var downloads = 0

    public init(issues: Int = 0, pulls: Int = 0, comments: Int = 0,
                stars: Int = 0, forks: Int = 0, downloads: Int = 0) {
        self.issues = issues
        self.pulls = pulls
        self.comments = comments
        self.stars = stars
        self.forks = forks
        self.downloads = downloads
    }

    /// The badge. Every kind of feedback counts, downloads included, since
    /// for a released app those are the most direct sign of interest.
    public var total: Int { issues + pulls + comments + stars + forks + downloads }

    /// Only what someone wrote: what a notification is about.
    public var written: Int { issues + pulls + comments }

    public static func + (a: GitHubFeedback, b: GitHubFeedback) -> GitHubFeedback {
        GitHubFeedback(issues: a.issues + b.issues, pulls: a.pulls + b.pulls,
                       comments: a.comments + b.comments, stars: a.stars + b.stars,
                       forks: a.forks + b.forks, downloads: a.downloads + b.downloads)
    }

    /// One line for the panel: "2 个议题 · 3 条评论 · 5 个星标".
    public var summary: String {
        var parts: [String] = []
        if issues > 0 { parts.append(tr("\(issues) 个议题")) }
        if pulls > 0 { parts.append(tr("\(pulls) 个拉取请求")) }
        if comments > 0 { parts.append(tr("\(comments) 条评论")) }
        if stars > 0 { parts.append(tr("\(stars) 个星标")) }
        if forks > 0 { parts.append(tr("\(forks) 个复刻")) }
        if downloads > 0 { parts.append(tr("\(downloads) 次下载")) }
        return parts.isEmpty ? tr("没有新反馈") : parts.joined(separator: " · ")
    }
}

public enum GitHubFeed {
    /// Whether an item came in after the user last looked.
    public static func isUnread(_ item: GitHubFeedItem, seen: GitHubSeen?) -> Bool {
        guard let seen else { return false }
        return item.createdAt > seen.at
    }

    /// Counts everything since `seen`. Counters that went down (a star
    /// taken back, an old release dropping out of the five read) count as
    /// nothing rather than as negative feedback.
    public static func feedback(items: [GitHubFeedItem], stats: GitHubStats?,
                                releases: [GitHubRelease]?, seen: GitHubSeen?) -> GitHubFeedback {
        guard let seen else { return GitHubFeedback() }
        var result = GitHubFeedback()
        for item in items where item.createdAt > seen.at {
            switch item.kind {
            case .issue: result.issues += 1
            case .pull: result.pulls += 1
            case .comment: result.comments += 1
            }
        }
        if let stats {
            result.stars = max(0, stats.stars - seen.stars)
            result.forks = max(0, stats.forks - seen.forks)
        }
        if let releases, let base = seen.downloads {
            result.downloads = max(0, totalDownloads(releases) - base)
        }
        return result
    }

    /// The baseline as of now: what "mark all read" stores.
    public static func seen(at now: Date, stats: GitHubStats?, releases: [GitHubRelease]?,
                            previous: GitHubSeen? = nil) -> GitHubSeen {
        GitHubSeen(at: now,
                   stars: stats?.stars ?? previous?.stars ?? 0,
                   forks: stats?.forks ?? previous?.forks ?? 0,
                   downloads: releases.map(totalDownloads) ?? previous?.downloads)
    }

    public static func totalDownloads(_ releases: [GitHubRelease]) -> Int {
        releases.reduce(0) { $0 + $1.downloads }
    }

    /// Issues, pull requests and comments together, newest first, without
    /// repeats, at most `limit`.
    public static func merged(_ lists: [[GitHubFeedItem]], limit: Int = 30) -> [GitHubFeedItem] {
        var seenIDs = Set<String>()
        let all = lists.joined().filter { seenIDs.insert($0.id).inserted }
        return Array(all.sorted { $0.createdAt > $1.createdAt }.prefix(limit))
    }

    /// Items to notify about: written after `watermark` (the newest thing
    /// already notified, or the first load) and not before `seen`.
    public static func toNotify(_ items: [GitHubFeedItem], after watermark: Date,
                                seen: GitHubSeen?) -> [GitHubFeedItem] {
        items.filter { $0.createdAt > watermark && isUnread($0, seen: seen) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// One notification per repository: its title and body.
    public static func notificationText(repo: String, items: [GitHubFeedItem]) -> (title: String, body: String)? {
        guard let first = items.first else { return nil }
        if items.count == 1 {
            let what: String = switch first.kind {
            case .issue: tr("新议题")
            case .pull: tr("新拉取请求")
            case .comment: tr("新评论")
            }
            return ("\(repo) · \(what)", "\(first.author)：\(first.title)")
        }
        let issues = items.filter { $0.kind == .issue }.count
        let pulls = items.filter { $0.kind == .pull }.count
        let comments = items.filter { $0.kind == .comment }.count
        var parts: [String] = []
        if issues > 0 { parts.append(tr("\(issues) 个议题")) }
        if pulls > 0 { parts.append(tr("\(pulls) 个拉取请求")) }
        if comments > 0 { parts.append(tr("\(comments) 条评论")) }
        return (tr("\(repo) 有 \(items.count) 条新反馈"),
                tr("新增 ") + parts.joined(separator: tr("、")) + tr("。最新：\(first.title)"))
    }

    // MARK: Relative time

    /// "刚刚", "5 分钟前", "3 小时前", "昨天", "4 天前", "2 个月前", "1 年前".
    public static func relativeText(_ date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        switch seconds {
        case ..<60: return tr("刚刚")
        case ..<3600: return tr("\(Int(seconds / 60)) 分钟前")
        case ..<86_400: return tr("\(Int(seconds / 3600)) 小时前")
        case ..<(86_400 * 2): return tr("昨天")
        case ..<(86_400 * 30): return tr("\(Int(seconds / 86_400)) 天前")
        case ..<(86_400 * 365): return tr("\(Int(seconds / (86_400 * 30))) 个月前")
        default: return tr("\(Int(seconds / (86_400 * 365))) 年前")
        }
    }

    // MARK: Parsing

    static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        return try? Date(text, strategy: .iso8601)
    }

    private struct User: Decodable { var login: String? }
    private struct Label: Decodable { var name: String? }

    /// `GET /repos/{o}/{r}/issues?state=all&sort=created`: issues and pull
    /// requests both, told apart by the `pull_request` key.
    public static func parseIssues(_ data: Data) -> [GitHubFeedItem]? {
        struct PullMarker: Decodable {}
        struct Wire: Decodable {
            var id: Int
            var number: Int
            var title: String?
            var user: User?
            var created_at: String?
            var html_url: String?
            var labels: [Label]?
            var pull_request: PullMarker?
        }
        guard let wire = try? JSONDecoder().decode([Wire].self, from: data) else { return nil }
        return wire.compactMap { item in
            guard let created = date(item.created_at) else { return nil }
            let pull = item.pull_request != nil
            return GitHubFeedItem(id: "\(pull ? "pull" : "issue")-\(item.id)",
                                  kind: pull ? .pull : .issue, number: item.number,
                                  title: item.title ?? "#\(item.number)",
                                  author: item.user?.login ?? "",
                                  createdAt: created,
                                  url: item.html_url.flatMap(URL.init(string:)),
                                  labels: (item.labels ?? []).compactMap(\.name))
        }
    }

    /// `GET /repos/{o}/{r}/issues/comments`. A comment does not carry its
    /// issue's title, so it is looked up in `titles` (from the issues read
    /// alongside); otherwise the comment's own first line stands in.
    public static func parseComments(_ data: Data, titles: [Int: String] = [:]) -> [GitHubFeedItem]? {
        struct Wire: Decodable {
            var id: Int
            var user: User?
            var created_at: String?
            var html_url: String?
            var issue_url: String?
            var body: String?
        }
        guard let wire = try? JSONDecoder().decode([Wire].self, from: data) else { return nil }
        return wire.compactMap { item in
            guard let created = date(item.created_at) else { return nil }
            let number = item.issue_url.flatMap { $0.split(separator: "/").last.flatMap { Int($0) } }
            let title: String
            if let number, let known = titles[number] {
                title = "#\(number) \(known)"
            } else {
                let line = (item.body ?? "").split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
                let short = line.count > 80 ? String(line.prefix(80)) + "…" : line
                title = number.map { "#\($0) \(short)" } ?? short
            }
            return GitHubFeedItem(id: "comment-\(item.id)", kind: .comment, number: number,
                                  title: title, author: item.user?.login ?? "",
                                  createdAt: created,
                                  url: item.html_url.flatMap(URL.init(string:)))
        }
    }

    /// `GET /repos/{o}/{r}/releases`: drafts are left out, they are not
    /// published and nobody can download them.
    public static func parseReleases(_ data: Data) -> [GitHubRelease]? {
        struct Asset: Decodable { var name: String?; var download_count: Int? }
        struct Wire: Decodable {
            var id: Int
            var tag_name: String?
            var name: String?
            var draft: Bool?
            var published_at: String?
            var html_url: String?
            var assets: [Asset]?
        }
        guard let wire = try? JSONDecoder().decode([Wire].self, from: data) else { return nil }
        return wire.filter { !($0.draft ?? false) }.map { item in
            GitHubRelease(id: item.id, tag: item.tag_name ?? "", name: item.name ?? item.tag_name ?? "",
                          publishedAt: date(item.published_at),
                          url: item.html_url.flatMap(URL.init(string:)),
                          assets: (item.assets ?? []).map {
                              GitHubRelease.Asset(name: $0.name ?? "", downloads: $0.download_count ?? 0)
                          })
        }
    }
}

// MARK: - Rate limits

public enum GitHubRateLimit {
    /// When to try again after a refusal, or nil when the status is not a
    /// rate limit. Follows GitHub's own guidance: `retry-after` first, then
    /// `x-ratelimit-reset` when nothing is left, otherwise a minute.
    /// Header names are matched without regard to case.
    public static func retryAt(status: Int, headers: [String: String], now: Date) -> Date? {
        guard status == 403 || status == 429 else { return nil }
        let lower = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
        if let after = lower["retry-after"].flatMap({ Double($0.trimmingCharacters(in: .whitespaces)) }) {
            return now.addingTimeInterval(max(1, after))
        }
        if lower["x-ratelimit-remaining"]?.trimmingCharacters(in: .whitespaces) == "0",
           let reset = lower["x-ratelimit-reset"].flatMap({ Double($0.trimmingCharacters(in: .whitespaces)) }) {
            return max(Date(timeIntervalSince1970: reset), now.addingTimeInterval(1))
        }
        // A 403 that is not about the rate is a refusal of another kind.
        return status == 429 ? now.addingTimeInterval(60) : nil
    }

    /// "请求太频繁，5 分钟后重试", rounded up, never "0 分钟".
    public static func waitText(until: Date, now: Date) -> String {
        let minutes = max(1, Int((until.timeIntervalSince(now) / 60).rounded(.up)))
        return tr("请求太频繁，\(minutes) 分钟后重试")
    }
}
