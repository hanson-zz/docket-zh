import XCTest

/// 世界时钟多城市：存储迁移、编码往返、增删排序、时差和昼夜文案、城市表和地标映射。
final class WorldClockListTests: XCTestCase {
    private let shanghai = TimeZone(identifier: "Asia/Shanghai")!
    /// 2026-10-20 周二 10:18 北京时间（伦敦还在夏令时，纽约是前一天晚上）。
    private let sample = Date(timeIntervalSince1970: 1_792_462_680)

    private func city(_ id: String) -> WorldCity {
        guard let city = WorldCities.city(id: id) else {
            XCTFail("内置表里没有 \(id)")
            return WorldCity(name: id, zone: "UTC")
        }
        return city
    }

    func testSampleIsTuesdayMorningInBeijing() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = shanghai
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: sample)
        XCTAssertEqual([parts.year, parts.month, parts.day, parts.hour, parts.minute], [2026, 10, 20, 10, 18])
        XCTAssertEqual(parts.weekday, 3)
    }

    // MARK: 存储迁移

    func testNoCitiesKeyFallsBackToLegacyZoneAndCity() {
        let empty = WidgetConfig()
        XCTAssertEqual(WorldClockList.cities(empty).map(\.id), ["london"])

        let legacy = WidgetConfig(["zone": .string("Asia/Tokyo"), "city": .string("东京")])
        let list = WorldClockList.cities(legacy)
        XCTAssertEqual(list.map(\.id), ["tokyo"])
        XCTAssertEqual(list.first?.landmark, .tokyoTower)

        // 旧卡片手改过的名字原样保留。
        let custom = WidgetConfig(["zone": .string("Asia/Tokyo"), "city": .string("公司")])
        XCTAssertEqual(WorldClockList.cities(custom).first?.name, "公司")
        XCTAssertEqual(WorldClockList.cities(custom).first?.zone, "Asia/Tokyo")

        // 时区认不出时退回伦敦，不画空卡片。
        let broken = WidgetConfig(["zone": .string("Nowhere/Land"), "city": .string("x")])
        XCTAssertEqual(WorldClockList.cities(broken).map(\.id), ["london"])
    }

    func testEmptyOrUnreadableListFallsBackToLegacy() {
        let config = WidgetConfig(["zone": .string("Europe/Paris"), "city": .string("巴黎"),
                                   WorldClockList.key: .list([.string("Nowhere/Land|x"), .string("")])])
        XCTAssertEqual(WorldClockList.cities(config).map(\.id), ["paris"])
    }

    func testWriteSyncsFirstCityBackToZoneAndCity() {
        var config = WidgetConfig(["zone": .string("Europe/London"), "city": .string("伦敦")])
        WorldClockList.write([city("newyork"), city("tokyo")], to: &config)
        XCTAssertEqual(config.strings(WorldClockList.key), ["America/New_York|纽约", "Asia/Tokyo|东京"])
        XCTAssertEqual(config.string("zone"), "America/New_York")
        XCTAssertEqual(config.string("city"), "纽约")
        XCTAssertEqual(WorldClockList.cities(config).map(\.id), ["newyork", "tokyo"])
    }

    func testWriteKeepsOneToTwelveWithoutDuplicates() {
        var config = WidgetConfig()
        WorldClockList.write([], to: &config)
        XCTAssertNil(config.values[WorldClockList.key], "空列表不写")

        let many = Array(WorldCities.all.prefix(20))
        WorldClockList.write(many + [many[0]], to: &config)
        XCTAssertEqual(config.strings(WorldClockList.key).count, WorldClockList.maxCount)

        WorldClockList.write([city("paris"), city("paris"), city("rome")], to: &config)
        XCTAssertEqual(WorldClockList.cities(config).map(\.id), ["paris", "rome"])
    }

    func testStoredDuplicatesAndOverflowAreTrimmedOnRead() {
        let raw = (WorldCities.all.prefix(14) + WorldCities.all.prefix(2)).map { WidgetConfig.Value.string($0.storageKey) }
        let config = WidgetConfig([WorldClockList.key: .list(Array(raw))])
        let list = WorldClockList.cities(config)
        XCTAssertEqual(list.count, 12)
        XCTAssertEqual(Set(list.map(\.id)).count, 12)
    }

    // MARK: 编码往返

    func testStorageRoundTripForEveryBuiltInCity() {
        for city in WorldCities.all {
            XCTAssertEqual(WorldCity(storage: city.storageKey), city, city.id)
        }
    }

    func testStorageReadsNamesFromAnyLanguage() {
        XCTAssertEqual(WorldCity(storage: "Asia/Shanghai|Beijing")?.id, "beijing")
        XCTAssertEqual(WorldCity(storage: "Asia/Shanghai|上海")?.id, "shanghai")
        XCTAssertEqual(WorldCity(storage: "Asia/Shanghai|上海")?.landmark, .orientalPearl)
        XCTAssertNil(WorldCity(storage: "Nowhere/Land|x"))
        XCTAssertNil(WorldCity(storage: "|伦敦"))
        XCTAssertEqual(WorldCity(storage: "Asia/Kolkata")?.name, "Kolkata")
    }

    func testSystemZoneRoundTripKeepsItsIdentity() {
        let found = WorldCities.search("Bahia", systemZones: ["America/Bahia"])
        guard let bahia = found.first(where: { $0.zone == "America/Bahia" }) else {
            return XCTFail("系统时区 America/Bahia 应能搜到")
        }
        XCTAssertFalse(bahia.isBuiltIn)
        XCTAssertEqual(bahia.landmark, .skyline)
        let decoded = WorldCity(storage: bahia.storageKey)
        XCTAssertEqual(decoded?.id, bahia.id)
        XCTAssertTrue(WorldClockList.contains(bahia, in: [decoded!]))
    }

    func testClockPanelCitiesUseTheSameEncoding() {
        var config = WidgetConfig()
        ClockPanelData.set(city("shanghai"), at: 0, in: &config)
        XCTAssertEqual(config.strings(ClockPanelData.citiesKey).first, city("shanghai").storageKey)
        XCTAssertEqual(ClockPanelData.cities(config).first?.id, "shanghai")
        XCTAssertEqual(ClockPanelData.defaultCities.map(\.id), ["london", "newyork", "tokyo"])
    }

    // MARK: 增删排序

    func testAddRemoveMove() {
        let list = [city("beijing"), city("london"), city("tokyo")]
        XCTAssertEqual(WorldClockList.adding(city("paris"), to: list).map(\.id), ["beijing", "london", "tokyo", "paris"])
        XCTAssertEqual(WorldClockList.adding(city("london"), to: list), list, "已添加的不重复")
        let full = Array(WorldCities.all.prefix(12))
        XCTAssertEqual(WorldClockList.adding(city("tahiti"), to: full).count, 12, "最多 12 个")

        XCTAssertEqual(WorldClockList.removing(at: 1, from: list).map(\.id), ["beijing", "tokyo"])
        XCTAssertEqual(WorldClockList.removing(at: 0, from: [city("beijing")]).map(\.id), ["beijing"], "至少留 1 个")
        XCTAssertEqual(WorldClockList.removing(at: 9, from: list), list)

        XCTAssertEqual(WorldClockList.moving(from: 2, to: 0, in: list).map(\.id), ["tokyo", "beijing", "london"])
        XCTAssertEqual(WorldClockList.moving(from: 0, to: 9, in: list).map(\.id), ["london", "tokyo", "beijing"])
        XCTAssertEqual(WorldClockList.moving(from: 1, to: 1, in: list), list)
    }

    func testDropIndexRoundsToNearestRow() {
        XCTAssertEqual(WorldClockList.dropIndex(from: 2, translation: -24, rowHeight: 50, count: 6), 2)
        XCTAssertEqual(WorldClockList.dropIndex(from: 2, translation: -26, rowHeight: 50, count: 6), 1)
        XCTAssertEqual(WorldClockList.dropIndex(from: 2, translation: 140, rowHeight: 50, count: 6), 5)
        XCTAssertEqual(WorldClockList.dropIndex(from: 2, translation: -500, rowHeight: 50, count: 6), 0)
        XCTAssertEqual(WorldClockList.dropIndex(from: 2, translation: 900, rowHeight: 50, count: 6), 5)
    }

    func testTileShowsFirstThreeAndColumnGrows() {
        var config = WidgetConfig()
        XCTAssertEqual(WorldClockList.verticalHeight(config), 76)
        WorldClockList.write([city("london"), city("newyork")], to: &config)
        XCTAssertEqual(WorldClockList.verticalHeight(config), 112)
        WorldClockList.write([city("london"), city("newyork"), city("tokyo"), city("paris"), city("sydney")],
                             to: &config)
        XCTAssertEqual(WorldClockList.tileCities(config).map(\.id), ["london", "newyork", "tokyo"])
        XCTAssertEqual(WorldClockList.verticalHeight(config), 164)
        let instance = WidgetInstance(kind: .world, expanded: true, config: config)
        XCTAssertEqual(WidgetCatalog.verticalHeight(instance), 164)
    }

    // MARK: 时差文案

    func testDifferenceText() {
        XCTAssertEqual(WorldClockText.difference(-7 * 3600, reference: "北京"), "比北京晚 7 小时")
        XCTAssertEqual(WorldClockText.difference(3600, reference: "北京"), "比北京早 1 小时")
        XCTAssertEqual(WorldClockText.difference(-(5 * 3600 + 1800), reference: "北京"), "比北京晚 5 小时 30 分")
        XCTAssertEqual(WorldClockText.difference(45 * 60, reference: "本地"), "比本地早 45 分")
        XCTAssertEqual(WorldClockText.difference(0, reference: "北京"), "与北京相同")
    }

    func testOffsetLineAgainstBeijing() {
        func line(_ id: String) -> String { WorldClockText.offsetLine(city(id), now: sample, here: shanghai) }
        XCTAssertEqual(line("beijing"), "此处")
        XCTAssertEqual(line("shanghai"), "与北京相同")
        XCTAssertEqual(line("london"), "比北京晚 7 小时")
        XCTAssertEqual(line("newyork"), "比北京晚 12 小时")
        XCTAssertEqual(line("tokyo"), "比北京早 1 小时")
        XCTAssertEqual(line("sydney"), "比北京早 3 小时")
        XCTAssertEqual(line("newdelhi"), "比北京晚 2 小时 30 分")
        XCTAssertEqual(line("kathmandu"), "比北京晚 2 小时 15 分")
    }

    func testReferenceIsFirstCityOfLocalZoneOrLocal() {
        XCTAssertEqual(WorldCities.reference(here: shanghai)?.id, "beijing")
        XCTAssertEqual(WorldCities.reference(here: TimeZone(identifier: "America/Los_Angeles")!)?.id, "losangeles")
        let chatham = TimeZone(identifier: "Pacific/Chatham")!
        XCTAssertNil(WorldCities.reference(here: chatham))
        XCTAssertEqual(WorldCities.referenceName(here: chatham), "本地")
        XCTAssertTrue(WorldClockText.offsetLine(city("london"), now: sample, here: chatham).hasPrefix("比本地晚"))
        XCTAssertEqual(WorldClockText.header(time: "10:18", count: 6, here: shanghai), "此处 北京 10:18 · 6 个城市")
    }

    // MARK: 昼夜

    func testDayPartBoundaries() {
        XCTAssertEqual(WorldClockText.dayPart(hour: 0), "凌晨")
        XCTAssertEqual(WorldClockText.dayPart(hour: 4), "凌晨")
        XCTAssertEqual(WorldClockText.dayPart(hour: 5), "清晨")
        XCTAssertEqual(WorldClockText.dayPart(hour: 8), "上午")
        XCTAssertEqual(WorldClockText.dayPart(hour: 11), "中午")
        XCTAssertEqual(WorldClockText.dayPart(hour: 13), "下午")
        XCTAssertEqual(WorldClockText.dayPart(hour: 17), "傍晚")
        XCTAssertEqual(WorldClockText.dayPart(hour: 19), "晚上")
        XCTAssertEqual(WorldClockText.dayPart(hour: 23), "晚上")
    }

    func testDayLineAndDaytime() {
        func zone(_ id: String) -> TimeZone { city(id).timeZone! }
        XCTAssertEqual(WorldClockText.dayLine(zone("beijing"), now: sample, here: shanghai), "周二 · 上午")
        XCTAssertEqual(WorldClockText.dayLine(zone("london"), now: sample, here: shanghai), "周二 · 凌晨")
        XCTAssertEqual(WorldClockText.dayLine(zone("newyork"), now: sample, here: shanghai), "昨天 · 晚上")
        XCTAssertEqual(WorldClockText.dayLine(zone("tokyo"), now: sample, here: shanghai), "周二 · 中午")
        XCTAssertEqual(WorldClockText.dayLine(zone("auckland"), now: sample, here: shanghai), "周二 · 下午")
        XCTAssertTrue(WorldClockText.isDaytime(zone("beijing"), now: sample))
        XCTAssertFalse(WorldClockText.isDaytime(zone("london"), now: sample))
        XCTAssertFalse(WorldClockText.isDaytime(zone("newyork"), now: sample))
        XCTAssertEqual(WorldClockText.weekdayName(1), "周日")
        XCTAssertEqual(WorldClockText.weekdayName(7), "周六")
    }

    // MARK: 城市表和地标

    func testCityTableIsWellFormed() {
        let all = WorldCities.all
        XCTAssertGreaterThanOrEqual(all.count, 150)
        XCTAssertEqual(Set(all.map(\.id)).count, all.count, "id 不重复")
        XCTAssertEqual(Set(all.map(\.name)).count, all.count, "中文名不重复")
        XCTAssertEqual(Set(all.map(\.english)).count, all.count, "英文名不重复")
        for city in all {
            XCTAssertNotNil(TimeZone(identifier: city.zone), "\(city.id) \(city.zone)")
            XCTAssertTrue(city.isBuiltIn, city.id)
            XCTAssertFalse(city.english.isEmpty, city.id)
            XCTAssertFalse(city.region.isEmpty, city.id)
            XCTAssertTrue(city.id.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber) }, city.id)
        }
        for id in WorldCities.commonIDs { XCTAssertNotNil(WorldCities.city(id: id), id) }
    }

    func testLandmarksMapByCityNotZone() {
        let expected: [String: CityLandmark] = [
            "beijing": .templeOfHeaven, "shanghai": .orientalPearl, "london": .bigBen,
            "newyork": .empireState, "tokyo": .tokyoTower, "paris": .eiffelTower,
            "sydney": .sydneyOpera, "dubai": .burjKhalifa, "singapore": .marinaBaySands,
        ]
        for (id, landmark) in expected { XCTAssertEqual(city(id).landmark, landmark, id) }
        XCTAssertEqual(city("beijing").zone, city("shanghai").zone)
        XCTAssertNotEqual(city("beijing").landmark, city("shanghai").landmark)
        for city in WorldCities.all where expected[city.id] == nil {
            XCTAssertEqual(city.landmark, .skyline, city.id)
        }
        XCTAssertEqual(Set(WorldCities.all.map(\.landmark)), Set(CityLandmark.allCases))
    }

    func testSearchByEnglishPinyinCountryAndZone() {
        XCTAssertEqual(WorldCities.search("Barcelona").first?.id, "barcelona")
        XCTAssertEqual(WorldCities.search("basailuona").first?.id, "barcelona")
        XCTAssertEqual(WorldCities.search("Sao Paulo").first?.id, "saopaulo")
        XCTAssertTrue(WorldCities.search("西班牙").contains { $0.id == "madrid" })
        XCTAssertTrue(WorldCities.search("Europe/Madrid").contains { $0.id == "barcelona" })
        XCTAssertEqual(WorldCities.search("Beijing").first?.id, "beijing")
    }
}
