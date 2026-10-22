import XCTest

/// 天气多城市样式的城市列表（面板「编辑」里增删排序）和单城市面板“当前位置”不可删。
final class WeatherCityListTests: XCTestCase {

    // MARK: 读写

    func testListTrimsDedupesAndFallsBack() {
        XCTAssertEqual(WeatherCityList.list([" 北京 ", "", "beijing", "Beijing", "上海"]),
                       ["北京", "beijing", "上海"])
        XCTAssertEqual(WeatherCityList.list([]), WeatherLayout.defaultCities)
        XCTAssertEqual(WeatherCityList.list(["  ", "\n"]), WeatherLayout.defaultCities)
        XCTAssertEqual(WeatherCityList.list(WidgetConfig()), WeatherLayout.defaultCities)
    }

    func testListKeepsMoreThanTheTileButCaps() {
        let raw = (0..<12).map { "城市\($0)" }
        let list = WeatherCityList.list(raw)
        XCTAssertEqual(list.count, WeatherCityList.maxCount)
        XCTAssertEqual(list.first, "城市0")
        // 卡片仍只取前 3 个，和面板列表的前 3 个一致。
        XCTAssertEqual(WeatherLayout.cities(list), Array(list.prefix(WeatherCityList.tileCount)))
    }

    func testWriteRoundTripsAndIgnoresEmpty() {
        var config = WidgetConfig()
        WeatherCityList.write(["杭州", " 杭州", "成都", "深圳", "厦门"], to: &config)
        XCTAssertEqual(config.strings(WeatherCityList.key), ["杭州", "成都", "深圳", "厦门"])
        XCTAssertEqual(WeatherCityList.list(config), ["杭州", "成都", "深圳", "厦门"])
        WeatherCityList.write([], to: &config)
        XCTAssertEqual(WeatherCityList.list(config), ["杭州", "成都", "深圳", "厦门"], "空列表不写")
    }

    func testTileShowsTheFirstThree() {
        XCTAssertEqual(WeatherCityList.tileCount, 3)
        XCTAssertTrue(WeatherCityList.isOnTile(0))
        XCTAssertTrue(WeatherCityList.isOnTile(2))
        XCTAssertFalse(WeatherCityList.isOnTile(3))
        XCTAssertFalse(WeatherCityList.isOnTile(-1))
    }

    // MARK: 增删排序

    func testAddSkipsBlanksAndDuplicates() {
        var list = ["北京"]
        list = WeatherCityList.adding(" 上海 ", to: list)
        list = WeatherCityList.adding("上海", to: list)
        list = WeatherCityList.adding("BEIJING", to: list)
        list = WeatherCityList.adding("beijing", to: list)
        list = WeatherCityList.adding("   ", to: list)
        XCTAssertEqual(list, ["北京", "上海", "BEIJING"])
        XCTAssertFalse(WeatherCityList.canAdd("北京", to: list))
        XCTAssertFalse(WeatherCityList.canAdd("", to: list))
        XCTAssertTrue(WeatherCityList.contains(" 上海", in: list))
    }

    func testAddStopsAtTheCap() {
        var list = ["北京"]
        for index in 0..<20 { list = WeatherCityList.adding("城市\(index)", to: list) }
        XCTAssertEqual(list.count, WeatherCityList.maxCount)
        XCTAssertFalse(WeatherCityList.canAdd("又一个", to: list))
        XCTAssertEqual(WeatherCityList.adding("又一个", to: list), list)
    }

    func testRemoveKeepsAtLeastOne() {
        let list = ["北京", "上海", "广州"]
        XCTAssertEqual(WeatherCityList.removing(at: 1, from: list), ["北京", "广州"])
        XCTAssertEqual(WeatherCityList.removing(at: 9, from: list), list)
        XCTAssertEqual(WeatherCityList.removing(at: 0, from: ["北京"]), ["北京"])
        XCTAssertFalse(WeatherCityList.canRemove(at: 0, in: ["北京"]))
        XCTAssertTrue(WeatherCityList.canRemove(at: 0, in: list))
    }

    func testMoveAndDrop() {
        let list = ["北京", "上海", "广州", "深圳"]
        XCTAssertEqual(WeatherCityList.moving(from: 3, to: 0, in: list), ["深圳", "北京", "上海", "广州"])
        XCTAssertEqual(WeatherCityList.moving(from: 0, to: 99, in: list), ["上海", "广州", "深圳", "北京"])
        XCTAssertEqual(WeatherCityList.moving(from: 7, to: 0, in: list), list)
        XCTAssertEqual(WeatherCityList.dropIndex(from: 0, translation: 104, rowHeight: 50, count: 4), 2)
        XCTAssertEqual(WeatherCityList.dropIndex(from: 3, translation: -400, rowHeight: 50, count: 4), 0)
        XCTAssertEqual(WeatherCityList.dropIndex(from: 1, translation: 20, rowHeight: 50, count: 4), 1)
    }

    // MARK: 单城市面板：当前位置保留

    func testCurrentLocationCannotBeRemoved() {
        let list = ["", "北京", "深圳"]
        XCTAssertFalse(WeatherPlaces.canRemove(at: 0, in: list))
        XCTAssertEqual(WeatherPlaces.removing(at: 0, from: list), list)
        XCTAssertTrue(WeatherPlaces.canRemove(at: 1, in: list))
        XCTAssertEqual(WeatherPlaces.removing(at: 1, from: list), ["", "深圳"])
        // 挪到后面也一样不能删。
        let moved = WeatherPlaces.moving(from: 0, to: 2, in: list)
        XCTAssertFalse(WeatherPlaces.canRemove(at: 2, in: moved))
        XCTAssertFalse(WeatherPlaces.canRemove(at: 0, in: ["北京"]))
    }

    func testCurrentLocationCanBeAddedBack() {
        let list = ["北京", "深圳"]
        XCTAssertFalse(WeatherPlaces.hasCurrentLocation(list))
        XCTAssertTrue(WeatherPlaces.canAdd(WeatherPlaces.currentLocation, to: list))
        let back = WeatherPlaces.adding(WeatherPlaces.currentLocation, to: list)
        XCTAssertEqual(back, ["北京", "深圳", ""])
        XCTAssertTrue(WeatherPlaces.hasCurrentLocation(back))
        XCTAssertFalse(WeatherPlaces.canAdd(WeatherPlaces.currentLocation, to: back))
    }
}
