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
    /// Pro 专属的图标未解锁时显示经典。
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

    /// bundle 自带的图标。选了别的图标时，Finder 里贴的是自定义图标。
    public static let classic = AppIconOption(
        id: "classic", title: tr("经典"), resourceName: nil, isSupporterOnly: false)

    /// 小熊猫是码头的品牌形象，所以这一款免费。
    public static let panda = AppIconOption(
        id: "panda", title: tr("小熊猫码头"), resourceName: "AppIcon-Panda", isSupporterOnly: false)

    /// 小熊猫码头的夜景版：深蓝夜空、暗色水面，同样免费。
    public static let pandaDark = AppIconOption(
        id: "pandaDark", title: tr("小熊猫夜色"), resourceName: "AppIcon-PandaDark", isSupporterOnly: false)

    // 经典扩展栏小熊猫的一套配色（用户 10-28 给的图）：深色和两款节日免费，
    // 戴皇冠、带 Pro 角标的四款是 Pro 专属。

    public static let classicDark = AppIconOption(
        id: "classicDark", title: tr("深色"), resourceName: "AppIcon-ClassicDark", isSupporterOnly: false)
    public static let classicBlue = AppIconOption(
        id: "classicBlue", title: tr("蓝色皇冠"), resourceName: "AppIcon-ClassicBlue", isSupporterOnly: true)
    public static let classicRed = AppIconOption(
        id: "classicRed", title: tr("红色皇冠"), resourceName: "AppIcon-ClassicRed", isSupporterOnly: true)
    public static let classicGold = AppIconOption(
        id: "classicGold", title: tr("金色皇冠"), resourceName: "AppIcon-ClassicGold", isSupporterOnly: true)
    public static let classicRainbow = AppIconOption(
        id: "classicRainbow", title: tr("炫彩皇冠"), resourceName: "AppIcon-ClassicRainbow", isSupporterOnly: true)
    public static let classicHalloween = AppIconOption(
        id: "classicHalloween", title: tr("万圣节"), resourceName: "AppIcon-ClassicHalloween", isSupporterOnly: false)
    public static let classicChristmas = AppIconOption(
        id: "classicChristmas", title: tr("圣诞节"), resourceName: "AppIcon-ClassicChristmas", isSupporterOnly: false)

    /// 设置里按这个顺序排列，第一项是默认。
    public static let all: [AppIconOption] = [
        classic, classicDark, classicBlue, classicRed, classicGold, classicRainbow,
        classicHalloween, classicChristmas, panda, pandaDark,
    ]

    public static var defaultOption: AppIconOption { classic }

    /// id 对应的图标；没存过、已删除或拼错的 id 一律回退经典。
    public static func option(_ id: String?) -> AppIconOption {
        guard let id else { return defaultOption }
        return all.first { $0.id == id } ?? defaultOption
    }

    /// 实际使用的图标：Pro 专属而未解锁时回退经典。
    public static func shown(_ id: String?, unlocked: Bool) -> AppIconOption {
        let chosen = option(id)
        return chosen.isSupporterOnly && !unlocked ? defaultOption : chosen
    }

    /// Finder 里的图标要怎么改。
    public enum FinderAction: Equatable, Sendable { case none, set, clear }

    /// UserDefaults 里记着上次贴到 Finder 的图标 id，避免每次启动都重写。
    public static let finderAppliedKey = "appIcon.finderApplied"

    /// 选的是经典而应用包上贴着自定义图标就揭掉；选的是别的图标，应用包上
    /// 没有自定义图标（比如更新后整包被替换）或贴的不是这一款就重贴。
    public static func finderAction(for option: AppIconOption, hasCustomIcon: Bool,
                                    lastApplied: String? = nil) -> FinderAction {
        if option.isBundleIcon { return hasCustomIcon ? .clear : .none }
        if !hasCustomIcon || lastApplied != option.id { return .set }
        return .none
    }
}
