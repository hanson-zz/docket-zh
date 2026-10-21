import XCTest

/// 天气面板左右滑换城市（距离和速度门槛、方向、到头不循环、回弹）和顶部短地名。
final class WeatherCitySwipeTests: XCTestCase {

    // MARK: 判断

    func testFarEnoughLeftIsNextRightIsPrevious() {
        XCTAssertEqual(WeatherCitySwipe.decision(dx: -60, dy: 0), 1)
        XCTAssertEqual(WeatherCitySwipe.decision(dx: 60, dy: 4), -1)
    }

    func testShortSlowDragDoesNothing() {
        XCTAssertNil(WeatherCitySwipe.decision(dx: -30, dy: 0, velocity: -100))
        XCTAssertNil(WeatherCitySwipe.decision(dx: 0, dy: 0))
    }

    func testFlickCountsWhenFastEnough() {
        XCTAssertEqual(WeatherCitySwipe.decision(dx: -20, dy: 0, velocity: -600), 1)
        XCTAssertEqual(WeatherCitySwipe.decision(dx: 20, dy: 0, velocity: 600), -1)
        // 太短的甩不算；速度和位移反向（甩完往回拉）也不算。
        XCTAssertNil(WeatherCitySwipe.decision(dx: -10, dy: 0, velocity: -900))
        XCTAssertNil(WeatherCitySwipe.decision(dx: -20, dy: 0, velocity: 600))
    }

    func testMostlyVerticalIsIgnored() {
        XCTAssertNil(WeatherCitySwipe.decision(dx: -80, dy: 70))
        XCTAssertEqual(WeatherCitySwipe.decision(dx: -80, dy: 50), 1)
    }

    func testNonFiniteIsIgnored() {
        XCTAssertNil(WeatherCitySwipe.decision(dx: .nan, dy: 0))
        XCTAssertNil(WeatherCitySwipe.decision(dx: -80, dy: .infinity))
    }

    // MARK: 边界

    func testTargetStopsAtEndsWithoutWrapping() {
        XCTAssertEqual(WeatherCitySwipe.target(current: 0, step: 1, count: 3), 1)
        XCTAssertEqual(WeatherCitySwipe.target(current: 1, step: -1, count: 3), 0)
        XCTAssertNil(WeatherCitySwipe.target(current: 2, step: 1, count: 3))
        XCTAssertNil(WeatherCitySwipe.target(current: 0, step: -1, count: 3))
        XCTAssertNil(WeatherCitySwipe.target(current: 0, step: 1, count: 1))
        XCTAssertNil(WeatherCitySwipe.target(current: 0, step: 1, count: 0))
        XCTAssertNil(WeatherCitySwipe.target(current: 0, step: 0, count: 3))
    }

    func testOffsetFollowsWhereItCanMoveAndRubberBandsAtEnds() {
        // 中间：跟手四分之一，封顶。
        XCTAssertEqual(WeatherCitySwipe.offset(dx: -40, current: 1, count: 3), -10, accuracy: 0.001)
        XCTAssertEqual(WeatherCitySwipe.offset(dx: -400, current: 1, count: 3),
                       -WeatherCitySwipe.followLimit, accuracy: 0.001)
        // 第一个往右拉、最后一个往左拉：回弹，永远小于上限。
        let edge = WeatherCitySwipe.offset(dx: 400, current: 0, count: 3)
        XCTAssertGreaterThan(edge, 0)
        XCTAssertLessThan(edge, WeatherCitySwipe.edgeLimit)
        let last = WeatherCitySwipe.offset(dx: -400, current: 2, count: 3)
        XCTAssertLessThan(last, 0)
        XCTAssertGreaterThan(last, -WeatherCitySwipe.edgeLimit)
        // 越拉越紧。
        XCTAssertLessThan(WeatherCitySwipe.offset(dx: 40, current: 0, count: 3),
                          WeatherCitySwipe.offset(dx: 80, current: 0, count: 3))
        XCTAssertEqual(WeatherCitySwipe.offset(dx: 0, current: 0, count: 3), 0)
        // 只有一个城市：两边都只回弹。
        XCTAssertLessThan(abs(WeatherCitySwipe.offset(dx: -400, current: 0, count: 1)),
                          WeatherCitySwipe.edgeLimit)
    }

    func testDotHitAreaIsAtLeast24() {
        XCTAssertGreaterThanOrEqual(WeatherCitySwipe.dotHitSize, 24)
    }

    // MARK: 触控板一次滑动

    func testTrackerHorizontalSwipeSwitchesOnce() {
        var tracker = WeatherCitySwipe.Tracker()
        var time = 0.0
        for _ in 0..<10 {
            tracker.feed(dx: -8, dy: 0.5, at: time)
            time += 0.016
        }
        XCTAssertEqual(tracker.axis, .horizontal)
        XCTAssertEqual(tracker.translation, -80, accuracy: 0.001)
        XCTAssertEqual(tracker.end(), 1)
        // end 之后清零。
        XCTAssertEqual(tracker.axis, .undecided)
        XCTAssertNil(tracker.end())
    }

    func testTrackerVerticalScrollNeverSwitches() {
        var tracker = WeatherCitySwipe.Tracker()
        tracker.feed(dx: 1, dy: 10, at: 0)
        XCTAssertEqual(tracker.axis, .vertical)
        // 定成竖向后再横着拖也不算。
        for step in 1...10 { tracker.feed(dx: -20, dy: 0, at: Double(step) * 0.016) }
        XCTAssertEqual(tracker.translation, 0)
        XCTAssertNil(tracker.end())
    }

    func testTrackerQuickFlick() {
        var tracker = WeatherCitySwipe.Tracker()
        tracker.feed(dx: 9, dy: 0, at: 0)
        tracker.feed(dx: 9, dy: 0, at: 0.02)
        tracker.feed(dx: 9, dy: 0, at: 0.04)
        XCTAssertGreaterThan(tracker.velocity, WeatherCitySwipe.velocityThreshold)
        XCTAssertEqual(tracker.end(), -1)
    }

    func testTrackerSmallWiggleDoesNothing() {
        var tracker = WeatherCitySwipe.Tracker()
        tracker.feed(dx: -3, dy: 1, at: 0)
        tracker.feed(dx: 2, dy: 0, at: 0.3)
        XCTAssertEqual(tracker.axis, .undecided)
        XCTAssertNil(tracker.end())
    }

    // MARK: 短地名

    func testChineseFullAddressBecomesCity() {
        XCTAssertEqual(PlaceName.short("中国河北省石家庄市长安区"), "石家庄")
        XCTAssertEqual(PlaceName.short("中国河北省石家庄市"), "石家庄")
        XCTAssertEqual(PlaceName.short("河北省石家庄市"), "石家庄")
        XCTAssertEqual(PlaceName.short("中国广东省深圳市南山区"), "深圳")
        XCTAssertEqual(PlaceName.short("中国广东省广州市"), "广州")
        XCTAssertEqual(PlaceName.short("中国新疆维吾尔自治区乌鲁木齐市"), "乌鲁木齐")
        XCTAssertEqual(PlaceName.short("内蒙古自治区呼和浩特市"), "呼和浩特")
    }

    func testMunicipalitiesAndSpecialRegions() {
        XCTAssertEqual(PlaceName.short("中国北京市朝阳区"), "北京")
        XCTAssertEqual(PlaceName.short("上海市"), "上海")
        XCTAssertEqual(PlaceName.short("中国重庆市渝中区"), "重庆")
        XCTAssertEqual(PlaceName.short("香港特别行政区"), "香港")
    }

    func testCountyWithoutCity() {
        XCTAssertEqual(PlaceName.short("中国河北省正定县"), "正定")
    }

    func testAlreadyShortOrWesternNamesStay() {
        XCTAssertEqual(PlaceName.short("北京"), "北京")
        XCTAssertEqual(PlaceName.short("石家庄"), "石家庄")
        XCTAssertEqual(PlaceName.short("Oslo"), "Oslo")
        XCTAssertEqual(PlaceName.short("Mumbai, Maharashtra"), "Mumbai")
        XCTAssertEqual(PlaceName.short("  奥斯陆 "), "奥斯陆")
        XCTAssertEqual(PlaceName.short(""), "")
    }

    func testTooltipOnlyWhenShortened() {
        XCTAssertEqual(PlaceName.tooltip("中国河北省石家庄市长安区"), "中国河北省石家庄市长安区")
        XCTAssertNil(PlaceName.tooltip("北京"))
        XCTAssertNil(PlaceName.tooltip(""))
    }
}
