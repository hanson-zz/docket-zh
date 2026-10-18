import Foundation
import XCTest

/// 「算」：一个输入框自动认出汇率、单位换算和算式，以及旧的三张卡片迁移过来。
final class SmartCalcTests: XCTestCase {
    /// 以人民币为基准的一张固定汇率表：1 CNY = 0.14 USD 等。
    private let rates = CurrencyRates(base: "CNY",
                                      rates: ["CNY": 1, "USD": 0.14, "EUR": 0.13, "JPY": 21.0,
                                              "HKD": 1.1, "GBP": 0.11, "KRW": 190, "SEK": 1.5],
                                      updated: Date(timeIntervalSince1970: 1_792_022_400))

    private func outcome(_ text: String, prefs: SmartCalc.Preferences = .init(),
                         file: StaticString = #filePath, line: UInt = #line) -> SmartCalc.Outcome? {
        switch SmartCalc.evaluate(text, rates: rates, preferences: prefs) {
        case .success(let value): return value
        case .failure(let failure):
            XCTFail("\(text) failed: \(failure)", file: file, line: line)
            return nil
        }
    }

    private func failure(_ text: String, rates: CurrencyRates? = nil) -> SmartCalc.Failure? {
        guard case .failure(let f) = SmartCalc.evaluate(text, rates: rates ?? self.rates) else { return nil }
        return f
    }

    private func currency(_ text: String) -> (Double, String, String?)? {
        guard case .currency(let a, let f, let t) = SmartCalc.parse(text) else { return nil }
        return (a, f, t)
    }

    private func unit(_ text: String) -> (Double, ConversionUnit, ConversionUnit?)? {
        guard case .unit(let v, let f, let t) = SmartCalc.parse(text) else { return nil }
        return (v, f, t)
    }

    // MARK: 识别成哪一类

    func testKindsFromTheDesign() {
        XCTAssertEqual(SmartCalc.parse("100 USD").kind, .currency)
        XCTAssertEqual(SmartCalc.parse("5 km").kind, .unit)
        XCTAssertEqual(SmartCalc.parse("128*3.5").kind, .math)
        XCTAssertEqual(SmartCalc.parse("128 × 3.5").kind, .math)
        XCTAssertEqual(SmartCalc.parse("3*4+2").kind, .math)
        XCTAssertEqual(SmartCalc.parse("(1+2)*3").kind, .math)
        XCTAssertEqual(SmartCalc.parse("50%").kind, .math)
    }

    func testCurrencyCodesAndChineseNames() {
        XCTAssertEqual(currency("100 USD")?.1, "USD")
        XCTAssertEqual(currency("100 usd")?.1, "USD")
        XCTAssertEqual(currency("100USD")?.1, "USD")
        XCTAssertEqual(currency("100美元")?.1, "USD")
        XCTAssertEqual(currency("100 美金")?.1, "USD")
        XCTAssertEqual(currency("100 dollars")?.1, "USD")
        XCTAssertEqual(currency("50 欧元")?.1, "EUR")
        XCTAssertEqual(currency("3000日元")?.1, "JPY")
        XCTAssertEqual(currency("200 港币")?.1, "HKD")
        XCTAssertEqual(currency("10 英镑")?.1, "GBP")
        XCTAssertEqual(currency("500 人民币")?.1, "CNY")
        XCTAssertEqual(currency("500 块")?.1, "CNY")
        XCTAssertEqual(currency("500元")?.1, "CNY")
        XCTAssertEqual(currency("20 rmb")?.1, "CNY")
        XCTAssertEqual(currency("1000 韩元")?.1, "KRW")
        XCTAssertEqual(currency("100 泰铢")?.1, "THB")
        XCTAssertEqual(currency("100 新台币")?.1, "TWD")
        XCTAssertEqual(currency("100 澳元")?.1, "AUD")
    }

    func testCurrencySymbolsInFront() {
        XCTAssertEqual(currency("$20")?.0, 20)
        XCTAssertEqual(currency("$20")?.1, "USD")
        XCTAssertEqual(currency("¥500")?.1, "CNY")
        XCTAssertEqual(currency("￥500")?.1, "CNY")
        XCTAssertEqual(currency("€9.5")?.0, 9.5)
        XCTAssertEqual(currency("€9.5")?.1, "EUR")
        XCTAssertEqual(currency("£3")?.1, "GBP")
        XCTAssertEqual(currency("HK$100")?.1, "HKD")
        XCTAssertEqual(currency("20$")?.1, "USD", "the sign after the number too")
    }

    func testCurrencyWithATarget() {
        let a = currency("¥500 to EUR")
        XCTAssertEqual(a?.0, 500)
        XCTAssertEqual(a?.1, "CNY")
        XCTAssertEqual(a?.2, "EUR")
        XCTAssertEqual(currency("100 usd to jpy")?.2, "JPY")
        XCTAssertEqual(currency("100 USD in CNY")?.2, "CNY")
        XCTAssertEqual(currency("100美元换成人民币")?.2, "CNY")
        XCTAssertEqual(currency("100美元是多少日元")?.2, "JPY")
        XCTAssertEqual(currency("100美元等于多少人民币")?.2, "CNY")
        XCTAssertEqual(currency("100 USD -> EUR")?.2, "EUR")
        XCTAssertEqual(currency("100 USD → EUR")?.2, "EUR")
        XCTAssertEqual(currency("100 USD = EUR")?.2, "EUR")
    }

    func testCurrencyAmountsCanBeSumsAndChineseMultiples() {
        XCTAssertEqual(currency("(100+20) USD")?.0, 120)
        XCTAssertEqual(currency("1,000 USD")?.0, 1000)
        XCTAssertEqual(currency("1万日元")?.0, 10_000)
        XCTAssertEqual(currency("1万日元")?.1, "JPY")
        XCTAssertEqual(currency("2.5万元")?.0, 25_000)
        XCTAssertEqual(currency("１００美元")?.0, 100, "full-width digits")
        XCTAssertEqual(currency("１００ＵＳＤ")?.1, "USD", "full-width letters")
        XCTAssertEqual(currency("usd")?.0, 1, "just a code means one of it")
    }

    func testAnyCodeTheRateTableKnows() {
        // SEK is not in the common list, but the table has it.
        guard case .success(let out) = SmartCalc.evaluate("100 SEK to CNY", rates: rates) else {
            return XCTFail("SEK should be read from the table")
        }
        XCTAssertEqual(out.unit, "CNY")
        // Without the table, three random letters are not a currency.
        XCTAssertNil(currency("100 SEK"))
        XCTAssertEqual(SmartCalc.parse("100 abc").kind, .unit, "an unknown word is reported as one")
    }

    func testUnitsInChineseAndEnglish() {
        XCTAssertEqual(unit("5 km")?.1, .kilometre)
        XCTAssertEqual(unit("5km")?.1, .kilometre)
        XCTAssertEqual(unit("5 公里")?.1, .kilometre)
        XCTAssertEqual(unit("5 千米")?.1, .kilometre)
        XCTAssertEqual(unit("3 斤")?.1, .jin)
        XCTAssertEqual(unit("3斤")?.1, .jin)
        XCTAssertEqual(unit("2 公斤")?.1, .kilogram)
        XCTAssertEqual(unit("2 千克")?.1, .kilogram, "千克 is a unit, not 千 × 克")
        XCTAssertEqual(unit("500 克")?.1, .gram)
        XCTAssertEqual(unit("10 磅")?.1, .pound)
        XCTAssertEqual(unit("10 lbs")?.1, .pound)
        XCTAssertEqual(unit("3 pounds")?.1, .pound, "pounds are weight; sterling is 英镑 or GBP")
        XCTAssertEqual(unit("8 oz")?.1, .ounce)
        XCTAssertEqual(unit("12 英寸")?.1, .inch)
        XCTAssertEqual(unit("12 inches")?.1, .inch)
        XCTAssertEqual(unit("6 feet")?.1, .foot)
        XCTAssertEqual(unit("6 英尺")?.1, .foot)
        XCTAssertEqual(unit("100 码")?.1, .yard)
        XCTAssertEqual(unit("26.2 miles")?.1, .mile)
        XCTAssertEqual(unit("170 cm")?.1, .centimetre)
        XCTAssertEqual(unit("170 公分")?.1, .centimetre)
        XCTAssertEqual(unit("1 吨")?.1, .tonne)
    }

    func testTemperatures() {
        XCTAssertEqual(unit("72°F")?.1, .fahrenheit)
        XCTAssertEqual(unit("72 °F")?.1, .fahrenheit)
        XCTAssertEqual(unit("72℉")?.1, .fahrenheit)
        XCTAssertEqual(unit("37℃")?.1, .celsius)
        XCTAssertEqual(unit("37 摄氏度")?.1, .celsius)
        XCTAssertEqual(unit("-40 °C")?.0, -40)
        XCTAssertEqual(unit("100 华氏度")?.1, .fahrenheit)
        XCTAssertEqual(unit("300 K")?.1, .kelvin)
    }

    func testUnitWithATarget() {
        XCTAssertEqual(unit("5 km to mi")?.2, .mile)
        XCTAssertEqual(unit("5 km in miles")?.2, .mile)
        XCTAssertEqual(unit("3斤换成克")?.2, .gram)
        XCTAssertEqual(unit("72°F to °C")?.2, .celsius)
        // "in" as the unit and as the separator.
        let inches = unit("10 in to cm")
        XCTAssertEqual(inches?.1, .inch)
        XCTAssertEqual(inches?.2, .centimetre)
        let both = unit("1 in in cm")
        XCTAssertEqual(both?.1, .inch)
        XCTAssertEqual(both?.2, .centimetre)
        XCTAssertNil(unit("10 in")?.2, "no target, just inches")
    }

    // MARK: 算出来的数

    func testCurrencyResults() {
        let usd = outcome("100 USD")
        XCTAssertEqual(usd?.kind, .currency)
        XCTAssertEqual(usd?.unit, "CNY")
        XCTAssertEqual(usd?.value ?? 0, 714.285714, accuracy: 1e-5)
        XCTAssertEqual(usd?.text, "714.29")
        XCTAssertEqual(usd?.source, "100.00 USD")
        XCTAssertEqual(usd?.rate ?? 0, 7.142857, accuracy: 1e-5)
        XCTAssertEqual(usd?.sourceUnit, "USD")
        XCTAssertEqual(usd?.rateLine, "1 USD = 7.14286 CNY")
        XCTAssertNil(outcome("5 km")?.rateLine)
        XCTAssertEqual(outcome("5 km")?.sourceUnit, "km")

        let yen = outcome("100 usd to jpy")
        XCTAssertEqual(yen?.unit, "JPY")
        XCTAssertEqual(yen?.text, "15,000", "yen has no cents, and the card groups thousands")
        XCTAssertEqual(yen?.copyText, "15000", "copied without the grouping")

        let euro = outcome("¥500 to EUR")
        XCTAssertEqual(euro?.value ?? 0, 65, accuracy: 1e-9)
    }

    func testOnlyTheSourceUsesTheDefaultPair() {
        let prefs = SmartCalc.Preferences(currencyFrom: "USD", currencyTo: "CNY")
        XCTAssertEqual(outcome("100 USD", prefs: prefs)?.unit, "CNY")
        XCTAssertEqual(outcome("100 EUR", prefs: prefs)?.unit, "CNY")
        XCTAssertEqual(outcome("100 人民币", prefs: prefs)?.unit, "USD", "the home currency goes the other way")
        let japan = SmartCalc.Preferences(currencyFrom: "JPY", currencyTo: "CNY")
        XCTAssertEqual(outcome("500 元", prefs: japan)?.unit, "JPY")
        // A pair that is one currency twice still converts somewhere.
        let same = SmartCalc.Preferences(currencyFrom: "CNY", currencyTo: "CNY")
        XCTAssertEqual(outcome("5 CNY", prefs: same)?.unit, "USD")
    }

    func testUnitResults() {
        let km = outcome("5 km")
        XCTAssertEqual(km?.kind, .unit)
        XCTAssertEqual(km?.unit, "mi")
        XCTAssertEqual(km?.text, "3.10686")
        XCTAssertEqual(km?.category, .length)
        XCTAssertEqual(outcome("3 斤")?.text, "1.5")
        XCTAssertEqual(outcome("3 斤")?.unit, "kg")
        XCTAssertEqual(outcome("72°F")?.text, "22.2222")
        XCTAssertEqual(outcome("72°F")?.unit, "°C")
        XCTAssertEqual(outcome("100 °C")?.text, "212")
        XCTAssertEqual(outcome("3斤换成克")?.text, "1500")
        XCTAssertEqual(outcome("1 mi to km")?.text, "1.60934")
    }

    func testTheOldConvertersPairIsTheDefault() {
        let prefs = SmartCalc.Preferences(unitFrom: .kilometre, unitTo: .metre)
        XCTAssertEqual(outcome("5 km", prefs: prefs)?.unit, "m")
        XCTAssertEqual(outcome("5 m", prefs: prefs)?.unit, "km", "either end of the pair")
        XCTAssertEqual(outcome("5 mi", prefs: prefs)?.unit, "km", "other units use the usual counterpart")
    }

    func testEveryUnitHasACounterpartOfItsOwnKind() {
        for unit in ConversionUnit.allCases {
            let other = SmartCalc.counterpart(unit)
            XCTAssertEqual(other.category, unit.category, "\(unit)")
            XCTAssertNotEqual(other, unit, "\(unit)")
        }
    }

    func testEveryUnitsOwnSymbolReadsBack() {
        // The migration writes symbols; each has to parse as itself.
        for unit in ConversionUnit.allCases {
            XCTAssertEqual(self.unit("2 \(unit.symbol)")?.1, unit, unit.symbol)
            XCTAssertEqual(self.unit("2 \(unit.name)")?.1, unit, unit.name)
        }
    }

    func testEveryCommonCurrencyReadsBackByCodeAndName() {
        for item in CurrencyNames.common {
            XCTAssertEqual(currency("5 \(item.code)")?.1, item.code, item.code)
            XCTAssertEqual(currency("5 \(item.code.lowercased())")?.1, item.code, item.code)
            XCTAssertEqual(currency("5 \(item.name)")?.1, item.code, item.name)
        }
    }

    func testMathResults() {
        XCTAssertEqual(outcome("3*4+2")?.text, "14")
        XCTAssertEqual(outcome("128 × 3.5")?.text, "448")
        XCTAssertEqual(outcome("(1+2)*3")?.text, "9")
        XCTAssertEqual(outcome("3*4+2=")?.text, "14", "a trailing equals sign is a question")
        XCTAssertEqual(outcome("3*4+2 =?")?.text, "14")
        XCTAssertEqual(outcome("3万")?.text, "30000")
        XCTAssertEqual(outcome("1280×(1+6%)")?.text, "1356.8")
        XCTAssertEqual(outcome("128*3.5")?.kind, .math)
        XCTAssertEqual(outcome("128*3.5")?.unit, "")
    }

    func testPercentagesAddAndTakeOff() {
        XCTAssertEqual(outcome("200+10%")?.text, "220")
        XCTAssertEqual(outcome("200-10%")?.text, "180")
        XCTAssertEqual(outcome("200*10%")?.text, "20")
        XCTAssertEqual(outcome("50%")?.text, "0.5")
        XCTAssertEqual(outcome("100+50%+10%")?.text, "165")
    }

    // MARK: 失败

    func testFailures() {
        XCTAssertEqual(failure(""), .empty)
        XCTAssertEqual(failure("   "), .empty)
        XCTAssertEqual(failure("="), .empty)
        XCTAssertEqual(failure("2+"), .math(.incomplete))
        XCTAssertEqual(failure("1/0"), .math(.divisionByZero))
        XCTAssertEqual(failure("5 km to kg"), .mismatch)
        XCTAssertEqual(failure("5 km to USD"), .mismatch)
        XCTAssertEqual(failure("100 USD to km"), .mismatch)
        XCTAssertEqual(failure("100 abc"), .unknownUnit("abc"))
        XCTAssertEqual(failure("100 xyz to usd"), .unknownUnit("xyz"))
        XCTAssertEqual(failure("100 USD to XYZ"), .unknownUnit("XYZ"))
        for f in [SmartCalc.Failure.empty, .math(.incomplete), .unknownUnit("x"), .mismatch, .noRate("USD")] {
            XCTAssertFalse(f.message.isEmpty)
        }
    }

    func testNoRatesYetIsSaidAndStillTaggedAsCurrency() {
        guard case .failure(let f) = SmartCalc.evaluate("100 USD", rates: nil) else {
            return XCTFail("no table, no answer")
        }
        XCTAssertEqual(f, .noRate("CNY"))
        XCTAssertEqual(f.kind, .currency)
        // Units and sums need no network.
        XCTAssertNotNil(try? SmartCalc.evaluate("5 km", rates: nil).get())
        XCTAssertNotNil(try? SmartCalc.evaluate("1+1", rates: nil).get())
    }

    func testOutputFormats() {
        XCTAssertEqual(outcome("5 km")?.copyText, "3.10686")
        XCTAssertEqual(outcome("1000 usd")?.text, "7,142.86")
        XCTAssertEqual(outcome("1000 usd")?.copyText, "7142.86")
    }

    // MARK: 最近记录和卡片

    func testHistory() {
        var history: [String] = []
        history = SmartCalc.remembering("1+1", in: history)
        history = SmartCalc.remembering("5 km", in: history)
        history = SmartCalc.remembering(" 1+1 ", in: history)
        XCTAssertEqual(history, ["1+1", "5 km"], "a repeat moves to the top once")
        history = SmartCalc.remembering("", in: history)
        XCTAssertEqual(history, ["1+1", "5 km"])
        for n in 0..<30 { history = SmartCalc.remembering("\(n)", in: history) }
        XCTAssertEqual(history.count, SmartCalc.historyLimit)
        XCTAssertEqual(history.first, "29")
    }

    func testTheCardShowsThePinnedOneFirst() {
        var config = WidgetConfig([SmartCalc.expressionKey: .string("1+1")])
        XCTAssertEqual(SmartCalc.shown(config), "1+1")
        config.set(SmartCalc.pinnedKey, .string("1 USD"))
        XCTAssertEqual(SmartCalc.shown(config), "1 USD")
        config.set(SmartCalc.pinnedKey, .string(""))
        XCTAssertEqual(SmartCalc.shown(config), "1+1")
    }

    func testPreferencesFromConfig() {
        let prefs = SmartCalc.Preferences(WidgetConfig([SmartCalc.currencyFromKey: .string("eur"),
                                                        SmartCalc.currencyToKey: .string("JPY"),
                                                        SmartCalc.unitFromKey: .string("lb"),
                                                        SmartCalc.unitToKey: .string("jin")]))
        XCTAssertEqual(prefs.currencyFrom, "EUR")
        XCTAssertEqual(prefs.currencyTo, "JPY")
        XCTAssertEqual(prefs.unitFrom, .pound)
        XCTAssertEqual(prefs.unitTo, .jin)
        let empty = SmartCalc.Preferences(WidgetConfig())
        XCTAssertEqual(empty.currencyFrom, "USD")
        XCTAssertEqual(empty.currencyTo, "CNY")
        XCTAssertNil(empty.unitFrom)
    }

    // MARK: 迁移

    func testOldCalculatorKeepsItsSum() {
        let config = SmartCalc.migratingCalculator(WidgetConfig(["expression": .string("1280×(1+6%)"),
                                                                 "hidePlate": .bool(true)]))
        XCTAssertEqual(config.string("expression"), "1280×(1+6%)")
        XCTAssertEqual(config.strings("history"), ["1280×(1+6%)"])
        XCTAssertTrue(config.bool("hidePlate"))
        XCTAssertNil(SmartCalc.migratingCalculator(WidgetConfig())["history"], "nothing invented")
    }

    func testOldConverterBecomesItsLastInputAndPair() throws {
        let old = WidgetConfig(["category": .string("weight"), "from": .string("lb"),
                                "to": .string("jin"), "value": .number(10), "tint": .string("blue")])
        let config = SmartCalc.migratingConverter(old)
        XCTAssertEqual(config.string("expression"), "10 lb to \(ConversionUnit.jin.symbol)")
        XCTAssertEqual(config.strings("history"), [config.string("expression")])
        XCTAssertEqual(config.string("unitFrom"), "lb")
        XCTAssertEqual(config.string("unitTo"), "jin")
        for key in ["category", "from", "to", "value"] { XCTAssertNil(config[key], key) }
        XCTAssertEqual(config.string("tint"), "blue", "other keys are kept")
        let out = try SmartCalc.evaluate(config.string("expression"), rates: nil,
                                         preferences: SmartCalc.Preferences(config)).get()
        XCTAssertEqual(out.value, 9.0718474, accuracy: 1e-6)
        XCTAssertEqual(out.unit, ConversionUnit.jin.symbol)
    }

    func testAFreshConverterMigratesToItsDefault() throws {
        let config = SmartCalc.migratingConverter(WidgetConfig())
        XCTAssertEqual(config.string("expression"), "1 mi to km")
        XCTAssertEqual(try SmartCalc.evaluate("1 mi to km", rates: nil).get().text, "1.60934")
        let temperature = SmartCalc.migratingConverter(WidgetConfig(["category": .string("temperature"),
                                                                     "from": .string("C"), "to": .string("F"),
                                                                     "value": .number(37)]))
        XCTAssertEqual(try SmartCalc.evaluate(temperature.string("expression"), rates: nil).get().text, "98.6")
        // A unit from another category falls back to the category's pair.
        let mixed = SmartCalc.migratingConverter(WidgetConfig(["category": .string("length"),
                                                               "from": .string("kg")]))
        XCTAssertEqual(mixed.string("unitFrom"), "mi")
    }

    func testOldCurrencyBecomesItsLastInputAndPair() throws {
        let old = WidgetConfig(["from": .string("EUR"), "to": .string("JPY"), "amount": .number(250)])
        let config = SmartCalc.migratingCurrency(old)
        XCTAssertEqual(config.string("expression"), "250 EUR to JPY")
        XCTAssertEqual(config.string("currencyFrom"), "EUR")
        XCTAssertEqual(config.string("currencyTo"), "JPY")
        for key in ["from", "to", "amount"] { XCTAssertNil(config[key], key) }
        let out = try SmartCalc.evaluate(config.string("expression"), rates: rates,
                                         preferences: SmartCalc.Preferences(config)).get()
        XCTAssertEqual(out.unit, "JPY")
        XCTAssertEqual(out.value, 250 / 0.13 * 21, accuracy: 1e-6)
        // Defaults: what the catalog used to give a new one.
        let fresh = SmartCalc.migratingCurrency(WidgetConfig())
        XCTAssertEqual(fresh.string("expression"), "100 USD to CNY")
        XCTAssertEqual(SmartCalc.migratingCurrency(WidgetConfig(["from": .string("??")])).string("currencyFrom"), "USD")
    }
}

/// 单位换算（`converter`）和汇率换算（`currency`）并进计算器，成了「算」。
final class CalcMergeTests: XCTestCase {
    /// 旧版本存下的样子：把 kind 换成旧的原始值。
    private func legacyJSON(_ instance: WidgetInstance, kind: String) throws -> Data {
        let data = try JSONEncoder().encode(instance)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["kind"] = kind
        return try JSONSerialization.data(withJSONObject: object)
    }

    func testTheLibraryListsOnlyTheOneCard() {
        XCTAssertNil(WidgetKind(rawValue: SmartCalc.legacyConverterKind))
        XCTAssertNil(WidgetKind(rawValue: SmartCalc.legacyCurrencyKind))
        let names = WidgetCatalog.entries.map(\.name)
        XCTAssertFalse(names.contains("单位换算"))
        XCTAssertFalse(names.contains("汇率换算"))
        XCTAssertFalse(names.contains("计算器"))
        XCTAssertEqual(WidgetCatalog.entries.filter { $0.name == "算" }.map(\.kind), [.calculator])
        // The old names still find it in the library's search.
        for query in ["单位换算", "汇率", "计算器", "jsq", "converter", "currency"] {
            XCTAssertTrue(WidgetSearch.matches(query, names: ["算"], kind: "calculator"), query)
        }
    }

    func testNoneOfTheThreeIsPro() {
        // All three were free; the merged card stays free.
        XCTAssertFalse(ProFeatures.isProKind(.calculator))
        let fresh = WidgetCatalog.make(.calculator)
        XCTAssertNotNil(fresh)
        XCTAssertFalse(ProFeatures.isPro(.calculator, overrides: fresh?.config.values ?? [:]))
    }

    func testASavedConverterComesBackAsCalc() throws {
        let id = UUID()
        let old = WidgetInstance(id: id, kind: .calculator, expanded: true,
                                 config: WidgetConfig(["category": .string("length"), "from": .string("km"),
                                                       "to": .string("mi"), "value": .number(5),
                                                       "hidePlate": .bool(true)]))
        let migrated = try JSONDecoder().decode(WidgetInstance.self, from: legacyJSON(old, kind: "converter"))
        XCTAssertEqual(migrated.id, id, "same id, so the tile keeps its place")
        XCTAssertEqual(migrated.kind, .calculator)
        XCTAssertEqual(migrated.config.string("expression"), "5 km to mi")
        XCTAssertEqual(migrated.config.string("unitFrom"), "km")
        XCTAssertEqual(migrated.config.string("unitTo"), "mi")
        XCTAssertTrue(migrated.config.bool("hidePlate"), "other keys are kept")
        XCTAssertNil(migrated.config["from"])
        let out = try SmartCalc.evaluate(SmartCalc.shown(migrated.config), rates: nil,
                                         preferences: SmartCalc.Preferences(migrated.config)).get()
        XCTAssertEqual(out.text, "3.10686")

        // One-time: the next save writes it as the calculator.
        let resaved = try JSONEncoder().encode(migrated)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: resaved) as? [String: Any])
        XCTAssertEqual(object["kind"] as? String, "calculator")
        XCTAssertEqual(try JSONDecoder().decode(WidgetInstance.self, from: resaved), migrated)
    }

    func testASavedCurrencyComesBackAsCalcWithItsPair() throws {
        let old = WidgetInstance(kind: .calculator,
                                 config: WidgetConfig(["from": .string("HKD"), "to": .string("CNY"),
                                                       "amount": .number(500)]))
        let migrated = try JSONDecoder().decode(WidgetInstance.self, from: legacyJSON(old, kind: "currency"))
        XCTAssertEqual(migrated.kind, .calculator)
        XCTAssertEqual(migrated.config.string("expression"), "500 HKD to CNY")
        XCTAssertEqual(migrated.config.string("currencyFrom"), "HKD")
        XCTAssertEqual(migrated.config.string("currencyTo"), "CNY")
        // Drawn with the catalog's defaults filled in, the pair is still the user's.
        let drawn = migrated.config.merging(defaults: WidgetCatalog.entry(.calculator)!.defaults)
        XCTAssertEqual(SmartCalc.Preferences(drawn).currencyFrom, "HKD")
        XCTAssertEqual(SmartCalc.Preferences(drawn).currencyTo, "CNY")
    }

    func testASavedCalculatorKeepsItsSum() throws {
        let old = WidgetInstance(kind: .calculator, config: WidgetConfig(["expression": .string("12*(3+4)")]))
        let migrated = try JSONDecoder().decode(WidgetInstance.self, from: JSONEncoder().encode(old))
        XCTAssertEqual(migrated.kind, .calculator)
        XCTAssertEqual(SmartCalc.shown(migrated.config), "12*(3+4)")
        XCTAssertEqual(migrated.config.strings("history"), ["12*(3+4)"])
        XCTAssertEqual(try SmartCalc.evaluate("12*(3+4)", rates: nil).get().text, "84")
    }

    func testTheCardIsTheSizeOfTheDesign() {
        guard let calc = WidgetCatalog.make(.calculator) else { return XCTFail("no calc") }
        XCTAssertEqual(WidgetCatalog.naturalSize(calc).width, 184)
        XCTAssertEqual(WidgetCatalog.contentSize(calc, position: .bottom).height, 58)
    }
}
