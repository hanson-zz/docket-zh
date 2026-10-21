import Foundation

/// 全局视觉规矩：卡片的尺寸常量、字号三级、状态的取值，以及空状态的小熊猫。
///
/// 只放数字和规则，不碰 SwiftUI，这样测试能直接编译它。画的部分在
/// `Sources/Widgets/DockStyleViews.swift`。
///
/// 数值取自货架上现有卡片最常见的写法，换成常量后外观不变；卡片尺寸仍由
/// `WidgetCatalog` 计算，这里不参与。
public enum DockMetrics {
    // MARK: 卡片

    /// 卡片圆角，约为卡片高度的 0.3，和 macOS 26 的分组表面一致。
    public static let cardCorner: Double = 18
    /// 卡片左右内边距。
    public static let cardInset: Double = 10
    /// 卡片里嵌套的小块（列表行、输入框、小面板）的圆角。
    public static let innerCorner: Double = 10

    // MARK: 图标容器

    /// 横排卡片打头的圆角方底，和隔空投送、正在播放的封面一样大。
    public static let badge: Double = 40
    /// 卡片里还要放别的东西时用的小一号方底。
    public static let badgeCompact: Double = 34
    /// 竖排货架里的方底。
    public static let badgeColumn: Double = 32
    /// 方底圆角占边长的比例。
    public static let badgeCornerRatio: Double = 0.26
    /// 方底里符号的大小占边长的比例。
    public static let badgeGlyphRatio: Double = 0.42

    public static func badgeCorner(_ size: Double) -> Double {
        size * badgeCornerRatio
    }

    // MARK: 间距

    /// 方底和右边文字之间。
    public static let rowSpacing: Double = 10
    /// 竖排时方底和下面文字之间。
    public static let columnSpacing: Double = 6
    /// 值和说明两行之间。
    public static let lineSpacing: Double = 1

    // MARK: 字号三级

    /// 主数字：时间、百分比、金额，粗体。
    public static let figureSize: Double = 24
    /// 标题：卡片名、正在做的事，半粗。
    public static let titleSize: Double = 13
    /// 说明：值下面的一行小字。全仓界面字最小 13pt（2026-10），原来是 11。
    public static let captionSize: Double = 13

    // MARK: 状态

    /// 禁用时内容的不透明度。
    public static let disabledOpacity: Double = 0.45
    /// 缺权限时内容的不透明度：还要看得清写的是什么，只是退后一点。
    public static let lockedOpacity: Double = 0.8
    /// 悬停时卡片放大的倍数。2% 留在卡片之间的空隙里，不挤开旁边。
    public static let hoverScale: Double = 1.02
    /// 悬停时卡片上叠的白，深色和浅色外观各一档。
    public static let hoverLiftDark: Double = 0.07
    public static let hoverLiftLight: Double = 0.22

    /// 拖入态的虚线框：线宽、虚线段和间隔，底下垫的淡色。
    public static let dropLineWidth: Double = 1.5
    public static let dropDash: [Double] = [5, 3]
    public static let dropStrokeOpacity: Double = 0.9
    public static let dropFillDark: Double = 0.14
    public static let dropFillLight: Double = 0.10
    /// 系统蓝，深色和浅色外观各一档（浅色用深一点的蓝，白底上才看得清）。
    public static let dropBlueDark = "#0A84FF"
    public static let dropBlueLight = "#007AFF"
    /// 拖入态图标微微放大的倍数。
    public static let dropBadgeScale: Double = 1.06
}

/// 一张卡片此刻的样子。几种情况同时成立时按 `resolve` 的先后取一个。
public enum TileState: Equatable, Sendable {
    case normal
    /// 指针停在卡片上：轻微提亮。
    case hovered
    /// 拖着能接收的东西停在卡片上：虚线框。
    case targeted
    /// 用不了：整体降透明度，不响应拖放。
    case disabled
    /// 缺系统权限：卡片上一把小锁和「需要 xx 权限 · 去开启」。
    case locked

    /// 缺权限最先，因为它决定卡片能不能读到东西；用不了的卡片接不住拖放，
    /// 所以禁用压过拖入；拖入压过悬停（拖着东西时指针当然也在卡片上）。
    public static func resolve(hovered: Bool, targeted: Bool = false,
                               disabled: Bool = false, locked: Bool = false) -> TileState {
        if locked { return .locked }
        if disabled { return .disabled }
        if targeted { return .targeted }
        if hovered { return .hovered }
        return .normal
    }

    /// 内容的不透明度。
    public var contentOpacity: Double {
        switch self {
        case .disabled: DockMetrics.disabledOpacity
        case .locked: DockMetrics.lockedOpacity
        case .normal, .hovered, .targeted: 1
        }
    }

    /// 卡片的缩放。只有悬停放大，打开“减少动态效果”时不放大，只提亮。
    public func scale(reduceMotion: Bool) -> Double {
        guard self == .hovered, !reduceMotion else { return 1 }
        return DockMetrics.hoverScale
    }

    /// 卡片上叠的白有多少。
    public func hoverLift(dark: Bool) -> Double {
        guard self == .hovered else { return 0 }
        return dark ? DockMetrics.hoverLiftDark : DockMetrics.hoverLiftLight
    }

    /// 虚线框只在拖入时出现。
    public var showsDropOutline: Bool { self == .targeted }

    /// 拖入时方底里的图标微微放大；减少动态效果时不放大。
    public func badgeScale(reduceMotion: Bool) -> Double {
        guard self == .targeted, !reduceMotion else { return 1 }
        return DockMetrics.dropBadgeScale
    }

    /// 状态切换动画的时长；减少动态效果时只保留很短的淡入淡出。
    public static func transitionDuration(reduceMotion: Bool) -> Double {
        reduceMotion ? 0.1 : 0.16
    }
}

/// 缺权限时卡片上的那句话。权限名沿用 `WidgetSearch.permissions`，
/// 新手引导和小组件库里写的是同一个名字。
public enum TilePermission {
    /// 某种小组件需要的权限名，不需要就是 nil。
    public static func name(for kindRaw: String) -> String? {
        WidgetSearch.permissions[kindRaw]
    }

    /// 「需要日历权限 · 去开启」。窄卡片只说「需要权限」。
    ///
    /// 权限名本身已经以“权限”结尾（完全磁盘访问权限）时不再重复；
    /// 带括号的（自动化（邮件））把“权限”放在括号前面，读起来顺。
    public static func prompt(_ permission: String, compact: Bool = false) -> String {
        compact ? tr("需要权限") : tr("需要\(noun(permission)) · 去开启")
    }

    /// 「日历权限」「完全磁盘访问权限」「自动化权限（邮件）」。
    public static func noun(_ permission: String) -> String {
        // 英文界面：权限名查表后直接用，“Full Disk Access”本身已是完整说法，其余补 access。
        let display = trKey(permission)
        if display != permission {
            return display.hasSuffix("Access") ? display : "\(display) access"
        }
        if permission.hasSuffix("权限") { return permission }
        if let open = permission.firstIndex(of: "（"), permission.hasSuffix("）") {
            let head = permission[..<open]
            let tail = permission[open...]
            return tr("\(head)权限\(tail)")
        }
        return tr("\(permission)权限")
    }

    /// 读屏念的完整说法。
    public static func accessibilityLabel(_ permission: String) -> String {
        tr("需要\(noun(permission))，点按去开启")
    }
}

/// 空状态的小熊猫：哪张卡片空着时画哪张图、说哪句话。
///
/// 图都是 `Resources/Pet` 里现成的小熊猫（pet-panda-*.png），不新增素材，
/// 也不用大熊猫。habit 到 basket 九格各有姿势、主题色、道具和一句提示。
public enum PandaEmpty: String, CaseIterable, Sendable {
    /// 待办全空（一条都没有）。
    case todo
    /// 待办都做完了。
    case todoDone
    /// 剪贴板历史为空。
    case clipboard
    /// 下载文件夹里什么都没有。
    case downloads
    /// 文件暂存里没有文件。
    case fileShelf
    case habit, anniversary, alarm, radio, podcast, bookmarks, screenshots, photos, basket

    /// 资源名，不带扩展名。
    public var imageName: String {
        switch self {
        case .todo: "pet-panda-idle"
        case .todoDone: "pet-panda-cheer"
        case .clipboard: "pet-panda-rest"
        case .downloads: "pet-panda-rest"
        case .fileShelf: "pet-panda-idle"
        case .habit: "pet-panda-cheer"
        case .anniversary: "pet-panda-eat"
        case .alarm: "pet-panda-rest"
        case .radio: "pet-panda-idle"
        case .podcast: "pet-panda-hungry"
        case .bookmarks: "pet-panda-idle"
        case .screenshots: "pet-panda-cheer"
        case .photos: "pet-panda-rest"
        case .basket: "pet-panda-eat"
        }
    }

    /// 图要不要左右翻过来。同一张图用在两格时靠镜像区分开，九格的
    /// （图，镜像）组合各不相同。
    public var mirrored: Bool {
        switch self {
        case .anniversary, .radio, .screenshots, .photos: true
        default: false
        }
    }

    /// 这一格的主题色（`#RRGGBB`），和小组件图标同一种颜色。待办、剪贴板、
    /// 下载、文件暂存保持原样，没有主题色。
    public var themeHex: String? {
        switch self {
        case .habit: "#34C759"
        case .anniversary: "#FF698C"
        case .alarm: "#FF9F0A"
        case .radio: "#BF5AF2"
        case .podcast: "#AF52DE"
        case .bookmarks: "#0A84FF"
        case .screenshots: "#64D2FF"
        case .photos: "#FFD60A"
        case .basket: "#30D158"
        case .todo, .todoDone, .clipboard, .downloads, .fileShelf: nil
        }
    }

    /// 主题色拆成三个分量，没有主题色时为 nil。
    public var theme: ColorCode? { themeHex.flatMap { ColorCode(hex: $0) } }

    /// 右上角道具圆标里的 SF Symbol。
    public var propSymbol: String? {
        switch self {
        case .habit: "checkmark"
        case .anniversary: "heart.fill"
        case .alarm: "bell.fill"
        case .radio: "music.note"
        case .podcast: "waveform"
        case .bookmarks: "bookmark.fill"
        case .screenshots: "viewfinder"
        case .photos: "photo"
        case .basket: "leaf.fill"
        case .todo, .todoDone, .clipboard, .downloads, .fileShelf: nil
        }
    }

    /// 大面板里标题下面那行灰字：告诉用户下一步具体做什么。小卡不显示。
    public var hint: String? {
        switch self {
        case .habit: tr("先定一个小目标，比如早睡")
        case .anniversary: tr("生日、纪念日，到了提醒你")
        case .alarm: tr("小熊猫在打盹，帮它定个点")
        case .radio: tr("搜搜城市名或喜欢的频道")
        case .podcast: tr("粘贴 RSS 或按名字搜索")
        case .bookmarks: tr("常去的网页，一点就开")
        case .screenshots: tr("截的图会出现在这里")
        case .photos: tr("选个文件夹，轮流播放")
        case .basket: tr("喝杯水，第一片就来了")
        case .todo, .todoDone, .clipboard, .downloads, .fileShelf: nil
        }
    }

    /// 主题色按钮上的字用深色还是白色。按感知亮度（0.299R + 0.587G + 0.114B）
    /// 算，只有很亮的颜色（相册的黄、截图的青）才用深色字。
    public var usesDarkLabel: Bool {
        guard let theme else { return false }
        return Self.brightness(theme) > Self.darkLabelThreshold
    }

    /// 超过这个亮度，白字看不清，按钮换深色字。
    public static let darkLabelThreshold = 0.7

    /// 感知亮度，0...1。
    public static func brightness(_ color: ColorCode) -> Double {
        0.299 * color.red + 0.587 * color.green + 0.114 * color.blue
    }

    /// 小熊猫呼吸：一个来回的秒数和放大到的倍数。
    public static let breathPeriod: Double = 3
    public static let breathScale: Double = 1.03

    /// 呼吸到 `t` 秒时的缩放，1.0 到 `breathScale` 之间平滑来回。
    public static func breath(at t: Double) -> Double {
        guard t.isFinite else { return 1 }
        let phase = (1 - cos(2 * Double.pi * t / breathPeriod)) / 2
        return 1 + (breathScale - 1) * phase
    }

    /// 一句话。`compact` 是竖排货架的短说法。
    public func line(compact: Bool = false) -> String {
        switch self {
        case .todo: compact ? tr("无待办") : tr("没有待办，歇会儿")
        case .todoDone: compact ? tr("做完了") : tr("都做完了")
        case .clipboard: compact ? tr("空") : tr("还没拷贝过东西")
        case .downloads: compact ? tr("空") : tr("下载文件夹是空的")
        case .fileShelf: compact ? tr("拖入") : tr("把文件拖到这里")
        case .habit: compact ? tr("无习惯") : tr("还没有习惯")
        case .anniversary: compact ? tr("纪念日") : tr("记住一个好日子")
        case .alarm: compact ? tr("无闹钟") : tr("还没有闹钟")
        case .radio: compact ? tr("无电台") : tr("收藏一个电台吧")
        case .podcast: compact ? tr("无订阅") : tr("订阅一个节目吧")
        case .bookmarks: compact ? tr("无书签") : tr("收藏一个网址吧")
        case .screenshots: compact ? tr("无截图") : tr("还没有截图")
        case .photos: compact ? tr("无图片") : tr("选一册喜欢的照片")
        case .basket: compact ? tr("无竹叶") : tr("今天还没有竹叶")
        }
    }

    /// 允许的图，空状态只用这几张，测试里核对。
    public static let allowedImages: Set<String> = [
        "pet-panda-idle", "pet-panda-rest", "pet-panda-cheer",
        "pet-panda-eat", "pet-panda-hungry",
    ]
}
