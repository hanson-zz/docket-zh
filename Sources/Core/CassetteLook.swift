import Foundation

/// 「正在播放」的中卡和三种卡带外观（磁带 / 随身听 / 收录机）。
///
/// - 卡片三档：完整（264 宽）、迷你（64 宽）和中卡（404 宽，`layout` 为 medium）。
///   没存 `layout` 的老卡片按完整读，`mini` 照旧优先。
/// - 外观存在 `cassette` 键：默认（plain，免费）和三种卡带（Pro）。卡带只画在
///   中卡上；完整、迷你和扩展栏在左右两侧（竖排）时一律画默认样式。
/// - 没解锁 Pro 时卡带退回默认样式显示，不盖锁、不改写配置，解锁或试用时自动回来
///   （和收音机皮肤一样，见 `ProLicenseGate.musicCassette`）。
/// - 机身是实物质感，颜色不随浅深色变；只印小熊猫小标或「DOCKLING」，不出现品牌名。
public enum MusicCard {
    public static let layoutKey = "layout"
    /// 完整（原来的宽卡片）。
    public static let wide = "wide"
    /// 中卡，卡带外观只在这一档显示。
    public static let medium = "medium"

    /// 中卡之前存的卡片：存过 `mini` 却没有 `layout` 的，补上完整，好让样式菜单认出来。
    /// 什么都没存的空配置不补。
    public static func legacyResolved(_ config: WidgetConfig) -> WidgetConfig {
        guard config.values[layoutKey] == nil, config.values["mini"] != nil else { return config }
        var copy = config
        copy.set(layoutKey, .string(wide))
        return copy
    }

    /// 中卡：不是迷你，且 `layout` 为 medium。
    public static func isMedium(_ config: WidgetConfig) -> Bool {
        !config.bool("mini") && config.string(layoutKey, default: wide) == medium
    }
}

public enum CassetteLook: String, CaseIterable, Sendable {
    /// 默认：原来的封面卡片，免费。
    case plain
    /// 磁带：茶色半透明外壳，两个转轮，封面做标签贴纸。
    case tape
    /// 随身听：奶油色机身，小窗里的转轮，实体按键。
    case portable
    /// 收录机：苔绿色横机身，左右喇叭网罩，中间磁带仓。
    case boombox

    public static let key = "cassette"
    public static let fallback: CassetteLook = .plain

    public var title: String {
        switch self {
        case .plain: tr("默认")
        case .tape: tr("磁带")
        case .portable: tr("随身听")
        case .boombox: tr("收录机")
        }
    }

    /// 三种卡带都是 Pro，默认免费。
    public var isPro: Bool { self != .plain }

    /// 存着的外观，认不出的值按默认读。
    public static func stored(_ config: WidgetConfig) -> CassetteLook {
        CassetteLook(rawValue: config.string(key, default: fallback.rawValue)) ?? fallback
    }

    /// 卡片上实际画哪种：只有横排的中卡画卡带；没解锁时 Pro 外观退回默认。
    public static func shown(config: WidgetConfig, unlocked: Bool, vertical: Bool) -> CassetteLook {
        guard MusicCard.isMedium(config), !vertical else { return .plain }
        let look = stored(config)
        if look.isPro, !unlocked { return .plain }
        return look
    }
}

/// 卡带的转轮怎么动：磁带量随进度从左轮走到右轮，转速跟着卷径变，
/// 收录机的纸盆轻轻胀缩。纯函数，测试可以拨到任意进度和时刻。
public enum CassetteMotion {
    /// 转轮的帧率：只在播放、卡片看得见并且没开减少动态效果时转。
    public static let fps = 24.0

    public static func framesPerSecond(playing: Bool, visible: Bool, reduceMotion: Bool) -> Double? {
        playing && visible && !reduceMotion ? fps : nil
    }

    /// 一卷带盘的半径。左轮（供带）随进度变少，右轮（收带）变多，按面积换算，
    /// 进度 0 时左满右空，进度 1 时左空右满；进度越界按 0...1 夹住。
    public static func packRadius(min rMin: Double, max rMax: Double, progress: Double, left: Bool) -> Double {
        let p = progress.isFinite ? Swift.min(Swift.max(progress, 0), 1) : 0
        let fill = left ? 1 - p : p
        let lo = Swift.max(0, Swift.min(rMin, rMax)), hi = Swift.max(rMin, rMax)
        return (lo * lo + (hi * hi - lo * lo) * fill).squareRoot()
    }

    /// 带速一定，卷得越粗转得越慢。`fraction` 是卷径占满卷的比例，按六档取值，
    /// 换档只在一首歌里发生几次（轮辐六重对称，换档时看不出跳）。
    /// 满卷约 1/3 圈每秒，最细（只剩轮毂）约 1 圈每秒。
    public static func degreesPerSecond(fraction: Double) -> Double {
        let f = fraction.isFinite ? Swift.min(Swift.max(fraction, 0.3), 1) : 1
        let step = (f * 6).rounded() / 6
        return 120 / Swift.max(step, 0.3)
    }

    /// 转轮在时刻 `t`（秒）的角度，0..<360。时间先按一小时取余，免得大数乘出来丢精度。
    public static func angle(t: Double, degreesPerSecond: Double) -> Double {
        guard t.isFinite, degreesPerSecond.isFinite else { return 0 }
        let local = t.truncatingRemainder(dividingBy: 3600)
        let a = (local * degreesPerSecond).truncatingRemainder(dividingBy: 360)
        return a < 0 ? a + 360 : a
    }

    /// 收录机纸盆的缩放：播放时在 1 到 1+`depth` 之间轻轻胀缩（两个频率叠在一起，
    /// 不读真实音量）；暂停或静止时是 1。
    public static let coneDepth = 0.06

    public static func coneScale(t: Double, animating: Bool) -> Double {
        guard animating, t.isFinite else { return 1 }
        let local = t.truncatingRemainder(dividingBy: 3600)
        let a = sin(local * 2 * .pi * 1.7)
        let b = sin(local * 2 * .pi * 0.6 + 1.3)
        let beat = 0.5 + 0.35 * a + 0.15 * b
        return 1 + coneDepth * Swift.min(Swift.max(beat, 0), 1)
    }
}
