import XCTest
@testable import Docket

/// 天气暖心提示：优先级、各项阈值、缺数据跳过、度数换算、卡片轮换。
final class WeatherTipsTests: XCTestCase {
    private let zone = TimeZone(identifier: "Asia/Shanghai")!

    /// 当地某天某个钟点。
    private func local(day: Int = 22, hour: Int, minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func day(_ key: String, high: Double, low: Double, chance: Double? = nil) -> DailyForecast.Day {
        DailyForecast.Day(key: key, code: 3, highC: high, lowC: low, precipitationChance: chance)
    }

    /// 一小时；`end` 是小时末（Open-Meteo 的降水记在这里）。
    private func hour(end: Date, chance: Double? = nil, mm: Double? = nil, code: Int? = 3,
                      uv: Double? = nil) -> WeatherNowcast.Hour {
        WeatherNowcast.Hour(time: end, temperatureC: 15, code: code, precipitationMM: mm,
                            precipitationChance: chance, uvIndex: uv)
    }

    private func input(now: Date? = nil, temperature: Double? = 18, apparent: Double? = nil,
                       wind: Double? = nil, aqi: Int? = nil, rain: RainOutlook.Status? = nil,
                       currentMM: Double? = nil, hours: [WeatherNowcast.Hour] = [],
                       yesterday: DailyForecast.Day? = nil, today: DailyForecast.Day? = nil,
                       tomorrow: DailyForecast.Day? = nil, fahrenheit: Bool = false) -> WeatherTips.Input {
        WeatherTips.Input(now: now ?? local(hour: 10), zone: zone, temperatureC: temperature, apparentC: apparent,
                          windSpeed: wind, aqi: aqi, rain: rain, currentPrecipitationMM: currentMM,
                          hours: hours, yesterday: yesterday, today: today, tomorrow: tomorrow,
                          fahrenheit: fahrenheit)
    }

    // MARK: 优先级

    func testEverythingAtOnceComesOutInPriorityOrder() {
        let now = local(hour: 10)
        let tips = WeatherTips.tips(input(
            now: now, temperature: 12, wind: 12, aqi: 180,
            hours: [hour(end: local(hour: 12), uv: 7), hour(end: local(hour: 15), chance: 80)],
            yesterday: day("2026-10-21", high: 24, low: 14),
            today: day("2026-10-22", high: 16, low: 4)))
        XCTAssertEqual(tips.map(\.kind), [.rain, .cooling, .swing, .uv, .wind, .air, .clothing])
        XCTAssertEqual(WeatherTips.top(input(now: now, temperature: 12, wind: 12, aqi: 180,
                                             hours: [hour(end: local(hour: 15), chance: 80)]))?.kind, .rain)
    }

    func testCalmDayFallsBackToClothing() {
        let tips = WeatherTips.tips(input(temperature: 18, wind: 2, aqi: 40,
                                          hours: [hour(end: local(hour: 11), chance: 10, mm: 0, uv: 3)],
                                          yesterday: day("2026-10-21", high: 22, low: 14),
                                          today: day("2026-10-22", high: 21, low: 13),
                                          tomorrow: day("2026-10-23", high: 20, low: 12)))
        XCTAssertEqual(tips.map(\.kind), [.clothing])
        XCTAssertEqual(tips.first?.text, "现在 18 度，穿薄外套正合适")
        XCTAssertEqual(tips.first?.short, "宜穿薄外套")
    }

    func testNoTemperatureAndNothingElseGivesNoTip() {
        XCTAssertTrue(WeatherTips.tips(input(temperature: nil)).isEmpty)
        XCTAssertNil(WeatherTips.top(input(temperature: nil)))
    }

    func testEachKindAppearsAtMostOnce() {
        let tips = WeatherTips.tips(input(hours: [hour(end: local(hour: 12), chance: 90),
                                                  hour(end: local(hour: 15), chance: 90)]))
        XCTAssertEqual(tips.filter { $0.kind == .rain }.count, 1)
    }

    // MARK: 1 降雨

    func testRainingNowFromTheMinuteOutlook() {
        let tip = WeatherTips.rain(input(rain: .stops(inMinutes: 25, open: false)))
        XCTAssertEqual(tip?.text, "正在下雨，出门记得带伞")
    }

    func testRainingNowFromTheCurrentHourWhenThereIsNoMinuteOutlook() {
        XCTAssertEqual(WeatherTips.rain(input(currentMM: 0.1))?.text, "正在下雨，出门记得带伞")
        XCTAssertNil(WeatherTips.rain(input(currentMM: 0.09)))
        // 分钟级说两小时内无雨时信它，不看当前这一小时。
        XCTAssertNil(WeatherTips.rain(input(rain: .dry, currentMM: 0.5)))
    }

    func testRainSoonFromTheMinuteOutlook() {
        let tip = WeatherTips.rain(input(rain: .starts(inMinutes: 40, lasting: 30, open: false)))
        XCTAssertEqual(tip?.text, "约 40 分钟后有雨，记得带伞")
        XCTAssertEqual(tip?.short, "40 分钟后有雨")
    }

    func testAfternoonRainFromTheHourlyChance() {
        // 14:00 到 15:00 这一小时概率 50%，记在 15:00。
        let tip = WeatherTips.rain(input(now: local(hour: 9), rain: .dry,
                                         hours: [hour(end: local(hour: 15), chance: 50)]))
        XCTAssertEqual(tip?.text, "下午有雨，出门记得带伞")
        XCTAssertEqual(tip?.short, "下午有雨，带伞")
    }

    func testHourlyChanceJustBelowTheThresholdIsDry() {
        XCTAssertNil(WeatherTips.rain(input(now: local(hour: 9), hours: [hour(end: local(hour: 15), chance: 49)])))
    }

    func testHourlyAmountAloneCountsAsRain() {
        let wet = input(now: local(hour: 9), hours: [hour(end: local(hour: 20), chance: nil, mm: 0.3)])
        XCTAssertEqual(WeatherTips.rain(wet)?.text, "傍晚有雨，出门记得带伞")
        let dry = input(now: local(hour: 9), hours: [hour(end: local(hour: 20), chance: nil, mm: 0.29)])
        XCTAssertNil(WeatherTips.rain(dry))
    }

    func testRainBeyondTwelveHoursIsIgnored() {
        let far = input(now: local(hour: 8), hours: [hour(end: local(hour: 21), chance: 90)])
        XCTAssertNil(WeatherTips.rain(far))
        let edge = input(now: local(hour: 8), hours: [hour(end: local(hour: 20, minute: 59), chance: 90)])
        XCTAssertNotNil(WeatherTips.rain(edge))
    }

    func testPastHoursAreIgnored() {
        XCTAssertNil(WeatherTips.rain(input(now: local(hour: 10), hours: [hour(end: local(hour: 9), chance: 100)])))
    }

    func testSnowSaysSnow() {
        let tip = WeatherTips.rain(input(now: local(hour: 9), hours: [hour(end: local(hour: 21), chance: 70, code: 73)]))
        XCTAssertEqual(tip?.text, "晚上有雪，注意保暖防滑")
    }

    func testTomorrowMorningRain() {
        let tip = WeatherTips.rain(input(now: local(hour: 22), hours: [hour(end: local(day: 23, hour: 8), chance: 60)]))
        XCTAssertEqual(tip?.text, "明早有雨，出门记得带伞")
    }

    func testDailyChanceOnlyWhenThereIsNoHourlyRainData() {
        let daily = input(today: day("2026-10-22", high: 20, low: 12, chance: 60))
        XCTAssertEqual(WeatherTips.rain(daily)?.text, "今天可能下雨，记得带伞")
        XCTAssertNil(WeatherTips.rain(input(today: day("2026-10-22", high: 20, low: 12, chance: 59))))
        // 逐小时说不下，就不拿每日的概率吓人。
        let hourly = input(hours: [hour(end: local(hour: 11), chance: 10)],
                           today: day("2026-10-22", high: 20, low: 12, chance: 80))
        XCTAssertNil(WeatherTips.rain(hourly))
    }

    func testPeriodNames() {
        let now = local(hour: 0, minute: 30)
        XCTAssertEqual(WeatherTips.period(local(hour: 0, minute: 50), now: now, zone: zone), "一会儿")
        XCTAssertEqual(WeatherTips.period(local(hour: 3), now: now, zone: zone), "凌晨")
        XCTAssertEqual(WeatherTips.period(local(hour: 5), now: now, zone: zone), "早上")
        XCTAssertEqual(WeatherTips.period(local(hour: 9), now: now, zone: zone), "上午")
        XCTAssertEqual(WeatherTips.period(local(hour: 12), now: now, zone: zone), "中午")
        XCTAssertEqual(WeatherTips.period(local(hour: 14), now: now, zone: zone), "下午")
        XCTAssertEqual(WeatherTips.period(local(hour: 18), now: now, zone: zone), "傍晚")
        XCTAssertEqual(WeatherTips.period(local(hour: 20), now: now, zone: zone), "晚上")
        XCTAssertEqual(WeatherTips.period(local(day: 23, hour: 2), now: now, zone: zone), "夜里")
        XCTAssertEqual(WeatherTips.period(local(day: 23, hour: 7), now: now, zone: zone), "明早")
    }

    // MARK: 2 降温

    func testColderThanYesterdayAtTheThreshold() {
        let tip = WeatherTips.cooling(input(yesterday: day("2026-10-21", high: 22, low: 12),
                                            today: day("2026-10-22", high: 14, low: 8)))
        XCTAssertEqual(tip?.text, "比昨天冷 8 度，加件外套")
        XCTAssertEqual(tip?.short, "比昨天冷 8 度")
        XCTAssertNotNil(WeatherTips.cooling(input(yesterday: day("2026-10-21", high: 20, low: 12),
                                                  today: day("2026-10-22", high: 14, low: 8))))
        XCTAssertNil(WeatherTips.cooling(input(yesterday: day("2026-10-21", high: 19.9, low: 12),
                                               today: day("2026-10-22", high: 14, low: 8))))
    }

    func testCoolerTomorrow() {
        let tip = WeatherTips.cooling(input(today: day("2026-10-22", high: 20, low: 12),
                                            tomorrow: day("2026-10-23", high: 13, low: 6)))
        XCTAssertEqual(tip?.text, "明天降温 7 度，记得添衣")
    }

    func testEveningPrefersTomorrowAndDaytimePrefersYesterday() {
        let days = (day("2026-10-21", high: 28, low: 18), day("2026-10-22", high: 20, low: 14),
                    day("2026-10-23", high: 12, low: 6))
        let morning = WeatherTips.cooling(input(now: local(hour: 10), yesterday: days.0, today: days.1, tomorrow: days.2))
        XCTAssertEqual(morning?.text, "比昨天冷 8 度，加件外套")
        let evening = WeatherTips.cooling(input(now: local(hour: 18), yesterday: days.0, today: days.1, tomorrow: days.2))
        XCTAssertEqual(evening?.text, "明天降温 8 度，记得添衣")
    }

    func testWarmingIsNotCooling() {
        XCTAssertNil(WeatherTips.cooling(input(yesterday: day("2026-10-21", high: 10, low: 2),
                                               today: day("2026-10-22", high: 20, low: 10),
                                               tomorrow: day("2026-10-23", high: 25, low: 15))))
    }

    func testCoolingInFahrenheitScalesTheDifference() {
        let tip = WeatherTips.cooling(input(yesterday: day("2026-10-21", high: 22, low: 12),
                                            today: day("2026-10-22", high: 12, low: 8), fahrenheit: true))
        XCTAssertEqual(tip?.text, "比昨天冷 18 度，加件外套")
    }

    // MARK: 3 温差

    func testDaySwingAtTheThreshold() {
        XCTAssertEqual(WeatherTips.swing(input(today: day("2026-10-22", high: 22, low: 10)))?.text,
                       "今天温差 12 度，早晚加件衣服")
        XCTAssertNotNil(WeatherTips.swing(input(today: day("2026-10-22", high: 20, low: 10))))
        XCTAssertNil(WeatherTips.swing(input(today: day("2026-10-22", high: 19.9, low: 10))))
        XCTAssertNil(WeatherTips.swing(input(today: nil)))
    }

    // MARK: 4 紫外线

    func testUVThresholds() {
        func uv(_ value: Double) -> WeatherTips.Tip? {
            WeatherTips.uv(input(now: local(hour: 10), hours: [hour(end: local(hour: 12), uv: value)]))
        }
        XCTAssertNil(uv(5.4))
        XCTAssertEqual(uv(5.5)?.text, "紫外线强，出门注意防晒")
        XCTAssertEqual(uv(7.4)?.text, "紫外线强，出门注意防晒")
        XCTAssertEqual(uv(7.5)?.text, "紫外线很强，记得涂防晒")
        XCTAssertEqual(uv(11)?.text, "紫外线很强，记得涂防晒")
    }

    func testUVOnlyLooksSixHoursAhead() {
        let late = input(now: local(hour: 6), hours: [hour(end: local(hour: 13), uv: 9)])
        XCTAssertNil(WeatherTips.uv(late))
        let current = input(now: local(hour: 10, minute: 30), hours: [hour(end: local(hour: 10), uv: 9)])
        XCTAssertNotNil(WeatherTips.uv(current), "包含现在的那一小时也算")
        XCTAssertNil(WeatherTips.uv(input(hours: [])))
    }

    // MARK: 5 风

    func testWindThresholds() {
        XCTAssertNil(WeatherTips.wind(input(wind: 10.7)))
        XCTAssertEqual(WeatherTips.wind(input(wind: 10.8))?.text, "今天风大，注意防风保暖")
        XCTAssertEqual(WeatherTips.wind(input(wind: 17.1))?.text, "今天风大，注意防风保暖")
        XCTAssertEqual(WeatherTips.wind(input(wind: 17.2))?.text, "大风天气，出门注意安全")
        XCTAssertNil(WeatherTips.wind(input(wind: nil)))
    }

    // MARK: 6 空气

    func testAirThresholds() {
        XCTAssertNil(WeatherTips.air(input(aqi: 100)))
        XCTAssertEqual(WeatherTips.air(input(aqi: 101))?.text, "空气一般，少在户外久留")
        XCTAssertEqual(WeatherTips.air(input(aqi: 150))?.text, "空气一般，少在户外久留")
        XCTAssertEqual(WeatherTips.air(input(aqi: 151))?.text, "空气较差，出门戴好口罩")
        XCTAssertNil(WeatherTips.air(input(aqi: nil)))
    }

    // MARK: 7 穿衣

    func testClothingUsesFeelsLikeWhenItDiffers() {
        let tip = WeatherTips.clothing(input(temperature: 12, apparent: 8.6))
        XCTAssertEqual(tip?.text, "体感 9 度，穿厚外套正合适")
        XCTAssertEqual(tip?.short, "宜穿厚外套")
    }

    func testClothingIgnoresASmallFeelsLikeGap() {
        // 差不到 3 度时说气温，但衣服仍按体感挑。
        let tip = WeatherTips.clothing(input(temperature: 17.5, apparent: 16))
        XCTAssertEqual(tip?.text, "现在 18 度，穿外套正合适")
    }

    func testClothingInFahrenheit() {
        XCTAssertEqual(WeatherTips.clothing(input(temperature: 30, fahrenheit: true))?.text, "现在 86 度，穿短袖正合适")
    }

    func testTipsStayShort() {
        let all = WeatherTips.tips(input(
            now: local(hour: 10), temperature: 12, apparent: 5, wind: 20, aqi: 220,
            hours: [hour(end: local(hour: 12), uv: 9), hour(end: local(hour: 15), chance: 80)],
            yesterday: day("2026-10-21", high: 30, low: 14), today: day("2026-10-22", high: 16, low: 2)))
        for tip in all {
            XCTAssertLessThanOrEqual(tip.text.count, 18, tip.text)
            XCTAssertLessThanOrEqual(tip.short.count, tip.text.count, tip.short)
            XCTAssertFalse(tip.text.contains("\u{2014}"))
        }
    }

    // MARK: 轮换

    func testRotationAdvancesEveryEightSeconds() {
        let tips = [WeatherTips.Tip(kind: .rain, text: "a", short: "a"),
                    WeatherTips.Tip(kind: .uv, text: "b", short: "b"),
                    WeatherTips.Tip(kind: .clothing, text: "c", short: "c")]
        let base = Date(timeIntervalSince1970: 800)  // 800 / 8 = 100，100 % 3 = 1
        XCTAssertEqual(WeatherTips.rotating(tips, now: base)?.text, "b")
        XCTAssertEqual(WeatherTips.rotating(tips, now: base.addingTimeInterval(7.9))?.text, "b")
        XCTAssertEqual(WeatherTips.rotating(tips, now: base.addingTimeInterval(8))?.text, "c")
        XCTAssertEqual(WeatherTips.rotating(tips, now: base.addingTimeInterval(16))?.text, "a")
        XCTAssertNil(WeatherTips.rotating([], now: base))
    }

    // MARK: 数据

    func testForecastAsksForYesterdayAndFindsNeighbourDays() throws {
        let url = try XCTUnwrap(DailyForecast.url(lat: 39.9, lon: 116.4))
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.first { $0.name == "past_days" }?.value, "1")
        let forecast = DailyForecast(current: nil, days: [day("2026-10-21", high: 20, low: 10),
                                                          day("2026-10-22", high: 15, low: 8),
                                                          day("2026-10-23", high: 12, low: 5)],
                                     utcOffsetSeconds: 8 * 3600)
        let now = local(hour: 10)
        XCTAssertEqual(forecast.day(offset: -1, now: now)?.key, "2026-10-21")
        XCTAssertEqual(forecast.day(offset: 0, now: now)?.key, "2026-10-22")
        XCTAssertEqual(forecast.day(offset: 1, now: now)?.key, "2026-10-23")
        XCTAssertNil(forecast.day(offset: 2, now: now))
        // 7 天列表照旧从今天起。
        XCTAssertEqual(forecast.upcoming(now: now, limit: 7).first?.key, "2026-10-22")
    }

    func testNowcastReadsFeelsLike() throws {
        let json = #"{"current":{"temperature_2m":12,"apparent_temperature":8.5,"weather_code":3,"is_day":1}}"#
        let cast = try XCTUnwrap(WeatherNowcast.parse(Data(json.utf8)))
        XCTAssertEqual(cast.current?.apparentC, 8.5)
        let url = try XCTUnwrap(WeatherNowcast.url(lat: 39.9, lon: 116.4))
        XCTAssertTrue(url.absoluteString.contains("apparent_temperature"))
    }
}
