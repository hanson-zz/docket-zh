import Foundation
import XCTest

/// 三个“圆环撞脸”拆开：圆只留给圆环仪表，电池画电池形状，系统活动画竖条；
/// 系统活动和网络活动只差一条图表线的样式并成开关。
final class ShapeMetersTests: XCTestCase {

    // MARK: 竖条

    func testSegmentsLightByRoundedShare() {
        XCTAssertEqual(ShapeMeters.segments, 8)
        XCTAssertEqual(ShapeMeters.litSegments(0), 0)
        XCTAssertEqual(ShapeMeters.litSegments(0.23), 2)
        XCTAssertEqual(ShapeMeters.litSegments(0.64), 5)
        XCTAssertEqual(ShapeMeters.litSegments(1), 8)
        XCTAssertEqual(ShapeMeters.litSegments(1.7), 8, "超过 100% 也只亮满")
        XCTAssertEqual(ShapeMeters.litSegments(-0.2), 0)
        XCTAssertEqual(ShapeMeters.litSegments(.nan), 0)
    }

    func testAnyRealLoadLightsAtLeastOneSegment() {
        XCTAssertEqual(ShapeMeters.litSegments(0.03), 1)
        XCTAssertEqual(ShapeMeters.litSegments(0.001), 0)
        XCTAssertEqual(ShapeMeters.litSegments(0.5, segments: 0), 0)
    }

    /// 竖条存的值仍是 rings：已经放好的“圆环”卡片直接换成竖条，名字改了。
    func testSystemRingsLayoutIsNowCalledSegments() {
        guard let entry = WidgetCatalog.entry(.system) else { return XCTFail("missing") }
        XCTAssertEqual(entry.variants.map(\.title), ["数字", "竖条", "条形", "液态"])
        let placed = WidgetInstance(kind: .system,
                                    config: WidgetConfig(["layout": .string("rings")]).merging(defaults: entry.defaults))
        XCTAssertEqual(WidgetCatalog.variantTitle(matching: placed.config, kind: .system), "竖条")
        XCTAssertEqual(placed.config.string("layout"), ShapeMeters.systemSegmentsLayout)
        // 两个读数仍是 160 宽，卡片在架子上的位置不动。
        XCTAssertEqual(WidgetCatalog.naturalSize(placed).width, 160)
    }

    // MARK: 电池格

    func testBatteryGaugeIsNowCalledCellsAndStaysPro() {
        guard let entry = WidgetCatalog.entry(.battery) else { return XCTFail("missing") }
        XCTAssertEqual(entry.variants.map(\.title), ["状态", "电池格", "仅图标"])
        let cells = entry.variants.first { $0.title == "电池格" }?.overrides
        XCTAssertEqual(cells?["layout"], .string("gauge"))
        XCTAssertTrue(ProFeatures.isProStyle(.battery, cells ?? [:]))
        let placed = WidgetInstance(kind: .battery,
                                    config: WidgetConfig(["layout": .string("gauge")]).merging(defaults: entry.defaults))
        XCTAssertEqual(WidgetCatalog.variantTitle(matching: placed.config, kind: .battery), "电池格")
    }

    func testOneDeviceIsAHorizontalCellSeveralAreUpright() {
        XCTAssertEqual(ShapeMeters.cellAxis(deviceCount: 0), .horizontal)
        XCTAssertEqual(ShapeMeters.cellAxis(deviceCount: 1), .horizontal)
        XCTAssertEqual(ShapeMeters.cellAxis(deviceCount: 2), .vertical)
        XCTAssertEqual(ShapeMeters.cellAxis(deviceCount: 3), .vertical)
    }

    func testAMissingDeviceIsAnEmptyCell() {
        XCTAssertEqual(ShapeMeters.cellFill(level: 0.76, present: true), 0.76, accuracy: 0.0001)
        XCTAssertEqual(ShapeMeters.cellFill(level: 0.76, present: false), 0)
        XCTAssertEqual(ShapeMeters.cellFill(level: 1.4, present: true), 1)
        XCTAssertEqual(ShapeMeters.cellFill(level: .nan, present: true), 0)
    }

    func testCellsOnlyTakeAColourWhenLow() {
        XCTAssertEqual(ShapeMeters.cellTone(level: 0.76, charging: false, present: true), .normal)
        XCTAssertEqual(ShapeMeters.cellTone(level: 0.18, charging: false, present: true), .low)
        XCTAssertEqual(ShapeMeters.cellTone(level: 0.08, charging: false, present: true), .critical)
        XCTAssertEqual(ShapeMeters.cellTone(level: 0.08, charging: true, present: true), .normal)
        XCTAssertEqual(ShapeMeters.cellTone(level: 0, charging: false, present: false), .absent)
    }

    /// 经典和液态画电池形状；Pro 的像素电池、能量粒子、小熊猫照旧。
    func testWhichLooksDrawACell() {
        XCTAssertTrue(ShapeMeters.drawsCell(look: "classic"))
        XCTAssertTrue(ShapeMeters.drawsCell(look: "liquid"))
        XCTAssertTrue(ShapeMeters.drawsCell(look: "unknown"))
        for look in ["pixel", "particles", "panda"] {
            XCTAssertFalse(ShapeMeters.drawsCell(look: look), look)
        }
    }

    // MARK: 圆环仪表

    func testGaugesCanMixInCPUAndMemory() {
        XCTAssertEqual(GaugeReading.allRings, ["storage", "battery", "cpu", "memory"])
        let mixed = WidgetConfig(["rings": .list([.string("memory"), .string("storage"), .string("cpu")])])
        XCTAssertEqual(GaugeReading.rings(mixed), ["storage", "cpu", "memory"])
        let all = WidgetInstance(kind: .gauges, config: WidgetConfig(["rings": .list(GaugeReading.allRings.map { .string($0) })]))
        XCTAssertEqual(WidgetCatalog.naturalSize(all).width, GaugeReading.tileWidth(rings: 4))
        // 旧卡片没存 rings 时仍是存储和电池两个。
        XCTAssertEqual(GaugeReading.rings(WidgetCatalog.make(.gauges)!.config), ["storage", "battery"])
    }

    // MARK: 合并成开关

    func testNoVariantDiffersOnlyByAChart() {
        for kind in [WidgetKind.system, .network] {
            guard let entry = WidgetCatalog.entry(kind) else { return XCTFail("\(kind)") }
            for variant in entry.variants {
                XCTAssertNil(variant.overrides["chart"], "\(kind)/\(variant.title) 不再自己定图表")
            }
            XCTAssertTrue(WidgetCatalog.configurableKeys(kind).contains("chart"), "\(kind) 有显示图表开关")
        }
    }

    /// 已放好的“数字 + 图表”卡片读出来是“数字”加开关打开，外观和大小不变。
    func testOldChartedSystemCardsKeepTheirGraph() {
        guard let entry = WidgetCatalog.entry(.system) else { return XCTFail("missing") }
        let old = WidgetConfig(["layout": .string("numbers"), "chart": .bool(true),
                                "metrics": .list([.string("cpu"), .string("memory")])])
        let placed = WidgetInstance(kind: .system, config: old.merging(defaults: entry.defaults))
        XCTAssertEqual(WidgetCatalog.variantTitle(matching: placed.config, kind: .system), "数字")
        XCTAssertTrue(ShapeMeters.chartOption(placed.config))
        XCTAssertEqual(WidgetCatalog.naturalSize(placed).width, 168)
    }
}
