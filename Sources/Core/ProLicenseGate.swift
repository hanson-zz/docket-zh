import Foundation

/// 码头 Pro 的锁：试用中或已激活（或老赞助者）才能添加、使用 Pro 小组件和 Pro 外观。
///
/// 哪些东西是 Pro 由 `ProFeatures` 决定，这里只决定没解锁时怎么办：
/// - 添加小组件面板里点 Pro 卡片：弹付费墙，不添加。
/// - 选 Pro 样式或外观：弹付费墙，不改。
/// - 已经在扩展栏上的 Pro 小组件：不删除，盖一层小锁遮罩，写“Pro 专属 · 解锁”。
/// - 原来的赞助者外观（表盘、角色、Wi-Fi、电池外观）照旧退回免费外观显示，不盖遮罩。
/// - 电池的液态外观也是 Pro，同样退回免费的经典外观显示，不盖遮罩。
/// - 天气的多城市和电池格没有同样大小的免费样式可退，盖小锁遮罩。
/// - 天气面板的城市列表免费 1 个：没解锁时加第 2 个弹付费墙；已经加了的不删，
///   带 Pro 标，面板只显示第 1 个，解锁或试用时自动回来。
/// - 时间进度整种免费，液态和四格是 Pro，没解锁时退回圆环显示，不盖遮罩。
/// - 喝水整种免费，角色和液态是 Pro，没解锁时都画成圆环，不盖遮罩；配置照旧
///   存着角色或液态，解锁或试用时自动回来。例外：卡片选的是累计达标解锁的
///   柴犬或橘猫时，角色样式照常显示，也不标 Pro。
/// - 收音机整种免费，三款复古皮肤（木壳电子管、晶体管便携、数码卡座）和五款新外观
///   （烟晶、灯阵、瓷白圆盘、掌机像素、墨白直尺）是 Pro，
///   没解锁时画回经典的半圆表盘，不盖遮罩；配置照旧存着皮肤，解锁或试用时自动回来。
/// - 习惯打卡整种免费，免费 3 个习惯：没解锁时加不了第 4 个（弹付费墙），已有
///   超过 3 个的不删数据，超出的只读带小锁；近七天报告是 Pro。
/// - 书签整种免费，分组文件夹是 Pro：没解锁时面板只显示“全部”，“＋”和“移到分组”
///   弹付费墙；分组照旧存着，不改写，解锁或试用时自动回来。
/// - 便签的 Pro 纸色退回默认的柠檬黄显示，不盖遮罩，便签照常能写。
/// - 颜色与背景里的自定义颜色和渐变背景退回默认颜色、无背景显示。
/// - 快速开关的 Pro 工具：设置里照样列出并带 Pro 标识，勾选时弹付费墙；已经勾上的
///   在卡片上画成带小锁的样子，点按弹付费墙，不执行。正开着的（演示模式、只锁
///   键盘、低电量模式）还能点一下关掉，免得到期后关不回去。
/// - AI 刘海对话：点刘海入口、按快捷键、设置里打开开关都弹付费墙，不展开对话。
///   AI 卡片跳转到网页或 App 照旧免费。
/// - 系统活动的超阈值提醒：规则照样列出，开关和“添加规则”弹付费墙；不判断、
///   不发通知、卡片不变红，规则不改写，解锁后恢复。
/// - 充电上限：开关和安装助手弹付费墙；已打开的不再生效（写给助手的设置里关掉，
///   电池照常充电），用户的选择另外记着，解锁后恢复。
public enum ProLicenseGate {

    /// 遮罩上的字。
    public static let lockTitle = tr("Pro 专属 · 解锁")

    /// Pro 是否已解锁：试用中、已激活，或这台 Mac 以前按过“我已赞助”。
    /// 老赞助用户不会因为改成收费而被锁。
    public static func isUnlocked(_ state: ProLicenseState, supporter: Bool) -> Bool {
        state.isUnlocked || supporter
    }

    /// 能不能从添加小组件面板添加这张卡片（种类加样式）。
    public static func canAdd(_ kind: WidgetKind, overrides: [String: WidgetConfig.Value], unlocked: Bool) -> Bool {
        unlocked || !ProFeatures.isPro(kind, overrides: overrides)
    }

    /// 能不能选这组样式覆盖（样式菜单的一项，或一个选项的一个值）。
    public static func canChoose(_ overrides: [String: WidgetConfig.Value], unlocked: Bool) -> Bool {
        unlocked || !ProFeatures.isProStyle(overrides)
    }

    /// 同上，带上种类：天气的多城市、电池格、便签的 Pro 纸色也算。
    public static func canChoose(_ kind: WidgetKind, _ overrides: [String: WidgetConfig.Value], unlocked: Bool) -> Bool {
        unlocked || !ProFeatures.isProStyle(kind, overrides)
    }

    /// 同上，再带上卡片现在的配置：喝水选的是已经达标解锁的柴犬或橘猫时，
    /// 角色样式免费能选。
    public static func canChoose(_ kind: WidgetKind, _ overrides: [String: WidgetConfig.Value],
                                 config: WidgetConfig, unlocked: Bool) -> Bool {
        unlocked || !ProFeatures.isProStyle(kind, overrides, config: config)
    }

    /// 颜色与背景里能不能选这个颜色（自定义颜色是 Pro）。
    public static func canChooseTint(_ choice: WidgetTint.Choice, unlocked: Bool) -> Bool {
        unlocked || !WidgetTint.isProChoice(choice)
    }

    /// 颜色与背景里能不能选这个背景（渐变是 Pro）。
    public static func canChooseBackground(_ background: WidgetTint.Background, unlocked: Bool) -> Bool {
        unlocked || !WidgetTint.isProBackground(background)
    }

    /// 已在扩展栏上的这个小组件要不要盖小锁遮罩。
    ///
    /// 整种是 Pro 的小组件，和用了液态外观的小组件（电池、时间进度、喝水除外）
    /// 要盖；这三种的液态和原来的赞助者外观有免费外观可退，退回去照常显示，不盖。天气的多城市和
    /// 电池格要盖。便签的 Pro 纸色退回柠檬黄，不盖。预览（添加面板
    /// 的缩略图）从不盖。
    public static func needsLockOverlay(_ instance: WidgetInstance, unlocked: Bool, isPreview: Bool = false) -> Bool {
        guard !unlocked, !isPreview else { return false }
        if ProFeatures.isProKind(instance.kind) { return true }
        let values = instance.config.values
        switch instance.kind {
        case .weather, .battery:
            if ProFeatures.isKindProStyle(instance.kind, values) { return true }
        default:
            break
        }
        // 电池、时间进度和喝水的 Pro 外观有免费外观可退，不盖。
        if instance.kind == .battery || instance.kind == .progress || instance.kind == .water { return false }
        return ProFeatures.isLiquid(values)
    }

    /// 便签实际画的纸色：没解锁时 Pro 纸色退回默认的柠檬黄。
    public static func noteColor(config: WidgetConfig, unlocked: Bool) -> PaperColor {
        let raw = config.string(ProFeatures.noteColorKey, default: PaperColor.yellow.rawValue)
        let color = PaperColor(rawValue: raw) ?? .yellow
        if !unlocked, ProFeatures.isProNoteColor(color.rawValue) { return .yellow }
        return color
    }

    /// 电池卡实际画哪种外观：没解锁时液态和赞助者外观都退回经典。
    public static func batteryLook(config: WidgetConfig, unlocked: Bool) -> BatteryLook {
        let look = BatteryLook.shown(config: config, unlocked: unlocked)
        if look == .liquid, !unlocked { return .classic }
        return look
    }

    /// 时间进度卡片实际画哪种外观：没解锁时液态和四格退回圆环。
    public static func timeProgressLayout(config: WidgetConfig, unlocked: Bool) -> String {
        let layout = TimeProgress.layout(config)
        guard !unlocked, layout == LiquidMotion.layout || layout == TimeProgress.quadLayout else { return layout }
        return TimeProgress.newWidgetLayout
    }

    /// 喝水卡片实际画哪种样式：没解锁时角色和液态都退回圆环。老卡片没存
    /// `layout` 时按角色读，所以没解锁时同样画圆环。
    public static func waterLayout(config: WidgetConfig, unlocked: Bool) -> WaterLayout {
        waterLayout(config: config, unlocked: unlocked, earnedCharacter: false)
    }

    /// 同上，`earnedCharacter` 为卡片选的是已经累计达标解锁的柴犬或橘猫（见
    /// `ProFeatures.waterCharacterEarned`）：这时没解锁 Pro 也照常画角色样式。
    /// 选小熊猫或 Pro 角色、或还没达标解锁时仍退回圆环；液态照旧是 Pro。
    public static func waterLayout(config: WidgetConfig, unlocked: Bool, earnedCharacter: Bool) -> WaterLayout {
        let layout = WaterLayout.stored(config)
        guard !unlocked, layout.isPro else { return layout }
        if layout == .character, earnedCharacter { return .character }
        return .ring
    }

    /// 收音机实际画哪种皮肤：没解锁时 8 款 Pro 外观都画回经典。没存 `skin` 的
    /// 旧卡片就是经典。
    public static func radioSkin(config: WidgetConfig, unlocked: Bool) -> RadioSkin {
        let skin = RadioSkin.stored(config)
        guard !unlocked, skin.isPro else { return skin }
        return .classic
    }

    // MARK: 习惯打卡

    /// 这张卡片最多能有几个习惯：没解锁时 3 个，解锁后 `HabitTracker.maxHabits` 个。
    public static func habitLimit(unlocked: Bool) -> Int {
        unlocked ? HabitTracker.maxHabits : min(ProFeatures.freeHabitLimit, HabitTracker.maxHabits)
    }

    /// 现在有 `count` 个习惯时还能不能新建。不能时（没解锁且满 3 个）点“新建”弹付费墙。
    public static func canAddHabit(count: Int, unlocked: Bool) -> Bool {
        count < habitLimit(unlocked: unlocked)
    }

    /// 排在第 `index` 个（从 0 数）的习惯是不是锁着：没解锁时第 4 个起只读。
    public static func isHabitLocked(at index: Int, unlocked: Bool) -> Bool {
        !unlocked && index >= ProFeatures.freeHabitLimit
    }

    /// 这个习惯是不是锁着（按它在列表里的位置）。
    public static func isHabitLocked(_ id: String, in habits: [Habit], unlocked: Bool) -> Bool {
        guard let index = habits.firstIndex(where: { $0.id == id }) else { return false }
        return isHabitLocked(at: index, unlocked: unlocked)
    }

    /// 习惯面板的近七天报告是不是能看。
    public static func canSeeHabitReport(unlocked: Bool) -> Bool { unlocked }

    /// 习惯列表的一次改动在没解锁时能不能生效，不能就原样退回改动前的列表。
    ///
    /// - 新加习惯：改完超过 3 个就不行。
    /// - 锁着的习惯（第 4 个起）：内容不能变（打卡、补卡、改名、改目标都不行），
    ///   也不能挪进前 3 个；前面的习惯删掉后它自然顶上来是可以的。
    /// - 删除任何一个都可以，数据是用户自己的。
    public static func allowedHabitEdit(before: [Habit], after: [Habit], unlocked: Bool) -> [Habit] {
        guard !unlocked else { return after }
        let limit = ProFeatures.freeHabitLimit
        let beforeIDs = before.map(\.id)
        let added = after.contains { !beforeIDs.contains($0.id) }
        if added, after.count > limit { return before }
        let locked = Set(beforeIDs.dropFirst(limit))
        for (index, habit) in after.enumerated() where locked.contains(habit.id) {
            guard let old = before.first(where: { $0.id == habit.id }), old == habit else { return before }
            if index < limit, after.count >= before.count { return before }
        }
        return after
    }

    // MARK: 书签分组

    /// 书签面板能不能用分组（顶部分组标签、新建分组、移到分组）。
    public static func canUseBookmarkGroups(unlocked: Bool) -> Bool { unlocked }

    // MARK: 天气城市

    /// 天气面板最多能切换几个城市：没解锁时 1 个，解锁后列表上限个。
    public static func weatherCityLimit(unlocked: Bool) -> Int {
        unlocked ? WeatherPlaces.maxCount : ProFeatures.freeWeatherCityLimit
    }

    /// 现在有 `count` 个城市时能不能再加。不能时（没解锁且已有 1 个）点“添加”弹付费墙。
    public static func canAddWeatherCity(count: Int, unlocked: Bool) -> Bool {
        count < weatherCityLimit(unlocked: unlocked)
    }

    /// 排在第 `index` 个（从 0 数）的城市是不是锁着：没解锁时第 2 个起带 Pro 标，
    /// 不删、不改写配置，只是面板上不能切过去。
    public static func isWeatherCityLocked(at index: Int, unlocked: Bool) -> Bool {
        !unlocked && index >= ProFeatures.freeWeatherCityLimit
    }

    // MARK: 快速开关

    /// 这个快速开关工具现在是不是锁着：没解锁且是 Pro 工具。
    public static func isToolLocked(_ tool: QuickToggle, unlocked: Bool) -> Bool {
        !unlocked && ProFeatures.proTools.contains(tool)
    }

    /// 卡片上点这个工具能不能执行。锁着的不执行，弹付费墙；但已经开着的
    /// （试用中打开的演示模式之类）总能点一下关掉。
    public static func canUseTool(_ tool: QuickToggle, isOn: Bool, unlocked: Bool) -> Bool {
        !isToolLocked(tool, unlocked: unlocked) || (tool.hasState && isOn)
    }

    /// 设置里多选列表能不能勾上这一项。取消勾选总是可以。
    public static func canEnableListChoice(key: String, value: String, unlocked: Bool) -> Bool {
        unlocked || !ProFeatures.isProListChoice(key: key, value: value)
    }

    // MARK: 系统活动的超阈值提醒

    /// 系统活动的超阈值提醒在不在判断：没解锁时不提醒、卡片不变红，规则照旧
    /// 存着，解锁或试用后自动恢复。面板里规则照样列出，开关和“添加规则”弹付费墙。
    public static func systemAlertsActive(unlocked: Bool) -> Bool { unlocked }

    // MARK: AI 刘海对话和充电上限

    /// 不属于某个小组件的 Pro 设置能不能用（刘海对话、充电上限）。
    public static func canUse(_ setting: ProFeatures.Setting, unlocked: Bool) -> Bool {
        unlocked
    }

    /// 能不能展开刘海对话（点刘海入口、快捷键、AI 卡片的小熊猫）。
    public static func canOpenAINotch(unlocked: Bool) -> Bool {
        canUse(.aiNotch, unlocked: unlocked)
    }

    /// 写给充电助手的设置：没解锁时关掉，让助手恢复正常充电；上限和缓冲照旧
    /// 保留。用户自己的开关另外记着，解锁后再写回去就恢复生效。
    public static func chargeLimitConfig(_ config: ChargeLimitConfig, unlocked: Bool) -> ChargeLimitConfig {
        var effective = config.clamped
        effective.enabled = config.enabled && canUse(.chargeLimit, unlocked: unlocked)
        return effective
    }
}
