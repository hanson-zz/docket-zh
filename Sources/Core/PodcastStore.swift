import Foundation

// MARK: - 存档读取与迁移

/// 播客存档（Application Support 里的 podcasts.json）的读取和旧数据迁移。
///
/// 以前整个存档用一次 `try? JSONDecoder().decode(PodcastLibrary.self, …)` 读，
/// 任何一个节目、任何一集、任何一个字段读不出来（字段缺了、改过名、类型变了、
/// 把小宇宙页面链接当 id 存的旧写法），整个存档就悄悄变成空的；接着订阅一个新
/// 节目时 `save()` 把只剩新节目的存档写回去，旧订阅就再也读不回来了。这里改成
/// 逐个节目、逐集读，读不出来的只丢那一条，并且数清楚修好了几条、丢了几条，
/// 让 `PodcastService` 先备份原文件、再在面板上说明白。纯函数，测试覆盖各种旧写法。
public enum PodcastStore {

    /// 读一份存档。整个文件不是 JSON 或者形状完全不认识时 `fileUnreadable`。
    public static func load(_ data: Data) -> PodcastLoad {
        do {
            return try JSONDecoder().decode(Box.self, from: data).load
        } catch {
            var load = PodcastLoad()
            load.fileUnreadable = true
            return load
        }
    }

    private struct Box: Decodable {
        var load: PodcastLoad
        init(from decoder: Decoder) throws { load = try PodcastStore.decodeLibrary(decoder) }
    }

    /// 存档的几种形状：现在的 `{"shows": [...], "newSince": ...}`；更早的
    /// `{"subscriptions": [...]}` / `{"podcasts": [...]}`；或者干脆是一个数组。
    /// 数组里每一项可以是节目对象，也可以只是一条链接或一个 id。
    static func decodeLibrary(_ decoder: Decoder) throws -> PodcastLoad {
        var load = PodcastLoad()
        var entries: [Entry] = []
        if let c = try? decoder.container(keyedBy: PodcastArchiveKey.self) {
            var known = false
            for key in ["shows", "subscriptions", "podcasts"] {
                guard let list = c.lossy([Entry].self, key) else { continue }
                known = true
                entries += key == "shows" ? list : list.map { $0.repaired() }
            }
            for key in ["newSince", "notifiedThrough", "progress", "pendingLinks"] where c.contains(.init(key)) {
                known = true
            }
            guard known else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "不认识的播客存档"))
            }
            load.library.newSince = c.dates("newSince")
            load.library.notifiedThrough = c.dates("notifiedThrough")
            load.library.progress = (c.lossy([String: PodcastArchiveLossy<PodcastProgress>].self, "progress") ?? [:])
                .compactMapValues(\.value)
            load.library.pendingLinks = c.lossy([String].self, "pendingLinks") ?? []
        } else {
            let list = try decoder.singleValueContainer().decode([Entry].self)
            entries = list.map { $0.repaired() }
        }

        var order: [String] = []
        var byID: [String: PodcastShow] = [:]
        for entry in entries {
            switch entry {
            case .show(let show, let repaired):
                if repaired { load.repaired += 1 }
                if let kept = byID[show.id] {
                    // 同一个节目存了两份（旧链接一份、新 id 一份）：留单集多的那份。
                    if show.episodes.count > kept.episodes.count { byID[show.id] = show }
                } else {
                    order.append(show.id)
                    byID[show.id] = show
                }
            case .lookup(let link):
                load.repaired += 1
                if !load.library.pendingLinks.contains(link) { load.library.pendingLinks.append(link) }
            case .broken:
                load.unreadable += 1
            }
        }
        load.library.shows = order.compactMap { byID[$0] }
        return load
    }

    /// 存档里的一项。
    enum Entry: Decodable {
        /// `repaired`：不是按现在的写法存的（id 是链接、字段改过名、只存了链接），读的时候换过。
        case show(PodcastShow, repaired: Bool)
        /// 只有单集链接或短链，要联网才知道是哪个节目。
        case lookup(String)
        case broken

        init(from decoder: Decoder) throws {
            if let text = try? decoder.singleValueContainer().decode(String.self) {
                switch PodcastStore.link(text) {
                case .podcast(let id)?:
                    self = .show(PodcastStore.placeholder(id), repaired: true)
                case .episode(let eid)?:
                    self = .lookup(XiaoyuzhouLink.episode(eid).pageURL.absoluteString)
                case nil:
                    self = PodcastStore.isShortLink(text) ? .lookup(PodcastStore.trimmed(text)) : .broken
                }
                return
            }
            do {
                let show = try PodcastShow(from: decoder)
                let c = try decoder.container(keyedBy: PodcastArchiveKey.self)
                let current = c.text(["id"]) == show.id && c.contains(.init("episodes"))
                    && c.contains(.init("title"))
                self = .show(show, repaired: !current)
            } catch PodcastArchiveError.needsLookup(let link) {
                self = .lookup(link)
            } catch {
                self = .broken
            }
        }

        /// 来自旧形状（`subscriptions`、顶层数组）的节目一律算迁移过。
        func repaired() -> Entry {
            if case .show(let show, _) = self { return .show(show, repaired: true) }
            return self
        }
    }

    /// 只知道 id 的节目：先占个位，启动后重新获取标题、封面和单集。
    public static func placeholder(_ id: String) -> PodcastShow {
        PodcastShow(id: id, title: tr("小宇宙节目"))
    }

    // MARK: 链接

    /// 存档里出现过的各种写法都换成小宇宙链接：纯 id（当节目 id）、完整链接、
    /// 带 `?s=` 分享参数的链接、只有路径的 `/podcast/<id>`、前后带空格或引号的。
    public static func link(_ text: String) -> XiaoyuzhouLink? {
        let value = trimmed(text)
        guard !value.isEmpty else { return nil }
        if XiaoyuzhouLink.isID(value) { return .podcast(value) }
        if let parsed = XiaoyuzhouLink.parse(value) { return parsed }
        let path = #/^/?(podcast|episode)/([A-Za-z0-9]+)(?:[/?#].*)?$/#
        if let match = value.wholeMatch(of: path.ignoresCase()) {
            let id = String(match.output.2)
            guard XiaoyuzhouLink.isID(id) else { return nil }
            return match.output.1.lowercased() == "podcast" ? .podcast(id) : .episode(id)
        }
        return nil
    }

    /// 小宇宙 App 分享出来的短链（xyzfm.link/s/…），要跟着跳转才知道是哪个节目。
    public static func isShortLink(_ text: String) -> Bool {
        let value = trimmed(text).lowercased()
        let bare = value.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
        return bare.hasPrefix("xyzfm.link/") && bare.count > "xyzfm.link/".count
    }

    static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.init(charactersIn: "\"'<>()（）")))
    }
}

/// 读一份存档的结果。
public struct PodcastLoad: Equatable, Sendable {
    public var library = PodcastLibrary()
    /// 按旧写法存的、读的时候换过的条数（链接当 id、改过名的字段、只剩链接的）。
    public var repaired = 0
    /// 怎么也读不出来、只能丢掉的条数。
    public var unreadable = 0
    /// 整个文件读不出来（不是 JSON、形状不认识）。
    public var fileUnreadable = false

    public init() {}

    /// 换过写法的要马上写回新格式。
    public var needsSave: Bool { repaired > 0 }
    /// 有东西读不出来：写回之前先把原文件备份一份，面板上提示。
    public var needsBackup: Bool { fileUnreadable || unreadable > 0 }
}

/// 节目对象里只有单集链接或短链：要联网读一次才知道节目。
public enum PodcastArchiveError: Error, Equatable {
    case needsLookup(String)
}

/// 一个读不出来就是 nil、不连累整个数组的值。
public struct PodcastArchiveLossy<Value: Decodable>: Decodable {
    public var value: Value?
    public init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
}

/// 存档用的字符串键。
public struct PodcastArchiveKey: CodingKey, Hashable {
    public var stringValue: String
    public var intValue: Int? { nil }
    public init(_ name: String) { stringValue = name }
    public init?(stringValue: String) { self.stringValue = stringValue }
    public init?(intValue: Int) { nil }
}

extension KeyedDecodingContainer where Key == PodcastArchiveKey {
    /// 第一个读得出的文字；数字也收（有的旧写法 id 是数字）。
    func text(_ keys: [String]) -> String? {
        for key in keys {
            let k = PodcastArchiveKey(key)
            if let value = try? decodeIfPresent(String.self, forKey: k) { return value }
            if let value = try? decodeIfPresent(Int.self, forKey: k) { return String(value) }
        }
        return nil
    }

    func number(_ keys: [String]) -> Double? {
        for key in keys {
            let k = PodcastArchiveKey(key)
            if let value = try? decodeIfPresent(Double.self, forKey: k), value.isFinite { return value }
            if let value = try? decodeIfPresent(String.self, forKey: k), let number = Double(value),
               number.isFinite { return number }
        }
        return nil
    }

    /// 先按解码器的日期格式（现在存的是数字），再认小宇宙页面那种 ISO 8601 文字。
    func date(_ keys: [String]) -> Date? {
        for key in keys {
            let k = PodcastArchiveKey(key)
            if let value = try? decodeIfPresent(Date.self, forKey: k) { return value }
            if let value = try? decodeIfPresent(String.self, forKey: k), let date = Xiaoyuzhou.date(value) {
                return date
            }
        }
        return nil
    }

    /// 网址：正常的、写成文字的，或者小宇宙页面那种 `{"picUrl": …}` 图片对象。
    func url(_ keys: [String]) -> URL? {
        for key in keys {
            let k = PodcastArchiveKey(key)
            if let value = try? decodeIfPresent(URL.self, forKey: k) { return value }
            if let value = try? decodeIfPresent(String.self, forKey: k),
               let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
               url.scheme == "https" || url.scheme == "http" { return url }
            if let image = try? decodeIfPresent([String: String].self, forKey: k) {
                let found = ["middlePicUrl", "smallPicUrl", "picUrl", "thumbnailUrl", "url"]
                    .compactMap { image[$0] }.compactMap(URL.init(string:)).first
                if let found { return found }
            }
        }
        return nil
    }

    func lossy<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        try? decodeIfPresent(type, forKey: PodcastArchiveKey(key))
    }

    func dates(_ key: String) -> [String: Date] {
        if let value = lossy([String: Date].self, key) { return value }
        if let text = lossy([String: String].self, key) { return text.compactMapValues { Xiaoyuzhou.date($0) } }
        return [:]
    }
}

// MARK: - 收听状态

/// 单集列表里一集的样子。
public enum PodcastEpisodeState: Equatable, Sendable {
    /// 订阅后才出、还没听。
    case new
    case unplayed
    /// 听了一部分，0...1。
    case inProgress(Double)
    case finished
}

extension PodcastLibrary {
    /// 一集现在的收听状态。
    public func state(of episode: PodcastEpisode, in showID: String) -> PodcastEpisodeState {
        if let saved = progress[episode.id] {
            if saved.finished { return .finished }
            if saved.position > 0 { return .inProgress(saved.fraction) }
        }
        let mark = newSince[showID] ?? .distantFuture
        return (episode.pubDate ?? .distantPast) > mark ? .new : .unplayed
    }

    /// 面板上「继续收听」那一集：听了一半的里面最新发布的一集；都没有就是最新一集。
    public func resumeEpisode(in showID: String) -> PodcastEpisode? {
        guard let show = show(showID) else { return nil }
        let started = show.episodes.first { episode in
            guard let saved = progress[episode.id] else { return false }
            return !saved.finished && saved.position > 0
        }
        return started ?? show.episodes.first
    }
}

extension PodcastPlayback {
    /// 听了一部分的单集还剩多少：「剩 23 分钟」「剩 1 小时 5 分钟」「剩不到 1 分钟」。
    public static func remainingText(position: Double, duration: Double) -> String {
        guard position.isFinite, duration.isFinite, duration > 0 else { return "" }
        let left = Int(max(0, duration - position))
        guard left >= 60 else { return tr("剩不到 1 分钟") }
        return tr("剩 \(durationText(left))")
    }

    /// 刷新全部节目时每两个之间隔这么久，订阅多的时候不会一下子打出十几个请求
    /// 被小宇宙限流（以前全部同时发，靠后的几个常常读不出来）。
    public static let refreshSpacing: TimeInterval = 1.2
}

// MARK: - 封面色

/// 面板顶上那一抹很淡的封面色：取封面的平均色，压低饱和度、限住明暗，
/// 灰白、黑白封面不染色（用播客自己的颜色）。纯函数，可测。
public enum PodcastArtTint {
    public static let maxSaturation = 0.5
    public static let brightnessRange = 0.42...0.78
    /// 饱和度低于这个算灰，不染色。
    public static let grayThreshold = 0.1

    public static func wash(_ average: ColorCode) -> ColorCode? {
        let (h, s, v) = hsv(average)
        guard s >= grayThreshold else { return nil }
        let saturation = min(s, maxSaturation)
        let brightness = min(max(v, brightnessRange.lowerBound), brightnessRange.upperBound)
        return rgb(h, saturation, brightness)
    }

    static func hsv(_ c: ColorCode) -> (Double, Double, Double) {
        let maxV = max(c.red, c.green, c.blue), minV = min(c.red, c.green, c.blue)
        let delta = maxV - minV
        var hue = 0.0
        if delta > 0 {
            if maxV == c.red { hue = ((c.green - c.blue) / delta).truncatingRemainder(dividingBy: 6) }
            else if maxV == c.green { hue = (c.blue - c.red) / delta + 2 }
            else { hue = (c.red - c.green) / delta + 4 }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        return (hue, maxV == 0 ? 0 : delta / maxV, maxV)
    }

    static func rgb(_ h: Double, _ s: Double, _ v: Double) -> ColorCode {
        let i = Int(h * 6) % 6
        let f = h * 6 - Double(Int(h * 6))
        let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
        switch i {
        case 0: return ColorCode(red: v, green: t, blue: p)
        case 1: return ColorCode(red: q, green: v, blue: p)
        case 2: return ColorCode(red: p, green: v, blue: t)
        case 3: return ColorCode(red: p, green: q, blue: v)
        case 4: return ColorCode(red: t, green: p, blue: v)
        default: return ColorCode(red: v, green: p, blue: q)
        }
    }
}
