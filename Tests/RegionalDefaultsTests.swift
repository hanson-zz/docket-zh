import XCTest

/// 英文界面按地区给新小组件的默认值；中文界面和已放好的小组件不变。
final class RegionalDefaultsTests: XCTestCase {
    func testChineseInterfaceKeepsChineseDefaults() {
        for region in ["CN", "US", "GB", nil] {
            XCTAssertEqual(RegionalDefaults.resolve(english: false, region: region), .chinese, "\(String(describing: region))")
        }
        XCTAssertEqual(RegionalDefaults.chinese.cryptoCurrency, "cny")
        XCTAssertEqual(RegionalDefaults.chinese.colors, .redUp)
        XCTAssertEqual(RegionalDefaults.chinese.metalUnit, .cnyPerGram)
        XCTAssertEqual(RegionalDefaults.chinese.currencySymbol, "¥")
    }

    func testEnglishInMainlandChinaStaysChinese() {
        XCTAssertEqual(RegionalDefaults.resolve(english: true, region: "CN"), .chinese)
        XCTAssertEqual(RegionalDefaults.resolve(english: true, region: "cn"), .chinese)
    }

    func testEnglishElsewhereUsesDollarsOuncesAndGreenUp() {
        let us = RegionalDefaults.resolve(english: true, region: "US")
        XCTAssertEqual(us.cryptoCurrency, "usd")
        XCTAssertEqual(us.colors, .greenUp)
        XCTAssertEqual(us.metalUnit, .usdPerOunce)
        XCTAssertEqual(us.currencySymbol, "$")
        XCTAssertEqual(RegionalDefaults.resolve(english: true, region: "GB").currencySymbol, "£")
        XCTAssertEqual(RegionalDefaults.resolve(english: true, region: "DE").currencySymbol, "€")
        XCTAssertEqual(RegionalDefaults.resolve(english: true, region: nil).currencySymbol, "$")
        XCTAssertEqual(RegionalDefaults.resolve(english: true, region: "HK").colors, .greenUp)
    }

    func testRedUpRegionsKeepRedUpInEnglish() {
        for region in ["TW", "JP", "KR"] {
            let defaults = RegionalDefaults.resolve(english: true, region: region)
            XCTAssertEqual(defaults.colors, .redUp, region)
            XCTAssertEqual(defaults.cryptoCurrency, "usd", region)
        }
    }

    func testTestsRunInChineseSoCatalogDefaultsAreUnchanged() {
        XCTAssertEqual(RegionalDefaults.current, .chinese)
        let crypto = WidgetCatalog.make(.crypto)!.config
        XCTAssertEqual(crypto.string("currency"), "cny")
        XCTAssertEqual(crypto.string("colors"), ChangeColors.redUp.rawValue)
        XCTAssertEqual(WidgetCatalog.make(.stock)!.config.string("metalUnit"), PreciousMetal.DisplayUnit.cnyPerGram.rawValue)
        XCTAssertEqual(WidgetCatalog.make(.slacker)!.config.string(SlackerClock.currencyKey), "¥")
    }

    func testSavedWidgetsKeepTheirOwnValues() {
        // 老卡片存着人民币和红涨，合并默认值时不会被换掉。
        let saved = WidgetConfig(["currency": .string("cny"), "colors": .string("redUp")])
        let merged = saved.merging(defaults: WidgetConfig(["currency": .string("usd"), "colors": .string("greenUp")]))
        XCTAssertEqual(merged.string("currency"), "cny")
        XCTAssertEqual(merged.string("colors"), "redUp")
    }

    func testSlackerCurrencySymbolFollowsTheConfig() {
        XCTAssertEqual(SlackerClock.Settings(config: WidgetConfig()).currencySymbol, "¥", "老卡片没有这个键，照旧是 ¥")
        let dollars = SlackerClock.Settings(config: WidgetConfig([SlackerClock.currencyKey: .string("$")]))
        XCTAssertEqual(dollars.currencySymbol, "$")
        XCTAssertEqual(SlackerClock.Settings(currencySymbol: "  ").currencySymbol, "¥")
    }
}
