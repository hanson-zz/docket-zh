import Foundation

/// A public repository's numbers, from api.github.com, kept pure for tests.
public struct GitHubStats: Equatable, Sendable {
    public var fullName: String
    public var stars: Int
    public var forks: Int
    public var watchers: Int
    /// GitHub's `open_issues_count` counts pull requests too.
    public var openIssuesAndPulls: Int
    /// From a separate search; nil until it has answered.
    public var openPulls: Int?
    public var htmlURL: URL?

    public init(fullName: String, stars: Int, forks: Int, watchers: Int,
                openIssuesAndPulls: Int, openPulls: Int? = nil, htmlURL: URL? = nil) {
        self.fullName = fullName
        self.stars = stars
        self.forks = forks
        self.watchers = watchers
        self.openIssuesAndPulls = openIssuesAndPulls
        self.openPulls = openPulls
        self.htmlURL = htmlURL
    }

    /// Issues alone, once the pull request count is known.
    public var openIssues: Int? {
        openPulls.map { max(0, openIssuesAndPulls - $0) }
    }

    /// `GET /repos/{owner}/{repo}`.
    public static func parseRepository(_ data: Data) -> GitHubStats? {
        struct Wire: Decodable {
            var full_name: String
            var stargazers_count: Int
            var forks_count: Int
            var subscribers_count: Int?
            var watchers_count: Int?
            var open_issues_count: Int
            var html_url: String?
        }
        guard let wire = try? JSONDecoder().decode(Wire.self, from: data) else { return nil }
        return GitHubStats(fullName: wire.full_name, stars: wire.stargazers_count,
                           forks: wire.forks_count,
                           watchers: wire.subscribers_count ?? wire.watchers_count ?? 0,
                           openIssuesAndPulls: wire.open_issues_count,
                           htmlURL: wire.html_url.flatMap(URL.init(string:)))
    }

    /// `GET /search/issues`: only the total is read.
    public static func parseSearchTotal(_ data: Data) -> Int? {
        struct Wire: Decodable { var total_count: Int }
        return (try? JSONDecoder().decode(Wire.self, from: data))?.total_count
    }

    /// `GET /notifications`: unread threads are the array's length.
    public static func parseNotificationCount(_ data: Data) -> Int? {
        struct Thread: Decodable { var unread: Bool? }
        guard let threads = try? JSONDecoder().decode([Thread].self, from: data) else { return nil }
        return threads.filter { $0.unread ?? true }.count
    }

    /// "1.2k" past a thousand, the way GitHub abbreviates its own counters.
    public static func short(_ count: Int) -> String {
        switch count {
        case ..<1000: return "\(max(0, count))"
        case ..<10_000:
            let text = String(format: "%.1f", Double(count) / 1000)
            return (text.hasSuffix(".0") ? String(text.dropLast(2)) : text) + "k"
        case ..<1_000_000: return "\(count / 1000)k"
        default:
            let text = String(format: "%.1f", Double(count) / 1_000_000)
            return (text.hasSuffix(".0") ? String(text.dropLast(2)) : text) + "M"
        }
    }
}

/// "owner/repo", from whatever was typed or pasted.
public enum RepoSlug {
    /// Accepts "owner/repo", "github.com/owner/repo", a full URL with a
    /// trailing ".git", a path after the repo, or a query. Nil when there are
    /// not two plausible names.
    public static func parse(_ text: String) -> (owner: String, repo: String)? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://", "http://", "git@github.com:", "www.", "github.com/"] {
            if s.lowercased().hasPrefix(prefix) { s.removeFirst(prefix.count) }
        }
        if let cut = s.firstIndex(where: { $0 == "?" || $0 == "#" }) { s = String(s[..<cut]) }
        let parts = s.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        let owner = parts[0]
        var repo = parts[1]
        if repo.lowercased().hasSuffix(".git") { repo.removeLast(4) }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard !owner.isEmpty, !repo.isEmpty,
              owner.unicodeScalars.allSatisfy(allowed.contains),
              repo.unicodeScalars.allSatisfy(allowed.contains),
              owner.unicodeScalars.allSatisfy(\.isASCII), repo.unicodeScalars.allSatisfy(\.isASCII)
        else { return nil }
        return (owner, repo)
    }
}
