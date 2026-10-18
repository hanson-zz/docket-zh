import Foundation
import XCTest

final class CryptoMarketTests: XCTestCase {
    /// Trimmed from a real `/coins/markets?vs_currency=cny&sparkline=true`
    /// answer: two coins, a short sparkline with a null in it, and one row
    /// with no price, which must be skipped rather than read as zero.
    private let sample = Data("""
    [
      {"id":"bitcoin","symbol":"btc","name":"Bitcoin","current_price":558865,
       "price_change_percentage_24h":1.09231,
       "price_change_percentage_24h_in_currency":1.0923,
       "sparkline_in_7d":{"price":[86592.23,85744.30,null,85721.70]}},
      {"id":"ethereum","symbol":"eth","name":"Ethereum","current_price":21692.4,
       "price_change_percentage_24h":-2.3141,
       "sparkline_in_7d":{"price":[3050.1,3040.2]}},
      {"id":"ghost","symbol":"gst","name":"Ghost","current_price":null}
    ]
    """.utf8)

    func testParsesTheMarketsArray() throws {
        let quotes = try XCTUnwrap(CryptoMarket.parse(sample))
        XCTAssertEqual(Set(quotes.keys), ["bitcoin", "ethereum"])
        let btc = try XCTUnwrap(quotes["bitcoin"])
        XCTAssertEqual(btc.symbol, "BTC")
        XCTAssertEqual(btc.name, "Bitcoin")
        XCTAssertEqual(btc.price, 558_865)
        XCTAssertEqual(btc.change24h ?? 0, 1.0923, accuracy: 1e-9, "the in-currency change wins")
        XCTAssertEqual(btc.sparkline, [86592.23, 85744.30, 85721.70], "nulls are dropped, not zeroed")
        XCTAssertEqual(quotes["ethereum"]?.change24h ?? 0, -2.3141, accuracy: 1e-9)
    }

    func testKeepsTheWholeWeekThinned() throws {
        let points = (0..<168).map { "\($0 + 100)" }.joined(separator: ",")
        let data = Data("""
        [{"id":"solana","symbol":"sol","name":"Solana","current_price":1300,
          "sparkline_in_7d":{"price":[\(points)]}}]
        """.utf8)
        let sol = try XCTUnwrap(CryptoMarket.parse(data)?["solana"])
        XCTAssertEqual(sol.sparkline.count, CryptoMarket.sparklinePoints)
        XCTAssertEqual(sol.sparkline.first, 100, "the line starts seven days ago")
        XCTAssertEqual(sol.sparkline.last, 267, "and ends now")
        XCTAssertNil(sol.change24h)
        XCTAssertEqual(sol.change7d ?? 0, 167, accuracy: 1e-9, "no figure from CoinGecko: first to last")
    }

    func testTheWeekChangeFromCoinGeckoWins() throws {
        let data = Data("""
        [{"id":"bitcoin","symbol":"btc","name":"Bitcoin","current_price":1,
          "price_change_percentage_7d_in_currency":-4.1,
          "sparkline_in_7d":{"price":[10,20]}}]
        """.utf8)
        let btc = try XCTUnwrap(CryptoMarket.parse(data)?["bitcoin"])
        XCTAssertEqual(btc.change7d ?? 0, -4.1, accuracy: 1e-9)
        XCTAssertEqual(btc.sparkline, [10, 20], "a short line is kept as is")
    }

    func testAQuoteCachedBeforeTheWeekChangeStillDecodes() throws {
        let old = Data(#"{"id":"bitcoin","symbol":"BTC","name":"Bitcoin","price":1,"change24h":2,"sparkline":[1,2]}"#.utf8)
        let quote = try JSONDecoder().decode(CryptoQuote.self, from: old)
        XCTAssertNil(quote.change7d)
        XCTAssertEqual(quote.sparkline, [1, 2])
    }

    func testThinningKeepsBothEnds() {
        XCTAssertEqual(CryptoMarket.thinned([1, 2, 3, 4, 5], to: 3), [1, 3, 5])
        XCTAssertEqual(CryptoMarket.thinned([1, 2], to: 3), [1, 2])
        XCTAssertNil(CryptoMarket.weekChange([0, 5]))
        XCTAssertEqual(CryptoMarket.weekChange([100, 110]) ?? 0, 10, accuracy: 1e-9)
    }

    func testBadges() {
        XCTAssertEqual(CryptoMarket.badgeLetter("BTC"), "B")
        XCTAssertEqual(CryptoMarket.badgeLetter("eth"), "Ξ")
        XCTAssertEqual(CryptoMarket.badgeLetter("SOL"), "S")
        XCTAssertEqual(CryptoMarket.badgeHex("BTC"), "#F7931A")
        XCTAssertEqual(CryptoMarket.badgeHex("XYZ"), CryptoMarket.badgeHex("XYZ"), "a coin keeps its colour")
        XCTAssertEqual(CryptoMarket.tileWidth(count: 3), 308, "96pt a coin, as the design asks")
    }

    func testAnErrorAnswerIsNotATable() {
        let limited = Data(#"{"status":{"error_code":429,"error_message":"You've exceeded the Rate Limit."}}"#.utf8)
        XCTAssertNil(CryptoMarket.parse(limited))
        XCTAssertNil(CryptoMarket.parse(Data("not json".utf8)))
        XCTAssertEqual(CryptoMarket.parse(Data("[]".utf8))?.isEmpty, true)
    }

    func testCoinsFromConfig() {
        XCTAssertEqual(CryptoMarket.coinIDs(WidgetConfig()), ["bitcoin", "ethereum", "solana"])
        let config = WidgetConfig(["coins": .list([" btc ", "BTC", "bitcoin", "doge",
                                                   "the-open-network", "bad id!", ""].map { .string($0) })])
        XCTAssertEqual(CryptoMarket.coinIDs(config), ["bitcoin", "dogecoin", "the-open-network"])
        let empty = WidgetConfig(["coins": .list([.string("  ")])])
        XCTAssertEqual(CryptoMarket.coinIDs(empty), ["bitcoin", "ethereum", "solana"], "never an empty tile")
        XCTAssertEqual(CryptoMarket.label(id: "bitcoin", quote: nil), "BTC")
        XCTAssertEqual(CryptoMarket.label(id: "pepe", quote: nil), "PEPE")
    }

    func testCurrencyAndRequest() throws {
        XCTAssertEqual(CryptoMarket.currency(WidgetConfig()), "cny")
        XCTAssertEqual(CryptoMarket.currency(WidgetConfig(["currency": .string("usd")])), "usd")
        XCTAssertEqual(CryptoMarket.currency(WidgetConfig(["currency": .string("eur")])), "cny")
        let url = try XCTUnwrap(CryptoMarket.marketsURL(ids: ["bitcoin", "ethereum"], currency: "cny"))
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(url.host, "api.coingecko.com")
        XCTAssertEqual(url.path, "/api/v3/coins/markets")
        XCTAssertTrue(items.contains(URLQueryItem(name: "ids", value: "bitcoin,ethereum")))
        XCTAssertTrue(items.contains(URLQueryItem(name: "vs_currency", value: "cny")))
        XCTAssertTrue(items.contains(URLQueryItem(name: "sparkline", value: "true")))
    }

    func testRefreshIsAtMostEveryFiveMinutes() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(CryptoMarket.shouldFetch(lastAttempt: nil, now: now, missing: false))
        XCTAssertFalse(CryptoMarket.shouldFetch(lastAttempt: now.addingTimeInterval(-299), now: now, missing: false))
        XCTAssertTrue(CryptoMarket.shouldFetch(lastAttempt: now.addingTimeInterval(-300), now: now, missing: false))
        // A coin with no price yet may come sooner, but not in a burst.
        XCTAssertFalse(CryptoMarket.shouldFetch(lastAttempt: now.addingTimeInterval(-30), now: now, missing: true))
        XCTAssertTrue(CryptoMarket.shouldFetch(lastAttempt: now.addingTimeInterval(-60), now: now, missing: true))
    }

    func testMergeKeepsCoinsTheFreshAnswerLeftOut() {
        let old = CryptoSnapshot(currency: "cny", quotes: [
            "bitcoin": CryptoQuote(id: "bitcoin", symbol: "BTC", name: "Bitcoin", price: 1, change24h: 0),
            "ethereum": CryptoQuote(id: "ethereum", symbol: "ETH", name: "Ethereum", price: 2, change24h: 0),
        ], fetched: .distantPast)
        let fresh = ["bitcoin": CryptoQuote(id: "bitcoin", symbol: "BTC", name: "Bitcoin", price: 3, change24h: 1)]
        let now = Date(timeIntervalSince1970: 5)
        let merged = CryptoMarket.merged(old, fresh: fresh, currency: "cny", at: now)
        XCTAssertEqual(merged.quotes["bitcoin"]?.price, 3)
        XCTAssertEqual(merged.quotes["ethereum"]?.price, 2)
        XCTAssertEqual(merged.fetched, now)
        // Another currency's prices never leak in.
        XCTAssertEqual(CryptoMarket.merged(old, fresh: fresh, currency: "usd", at: now).quotes.count, 1)
    }

    func testSnapshotRoundTripsThroughTheCacheFormat() throws {
        let snapshot = CryptoSnapshot(currency: "usd", quotes: [
            "solana": CryptoQuote(id: "solana", symbol: "SOL", name: "Solana", price: 182.37,
                                  change24h: nil, sparkline: [1, 2, 3]),
        ], fetched: Date(timeIntervalSince1970: 1_700_000_000))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        XCTAssertEqual(try decoder.decode(CryptoSnapshot.self, from: encoder.encode(snapshot)), snapshot)
    }

    func testRedUpByDefaultAndSwitchable() {
        XCTAssertEqual(ChangeColors.from(WidgetConfig()), .redUp)
        XCTAssertEqual(ChangeColors.from(WidgetCatalog.make(.crypto)!.config), .redUp)
        XCTAssertEqual(CryptoMarket.tone(1.2, colors: .redUp), .red)
        XCTAssertEqual(CryptoMarket.tone(-1.2, colors: .redUp), .green)
        XCTAssertEqual(CryptoMarket.tone(1.2, colors: .greenUp), .green)
        XCTAssertEqual(CryptoMarket.tone(-1.2, colors: .greenUp), .red)
        XCTAssertEqual(CryptoMarket.tone(0.001, colors: .redUp), .neutral, "rounds to 0.00%")
        XCTAssertEqual(CryptoMarket.tone(nil, colors: .redUp), .neutral)
        XCTAssertEqual(ChangeColors.redUp.title, "红涨绿跌")
    }

    func testFormatting() {
        XCTAssertEqual(CryptoMarket.priceText(558_865, currency: "cny"), "¥558,865")
        XCTAssertEqual(CryptoMarket.priceText(3_046.7, currency: "usd"), "$3,047")
        XCTAssertEqual(CryptoMarket.priceText(182.37, currency: "usd"), "$182.37")
        XCTAssertEqual(CryptoMarket.priceText(0.1834, currency: "usd"), "$0.1834")
        XCTAssertEqual(CryptoMarket.priceText(0.00001234, currency: "cny"), "¥0.00001234")
        XCTAssertEqual(CryptoMarket.changeText(1.0923), "+1.09%")
        XCTAssertEqual(CryptoMarket.changeText(-2.3141), "-2.31%")
        XCTAssertEqual(CryptoMarket.changeText(-0.001), "0.00%")
        XCTAssertEqual(CryptoMarket.changeText(nil), "-")
    }

    func testSizesFollowTheCoinCount() {
        var instance = WidgetCatalog.make(.crypto)!
        XCTAssertEqual(WidgetCatalog.naturalSize(instance).width, CryptoMarket.tileWidth(count: 3))
        instance.config.set("coins", .list([.string("BTC")]))
        XCTAssertEqual(WidgetCatalog.naturalSize(instance).width, CryptoMarket.tileWidth(count: 1))
        XCTAssertGreaterThanOrEqual(WidgetCatalog.verticalHeight(instance), 62)
        instance.config.set("coins", .list((1...9).map { .string("coin\($0)") }))
        XCTAssertEqual(WidgetCatalog.naturalSize(instance).width,
                       CryptoMarket.tileWidth(count: CryptoMarket.tileCoins), "the tile caps, the panel lists all")
        XCTAssertEqual(WidgetCatalog.contentSize(instance, position: .bottom).height, 58)
        XCTAssertLessThan(CryptoMarket.columnHeight(count: 3, chart: false),
                          CryptoMarket.columnHeight(count: 3, chart: true))
    }
}
