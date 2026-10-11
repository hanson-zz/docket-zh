import Foundation

/// One link on the bookmarks widget, parsed from the text it is stored as.
///
/// Stored as plain text, "标题 https://example.com" or just the address, so
/// it can be edited in Settings as an ordinary comma separated list. The
/// address is the last word that reads as one; everything before it is the
/// title, and without a title the host stands in.
public struct Bookmark: Equatable, Sendable {
    public var title: String
    public var url: URL

    public init(title: String, url: URL) {
        self.title = title
        self.url = url
    }

    /// Nil when nothing in the entry reads as an address.
    public init?(parsing entry: String) {
        let words = entry.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let index = words.lastIndex(where: { Self.address($0) != nil }),
              let url = Self.address(words[index]) else { return nil }
        let title = words.enumerated().filter { $0.offset != index }.map { $0.element }
            .joined(separator: " ")
        self.url = url
        self.title = title.isEmpty ? Self.shortHost(url) : title
    }

    /// "example.com", "https://example.com/x", "mailto:a@b.c".
    ///
    /// A bare word with a dot in it is taken as a web address, since that is
    /// what anyone typing "bilibili.com" means. Anything else needs a scheme.
    static func address(_ word: String) -> URL? {
        let word = word.trimmingCharacters(in: CharacterSet(charactersIn: "<>\"'"))
        guard !word.isEmpty else { return nil }
        if let url = URL(string: word), let scheme = url.scheme?.lowercased() {
            switch scheme {
            case "http", "https":
                return url.host?.isEmpty == false ? url : nil
            case "mailto", "file", "x-apple.systempreferences", "obsidian", "notion":
                return url
            default:
                // "localhost:3000" parses with a scheme of "localhost".
                break
            }
        }
        guard word.contains("."), !word.hasPrefix("."), !word.hasSuffix("."),
              word.rangeOfCharacter(from: .whitespaces) == nil,
              let url = URL(string: "https://" + word), url.host?.contains(".") == true
        else { return nil }
        return url
    }

    /// "github.com" for "https://www.github.com/x".
    public static func shortHost(_ url: URL) -> String {
        guard var host = url.host, !host.isEmpty else { return url.absoluteString }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    /// What the tile draws when there is no icon: the title's first letter
    /// or character, upper-cased.
    public var initial: String {
        guard let first = title.first(where: { !$0.isWhitespace && !$0.isPunctuation }) else { return "?" }
        return String(first).uppercased()
    }

    /// A colour slot from the host, so a link keeps its colour across
    /// launches and two links rarely share one.
    public func paletteIndex(count: Int) -> Int {
        guard count > 0 else { return 0 }
        var hash: UInt32 = 2_166_136_261
        for byte in Self.shortHost(url).lowercased().utf8 {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        return Int(hash % UInt32(count))
    }

    /// Every entry that parses, in order.
    public static func list(_ entries: [String]) -> [Bookmark] {
        entries.compactMap(Bookmark.init(parsing:))
    }

    /// The tile's width for this many links: a 30pt disc each, 6pt apart,
    /// inside the card's inset. Never narrower than a short label needs.
    public static func tileWidth(count: Int) -> Double {
        let shown = min(max(count, 1), 8)
        return max(100, Double(shown * 30 + (shown - 1) * 6) + 28)
    }

    /// The column's height: two discs a row.
    public static func columnHeight(count: Int) -> Double {
        let rows = (min(max(count, 1), 8) + 1) / 2
        return max(62, Double(rows * 34) + 16)
    }
}
