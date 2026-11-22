import Foundation

/// 天气面板精修用到的纯逻辑：小熊猫提醒卡怎么排、怎么写，主天气区的最高最低和体感，
/// 未来两小时降水够不够可靠，底部的更新时间和离线文案，空气质量详情的建议。
///
/// 一条原则：哪项数据没拿到就返回 nil，界面整项不画，绝不拿示例数字或 0 顶上。
public enum WeatherGlance {
    // MARK: - 提醒卡

    /// 提醒卡的样子：告警（重要天气或空气质量）是两行带标题的卡，平常天只剩一行。
    public enum ReminderStyle: Equatable, Sendable {
        case alert
        case calm
    }

    /// 面板顶上小熊猫那张提醒卡。
    public struct Reminder: Equatable, Sendable {
        /// 主句来自哪一类提示（小熊猫姿势按它挑）。
        public var kind: WeatherTips.Tip.Kind
        public var style: ReminderStyle
        /// 告警卡的标题；平常天就是那一行。
        public var title: String
        /// 告警卡的第二行，没有时 nil。
        public var detail: String?
        /// 空气质量告警时标题旁的 AQI 数值（美标），否则 nil。
        public var aqi: Int?
        /// 这张卡和空气质量有关（主句或第二行），点一下切到指数页看 AQI 详情。
        public var aboutAir: Bool

        public init(kind: WeatherTips.Tip.Kind, style: ReminderStyle, title: String, detail: String? = nil,
                    aqi: Int? = nil, aboutAir: Bool = false) {
            self.kind = kind
            self.style = style
            self.title = title
            self.detail = detail
            self.aqi = aqi
            self.aboutAir = aboutAir
        }
    }

    /// 提醒的轻重：数字小的先说。重要天气（下雨下雪、风大）最先，其次空气质量告警，
    /// 再是降温、温差、紫外线，穿衣兜底。同一档里照 `WeatherTips` 原来的顺序。
    public static func rank(_ kind: WeatherTips.Tip.Kind) -> Int {
        switch kind {
        case .rain, .wind: 0
        case .air: 1
        case .cooling, .swing, .uv: 2
        case .clothing: 3
        }
    }

    /// 按轻重重新排好的提示（稳定排序）。
    public static func prioritized(_ tips: [WeatherTips.Tip]) -> [WeatherTips.Tip] {
        tips.enumerated()
            .sorted { lhs, rhs in
                let a = rank(lhs.element.kind), b = rank(rhs.element.kind)
                return a == b ? lhs.offset < rhs.offset : a < b
            }
            .map(\.element)
    }

    /// 从全部提示里挑出提醒卡。没有任何提示时 nil（整张卡不画）。
    ///
    /// - 有告警（下雨、风大、空气差，或降温、温差、紫外线）：两行卡，标题是最要紧的那句；
    ///   空气差时标题写“空气质量较差 / 空气轻度污染”，带 AQI 数值，第二行是建议；
    ///   别的告警排第一、空气也差时，第二行补一句空气，点卡片能去看 AQI。
    /// - 只剩穿衣那句：缩成一行，用短句（“宜穿羽绒服”），不再重复大字里的温度。
    public static func reminder(tips: [WeatherTips.Tip], aqi: Int?) -> Reminder? {
        let ordered = prioritized(tips)
        guard let top = ordered.first else { return nil }
        let polluted = aqi.map { $0 > WeatherTips.aqiPolluted } ?? false

        if top.kind == .clothing {
            return Reminder(kind: .clothing, style: .calm, title: top.short)
        }
        if top.kind == .air, let aqi, polluted {
            return Reminder(kind: .air, style: .alert, title: airTitle(aqi), detail: top.text, aqi: aqi,
                            aboutAir: true)
        }
        if polluted, let aqi, ordered.contains(where: { $0.kind == .air }) {
            return Reminder(kind: top.kind, style: .alert, title: top.text,
                            detail: tr("\(airTitle(aqi)) · AQI \(aqi)"), aboutAir: true)
        }
        // 第二行放下一句不同类的告警（穿衣不算），没有就只有标题。
        let next = ordered.dropFirst().first { $0.kind != .clothing && $0.kind != top.kind }
        return Reminder(kind: top.kind, style: .alert, title: top.text, detail: next?.short)
    }

    /// 空气质量告警卡的标题：美标 AQI 超过 150 “空气质量较差”，101 到 150 “空气轻度污染”。
    public static func airTitle(_ aqi: Int) -> String {
        aqi > WeatherTips.aqiBad ? tr("空气质量较差") : tr("空气轻度污染")
    }

    // MARK: - 主天气区

    /// 大字旁边“最高 9° · 最低 0°”。最高最低都要有才写；缺任何一个 nil。
    public static func rangeLine(high: Double?, low: Double?, fahrenheit: Bool) -> String? {
        guard let high, let low, high.isFinite, low.isFinite else { return nil }
        let hi = WeatherTips.degrees(high, fahrenheit: fahrenheit)
        let lo = WeatherTips.degrees(low, fahrenheit: fahrenheit)
        return tr("最高 \(hi)° · 最低 \(lo)°")
    }

    /// “体感 3°”。没有体感温度时 nil。
    public static func feelsLine(_ apparent: Double?, fahrenheit: Bool) -> String? {
        guard let apparent, apparent.isFinite else { return nil }
        return tr("体感 \(WeatherTips.degrees(apparent, fahrenheit: fahrenheit))°")
    }

    // MARK: - 未来两小时降水

    /// 至少要盖住这么多格（15 分钟一格，6 格是一个半小时）才算可靠，少了整块不画。
    public static let minimumRainSlots = 6

    /// 今天页的“未来两小时”。
    public struct RainGlance: Equatable, Sendable {
        public var status: RainOutlook.Status
        /// 右边那一句：无雨时“暂无明显降水”，有雨时“约 40 分钟后有雨”“正在下雨”。
        public var headline: String
        /// 有雨时的第二句（“持续半小时”“约 25 分钟后停”），无雨时空。
        public var detail: String
        /// 有雨才画降水条；无雨只占一行。
        public var showsBars: Bool
    }

    /// 从 15 分钟降水里得出未来两小时；数据缺或盖不住一个半小时时 nil（不显示）。
    public static func rain(_ slots: [RainOutlook.Slot], now: Date) -> RainGlance? {
        let bars = RainOutlook.bars(slots, now: now)
        guard bars.count >= minimumRainSlots, let status = RainOutlook.status(slots, now: now) else { return nil }
        switch status {
        case .dry:
            return RainGlance(status: status, headline: tr("暂无明显降水"), detail: "", showsBars: false)
        default:
            return RainGlance(status: status, headline: RainOutlook.headline(status),
                              detail: RainOutlook.detail(status), showsBars: true)
        }
    }

    // MARK: - 更新时间

    /// 底部的状态：离线且有旧数据时“离线，显示缓存数据”；否则“14:10 更新”（今天之前的
    /// 带上日期）；从没成功过时 nil。钟点按这台 Mac 的时区。
    public static func updateStatus(updatedAt: Date?, offline: Bool, hasData: Bool, now: Date,
                                    zone: TimeZone = .current) -> String? {
        if offline, hasData { return tr("离线，显示缓存数据") }
        guard let updatedAt, hasData else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.month, .day, .hour, .minute], from: updatedAt)
        let clock = String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
        if calendar.isDate(updatedAt, inSameDayAs: now) { return tr("\(clock) 更新") }
        return tr("\(parts.month ?? 1) 月 \(parts.day ?? 1) 日 \(clock) 更新")
    }

    // MARK: - 空气质量详情

    /// 美标 AQI 六档的完整名：优、良、轻度污染、中度污染、重度污染、严重污染。
    public static func aqiLongLevel(_ aqi: Int) -> String {
        switch aqi {
        case ...50: tr("优", context: "aqi")
        case 51...100: tr("良", context: "aqi")
        case 101...150: tr("轻度污染")
        case 151...200: tr("中度污染")
        case 201...300: tr("重度污染")
        default: tr("严重污染")
        }
    }

    /// 每档一句建议。
    public static func aqiAdvice(_ aqi: Int) -> String {
        switch aqi {
        case ...50: tr("空气很好，适合户外活动")
        case 51...100: tr("空气尚可，极少数敏感人群减少久留户外")
        case 101...150: tr("敏感人群减少户外活动，外出可戴口罩")
        case 151...200: tr("减少户外活动，外出建议戴口罩")
        case 201...300: tr("尽量待在室内，外出戴好口罩")
        default: tr("避免外出，关好门窗")
        }
    }

    /// AQI 刻度条上标记的位置 0 到 1：刻度画到 300，再高贴在最右。
    public static func aqiFraction(_ aqi: Int) -> Double {
        min(1, max(0, Double(aqi) / 300))
    }

    // MARK: - 2×2 小卡

    /// 风向风力小卡：“东南风 2 级”，没风“无风”。
    public static func windCard(speed: Double, from degrees: Double) -> String {
        let force = Wind.beaufort(speed)
        guard force > 0 else { return tr("无风") }
        return tr("\(Wind.direction(degrees)) \(force) 级")
    }
}
