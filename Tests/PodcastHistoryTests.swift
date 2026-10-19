import XCTest

/// 播客：小宇宙节目页只给最新一批单集，刷新时按单集 id 合并，旧单集累积保留。
final class PodcastHistoryTests: XCTestCase {

    private func episode(_ id: String, _ offset: TimeInterval?, title: String? = nil,
                         duration: Int = 600) -> PodcastEpisode {
        PodcastEpisode(id: id, title: title ?? id,
                       pubDate: offset.map { Date(timeIntervalSince1970: 1_700_000_000 + $0) },
                       duration: duration, audioURL: URL(string: "https://example.com/\(id).m4a"))
    }

    private func show(_ episodes: [PodcastEpisode], title: String = "节目", count: Int? = nil) -> PodcastShow {
        PodcastShow(id: "show", title: title, episodeCount: count ?? episodes.count, episodes: episodes)
    }

    func testEpisodesThatFallOffThePageAreKept() {
        var library = PodcastLibrary()
        library.subscribe(show([episode("b", 100), episode("a", 0)]))
        // 下一次读页面：出了新的一集，最旧的 a 已经不在这一批里了。
        _ = library.merge(show([episode("c", 200), episode("b", 100)], count: 3))
        XCTAssertEqual(library.show("show")?.episodes.map(\.id), ["c", "b", "a"])
    }

    func testFreshFieldsWinForTheSameEpisode() {
        var library = PodcastLibrary()
        library.subscribe(show([episode("a", 0, title: "旧标题", duration: 600)]))
        _ = library.merge(show([episode("a", 0, title: "新标题", duration: 900)], title: "新节目名"))
        let kept = library.show("show")
        XCTAssertEqual(kept?.title, "新节目名")
        XCTAssertEqual(kept?.episodes.count, 1)
        XCTAssertEqual(kept?.episodes.first?.title, "新标题")
        XCTAssertEqual(kept?.episodes.first?.duration, 900)
    }

    func testMissingFreshFieldsKeepTheOldOnes() {
        var old = episode("a", 0)
        old.chapters = [PodcastChapter(start: 0, title: "开场")]
        old.imageURL = URL(string: "https://example.com/a.png")
        let fresh = PodcastEpisode(id: "a", title: "a", pubDate: nil, duration: 0, audioURL: nil)
        let merged = PodcastLibrary.updated(old, with: fresh)
        XCTAssertEqual(merged.pubDate, old.pubDate)
        XCTAssertEqual(merged.duration, 600)
        XCTAssertEqual(merged.audioURL, old.audioURL)
        XCTAssertEqual(merged.imageURL, old.imageURL)
        XCTAssertEqual(merged.chapters?.first?.title, "开场")
    }

    func testNewestFirstWithUndatedLast() {
        let combined = PodcastLibrary.combined(show([episode("x", nil), episode("a", 0)]),
                                               with: show([episode("c", 300), episode("b", 100)]))
        XCTAssertEqual(combined.episodes.map(\.id), ["c", "b", "a", "x"])
    }

    func testAnEmptyReadKeepsEverything() {
        var library = PodcastLibrary()
        library.subscribe(show([episode("b", 100), episode("a", 0)]))
        _ = library.merge(show([], count: 2))
        XCTAssertEqual(library.show("show")?.episodes.map(\.id), ["b", "a"])
    }

    func testTheOldestPastTheLimitAreDropped() {
        let kept = show((0..<6).map { episode("e\($0)", TimeInterval($0)) })
        let combined = PodcastLibrary.combined(kept, with: show([episode("e9", 900)]), limit: 4)
        XCTAssertEqual(combined.episodes.map(\.id), ["e9", "e5", "e4", "e3"])
        XCTAssertEqual(PodcastLibrary.episodeLimit, 500)
    }

    func testTheDefaultLimitHolds() {
        let many = show((0..<520).map { episode("e\($0)", TimeInterval($0)) })
        let combined = PodcastLibrary.combined(many, with: show([episode("new", 10_000)]))
        XCTAssertEqual(combined.episodes.count, 500)
        XCTAssertEqual(combined.episodes.first?.id, "new")
    }

    func testResubscribingKeepsHistoryAndMarks() {
        var library = PodcastLibrary()
        library.subscribe(show([episode("b", 100), episode("a", 0)]))
        let mark = library.newSince["show"]
        XCTAssertFalse(library.subscribe(show([episode("c", 200), episode("b", 100)])))
        XCTAssertEqual(library.show("show")?.episodes.map(\.id), ["c", "b", "a"])
        XCTAssertEqual(library.newSince["show"], mark)
    }

    func testAnnouncingAndProgressAreUnchanged() {
        var library = PodcastLibrary()
        library.subscribe(show([episode("b", 100), episode("a", 0)]))
        library.record("a", position: 30, duration: 600)
        let fresh = library.merge(show([episode("c", 200), episode("b", 100)]))
        XCTAssertEqual(fresh.map(\.id), ["c"])
        XCTAssertEqual(library.unheard("show").map(\.id), ["c"])
        XCTAssertEqual(library.resumePosition("a"), 30)
        // 同一批再读一次不再通知。
        XCTAssertTrue(library.merge(show([episode("c", 200), episode("b", 100)])).isEmpty)
        // 取消订阅时连累积下来的旧单集的进度一起清掉。
        library.remove("show")
        XCTAssertNil(library.progress["a"])
    }

    func testOlderEpisodesNote() {
        XCTAssertTrue(PodcastLibrary.hasOlderEpisodes(show([episode("a", 0)], count: 265)))
        XCTAssertFalse(PodcastLibrary.hasOlderEpisodes(show([episode("a", 0)], count: 1)))
    }
}
