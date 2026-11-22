import XCTest
@testable import Docket

/// 天气面板精修：提醒卡优先级、未来两小时降水够不够可靠、更新时间和离线文案、缺值隐藏。
final class WeatherGlanceTests: XCTestCase {
    private let zone = TimeZone(identifier: "Asia/Shanghai")!
    private let now = Date(timeIntervalSince1970: 1_792_500_000)

    private func tip(_ kind: WeatherTips.Tip.Kind, _ text: String, _ short: String = "") -> WeatherTips.Tip {
        WeatherTips.Tip(kind: kind, text: text, short: short.isEmpty ? text : short)
    }

    private func slots(_ mm: [Double]) -> [RainOutlook.Slot] {
        mm.enumerated().map { index, value in
            RainOutlook.Slot(start: now.addingTimeInterval(-5 * 60 + Double(index) * 900), mm: value)
        }
    }

    // MARK: 提醒优先级

    func testImportantWeatherAndAirComeBeforeTheRest() {
        let tips = [tip(.cooling, "降温"), tip(.swing, "温差"), tip(.uv, "紫外线"), tip(.wind, "风大"),
                    tip(.air, "空气"), tip(.clothing, "穿衣")]
        XCTAssertEqual(WeatherGlance.prioritized(tips).map(\.kind), [.wind, .air, .cooling, .swing, .uv, .clothing])
        XCTAssertEqual(WeatherGlance.prioritized([tip(.wind, "风"), tip(.rain, "雨")]).map(\.kind), [.wind, .rain])
    }

    func testAirAlertCarriesAQIAndOpensIndices() {
        let tips = [tip(.cooling, "比昨天冷 6 度，加件外套"), tip(.air, "空气较差，出门戴好口罩"),
                    tip(.clothing, "现在 6 度，穿厚外套正合适", "宜穿厚外套")]
        let reminder = WeatherGlance.reminder(tips: tips, aqi: 168)
        XCTAssertEqual(reminder?.style, .alert)
        XCTAssertEqual(reminder?.kind, .air)
        XCTAssertEqual(reminder?.title, "空气质量较差")
        XCTAssertEqual(reminder?.detail, "空气较差，出门戴好口罩")
        XCTAssertEqual(reminder?.aqi, 168)
        XCTAssertEqual(reminder?.aboutAir, true)
        XCTAssertEqual(WeatherGlance.airTitle(128), "空气轻度污染")
    }

    func testRainFirstWithPollutedAirAddsAirLine() {
        let tips = [tip(.rain, "约 40 分钟后有雨，记得带伞"), tip(.air, "空气一般，少在户外久留")]
        let reminder = WeatherGlance.reminder(tips: tips, aqi: 120)
        XCTAssertEqual(reminder?.kind, .rain)
        XCTAssertEqual(reminder?.title, "约 40 分钟后有雨，记得带伞")
        XCTAssertEqual(reminder?.detail, "空气轻度污染 · AQI 120")
        XCTAssertNil(reminder?.aqi)
        XCTAssertEqual(reminder?.aboutAir, true)
    }

    func testOtherAlertTakesNextDifferentKindAsSecondLine() {
        let tips = [tip(.cooling, "明天降温 7 度，记得添衣", "明天降温 7 度"), tip(.uv, "紫外线强，出门注意防晒", "紫外线强，防晒"),
                    tip(.clothing, "现在 6 度，穿厚外套正合适", "宜穿厚外套")]
        let reminder = WeatherGlance.reminder(tips: tips, aqi: 40)
        XCTAssertEqual(reminder?.style, .alert)
        XCTAssertEqual(reminder?.detail, "紫外线强，防晒")
        XCTAssertEqual(reminder?.aboutAir, false)
    }

    func testCalmDayShrinksToOneShortLine() {
        let tips = [tip(.clothing, "现在 6 度，穿厚外套正合适", "宜穿厚外套")]
        let reminder = WeatherGlance.reminder(tips: tips, aqi: 45)
        XCTAssertEqual(reminder?.style, .calm)
        // 不重复大字里的温度。
        XCTAssertEqual(reminder?.title, "宜穿厚外套")
        XCTAssertNil(reminder?.detail)
        XCTAssertNil(reminder?.aqi)
    }

    func testNoTipsNoCard() {
        XCTAssertNil(WeatherGlance.reminder(tips: [], aqi: 200))
    }

    // MARK: 主天气区缺值隐藏

    func testRangeAndFeelsOnlyWithRealValues() {
        XCTAssertEqual(WeatherGlance.rangeLine(high: 9.4, low: -0.4, fahrenheit: false), "最高 9° · 最低 0°")
        XCTAssertNil(WeatherGlance.rangeLine(high: 9, low: nil, fahrenheit: false))
        XCTAssertNil(WeatherGlance.rangeLine(high: nil, low: 0, fahrenheit: false))
        XCTAssertNil(WeatherGlance.rangeLine(high: .nan, low: 0, fahrenheit: false))
        XCTAssertEqual(WeatherGlance.feelsLine(2.6, fahrenheit: false), "体感 3°")
        XCTAssertEqual(WeatherGlance.feelsLine(0, fahrenheit: true), "体感 32°")
        XCTAssertNil(WeatherGlance.feelsLine(nil, fahrenheit: false))
    }

    // MARK: 未来两小时

    func testDryTwoHoursIsOneLine() {
        let glance = WeatherGlance.rain(slots(Array(repeating: 0, count: 9)), now: now)
        XCTAssertEqual(glance?.headline, "暂无明显降水")
        XCTAssertEqual(glance?.showsBars, false)
        XCTAssertEqual(glance?.detail, "")
    }

    func testRainSoonShowsBars() {
        let glance = WeatherGlance.rain(slots([0, 0, 0, 0.3, 0.5, 0, 0, 0, 0]), now: now)
        XCTAssertEqual(glance?.showsBars, true)
        XCTAssertEqual(glance?.headline, "约 40 分钟后有雨")
        XCTAssertEqual(glance?.detail, "持续半小时")
    }

    func testTooLittleDataIsHidden() {
        XCTAssertNil(WeatherGlance.rain([], now: now))
        XCTAssertNil(WeatherGlance.rain(slots([0, 0, 0, 0, 0]), now: now))
        XCTAssertNotNil(WeatherGlance.rain(slots([0, 0, 0, 0, 0, 0]), now: now))
    }

    // MARK: 更新时间

    func testUpdatedToday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let at = calendar.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 14, minute: 10))!
        let later = at.addingTimeInterval(3600)
        XCTAssertEqual(WeatherGlance.updateStatus(updatedAt: at, offline: false, hasData: true, now: later, zone: zone),
                       "14:10 更新")
        let nextDay = at.addingTimeInterval(86_400)
        XCTAssertEqual(WeatherGlance.updateStatus(updatedAt: at, offline: false, hasData: true, now: nextDay,
                                                  zone: zone), "11 月 22 日 14:10 更新")
    }

    func testOfflineSaysCachedAndNothingWithoutData() {
        XCTAssertEqual(WeatherGlance.updateStatus(updatedAt: now, offline: true, hasData: true, now: now, zone: zone),
                       "离线，显示缓存数据")
        XCTAssertNil(WeatherGlance.updateStatus(updatedAt: nil, offline: false, hasData: true, now: now, zone: zone))
        XCTAssertNil(WeatherGlance.updateStatus(updatedAt: now, offline: true, hasData: false, now: now, zone: zone))
    }

    // MARK: 空气质量详情和小卡

    func testAQIDetail() {
        XCTAssertEqual(WeatherGlance.aqiLongLevel(40), "优")
        XCTAssertEqual(WeatherGlance.aqiLongLevel(128), "轻度污染")
        XCTAssertEqual(WeatherGlance.aqiLongLevel(320), "严重污染")
        XCTAssertEqual(WeatherGlance.aqiFraction(150), 0.5, accuracy: 0.0001)
        XCTAssertEqual(WeatherGlance.aqiFraction(480), 1)
        XCTAssertFalse(WeatherGlance.aqiAdvice(160).isEmpty)
    }

    func testWindCard() {
        XCTAssertEqual(WeatherGlance.windCard(speed: 2.5, from: 135), "东南风 2 级")
        XCTAssertEqual(WeatherGlance.windCard(speed: 0.1, from: 0), "无风")
    }
}
