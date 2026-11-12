import Foundation

/// 设置备份里的程序坞自定义图标（码头 Pro）。
///
/// 备份是一个 JSON 文件（`Backup.Payload`），图标放在它的 `dockAppIcons` 里：
/// `[bundle id（小写）: PNG 的 base64]`。存的是已经缩放好的方形 PNG（最大 512 像素，
/// 一张几十到几百 KB），所以不用另开目录或打包，备份仍然是一个文件，拷到另一台 Mac
/// 也不会丢图。旧备份没有这个字段，读出来是 nil，恢复时什么都不改。
public enum DockAppIconBackup {

    /// 从备份里读出、要写回的一张图标。
    public struct Entry: Equatable, Sendable {
        /// 映射用的键（小写的 bundle id）。
        public var bundleID: String
        public var png: Data

        public init(bundleID: String, png: Data) {
            self.bundleID = bundleID
            self.png = png
        }
    }

    private static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    /// 看文件头是不是 PNG。只收 PNG：码头自己存的图标都是 PNG，别的东西多半是手改坏的备份。
    public static func isPNG(_ data: Data) -> Bool {
        data.count > pngSignature.count && Array(data.prefix(pngSignature.count)) == pngSignature
    }

    /// 导出：映射里每个 App 读出它的图片，转成 base64。`read` 按文件名读图片目录里的文件，
    /// 读不出、不是 PNG、太大的跳过（文件丢了的那项本来也画不出来）。没有图标时是空字典。
    public static func encode(map: [String: String], read: (String) -> Data?) -> [String: String] {
        var out: [String: String] = [:]
        for (bundleID, file) in map {
            guard let key = DockAppIcons.mapKey(bundleID),
                  DockAppIcons.file(for: key, in: map) == file,
                  let data = read(file), isPNG(data), data.count <= DockAppIcons.maximumBytes else { continue }
            out[key] = data.base64EncodedString()
        }
        return out
    }

    /// 恢复：把备份里的图标解出来，按 bundle id 排好序。旧备份（nil）、bundle id 不能当文件名、
    /// base64 解不开、不是 PNG、太大的都跳过；只差大小写的同一个 App 只留一张。
    public static func entries(from icons: [String: String]?) -> [Entry] {
        guard let icons else { return [] }
        var seen = Set<String>()
        var out: [Entry] = []
        for raw in icons.keys.sorted() {
            guard let key = DockAppIcons.mapKey(raw), DockAppIcons.fileName(for: key) != nil,
                  !seen.contains(key),
                  let text = icons[raw],
                  let data = Data(base64Encoded: text, options: .ignoreUnknownCharacters),
                  isPNG(data), data.count <= DockAppIcons.maximumBytes else { continue }
            seen.insert(key)
            out.append(Entry(bundleID: key, png: data))
        }
        return out
    }
}
