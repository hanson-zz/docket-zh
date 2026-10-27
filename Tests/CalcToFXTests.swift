import Foundation
import XCTest

/// 「算」计算页「换汇率」：结果带到汇率页的金额栏（`CurrencyDesk.carryAmount`、`receiving`）。
final class CalcToFXTests: XCTestCase {

    private let rates = CurrencyRates(base: "CNY",
                                      rates: ["CNY": 1, "USD": 0.14, "EUR": 0.13, "JPY": 21.0],
                                      updated: Date(timeIntervalSince1970: 1_760_000_000))

    private func outcome(_ text: String, grouping: Bool = false) throws -> SmartCalc.Outcome {
        var config = WidgetConfig()
        config.set(CalcNumberStyle.groupingKey, .bool(grouping))
        let prefs = SmartCalc.Preferences(config)
        return try XCTUnwrap(try? SmartCalc.evaluate(text, rates: rates, preferences: prefs).get(),
                             "\(text) should evaluate")
    }

    private func carried(_ text: String, grouping: Bool = false) throws -> CurrencyDesk.Carry? {
        CurrencyDesk.carryAmount(from: try outcome(text, grouping: grouping))
    }

    // MARK: 取值

    func testAnIntegerResultCarriesAsIs() throws {
        XCTAssertEqual(try carried("3*4+2"), CurrencyDesk.Carry(amount: "14"))
        XCTAssertEqual(try carried("128"), CurrencyDesk.Carry(amount: "128"), "a plain number carries too")
    }

    func testADecimalResultKeepsItsPrecision() throws {
        XCTAssertEqual(try carried("12.5*3")?.amount, "37.5")
        XCTAssertEqual(try carried("0.1+0.2")?.amount, "0.3", "floating noise is dropped")
    }

    func testANegativeResultKeepsItsSign() throws {
        XCTAssertEqual(try carried("5-17.5")?.amount, "-12.5")
        XCTAssertEqual(try carried("-0")?.amount, "0")
    }

    func testAGroupedResultCarriesWithoutCommas() throws {
        let out = try outcome("1234567.5*1", grouping: true)
        XCTAssertTrue(out.text.contains(","), "the panel shows thousands separators")
        XCTAssertEqual(CurrencyDesk.carryAmount(from: out)?.amount, "1234567.5")
        XCTAssertEqual(try carried("1,299*3+50")?.amount, "3947")
    }

    func testAUnitResultCannotBeCarried() throws {
        XCTAssertNil(try carried("5 km"))
        XCTAssertNil(try carried("100 kg to lb"))
    }

    func testACurrencyResultCarriesItsAmountAndCode() throws {
        let carry = try XCTUnwrap(try carried("100 usd to jpy"))
        XCTAssertEqual(carry.code, "JPY")
        XCTAssertEqual(carry.amount, "15000", "JPY has no minor unit")
        let euros = try XCTUnwrap(try carried("100 cny to eur"))
        XCTAssertEqual(euros, CurrencyDesk.Carry(amount: "13", code: "EUR"))
        let dollars = try XCTUnwrap(try carried("1000 jpy to usd"))
        XCTAssertEqual(dollars.amount, "6.67", "rounded to the target currency's cents")
    }

    func testALongFractionIsCut() throws {
        XCTAssertEqual(try carried("10/3")?.amount, "3.3333333333")
        XCTAssertEqual(try carried("2/3")?.amount, "0.6666666667")
        XCTAssertEqual(CurrencyDesk.carryNumber(1e-12), "0", "below the last carried digit")
    }

    func testHugeOrBrokenValuesCannotBeCarried() {
        let big = SmartCalc.Outcome(kind: .math, value: 1e16, text: "1e+16", unit: "", source: "",
                                    sourceUnit: "", rate: nil, category: nil)
        XCTAssertNil(CurrencyDesk.carryAmount(from: big))
        var nan = big
        nan.value = .nan
        XCTAssertNil(CurrencyDesk.carryAmount(from: nan))
        var noCode = big
        noCode.kind = .currency
        noCode.value = 10
        XCTAssertNil(CurrencyDesk.carryAmount(from: noCode))
    }

    // MARK: 汇率页收下

    func testReceivingAPlainNumberKeepsTheCurrencies() {
        let state = CurrencyDesk.State(from: "USD", to: "CNY", amount: "100", favorites: ["1 EUR to CNY"])
        let next = CurrencyDesk.receiving(CurrencyDesk.Carry(amount: "37.5"), into: state)
        XCTAssertEqual(next.from, "USD")
        XCTAssertEqual(next.to, "CNY")
        XCTAssertEqual(next.amount, "37.5")
        XCTAssertEqual(next.favorites, state.favorites)
        XCTAssertEqual(next.list, state.list)
        let out = CurrencyDesk.convert(next, rates: rates)
        XCTAssertEqual(try XCTUnwrap(out.result).value, 37.5 / 0.14, accuracy: 1e-9, "converts right away")
    }

    func testReceivingACurrencyMovesItToFrom() {
        let state = CurrencyDesk.State(from: "USD", to: "CNY", amount: "100")
        let next = CurrencyDesk.receiving(CurrencyDesk.Carry(amount: "15000", code: "jpy"), into: state)
        XCTAssertEqual(next.from, "JPY")
        XCTAssertEqual(next.to, "CNY")
        XCTAssertEqual(next.amount, "15000")
    }

    func testReceivingTheTargetCurrencySwaps() {
        let state = CurrencyDesk.State(from: "USD", to: "CNY", amount: "100")
        let next = CurrencyDesk.receiving(CurrencyDesk.Carry(amount: "714.29", code: "CNY"), into: state)
        XCTAssertEqual(next.from, "CNY")
        XCTAssertEqual(next.to, "USD")
        XCTAssertEqual(next.amount, "714.29")
    }

    func testReceivingSettlesATypedPairFirst() {
        let state = CurrencyDesk.State(from: "USD", to: "CNY", amount: "100 eur to jpy")
        let next = CurrencyDesk.receiving(CurrencyDesk.Carry(amount: "8"), into: state)
        XCTAssertEqual(next.from, "EUR")
        XCTAssertEqual(next.to, "JPY")
        XCTAssertEqual(next.amount, "8")
    }

    // MARK: 切到汇率页时自动同步

    private func sync(from previous: CurrencyDesk.Mode? = .calc, to next: CurrencyDesk.Mode = .fx,
                      _ input: String, last: String = "") throws -> CurrencyDesk.Carry? {
        let carry = CurrencyDesk.carryAmount(from: try outcome(input))
        return CurrencyDesk.autoSync(from: previous, to: next, input: input, carry: carry, lastSynced: last)
    }

    func testSwitchingWithAFreshResultSyncs() throws {
        XCTAssertEqual(try sync("12.5*3"), CurrencyDesk.Carry(amount: "37.5"))
        XCTAssertEqual(try sync("100 usd to jpy"), CurrencyDesk.Carry(amount: "15000", code: "JPY"),
                       "a currency result carries its code, same as the button")
    }

    func testAChangedResultSyncsAgain() throws {
        let first = try XCTUnwrap(try sync("12.5*3"))
        let last = CurrencyDesk.syncSignature(input: "12.5*3", carry: first)
        XCTAssertEqual(try sync("12.5*4", last: last), CurrencyDesk.Carry(amount: "50"))
    }

    func testAnUnchangedResultDoesNotOverwrite() throws {
        let first = try XCTUnwrap(try sync("12.5*3"))
        let last = CurrencyDesk.syncSignature(input: "12.5*3", carry: first)
        XCTAssertNil(try sync("12.5*3", last: last), "the amount typed on the FX page stays")
        XCTAssertNil(try sync("  12.5*3 ", last: last), "surrounding spaces are not a change")
    }

    func testAResultThatCannotBeCarriedDoesNotSync() throws {
        XCTAssertNil(try sync("5 km"))
        XCTAssertNil(try sync("100 kg to lb"))
        XCTAssertNil(CurrencyDesk.autoSync(from: .calc, to: .fx, input: "", carry: nil, lastSynced: ""),
                     "an empty calculator leaves the FX page alone")
        XCTAssertNil(CurrencyDesk.autoSync(from: .calc, to: .fx, input: "1+", carry: nil, lastSynced: ""),
                     "an error leaves the FX page alone")
        XCTAssertNil(CurrencyDesk.autoSync(from: .calc, to: .fx, input: "  ", carry: CurrencyDesk.Carry(amount: "1"),
                                           lastSynced: ""))
    }

    func testOpeningOnTheFXPageDoesNotSync() throws {
        XCTAssertNil(try sync(from: nil, "12.5*3"), "opening the panel on the FX page is not a switch")
        XCTAssertNil(try sync(from: .fx, "12.5*3"))
        XCTAssertNil(try sync(from: .fx, to: .calc, "12.5*3"), "going back to the calculator never syncs")
    }

    func testTheSignatureTellsInputsAndCodesApart() {
        let plain = CurrencyDesk.syncSignature(input: "15000", carry: CurrencyDesk.Carry(amount: "15000"))
        let yen = CurrencyDesk.syncSignature(input: "15000", carry: CurrencyDesk.Carry(amount: "15000", code: "JPY"))
        XCTAssertNotEqual(plain, yen)
        let other = CurrencyDesk.syncSignature(input: "3*5000", carry: CurrencyDesk.Carry(amount: "15000"))
        XCTAssertNotEqual(plain, other, "a new calculation with the same result still counts as new")
    }
}
