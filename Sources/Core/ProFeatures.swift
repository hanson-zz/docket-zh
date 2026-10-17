import Foundation

/// 码头 Pro 专属的范围：哪些小组件整种是 Pro，哪些样式、外观、工具和设置是 Pro。
///
/// 界面上的“Pro”标识和 `ProLicenseGate` 的锁都从这里读哪些东西是 Pro。
///
/// 清单按用户定的来：
/// - 原来的赞助者专属样式：时钟的霓虹、实景、简约、极简表盘，喝水和电子宠物
///   除小熊猫外的角色，网络活动的数字、点状、细线 Wi-Fi，电池的像素电池、
///   能量粒子、小熊猫抱电池。
/// - 整种是 Pro 的小组件，见 `proKinds`。
/// - 快速开关里的截图识字、二维码、演示模式、只锁键盘、低电量模式。
/// - 所有小组件的“液态”外观（`layout` 或 `look` 为 liquid）。
/// - 只属于某一种小组件的 Pro 样式，见 `isKindProStyle`：天气的多城市、电池的
///   百分比圆环、便签除最浅五种以外的纸色。
/// - 小组件颜色与背景里的自定义取色和渐变背景，见 `WidgetTint.isProChoice`。
/// - AI 刘海对话的设置和电池面板里的充电上限。
public enum ProFeatures {

    /// 胶囊上的字。
    public static let badgeTitle = "Pro"
    /// 文字里的说法，替换原来的“赞助者专属”。
    public static let label = tr("Pro 专属")
    /// 鼠标停在 Pro 标识上时的提示。
    public static let help = tr("码头 Pro 专属，正式版推出后需要激活码解锁。")

    /// 整种都是 Pro 的小组件，共 20 种：摸鱼时钟、时间进度、环境音、播客、
    /// 废纸篓、GitHub、应用切换器、Codex 用量、小熊猫的竹篮、电子宠物，以及
    /// 后来加进来的应用音量、录音、股票、自选股、加密货币行情、壁纸切换、
    /// 收音机、文件暂存、翻译、习惯打卡。
    public static let proKinds: Set<WidgetKind> = [
        .slacker, .progress, .ambient, .podcast, .trash,
        .github, .appSwitcher, .aiUsage, .perfectDay, .pet,
        .appVolume, .recorder, .stock, .watchlist, .crypto,
        .wallpaper, .radio, .fileShelf, .translate, .habit,
    ]

    /// 天气的多城市样式（`layout` 为 cities）是 Pro。
    public static let weatherCitiesLayout = "cities"
    /// 电池的百分比圆环样式（`layout` 为 gauge）是 Pro。
    public static let batteryGaugeLayout = "gauge"
    /// 便签存纸色的键。
    public static let noteColorKey = "color"
    /// 便签免费的纸色：按亮度挑的最浅五种（奶油白、薄荷绿、蜜桃、薰衣草、
    /// 柠檬黄），默认的柠檬黄在里面。其余纸色都是 Pro。
    public static let freeNoteColors: Set<PaperColor> = [.cream, .mint, .peach, .lavender, .yellow]

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

    /// 只对某一种小组件才算 Pro 的样式：同一个值放在别的小组件上是免费的
    /// （比如 `layout` 为 gauge、`color` 为 coral），所以要带上种类判断。
    public static func isKindProStyle(_ kind: WidgetKind, _ overrides: [String: WidgetConfig.Value]) -> Bool {
        switch kind {
        case .weather:
            if case .string(let layout) = overrides["layout"] { return layout == weatherCitiesLayout }
        case .battery:
            if case .string(let layout) = overrides["layout"] { return layout == batteryGaugeLayout }
        case .notes:
            if case .string(let raw) = overrides[noteColorKey] { return isProNoteColor(raw) }
        default:
            break
        }
        return false
    }

    /// 便签的这个纸色是不是 Pro。认不出的值按默认的柠檬黄读，所以是免费的。
    public static func isProNoteColor(_ raw: String) -> Bool {
        guard let color = PaperColor(rawValue: raw) else { return false }
        return !freeNoteColors.contains(color)
    }

    /// 这种小组件的一组样式覆盖是不是 Pro：通用的 Pro 样式，或只属于它的。
    public static func isProStyle(_ kind: WidgetKind, _ overrides: [String: WidgetConfig.Value]) -> Bool {
        isProStyle(overrides) || isKindProStyle(kind, overrides)
    }

    /// 一张小组件卡片（种类加样式）要不要标 Pro。
    public static func isPro(_ kind: WidgetKind, overrides: [String: WidgetConfig.Value]) -> Bool {
        isProKind(kind) || isProStyle(kind, overrides)
    }

    /// 一个已经放好的小组件现在要不要标 Pro：整种是 Pro，或现在用的外观是 Pro。
    public static func isPro(_ instance: WidgetInstance) -> Bool {
        isPro(instance.kind, overrides: instance.config.values)
    }

    /// 设置里某个单选项的一个值是不是 Pro（如外观选“液态”、喝水选柴犬）。
    public static func isProChoice(key: String, value: String) -> Bool {
        isProStyle([key: .string(value)])
    }

    /// 同上，带上种类，便签的纸色这类只属于一种小组件的选项也算。
    public static func isProChoice(kind: WidgetKind, key: String, value: String) -> Bool {
        isProStyle(kind, [key: .string(value)])
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
