import Foundation

/// 喝水的三种样式各管一件事，看起来不再都是“水往上涨”：
///
/// - 圆环（免费）：干净的进度环加数字，新放的喝水默认用它。
/// - 角色（Pro）：主角是选的角色（默认小熊猫），按今天的进度换姿势，
///   下面八节竹子是进度；不再画杯子涨水。见 `WaterPose`。
/// - 液态（Pro）：整张卡片是一杯水，水体更浓、有气泡，点 + 时水面晃一下
///   溅几颗水珠，满了顶上一道高光。没有角色。
///
/// 存法不变：仍存在 `layout` 键下（ring、character、liquid）。没存 `layout`
/// 的老卡片按角色读（老用户原来就是角色），只有新放的写 ring。没解锁时角色
/// 和液态都画成圆环、不盖锁，配置不改写，解锁或试用时自动回来（见
/// `ProLicenseGate.waterLayout`）。
public enum WaterLayout: String, CaseIterable, Sendable {
    case ring
    case character
    case liquid

    /// 存样式的键。
    public static let key = "layout"
    /// 新放的喝水写进去的样式。
    public static let newWidget: WaterLayout = .ring
    /// 没存 `layout` 的老卡片按这个读，和目录默认值一致。
    public static let legacyDefault: WaterLayout = .character

    /// 配置里存的原始值，没存时是老卡片的角色。
    public static func raw(_ config: WidgetConfig) -> String {
        config.string(key, default: legacyDefault.rawValue)
    }

    /// 配置里存的样式。认不出的值按角色读，和原来“不是圆环也不是液态就画
    /// 角色”的画法一样。
    public static func stored(_ config: WidgetConfig) -> WaterLayout {
        WaterLayout(rawValue: raw(config)) ?? .character
    }

    /// 角色和液态是 Pro，圆环免费。
    public var isPro: Bool { self != .ring }
}

/// 角色样式里角色的姿势，按今天的进度分档：
///
/// - 0 到 30%：口渴（`pet-*-hungry`），“还渴着”；
/// - 30 到 70%：小口喝着（小熊猫抱竹筒小口喝 `pet-panda-sip`，其他角色
///   `water-*-drink`）；
/// - 70% 到没达标：快喝饱了（`pet-panda-idle` / `water-*-idle`）；
/// - 达标：欢呼（`pet-panda-cheer` / `water-*-cheer`），小熊猫多几条小彩带。
///
/// 另外两种状态盖过分档：提醒时段里 2 小时没喝时“渴了”（口渴图降饱和，
/// 头上一个“渴了”气泡，下面写“2 小时没喝了”）；5 小时没喝照旧渴成骷髅（见 `WaterParched`）。卡片上点 +
/// 时播一帧“竹筒举到嘴边喝一口”（小熊猫 `pet-panda-drink`，其他角色
/// `water-*-drink`）约 0.8 秒，打开“减少动态效果”时不播。
public enum WaterPose {

    public enum Stage: String, CaseIterable, Sendable {
        case thirsty
        case sipping
        case nearlyFull
        case done

        /// 卡片上角色旁边那句话。
        public var caption: String {
            switch self {
            case .thirsty: tr("还渴着")
            case .sipping: tr("小口喝着")
            case .nearlyFull: tr("快喝饱了")
            case .done: tr("达标啦")
            }
        }
    }

    /// 分档的两条线：30% 和 70%。
    public static let sippingFrom = 0.3
    public static let nearlyFullFrom = 0.7

    /// 今天的进度落在哪一档。达标（喝到目标）才算 done，差一口还是快喝饱了。
    public static func stage(total: Int, goal: Int) -> Stage {
        guard goal > 0 else { return .thirsty }
        if total >= goal { return .done }
        let share = WaterIntake.progress(total: total, goal: goal)
        if share >= nearlyFullFrom { return .nearlyFull }
        if share >= sippingFrom { return .sipping }
        return .thirsty
    }

    /// 提醒时段里这么久没喝就“渴了”。比打瞌睡的 3 小时、渴成骷髅的 5 小时都早。
    public static let dryAfter: TimeInterval = 2 * 3600

    /// “渴了”时已经几个整小时没喝，不渴时为 nil。只在提醒时段里、今天还没
    /// 达标时才会渴：时段外不催。时段开始前喝的不算，和 `WaterParched` 一样
    /// 从时段开始算起。
    public static func dryHours(now: Date, lastDrink: Date?, total: Int, goal: Int,
                                window: WaterReminder, calendar: Calendar = WaterIntake.calendar) -> Int? {
        guard goal > 0, total < goal, window.isActive(now, calendar: calendar) else { return nil }
        let opened = window.window(calendar.startOfDay(for: now)).start
        let since = max(lastDrink ?? opened, opened)
        let gap = now.timeIntervalSince(since)
        guard gap >= dryAfter else { return nil }
        return Int(gap / 3600)
    }

    public static func dryHours(_ config: WidgetConfig, now: Date, calendar: Calendar = WaterIntake.calendar) -> Int? {
        let days = WaterIntake.days(config)
        let today = WaterIntake.today(days, goal: WaterIntake.goal(config, now: now, calendar: calendar),
                                      now: now, calendar: calendar)
        return dryHours(now: now, lastDrink: WaterIntake.lastDrink(days, calendar: calendar),
                        total: today.total, goal: today.goal, window: WaterReminder(config: config),
                        calendar: calendar)
    }

    /// 卡片这一刻画什么。
    public enum Look: Equatable, Sendable {
        /// 按进度分档的姿势。
        case stage(Stage)
        /// 2 小时以上没喝（带整小时数）：口渴图降饱和，带“渴了”气泡。
        case dry(hours: Int)
        /// 5 小时没喝：骷髅。
        case parched
        /// 刚点了 +：举起竹筒喝一口的那一帧。
        case gulp
    }

    /// 优先级：喝一口那一帧 > 达标 > 骷髅 > 渴了 > 分档。达标时不会是骷髅
    /// 或渴了（两者都要求没达标），这里再保险一次。
    public static func look(stage: Stage, dryHours: Int?, parched: Bool, gulping: Bool) -> Look {
        if gulping { return .gulp }
        if stage == .done { return .stage(.done) }
        if parched { return .parched }
        if let dryHours { return .dry(hours: dryHours) }
        return .stage(stage)
    }

    /// 这一刻的图（不带扩展名）。
    public static func imageName(_ character: WaterCharacter, _ look: Look) -> String {
        let id = character.rawValue
        let panda = character == .redPanda
        switch look {
        case .parched:
            return WaterParched.imageName(character)
        case .gulp:
            return panda ? "pet-panda-drink" : "water-\(id)-drink"
        case .dry, .stage(.thirsty):
            return "pet-\(id)-hungry"
        case .stage(.sipping):
            return panda ? "pet-panda-sip" : "water-\(id)-drink"
        case .stage(.nearlyFull):
            return panda ? "pet-panda-idle" : "water-\(id)-idle"
        case .stage(.done):
            return panda ? "pet-panda-cheer" : "water-\(id)-cheer"
        }
    }

    /// 这一刻角色旁边那句话。
    public static func caption(_ look: Look, stage: Stage) -> String {
        switch look {
        case .parched: tr("渴成骷髅了")
        case .dry(let hours): tr("\(max(1, hours)) 小时没喝了")
        case .gulp: stage.caption
        case .stage(let shown): shown.caption
        }
    }

    /// “渴了”时角色头上的气泡。
    public static let dryBubble = tr("渴了")

    /// 点 + 后那一帧举多久。
    public static let gulpSeconds: TimeInterval = 0.8

    /// 一排几节竹子，和原来的八个小杯一样按 `WaterPetCards.filledCups` 算亮几节。
    public static let bambooSlots = WaterPetCards.cupSlots
}
