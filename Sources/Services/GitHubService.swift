import Foundation
import Observation

/// A public repository's stars, issues and pull requests, and the signed-in
/// user's unread notifications when a token has been given.
///
/// Unauthenticated, api.github.com allows 60 requests an hour per address;
/// a refresh here is two (the repository and a search for its open pull
/// requests), every ten minutes at most, so a dozen an hour. A personal
/// token raises the limit and adds the notification count; it is kept in
/// the keychain, never in Docket's own settings file.
@MainActor @Observable
final class GitHubService {
    static let shared = GitHubService()
    nonisolated static let tokenAccount = "github-token"

    private(set) var stats: [String: GitHubStats] = [:]
    private(set) var notifications: Int?
    private(set) var errors: [String: String] = [:]
    private(set) var hasToken = KeychainStore.read(GitHubService.tokenAccount) != nil
    private(set) var loading: Set<String> = []

    @ObservationIgnored private var lastFetch: [String: Date] = [:]

    private init() {}

    func setToken(_ token: String?) {
        let trimmed = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            KeychainStore.delete(Self.tokenAccount)
            notifications = nil
        } else {
            KeychainStore.write(trimmed, for: Self.tokenAccount)
        }
        hasToken = !trimmed.isEmpty
        lastFetch = [:]
    }

    /// Fetches `slug` unless it was fetched in the last ten minutes.
    func refresh(_ slug: String, force: Bool = false) {
        guard let parsed = RepoSlug.parse(slug) else {
            errors[slug] = "仓库格式应为“用户/仓库”"
            return
        }
        let key = "\(parsed.owner)/\(parsed.repo)"
        let now = Date.now
        if !force, let last = lastFetch[key], now.timeIntervalSince(last) < 600 { return }
        guard !loading.contains(key) else { return }
        lastFetch[key] = now
        loading.insert(key)
        let token = KeychainStore.read(Self.tokenAccount)
        Task {
            defer { loading.remove(key) }
            let repoURL = URL(string: "https://api.github.com/repos/\(key)")!
            guard let (data, status) = await Self.get(repoURL, token: token) else {
                errors[key] = stats[key] == nil ? "无法连接 GitHub" : nil
                return
            }
            guard status == 200, var parsed = GitHubStats.parseRepository(data) else {
                errors[key] = switch status {
                case 404: "找不到这个仓库（或它是私有仓库）"
                case 401: "令牌无效"
                case 403, 429: "已达到 GitHub 请求上限，稍后再试"
                default: "GitHub 返回错误 \(status)"
                }
                return
            }
            var search = URLComponents(string: "https://api.github.com/search/issues")!
            search.queryItems = [URLQueryItem(name: "q", value: "repo:\(key) type:pr state:open"),
                                 URLQueryItem(name: "per_page", value: "1")]
            if let url = search.url, let (body, code) = await Self.get(url, token: token), code == 200 {
                parsed.openPulls = GitHubStats.parseSearchTotal(body)
            } else {
                parsed.openPulls = stats[key]?.openPulls
            }
            stats[key] = parsed
            errors[key] = nil
            if let token {
                let url = URL(string: "https://api.github.com/notifications?per_page=50")!
                if let (body, code) = await Self.get(url, token: token), code == 200 {
                    notifications = GitHubStats.parseNotificationCount(body)
                } else {
                    notifications = nil
                }
            }
        }
    }

    func stats(for slug: String) -> GitHubStats? {
        guard let parsed = RepoSlug.parse(slug) else { return nil }
        return stats["\(parsed.owner)/\(parsed.repo)"]
    }

    func error(for slug: String) -> String? {
        guard let parsed = RepoSlug.parse(slug) else { return "仓库格式应为“用户/仓库”" }
        return errors["\(parsed.owner)/\(parsed.repo)"]
    }

    private static func get(_ url: URL, token: String?) async -> (Data, Int)? {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Dockling (https://github.com/hanson-zz/docket-zh)", forHTTPHeaderField: "User-Agent")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return nil }
        return (data, http.statusCode)
    }
}
