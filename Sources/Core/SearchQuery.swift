import Foundation

/// The pure half of the search widget: which engine, and what URL a query
/// becomes. Tested in the core; the panel only opens what this returns.
public enum SearchEngine: String, CaseIterable, Sendable {
    case bing, baidu, google, duckduckgo

    public var title: String {
        switch self {
        case .bing: "必应"
        case .baidu: "百度"
        case .google: "Google"
        case .duckduckgo: "DuckDuckGo"
        }
    }

    private var base: String {
        switch self {
        case .bing: "https://www.bing.com/search?q="
        case .baidu: "https://www.baidu.com/s?wd="
        case .google: "https://www.google.com/search?q="
        case .duckduckgo: "https://duckduckgo.com/?q="
        }
    }

    /// Nil for a blank query. Something that is already a web address opens
    /// as itself rather than as a search for it.
    public func url(for query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains(" "), trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://"),
           let direct = URL(string: trimmed) {
            return direct
        }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+#?")
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: base + encoded)
    }
}
