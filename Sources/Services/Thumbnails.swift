import AppKit
import ImageIO
import Observation
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// Small pictures of files, made once and kept.
///
/// Every file widget draws through here so nothing ever decodes a full
/// resolution photo to fill a 58pt card. Pictures are downsampled by ImageIO
/// straight from the file, which never materialises the whole bitmap; other
/// files go to Quick Look, which is what Finder itself shows. Both run off
/// the main thread, and a view asking for a thumbnail that is not ready yet
/// gets nil and is redrawn when it lands, through `generation`.
@MainActor @Observable
final class Thumbnails {
    static let shared = Thumbnails()

    /// Bumped whenever a thumbnail arrives, so views that asked are redrawn.
    private(set) var generation = 0

    @ObservationIgnored private let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        // Thumbnails of a few hundred pixels: a few hundred of them is a
        // handful of megabytes.
        cache.countLimit = 400
        return cache
    }()
    @ObservationIgnored private var pending = Set<String>()
    /// Files Quick Look and ImageIO both gave up on, so they are not retried
    /// on every redraw.
    @ObservationIgnored private var failed = Set<String>()

    private init() {}

    /// A picture of the file at most `pixels` on its long side, or nil while
    /// it is being made. Falls back to the file's icon when nothing better
    /// can be had.
    func image(for url: URL, pixels: Int) -> NSImage? {
        _ = generation
        let key = Self.key(url, pixels)
        if let hit = cache.object(forKey: key as NSString) { return hit }
        if failed.contains(key) { return icon(for: url) }
        guard !pending.contains(key) else { return nil }
        pending.insert(key)
        let size = pixels
        Task {
            let made = await Self.make(url, pixels: size)
            pending.remove(key)
            if let made {
                cache.setObject(NSImage(cgImage: made.image, size: .zero), forKey: key as NSString)
            } else {
                failed.insert(key)
            }
            generation &+= 1
        }
        return nil
    }

    /// Finder's icon for a file, which is always available immediately.
    func icon(for url: URL) -> NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }

    /// Forgets a file, after it is moved or replaced.
    func forget(_ url: URL) {
        cache.removeAllObjects()
        failed = failed.filter { !$0.hasPrefix(url.path + "|") }
    }

    private static func key(_ url: URL, _ pixels: Int) -> String {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?.timeIntervalSinceReferenceDate ?? 0
        return "\(url.path)|\(pixels)|\(Int(modified))"
    }

    struct Made: @unchecked Sendable {
        let image: CGImage
    }

    nonisolated private static let queue = DispatchQueue(label: "com.docket-zh.thumbnails",
                                             qos: .utility, attributes: .concurrent)

    private nonisolated static func make(_ url: URL, pixels: Int) async -> Made? {
        let ext = url.pathExtension.lowercased()
        if ListedFile.imageExtensions.contains(ext) {
            let direct: Made? = await withCheckedContinuation { continuation in
                queue.async { continuation.resume(returning: downsample(url, pixels: pixels)) }
            }
            if let direct { return direct }
        }
        return await quickLook(url, pixels: pixels)
    }

    /// ImageIO's own thumbnailer: decodes only as much of the file as the
    /// requested size needs, and honours the EXIF orientation.
    private nonisolated static func downsample(_ url: URL, pixels: Int) -> Made? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else { return nil }
        let thumb = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: pixels,
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumb) else { return nil }
        return Made(image: image)
    }

    private nonisolated static func quickLook(_ url: URL, pixels: Int) async -> Made? {
        let side = CGFloat(pixels) / 2
        let request = QLThumbnailGenerator.Request(fileAt: url,
                                                   size: CGSize(width: side, height: side),
                                                   scale: 2,
                                                   representationTypes: .thumbnail)
        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: representation.map { Made(image: $0.cgImage) })
            }
        }
    }
}
