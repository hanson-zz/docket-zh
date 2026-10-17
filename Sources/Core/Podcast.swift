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
}

/// One subscribed show and the episodes its page listed the last time it
/// was read. The page lists the newest episodes only, so `episodes` is not
/// necessarily every episode the show has; `episodeCount` is.
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

    public init() {}

    public func show(_ id: String) -> PodcastShow? { shows.first { $0.id == id } }

    /// Adds a show, or refreshes it when already subscribed. Returns whether
    /// it was new. Nothing a new subscription already lists counts as new or
    /// is announced: only what comes out after it.
    @discardableResult
    public mutating func subscribe(_ show: PodcastShow) -> Bool {
        if let index = shows.firstIndex(where: { $0.id == show.id }) {
            shows[index] = show
            return false
        }
        shows.append(show)
        let mark = show.newestDate ?? .distantPast
        newSince[show.id] = mark
        notifiedThrough[show.id] = mark
        return true
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
    public mutating func merge(_ fresh: PodcastShow) -> [PodcastEpisode] {
        guard let index = shows.firstIndex(where: { $0.id == fresh.id }) else { return [] }
        let fresher = Self.newEpisodes(in: fresh, after: notifiedThrough[fresh.id])
        shows[index] = fresh
        if let newest = fresh.newestDate {
            notifiedThrough[fresh.id] = max(newest, notifiedThrough[fresh.id] ?? .distantPast)
        }
        return fresher
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
