import AppKit
import Foundation
import Observation

/// The newest files in a folder, re-read on a gentle poll.
///
/// One feed per folder, shared by every tile and panel that shows it, the
/// same way every Now Playing tile shares one `MusicService`. The listing
/// itself runs off the main thread; only the finished, sorted array comes
/// back, so a Downloads folder with thousands of items never stalls the
/// shelf.
///
/// Docket is not sandboxed, so nothing here needs a security-scoped
/// bookmark. What it does need is consent: Desktop and Downloads are
/// protected by TCC, and the first read of either is what makes macOS ask.
/// A refusal comes back as a permission error, which the feed reports in
/// words instead of showing an empty folder.
@MainActor @Observable
final class FolderFeed {
    enum Source: Hashable, Sendable {
        /// Pictures under a folder, recursively. Empty path means ~/Pictures.
        case pictures(String)
        /// Captures in wherever `screencapture` writes them.
        case screenshots
        /// Everything at the top of ~/Downloads.
        case downloads
    }

    let source: Source
    private(set) var files: [ListedFile] = []
    /// 还没下完的文件和进度（只有“下载”有），用来在图标上画进度。
    private(set) var downloading: [ActiveDownload] = []
    private(set) var folder: URL
    /// `nil` until the first listing finished.
    private(set) var loadedAt: Date?
    private(set) var error: String?
    /// 读不了是因为系统没给权限（文件与文件夹），面板据此给出“打开隐私设置”。
    private(set) var accessDenied = false
    /// 文件夹第一层一共几项、文件加起来多大（面板标题下的「86 个项目 · 2.4 GB」）。
    /// 文件夹本身的大小不算进去。截图是截图的张数和大小。
    private(set) var totalCount = 0
    private(set) var totalBytes: Int64 = 0
    /// 每个正在下载的文件第一次被看到的时间和进度，用来推「还剩几分钟」。
    @ObservationIgnored private var firstSeen: [URL: (at: Date, fraction: Double?)] = [:]

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var inFlight = false
    @ObservationIgnored private var lastStart: Date = .distantPast

    private static var feeds: [Source: FolderFeed] = [:]

    static func shared(_ source: Source) -> FolderFeed {
        if let feed = feeds[source] { return feed }
        let feed = FolderFeed(source: source)
        feeds[source] = feed
        return feed
    }

    private init(source: Source) {
        self.source = source
        self.folder = Self.folder(for: source)
    }

    static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    static func folder(for source: Source) -> URL {
        switch source {
        case .pictures(let path):
            let trimmed = path.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return home.appendingPathComponent("Pictures", isDirectory: true) }
            let expanded = (trimmed as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded, isDirectory: true)
        case .screenshots:
            return ScreenshotLocation.resolve(screencapturePreference("location"), home: home)
        case .downloads:
            return home.appendingPathComponent("Downloads", isDirectory: true)
        }
    }

    /// `screencapture`'s own preferences, re-read every time: the user can
    /// change the location in the Screenshot app while Docket runs, and
    /// cfprefsd keeps handing back a cached copy until asked to look again.
    static func screencapturePreference(_ key: String) -> String? {
        let domain = "com.apple.screencapture" as CFString
        _ = CFPreferencesAppSynchronize(domain)
        return CFPreferencesCopyAppValue(key as CFString, domain) as? String
    }

    /// How long a listing stays fresh. Screenshots are the one that has to
    /// feel instant: you take one and look down at the shelf.
    private var interval: TimeInterval {
        switch source {
        case .pictures: 120
        case .screenshots: 3
        case .downloads: DownloadProgress.pollInterval(downloading: !downloading.isEmpty, idle: 5)
        }
    }

    /// Idempotent; the first tile to appear starts it.
    func start() {
        guard timer == nil else { return }
        refresh(force: true)
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Re-reads now if allowed. `force` skips the interval (a panel opening,
    /// a file just trashed) but never stacks a second listing on the first.
    func refresh(force: Bool = false) {
        let now = Date.now
        guard PollGate.shouldStart(inFlight: inFlight,
                                   blocked: false,
                                   sinceLastStart: force ? .infinity : now.timeIntervalSince(lastStart),
                                   interval: interval) else { return }
        inFlight = true
        lastStart = now
        let folder = Self.folder(for: source)
        self.folder = folder
        let source = source
        let prefix = source == .screenshots ? Self.screencapturePreference("name") : nil
        Task {
            let result = await Self.offMain { Self.list(source, folder: folder, customPrefix: prefix) }
            inFlight = false
            loadedAt = .now
            switch result {
            case .success(let listed):
                error = nil
                accessDenied = false
                if listed.files != files { files = listed.files }
                if listed.downloading != downloading { downloading = listed.downloading }
                if listed.totalCount != totalCount { totalCount = listed.totalCount }
                if listed.totalBytes != totalBytes { totalBytes = listed.totalBytes }
                noteDownloads(listed.downloading)
            case .failure(let message):
                error = message.text
                accessDenied = message.denied
                files = []
                downloading = []
                totalCount = 0
                totalBytes = 0
                firstSeen = [:]
            }
        }
    }

    /// 记下新出现的下载第一次的进度；下完或取消了的忘掉。
    private func noteDownloads(_ active: [ActiveDownload]) {
        let now = Date.now
        var next: [URL: (at: Date, fraction: Double?)] = [:]
        for download in active {
            if let seen = firstSeen[download.id], seen.fraction != nil || download.fraction == nil {
                next[download.id] = seen
            } else {
                next[download.id] = (now, download.fraction)
            }
        }
        firstSeen = next
    }

    /// 「64% · 还剩 1 分钟」；推不出来时只有百分比。
    func progressLine(_ download: ActiveDownload, now: Date = .now) -> String {
        let seen = firstSeen[download.id]
        let left = seen.flatMap {
            DownloadETA.remaining(firstAt: $0.at, firstFraction: $0.fraction, now: now, fraction: download.fraction)
        }
        return DownloadETA.line(fraction: download.fraction, remaining: left)
    }

    /// 批量移走、删掉、改名以后先把旧的从列表里拿掉，不等下一次轮询。
    func forget(_ urls: Set<URL>) {
        guard !urls.isEmpty else { return }
        files.removeAll { urls.contains($0.url) }
        downloading.removeAll { urls.contains($0.id) }
        urls.forEach { Thumbnails.shared.forget($0) }
        refresh(force: true)
    }

    /// Moves a file to the Trash and drops it from the listing at once.
    func trash(_ file: ListedFile) {
        do {
            try FileManager.default.trashItem(at: file.url, resultingItemURL: nil)
            files.removeAll { $0.url == file.url }
            Thumbnails.shared.forget(file.url)
        } catch {
            NSSound.beep()
        }
        refresh(force: true)
    }

    // MARK: Listing

    struct Failure: Error, Sendable {
        var text: String
        var denied = false
    }

    /// 系统设置 ▸ 隐私与安全性 ▸ 文件与文件夹。
    static func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") else { return }
        NSWorkspace.shared.open(url)
    }

    struct Listing: Sendable {
        var files: [ListedFile]
        var downloading: [ActiveDownload] = []
        var totalCount = 0
        var totalBytes: Int64 = 0
    }

    nonisolated private static let queue = DispatchQueue(label: "com.docket-zh.folderfeed", qos: .utility)

    nonisolated private static func offMain<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    nonisolated private static let keys: [URLResourceKey] = [
        .contentModificationDateKey, .creationDateKey, .addedToDirectoryDateKey,
        .isDirectoryKey, .isPackageKey, .fileSizeKey, .isHiddenKey,
    ]

    nonisolated private static func list(_ source: Source, folder: URL,
                                         customPrefix: String?) -> Result<Listing, Failure> {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .failure(Failure(text: tr("找不到文件夹“\(folder.lastPathComponent)”。")))
        }
        switch source {
        case .pictures:
            return .success(Listing(files: pictures(in: folder)))
        case .screenshots, .downloads:
            let contents: [URL]
            do {
                contents = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                      options: [.skipsHiddenFiles])
            } catch {
                return .failure(Failure(text: denied(folder), denied: true))
            }
            var listed: [ListedFile] = []
            var partial: [ListedFile] = []
            for url in contents {
                guard let file = describe(url) else { continue }
                if source == .screenshots {
                    guard !file.isDirectory, isCapture(url, customPrefix: customPrefix) else { continue }
                } else if file.isPartialDownload {
                    partial.append(file)
                    continue
                }
                listed.append(file)
            }
            // 正在下载的最多看 6 个，每个读一次扩展属性或 Safari 的 Info.plist。
            // 很久没再写入的是下失败或暂停后留下的残件，不算正在下载。
            let now = Date.now
            let active = partial.filter { DownloadProgress.isActive(lastWrite: DownloadProgress.lastWrite($0.url), now: now) }
            let downloading = ListedFile.newestFirst(active, limit: 6).map {
                ActiveDownload(file: $0, fraction: DownloadProgress.read($0.url))
            }
            // 面板里能搜索、筛选，所以列得比卡片上多：下载 400 个，截图 240 张。
            let bytes = listed.reduce(Int64(0)) { $0 + max(0, $1.size ?? 0) }
            return .success(Listing(files: ListedFile.newestFirst(listed, limit: source == .screenshots ? 240 : 400),
                                    downloading: downloading,
                                    totalCount: listed.count, totalBytes: bytes))
        }
    }

    nonisolated private static func denied(_ folder: URL) -> String {
        tr("无法读取“\(folder.lastPathComponent)”文件夹。请在 系统设置 → 隐私与安全性 → 文件与文件夹 中允许码头访问。")
    }

    nonisolated private static func describe(_ url: URL) -> ListedFile? {
        guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
        if values.isHidden == true { return nil }
        let date = values.addedToDirectoryDate ?? values.creationDate
            ?? values.contentModificationDate ?? .distantPast
        // A package (an .app, a .pages document) is one file to a person.
        let folder = values.isDirectory == true && values.isPackage != true
        return ListedFile(url: url, date: date, isDirectory: folder,
                          size: values.fileSize.map(Int64.init))
    }

    /// Named like a capture, or marked as one by `screencapture` itself.
    nonisolated private static func isCapture(_ url: URL, customPrefix: String?) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard ListedFile.imageExtensions.contains(ext) || ext == "mov" else { return false }
        if ScreenshotNaming.looksLikeCapture(url.lastPathComponent, customPrefix: customPrefix) { return true }
        return url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return getxattr(path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) >= 0
        }
    }

    /// Pictures under a folder, newest first, without walking a whole disk:
    /// packages (a Photos library among them) are skipped, and the walk
    /// stops after a fixed number of entries.
    nonisolated private static func pictures(in folder: URL) -> [ListedFile] {
        guard let walker = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var found: [ListedFile] = []
        var visited = 0
        while let url = walker.nextObject() as? URL {
            visited += 1
            if visited > 8000 || found.count >= 600 { break }
            guard ListedFile.imageExtensions.contains(url.pathExtension.lowercased()),
                  let file = describe(url), !file.isDirectory else { continue }
            var dated = file
            // A photo's own date is when it was last changed, not when it was
            // dropped into this folder.
            if let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate { dated.date = modified }
            found.append(dated)
        }
        return ListedFile.newestFirst(found, limit: 300)
    }
}
