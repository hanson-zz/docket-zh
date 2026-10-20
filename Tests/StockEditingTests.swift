import XCTest

/// 股票、自选股面板里的编辑：持仓（老格式兼容、带成本价）、加删排序、搜索。
final class StockEditingTests: XCTestCase {
    private func config(_ values: [String: WidgetConfig.Value]) -> WidgetConfig { WidgetConfig(values) }
    private func list(_ items: [String]) -> WidgetConfig.Value { .list(items.map { .string($0) }) }

    // MARK: 持仓

    /// 设置页里按老格式写的持仓照样读得出来，股数和以前一样。
    func testOldHoldingFormatsStillRead() {
        let old = config(["holdings": list(["NVDA 100", "aapl:50", "600519.SS=200", "0700.HK＝300",
                                            "TSLA\t-20", "bad", "MSFT 0", "AMD abc"])])
        XCTAssertEqual(StockBoard.holdings(old),
                       ["NVDA": 100, "AAPL": 50, "600519.SS": 200, "0700.HK": 300, "TSLA": -20])
        XCTAssertTrue(StockBoard.holdingEntries(old).values.allSatisfy { $0.cost == nil })
    }

    func testHoldingWithCost() {
        let new = config(["holdings": list(["NVDA 100 238", "AAPL 20 @150.5", "AMD 10 -3", "MSFT 5 x"])])
        let entries = StockBoard.holdingEntries(new)
        XCTAssertEqual(entries["NVDA"], StockBoard.Holding(shares: 100, cost: 238))
        XCTAssertEqual(entries["AAPL"], StockBoard.Holding(shares: 20, cost: 150.5))
        XCTAssertNil(entries["AMD"], "a bad cost drops the line rather than guessing")
        XCTAssertNil(entries["MSFT"])
        XCTAssertEqual(StockBoard.holdings(new), ["NVDA": 100, "AAPL": 20], "today's P/L still reads shares")
    }

    func testHoldingText() {
        XCTAssertEqual(StockBoard.holdingText("nvda", .init(shares: 100)), "NVDA 100")
        XCTAssertEqual(StockBoard.holdingText("NVDA", .init(shares: 100, cost: 238.5)), "NVDA 100 238.5")
        XCTAssertEqual(StockBoard.holdingLabel(nil), "持仓")
        XCTAssertEqual(StockBoard.holdingLabel(.init(shares: 100)), "100 股")
        XCTAssertEqual(StockBoard.holdingLabel(.init(shares: 100, cost: 238)), "100 股 @238")
        XCTAssertEqual(StockBoard.number(" 1,200.5 "), 1200.5)
        XCTAssertNil(StockBoard.number(""))
        XCTAssertNil(StockBoard.number("abc"))
        XCTAssertEqual(StockBoard.numberText(238), "238")
    }

    /// 面板里改一只：原来那行换掉、位置不变；别的行（包括写坏的）原样留着。
    func testSettingHoldingKeepsOtherLines() {
        let base = config(["holdings": list(["AAPL:50", "NVDA 100", "随便写的"])])
        XCTAssertEqual(StockBoard.settingHolding("nvda", .init(shares: 120, cost: 238), in: base),
                       ["AAPL:50", "NVDA 120 238", "随便写的"])
        XCTAssertEqual(StockBoard.settingHolding("TSLA", .init(shares: 50), in: base),
                       ["AAPL:50", "NVDA 100", "随便写的", "TSLA 50"])
        XCTAssertEqual(StockBoard.settingHolding("AAPL", nil, in: base), ["NVDA 100", "随便写的"])
        XCTAssertEqual(StockBoard.settingHolding("AAPL", .init(shares: 0), in: base), ["NVDA 100", "随便写的"])
        let dup = config(["holdings": list(["NVDA 1", "NVDA 2"])])
        XCTAssertEqual(StockBoard.settingHolding("NVDA", .init(shares: 3), in: dup), ["NVDA 3"])
        // 写回后读出来的就是填的。
        let saved = config(["holdings": list(StockBoard.settingHolding("NVDA", .init(shares: 120, cost: 238), in: base))])
        XCTAssertEqual(StockBoard.holdingEntries(saved)["NVDA"], .init(shares: 120, cost: 238))
        XCTAssertEqual(StockBoard.holdingEntries(saved)["AAPL"], .init(shares: 50))
    }

    func testHoldingProfit() {
        let positions = [StockBoard.Position(symbol: "NVDA", price: 250, change: 5, currency: "USD"),
                         StockBoard.Position(symbol: "AAPL", price: 200, change: 1, currency: "USD"),
                         StockBoard.Position(symbol: "0700.HK", price: 400, change: 2, currency: "HKD")]
        let profit = StockBoard.holdingProfit(positions, holdings: [
            "NVDA": .init(shares: 100, cost: 200), "AAPL": .init(shares: 10), "0700.HK": .init(shares: 100, cost: 420)])
        XCTAssertEqual(profit.map(\.currency), ["USD", "HKD"])
        XCTAssertEqual(profit[0].amount, 5_000, accuracy: 0.001)
        XCTAssertEqual(profit[0].percent ?? 0, 25, accuracy: 0.001)
        XCTAssertEqual(profit[1].amount, -2_000, accuracy: 0.001)
        XCTAssertTrue(StockBoard.holdingProfit(positions, holdings: ["AAPL": .init(shares: 10)]).isEmpty,
                      "no cost, no holding P/L")
    }

    // MARK: 加、删、排序

    func testWatchlistWithoutGroupsEditsSymbols() {
        let base = config(["symbols": list(["AAPL", "NVDA"])])
        XCTAssertEqual(StockBoard.editingSymbols(base, watchlist: true), ["AAPL", "NVDA"])
        let added = StockBoard.addingSymbol("tsla", to: base, watchlist: true)
        XCTAssertEqual(added?.strings("symbols", default: []), ["AAPL", "NVDA", "TSLA"])
        XCTAssertNil(StockBoard.addingSymbol("nvda", to: base, watchlist: true), "already there")
        XCTAssertNil(StockBoard.addingSymbol("  ", to: base, watchlist: true))
    }

    func testWatchlistWithGroupsEditsCurrentGroupOnly() {
        let base = config(["groups": list(["科技=NVDA TSLA", "港股=0700.HK"]), "group": .string("港股")])
        let next = StockBoard.addingSymbol("9988.HK", to: base, watchlist: true)!
        XCTAssertEqual(StockBoard.groups(next).map(\.text), ["科技=NVDA TSLA", "港股=0700.HK 9988.HK"])
        XCTAssertEqual(next.string("group", default: ""), "港股")
        let moved = StockBoard.settingSymbols(["9988.HK", "0700.HK"], in: next, watchlist: true)
        XCTAssertEqual(StockBoard.currentGroup(moved).symbols, ["9988.HK", "0700.HK"])
    }

    /// 删到只剩一只就不能再删：空列表会冒出默认的几只。
    func testLastSymbolStays() {
        XCTAssertFalse(StockBoard.canRemove(count: 1))
        XCTAssertTrue(StockBoard.canRemove(count: 2))
        let base = config(["symbols": list(["AAPL"])])
        XCTAssertEqual(StockBoard.settingSymbols([], in: base, watchlist: true), base)
    }

    func testStockRotationMovesCurrentWhenRemoved() {
        let base = config(["symbols": list(["AAPL", "NVDA"]), "symbol": .string("NVDA")])
        let next = StockBoard.settingSymbols(["AAPL"], in: base, watchlist: false)
        XCTAssertEqual(next.string("symbol", default: ""), "AAPL")
        XCTAssertEqual(StockBoard.rotation(next), ["AAPL"])
        let kept = StockBoard.settingSymbols(["NVDA", "AAPL"], in: base, watchlist: false)
        XCTAssertEqual(kept.string("symbol", default: ""), "NVDA")
        XCTAssertEqual(StockBoard.editingSymbols(config([:]), watchlist: false), ["AAPL"])
    }

    func testEditorLimit() {
        let many = (0..<StockBoard.editorLimit).map { "S\($0)" }
        let base = config(["symbols": list(many)])
        XCTAssertNil(StockBoard.addingSymbol("ONE", to: base, watchlist: true))
    }

    func testMoveAndDragTarget() {
        let items = ["A", "B", "C", "D"]
        XCTAssertEqual(StockBoard.moved(items, from: 0, to: 2), ["B", "C", "A", "D"])
        XCTAssertEqual(StockBoard.moved(items, from: 3, to: 0), ["D", "A", "B", "C"])
        XCTAssertEqual(StockBoard.moved(items, from: 1, to: 99), ["A", "C", "D", "B"])
        XCTAssertEqual(StockBoard.moved(items, from: 9, to: 0), items)
        XCTAssertEqual(StockBoard.dragTarget(from: 0, offset: 85, rowHeight: 42, count: 4), 2)
        XCTAssertEqual(StockBoard.dragTarget(from: 0, offset: 20, rowHeight: 42, count: 4), 0)
        XCTAssertEqual(StockBoard.dragTarget(from: 1, offset: -500, rowHeight: 42, count: 4), 0)
        XCTAssertEqual(StockBoard.dragTarget(from: 2, offset: 500, rowHeight: 42, count: 4), 3)
        XCTAssertEqual(StockBoard.dragTarget(from: 2, offset: .nan, rowHeight: 42, count: 4), 2)
    }

    // MARK: 搜索

    func testGuessFromCode() {
        XCTAssertEqual(StockSearch.guess("600519"), "600519.SS")
        XCTAssertEqual(StockSearch.guess("000001"), "000001.SZ")
        XCTAssertEqual(StockSearch.guess("300750"), "300750.SZ")
        XCTAssertEqual(StockSearch.guess("700"), "0700.HK")
        XCTAssertEqual(StockSearch.guess("00700"), "0700.HK")
        XCTAssertEqual(StockSearch.guess("9988"), "9988.HK")
        XCTAssertEqual(StockSearch.guess(" nvda "), "NVDA")
        XCTAssertEqual(StockSearch.guess("brk-b"), "BRK-B")
        XCTAssertEqual(StockSearch.guess("^gspc"), "^GSPC")
        XCTAssertNil(StockSearch.guess("茅台"))
        XCTAssertNil(StockSearch.guess("12345678"))
        XCTAssertNil(StockSearch.guess("000"))
        XCTAssertNil(StockSearch.guess(""))
    }

    func testLocalNamesFindChineseStocks() {
        XCTAssertEqual(StockSearch.local("茅台").map(\.symbol), ["600519.SS"])
        XCTAssertTrue(StockSearch.local("腾讯").map(\.symbol).contains("0700.HK"))
        XCTAssertTrue(StockSearch.local("nvd").map(\.symbol).contains("NVDA"))
        XCTAssertTrue(StockSearch.local("   ").isEmpty)
    }

    func testParseYahooSearch() {
        let json = """
        {"quotes":[{"symbol":"NVDA","shortname":"NVIDIA Corp","longname":"NVIDIA Corporation","exchDisp":"NASDAQ","quoteType":"EQUITY"},
                   {"symbol":"NVDA250117C00100000","quoteType":"OPTION"},
                   {"shortname":"no symbol"},
                   {"symbol":"NVDL","shortname":"GraniteShares 2x","exchDisp":"NASDAQ","quoteType":"ETF"}]}
        """
        let hits = StockSearch.parse(Data(json.utf8))
        XCTAssertEqual(hits.map(\.symbol), ["NVDA", "NVDL"])
        XCTAssertEqual(hits[0].name, "英伟达", "the known Chinese name wins")
        XCTAssertEqual(hits[1].name, "GraniteShares 2x")
        XCTAssertEqual(hits[1].exchange, "NASDAQ")
        XCTAssertTrue(StockSearch.parse(Data("Too Many Requests".utf8)).isEmpty)
    }

    func testMergedDedupesAndLimits() {
        let local = [StockSearch.Hit(symbol: "600519.SS", name: "贵州茅台")]
        let remote = (0..<8).map { StockSearch.Hit(symbol: "R\($0)", name: "") }
            + [StockSearch.Hit(symbol: "600519.ss", name: "Kweichow")]
        let merged = StockSearch.merged(local: local, remote: remote, guess: "600519.SS")
        XCTAssertEqual(merged.count, StockSearch.limit)
        XCTAssertEqual(merged.first?.name, "贵州茅台")
        XCTAssertEqual(merged.filter { $0.symbol == "600519.SS" }.count, 1)
        XCTAssertEqual(StockSearch.merged(local: [], remote: [], guess: "NVDA").map(\.symbol), ["NVDA"])
        XCTAssertNotNil(StockSearch.url("贵州 茅台"))
        XCTAssertNil(StockSearch.url("  "))
    }
}
