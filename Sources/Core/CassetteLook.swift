import Foundation

/// 「正在播放」的三档卡片：完整（264 宽）、迷你（64 宽）和中卡（404 宽，`layout` 为 medium）。
///
/// 没存 `layout` 的老卡片按完整读，`mini` 照旧优先。卡带外观（磁带、随身听、收录机）
/// 2026-10-23 起搬出正在播放，成了单独的 Pro 小组件「复古卡带」（`CassetteWidget`）；
/// 正在播放的中卡只画默认的封面样式，免费。原来存的 `cassette`、`cassetteCompact`
/// 由 `CassetteMigration` 在启动时迁走。
public enum MusicCard {
    public static let layoutKey = "layout"
    /// 完整（原来的宽卡片）。
    public static let wide = "wide"
    /// 中卡：404 宽的默认样式。
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

/// 正在播放以前的卡带外观，只剩迁移在读（`CassetteMigration`）。
///
/// 存在 `cassette` 键：默认（plain）和三种卡带。紧凑开关存在 `cassetteCompact`。
public enum CassetteLook: String, CaseIterable, Sendable {
    case plain, tape, portable, boombox

    public static let key = "cassette"
    /// 以前中卡上的「紧凑卡片（216 宽）」开关。
    public static let legacyCompactKey = "cassetteCompact"

    /// 存着的外观，认不出的值按默认读。
    public static func stored(_ config: WidgetConfig) -> CassetteLook {
        CassetteLook(rawValue: config.string(key, default: plain.rawValue)) ?? .plain
    }

    /// 对应的复古卡带机型；默认样式没有。
    public var model: CassetteModel? {
        switch self {
        case .plain: nil
        case .tape: .tape
        case .portable: .portable
        case .boombox: .boombox
        }
    }
}

/// 复古卡带的三种机型：磁带、随身听、收录机，都是 Pro（整种小组件是 Pro）。
public enum CassetteModel: String, CaseIterable, Sendable {
    /// 磁带：茶色半透明外壳，两个转轮，封面做标签贴纸。
    case tape
    /// 随身听：奶油色机身，小窗里的转轮，灰绿液晶。
    case portable
    /// 收录机：苔绿色横机身，左右喇叭网罩，中间调台条和磁带仓。
    case boombox

    public static let key = "model"
    public static let fallback: CassetteModel = .tape

    public var title: String {
        switch self {
        case .tape: tr("磁带")
        case .portable: tr("随身听")
        case .boombox: tr("收录机")
        }
    }

    /// 存着的机型，没存或认不出的按磁带读。
    public static func stored(_ config: WidgetConfig) -> CassetteModel {
        CassetteModel(rawValue: config.string(key, default: fallback.rawValue)) ?? fallback
    }
}

/// 「复古卡带」小组件（Pro）：播放数据和控制都走正在播放的同一套服务，这里只管
/// 卡片尺寸、机型、紧凑和面板上要显示的几样东西。
///
/// - 扩展栏横排是中卡 404×58（和 Codex 用量的中卡一样），三种机型都有。
/// - 紧凑（`compactKey`）收窄到 216 宽，只给磁带：随身听、收录机的机身和按键放不进
///   216×58，设置里只在磁带时列出（已经开着的换了机型也列，好关掉）；别的机型开着
///   紧凑也按 404 宽画机身。
/// - 扩展栏在左右两侧时是 76 宽的竖条：一盒精简磁带、歌名和播放键，不缩放机身。
/// - 机身是实物质感，颜色写死，不随浅深色变；底板、按键、文字跟着浅色 / 深色走。
public enum CassetteWidget {
    public static let modelKey = CassetteModel.key
    /// 紧凑卡片（216 宽，只有磁带）。
    public static let compactKey = "compact"
    public static let mediumWidth = 404.0
    public static let compactWidth = 216.0
    /// 库里和卡片上的高度（扩展栏里内容高一律 58）。
    public static let cardHeight = 104.0
    /// 竖排时的长度：小磁带、两行字、播放键。
    public static let columnHeight = 112.0

    /// 卡片真的按紧凑画：开了紧凑，机型是磁带。
    public static func isCompact(_ config: WidgetConfig) -> Bool {
        config.bool(compactKey) && CassetteModel.stored(config) == .tape
    }

    /// 设置里列不列「紧凑」：选了磁带才列；已经开着的（之后换了机型）也列，好关掉。
    public static func offersCompact(_ config: WidgetConfig) -> Bool {
        CassetteModel.stored(config) == .tape || config.bool(compactKey)
    }

    /// 横排卡片的宽度。
    public static func width(_ config: WidgetConfig) -> Double {
        isCompact(config) ? compactWidth : mediumWidth
    }

    // MARK: 面板

    /// 面板「接下来」收起时列几首（B 面 3 首）。
    public static let upNextRows = 3

    /// 「接下来」要列哪几首：收起时前 3 首，展开时全部。
    public static func upNextShown(count: Int, expanded: Bool) -> Int {
        max(0, expanded ? count : min(count, upNextRows))
    }

    /// 标题行右边的「B 面 · 3 首」：一首都没有时不写。
    public static func upNextSummary(count: Int) -> String? {
        count > 0 ? tr("B 面 · \(count) 首") : nil
    }

    /// 「查看全部」：多于收起时那几首才有。
    public static func offersShowAll(count: Int) -> Bool { count > upNextRows }

    /// 接下来第 `offset` 首（从 0 数）的曲序，两位数：当前是第 3 首时下一首写「04」。
    /// 不知道当前是第几首时从 01 数。
    public static func trackNumber(offset: Int, current: Int? = nil) -> String {
        let n = max(1, (current ?? 0) + offset + 1)
        return n < 10 ? "0\(n)" : "\(n)"
    }

    /// 带长计数器上的一格：两位分钟加两位秒「01:42」，一小时以上「1:02:03」。
    /// 读不到或负的按 0。
    public static func counter(_ seconds: Double) -> String {
        let total = seconds.isFinite ? max(0, Int(seconds.rounded())) : 0
        let h = total / 3600, m = (total / 60) % 60, s = total % 60
        func two(_ v: Int) -> String { v < 10 ? "0\(v)" : "\(v)" }
        return h > 0 ? "\(h):\(two(m)):\(two(s))" : "\(two(m)):\(two(s))"
    }

    /// 计数器整行：「01:42 · 04:05」；没有时长（直播、网页视频）只写已放的。
    public static func counterLine(elapsed: Double, duration: Double) -> String {
        guard duration.isFinite, duration > 0 else { return counter(elapsed) }
        return "\(counter(elapsed)) · \(counter(duration))"
    }

    /// 面板底部的机型分段点了一种：三种都是 Pro（整种是 Pro），没解锁时弹付费墙。
    public enum PickResult: Equatable, Sendable {
        case apply
        case unchanged
        case paywall
    }

    public static func pick(_ model: CassetteModel, current: CassetteModel, unlocked: Bool) -> PickResult {
        guard unlocked else { return .paywall }
        return model == current ? .unchanged : .apply
    }

    /// 换机型：紧凑只给磁带，换成别的机型时顺手关掉，免得卡片宽度忽变。
    public static func choosing(_ model: CassetteModel, in config: WidgetConfig) -> WidgetConfig {
        var copy = config
        copy.set(modelKey, .string(model.rawValue))
        if model != .tape { copy.set(compactKey, .bool(false)) }
        return copy
    }

    /// 和正在播放共用的键：来源、自动切换、固定来源、浏览器、上一首下一首按钮。
    /// 迁移时从正在播放的卡片原样带过来，`MusicService.configure` 读的就是这些。
    public static let sharedMusicKeys: [String] = [
        "spotify", "apple", "netease", "xiaoyuzhou", "qqmusic", "browsers",
        MusicSourceSwitch.autoKey, MusicSourceSwitch.pinnedKey, "previous", "next",
    ]
}

/// 卡带外观搬出正在播放时的一次性迁移（启动时、授权状态算好以后跑一遍）。
///
/// - 横排中卡上选了磁带、随身听或收录机的正在播放卡片：已解锁 Pro（含试用）时换成
///   复古卡带对应机型，同一个 id，位置不变；来源、自动切换、固定来源、上一首下一首
///   按钮、颜色、按条件显示这些设置照搬，紧凑开关只在磁带上带过去。
/// - 没解锁时留在正在播放，回到默认样式（`cassette` 和紧凑去掉），卡片不丢。
/// - 完整、迷你卡片上存着的卡带外观本来就没画出来，只把这两个键去掉。
/// - 跑过一遍以后再跑什么都不变（两个旧键都没了）。
public enum CassetteMigration {
    /// 只属于正在播放、搬到复古卡带时不带的键。
    static let musicOnlyKeys: [String] = [
        "mini", MusicCard.layoutKey, "backward", "forward", "skip",
        CassetteLook.key, CassetteLook.legacyCompactKey,
    ]

    /// 这张卡片要不要迁：正在播放上还存着卡带外观的两个键之一。
    public static func needsMigration(_ instance: WidgetInstance) -> Bool {
        instance.kind == .music
            && (instance.config.values[CassetteLook.key] != nil
                || instance.config.values[CassetteLook.legacyCompactKey] != nil)
    }

    /// 迁移一张卡片；不用迁的原样返回。
    public static func migrated(_ instance: WidgetInstance, unlocked: Bool) -> WidgetInstance {
        guard needsMigration(instance) else { return instance }
        let config = instance.config
        let look = CassetteLook.stored(config)
        if unlocked, MusicCard.isMedium(config), let model = look.model {
            var values = config.values
            for key in musicOnlyKeys { values.removeValue(forKey: key) }
            values[CassetteWidget.modelKey] = .string(model.rawValue)
            values[CassetteWidget.compactKey] = .bool(model == .tape && config.bool(CassetteLook.legacyCompactKey))
            return WidgetInstance(id: instance.id, kind: .cassette, expanded: true, config: WidgetConfig(values))
        }
        var copy = instance
        copy.config.set(CassetteLook.key, nil)
        copy.config.set(CassetteLook.legacyCompactKey, nil)
        return copy
    }

    /// 迁移一串扩展栏项目（文件夹里的也算）；什么都没变时是 nil，不用写回。
    public static func migrated(_ items: [DockItem], unlocked: Bool) -> [DockItem]? {
        var changed = false
        let result = items.map { item -> DockItem in
            switch item {
            case .widget(let widget) where needsMigration(widget):
                changed = true
                return .widget(migrated(widget, unlocked: unlocked))
            case .group(var group):
                if let inner = migrated(group.items, unlocked: unlocked) {
                    changed = true
                    group.items = inner
                    return .group(group)
                }
                return item
            default:
                return item
            }
        }
        return changed ? result : nil
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
