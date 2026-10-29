import AppKit
import Observation

/// 书签图标的图片：网站图标的本地缓存和上传的图片。
///
/// 卡片和面板每次重画只查这里内存里的 `NSImage`，不联网、不读盘：第一次问到
/// 某张图时才在下一轮从磁盘读，磁盘上没有（网站图标）才联网取，取到的缩成
/// `BookmarkIcons.storedPixels` 像素的 PNG 存下来，下次启动直接用。
///
/// - 网站图标：`~/Library/Caches/<bundle id>/bookmark-icons/<域名>.png`，同一个网站
///   的书签共用一张。自动取都失败时留一个 `<域名>.none`，`BookmarkIcons.retryAfter`
///   之内不再自动试；表单里点“获取图标”不管它。
/// - 上传的图片：`~/Library/Application Support/<bundle id>/bookmark-icons/upload-<UUID>.png`，
///   配置里只存文件名（见 `BookmarkIcons`）。
@MainActor @Observable
final class BookmarkIconStore {
    static let shared = BookmarkIconStore()

    /// 网站图标，按缓存文件名（`BookmarkIcons.siteFileName`）。
    private(set) var sites: [String: NSImage] = [:]
    /// 上传的图片，按文件名。
    private(set) var uploads: [String: NSImage] = [:]

    /// 已经开始读盘的网站图标。
    @ObservationIgnored private var started = Set<String>()
    /// 读过盘、磁盘上没有的网站图标。
    @ObservationIgnored private var missingOnDisk = Set<String>()
    /// 这次运行已经自动联网试过的网站图标。
    @ObservationIgnored private var autoTried = Set<String>()
    @ObservationIgnored private var askedUploads = Set<String>()
    @ObservationIgnored private var fetching = Set<String>()

    private init() {}

    // MARK: 画的时候查

    /// 某个书签网站的图标。没有时返回 nil，并在下一轮开始读盘；`autoFetch` 时
    /// 磁盘上也没有就联网取一次（失败后隔一阵才再自动试）。卡片在网页预览还没
    /// 读到时传 false，只读盘，等预览里有了页面自己的 icon 地址再联网。
    func siteIcon(for url: URL, pageIcon: String?, autoFetch: Bool) -> NSImage? {
        guard let name = BookmarkIcons.siteFileName(for: url) else { return nil }
        if let image = sites[name] { return image }
        // 不在画面更新途中改状态：读盘和联网都放到下一轮。
        if started.insert(name).inserted {
            Task {
                await self.readSite(name)
                if autoFetch { await self.fetchIfDue(name, page: url, pageIcon: pageIcon) }
            }
        } else if autoFetch, missingOnDisk.contains(name), !autoTried.contains(name) {
            Task { await self.fetchIfDue(name, page: url, pageIcon: pageIcon) }
        }
        return nil
    }

    /// 上传的图片。还没读过时返回 nil，下一轮读盘。
    func uploadedIcon(_ file: String) -> NSImage? {
        guard BookmarkIcons.isUploadFileName(file) else { return nil }
        if let image = uploads[file] { return image }
        guard askedUploads.insert(file).inserted, let path = Self.uploadsFolder?.appending(path: file) else { return nil }
        Task {
            guard let data = await Self.read(path), let image = NSImage(data: data) else { return }
            self.uploads[file] = image
        }
        return nil
    }

    // MARK: 取网站图标

    private func readSite(_ name: String) async {
        if let path = Self.sitesFolder?.appending(path: name), let data = await Self.read(path),
           let image = NSImage(data: data) {
            sites[name] = image
        } else {
            missingOnDisk.insert(name)
        }
    }

    private func fetchIfDue(_ name: String, page: URL, pageIcon: String?) async {
        guard sites[name] == nil, missingOnDisk.contains(name), autoTried.insert(name).inserted,
              BookmarkIcons.shouldRetry(failed: Self.failureDate(name)) else { return }
        _ = await download(name, page: page, pageIcon: pageIcon)
    }

    /// 表单里点“获取图标”：不管之前失败过没有，按顺序再试一遍。取到的存进缓存。
    func fetchSiteIcon(page: URL, pageIcon: String?) async -> NSImage? {
        guard let name = BookmarkIcons.siteFileName(for: page) else { return nil }
        started.insert(name)
        autoTried.insert(name)
        return await download(name, page: page, pageIcon: pageIcon)
    }

    private func download(_ name: String, page: URL, pageIcon: String?) async -> NSImage? {
        guard fetching.insert(name).inserted else { return sites[name] }
        defer { fetching.remove(name) }
        for candidate in BookmarkIcons.iconCandidates(page: page, pageIcon: pageIcon) {
            guard let data = await Self.get(candidate), let png = Self.shrunkPNG(data),
                  let image = NSImage(data: png) else { continue }
            sites[name] = image
            if let folder = Self.sitesFolder {
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try? png.write(to: folder.appending(path: name), options: .atomic)
                try? FileManager.default.removeItem(at: folder.appending(path: name + ".none"))
            }
            return image
        }
        if let folder = Self.sitesFolder {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? Data().write(to: folder.appending(path: name + ".none"), options: .atomic)
        }
        return nil
    }

    private nonisolated static func get(_ url: URL) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue(LinkPreviewFetcher.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("image/avif,image/webp,image/png,image/svg+xml,image/*;q=0.8,*/*;q=0.5",
                         forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    private static func failureDate(_ name: String) -> Date? {
        guard let path = sitesFolder?.appending(path: name + ".none") else { return nil }
        return (try? FileManager.default.attributesOfItem(atPath: path.path))?[.modificationDate] as? Date
    }

    // MARK: 上传

    /// 把选好的图片缩小存进上传目录，返回文件名；读不出图片时是 nil。
    func importUpload(from source: URL) -> String? {
        guard let data = try? Data(contentsOf: source), let png = Self.shrunkPNG(data, minimumWidth: 1),
              let image = NSImage(data: png), let folder = Self.uploadsFolder else { return nil }
        let name = BookmarkIcons.uploadFileName(UUID())
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try png.write(to: folder.appending(path: name), options: .atomic)
        } catch {
            return nil
        }
        uploads[name] = image
        askedUploads.insert(name)
        return name
    }

    /// 删掉不再用到的上传图片（书签删了、换了图标、表单取消了）。
    func removeUploads(_ files: Set<String>) {
        guard let folder = Self.uploadsFolder else { return }
        for file in files where BookmarkIcons.isUploadFileName(file) {
            uploads[file] = nil
            askedUploads.remove(file)
            try? FileManager.default.removeItem(at: folder.appending(path: file))
        }
    }

    // MARK: 图片

    /// 解出图片，最长边缩到 `BookmarkIcons.storedPixels`，存成 PNG。.ico 里有几张时取最大的那张来缩。
    static func shrunkPNG(_ data: Data, minimumWidth: Int = 16) -> Data? {
        guard let image = NSImage(data: data) else { return nil }
        let widest = image.representations.map(\.pixelsWide).max() ?? 0
        let pixels = widest > 0 ? widest : Int(image.size.width)
        if minimumWidth >= 16 {
            guard BookmarkIcons.acceptsDownload(bytes: data.count, pixelWidth: pixels) else { return nil }
        } else {
            guard pixels >= minimumWidth, data.count < 40_000_000 else { return nil }
        }
        let aspect = image.size.width > 0 && image.size.height > 0 ? image.size.height / image.size.width : 1
        let sourceWidth = CGFloat(max(pixels, 1))
        let sourceHeight = sourceWidth * aspect
        let scale = min(1, CGFloat(BookmarkIcons.storedPixels) / max(sourceWidth, sourceHeight))
        let width = max(1, Int((sourceWidth * scale).rounded()))
        let height = max(1, Int((sourceHeight * scale).rounded()))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height),
                   from: .zero, operation: .copy, fraction: 1)
        context.flushGraphics()
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: 目录

    private static var bundleID: String { Bundle.main.bundleIdentifier ?? "com.docket-zh.app" }

    static var sitesFolder: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: bundleID, directoryHint: .isDirectory)
            .appending(path: "bookmark-icons", directoryHint: .isDirectory)
    }

    static var uploadsFolder: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: bundleID, directoryHint: .isDirectory)
            .appending(path: "bookmark-icons", directoryHint: .isDirectory)
    }

    /// 读盘放到后台，主线程只拿结果。
    private nonisolated static func read(_ url: URL) async -> Data? {
        await Task.detached(priority: .utility) { try? Data(contentsOf: url) }.value
    }
}
