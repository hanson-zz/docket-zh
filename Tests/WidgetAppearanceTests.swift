import XCTest

/// 详情面板里的“外观”入口：哪些卡片有、摘要怎么写、色块一排几个。
final class WidgetAppearanceTests: XCTestCase {

    func testOfferedMatchesTheSettingsSection() {
        XCTAssertTrue(WidgetAppearance.offered(.battery))
        XCTAssertTrue(WidgetAppearance.offered(.music), "封面卡片不叠背景，但颜色可以选")
        XCTAssertFalse(WidgetAppearance.offered(.photos))
        XCTAssertFalse(WidgetAppearance.offered(.notes))
        XCTAssertFalse(WidgetAppearance.offered(.stripe))
        for kind in [WidgetKind.photos, .wallpaper, .notes, .stripe, .paddle, .shopify, .battery, .clock, .music] {
            XCTAssertEqual(WidgetAppearance.offered(kind),
                           WidgetTint.offersColor(kind) || WidgetTint.offersBackground(kind), "\(kind)")
        }
    }

    func testDefaultConfigIsNotCustomized() {
        XCTAssertFalse(WidgetAppearance.isCustomized(WidgetConfig(), kind: .battery))
        XCTAssertEqual(WidgetAppearance.summary(WidgetConfig(), kind: .battery), "默认")
    }

    func testSummaryListsColorThenBackground() {
        var config = WidgetConfig()
        config.set(WidgetTint.key, .string("pink"))
        XCTAssertTrue(WidgetAppearance.isCustomized(config, kind: .battery))
        XCTAssertEqual(WidgetAppearance.summary(config, kind: .battery), "粉")

        config.set(WidgetTint.backgroundKey, .string("dots"))
        XCTAssertEqual(WidgetAppearance.summary(config, kind: .battery), "粉 · 网点背景")

        config.set(WidgetTint.key, .string("system"))
        XCTAssertEqual(WidgetAppearance.summary(config, kind: .battery), "跟随系统 · 网点背景")

        config.set(WidgetTint.key, .string("#123456"))
        XCTAssertEqual(WidgetAppearance.summary(config, kind: .battery), "自定义颜色 · 网点背景")

        config.set(WidgetTint.key, nil)
        XCTAssertEqual(WidgetAppearance.summary(config, kind: .battery), "网点背景")
    }

    func testBackgroundIgnoredWhereTheKindHasNone() {
        var config = WidgetConfig()
        config.set(WidgetTint.backgroundKey, .string("gradient"))
        XCTAssertFalse(WidgetAppearance.isCustomized(config, kind: .music),
                       "封面卡片不提供背景，留着的旧值不算调过")
        XCTAssertEqual(WidgetAppearance.summary(config, kind: .music), "默认")
        XCTAssertTrue(WidgetAppearance.isCustomized(config, kind: .battery))
    }

    func testUnknownTintReadsAsDefault() {
        var config = WidgetConfig()
        config.set(WidgetTint.key, .string("not-a-colour"))
        XCTAssertFalse(WidgetAppearance.isCustomized(config, kind: .clock))
    }

    func testSwatchColumnsFitTheWidth() {
        // 设置页：9 个一排（28 宽、6 间距要 300）。
        XCTAssertEqual(WidgetAppearance.swatchColumns(available: 400, cell: 28, spacing: 6), 9)
        XCTAssertEqual(WidgetAppearance.swatchColumns(available: 300, cell: 28, spacing: 6), 9)
        XCTAssertEqual(WidgetAppearance.swatchColumns(available: 299, cell: 28, spacing: 6), 8)
        // 最窄的面板 280 减去两边 16 的边距。
        XCTAssertEqual(WidgetAppearance.swatchColumns(available: 248, cell: 28, spacing: 6), 7)
        XCTAssertEqual(WidgetAppearance.swatchColumns(available: 10, cell: 28, spacing: 6), 1)
        XCTAssertEqual(WidgetAppearance.swatchColumns(available: .infinity, cell: 28, spacing: 6), 1)
        XCTAssertEqual(WidgetAppearance.swatchColumns(available: 1000, cell: 28, spacing: 6, maximum: 5), 5)
    }
}
