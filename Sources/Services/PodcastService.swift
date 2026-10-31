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
    /// 封面压淡后的颜色（面板顶上那一抹），灰白封面没有，按封面地址。
    private(set) var artworkTint: [URL: ColorCode] = [:]
    /// 启动时存档没读全：有几条旧订阅读不出来、原文件备份在哪。面板上提示。
    private(set) var loadIssue: LoadIssue?
    /// 正在重新获取旧订阅（启动后的迁移、点「重新获取」）。
    private(set) var recovering = false

    struct LoadIssue: Equatable {
        /// 读不出来、只能丢掉的条数；整个文件读不出来时是 nil。
        var lost: Int?
        /// 原文件的备份。
        var backup: URL?

        var message: String {
            if let lost {
                return tr("有 \(lost) 个旧订阅读不出来，原存档已备份。可以重新获取，或重新粘贴链接订阅。")
            }
            return tr("播客存档读不出来，原文件已备份。可以重新获取，或重新粘贴链接订阅。")
        }
    }

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
        /// 小宇宙上找不到（404）：节目下架了，或者存的链接已经不对。
        case notFound
        /// 小宇宙拒绝了请求（403、429）：一下子请求太多被限流。
        case refused

        var message: String {
            switch self {
            case .notALink: tr("这不是小宇宙的节目或单集链接。")
            case .network: tr("连不上小宇宙，请检查网络后再试。")
            case .unreadable: tr("读不出这个节目的信息，页面可能已变更。")
            case .notFound: tr("小宇宙上找不到这个节目，可能已下架或链接已变。")
            case .refused: tr("小宇宙暂时拒绝了请求，请稍后重新获取。")
            }
        }
    }

    private init() {
        let loaded = Self.read()
        library = loaded.library
        loadIssue = loaded.issue
        if loaded.save { save() }
        // 旧存档迁移来的节目（只有 id、还没有单集）和只剩链接的订阅，启动后
        // 重新获取一次；不等到整点检查，也不要求扩展栏上放着播客卡片。
        if !library.pendingLinks.isEmpty || !library.showsToRefetch.isEmpty {
            Task { await recover() }
        }
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

    /// 一个接一个地读，中间隔 `PodcastPlayback.refreshSpacing`：以前全部同时发，
    /// 订阅多的时候被小宇宙限流，靠后的节目常常读不出来。
    func refreshAll() {
        let ids = library.shows.map(\.id)
        Task {
            for (index, id) in ids.enumerated() {
                if index > 0 { try? await Task.sleep(for: .seconds(PodcastPlayback.refreshSpacing)) }
                await refresh(id)
            }
        }
    }

    /// 重新获取读不全的订阅：先把只剩单集链接、短链的旧订阅换成节目，再把还没有
    /// 单集或上次读取失败的节目逐个重读。面板上的「重新获取」也走这里。
    func recover() async {
        guard !recovering else { return }
        recovering = true
        defer { recovering = false }
        for (index, link) in library.pendingLinks.enumerated() {
            if index > 0 { try? await Task.sleep(for: .seconds(PodcastPlayback.refreshSpacing)) }
            switch await resolve(link) {
            case .success:
                library.resolvePending(link)
                save()
            case .failure(.notALink), .failure(.notFound):
                // 链接本身不对或节目已下架：再试也没用，拿掉，提示里算一条丢失。
                library.resolvePending(link)
                loadIssue = LoadIssue(lost: (loadIssue?.lost ?? 0) + 1, backup: loadIssue?.backup)
                save()
            case .failure:
                continue
            }
        }
        let ids = Set(library.showsToRefetch).union(problems.keys)
        for (index, id) in library.shows.map(\.id).filter(ids.contains).enumerated() {
            if index > 0 { try? await Task.sleep(for: .seconds(PodcastPlayback.refreshSpacing)) }
            await refresh(id)
        }
        if library.pendingLinks.isEmpty, problems.isEmpty, loadIssue?.lost == 0 { loadIssue = nil }
    }

    /// 关掉启动时的存档提示（已经重新订阅过、不想再看）。
    func dismissLoadIssue() { loadIssue = nil }

    /// 旧订阅里的一条链接：小宇宙链接直接订阅；xyzfm.link 短链先跟着跳转拿到真正的地址。
    private func resolve(_ text: String) async -> Result<PodcastShow, Failure> {
        if let link = PodcastStore.link(text) { return await add(link) }
        guard PodcastStore.isShortLink(text) else { return .failure(.notALink) }
        let address = text.lowercased().hasPrefix("http") ? text : "https://" + text
        guard let url = URL(string: address) else { return .failure(.notALink) }
        switch await Self.landing(url) {
        case .failure(let failure): return .failure(failure)
        case .success(let landed):
            guard let link = XiaoyuzhouLink.parse(landed.absoluteString) else { return .failure(.notALink) }
            return await add(link)
        }
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
            if library.show(pid) != nil { problems[pid] = failure.message }
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
            if let image {
                artwork[url] = image
                if let average = Self.averageColor(image), let wash = PodcastArtTint.wash(average) {
                    artworkTint[url] = wash
                }
            }
        }
        return nil
    }

    /// 封面缩到 8×8 取平均色（太白、太黑的点不算，免得白边、黑底把颜色冲掉）。
    private static func averageColor(_ image: NSImage) -> ColorCode? {
        let side = 8
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        var red = 0.0, green = 0.0, blue = 0.0, count = 0.0
        for x in 0..<side {
            for y in 0..<side {
                guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let r = Double(color.redComponent), g = Double(color.greenComponent), b = Double(color.blueComponent)
                let peak = max(r, g, b), floor = min(r, g, b)
                if peak < 0.08 || floor > 0.94 { continue }
                red += r; green += g; blue += b; count += 1
            }
        }
        guard count > 0 else { return nil }
        return ColorCode(red: red / count, green: green / count, blue: blue / count)
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
        guard let http = response as? HTTPURLResponse else { return .failure(.unreadable) }
        switch http.statusCode {
        case 200..<300: return .success(String(decoding: data, as: UTF8.self))
        case 404, 410: return .failure(.notFound)
        case 403, 429: return .failure(.refused)
        default: return .failure(.unreadable)
        }
    }

    /// 短链跳转以后落到的地址。
    private nonisolated static func landing(_ url: URL) async -> Result<URL, Failure> {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(LinkPreviewFetcher.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return .failure(.network) }
        guard let landed = response.url else { return .failure(.unreadable) }
        return .success(landed)
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

    /// 读存档。以前一次 `try?` 整份解码，任何一处不对整份就读成空的，接着订阅新节目时
    /// 存档被只剩新节目的版本覆盖，旧订阅从此读不回来。现在逐个节目宽松读取
    /// （`PodcastStore.load`），旧写法换成新格式马上写回；有读不出来的，先把原文件
    /// 备份成 podcasts-backup-时间.json 再写，面板上提示可以重新获取。
    private static func read() -> (library: PodcastLibrary, issue: LoadIssue?, save: Bool) {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return (PodcastLibrary(), nil, false) }
        // Dates as plain numbers: ISO 8601 would drop the milliseconds 小宇宙
        // dates carry, and a stored mark a fraction of a second early would
        // make the newest episode look new again after every launch.
        let loaded = PodcastStore.load(data)
        var issue: LoadIssue?
        if loaded.needsBackup {
            let backup = backupCopy(of: url)
            issue = LoadIssue(lost: loaded.fileUnreadable ? nil : loaded.unreadable, backup: backup)
        }
        // 有东西读不出来却没备份成功时先不写回，免得把唯一的原文件覆盖掉。
        let canWrite = issue == nil || issue?.backup != nil
        return (loaded.library, issue, loaded.needsSave && canWrite)
    }

    private static func backupCopy(of url: URL) -> URL? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let backup = url.deletingLastPathComponent()
            .appendingPathComponent("podcasts-backup-\(formatter.string(from: .now)).json")
        do {
            try FileManager.default.copyItem(at: url, to: backup)
            return backup
        } catch {
            return nil
        }
    }

    private func save() {
        guard let url = Self.fileURL else { return }
        // 启动时没读全、当时又没备份成功：第一次写回之前再备份一次原文件。
        if let issue = loadIssue, issue.backup == nil, FileManager.default.fileExists(atPath: url.path) {
            loadIssue?.backup = Self.backupCopy(of: url)
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(library) { try? data.write(to: url, options: .atomic) }
    }
}
