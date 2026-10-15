import Foundation

/// 设置 ▸ 通用 ▸ 应用图标 里能选的一个图标。
///
/// 纯数据：图片由应用在运行时从 bundle 里按 `resourceName` 读取，
/// 再交给 `NSApplication.applicationIconImage`。`resourceName` 为 nil
/// 表示 bundle 自带的图标（经典），也就是把运行时图标清空、交还给系统。
public struct AppIconOption: Identifiable, Equatable, Sendable {
    /// 存进 UserDefaults 的值，发布后不要改。
    public let id: String
    /// 卡片上显示的名字。
    public let title: String
    /// bundle 里 PNG 的文件名（不含扩展名）。同名的 `-512`、`-256` 小尺寸可选。
    public let resourceName: String?
    /// 赞助者专属的图标未解锁时显示经典。
    public let isSupporterOnly: Bool

    public init(id: String, title: String, resourceName: String?, isSupporterOnly: Bool) {
        self.id = id
        self.title = title
        self.resourceName = resourceName
        self.isSupporterOnly = isSupporterOnly
    }

    /// 是不是 bundle 自带的经典图标。
    public var isBundleIcon: Bool { resourceName == nil }
}

/// 所有可选的应用图标。以后加新的小熊猫图标，往 `all` 里追加一项、
/// 把 PNG 放进 Resources/AppIcons 即可。
public enum AppIconCatalog {
    /// UserDefaults 里保存所选图标 id 的键。
    public static let key = "appIcon.choice"

    /// bundle 自带的图标，Finder 和启动台一直显示它。
    public static let classic = AppIconOption(
        id: "classic", title: "经典", resourceName: nil, isSupporterOnly: false)

    /// 小熊猫是码头的品牌形象，所以这一款免费。
    public static let panda = AppIconOption(
        id: "panda", title: "小熊猫码头", resourceName: "AppIcon-Panda", isSupporterOnly: false)

    /// 设置里按这个顺序排列，第一项是默认。
    public static let all: [AppIconOption] = [classic, panda]

    public static var defaultOption: AppIconOption { classic }

    /// id 对应的图标；没存过、已删除或拼错的 id 一律回退经典。
    public static func option(_ id: String?) -> AppIconOption {
        guard let id else { return defaultOption }
        return all.first { $0.id == id } ?? defaultOption
    }

    /// 实际使用的图标：赞助者专属而未解锁时回退经典。
    public static func shown(_ id: String?, unlocked: Bool) -> AppIconOption {
        let chosen = option(id)
        return chosen.isSupporterOnly && !unlocked ? defaultOption : chosen
    }
}
