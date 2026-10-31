import XCTest

/// 播客存档：旧写法迁移、读不出的只丢那一条、收听状态和封面色。
final class PodcastStoreTests: XCTestCase {
    private let pid = "670bdb14db2cf82757e88a43"
    private let otherPid = "5e4515bd418a84a046e2b11a"
    private let eid = "670be7eedb2cf82757ebea6a"

    private func load(_ json: String) -> PodcastLoad {
        PodcastStore.load(Data(json.utf8))
    }

    private func episode(_ id: String, _ offset: TimeInterval, duration: Int = 600) -> PodcastEpisode {
        PodcastEpisode(id: id, title: id, pubDate: Date(timeIntervalSince1970: 1_700_000_000 + offset),
                       duration: duration, audioURL: URL(string: "https://example.com/\(id).m4a"))
    }

    // MARK: 现在的格式

    func testTheCurrentFormatLoadsUnchanged() throws {
        var library = PodcastLibrary()
        let show = try XCTUnwrap(Xiaoyuzhou.podcast(fromPage: XiaoyuzhouFixtures.podcastPage))
        library.subscribe(show)
        library.record(show.episodes[0].id, position: 120, duration: 600)
        let loaded = PodcastStore.load(try JSONEncoder().encode(library))
        XCTAssertEqual(loaded.library, library)
        XCTAssertEqual(loaded.repaired, 0)
        XCTAssertEqual(loaded.unreadable, 0)
        XCTAssertFalse(loaded.fileUnreadable)
        XCTAssertFalse(loaded.needsSave)
        XCTAssertFalse(loaded.needsBackup)
    }

    func testMissingLibraryKeysNoLongerEmptyTheWholeArchive() throws {
        // 只有 shows：以前严格解码要求 newSince、notifiedThrough、progress 都在，缺一个整份读成空的。
        let json = #"{"shows":[{"id":"\#(pid)","title":"冥想音疗馆","author":"","summary":"","episodeCount":0,"episodes":[]}]}"#
        let decoded = try JSONDecoder().decode(PodcastLibrary.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.shows.map(\.id), [pid])
        XCTAssertEqual(load(json).library.shows.first?.title, "冥想音疗馆")
    }

    // MARK: 旧写法迁移

    func testAPageLinkStoredAsTheIDIsMigrated() {
        let json = #"{"shows":[{"id":"https://www.xiaoyuzhoufm.com/podcast/\#(pid)?s=eyJ1IjoxfQ","title":"冥想音疗馆","episodes":[]}],"newSince":{},"notifiedThrough":{},"progress":{}}"#
        let loaded = load(json)
        XCTAssertEqual(loaded.library.shows.map(\.id), [pid])
        XCTAssertEqual(loaded.library.shows[0].pageURL.absoluteString, "https://www.xiaoyuzhoufm.com/podcast/\(pid)")
        XCTAssertEqual(loaded.repaired, 1)
        XCTAssertTrue(loaded.needsSave)
        XCTAssertEqual(loaded.library.showsToRefetch, [pid])
    }

    func testRenamedFieldsAreRead() throws {
        let json = #"""
        {"shows":[{"pid":"\#(pid)","name":"冥想音疗馆","cover":{"picUrl":"https://image.xyzcdn.net/a.jpg"},
          "episodeCount":"12","latestEpisodePubDate":"2024-10-13T15:31:56.767Z",
          "episodes":[{"eid":"\#(eid)","title":"心灵音乐 005","duration":3602.4,
                       "pubDate":"2024-10-13T15:31:56.767Z","audioURL":"https://media.xyzcdn.net/x.m4a"}]}]}
        """#
        let loaded = load(json)
        let show = try XCTUnwrap(loaded.library.shows.first)
        XCTAssertEqual(show.id, pid)
        XCTAssertEqual(show.title, "冥想音疗馆")
        XCTAssertEqual(show.imageURL?.absoluteString, "https://image.xyzcdn.net/a.jpg")
        XCTAssertEqual(show.episodeCount, 12)
        XCTAssertNotNil(show.latestPubDate)
        XCTAssertEqual(show.episodes.first?.id, eid)
        XCTAssertEqual(show.episodes.first?.duration, 3602)
        XCTAssertNotNil(show.episodes.first?.pubDate)
        XCTAssertEqual(loaded.repaired, 1)
    }

    func testABrokenShowOrEpisodeCostsOnlyItself() {
        let json = #"""
        {"shows":[
          {"id":"\#(pid)","title":"好的","episodes":[{"id":"a","title":"一"},{"title":"没有 id 的一集"},{"id":"b","title":"二"}]},
          {"title":"没有 id 也没有链接"},
          {"id":"\#(otherPid)","title":"另一个","episodes":[]}
        ],"newSince":{},"notifiedThrough":{},"progress":{"a":{"position":30,"duration":600,"finished":false},"z":"坏的"}}
        """#
        let loaded = load(json)
        XCTAssertEqual(loaded.library.shows.map(\.id), [pid, otherPid])
        XCTAssertEqual(loaded.library.shows[0].episodes.map(\.id), ["a", "b"])
        XCTAssertEqual(loaded.unreadable, 1)
        XCTAssertTrue(loaded.needsBackup)
        XCTAssertEqual(loaded.library.progress.keys.sorted(), ["a"])
    }

    func testAListOfLinksIsMigrated() {
        let json = #"""
        ["https://www.xiaoyuzhoufm.com/podcast/\#(pid)?s=abc",
         "推荐给你：https://www.xiaoyuzhoufm.com/episode/\#(eid)",
         " https://xyzfm.link/s/AbC123 ",
         "\#(otherPid)",
         "随便几个字"]
        """#
        let loaded = load(json)
        XCTAssertEqual(loaded.library.shows.map(\.id), [pid, otherPid])
        XCTAssertEqual(loaded.library.shows[0].title, "小宇宙节目")
        XCTAssertEqual(loaded.library.pendingLinks,
                       ["https://www.xiaoyuzhoufm.com/episode/\(eid)", "https://xyzfm.link/s/AbC123"])
        XCTAssertEqual(loaded.repaired, 4)
        XCTAssertEqual(loaded.unreadable, 1)
        XCTAssertEqual(Set(loaded.library.showsToRefetch), [pid, otherPid])
    }

    func testOlderSubscriptionsKey() {
        let json = #"{"subscriptions":[{"url":"https://www.xiaoyuzhoufm.com/podcast/\#(pid)","title":"旧"},{"link":"https://www.xiaoyuzhoufm.com/episode/\#(eid)"}]}"#
        let loaded = load(json)
        XCTAssertEqual(loaded.library.shows.map(\.id), [pid])
        XCTAssertEqual(loaded.library.shows[0].title, "旧")
        XCTAssertEqual(loaded.library.pendingLinks, ["https://www.xiaoyuzhoufm.com/episode/\(eid)"])
        XCTAssertEqual(loaded.repaired, 2)
    }

    func testTheSameShowTwiceKeepsTheFullerCopy() {
        let json = #"""
        {"shows":[{"id":"https://www.xiaoyuzhoufm.com/podcast/\#(pid)","title":"旧","episodes":[]},
                  {"id":"\#(pid)","title":"新","episodes":[{"id":"a","title":"一"}]}]}
        """#
        let loaded = load(json)
        XCTAssertEqual(loaded.library.shows.count, 1)
        XCTAssertEqual(loaded.library.shows[0].title, "新")
    }

    func testAFileThatIsNotAnArchive() {
        XCTAssertTrue(load("不是 JSON").fileUnreadable)
        XCTAssertTrue(load(#"{"something":"else"}"#).fileUnreadable)
        XCTAssertTrue(load("不是 JSON").needsBackup)
        XCTAssertTrue(load("不是 JSON").library.shows.isEmpty)
    }

    func testResolvingAPendingLink() {
        var library = PodcastLibrary()
        library.pendingLinks = ["a", "b"]
        library.resolvePending("a")
        XCTAssertEqual(library.pendingLinks, ["b"])
    }

    func testAMigratedShowStartsCountingNewFromItsFirstRead() {
        var library = PodcastLibrary()
        library.shows = [PodcastStore.placeholder("show")]
        let first = PodcastShow(id: "show", title: "节目", episodes: [episode("a", 0)])
        XCTAssertTrue(library.merge(first).isEmpty, "a first read announces nothing")
        XCTAssertEqual(library.unheardCount, 0)
        XCTAssertEqual(library.show("show")?.title, "节目")
        let second = PodcastShow(id: "show", title: "节目", episodes: [episode("b", 3600), episode("a", 0)])
        XCTAssertEqual(library.merge(second).map(\.id), ["b"])
        XCTAssertEqual(library.unheard("show").map(\.id), ["b"])
    }

    // MARK: 链接

    func testLinkForms() {
        XCTAssertEqual(PodcastStore.link(pid), .podcast(pid))
        XCTAssertEqual(PodcastStore.link("  \"\(pid)\" "), .podcast(pid))
        XCTAssertEqual(PodcastStore.link("/podcast/\(pid)"), .podcast(pid))
        XCTAssertEqual(PodcastStore.link("episode/\(eid)?s=1"), .episode(eid))
        XCTAssertEqual(PodcastStore.link("https://www.xiaoyuzhoufm.com/podcast/\(pid)?s=x"), .podcast(pid))
        XCTAssertNil(PodcastStore.link(""))
        XCTAssertNil(PodcastStore.link("https://example.com/podcast/\(pid)"))
        XCTAssertTrue(PodcastStore.isShortLink("https://xyzfm.link/s/AbC123"))
        XCTAssertTrue(PodcastStore.isShortLink("xyzfm.link/s/AbC123"))
        XCTAssertFalse(PodcastStore.isShortLink("https://xyzfm.link/"))
        XCTAssertFalse(PodcastStore.isShortLink("https://example.com/s/AbC123"))
    }

    // MARK: 收听状态

    func testEpisodeStates() {
        var library = PodcastLibrary()
        let show = PodcastShow(id: "show", title: "节目", episodes: [episode("a", 0)])
        library.subscribe(show)
        _ = library.merge(PodcastShow(id: "show", title: "节目",
                                      episodes: [episode("d", 7200), episode("c", 3600), episode("a", 0)]))
        XCTAssertEqual(library.state(of: episode("d", 7200), in: "show"), .new)
        XCTAssertEqual(library.state(of: episode("a", 0), in: "show"), .unplayed)
        library.record("c", position: 150, duration: 600)
        XCTAssertEqual(library.state(of: episode("c", 3600), in: "show"), .inProgress(0.25))
        library.markFinished("a", duration: 600)
        XCTAssertEqual(library.state(of: episode("a", 0), in: "show"), .finished)
    }

    func testResumeEpisodePrefersOneStarted() {
        var library = PodcastLibrary()
        library.subscribe(PodcastShow(id: "show", title: "节目",
                                      episodes: [episode("c", 7200), episode("b", 3600), episode("a", 0)]))
        XCTAssertEqual(library.resumeEpisode(in: "show")?.id, "c")
        library.record("a", position: 100, duration: 600)
        XCTAssertEqual(library.resumeEpisode(in: "show")?.id, "a")
        library.record("b", position: 50, duration: 600)
        XCTAssertEqual(library.resumeEpisode(in: "show")?.id, "b", "the newest of the started ones")
        library.markFinished("b", duration: 600)
        XCTAssertEqual(library.resumeEpisode(in: "show")?.id, "a")
        XCTAssertNil(library.resumeEpisode(in: "missing"))
    }

    func testRemainingText() {
        XCTAssertEqual(PodcastPlayback.remainingText(position: 600, duration: 2000), "剩 23 分钟")
        XCTAssertEqual(PodcastPlayback.remainingText(position: 0, duration: 3900), "剩 1 小时 5 分钟")
        XCTAssertEqual(PodcastPlayback.remainingText(position: 590, duration: 600), "剩不到 1 分钟")
        XCTAssertEqual(PodcastPlayback.remainingText(position: 10, duration: 0), "")
        XCTAssertEqual(PodcastPlayback.remainingText(position: .nan, duration: 600), "")
        XCTAssertGreaterThan(PodcastPlayback.refreshSpacing, 0)
    }

    // MARK: 封面色

    func testArtTint() throws {
        XCTAssertNil(PodcastArtTint.wash(ColorCode(red: 0.5, green: 0.5, blue: 0.52)), "a grey cover adds no colour")
        let red = try XCTUnwrap(PodcastArtTint.wash(ColorCode(red: 1, green: 0, blue: 0)))
        let (hue, saturation, brightness) = PodcastArtTint.hsv(red)
        XCTAssertEqual(hue, 0, accuracy: 0.01)
        XCTAssertEqual(saturation, PodcastArtTint.maxSaturation, accuracy: 0.01)
        XCTAssertTrue(PodcastArtTint.brightnessRange.contains(brightness))
        let dark = try XCTUnwrap(PodcastArtTint.wash(ColorCode(red: 0.05, green: 0.1, blue: 0.3)))
        XCTAssertGreaterThanOrEqual(PodcastArtTint.hsv(dark).2, PodcastArtTint.brightnessRange.lowerBound - 0.001)
    }
}
