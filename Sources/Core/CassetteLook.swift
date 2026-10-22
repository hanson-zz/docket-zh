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
/// - 中卡可以开「紧凑」（`compactKey`）：卡片收窄到 216 宽，只画一盒精简磁带加歌名歌手。
///   紧凑开着时随身听、收录机也画成磁带（216×58 放不下机身和按键）；没解锁时退回
///   默认样式，按 216 宽排。卡片宽度只看 `layout` 和紧凑，不看外观和解锁，
///   在面板里换外观不会让卡片忽宽忽窄。
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

    /// 中卡的「紧凑」开关：216 宽的小磁带卡。
    public static let compactKey = "cassetteCompact"
    /// 紧凑卡片的宽度（效果图小卡 216×104，扩展栏里内容高 58）。
    public static let compactWidth = 216.0

    /// 紧凑：中卡上开了紧凑开关。
    public static func isCompact(_ config: WidgetConfig) -> Bool {
        isMedium(config) && config.bool(compactKey)
    }

    /// 设置里列不列「紧凑」：中卡选了磁带时列出；已经开着的（之后换了外观）也列，
    /// 好让人关掉。
    public static func offersCompact(_ config: WidgetConfig) -> Bool {
        guard isMedium(config) else { return false }
        return CassetteLook.stored(config) == .tape || config.bool(compactKey)
    }

    /// 面板底部的外观选择条：只在横排扩展栏的中卡（含紧凑）上有，别的卡片不画卡带，
    /// 选了也看不到，干脆不显示。
    public static func showsLookPicker(_ config: WidgetConfig, vertical: Bool, preview: Bool) -> Bool {
        isMedium(config) && !vertical && !preview
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
    /// 紧凑卡片放不下随身听和收录机的机身，这两种画成磁带。
    public static func shown(config: WidgetConfig, unlocked: Bool, vertical: Bool) -> CassetteLook {
        guard MusicCard.isMedium(config), !vertical else { return .plain }
        let look = stored(config)
        if look.isPro, !unlocked { return .plain }
        if MusicCard.isCompact(config), look != .plain { return .tape }
        return look
    }

    /// 面板外观条上点了一种：直接换，或者先弹付费墙（Pro 外观、没解锁）。
    public enum PickResult: Equatable, Sendable {
        case apply
        case paywall
    }

    public static func pick(_ look: CassetteLook, unlocked: Bool) -> PickResult {
        look.isPro && !unlocked ? .paywall : .apply
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
    /// 换档只在一首歌里发生几次；换档时角度从当前位置接着转，见 `Spin`。
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

    /// 一个转轮的累计角度。转速换档时从当前角度接着转，不会因为 `t × 新转速`
    /// 和 `t × 旧转速` 差出一截而跳一下；暂停时停在原地，再播放从停下的角度接着走。
    public struct Spin: Equatable, Sendable {
        /// 上次换档（或开始）时的角度，0..<360。
        public private(set) var baseAngle: Double
        /// 上次换档（或开始）的时刻；暂停时是 nil。
        public private(set) var baseTime: Double?
        public private(set) var rate: Double = 0

        public init(phase: Double = 0) {
            baseAngle = Spin.wrap(phase)
        }

        /// 时刻 `t` 的角度，转速是 `degreesPerSecond`。转速变了就把当前角度记成新起点。
        public mutating func angle(at t: Double, degreesPerSecond dps: Double) -> Double {
            guard t.isFinite, dps.isFinite else { return baseAngle }
            guard let start = baseTime, t >= start else {
                // 刚开始、刚从暂停回来，或时钟往回拨了：从现在的角度起算。
                baseTime = t
                rate = dps
                return baseAngle
            }
            let now = Spin.wrap(baseAngle + (t - start) * rate)
            if dps != rate || t - start > 3600 {
                baseAngle = now
                baseTime = t
                rate = dps
            }
            return now
        }

        /// 停住：角度留在 `t` 时的位置，下次 `angle` 从这里接着转。
        public mutating func pause(at t: Double) {
            if let start = baseTime, t.isFinite, t >= start {
                baseAngle = Spin.wrap(baseAngle + (t - start) * rate)
            }
            baseTime = nil
        }

        /// 现在停着的角度（暂停时画这个）。
        public var restingAngle: Double { baseAngle }

        static func wrap(_ degrees: Double) -> Double {
            guard degrees.isFinite else { return 0 }
            let a = degrees.truncatingRemainder(dividingBy: 360)
            return a < 0 ? a + 360 : a
        }
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
