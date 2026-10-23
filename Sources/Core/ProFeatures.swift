import Foundation

/// 码头 Pro 专属的范围：哪些小组件整种是 Pro，哪些样式、外观、工具和设置是 Pro。
///
/// 界面上的“Pro”标识和 `ProLicenseGate` 的锁都从这里读哪些东西是 Pro。
///
/// 清单按用户定的来：
/// - 原来的赞助者专属样式：时钟的霓虹、实景、液晶（原简约）表盘和翻页的
///   “大号带时分秒”卡片（原极简），清单在 `ClockStyles`；企鹅、水獭、章鱼
///   三个角色（喝水的柴犬、橘猫改为累计达标解锁，电子宠物整种是 Pro），网络
///   活动的数字 Wi-Fi（点状、细线已并入免费的经典），电池的像素电池、能量粒子、小熊猫抱电池。
/// - 整种是 Pro 的小组件，见 `proKinds`。
/// - 快速开关里的截图识字、二维码、演示模式、只锁键盘、低电量模式。
/// - 所有小组件的“液态”外观（`layout` 或 `look` 为 liquid）。
///   电池的液态还带插拔电源时水面晃荡溅水珠、低电量变红鼓起圆滴、颜色随电量
///   红黄绿渐变（见 `BatteryLiquidFX`），都只属于液态外观，不另算一项 Pro。
/// - 只属于某一种小组件的 Pro 样式，见 `isKindProStyle`：天气的多城市、电池的
///   电池格（原百分比圆环）、便签除最浅五种以外的纸色、时间进度的四格、喝水的
///   角色样式（`layout` 为 character；圆环免费，液态本来就是 Pro）、收音机的
///   三款复古皮肤和五款新外观（`skin` 为经典以外的值；半圆表盘的经典免费）、
///   纪念日单个卡片的玻璃沙漏（`hourglass` 为 glass；线条沙漏和撕页免费，见 `AnniversaryLook`）、
///   世界时钟多城市卡片的天空格子（`look` 为 sky；普通格子免费，世界时钟整种、联系状态圆点、
///   科普卡、菜单栏第二时区都免费，见 `WorldClockLook`）。喝水卡片
///   选的是累计达标解锁的柴犬或橘猫时，角色样式不算 Pro，见 `waterCharacterEarned`。
///   正在播放原来中卡上的三种卡带外观 2026-10-23 起搬成整种 Pro 的「复古卡带」。
/// - 录音的转文字、裁剪和编辑，见 `ProLicenseGate.canUseRecorderTools`。
/// - 书签的分组文件夹（`BookmarkGroups`），见 `ProLicenseGate.canUseBookmarkGroups`。
/// - 邮件面板的多账户筛选（`MailInbox`），见 `ProLicenseGate.canFilterMailAccounts`。
/// - 习惯打卡免费 `freeHabitLimit` 个习惯，第 4 个起和近七天报告是 Pro，见
///   `ProLicenseGate` 里的习惯部分。
/// - 小组件颜色与背景里的自定义取色和渐变背景，见 `WidgetTint.isProChoice`。
/// - AI 刘海对话的设置和电池面板里的充电上限。
/// - 系统活动面板里的超阈值提醒（规则存在卡片的 `alertRules`），见
///   `ProLicenseGate.systemAlertsActive`。
/// - 麦克风面板的使用记录保留 30 天（免费只看今天），见
///   `ProLicenseGate.micHistoryActive`。
/// - 壁纸的自动换：按早中晚的时刻、跟日出日落、到点从收藏随机（设置存在卡片的
///   `autoChange` 这一组，见 `WallpaperSchedule`），见
///   `ProLicenseGate.wallpaperAutoChangeActive`。壁纸本身 2026-10-20 起免费。
/// - 扩展栏悬停正在运行的 App 弹出窗口预览（`CustomDockSettings.hoverWindowPreview`），
///   见 `ProLicenseGate.windowPreviewActive`。
/// - 从小组件库新建应用分组和文件夹分组（`Setting.shelfGroups`），见
///   `ProLicenseGate.canCreateShelfGroup`。拖一个图标到另一个上叠成分组仍免费，
///   已经放好的分组没解锁时照常显示、打开、增删，只是不能再从库里新建。
/// - 加密货币面板的到价提醒（高于、低于，存在卡片的 `alerts`），见
///   `ProLicenseGate.canUseCryptoAlerts`。加密货币行情本身 2026-10-20 起免费。
/// - 截图编辑工具条的截图翻译（译文盖在截图上，翻译面板的「截图翻译」同一个）和贴图，
///   见 `ShotFeature`、`ProLicenseGate.canUseShotFeature`。标注、取字、存文件、拷贝免费。
public enum ProFeatures {

    /// 胶囊上的字。
    public static let badgeTitle = "Pro"
    /// 文字里的说法，替换原来的“赞助者专属”。
    public static let label = tr("Pro 专属")
    /// 鼠标停在 Pro 标识上时的提示。
    public static let help = tr("码头 Pro 专属，正式版推出后需要激活码解锁。")

    /// 整种都是 Pro 的小组件，共 15 种：摸鱼时钟、环境音、播客、废纸篓、
    /// GitHub、应用切换器、Codex 用量、小熊猫的竹篮、电子宠物，以及后来加进来的
    /// 应用音量、股票、自选股、文件暂存、翻译、复古卡带（磁带、随身听、收录机三种机型，
    /// 原来是正在播放中卡的卡带外观）。
    /// 壁纸切换 2026-10-20 起改为免费，按时间自动换是 Pro。
    /// 加密货币行情 2026-10-20 起改为免费，到价提醒是 Pro（见
    /// `ProLicenseGate.canUseCryptoAlerts`）。
    /// 时间进度和习惯打卡 2026-10-19 起改为免费：时间进度的液态和四格、
    /// 习惯打卡第 4 个起和报告仍是 Pro。收音机 2026-10-20 起改为免费，经典的
    /// 半圆表盘免费，三款复古皮肤和五款新外观是 Pro（见 `RadioSkin`）。录音
    /// 2026-10-20 起改为免费，转文字、裁剪和编辑是 Pro（见
    /// `ProLicenseGate.canUseRecorderTools`）。
    public static let proKinds: Set<WidgetKind> = [
        .slacker, .ambient, .podcast, .trash,
        .github, .appSwitcher, .aiUsage, .perfectDay, .pet,
        .appVolume, .stock, .watchlist,
        .fileShelf, .translate, .cassette,
    ]

    /// 有液态外观的小组件，共 8 种：电池、系统活动、专注计时、时间进度、喝水、
    /// Codex 用量、小熊猫的竹篮、摸鱼时钟。付费墙和官网的“8 种液态外观”从这里数，
    /// 给新的小组件加液态外观时记得加进来。
    public static let liquidKinds: [WidgetKind] = [
        .battery, .system, .timer, .progress, .water, .aiUsage, .perfectDay, .slacker,
    ]

    /// 原来的赞助者专属外观一共几种，付费墙和官网的“17 种专属外观”从这里数：
    /// 时钟的 Pro 表盘和 Pro 选项值（霓虹、实景、液晶，翻页的大号带时分秒卡片）、
    /// 企鹅水獭章鱼三个角色、数字 Wi-Fi、三种电池外观、六种扩展栏底板配色。
    public static var exclusiveStyleCount: Int {
        let faces = ClockStyles.all.filter(\.isPro).count
            + ClockStyles.allOptions.reduce(0) { $0 + $1.proValues.count }
        let characters = WaterCharacter.allCases.filter(\.isSupporterOnly).count
        let wifi = WifiRingStyle.allCases.filter(\.isSupporterOnly).count
        let battery = BatteryLook.allCases.filter(\.isSupporterOnly).count
        return faces + characters + wifi + battery + ShelfColor.allCases.count
    }

    /// 习惯打卡免费能用的习惯个数。第 4 个起和近七天报告是 Pro；已经有更多
    /// 习惯的不删数据，超出的只读并带小锁。
    public static let freeHabitLimit = 3

    /// 天气的多城市样式（`layout` 为 cities）是 Pro。
    public static let weatherCitiesLayout = "cities"
    /// 天气面板的城市列表免费能看几个：第 2 个城市起和多城市样式一样是 Pro，
    /// 见 `ProLicenseGate.isWeatherCityLocked`。
    public static let freeWeatherCityLimit = 1
    /// 电池的电池格样式（原百分比圆环，`layout` 仍为 gauge）是 Pro。
    public static let batteryGaugeLayout = "gauge"
    /// 便签存纸色的键。
    public static let noteColorKey = "color"
    /// 便签免费的纸色：按亮度挑的最浅五种（奶油白、薄荷绿、蜜桃、薰衣草、
    /// 柠檬黄），默认的柠檬黄在里面。其余纸色都是 Pro。
    public static let freeNoteColors: Set<PaperColor> = [.cream, .mint, .peach, .lavender, .yellow]

    /// 原来的赞助者专属表盘（时钟的 layout）：霓虹、实景、液晶，以及并进翻页的
    /// 旧值 minimal。从时钟样式注册表 `ClockStyles` 算出来，加样式时不用改这里。
    public static var proClockLayouts: Set<String> { ClockStyles.proLayouts }

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
        /// 设置 ▸ 扩展栏的「悬停显示窗口预览」。
        case windowPreview
        /// 从小组件库新建「应用分组」和「文件夹分组」。拖图标叠成的分组不算，
        /// 已经放好的分组没解锁时也照常显示和使用，见 `ProLicenseGate.canCreateShelfGroup`。
        case shelfGroups
        /// 截图编辑工具条和翻译面板里的「截图翻译」：本机识别、翻译，译文按原文块的位置
        /// 盖在截图上。取字（只识别、拷贝）免费，见 `ShotFeature`。
        case shotTranslate
        /// 截图编辑工具条里的「贴图」：把截图钉在屏幕最上层的小窗里。
        case shotPin
    }

    // MARK: 判断

    /// 这种小组件整种是不是 Pro。
    public static func isProKind(_ kind: WidgetKind) -> Bool { proKinds.contains(kind) }

    /// 原来的赞助者专属样式（表盘、企鹅水獭章鱼三个角色、Wi-Fi、电池外观），和
    /// `WidgetCatalog.isSupporterOnly` 原来的判断一样，那边现在调这里。
    /// 只有这些受 `Supporter.isUnlocked` 管。
    public static func isSupporterStyle(_ overrides: [String: WidgetConfig.Value]) -> Bool {
        // 时钟：Pro 样式（layout）或 Pro 选项值（翻页的大号带时分秒卡片）。
        if ClockStyles.isProOverrides(overrides) { return true }
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
        case .progress:
            if case .string(let layout) = overrides[TimeProgress.layoutKey] { return layout == TimeProgress.quadLayout }
        case .radio:
            // 收音机整种免费，经典免费，其余 8 款外观是 Pro。
            if case .string(let raw) = overrides[RadioSkin.key] { return RadioSkin(stored: raw).isPro }
        case .anniversary:
            // 纪念日的玻璃沙漏是 Pro，线条沙漏和撕页日历免费。
            if case .string(let raw) = overrides[AnniversaryLook.key] {
                return (AnniversaryLook(rawValue: raw) ?? AnniversaryLook.legacy).isPro
            }
        case .world:
            // 世界时钟的天空格子是 Pro，普通格子免费。
            if case .string(let raw) = overrides[WorldClockLook.key] {
                return (WorldClockLook(rawValue: raw) ?? WorldClockLook.legacy).isPro
            }
        case .water:
            // 喝水的角色样式 2026-10-20 起是 Pro，圆环免费。
            if case .string(let layout) = overrides[WaterLayout.key] { return layout == WaterLayout.character.rawValue }
        case .pet:
            // 电子宠物整种是 Pro，角色照旧：小熊猫以外都标 Pro。喝水的柴犬和
            // 橘猫靠达标天数解锁，那是喝水自己的规则，见 WaterCharacter.access。
            if case .string(let raw) = overrides["character"], let character = WaterCharacter(rawValue: raw) {
                return character != .redPanda
            }
        default:
            break
        }
        return false
    }

    /// 喝水卡片选的角色是柴犬或橘猫，且已经累计达标解锁（不算 Pro 打开的）。
    /// 这时角色样式对免费用户也能用：卡片照常画角色，样式不标 Pro。
    public static func waterCharacterEarned(_ config: WidgetConfig, now: Date = .now,
                                            calendar: Calendar = WaterIntake.calendar) -> Bool {
        let character = WaterCharacter.from(config)
        guard character.daysToEarn != nil else { return false }
        return WaterCharacter.access(character, config: config, pro: false, now: now, calendar: calendar) == .earned
    }

    /// 带上卡片现在的配置判断一组样式覆盖是不是 Pro。和 `isProStyle(_:_:)` 一样，
    /// 只多一条：喝水换成角色样式、而卡片（加上这组覆盖后）选的是已经达标
    /// 解锁的柴犬或橘猫时，角色样式不算 Pro。
    public static func isProStyle(_ kind: WidgetKind, _ overrides: [String: WidgetConfig.Value],
                                  config: WidgetConfig, now: Date = .now) -> Bool {
        if kind == .water, case .string(let layout) = overrides[WaterLayout.key],
           layout == WaterLayout.character.rawValue {
            var merged = config
            for (key, value) in overrides { merged.set(key, value) }
            if waterCharacterEarned(merged, now: now) {
                var rest = overrides
                rest.removeValue(forKey: WaterLayout.key)
                return isProStyle(kind, rest)
            }
        }
        return isProStyle(kind, overrides)
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
        var values = instance.config.values
        // 没存 `layout` 的老喝水卡片按角色读（画出来也是角色），标识跟着一样。
        if instance.kind == .water, values[WaterLayout.key] == nil {
            values[WaterLayout.key] = .string(WaterLayout.legacyDefault.rawValue)
        }
        // 喝水选的是已经达标解锁的柴犬或橘猫时，角色样式不标 Pro。
        return isProKind(instance.kind) || isProStyle(instance.kind, values, config: instance.config)
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
