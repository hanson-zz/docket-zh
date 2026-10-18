import XCTest

/// 股票、自选股的纯逻辑：涨跌颜色、到价提醒、分时坐标、分组、排序、涨跌统计、
/// 色块深浅、持仓盈亏、“还有 N 只”，以及黄金白银的换算。
final class StockBoardTests: XCTestCase {

    // MARK: 涨跌颜色

    func testStocksDefaultToRedUpLikeCrypto() {
        let empty = WidgetConfig()
        XCTAssertEqual(StockBoard.colors(empty), .redUp)
        XCTAssertEqual(StockBoard.tone(2.41, colors: .redUp), .red)
        XCTAssertEqual(StockBoard.tone(-1.51, colors: .redUp), .green)
        XCTAssertEqual(StockBoard.tone(2.41, colors: .greenUp), .green)
        XCTAssertEqual(StockBoard.tone(-1.51, colors: .greenUp), .red)
        XCTAssertEqual(StockBoard.tone(0.001, colors: .redUp), .neutral)
        XCTAssertEqual(StockBoard.tone(nil, colors: .redUp), .neutral)
        XCTAssertEqual(StockBoard.colors(WidgetConfig(["colors": .string("greenUp")])), .greenUp)
    }

    func testTheCatalogDefaultsBothStockKindsToRedUp() throws {
        for kind in [WidgetKind.stock, .watchlist, .crypto] {
            let instance = try XCTUnwrap(WidgetCatalog.make(kind))
            XCTAssertEqual(ChangeColors.from(instance.config), .redUp, "\(kind)")
        }
    }

    func testChipsDeepenWithTheMove() {
        XCTAssertEqual(StockBoard.chipStrength(nil), 0.35)
        XCTAssertEqual(StockBoard.chipStrength(0), 0.35)
        XCTAssertLessThan(StockBoard.chipStrength(0.38), StockBoard.chipStrength(4.82))
        XCTAssertEqual(StockBoard.chipStrength(-5), 1)
        XCTAssertEqual(StockBoard.chipStrength(12), 1, "capped")
        XCTAssertEqual(StockBoard.chipStrength(2), StockBoard.chipStrength(-2), "a fall is as deep as a rise")
    }

    func testFormatting() {
        XCTAssertEqual(StockBoard.priceText(1486.2), "1,486.20")
        XCTAssertEqual(StockBoard.priceText(nil), "-")
        XCTAssertEqual(StockBoard.changeText(5.456), "+5.46")
        XCTAssertEqual(StockBoard.changeText(-22.8), "-22.80")
        XCTAssertEqual(StockBoard.percentText(2.41), "+2.41%")
        XCTAssertEqual(StockBoard.volumeText(48_120_000), "4,812万")
        XCTAssertEqual(StockBoard.volumeText(230_000_000), "2.3亿")
        XCTAssertEqual(StockBoard.volumeText(8600), "8,600")
        XCTAssertEqual(StockBoard.volumeText(nil), "-")
    }

    // MARK: 轮播和名称

    func testRotation() {
        let config = WidgetConfig(["symbols": .list([.string("aapl"), .string(" AAPL "), .string("600519.ss")])])
        XCTAssertEqual(StockBoard.rotation(config), ["AAPL", "600519.SS"])
        XCTAssertEqual(StockBoard.rotation(WidgetConfig(["symbol": .string("msft")])), ["MSFT"])
        XCTAssertEqual(StockBoard.rotation(WidgetConfig()), ["AAPL"])
        let list = ["AAPL", "600519.SS", "NVDA"]
        XCTAssertEqual(StockBoard.step(from: "NVDA", in: list), "AAPL", "wraps round")
        XCTAssertEqual(StockBoard.step(from: "AAPL", in: list, by: -1), "NVDA")
        XCTAssertEqual(StockBoard.step(from: "TSLA", in: list), "AAPL", "a symbol no longer listed starts again")
        XCTAssertNil(StockBoard.step(from: "AAPL", in: []))
    }

    func testNames() {
        XCTAssertEqual(StockBoard.displayName("aapl", fallback: "Apple Inc."), "苹果")
        XCTAssertEqual(StockBoard.displayName("600519.SS", fallback: nil), "贵州茅台")
        XCTAssertEqual(StockBoard.displayName("GC=F", fallback: "Gold Dec 26"), "黄金")
        XCTAssertEqual(StockBoard.displayName("ZZZ", fallback: "Zed Corp"), "Zed Corp")
        XCTAssertEqual(StockBoard.displayName("ZZZ", fallback: "ZZZ"), "", "the ticker twice reads as a bug")
        XCTAssertEqual(StockBoard.displaySymbol("si=f"), "白银")
        XCTAssertEqual(StockBoard.displaySymbol("nvda"), "NVDA")
    }

    // MARK: 到价提醒

    func testAlertsParseAndPrint() throws {
        let up = try XCTUnwrap(StockBoard.Alert.parse("aapl > 237"))
        XCTAssertEqual(up, StockBoard.Alert(symbol: "AAPL", price: 237, above: true))
        XCTAssertEqual(up.text, "AAPL>237")
        let down = try XCTUnwrap(StockBoard.Alert.parse("GC=F<2,300.5"))
        XCTAssertFalse(down.above)
        XCTAssertEqual(down.price, 2300.5)
        XCTAssertEqual(down.text, "GC=F<2300.5")
        XCTAssertEqual(StockBoard.Alert.parse("AAPL≥240")?.above, true)
        XCTAssertNil(StockBoard.Alert.parse("AAPL 237"))
        XCTAssertNil(StockBoard.Alert.parse(">237"))
        XCTAssertNil(StockBoard.Alert.parse("AAPL>abc"))
        XCTAssertNil(StockBoard.Alert.parse("AAPL>-3"))
        let config = WidgetConfig(["alerts": .list([.string("AAPL>237"), .string("aapl > 237"), .string("junk")])])
        XCTAssertEqual(StockBoard.alerts(config).count, 1, "duplicates and junk dropped")
    }

    func testDistanceToTheAlert() throws {
        let alert = StockBoard.Alert(symbol: "AAPL", price: 237, above: true)
        XCTAssertEqual(try XCTUnwrap(alert.distance(from: 232.18)), 2.076, accuracy: 0.001)
        XCTAssertEqual(StockBoard.distanceText(alert, price: 232.18), "距提醒价 2.1%")
        XCTAssertEqual(alert.distance(from: 240), 0)
        XCTAssertEqual(StockBoard.distanceText(alert, price: 240), "已到提醒价")
        XCTAssertNil(alert.distance(from: nil))
        let below = StockBoard.Alert(symbol: "AAPL", price: 220, above: false)
        XCTAssertFalse(below.isReached(by: 232))
        XCTAssertTrue(below.isReached(by: 220))
        XCTAssertTrue(below.isReached(by: 219))
    }

    func testTheCardShowsTheNearestOpenAlert() {
        let alerts = [
            StockBoard.Alert(symbol: "AAPL", price: 250, above: true),
            StockBoard.Alert(symbol: "AAPL", price: 228, above: false),
            StockBoard.Alert(symbol: "AAPL", price: 230, above: true),
            StockBoard.Alert(symbol: "NVDA", price: 140, above: true),
        ]
        XCTAssertEqual(StockBoard.nearestAlert(for: "aapl", price: 232, in: alerts)?.price, 228,
                       "the one at 230 is already reached")
        XCTAssertNil(StockBoard.nearestAlert(for: "TSLA", price: 232, in: alerts))
    }

    func testEachAlertNotifiesOnce() {
        let alerts = [
            StockBoard.Alert(symbol: "AAPL", price: 237, above: true),
            StockBoard.Alert(symbol: "NVDA", price: 140, above: false),
        ]
        let prices = ["AAPL": 237.5, "NVDA": 142.0]
        let first = StockBoard.newlyReached(alerts, prices: prices, fired: [])
        XCTAssertEqual(first.map(\.symbol), ["AAPL"])
        let again = StockBoard.newlyReached(alerts, prices: prices, fired: Set(first.map(\.text)))
        XCTAssertTrue(again.isEmpty, "once only")
        XCTAssertTrue(StockBoard.newlyReached(alerts, prices: [:], fired: []).isEmpty, "no price, no alert")
        XCTAssertEqual(StockBoard.prunedFired(["AAPL>237", "TSLA>300"], alerts: alerts), ["AAPL>237"])
    }

    func testAnAlertMadeInThePanelPicksItsDirection() {
        XCTAssertEqual(StockBoard.makeAlert(symbol: "aapl", target: 237, current: 232)?.above, true)
        XCTAssertEqual(StockBoard.makeAlert(symbol: "aapl", target: 220, current: 232)?.above, false)
        XCTAssertEqual(StockBoard.makeAlert(symbol: "aapl", target: 220, current: nil)?.above, true)
        XCTAssertNil(StockBoard.makeAlert(symbol: "aapl", target: 0, current: 232))
    }

    // MARK: 分时图

    func testSessionStatus() {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 2_000)
        XCTAssertEqual(StockBoard.session(now: Date(timeIntervalSince1970: 1_500), start: start, end: end), .open)
        XCTAssertEqual(StockBoard.session(now: Date(timeIntervalSince1970: 2_500), start: start, end: end), .closed)
        XCTAssertEqual(StockBoard.session(now: Date(), start: nil, end: end), .unknown)
        XCTAssertEqual(StockBoard.Session.open.title, "盘中")
    }

    func testIntradayFillsTheSessionAndStopsAtNow() {
        let start = Date(timeIntervalSince1970: 0)
        let end = Date(timeIntervalSince1970: 100)
        let xs = StockBoard.xPositions(timestamps: [0, 25, 50], count: 3, start: start, end: end)
        XCTAssertEqual(xs, [0, 0.25, 0.5], "half way through the day, half way across")
        XCTAssertEqual(StockBoard.xPositions(timestamps: [], count: 3, start: start, end: end), [0, 0.5, 1],
                       "no times: spread evenly")
        XCTAssertEqual(StockBoard.xPositions(timestamps: [-10, 200], count: 2, start: start, end: end), [0, 1])
    }

    func testTheRangeHoldsThePreviousCloseAndANearAlert() throws {
        let range = try XCTUnwrap(StockBoard.yRange(values: [230, 232], previousClose: 226.72, alert: 237))
        XCTAssertLessThan(range.lowerBound, 226.72)
        XCTAssertGreaterThan(range.upperBound, 237, "an alert 2% away is drawn")
        let far = try XCTUnwrap(StockBoard.yRange(values: [230, 232], previousClose: 231, alert: 300))
        XCTAssertLessThan(far.upperBound, 300, "an alert 30% away is not")
        XCTAssertNil(StockBoard.yFraction(300, in: far))
        XCTAssertEqual(try XCTUnwrap(StockBoard.yFraction(5, in: 0...10)), 0.5)
        XCTAssertNil(StockBoard.yRange(values: [], previousClose: 1, alert: nil))
        let flat = try XCTUnwrap(StockBoard.yRange(values: [5, 5], previousClose: nil, alert: nil))
        XCTAssertLessThan(flat.lowerBound, flat.upperBound, "a flat day still has height")
    }

    func testVolumeBars() {
        let bars = StockBoard.volumeBars(volumes: [10, 30, 0, 20], closes: [1, 2, 2, 1.5],
                                         positions: [0.05, 0.3, 0.55, 0.8], buckets: 4)
        XCTAssertEqual(bars.count, 3, "an empty slot draws no bar")
        XCTAssertEqual(bars.map(\.height), [10.0 / 30, 1, 20.0 / 30])
        XCTAssertEqual(bars.map(\.rising), [true, true, false])
        XCTAssertEqual(bars.first?.position, 0.125)
        XCTAssertTrue(StockBoard.volumeBars(volumes: [], closes: [], positions: [], buckets: 4).isEmpty)
    }

    // MARK: 自选股

    func testGroups() throws {
        let group = try XCTUnwrap(StockBoard.Group.parse("科技 = nvda tsla、AAPL"))
        XCTAssertEqual(group.name, "科技")
        XCTAssertEqual(group.symbols, ["NVDA", "TSLA", "AAPL"])
        XCTAssertEqual(group.text, "科技=NVDA TSLA AAPL")
        XCTAssertEqual(StockBoard.Group.parse("A股：600519.SS")?.symbols, ["600519.SS"])
        XCTAssertNil(StockBoard.Group.parse("科技="))
        XCTAssertNil(StockBoard.Group.parse("=AAPL"))
        XCTAssertNil(StockBoard.Group.parse("AAPL MSFT"))

        let plain = WidgetConfig(["symbols": .list([.string("AAPL"), .string("MSFT")])])
        XCTAssertEqual(StockBoard.groups(plain), [StockBoard.Group(name: "自选", symbols: ["AAPL", "MSFT"])],
                       "no groups: the list is one group")

        let config = WidgetConfig([
            "groups": .list([.string("科技=NVDA TSLA"), .string("A股=600519.SS"), .string("科技=AAPL")]),
            "group": .string("A股"),
        ])
        XCTAssertEqual(StockBoard.groups(config).map(\.name), ["科技", "A股"], "same name kept once")
        XCTAssertEqual(StockBoard.currentGroup(config).name, "A股")
        XCTAssertEqual(StockBoard.nextGroupName(config), "科技")
        var missing = config
        missing.set("group", .string("港股"))
        XCTAssertEqual(StockBoard.currentGroup(missing).name, "科技", "a deleted group falls back to the first")
    }

    func testSavingAndRemovingGroups() {
        let plain = WidgetConfig(["symbols": .list([.string("AAPL")])])
        let saved = StockBoard.saving(StockBoard.Group(name: "科技", symbols: ["NVDA"]), in: plain)
        XCTAssertEqual(saved, ["自选=AAPL", "科技=NVDA"], "the old list becomes the first group")
        var config = WidgetConfig(["groups": .list(saved.map { .string($0) })])
        let replaced = StockBoard.saving(StockBoard.Group(name: "科技", symbols: ["NVDA", "TSLA"]), in: config)
        XCTAssertEqual(replaced, ["自选=AAPL", "科技=NVDA TSLA"])
        config.set("groups", .list(replaced.map { .string($0) }))
        XCTAssertEqual(StockBoard.removing("自选", in: config), ["科技=NVDA TSLA"])
        let single = WidgetConfig(["groups": .list([.string("科技=NVDA")])])
        XCTAssertEqual(StockBoard.removing("科技", in: single), ["科技=NVDA"], "the last group stays")
    }

    func testQuickAddingGoldAndSilver() {
        let stock = StockBoard.adding(PreciousMetal.gold.symbol, to: WidgetConfig(["symbols": .list([.string("AAPL")])]),
                                      watchlist: false)
        XCTAssertEqual(stock.strings("symbols"), ["AAPL", "GC=F"])
        XCTAssertEqual(stock.string("symbol"), "GC=F", "shown straight away")
        let twice = StockBoard.adding("gc=f", to: stock, watchlist: false)
        XCTAssertEqual(twice.strings("symbols"), ["AAPL", "GC=F"], "not added twice")

        let plain = StockBoard.adding("SI=F", to: WidgetConfig(), watchlist: true)
        XCTAssertEqual(plain.strings("symbols"), ["AAPL", "MSFT", "NVDA", "SI=F"])
        let grouped = WidgetConfig(["groups": .list([.string("科技=NVDA"), .string("避险=GC=F")]),
                                    "group": .string("避险")])
        let added = StockBoard.adding("SI=F", to: grouped, watchlist: true)
        XCTAssertEqual(added.strings("groups"), ["科技=NVDA", "避险=GC=F SI=F"], "into the group on show")
    }

    func testSortingByTheDaysMove() {
        let percents = ["NVDA": 4.82, "TSLA": 3.10, "AMZN": -0.62, "AAPL": 2.41]
        let symbols = ["AAPL", "AMZN", "MSFT", "NVDA", "TSLA"]
        XCTAssertEqual(StockBoard.sorted(symbols, percents: percents, order: .change),
                       ["NVDA", "TSLA", "AAPL", "AMZN", "MSFT"], "no quote yet goes last")
        XCTAssertEqual(StockBoard.sorted(symbols, percents: percents, order: .custom), symbols)
        XCTAssertEqual(StockBoard.sorted(["B", "A"], percents: ["A": 1, "B": 1], order: .change), ["B", "A"],
                       "ties keep their order")
        XCTAssertEqual(StockBoard.Order.from(WidgetConfig()), .change)
    }

    func testBreadth() {
        let breadth = StockBoard.breadth([4.82, 3.1, 2.41, 1.05, 0.38, -0.62, -1, -2, 0, nil])
        XCTAssertEqual(breadth, StockBoard.Breadth(up: 5, down: 3, flat: 1))
        XCTAssertEqual(breadth.upShare, 5.0 / 8)
        XCTAssertEqual(StockBoard.Breadth(up: 0, down: 0, flat: 2).upShare, 0.5)
        XCTAssertEqual(StockBoard.breadthText(breadth), "涨 5 跌 3")
    }

    func testOverflow() {
        XCTAssertEqual(StockBoard.fit(count: 4, capacity: 6).shown, 4)
        XCTAssertEqual(StockBoard.fit(count: 6, capacity: 6).hidden, 0)
        let crowded = StockBoard.fit(count: 8, capacity: 6)
        XCTAssertEqual(crowded.shown, 5, "the last slot says how many more")
        XCTAssertEqual(crowded.hidden, 3)
        XCTAssertEqual(StockBoard.moreText(3), "还有 3 只")
    }

    func testTodaysProfitNeedsHoldings() {
        let config = WidgetConfig(["holdings": .list([.string("NVDA 100"), .string("aapl:50"), .string("bad")])])
        let holdings = StockBoard.holdings(config)
        XCTAssertEqual(holdings, ["NVDA": 100, "AAPL": 50])
        let positions = [
            StockBoard.Position(symbol: "NVDA", price: 142.86, change: 6.57, currency: "USD"),
            StockBoard.Position(symbol: "AAPL", price: 232.18, change: 5.46, currency: "USD"),
            StockBoard.Position(symbol: "MSFT", price: 428.55, change: 4.45, currency: "USD"),
        ]
        let profit = StockBoard.todayProfit(positions, holdings: holdings)
        XCTAssertEqual(profit.count, 1)
        XCTAssertEqual(profit[0].amount, 6.57 * 100 + 5.46 * 50, accuracy: 1e-9)
        let base = (142.86 - 6.57) * 100 + (232.18 - 5.46) * 50
        XCTAssertEqual(profit[0].percent ?? 0, profit[0].amount / base * 100, accuracy: 1e-9)
        XCTAssertEqual(StockBoard.profitText(profit[0]), "+$930.00")
        XCTAssertTrue(StockBoard.todayProfit(positions, holdings: [:]).isEmpty, "nothing filled, nothing shown")
        XCTAssertEqual(StockBoard.profitText(.init(currency: "CNY", amount: -1286.4, percent: nil)), "-¥1,286.40")
    }

    func testSizes() throws {
        var stock = try XCTUnwrap(WidgetCatalog.make(.stock))
        XCTAssertEqual(WidgetCatalog.naturalSize(stock).width, StockBoard.stockTileWidth(chart: true))
        stock.config.set("chart", .bool(false))
        XCTAssertEqual(WidgetCatalog.naturalSize(stock).width, StockBoard.stockTileWidth(chart: false))
        let watchlist = try XCTUnwrap(WidgetCatalog.make(.watchlist))
        XCTAssertEqual(WidgetCatalog.naturalSize(watchlist).width, StockBoard.watchlistTileWidth)
        XCTAssertEqual(WidgetCatalog.verticalHeight(watchlist), StockBoard.watchlistColumnHeight(count: 3))
        XCTAssertLessThan(StockBoard.watchlistColumnHeight(count: 2), StockBoard.watchlistColumnHeight(count: 6))
        XCTAssertEqual(StockBoard.watchlistColumnHeight(count: 9), StockBoard.watchlistColumnHeight(count: 6))
    }

    // MARK: 黄金白银

    func testMetals() {
        XCTAssertEqual(PreciousMetal(symbol: "gc=f"), .gold)
        XCTAssertEqual(PreciousMetal(symbol: "SI=F"), .silver)
        XCTAssertNil(PreciousMetal(symbol: "AAPL"))
        XCTAssertEqual(PreciousMetal.gold.symbol, "GC=F")
        XCTAssertEqual(PreciousMetal.gold.title, "黄金")
        XCTAssertEqual(PreciousMetal.silver.title, "白银")
    }

    func testOuncesToGrams() throws {
        // 2,400 美元/盎司，汇率 7.12：2400 × 7.12 / 31.1035 ≈ 549.38 元/克。
        let gram = try XCTUnwrap(PreciousMetal.cnyPerGram(usdPerOunce: 2400, usdToCny: 7.12))
        XCTAssertEqual(gram, 2400 * 7.12 / 31.1035, accuracy: 1e-9)
        XCTAssertEqual(gram, 549.38, accuracy: 0.01)
        XCTAssertEqual(PreciousMetal.factor(.usdPerOunce, usdToCny: nil), 1)
        XCTAssertNil(PreciousMetal.factor(.cnyPerGram, usdToCny: nil), "no rate, no made-up price")
        XCTAssertNil(PreciousMetal.factor(.cnyPerGram, usdToCny: 0))
        XCTAssertEqual(PreciousMetal.shownUnit(.cnyPerGram, usdToCny: nil), .usdPerOunce)
        XCTAssertEqual(PreciousMetal.shownUnit(.cnyPerGram, usdToCny: 7.1), .cnyPerGram)
        XCTAssertEqual(PreciousMetal.DisplayUnit.from(WidgetConfig()), .cnyPerGram, "元/克 by default")
        XCTAssertEqual(PreciousMetal.DisplayUnit.cnyPerGram.title, "元/克")
        XCTAssertEqual(PreciousMetal.DisplayUnit.usdPerOunce.title, "美元/盎司")
    }

    func testTheRateIsFetchedOnlyWhenAMetalNeedsIt() {
        XCTAssertTrue(PreciousMetal.needsExchangeRate(["AAPL", "GC=F"], unit: .cnyPerGram))
        XCTAssertFalse(PreciousMetal.needsExchangeRate(["AAPL"], unit: .cnyPerGram))
        XCTAssertFalse(PreciousMetal.needsExchangeRate(["GC=F"], unit: .usdPerOunce))
    }
}
