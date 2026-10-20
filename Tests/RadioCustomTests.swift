import Foundation
import XCTest

final class RadioCustomTests: XCTestCase {
    private var counter = 0
    private func nextID() -> String {
        counter += 1
        return "id\(counter)"
    }

    // MARK: Station encoding

    func testOldFiveFieldStationsStillRead() {
        let raw = "a\tOld\thttps://x.example/live.mp3\tMP3\t128"
        let station = RadioStation(decoding: raw, fallbackID: "f")
        XCTAssertEqual(station?.backups, [])
        XCTAssertEqual(station?.isCustom, false)
        XCTAssertEqual(station?.mayBeDead, false)
        // 没有标记和备用地址时写回去还是五段，旧版本读得懂。
        XCTAssertEqual(station?.encoded, raw)
    }

    func testBackupsAndFlagsRoundTrip() {
        let station = RadioStation(id: "c1", name: "我的台", url: "https://a.example/live",
                                   backups: ["https://b.example/live", "http://c.example/live.m3u8"],
                                   isCustom: true, mayBeDead: true)
        let decoded = RadioStation(decoding: station.encoded, fallbackID: "x")
        XCTAssertEqual(decoded, station)
        XCTAssertEqual(decoded?.addresses, ["https://a.example/live", "https://b.example/live",
                                            "http://c.example/live.m3u8"])
    }

    func testBadAndRepeatedBackupsAreDropped() {
        let raw = "c\tX\thttps://a.example/s\t\t0\tcustom\thttps://a.example/s rtmp://bad/x https://b.example/s https://b.example/s"
        let station = RadioStation(decoding: raw, fallbackID: "f")
        XCTAssertEqual(station?.backups, ["https://b.example/s"])
        XCTAssertEqual(station?.isCustom, true)
    }

    func testStationsSharingAnAddressMatch() {
        let one = RadioStation(id: "1", name: "A", url: "https://a.example/s", backups: ["https://b.example/s"])
        let two = RadioStation(id: "2", name: "B", url: "https://b.example/s")
        let three = RadioStation(id: "3", name: "C", url: "https://c.example/s")
        XCTAssertTrue(one.matches(two))
        XCTAssertTrue(two.matches(one))
        XCTAssertFalse(one.matches(three))
        XCTAssertEqual(RadioDial.adding(two, to: [one]), [one])
    }

    func testPastedCustomStationIsMarkedCustom() {
        XCTAssertEqual(RadioDial.custom(name: "x", url: "https://x.example/live.mp3")?.isCustom, true)
    }

    // MARK: Addresses

    func testStreamAddresses() {
        XCTAssertEqual(RadioAddress("https://x.example/live.mp3").streamURL?.host, "x.example")
        XCTAssertNotNil(RadioAddress(" http://x.example/hls/index.m3u8 ").streamURL)
        XCTAssertNotNil(RadioAddress("https://x.example:8000/stream").streamURL)
    }

    func testPlaylistAddressesNeedFetching() {
        XCTAssertEqual(RadioAddress("https://x.example/listen.pls"),
                       .playlist(URL(string: "https://x.example/listen.pls")!))
        XCTAssertEqual(RadioAddress("http://x.example/a.M3U"),
                       .playlist(URL(string: "http://x.example/a.M3U")!))
    }

    func testUnsupportedProtocols() {
        XCTAssertEqual(RadioAddress("rtmp://live.example/app/stream"), .unsupported("RTMP"))
        XCTAssertEqual(RadioAddress("RTSP://cam.example/1"), .unsupported("RTSP"))
        XCTAssertEqual(RadioAddress("mms://old.example/radio"), .unsupported("MMS"))
        XCTAssertEqual(RadioAddress("mmsh://old.example/radio"), .unsupported("MMS"))
        XCTAssertEqual(RadioAddress("https://x.example/live.flv"), .unsupported("FLV"))
    }

    func testInvalidAddresses() {
        XCTAssertEqual(RadioAddress(""), .invalid)
        XCTAssertEqual(RadioAddress("radio.example.com"), .invalid)
        XCTAssertEqual(RadioAddress("file:///tmp/a.mp3"), .invalid)
        XCTAssertEqual(RadioAddress("https://x.example/a b"), .invalid)
    }

    // MARK: Playlists

    func testExtendedM3UGroupsByName() {
        let text = """
        #EXTM3U
        #EXTINF:-1,音乐台
        https://a.example/music.mp3
        #EXTINF:-1 tvg-logo="x",新闻台
        https://a.example/news.m3u8
        #EXTINF:-1,音乐台
        https://b.example/music.mp3
        """
        let parsed = RadioPlaylist.parse(text, makeID: nextID)
        XCTAssertFalse(parsed.isHLSManifest)
        XCTAssertEqual(parsed.stations.map(\.name), ["音乐台", "新闻台"])
        XCTAssertEqual(parsed.stations[0].url, "https://a.example/music.mp3")
        XCTAssertEqual(parsed.stations[0].backups, ["https://b.example/music.mp3"])
        XCTAssertEqual(parsed.stations[1].codec, "HLS")
        XCTAssertTrue(parsed.stations.allSatisfy(\.isCustom))
    }

    func testPlainM3UUsesHostsAndFileName() {
        let one = RadioPlaylist.parse("https://a.example/1.mp3\r\nhttps://a.example/2.mp3\r\n",
                                      fallbackName: "晚间", makeID: nextID)
        XCTAssertEqual(one.stations.count, 1)
        XCTAssertEqual(one.stations[0].name, "晚间")
        XCTAssertEqual(one.stations[0].addresses, ["https://a.example/1.mp3", "https://a.example/2.mp3"])

        let two = RadioPlaylist.parse("https://a.example/1.mp3\nhttps://www.b.example/2.mp3\n",
                                      fallbackName: "晚间", makeID: nextID)
        XCTAssertEqual(two.stations.map(\.name), ["a.example", "b.example"])
    }

    func testPLSWithTitlesAndShoutcastPrefixes() {
        let text = """
        [playlist]
        NumberOfEntries=3
        File2=http://b.example:8000/stream
        Title2=(#2 - 5/100) Jazz FM
        File1=http://a.example:8000/stream
        Title1=(#1 - 12/500) Jazz FM
        Length1=-1
        File3=rtmp://c.example/live
        Title3=Jazz FM
        Version=2
        """
        let parsed = RadioPlaylist.parse(text, makeID: nextID)
        XCTAssertEqual(parsed.stations.count, 1)
        XCTAssertEqual(parsed.stations[0].name, "Jazz FM")
        XCTAssertEqual(parsed.stations[0].addresses, ["http://a.example:8000/stream", "http://b.example:8000/stream"])
        XCTAssertEqual(parsed.unsupported, 1)
    }

    func testHLSManifestIsNotAStationList() {
        let text = "#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXTINF:10,\nseg1.ts\n"
        let parsed = RadioPlaylist.parse(text, makeID: nextID)
        XCTAssertTrue(parsed.isHLSManifest)
        XCTAssertTrue(parsed.stations.isEmpty)
    }

    func testRelativeAndJunkLinesAreSkipped() {
        let parsed = RadioPlaylist.parse("#EXTM3U\nsong.mp3\n\n#comment\nhttps://ok.example/live\n", makeID: nextID)
        XCTAssertEqual(parsed.stations.map(\.url), ["https://ok.example/live"])
        XCTAssertEqual(parsed.unsupported, 0)
    }

    func testCleanName() {
        XCTAssertEqual(RadioPlaylist.cleanName("(#1 - 3/10) Name"), "Name")
        XCTAssertEqual(RadioPlaylist.cleanName("  A\tB "), "A B")
    }

    // MARK: Probe

    func testProbeAcceptsAudio() {
        let bytes = Data([0xFF, 0xFB, 0x90, 0x00])
        XCTAssertTrue(RadioProbe.alive(status: 200, contentType: "audio/mpeg", head: bytes))
        XCTAssertTrue(RadioProbe.alive(status: 200, contentType: "audio/aacp", head: bytes))
        XCTAssertTrue(RadioProbe.alive(status: 200, contentType: "application/ogg", head: bytes))
        XCTAssertTrue(RadioProbe.alive(status: 206, contentType: nil, head: bytes))
        XCTAssertTrue(RadioProbe.alive(status: 200, contentType: "application/vnd.apple.mpegurl",
                                       head: Data("#EXTM3U\n#EXT-X-VERSION:3".utf8)))
        XCTAssertTrue(RadioProbe.alive(status: 200, contentType: "text/plain",
                                       head: Data("#EXTM3U\n".utf8)))
    }

    func testProbeRejectsPagesAndErrors() {
        let bytes = Data([0xFF, 0xFB])
        XCTAssertFalse(RadioProbe.alive(status: 404, contentType: "audio/mpeg", head: bytes))
        XCTAssertFalse(RadioProbe.alive(status: 500, contentType: nil, head: bytes))
        XCTAssertFalse(RadioProbe.alive(status: 200, contentType: "text/html; charset=utf-8",
                                        head: Data("<html><body>".utf8)))
        XCTAssertFalse(RadioProbe.alive(status: 200, contentType: "application/octet-stream",
                                        head: Data("<!DOCTYPE html>".utf8)))
        XCTAssertFalse(RadioProbe.alive(status: 200, contentType: "audio/x-scpls", head: Data("[playlist]".utf8)))
        XCTAssertFalse(RadioProbe.alive(status: 200, contentType: nil, head: Data()))
        XCTAssertFalse(RadioProbe.alive(status: 200, contentType: "application/json", head: Data("{}".utf8)))
    }

    // MARK: Health check

    func testAutoCheckOncePerDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let morning = Date(timeIntervalSince1970: 1_792_454_400) // 2026-10-20 08:00 +08:00
        XCTAssertEqual(RadioHealth.dayStamp(morning, calendar: calendar), "2026-10-20")
        XCTAssertTrue(RadioHealth.shouldAutoCheck(lastStamp: nil, now: morning, calendar: calendar))
        XCTAssertTrue(RadioHealth.shouldAutoCheck(lastStamp: "2026-10-19", now: morning, calendar: calendar))
        XCTAssertFalse(RadioHealth.shouldAutoCheck(lastStamp: "2026-10-20", now: morning.addingTimeInterval(12 * 3600),
                                                   calendar: calendar))
        XCTAssertTrue(RadioHealth.shouldAutoCheck(lastStamp: "2026-10-20", now: morning.addingTimeInterval(17 * 3600),
                                                  calendar: calendar))
    }

    func testAddressesToCheckAreUnique() {
        let a = RadioStation(id: "a", name: "A", url: "https://a/1", backups: ["https://a/2"])
        let b = RadioStation(id: "b", name: "B", url: "https://a/2")
        XCTAssertEqual(RadioHealth.addresses([a, b]), ["https://a/1", "https://a/2"])
    }

    func testDeadStationIsMarkedButKept() {
        let a = RadioStation(id: "a", name: "A", url: "https://a/1", backups: ["https://a/2"])
        let result = RadioHealth.applying(["https://a/1": false, "https://a/2": false], to: [a])
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].mayBeDead)
        XCTAssertEqual(result[0].addresses, a.addresses)
        XCTAssertEqual(RadioHealth.dead(result).map(\.id), ["a"])
    }

    func testWorkingBackupMovesToTheFront() {
        let a = RadioStation(id: "a", name: "A", url: "https://a/1", backups: ["https://a/2", "https://a/3"],
                             mayBeDead: true)
        let result = RadioHealth.applying(["https://a/1": false, "https://a/2": false, "https://a/3": true], to: [a])
        XCTAssertFalse(result[0].mayBeDead)
        XCTAssertEqual(result[0].url, "https://a/3")
        XCTAssertEqual(result[0].backups, ["https://a/1", "https://a/2"])
        XCTAssertEqual(result[0].id, "a")
    }

    func testHealthyOrderIsKept() {
        let a = RadioStation(id: "a", name: "A", url: "https://a/1", backups: ["https://a/2"])
        let result = RadioHealth.applying(["https://a/1": true, "https://a/2": true], to: [a])
        XCTAssertEqual(result, [a])
    }

    func testUncheckedStationsAreUntouched() {
        let fresh = RadioStation(id: "n", name: "N", url: "https://n/1", mayBeDead: true)
        XCTAssertEqual(RadioHealth.applying(["https://other": false], to: [fresh]), [fresh])
    }

    func testNothingConnectingAcrossStationsLooksOffline() {
        let a = RadioStation(id: "a", name: "A", url: "https://a/1", backups: ["https://a/2"])
        let b = RadioStation(id: "b", name: "B", url: "https://b/1")
        // 两个电台一条都连不上：多半没联网，这次不算。
        XCTAssertTrue(RadioHealth.looksOffline(["https://a/1": false, "https://a/2": false, "https://b/1": false],
                                               stations: [a, b]))
        // 有一条连得上就是真的结果。
        XCTAssertFalse(RadioHealth.looksOffline(["https://a/1": false, "https://a/2": false, "https://b/1": true],
                                                stations: [a, b]))
        // 只测了一个电台（主地址加备用都坏了）分不出来，照常标失效。
        XCTAssertFalse(RadioHealth.looksOffline(["https://a/1": false, "https://a/2": false], stations: [a, b]))
        XCTAssertFalse(RadioHealth.looksOffline([:], stations: [a, b]))
    }

    func testBannerAndDismissal() {
        let a = RadioStation(id: "a", name: "A", url: "https://a/1", mayBeDead: true)
        let b = RadioStation(id: "b", name: "B", url: "https://b/1", mayBeDead: true)
        XCTAssertFalse(RadioHealth.bannerVisible(dead: [], dismissed: nil))
        XCTAssertTrue(RadioHealth.bannerVisible(dead: [a], dismissed: nil))
        let token = RadioHealth.dismissToken([a])
        XCTAssertFalse(RadioHealth.bannerVisible(dead: [a], dismissed: token))
        // 又多了一个失效的，再提示。
        XCTAssertTrue(RadioHealth.bannerVisible(dead: [a, b], dismissed: token))
    }

    func testRemovingConfirmedStationsKeepsTheDial() {
        let list = ["a", "b", "c", "d"].map { RadioStation(id: $0, name: $0, url: "https://\($0)/s") }
        XCTAssertEqual(RadioHealth.removing(["b", "d"], from: list).map(\.id), ["a", "c"])
        // 调在 c 上，删掉 b 后 c 往前挪一位。
        XCTAssertEqual(RadioHealth.index(afterRemoving: ["b"], from: list, current: 2), 1)
        // 调在被删的 b 上，停到它后面那台。
        XCTAssertEqual(RadioHealth.index(afterRemoving: ["b"], from: list, current: 1), 1)
        XCTAssertEqual(RadioHealth.index(afterRemoving: ["d"], from: list, current: 3), 2)
        XCTAssertEqual(RadioHealth.index(afterRemoving: ["a", "b", "c", "d"], from: list, current: 2), 0)
    }

    // MARK: Failover

    func testSingleAddressKeepsTheOldRetrySchedule() {
        var round = 0
        var waits: [Double] = []
        var problems: [Bool] = []
        for _ in 0..<6 {
            let step = RadioFailover.after(failed: 0, count: 1, round: round)
            XCTAssertEqual(step.address, 0)
            waits.append(step.wait)
            problems.append(step.showsProblem)
            round = step.round
        }
        XCTAssertEqual(waits, [2, 4, 8, 16, 30, 30])
        XCTAssertEqual(problems, [false, false, true, true, true, true])
    }

    func testBackupsAreTriedInOrderQuickly() {
        let first = RadioFailover.after(failed: 0, count: 3, round: 0)
        XCTAssertEqual(first, RadioFailover.Step(address: 1, wait: 1, round: 0, showsProblem: false))
        let second = RadioFailover.after(failed: 1, count: 3, round: 0)
        XCTAssertEqual(second.address, 2)
        XCTAssertEqual(second.wait, RadioFailover.backupWait)
        // 一轮都失败，回到主地址并开始退避。
        let wrap = RadioFailover.after(failed: 2, count: 3, round: 0)
        XCTAssertEqual(wrap, RadioFailover.Step(address: 0, wait: 2, round: 1, showsProblem: false))
    }

    // MARK: Fade

    func testFadePhases() {
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(RadioFade.phase(now: now, stopAt: nil), .off)
        XCTAssertEqual(RadioFade.phase(now: now, stopAt: now.addingTimeInterval(60)), .full)
        XCTAssertEqual(RadioFade.phase(now: now, stopAt: now.addingTimeInterval(30)), .fading(1))
        XCTAssertEqual(RadioFade.phase(now: now, stopAt: now.addingTimeInterval(15)), .fading(0.5))
        XCTAssertEqual(RadioFade.phase(now: now, stopAt: now.addingTimeInterval(3)), .fading(0.1))
        XCTAssertEqual(RadioFade.phase(now: now, stopAt: now), .due)
        XCTAssertEqual(RadioFade.phase(now: now, stopAt: now.addingTimeInterval(-1)), .due)
    }

    func testFadeIsLinear() {
        XCTAssertEqual(RadioFade.multiplier(remaining: 30), 1)
        XCTAssertEqual(RadioFade.multiplier(remaining: 45), 1)
        XCTAssertEqual(RadioFade.multiplier(remaining: 22.5), 0.75)
        XCTAssertEqual(RadioFade.multiplier(remaining: 7.5), 0.25)
        XCTAssertEqual(RadioFade.multiplier(remaining: 0), 0)
        XCTAssertEqual(RadioFade.multiplier(remaining: -5), 0)
    }

    func testFadeGainScalesTheVolume() {
        XCTAssertEqual(RadioFade.gain(volume: 60, multiplier: 1), 0.6, accuracy: 1e-9)
        XCTAssertEqual(RadioFade.gain(volume: 60, multiplier: 0.5), 0.3, accuracy: 1e-9)
        XCTAssertEqual(RadioFade.gain(volume: 80, multiplier: 0), 0)
        XCTAssertEqual(RadioFade.gain(volume: 150, multiplier: 2), 1)
    }
}
