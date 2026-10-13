import Foundation
import Observation

/// Daily forecasts from Open-Meteo, cached per coordinate.
///
/// Free, no key. MET's compact endpoint, which the rest of the weather
/// widget reads, has no daily high and low and thins out after a few days,
/// so the 7- and 10-day layouts and the multi-city card read this instead.
///
/// Every place has its own entry, keyed by its coordinate, so the multi-city
/// card asking for three cities never touches the one shared location
/// `WeatherService` keeps for the other layouts. Each entry is fetched at most
/// once every 30 minutes, and a failed fetch keeps the last good forecast.
@MainActor @Observable
final class ForecastService {
    static let shared = ForecastService()

    /// Forecasts by `DailyForecast.cacheKey`.
    private(set) var forecasts: [String: DailyForecast] = [:]
    /// Where each city of the multi-city card resolved to, by lowercased
    /// name. Observed, so a card redraws when a lookup lands even if the
    /// forecast for that spot was already cached.
    private(set) var cityPlaces: [String: WeatherService.Coordinate] = [:]

    @ObservationIgnored private var lastAttempt: [String: Date] = [:]
    @ObservationIgnored private var loading: Set<String> = []

    private static let userAgent = "Dockling/1.0 (macOS dock widget; https://github.com/hanson-zz/docket-zh)"

    private init() {}

    // MARK: Reading

    func forecast(at coordinate: WeatherService.Coordinate) -> DailyForecast? {
        forecasts[DailyForecast.cacheKey(lat: coordinate.lat, lon: coordinate.lon)]
    }

    /// The forecast for a city of the multi-city card, once it has resolved
    /// and been fetched.
    func forecast(city: String) -> DailyForecast? {
        cityPlaces[city.lowercased()].flatMap { forecast(at: $0) }
    }

    // MARK: Fetching

    /// Fetches unless this place was tried in the last 30 minutes.
    func refresh(_ coordinate: WeatherService.Coordinate) async {
        let key = DailyForecast.cacheKey(lat: coordinate.lat, lon: coordinate.lon)
        guard !loading.contains(key),
              DailyForecast.isDue(lastAttempt: lastAttempt[key], now: .now),
              let url = DailyForecast.url(lat: coordinate.lat, lon: coordinate.lon)
        else { return }

        loading.insert(key)
        lastAttempt[key] = .now
        defer { loading.remove(key) }

        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let parsed = DailyForecast.parse(data)
            else { return }
            forecasts[key] = parsed
        } catch {
            // Offline or throttled: keep whatever was there.
        }
    }

    /// Resolves each city with the weather widget's own map lookup and
    /// refreshes its forecast. A city that does not resolve is left out
    /// rather than shown with another city's numbers.
    func load(cities: [String]) async {
        for city in cities {
            let name = city.lowercased()
            if cityPlaces[name] == nil,
               let found = await WeatherService.shared.coordinate(for: city) {
                cityPlaces[name] = found
            }
            if let place = cityPlaces[name] {
                await refresh(place)
            }
        }
    }
}
