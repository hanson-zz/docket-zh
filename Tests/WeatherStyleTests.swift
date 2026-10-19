import Foundation
import XCTest

/// 天气七个样式并成四个：当前（副标题选项）、多日预报（天数选项）、逐小时、多城市；
/// 旧样式存档迁到新样式加选项；2 小时内有雨时副标题先说雨。
final class WeatherStyleTests: XCTestCase {

    private func config(_ values: [String: WidgetConfig.Value]) -> WidgetConfig { WidgetConfig(values) }

    func testCatalogOffersFourStyles() {
        let variants = WidgetCatalog.entry(.weather)!.variants
        XCTAssertEqual(variants.map(\.title), ["当前", "多日预报", "逐小时预报", "多城市"])
        XCTAssertEqual(variants.map { $0.overrides["layout"] },
                       WeatherStyle.layouts.map { .string($0) })
        // 只有多城市是 Pro。
        XCTAssertEqual(variants.filter { ProFeatures.isPro(.weather, overrides: $0.overrides) }.map(\.title), ["多城市"])
        let made = WidgetCatalog.make(.weather)!
        XCTAssertEqual(WeatherStyle.layout(made.config), "current")
        XCTAssertEqual(WeatherStyle.caption(made.config), .city)
        XCTAssertEqual(WeatherStyle.days(made.config), 7)
    }

    func testOldLayoutsMigrateToNewLayoutAndOption() {
        let cases: [(old: String, layout: String, caption: String?, days: String?)] = [
            ("conditions", "current", "condition", nil),
            ("sky", "current", "sky", nil),
            ("week", "forecast", nil, "7"),
            ("tenDays", "forecast", nil, "10"),
        ]
        for item in cases {
            let old = config(["layout": .string(item.old), "city": .string("杭州"), "fahrenheit": .bool(true)])
            let moved = WeatherStyle.migrating(old)
            XCTAssertEqual(moved.string("layout"), item.layout, item.old)
            XCTAssertEqual(moved.values["caption"], item.caption.map { .string($0) }, item.old)
            XCTAssertEqual(moved.values["days"], item.days.map { .string($0) }, item.old)
            // 其余设置原样保留。
            XCTAssertEqual(moved.string("city"), "杭州", item.old)
            XCTAssertTrue(moved.bool("fahrenheit"), item.old)
            // 迁移前后读出来是同一个样式和选项。
            XCTAssertEqual(WeatherStyle.layout(old), WeatherStyle.layout(moved), item.old)
            XCTAssertEqual(WeatherStyle.caption(old), WeatherStyle.caption(moved), item.old)
            XCTAssertEqual(WeatherStyle.days(old), WeatherStyle.days(moved), item.old)
            // 迁一次就够，再迁不变。
            XCTAssertEqual(WeatherStyle.migrating(moved), moved, item.old)
        }
        // 新样式和没存样式的不动。
        for layout in ["current", "forecast", "hourly", "cities"] {
            let c = config(["layout": .string(layout)])
            XCTAssertEqual(WeatherStyle.migrating(c), c, layout)
        }
        XCTAssertEqual(WeatherStyle.migrating(WidgetConfig()), WidgetConfig())
    }

    func testSavedOldWidgetDecodesAsNewStyle() throws {
        let saved = WidgetInstance(kind: .weather, expanded: true,
                                   config: config(["layout": .string("tenDays"), "city": .string("Oslo")]))
        let data = try JSONEncoder().encode(saved)
        let back = try JSONDecoder().decode(WidgetInstance.self, from: data)
        XCTAssertEqual(back.id, saved.id)
        XCTAssertEqual(back.config.string("layout"), "forecast")
        XCTAssertEqual(back.config.string("days"), "10")
        XCTAssertEqual(back.config.string("city"), "Oslo")
        XCTAssertEqual(WidgetCatalog.variantTitle(matching: back.config, kind: .weather), "多日预报")
        // 卡片尺寸和迁移前一样。
        XCTAssertEqual(WidgetCatalog.naturalSize(back), WidgetCatalog.naturalSize(saved))
        XCTAssertEqual(WidgetCatalog.verticalHeight(back), WidgetCatalog.verticalHeight(saved))

        let sky = WidgetInstance(kind: .weather, expanded: true, config: config(["layout": .string("sky")]))
        let skyBack = try JSONDecoder().decode(WidgetInstance.self, from: JSONEncoder().encode(sky))
        XCTAssertEqual(skyBack.config.string("layout"), "current")
        XCTAssertEqual(WeatherStyle.caption(skyBack.config), .sky)
        XCTAssertEqual(WidgetCatalog.naturalSize(skyBack), CGSize(width: 196, height: 132), "风与日出日落照旧 196 宽")
        let conditions = WidgetInstance(kind: .weather, expanded: true, config: config(["layout": .string("conditions")]))
        let conditionsBack = try JSONDecoder().decode(WidgetInstance.self, from: JSONEncoder().encode(conditions))
        XCTAssertEqual(WidgetCatalog.naturalSize(conditionsBack), CGSize(width: 148, height: 132))
    }

    func testOptionsFollowTheLayout() {
        let current = config(["layout": .string("current")])
        XCTAssertTrue(WidgetCatalog.applies("caption", to: current, kind: .weather))
        XCTAssertFalse(WidgetCatalog.applies("days", to: current, kind: .weather))
        let forecast = config(["layout": .string("forecast")])
        XCTAssertTrue(WidgetCatalog.applies("days", to: forecast, kind: .weather))
        XCTAssertFalse(WidgetCatalog.applies("caption", to: forecast, kind: .weather))
        XCTAssertTrue(WidgetCatalog.applies("city", to: forecast, kind: .weather))
        for layout in ["hourly", "cities"] {
            let c = config(["layout": .string(layout)])
            XCTAssertFalse(WidgetCatalog.applies("caption", to: c, kind: .weather), layout)
            XCTAssertFalse(WidgetCatalog.applies("days", to: c, kind: .weather), layout)
        }
        // 还存着旧值的卡片也按新样式给选项。
        XCTAssertTrue(WidgetCatalog.applies("caption", to: config(["layout": .string("sky")]), kind: .weather))
        XCTAssertTrue(WidgetCatalog.applies("days", to: config(["layout": .string("week")]), kind: .weather))
    }

    func testCaptionAndDaysReadTolerantly() {
        XCTAssertEqual(WeatherStyle.caption(config(["caption": .string("wind")])), .wind)
        XCTAssertEqual(WeatherStyle.caption(config(["caption": .string("nope")])), .city)
        XCTAssertEqual(WeatherStyle.days(config(["layout": .string("forecast"), "days": .string("10")])), 10)
        XCTAssertEqual(WeatherStyle.days(config(["layout": .string("forecast"), "days": .string("5")])), 7)
        XCTAssertEqual(WeatherStyle.layout(config(["layout": .string("spiral")])), "current")
        XCTAssertEqual(WeatherStyle.columnDays(config(["days": .string("10")])), 7)
        XCTAssertEqual(WeatherStyle.columnDays(config(["days": .string("7")])), 5)
        XCTAssertTrue(WeatherStyle.Caption.sky.showsWind && WeatherStyle.Caption.sky.showsSun)
        XCTAssertTrue(WeatherStyle.Caption.wind.showsWind && !WeatherStyle.Caption.wind.showsSun)
        XCTAssertTrue(!WeatherStyle.Caption.sun.showsWind && WeatherStyle.Caption.sun.showsSun)
        XCTAssertFalse(WeatherStyle.Caption.city.showsWind || WeatherStyle.Caption.condition.showsSun)
        XCTAssertEqual(WeatherStyle.Caption.allCases.count, 5)
        XCTAssertEqual(WeatherStyle.dayChoices, [7, 10])
        // 10 天比 7 天宽，竖排更高。
        let ten = config(["layout": .string("forecast"), "days": .string("10")])
        let seven = config(["layout": .string("forecast"), "days": .string("7")])
        XCTAssertGreaterThan(WeatherLayout.forecastWidth(ten), WeatherLayout.forecastWidth(seven))
        XCTAssertGreaterThan(WeatherLayout.forecastColumnHeight(ten), WeatherLayout.forecastColumnHeight(seven))
    }

    // MARK: 快下雨了

    func testRainWithinTwoHoursComesFirst() {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        func hour(_ minutes: Double, _ mm: Double) -> (start: Date, mm: Double) {
            (start: now.addingTimeInterval(minutes * 60), mm: mm)
        }
        // 23 分钟后那一小时有雨：取整到 5 分钟。
        XCTAssertEqual(WeatherStyle.minutesUntilRain(now: now, currentHourMM: 0,
                                                     hours: [hour(23, 0.4), hour(83, 1)]), 25)
        // 先干后湿：取第一个有雨的小时。
        XCTAssertEqual(WeatherStyle.minutesUntilRain(now: now, currentHourMM: 0,
                                                     hours: [hour(38, 0), hour(98, 0.2)]), 100)
        // 不按顺序给也一样。
        XCTAssertEqual(WeatherStyle.minutesUntilRain(now: now, currentHourMM: nil,
                                                     hours: [hour(98, 0.2), hour(38, 0.3)]), 40)
        // 很快就下也至少写 5 分钟。
        XCTAssertEqual(WeatherStyle.minutesUntilRain(now: now, currentHourMM: 0, hours: [hour(1, 2)]), 5)
        // 正好 2 小时算，超过 2 小时不算。
        XCTAssertEqual(WeatherStyle.minutesUntilRain(now: now, currentHourMM: 0, hours: [hour(120, 1)]), 120)
        XCTAssertNil(WeatherStyle.minutesUntilRain(now: now, currentHourMM: 0, hours: [hour(121, 1)]))
        // 毛毛雨不到门槛、过去的小时、空数据都不算。
        XCTAssertNil(WeatherStyle.minutesUntilRain(now: now, currentHourMM: 0, hours: [hour(30, 0.05)]))
        XCTAssertNil(WeatherStyle.minutesUntilRain(now: now, currentHourMM: 0, hours: [hour(-30, 3)]))
        XCTAssertNil(WeatherStyle.minutesUntilRain(now: now, currentHourMM: 0, hours: []))
        // 现在已经在下：不说“多少分钟后有雨”。
        XCTAssertNil(WeatherStyle.minutesUntilRain(now: now, currentHourMM: 0.8, hours: [hour(20, 1)]))
        XCTAssertEqual(WeatherStyle.rainSoonText(minutes: 40), "约 40 分钟后有雨")
        XCTAssertEqual(WeatherStyle.rainSoonShortText(minutes: 40), "40 分钟后雨")
    }
}
