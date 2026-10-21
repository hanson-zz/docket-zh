import Foundation

// 收音机「找台」：搜索页的流派标签和翻页，世界页的国家台数和点阵地图。
//
// 界面在 Widgets/Details/RadioBrowseViews.swift，网络请求在 Services/RadioBrowseService.swift。
// 这里只放判断和解析，好写测试。

// MARK: - Genres

/// 搜索框下面那排流派标签。Radio Browser 的标签多是英文，一个中文标签对应一组英文 tag，
/// 分别查再合并（见 `RadioBrowse.merge`）。“热门”不是一个流派，是不选任何流派（nil）。
public enum RadioGenre: String, CaseIterable, Identifiable, Sendable {
    case news, music, pop, classical, jazz, rock, electronic, crosstalk, sports

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .news: tr("新闻")
        case .music: tr("音乐")
        case .pop: tr("流行")
        case .classical: tr("古典")
        case .jazz: tr("爵士")
        case .rock: tr("摇滚")
        case .electronic: tr("电子")
        case .crosstalk: tr("相声评书")
        case .sports: tr("体育")
        }
    }

    /// 查目录用的英文 tag（精确匹配），按顺序；2026-10-21 实查过这些 tag 下有台。
    public var tags: [String] {
        switch self {
        case .news: ["news"]
        case .music: ["music"]
        case .pop: ["pop"]
        case .classical: ["classical"]
        case .jazz: ["jazz"]
        case .rock: ["rock"]
        case .electronic: ["electronic", "dance"]
        case .crosstalk: ["crosstalk", "storytelling", "comedy"]
        case .sports: ["sports", "sport"]
        }
    }

    /// 再点一下选中的那个就取消，回到“热门”。
    public static func toggled(_ tapped: RadioGenre?, current: RadioGenre?) -> RadioGenre? {
        guard let tapped else { return nil }
        return tapped == current ? nil : tapped
    }
}

// MARK: - A search

/// 一次找台：名字、范围、流派，或者世界页里的一个国家。翻页用 `offset`。
public struct RadioSearch: Equatable, Sendable {
    public var name: String
    public var region: RadioRegion
    public var genre: RadioGenre?
    /// ISO 3166-1 两位码；有它时按国家查，不看 `region`。
    public var country: String?
    /// 国家页里“只看中文台”。
    public var chineseOnly: Bool

    public init(name: String = "", region: RadioRegion = .global, genre: RadioGenre? = nil,
                country: String? = nil, chineseOnly: Bool = false) {
        self.name = RadioDial.oneLine(name)
        self.region = region
        self.genre = genre
        self.country = country.map { $0.uppercased() }
        self.chineseOnly = chineseOnly
    }

    /// 只看某国（不叠中文、不叠流派、不搜名字）时的台数，就是国家列表里那个数。
    public var isWholeCountry: Bool {
        country != nil && !chineseOnly && genre == nil && name.isEmpty
    }

    /// 范围或国家对应的筛选参数。
    public var filter: [URLQueryItem] {
        if let country {
            var items = [URLQueryItem(name: "countrycode", value: country)]
            if chineseOnly { items.append(URLQueryItem(name: "language", value: "chinese")) }
            return items
        }
        return region.filter
    }

    /// 每个 tag 一条地址（没选流派时一条），同一页用同一个 offset。
    public func urls(offset: Int = 0, limit: Int = RadioBrowser.limit,
                     host: String = RadioBrowser.hosts[0]) -> [URL] {
        let tags: [String?] = genre.map { $0.tags.map(Optional.some) } ?? [nil]
        return tags.compactMap { tag in
            RadioBrowser.searchURL(name: name, filter: filter, tag: tag, offset: offset, limit: limit, host: host)
        }
    }
}

/// 搜索结果里的一行：电台本身、收听量（排序用）和地点（省份或国家，显示用）。
public struct RadioListing: Equatable, Sendable, Identifiable {
    public var station: RadioStation
    public var clicks: Int
    public var place: String

    public init(station: RadioStation, clicks: Int = 0, place: String = "") {
        self.station = station
        self.clicks = clicks
        self.place = place
    }

    public var id: String { station.id }

    /// “MP3 · 128 kbps · 上海”。
    public var detail: String {
        place.isEmpty ? station.detail : "\(station.detail) · \(place)"
    }
}

extension RadioBrowser {
    /// 带流派和翻页的查法。`filter` 是范围或国家（见 `RadioSearch.filter`），`tag` 精确匹配。
    public static func searchURL(name: String, filter: [URLQueryItem], tag: String?, offset: Int,
                                 limit: Int = RadioBrowser.limit, host: String = hosts[0]) -> URL? {
        let words = RadioDial.oneLine(name)
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = host
        parts.path = "/json/stations/search"
        var items: [URLQueryItem] = []
        if !words.isEmpty { items.append(URLQueryItem(name: "name", value: words)) }
        if let tag, !tag.isEmpty {
            items.append(URLQueryItem(name: "tag", value: tag))
            items.append(URLQueryItem(name: "tagExact", value: "true"))
        }
        items += filter
        items += [
            URLQueryItem(name: "limit", value: String(max(1, limit))),
            URLQueryItem(name: "offset", value: String(max(0, offset))),
            URLQueryItem(name: "hidebroken", value: "true"),
            URLQueryItem(name: "order", value: "clickcount"),
            URLQueryItem(name: "reverse", value: "true"),
        ]
        parts.queryItems = items
        return parts.url
    }

    private struct RankedRow: Decodable {
        var clickcount: Int?
        var state: String?
        var country: String?
        var countrycode: String?
    }

    /// 一页目录回答：可用的电台（和 `parse` 一样去掉没地址的、重复的），加上这页原本有几行
    /// （判断还有没有下一页用，见 `RadioBrowse.hasMore`）。不是 JSON 时是 nil。
    public static func parseListings(_ data: Data) -> (listings: [RadioListing], rows: Int)? {
        guard let stations = parse(data),
              let rows = try? JSONDecoder().decode([RankedRow].self, from: data),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return nil }
        // parse 去掉了一些行，按地址把收听量和地点对回去。
        var byAddress: [String: RankedRow] = [:]
        for (row, object) in zip(rows, raw) {
            for key in ["url_resolved", "url"] {
                if let text = object[key] as? String, let url = RadioDial.streamURL(text),
                   byAddress[url.absoluteString] == nil {
                    byAddress[url.absoluteString] = row
                }
            }
        }
        let listings = stations.map { station -> RadioListing in
            let row = byAddress[station.url]
            let state = RadioDial.oneLine(row?.state ?? "")
            let code = (row?.countrycode ?? "").uppercased()
            let place = !state.isEmpty && state.count <= 16 ? state
                : (code.isEmpty ? "" : RadioCountries.name(code, fallback: row?.country ?? ""))
            return RadioListing(station: station, clicks: max(0, row?.clickcount ?? 0), place: place)
        }
        return (listings, rows.count)
    }
}

// MARK: - Merging and paging

public enum RadioBrowse {
    /// 每页取几个，和原来的热门列表一样。
    public static let pageSize = RadioBrowser.limit
    /// 世界地图下面的国家卡片列几个台。
    public static let previewCount = 4

    /// 把几个 tag 各自的一页合并：去掉已经显示的和彼此重复的（同一个台或有一条地址相同），
    /// 新的一批按收听量从高到低排，接在已显示的后面（已显示的不挪位置，列表不跳）。
    public static func merge(_ shown: [RadioListing], batches: [[RadioListing]]) -> [RadioListing] {
        var result = shown
        var fresh: [RadioListing] = []
        for item in batches.joined() {
            let repeated = (result + fresh).contains {
                $0.station.id == item.station.id || $0.station.matches(item.station)
            }
            if !repeated { fresh.append(item) }
        }
        // 稳定排序：收听量一样时保持原来的先后。
        let ordered = fresh.enumerated().sorted {
            $0.element.clicks != $1.element.clicks ? $0.element.clicks > $1.element.clicks : $0.offset < $1.offset
        }.map(\.element)
        result += ordered
        return result
    }

    /// 下一页的 offset：每个 tag 都按页数往后翻，和合并去重后显示了几个无关。
    public static func offset(page: Int, size: Int = pageSize) -> Int { max(0, page) * size }

    /// 还有没有下一页：任何一个 tag 这页取满了就还有。
    public static func hasMore(rowsPerTag: [Int], size: Int = pageSize) -> Bool {
        rowsPerTag.contains { $0 >= size }
    }

    /// 能说出总数时的台数（约数，来自国家列表）：只看某国，或者范围是某个地区且没搜名字、没选流派。
    public static func knownTotal(_ search: RadioSearch, counts: [String: Int]) -> Int? {
        if search.isWholeCountry, let code = search.country { return counts[code] }
        guard search.country == nil, search.genre == nil, search.name.isEmpty else { return nil }
        switch search.region {
        case .mainland, .hongKong, .taiwan, .macau: return counts[search.region.rawValue]
        case .chinese, .global: return nil
        }
    }
}

// MARK: - Countries

/// 目录里一个国家或地区和它的台数。
public struct RadioCountry: Equatable, Sendable, Identifiable {
    public var code: String
    public var count: Int
    /// 目录给的英文名，本地化名字查不到时用。
    public var englishName: String

    public init(code: String, count: Int, englishName: String = "") {
        self.code = code.uppercased()
        self.count = count
        self.englishName = englishName
    }

    public var id: String { code }
}

public enum RadioCountries {
    /// 国家台数缓存一天。
    public static let cacheLifetime: TimeInterval = 24 * 60 * 60

    public static func countriesURL(host: String = RadioBrowser.hosts[0]) -> URL? {
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = host
        parts.path = "/json/countries"
        return parts.url
    }

    private struct Row: Decodable {
        var name: String?
        var iso_3166_1: String?
        var stationcount: Int?
    }

    /// /json/countries 的回答：同一个码出现几次就把台数加起来，去掉认不出的码和 0 台的，
    /// 按台数从多到少（一样多按码）。不是 JSON 时是 nil。
    public static func parse(_ data: Data) -> [RadioCountry]? {
        guard let rows = try? JSONDecoder().decode([Row].self, from: data) else { return nil }
        var counts: [String: Int] = [:]
        var names: [String: String] = [:]
        for row in rows {
            let code = (row.iso_3166_1 ?? "").trimmingCharacters(in: .whitespaces).uppercased()
            guard isCode(code) else { continue }
            counts[code, default: 0] += max(0, row.stationcount ?? 0)
            if names[code] == nil, let name = row.name, !name.isEmpty { names[code] = name }
        }
        return sorted(counts.compactMap { code, count in
            count > 0 ? RadioCountry(code: code, count: count, englishName: names[code] ?? "") : nil
        })
    }

    public static func sorted(_ list: [RadioCountry]) -> [RadioCountry] {
        list.sorted { $0.count != $1.count ? $0.count > $1.count : $0.code < $1.code }
    }

    public static func isCode(_ code: String) -> Bool {
        code.unicodeScalars.count == 2 && code.unicodeScalars.allSatisfy { $0.value >= 65 && $0.value <= 90 }
    }

    /// 存进缓存的一行字：“CN:2173:China,US:7454:The United States Of America”。
    public static func encode(_ list: [RadioCountry]) -> String {
        list.map { "\($0.code):\($0.count):\($0.englishName.replacingOccurrences(of: ",", with: " ").replacingOccurrences(of: ":", with: " "))" }
            .joined(separator: ",")
    }

    public static func decode(_ text: String) -> [RadioCountry] {
        sorted(text.split(separator: ",").compactMap { part in
            let bits = part.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard bits.count >= 2, isCode(bits[0]), let count = Int(bits[1]), count > 0 else { return nil }
            return RadioCountry(code: bits[0], count: count, englishName: bits.count > 2 ? bits[2] : "")
        })
    }

    /// 缓存还新鲜（不到一天，时钟往回拨也算过期）。
    public static func isFresh(savedAt: Date?, now: Date) -> Bool {
        guard let savedAt else { return false }
        let age = now.timeIntervalSince(savedAt)
        return age >= 0 && age < cacheLifetime
    }

    /// “242 个地区 · 约 61,168 台”里的两个数。
    public static func totals(_ list: [RadioCountry]) -> (regions: Int, stations: Int) {
        (list.filter { $0.count > 0 }.count, list.reduce(0) { $0 + max(0, $1.count) })
    }

    /// 地图上点的亮度三档：0 暂无，1 是 1 到 49，2 是 50 到 499，3 是 500 以上。
    public static func tier(_ count: Int) -> Int {
        switch count {
        case 500...: 3
        case 50...: 2
        case 1...: 1
        default: 0
        }
    }

    /// 列表里台数条的长度，最多的那个国家是满条。
    public static func barFraction(_ count: Int, max top: Int) -> Double {
        guard top > 0 else { return 0 }
        return min(1, Swift.max(0, Double(count) / Double(top)))
    }

    /// 系统 emoji 国旗（两个区域指示符），认不出的码给空字符串。
    public static func flag(_ code: String) -> String {
        let upper = code.uppercased()
        guard isCode(upper) else { return "" }
        var text = ""
        for scalar in upper.unicodeScalars {
            if let flag = Unicode.Scalar(0x1F1E6 + scalar.value - 65) { text.unicodeScalars.append(flag) }
        }
        return text
    }

    /// 按界面语言的国名。港澳台用短名，系统查不到时用目录给的英文名，再不行用码。
    static func name(_ code: String, fallback: String = "", locale: Locale = L10n.interfaceLocale) -> String {
        let upper = code.uppercased()
        let english = locale.language.languageCode?.identifier == "en"
        switch upper {
        case "HK": return english ? "Hong Kong" : "香港"
        case "MO": return english ? "Macau" : "澳门"
        case "TW": return english ? "Taiwan" : "台湾"
        default: break
        }
        if let local = locale.localizedString(forRegionCode: upper), !local.isEmpty, local != upper { return local }
        return fallback.isEmpty ? upper : fallback
    }

    /// 列表上方“搜国家或地区”：国名（本地化或英文）或码里有这几个字的，顺序不变。
    static func filter(_ list: [RadioCountry], query: String,
                              locale: Locale = L10n.interfaceLocale) -> [RadioCountry] {
        let words = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return list }
        return list.filter { country in
            country.code.caseInsensitiveCompare(words) == .orderedSame
                || name(country.code, fallback: country.englishName, locale: locale)
                    .localizedCaseInsensitiveContains(words)
                || country.englishName.localizedCaseInsensitiveContains(words)
        }
    }

    /// 列表的两种排法。
    public enum Order: String, CaseIterable, Sendable {
        case count, name

        public var title: String {
            switch self {
            case .count: tr("按台数")
            case .name: tr("按名称")
            }
        }
    }

    static func ordered(_ list: [RadioCountry], by order: Order,
                               locale: Locale = L10n.interfaceLocale) -> [RadioCountry] {
        switch order {
        case .count: return sorted(list)
        case .name:
            return list.sorted {
                name($0.code, fallback: $0.englishName, locale: locale)
                    .compare(name($1.code, fallback: $1.englishName, locale: locale), locale: locale) == .orderedAscending
            }
        }
    }
}

// MARK: - Dot map

/// 世界页的点阵地图：4° 经纬一格，只记陆地上的点和它属于哪个国家，不存国界线。
/// 资源 Resources/Radio/radio-world-dots.json 由 scripts/make-radio-world-dots.py 从
/// Natural Earth 110m（公有领域）离线算好。
public struct RadioWorldMap: Equatable, Sendable {
    public struct Dot: Equatable, Sendable {
        public var col: Int
        public var row: Int
        /// 国家码；海岛、争议地区这类认不出的是 nil。
        public var code: String?

        public init(col: Int, row: Int, code: String?) {
            self.col = col
            self.row = row
            self.code = code
        }
    }

    public var cols: Int
    public var rows: Int
    public var dots: [Dot]

    public init(cols: Int, rows: Int, dots: [Dot]) {
        self.cols = cols
        self.rows = rows
        self.dots = dots
    }

    private struct File: Decodable {
        var cols: Int
        var rows: Int
        var codes: [String]
        var dots: [[Int]]
    }

    /// 读资源 JSON；格式不对、尺寸不对时是 nil，世界页就只显示列表。
    public init?(data: Data) {
        guard let file = try? JSONDecoder().decode(File.self, from: data), file.cols > 0, file.rows > 0 else {
            return nil
        }
        var dots: [Dot] = []
        for triple in file.dots {
            guard triple.count == 3, (0..<file.cols).contains(triple[0]), (0..<file.rows).contains(triple[1]),
                  file.codes.indices.contains(triple[2]) else { continue }
            let code = file.codes[triple[2]]
            dots.append(Dot(col: triple[0], row: triple[1], code: RadioCountries.isCode(code) ? code : nil))
        }
        guard !dots.isEmpty else { return nil }
        self.init(cols: file.cols, rows: file.rows, dots: dots)
    }

    /// 点击吸附：在点（格子坐标，可以是小数）附近找最近的、有台的国家的点，
    /// 超过 `within` 格就当没点中。小国在地图上点不准，列表兜底。
    public func nearestCountry(col: Double, row: Double, counts: [String: Int], within: Double = 3) -> String? {
        var best: (code: String, distance: Double)?
        for dot in dots {
            guard let code = dot.code, (counts[code] ?? 0) > 0 else { continue }
            let dx = Double(dot.col) + 0.5 - col
            let dy = Double(dot.row) + 0.5 - row
            let distance = (dx * dx + dy * dy).squareRoot()
            if distance <= within, distance < (best?.distance ?? .infinity) { best = (code, distance) }
        }
        return best?.code
    }

    /// 视图坐标换成格子坐标：地图按宽度铺满，每格 `width / cols`。
    public func cell(at point: (x: Double, y: Double), width: Double) -> (col: Double, row: Double) {
        let pitch = width / Double(max(1, cols))
        guard pitch > 0 else { return (0, 0) }
        return (point.x / pitch, point.y / pitch)
    }

    /// 某国所有点的中心（格子坐标），用来摆名字气泡；地图上没有这个国家时是 nil。
    public func centre(of code: String) -> (col: Double, row: Double, top: Double)? {
        let mine = dots.filter { $0.code == code }
        guard !mine.isEmpty else { return nil }
        let col = mine.reduce(0.0) { $0 + Double($1.col) + 0.5 } / Double(mine.count)
        let row = mine.reduce(0.0) { $0 + Double($1.row) + 0.5 } / Double(mine.count)
        let top = Double(mine.map(\.row).min() ?? 0)
        return (col, row, top)
    }
}
