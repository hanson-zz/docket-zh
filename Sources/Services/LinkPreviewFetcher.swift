import Foundation

/// Fetches bookmarked pages and reads their previews with `LinkPreview`.
///
/// Once per link: the result, success or failure, is written into the
/// widget's config, and `LinkPreview.needsFetch` keeps the shelf from asking
/// again on every redraw. Only the first 512 KB of a page is read, which
/// holds the head of anything reasonable.
@MainActor
enum LinkPreviewFetcher {
    /// Addresses being fetched right now, so the tile and the panel never
    /// ask for the same page twice at once.
    private static var inFlight: Set<String> = []

    nonisolated static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"

    /// Fetches every link in `urls` not already being fetched and returns a
    /// preview for each, a failure entry where the page could not be read.
    static func fetch(_ urls: [URL]) async -> [LinkPreview] {
        let wanted = urls.filter { !inFlight.contains($0.absoluteString) }
        guard !wanted.isEmpty else { return [] }
        for url in wanted { inFlight.insert(url.absoluteString) }
        defer { for url in wanted { inFlight.remove(url.absoluteString) } }
        return await withTaskGroup(of: LinkPreview.self) { group in
            for url in wanted {
                group.addTask { await read(url) }
            }
            var out: [LinkPreview] = []
            for await preview in group { out.append(preview) }
            return out
        }
    }

    private nonisolated static func read(_ url: URL) async -> LinkPreview {
        var request = URLRequest(url: url, timeoutInterval: 12)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9,en;q=0.6", forHTTPHeaderField: "Accept-Language")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode) else {
            return LinkPreview.failure(url)
        }
        let body = data.prefix(512 * 1024)
        let html = decode(Data(body), contentType: http.value(forHTTPHeaderField: "Content-Type"))
        guard var preview = LinkPreview.parse(html, page: http.url ?? url) else {
            return LinkPreview.failure(url)
        }
        // Keyed by what the bookmark says, not where a redirect ended up.
        preview.url = url.absoluteString
        return preview
    }

    /// UTF-8 unless the page says otherwise; GBK pages are still common on
    /// Chinese sites and read as noise in UTF-8.
    private nonisolated static func decode(_ data: Data, contentType: String?) -> String {
        let head = String(decoding: data.prefix(4096), as: UTF8.self)
        let charset = LinkPreview.charset(contentType: contentType, head: head)
        if let charset, ["gbk", "gb2312", "gb18030", "x-gbk"].contains(charset) {
            let gb = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
            if let text = String(data: data, encoding: String.Encoding(rawValue: gb)) { return text }
        }
        if charset == "big5" {
            let big5 = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.big5.rawValue))
            if let text = String(data: data, encoding: String.Encoding(rawValue: big5)) { return text }
        }
        return String(decoding: data, as: UTF8.self)
    }
}
