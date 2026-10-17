import Foundation

/// 码头 Pro 专属的范围：哪些小组件整种是 Pro，哪些样式、外观、工具和设置是 Pro。
///
/// 现在只用来在界面上统一标“Pro”，不加新的锁：原来的赞助者解锁
/// （`Supporter.isUnlocked`）照旧管原来那几样外观，其余只是标识。以后有了
/// 激活码，判断哪些东西要解锁也从这里读。
///
/// 清单按用户定的来：
/// - 原来的赞助者专属样式：时钟的霓虹、实景、简约、极简表盘，喝水和电子宠物
///   除小熊猫外的角色，网络活动的数字、点状、细线 Wi-Fi，电池的像素电池、
///   能量粒子、小熊猫抱电池。
/// - 整种是 Pro 的小组件，见 `proKinds`。
/// - 快速开关里的截图识字、二维码、演示模式、只锁键盘、低电量模式。
/// - 所有小组件的“液态”外观（`layout` 或 `look` 为 liquid）。
/// - AI 刘海对话的设置和电池面板里的充电上限。
public enum ProFeatures {

    /// 胶囊上的字。
    public static let badgeTitle = "Pro"
    /// 文字里的说法，替换原来的“赞助者专属”。
    public static let label = tr("Pro 专属")
    /// 鼠标停在 Pro 标识上时的提示。
    public static let help = tr("码头 Pro 专属，正式版推出后需要激活码解锁。")

    /// 整种都是 Pro 的小组件：摸鱼时钟、时间进度、环境音、播客、废纸篓、
    /// GitHub、应用切换器、Codex 用量、小熊猫的竹篮、电子宠物。
    public static let proKinds: Set<WidgetKind> = [
        .slacker, .progress, .ambient, .podcast, .trash,
        .github, .appSwitcher, .aiUsage, .perfectDay, .pet,
    ]

    /// 原来的赞助者专属表盘（时钟的 layout）。
    public static let proClockLayouts: Set<String> = ["neon", "nixie", "lcd", "minimal"]

    /// 液态外观在配置里的值，放在 `layout` 或 `look` 键下。
    public static let liquidValue = "liquid"
    /// 存外观的两个键。
    public static let lookKeys: [String] = ["layout", "look"]

    /// 快速开关里是 Pro 的工具。
    public static let proTools: Set<QuickToggle> = [
        .textCapture, .qrCode, .presentation, .keyboardLock, .lowPower,
    ]

    /// 不属于某个小组件的 Pro 设置。
    public enum Setting: String, CaseIterable, Sendable {
        /// 设置 ▸ AI 里刘海对话的那一组。
        case aiNotch
        /// 电池面板里的充电上限。
        case chargeLimit
    }

    // MARK: 判断

    /// 这种小组件整种是不是 Pro。
    public static func isProKind(_ kind: WidgetKind) -> Bool { proKinds.contains(kind) }

    /// 原来的赞助者专属样式（表盘、角色、Wi-Fi、电池外观），和
    /// `WidgetCatalog.isSupporterOnly` 原来的判断一样，那边现在调这里。
    /// 只有这些受 `Supporter.isUnlocked` 管。
    public static func isSupporterStyle(_ overrides: [String: WidgetConfig.Value]) -> Bool {
        if case .string(let layout) = overrides["layout"], proClockLayouts.contains(layout) { return true }
        if case .string(let raw) = overrides["character"],
           let character = WaterCharacter(rawValue: raw), character.isSupporterOnly { return true }
        if case .string(let layout) = overrides["layout"], WifiRingStyle.from(layout: layout)?.isSupporterOnly == true { return true }
        if case .string(let look) = overrides[BatteryLook.key], BatteryLook.from(look)?.isSupporterOnly == true { return true }
        return false
    }

    /// 选的是液态外观。
    public static func isLiquid(_ overrides: [String: WidgetConfig.Value]) -> Bool {
        lookKeys.contains { key in
            if case .string(let value) = overrides[key] { return value == liquidValue }
            return false
        }
    }

    /// 一组样式覆盖（库里的一张卡片、样式菜单的一项，或一个选项的一个值）
    /// 是不是 Pro 样式。
    public static func isProStyle(_ overrides: [String: WidgetConfig.Value]) -> Bool {
        isSupporterStyle(overrides) || isLiquid(overrides)
    }

    /// 一张小组件卡片（种类加样式）要不要标 Pro。
    public static func isPro(_ kind: WidgetKind, overrides: [String: WidgetConfig.Value]) -> Bool {
        isProKind(kind) || isProStyle(overrides)
    }

    /// 一个已经放好的小组件现在要不要标 Pro：整种是 Pro，或现在用的外观是 Pro。
    public static func isPro(_ instance: WidgetInstance) -> Bool {
        isPro(instance.kind, overrides: instance.config.values)
    }

    /// 设置里某个单选项的一个值是不是 Pro（如外观选“液态”、喝水选柴犬）。
    public static func isProChoice(key: String, value: String) -> Bool {
        isProStyle([key: .string(value)])
    }

    /// 快速开关的一个工具（存的 rawValue）是不是 Pro。
    public static func isProTool(_ raw: String) -> Bool {
        guard let tool = QuickToggle(rawValue: raw) else { return false }
        return proTools.contains(tool)
    }

    /// 设置里多选列表的一项是不是 Pro。目前只有快速开关的工具。
    public static func isProListChoice(key: String, value: String) -> Bool {
        key == QuickToggle.key && isProTool(value)
    }

    /// 菜单里放不下胶囊时，在名字后面加的字。
    public static func menuTitle(_ title: String, isPro: Bool) -> String {
        isPro ? "\(title)（\(label)）" : title
    }
}
