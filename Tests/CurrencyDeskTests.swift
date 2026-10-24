import Foundation
import XCTest

/// 「算」面板的汇率页：从 / 到两行、对调、多币种、收藏、记录、小键盘和卡片轮播。
final class CurrencyDeskTests: XCTestCase {

    /// 1 CNY 值多少：USD 0.14、JPY 21、EUR 0.13、HKD 1.09、GBP 0.105、KWD 0.043。
    private let rates = CurrencyRates(base: "CNY",
                                      rates: ["CNY": 1, "USD": 0.14, "EUR": 0.13, "JPY": 21.0, "HKD": 1.09,
                                              "GBP": 0.105, "KWD": 0.043, "BTC": 0.0000015],
                                      updated: Date(timeIntervalSince1970: 1_760_000_000))

    private var codes: Set<String> { SmartCalc.commonCodes.union(rates.rates.keys) }

    // MARK: 币种目录

    func testMinorUnitsFollowTheCurrency() {
        XCTAssertEqual(CurrencyCatalog.fractionDigits("usd"), 2)
        XCTAssertEqual(CurrencyCatalog.fractionDigits("JPY"), 0)
        XCTAssertEqual(CurrencyCatalog.fractionDigits("KRW"), 0)
        XCTAssertEqual(CurrencyCatalog.fractionDigits("KWD"), 3)
        XCTAssertEqual(CurrencyCatalog.format(2105.4, code: "JPY"), "2,105")
        XCTAssertEqual(CurrencyCatalog.format(1234.5, code: "USD"), "1,234.50")
        XCTAssertEqual(CurrencyCatalog.format(1.23456, code: "KWD"), "1.235")
        XCTAssertEqual(CurrencyCatalog.format(1_234_567.891, code: "CNY"), "1,234,567.89")
        XCTAssertEqual(CurrencyCatalog.format(-1234.5, code: "USD"), "-1,234.50")
        XCTAssertEqual(CurrencyCatalog.format(.infinity, code: "USD"), "-")
    }

    func testTinyAmountsAreNotRoundedAway() {
        XCTAssertEqual(CurrencyCatalog.format(0.47, code: "JPY"), "0.47", "under one yen still shows")
        XCTAssertEqual(CurrencyCatalog.format(0.0015, code: "BTC"), "0.001500")
        XCTAssertEqual(CurrencyCatalog.format(0, code: "JPY"), "0")
        XCTAssertEqual(CurrencyCatalog.plain(0.0015, code: "BTC"), "0.0015")
    }

    func testOldFormatterNowFollowsTheCatalog() {
        XCTAssertEqual(CurrencyNames.format(1234.5, code: "USD"), "1,234.50")
        XCTAssertEqual(CurrencyNames.format(2105.4, code: "JPY"), "2,105")
        XCTAssertEqual(CurrencyNames.format(1.23456, code: "KWD"), "1.235")
    }

    func testPlainRoundsToMinorUnitsWithoutGrouping() {
        XCTAssertEqual(CurrencyCatalog.plain(28101.876, code: "CNY"), "28101.88")
        XCTAssertEqual(CurrencyCatalog.plain(592480.4, code: "JPY"), "592480")
        XCTAssertEqual(CurrencyCatalog.plain(100, code: "USD"), "100")
        XCTAssertEqual(CurrencyCatalog.plain(12.5, code: "USD"), "12.5")
    }

    func testStyleOverridesTheMinorUnits() {
        let four = CalcNumberStyle(decimals: .four, grouping: true)
        XCTAssertEqual(CurrencyCatalog.format(2105.4, code: "JPY", style: four), "2,105.4000")
        let plain = CalcNumberStyle(decimals: .auto, grouping: false)
        XCTAssertEqual(CurrencyCatalog.format(2105.4, code: "JPY", style: plain), "2105")
    }

    func testFlagsComeFromTheRegionCode() {
        XCTAssertEqual(CurrencyCatalog.flag("CNY"), "🇨🇳")
        XCTAssertEqual(CurrencyCatalog.flag("usd"), "🇺🇸")
        XCTAssertEqual(CurrencyCatalog.flag("EUR"), "🇪🇺")
        XCTAssertNil(CurrencyCatalog.flag("XAU"), "no flag for gold or SDR")
        XCTAssertNil(CurrencyCatalog.flag("12"))
    }

    func testNamesAndSymbols() {
        XCTAssertEqual(CurrencyCatalog.name("CNY"), "人民币")
        XCTAssertEqual(CurrencyCatalog.name("kwd"), "科威特第纳尔", "names outside the common twenty come from the city table")
        XCTAssertEqual(CurrencyCatalog.symbol("HKD"), "HK$")
        XCTAssertEqual(CurrencyCatalog.symbol("ZZZ"), "ZZZ")
    }

    func testRateTextReadsLikeABankBoard() {
        XCTAssertEqual(CurrencyCatalog.rateText(7.11981), "7.1198")
        XCTAssertEqual(CurrencyCatalog.rateText(153.214), "153.21")
        XCTAssertEqual(CurrencyCatalog.rateText(0.140449), "0.1404")
        XCTAssertEqual(CurrencyCatalog.rateText(0.00681234), "0.006812")
        XCTAssertEqual(CurrencyCatalog.rateLine(from: "usd", to: "cny", rate: 7.11981), "1 USD = 7.1198 CNY")
        XCTAssertEqual(CurrencyCatalog.rateText(0), "-")
    }

    func testSearchPutsCodePrefixFirstAndPinnedOnTop() {
        let all = CurrencyCatalog.codes(rates)
        XCTAssertEqual(CurrencyCatalog.search("hk", codes: all, pinned: []).first?.code, "HKD")
        XCTAssertEqual(CurrencyCatalog.search("港", codes: all, pinned: []).first?.code, "HKD")
        XCTAssertEqual(CurrencyCatalog.search("美金", codes: all, pinned: []).first?.code, "USD", "aliases count")
        XCTAssertEqual(CurrencyCatalog.search("€", codes: all, pinned: []).first?.code, "EUR", "symbols count")
        XCTAssertTrue(CurrencyCatalog.search("zzzz", codes: all, pinned: []).isEmpty)
        let empty = CurrencyCatalog.search("", codes: all, pinned: ["JPY", "CNY", "JPY"])
        XCTAssertEqual(empty.prefix(2).map(\.code), ["JPY", "CNY"])
        XCTAssertEqual(Set(empty.map(\.code)).count, empty.count, "no duplicates")
        XCTAssertEqual(empty.count, Set(all).count)
    }

    func testCodesFallBackToTheCommonListWithoutRates() {
        XCTAssertEqual(Set(CurrencyCatalog.codes(nil)), SmartCalc.commonCodes)
        XCTAssertTrue(CurrencyCatalog.codes(rates).contains("KWD"))
    }

    // MARK: 状态和兼容

    func testANewWidgetStartsFromTheSettingsPair() {
        let config = WidgetConfig([SmartCalc.currencyFromKey: .string("EUR"), SmartCalc.currencyToKey: .string("JPY")])
        let state = CurrencyDesk.State(config)
        XCTAssertEqual(state.from, "EUR")
        XCTAssertEqual(state.to, "JPY")
        XCTAssertEqual(state.amount, "100")
        XCTAssertEqual(state.list, CurrencyDesk.defaultList)
        XCTAssertEqual(state.favorites, [])
    }

    func testAnOldWidgetPicksUpItsLastConversion() {
        // 旧汇率卡片迁移过来就是这样。
        let migrated = SmartCalc.migratingCurrency(WidgetConfig(["from": .string("GBP"), "to": .string("HKD"),
                                                                  "amount": .number(250)]))
        let state = CurrencyDesk.State(migrated)
        XCTAssertEqual(state.from, "GBP")
        XCTAssertEqual(state.to, "HKD")
        XCTAssertEqual(state.amount, "250")
        XCTAssertEqual(CurrencyDesk.mode(migrated), .fx)
    }

    func testModeFollowsWhatTheCardShowsUntilChosen() {
        XCTAssertEqual(CurrencyDesk.mode(WidgetConfig()), .fx)
        XCTAssertEqual(CurrencyDesk.mode(WidgetConfig([SmartCalc.expressionKey: .string("5 km")])), .calc)
        XCTAssertEqual(CurrencyDesk.mode(WidgetConfig([SmartCalc.expressionKey: .string("3*4")])), .calc)
        XCTAssertEqual(CurrencyDesk.mode(WidgetConfig([SmartCalc.expressionKey: .string("100 usd")])), .fx)
        XCTAssertEqual(CurrencyDesk.mode(WidgetConfig([SmartCalc.expressionKey: .string("5 km"),
                                                       CurrencyDesk.modeKey: .string("fx")])), .fx)
    }

    func testStateRoundTripsThroughTheConfig() {
        let state = CurrencyDesk.State(from: "jpy", to: "usd", amount: "1,299*3", list: ["EUR", "eur", "HKD", "bad!"],
                                       favorites: ["100 USD to CNY"])
        XCTAssertEqual(state.list, ["EUR", "HKD"], "cleaned and deduplicated")
        var config = WidgetConfig()
        state.write(into: &config)
        XCTAssertEqual(CurrencyDesk.State(config), state)
        // 清空了的列表照样是空的，不退回默认。
        var emptied = config
        emptied.set(CurrencyDesk.listKey, .list([]))
        XCTAssertEqual(CurrencyDesk.State(emptied).list, [])
    }

    func testOldHistoryAndPinAreUntouched() {
        var config = WidgetConfig([SmartCalc.historyKey: .list([.string("5 km")]), SmartCalc.pinnedKey: .string("1 USD")])
        CurrencyDesk.State(config).write(into: &config)
        XCTAssertEqual(config.strings(SmartCalc.historyKey), ["5 km"])
        XCTAssertEqual(config.string(SmartCalc.pinnedKey), "1 USD")
    }

    // MARK: 读金额和换算

    func testAPlainAmountConverts() throws {
        let state = CurrencyDesk.State(from: "USD", to: "CNY", amount: "100")
        let out = CurrencyDesk.convert(state, rates: rates)
        let result = try XCTUnwrap(out.result)
        XCTAssertEqual(result.value, 100 / 0.14, accuracy: 1e-9)
        XCTAssertEqual(result.text, "714.29")
        XCTAssertFalse(out.reading.isExpression)
        XCTAssertEqual(out.amountText, "100.00")
        XCTAssertEqual(out.rateLine, "1 USD = 7.1429 CNY")
        XCTAssertEqual(out.inverseLine, "1 CNY = 0.1400 USD")
        XCTAssertEqual(out.sentence, "100.00 USD = 714.29 CNY")
        XCTAssertEqual(out.copyText, "714.29")
        XCTAssertEqual(out.carryText, "714.29")
    }

    func testAnExpressionAmountConverts() throws {
        let state = CurrencyDesk.State(from: "USD", to: "CNY", amount: "1,299*3+50")
        let out = CurrencyDesk.convert(state, rates: rates)
        XCTAssertTrue(out.reading.isExpression)
        XCTAssertEqual(try XCTUnwrap(out.reading.amount), 3947, accuracy: 1e-9)
        XCTAssertEqual(out.amountText, "3,947.00")
        XCTAssertEqual(out.copyText, "28192.86", "copied without grouping")
    }

    func testTypingCurrenciesInTheAmountMovesTheRows() {
        let state = CurrencyDesk.State(from: "USD", to: "CNY", amount: "1299*3+50 eur to jpy")
        let reading = CurrencyDesk.read(state, codes: codes)
        XCTAssertTrue(reading.typedCodes)
        XCTAssertEqual(reading.from, "EUR")
        XCTAssertEqual(reading.to, "JPY")
        XCTAssertEqual(reading.amount ?? 0, 3947, accuracy: 1e-9)

        // 只写一种：写的是「到」那种就对调。
        let flipped = CurrencyDesk.read(CurrencyDesk.State(from: "USD", to: "CNY", amount: "500 元"), codes: codes)
        XCTAssertEqual(flipped.from, "CNY")
        XCTAssertEqual(flipped.to, "USD")
        let other = CurrencyDesk.read(CurrencyDesk.State(from: "USD", to: "CNY", amount: "500 hkd"), codes: codes)
        XCTAssertEqual(other.from, "HKD")
        XCTAssertEqual(other.to, "CNY")
    }

    func testEmptyAmountShowsOneUnit() {
        let out = CurrencyDesk.convert(CurrencyDesk.State(from: "USD", to: "JPY", amount: " "), rates: rates)
        XCTAssertEqual(out.reading.amount, 1)
        XCTAssertEqual(out.result?.text, "150")
    }

    func testABrokenExpressionSaysWhy() {
        let out = CurrencyDesk.convert(CurrencyDesk.State(amount: "3*/"), rates: rates)
        XCTAssertNil(out.reading.amount)
        XCTAssertNotNil(out.reading.failure)
        XCTAssertNil(out.result)
        XCTAssertNotNil(out.rateLine, "the rate itself still shows")
        XCTAssertEqual(out.amountText, "-")
    }

    func testNoRatesYetGivesNoResult() {
        let out = CurrencyDesk.convert(CurrencyDesk.State(), rates: nil)
        XCTAssertNil(out.result)
        XCTAssertNil(out.rateLine)
        XCTAssertEqual(out.list, [])
    }

    func testMultiCurrencyListSkipsTheTwoRowsAndMissingRates() {
        let state = CurrencyDesk.State(from: "USD", to: "CNY", amount: "100", list: ["JPY", "CNY", "ZAR", "EUR", "USD"])
        let out = CurrencyDesk.convert(state, rates: rates)
        XCTAssertEqual(out.list.map(\.code), ["JPY", "EUR"], "from/to hidden, ZAR has no rate")
        XCTAssertEqual(out.list.first?.text, "15,000")
        XCTAssertEqual(state.shownList, ["JPY", "ZAR", "EUR"])
    }

    // MARK: 操作

    func testSwapKeepsTheAmount() {
        let state = CurrencyDesk.State(from: "USD", to: "CNY", amount: "100")
        let next = CurrencyDesk.swapped(state)
        XCTAssertEqual(next.from, "CNY")
        XCTAssertEqual(next.to, "USD")
        XCTAssertEqual(next.amount, "100")
        XCTAssertEqual(CurrencyDesk.swapped(next), state)
    }

    func testSwapSettlesTypedCurrenciesFirst() {
        let state = CurrencyDesk.State(from: "USD", to: "CNY", amount: "20 eur to jpy")
        let next = CurrencyDesk.swapped(state, codes: codes)
        XCTAssertEqual(next.from, "JPY")
        XCTAssertEqual(next.to, "EUR")
        XCTAssertEqual(next.amount, "20")
    }

    func testChoosingTheOtherRowsCurrencySwaps() {
        let state = CurrencyDesk.State(from: "USD", to: "CNY")
        XCTAssertEqual(CurrencyDesk.choosingFrom("cny", in: state).from, "CNY")
        XCTAssertEqual(CurrencyDesk.choosingFrom("cny", in: state).to, "USD")
        XCTAssertEqual(CurrencyDesk.choosingTo("USD", in: state).to, "USD")
        XCTAssertEqual(CurrencyDesk.choosingTo("USD", in: state).from, "CNY")
        XCTAssertEqual(CurrencyDesk.choosingFrom("EUR", in: state).from, "EUR")
        XCTAssertEqual(CurrencyDesk.choosingFrom("EUR", in: state).to, "CNY")
    }

    func testChoosingAListedTargetKeepsTheListWhole() {
        let state = CurrencyDesk.State(from: "USD", to: "CNY", list: ["JPY", "EUR"])
        let next = CurrencyDesk.choosingTo("EUR", in: state)
        XCTAssertEqual(next.to, "EUR")
        XCTAssertEqual(next.list, ["JPY", "CNY"], "the old target takes its place")
    }

    func testPromotingARowKeepsEveryValue() throws {
        let state = CurrencyDesk.State(from: "USD", to: "CNY", amount: "100", list: ["JPY", "EUR"])
        let before = CurrencyDesk.convert(state, rates: rates)
        let next = CurrencyDesk.promoting("JPY", in: state, rates: rates)
        XCTAssertEqual(next.from, "JPY")
        XCTAssertEqual(next.amount, "15000")
        XCTAssertEqual(next.list, ["USD", "EUR"])
        let after = CurrencyDesk.convert(next, rates: rates)
        XCTAssertEqual(try XCTUnwrap(after.result?.value), try XCTUnwrap(before.result?.value), accuracy: 0.01)
        XCTAssertEqual(after.list.map(\.code), ["USD", "EUR"])
        XCTAssertEqual(after.list.first?.text, "100.00")
    }

    func testPromotingTheTargetJustSwaps() {
        let state = CurrencyDesk.State(from: "USD", to: "CNY")
        XCTAssertEqual(CurrencyDesk.promoting("CNY", in: state, rates: rates), CurrencyDesk.swapped(state))
        XCTAssertEqual(CurrencyDesk.promoting("USD", in: state, rates: rates), state)
    }

    func testArrowKeysCycleTheTarget() {
        let state = CurrencyDesk.State(from: "USD", to: "CNY", list: ["JPY", "EUR"])
        let down = CurrencyDesk.cyclingTarget(state, step: 1)
        XCTAssertEqual(down.to, "JPY")
        XCTAssertEqual(down.list, ["CNY", "EUR"])
        let up = CurrencyDesk.cyclingTarget(state, step: -1)
        XCTAssertEqual(up.to, "EUR")
        let lonely = CurrencyDesk.State(from: "USD", to: "CNY", list: ["USD"])
        XCTAssertEqual(CurrencyDesk.cyclingTarget(lonely, step: 1), lonely)
    }

    // MARK: 多币种列表

    func testListAddRemoveAndLimit() {
        var list = ["JPY"]
        list = CurrencyDesk.adding("eur", to: list)
        XCTAssertEqual(list, ["JPY", "EUR"])
        XCTAssertEqual(CurrencyDesk.adding("JPY", to: list), list, "no duplicates")
        XCTAssertEqual(CurrencyDesk.removing("jpy", from: list), ["EUR"])
        let full = Array(repeating: "", count: CurrencyDesk.listLimit).enumerated().map { "A\(Character(UnicodeScalar(65 + $0.offset)!))A" }
        XCTAssertFalse(CurrencyDesk.canAdd(full))
        XCTAssertEqual(CurrencyDesk.adding("ZZZ", to: full), full)
    }

    func testReorderingTheShownRowsMapsBackToTheStoredList() {
        let state = CurrencyDesk.State(from: "USD", to: "CNY", list: ["JPY", "USD", "EUR", "HKD"])
        XCTAssertEqual(state.shownList, ["JPY", "EUR", "HKD"])
        XCTAssertEqual(CurrencyDesk.movingShown(state, from: 2, to: 0), ["HKD", "USD", "JPY", "EUR"])
        XCTAssertEqual(CurrencyDesk.movingShown(state, from: 0, to: 0), state.list)
        XCTAssertEqual(CurrencyDesk.dropIndex(from: 0, offset: 82, step: 40, count: 3), 2)
        XCTAssertEqual(CurrencyDesk.dropIndex(from: 1, offset: -500, step: 40, count: 3), 0)
        XCTAssertEqual(CurrencyDesk.moving(["A", "B", "C"], from: 0, to: 9), ["B", "C", "A"])
    }

    // MARK: 记录和收藏

    func testEntriesUseTheTapeSyntax() {
        XCTAssertEqual(CurrencyDesk.entry(CurrencyDesk.State(from: "USD", to: "CNY", amount: "1,299*3+50")),
                       "1299*3+50 USD to CNY")
        XCTAssertEqual(CurrencyDesk.entry(CurrencyDesk.State(from: "USD", to: "CNY", amount: "")), "1 USD to CNY")
        XCTAssertEqual(CurrencyDesk.entry(CurrencyDesk.State(from: "USD", to: "CNY", amount: "20 eur to jpy"), codes: codes),
                       "20 EUR to JPY")
        XCTAssertNil(CurrencyDesk.entry(CurrencyDesk.State(amount: "3*/")))
        // 记下的这一条在计算页和卡片上照样能算。
        let entry = CurrencyDesk.entry(CurrencyDesk.State(from: "USD", to: "CNY", amount: "1299*3+50"))!
        guard case .success(let out) = SmartCalc.evaluate(entry, rates: rates) else { return XCTFail("tape entry evaluates") }
        XCTAssertEqual(out.value, 3947 / 0.14, accuracy: 1e-6)
    }

    func testLoadingAnEntryRestoresTheRows() {
        let base = CurrencyDesk.State(from: "USD", to: "CNY", list: ["JPY"])
        let loaded = CurrencyDesk.loading("1299*3+50 EUR to JPY", into: base, codes: codes)
        XCTAssertEqual(loaded?.from, "EUR")
        XCTAssertEqual(loaded?.to, "JPY")
        XCTAssertEqual(loaded?.amount, "1299*3+50", "the expression comes back for editing")
        XCTAssertEqual(loaded?.list, ["JPY"])
        XCTAssertEqual(CurrencyDesk.loading("100美元", into: base)?.amount, "100")
        XCTAssertEqual(CurrencyDesk.loading("100美元", into: base)?.to, "CNY")
        XCTAssertNil(CurrencyDesk.loading("5 km", into: base))
    }

    func testLabelsAreShort() {
        XCTAssertEqual(CurrencyDesk.label("100 USD to CNY"), "100 USD → CNY")
        XCTAssertEqual(CurrencyDesk.label("1299*3+50 USD to CNY"), "1299*3+50 USD → CNY")
        XCTAssertEqual(CurrencyDesk.label("5 km"), "5 km")
    }

    func testFavoritesToggleAndCap() {
        var favorites = CurrencyDesk.togglingFavorite("100 USD to CNY", in: [])
        XCTAssertEqual(favorites, ["100 USD to CNY"])
        XCTAssertTrue(CurrencyDesk.isFavorite("100 usd to cny", in: favorites), "case and spaces do not matter")
        favorites = CurrencyDesk.togglingFavorite("1 EUR to CNY", in: favorites)
        XCTAssertEqual(favorites.first, "1 EUR to CNY")
        favorites = CurrencyDesk.togglingFavorite("100 usd to CNY", in: favorites)
        XCTAssertEqual(favorites, ["1 EUR to CNY"])
        var many: [String] = []
        for n in 0..<20 { many = CurrencyDesk.togglingFavorite("\(n) USD to CNY", in: many) }
        XCTAssertEqual(many.count, CurrencyDesk.favoritesLimit)
        XCTAssertEqual(many.first, "19 USD to CNY")
    }

    // MARK: 卡片轮播

    func testRotationNeedsProTwoFavoritesAndNoPin() {
        var config = WidgetConfig([CurrencyDesk.favoritesKey: .list([.string("100 USD to CNY"), .string("1 EUR to CNY")])])
        XCTAssertEqual(CurrencyDesk.rotation(config, unlocked: true).count, 2)
        XCTAssertEqual(CurrencyDesk.rotation(config, unlocked: false), [], "free cards show the last or pinned entry")
        config.set(SmartCalc.expressionKey, .string("100 HKD to CNY"))
        XCTAssertEqual(CurrencyDesk.rotation(config, unlocked: true).count, 2, "a currency entry keeps rotating")
        config.set(SmartCalc.expressionKey, .string("5 km"))
        XCTAssertEqual(CurrencyDesk.rotation(config, unlocked: true), [], "a fresh unit sum shows first")
        config.set(SmartCalc.expressionKey, nil)
        config.set(SmartCalc.pinnedKey, .string("5 km"))
        XCTAssertEqual(CurrencyDesk.rotation(config, unlocked: true), [], "a pin wins")
        let one = WidgetConfig([CurrencyDesk.favoritesKey: .list([.string("100 USD to CNY")])])
        XCTAssertEqual(CurrencyDesk.rotation(one, unlocked: true), [])
    }

    func testRotationIndexFollowsTheClock() {
        let start = Date(timeIntervalSince1970: 600)
        XCTAssertEqual(CurrencyDesk.rotationIndex(now: start, count: 3), 100 % 3)
        XCTAssertEqual(CurrencyDesk.rotationIndex(now: start.addingTimeInterval(6), count: 3), 101 % 3)
        XCTAssertEqual(CurrencyDesk.rotationIndex(now: start, count: 0), 0)
    }

    // MARK: 小键盘

    private func type(_ keys: [CurrencyDesk.Key], from text: String = "") -> String {
        keys.reduce(text) { CurrencyDesk.pressing($1, in: $0) }
    }

    func testKeypadBuildsAnExpression() {
        XCTAssertEqual(type([.digit(1), .digit(2), .multiply, .digit(3), .add, .digit(5), .doubleZero]), "12*3+500")
        XCTAssertEqual(type([.dot, .digit(5)]), "0.5")
        XCTAssertEqual(type([.digit(1), .dot, .dot, .digit(2), .dot]), "1.2", "one point per number")
        XCTAssertEqual(type([.digit(0), .digit(0), .digit(7)]), "7")
        XCTAssertEqual(type([.doubleZero]), "0")
        XCTAssertEqual(type([.digit(9), .back]), "")
        XCTAssertEqual(type([.digit(9), .clear]), "")
    }

    func testKeypadOperatorsReplaceEachOther() {
        XCTAssertEqual(type([.digit(2), .add, .multiply]), "2*")
        XCTAssertEqual(type([.multiply]), "", "no leading times")
        XCTAssertEqual(type([.subtract, .digit(3)]), "-3", "a leading minus is fine")
        XCTAssertEqual(type([.open, .subtract, .digit(1), .close]), "(-1)")
        XCTAssertEqual(type([.digit(2), .open, .digit(3), .close]), "2*(3)", "a bracket after a number multiplies")
        XCTAssertEqual(type([.close]), "", "nothing to close")
        XCTAssertEqual(type([.open, .digit(3), .add, .close]), "(3+", "cannot close after an operator")
    }

    func testKeypadResultEvaluates() {
        let text = type([.digit(1), .digit(2), .digit(9), .digit(9), .multiply, .digit(3), .add, .digit(5), .digit(0)])
        XCTAssertEqual(try Calculator.evaluate(text).get(), 3947)
        XCTAssertEqual(CurrencyDesk.keypad.flatMap { $0 }.count, 20)
    }
}

/// 汇率页的 Pro 划分：多币种列表和卡片轮播是 Pro，其余免费。
final class CurrencyDeskProTests: XCTestCase {
    func testOnlyTheListAndTheRotationArePro() {
        XCTAssertFalse(ProLicenseGate.canUseCurrencyList(unlocked: false))
        XCTAssertTrue(ProLicenseGate.canUseCurrencyList(unlocked: true))
        XCTAssertFalse(ProLicenseGate.canRotateCalcFavorites(unlocked: false))
        XCTAssertTrue(ProLicenseGate.canRotateCalcFavorites(unlocked: true))
        XCTAssertFalse(ProFeatures.isProKind(.calculator), "the calculator itself stays free")
    }
}
