import Foundation

/// 天气的「暖心提示」：从已经拿到的天气数据里挑几句短短的提醒，面板顶上的小熊猫
/// 说最要紧的那句，卡片上每 8 秒轮换一句（放得下才显示）。
///
/// 按优先级排：1 降雨、带伞，2 降温，3 早晚温差大，4 紫外线强，5 风大，6 空气差，
/// 7 穿衣建议（只要有温度就总有这一句兜底）。每类最多一句；哪项数据缺了就跳过那项，
/// 不猜。阈值见各常量，测试里逐条钉住。
///
/// 文案中文约 12 到 18 字（`text`，面板气泡用），另给一句更短的（`short`，卡片
/// 一行放不下长句时退用）。温差、降温的度数按用户选的 °C / °F 换算。
public enum WeatherTips {
    /// 设置开关「暖心提示」，默认开。
    public static let showKey = "showTips"

    /// 卡片上每句停留的秒数。
    public static let rotationSeconds: TimeInterval = 8

    // MARK: 阈值

    /// 逐小时降水概率到这么多（%）算“会下雨”。
    public static let rainChance: Double = 50
    /// 或者这一小时的降水量到这么多毫米。
    public static let rainMM: Double = 0.3
    /// 只有每日预报时，今天的降水概率到这么多（%）才提醒。
    public static let dailyRainChance: Double = 60
    /// 当前这一小时已经有这么多毫米，算“正在下雨”。
    public static let rainingNowMM: Double = 0.1
    /// 逐小时往后看多久。
    public static let rainLookahead: TimeInterval = 12 * 3600
    /// 最高温比昨天（或明天比今天）低这么多摄氏度算降温。
    public static let coolingDrop: Double = 6
    /// 今天最高最低温差到这么多摄氏度算温差大。
    public static let swingRange: Double = 10
    /// 紫外线指数（四舍五入）到这么多算强，再到 `uvVeryStrong` 算很强。
    public static let uvStrong = 6
    public static let uvVeryStrong = 8
    /// 紫外线往后看几小时取最大值。
    public static let uvLookahead: TimeInterval = 6 * 3600
    /// 风力（蒲福级）到这么多算风大，到 `galeForce` 算大风。
    public static let windyForce = 6
    public static let galeForce = 8
    /// 美标 AQI 超过这个算空气差（轻度污染起），超过 `aqiBad` 改说戴口罩。
    public static let aqiPolluted = 100
    public static let aqiBad = 150
    /// 体感和气温差到这么多摄氏度，穿衣那句改说“体感”。
    public static let feelsGap: Double = 3
    /// 到了当地这个钟点以后，先比明天和今天（晚上更关心明天），之前先比今天和昨天。
    public static let eveningHour = 18

    // MARK: 输入输出

    /// 一句提示。
    public struct Tip: Equatable, Sendable {
        public enum Kind: Int, Comparable, CaseIterable, Sendable {
            case rain = 1, cooling, swing, uv, wind, air, clothing

            public static func < (a: Kind, b: Kind) -> Bool { a.rawValue < b.rawValue }
        }

        public var kind: Kind
        /// 面板气泡里的一句，中文约 12 到 18 字。
        public var text: String
        /// 卡片一行放不下 `text` 时退用的短句。
        public var short: String

        public init(kind: Kind, text: String, short: String) {
            self.kind = kind
            self.text = text
            self.short = short
        }
    }

    /// 判断要用的天气数据，全部可缺。
    public struct Input: Sendable {
        public var now: Date
        /// 这个城市自己的时区，“下午”“明早”按它算。
        public var zone: TimeZone
        public var temperatureC: Double?
        public var apparentC: Double?
        /// 米每秒。
        public var windSpeed: Double?
        /// 美标 AQI。
        public var aqi: Int?
        /// 2 小时分钟级降水的判断（`RainOutlook.status`）。
        public var rain: RainOutlook.Status?
        /// 当前这一小时的降水量（毫米），MET 有。
        public var currentPrecipitationMM: Double?
        /// 逐小时（Open-Meteo，降水量和概率记在小时末，即前一小时）。
        public var hours: [WeatherNowcast.Hour]
        public var yesterday: DailyForecast.Day?
        public var today: DailyForecast.Day?
        public var tomorrow: DailyForecast.Day?
        public var fahrenheit: Bool

        public init(now: Date, zone: TimeZone = .current, temperatureC: Double? = nil, apparentC: Double? = nil,
                    windSpeed: Double? = nil, aqi: Int? = nil, rain: RainOutlook.Status? = nil,
                    currentPrecipitationMM: Double? = nil, hours: [WeatherNowcast.Hour] = [],
                    yesterday: DailyForecast.Day? = nil, today: DailyForecast.Day? = nil,
                    tomorrow: DailyForecast.Day? = nil, fahrenheit: Bool = false) {
            self.now = now
            self.zone = zone
            self.temperatureC = temperatureC
            self.apparentC = apparentC
            self.windSpeed = windSpeed
            self.aqi = aqi
            self.rain = rain
            self.currentPrecipitationMM = currentPrecipitationMM
            self.hours = hours
            self.yesterday = yesterday
            self.today = today
            self.tomorrow = tomorrow
            self.fahrenheit = fahrenheit
        }
    }

    /// 全部提示，按优先级排好，每类最多一句。
    public static func tips(_ input: Input) -> [Tip] {
        [rain(input), cooling(input), swing(input), uv(input), wind(input), air(input), clothing(input)]
            .compactMap { $0 }
    }

    /// 最高优先级的那句（面板小熊猫说的）。
    public static func top(_ input: Input) -> Tip? {
        tips(input).first
    }

    /// 卡片上此刻轮到哪一句：每 `rotationSeconds` 秒换下一句，循环。
    public static func rotating(_ tips: [Tip], now: Date) -> Tip? {
        guard !tips.isEmpty else { return nil }
        let slot = Int((max(0, now.timeIntervalSince1970) / rotationSeconds).rounded(.down))
        return tips[slot % tips.count]
    }

    // MARK: 1 降雨

    static func rain(_ input: Input) -> Tip? {
        // 正在下：分钟级说在下，或者 MET 这一小时有雨量。
        if case .stops? = input.rain {
            return raining
        }
        if input.rain == nil, let mm = input.currentPrecipitationMM, mm >= rainingNowMM {
            return raining
        }
        if case .starts(let minutes, _, _)? = input.rain {
            return Tip(kind: .rain, text: tr("约 \(minutes) 分钟后有雨，记得带伞"),
                       short: tr("\(minutes) 分钟后有雨"))
        }
        // 逐小时：往后 12 小时第一个会下的小时。
        let horizon = input.now.addingTimeInterval(rainLookahead)
        let wet = input.hours
            .sorted { $0.time < $1.time }
            .first { hour in
                // 记在小时末：time 是这一小时的结束。
                guard hour.time > input.now, hour.time.addingTimeInterval(-3600) < horizon else { return false }
                if let chance = hour.precipitationChance, chance >= rainChance { return true }
                if let mm = hour.precipitationMM, mm >= rainMM { return true }
                return false
            }
        if let wet {
            let start = max(input.now, wet.time.addingTimeInterval(-3600))
            let label = period(start, now: input.now, zone: input.zone)
            if let code = wet.code, isSnow(code) {
                return Tip(kind: .rain, text: tr("\(label)有雪，注意保暖防滑"), short: tr("\(label)有雪"))
            }
            return Tip(kind: .rain, text: tr("\(label)有雨，出门记得带伞"), short: tr("\(label)有雨，带伞"))
        }
        // 有逐小时数据却没找到雨：信逐小时，不再看每日。
        let hasHourlyRain = input.hours.contains { $0.precipitationChance != nil || $0.precipitationMM != nil }
        if !hasHourlyRain, let chance = input.today?.precipitationChance, chance >= dailyRainChance {
            return Tip(kind: .rain, text: tr("今天可能下雨，记得带伞"), short: tr("今天可能有雨"))
        }
        return nil
    }

    private static var raining: Tip {
        Tip(kind: .rain, text: tr("正在下雨，出门记得带伞"), short: tr("正在下雨，带伞"))
    }

    /// WMO 雪的代码。
    static func isSnow(_ code: Int) -> Bool {
        [71, 73, 75, 77, 85, 86].contains(code)
    }

    /// 一个时刻说成“下午”“明早”这类，按城市自己的时区。
    ///
    /// 今天：0 到 5 点凌晨、5 到 9 早上、9 到 12 上午、12 到 14 中午、14 到 18 下午、
    /// 18 到 20 傍晚、20 到 24 晚上；明天 0 到 5 点是“夜里”，5 点以后是“明早”
    /// （往后最多看 12 小时，到不了明天中午）。离现在不到 1 小时说“一会儿”。
    public static func period(_ date: Date, now: Date, zone: TimeZone) -> String {
        if date.timeIntervalSince(now) < 3600 { return tr("一会儿", context: "tip") }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let hour = calendar.component(.hour, from: date)
        let sameDay = calendar.isDate(date, inSameDayAs: now)
        if !sameDay {
            return hour < 5 ? tr("夜里", context: "tip") : tr("明早", context: "tip")
        }
        switch hour {
        case ..<5: return tr("凌晨", context: "tip")
        case 5..<9: return tr("早上", context: "tip")
        case 9..<12: return tr("上午", context: "tip")
        case 12..<14: return tr("中午", context: "tip")
        case 14..<18: return tr("下午", context: "tip")
        case 18..<20: return tr("傍晚", context: "tip")
        default: return tr("晚上", context: "tip")
        }
    }

    // MARK: 2 降温

    static func cooling(_ input: Input) -> Tip? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = input.zone
        let evening = calendar.component(.hour, from: input.now) >= eveningHour

        func versusYesterday() -> Tip? {
            guard let yesterday = input.yesterday, let today = input.today else { return nil }
            let drop = yesterday.highC - today.highC
            guard drop >= coolingDrop else { return nil }
            let shown = degreesDelta(drop, fahrenheit: input.fahrenheit)
            return Tip(kind: .cooling, text: tr("比昨天冷 \(shown) 度，加件外套"), short: tr("比昨天冷 \(shown) 度"))
        }
        func versusTomorrow() -> Tip? {
            guard let today = input.today, let tomorrow = input.tomorrow else { return nil }
            let drop = today.highC - tomorrow.highC
            guard drop >= coolingDrop else { return nil }
            let shown = degreesDelta(drop, fahrenheit: input.fahrenheit)
            return Tip(kind: .cooling, text: tr("明天降温 \(shown) 度，记得添衣"), short: tr("明天降温 \(shown) 度"))
        }
        return evening ? (versusTomorrow() ?? versusYesterday()) : (versusYesterday() ?? versusTomorrow())
    }

    // MARK: 3 早晚温差

    static func swing(_ input: Input) -> Tip? {
        guard let today = input.today else { return nil }
        let range = today.highC - today.lowC
        guard range >= swingRange else { return nil }
        let shown = degreesDelta(range, fahrenheit: input.fahrenheit)
        return Tip(kind: .swing, text: tr("今天温差 \(shown) 度，早晚加件衣服"), short: tr("温差 \(shown) 度，早晚添衣"))
    }

    // MARK: 4 紫外线

    static func uv(_ input: Input) -> Tip? {
        // 从包含现在的那一小时起，往后 6 小时里最大的紫外线。
        let from = input.now.addingTimeInterval(-3600)
        let to = input.now.addingTimeInterval(uvLookahead)
        let values = input.hours.filter { $0.time > from && $0.time <= to }.compactMap(\.uvIndex)
        guard let peak = values.max(), peak.isFinite else { return nil }
        let index = Int(max(0, peak).rounded())
        if index >= uvVeryStrong {
            return Tip(kind: .uv, text: tr("紫外线很强，记得涂防晒"), short: tr("紫外线很强"))
        }
        if index >= uvStrong {
            return Tip(kind: .uv, text: tr("紫外线强，出门注意防晒"), short: tr("紫外线强，防晒"))
        }
        return nil
    }

    // MARK: 5 风

    static func wind(_ input: Input) -> Tip? {
        guard let speed = input.windSpeed, speed.isFinite else { return nil }
        let force = Wind.beaufort(speed)
        if force >= galeForce {
            return Tip(kind: .wind, text: tr("大风天气，出门注意安全"), short: tr("大风，注意安全"))
        }
        if force >= windyForce {
            return Tip(kind: .wind, text: tr("今天风大，注意防风保暖"), short: tr("风大，注意保暖"))
        }
        return nil
    }

    // MARK: 6 空气

    static func air(_ input: Input) -> Tip? {
        guard let aqi = input.aqi else { return nil }
        if aqi > aqiBad {
            return Tip(kind: .air, text: tr("空气较差，出门戴好口罩"), short: tr("空气差，戴口罩"))
        }
        if aqi > aqiPolluted {
            return Tip(kind: .air, text: tr("空气一般，少在户外久留"), short: tr("空气轻度污染"))
        }
        return nil
    }

    // MARK: 7 穿衣

    static func clothing(_ input: Input) -> Tip? {
        guard let celsius = input.temperatureC, celsius.isFinite else { return nil }
        let feels = input.apparentC.flatMap { $0.isFinite ? $0 : nil }
        let basis = feels ?? celsius
        // 英文里衣服名放在句中，小写（“a light jacket”的语气，中文不受影响）。
        let wear = L10n.isEnglish ? WeatherIndex.clothing(celsius: basis).lowercased()
                                  : WeatherIndex.clothing(celsius: basis)
        let short = tr("宜穿\(wear)")
        if let feels, abs(feels - celsius) >= feelsGap {
            let shown = degrees(feels, fahrenheit: input.fahrenheit)
            return Tip(kind: .clothing, text: tr("体感 \(shown) 度，穿\(wear)正合适"), short: short)
        }
        let shown = degrees(celsius, fahrenheit: input.fahrenheit)
        return Tip(kind: .clothing, text: tr("现在 \(shown) 度，穿\(wear)正合适"), short: short)
    }

    // MARK: 度数

    /// 一个温度按单位取整。
    public static func degrees(_ celsius: Double, fahrenheit: Bool) -> Int {
        Int((fahrenheit ? celsius * 9 / 5 + 32 : celsius).rounded())
    }

    /// 一个温差按单位取整（华氏的差是摄氏的 1.8 倍，不加 32）。
    public static func degreesDelta(_ celsius: Double, fahrenheit: Bool) -> Int {
        Int((fahrenheit ? celsius * 9 / 5 : celsius).rounded())
    }
}
