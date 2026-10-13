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

    public init(id: String = RadioStation.newID(), name: String, url: String,
                codec: String = "", bitrate: Int = 0) {
        self.id = id
        self.name = name
        self.url = url
        self.codec = codec
        self.bitrate = bitrate
    }

    public static func newID() -> String {
        String(UUID().uuidString.prefix(8)).lowercased()
    }

    public var encoded: String {
        [id, RadioDial.oneLine(name), url, RadioDial.oneLine(codec), String(max(0, bitrate))]
            .joined(separator: "\t")
    }

    /// Tolerant on purpose: a bare stream address written by hand is still a
    /// station, named after its host.
    public init?(decoding raw: String, fallbackID: String) {
        let parts = raw.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        if parts.count >= 3 {
            guard let url = RadioDial.streamURL(parts[2]) else { return nil }
            let id = parts[0].trimmingCharacters(in: .whitespaces)
            let name = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            self.init(id: id.isEmpty ? fallbackID : id,
                      name: name.isEmpty ? RadioDial.hostName(url) : name,
                      url: url.absoluteString,
                      codec: parts.count > 3 ? parts[3].trimmingCharacters(in: .whitespaces) : "",
                      bitrate: parts.count > 4 ? max(0, Int(parts[4]) ?? 0) : 0)
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
        return parts.isEmpty ? "网络电台" : parts.joined(separator: " · ")
    }
}

public enum RadioDial {
    public static let stationsKey = "stations"
    public static let indexKey = "index"
    /// A dial, not a directory: past this the favourites stop being a dial.
    public static let maxStations = 60
    public static let maxNameLength = 60

    /// Stations a new widget starts with. Each one was checked to answer with
    /// real audio (an HLS playlist with MPEG-TS segments, or an MP3 stream)
    /// over HTTPS before it was added here.
    public static let presets: [RadioStation] = [
        RadioStation(id: "cnr-zgzs", name: "中国之声",
                     url: "https://ngcdn001.cnr.cn/live/zgzs/index.m3u8", codec: "HLS"),
        RadioStation(id: "cnr-jjzs", name: "经济之声",
                     url: "https://ngcdn002.cnr.cn/live/jjzs/index.m3u8", codec: "HLS"),
        RadioStation(id: "cnr-yyzs", name: "音乐之声",
                     url: "https://ngcdn001.cnr.cn/live/yyzs/index.m3u8", codec: "HLS"),
        RadioStation(id: "cri-hqzx", name: "环球资讯广播",
                     url: "https://sk.cri.cn/905.m3u8", codec: "HLS"),
        RadioStation(id: "bj-news", name: "北京新闻广播",
                     url: "https://lhttp.qtfm.cn/live/339/64k.mp3", codec: "MP3", bitrate: 64),
        RadioStation(id: "sh-101", name: "动感 101",
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
              !stations.contains(where: { $0.url == station.url }) else { return stations }
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
                            codec: address.absoluteString.lowercased().contains(".m3u8") ? "HLS" : "")
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

// MARK: - Radio Browser

/// The public station directory at radio-browser.info: no key, but it asks
/// every client to send a descriptive User-Agent, and its terms ask that the
/// directory be credited where it is shown.
public enum RadioBrowser {
    public static let userAgent = "Dockling/1.0 (macOS dock radio widget; https://github.com/hanson-zz/docket-zh)"
    public static let attribution = "电台目录来自 Radio Browser"
    public static let homepage = URL(string: "https://www.radio-browser.info")!
    /// Mirrors, tried in order. The directory runs several identical servers.
    public static let hosts = ["de1.api.radio-browser.info", "de2.api.radio-browser.info",
                               "all.api.radio-browser.info"]
    public static let limit = 30

    public static func searchURL(name: String, host: String = hosts[0]) -> URL? {
        let words = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return nil }
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = host
        parts.path = "/json/stations/search"
        parts.queryItems = [
            URLQueryItem(name: "name", value: words),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "hidebroken", value: "true"),
            URLQueryItem(name: "order", value: "clickcount"),
            URLQueryItem(name: "reverse", value: "true"),
        ]
        return parts.url
    }

    /// The most listened stations of one country, by ISO code ("CN").
    public static func countryURL(code: String, host: String = hosts[0]) -> URL? {
        let cc = code.trimmingCharacters(in: .whitespaces).uppercased()
        guard cc.count == 2, cc.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = host
        parts.path = "/json/stations/bycountrycodeexact/\(cc)"
        parts.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "hidebroken", value: "true"),
            URLQueryItem(name: "order", value: "clickcount"),
            URLQueryItem(name: "reverse", value: "true"),
        ]
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
        case ..<1: "不定时"
        case 60: "1 小时"
        case 120: "2 小时"
        default: "\(minutes) 分钟"
        }
    }

    /// "12:05", or "1:01:01" past an hour; "0:00" once it is due.
    public static func remaining(until end: Date, now: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(now).rounded(.up)))
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
