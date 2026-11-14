import AppKit
import Foundation

/// 下载完成提示：看 ~/Downloads 第一层，有文件下好了就交给小熊猫（`.downloadFinished`）。
///
/// 不轮询：文件夹一有变化（新建、改名、删除）由 DispatchSource 叫醒，在后台读一次第一层，
/// 规则在 Core 的 `DesktopPetDownloadWatch`（临时文件不算、大小 2 秒不变才算下好）。
/// 还有新文件在等大小稳定时，过约 2 秒再看一次，直到都定下来。
/// 下载卡片的 `FolderFeed` 只在码头上有下载卡片时才跑，这里不依赖它。
/// 第一次打开下载文件夹时系统可能问一次「允许访问下载文件夹」。
@MainActor
final class DesktopPetDownloadsWatcher {
    static let shared = DesktopPetDownloadsWatcher()

    private init() {}

    private var source: DispatchSourceFileSystemObject?
    private var watch = DesktopPetDownloadWatch()
    private var scanning = false
    private var rescan = false
    private var recheck: Task<Void, Never>?
    /// 谁在等「下载好了」：小熊猫（`petClient`）和刘海小岛各一个。
    private var finishedHandlers: [String: @MainActor ([String]) -> Void] = [:]
    /// 谁要正在下载的进度（刘海小岛）：每读一次文件夹，给还没下完的文件的进度。
    private var progressHandlers: [String: @MainActor ([Double?]) -> Void] = [:]
    /// 上一次读到还有未完成的下载：进度变了文件夹不一定有事件，过一会儿再读。
    private var downloading = false

    private static let petClient = "pet"
    /// 有下载在进行、并且有人要进度时，多久读一次。
    private static let progressInterval: Double = 1.5

    private var folder: URL { FolderFeed.folder(for: .downloads) }

    /// 小熊猫用：下载好了交给它。
    func start(_ onFinished: @escaping @MainActor ([String]) -> Void) {
        start(client: Self.petClient, onFinished: onFinished)
    }

    func stop() {
        stop(client: Self.petClient)
    }

    /// 多个地方可以同时看：每个 `client` 一份回调，最后一个走了才停。
    func start(client: String, onFinished: @escaping @MainActor ([String]) -> Void,
               onProgress: (@MainActor ([Double?]) -> Void)? = nil) {
        finishedHandlers[client] = onFinished
        progressHandlers[client] = onProgress
        if source != nil {
            if onProgress != nil { scan() }
            return
        }
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd,
                                                               eventMask: [.write, .rename, .delete, .link],
                                                               queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated { DesktopPetDownloadsWatcher.shared.scan() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
        watch = DesktopPetDownloadWatch()
        scan()
    }

    func stop(client: String) {
        finishedHandlers[client] = nil
        progressHandlers[client] = nil
        guard finishedHandlers.isEmpty, progressHandlers.isEmpty else { return }
        source?.cancel()
        source = nil
        recheck?.cancel()
        recheck = nil
        watch = DesktopPetDownloadWatch()
        scanning = false
        rescan = false
        downloading = false
    }

    /// 读一次第一层（后台），读完交给 `DesktopPetDownloadWatch`。正在读时只记下再读一次。
    func scan() {
        guard source != nil else { return }
        guard !scanning else {
            rescan = true
            return
        }
        scanning = true
        let folder = folder
        let wantsProgress = !progressHandlers.isEmpty
        Task.detached(priority: .utility) {
            let listing = DesktopPetDownloadsWatcher.listing(folder)
            let progress = wantsProgress ? DesktopPetDownloadsWatcher.progress(folder, listing: listing) : []
            await MainActor.run {
                DesktopPetDownloadsWatcher.shared.scanned(listing, progress: progress, folder: folder)
            }
        }
    }

    func scanned(_ listing: [String: Int64]?, progress: [Double?] = [], folder: URL) {
        scanning = false
        guard source != nil else { return }
        if let listing {
            let done = watch.observe(listing, now: Date())
            if !done.isEmpty {
                let paths = done.map { folder.appendingPathComponent($0).path }
                for handler in finishedHandlers.values { handler(paths) }
            }
        }
        downloading = !progress.isEmpty
        for handler in progressHandlers.values { handler(progress) }
        if rescan {
            rescan = false
            scan()
            return
        }
        recheck?.cancel()
        recheck = nil
        let delay: Double
        if watch.waiting {
            delay = DesktopPetAssist.downloadSettle + 0.2
        } else if downloading, !progressHandlers.isEmpty {
            delay = Self.progressInterval
        } else {
            return
        }
        recheck = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            DesktopPetDownloadsWatcher.shared.scan()
        }
    }

    /// 还没下完、最近还在写入的文件（.download / .crdownload / .part）的进度，读不到进度的是 nil。
    /// 在后台调用。
    nonisolated private static func progress(_ folder: URL, listing: [String: Int64]?) -> [Double?] {
        guard let listing else { return [] }
        let now = Date()
        var result: [Double?] = []
        for name in listing.keys.sorted() where DownloadProgress.finalName(name) != name {
            let url = folder.appendingPathComponent(name)
            guard DownloadProgress.isActive(lastWrite: DownloadProgress.lastWrite(url), now: now) else { continue }
            result.append(DownloadProgress.read(url))
        }
        return result
    }

    /// 第一层的名字和大小；文件夹（含 .download 这类包）大小记 0。读不了是 nil。
    nonisolated private static func listing(_ folder: URL) -> [String: Int64]? {
        let keys: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                                      options: [])
        else { return nil }
        var result: [String: Int64] = [:]
        for url in urls {
            let values = try? url.resourceValues(forKeys: Set(keys))
            let size = values?.isDirectory == true ? 0 : Int64(values?.fileSize ?? 0)
            result[url.lastPathComponent] = size
        }
        return result
    }

    /// 单击小熊猫：在访达中选中这些文件；都不在了就打开下载文件夹。
    static func reveal(_ paths: [String]) {
        let urls = paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        if urls.isEmpty {
            NSWorkspace.shared.open(FolderFeed.folder(for: .downloads))
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
    }
}
