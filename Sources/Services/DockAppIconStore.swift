import AppKit
import ImageIO
import Observation
import UniformTypeIdentifiers

/// 程序坞里 App 的自定义显示图标（码头 Pro）：映射、图片的读写和清理。
///
/// 规则和存储键在 Core 的 `DockAppIcons`。这里只管：
/// - 映射 `[bundle id: 文件名]` 存在 UserDefaults，图片在
///   `~/Library/Application Support/<bundle id>/dock-app-icons/<App 的 bundle id>.png`。
/// - 格子每次重画只查内存里的 `NSImage`，第一次问到某张图时才在下一轮从磁盘读；
///   读不出来（文件丢了、坏了）就当没设过，画默认图标，不弹错。
/// - 选的图片在后台用 ImageIO 解码、缩放成方形 PNG（`DockAppIcons.squareLayout`），
///   主线程只拿结果；选的是 App 就取它在访达里的图标。
/// - 启动时清理已卸载、也不在任何布局里的 App 的图片，以及目录里没人用的文件。
/// - 写图、删图都排在同一条串行队列 `io` 上，按调用的先后执行；每次更换、恢复默认都
///   领一张票（`DockAppIconTickets`），后台解码完票已过期就不再改映射，最后一次操作生效。
/// - 设置备份里带上映射和图片（`DockAppIconBackup`），恢复时写回并立刻重画。
@MainActor @Observable
final class DockAppIconStore {
    static let shared = DockAppIconStore()

    /// bundle id（小写）到文件名，和 UserDefaults 同步。
    private(set) var files: [String: String]
    /// 读好的图片，按文件名。
    private(set) var images: [String: NSImage] = [:]

    @ObservationIgnored private var asked = Set<String>()
    /// 读过盘但读不出来的文件，不再反复读。
    @ObservationIgnored private var unreadable = Set<String>()
    /// 每个 App 最近一次更换、恢复默认的票，旧的做完了也不生效。
    @ObservationIgnored private var tickets = DockAppIconTickets()

    /// 图片目录的写入、删除和备份时的读取都排在这条串行队列上，先调用的先做：
    /// 「恢复默认」的删除不会落在之后那次更换的写入后面，把新图删掉。
    private nonisolated static let io = DispatchQueue(label: "dock-app-icons.io", qos: .userInitiated)

    /// 在 `io` 上做一件事。入队发生在调用的这一刻（同步），所以队列顺序就是调用顺序。
    private nonisolated static func onQueue<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            io.async { continuation.resume(returning: work()) }
        }
    }

    private init() {
        let stored = UserDefaults.standard.dictionary(forKey: DockAppIcons.defaultsKey) as? [String: String]
        files = stored ?? [:]
    }

    // MARK: 画的时候查

    /// 这个 App 设过自定义图标没有（不管解没解锁），右键菜单里决定要不要列「恢复默认图标」。
    func hasCustomIcon(_ bundleID: String) -> Bool {
        DockAppIcons.file(for: bundleID, in: files) != nil
    }

    /// 扩展栏上画的自定义图标：没解锁、没设过、还没读好或读不出来时是 nil（画默认图标）。
    func customIcon(for bundleID: String, unlocked: Bool) -> NSImage? {
        guard let file = DockAppIcons.display(for: bundleID, in: files, unlocked: unlocked) else { return nil }
        if let image = images[file] { return image }
        // 不在画面更新途中改状态：读盘放到下一轮。
        guard !unreadable.contains(file), asked.insert(file).inserted,
              let url = Self.folder?.appending(path: file) else { return nil }
        Task { await self.load(file, from: url) }
        return nil
    }

    /// 格子上实际画的图：自定义图标优先，没有就是 App 自己的图标。
    func icon(for bundleID: String, fallback: NSImage, unlocked: Bool) -> NSImage {
        customIcon(for: bundleID, unlocked: unlocked) ?? fallback
    }

    private func load(_ file: String, from url: URL) async {
        let data = await Task.detached(priority: .utility) { try? Data(contentsOf: url) }.value
        guard let data, let image = NSImage(data: data), image.isValid, image.size.width > 0 else {
            unreadable.insert(file)
            return
        }
        // 读盘途中换了新图（已经放进内存）或恢复了默认，旧文件读出来的就不要了。
        guard images[file] == nil, files.values.contains(file) else { return }
        images[file] = image
    }

    // MARK: 更换和恢复

    enum ChangeError: Error {
        /// bundle id 不能当文件名（空的、带奇怪字符）。
        case noBundleID
        /// 读不出图片，或者太小、太大。
        case unreadable
        /// 写不进 Application Support。
        case writeFailed
        /// 还没做完时又换了一张或恢复了默认，这次作废，以后来的那次为准。不弹错。
        case superseded
    }

    /// 用选的文件当这个 App 的图标：图片缩放成方形存下；选的是 App 就取它的图标。成功后立刻生效。
    func setIcon(from source: URL, for bundleID: String) async -> Result<Void, ChangeError> {
        guard DockAppIcons.fileName(for: bundleID) != nil else { return .failure(.noBundleID) }
        let ticket = tickets.begin(bundleID)
        let png: Data?
        if Self.isApp(source) {
            png = Self.appIconPNG(source)
        } else {
            png = await Task.detached(priority: .userInitiated) {
                DockAppIconStore.squarePNG(contentsOf: source)
            }.value
        }
        return await store(png, for: bundleID, ticket: ticket)
    }

    /// 用拖来的图片数据（浏览器、预览里拖出来、没有文件的图）当这个 App 的图标。
    /// 和选文件一样缩放成方形、同样的大小限制。
    func setIcon(fromImageData data: Data, for bundleID: String) async -> Result<Void, ChangeError> {
        guard DockAppIcons.fileName(for: bundleID) != nil else { return .failure(.noBundleID) }
        let ticket = tickets.begin(bundleID)
        let png = await Task.detached(priority: .userInitiated) {
            DockAppIconStore.squarePNG(data: data)
        }.value
        return await store(png, for: bundleID, ticket: ticket)
    }

    /// 存下规范化好的 PNG，成功后立刻生效。`ticket` 已经不是这个 App 最新的一张时
    /// （解码途中又换了图或恢复了默认）不写盘；写盘途中过期的也不改映射和内存里的图。
    private func store(_ png: Data?, for bundleID: String, ticket: Int) async -> Result<Void, ChangeError> {
        guard let file = DockAppIcons.fileName(for: bundleID), let key = DockAppIcons.mapKey(bundleID),
              let folder = Self.folder else { return .failure(.noBundleID) }
        guard tickets.isCurrent(ticket, for: key) else { return .failure(.superseded) }
        guard let png, let image = NSImage(data: png), image.isValid else { return .failure(.unreadable) }
        let target = folder.appending(path: file)
        let written = await Self.onQueue { () -> Bool in
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try png.write(to: target, options: .atomic)
                return true
            } catch {
                return false
            }
        }
        guard tickets.isCurrent(ticket, for: key) else { return .failure(.superseded) }
        guard written else { return .failure(.writeFailed) }
        images[file] = image
        asked.insert(file)
        unreadable.remove(file)
        files = DockAppIcons.setting(file, for: key, in: files)
        save()
        return .success(())
    }

    /// 恢复默认图标：丢掉映射、删掉图片。没解锁时也能点。
    /// 正在后台解码、写盘的更换一并作废；删除排在已经入队的写入后面。
    func resetIcon(for bundleID: String) {
        _ = tickets.begin(bundleID)
        guard let file = DockAppIcons.file(for: bundleID, in: files) else { return }
        files = DockAppIcons.setting(nil, for: bundleID, in: files)
        save()
        images[file] = nil
        asked.remove(file)
        unreadable.remove(file)
        Self.remove([file])
    }

    private func save() {
        UserDefaults.standard.set(files, forKey: DockAppIcons.defaultsKey)
    }

    // MARK: 备份

    /// 设置备份用：每个设过图标的 App 的图片，base64（`DockAppIconBackup`）。
    /// 在 `io` 上同步读，正在写的图先写完再读，不会读到一半。
    func backupIcons() -> [String: String] {
        guard let folder = Self.folder, !files.isEmpty else { return [:] }
        let map = files
        let data: [String: Data] = Self.io.sync {
            var out: [String: Data] = [:]
            for file in Set(map.values) where DockAppIcons.isOwnFileName(file) {
                out[file] = try? Data(contentsOf: folder.appending(path: file))
            }
            return out
        }
        return DockAppIconBackup.encode(map: map) { data[$0] }
    }

    /// 从设置备份恢复：逐个写回图片和映射，立刻重画。备份里的同一个 App 覆盖现有的图，
    /// 备份里没有的 App 不动（和布局一样是合并，不是替换）。返回写回了几张。
    func restore(_ entries: [DockAppIconBackup.Entry]) async -> Int {
        var restored = 0
        for entry in entries {
            let ticket = tickets.begin(entry.bundleID)
            let source = entry.png
            // 备份可能被手改过，照常走一遍解码和缩放，坏图、超大图在这里挡掉。
            let png = await Task.detached(priority: .userInitiated) {
                DockAppIconStore.squarePNG(data: source)
            }.value
            if case .success = await store(png, for: entry.bundleID, ticket: ticket) {
                restored += 1
            }
        }
        return restored
    }

    // MARK: 清理

    /// 启动时调用：已卸载且不在任何布局里的 App 的图标丢掉，目录里没人用的文件删掉。
    func cleanUp(profiles: [DockProfile]) {
        let referenced = DockAppIcons.referencedBundleIDs(in: profiles)
        let result = DockAppIcons.pruned(files, referenced: referenced) { bundleID in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
        }
        if result.kept != files {
            files = result.kept
            save()
            for file in result.removedFiles { images[file] = nil }
        }
        let kept = files
        let removed = result.removedFiles
        guard let folder = Self.folder else { return }
        // 排在 `io` 上：之后入队的更换写完的新图不会被当成没人用的文件删掉。
        Self.io.async {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
            let orphans = DockAppIcons.orphanFiles(onDisk: names, map: kept)
            for name in removed.union(orphans) {
                try? FileManager.default.removeItem(at: folder.appending(path: name))
            }
        }
    }

    private static func remove(_ names: Set<String>) {
        guard let folder = Self.folder else { return }
        io.async {
            for name in names where DockAppIcons.isOwnFileName(name) {
                try? FileManager.default.removeItem(at: folder.appending(path: name))
            }
        }
    }

    // MARK: 图片

    static func isApp(_ url: URL) -> Bool {
        if url.pathExtension.lowercased() == "app" { return true }
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
        return type?.conforms(to: .applicationBundle) == true
    }

    /// 另一个 App 在访达里的图标，画成 512 像素的方形 PNG。
    private static func appIconPNG(_ app: URL) -> Data? {
        let icon = NSWorkspace.shared.icon(forFile: app.path(percentEncoded: false))
        let side = CGFloat(DockAppIcons.storedPixels)
        var rect = NSRect(x: 0, y: 0, width: side, height: side)
        guard let image = icon.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        return squarePNG(image)
    }

    /// 读一个图片文件（PNG、JPG、HEIC、ICNS 等，ImageIO 认得的都行），取里面最大的一张
    /// （ICNS、ICO 里有好几张），按 EXIF 方向转正，缩放成方形 PNG。读不出、太小、太大时是 nil。
    nonisolated static func squarePNG(contentsOf url: URL) -> Data? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        let bytes = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        guard bytes > 0, bytes <= DockAppIcons.maximumBytes,
              let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        return squarePNG(source: source, bytes: bytes)
    }

    /// 同上，图片在内存里（拖放带来的 PNG、TIFF、JPEG 数据）。
    nonisolated static func squarePNG(data: Data) -> Data? {
        guard !data.isEmpty, data.count <= DockAppIcons.maximumBytes,
              let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        return squarePNG(source: source, bytes: data.count)
    }

    /// 只读文件头和缩略图，不缓存解码后的原图。
    private nonisolated static var sourceOptions: CFDictionary {
        [kCGImageSourceShouldCache: false] as CFDictionary
    }

    private nonisolated static func squarePNG(source: CGImageSource, bytes: Int) -> Data? {
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }
        var best = 0
        var bestWidth = 0
        var bestHeight = 0
        for index in 0..<count {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, sourceOptions) as? [CFString: Any]
            else { continue }
            let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
            let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
            if width * height > bestWidth * bestHeight {
                best = index
                bestWidth = width
                bestHeight = height
            }
        }
        guard DockAppIcons.accepts(bytes: bytes, pixelWidth: bestWidth, pixelHeight: bestHeight) else { return nil }
        // 直接从文件出 512 像素的缩略图，不先把原图完整解成 NSImage 或位图；大图再让解码器
        // 边读边抽样（2、4、8 倍），几万像素的 PNG 内存峰值也只有抽样后那一份。
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: DockAppIcons.storedPixels,
            kCGImageSourceSubsampleFactor: DockAppIcons.subsampleFactor(pixelWidth: bestWidth, pixelHeight: bestHeight),
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, best, options as CFDictionary) else { return nil }
        return squarePNG(image)
    }

    /// 把图按 `DockAppIcons.squareLayout` 放进透明的方形画布，存成 PNG。
    nonisolated static func squarePNG(_ image: CGImage) -> Data? {
        guard let layout = DockAppIcons.squareLayout(pixelWidth: image.width, pixelHeight: image.height),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: layout.side, height: layout.side,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.clear(CGRect(x: 0, y: 0, width: layout.side, height: layout.side))
        context.draw(image, in: CGRect(x: layout.x, y: layout.y, width: layout.width, height: layout.height))
        guard let squared = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString,
                                                                 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, squared, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    // MARK: 目录

    private nonisolated static var bundleID: String { Bundle.main.bundleIdentifier ?? "com.docket-zh.app" }

    nonisolated static var folder: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: bundleID, directoryHint: .isDirectory)
            .appending(path: DockAppIcons.folderName, directoryHint: .isDirectory)
    }
}

/// 分组里的格子既可能是 App 也可能是文件夹、文件：只有 App 换自定义图标。
@MainActor
enum DockAppIconDisplay {
    static func image(for item: DockItem, fallback: NSImage, unlocked: Bool) -> NSImage {
        guard case .app(_, let bundleID, _) = item else { return fallback }
        return DockAppIconStore.shared.icon(for: bundleID, fallback: fallback, unlocked: unlocked)
    }
}
