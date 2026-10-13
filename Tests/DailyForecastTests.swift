import Foundation
import XCTest

/// The pure half of the 7-day, 10-day and multi-city weather layouts:
/// Open-Meteo's JSON, WMO codes, day labels, the range bar, the refresh
/// throttle and the catalog's sizes. The fetching half needs the network.
final class DailyForecastTests: XCTestCase {

    private let sample = Data("""
    {"latitude":39.9,"longitude":116.4,"utc_offset_seconds":28800,"timezone":"Asia/Shanghai",
     "current":{"time":"2026-10-13T22:45","interval":900,"temperature_2m":14.6,"weather_code":0,"is_day":0},
     "daily":{"time":["2026-10-13","2026-10-14","2026-10-15","2026-10-16"],
              "weather_code":[3,61,null,95],
              "temperature_2m_max":[19.2,16.0,18.0,22.5],
              "temperature_2m_min":[9.1,11.4,8.0,15.0],
              "precipitation_probability_max":[5,80,null,null]}}
    """.utf8)

    /// 2026-10-13 15:00 UTC, which is 23:00 in Beijing.
    private let lateEvening = Date(timeIntervalSince1970: 1_791_903_600)

    // MARK: Parsing

    func testParsesCurrentAndDays() throws {
        let forecast = try XCTUnwrap(DailyForecast.parse(sample))
        XCTAssertEqual(forecast.utcOffsetSeconds, 28_800)
        XCTAssertEqual(forecast.current, DailyForecast.Now(temperatureC: 14.6, code: 0, isDay: false))
        // The day with a null code is dropped, not drawn as code 0.
        XCTAssertEqual(forecast.days.map(\.key), ["2026-10-13", "2026-10-14", "2026-10-16"])
        XCTAssertEqual(forecast.days[1], DailyForecast.Day(key: "2026-10-14", code: 61, highC: 16,
                                                           lowC: 11.4, precipitationChance: 80))
        XCTAssertNil(forecast.days[2].precipitationChance)
    }

    func testRejectsErrorsAndEmptyReplies() {
        XCTAssertNil(DailyForecast.parse(Data(#"{"error":true,"reason":"Latitude must be in range"}"#.utf8)))
        XCTAssertNil(DailyForecast.parse(Data("not json".utf8)))
        XCTAssertNil(DailyForecast.parse(Data(#"{"daily":{"time":[]}}"#.utf8)))
        XCTAssertNil(DailyForecast.parse(Data(#"{"daily":{"time":["2026-10-13"],"weather_code":[null]}}"#.utf8)))
    }

    func testMissingCurrentStillGivesDays() throws {
        let data = Data(#"{"daily":{"time":["2026-10-13"],"weather_code":[2],"temperature_2m_max":[20],"temperature_2m_min":[10]}}"#.utf8)
        let forecast = try XCTUnwrap(DailyForecast.parse(data))
        XCTAssertNil(forecast.current)
        XCTAssertEqual(forecast.days.count, 1)
        XCTAssertEqual(forecast.utcOffsetSeconds, 0)
    }

    func testSwappedHighAndLowAreOrdered() throws {
        let data = Data(#"{"daily":{"time":["2026-10-13"],"weather_code":[2],"temperature_2m_max":[5],"temperature_2m_min":[12]}}"#.utf8)
        let day = try XCTUnwrap(DailyForecast.parse(data)?.days.first)
        XCTAssertEqual(day.highC, 12)
        XCTAssertEqual(day.lowC, 5)
    }

    // MARK: Days

    func testTodayIsThePlacesToday() throws {
        let forecast = try XCTUnwrap(DailyForecast.parse(sample))
        XCTAssertEqual(forecast.todayKey(now: lateEvening), "2026-10-13")
        // Two hours later it is past midnight in Beijing, still the 13th in UTC.
        let afterMidnight = lateEvening.addingTimeInterval(2 * 3600)
        XCTAssertEqual(forecast.todayKey(now: afterMidnight), "2026-10-14")
        XCTAssertEqual(forecast.upcoming(now: afterMidnight, limit: 10).map(\.key),
                       ["2026-10-14", "2026-10-16"])
        XCTAssertEqual(forecast.today(now: afterMidnight)?.code, 61)
    }

    func testUpcomingIsCapped() throws {
        let forecast = try XCTUnwrap(DailyForecast.parse(sample))
        XCTAssertEqual(forecast.upcoming(now: lateEvening, limit: 2).count, 2)
        XCTAssertEqual(forecast.upcoming(now: lateEvening, limit: 0).count, 0)
    }

    func testWeekdayLabels() {
        // 2026-10-13 is a Tuesday.
        XCTAssertEqual(DailyForecast.weekdayLabel("2026-10-13", today: "2026-10-13"), "今天")
        XCTAssertEqual(DailyForecast.weekdayLabel("2026-10-14", today: "2026-10-13"), "周三")
        XCTAssertEqual(DailyForecast.weekdayLabel("2026-10-18", today: "2026-10-13"), "周日")
        XCTAssertEqual(DailyForecast.weekdayLabel("2026-10-19", today: "2026-10-13"), "周一")
        XCTAssertEqual(DailyForecast.weekdayLabel("garbage", today: "2026-10-13"), "garbage")
    }

    // MARK: Range bar

    func testRangeFractionsPlaceTheDayOnTheWeek() {
        let f = DailyForecast.rangeFractions(low: 10, high: 15, scaleLow: 5, scaleHigh: 25)
        XCTAssertEqual(f.start, 0.25, accuracy: 1e-9)
        XCTAssertEqual(f.end, 0.5, accuracy: 1e-9)
    }

    func testRangeFractionsClampAndSurviveAFlatWeek() {
        let wide = DailyForecast.rangeFractions(low: 0, high: 40, scaleLow: 5, scaleHigh: 25)
        XCTAssertEqual(wide.start, 0)
        XCTAssertEqual(wide.end, 1)
        let flat = DailyForecast.rangeFractions(low: 10, high: 10, scaleLow: 10, scaleHigh: 10)
        XCTAssertLessThan(flat.start, flat.end)
        XCTAssertTrue(flat.start.isFinite && flat.end.isFinite)
    }

    func testScaleSpansEveryDay() throws {
        let forecast = try XCTUnwrap(DailyForecast.parse(sample))
        let scale = try XCTUnwrap(DailyForecast.scale(forecast.days))
        XCTAssertEqual(scale.low, 9.1)
        XCTAssertEqual(scale.high, 22.5)
        XCTAssertNil(DailyForecast.scale([]))
    }

    // MARK: Refresh and cache

    func testRefreshAtMostEveryThirtyMinutes() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(DailyForecast.isDue(lastAttempt: nil, now: now))
        XCTAssertFalse(DailyForecast.isDue(lastAttempt: now.addingTimeInterval(-29 * 60), now: now))
        XCTAssertTrue(DailyForecast.isDue(lastAttempt: now.addingTimeInterval(-30 * 60), now: now))
    }

    func testCacheKeyRoundsNearbySpellingsTogether() {
        XCTAssertEqual(DailyForecast.cacheKey(lat: 39.9042, lon: 116.4074),
                       DailyForecast.cacheKey(lat: 39.9011, lon: 116.4071))
        XCTAssertNotEqual(DailyForecast.cacheKey(lat: 39.90, lon: 116.40),
                          DailyForecast.cacheKey(lat: 31.23, lon: 121.47))
    }

    func testRequestAsksForTenDaysWithTheLocalTimeZone() throws {
        let url = try XCTUnwrap(DailyForecast.url(lat: 39.9042, lon: 116.4074))
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(url.host, "api.open-meteo.com")
        XCTAssertEqual(query["forecast_days"], "10")
        XCTAssertEqual(query["timezone"], "auto")
        XCTAssertEqual(query["latitude"], "39.9042")
        XCTAssertTrue(query["daily"]?.contains("temperature_2m_max") ?? false)
        XCTAssertTrue(query["current"]?.contains("weather_code") ?? false)
    }

    // MARK: WMO codes

    func testEveryDocumentedCodeHasASymbolAndAName() {
        let documented = [0, 1, 2, 3, 45, 48, 51, 53, 55, 56, 57, 61, 63, 65, 66, 67,
                          71, 73, 75, 77, 80, 81, 82, 85, 86, 95, 96, 99]
        for code in documented {
            XCTAssertNotEqual(WMOWeather.condition(code), "未知", "\(code)")
            XCTAssertFalse(WMOWeather.symbol(code).isEmpty, "\(code)")
        }
        XCTAssertEqual(WMOWeather.condition(42), "未知")
        XCTAssertEqual(WMOWeather.symbol(42), "cloud.fill")
    }

    func testCodesMapToTheRightSky() {
        XCTAssertEqual(WMOWeather.symbol(0), "sun.max.fill")
        XCTAssertEqual(WMOWeather.symbol(0, isDay: false), "moon.stars.fill")
        XCTAssertEqual(WMOWeather.symbol(63), "cloud.rain.fill")
        XCTAssertEqual(WMOWeather.symbol(75), "cloud.snow.fill")
        XCTAssertEqual(WMOWeather.symbol(95), "cloud.bolt.rain.fill")
        XCTAssertEqual(WMOWeather.condition(0), "晴")
        XCTAssertEqual(WMOWeather.condition(2), "多云")
        XCTAssertEqual(WMOWeather.condition(3), "阴")
        XCTAssertEqual(WMOWeather.condition(65), "大雨")
    }

    // MARK: Cities and sizes

    func testCitiesAreCleanedAndCapped() {
        XCTAssertEqual(WeatherLayout.cities([" 北京 ", "", "上海", "beijing", "Beijing", "广州", "深圳"]),
                       ["北京", "上海", "beijing"])
        XCTAssertEqual(WeatherLayout.cities(["杭州"]), ["杭州"])
        XCTAssertEqual(WeatherLayout.cities([]), WeatherLayout.defaultCities)
        XCTAssertEqual(WeatherLayout.cities(["  "]), WeatherLayout.defaultCities)
    }

    func testForecastLayoutsAreWideEnoughForTheirDays() {
        let week = WidgetCatalog.make(.weather, overrides: ["layout": .string("week")])!
        let ten = WidgetCatalog.make(.weather, overrides: ["layout": .string("tenDays")])!
        let current = WidgetCatalog.make(.weather)!
        let weekWidth = WidgetCatalog.contentSize(week, position: .bottom).width
        let tenWidth = WidgetCatalog.contentSize(ten, position: .bottom).width
        XCTAssertGreaterThanOrEqual(weekWidth, 7 * 38)
        XCTAssertGreaterThan(tenWidth, weekWidth)
        XCTAssertGreaterThan(weekWidth, WidgetCatalog.contentSize(current, position: .bottom).width)
        // Stacked, ten days is a taller column than seven.
        XCTAssertGreaterThan(WidgetCatalog.verticalHeight(ten), WidgetCatalog.verticalHeight(week))
        XCTAssertGreaterThan(WidgetCatalog.verticalHeight(week), 76)
    }

    func testCitiesWidthFollowsTheCount() {
        var two = WidgetCatalog.make(.weather, overrides: ["layout": .string("cities")])!
        two.config.set("cities", .list([.string("北京"), .string("上海")]))
        let three = WidgetCatalog.make(.weather, overrides: ["layout": .string("cities")])!
        XCTAssertLessThan(WidgetCatalog.naturalSize(two).width, WidgetCatalog.naturalSize(three).width)
        var five = three
        five.config.set("cities", .list(["a", "b", "c", "d", "e"].map { .string($0) }))
        XCTAssertEqual(WidgetCatalog.naturalSize(five).width, WidgetCatalog.naturalSize(three).width)
    }

    func testCityOptionsFollowTheLayout() {
        let cities = WidgetConfig(["layout": .string("cities")])
        XCTAssertTrue(WidgetCatalog.applies("cities", to: cities, kind: .weather))
        XCTAssertFalse(WidgetCatalog.applies("city", to: cities, kind: .weather))
        let week = WidgetConfig(["layout": .string("week")])
        XCTAssertFalse(WidgetCatalog.applies("cities", to: week, kind: .weather))
        XCTAssertTrue(WidgetCatalog.applies("city", to: week, kind: .weather))
        XCTAssertTrue(WidgetCatalog.applies("fahrenheit", to: cities, kind: .weather))
    }
}
