import Foundation

/// 判断一个 App（或文件、文件夹）的图标是不是换过了。
///
/// 扩展栏把图标按路径缓存起来，因为 `NSWorkspace.icon(forFile:)` 要读盘，
/// 扩展栏每次排版都要问一遍。但只按路径缓存，App 换了自定义图标（比如「拾掇」
/// 用 `NSWorkspace.setIcon(_:forFile:)` 往 .app 里写 `Icon\r`）后，扩展栏会一直
/// 显示旧图标，直到码头重启。
///
/// 所以缓存同时记下这几个位置的修改时间，变了就重取：
/// - 路径本身（setIcon 后多半会摸一下 bundle）
/// - `Icon\r`（自定义图标就存在这里）
/// - `Contents/Info.plist`、`Contents/Resources`（App 升级、换内置图标）
///
/// 一个都读不到（文件被删了）也算一个印记，和之前不同照样重取。
public struct AppIconStamp: Equatable, Sendable {
    public var dates: [Date?]

    public init(dates: [Date?]) {
        self.dates = dates
    }

    /// 要看修改时间的位置，顺序固定。
    public static func watchedPaths(for path: String) -> [String] {
        let base = path.hasSuffix("/") ? String(path.dropLast()) : path
        return [
            base,
            base + "/Icon\r",
            base + "/Contents/Info.plist",
            base + "/Contents/Resources",
        ]
    }

    /// 读当前的印记。只是几次 stat，便宜。
    public static func read(path: String, fileManager: FileManager = .default) -> AppIconStamp {
        AppIconStamp(dates: watchedPaths(for: path).map { p in
            (try? fileManager.attributesOfItem(atPath: p))?[.modificationDate] as? Date
        })
    }

    /// 缓存里的图标还能不能用。
    public static func isFresh(cached: AppIconStamp, current: AppIconStamp) -> Bool {
        cached == current
    }

    /// 后台多久扫一次已缓存的图标。扫一次是每个图标 4 次 stat。
    public static let sweepInterval: TimeInterval = 5
}
