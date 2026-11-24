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
        id: "classic", title: tr("浅色"), resourceName: nil, isSupporterOnly: false)

    // 「小熊猫码头」「小熊猫夜色」两款 11-24 按用户要求下架；选过的人回退经典（`option` 找不到 id）。

    // 经典扩展栏小熊猫的一套配色（用户 10-28 给的图）。11-24 用户定：只有浅色（bundle 自带，
    // id 仍是 classic）和深色免费，四款皇冠和两款节日都是 Pro 专属。

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
        id: "classicHalloween", title: tr("万圣节"), resourceName: "AppIcon-ClassicHalloween", isSupporterOnly: true)
    public static let classicChristmas = AppIconOption(
        id: "classicChristmas", title: tr("圣诞节"), resourceName: "AppIcon-ClassicChristmas", isSupporterOnly: true)

    /// 设置里按这个顺序排列，第一项是默认。
    public static let all: [AppIconOption] = [
        classic, classicDark, classicBlue, classicRed, classicGold, classicRainbow,
        classicHalloween, classicChristmas,
    ]

    /// 会员隐藏系列「小熊猫英雄」（11-24 用户定）：原创造型，不用任何现有超级英雄的形象和名字。
    /// 只有 Pro 解锁后才在设置里出现，没解锁时整组不显示（不是显示成带锁的卡片）；
    /// 图还没进 bundle 的那款也不显示，所以先上代码、等图到了直接放进 Resources/AppIcons。
    public static let heroBamboo = AppIconOption(
        id: "heroBamboo", title: tr("竹叶剑客"), resourceName: "AppIcon-HeroBamboo", isSupporterOnly: true)
    public static let heroForge = AppIconOption(
        id: "heroForge", title: tr("熔岩工匠"), resourceName: "AppIcon-HeroForge", isSupporterOnly: true)
    public static let heroCourier = AppIconOption(
        id: "heroCourier", title: tr("云端信使"), resourceName: "AppIcon-HeroCourier", isSupporterOnly: true)
    public static let heroLantern = AppIconOption(
        id: "heroLantern", title: tr("午夜巡航"), resourceName: "AppIcon-HeroLantern", isSupporterOnly: true)
    public static let heroRunner = AppIconOption(
        id: "heroRunner", title: tr("雷云跑者"), resourceName: "AppIcon-HeroRunner", isSupporterOnly: true)
    public static let heroStargazer = AppIconOption(
        id: "heroStargazer", title: tr("星图法师"), resourceName: "AppIcon-HeroStargazer", isSupporterOnly: true)
    public static let heroCaptain = AppIconOption(
        id: "heroCaptain", title: tr("码头船长"), resourceName: "AppIcon-HeroCaptain", isSupporterOnly: true)
    public static let heroNinja = AppIconOption(
        id: "heroNinja", title: tr("暗影忍者"), resourceName: "AppIcon-HeroNinja", isSupporterOnly: true)

    /// 隐藏系列，按这个顺序排在 `all` 后面。
    public static let hidden: [AppIconOption] = [
        heroBamboo, heroForge, heroCourier, heroLantern, heroRunner, heroStargazer, heroCaptain, heroNinja,
    ]

    public static var defaultOption: AppIconOption { classic }

    /// 设置里要列出的图标：解锁后在 `all` 后面接上隐藏系列。
    public static func visible(unlocked: Bool) -> [AppIconOption] {
        unlocked ? all + hidden : all
    }

    /// id 对应的图标；没存过、已删除或拼错的 id 一律回退经典。
    public static func option(_ id: String?) -> AppIconOption {
        guard let id else { return defaultOption }
        return (all + hidden).first { $0.id == id } ?? defaultOption
    }

    /// 实际使用的图标：Pro 专属而未解锁时回退经典。
    public static func shown(_ id: String?, unlocked: Bool) -> AppIconOption {
        let chosen = option(id)
        return chosen.isSupporterOnly && !unlocked ? defaultOption : chosen
    }

    /// 授权状态变了以后要换成哪款图标：选了 Pro 图标而现在没解锁时是经典，重新
    /// 解锁后是所选；和 `applied`（已套用的 id）一样就返回 nil，不用重换。
    public static func relicensed(_ id: String?, unlocked: Bool, applied: String?) -> AppIconOption? {
        let option = shown(id, unlocked: unlocked)
        return option.id == applied ? nil : option
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
