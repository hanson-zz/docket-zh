import Foundation
import XCTest

/// 设置 ▸ 扩展栏 ▸ 小组件间距：2 到 16pt，默认 4（加这项之前写死的值），
/// 大小超过 100% 时仍按比例放大。
final class ItemGapTests: XCTestCase {

    /// 不传间距和传默认值，结果和以前写死的 4 * scale / min(1, scale) 一样，
    /// 老用户的扩展栏一个点都不动。
    func testDefaultGapKeepsTheOldSpacingAtEverySize() {
        for step in 0...125 {
            let scale = 0.25 + Double(step) * 0.01
            let old = 4 * scale / min(1, scale)
            XCTAssertEqual(Geometry.chrome(scale: scale).itemGap, old, accuracy: 1e-9)
            XCTAssertEqual(Geometry.chrome(scale: scale, itemGap: 4).itemGap, old, accuracy: 1e-9)
        }
    }

    /// 大小不超过 100% 时间距就是设的点数。
    func testGapIsTheChosenPointsUpToFullSize() {
        XCTAssertEqual(Geometry.chrome(scale: 0.35, itemGap: 8).itemGap, 8, accuracy: 1e-9)
        XCTAssertEqual(Geometry.chrome(scale: 1, itemGap: 14).itemGap, 14, accuracy: 1e-9)
    }

    /// 超过 100% 时仍按比例放大：150% 时 8pt 画成 12pt。
    func testGapStillGrowsAboveFullSize() {
        XCTAssertEqual(Geometry.chrome(scale: 1.5, itemGap: 8).itemGap, 12, accuracy: 1e-9)
        XCTAssertEqual(Geometry.chrome(scale: 1.5, itemGap: 4).itemGap, 6, accuracy: 1e-9)
    }

    /// 只动间距，别的边框尺寸不变。
    func testGapLeavesTheRestOfTheChromeAlone() {
        let base = Geometry.chrome(scale: 0.6)
        let wide = Geometry.chrome(scale: 0.6, itemGap: 16)
        XCTAssertEqual(wide.padding, base.padding)
        XCTAssertEqual(wide.radius, base.radius)
        XCTAssertEqual(wide.adjacentGap, base.adjacentGap)
        XCTAssertEqual(wide.gripCross, base.gripCross)
    }

    /// 写坏的值夹回 2 到 16、取整，不是数的回到默认。
    func testStoredGapIsClampedAndRounded() {
        XCTAssertEqual(Geometry.itemGap(1), 2)
        XCTAssertEqual(Geometry.itemGap(-30), 2)
        XCTAssertEqual(Geometry.itemGap(40), 16)
        XCTAssertEqual(Geometry.itemGap(7.4), 7)
        XCTAssertEqual(Geometry.itemGap(.nan), Geometry.defaultItemGap)
        XCTAssertEqual(Geometry.itemGap(.infinity), Geometry.defaultItemGap)
        XCTAssertEqual(Geometry.itemGapRange, 2...16)
        XCTAssertEqual(Geometry.chrome(scale: 0.5, itemGap: 99).itemGap, 16, accuracy: 1e-9)
    }

    /// 小间隔就是一个间距，跟着设的间距走。
    func testSmallSpacerFollowsTheChosenGap() {
        let gap = Geometry.chrome(scale: 0.35, itemGap: 10).itemGap
        XCTAssertEqual(Geometry.spacerLength(.small, tile: 50, itemGap: gap), 10, accuracy: 1e-9)
    }

    /// 旧配置里没有这个键，读出来是 4。
    func testSettingsWrittenBeforeTheGapExistedReadAsFour() throws {
        var settings = CustomDockSettings()
        settings.itemGap = 12
        let encoded = try JSONEncoder().encode(settings)
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNotNil(fields.removeValue(forKey: "itemGap"), "precondition: the gap is encoded")

        let legacy = try JSONSerialization.data(withJSONObject: fields)
        let back = try JSONDecoder().decode(CustomDockSettings.self, from: legacy)
        XCTAssertEqual(back.itemGap, 4)
        XCTAssertEqual(CustomDockSettings().itemGap, 4)
    }

    /// 设过的间距存下来，重启后还在。
    func testChosenGapSurvivesARoundTrip() throws {
        var settings = CustomDockSettings()
        settings.itemGap = 9
        let back = try JSONDecoder().decode(CustomDockSettings.self,
                                            from: JSONEncoder().encode(settings))
        XCTAssertEqual(back.itemGap, 9)
    }

    /// 这个键写成了别的类型（比如字符串）时不连累整份配置，回到默认。
    func testAMalformedGapFallsBackWithoutLosingTheRest() throws {
        let json = #"{"followSystemDock": false, "itemGap": "wide", "edgeGap": 10}"#
        let back = try JSONDecoder().decode(CustomDockSettings.self, from: Data(json.utf8))
        XCTAssertEqual(back.itemGap, 4)
        XCTAssertFalse(back.followSystemDock)
        XCTAssertEqual(back.edgeGap, 10)
    }
}
