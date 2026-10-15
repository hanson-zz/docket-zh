import XCTest

/// 单集简介里的时间轴读成章节，播放时在进度条下面跟着走。
final class PodcastChaptersTests: XCTestCase {

    func testPlainTimeline() {
        let text = """
        本期嘉宾聊了很多。
        00:00 开场
        03:12 聊聊 AI 编程
        1:02:30 听众来信
        """
        let chapters = PodcastChapters.parse(text)
        XCTAssertEqual(chapters.map(\.start), [0, 192, 3750])
        XCTAssertEqual(chapters.map(\.title), ["开场", "聊聊 AI 编程", "听众来信"])
    }

    func testCommonDecorations() {
        let text = """
        (00:30) 括号
        【05:00】方括号
        - 10:00 - 破折号
        1. 15:00：带序号
        ▶ 20:00 | 竖线
        """
        let chapters = PodcastChapters.parse(text)
        XCTAssertEqual(chapters.map(\.start), [30, 300, 600, 900, 1200])
        XCTAssertEqual(chapters.map(\.title), ["括号", "方括号", "破折号", "带序号", "竖线"])
    }

    func testHTMLShownotes() {
        let html = "<p>本期时间轴</p><p>00:00&nbsp;开场</p><p><span>12:30</span> 聊 AI &amp; 未来</p><br/>45:00 结尾"
        let chapters = PodcastChapters.parse(html)
        XCTAssertEqual(chapters.map(\.start), [0, 750, 2700])
        XCTAssertEqual(chapters[1].title, "聊 AI & 未来")
    }

    func testOneMentionIsNotATimeline() {
        XCTAssertTrue(PodcastChapters.parse("在 5:00 左右我们提到了一本书").isEmpty)
        XCTAssertTrue(PodcastChapters.parse("05:00 只有一行").isEmpty)
        XCTAssertTrue(PodcastChapters.parse("").isEmpty)
    }

    func testDropsBadTimesAndPastTheEnd() {
        XCTAssertNil(PodcastChapters.seconds("3:75"))
        XCTAssertEqual(PodcastChapters.seconds("1:00:00"), 3600)
        let text = "00:00 开场\n10:00 中段\n2:00:00 写错了的时间"
        XCTAssertEqual(PodcastChapters.parse(text, duration: 1800).map(\.start), [0, 600])
    }

    func testSortedAndDeduplicated() {
        let text = "10:00 后\n00:00 前\n10:00 重复"
        XCTAssertEqual(PodcastChapters.parse(text).map(\.title), ["前", "后"])
    }

    func testCurrentChapterFollowsPosition() {
        let chapters = [PodcastChapter(start: 60, title: "一"), PodcastChapter(start: 300, title: "二"),
                        PodcastChapter(start: 900, title: "三")]
        XCTAssertNil(PodcastChapters.currentIndex(chapters, at: 10), "第一章开始之前")
        XCTAssertEqual(PodcastChapters.currentIndex(chapters, at: 60), 0)
        XCTAssertEqual(PodcastChapters.currentIndex(chapters, at: 299), 0)
        XCTAssertEqual(PodcastChapters.current(chapters, at: 300)?.title, "二")
        XCTAssertEqual(PodcastChapters.current(chapters, at: 5000)?.title, "三")
        XCTAssertNil(PodcastChapters.currentIndex(chapters, at: .nan))
    }

    func testLongTitlesAreTrimmed() {
        let long = String(repeating: "长", count: 100)
        let chapters = PodcastChapters.parse("00:00 \(long)\n01:00 短")
        XCTAssertEqual(chapters[0].title.count, PodcastChapters.maxTitleLength + 1)
    }

    func testOldSavedEpisodesStillDecode() throws {
        let json = #"{"id":"e1","title":"旧单集","duration":60}"#
        let episode = try JSONDecoder().decode(PodcastEpisode.self, from: Data(json.utf8))
        XCTAssertNil(episode.chapters)
    }

    func testEpisodePageDescriptionBecomesChapters() {
        let data = #"{"props":{"pageProps":{"episode":{"eid":"e1","pid":"p1","title":"一集","duration":1800,"description":"00:00 开场\n10:00 正题","podcast":{"pid":"p1","title":"节目"}}}}}"#
        let html = "<script id=\"__NEXT_DATA__\" type=\"application/json\">\(data)</script>"
        let parsed = Xiaoyuzhou.episode(fromPage: html)
        XCTAssertEqual(parsed?.episode.chapters?.map(\.title), ["开场", "正题"])
    }
}
