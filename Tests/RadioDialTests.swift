import Foundation
import XCTest

final class RadioDialTests: XCTestCase {
    private func config(_ raw: [String]) -> WidgetConfig {
        WidgetConfig([RadioDial.stationsKey: .list(raw.map { .string($0) })])
    }

    // MARK: Encoding

    func testStationRoundTripsThroughItsString() {
        let station = RadioStation(id: "a1", name: "中国之声", url: "https://ngcdn001.cnr.cn/live/zgzs/index.m3u8",
                                   codec: "HLS", bitrate: 0)
        XCTAssertEqual(RadioStation(decoding: station.encoded, fallbackID: "x"), station)
        var cfg = WidgetConfig()
        RadioDial.store([station], in: &cfg)
        XCTAssertEqual(RadioDial.stations(cfg), [station])
    }

    func testTabsAndNewlinesInANameCannotBreakTheEncoding() {
        let station = RadioStation(id: "a1", name: "Jazz\tFM\nLive", url: "http://example.com/live.mp3")
        let decoded = RadioStation(decoding: station.encoded, fallbackID: "x")
        XCTAssertEqual(decoded?.name, "Jazz FM Live")
        XCTAssertEqual(decoded?.url, "http://example.com/live.mp3")
    }

    func testABareAddressIsAStationNamedAfterItsHost() {
        let decoded = RadioStation(decoding: "https://www.example.org/stream.aac", fallbackID: "s0")
        XCTAssertEqual(decoded?.id, "s0")
        XCTAssertEqual(decoded?.name, "example.org")
        XCTAssertNil(RadioStation(decoding: "not a url", fallbackID: "s0"))
        XCTAssertNil(RadioStation(decoding: "id\tname\tftp://example.com/a", fallbackID: "s0"))
    }

    func testOlderThreeFieldStringsStillRead() {
        let decoded = RadioStation(decoding: "k\t电台\thttp://a.example/x.mp3", fallbackID: "s0")
        XCTAssertEqual(decoded, RadioStation(id: "k", name: "电台", url: "http://a.example/x.mp3"))
    }

    func testNoSavedListMeansThePresetsButAnEmptiedListStaysEmpty() {
        XCTAssertEqual(RadioDial.stations(WidgetConfig()), RadioDial.presets)
        XCTAssertEqual(RadioDial.stations(config([])), [])
        XCTAssertFalse(RadioDial.presets.isEmpty)
        for preset in RadioDial.presets {
            XCTAssertTrue(preset.url.hasPrefix("https://"), preset.name)
            XCTAssertNotNil(RadioDial.streamURL(preset.url), preset.name)
        }
        XCTAssertEqual(Set(RadioDial.presets.map(\.id)).count, RadioDial.presets.count)
    }

    func testRepeatedStreamsAndIDsAreCleanedUp() {
        let stations = RadioDial.stations(config([
            "a\tOne\thttp://a.example/1",
            "a\tTwo\thttp://a.example/2",
            "b\tOne again\thttp://a.example/1",
            "garbage",
        ]))
        XCTAssertEqual(stations.map(\.name), ["One", "Two"])
        XCTAssertEqual(Set(stations.map(\.id)).count, 2)
    }

    func testDetailDescribesTheStream() {
        XCTAssertEqual(RadioStation(name: "a", url: "http://x/a", codec: "mp3", bitrate: 128).detail, "MP3 · 128 kbps")
        XCTAssertEqual(RadioStation(name: "a", url: "https://x/live/index.m3u8").detail, "HLS")
        XCTAssertEqual(RadioStation(name: "a", url: "http://x/a", codec: "UNKNOWN").detail, "网络电台")
    }

    // MARK: Dial

    func testIndexIsClampedAndSteppingWraps() {
        var cfg = config(["a\tA\thttp://a.example/1", "b\tB\thttp://a.example/2", "c\tC\thttp://a.example/3"])
        RadioDial.setIndex(9, in: &cfg)
        XCTAssertEqual(RadioDial.index(cfg, count: 3), 2)
        XCTAssertEqual(RadioDial.current(cfg)?.name, "C")
        XCTAssertEqual(RadioDial.next(2, count: 3), 0)
        XCTAssertEqual(RadioDial.previous(0, count: 3), 2)
        XCTAssertEqual(RadioDial.next(0, count: 0), 0)
        XCTAssertNil(RadioDial.current(config([])))
        XCTAssertEqual(RadioDial.channelText(0), "01")
        XCTAssertEqual(RadioDial.channelText(11), "12")
    }

    func testAddingSkipsAStreamAlreadySaved() {
        let one = RadioStation(id: "a", name: "A", url: "http://a.example/1")
        let list = RadioDial.adding(one, to: [])
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(RadioDial.adding(RadioStation(id: "b", name: "B", url: "http://a.example/1"), to: list).count, 1)
        XCTAssertEqual(RadioDial.removing("a", from: list), [])
    }

    func testRemovingKeepsTheDialOnTheSameStation() {
        // Removing one before the tuned station shifts it down by one.
        XCTAssertEqual(RadioDial.index(afterRemoving: 0, current: 2, count: 4), 1)
        // Removing the tuned last station falls back to its neighbour.
        XCTAssertEqual(RadioDial.index(afterRemoving: 3, current: 3, count: 4), 2)
        // Removing one after it changes nothing.
        XCTAssertEqual(RadioDial.index(afterRemoving: 3, current: 1, count: 4), 1)
        XCTAssertEqual(RadioDial.index(afterRemoving: 0, current: 0, count: 1), 0)
    }

    func testCustomStationsNeedAStreamAddress() {
        let custom = RadioDial.custom(name: "  ", url: " https://radio.example.com/live.m3u8 ", id: "c")
        XCTAssertEqual(custom?.name, "radio.example.com")
        XCTAssertEqual(custom?.codec, "HLS")
        XCTAssertEqual(RadioDial.custom(name: "我的台", url: "http://x.example/a.mp3")?.name, "我的台")
        XCTAssertNil(RadioDial.custom(name: "x", url: "radio.example.com"))
        XCTAssertNil(RadioDial.custom(name: "x", url: "file:///tmp/a.mp3"))
    }

    func testNowPlayingTitleIsCleaned() {
        XCTAssertEqual(RadioDial.nowPlaying("StreamTitle='周杰伦 - 晴天';", stationName: "音乐台"), "周杰伦 - 晴天")
        XCTAssertEqual(RadioDial.nowPlaying("  Artist - Song ", stationName: "X"), "Artist - Song")
        XCTAssertNil(RadioDial.nowPlaying("", stationName: "X"))
        XCTAssertNil(RadioDial.nowPlaying(nil, stationName: "X"))
        XCTAssertNil(RadioDial.nowPlaying("StreamTitle='';", stationName: "X"))
        XCTAssertNil(RadioDial.nowPlaying("Unknown", stationName: "X"))
        XCTAssertNil(RadioDial.nowPlaying("中国之声", stationName: "中国之声"))
    }

    // MARK: Radio Browser

    private func query(_ url: URL) throws -> [String: String] {
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.scheme, "https")
        XCTAssertEqual(parts.host, "de1.api.radio-browser.info")
        XCTAssertEqual(parts.path, "/json/stations/search")
        return Dictionary(uniqueKeysWithValues: (parts.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    func testSearchByNameInsideRegion() throws {
        let items = try query(XCTUnwrap(RadioBrowser.searchURL(name: " 音乐 之声 ", region: .chinese)))
        XCTAssertEqual(items["name"], "音乐 之声")
        XCTAssertEqual(items["language"], "chinese")
        XCTAssertNil(items["countrycode"])
        XCTAssertEqual(items["limit"], "30")
        XCTAssertEqual(items["hidebroken"], "true")
        XCTAssertEqual(items["order"], "clickcount")
        XCTAssertEqual(items["reverse"], "true")

        let hk = try query(XCTUnwrap(RadioBrowser.searchURL(name: "RTHK", region: .hongKong)))
        XCTAssertEqual(hk["name"], "RTHK")
        XCTAssertEqual(hk["countrycode"], "HK")
        XCTAssertNil(hk["language"])
    }

    func testEmptyNameListsRegionTopStations() throws {
        for region in RadioRegion.allCases {
            let items = try query(XCTUnwrap(RadioBrowser.searchURL(name: "   ", region: region)))
            XCTAssertNil(items["name"], region.rawValue)
            XCTAssertEqual(items["order"], "clickcount")
            XCTAssertEqual(items["reverse"], "true")
            switch region {
            case .chinese:
                XCTAssertEqual(items["language"], "chinese")
                XCTAssertNil(items["countrycode"])
            case .mainland, .hongKong, .taiwan, .macau:
                XCTAssertEqual(items["countrycode"], region.rawValue)
                XCTAssertNil(items["language"])
            case .global:
                XCTAssertNil(items["countrycode"])
                XCTAssertNil(items["language"])
            }
        }
        let cn = try query(XCTUnwrap(RadioBrowser.searchURL(region: .mainland)))
        XCTAssertEqual(cn["countrycode"], "CN")
    }

    func testRegionTitlesCodesAndStorage() {
        XCTAssertEqual(RadioRegion.allCases.map(\.title), ["中文电台", "大陆", "香港", "台湾", "澳门", "全球"])
        XCTAssertEqual([RadioRegion.mainland, .hongKong, .taiwan, .macau].map(\.rawValue), ["CN", "HK", "TW", "MO"])
        XCTAssertEqual(RadioRegion.fallback, .chinese)

        var config = WidgetConfig()
        XCTAssertEqual(RadioRegion.stored(config), .chinese)
        RadioRegion.store(.taiwan, in: &config)
        XCTAssertEqual(config.string(RadioRegion.configKey), "TW")
        XCTAssertEqual(RadioRegion.stored(config), .taiwan)
        config.set(RadioRegion.configKey, .string("XX"))
        XCTAssertEqual(RadioRegion.stored(config), .chinese)
        XCTAssertEqual(RadioRegion(stored: "all"), .global)
    }

    func testUserAgentIsDescriptiveASCII() {
        XCTAssertTrue(RadioBrowser.userAgent.hasPrefix("Dockling"))
        XCTAssertTrue(RadioBrowser.userAgent.allSatisfy(\.isASCII))
        XCTAssertEqual(RadioBrowser.attribution, "电台目录来自 Radio Browser")
    }

    func testParsingADirectoryAnswer() throws {
        let json = """
        [
          {"stationuuid": "24711F7F-8ff5-4141", "name": " 怀集音乐之声 ", "url": "http://old.example/a",
           "url_resolved": "https://lhttp.qingting.fm/live/4804/64k.mp3", "codec": "MP3", "bitrate": 64, "hls": 0},
          {"stationuuid": "b2", "name": "CNR", "url": "https://ngcdn001.cnr.cn/live/zgzs/index.m3u8",
           "url_resolved": "", "codec": "UNKNOWN", "bitrate": 0, "hls": 1},
          {"stationuuid": "c3", "name": "Duplicate", "url": "https://lhttp.qingting.fm/live/4804/64k.mp3",
           "url_resolved": "https://lhttp.qingting.fm/live/4804/64k.mp3", "codec": "MP3", "bitrate": 64},
          {"stationuuid": "d4", "name": "", "url": "https://x.example/a", "codec": "MP3"},
          {"stationuuid": "e5", "name": "No address", "url": "", "url_resolved": null},
          {"name": "Extra fields are fine", "url": "http://y.example/b", "votes": 3, "tags": "news"}
        ]
        """
        let stations = try XCTUnwrap(RadioBrowser.parse(Data(json.utf8)))
        XCTAssertEqual(stations.map(\.name), ["怀集音乐之声", "CNR", "Extra fields are fine"])
        XCTAssertEqual(stations[0].url, "https://lhttp.qingting.fm/live/4804/64k.mp3")
        XCTAssertEqual(stations[0].id, "rb-24711f7f")
        XCTAssertEqual(stations[0].detail, "MP3 · 64 kbps")
        XCTAssertEqual(stations[1].url, "https://ngcdn001.cnr.cn/live/zgzs/index.m3u8")
        XCTAssertEqual(stations[1].codec, "HLS")
        XCTAssertNil(RadioBrowser.parse(Data("<html>".utf8)))
        XCTAssertEqual(RadioBrowser.parse(Data("[]".utf8)), [])
    }

    // MARK: Retry and sleep timer

    func testRetryBacksOff() {
        XCTAssertEqual((0..<7).map { RadioRetry.delay(attempt: $0) }, [2, 4, 8, 16, 30, 30, 30])
        XCTAssertEqual(RadioRetry.delay(attempt: -1), 2)
    }

    func testSleepTimerText() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(RadioSleep.choices, [0, 15, 30, 60, 120])
        XCTAssertEqual(RadioSleep.remaining(until: now.addingTimeInterval(725), now: now), "12:05")
        XCTAssertEqual(RadioSleep.remaining(until: now.addingTimeInterval(3_661), now: now), "1:01:01")
        XCTAssertEqual(RadioSleep.remaining(until: now.addingTimeInterval(-5), now: now), "0:00")
        XCTAssertEqual(RadioSleep.title(0), "不定时")
        XCTAssertEqual(RadioSleep.title(15), "15 分钟")
        XCTAssertEqual(RadioSleep.title(60), "1 小时")
        XCTAssertEqual(RadioSleep.title(120), "2 小时")
    }

    // MARK: Catalog and visibility

    func testRadioIsAMediaWidgetThatCanShowOnlyWhilePlaying() {
        let entry = WidgetCatalog.entry(.radio)
        XCTAssertEqual(entry?.category, .media)
        XCTAssertEqual(entry?.name, "收音机")
        XCTAssertTrue(WidgetVisibility.supportsCondition(.radio))
        var radio = WidgetCatalog.make(.radio)!
        XCTAssertEqual(WidgetVisibility.conditionTitle(.radio, config: radio.config), "正在收听时显示")
        radio.config.set(WidgetVisibility.modeKey, .string("conditional"))
        XCTAssertFalse(WidgetVisibility.isVisible(radio, WidgetConditions(radioPlaying: false)))
        XCTAssertTrue(WidgetVisibility.isVisible(radio, WidgetConditions(radioPlaying: true)))
    }
}
