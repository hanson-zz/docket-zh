import Foundation
import Observation

/// 天气面板补充的数据，来自 Open-Meteo（免费、不要 key）：15 分钟一格的降水、
/// 逐小时紫外线和降水概率、当前空气质量；第 2 个城市起，当前天气和逐小时也从这里来。
///
/// MET Norway 在中国没有分钟级降水和空气质量，所以另起一个服务补，不碰
/// `WeatherService` 原来的请求：这里失败时面板只把降水条和生活指数那几格藏起来，
/// 原有的当前天气、逐小时、多日照旧。
///
/// 每个地点按坐标缓存，同一地点 15 分钟内最多请求一次；失败时保留上一次的结果，
/// 一直没成功过就是 nil。
@MainActor @Observable
final class WeatherExtrasService {
    static let shared = WeatherExtrasService()

    /// 15 分钟降水、逐小时，按 `DailyForecast.cacheKey`。
    private(set) var nowcasts: [String: WeatherNowcast] = [:]
    /// 当前美国 AQI，按 `DailyForecast.cacheKey`。
    private(set) var airQuality: [String: Int] = [:]
    /// 面板里每个城市解析到的坐标，按小写的城市名。
    private(set) var places: [String: WeatherService.Coordinate] = [:]
    /// 正在请求的地点。
    private(set) var loadingKeys: Set<String> = []

    @ObservationIgnored private var lastAttempt: [String: Date] = [:]

    private nonisolated static let userAgent = "Dockling/1.0 (macOS dock widget; https://github.com/hanson-zz/docket-zh)"
    private static let minimumInterval: TimeInterval = 15 * 60

    private init() {}

    // MARK: 读

    func nowcast(at place: WeatherService.Coordinate) -> WeatherNowcast? {
        nowcasts[Self.key(place)]
    }

    func aqi(at place: WeatherService.Coordinate) -> Int? {
        airQuality[Self.key(place)]
    }

    /// 面板里第 2 个城市起的坐标，解析过才有。
    func place(city: String) -> WeatherService.Coordinate? {
        places[city.lowercased()]
    }

    nonisolated static func key(_ place: WeatherService.Coordinate) -> String {
        DailyForecast.cacheKey(lat: place.lat, lon: place.lon)
    }

    // MARK: 取

    /// 先用天气服务自己的地图查找把城市名换成坐标（有缓存），再刷新那里的数据。
    /// 查不到的城市留空，面板写“暂无数据”。
    func load(city: String) async {
        let name = city.lowercased()
        if places[name] == nil, let found = await WeatherService.shared.coordinate(for: city) {
            places[name] = found
        }
        guard let place = places[name] else { return }
        await refresh(place)
        await ForecastService.shared.refresh(place)
    }

    /// 15 分钟内请求过的地点不再请求。两个接口各自成功各自更新。
    func refresh(_ place: WeatherService.Coordinate) async {
        let key = Self.key(place)
        guard !loadingKeys.contains(key) else { return }
        if let last = lastAttempt[key], Date.now.timeIntervalSince(last) < Self.minimumInterval { return }
        loadingKeys.insert(key)
        lastAttempt[key] = .now
        defer { loadingKeys.remove(key) }

        async let forecastData = Self.fetch(WeatherNowcast.url(lat: place.lat, lon: place.lon))
        async let airData = Self.fetch(AirQualityReading.url(lat: place.lat, lon: place.lon))
        let (forecast, air) = await (forecastData, airData)

        if let forecast, let parsed = WeatherNowcast.parse(forecast) {
            nowcasts[key] = parsed
        }
        if let air, let reading = AirQualityReading.parse(air) {
            airQuality[key] = reading
        }
    }

    /// 只拿 200 的正文；断网、超时、限流都是 nil。
    private nonisolated static func fetch(_ url: URL?) async -> Data? {
        guard let url else { return nil }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        guard let result = try? await URLSession.shared.data(for: request),
              (result.1 as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return result.0
    }

    // MARK: 换成面板用的样子

    /// 第 2 个城市起的当前天气，用 Open-Meteo 的 WMO 代码换成同一套图标和中文。
    nonisolated static func now(from cast: WeatherNowcast) -> WeatherNow? {
        guard let current = cast.current else { return nil }
        return WeatherNow(temperatureC: current.temperatureC,
                          symbolName: WMOWeather.symbol(current.code, isDay: current.isDay),
                          condition: WMOWeather.condition(current.code),
                          windSpeed: current.windSpeed, windFrom: current.windFrom,
                          humidity: current.humidity,
                          precipitationMM: cast.hour(at: .now)?.precipitationMM)
    }

    /// 第 2 个城市起的逐小时。
    nonisolated static func hours(from cast: WeatherNowcast, now: Date, limit: Int) -> [WeatherHour] {
        cast.upcomingHours(after: now, limit: limit).compactMap { hour in
            guard let celsius = hour.temperatureC, let code = hour.code else { return nil }
            // 降水记在小时末，这一小时的雨量是下一个整点那一条。
            let rain = cast.hours.first { abs($0.time.timeIntervalSince(hour.time.addingTimeInterval(3600))) < 60 }?
                .precipitationMM ?? 0
            return WeatherHour(date: hour.time, temperatureC: celsius,
                               symbolName: WMOWeather.symbol(code, isDay: hour.isDay),
                               precipitationMM: rain)
        }
    }
}
