import AppKit
import Foundation
import Observation
@preconcurrency import UserNotifications

/// The 播客 widgets' subscriptions: reads 小宇宙 show pages, keeps the
/// library on disk, checks for new episodes every hour while a 播客 widget is
/// on the shelf, and announces them.
///
/// One library for the whole app, kept in Application Support, so every
/// 播客 widget shows the same shows and the bookmarks widget can add one
/// with "加到播客" whether or not a 播客 widget is open.
@MainActor @Observable
final class PodcastService {
    static let shared = PodcastService()

    private(set) var library: PodcastLibrary
    /// Shows being read right now, by id.
    private(set) var loading: Set<String> = []
    /// The last read of a show that failed, in words, by id.
    private(set) var problems: [String: String] = [:]
    /// Covers already downloaded, by address.
    private(set) var artwork: [URL: NSImage] = [:]

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var active = false
    @ObservationIgnored private var notify = true
    @ObservationIgnored private var lastCheck: Date?
    @ObservationIgnored private var askedPermission = false
    @ObservationIgnored private var artworkLoading: Set<URL> = []
    @ObservationIgnored private let presenter = BannerPresenter()

    enum Failure: Error, Equatable {
        case notALink
        case network
        case unreadable

        var message: String {
            switch self {
            case .notALink: tr("这不是小宇宙的节目或单集链接。")
            case .network: tr("连不上小宇宙，请检查网络后再试。")
            case .unreadable: tr("读不出这个节目的信息，页面可能已变更。")
            }
        }
    }

    private init() {
        library = Self.read()
    }

    // MARK: Schedule

    /// Called whenever the shelf's 播客 widgets change: `active` while at
    /// least one is placed, `notify` when at least one of those wants
    /// notifications. Checks stop entirely when none is placed.
    func schedule(active: Bool, notify: Bool) {
        self.active = active
        self.notify = notify
        guard active else {
            timer?.invalidate()
            timer = nil
            return
        }
        if notify { askPermissionOnce() }
        if timer == nil {
            let timer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            timer.tolerance = 60
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
        tick()
    }

    /// Wakes every five minutes and reads the shows once an hour has passed,
    /// so a Mac that slept through the hour catches up soon after it wakes.
    private func tick() {
        guard active else { return }
        if let lastCheck, Date.now.timeIntervalSince(lastCheck) < PodcastPlayback.refreshInterval { return }
        lastCheck = .now
        refreshAll()
    }

    func refreshAll() {
        for show in library.shows { Task { await refresh(show.id) } }
    }

    // MARK: Subscribing

    /// Subscribes to the show `text` links to, directly or through one of
    /// its episodes. Returns the show.
    @discardableResult
    func add(_ text: String) async -> Result<PodcastShow, Failure> {
        guard let link = XiaoyuzhouLink.parse(text) else { return .failure(.notALink) }
        return await add(link)
    }

    @discardableResult
    func add(_ link: XiaoyuzhouLink) async -> Result<PodcastShow, Failure> {
        let pid: String
        switch link {
        case .podcast(let id):
            pid = id
        case .episode:
            switch await Self.page(link.pageURL) {
            case .failure(let failure): return .failure(failure)
            case .success(let html):
                guard let found = Xiaoyuzhou.episode(fromPage: html) else { return .failure(.unreadable) }
                pid = found.podcastID
            }
        }
        loading.insert(pid)
        defer { loading.remove(pid) }
        switch await Self.page(XiaoyuzhouLink.podcast(pid).pageURL) {
        case .failure(let failure):
            return .failure(failure)
        case .success(let html):
            guard let show = Xiaoyuzhou.podcast(fromPage: html) else { return .failure(.unreadable) }
            library.subscribe(show)
            problems[show.id] = nil
            save()
            if notify { askPermissionOnce() }
            return .success(show)
        }
    }

    func isSubscribed(_ link: XiaoyuzhouLink) -> Bool {
        if case .podcast(let id) = link { return library.show(id) != nil }
        return false
    }

    func remove(_ showID: String) {
        if let current = PodcastPlayer.shared.showID, current == showID { PodcastPlayer.shared.stop() }
        library.remove(showID)
        problems[showID] = nil
        save()
    }

    func markHeard(_ showID: String) {
        library.markHeard(showID)
        save()
    }

    /// Reads one show again and announces anything new.
    func refresh(_ showID: String) async {
        guard !loading.contains(showID), library.show(showID) != nil else { return }
        loading.insert(showID)
        defer { loading.remove(showID) }
        switch await Self.page(XiaoyuzhouLink.podcast(showID).pageURL) {
        case .failure(let failure):
            problems[showID] = failure.message
        case .success(let html):
            guard let show = Xiaoyuzhou.podcast(fromPage: html) else {
                problems[showID] = Failure.unreadable.message
                return
            }
            problems[showID] = nil
            let fresh = library.merge(show)
            save()
            if notify, active, !fresh.isEmpty { announce(fresh, in: show) }
        }
    }

    // MARK: Progress

    func record(_ episodeID: String, position: Double, duration: Double) {
        library.record(episodeID, position: position, duration: duration)
        save()
    }

    func markFinished(_ episodeID: String, duration: Double) {
        library.markFinished(episodeID, duration: duration)
        save()
    }

    // MARK: Artwork

    /// The cover at `url`, downloading it the first time it is asked for.
    func image(_ url: URL?) -> NSImage? {
        guard let url else { return nil }
        if let image = artwork[url] { return image }
        guard !artworkLoading.contains(url) else { return nil }
        artworkLoading.insert(url)
        Task {
            let image = await Self.download(url)
            artworkLoading.remove(url)
            if let image { artwork[url] = image }
        }
        return nil
    }

    private nonisolated static func download(_ url: URL) async -> NSImage? {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(LinkPreviewFetcher.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        return NSImage(data: data)
    }

    // MARK: Network

    private nonisolated static func page(_ url: URL) async -> Result<String, Failure> {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(LinkPreviewFetcher.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            return .failure(.network)
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return .failure(.unreadable)
        }
        return .success(String(decoding: data, as: UTF8.self))
    }

    // MARK: Notifications

    private func askPermissionOnce() {
        guard !askedPermission else { return }
        askedPermission = true
        let center = UNUserNotificationCenter.current()
        if center.delegate == nil { center.delegate = presenter }
        Task { _ = try? await center.requestAuthorization(options: [.alert, .sound]) }
    }

    private func announce(_ episodes: [PodcastEpisode], in show: PodcastShow) {
        let center = UNUserNotificationCenter.current()
        if center.delegate == nil { center.delegate = presenter }
        let content = UNMutableNotificationContent()
        content.title = tr("\(show.title) 有新单集")
        content.body = episodes.count == 1
            ? episodes[0].title
            : tr("\(episodes[0].title) 等 \(episodes.count) 集")
        content.sound = .default
        let request = UNNotificationRequest(identifier: "docket.podcast.\(show.id).\(episodes[0].id)",
                                            content: content, trigger: nil)
        Task { try? await center.add(request) }
    }

    // MARK: Disk

    private static var fileURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("com.docket-zh.app", isDirectory: true)
            .appendingPathComponent("podcasts.json")
    }

    private static func read() -> PodcastLibrary {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return PodcastLibrary() }
        // Dates as plain numbers: ISO 8601 would drop the milliseconds 小宇宙
        // dates carry, and a stored mark a fraction of a second early would
        // make the newest episode look new again after every launch.
        return (try? JSONDecoder().decode(PodcastLibrary.self, from: data)) ?? PodcastLibrary()
    }

    private func save() {
        guard let url = Self.fileURL else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(library) { try? data.write(to: url, options: .atomic) }
    }
}
