import Foundation

// MARK: - Models

/// One episode of a 小宇宙 show, as its public page describes it.
public struct PodcastEpisode: Codable, Equatable, Sendable, Identifiable {
    /// 小宇宙's episode id, `eid`.
    public var id: String
    public var title: String
    public var pubDate: Date?
    /// Seconds.
    public var duration: Int
    public var audioURL: URL?
    public var imageURL: URL?
    /// 简介里主播写的时间轴，没有时间轴是 nil。可选，所以旧存档照常读取。
    public var chapters: [PodcastChapter]?

    public init(id: String, title: String, pubDate: Date?, duration: Int,
                audioURL: URL?, imageURL: URL? = nil, chapters: [PodcastChapter]? = nil) {
        self.id = id
        self.title = title
        self.pubDate = pubDate
        self.duration = duration
        self.audioURL = audioURL
        self.imageURL = imageURL
        self.chapters = chapters
    }

    /// 宽松读取存档：只有 id 是必须的（旧写法 `eid` 也认），其他字段缺了、
    /// 类型变了（时长存成小数、日期存成文字、网址写坏）都用默认值，免得一集
    /// 读不出来连累整个节目。写回仍是原来的字段名。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: PodcastArchiveKey.self)
        guard let id = c.text(["id", "eid"]), !id.isEmpty else {
            throw DecodingError.keyNotFound(PodcastArchiveKey("id"),
                                            .init(codingPath: c.codingPath, debugDescription: "单集没有 id"))
        }
        self.id = id
        title = c.text(["title"]) ?? tr("未命名单集")
        pubDate = c.date(["pubDate"])
        duration = Int(max(0, c.number(["duration"]) ?? 0))
        audioURL = c.url(["audioURL", "audio", "enclosure"])
        imageURL = c.url(["imageURL", "image"])
        chapters = c.lossy([PodcastChapter].self, "chapters")
    }
}

/// One subscribed show and every episode kept for it. The page lists the
/// newest episodes only, so each read is merged into what was kept before
/// (see `PodcastLibrary.combined`): episodes that fall off the page stay,
/// up to `PodcastLibrary.episodeLimit`. `episodes` is still not necessarily
/// every episode the show has; `episodeCount` is.
public struct PodcastShow: Codable, Equatable, Sendable, Identifiable {
    /// 小宇宙's show id, `pid`.
    public var id: String
    public var title: String
    public var author: String
    public var summary: String
    public var imageURL: URL?
    public var latestPubDate: Date?
    public var episodeCount: Int
    /// Newest first.
    public var episodes: [PodcastEpisode]

    public init(id: String, title: String, author: String = "", summary: String = "",
                imageURL: URL? = nil, latestPubDate: Date? = nil, episodeCount: Int = 0,
                episodes: [PodcastEpisode] = []) {
        self.id = id
        self.title = title
        self.author = author
        self.summary = summary
        self.imageURL = imageURL
        self.latestPubDate = latestPubDate
        self.episodeCount = episodeCount
        self.episodes = episodes
    }

    /// 宽松读取存档，同 `PodcastEpisode.init(from:)`。节目 id 认 `id`、`pid`、
    /// `podcastID`，也认整条小宇宙链接（早先有的存档把页面地址当 id 存）；都没有时
    /// 再从 `url`、`link`、`pageURL` 里找。读出来的 id 一律换成纯 id，页面地址由
    /// `pageURL` 现拼。只找到单集链接或 xyzfm.link 短链时抛
    /// `PodcastArchiveError.needsLookup`，由 `PodcastStore` 记下来联网换成节目。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: PodcastArchiveKey.self)
        let raw = ["id", "pid", "podcastID", "podcastId", "url", "link", "pageURL", "pageUrl"]
            .compactMap { c.text([$0]) }
        var found: String?
        var lookup: String?
        for candidate in raw {
            switch PodcastStore.link(candidate) {
            case .podcast(let pid)?:
                found = pid
            case .episode(let eid)?:
                lookup = lookup ?? XiaoyuzhouLink.episode(eid).pageURL.absoluteString
            case nil:
                if PodcastStore.isShortLink(candidate) { lookup = lookup ?? PodcastStore.trimmed(candidate) }
            }
            if found != nil { break }
        }
        guard let id = found else {
            if let lookup { throw PodcastArchiveError.needsLookup(lookup) }
            throw DecodingError.keyNotFound(PodcastArchiveKey("id"),
                                            .init(codingPath: c.codingPath, debugDescription: "节目没有 id"))
        }
        self.id = id
        title = c.text(["title", "name"]).flatMap { $0.isEmpty ? nil : $0 } ?? tr("未命名节目")
        author = c.text(["author"]) ?? ""
        summary = c.text(["summary", "description"]) ?? ""
        imageURL = c.url(["imageURL", "image", "cover"])
        latestPubDate = c.date(["latestPubDate", "latestEpisodePubDate"])
        let episodes = (c.lossy([PodcastArchiveLossy<PodcastEpisode>].self, "episodes") ?? [])
            .compactMap(\.value)
        self.episodes = episodes
        episodeCount = Int(max(0, c.number(["episodeCount"]) ?? Double(episodes.count)))
    }

    /// The newest date anything on the page carries.
    public var newestDate: Date? {
        ([latestPubDate] + episodes.map(\.pubDate)).compactMap { $0 }.max()
    }

    public var pageURL: URL { XiaoyuzhouLink.podcast(id).pageURL }
}

// MARK: - Links

/// A pasted 小宇宙 address: a show or one episode.
public enum XiaoyuzhouLink: Equatable, Sendable {
    case podcast(String)
    case episode(String)

    /// Finds the first 小宇宙 show or episode address anywhere in `text`, so
    /// a share message with words or punctuation right against the link
    /// ("推荐给你：https://…") still works.
    public static func parse(_ text: String) -> XiaoyuzhouLink? {
        let pattern = #/(?:^|[^A-Za-z0-9.\-])(?:https?://)?(?:[A-Za-z0-9\-]+\.)*xiaoyuzhoufm\.com/(podcast|episode)/([A-Za-z0-9]+)/#
        for match in text.matches(of: pattern.ignoresCase()) {
            let id = String(match.output.2)
            guard isID(id) else { continue }
            return match.output.1.lowercased() == "podcast" ? .podcast(id) : .episode(id)
        }
        return nil
    }

    /// 小宇宙 ids are 24 hex digits; anything alphanumeric of a sane length
    /// is accepted so a future id format does not break pasting.
    static func isID(_ text: String) -> Bool {
        (8...64).contains(text.count) && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    public var pageURL: URL {
        switch self {
        case .podcast(let id): URL(string: "https://www.xiaoyuzhoufm.com/podcast/\(id)")!
        case .episode(let id): URL(string: "https://www.xiaoyuzhoufm.com/episode/\(id)")!
        }
    }
}

// MARK: - Page parsing

/// Reads the JSON a 小宇宙 page embeds for its own renderer,
/// `<script id="__NEXT_DATA__" type="application/json">`.
///
/// The show page carries `props.pageProps.podcast` with its newest
/// `episodes`; an episode page carries `props.pageProps.episode`, whose
/// `podcast` names the show without its episodes. Pure, so it is tested
/// against trimmed copies of real pages.
public enum Xiaoyuzhou {
    /// The embedded JSON, or nil when the page has none.
    public static func nextData(_ html: String) -> Data? {
        guard let marker = html.range(of: "id=\"__NEXT_DATA__\"") else { return nil }
        guard let open = html[marker.upperBound...].range(of: ">"),
              let close = html[open.upperBound...].range(of: "</script>") else { return nil }
        let json = html[open.upperBound..<close.lowerBound]
        return json.isEmpty ? nil : Data(json.utf8)
    }

    /// The show on a show page.
    public static func podcast(fromPage html: String) -> PodcastShow? {
        guard let data = nextData(html),
              let page = try? JSONDecoder().decode(NextData.self, from: data),
              let raw = page.props.pageProps.podcast else { return nil }
        return raw.show
    }

    /// The episode on an episode page, with the id and title of its show.
    public static func episode(fromPage html: String)
        -> (episode: PodcastEpisode, podcastID: String, podcastTitle: String)? {
        guard let data = nextData(html),
              let page = try? JSONDecoder().decode(NextData.self, from: data),
              let raw = page.props.pageProps.episode,
              let episode = raw.episode else { return nil }
        let pid = raw.pid ?? raw.podcast?.pid
        guard let pid, !pid.isEmpty else { return nil }
        return (episode, pid, raw.podcast?.title ?? "")
    }

    /// "2024-10-13T15:31:57.767Z", with or without the fraction.
    public static func date(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }

    // The page's shape, only the fields read. Every field is optional so a
    // field 小宇宙 drops costs that field rather than the whole show.
    private struct NextData: Decodable {
        var props: Props
        struct Props: Decodable { var pageProps: PageProps }
        struct PageProps: Decodable {
            var podcast: RawPodcast?
            var episode: RawEpisode?
        }
    }

    private struct RawImage: Decodable {
        var picUrl: String?
        var thumbnailUrl: String?
        var smallPicUrl: String?
        var middlePicUrl: String?

        /// The 200-ish pixel copy where there is one: a card draws it at 40pt.
        var url: URL? {
            [middlePicUrl, smallPicUrl, picUrl, thumbnailUrl].compactMap { $0 }
                .compactMap(URL.init(string:)).first { $0.scheme == "https" || $0.scheme == "http" }
        }
    }

    private struct RawPodcast: Decodable {
        var pid: String?
        var title: String?
        var author: String?
        var description: String?
        var image: RawImage?
        var latestEpisodePubDate: String?
        var episodeCount: Int?
        var episodes: [RawEpisode]?

        var show: PodcastShow? {
            guard let pid, !pid.isEmpty else { return nil }
            let episodes = (self.episodes ?? []).compactMap(\.episode)
                .sorted { ($0.pubDate ?? .distantPast) > ($1.pubDate ?? .distantPast) }
            return PodcastShow(id: pid,
                               title: (title?.isEmpty == false ? title : nil) ?? tr("未命名节目"),
                               author: author ?? "",
                               summary: description ?? "",
                               imageURL: image?.url,
                               latestPubDate: Xiaoyuzhou.date(latestEpisodePubDate),
                               episodeCount: episodeCount ?? episodes.count,
                               episodes: episodes)
        }
    }

    private struct RawEpisode: Decodable {
        var eid: String?
        var pid: String?
        var title: String?
        var duration: Double?
        var pubDate: String?
        var image: RawImage?
        var enclosure: Enclosure?
        var media: Media?
        var podcast: RawPodcast?
        var description: String?
        var shownotes: String?

        struct Enclosure: Decodable { var url: String? }
        struct Media: Decodable {
            var source: Source?
            struct Source: Decodable { var url: String? }
        }

        var episode: PodcastEpisode? {
            guard let eid, !eid.isEmpty else { return nil }
            let audio = [enclosure?.url, media?.source?.url].compactMap { $0 }
                .compactMap(URL.init(string:)).first
            let seconds = max(0, duration ?? 0)
            // 简介和 shownotes 哪个写了时间轴就用哪个，都写了取条数多的。
            let candidates = [shownotes, description].compactMap { $0 }
                .map { PodcastChapters.parse($0, duration: seconds) }
            let chapters = candidates.max { $0.count < $1.count } ?? []
            return PodcastEpisode(id: eid,
                                  title: (title?.isEmpty == false ? title : nil) ?? tr("未命名单集"),
                                  pubDate: Xiaoyuzhou.date(pubDate),
                                  duration: Int(seconds),
                                  audioURL: audio,
                                  imageURL: image?.url,
                                  chapters: chapters.isEmpty ? nil : chapters)
        }
    }
}

// MARK: - Library

/// Where one episode was left.
public struct PodcastProgress: Codable, Equatable, Sendable {
    public var position: Double
    public var duration: Double
    public var finished: Bool

    public init(position: Double, duration: Double, finished: Bool = false) {
        self.position = position
        self.duration = duration
        self.finished = finished
    }

    /// 0...1 for a progress bar.
    public var fraction: Double {
        guard duration > 0 else { return finished ? 1 : 0 }
        return finished ? 1 : min(1, max(0, position / duration))
    }
}

/// Every subscription, what is new in each, and where each episode was left.
///
/// Shared by every 播客 widget, so a show added from the bookmarks widget
/// appears in all of them. Pure, so the "is this new" rules are tested.
public struct PodcastLibrary: Codable, Equatable, Sendable {
    /// In the order they were added.
    public var shows: [PodcastShow] = []
    /// Per show: episodes published after this are new until played.
    public var newSince: [String: Date] = [:]
    /// Per show: the newest episode a notification has already announced.
    public var notifiedThrough: [String: Date] = [:]
    /// Per episode id.
    public var progress: [String: PodcastProgress] = [:]
    /// 旧存档里只剩单集链接的订阅：要联网读单集页才知道是哪个节目，
    /// `PodcastService` 启动时换成节目，换好了从这里拿掉。
    public var pendingLinks: [String] = []

    public init() {}

    enum CodingKeys: String, CodingKey {
        case shows, newSince, notifiedThrough, progress, pendingLinks
    }

    /// 宽松读取，见 `PodcastStore.load`：缺字段、改过名的字段、整条链接当 id、
    /// 坏掉的某一个节目或某一集，都不再让整个存档读成空的。
    public init(from decoder: Decoder) throws {
        self = try PodcastStore.decodeLibrary(decoder).library
    }

    public func show(_ id: String) -> PodcastShow? { shows.first { $0.id == id } }

    /// Adds a show, or refreshes it when already subscribed. Returns whether
    /// it was new. Nothing a new subscription already lists counts as new or
    /// is announced: only what comes out after it.
    @discardableResult
    public mutating func subscribe(_ show: PodcastShow) -> Bool {
        if let index = shows.firstIndex(where: { $0.id == show.id }) {
            shows[index] = Self.combined(shows[index], with: show)
            return false
        }
        shows.append(show)
        let mark = show.newestDate ?? .distantPast
        newSince[show.id] = mark
        notifiedThrough[show.id] = mark
        return true
    }

    /// 订阅成功或确认读不出来以后，把这条旧链接从待换列表里拿掉。
    public mutating func resolvePending(_ link: String) {
        pendingLinks.removeAll { $0 == link }
    }

    /// 存档里有、但还没读到过单集的节目（旧存档迁移来的、上次读取失败的），
    /// 启动后先重新获取它们。
    public var showsToRefetch: [String] {
        shows.filter { $0.episodes.isEmpty }.map(\.id)
    }

    public mutating func remove(_ id: String) {
        guard let show = show(id) else { return }
        shows.removeAll { $0.id == id }
        newSince[id] = nil
        notifiedThrough[id] = nil
        for episode in show.episodes { progress[episode.id] = nil }
    }

    /// Takes a fresh read of a subscribed show and returns the episodes not
    /// announced before, newest first. An unsubscribed show is ignored.
    /// Episodes the page no longer lists are kept: see `combined`.
    public mutating func merge(_ fresh: PodcastShow) -> [PodcastEpisode] {
        guard let index = shows.firstIndex(where: { $0.id == fresh.id }) else { return [] }
        let fresher = Self.newEpisodes(in: fresh, after: notifiedThrough[fresh.id])
        shows[index] = Self.combined(shows[index], with: fresh)
        // 旧存档迁移来的节目没有「从哪天算新」的记号：第一次读到时补上，
        // 之后出的新单集才会算新，已有的不会一下子全变成新。
        if newSince[fresh.id] == nil { newSince[fresh.id] = fresh.newestDate ?? .distantPast }
        if let newest = fresh.newestDate {
            notifiedThrough[fresh.id] = max(newest, notifiedThrough[fresh.id] ?? .distantPast)
        }
        return fresher
    }

    /// 每个节目最多保留的单集数，防止存档越积越大。
    public static let episodeLimit = 500

    /// 小宇宙节目页只给最新一批单集，所以新读到的一批和已保存的按单集 id
    /// 合并：同一集用新数据的字段（新数据缺的可选字段沿用旧的），页面上已经
    /// 没有的旧单集保留；按发布时间倒序，没有日期的排最后，超过 `limit` 的
    /// 最旧单集丢弃。节目本身的标题、封面、集数等都用新数据。
    public static func combined(_ kept: PodcastShow, with fresh: PodcastShow,
                                limit: Int = episodeLimit) -> PodcastShow {
        var byID: [String: PodcastEpisode] = [:]
        for episode in kept.episodes where byID[episode.id] == nil { byID[episode.id] = episode }
        for episode in fresh.episodes {
            if let old = byID[episode.id] {
                byID[episode.id] = updated(old, with: episode)
            } else {
                byID[episode.id] = episode
            }
        }
        var result = fresh
        result.episodes = Array(byID.values.sorted(by: newestFirst).prefix(max(0, limit)))
        return result
    }

    /// `fresh` 的字段覆盖 `old`，但 `fresh` 缺的（没日期、没音频、没封面、
    /// 没时间轴、时长为 0）沿用 `old`。
    static func updated(_ old: PodcastEpisode, with fresh: PodcastEpisode) -> PodcastEpisode {
        var episode = fresh
        if episode.pubDate == nil { episode.pubDate = old.pubDate }
        if episode.duration <= 0 { episode.duration = old.duration }
        if episode.audioURL == nil { episode.audioURL = old.audioURL }
        if episode.imageURL == nil { episode.imageURL = old.imageURL }
        if episode.chapters == nil { episode.chapters = old.chapters }
        return episode
    }

    /// 发布时间倒序；同一时间（或都没有日期）按 id 排，顺序稳定。
    static func newestFirst(_ a: PodcastEpisode, _ b: PodcastEpisode) -> Bool {
        switch (a.pubDate, b.pubDate) {
        case let (x?, y?) where x != y: return x > y
        case (.some, nil): return true
        case (nil, .some): return false
        default: return a.id > b.id
        }
    }

    /// 单集列表底部那一行：已保存的单集是不是已经是节目的全部。
    public static func hasOlderEpisodes(_ show: PodcastShow) -> Bool {
        show.episodeCount > show.episodes.count
    }

    /// Episodes dated after `mark`. Without a mark nothing is new: a show
    /// read for the first time announces nothing.
    public static func newEpisodes(in show: PodcastShow, after mark: Date?) -> [PodcastEpisode] {
        guard let mark else { return [] }
        return show.episodes.filter { ($0.pubDate ?? .distantPast) > mark }
    }

    /// Published since subscribing and not started.
    public func unheard(_ showID: String) -> [PodcastEpisode] {
        guard let show = show(showID) else { return [] }
        let mark = newSince[showID] ?? .distantFuture
        return show.episodes.filter { ($0.pubDate ?? .distantPast) > mark && progress[$0.id] == nil }
    }

    public var unheardCount: Int { shows.reduce(0) { $0 + unheard($1.id).count } }

    /// Clears a show's new episodes without playing them.
    public mutating func markHeard(_ showID: String) {
        guard let newest = show(showID)?.newestDate else { return }
        newSince[showID] = max(newest, newSince[showID] ?? .distantPast)
    }

    /// Saves where an episode is. Within the last 15 seconds counts as
    /// finished, so the next play starts it over rather than at its credits.
    public mutating func record(_ episodeID: String, position: Double, duration: Double) {
        guard position.isFinite, duration.isFinite, position >= 0 else { return }
        let finished = duration > 0 && position >= duration - PodcastPlayback.finishMargin
        progress[episodeID] = PodcastProgress(position: position, duration: duration, finished: finished)
    }

    public mutating func markFinished(_ episodeID: String, duration: Double) {
        progress[episodeID] = PodcastProgress(position: duration, duration: duration, finished: true)
    }

    /// Where playback of an episode should start.
    public func resumePosition(_ episodeID: String) -> Double {
        guard let saved = progress[episodeID], !saved.finished else { return 0 }
        return max(0, saved.position)
    }
}

// MARK: - Playback and text

public enum PodcastPlayback {
    public static let backSeconds: Double = 15
    public static let forwardSeconds: Double = 30
    /// The tail of an episode that counts as heard.
    public static let finishMargin: Double = 15

    /// `position + delta`, kept inside the episode.
    public static func skip(_ position: Double, by delta: Double, duration: Double) -> Double {
        let target = position + delta
        guard duration > 0 else { return max(0, target) }
        return min(max(0, target), duration)
    }

    /// "1:02:03" or "4:05".
    public static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = max(0, Int(seconds.rounded(.down)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// "1 小时 5 分钟", "45 分钟", "不到 1 分钟".
    public static func durationText(_ seconds: Int) -> String {
        guard seconds >= 60 else { return seconds > 0 ? tr("不到 1 分钟") : "" }
        let minutes = (seconds + 30) / 60
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return tr("\(m) 分钟") }
        return m == 0 ? tr("\(h) 小时") : tr("\(h) 小时 \(m) 分钟")
    }

    /// "10月13日" this year, "2024年10月13日" otherwise, in `calendar`'s zone.
    public static func dateText(_ date: Date?, now: Date = .now, calendar: Calendar = .current) -> String {
        guard let date else { return "" }
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let thisYear = calendar.component(.year, from: now)
        guard let y = parts.year, let m = parts.month, let d = parts.day else { return "" }
        return y == thisYear ? tr("\(m)月\(d)日") : tr("\(y)年\(m)月\(d)日")
    }

    /// Hourly; a show nobody updates more than daily loses nothing by it.
    public static let refreshInterval: TimeInterval = 3600
}

// MARK: - Schedule

/// Whether the shelf has a 播客 widget, and whether any of them wants new
/// episodes announced. Checking for new episodes runs only while `active`.
public enum PodcastWatch {
    public struct Plan: Equatable, Sendable {
        public var active: Bool
        public var notify: Bool

        public init(active: Bool = false, notify: Bool = false) {
            self.active = active
            self.notify = notify
        }
    }

    public static func plan(_ widgets: [WidgetInstance]) -> Plan {
        let podcasts = widgets.filter { $0.kind == .podcast }
        return Plan(active: !podcasts.isEmpty,
                    notify: podcasts.contains { $0.config.bool("notify", default: true) })
    }
}
