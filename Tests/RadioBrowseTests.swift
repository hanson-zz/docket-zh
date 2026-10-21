import Foundation
import XCTest

final class RadioBrowseTests: XCTestCase {
    private func item(_ id: String, _ url: String, clicks: Int) -> RadioListing {
        RadioListing(station: RadioStation(id: id, name: id, url: url), clicks: clicks)
    }

    private func query(_ url: URL) -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    }

    // MARK: Genres

    func testEveryGenreMapsToEnglishTagsAndCrosstalkToSeveral() {
        for genre in RadioGenre.allCases {
            XCTAssertFalse(genre.tags.isEmpty, "\(genre)")
            XCTAssertFalse(genre.title.isEmpty)
            for tag in genre.tags {
                XCTAssertNil(tag.range(of: "\\p{Han}", options: .regularExpression), "tag 要是英文：\(tag)")
                XCTAssertEqual(tag, tag.lowercased())
            }
        }
        XCTAssertEqual(RadioGenre.crosstalk.title, "相声评书")
        XCTAssertTrue(RadioGenre.crosstalk.tags.contains("crosstalk"))
        XCTAssertGreaterThan(RadioGenre.crosstalk.tags.count, 1)
        XCTAssertEqual(RadioGenre.news.tags, ["news"])
    }

    func testTappingTheChosenGenreAgainGoesBackToPopular() {
        XCTAssertEqual(RadioGenre.toggled(.news, current: nil), .news)
        XCTAssertNil(RadioGenre.toggled(.news, current: .news))
        XCTAssertEqual(RadioGenre.toggled(.jazz, current: .news), .jazz)
        XCTAssertNil(RadioGenre.toggled(nil, current: .rock))
    }

    // MARK: URLs

    func testAGenreSearchAsksOncePerTagWithTheSameOffset() {
        let search = RadioSearch(region: .chinese, genre: .crosstalk)
        let urls = search.urls(offset: 60)
        XCTAssertEqual(urls.count, RadioGenre.crosstalk.tags.count)
        for (url, tag) in zip(urls, RadioGenre.crosstalk.tags) {
            let q = query(url)
            XCTAssertEqual(q["tag"], tag)
            XCTAssertEqual(q["tagExact"], "true")
            XCTAssertEqual(q["offset"], "60")
            XCTAssertEqual(q["limit"], "30")
            XCTAssertEqual(q["language"], "chinese")
            XCTAssertEqual(q["order"], "clickcount")
            XCTAssertEqual(q["reverse"], "true")
            XCTAssertEqual(url.path, "/json/stations/search")
        }
    }

    func testPopularIsOneRequestWithoutATag() {
        let urls = RadioSearch(name: "音乐", region: .hongKong).urls()
        XCTAssertEqual(urls.count, 1)
        let q = query(urls[0])
        XCTAssertNil(q["tag"])
        XCTAssertEqual(q["name"], "音乐")
        XCTAssertEqual(q["countrycode"], "HK")
        XCTAssertEqual(q["offset"], "0")
    }

    func testACountryReplacesTheRegionAndCanAskForChineseOnly() {
        let plain = query(RadioSearch(region: .chinese, country: "us").urls()[0])
        XCTAssertEqual(plain["countrycode"], "US")
        XCTAssertNil(plain["language"])
        let chinese = query(RadioSearch(country: "US", chineseOnly: true).urls(limit: 4)[0])
        XCTAssertEqual(chinese["language"], "chinese")
        XCTAssertEqual(chinese["limit"], "4")
    }

    func testTheOldSearchURLIsUnchanged() {
        let q = query(RadioBrowser.searchURL(name: "", region: .chinese)!)
        XCTAssertNil(q["offset"])
        XCTAssertNil(q["tag"])
        XCTAssertEqual(q["language"], "chinese")
    }

    // MARK: Merge and paging

    func testMergingDropsRepeatsAndSortsTheNewBatchByClicks() {
        let shown = [item("a", "https://a.example/s", clicks: 5)]
        let news = [item("b", "https://b.example/s", clicks: 10), item("a", "https://a.example/s", clicks: 5)]
        let talk = [item("c", "https://c.example/s", clicks: 50),
                    item("b2", "https://b.example/s", clicks: 10),   // 同一条地址，算重复
                    item("d", "https://d.example/s", clicks: 10)]
        let merged = RadioBrowse.merge(shown, batches: [news, talk])
        XCTAssertEqual(merged.map(\.id), ["a", "c", "b", "d"])
    }

    func testMergingKeepsWhatIsShownInPlace() {
        let shown = [item("low", "https://l.example/s", clicks: 1)]
        let merged = RadioBrowse.merge(shown, batches: [[item("high", "https://h.example/s", clicks: 999)]])
        XCTAssertEqual(merged.first?.id, "low")
        XCTAssertEqual(merged.count, 2)
        XCTAssertEqual(RadioBrowse.merge([], batches: []), [])
    }

    func testPagingOffsetsAndWhenThereIsMore() {
        XCTAssertEqual(RadioBrowse.offset(page: 0), 0)
        XCTAssertEqual(RadioBrowse.offset(page: 2), 60)
        XCTAssertEqual(RadioBrowse.offset(page: -1), 0)
        XCTAssertTrue(RadioBrowse.hasMore(rowsPerTag: [30]))
        XCTAssertTrue(RadioBrowse.hasMore(rowsPerTag: [3, 30]))
        XCTAssertFalse(RadioBrowse.hasMore(rowsPerTag: [29, 7]))
        XCTAssertFalse(RadioBrowse.hasMore(rowsPerTag: []))
        XCTAssertTrue(RadioBrowse.hasMore(rowsPerTag: [4], size: 4))
    }

    func testATotalIsOnlyGivenWhenTheCountryListKnowsIt() {
        let counts = ["CN": 2173, "HK": 120]
        XCTAssertEqual(RadioBrowse.knownTotal(RadioSearch(country: "CN"), counts: counts), 2173)
        XCTAssertNil(RadioBrowse.knownTotal(RadioSearch(country: "CN", chineseOnly: true), counts: counts))
        XCTAssertEqual(RadioBrowse.knownTotal(RadioSearch(region: .hongKong), counts: counts), 120)
        XCTAssertNil(RadioBrowse.knownTotal(RadioSearch(region: .hongKong, genre: .news), counts: counts))
        XCTAssertNil(RadioBrowse.knownTotal(RadioSearch(name: "x", region: .mainland), counts: counts))
        XCTAssertNil(RadioBrowse.knownTotal(RadioSearch(region: .chinese), counts: counts))
        XCTAssertNil(RadioBrowse.knownTotal(RadioSearch(country: "FR"), counts: counts))
    }

    func testListingsKeepClicksAndPlaceAndCountRawRows() throws {
        let json = """
        [{"stationuuid":"11111111-aaaa","name":"上海新闻广播","url":"https://a.example/1.mp3","codec":"MP3",
          "bitrate":0,"clickcount":321,"state":"上海","countrycode":"CN","country":"China"},
         {"stationuuid":"22222222-bbbb","name":"","url":"https://a.example/2.mp3","clickcount":9},
         {"stationuuid":"33333333-cccc","name":"KEXP","url":"https://a.example/3.aac","codec":"AAC",
          "bitrate":128,"clickcount":40,"state":"","countrycode":"US","country":"The United States Of America"}]
        """
        let parsed = try XCTUnwrap(RadioBrowser.parseListings(Data(json.utf8)))
        XCTAssertEqual(parsed.rows, 3)
        XCTAssertEqual(parsed.listings.count, 2)
        XCTAssertEqual(parsed.listings[0].clicks, 321)
        XCTAssertEqual(parsed.listings[0].place, "上海")
        XCTAssertEqual(parsed.listings[0].detail, "MP3 · 上海")
        XCTAssertEqual(parsed.listings[1].clicks, 40)
        XCTAssertEqual(parsed.listings[1].place, "美国")
        XCTAssertNil(RadioBrowser.parseListings(Data("nope".utf8)))
    }

    // MARK: Countries

    func testCountryCountsParseSumDuplicatesAndDropJunk() throws {
        let json = """
        [{"name":"China","iso_3166_1":"CN","stationcount":2000},
         {"name":"China","iso_3166_1":"cn","stationcount":173},
         {"name":"Germany","iso_3166_1":"DE","stationcount":6278},
         {"name":"Nowhere","iso_3166_1":"","stationcount":5},
         {"name":"Bad","iso_3166_1":"XYZ","stationcount":5},
         {"name":"Empty","iso_3166_1":"AQ","stationcount":0}]
        """
        let list = try XCTUnwrap(RadioCountries.parse(Data(json.utf8)))
        XCTAssertEqual(list.map(\.code), ["DE", "CN"])
        XCTAssertEqual(list.map(\.count), [6278, 2173])
        XCTAssertEqual(list[1].englishName, "China")
        let totals = RadioCountries.totals(list)
        XCTAssertEqual(totals.regions, 2)
        XCTAssertEqual(totals.stations, 8451)
        XCTAssertNil(RadioCountries.parse(Data("{}".utf8)))
    }

    func testCountryCacheRoundTripsAndExpiresAfterADay() {
        let list = [RadioCountry(code: "US", count: 7454, englishName: "The United States, Of: America"),
                    RadioCountry(code: "CN", count: 2173, englishName: "China")]
        let decoded = RadioCountries.decode(RadioCountries.encode(list))
        XCTAssertEqual(decoded.map(\.code), ["US", "CN"])
        XCTAssertEqual(decoded.map(\.count), [7454, 2173])
        XCTAssertEqual(RadioCountries.decode("garbage,ZZZ:1,CN:x"), [])
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(RadioCountries.isFresh(savedAt: now.addingTimeInterval(-3600), now: now))
        XCTAssertFalse(RadioCountries.isFresh(savedAt: now.addingTimeInterval(-86_400), now: now))
        XCTAssertFalse(RadioCountries.isFresh(savedAt: now.addingTimeInterval(60), now: now))
        XCTAssertFalse(RadioCountries.isFresh(savedAt: nil, now: now))
    }

    func testTiersFlagsNamesAndBars() {
        XCTAssertEqual([0, 1, 49, 50, 499, 500, 9000].map(RadioCountries.tier), [0, 1, 1, 2, 2, 3, 3])
        XCTAssertEqual(RadioCountries.flag("cn"), "🇨🇳")
        XCTAssertEqual(RadioCountries.flag("X"), "")
        let zh = Locale(identifier: "zh-Hans")
        XCTAssertEqual(RadioCountries.name("HK", locale: zh), "香港")
        XCTAssertEqual(RadioCountries.name("DE", locale: zh), "德国")
        XCTAssertEqual(RadioCountries.name("TW", locale: Locale(identifier: "en")), "Taiwan")
        XCTAssertEqual(RadioCountries.barFraction(50, max: 100), 0.5)
        XCTAssertEqual(RadioCountries.barFraction(5, max: 0), 0)
    }

    func testCountryFilterAndOrder() {
        let zh = Locale(identifier: "zh-Hans")
        let list = [RadioCountry(code: "US", count: 9, englishName: "The United States Of America"),
                    RadioCountry(code: "JP", count: 5, englishName: "Japan"),
                    RadioCountry(code: "DE", count: 7, englishName: "Germany")]
        XCTAssertEqual(RadioCountries.filter(list, query: "日本", locale: zh).map(\.code), ["JP"])
        XCTAssertEqual(RadioCountries.filter(list, query: "japan", locale: zh).map(\.code), ["JP"])
        XCTAssertEqual(RadioCountries.filter(list, query: "de", locale: zh).map(\.code), ["DE"])
        XCTAssertEqual(RadioCountries.filter(list, query: "  ", locale: zh).count, 3)
        XCTAssertEqual(RadioCountries.ordered(list, by: .count).map(\.code), ["US", "DE", "JP"])
        XCTAssertEqual(RadioCountries.ordered(list, by: .name, locale: Locale(identifier: "en")).map(\.code),
                       ["DE", "JP", "US"])
    }

    // MARK: Dot map

    private var smallMap: RadioWorldMap {
        RadioWorldMap(cols: 10, rows: 5, dots: [
            .init(col: 1, row: 1, code: "AA"), .init(col: 2, row: 1, code: "AA"),
            .init(col: 5, row: 2, code: "BB"),
            .init(col: 8, row: 3, code: nil), .init(col: 9, row: 3, code: "CC"),
        ])
    }

    func testTappingSnapsToTheNearestCountryWithStations() {
        let counts = ["AA": 10, "BB": 3, "CC": 0]
        // 正中 BB 的点。
        XCTAssertEqual(smallMap.nearestCountry(col: 5.5, row: 2.5, counts: counts), "BB")
        // 两国之间偏 AA。
        XCTAssertEqual(smallMap.nearestCountry(col: 3.6, row: 1.8, counts: counts), "AA")
        // CC 没有台：吸附到 3 格内有台的 BB；太远就没点中。
        XCTAssertEqual(smallMap.nearestCountry(col: 7.5, row: 2.5, counts: counts), "BB")
        XCTAssertNil(smallMap.nearestCountry(col: 9.5, row: 3.5, counts: counts))
        XCTAssertNil(smallMap.nearestCountry(col: 5.5, row: 2.5, counts: [:]))
    }

    func testViewPointsBecomeCellsAndCountriesHaveACentre() {
        let cell = smallMap.cell(at: (x: 55, y: 25), width: 100)
        XCTAssertEqual(cell.col, 5.5, accuracy: 0.001)
        XCTAssertEqual(cell.row, 2.5, accuracy: 0.001)
        let centre = smallMap.centre(of: "AA")
        XCTAssertEqual(centre?.col ?? 0, 2.0, accuracy: 0.001)
        XCTAssertEqual(centre?.row ?? 0, 1.5, accuracy: 0.001)
        XCTAssertEqual(centre?.top ?? -1, 1, accuracy: 0.001)
        XCTAssertNil(smallMap.centre(of: "ZZ"))
    }

    func testTheMapFileFormatReadsAndRejectsJunk() throws {
        let json = #"{"cols":4,"rows":2,"codes":["","CN","-99"],"dots":[[0,0,1],[1,0,0],[2,1,2],[9,9,1],[1,1]]}"#
        let map = try XCTUnwrap(RadioWorldMap(data: Data(json.utf8)))
        XCTAssertEqual(map.cols, 4)
        XCTAssertEqual(map.dots.count, 3)
        XCTAssertEqual(map.dots[0].code, "CN")
        XCTAssertNil(map.dots[1].code)
        XCTAssertNil(map.dots[2].code)
        XCTAssertNil(RadioWorldMap(data: Data("[]".utf8)))
        XCTAssertNil(RadioWorldMap(data: Data(#"{"cols":0,"rows":2,"codes":[],"dots":[]}"#.utf8)))
    }
}
