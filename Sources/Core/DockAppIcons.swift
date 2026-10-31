import Foundation

/// 程序坞里 App 的自定义显示图标（码头 Pro）。
///
/// 只换码头扩展栏上画的图，不改系统图标、不写 App 包（访达等系统 App 受 SIP 保护，
/// 也不该碰）：启动、退出、运行中指示、角标、拖拽排序和悬停名称都照旧按原 App 的
/// bundle id 和路径走。
///
/// 按 bundle id 存，一个 App 一张图，所以同一个 App 在几个布局里、在分组里、镜像系统
/// 程序坞时都显示同一张。映射（bundle id 到文件名）存在 UserDefaults 的 `defaultsKey`，
/// 图片是缩放成方形的 PNG，放在 Application Support 下应用目录的 `folderName` 里
/// （见 Services 的 `DockAppIconStore`）。
///
/// 没解锁 Pro（试用结束、授权过期）时画回默认图标，映射和图片都留着，解锁后自动回来，
/// 见 `display(for:in:unlocked:)`。
public enum DockAppIcons {
    /// UserDefaults 里存映射的键：`[bundle id: 文件名]`。
    public static let defaultsKey = "dockAppIcons.files"
    /// 图片目录名（Application Support/<应用 bundle id>/ 下）。
    public static let folderName = "dock-app-icons"

    /// 存下来的方形图片边长（像素）。扩展栏图标最大约 128pt，放大镜效果再放大两倍左右，
    /// 2 倍屏上 512 足够清楚，文件也不大。
    public static let storedPixels = 512
    /// 图片最短边至少几像素才收。再小放到扩展栏上就是一团马赛克。
    public static let minimumPixels = 16
    /// 选的文件最大多少字节。相机原图 HEIC 一般几 MB，留足余量又不至于把内存撑爆。
    public static let maximumBytes = 50_000_000

    /// 上传时能选的文件扩展名（另外也能选一个 App，取它的图标）。
    public static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "icns", "tiff", "tif", "gif", "webp"]

    // MARK: 存储键

    /// 某个 App 的图片文件名：bundle id 转小写，只留字母、数字、点、横线和下划线，
    /// 加上 `.png`。空的、全是不认识的字符、太长的、只是点的都是 nil（不存）。
    public static func fileName(for bundleID: String) -> String? {
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, trimmed.count <= 200 else { return nil }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789.-_")
        guard trimmed.allSatisfy({ allowed.contains($0) }),
              trimmed.contains(where: { $0 != "." }) else { return nil }
        return trimmed + ".png"
    }

    /// 是不是这个功能自己写的文件名（清理目录时只删这种）。
    public static func isOwnFileName(_ name: String) -> Bool {
        guard name.hasSuffix(".png") else { return false }
        return fileName(for: String(name.dropLast(4))) == name
    }

    /// 映射里查一个 App：bundle id 不分大小写。
    public static func file(for bundleID: String, in map: [String: String]) -> String? {
        guard let key = mapKey(bundleID) else { return nil }
        return map[key].flatMap { isOwnFileName($0) ? $0 : nil }
    }

    /// 映射用的键：转小写、去空白，空的不存。
    public static func mapKey(_ bundleID: String) -> String? {
        let key = bundleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return key.isEmpty ? nil : key
    }

    /// 写一个 App 的图片（`file` 为 nil 是恢复默认图标），返回新映射。
    public static func setting(_ file: String?, for bundleID: String, in map: [String: String]) -> [String: String] {
        guard let key = mapKey(bundleID) else { return map }
        var out = map
        out[key] = file
        return out
    }

    // MARK: Pro

    /// 扩展栏上这个 App 实际画哪张自定义图：没解锁或没设过是 nil（画默认图标）。
    /// 没解锁时映射不动，解锁后同一张图自动回来。
    public static func display(for bundleID: String, in map: [String: String], unlocked: Bool) -> String? {
        guard ProLicenseGate.canUse(.dockAppIcons, unlocked: unlocked) else { return nil }
        return file(for: bundleID, in: map)
    }

    // MARK: 图片规范化

    /// 把一张图放进方形画布的方案：画布边长和图在画布里的位置（像素，原点在左下或
    /// 左上都一样，因为是居中的）。
    public struct SquareLayout: Equatable, Sendable {
        public var side: Int
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double
    }

    /// 能不能收这张图：文件不空、不超过 `maximumBytes`，宽高都至少 `minimumPixels`。
    public static func accepts(bytes: Int, pixelWidth: Int, pixelHeight: Int) -> Bool {
        bytes > 0 && bytes <= maximumBytes && pixelWidth >= minimumPixels && pixelHeight >= minimumPixels
    }

    /// 缩放成方形：画布边长是长边，不超过 `storedPixels`（小图不放大，扩展栏缩放时自己会插值）；
    /// 图按比例缩到长边等于画布边长，居中，短边两侧留透明。宽或高不是正数时是 nil。
    public static func squareLayout(pixelWidth: Int, pixelHeight: Int) -> SquareLayout? {
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }
        let longest = max(pixelWidth, pixelHeight)
        let side = min(storedPixels, longest)
        let scale = Double(side) / Double(longest)
        let width = max(1, min(Double(side), (Double(pixelWidth) * scale).rounded()))
        let height = max(1, min(Double(side), (Double(pixelHeight) * scale).rounded()))
        let x = ((Double(side) - width) / 2).rounded(.down)
        let y = ((Double(side) - height) / 2).rounded(.down)
        return SquareLayout(side: side, x: x, y: y, width: width, height: height)
    }

    // MARK: 清理

    /// 所有布局里（包括分组里）放着的 App 的 bundle id，转小写。
    public static func referencedBundleIDs(in profiles: [DockProfile]) -> Set<String> {
        var out = Set<String>()
        func walk(_ items: [DockItem]) {
            for item in items {
                switch item {
                case .app(_, let bundleID, _):
                    if let key = mapKey(bundleID) { out.insert(key) }
                case .group(let group):
                    walk(group.items)
                default:
                    break
                }
            }
        }
        for profile in profiles { walk(profile.items) }
        return out
    }

    /// 启动时清理：App 已经卸载（这台 Mac 上找不到这个 bundle id）且哪个布局里都不再放着它的，
    /// 丢掉映射、删掉图片。还在布局里的（卸载了但图标格子还在，画成失效项）先留着，等用户
    /// 从程序坞移除后下次启动再清；装在外接盘上、暂时没挂载的 App 只要还在布局里也不会被清。
    /// 返回留下的映射和要删的文件名。
    public static func pruned(_ map: [String: String], referenced: Set<String>,
                              isInstalled: (String) -> Bool) -> (kept: [String: String], removedFiles: Set<String>) {
        var kept: [String: String] = [:]
        var removed = Set<String>()
        for (bundleID, file) in map {
            let ownFile = isOwnFileName(file)
            if ownFile, referenced.contains(bundleID) || isInstalled(bundleID) {
                kept[bundleID] = file
            } else if ownFile {
                removed.insert(file)
            }
        }
        return (kept, removed)
    }

    /// 目录里映射已经不再用到的文件（换图中途退出、旧版本留下的）。只认这个功能自己的文件名。
    public static func orphanFiles(onDisk names: [String], map: [String: String]) -> Set<String> {
        let used = Set(map.values)
        return Set(names.filter { isOwnFileName($0) && !used.contains($0) })
    }
}
