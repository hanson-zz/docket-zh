import Foundation

/// 收音机：一个网络电台，放在收藏里的就是一个频道。
///
/// Each favourite is one string in the widget's config under `stations`,
/// `id<TAB>name<TAB>url<TAB>codec<TAB>bitrate`, encoded the same way the
/// quick to-do list keeps its items: the existing config type carries it
/// without a new Codable shape, and a tab cannot be typed into the
/// single-line fields that add stations.
public struct RadioStation: Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var url: String
    /// "MP3", "AAC", "HLS" and so on, or empty when unknown.
    public var codec: String
    /// In kbps, 0 when unknown.
    public var bitrate: Int
    /// 备用地址，按顺序排在 `url` 后面：主地址连不上时播放器依次换下一条。
    public var backups: [String]
    /// 用户自己加的（贴地址或导入播放列表），收藏里标“自定义”。
    public var isCustom: Bool
    /// 上次检查时所有地址都连不上，收藏里标“可能失效”。只是标记，不会自动删。
    public var mayBeDead: Bool

    public init(id: String = RadioStation.newID(), name: String, url: String,
                codec: String = "", bitrate: Int = 0, backups: [String] = [],
                isCustom: Bool = false, mayBeDead: Bool = false) {
        self.id = id
        self.name = name
        self.url = url
        self.codec = codec
        self.bitrate = bitrate
        self.backups = backups
        self.isCustom = isCustom
        self.mayBeDead = mayBeDead
    }

    /// 主地址在前、备用地址在后，播放和检查都按这个顺序。
    public var addresses: [String] { [url] + backups }

    /// 两个电台有一条地址相同，就当作同一个电台（检查后主地址可能换成备用那条）。
    public func matches(_ other: RadioStation) -> Bool {
        let mine = Set(addresses)
        return other.addresses.contains { mine.contains($0) }
    }

    public static func newID() -> String {
        String(UUID().uuidString.prefix(8)).lowercased()
    }

    /// 旧的五段照旧；有标记或备用地址时再加两段：标记（`custom`、`dead`，逗号分开）
    /// 和空格分开的备用地址。旧版本读到多出的两段会忽略。
    public var encoded: String {
        var parts = [id, RadioDial.oneLine(name), url, RadioDial.oneLine(codec), String(max(0, bitrate))]
        let flags = [isCustom ? "custom" : nil, mayBeDead ? "dead" : nil].compactMap { $0 }
        if !flags.isEmpty || !backups.isEmpty {
            parts.append(flags.joined(separator: ","))
            parts.append(backups.joined(separator: " "))
        }
        return parts.joined(separator: "\t")
    }

    /// Tolerant on purpose: a bare stream address written by hand is still a
    /// station, named after its host.
    public init?(decoding raw: String, fallbackID: String) {
        let parts = raw.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        if parts.count >= 3 {
            guard let url = RadioDial.streamURL(parts[2]) else { return nil }
            let id = parts[0].trimmingCharacters(in: .whitespaces)
            let name = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let flags: Set<String> = parts.count > 5
                ? Set(parts[5].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }) : []
            var backups: [String] = []
            if parts.count > 6 {
                for word in parts[6].split(separator: " ") {
                    guard let backup = RadioDial.streamURL(String(word))?.absoluteString,
                          backup != url.absoluteString, !backups.contains(backup) else { continue }
                    backups.append(backup)
                }
            }
            self.init(id: id.isEmpty ? fallbackID : id,
                      name: name.isEmpty ? RadioDial.hostName(url) : name,
                      url: url.absoluteString,
                      codec: parts.count > 3 ? parts[3].trimmingCharacters(in: .whitespaces) : "",
                      bitrate: parts.count > 4 ? max(0, Int(parts[4]) ?? 0) : 0,
                      backups: Array(backups.prefix(RadioDial.maxBackups)),
                      isCustom: flags.contains("custom"), mayBeDead: flags.contains("dead"))
        } else {
            guard let url = RadioDial.streamURL(raw) else { return nil }
            self.init(id: fallbackID, name: RadioDial.hostName(url), url: url.absoluteString)
        }
    }

    /// "MP3 · 128 kbps", "HLS", or "网络电台" when nothing is known.
    public var detail: String {
        var parts: [String] = []
        if !codec.isEmpty, codec.uppercased() != "UNKNOWN" { parts.append(codec.uppercased()) }
        if bitrate > 0 { parts.append("\(bitrate) kbps") }
        if parts.isEmpty, url.lowercased().contains(".m3u8") { parts.append("HLS") }
        return parts.isEmpty ? tr("网络电台") : parts.joined(separator: " · ")
    }
}

public enum RadioDial {
    public static let stationsKey = "stations"
    public static let indexKey = "index"
    /// A dial, not a directory: past this the favourites stop being a dial.
    public static let maxStations = 60
    public static let maxNameLength = 60
    /// 一个电台最多记几条备用地址（不算主地址）。
    public static let maxBackups = 9

    /// Stations a new widget starts with. Each one was checked to answer with
    /// real audio (an HLS playlist with MPEG-TS segments, or an MP3 stream)
    /// over HTTPS before it was added here.
    public static let presets: [RadioStation] = [
        RadioStation(id: "cnr-zgzs", name: tr("中国之声"),
                     url: "https://ngcdn001.cnr.cn/live/zgzs/index.m3u8", codec: "HLS"),
        RadioStation(id: "cnr-jjzs", name: tr("经济之声"),
                     url: "https://ngcdn002.cnr.cn/live/jjzs/index.m3u8", codec: "HLS"),
        RadioStation(id: "cnr-yyzs", name: tr("音乐之声"),
                     url: "https://ngcdn001.cnr.cn/live/yyzs/index.m3u8", codec: "HLS"),
        RadioStation(id: "cri-hqzx", name: tr("环球资讯广播"),
                     url: "https://sk.cri.cn/905.m3u8", codec: "HLS"),
        RadioStation(id: "bj-news", name: tr("北京新闻广播"),
                     url: "https://lhttp.qtfm.cn/live/339/64k.mp3", codec: "MP3", bitrate: 64),
        RadioStation(id: "sh-101", name: tr("动感 101"),
                     url: "https://lhttp.qingting.fm/live/274/64k.mp3", codec: "MP3", bitrate: 64),
    ]

    // MARK: Reading and writing the favourites

    /// The widget's favourites. A widget that has never saved a list gets
    /// the presets; one whose list was emptied on purpose stays empty.
    public static func stations(_ config: WidgetConfig) -> [RadioStation] {
        guard config[stationsKey] != nil else { return presets }
        var seenIDs = Set<String>()
        var seenURLs = Set<String>()
        var result: [RadioStation] = []
        for (index, raw) in config.strings(stationsKey).enumerated() {
            guard var station = RadioStation(decoding: raw, fallbackID: "s\(index)") else { continue }
            guard !seenURLs.contains(station.url) else { continue }
            if seenIDs.contains(station.id) { station.id = "\(station.id)-\(index)" }
            seenIDs.insert(station.id)
            seenURLs.insert(station.url)
            result.append(station)
            if result.count >= maxStations { break }
        }
        return result
    }

    public static func store(_ stations: [RadioStation], in config: inout WidgetConfig) {
        config.set(stationsKey, .list(stations.prefix(maxStations).map { .string($0.encoded) }))
    }

    /// The tuned channel, always inside the list (0 for an empty one).
    public static func index(_ config: WidgetConfig, count: Int) -> Int {
        clamp(config.int(indexKey, default: 0), count: count)
    }

    public static func setIndex(_ index: Int, in config: inout WidgetConfig) {
        config.set(indexKey, .number(Double(max(0, index))))
    }

    public static func current(_ config: WidgetConfig) -> RadioStation? {
        let all = stations(config)
        guard !all.isEmpty else { return nil }
        return all[index(config, count: all.count)]
    }

    public static func clamp(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(0, index), count - 1)
    }

    /// Stepping past either end wraps, like a preset button on a car radio.
    public static func next(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (clamp(index, count: count) + 1) % count
    }

    public static func previous(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (clamp(index, count: count) - 1 + count) % count
    }

    /// "01", "12": the channel number the panel shows big.
    public static func channelText(_ index: Int) -> String {
        String(format: "%02d", max(0, index) + 1)
    }

    /// Appends unless that stream is already a favourite.
    public static func adding(_ station: RadioStation, to stations: [RadioStation]) -> [RadioStation] {
        guard stations.count < maxStations,
              !stations.contains(where: { $0.matches(station) }) else { return stations }
        var clean = station
        clean.name = String(oneLine(station.name).prefix(maxNameLength))
        if clean.name.isEmpty, let url = URL(string: station.url) { clean.name = hostName(url) }
        return stations + [clean]
    }

    public static func removing(_ id: String, from stations: [RadioStation]) -> [RadioStation] {
        stations.filter { $0.id != id }
    }

    /// Where the dial should sit after `removed` is taken out from under it:
    /// on the same station when it survives, otherwise its neighbour.
    public static func index(afterRemoving removed: Int, current: Int, count: Int) -> Int {
        let shifted = removed < current ? current - 1 : current
        return clamp(shifted, count: count - 1)
    }

    // MARK: Addresses and names

    /// An http or https address with a host, or nil. Radio streams are both.
    public static func streamURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" "), !trimmed.contains("\t"),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// A custom station from what was typed: the address must be a stream
    /// address; the name falls back to its host.
    public static func custom(name: String, url: String, id: String = RadioStation.newID()) -> RadioStation? {
        guard let address = streamURL(url) else { return nil }
        let words = String(oneLine(name).prefix(maxNameLength))
        return RadioStation(id: id, name: words.isEmpty ? hostName(address) : words,
                            url: address.absoluteString,
                            codec: address.absoluteString.lowercased().contains(".m3u8") ? "HLS" : "",
                            isCustom: true)
    }

    public static func hostName(_ url: URL) -> String {
        let host = url.host ?? url.absoluteString
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func oneLine(_ text: String) -> String {
        text.components(separatedBy: .newlines).joined(separator: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    /// The "now playing" line a stream sends (ICY `StreamTitle`), cleaned
    /// up: nil when it is empty, a placeholder, or just the station's name.
    public static func nowPlaying(_ raw: String?, stationName: String) -> String? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if text.hasPrefix("StreamTitle='") {
            text = String(text.dropFirst("StreamTitle='".count))
            if text.hasSuffix("';") { text = String(text.dropLast(2)) }
            else if text.hasSuffix("'") { text = String(text.dropLast()) }
        }
        text = oneLine(text)
        let placeholders: Set<String> = ["-", "unknown", "untitled", "n/a", "null"]
        guard !text.isEmpty, !placeholders.contains(text.lowercased()),
              text.caseInsensitiveCompare(stationName) != .orderedSame else { return nil }
        return String(text.prefix(120))
    }
}

// MARK: - Dial frequencies

/// 网络电台没有真实频率。复古皮肤的刻度窗、段码屏和收藏列表上的“FM 98.0”
/// 是按收藏顺序给每台排的位置：88 到 108 MHz 均匀分成收藏个数份，每台落在
/// 自己那一份的正中，取到 0.1 MHz。指针跟着频道走，换台就是换位置。
extension RadioDial {
    public static let lowMHz = 88.0
    public static let highMHz = 108.0
    /// 数码卡座的琴键个数，对应前 5 个收藏。
    public static let presetKeys = 5

    /// 第 `index` 个收藏（从 0 数）在刻度上的频率。列表为空时是刻度正中。
    public static func frequency(_ index: Int, count: Int) -> Double {
        guard count > 0 else { return (lowMHz + highMHz) / 2 }
        let slot = Double(clamp(index, count: count))
        let raw = lowMHz + (highMHz - lowMHz) * (slot + 0.5) / Double(count)
        return (raw * 10).rounded() / 10
    }

    /// 全部收藏的频率，按收藏顺序。
    public static func frequencies(count: Int) -> [Double] {
        (0..<max(0, count)).map { frequency($0, count: count) }
    }

    /// 频率在刻度上的位置，88 MHz 为 0，108 MHz 为 1，超出的夹到两头。
    public static func dialFraction(_ mhz: Double) -> Double {
        min(max((mhz - lowMHz) / (highMHz - lowMHz), 0), 1)
    }

    /// 刻度上离这个位置（0 到 1）最近的收藏，点或拖刻度窗时换到它。
    public static func nearestStation(toFraction fraction: Double, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let target = lowMHz + (highMHz - lowMHz) * min(max(fraction, 0), 1)
        var best = 0
        var gap = Double.infinity
        for (index, mhz) in frequencies(count: count).enumerated() where abs(mhz - target) < gap {
            gap = abs(mhz - target)
            best = index
        }
        return best
    }

    /// “98.0”“101.7”。
    public static func frequencyText(_ mhz: Double) -> String {
        String(format: "%.1f", mhz)
    }

    /// 列表和卡片上的“FM 98.0”。
    public static func fmText(_ index: Int, count: Int) -> String {
        "FM " + frequencyText(frequency(index, count: count))
    }

    /// 段码屏上的字：固定四位数字加小数点，不够三位整数时前面补空格
    /// （空格那一位只亮暗影），“ 98.0”“101.7”。
    public static func segmentText(_ mhz: Double) -> String {
        let text = frequencyText(mhz)
        return text.count < 5 ? String(repeating: " ", count: 5 - text.count) + text : text
    }

    /// 琴键 `key`（从 0 数）对应的收藏，没有那么多收藏时是 nil。
    public static func presetStation(key: Int, count: Int) -> Int? {
        guard key >= 0, key < presetKeys, key < count else { return nil }
        return key
    }

    /// 现在按下的那颗琴键：调到前 5 个收藏时是它，其余时候没有键按下。
    public static func pressedKey(index: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let tuned = clamp(index, count: count)
        return tuned < presetKeys ? tuned : nil
    }

    /// 段码屏右下角：前 5 个是“P3”，再往后是频道号“CH 12”。
    public static func presetLabel(index: Int, count: Int) -> String {
        guard count > 0 else { return "P-" }
        if let key = pressedKey(index: index, count: count) { return "P\(key + 1)" }
        return "CH " + channelText(index)
    }

    /// “频道 03 / 05”。
    public static func channelOfTotal(_ index: Int, count: Int) -> String {
        tr("频道 \(channelText(index)) / \(channelText(max(0, count - 1)))")
    }
}

// MARK: - Skins

/// 收音机的四种皮肤，存在 `skin` 键下。半圆表盘的经典样式免费，也是默认；
/// 三款复古皮肤是 Pro 样式（见 `ProFeatures.isKindProStyle`）。旧卡片没存这个
/// 键，按经典读；没解锁时复古皮肤画回经典，不盖锁，配置不改写（见
/// `ProLicenseGate.radioSkin`）。
public enum RadioSkin: String, CaseIterable, Sendable {
    /// 半圆刻度盘加红指针，原来的样子。
    case classic
    /// 木壳电子管：胡桃木纹、米色布纹喇叭网、琥珀指针。
    case wood
    /// 晶体管便携：深色皮革、镀铬边、竖向刻度窗和红指针。
    case transistor
    /// 数码卡座：拉丝金属、绿色段码屏、双 VU 表、1 到 5 琴键。
    case deck

    public static let key = "skin"
    public static let fallback: RadioSkin = .classic

    public var title: String {
        switch self {
        case .classic: tr("经典")
        case .wood: tr("木壳电子管")
        case .transistor: tr("晶体管便携")
        case .deck: tr("数码卡座")
        }
    }

    /// 三款复古皮肤是 Pro，经典免费。
    public var isPro: Bool { self != .classic }

    /// 存的值读回来，认不出或没存时是经典。
    public init(stored raw: String) {
        self = RadioSkin(rawValue: raw.trimmingCharacters(in: .whitespaces)) ?? Self.fallback
    }

    public static func stored(_ config: WidgetConfig) -> RadioSkin {
        RadioSkin(stored: config.string(key, default: fallback.rawValue))
    }
}

/// 数码卡座 VU 表的假动画：不读真实电平，播放时按时间算一个起伏的读数，
/// 左右声道错开。0 是表针最左，1 是最右（红区从 0.75 起）。
public enum RadioVU {
    /// 打开“减少动态效果”或预览时表针停在这里。
    public static let still: [Double] = [0.52, 0.6]
    /// 红区起点。
    public static let redFrom = 0.75

    public static func level(time: Double, channel: Int) -> Double {
        let phase = channel == 0 ? 0.0 : 1.3
        let slow = sin(time * 1.7 + phase)
        let fast = sin(time * 5.3 + phase * 2.1)
        let flutter = sin(time * 11.9 + phase * 0.7)
        let value = 0.5 + 0.22 * slow + 0.12 * fast + 0.06 * flutter
        return min(max(value, 0.08), 0.95)
    }

    /// 表针角度（度），0 时 -46°，1 时 +46°，和刻度一致。
    public static func angle(_ level: Double) -> Double {
        -46 + 92 * min(max(level, 0), 1)
    }
}

// MARK: - Search region

/// Which part of the directory "搜索电台" looks in. Chinese-language
/// stations by default; the rest narrow by country code, and "全球" does not
/// narrow at all. The raw value is what the widget's config keeps.
public enum RadioRegion: String, CaseIterable, Identifiable, Sendable {
    case chinese = "chinese"
    case mainland = "CN"
    case hongKong = "HK"
    case taiwan = "TW"
    case macau = "MO"
    case global = "all"

    public static let configKey = "searchRegion"
    public static let fallback: RadioRegion = .chinese

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .chinese: tr("中文电台")
        case .mainland: tr("大陆")
        case .hongKong: tr("香港")
        case .taiwan: tr("台湾")
        case .macau: tr("澳门")
        case .global: tr("全球")
        }
    }

    /// The query items that narrow a Radio Browser search to this region.
    public var filter: [URLQueryItem] {
        switch self {
        case .chinese: [URLQueryItem(name: "language", value: "chinese")]
        case .mainland, .hongKong, .taiwan, .macau: [URLQueryItem(name: "countrycode", value: rawValue)]
        case .global: []
        }
    }

    /// A stored value read back; anything unknown is the default.
    public init(stored raw: String) {
        self = RadioRegion(rawValue: raw.trimmingCharacters(in: .whitespaces)) ?? Self.fallback
    }

    public static func stored(_ config: WidgetConfig) -> RadioRegion {
        RadioRegion(stored: config.string(configKey))
    }

    public static func store(_ region: RadioRegion, in config: inout WidgetConfig) {
        config.set(configKey, .string(region.rawValue))
    }
}

// MARK: - Radio Browser

/// The public station directory at radio-browser.info: no key, but it asks
/// every client to send a descriptive User-Agent, and its terms ask that the
/// directory be credited where it is shown.
public enum RadioBrowser {
    public static let userAgent = "Dockling/1.0 (macOS dock radio widget; https://github.com/hanson-zz/docket-zh)"
    public static let attribution = tr("电台目录来自 Radio Browser")
    public static let homepage = URL(string: "https://www.radio-browser.info")!
    /// Mirrors, tried in order. The directory runs several identical servers.
    public static let hosts = ["de1.api.radio-browser.info", "de2.api.radio-browser.info",
                               "all.api.radio-browser.info"]
    public static let limit = 30

    /// The directory's station search, narrowed to `region`. With no name
    /// it lists that region's most listened stations; with one it searches
    /// station names inside the region. Always ordered by clicks, broken
    /// streams left out.
    public static func searchURL(name: String = "", region: RadioRegion = .global,
                                 host: String = hosts[0]) -> URL? {
        let words = RadioDial.oneLine(name)
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = host
        parts.path = "/json/stations/search"
        var items: [URLQueryItem] = []
        if !words.isEmpty { items.append(URLQueryItem(name: "name", value: words)) }
        items += region.filter
        items += [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "hidebroken", value: "true"),
            URLQueryItem(name: "order", value: "clickcount"),
            URLQueryItem(name: "reverse", value: "true"),
        ]
        parts.queryItems = items
        return parts.url
    }

    private struct Row: Decodable {
        var stationuuid: String?
        var name: String?
        var url: String?
        var url_resolved: String?
        var codec: String?
        var bitrate: Int?
        var hls: Int?
    }

    /// Stations from a directory answer, without the ones that have no usable
    /// address and without repeats of one stream. Nil when it is not JSON.
    public static func parse(_ data: Data) -> [RadioStation]? {
        guard let rows = try? JSONDecoder().decode([Row].self, from: data) else { return nil }
        var seen = Set<String>()
        var result: [RadioStation] = []
        for row in rows {
            let address = [row.url_resolved, row.url].compactMap { $0 }
                .compactMap(RadioDial.streamURL).first
            guard let address, !seen.contains(address.absoluteString) else { continue }
            let name = RadioDial.oneLine(row.name ?? "")
            guard !name.isEmpty else { continue }
            seen.insert(address.absoluteString)
            var codec = (row.codec ?? "").trimmingCharacters(in: .whitespaces)
            if codec.uppercased() == "UNKNOWN" { codec = (row.hls ?? 0) == 1 ? "HLS" : "" }
            let uuid = (row.stationuuid ?? "").lowercased()
            result.append(RadioStation(id: uuid.isEmpty ? RadioStation.newID() : "rb-" + String(uuid.prefix(8)),
                                       name: String(name.prefix(RadioDial.maxNameLength)),
                                       url: address.absoluteString, codec: codec,
                                       bitrate: max(0, row.bitrate ?? 0)))
        }
        return result
    }
}

// MARK: - Retry and sleep timer

/// How long to wait before reconnecting a stream that stalled or dropped.
public enum RadioRetry {
    public static let schedule: [Double] = [2, 4, 8, 16, 30]

    /// `attempt` counts from 0; everything past the schedule waits 30 s.
    public static func delay(attempt: Int) -> Double {
        schedule[min(max(0, attempt), schedule.count - 1)]
    }
}

public enum RadioSleep {
    /// 0 is "off".
    public static let choices: [Int] = [0, 15, 30, 60, 120]

    public static func title(_ minutes: Int) -> String {
        switch minutes {
        case ..<1: tr("不定时")
        case 60: tr("1 小时")
        case 120: tr("2 小时")
        default: tr("\(minutes) 分钟")
        }
    }

    /// "12:05", or "1:01:01" past an hour; "0:00" once it is due.
    public static func remaining(until end: Date, now: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(now).rounded(.up)))
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
