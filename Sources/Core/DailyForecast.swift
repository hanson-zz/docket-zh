import Foundation

/// A day-by-day forecast for one place, from Open-Meteo.
///
/// Pure: parsing the provider's JSON, naming a WMO weather code in Chinese,
/// labelling the days, placing a day's range on the week's scale and deciding
/// when a copy is due a refresh are all here, so they are tested without the
/// network. `ForecastService` does the fetching and caching.
public struct DailyForecast: Equatable, Sendable {
    /// One calendar day on the place's own clock.
    public struct Day: Equatable, Sendable {
        /// "2026-10-13", as Open-Meteo writes it with `timezone=auto`: a date
        /// on the place's calendar, not an instant.
        public var key: String
        /// WMO 4677 code, see `WMOWeather`.
        public var code: Int
        public var highC: Double
        public var lowC: Double
        /// Percent, when the model publishes one for that day.
        public var precipitationChance: Double?

        public init(key: String, code: Int, highC: Double, lowC: Double,
                    precipitationChance: Double? = nil) {
            self.key = key
            self.code = code
            self.highC = highC
            self.lowC = lowC
            self.precipitationChance = precipitationChance
        }
    }

    /// Conditions at the time of the request.
    public struct Now: Equatable, Sendable {
        public var temperatureC: Double
        public var code: Int
        /// False at night, so a clear sky reads as a moon.
        public var isDay: Bool

        public init(temperatureC: Double, code: Int, isDay: Bool = true) {
            self.temperatureC = temperatureC
            self.code = code
            self.isDay = isDay
        }
    }

    public var current: Now?
    public var days: [Day]
    /// The place's offset from UTC, so "today" is the place's today and not
    /// this Mac's.
    public var utcOffsetSeconds: Int

    public init(current: Now?, days: [Day], utcOffsetSeconds: Int = 0) {
        self.current = current
        self.days = days
        self.utcOffsetSeconds = utcOffsetSeconds
    }

    // MARK: Parsing

    /// Open-Meteo's `/v1/forecast` with `daily=weather_code,temperature_2m_max,
    /// temperature_2m_min,precipitation_probability_max` and
    /// `current=temperature_2m,weather_code,is_day`.
    ///
    /// Every series is read as optional numbers, since the model publishes
    /// nulls at the far end of its range. A day missing its code or either
    /// temperature is dropped rather than drawn as zero. Nil for an error
    /// response, anything malformed, or a reply with no usable day at all.
    public static func parse(_ data: Data) -> DailyForecast? {
        struct Wire: Decodable {
            struct Current: Decodable {
                var temperature_2m: Double?
                var weather_code: Double?
                var is_day: Double?
            }
            struct Daily: Decodable {
                var time: [String]
                var weather_code: [Double?]?
                var temperature_2m_max: [Double?]?
                var temperature_2m_min: [Double?]?
                var precipitation_probability_max: [Double?]?
            }
            var error: Bool?
            var utc_offset_seconds: Int?
            var current: Current?
            var daily: Daily?
        }
        guard let wire = try? JSONDecoder().decode(Wire.self, from: data),
              wire.error != true, let daily = wire.daily
        else { return nil }

        func at<T>(_ list: [T?]?, _ index: Int) -> T? {
            guard let list, list.indices.contains(index) else { return nil }
            return list[index]
        }

        var days: [Day] = []
        for (index, key) in daily.time.enumerated() {
            guard let code = at(daily.weather_code, index),
                  let high = at(daily.temperature_2m_max, index),
                  let low = at(daily.temperature_2m_min, index),
                  code.isFinite, high.isFinite, low.isFinite
            else { continue }
            days.append(Day(key: key, code: Int(code), highC: max(high, low), lowC: min(high, low),
                            precipitationChance: at(daily.precipitation_probability_max, index)))
        }
        guard !days.isEmpty else { return nil }

        var now: Now?
        if let current = wire.current, let celsius = current.temperature_2m,
           let code = current.weather_code, celsius.isFinite, code.isFinite {
            now = Now(temperatureC: celsius, code: Int(code), isDay: (current.is_day ?? 1) != 0)
        }
        return DailyForecast(current: now, days: days, utcOffsetSeconds: wire.utc_offset_seconds ?? 0)
    }

    // MARK: Days

    /// Today's key on the place's calendar.
    public func todayKey(now: Date) -> String {
        Self.dayKey(now, utcOffsetSeconds: utcOffsetSeconds)
    }

    /// The days from today on, at most `limit`.
    ///
    /// A copy fetched before midnight still opens on yesterday, and a cache
    /// kept through a failed refresh can be a day or two old. Dropping the
    /// past keeps the first column honest about being today.
    public func upcoming(now: Date, limit: Int) -> [Day] {
        let today = todayKey(now: now)
        // Keys sort as dates, so a string comparison is a date comparison.
        return Array(days.filter { $0.key >= today }.prefix(max(0, limit)))
    }

    /// Today, if the forecast still covers it.
    public func today(now: Date) -> Day? {
        let key = todayKey(now: now)
        return days.first { $0.key == key }
    }

    /// 今天前后第 `offset` 天（-1 昨天，1 明天），按这个地方的日历。暖心提示
    /// 比较昨天、今天、明天的最高温用；请求带 `past_days=1`，所以有昨天。
    public func day(offset: Int, now: Date) -> Day? {
        let key = Self.dayKey(now.addingTimeInterval(Double(offset) * 86_400), utcOffsetSeconds: utcOffsetSeconds)
        return days.first { $0.key == key }
    }

    /// "2026-10-13" for an instant, at a fixed offset from UTC.
    public static func dayKey(_ date: Date, utcOffsetSeconds: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: utcOffsetSeconds) ?? .gmt
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// "今天" for today, otherwise "周一" to "周日". A key that does not
    /// parse is returned as it came, which at least says which day it is.
    public static func weekdayLabel(_ key: String, today: String) -> String {
        if key == today { return tr("今天") }
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return key }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        guard let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
        else { return key }
        // Calendar's weekday is 1 for Sunday.
        let names = [tr("周日"), tr("周一"), tr("周二"), tr("周三"), tr("周四"), tr("周五"), tr("周六")]
        return names[(calendar.component(.weekday, from: date) - 1) % 7]
    }

    // MARK: Range bar

    /// Where a day's low and high sit on the scale of every day shown, as
    /// fractions from 0 (the coldest low) to 1 (the warmest high).
    ///
    /// The system's own weather draws each day's bar against the whole
    /// week, so a cold day reads as a bar sitting left and a mild one as a
    /// bar sitting right. A week with no spread at all centres a sliver
    /// rather than dividing by zero.
    public static func rangeFractions(low: Double, high: Double,
                                      scaleLow: Double, scaleHigh: Double) -> (start: Double, end: Double) {
        let span = scaleHigh - scaleLow
        guard span > 0.01 else { return (0.45, 0.55) }
        func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
        let start = clamp((min(low, high) - scaleLow) / span)
        let end = clamp((max(low, high) - scaleLow) / span)
        return (start, max(start, end))
    }

    /// The coldest low and warmest high across `days`.
    public static func scale(_ days: [Day]) -> (low: Double, high: Double)? {
        guard let low = days.map(\.lowC).min(), let high = days.map(\.highC).max() else { return nil }
        return (low, high)
    }

    // MARK: Refresh

    /// Open-Meteo updates its models hourly at best, and a daily forecast
    /// barely moves within the hour. Half an hour is ample, and keeps the
    /// free endpoint's goodwill.
    public static let refreshInterval: TimeInterval = 30 * 60

    /// Whether the last attempt (successful or not) is old enough to try again.
    public static func isDue(lastAttempt: Date?, now: Date,
                             interval: TimeInterval = refreshInterval) -> Bool {
        guard let lastAttempt else { return true }
        return now.timeIntervalSince(lastAttempt) >= interval
    }

    /// The cache key for a coordinate. Two decimals is about a kilometre,
    /// which is finer than the model's grid, so two spellings of one city
    /// share one entry.
    public static func cacheKey(lat: Double, lon: Double) -> String {
        String(format: "%.2f,%.2f", lat, lon)
    }

    /// The request for a coordinate.
    public static func url(lat: Double, lon: Double, days: Int = 10) -> URL? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", lat)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", lon)),
            URLQueryItem(name: "daily",
                         value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: String(days)),
            // 多取昨天一天，暖心提示说“比昨天冷几度”；列表和 7 天都从今天起算（upcoming）。
            URLQueryItem(name: "past_days", value: "1"),
        ]
        return components?.url
    }
}

/// WMO 4677 weather interpretation codes, as Open-Meteo publishes them.
public enum WMOWeather {
    /// An SF Symbol for a code. Unknown codes land on a plain cloud rather
    /// than nothing, the same way the MET mapping does.
    public static func symbol(_ code: Int, isDay: Bool = true) -> String {
        switch code {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51, 53, 55: "cloud.drizzle.fill"
        case 56, 57, 66, 67: "cloud.sleet.fill"
        case 61, 63, 80, 81: "cloud.rain.fill"
        case 65, 82: "cloud.heavyrain.fill"
        case 71, 73, 75, 77, 85, 86: "cloud.snow.fill"
        case 95, 96, 99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    /// The condition in Chinese, in the words the MET mapping already uses
    /// where the two overlap ("晴", "多云", "阴").
    public static func condition(_ code: Int) -> String {
        switch code {
        case 0: tr("晴")
        case 1: tr("少云")
        case 2: tr("多云")
        case 3: tr("阴")
        case 45: tr("雾")
        case 48: tr("雾凇")
        case 51: tr("小毛毛雨")
        case 53: tr("毛毛雨")
        case 55: tr("大毛毛雨")
        case 56, 57: tr("冻毛毛雨")
        case 61: tr("小雨")
        case 63: tr("中雨")
        case 65: tr("大雨")
        case 66, 67: tr("冻雨")
        case 71: tr("小雪")
        case 73: tr("中雪")
        case 75: tr("大雪")
        case 77: tr("雪粒")
        case 80: tr("小阵雨")
        case 81: tr("阵雨")
        case 82: tr("强阵雨")
        case 85: tr("小阵雪")
        case 86: tr("大阵雪")
        case 95: tr("雷阵雨")
        case 96, 99: tr("雷阵雨伴有冰雹")
        default: tr("未知")
        }
    }
}

/// The multi-city layout's list and the forecast layouts' measurements.
///
/// Here rather than in the catalog so the numbers the catalog sizes a tile
/// with and the numbers the tile lays itself out with are one set.
public enum WeatherLayout {
    /// Shown when nothing usable is configured.
    public static let defaultCities = ["北京", "上海", "广州"]

    /// At most this many cities share one card. A fourth would leave each
    /// one too little width for its name on a 58pt strip.
    public static let maxCities = 3

    /// The cities the multi-city layout shows: trimmed, blanks dropped,
    /// duplicates (ignoring case) dropped, at most three. Nothing usable
    /// falls back to the defaults, so the card is never empty.
    public static func cities(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for name in raw {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            result.append(trimmed)
            if result.count == maxCities { break }
        }
        return result.isEmpty ? defaultCities : result
    }

    /// How many days the forecast layout shows on a bottom shelf: its 天数
    /// option, 7 or 10. See `WeatherStyle.days`.
    public static func days(_ config: WidgetConfig) -> Int {
        WeatherStyle.days(config)
    }

    /// How many days the same layout shows stacked in a 76pt side column,
    /// where every day is a row and ten rows would make a tower.
    public static func columnDays(_ config: WidgetConfig) -> Int {
        WeatherStyle.columnDays(config)
    }

    /// Width of one day's column on a bottom shelf. Enough for "24° 16°"
    /// at 11pt, which is the widest thing in it.
    public static let dayColumnWidth: Double = 40

    /// Height of one day's row in a side column.
    public static let dayRowHeight: Double = 19

    /// Width of one city's cell on a bottom shelf.
    public static let cityCellWidth: Double = 88

    /// Height of one city's block in a side column: name, then reading.
    public static let cityRowHeight: Double = 36

    /// WidgetSurface's horizontal inset on both sides. Hardcoded rather than
    /// read from WidgetStyle so the catalog stays free of SwiftUI.
    public static let inset: Double = 20

    public static func forecastWidth(_ config: WidgetConfig) -> Double {
        Double(days(config)) * dayColumnWidth + inset
    }

    public static func forecastColumnHeight(_ config: WidgetConfig) -> Double {
        Double(columnDays(config)) * dayRowHeight + 17
    }

    public static func citiesWidth(count: Int) -> Double {
        Double(min(maxCities, max(1, count))) * cityCellWidth + inset
    }

    public static func citiesColumnHeight(count: Int) -> Double {
        max(76, Double(min(maxCities, max(1, count))) * cityRowHeight + 8)
    }
}
