import XCTest

/// 播客: reading 小宇宙 pages, links, and what counts as a new episode.
final class PodcastTests: XCTestCase {

    // MARK: Links

    func testShowAndEpisodeLinks() {
        XCTAssertEqual(XiaoyuzhouLink.parse("https://www.xiaoyuzhoufm.com/podcast/670bdb14db2cf82757e88a43"),
                       .podcast("670bdb14db2cf82757e88a43"))
        XCTAssertEqual(XiaoyuzhouLink.parse("https://www.xiaoyuzhoufm.com/episode/670be7eedb2cf82757ebea6a?s=abc"),
                       .episode("670be7eedb2cf82757ebea6a"))
        XCTAssertEqual(XiaoyuzhouLink.parse("xiaoyuzhoufm.com/podcast/670bdb14db2cf82757e88a43"),
                       .podcast("670bdb14db2cf82757e88a43"))
    }

    func testALinkInsideASharedMessage() {
        let shared = "我在小宇宙听这个节目，推荐给你：https://www.xiaoyuzhoufm.com/podcast/670bdb14db2cf82757e88a43 快来听"
        XCTAssertEqual(XiaoyuzhouLink.parse(shared), .podcast("670bdb14db2cf82757e88a43"))
    }

    func testOtherAddressesAreNotShows() {
        XCTAssertNil(XiaoyuzhouLink.parse("https://www.xiaoyuzhoufm.com/"))
        XCTAssertNil(XiaoyuzhouLink.parse("https://www.xiaoyuzhoufm.com/about"))
        XCTAssertNil(XiaoyuzhouLink.parse("https://example.com/podcast/670bdb14db2cf82757e88a43"))
        XCTAssertNil(XiaoyuzhouLink.parse("随便几个字"))
    }

    func testPageURLs() {
        XCTAssertEqual(XiaoyuzhouLink.podcast("abc12345").pageURL.absoluteString,
                       "https://www.xiaoyuzhoufm.com/podcast/abc12345")
        XCTAssertEqual(XiaoyuzhouLink.episode("abc12345").pageURL.absoluteString,
                       "https://www.xiaoyuzhoufm.com/episode/abc12345")
    }

    // MARK: Pages

    func testNextDataIsFound() throws {
        let data = try XCTUnwrap(Xiaoyuzhou.nextData(XiaoyuzhouFixtures.podcastPage))
        XCTAssertNotNil(try JSONSerialization.jsonObject(with: data))
        XCTAssertNil(Xiaoyuzhou.nextData("<html><body>没有数据</body></html>"))
    }

    func testShowPage() throws {
        let show = try XCTUnwrap(Xiaoyuzhou.podcast(fromPage: XiaoyuzhouFixtures.podcastPage))
        XCTAssertEqual(show.id, "670bdb14db2cf82757e88a43")
        XCTAssertEqual(show.title, "冥想音疗馆")
        XCTAssertEqual(show.author, "Hanson汉森")
        XCTAssertEqual(show.episodeCount, 5)
        XCTAssertEqual(show.imageURL?.host, "image.xyzcdn.net")
        XCTAssertEqual(show.episodes.count, 2)

        let newest = show.episodes[0]
        XCTAssertEqual(newest.id, "670be7eedb2cf82757ebea6a")
        XCTAssertTrue(newest.title.hasPrefix("心灵音乐 - 005"))
        XCTAssertEqual(newest.duration, 3602)
        XCTAssertEqual(newest.audioURL?.absoluteString,
                       "https://media.xyzcdn.net/lmQvN-hRgL_sb8WeUDLlFTIged7v.m4a")
        XCTAssertNotNil(newest.pubDate)
        // Newest first.
        XCTAssertGreaterThan(newest.pubDate!, show.episodes[1].pubDate!)
        XCTAssertEqual(show.newestDate, show.latestPubDate)
    }

    func testEpisodePageNamesItsShow() throws {
        let found = try XCTUnwrap(Xiaoyuzhou.episode(fromPage: XiaoyuzhouFixtures.episodePage))
        XCTAssertEqual(found.podcastID, "670bdb14db2cf82757e88a43")
        XCTAssertEqual(found.podcastTitle, "冥想音疗馆")
        XCTAssertEqual(found.episode.id, "670be7eedb2cf82757ebea6a")
        XCTAssertEqual(found.episode.duration, 3602)
        // An episode page is not a show page.
        XCTAssertNil(Xiaoyuzhou.podcast(fromPage: XiaoyuzhouFixtures.episodePage))
    }

    func testABrokenPageIsNil() {
        let page = #"<script id="__NEXT_DATA__" type="application/json">{"props":{"pageProps":{}}}</script>"#
        XCTAssertNil(Xiaoyuzhou.podcast(fromPage: page))
        XCTAssertNil(Xiaoyuzhou.podcast(fromPage: #"<script id="__NEXT_DATA__" type="application/json">{oops</script>"#))
    }

    func testDates() {
        let withFraction = Xiaoyuzhou.date("2024-10-13T15:31:57.767Z")
        let without = Xiaoyuzhou.date("2024-10-13T15:31:57Z")
        XCTAssertNotNil(withFraction)
        XCTAssertNotNil(without)
        XCTAssertEqual(withFraction!.timeIntervalSince(without!), 0.767, accuracy: 0.001)
        XCTAssertNil(Xiaoyuzhou.date("昨天"))
        XCTAssertNil(Xiaoyuzhou.date(nil))
    }

    // MARK: New episodes

    private func episode(_ id: String, _ offset: TimeInterval) -> PodcastEpisode {
        PodcastEpisode(id: id, title: id, pubDate: Date(timeIntervalSince1970: 1_700_000_000 + offset),
                       duration: 600, audioURL: URL(string: "https://example.com/\(id).m4a"))
    }

    private func show(_ episodes: [PodcastEpisode]) -> PodcastShow {
        PodcastShow(id: "show", title: "节目", episodeCount: episodes.count, episodes: episodes)
    }

    func testSubscribingAnnouncesNothingOld() {
        var library = PodcastLibrary()
        XCTAssertTrue(library.subscribe(show([episode("b", 100), episode("a", 0)])))
        XCTAssertFalse(library.subscribe(show([episode("b", 100), episode("a", 0)])))
        XCTAssertEqual(library.shows.count, 1)
        XCTAssertEqual(library.unheardCount, 0)
        XCTAssertTrue(library.merge(show([episode("b", 100), episode("a", 0)])).isEmpty)
    }

    func testANewerEpisodeIsAnnouncedOnceAndUnheardUntilPlayed() {
        var library = PodcastLibrary()
        library.subscribe(show([episode("a", 0)]))
        let fresh = library.merge(show([episode("b", 3600), episode("a", 0)]))
        XCTAssertEqual(fresh.map(\.id), ["b"])
        XCTAssertEqual(library.unheard("show").map(\.id), ["b"])
        XCTAssertEqual(library.unheardCount, 1)
        // The next read finds nothing new to announce.
        XCTAssertTrue(library.merge(show([episode("b", 3600), episode("a", 0)])).isEmpty)
        // Playing it clears it.
        library.record("b", position: 30, duration: 600)
        XCTAssertEqual(library.unheardCount, 0)
    }

    func testMarkHeardClearsWithoutPlaying() {
        var library = PodcastLibrary()
        library.subscribe(show([episode("a", 0)]))
        _ = library.merge(show([episode("c", 7200), episode("b", 3600), episode("a", 0)]))
        XCTAssertEqual(library.unheardCount, 2)
        library.markHeard("show")
        XCTAssertEqual(library.unheardCount, 0)
    }

    func testWithoutAMarkNothingIsNew() {
        XCTAssertTrue(PodcastLibrary.newEpisodes(in: show([episode("a", 0)]), after: nil).isEmpty)
    }

    func testAnUnsubscribedShowIsIgnoredAndRemovalClearsItsState() {
        var library = PodcastLibrary()
        XCTAssertTrue(library.merge(show([episode("a", 0)])).isEmpty)
        XCTAssertTrue(library.shows.isEmpty)
        library.subscribe(show([episode("a", 0)]))
        library.record("a", position: 10, duration: 600)
        library.remove("show")
        XCTAssertTrue(library.shows.isEmpty)
        XCTAssertNil(library.progress["a"])
        XCTAssertNil(library.newSince["show"])
    }

    func testTheLibrarySurvivesARoundTripWithItsMilliseconds() throws {
        var library = PodcastLibrary()
        let show = try XCTUnwrap(Xiaoyuzhou.podcast(fromPage: XiaoyuzhouFixtures.podcastPage))
        library.subscribe(show)
        let decoded = try JSONDecoder().decode(PodcastLibrary.self, from: JSONEncoder().encode(library))
        XCTAssertEqual(decoded, library)
        var again = decoded
        XCTAssertTrue(again.merge(show).isEmpty, "a saved mark must not make the newest episode new again")
        XCTAssertEqual(again.unheardCount, 0)
    }

    // MARK: Progress

    func testResumeAndFinish() {
        var library = PodcastLibrary()
        XCTAssertEqual(library.resumePosition("a"), 0)
        library.record("a", position: 125, duration: 600)
        XCTAssertEqual(library.resumePosition("a"), 125)
        XCTAssertEqual(library.progress["a"]?.fraction ?? 0, 125.0 / 600, accuracy: 0.0001)
        // Within the last 15 seconds counts as heard, and starts over.
        library.record("a", position: 590, duration: 600)
        XCTAssertEqual(library.progress["a"]?.finished, true)
        XCTAssertEqual(library.resumePosition("a"), 0)
        library.record("b", position: .nan, duration: 600)
        XCTAssertNil(library.progress["b"])
    }

    func testSkipStaysInsideTheEpisode() {
        XCTAssertEqual(PodcastPlayback.skip(10, by: -PodcastPlayback.backSeconds, duration: 600), 0)
        XCTAssertEqual(PodcastPlayback.skip(100, by: PodcastPlayback.forwardSeconds, duration: 600), 130)
        XCTAssertEqual(PodcastPlayback.skip(590, by: 30, duration: 600), 600)
        XCTAssertEqual(PodcastPlayback.skip(590, by: 30, duration: 0), 620)
    }

    func testText() {
        XCTAssertEqual(PodcastPlayback.clock(65), "1:05")
        XCTAssertEqual(PodcastPlayback.clock(3602), "1:00:02")
        XCTAssertEqual(PodcastPlayback.durationText(3602), "1 小时")
        XCTAssertEqual(PodcastPlayback.durationText(3900), "1 小时 5 分钟")
        XCTAssertEqual(PodcastPlayback.durationText(2700), "45 分钟")
        XCTAssertEqual(PodcastPlayback.durationText(30), "不到 1 分钟")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let date = Xiaoyuzhou.date("2024-10-13T15:31:57.767Z")
        XCTAssertEqual(PodcastPlayback.dateText(date, now: date!, calendar: calendar), "10月13日")
        XCTAssertEqual(PodcastPlayback.dateText(date, now: date!.addingTimeInterval(400 * 86400), calendar: calendar),
                       "2024年10月13日")
    }

    // MARK: Catalog

    func testTheWidgetIsInTheLibraryAndChecksOnlyWhilePlaced() {
        let entry = WidgetCatalog.entry(.podcast)
        XCTAssertEqual(entry?.name, "播客")
        XCTAssertEqual(WidgetCatalog.configurableKeys(.podcast), ["notify"])
        XCTAssertEqual(PodcastWatch.plan([]), PodcastWatch.Plan(active: false, notify: false))
        var widget = WidgetCatalog.make(.podcast)!
        XCTAssertEqual(PodcastWatch.plan([widget]), PodcastWatch.Plan(active: true, notify: true))
        widget.config.set("notify", .bool(false))
        XCTAssertEqual(PodcastWatch.plan([widget, WidgetCatalog.make(.clock)!]),
                       PodcastWatch.Plan(active: true, notify: false))
    }

    func testSearchFindsIt() {
        for query in ["播客", "boke", "bk", "podcast", "小宇宙", "xiaoyuzhou"] {
            XCTAssertTrue(WidgetSearch.matches(query, names: ["播客"], kind: "podcast"), query)
        }
    }
}

/// 书签: reading a page's preview.
final class LinkPreviewTests: XCTestCase {
    private let page = URL(string: "https://example.com/articles/one")!

    func testOpenGraphWins() throws {
        let html = """
        <html><head><title>Plain title</title>
        <meta property="og:title" content="Open &amp; Graph">
        <meta name='description' content='Plain summary'>
        <meta content="OG summary" property="og:description" />
        <meta property="og:image" content="/img/cover.png">
        <link rel="shortcut icon" href="//cdn.example.com/fav.png">
        </head><body>…</body></html>
        """
        let preview = try XCTUnwrap(LinkPreview.parse(html, page: page))
        XCTAssertEqual(preview.title, "Open & Graph")
        XCTAssertEqual(preview.summary, "OG summary")
        XCTAssertEqual(preview.image, "https://example.com/img/cover.png")
        XCTAssertEqual(preview.icon, "https://cdn.example.com/fav.png")
        XCTAssertEqual(preview.url, page.absoluteString)
        XCTAssertFalse(preview.failed)
        XCTAssertTrue(preview.hasContent)
    }

    func testFallsBackToTitleAndDescription() throws {
        let html = "<HTML><HEAD><TITLE>\n  知乎 - 有问题，就会有答案 \n</TITLE><meta name=\"description\" content=\"中文&#26412;&#x5730;摘要\"></HEAD></HTML>"
        let preview = try XCTUnwrap(LinkPreview.parse(html, page: page))
        XCTAssertEqual(preview.title, "知乎 - 有问题，就会有答案")
        XCTAssertEqual(preview.summary, "中文本地摘要")
        XCTAssertNil(preview.image)
        XCTAssertEqual(preview.icon, "https://example.com/favicon.ico")
    }

    func testTheXiaoyuzhouShowPage() throws {
        let show = URL(string: "https://www.xiaoyuzhoufm.com/podcast/670bdb14db2cf82757e88a43")!
        let preview = try XCTUnwrap(LinkPreview.parse(XiaoyuzhouFixtures.podcastPage, page: show))
        XCTAssertEqual(preview.title, "冥想音疗馆")
    }

    func testAPageWithNothingIsNil() {
        XCTAssertNil(LinkPreview.parse("<html><head></head><body>hi</body></html>", page: page))
    }

    func testLongTextIsCut() throws {
        let long = String(repeating: "长", count: 500)
        let preview = try XCTUnwrap(LinkPreview.parse("<title>\(long)</title>", page: page))
        XCTAssertEqual(preview.title?.count, 120)
        XCTAssertTrue(preview.title?.hasSuffix("…") == true)
    }

    func testCharset() {
        XCTAssertEqual(LinkPreview.charset(contentType: "text/html; charset=GBK", head: ""), "gbk")
        XCTAssertEqual(LinkPreview.charset(contentType: nil, head: "<meta charset=\"gb2312\">"), "gb2312")
        XCTAssertNil(LinkPreview.charset(contentType: "text/html", head: "<html>"))
    }

    func testOnlyWebPagesAreFetchedAndFailuresWait() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(LinkPreview.needsFetch(page, stored: nil, now: now))
        XCTAssertFalse(LinkPreview.needsFetch(URL(string: "mailto:a@b.c")!, stored: nil, now: now))
        let done = LinkPreview(url: page.absoluteString, title: "x", fetched: now)
        XCTAssertFalse(LinkPreview.needsFetch(page, stored: done, now: now.addingTimeInterval(86400 * 30)))
        let failed = LinkPreview.failure(page, now: now)
        XCTAssertFalse(LinkPreview.needsFetch(page, stored: failed, now: now.addingTimeInterval(60)))
        XCTAssertTrue(LinkPreview.needsFetch(page, stored: failed, now: now.addingTimeInterval(LinkPreview.retryAfter)))
    }

    func testStoredInTheConfigAndPrunedWithTheLinks() {
        var config = WidgetConfig(["links": .list([.string("示例 https://example.com/articles/one"),
                                                   .string("https://other.example.org")])])
        XCTAssertTrue(LinkPreview.stored(config).isEmpty, "an old save has no previews")
        let one = LinkPreview(url: "https://example.com/articles/one", title: "一", summary: "摘要",
                              fetched: Date(timeIntervalSince1970: 1_800_000_000))
        let gone = LinkPreview(url: "https://removed.example.net", title: "旧")
        LinkPreview.store([one, gone], in: &config)
        let stored = LinkPreview.stored(config)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored["https://example.com/articles/one"], one)
        // Dropping the link drops its preview.
        config.set("links", .list([.string("https://other.example.org")]))
        LinkPreview.store([], in: &config)
        XCTAssertNil(config[LinkPreview.configKey])
    }

    func testPreviewsAreNotAnOption() {
        XCTAssertFalse(WidgetCatalog.configurableKeys(.bookmarks).contains(LinkPreview.configKey))
    }

    func testDisplayTitle() {
        let named = Bookmark(parsing: "我的 https://example.com/articles/one")!
        let bare = Bookmark(parsing: "https://example.com/articles/one")!
        let preview = LinkPreview(url: bare.url.absoluteString, title: "页面标题")
        XCTAssertTrue(named.hasOwnTitle)
        XCTAssertFalse(bare.hasOwnTitle)
        XCTAssertEqual(named.displayTitle(preview), "我的")
        XCTAssertEqual(bare.displayTitle(preview), "页面标题")
        XCTAssertEqual(bare.displayTitle(LinkPreview.failure(bare.url)), "example.com")
        XCTAssertEqual(bare.displayTitle(nil), "example.com")
    }

    func testXiaoyuzhouBookmarks() {
        XCTAssertEqual(Bookmark(parsing: "https://www.xiaoyuzhoufm.com/episode/670be7eedb2cf82757ebea6a")?.xiaoyuzhou,
                       .episode("670be7eedb2cf82757ebea6a"))
        XCTAssertNil(Bookmark(parsing: "https://www.bilibili.com")?.xiaoyuzhou)
    }
}
