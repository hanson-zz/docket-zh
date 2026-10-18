import AppKit
import CoreLocation
import Foundation
import ImageIO
import MapKit
import Observation
import Photos

/// 相册宽幅的“那年今天”：照片图库里往年今天拍的照片，带拍摄日期和地点。
///
/// 只读 PHAsset 的 creationDate 和 location，照片本身按卡片大小要一张缩略图。
/// 地点用 MapKit 反查成城市名（和天气用的是同一个接口），查不到就只写日期。
/// 照片图库要系统的“照片”权限：宽幅卡片第一次出现在扩展栏上时请求一次，
/// 被拒绝或今天没有往年的照片时，卡片照旧轮播文件夹里的图片，能从图片自带的
/// EXIF 读到拍摄日期和 GPS 时，同样写日期和地点。
@MainActor @Observable
final class PhotoMemories {
    static let shared = PhotoMemories()

    enum Access: Equatable {
        case granted, denied, notDetermined
    }

    struct Memory: Identifiable, Equatable {
        var id: String
        var date: Date
        var latitude: Double?
        var longitude: Double?
    }

    typealias Meta = PhotoMeta

    /// 往年今天的照片，从近到远。
    private(set) var memories: [Memory] = []
    private(set) var access: Access = .notDetermined
    /// 缩略图，按照片 ID。
    private(set) var images: [String: NSImage] = [:]
    /// 反查到的地点，按照片 ID 或文件路径；空字符串是查过但没有。
    private(set) var places: [String: String] = [:]
    /// 文件夹图片的 EXIF，按路径。
    private(set) var fileMeta: [URL: Meta] = [:]

    @ObservationIgnored private var loadedDay = ""
    @ObservationIgnored private var assets: [String: PHAsset] = [:]
    @ObservationIgnored private var requested: Set<String> = []
    @ObservationIgnored private var geocoding: Set<String> = []
    @ObservationIgnored private var reading: Set<URL> = []

    private static let askedKey = "photoMemories.asked"
    /// 一天最多拿多少张，够轮播就行。
    private static let limit = 24

    private init() {}

    // MARK: 那年今天

    /// 换了一天或权限变了就重读；同一天里重复调用不做事。
    func start(now: Date = .now) {
        let status = Self.status()
        if status != access { access = status }
        switch status {
        case .notDetermined:
            guard !UserDefaults.standard.bool(forKey: Self.askedKey) else { return }
            UserDefaults.standard.set(true, forKey: Self.askedKey)
            PHPhotoLibrary.requestAuthorization(for: .readWrite, handler: Self.authorizationHandler())
        case .denied:
            if !memories.isEmpty { memories = [] }
        case .granted:
            let day = PhotoMemory.dateText(now)
            guard day != loadedDay else { return }
            loadedDay = day
            load(now: now)
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 同 `imageHandler`：系统在自己的线程上回答，闭包不能带主 actor 隔离。
    nonisolated private static func authorizationHandler() -> @Sendable (PHAuthorizationStatus) -> Void {
        { _ in
            Task { @MainActor in
                let memories = PhotoMemories.shared
                memories.loadedDay = ""
                memories.start()
            }
        }
    }

    private static func status() -> Access {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    private func load(now: Date) {
        var found: [Memory] = []
        var kept: [String: PHAsset] = [:]
        for range in PhotoMemory.dayRanges(today: now) {
            guard found.count < Self.limit else { break }
            let options = PHFetchOptions()
            options.predicate = NSPredicate(format: "mediaType == %d AND creationDate >= %@ AND creationDate < %@",
                                            PHAssetMediaType.image.rawValue,
                                            range.start as NSDate, range.end as NSDate)
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
            options.fetchLimit = Self.limit - found.count
            let result = PHAsset.fetchAssets(with: options)
            for index in 0..<result.count {
                let asset = result.object(at: index)
                guard let date = asset.creationDate else { continue }
                let coordinate = asset.location?.coordinate
                found.append(Memory(id: asset.localIdentifier, date: date,
                                    latitude: coordinate?.latitude, longitude: coordinate?.longitude))
                kept[asset.localIdentifier] = asset
            }
        }
        assets = kept
        if found != memories { memories = found }
    }

    /// 缩略图；还没有就去要，到了以后卡片会重画。
    func image(for memory: Memory) -> NSImage? {
        if let image = images[memory.id] { return image }
        guard !requested.contains(memory.id), let asset = assets[memory.id] else { return nil }
        requested.insert(memory.id)
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 640, height: 640),
                                              contentMode: .aspectFill, options: options,
                                              resultHandler: Self.imageHandler(id: memory.id))
        return nil
    }

    private func store(_ image: NSImage?, for id: String) {
        guard let image else { return }
        images[id] = image
    }

    /// 在主 actor 以外做出来：图片的回调可能在别的线程，主 actor 里写的闭包
    /// 在 Swift 6 下会被当成主 actor 隔离，在别的线程被调用就会崩。
    nonisolated private static func imageHandler(id: String) -> @Sendable (NSImage?, [AnyHashable: Any]?) -> Void {
        { image, _ in
            let box = ImageBox(image: image)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { PhotoMemories.shared.store(box.image, for: id) }
            }
        }
    }

    // MARK: 地点

    /// 反查好的城市名；没有坐标、还在查或查不到时是 nil。
    func place(key: String, latitude: Double?, longitude: Double?) -> String? {
        if let known = places[key] { return known.isEmpty ? nil : known }
        guard let latitude, let longitude, !geocoding.contains(key) else { return nil }
        geocoding.insert(key)
        Task { await geocode(key: key, latitude: latitude, longitude: longitude) }
        return nil
    }

    private func geocode(key: String, latitude: Double, longitude: Double) async {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        var name: String?
        if let request = MKReverseGeocodingRequest(location: location),
           let item = try? await request.mapItems.first {
            name = PhotoMemory.placeName(cityWithContext: item.addressRepresentations?.cityWithContext)
        }
        places[key] = name ?? ""
    }

    // MARK: 文件夹图片的 EXIF

    /// 文件夹里一张图片的拍摄日期和坐标；第一次问时去读，读完卡片重画。
    func meta(for url: URL) -> Meta? {
        if let known = fileMeta[url] { return known }
        guard !reading.contains(url) else { return nil }
        reading.insert(url)
        Task {
            let meta = await Self.readMeta(url)
            fileMeta[url] = meta
        }
        return nil
    }

    nonisolated private static func readMeta(_ url: URL) async -> Meta {
        await Task.detached(priority: .utility) { () -> PhotoMeta in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
            else { return PhotoMeta() }
            let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any]
            let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
            let text = exif?[kCGImagePropertyExifDateTimeOriginal as String] as? String
                ?? tiff?[kCGImagePropertyTIFFDateTime as String] as? String
            let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any]
            let latitude = PhotoMemory.coordinate(gps?[kCGImagePropertyGPSLatitude as String] as? Double,
                                                  ref: gps?[kCGImagePropertyGPSLatitudeRef as String] as? String,
                                                  isLatitude: true)
            let longitude = PhotoMemory.coordinate(gps?[kCGImagePropertyGPSLongitude as String] as? Double,
                                                   ref: gps?[kCGImagePropertyGPSLongitudeRef as String] as? String,
                                                   isLatitude: false)
            return PhotoMeta(date: PhotoMemory.exifDate(text),
                        latitude: latitude == nil || longitude == nil ? nil : latitude,
                        longitude: latitude == nil || longitude == nil ? nil : longitude)
        }.value
    }
}

/// 拍摄日期和坐标，从照片图库或图片文件的 EXIF 来。
struct PhotoMeta: Equatable, Sendable {
    var date: Date?
    var latitude: Double?
    var longitude: Double?
}

/// 把回调里的图片带回主线程。图片到了主线程才用，这里不碰它。
private struct ImageBox: @unchecked Sendable {
    let image: NSImage?
}
