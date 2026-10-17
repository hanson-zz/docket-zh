import Foundation

/// 码头 Pro 的锁：试用中或已激活（或老赞助者）才能添加、使用 Pro 小组件和 Pro 外观。
///
/// 哪些东西是 Pro 由 `ProFeatures` 决定，这里只决定没解锁时怎么办：
/// - 添加小组件面板里点 Pro 卡片：弹付费墙，不添加。
/// - 选 Pro 样式或外观：弹付费墙，不改。
/// - 已经在扩展栏上的 Pro 小组件：不删除，盖一层小锁遮罩，写“Pro 专属 · 解锁”。
/// - 原来的赞助者外观（表盘、角色、Wi-Fi、电池外观）照旧退回免费外观显示，不盖遮罩。
/// - 电池的液态外观也是 Pro，同样退回免费的经典外观显示，不盖遮罩。
/// - 天气的多城市和电池的百分比圆环没有同样大小的免费样式可退，盖小锁遮罩。
/// - 便签的 Pro 纸色退回默认的柠檬黄显示，不盖遮罩，便签照常能写。
/// - 颜色与背景里的自定义颜色和渐变背景退回默认颜色、无背景显示。
///
/// 快速开关的 Pro 工具、AI 刘海和充电上限这次只有标识，不在这里上锁。
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

    /// 同上，带上种类：天气的多城市、电池的百分比圆环、便签的 Pro 纸色也算。
    public static func canChoose(_ kind: WidgetKind, _ overrides: [String: WidgetConfig.Value], unlocked: Bool) -> Bool {
        unlocked || !ProFeatures.isProStyle(kind, overrides)
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
    /// 整种是 Pro 的小组件，和用了液态外观的小组件（电池除外）要盖；电池的液态
    /// 和原来的赞助者外观有免费外观可退，退回去照常显示，不盖。天气的多城市和
    /// 电池的百分比圆环要盖。便签的 Pro 纸色退回柠檬黄，不盖。预览（添加面板
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
        if instance.kind == .battery { return false }
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
}
