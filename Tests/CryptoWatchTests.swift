import Foundation
import XCTest

/// 加密货币面板：币种增删排、名字和搜索、到价提醒（Pro）。
final class CryptoWatchTests: XCTestCase {

    // MARK: 币种列表

    func testCoinsAreWrittenAsTickersWhenKnown() {
        var config = WidgetConfig()
        CryptoWatch.writeCoins(["bitcoin", "solana", "solo-coin"], into: &config)
        XCTAssertEqual(config.strings("coins"), ["BTC", "SOL", "solo-coin"])
        // 读回来是同一组 id，顺序不变。
        XCTAssertEqual(CryptoMarket.coinIDs(config), ["bitcoin", "solana", "solo-coin"])
    }

    func testAddingRefusesDuplicatesAndAFullList() {
        XCTAssertEqual(CryptoWatch.adding("dogecoin", to: ["bitcoin"]), ["bitcoin", "dogecoin"])
        XCTAssertEqual(CryptoWatch.adding("DOGE", to: ["bitcoin"]), ["bitcoin", "dogecoin"], "代码也认")
        XCTAssertNil(CryptoWatch.adding("bitcoin", to: ["bitcoin"]))
        XCTAssertNil(CryptoWatch.adding("not valid!", to: ["bitcoin"]))
        let full = (0..<CryptoMarket.maxCoins).map { "coin-\($0)" }
        XCTAssertFalse(CryptoWatch.canAdd(count: full.count))
        XCTAssertNil(CryptoWatch.adding("dogecoin", to: full))
        XCTAssertNotNil(CryptoWatch.adding("dogecoin", to: Array(full.dropLast())))
    }

    func testTheLastCoinCannotBeRemoved() {
        XCTAssertEqual(CryptoWatch.removing("bitcoin", from: ["bitcoin", "ethereum"]), ["ethereum"])
        XCTAssertFalse(CryptoWatch.canRemove(count: 1))
        XCTAssertEqual(CryptoWatch.removing("bitcoin", from: ["bitcoin"]), ["bitcoin"],
                       "空列表会退回默认三个币，所以最后一个留着")
        XCTAssertEqual(CryptoWatch.removing("ghost", from: ["bitcoin", "ethereum"]), ["bitcoin", "ethereum"])
    }

    func testMovingAndDropIndex() {
        let ids = ["a", "b", "c", "d"]
        XCTAssertEqual(CryptoWatch.moving(ids, from: 0, to: 2), ["b", "c", "a", "d"])
        XCTAssertEqual(CryptoWatch.moving(ids, from: 3, to: 0), ["d", "a", "b", "c"])
        XCTAssertEqual(CryptoWatch.moving(ids, from: 1, to: 99), ["a", "c", "d", "b"])
        XCTAssertEqual(CryptoWatch.moving(ids, from: 9, to: 0), ids)
        // 一行 54：拖过半行才换位置，两头夹住。
        XCTAssertEqual(CryptoWatch.dropIndex(from: 0, offset: 20, step: 54, count: 4), 0)
        XCTAssertEqual(CryptoWatch.dropIndex(from: 0, offset: 30, step: 54, count: 4), 1)
        XCTAssertEqual(CryptoWatch.dropIndex(from: 0, offset: 120, step: 54, count: 4), 2)
        XCTAssertEqual(CryptoWatch.dropIndex(from: 2, offset: -500, step: 54, count: 4), 0)
        XCTAssertEqual(CryptoWatch.dropIndex(from: 2, offset: 500, step: 54, count: 4), 3)
        XCTAssertEqual(CryptoWatch.dropIndex(from: 0, offset: .nan, step: 54, count: 4), 0)
        XCTAssertEqual(CryptoWatch.dropIndex(from: 0, offset: 10, step: 54, count: 0), 0)
    }

    // MARK: 名字和搜索

    func testDisplayNames() {
        XCTAssertEqual(CryptoWatch.displayName(id: "bitcoin", fallback: "Bitcoin", english: false), "比特币")
        XCTAssertEqual(CryptoWatch.displayName(id: "bitcoin", fallback: nil, english: true), "Bitcoin")
        XCTAssertEqual(CryptoWatch.displayName(id: "solo-coin", fallback: "Sologenic", english: false), "Sologenic")
        XCTAssertEqual(CryptoWatch.displayName(id: "solo-coin", fallback: nil, english: false), "SOLO-COIN")
        // 常见币表和代码表对得上。
        for coin in CryptoWatch.catalog {
            XCTAssertEqual(CryptoMarket.knownIDs[coin.symbol], coin.id, coin.symbol)
        }
    }

    func testLocalSearchMatchesTickersAndChineseNames() {
        XCTAssertEqual(CryptoWatch.localSearch("so").first?.id, "solana")
        XCTAssertEqual(CryptoWatch.localSearch("狗狗").map(\.id), ["dogecoin"])
        XCTAssertEqual(CryptoWatch.localSearch(" BTC ").first?.id, "bitcoin")
        XCTAssertEqual(CryptoWatch.localSearch("op").first?.id, "optimism", "代码完全一样的排最前")
        XCTAssertTrue(CryptoWatch.localSearch("").isEmpty)
        XCTAssertTrue(CryptoWatch.localSearch("zzzz").isEmpty)
    }

    func testRemoteSearchNeedsTwoLatinCharacters() {
        XCTAssertFalse(CryptoWatch.wantsRemoteSearch("s"))
        XCTAssertTrue(CryptoWatch.wantsRemoteSearch("so"))
        XCTAssertFalse(CryptoWatch.wantsRemoteSearch("比特"), "中文只在本地搜")
        XCTAssertFalse(CryptoWatch.wantsRemoteSearch("   "))
        XCTAssertEqual(CryptoWatch.searchURL(" so ")?.absoluteString, "https://api.coingecko.com/api/v3/search?query=so")
    }

    func testParseSearch() {
        let data = Data("""
        {"coins":[
          {"id":"solana","name":"Solana","symbol":"SOL","market_cap_rank":6},
          {"id":"solo-coin","name":"Sologenic","symbol":"solo"},
          {"id":"Bad_ID","name":"Bad","symbol":"BAD"},
          {"id":"solana","name":"Dup","symbol":"SOL"},
          {"name":"No id"}
        ],"exchanges":[]}
        """.utf8)
        let hits = CryptoWatch.parseSearch(data)
        XCTAssertEqual(hits, [CryptoSearchHit(id: "solana", symbol: "SOL", name: "Solana"),
                              CryptoSearchHit(id: "solo-coin", symbol: "SOLO", name: "Sologenic")])
        XCTAssertNil(CryptoWatch.parseSearch(Data(#"{"status":{"error_code":429}}"#.utf8)))
        XCTAssertNil(CryptoWatch.parseSearch(Data("[]".utf8)))
        XCTAssertEqual(CryptoWatch.parseSearch(Data(#"{"coins":[]}"#.utf8)), [])
    }

    func testMergedResultsPutLocalFirstWithoutDuplicates() {
        let local = [CryptoSearchHit(id: "solana", symbol: "SOL", name: "Solana")]
        let remote = [CryptoSearchHit(id: "solana", symbol: "SOL", name: "Solana"),
                      CryptoSearchHit(id: "solo-coin", symbol: "SOLO", name: "Sologenic")]
        XCTAssertEqual(CryptoWatch.mergedResults(local: local, remote: remote).map(\.id), ["solana", "solo-coin"])
        let many = (0..<10).map { CryptoSearchHit(id: "c\($0)", symbol: "C\($0)", name: "C\($0)") }
        XCTAssertEqual(CryptoWatch.mergedResults(local: [], remote: many, limit: 6).count, 6)
    }

    // MARK: 到价提醒

    func testAlertTextRoundTrips() {
        let alert = CryptoAlert(coin: "bitcoin", above: true, price: 800_000, currency: "cny")
        XCTAssertEqual(alert.text, "bitcoin>800000@cny")
        XCTAssertEqual(CryptoAlert.parse(alert.text), alert)
        var off = CryptoAlert(coin: "shiba-inu", above: false, price: 0.00001234, currency: "usd")
        off.on = false
        XCTAssertTrue(off.text.hasPrefix("~shiba-inu<"))
        XCTAssertEqual(CryptoAlert.parse(off.text), off, "很小的价也读回来一样")
        XCTAssertEqual(CryptoAlert.parse(" BTC > 750000.5 @ USD "),
                       CryptoAlert(coin: "bitcoin", above: true, price: 750_000.5, currency: "usd"))
        XCTAssertEqual(CryptoAlert.parse("eth<20000")?.currency, "cny", "没写计价按人民币")
        for bad in ["", "bitcoin", "bitcoin>0@cny", "bitcoin>-1@cny", "bitcoin>abc@cny", "bitcoin>1@eur",
                    "bit coin>1@cny", "bitcoin>1@cny@usd", ">1@cny"] {
            XCTAssertNil(CryptoAlert.parse(bad), bad)
        }
    }

    func testAlertsAreReadOnePerCoinAndDirection() {
        var config = WidgetConfig()
        config.set("alerts", .list(["bitcoin>800000@cny", "bitcoin>900000@cny", "bitcoin<700000@cny",
                                    "garbage", "dogecoin<1@cny"].map { .string($0) }))
        let all = CryptoWatch.alerts(config)
        XCTAssertEqual(all.map(\.text), ["bitcoin>800000@cny", "bitcoin<700000@cny", "dogecoin<1@cny"])
        XCTAssertEqual(CryptoWatch.alerts(config, coins: ["bitcoin"]).count, 2, "不在列表里的币不算")
        XCTAssertEqual(CryptoWatch.alert(all, coin: "bitcoin", above: false)?.price, 700_000)
        XCTAssertNil(CryptoWatch.alert(all, coin: "ethereum", above: true))
    }

    func testSettingReplacesTheSameSlot() {
        let a = CryptoAlert(coin: "bitcoin", above: true, price: 1, currency: "cny")
        let b = CryptoAlert(coin: "bitcoin", above: false, price: 2, currency: "cny")
        var list = CryptoWatch.setting(a, in: [])
        list = CryptoWatch.setting(b, in: list)
        list = CryptoWatch.setting(CryptoAlert(coin: "bitcoin", above: true, price: 3, currency: "usd"), in: list)
        XCTAssertEqual(list.map(\.text), ["bitcoin>3@usd", "bitcoin<2@cny"])
        XCTAssertEqual(CryptoWatch.removing(coin: "bitcoin", above: true, from: list).map(\.text), ["bitcoin<2@cny"])
        XCTAssertTrue(CryptoWatch.removing(coin: "bitcoin", from: list).isEmpty)
        var config = WidgetConfig()
        CryptoWatch.writeAlerts(list, into: &config)
        XCTAssertEqual(CryptoWatch.alerts(config), list, "存进去再读出来一样（重启后还在）")
    }

    func testDueAlertsFireOnceAndTurnOff() {
        let above = CryptoAlert(coin: "bitcoin", above: true, price: 800_000, currency: "cny")
        let below = CryptoAlert(coin: "bitcoin", above: false, price: 700_000, currency: "cny")
        let usd = CryptoAlert(coin: "ethereum", above: true, price: 4000, currency: "usd")
        var off = CryptoAlert(coin: "dogecoin", above: true, price: 1, currency: "cny")
        off.on = false
        let alerts = [above, below, usd, off]
        let prices: [String: Double] = ["bitcoin@cny": 800_000, "ethereum@usd": 3999, "dogecoin@cny": 5]
        let due = CryptoWatch.due(alerts) { prices["\($0)@\($1)"] }
        XCTAssertEqual(due, [above], "到价才算，关着的不算，另一种计价按自己的价比")
        XCTAssertTrue(CryptoWatch.due(alerts) { _, _ in nil }.isEmpty, "没有价（断网、还没取到）不算")
        let after = CryptoWatch.firing(due, in: alerts)
        XCTAssertFalse(after[0].on)
        XCTAssertEqual(after[0].price, 800_000, "价格留着，再打开还是这条")
        XCTAssertTrue(after[1].on)
        XCTAssertTrue(CryptoWatch.due(after) { prices["\($0)@\($1)"] }.isEmpty, "提醒一次后不再响")
        // 判断期间改了价：改过的那条不关。
        let edited = CryptoWatch.setting(CryptoAlert(coin: "bitcoin", above: true, price: 900_000, currency: "cny"),
                                         in: alerts)
        XCTAssertTrue(CryptoWatch.firing(due, in: edited)[0].on)
    }

    func testReachedEdges() {
        let above = CryptoAlert(coin: "bitcoin", above: true, price: 100, currency: "cny")
        XCTAssertTrue(above.isReached(by: 100))
        XCTAssertFalse(above.isReached(by: 99.99))
        XCTAssertFalse(above.isReached(by: .nan))
        XCTAssertFalse(above.isReached(by: nil))
        let below = CryptoAlert(coin: "bitcoin", above: false, price: 100, currency: "cny")
        XCTAssertTrue(below.isReached(by: 100))
        XCTAssertFalse(below.isReached(by: 0), "价格是 0 是坏数据，不算跌到")
    }

    func testFeaturedWatchedAndCurrencies() {
        var offBTC = CryptoAlert(coin: "bitcoin", above: true, price: 1, currency: "cny")
        offBTC.on = false
        let ethBelow = CryptoAlert(coin: "ethereum", above: false, price: 2, currency: "usd")
        let ethAbove = CryptoAlert(coin: "ethereum", above: true, price: 3, currency: "cny")
        let alerts = [offBTC, ethBelow, ethAbove]
        XCTAssertEqual(CryptoWatch.featured(alerts, order: ["bitcoin", "ethereum"]), ethAbove, "高于在低于前")
        XCTAssertNil(CryptoWatch.featured([offBTC], order: ["bitcoin"]))
        XCTAssertNil(CryptoWatch.featured([], order: []))
        XCTAssertEqual(CryptoWatch.watchedCoins(alerts), ["ethereum"])
        XCTAssertEqual(CryptoWatch.currencies(alerts), ["usd", "cny"])
        XCTAssertEqual(CryptoWatch.title(ethAbove, name: "以太坊"), "以太坊高于 ¥3.00")
    }

    func testHitsAccumulateWithoutDuplicates() {
        var config = WidgetConfig()
        XCTAssertTrue(CryptoWatch.hits(config).isEmpty)
        CryptoWatch.addingHits(["bitcoin"], to: &config)
        CryptoWatch.addingHits(["bitcoin", "ethereum"], to: &config)
        XCTAssertEqual(CryptoWatch.hits(config), ["bitcoin", "ethereum"])
    }

    // MARK: 输入

    func testParsePrice() {
        XCTAssertEqual(CryptoWatch.parsePrice("¥800,000"), 800_000)
        XCTAssertEqual(CryptoWatch.parsePrice(" 800000 "), 800_000)
        XCTAssertEqual(CryptoWatch.parsePrice("80万"), 800_000)
        XCTAssertEqual(CryptoWatch.parsePrice("$0.1834"), 0.1834)
        XCTAssertEqual(CryptoWatch.parsePrice("1，200。5"), 1200.5)
        XCTAssertEqual(CryptoWatch.parsePrice("1.5亿"), 150_000_000)
        for bad in ["", "¥", "0", "-5", "abc", "万", "inf", "nan"] {
            XCTAssertNil(CryptoWatch.parsePrice(bad), bad)
        }
    }

    func testSuggestedPriceSitsOnTheRightSide() {
        XCTAssertEqual(CryptoWatch.suggested(current: 782_410, above: true), 830_000)
        XCTAssertEqual(CryptoWatch.suggested(current: 782_410, above: false), 740_000)
        XCTAssertEqual(CryptoWatch.suggested(current: 1.42, above: true), 1.5)
        XCTAssertEqual(CryptoWatch.suggested(current: 1.42, above: false), 1.3)
        XCTAssertNil(CryptoWatch.suggested(current: nil, above: true))
        XCTAssertNil(CryptoWatch.suggested(current: 0, above: true))
        for price in [0.00001234, 0.1834, 3.7, 99, 26_930, 782_410] {
            XCTAssertGreaterThan(CryptoWatch.suggested(current: price, above: true)!, price)
            XCTAssertLessThan(CryptoWatch.suggested(current: price, above: false)!, price)
        }
    }

    func testInputAndChipText() {
        XCTAssertEqual(CryptoWatch.inputText(800_000, currency: "cny"), "800,000")
        XCTAssertEqual(CryptoWatch.inputText(1.5, currency: "usd"), "1.50")
        XCTAssertEqual(CryptoWatch.parsePrice(CryptoWatch.inputText(26_930, currency: "cny")), 26_930)
        XCTAssertEqual(CryptoWatch.chipText(2.44), "+2.4%")
        XCTAssertEqual(CryptoWatch.chipText(-0.76), "-0.8%")
        XCTAssertEqual(CryptoWatch.chipText(0.04), "0.0%")
        XCTAssertEqual(CryptoWatch.chipText(-0.04), "0.0%")
        XCTAssertEqual(CryptoWatch.chipText(nil), "-")
        XCTAssertEqual(CryptoWatch.chipText(.infinity), "-")
    }

    // MARK: Pro

    func testAlertsArePro() {
        XCTAssertFalse(ProLicenseGate.canUseCryptoAlerts(unlocked: false))
        XCTAssertTrue(ProLicenseGate.canUseCryptoAlerts(unlocked: true))
        XCTAssertFalse(ProFeatures.isProKind(.crypto), "加密货币行情本身免费")
        XCTAssertTrue(ProLicenseGate.canAdd(.crypto, overrides: [:], unlocked: false))
        XCTAssertTrue(ProUnlockStyle.allCases.contains(.cryptoAlerts))
        // 提醒和变色的键不进设置页，只在面板里改。
        let keys = WidgetCatalog.configurableKeys(.crypto)
        XCTAssertFalse(keys.contains(CryptoWatch.alertsKey))
        XCTAssertFalse(keys.contains(CryptoWatch.hitsKey))
    }

    // MARK: 只取还在用的币

    func testInUseFollowsCoinsCurrencyAndLiveAlerts() {
        var config = WidgetConfig()
        config.set("currency", .string("cny"))
        CryptoWatch.writeCoins(["bitcoin", "ethereum"], into: &config)
        CryptoWatch.writeAlerts([CryptoAlert(coin: "bitcoin", above: true, price: 1, currency: "usd"),
                                 CryptoAlert(coin: "ethereum", above: true, price: 1, currency: "usd", on: false),
                                 CryptoAlert(coin: "solana", above: true, price: 1, currency: "usd")],
                                into: &config)
        XCTAssertEqual(CryptoWatch.inUse([config], alertsOn: true),
                       ["cny": ["bitcoin", "ethereum"], "usd": ["bitcoin"]],
                       "an alert for a coin no longer on the card, or switched off, fetches nothing")
        XCTAssertEqual(CryptoWatch.inUse([config], alertsOn: false), ["cny": ["bitcoin", "ethereum"]])
        XCTAssertEqual(CryptoWatch.inUse([], alertsOn: true), [:])
    }

    func testPruningDropsRemovedCoinsAndEmptyCurrencies() {
        let tracked: [String: Set<String>] = ["cny": ["bitcoin", "dogecoin"], "usd": ["solana"]]
        XCTAssertEqual(CryptoWatch.pruned(tracked, inUse: ["cny": ["bitcoin", "ethereum"]]),
                       ["cny": ["bitcoin"]])
        XCTAssertEqual(CryptoWatch.pruned(tracked, inUse: [:]), [:])
    }
}
