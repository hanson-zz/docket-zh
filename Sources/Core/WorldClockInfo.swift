import Foundation

// 世界时钟改版的纯逻辑：现在适合联系吗、卡片格子的天空色和字色、科普卡上的
// 日出日落和汇率那一行、菜单栏第二时区挑哪个城市。都不碰界面，方便测试。

// MARK: - 现在适合联系吗

/// 按双方当地钟点判断现在适不适合联系对方。上班时间按 9:00 到 18:00 算。
///
/// - 绿“适合”：双方当地都在 9:00 到 18:00。
/// - 红“对方在睡觉”：对方当地 22:00 到第二天 7:00。
/// - 其余是黄，按先看对方、再看自己的顺序细分：对方 7 到 9 点“快上班”，
///   对方 18 到 22 点“已下班”；对方在上班时间而你不在时，你这边 7 到 9 点
///   “你那边还没上班”，18 到 22 点“你那边已下班”，22 到 7 点“你那边是深夜”。
public enum WorldClockContact {
    public enum Level: String, Sendable, CaseIterable {
        /// 绿。
        case good
        /// 黄。
        case maybe
        /// 红。
        case asleep

        /// 名字旁、菜单栏上的小圆点。
        public var dot: WorldClockSky.RGB {
            switch self {
            case .good: WorldClockSky.RGB(hex: 0x30C25A)
            case .maybe: WorldClockSky.RGB(hex: 0xF5B000)
            case .asleep: WorldClockSky.RGB(hex: 0xFF453A)
            }
        }

        /// 胶囊里的字：浅色外观用深一档，深色外观用浅一档。胶囊底是圆点色
        /// 18% 盖在面板玻璃上，两种外观下字和底的对比度都不低于 4.5（见测试）。
        public var inkLight: WorldClockSky.RGB {
            switch self {
            case .good: WorldClockSky.RGB(hex: 0x11703A)
            case .maybe: WorldClockSky.RGB(hex: 0x7A4A00)
            case .asleep: WorldClockSky.RGB(hex: 0xB3261E)
            }
        }

        public var inkDark: WorldClockSky.RGB {
            switch self {
            case .good: WorldClockSky.RGB(hex: 0x7FE0A0)
            case .maybe: WorldClockSky.RGB(hex: 0xFFD27A)
            case .asleep: WorldClockSky.RGB(hex: 0xFF9A90)
            }
        }

        /// 胶囊底的不透明度。
        public static let capsuleOpacity = 0.18
    }

    public enum Reason: String, Sendable, CaseIterable {
        case bothWorking
        case theyStartSoon
        case theyOffWork
        case theyAsleep
        case youBeforeWork
        case youOffWork
        case youLateNight

        public var level: Level {
            switch self {
            case .bothWorking: .good
            case .theyAsleep: .asleep
            default: .maybe
            }
        }

        /// 胶囊和菜单里的文字。
        public var text: String {
            switch self {
            case .bothWorking: tr("适合")
            case .theyStartSoon: tr("快上班")
            case .theyOffWork: tr("已下班")
            case .theyAsleep: tr("对方在睡觉")
            case .youBeforeWork: tr("你那边还没上班")
            case .youOffWork: tr("你那边已下班")
            case .youLateNight: tr("你那边是深夜")
            }
        }
    }

    /// 上班时间（分钟数，含头不含尾）。
    public static let workStart = 9 * 60
    public static let workEnd = 18 * 60
    /// 22:00 到 7:00 算睡觉。
    public static let sleepStart = 22 * 60
    public static let sleepEnd = 7 * 60

    /// 只看钟点：两边当地的“一天里的第几分钟”（0 到 1439）。
    public static func reason(theirMinutes: Int, yourMinutes: Int) -> Reason {
        let them = normalized(theirMinutes), you = normalized(yourMinutes)
        if them >= sleepStart || them < sleepEnd { return .theyAsleep }
        if them < workStart { return .theyStartSoon }
        if them >= workEnd { return .theyOffWork }
        // 对方在上班时间。
        if you >= workStart && you < workEnd { return .bothWorking }
        if you >= sleepStart || you < sleepEnd { return .youLateNight }
        if you < workStart { return .youBeforeWork }
        return .youOffWork
    }

    /// 这一刻对方所在时区和此处的判断。
    public static func reason(there: TimeZone, now: Date, here: TimeZone = .current) -> Reason {
        reason(theirMinutes: minuteOfDay(now, zone: there), yourMinutes: minuteOfDay(now, zone: here))
    }

    /// “对方 03:56”，固定 24 小时制两位数。
    public static func theirTime(_ zone: TimeZone, now: Date) -> String {
        tr("对方 \(WorldClockInfo.hhmm(now, zone: zone))")
    }

    public static func minuteOfDay(_ date: Date, zone: TimeZone) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    private static func normalized(_ minutes: Int) -> Int {
        ((minutes % 1440) + 1440) % 1440
    }
}

// MARK: - 卡片格子的天空

/// 扩展栏卡片每个城市格的底色：当地此刻的天空。白天亮蓝，清晨和黄昏橙紫，
/// 夜里深蓝（界面另加星点）。字色按底色挑白或深灰，保证对比度不低于 4.5。
///
/// 有经纬度时按当天真实的日出日落分段（日出前 40 分钟起是清晨，日出后
/// 50 分钟起是白天，日落前 60 分钟起是黄昏，日落后 40 分钟起是夜里）；
/// 表外的城市没有经纬度，按钟点：5 到 7 点清晨，7 到 17 点白天，17 到 19 点
/// 黄昏，其余夜里。
public enum WorldClockSky {
    public enum Phase: String, Sendable, CaseIterable {
        case night, dawn, day, dusk

        /// 夜里画星点。
        public var hasStars: Bool { self == .night }
    }

    /// sRGB，0 到 1。
    public struct RGB: Equatable, Sendable {
        public var r: Double
        public var g: Double
        public var b: Double

        public init(_ r: Double, _ g: Double, _ b: Double) {
            self.r = r
            self.g = g
            self.b = b
        }

        public init(hex: UInt32) {
            self.init(Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
        }

        /// WCAG 相对亮度。
        public var luminance: Double {
            func channel(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
            return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
        }
    }

    public static let white = RGB(1, 1, 1)
    /// 浅色底上的字，#1A1A1A。
    public static let darkInk = RGB(hex: 0x1A1A1A)

    /// 按钟点分段（没有经纬度时）。
    public static func phase(hour: Double) -> Phase {
        switch hour {
        case 5..<7: .dawn
        case 7..<17: .day
        case 17..<19: .dusk
        default: .night
        }
    }

    /// 这一刻城市的天空。有经纬度按当天日出日落，否则按当地钟点。
    public static func phase(now: Date, zone: TimeZone, latitude: Double?, longitude: Double?) -> Phase {
        if let latitude, let longitude,
           let sun = SunTimes.on(now, latitude: latitude, longitude: longitude, zone: zone) {
            switch sun {
            case .polarDay: return .day
            case .polarNight: return .night
            case .normal(let rise, let set):
                if now < rise.addingTimeInterval(-40 * 60) { return .night }
                if now < rise.addingTimeInterval(50 * 60) { return .dawn }
                if now < set.addingTimeInterval(-60 * 60) { return .day }
                if now < set.addingTimeInterval(40 * 60) { return .dusk }
                return .night
            }
        }
        return phase(hour: WorldClockInfo.hour(now, zone: zone))
    }

    public static func phase(_ city: WorldCity, now: Date) -> Phase {
        phase(now: now, zone: city.timeZone ?? .current, latitude: city.latitude, longitude: city.longitude)
    }

    /// 渐变从上到下的两个颜色。
    public static func colors(_ phase: Phase) -> [RGB] {
        switch phase {
        case .night: [RGB(hex: 0x0E1A4A), RGB(hex: 0x27387E)]
        case .dawn: [RGB(hex: 0x3D3A8E), RGB(hex: 0xA9506C)]
        case .day: [RGB(hex: 0x62B3F6), RGB(hex: 0xA9D7FB)]
        case .dusk: [RGB(hex: 0xB0512E), RGB(hex: 0x6C3E9E)]
        }
    }

    /// 字用白色还是深灰：哪个对渐变里最不利的那个颜色对比度更高就用哪个。
    public static func usesLightInk(_ phase: Phase) -> Bool {
        let stops = colors(phase)
        let onWhite = stops.map { contrast(white, $0) }.min() ?? 0
        let onDark = stops.map { contrast(darkInk, $0) }.min() ?? 0
        return onWhite >= onDark
    }

    public static func ink(_ phase: Phase) -> RGB {
        usesLightInk(phase) ? white : darkInk
    }

    /// 字和渐变里每个颜色的对比度里最小的那个。
    public static func worstContrast(_ phase: Phase) -> Double {
        let ink = ink(phase)
        return colors(phase).map { contrast(ink, $0) }.min() ?? 0
    }

    /// `top` 以 `opacity` 盖在 `base` 上的颜色。
    public static func over(_ top: RGB, opacity: Double, on base: RGB) -> RGB {
        RGB(base.r + (top.r - base.r) * opacity, base.g + (top.g - base.g) * opacity,
            base.b + (top.b - base.b) * opacity)
    }

    /// WCAG 对比度，1 到 21。
    public static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let la = a.luminance, lb = b.luminance
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}

// MARK: - 科普卡

public enum WorldClockInfo {
    /// 科普卡上日出日落那两格。极昼极夜时只有一格。
    public enum SunCells: Equatable, Sendable {
        case normal(rise: String, set: String)
        case polarDay
        case polarNight
    }

    /// 城市当地今天的日出日落，按城市自己的钟写。没有经纬度时 nil。
    public static func sun(_ city: WorldCity, now: Date) -> SunCells? {
        guard let latitude = city.latitude, let longitude = city.longitude else { return nil }
        let zone = city.timeZone ?? .current
        switch SunTimes.on(now, latitude: latitude, longitude: longitude, zone: zone) {
        case .normal(let rise, let set)?: return .normal(rise: hhmm(rise, zone: zone), set: hhmm(set, zone: zone))
        case .polarDay?: return .polarDay
        case .polarNight?: return .polarNight
        case nil: return nil
        }
    }

    /// 汇率那一行用哪种货币做参照：此处（参照城市）的货币，找不到时人民币。
    public static func referenceCurrency(here: TimeZone = .current) -> String {
        WorldCities.reference(here: here).flatMap { CityFacts.fact(for: $0)?.currency } ?? "CNY"
    }

    /// “1 美元 ≈ 7.12 元”“100 日元 ≈ 4.71 元”，英文界面“1 USD ≈ 7.12 CNY”。
    /// 和参照货币相同、没有汇率表、表里没有这种货币时 nil，界面就不写汇率。
    /// 汇率只从汇率服务的表里来，这里不写死任何数字。
    public static func rateLine(code: String, reference: String, rates: CurrencyRates?) -> String? {
        let code = code.uppercased(), reference = reference.uppercased()
        guard code != reference, let rates, let one = rates.rate(from: code, to: reference),
              one.isFinite, one > 0 else { return nil }
        // 一单位不到 0.1 个参照货币（日元、韩元、越南盾）时换成 10 的整数倍，
        // 让右边至少是 1；美元换英镑这种 0.75 照写。
        var amount = 1.0
        if one < 0.1 {
            while one * amount < 1, amount < 1_000_000 { amount *= 10 }
        }
        let value = one * amount
        let digits = value >= 100 ? 0 : (value >= 10 ? 1 : 2)
        let number = String(format: "%.\(digits)f", value)
        let count = String(format: "%.0f", amount)
        if L10n.isEnglish { return "\(count) \(code) ≈ \(number) \(reference)" }
        let unit = reference == "CNY" ? "元" : CityFacts.currencyName(reference)
        return "\(count) \(CityFacts.currencyName(code)) ≈ \(number) \(unit)"
    }

    /// 货币格子的大字：“美元 USD”。
    public static func currencyTitle(_ code: String) -> String {
        "\(CityFacts.currencyName(code)) \(code.uppercased())"
    }

    /// 固定 24 小时制两位数：“03:56”。
    public static func hhmm(_ date: Date, zone: TimeZone) -> String {
        let minutes = WorldClockContact.minuteOfDay(date, zone: zone)
        return String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    /// 当地钟点，带分钟的小数：9:30 是 9.5。
    public static func hour(_ date: Date, zone: TimeZone) -> Double {
        Double(WorldClockContact.minuteOfDay(date, zone: zone)) / 60
    }
}

// MARK: - 菜单栏第二时区

/// 菜单栏的“● 纽约 03:56”和点开后的下拉列表。
public enum WorldClockMenuBar {
    /// 菜单栏显示哪个城市：设置里选过、而且还在列表里的那个；没选或已经删掉时，
    /// 列表里第一个和此处时差不为 0 的城市（通常是第二个）；都和此处同一时间时
    /// 是第二个，只有一个时是它。
    public static func pick(_ cities: [WorldCity], chosen: String?, now: Date,
                            here: TimeZone = .current) -> WorldCity? {
        if let chosen, let match = cities.first(where: { $0.id == chosen || $0.storageKey == chosen }) {
            return match
        }
        if let other = cities.first(where: { city in
            guard let zone = city.timeZone else { return false }
            return WorldClockText.offsetSeconds(zone, now: now, here: here) != 0
        }) {
            return other
        }
        return cities.count > 1 ? cities[1] : cities.first
    }

    /// 菜单栏上的字：“纽约 03:56”。前面的圆点由界面按联系状态上色。
    public static func title(_ city: WorldCity, now: Date) -> String {
        "\(city.name) \(WorldClockInfo.hhmm(now, zone: city.timeZone ?? .current))"
    }

    /// 下拉列表里的城市：去掉此处本身（参照城市），其余照列表顺序。
    public static func rows(_ cities: [WorldCity], here: TimeZone = .current) -> [WorldCity] {
        let reference = WorldCities.reference(here: here)
        let rest = cities.filter { $0.id != reference?.id }
        return rest.isEmpty ? cities : rest
    }

    /// 设置里“菜单栏显示纽约”这一项的文字。
    public static func toggleTitle(_ city: WorldCity) -> String {
        tr("菜单栏显示\(city.name)")
    }
}
