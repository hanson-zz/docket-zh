import Foundation

// 收音机：自己加电台、收藏失效检查、主地址失败换备用、定时关闭渐弱。
// 面板和播放器只管连网和画，判断都在这里，方便测试。

// MARK: - Pasted addresses

/// 贴进“添加电台”的地址能怎么用。
public enum RadioAddress: Equatable, Sendable {
    /// http/https 的音频流或 .m3u8 HLS，直接给播放器。
    case stream(URL)
    /// http/https 的 .m3u 或 .pls 播放列表，要先取回来解析出里面的地址。
    case playlist(URL)
    /// 播放器不支持的协议（RTMP、RTSP、MMS、FLV），值是给人看的协议名。
    case unsupported(String)
    /// 不是网址。
    case invalid

    /// 系统播放器放不了的协议。
    public static let unsupportedSchemes: [String: String] = [
        "rtmp": "RTMP", "rtmps": "RTMP", "rtmpe": "RTMP", "rtmpt": "RTMP",
        "rtsp": "RTSP", "rtsps": "RTSP", "rtspu": "RTSP",
        "mms": "MMS", "mmsh": "MMS", "mmst": "MMS", "mmsu": "MMS",
    ]

    public init(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let colon = trimmed.range(of: "://") {
            let scheme = trimmed[..<colon.lowerBound].lowercased()
            if let name = Self.unsupportedSchemes[scheme] { self = .unsupported(name); return }
        }
        guard let url = RadioDial.streamURL(trimmed) else { self = .invalid; return }
        switch url.pathExtension.lowercased() {
        case "flv": self = .unsupported("FLV")
        case "m3u", "pls": self = .playlist(url)
        default: self = .stream(url)
        }
    }

    /// 能当电台地址存下来的（直播流），其余是 nil。
    public var streamURL: URL? {
        if case .stream(let url) = self { return url }
        return nil
    }
}

// MARK: - Playlist files

/// 解析 .m3u / .m3u8 / .pls 播放列表：一条条地址加上名字，按名字并成电台，
/// 同一个电台的多条地址按出现顺序排，第一条是主地址，其余是备用。
public enum RadioPlaylist {
    public struct Entry: Equatable, Sendable {
        public var name: String
        public var url: String

        public init(name: String, url: String) {
            self.name = name
            self.url = url
        }
    }

    public struct Parsed: Equatable, Sendable {
        /// 解析出来的电台，全部标“自定义”。
        public var stations: [RadioStation]
        /// 跳过的不支持协议的地址个数（RTMP 这类）。
        public var unsupported: Int
        /// 这是 HLS 流本身的清单（有 #EXT-X- 标签），不是电台列表。
        public var isHLSManifest: Bool
    }

    /// 只要有一条 #EXT-X- 标签，就是 HLS 流自己的清单。
    public static func isHLSManifest(_ text: String) -> Bool {
        text.range(of: "#EXT-X-", options: .caseInsensitive) != nil
    }

    /// 文件里的每一条地址和名字，按出现顺序。PLS 按 FileN 的编号排。
    public static func entries(_ text: String) -> [Entry] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0.hasPrefix("\u{FEFF}") ? String($0.dropFirst()) : $0 }
            .filter { !$0.isEmpty }
        let isPLS = lines.contains { $0.lowercased() == "[playlist]" }
            || lines.contains { $0.range(of: #"^File\d+\s*="#, options: [.regularExpression, .caseInsensitive]) != nil }
        return isPLS ? plsEntries(lines) : m3uEntries(lines)
    }

    private static func plsEntries(_ lines: [String]) -> [Entry] {
        var files: [Int: String] = [:]
        var titles: [Int: String] = [:]
        for line in lines {
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if key.hasPrefix("file"), let number = Int(key.dropFirst(4)) {
                files[number] = value
            } else if key.hasPrefix("title"), let number = Int(key.dropFirst(5)) {
                titles[number] = value
            }
        }
        return files.keys.sorted().map { Entry(name: titles[$0] ?? "", url: files[$0] ?? "") }
    }

    private static func m3uEntries(_ lines: [String]) -> [Entry] {
        var result: [Entry] = []
        var pendingName = ""
        for line in lines {
            if line.hasPrefix("#") {
                if line.uppercased().hasPrefix("#EXTINF"), let comma = line.firstIndex(of: ",") {
                    pendingName = String(line[line.index(after: comma)...])
                }
                continue
            }
            result.append(Entry(name: pendingName, url: line))
            pendingName = ""
        }
        return result
    }

    /// 去掉 SHOUTcast 给的“(#1 - 12/500) ”这类前缀，合成一行，限长。
    public static func cleanName(_ raw: String) -> String {
        var text = RadioDial.oneLine(raw)
        if let range = text.range(of: #"^\(#\d+[^)]*\)\s*"#, options: .regularExpression) {
            text.removeSubrange(range)
        }
        return String(text.trimmingCharacters(in: .whitespaces).prefix(RadioDial.maxNameLength))
    }

    /// 解析一份播放列表。同名的条目并成一个电台（多出来的地址做备用）；
    /// 没写名字的按主机并，名字用主机名，整个文件只得出一个电台时用
    /// `fallbackName`（一般是文件名）。不支持的协议和不是网址的行跳过。
    public static func parse(_ text: String, fallbackName: String = "",
                             makeID: () -> String = { RadioStation.newID() }) -> Parsed {
        if isHLSManifest(text) { return Parsed(stations: [], unsupported: 0, isHLSManifest: true) }
        var unsupported = 0
        var order: [String] = []
        var groups: [String: (name: String, titled: Bool, urls: [String])] = [:]
        for entry in entries(text) {
            let address = RadioAddress(entry.url)
            let url: URL
            switch address {
            case .stream(let found), .playlist(let found): url = found
            case .unsupported: unsupported += 1; continue
            case .invalid: continue
            }
            let name = cleanName(entry.name)
            let key = name.isEmpty ? "host:" + RadioDial.hostName(url).lowercased() : "name:" + name.lowercased()
            var group = groups[key] ?? (name: name.isEmpty ? RadioDial.hostName(url) : name,
                                        titled: !name.isEmpty, urls: [])
            if groups[key] == nil { order.append(key) }
            if !group.urls.contains(url.absoluteString) { group.urls.append(url.absoluteString) }
            groups[key] = group
        }
        let fallback = cleanName(fallbackName)
        var stations: [RadioStation] = []
        for key in order.prefix(RadioDial.maxStations) {
            guard let group = groups[key], let first = group.urls.first else { continue }
            let name = !group.titled && order.count == 1 && !fallback.isEmpty ? fallback : group.name
            stations.append(RadioStation(id: makeID(), name: name, url: first,
                                         codec: first.lowercased().contains(".m3u8") ? "HLS" : "",
                                         backups: Array(group.urls.dropFirst().prefix(RadioDial.maxBackups)),
                                         isCustom: true))
        }
        return Parsed(stations: stations, unsupported: unsupported, isHLSManifest: false)
    }
}

// MARK: - Probing a stream

/// 试连一条地址时，看回来的头几百字节算不算音频。
public enum RadioProbe {
    /// 添加电台时试连等多久。
    public static let addTimeout: Double = 5
    /// 收藏检查时每条地址等多久。
    public static let checkTimeout: Double = 8
    /// 收藏检查同时连几条。
    public static let maxConcurrent = 4
    /// 最多读多少字节就下结论。
    public static let headBytes = 512

    /// 2xx，而且回来的是音频、HLS 清单或说不清类型的二进制，才算连得上。
    /// 网页（登录页、404 页面）和 .pls 这种列表本身不算。
    public static func alive(status: Int, contentType: String?, head: Data) -> Bool {
        guard (200..<300).contains(status) else { return false }
        let type = (contentType ?? "").lowercased()
        let text = String(decoding: head.prefix(64), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.hasPrefix("<!doctype") || text.hasPrefix("<html") || text.hasPrefix("<?xml") { return false }
        if text.hasPrefix("#extm3u") { return true }
        if type.contains("scpls") || type.contains("text/html") { return false }
        if type.hasPrefix("audio/") || type.hasPrefix("video/") || type.contains("mpegurl")
            || type.contains("ogg") || type.contains("octet-stream") || type.contains("aac") {
            return true
        }
        if type.isEmpty { return !head.isEmpty }
        return false
    }
}

// MARK: - Favourites health check

/// 收藏失效检查：每天自动最多一次，或手动点“检查”。只标记“可能失效”，
/// 把还连得上的地址提到前面，删除要用户确认。
public enum RadioHealth {
    /// 当天的标记，“2026-10-20”。
    public static func dayStamp(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// 今天还没自动检查过才检查。
    public static func shouldAutoCheck(lastStamp: String?, now: Date, calendar: Calendar = .current) -> Bool {
        guard let lastStamp, !lastStamp.isEmpty else { return true }
        return lastStamp != dayStamp(now, calendar: calendar)
    }

    /// 要试连的地址：每个电台的每条地址，去重，按收藏顺序。
    public static func addresses(_ stations: [RadioStation]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for address in stations.flatMap(\.addresses) {
            if seen.insert(address).inserted { result.append(address) }
        }
        return result
    }

    /// 把试连结果（地址 -> 连得上）套到收藏上：有连得上的地址就去掉“可能失效”，
    /// 连得上的按原顺序提到前面，没测到的居中，连不上的放最后；全部连不上的标
    /// “可能失效”，地址顺序不动。不在结果里的电台（检查中途新加的）原样保留。
    public static func applying(_ results: [String: Bool], to stations: [RadioStation]) -> [RadioStation] {
        stations.map { station in
            let addresses = station.addresses
            guard addresses.contains(where: { results[$0] != nil }) else { return station }
            let up = addresses.filter { results[$0] == true }
            let unknown = addresses.filter { results[$0] == nil }
            let down = addresses.filter { results[$0] == false }
            var updated = station
            if up.isEmpty && unknown.isEmpty {
                updated.mayBeDead = true
                return updated
            }
            let ordered = up + unknown + down
            updated.mayBeDead = false
            updated.url = ordered[0]
            updated.backups = Array(ordered.dropFirst())
            return updated
        }
    }

    /// 标着“可能失效”的电台。
    public static func dead(_ stations: [RadioStation]) -> [RadioStation] {
        stations.filter(\.mayBeDead)
    }

    /// 关掉提示时记下当时是哪几个电台；同一批不再提示，有新的失效电台才再出来。
    public static func dismissToken(_ dead: [RadioStation]) -> String {
        dead.map(\.id).sorted().joined(separator: ",")
    }

    public static func bannerVisible(dead: [RadioStation], dismissed: String?) -> Bool {
        guard !dead.isEmpty else { return false }
        return dismissToken(dead) != (dismissed ?? "")
    }

    /// 用户确认后删掉这些电台。
    public static func removing(_ ids: Set<String>, from stations: [RadioStation]) -> [RadioStation] {
        stations.filter { !ids.contains($0.id) }
    }

    /// 删掉一批之后转盘停在哪：原来那台还在就停在它上面，否则停在最近的一台。
    public static func index(afterRemoving ids: Set<String>, from stations: [RadioStation], current: Int) -> Int {
        let kept = removing(ids, from: stations)
        guard !kept.isEmpty else { return 0 }
        let tuned = RadioDial.clamp(current, count: stations.count)
        let before = stations.prefix(tuned).filter { !ids.contains($0.id) }.count
        return RadioDial.clamp(before, count: kept.count)
    }
}

// MARK: - Backup addresses

/// 一条地址连不上时下一步连哪条、等多久。
///
/// 先按顺序换备用地址，只等 1 秒（一时卡顿有机会自己恢复）；一轮都失败了回到主地址，按 `RadioRetry` 的
/// 间隔（2、4、8、16，之后每 30 秒）再来一轮。只有一条地址的电台和原来
/// 一样：每次失败按那个间隔重连，第三次起提示连不上。
public enum RadioFailover {
    public struct Step: Equatable, Sendable {
        /// 下一次连第几条地址（0 是主地址）。
        public var address: Int
        /// 等几秒再连。
        public var wait: Double
        /// 已经整轮失败了几次。
        public var round: Int
        /// 该在面板上提示“连接不上电台”了。
        public var showsProblem: Bool
    }

    /// 换备用地址前等几秒。
    public static let backupWait: Double = 1

    public static func after(failed address: Int, count: Int, round: Int) -> Step {
        let total = max(count, 1)
        let rounds = max(round, 0)
        if address + 1 < total {
            return Step(address: address + 1, wait: backupWait, round: rounds, showsProblem: rounds >= 2)
        }
        return Step(address: 0, wait: RadioRetry.delay(attempt: rounds), round: rounds + 1,
                    showsProblem: rounds + 1 >= 3)
    }
}

// MARK: - Sleep timer fade

/// 定时关闭到点前最后 30 秒线性渐弱到 0，然后暂停。音量本身不改，
/// 渐弱只是乘在播放音量上的系数，暂停后系数回到 1。渐弱中用户手动调音量、
/// 换台或暂停，播放器就取消渐弱（见 `RadioPlayer`）。
public enum RadioFade {
    public static let duration: Double = 30

    public enum Phase: Equatable, Sendable {
        /// 没开定时。
        case off
        /// 定时开着，还没到最后 30 秒。
        case full
        /// 渐弱中，值是音量系数（1 到 0）。
        case fading(Double)
        /// 到点了，该暂停。
        case due
    }

    public static func phase(now: Date, stopAt: Date?, duration: Double = RadioFade.duration) -> Phase {
        guard let stopAt else { return .off }
        let remaining = stopAt.timeIntervalSince(now)
        if remaining <= 0 { return .due }
        if remaining > duration { return .full }
        return .fading(multiplier(remaining: remaining, duration: duration))
    }

    /// 剩 `remaining` 秒时的音量系数：剩满 30 秒是 1，到点是 0，中间按直线。
    public static func multiplier(remaining: Double, duration: Double = RadioFade.duration) -> Double {
        guard duration > 0 else { return remaining > 0 ? 1 : 0 }
        return min(max(remaining / duration, 0), 1)
    }

    /// 播放器用的增益（0 到 1）：面板上的音量（0 到 100）乘系数。
    public static func gain(volume: Double, multiplier: Double) -> Double {
        min(max(volume, 0), 100) / 100 * min(max(multiplier, 0), 1)
    }
}
