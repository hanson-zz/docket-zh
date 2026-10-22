import Foundation

/// 天气面板改版用到的纯逻辑：Open-Meteo 的分钟级降水、逐小时紫外线和空气质量
/// 怎么解析，2 小时降水条和那一句“约 40 分钟后有雨，持续半小时”怎么写，
/// 生活指数三格（穿衣、紫外线、空气质量）怎么分档，以及面板里的城市列表
/// （搜索添加、拖动排序、删除）怎么存。
///
/// MET Norway 在中国没有分钟级降水和空气质量，这几块改用 Open-Meteo 的免费接口
/// （不要 key）补：`/v1/forecast` 的 `minutely_15=precipitation` 和 `hourly=uv_index`，
/// `air-quality-api` 的 `current=us_aqi`。接口失败时这几块直接隐藏，原有的
/// 当前天气、逐小时、多日照旧。
public enum WeatherPanel {
    /// 面板里额外添加的城市（第 2 个起），按顺序。第 1 个城市仍是原来的 `city`
    /// （空字符串是“当前位置”），旧版本和卡片照样读它。
    public static let moreCitiesKey = "moreCities"
    /// 面板显示：2 小时降水提示。
    public static let showRainKey = "showRain"
    /// 面板显示：生活指数。
    public static let showIndicesKey = "showIndices"
}

// MARK: - Open-Meteo 解析

/// Open-Meteo `/v1/forecast` 一次请求里面板要的东西，按 `timeformat=unixtime` 读，
/// 时间都是 UTC 秒，不用管时区。
///
/// 第 1 个城市只用其中的分钟级降水、紫外线和降水概率（当前天气和逐小时仍来自
/// MET）；第 2 个城市起整块都用它，因为共用的 MET 位置只有一个。
public struct WeatherNowcast: Equatable, Sendable {
    /// 当前天气。
    public struct Current: Equatable, Sendable {
        public var temperatureC: Double
        public var code: Int
        public var isDay: Bool
        /// 米每秒（请求带 `wind_speed_unit=ms`），和 MET 一样。
        public var windSpeed: Double?
        public var windFrom: Double?
        public var humidity: Double?

        public init(temperatureC: Double, code: Int, isDay: Bool = true, windSpeed: Double? = nil,
                    windFrom: Double? = nil, humidity: Double? = nil) {
            self.temperatureC = temperatureC
            self.code = code
            self.isDay = isDay
            self.windSpeed = windSpeed
            self.windFrom = windFrom
            self.humidity = humidity
        }
    }

    /// 一小时。`time` 是这一小时的开始。
    public struct Hour: Equatable, Sendable {
        public var time: Date
        public var temperatureC: Double?
        public var code: Int?
        public var isDay: Bool
        /// 前一小时的降水量（Open-Meteo 的 `precipitation` 记在小时末）。
        public var precipitationMM: Double?
        public var precipitationChance: Double?
        public var uvIndex: Double?

        public init(time: Date, temperatureC: Double? = nil, code: Int? = nil, isDay: Bool = true,
                    precipitationMM: Double? = nil, precipitationChance: Double? = nil, uvIndex: Double? = nil) {
            self.time = time
            self.temperatureC = temperatureC
            self.code = code
            self.isDay = isDay
            self.precipitationMM = precipitationMM
            self.precipitationChance = precipitationChance
            self.uvIndex = uvIndex
        }
    }

    public var current: Current?
    public var hours: [Hour]
    /// 15 分钟一格的降水。
    public var slots: [RainOutlook.Slot]

    public init(current: Current? = nil, hours: [Hour] = [], slots: [RainOutlook.Slot] = []) {
        self.current = current
        self.hours = hours
        self.slots = slots
    }

    /// 请求的地址。`forecast_minutely_15=12` 加 `past_minutely_15=1` 盖住现在往后
    /// 2 小时多一点（能判断雨停没停）；逐小时取 13 小时（往前 1 小时给“现在”）。
    public static func url(lat: Double, lon: Double) -> URL? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", lat)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", lon)),
            URLQueryItem(name: "current",
                         value: "temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m,wind_direction_10m,is_day"),
            URLQueryItem(name: "hourly",
                         value: "temperature_2m,weather_code,precipitation,precipitation_probability,uv_index,is_day"),
            URLQueryItem(name: "minutely_15", value: "precipitation"),
            URLQueryItem(name: "forecast_minutely_15", value: "12"),
            URLQueryItem(name: "past_minutely_15", value: "1"),
            URLQueryItem(name: "forecast_hours", value: "13"),
            URLQueryItem(name: "past_hours", value: "1"),
            URLQueryItem(name: "wind_speed_unit", value: "ms"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        return components?.url
    }

    /// 解析 `/v1/forecast` 的回复。出错（`error: true`）、格式不对或者三块都是空的
    /// 返回 nil；缺哪一块就那一块为空，界面据此只隐藏那一块。
    public static func parse(_ data: Data) -> WeatherNowcast? {
        struct Wire: Decodable {
            struct Current: Decodable {
                var temperature_2m: Double?
                var relative_humidity_2m: Double?
                var weather_code: Double?
                var wind_speed_10m: Double?
                var wind_direction_10m: Double?
                var is_day: Double?
            }
            struct Hourly: Decodable {
                var time: [Double]
                var temperature_2m: [Double?]?
                var weather_code: [Double?]?
                var precipitation: [Double?]?
                var precipitation_probability: [Double?]?
                var uv_index: [Double?]?
                var is_day: [Double?]?
            }
            struct Minutely: Decodable {
                var time: [Double]
                var precipitation: [Double?]?
            }
            var error: Bool?
            var current: Current?
            var hourly: Hourly?
            var minutely_15: Minutely?
        }
        guard let wire = try? JSONDecoder().decode(Wire.self, from: data), wire.error != true else { return nil }

        func at(_ list: [Double?]?, _ index: Int) -> Double? {
            guard let list, list.indices.contains(index), let value = list[index], value.isFinite else { return nil }
            return value
        }

        var current: Current?
        if let c = wire.current, let celsius = c.temperature_2m, let code = c.weather_code,
           celsius.isFinite, code.isFinite {
            current = Current(temperatureC: celsius, code: Int(code), isDay: (c.is_day ?? 1) != 0,
                              windSpeed: c.wind_speed_10m, windFrom: c.wind_direction_10m,
                              humidity: c.relative_humidity_2m)
        }

        var hours: [Hour] = []
        if let h = wire.hourly {
            for (index, stamp) in h.time.enumerated() {
                hours.append(Hour(time: Date(timeIntervalSince1970: stamp),
                                  temperatureC: at(h.temperature_2m, index),
                                  code: at(h.weather_code, index).map { Int($0) },
                                  isDay: (at(h.is_day, index) ?? 1) != 0,
                                  precipitationMM: at(h.precipitation, index),
                                  precipitationChance: at(h.precipitation_probability, index),
                                  uvIndex: at(h.uv_index, index)))
            }
        }

        var slots: [RainOutlook.Slot] = []
        if let m = wire.minutely_15 {
            for (index, stamp) in m.time.enumerated() {
                guard let mm = at(m.precipitation, index) else { continue }
                // Open-Meteo 的分钟级降水是“前 15 分钟之和”，记在这一格的末尾。
                let end = Date(timeIntervalSince1970: stamp)
                slots.append(RainOutlook.Slot(start: end.addingTimeInterval(-RainOutlook.slotLength), mm: max(0, mm)))
            }
        }

        if current == nil, hours.isEmpty, slots.isEmpty { return nil }
        return WeatherNowcast(current: current, hours: hours, slots: slots)
    }

    /// 现在这一小时的紫外线指数（开始时间不晚于现在的最后一小时）；没有时 nil。
    public func uvIndex(now: Date) -> Double? {
        hour(at: now)?.uvIndex
    }

    /// 包含 `now` 的那一小时。
    public func hour(at now: Date) -> Hour? {
        hours.last { $0.time <= now && now.timeIntervalSince($0.time) < 3600 }
    }

    /// 某个整点开始的那一小时的降水概率（Open-Meteo 记在小时末，所以取下一个整点的值）。
    public func precipitationChance(hourStarting start: Date) -> Double? {
        let end = start.addingTimeInterval(3600)
        return hours.first { abs($0.time.timeIntervalSince(end)) < 60 }?.precipitationChance
    }

    /// 往后的逐小时（开始时间晚于现在），最多 `limit` 个，缺温度或天气代码的跳过。
    public func upcomingHours(after now: Date, limit: Int) -> [Hour] {
        Array(hours.filter { $0.time > now && $0.temperatureC != nil && $0.code != nil }.prefix(max(0, limit)))
    }
}

/// Open-Meteo 空气质量接口。
public enum AirQualityReading {
    /// `current=us_aqi,european_aqi`。分档用美国 AQI：0 到 500 的刻度和国内的
    /// 空气质量指数一样分“优、良、轻度、中度、重度、严重”六档。
    public static func url(lat: Double, lon: Double) -> URL? {
        var components = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", lat)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", lon)),
            URLQueryItem(name: "current", value: "us_aqi,european_aqi"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        return components?.url
    }

    /// 当前的美国 AQI，取整。没有、出错或不是数字时 nil。
    public static func parse(_ data: Data) -> Int? {
        struct Wire: Decodable {
            struct Current: Decodable { var us_aqi: Double? }
            var error: Bool?
            var current: Current?
        }
        guard let wire = try? JSONDecoder().decode(Wire.self, from: data), wire.error != true,
              let aqi = wire.current?.us_aqi, aqi.isFinite, aqi >= 0 else { return nil }
        return Int(aqi.rounded())
    }
}

// MARK: - 2 小时降水

/// 面板顶上的 2 小时降水条和那一句话。
public enum RainOutlook {
    /// 一格 15 分钟。
    public static let slotLength: TimeInterval = 15 * 60
    /// 往后看 2 小时，8 格。
    public static let window: TimeInterval = 2 * 3600
    public static let barCount = 8
    /// 15 分钟至少这么多毫米才算有雨。国内的分钟数据是从逐小时插出来的，
    /// 一小时 0.1 毫米（逐小时预报画雨量条的门槛）摊到每格约 0.025，取 0.03。
    public static let thresholdMM = 0.03
    /// 柱子满格对应的毫米数（15 分钟 2 毫米已是大雨）。
    public static let fullBarMM = 2.0

    /// 一格：开始时间和这 15 分钟的降水量。
    public struct Slot: Equatable, Sendable {
        public var start: Date
        public var mm: Double

        public init(start: Date, mm: Double) {
            self.start = start
            self.mm = mm
        }

        public var end: Date { start.addingTimeInterval(RainOutlook.slotLength) }
        public var isRain: Bool { mm >= RainOutlook.thresholdMM }
    }

    /// 判断的结果。
    public enum Status: Equatable, Sendable {
        /// 2 小时内无雨。
        case dry
        /// 约 `inMinutes` 分钟后开始，持续约 `lasting` 分钟；`open` 为数据末尾还在下。
        case starts(inMinutes: Int, lasting: Int, open: Bool)
        /// 正在下，约 `inMinutes` 分钟后停；`open` 为 2 小时内不会停。
        case stops(inMinutes: Int, open: Bool)
    }

    /// 从现在起的 8 格（结束时间晚于现在的前 8 格）。数据不够 8 格时有几格给几格。
    public static func bars(_ slots: [Slot], now: Date) -> [Slot] {
        Array(slots.sorted { $0.start < $1.start }.filter { $0.end > now }.prefix(barCount))
    }

    /// 柱子高度 0 到 1：开平方，小雨也看得见，大雨不至于顶破。没雨是 0。
    public static func level(_ mm: Double) -> Double {
        guard mm.isFinite, mm >= thresholdMM else { return 0 }
        return min(1, max(0.12, (mm / fullBarMM).squareRoot()))
    }

    /// 2 小时内下不下雨、几时开始、下多久。没有任何一格时 nil（面板隐藏这一块）。
    ///
    /// 分钟数取整到 5 分钟，至少 5 分钟；持续时长按格数算（15 分钟一格），一直下到
    /// 数据末尾的记 `open`。
    public static func status(_ slots: [Slot], now: Date) -> Status? {
        let ordered = slots.sorted { $0.start < $1.start }.filter { $0.end > now }
        guard !ordered.isEmpty else { return nil }
        let horizon = now.addingTimeInterval(window)

        // 现在这一格在下：找它停的那一刻。
        if let first = ordered.first, first.start <= now, first.isRain {
            guard let stop = ordered.first(where: { !$0.isRain }) else {
                return .stops(inMinutes: roundedMinutes(ordered.last!.end.timeIntervalSince(now)), open: true)
            }
            if stop.start > horizon { return .stops(inMinutes: roundedMinutes(window), open: true) }
            return .stops(inMinutes: roundedMinutes(stop.start.timeIntervalSince(now)), open: false)
        }

        guard let startIndex = ordered.firstIndex(where: { $0.isRain && $0.start < horizon }) else { return .dry }
        let start = ordered[startIndex]
        var count = 0
        var index = startIndex
        while index < ordered.count, ordered[index].isRain {
            count += 1
            index += 1
        }
        let open = index == ordered.count
        return .starts(inMinutes: roundedMinutes(start.start.timeIntervalSince(now)),
                       lasting: count * Int(slotLength / 60), open: open)
    }

    private static func roundedMinutes(_ seconds: TimeInterval) -> Int {
        max(5, Int((seconds / 60 / 5).rounded()) * 5)
    }

    /// 降水条上面的大字：“约 40 分钟后有雨”“正在下雨”“2 小时内无雨”。
    public static func headline(_ status: Status) -> String {
        switch status {
        case .dry: tr("2 小时内无雨")
        case .starts(let minutes, _, _): WeatherStyle.rainSoonText(minutes: minutes)
        case .stops: tr("正在下雨")
        }
    }

    /// 大字右边的小字：“持续半小时”“约 25 分钟后停”。无雨时为空。
    public static func detail(_ status: Status) -> String {
        switch status {
        case .dry: ""
        case .starts(_, let lasting, let open): durationText(minutes: lasting, open: open)
        case .stops(let minutes, let open): open ? tr("2 小时内不会停") : tr("约 \(minutes) 分钟后停")
        }
    }

    /// 一整句，给读屏和卡片提示用：“约 40 分钟后有雨，持续半小时”。
    public static func sentence(_ status: Status) -> String {
        let tail = detail(status)
        return tail.isEmpty ? headline(status) : tr("\(headline(status))，\(tail)")
    }

    /// “持续约 15 分钟”“持续半小时”“持续约 1 小时”“持续约 1 个半小时”“持续 2 小时以上”。
    public static func durationText(minutes: Int, open: Bool) -> String {
        if minutes >= 120 { return tr("持续 2 小时以上") }
        if open { return tr("之后一直有雨") }
        switch minutes {
        case ..<30: return tr("持续约 \(max(15, minutes)) 分钟")
        case 30: return tr("持续半小时")
        case 31..<60: return tr("持续约 \(minutes) 分钟")
        case 60: return tr("持续约 1 小时")
        case 90: return tr("持续约 1 个半小时")
        default:
            let hours = Double(minutes) / 60
            return tr("持续约 \(hours.formatted(.number.precision(.fractionLength(0...1)))) 小时")
        }
    }

    /// 降水条下面的刻度：现在、30 分、60 分、90 分、2 小时。
    public static let axisLabels: [String] = [tr("现在"), tr("30 分"), tr("60 分"), tr("90 分"), tr("2 小时")]
}

// MARK: - 生活指数

/// 生活指数三格：穿衣（按温度）、紫外线、空气质量。
public enum WeatherIndex {
    /// 按气温给一句穿衣：28° 以上短袖，23 到 28 薄长袖，17 到 23 薄外套，
    /// 11 到 17 外套，5 到 11 厚外套，-5 到 5 羽绒服，再冷厚羽绒服。
    public static func clothing(celsius: Double) -> String {
        switch celsius {
        case 28...: tr("短袖")
        case 23..<28: tr("薄长袖")
        case 17..<23: tr("薄外套")
        case 11..<17: tr("外套")
        case 5..<11: tr("厚外套")
        case -5..<5: tr("羽绒服")
        default: tr("厚羽绒服")
        }
    }

    /// 紫外线强度，按世界卫生组织的分档：0 到 2 弱，3 到 5 中等，6 到 7 强，
    /// 8 到 10 很强，11 以上极强。指数先四舍五入。
    public static func uvLevel(_ index: Double) -> String {
        switch Int(max(0, index).rounded()) {
        case ...2: tr("弱", context: "uv")
        case 3...5: tr("中等", context: "uv")
        case 6...7: tr("强", context: "uv")
        case 8...10: tr("很强", context: "uv")
        default: tr("极强", context: "uv")
        }
    }

    /// 紫外线格的小字：“指数 2”。
    public static func uvDetail(_ index: Double) -> String {
        tr("指数 \(Int(max(0, index).rounded()))")
    }

    /// 空气质量六档的短名（格子窄，“轻度污染”只写“轻度”）：0 到 50 优，51 到 100 良，
    /// 101 到 150 轻度，151 到 200 中度，201 到 300 重度，再高严重。
    public static func aqiLevel(_ aqi: Int) -> String {
        switch aqi {
        case ...50: tr("优", context: "aqi")
        case 51...100: tr("良", context: "aqi")
        case 101...150: tr("轻度", context: "aqi")
        case 151...200: tr("中度", context: "aqi")
        case 201...300: tr("重度", context: "aqi")
        default: tr("严重", context: "aqi")
        }
    }

    /// 空气质量到了要提醒的程度（轻度及以上），面板把这一档写成暖色。
    public static func aqiIsPolluted(_ aqi: Int) -> Bool { aqi > 100 }

    /// 风这一格的短写法：“东北 3 级”，没风写“无风”。四格并排放不下“东北风 3 级 · 4.2 m/s”。
    public static func windShort(speed: Double, from degrees: Double) -> String {
        let force = Wind.beaufort(speed)
        guard force > 0 else { return tr("无风") }
        return tr("\(point(degrees)) \(force) 级")
    }

    /// 风从哪个方向来：北、东北……西北。
    public static func point(_ degrees: Double) -> String {
        let points = [tr("北"), tr("东北"), tr("东"), tr("东南"), tr("南"), tr("西南"), tr("西"), tr("西北")]
        guard degrees.isFinite else { return points[0] }
        let normal = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return points[Int((normal / 45).rounded()) % 8]
    }
}

// MARK: - 城市列表

/// 面板里的城市列表：第 1 个是原来的 `city`（空字符串是“当前位置”），
/// 第 2 个起存在 `moreCities`。写回时第 1 个同步回 `city`，卡片和旧版本照样读。
///
/// 第 2 个城市起是 Pro（和多城市样式同一条规矩，见 `ProLicenseGate.isWeatherCityLocked`）：
/// 没解锁时列表照旧保存、不删，面板只显示第 1 个，其余的带 Pro 标、点不开。
public enum WeatherPlaces {
    /// 最多几个城市。
    public static let maxCount = 8

    /// 当前位置在列表里的写法。
    public static let currentLocation = ""

    /// 存着的城市列表。重复的（不分大小写）只留第一个，“当前位置”最多一个。
    public static func list(_ config: WidgetConfig) -> [String] {
        let first = config.string("city").trimmingCharacters(in: .whitespacesAndNewlines)
        let more = config.strings(WeatherPanel.moreCitiesKey)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return deduped([first] + more)
    }

    /// 写回：第 1 个进 `city`，其余进 `moreCities`。空列表写成只有“当前位置”。
    public static func write(_ list: [String], to config: inout WidgetConfig) {
        let clean = deduped(list.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        let first = clean.first ?? currentLocation
        config.set("city", .string(first))
        config.set(WeatherPanel.moreCitiesKey, .list(clean.dropFirst().map { .string($0) }))
    }

    /// 能不能再加：没满 `maxCount`，也不重复。
    public static func canAdd(_ city: String, to list: [String]) -> Bool {
        let name = city.trimmingCharacters(in: .whitespacesAndNewlines)
        return list.count < maxCount && !contains(name, in: list)
    }

    public static func contains(_ city: String, in list: [String]) -> Bool {
        let key = city.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return list.contains { $0.lowercased() == key }
    }

    /// 加到最后。重复或满了原样返回。
    public static func adding(_ city: String, to list: [String]) -> [String] {
        let name = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canAdd(name, to: list) else { return list }
        return list + [name]
    }

    /// 第 `index` 个能不能删：至少留 1 个，“当前位置”那项保留不删。
    public static func canRemove(at index: Int, in list: [String]) -> Bool {
        list.count > 1 && list.indices.contains(index) && list[index] != currentLocation
    }

    /// 列表里有没有“当前位置”。
    public static func hasCurrentLocation(_ list: [String]) -> Bool {
        list.contains(currentLocation)
    }

    /// 删掉第 `index` 个，至少留 1 个；“当前位置”不删。
    public static func removing(at index: Int, from list: [String]) -> [String] {
        guard canRemove(at: index, in: list) else { return list }
        var copy = list
        copy.remove(at: index)
        return copy
    }

    /// 把第 `from` 个挪到第 `to` 个，越界的夹到两端。
    public static func moving(from: Int, to: Int, in list: [String]) -> [String] {
        guard list.indices.contains(from) else { return list }
        let target = min(max(0, to), list.count - 1)
        guard target != from else { return list }
        var copy = list
        let item = copy.remove(at: from)
        copy.insert(item, at: target)
        return copy
    }

    /// 拖动松手时落在第几格：位移按行高四舍五入。
    public static func dropIndex(from: Int, translation: Double, rowHeight: Double, count: Int) -> Int {
        guard rowHeight > 0, count > 0 else { return from }
        let steps = Int((translation / rowHeight).rounded())
        return min(max(0, from + steps), count - 1)
    }

    /// 面板上切换城市时能看哪几个：没解锁时只有第 1 个。
    public static func visible(_ list: [String], unlocked: Bool) -> [String] {
        Array(list.prefix(ProLicenseGate.weatherCityLimit(unlocked: unlocked)))
    }

    private static func deduped(_ list: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for name in list {
            let key = name.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(name)
        }
        return Array(out.prefix(maxCount))
    }
}
