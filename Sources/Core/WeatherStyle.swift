import Foundation

/// 天气的四个样式和它们的选项，以及旧样式存档怎么迁过来。
///
/// 原来有七个样式，其中五个是重复的：当前、天气状况、风与日出日落三张卡片一模一样，
/// 只换第三行的字；未来 7 天和未来 10 天只差天数。2026-10-19 起并成四个：
/// - 当前（`current`）：第三行由“副标题”选项决定，城市、天气状况、风、日出日落，
///   或风与日出日落一起（原来的“风与日出日落”样式）。2 小时内有雨时副标题优先写
///   “约 N 分钟后有雨”。
/// - 多日预报（`forecast`）：“天数”选项 7 天或 10 天。
/// - 逐小时（`hourly`）。
/// - 多城市（`cities`，Pro）。
///
/// 已经放好的旧卡片读配置时换成新样式加对应选项（`migrating`），样子不变；
/// 没走解码、直接拿旧值建的配置（截图工具里的示例）也按 `layout`、`caption`、
/// `days` 这几个读法认得旧值。
public enum WeatherStyle {
    public static let layoutKey = "layout"
    public static let captionKey = "caption"
    public static let daysKey = "days"

    public static let currentLayout = "current"
    public static let forecastLayout = "forecast"
    public static let hourlyLayout = "hourly"
    public static let citiesLayout = "cities"

    /// 新的四个样式，添加面板和样式菜单按这个顺序列。
    public static let layouts = [currentLayout, forecastLayout, hourlyLayout, citiesLayout]

    /// 旧样式：天气状况、风与日出日落（并进“当前”），未来 7 天、未来 10 天（并进“多日预报”）。
    public static let legacyConditionsLayout = "conditions"
    public static let legacySkyLayout = "sky"
    public static let legacyWeekLayout = "week"
    public static let legacyTenDaysLayout = "tenDays"

    /// “当前”样式第三行写什么。
    public enum Caption: String, CaseIterable, Sendable {
        /// 城市名（原来的“当前”）。
        case city
        /// 天气状况，比如“多云”（原来的“天气状况”）。
        case condition
        /// 风向和风力。
        case wind
        /// 下一次日出或日落。
        case sun
        /// 风与日出日落一起（原来的“风与日出日落”）。
        case sky

        public var title: String {
            switch self {
            case .city: tr("城市")
            case .condition: tr("天气状况")
            // 光一个“风”在别处是“东北风”的后缀，所以带说明。
            case .wind: tr("风", context: "caption")
            case .sun: tr("日出日落")
            case .sky: tr("风与日出日落")
            }
        }

        /// 风写不写、日出日落写不写。
        public var showsWind: Bool { self == .wind || self == .sky }
        public var showsSun: Bool { self == .sun || self == .sky }
    }

    /// 多日预报的天数。
    public static let dayChoices = [7, 10]
    public static let defaultDays = 7

    // MARK: 读配置

    /// 这张卡片现在是四个样式里的哪一个。旧值按迁移后的样式读，认不出的按“当前”。
    public static func layout(_ config: WidgetConfig) -> String {
        let raw = config.string(layoutKey, default: currentLayout)
        switch raw {
        case legacyConditionsLayout, legacySkyLayout: return currentLayout
        case legacyWeekLayout, legacyTenDaysLayout: return forecastLayout
        case currentLayout, forecastLayout, hourlyLayout, citiesLayout: return raw
        default: return currentLayout
        }
    }

    /// “当前”样式的副标题。还存着旧样式值的按旧样式读。
    public static func caption(_ config: WidgetConfig) -> Caption {
        switch config.string(layoutKey, default: currentLayout) {
        case legacyConditionsLayout: return .condition
        case legacySkyLayout: return .sky
        default: return Caption(rawValue: config.string(captionKey, default: Caption.city.rawValue)) ?? .city
        }
    }

    /// 多日预报画几天：7 或 10。还存着“未来 10 天”的按 10 天读，认不出的按 7 天。
    public static func days(_ config: WidgetConfig) -> Int {
        switch config.string(layoutKey, default: currentLayout) {
        case legacyTenDaysLayout: return 10
        case legacyWeekLayout: return 7
        default:
            let value = Int(config.string(daysKey, default: String(defaultDays))) ?? defaultDays
            return dayChoices.contains(value) ? value : defaultDays
        }
    }

    /// 侧边竖排时多日预报一列画几天，十行太高，所以 10 天时画 7 天、7 天时画 5 天。
    public static func columnDays(_ config: WidgetConfig) -> Int {
        days(config) == 10 ? 7 : 5
    }

    // MARK: 迁移

    /// 读配置时把旧样式换成新样式加选项，只改 `layout`、`caption`、`days` 三个键：
    /// 天气状况 → 当前 + 副标题“天气状况”；风与日出日落 → 当前 + 副标题“风与日出日落”；
    /// 未来 7 天 → 多日预报 + 7 天；未来 10 天 → 多日预报 + 10 天。其余配置原样保留。
    public static func migrating(_ config: WidgetConfig) -> WidgetConfig {
        guard case .string(let raw) = config.values[layoutKey] else { return config }
        var copy = config
        switch raw {
        case legacyConditionsLayout:
            copy.set(layoutKey, .string(currentLayout))
            copy.set(captionKey, .string(Caption.condition.rawValue))
        case legacySkyLayout:
            copy.set(layoutKey, .string(currentLayout))
            copy.set(captionKey, .string(Caption.sky.rawValue))
        case legacyWeekLayout:
            copy.set(layoutKey, .string(forecastLayout))
            copy.set(daysKey, .string("7"))
        case legacyTenDaysLayout:
            copy.set(layoutKey, .string(forecastLayout))
            copy.set(daysKey, .string("10"))
        default:
            return config
        }
        return copy
    }

    // MARK: 快下雨了

    /// 往后看多久的雨：2 小时。
    public static let rainWindow: TimeInterval = 2 * 3600
    /// 一小时至少这么多毫米才算有雨，和逐小时预报画雨量条的门槛一样。
    public static let rainThresholdMM = 0.1

    /// 2 小时内要下雨时，离下雨还有几分钟（取整到 5 分钟，至少 5 分钟）；
    /// 现在这一小时已经在下、2 小时内没雨或数据为空时返回 nil。
    ///
    /// - Parameters:
    ///   - currentHourMM: 现在所在这一小时的降水量（预报的当前时段），nil 是不知道。
    ///   - hours: 往后每小时的开始时间和那一小时的降水量，按时间排好或不排都行。
    public static func minutesUntilRain(now: Date, currentHourMM: Double?,
                                        hours: [(start: Date, mm: Double)]) -> Int? {
        if let currentHourMM, currentHourMM >= rainThresholdMM { return nil }
        let soon = hours
            .filter { $0.mm >= rainThresholdMM && $0.start > now && $0.start.timeIntervalSince(now) <= rainWindow }
            .map(\.start)
            .min()
        guard let soon else { return nil }
        let minutes = soon.timeIntervalSince(now) / 60
        let rounded = Int((minutes / 5).rounded()) * 5
        return max(5, rounded)
    }

    /// “约 40 分钟后有雨”。
    public static func rainSoonText(minutes: Int) -> String {
        tr("约 \(minutes) 分钟后有雨")
    }
}
