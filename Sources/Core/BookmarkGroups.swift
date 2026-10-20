import Foundation

/// 书签面板里直接改列表：添加、改名、删除、排序。
///
/// 列表照旧存在 `links`，一项一个“标题 网址”或只有网址（见 `Bookmark`），
/// 设置里那串逗号分隔的文字和旧版本都还能读。这里的改动都按网址找那一项，
/// 认不出网址的项原样留着，不替用户删。
public enum BookmarkList {

    /// 存成一项：标题空着或就是域名时只存网址，标题之后由链接预览取；
    /// 逗号在设置里是分隔符，换成空格，连续的空白并成一个。
    public static func entry(title: String, url: URL) -> String {
        let cleaned = title.replacingOccurrences(of: ",", with: " ").replacingOccurrences(of: "，", with: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if cleaned.isEmpty || cleaned == Bookmark.shortHost(url) { return url.absoluteString }
        return "\(cleaned) \(url.absoluteString)"
    }

    /// 添加的结果。
    public enum AddResult: Equatable, Sendable {
        case added([String])
        /// 认不出网址。
        case invalid
        /// 已经有同一个地址。
        case duplicate
        /// 已经放满 `Bookmark.maxCount` 个。
        case full
    }

    /// 粘贴进来的一段文字加在最后。可以是“标题 网址”，也可以只有网址。
    public static func adding(_ text: String, to entries: [String], limit: Int = Bookmark.maxCount) -> AddResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let link = Bookmark(parsing: trimmed) else { return .invalid }
        let existing = Bookmark.list(entries)
        let key = Bookmark.normalisedKey(link.url)
        if existing.contains(where: { Bookmark.normalisedKey($0.url) == key }) { return .duplicate }
        guard existing.count < limit else { return .full }
        let title = link.hasOwnTitle ? link.title : ""
        return .added(entries + [entry(title: title, url: link.url)])
    }

    /// 第几项（原始列表里的下标）是这个网址。
    static func rawIndex(of url: URL, in entries: [String]) -> Int? {
        let key = Bookmark.normalisedKey(url)
        return entries.firstIndex { entry in
            Bookmark(parsing: entry).map { Bookmark.normalisedKey($0.url) == key } ?? false
        }
    }

    /// 改名。名字清空就退回只存网址，显示网页标题或域名。
    public static func renaming(_ url: URL, to name: String, in entries: [String]) -> [String] {
        guard let index = rawIndex(of: url, in: entries), let link = Bookmark(parsing: entries[index]) else {
            return entries
        }
        var copy = entries
        copy[index] = entry(title: name.trimmingCharacters(in: .whitespacesAndNewlines), url: link.url)
        return copy
    }

    /// 删掉这个网址那一项。
    public static func removing(_ url: URL, from entries: [String]) -> [String] {
        guard let index = rawIndex(of: url, in: entries) else { return entries }
        var copy = entries
        copy.remove(at: index)
        return copy
    }

    /// 在眼下看得到的那几个（全部，或某个分组）里把第 `from` 个挪到第 `to` 个，
    /// 别的分组的书签在整张列表里的位置不动。
    public static func moving(from: Int, to: Int, visible: [URL], in entries: [String]) -> [String] {
        guard visible.indices.contains(from), !visible.isEmpty else { return entries }
        let target = min(max(0, to), visible.count - 1)
        guard target != from,
              let fromRaw = rawIndex(of: visible[from], in: entries),
              let toRaw = rawIndex(of: visible[target], in: entries) else { return entries }
        var copy = entries
        let item = copy.remove(at: fromRaw)
        // 往后挪：拿掉之后目标前移一格，插在 toRaw 正好在它后面；往前挪插在它前面。
        copy.insert(item, at: min(toRaw, copy.count))
        return copy
    }
}

/// 书签分组（Pro）：顶部标签“全部 / 自定义分组 / ＋”切换，编辑态“移到分组”。
///
/// 存在 `groups`，一组一项，写成“分组名=网址 网址”，和自选股的分组同一个
/// 写法；一个书签最多在一个分组里，不在任何分组的只在“全部”。不是目录里的
/// 默认项，设置里不列，旧卡片没有这个键就是没有分组。
///
/// 没解锁 Pro 时面板只显示“全部”，分组照旧存着，不改写，解锁或试用时回来。
public struct BookmarkGroup: Equatable, Sendable {
    public var name: String
    /// 组里书签的网址，`URL.absoluteString`。
    public var urls: [String]

    public init(name: String, urls: [String] = []) {
        self.name = name
        self.urls = urls
    }
}

public enum BookmarkGroups {
    public static let key = "groups"
    /// 最多几个分组，标签一行加滚动放得下。
    public static let maxGroups = 12
    /// 分组名最多几个字。
    public static let maxNameLength = 12

    // MARK: 读写

    /// 存着的分组，按顺序。认不出、没名字和重名的跳过。
    public static func groups(_ config: WidgetConfig) -> [BookmarkGroup] {
        var out: [BookmarkGroup] = []
        for text in config.strings(key) {
            guard let eq = text.firstIndex(of: "=") else { continue }
            let name = text[..<eq].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !out.contains(where: { $0.name == name }) else { continue }
            let urls = text[text.index(after: eq)...].split(whereSeparator: \.isWhitespace).map(String.init)
            out.append(BookmarkGroup(name: name, urls: urls))
        }
        return out
    }

    /// 写回配置；一个分组都没有时删掉这个键。
    public static func write(_ groups: [BookmarkGroup], into config: inout WidgetConfig) {
        let texts = groups.map { "\($0.name)=\($0.urls.joined(separator: " "))" }
        config.set(key, texts.isEmpty ? nil : .list(texts.map { .string($0) }))
    }

    // MARK: 分组本身

    /// 新分组的名字：去掉首尾空白，“=”和逗号是分隔符所以去掉，最多 12 个字。
    /// 空了返回 nil。
    public static func cleanName(_ raw: String) -> String? {
        let stripped = raw.replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "，", with: "")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let name = String(stripped.prefix(maxNameLength))
        return name.isEmpty ? nil : name
    }

    /// 加一个空分组。名字不合用、重名或已经有 12 个时返回 nil。
    public static func adding(_ raw: String, to groups: [BookmarkGroup]) -> [BookmarkGroup]? {
        guard let name = cleanName(raw), !groups.contains(where: { $0.name == name }),
              groups.count < maxGroups else { return nil }
        return groups + [BookmarkGroup(name: name)]
    }

    /// 删掉一个分组，组里的书签还在“全部”里。
    public static func removing(_ name: String, from groups: [BookmarkGroup]) -> [BookmarkGroup] {
        groups.filter { $0.name != name }
    }

    // MARK: 书签在哪个分组

    /// 这个书签在哪个分组，不在任何分组时是 nil。
    public static func group(of url: URL, in groups: [BookmarkGroup]) -> String? {
        let key = Bookmark.normalisedKey(url)
        return groups.first { group in
            group.urls.contains { URL(string: $0).map(Bookmark.normalisedKey) == key }
        }?.name
    }

    /// 把书签移到分组 `name`（nil 为移出分组，只留在“全部”）。一个书签只在一个分组里。
    public static func moving(_ url: URL, to name: String?, in groups: [BookmarkGroup]) -> [BookmarkGroup] {
        let key = Bookmark.normalisedKey(url)
        var out = groups.map { group in
            var copy = group
            copy.urls.removeAll { URL(string: $0).map(Bookmark.normalisedKey) == key }
            return copy
        }
        if let name, let index = out.firstIndex(where: { $0.name == name }) {
            out[index].urls.append(url.absoluteString)
        }
        return out
    }

    /// 去掉已经不在书签列表里的网址（删了书签、在设置里改了列表）。分组本身留着。
    public static func pruned(_ groups: [BookmarkGroup], links: [Bookmark]) -> [BookmarkGroup] {
        let live = Set(links.map { Bookmark.normalisedKey($0.url) })
        return groups.map { group in
            var copy = group
            copy.urls = group.urls.filter { URL(string: $0).map { live.contains(Bookmark.normalisedKey($0)) } ?? false }
            return copy
        }
    }

    // MARK: 面板上显示什么

    /// 顶部的分组标签（不含“全部”）。没解锁时没有，只显示“全部”。
    public static func tabs(_ groups: [BookmarkGroup], unlocked: Bool) -> [String] {
        unlocked ? groups.map(\.name) : []
    }

    /// 选中的标签实际是哪个：没解锁、分组被删了时退回“全部”（nil）。
    public static func selectedTab(_ tab: String?, groups: [BookmarkGroup], unlocked: Bool) -> String? {
        guard unlocked, let tab, groups.contains(where: { $0.name == tab }) else { return nil }
        return tab
    }

    /// 这个标签下显示的书签，按列表顺序。“全部”（nil）是所有书签。
    public static func visible(_ links: [Bookmark], tab: String?, groups: [BookmarkGroup],
                               unlocked: Bool) -> [Bookmark] {
        guard let tab = selectedTab(tab, groups: groups, unlocked: unlocked),
              let group = groups.first(where: { $0.name == tab }) else { return links }
        let keys = Set(group.urls.compactMap { URL(string: $0).map(Bookmark.normalisedKey) })
        return links.filter { keys.contains(Bookmark.normalisedKey($0.url)) }
    }
}
