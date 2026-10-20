import XCTest
@testable import Docket

/// 天气面板改版的纯逻辑：Open-Meteo 解析、2 小时降水那一句、生活指数分档、城市列表。
final class WeatherPanelTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_500_000)

    /// 从 `now` 所在的那一格起，按毫米数列出 15 分钟一格。
    private func slots(_ mm: [Double], offsetMinutes: Double = -5) -> [RainOutlook.Slot] {
        mm.enumerated().map { index, value in
            RainOutlook.Slot(start: now.addingTimeInterval(offsetMinutes * 60 + Double(index) * 900), mm: value)
        }
    }

    // MARK: 降水那一句

    func testDryWhenNothingFallsInTwoHours() {
        let status = RainOutlook.status(slots(Array(repeating: 0, count: 9)), now: now)
        XCTAssertEqual(status, .dry)
        XCTAssertEqual(RainOutlook.sentence(.dry), "2 小时内无雨")
        XCTAssertEqual(RainOutlook.detail(.dry), "")
    }

    func testRainInFortyMinutesLastingHalfAnHour() {
        // 第 0 格从 5 分钟前开始，第 3 格从 40 分钟后开始，下两格。
        let status = RainOutlook.status(slots([0, 0, 0, 0.3, 0.5, 0, 0, 0, 0]), now: now)
        XCTAssertEqual(status, .starts(inMinutes: 40, lasting: 30, open: false))
        XCTAssertEqual(RainOutlook.headline(status!), "约 40 分钟后有雨")
        XCTAssertEqual(RainOutlook.detail(status!), "持续半小时")
        XCTAssertEqual(RainOutlook.sentence(status!), "约 40 分钟后有雨，持续半小时")
    }

    func testRainAlreadyFallingSaysWhenItStops() {
        let status = RainOutlook.status(slots([0.4, 0.4, 0, 0, 0, 0, 0, 0, 0]), now: now)
        XCTAssertEqual(status, .stops(inMinutes: 25, open: false))
        XCTAssertEqual(RainOutlook.sentence(status!), "正在下雨，约 25 分钟后停")
    }

    func testRainThatDoesNotStopInTwoHours() {
        let status = RainOutlook.status(slots(Array(repeating: 1, count: 9)), now: now)
        if case .stops(_, let open)? = status { XCTAssertTrue(open) } else { XCTFail("\(String(describing: status))") }
        XCTAssertEqual(RainOutlook.detail(status!), "2 小时内不会停")
    }

    func testRainRunningOffTheEndOfTheData() {
        let status = RainOutlook.status(slots([0, 0, 0, 0, 0, 0, 0, 0.2, 0.2]), now: now)
        XCTAssertEqual(status, .starts(inMinutes: 100, lasting: 30, open: true))
        XCTAssertEqual(RainOutlook.detail(status!), "之后一直有雨")
    }

    func testRainBeyondTwoHoursIsDry() {
        var mm = Array(repeating: 0.0, count: 9)
        mm.append(0.5)
        XCTAssertEqual(RainOutlook.status(slots(mm), now: now), .dry)
    }

    func testDrizzleBelowThresholdIsDry() {
        XCTAssertEqual(RainOutlook.status(slots([0, 0.01, 0.02, 0.02, 0, 0, 0, 0, 0]), now: now), .dry)
    }

    func testNoSlotsMeansHidden() {
        XCTAssertNil(RainOutlook.status([], now: now))
        // 全是过去的格子也算没有。
        XCTAssertNil(RainOutlook.status(slots([1, 1], offsetMinutes: -60), now: now))
    }

    func testMinutesRoundToFiveAndNeverZero() {
        // 下一格 10 分钟后开始，取整到 10；正好开始的那一刻也写 5 分钟。
        XCTAssertEqual(RainOutlook.status(slots([0, 0.5], offsetMinutes: -5), now: now),
                       .starts(inMinutes: 10, lasting: 15, open: true))
        XCTAssertEqual(RainOutlook.status(slots([0, 0.5], offsetMinutes: -14), now: now),
                       .starts(inMinutes: 5, lasting: 15, open: true))
    }

    func testDurationWording() {
        XCTAssertEqual(RainOutlook.durationText(minutes: 15, open: false), "持续约 15 分钟")
        XCTAssertEqual(RainOutlook.durationText(minutes: 30, open: false), "持续半小时")
        XCTAssertEqual(RainOutlook.durationText(minutes: 45, open: false), "持续约 45 分钟")
        XCTAssertEqual(RainOutlook.durationText(minutes: 60, open: false), "持续约 1 小时")
        XCTAssertEqual(RainOutlook.durationText(minutes: 90, open: false), "持续约 1 个半小时")
        XCTAssertEqual(RainOutlook.durationText(minutes: 72, open: false), "持续约 1.2 小时")
        XCTAssertEqual(RainOutlook.durationText(minutes: 120, open: false), "持续 2 小时以上")
        XCTAssertEqual(RainOutlook.durationText(minutes: 135, open: true), "持续 2 小时以上")
    }

    func testBarsAreTheNextEightSlots() {
        let all = slots([0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9], offsetMinutes: -20)
        let bars = RainOutlook.bars(all, now: now)
        XCTAssertEqual(bars.count, 8)
        // 第 0 格 20 分钟前开始、5 分钟前结束，已经过去了。
        XCTAssertEqual(bars.first?.mm, 0.1)
    }

    func testBarLevels() {
        XCTAssertEqual(RainOutlook.level(0), 0)
        XCTAssertEqual(RainOutlook.level(0.02), 0)
        XCTAssertGreaterThanOrEqual(RainOutlook.level(0.03), 0.12)
        XCTAssertEqual(RainOutlook.level(2), 1)
        XCTAssertEqual(RainOutlook.level(50), 1)
        XCTAssertLessThan(RainOutlook.level(0.3), RainOutlook.level(1))
    }

    // MARK: 解析

    func testParsesOpenMeteoForecast() throws {
        let json = """
        {"utc_offset_seconds":28800,
         "current":{"time":1792500000,"temperature_2m":18.4,"relative_humidity_2m":86,"weather_code":61,
                    "wind_speed_10m":3.1,"wind_direction_10m":45,"is_day":1},
         "hourly":{"time":[1792497600,1792501200,1792504800],
                   "temperature_2m":[18,18.5,null],"weather_code":[3,61,61],
                   "precipitation":[0,0.4,1.2],"precipitation_probability":[10,70,80],
                   "uv_index":[2.4,1.1,0.5],"is_day":[1,1,0]},
         "minutely_15":{"time":[1792500300,1792501200,1792502100],"precipitation":[0,0.1,null]}}
        """
        let cast = try XCTUnwrap(WeatherNowcast.parse(Data(json.utf8)))
        XCTAssertEqual(cast.current?.temperatureC, 18.4)
        XCTAssertEqual(cast.current?.code, 61)
        XCTAssertEqual(cast.current?.humidity, 86)
        XCTAssertEqual(cast.current?.windSpeed, 3.1)
        XCTAssertEqual(cast.hours.count, 3)
        XCTAssertNil(cast.hours[2].temperatureC)
        XCTAssertEqual(cast.hours[2].isDay, false)
        // 分钟级是“前 15 分钟之和”，开始时间往前推 15 分钟；null 那格丢掉。
        XCTAssertEqual(cast.slots.count, 2)
        XCTAssertEqual(cast.slots[0].start, Date(timeIntervalSince1970: 1_792_500_300 - 900))
        XCTAssertEqual(cast.slots[1].mm, 0.1)
        // 现在（1792500000）所在的那一小时从 1792497600 开始。
        XCTAssertEqual(cast.uvIndex(now: Date(timeIntervalSince1970: 1_792_500_000)), 2.4)
        // 1792501200 开始的那一小时，概率记在小时末 1792504800。
        XCTAssertEqual(cast.precipitationChance(hourStarting: Date(timeIntervalSince1970: 1_792_501_200)), 80)
        let upcoming = cast.upcomingHours(after: Date(timeIntervalSince1970: 1_792_500_000), limit: 6)
        XCTAssertEqual(upcoming.map(\.time), [Date(timeIntervalSince1970: 1_792_501_200)])
    }

    func testForecastErrorsAndEmptyRepliesAreNil() {
        XCTAssertNil(WeatherNowcast.parse(Data(#"{"error":true,"reason":"bad"}"#.utf8)))
        XCTAssertNil(WeatherNowcast.parse(Data("{}".utf8)))
        XCTAssertNil(WeatherNowcast.parse(Data("not json".utf8)))
    }

    func testForecastWithOnlyMinutelyStillParses() throws {
        let json = #"{"minutely_15":{"time":[1792500300],"precipitation":[0.2]}}"#
        let cast = try XCTUnwrap(WeatherNowcast.parse(Data(json.utf8)))
        XCTAssertNil(cast.current)
        XCTAssertTrue(cast.hours.isEmpty)
        XCTAssertEqual(cast.slots.count, 1)
    }

    func testParsesAirQuality() {
        XCTAssertEqual(AirQualityReading.parse(Data(#"{"current":{"us_aqi":61.6,"european_aqi":40}}"#.utf8)), 62)
        XCTAssertNil(AirQualityReading.parse(Data(#"{"current":{"us_aqi":null}}"#.utf8)))
        XCTAssertNil(AirQualityReading.parse(Data(#"{"error":true}"#.utf8)))
        XCTAssertNil(AirQualityReading.parse(Data("[]".utf8)))
    }

    func testURLsAskForWhatThePanelReads() throws {
        let forecast = try XCTUnwrap(WeatherNowcast.url(lat: 30.27, lon: 120.15)?.absoluteString)
        XCTAssertTrue(forecast.hasPrefix("https://api.open-meteo.com/v1/forecast?"))
        XCTAssertTrue(forecast.contains("minutely_15=precipitation"))
        XCTAssertTrue(forecast.contains("uv_index"))
        XCTAssertTrue(forecast.contains("timeformat=unixtime"))
        XCTAssertTrue(forecast.contains("wind_speed_unit=ms"))
        let air = try XCTUnwrap(AirQualityReading.url(lat: 30.27, lon: 120.15)?.absoluteString)
        XCTAssertTrue(air.hasPrefix("https://air-quality-api.open-meteo.com/v1/air-quality?"))
        XCTAssertTrue(air.contains("us_aqi"))
    }

    // MARK: 生活指数

    func testClothingByTemperature() {
        XCTAssertEqual(WeatherIndex.clothing(celsius: 32), "短袖")
        XCTAssertEqual(WeatherIndex.clothing(celsius: 25), "薄长袖")
        XCTAssertEqual(WeatherIndex.clothing(celsius: 18), "薄外套")
        XCTAssertEqual(WeatherIndex.clothing(celsius: 12), "外套")
        XCTAssertEqual(WeatherIndex.clothing(celsius: 6), "厚外套")
        XCTAssertEqual(WeatherIndex.clothing(celsius: 0), "羽绒服")
        XCTAssertEqual(WeatherIndex.clothing(celsius: -12), "厚羽绒服")
        // 边界值归上一档。
        XCTAssertEqual(WeatherIndex.clothing(celsius: 28), "短袖")
        XCTAssertEqual(WeatherIndex.clothing(celsius: 17), "薄外套")
    }

    func testUVLevels() {
        XCTAssertEqual(WeatherIndex.uvLevel(0), "弱")
        XCTAssertEqual(WeatherIndex.uvLevel(2.4), "弱")
        XCTAssertEqual(WeatherIndex.uvLevel(2.5), "中等")
        XCTAssertEqual(WeatherIndex.uvLevel(6), "强")
        XCTAssertEqual(WeatherIndex.uvLevel(9), "很强")
        XCTAssertEqual(WeatherIndex.uvLevel(11.2), "极强")
        XCTAssertEqual(WeatherIndex.uvDetail(2.4), "指数 2")
    }

    func testAQILevels() {
        XCTAssertEqual(WeatherIndex.aqiLevel(0), "优")
        XCTAssertEqual(WeatherIndex.aqiLevel(50), "优")
        XCTAssertEqual(WeatherIndex.aqiLevel(62), "良")
        XCTAssertEqual(WeatherIndex.aqiLevel(101), "轻度")
        XCTAssertEqual(WeatherIndex.aqiLevel(154), "中度")
        XCTAssertEqual(WeatherIndex.aqiLevel(250), "重度")
        XCTAssertEqual(WeatherIndex.aqiLevel(420), "严重")
        XCTAssertFalse(WeatherIndex.aqiIsPolluted(100))
        XCTAssertTrue(WeatherIndex.aqiIsPolluted(101))
    }

    func testShortWind() {
        XCTAssertEqual(WeatherIndex.windShort(speed: 4.2, from: 45), "东北 3 级")
        XCTAssertEqual(WeatherIndex.windShort(speed: 0.1, from: 45), "无风")
        XCTAssertEqual(WeatherIndex.point(359), "北")
        XCTAssertEqual(WeatherIndex.point(-90), "西")
    }

    // MARK: 城市列表

    func testListReadsCityThenMoreCities() {
        let config = WidgetConfig(["city": .string(""),
                                   WeatherPanel.moreCitiesKey: .list([.string("北京"), .string("深圳"), .string("北京")])])
        XCTAssertEqual(WeatherPlaces.list(config), ["", "北京", "深圳"])
        XCTAssertEqual(WeatherPlaces.list(WidgetConfig()), [""])
    }

    func testWriteSyncsTheFirstBackToCity() {
        var config = WidgetConfig()
        WeatherPlaces.write(["北京", "", "深圳"], to: &config)
        XCTAssertEqual(config.string("city"), "北京")
        XCTAssertEqual(config.strings(WeatherPanel.moreCitiesKey), ["", "深圳"])
        XCTAssertEqual(WeatherPlaces.list(config), ["北京", "", "深圳"])
        WeatherPlaces.write([], to: &config)
        XCTAssertEqual(config.string("city"), "")
        XCTAssertEqual(config.strings(WeatherPanel.moreCitiesKey), [])
    }

    func testAddRemoveMove() {
        var list = [""]
        list = WeatherPlaces.adding("北京", to: list)
        list = WeatherPlaces.adding(" 北京 ", to: list)
        list = WeatherPlaces.adding("Shenzhen", to: list)
        list = WeatherPlaces.adding("shenzhen", to: list)
        XCTAssertEqual(list, ["", "北京", "Shenzhen"])
        XCTAssertEqual(WeatherPlaces.moving(from: 2, to: 0, in: list), ["Shenzhen", "", "北京"])
        XCTAssertEqual(WeatherPlaces.moving(from: 0, to: 9, in: list), ["北京", "Shenzhen", ""])
        XCTAssertEqual(WeatherPlaces.removing(at: 1, from: list), ["", "Shenzhen"])
        XCTAssertEqual(WeatherPlaces.removing(at: 0, from: ["北京"]), ["北京"])
        XCTAssertEqual(WeatherPlaces.dropIndex(from: 0, translation: 110, rowHeight: 58, count: 3), 2)
        XCTAssertEqual(WeatherPlaces.dropIndex(from: 1, translation: -20, rowHeight: 58, count: 3), 1)
    }

    func testListIsCapped() {
        var list = [""]
        for index in 0..<20 { list = WeatherPlaces.adding("城市\(index)", to: list) }
        XCTAssertEqual(list.count, WeatherPlaces.maxCount)
        XCTAssertFalse(WeatherPlaces.canAdd("又一个", to: list))
    }

    // MARK: Pro

    func testSecondCityOnIsPro() {
        XCTAssertTrue(ProLicenseGate.canAddWeatherCity(count: 0, unlocked: false))
        XCTAssertFalse(ProLicenseGate.canAddWeatherCity(count: 1, unlocked: false))
        XCTAssertTrue(ProLicenseGate.canAddWeatherCity(count: 1, unlocked: true))
        XCTAssertFalse(ProLicenseGate.isWeatherCityLocked(at: 0, unlocked: false))
        XCTAssertTrue(ProLicenseGate.isWeatherCityLocked(at: 1, unlocked: false))
        XCTAssertFalse(ProLicenseGate.isWeatherCityLocked(at: 1, unlocked: true))
        // 没解锁时列表不删，只是面板只看第 1 个。
        let list = ["", "北京", "深圳"]
        XCTAssertEqual(WeatherPlaces.visible(list, unlocked: false), [""])
        XCTAssertEqual(WeatherPlaces.visible(list, unlocked: true), list)
    }
}
