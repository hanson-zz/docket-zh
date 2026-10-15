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

// MARK: - 搜索站

/// 网页搜索面板里的一个搜索站：内置的（百度、小红书、GitHub……）或
/// 用户自己填网址加的。网址里用 `%s` 标出搜索词的位置。
public struct SearchSite: Codable, Equatable, Sendable, Identifiable {
    /// 内置站是固定 id（旧的 `engine` 值 bing、baidu、google、duckduckgo
    /// 也在其中，已有设置照常生效）；自定义站以 `custom-` 开头。
    public var id: String
    public var title: String
    /// 例如 `https://search.bilibili.com/all?keyword=%s`。
    public var template: String
    /// 图标底色（十六进制），网站图标读不到时画首字。
    public var tint: String

    public init(id: String, title: String, template: String, tint: String = "#5E8BFF") {
        self.id = id
        self.title = title
        self.template = template
        self.tint = tint
    }

    public var isCustom: Bool { id.hasPrefix(SearchSites.customPrefix) }

    /// 网站首页，用来取图标：`https://host`。
    public var home: URL? {
        guard let url = URL(string: template.replacingOccurrences(of: "%s", with: "")),
              let scheme = url.scheme, scheme == "https" || scheme == "http",
              let host = url.host(), !host.isEmpty else { return nil }
        return URL(string: "\(scheme)://\(host)")
    }

    /// 图标上画的首字：中文取第一个字，英文取首字母大写。
    public var initial: String {
        guard let first = title.trimmingCharacters(in: .whitespaces).first else { return "?" }
        return String(first).uppercased()
    }

    /// 空白搜索词是 nil。本身就是网址的直接打开。
    public func url(for query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if !trimmed.contains(" "), trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://"),
           let direct = URL(string: trimmed) {
            return direct
        }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+#?/")
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        let filled = template.contains("%s") ? template.replacingOccurrences(of: "%s", with: encoded)
                                             : template + encoded
        return URL(string: filled)
    }
}

public enum SearchSites {
    public static let customPrefix = "custom-"

    /// 面板里可加的内置站。前四个是原来的搜索引擎，id 不变。
    public static let builtIn: [SearchSite] = [
        SearchSite(id: "baidu", title: "百度", template: "https://www.baidu.com/s?wd=%s", tint: "#2932E1"),
        SearchSite(id: "bing", title: "必应", template: "https://www.bing.com/search?q=%s", tint: "#00809D"),
        SearchSite(id: "google", title: "Google", template: "https://www.google.com/search?q=%s", tint: "#4285F4"),
        SearchSite(id: "duckduckgo", title: "DuckDuckGo", template: "https://duckduckgo.com/?q=%s", tint: "#DE5833"),
        SearchSite(id: "xiaohongshu", title: "小红书", template: "https://www.xiaohongshu.com/search_result?keyword=%s", tint: "#FF2442"),
        SearchSite(id: "douyin", title: "抖音", template: "https://www.douyin.com/search/%s", tint: "#161823"),
        SearchSite(id: "bilibili", title: "哔哩哔哩", template: "https://search.bilibili.com/all?keyword=%s", tint: "#00AEEC"),
        SearchSite(id: "github", title: "GitHub", template: "https://github.com/search?q=%s", tint: "#24292F"),
        SearchSite(id: "zhihu", title: "知乎", template: "https://www.zhihu.com/search?type=content&q=%s", tint: "#1772F6"),
        SearchSite(id: "weibo", title: "微博", template: "https://s.weibo.com/weibo?q=%s", tint: "#E6162D"),
        SearchSite(id: "taobao", title: "淘宝", template: "https://s.taobao.com/search?q=%s", tint: "#FF5000"),
        SearchSite(id: "jd", title: "京东", template: "https://search.jd.com/Search?keyword=%s", tint: "#E1251B"),
        SearchSite(id: "youtube", title: "YouTube", template: "https://www.youtube.com/results?search_query=%s", tint: "#FF0000"),
        SearchSite(id: "wikipedia", title: "维基百科", template: "https://zh.wikipedia.org/w/index.php?search=%s", tint: "#54595D"),
    ]

    /// 新加的搜索小组件默认显示的一排。
    public static let defaultIDs = ["baidu", "bing", "xiaohongshu", "google", "douyin", "bilibili", "github"]

    /// 每张卡片最多放几个，再多面板就挤了。
    public static let maxCount = 12

    public static func builtIn(_ id: String) -> SearchSite? { builtIn.first { $0.id == id } }

    /// 按保存的 id 顺序取出搜索站：内置的按 id 找，自定义的在 `custom` 里找，
    /// 找不到的跳过、重复的去掉。一个都没有时用默认一排。
    public static func resolve(ids: [String], custom: [SearchSite]) -> [SearchSite] {
        var seen = Set<String>()
        let sites = ids.compactMap { id -> SearchSite? in
            guard seen.insert(id).inserted else { return nil }
            return builtIn(id) ?? custom.first { $0.id == id }
        }
        return sites.isEmpty ? defaultIDs.compactMap(builtIn) : Array(sites.prefix(maxCount))
    }

    /// 当前用哪个站：保存的那个还在列表里就用它，否则用列表第一个。
    public static func selected(_ id: String, in sites: [SearchSite]) -> SearchSite? {
        sites.first { $0.id == id } ?? sites.first
    }

    /// 用户填的自定义站。网址没写协议补 https；没写 `%s` 就把搜索词接在
    /// 末尾。名字空或网址不是 http(s) 时是 nil。
    public static func custom(title: String, address: String, id: String) -> SearchSite? {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var template = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !template.isEmpty, !template.contains(" ") else { return nil }
        let lower = template.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            // 写了别的协议（ftp:// 之类）不收。
            guard !lower.contains("://") else { return nil }
            template = "https://" + template
        }
        let site = SearchSite(id: customPrefix + id, title: String(name.prefix(12)), template: template)
        return site.home == nil ? nil : site
    }

    /// 自定义站存成 JSON 字符串放在小组件设置里。
    public static func encode(_ sites: [SearchSite]) -> String {
        guard let data = try? JSONEncoder().encode(sites) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    public static func decode(_ text: String) -> [SearchSite] {
        guard !text.isEmpty, let sites = try? JSONDecoder().decode([SearchSite].self, from: Data(text.utf8)) else {
            return []
        }
        return sites.filter(\.isCustom)
    }
}
