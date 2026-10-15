import Foundation

/// What a bookmarked page says about itself: a title, a line of summary and
/// a picture, read once when the link is added and kept with the widget.
///
/// Stored in the bookmarks widget's config under `previews`, one JSON string
/// per link, keyed by the link's address. Not a catalog default, so it is
/// never offered as an option, and a build that predates it ignores it: old
/// saves have no previews and simply show the address until one is fetched.
public struct LinkPreview: Codable, Equatable, Sendable {
    /// The bookmark's address, `URL.absoluteString`.
    public var url: String
    public var title: String?
    public var summary: String?
    /// `og:image`, when the page has one.
    public var image: String?
    /// The page's icon, or the site's `/favicon.ico`.
    public var icon: String?
    public var fetched: Date
    /// The last attempt could not read the page.
    public var failed: Bool

    public init(url: String, title: String? = nil, summary: String? = nil, image: String? = nil,
                icon: String? = nil, fetched: Date = .now, failed: Bool = false) {
        self.url = url
        self.title = title
        self.summary = summary
        self.image = image
        self.icon = icon
        self.fetched = fetched
        self.failed = failed
    }

    public static let configKey = "previews"
    /// A page that failed is tried again after this long, not on every redraw.
    public static let retryAfter: TimeInterval = 6 * 3600

    /// Whether anything worth showing was read.
    public var hasContent: Bool { !failed && (title?.isEmpty == false || summary?.isEmpty == false) }

    // MARK: Stored in the config

    /// Every stored preview by address. Entries that do not decode are skipped.
    public static func stored(_ config: WidgetConfig) -> [String: LinkPreview] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        var out: [String: LinkPreview] = [:]
        for text in config.strings(configKey) {
            guard let preview = try? decoder.decode(LinkPreview.self, from: Data(text.utf8)) else { continue }
            out[preview.url] = preview
        }
        return out
    }

    /// Writes `fresh` over what is stored and drops previews of links that
    /// are no longer in the list.
    public static func store(_ fresh: [LinkPreview], in config: inout WidgetConfig) {
        var all = stored(config)
        for preview in fresh { all[preview.url] = preview }
        let live = Set(Bookmark.list(config.strings("links")).map(\.url.absoluteString))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = .sortedKeys
        let texts = all.values.filter { live.contains($0.url) }.sorted { $0.url < $1.url }
            .compactMap { try? encoder.encode($0) }.compactMap { String(data: $0, encoding: .utf8) }
        config.set(configKey, texts.isEmpty ? nil : .list(texts.map { .string($0) }))
    }

    /// Only web pages are fetched, and each once: again only after a failure
    /// has had time to clear, or when asked to by hand.
    public static func needsFetch(_ url: URL, stored: LinkPreview?, now: Date = .now) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        guard let stored else { return true }
        return stored.failed && now.timeIntervalSince(stored.fetched) >= retryAfter
    }

    // MARK: Parsing

    /// Reads a page's title, summary, picture and icon.
    ///
    /// Open Graph first, then Twitter's tags, then the plain `<title>` and
    /// `<meta name="description">`. Relative addresses are resolved against
    /// `page`. Nil when the page offers neither a title nor a summary.
    public static func parse(_ html: String, page: URL, now: Date = .now) -> LinkPreview? {
        // The head is where all of this lives; a long body is not worth
        // running every pattern over.
        let head: Substring = {
            if let end = html.range(of: "</head>", options: .caseInsensitive) { return html[..<end.lowerBound] }
            return html.prefix(200_000)
        }()
        let metas = metaTags(head)
        func meta(_ keys: [String]) -> String? {
            for key in keys {
                if let value = metas[key], !value.isEmpty { return value }
            }
            return nil
        }
        let title = clean(meta(["og:title", "twitter:title"]) ?? titleTag(head), limit: 120)
        let summary = clean(meta(["og:description", "twitter:description", "description"]), limit: 240)
        guard title != nil || summary != nil else { return nil }
        let image = meta(["og:image", "og:image:url", "twitter:image"]).flatMap { resolve(decode($0), page) }
        let icon = iconLink(head).flatMap { resolve(decode($0), page) } ?? defaultIcon(page)
        return LinkPreview(url: page.absoluteString, title: title, summary: summary,
                           image: image, icon: icon, fetched: now, failed: false)
    }

    /// A failed attempt, kept so the next one waits.
    public static func failure(_ url: URL, now: Date = .now) -> LinkPreview {
        LinkPreview(url: url.absoluteString, icon: defaultIcon(url), fetched: now, failed: true)
    }

    /// The charset a page declares in its header or its first bytes, lower-cased.
    public static func charset(contentType: String?, head: String) -> String? {
        if let contentType, let match = contentType.lowercased().firstMatch(of: #/charset=["']?([a-z0-9_\-]+)/#) {
            return String(match.output.1)
        }
        if let match = head.lowercased().firstMatch(of: #/<meta[^>]*charset=["']?([a-z0-9_\-]+)/#) {
            return String(match.output.1)
        }
        return nil
    }

    /// `property` or `name` to `content`, for every `<meta>` in `html`.
    /// The first tag for a key wins, as a browser's preview would read it.
    static func metaTags(_ html: Substring) -> [String: String] {
        var out: [String: String] = [:]
        for tag in html.matches(of: #/<meta\b[^>]*>/#.ignoresCase()) {
            let attrs = attributes(String(tag.output))
            guard let content = attrs["content"] else { continue }
            for keyName in ["property", "name", "itemprop"] {
                guard let key = attrs[keyName]?.lowercased(), out[key] == nil else { continue }
                out[key] = content
            }
        }
        return out
    }

    /// The attributes of one tag, names lower-cased, quoted either way.
    static func attributes(_ tag: String) -> [String: String] {
        var out: [String: String] = [:]
        for match in tag.matches(of: #/([A-Za-z_:][A-Za-z0-9_:\-]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))/#) {
            let name = String(match.output.1).lowercased()
            let value = match.output.2 ?? match.output.3 ?? match.output.4 ?? ""
            if out[name] == nil { out[name] = String(value) }
        }
        return out
    }

    static func titleTag(_ html: Substring) -> String? {
        guard let match = html.firstMatch(of: #/<title[^>]*>([\s\S]*?)</title>/#.ignoresCase()) else { return nil }
        return String(match.output.1)
    }

    /// `<link rel="icon">`, preferring a plain icon over Apple's large one.
    static func iconLink(_ html: Substring) -> String? {
        var touch: String?
        for tag in html.matches(of: #/<link\b[^>]*>/#.ignoresCase()) {
            let attrs = attributes(String(tag.output))
            guard let rel = attrs["rel"]?.lowercased(), let href = attrs["href"], !href.isEmpty else { continue }
            let words = rel.split(separator: " ")
            if words.contains("icon") { return href }
            if touch == nil, rel.contains("apple-touch-icon") { touch = href }
        }
        return touch
    }

    static func defaultIcon(_ page: URL) -> String? {
        guard let scheme = page.scheme, let host = page.host, !host.isEmpty else { return nil }
        return "\(scheme)://\(host)/favicon.ico"
    }

    /// Absolute http(s) only; `data:` and the like are dropped.
    static func resolve(_ href: String, _ page: URL) -> String? {
        let trimmed = href.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed, relativeTo: page)?.absoluteURL,
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        return url.absoluteString
    }

    /// Entities decoded, whitespace collapsed, cut to `limit` characters.
    static func clean(_ text: String?, limit: Int) -> String? {
        guard let text else { return nil }
        let collapsed = decode(text).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return collapsed.count > limit ? String(collapsed.prefix(limit - 1)) + "…" : collapsed
    }

    /// Named entities that turn up in titles, and every numeric one.
    static func decode(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var out = ""
        var rest = text.startIndex
        for match in text.matches(of: #/&#([xX][0-9A-Fa-f]+|[0-9]+);/#) {
            let body = match.output.1
            let value = body.hasPrefix("x") || body.hasPrefix("X")
                ? UInt32(body.dropFirst(), radix: 16) : UInt32(body)
            guard let value, let scalar = Unicode.Scalar(value) else { continue }
            out += text[rest..<match.range.lowerBound]
            out.unicodeScalars.append(scalar)
            rest = match.range.upperBound
        }
        out += text[rest...]
        for (entity, char) in [("&quot;", "\""), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"),
                               ("&nbsp;", " "), ("&middot;", "·"), ("&hellip;", "…"), ("&amp;", "&")] {
            out = out.replacingOccurrences(of: entity, with: char)
        }
        return out
    }
}

public extension Bookmark {
    /// Whether the entry named the link itself rather than leaving the host
    /// to stand in. A named link keeps its name over the page's title.
    var hasOwnTitle: Bool { title != Self.shortHost(url) }

    /// The 小宇宙 show or episode this link points at, if it is one.
    var xiaoyuzhou: XiaoyuzhouLink? { XiaoyuzhouLink.parse(url.absoluteString) }

    /// What to call the link: its own name, else the page's title, else the host.
    func displayTitle(_ preview: LinkPreview?) -> String {
        if hasOwnTitle { return title }
        if let fetched = preview?.title, preview?.failed == false, !fetched.isEmpty { return fetched }
        return title
    }
}
