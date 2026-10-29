import Foundation

/// 书签自己选的图标：网站图标、文字图标（1 到 2 个字加一种颜色）或上传的图片。
///
/// 存在书签小组件配置的 `icons` 里，一个书签一项 JSON，按网址找（不分大小写、
/// 结尾斜杠不算，和 `Bookmark.normalisedKey` 一样）。不是目录里的默认项，设置里
/// 不列；旧卡片没有这个键，或者某个书签不在里面，就照原来画：有缓存的网站图标
/// 画图标，没有画首字色块。
///
/// 上传的图片不进配置，只存文件名：图片缩小后放在 Application Support 下应用
/// 目录的 `bookmark-icons` 里（见 `BookmarkIconStore`）。
public enum BookmarkIcon: Equatable, Sendable {
    /// 网站自己的图标（页面里的 icon、apple-touch-icon 或 /favicon.ico），读到后缓存在本地。
    case site
    /// 文字图标：`text` 是 1 到 2 个字，`color` 是 `BookmarkIcons.palette` 里的下标。
    case text(String, color: Int)
    /// 上传的图片，`BookmarkIconStore` 目录里的文件名。
    case image(String)
}

public enum BookmarkIcons {
    public static let key = "icons"

    /// 文字图标最多几个字。
    public static let maxTextLength = 2

    /// 文字图标可选的颜色，十种，深浅都压得住白字。没有大面积的亮蓝：蓝只占一格。
    public static let palette: [String] = [
        "#F0564A", // 珊瑚红
        "#F5862E", // 小熊猫橙
        "#D99A16", // 琥珀
        "#2FB36B", // 草绿
        "#15A596", // 青绿
        "#3A7FE0", // 蓝
        "#5B63D3", // 靛
        "#9A57D6", // 紫
        "#E2558F", // 桃粉
        "#5F6773", // 石墨
    ]

    // MARK: 文字图标

    /// 文字图标默认的字：名称里第一个不是空白、不是标点的字，字母大写。
    /// 和卡片原来的首字色块是同一个字（见 `Bookmark.initial`）。
    public static func defaultText(for title: String) -> String {
        guard let first = title.first(where: { !$0.isWhitespace && !$0.isPunctuation }) else { return "?" }
        return String(first).uppercased()
    }

    /// 用户输入的文字图标：去掉空白，最多留 `maxTextLength` 个字（按看到的字数，
    /// 表情和带声调的字算一个），字母大写。什么都没有时是 nil，由调用方退回默认字。
    public static func cleanText(_ raw: String) -> String? {
        let kept = raw.filter { !$0.isWhitespace && !$0.isNewline }
        guard !kept.isEmpty else { return nil }
        return String(kept.prefix(maxTextLength)).uppercased()
    }

    /// 颜色下标落在色板里，越界的（旧数据或手改的配置）折回范围内。
    public static func clampedColor(_ index: Int) -> Int {
        let count = palette.count
        return ((index % count) + count) % count
    }

    /// 新建文字图标时默认的颜色：按域名算，同一个网站每次都是同一种。
    public static func defaultColor(for url: URL) -> Int {
        Bookmark(title: "", url: url).paletteIndex(count: palette.count)
    }

    // MARK: 读写配置

    /// 存成 JSON 的一项。`kind` 是 site / text / image。
    struct Entry: Codable, Equatable {
        var url: String
        var kind: String
        var text: String?
        var color: Int?
        var file: String?
    }

    /// 存着的图标，按 `Bookmark.normalisedKey` 找。认不出的项跳过，同一个网址后面的盖前面的。
    public static func stored(_ config: WidgetConfig) -> [String: BookmarkIcon] {
        var out: [String: BookmarkIcon] = [:]
        for text in config.strings(key) {
            guard let pair = decode(text) else { continue }
            out[Bookmark.normalisedKey(pair.0)] = pair.1
        }
        return out
    }

    /// 某个书签的图标，没选过是 nil（照原来画）。
    public static func icon(for url: URL, in stored: [String: BookmarkIcon]) -> BookmarkIcon? {
        stored[Bookmark.normalisedKey(url)]
    }

    /// 写一个书签的图标（nil 是清掉，回到原来的画法），顺手丢掉已经不在 `links` 里的书签的图标。
    public static func store(_ icon: BookmarkIcon?, for url: URL, in config: inout WidgetConfig) {
        var all: [String: (URL, BookmarkIcon)] = [:]
        for text in config.strings(key) {
            guard let pair = decode(text) else { continue }
            all[Bookmark.normalisedKey(pair.0)] = pair
        }
        let key = Bookmark.normalisedKey(url)
        all[key] = icon.map { (url, $0) }
        write(all, into: &config)
    }

    /// 只丢掉已经删掉的书签的图标，别的不动（删书签、改网址之后调用）。
    public static func prune(_ config: inout WidgetConfig) {
        var all: [String: (URL, BookmarkIcon)] = [:]
        for text in config.strings(key) {
            guard let pair = decode(text) else { continue }
            all[Bookmark.normalisedKey(pair.0)] = pair
        }
        guard !all.isEmpty else { return }
        write(all, into: &config)
    }

    /// 配置里用到的上传图片文件名。删书签、换图标后不再用到的文件由调用方删掉。
    public static func uploadFiles(_ config: WidgetConfig) -> Set<String> {
        Set(stored(config).values.compactMap { icon in
            if case .image(let file) = icon { return file }
            return nil
        })
    }

    private static func write(_ all: [String: (URL, BookmarkIcon)], into config: inout WidgetConfig) {
        let live = Set(Bookmark.list(config.strings("links")).map { Bookmark.normalisedKey($0.url) })
        let texts = all.filter { live.contains($0.key) }.sorted { $0.key < $1.key }
            .compactMap { encode($0.value.1, url: $0.value.0) }
        config.set(key, texts.isEmpty ? nil : .list(texts.map { .string($0) }))
    }

    static func encode(_ icon: BookmarkIcon, url: URL) -> String? {
        let entry: Entry
        switch icon {
        case .site:
            entry = Entry(url: url.absoluteString, kind: "site")
        case .text(let text, let color):
            entry = Entry(url: url.absoluteString, kind: "text",
                          text: cleanText(text) ?? "?", color: clampedColor(color))
        case .image(let file):
            guard isUploadFileName(file) else { return nil }
            entry = Entry(url: url.absoluteString, kind: "image", file: file)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(entry)).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func decode(_ text: String) -> (URL, BookmarkIcon)? {
        guard let entry = try? JSONDecoder().decode(Entry.self, from: Data(text.utf8)),
              let url = URL(string: entry.url) else { return nil }
        switch entry.kind {
        case "site":
            return (url, .site)
        case "text":
            guard let text = entry.text.flatMap(cleanText) else { return nil }
            return (url, .text(text, color: clampedColor(entry.color ?? 0)))
        case "image":
            guard let file = entry.file, isUploadFileName(file) else { return nil }
            return (url, .image(file))
        default:
            return nil
        }
    }

    // MARK: 文件

    /// 上传图片存成的文件名：`upload-<UUID>.png`。
    public static func uploadFileName(_ id: UUID) -> String {
        "upload-\(id.uuidString.lowercased()).png"
    }

    /// 配置里读来的文件名只认自己起的那种，不让 `../` 之类指到目录外面。
    public static func isUploadFileName(_ name: String) -> Bool {
        guard name.hasPrefix("upload-"), name.hasSuffix(".png"), name.count <= 64 else { return false }
        return name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == ".") }
            && !name.contains("..")
    }

    /// 网站图标的缓存文件名，按域名（去掉 www.、小写）：同一个网站的几个书签共用一张。
    /// 认不出域名（mailto: 之类）时是 nil，不取图标。
    public static func siteFileName(for url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        let short = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let safe = short.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }
        guard !safe.isEmpty, !safe.hasPrefix(".") else { return nil }
        return safe + ".png"
    }

    /// 取网站图标依次试的地址：页面里写的 icon（`LinkPreview.icon`），再是
    /// `/apple-touch-icon.png`，最后 `/favicon.ico`。重复的只试一次。
    public static func iconCandidates(page: URL, pageIcon: String?) -> [URL] {
        var out: [URL] = []
        func add(_ url: URL?) {
            guard let url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
                  !out.contains(url) else { return }
            out.append(url)
        }
        add(pageIcon.flatMap { URL(string: $0) })
        if let scheme = page.scheme?.lowercased(), scheme == "http" || scheme == "https",
           let host = page.host, !host.isEmpty {
            let port = page.port.map { ":\($0)" } ?? ""
            add(URL(string: "\(scheme)://\(host)\(port)/apple-touch-icon.png"))
            add(URL(string: "\(scheme)://\(host)\(port)/favicon.ico"))
        }
        return out
    }

    /// 自动取网站图标都失败过一次后，隔多久再自动试（手动点“获取图标”不受限）。
    public static let retryAfter: TimeInterval = LinkPreview.retryAfter

    /// 上次自动取失败在 `failed`，现在该不该再试。
    public static func shouldRetry(failed: Date?, now: Date = .now) -> Bool {
        guard let failed else { return true }
        return now.timeIntervalSince(failed) >= retryAfter
    }

    /// 读到的图标是不是能用：太小的多半是透明占位，太大的不是图标。
    public static func acceptsDownload(bytes: Int, pixelWidth: Int) -> Bool {
        bytes > 64 && bytes < 2_000_000 && pixelWidth >= 16
    }

    /// 存进缓存和上传目录的图片最长边（像素）。卡片 30pt、面板 56pt，2 倍屏 128 足够。
    public static let storedPixels = 128
}

public extension BookmarkList {
    /// 表单里“保存”：`original` 为 nil 是新加一条，加在最后；否则改那一条（名字和网址都可能变），
    /// 位置不动。新网址和别的书签重复时是 `.duplicate`。
    static func saving(title: String, url: URL, replacing original: URL?, in entries: [String],
                       limit: Int = Bookmark.maxCount) -> AddResult {
        let key = Bookmark.normalisedKey(url)
        let index = original.flatMap { rawIndex(of: $0, in: entries) }
        let clash = entries.indices.contains { i in
            i != index && (Bookmark(parsing: entries[i]).map { Bookmark.normalisedKey($0.url) == key } ?? false)
        }
        if clash { return .duplicate }
        let line = entry(title: title.trimmingCharacters(in: .whitespacesAndNewlines), url: url)
        if let index {
            var copy = entries
            copy[index] = line
            return .added(copy)
        }
        guard Bookmark.list(entries).count < limit else { return .full }
        return .added(entries + [line])
    }
}

public extension Bookmark {
    /// 表单里输入的网址：和列表里认网址的规则一样（裸域名补 https）。
    static func parseAddress(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
        return address(trimmed)
    }
}
