import XCTest

/// 播客面板 2.0：封面主色、背景渐变、单集状态与筛选、列表折叠、日期标注、短名、小熊猫。
final class PodcastPlayerLookTests: XCTestCase {

    // MARK: 封面主色

    func testAverageSkipsBlackAndWhite() throws {
        let samples = [ColorCode(red: 0, green: 0, blue: 0), ColorCode(red: 1, green: 1, blue: 1),
                       ColorCode(red: 0.8, green: 0.2, blue: 0.2), ColorCode(red: 0.6, green: 0.2, blue: 0.2)]
        let average = try XCTUnwrap(PodcastCoverColor.average(samples))
        XCTAssertEqual(average.red, 0.7, accuracy: 0.001)
        XCTAssertEqual(average.green, 0.2, accuracy: 0.001)
        XCTAssertNil(PodcastCoverColor.average([ColorCode(red: 0, green: 0, blue: 0)]))
        XCTAssertNil(PodcastCoverColor.average([]))
    }

    func testDominantPicksTheHueWithTheMostColourNotTheMean() throws {
        // 一半红一半青：平均是灰，主色应该是其中一个，不是灰。
        let red = ColorCode(red: 0.9, green: 0.1, blue: 0.1)
        let cyan = ColorCode(red: 0.1, green: 0.6, blue: 0.6)
        let samples = Array(repeating: red, count: 6) + Array(repeating: cyan, count: 4)
        let dominant = try XCTUnwrap(PodcastCoverColor.dominant(samples))
        let (hue, saturation, _) = PodcastArtTint.hsv(dominant)
        XCTAssertEqual(hue, 0, accuracy: 0.02, "红色的点多、颜色也更足")
        XCTAssertGreaterThan(saturation, 0.5)
    }

    func testDominantOfAGreyCoverIsNil() {
        let greys = (0..<16).map { i in
            let v = 0.2 + Double(i) * 0.04
            return ColorCode(red: v, green: v, blue: v + 0.01)
        }
        XCTAssertNil(PodcastCoverColor.dominant(greys))
        XCTAssertNil(PodcastCoverColor.dominant([]))
    }

    // MARK: 背景渐变

    func testBackdropIsNilWithoutColour() {
        XCTAssertNil(PodcastCoverColor.backdrop(nil, dark: false))
        XCTAssertNil(PodcastCoverColor.backdrop(ColorCode(red: 0.5, green: 0.5, blue: 0.5), dark: true))
    }

    /// 扫一圈色相和饱和度：浅色外观下渐变始终很浅（浅底），深色外观下始终很暗，
    /// 饱和度和透明度都不超过上限。
    func testBackdropStaysLightInLightModeAndDarkInDarkMode() throws {
        for hueStep in 0..<24 {
            for saturation in [0.2, 0.5, 0.8, 1.0] {
                let colour = PodcastArtTint.rgb(Double(hueStep) / 24, saturation, 0.8)
                let light = try XCTUnwrap(PodcastCoverColor.backdrop(colour, dark: false))
                let dark = try XCTUnwrap(PodcastCoverColor.backdrop(colour, dark: true))
                XCTAssertGreaterThan(PodcastCoverColor.luminance(light.top), 0.55)
                XCTAssertGreaterThan(PodcastCoverColor.luminance(light.bottom), 0.5)
                XCTAssertLessThan(PodcastCoverColor.luminance(dark.top), 0.08)
                XCTAssertLessThan(PodcastCoverColor.luminance(dark.bottom), 0.03)
                XCTAssertLessThanOrEqual(PodcastArtTint.hsv(light.top).1, PodcastCoverColor.lightSaturationCap + 0.001)
                XCTAssertLessThanOrEqual(PodcastArtTint.hsv(dark.top).1, PodcastCoverColor.darkSaturationCap + 0.001)
                XCTAssertLessThanOrEqual(light.opacity, 0.6)
                XCTAssertLessThanOrEqual(dark.opacity, 0.6)
            }
        }
    }

    func testBlueIsDampedMoreThanRed() throws {
        let blue = try XCTUnwrap(PodcastCoverColor.backdrop(ColorCode(red: 0.1, green: 0.4, blue: 0.95), dark: true))
        let red = try XCTUnwrap(PodcastCoverColor.backdrop(ColorCode(red: 0.95, green: 0.1, blue: 0.1), dark: true))
        XCTAssertLessThan(PodcastArtTint.hsv(blue.top).1, PodcastArtTint.hsv(red.top).1)
    }

    // MARK: 单集状态

    func testStatusFromState() {
        XCTAssertEqual(PodcastEpisodeStatus.of(.new, isPlaying: false), .unheard)
        XCTAssertEqual(PodcastEpisodeStatus.of(.unplayed, isPlaying: false), .unheard)
        XCTAssertEqual(PodcastEpisodeStatus.of(.inProgress(0.326), isPlaying: false), .listening(percent: 32))
        XCTAssertEqual(PodcastEpisodeStatus.of(.finished, isPlaying: false), .finished)
        XCTAssertEqual(PodcastEpisodeStatus.of(.finished, isPlaying: true), .playing)
        XCTAssertEqual(PodcastEpisodeStatus.of(.unplayed, isPlaying: false, livePosition: 300, liveDuration: 600),
                       .listening(percent: 50))
        XCTAssertEqual(PodcastEpisodeStatus.of(.unplayed, isPlaying: false, livePosition: 595, liveDuration: 600),
                       .finished)
    }

    func testPercentStaysBetweenOneAndNinetyNine() {
        XCTAssertEqual(PodcastEpisodeStatus.percent(0.001), 1)
        XCTAssertEqual(PodcastEpisodeStatus.percent(0.999), 99)
        XCTAssertEqual(PodcastEpisodeStatus.percent(.nan), 1)
    }

    func testStatusLabels() {
        XCTAssertEqual(PodcastEpisodeStatus.playing.label, "正在播放")
        XCTAssertEqual(PodcastEpisodeStatus.unheard.label, "未听")
        XCTAssertEqual(PodcastEpisodeStatus.listening(percent: 40).label, "收听中 40%")
        XCTAssertEqual(PodcastEpisodeStatus.finished.label, "已听完")
    }

    // MARK: 筛选

    func testFilter() {
        let statuses: [PodcastEpisodeStatus] = [.playing, .unheard, .listening(percent: 10), .finished, .unheard]
        let indices = Array(statuses.indices)
        XCTAssertEqual(PodcastEpisodeFilter.all.apply(indices) { statuses[$0] }, [0, 1, 2, 3, 4])
        XCTAssertEqual(PodcastEpisodeFilter.unheard.apply(indices) { statuses[$0] }, [1, 4])
        XCTAssertEqual(PodcastEpisodeFilter.listening.apply(indices) { statuses[$0] }, [0, 2])
        XCTAssertEqual(PodcastEpisodeFilter.allCases.map(\.title), ["全部", "未听", "收听中"])
    }

    func testFilterOnALibrary() {
        func episode(_ id: String, _ offset: TimeInterval) -> PodcastEpisode {
            PodcastEpisode(id: id, title: id, pubDate: Date(timeIntervalSince1970: 1_700_000_000 + offset),
                           duration: 600, audioURL: URL(string: "https://example.com/\(id).m4a"))
        }
        var library = PodcastLibrary()
        library.subscribe(PodcastShow(id: "show", title: "节目",
                                      episodes: [episode("c", 200), episode("b", 100), episode("a", 0)]))
        library.record("b", position: 120, duration: 600)
        library.markFinished("a", duration: 600)
        let episodes = library.show("show")?.episodes ?? []
        let status = { (e: PodcastEpisode) in
            PodcastEpisodeStatus.of(library.state(of: e, in: "show"), isPlaying: false)
        }
        XCTAssertEqual(PodcastEpisodeFilter.unheard.apply(episodes, status: status).map(\.id), ["c"])
        XCTAssertEqual(PodcastEpisodeFilter.listening.apply(episodes, status: status).map(\.id), ["b"])
        XCTAssertEqual(status(episodes[1]), .listening(percent: 20))
    }

    // MARK: 折叠

    func testListing() {
        XCTAssertEqual(PodcastEpisodeListing.visibleCount(total: 10, expanded: false), 3)
        XCTAssertEqual(PodcastEpisodeListing.visibleCount(total: 10, expanded: true), 10)
        XCTAssertEqual(PodcastEpisodeListing.visibleCount(total: 2, expanded: false), 2)
        XCTAssertEqual(PodcastEpisodeListing.hiddenCount(total: 10, expanded: false), 7)
        XCTAssertEqual(PodcastEpisodeListing.hiddenCount(total: 10, expanded: true), 0)
        XCTAssertFalse(PodcastEpisodeListing.needsToggle(total: 3))
        XCTAssertTrue(PodcastEpisodeListing.needsToggle(total: 4))
        XCTAssertEqual(PodcastEpisodeListing.visibleCount(total: -1, expanded: false), 0)
    }

    // MARK: 日期

    func testDateLabelsAreDistinct() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 22)))
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 9)))
        XCTAssertEqual(PodcastDateLabel.updated(date, now: now, calendar: calendar), "节目更新于 10月3日")
        XCTAssertEqual(PodcastDateLabel.published(date, now: now, calendar: calendar), "发布于 10月3日")
        XCTAssertEqual(PodcastDateLabel.updated(nil), "")
        XCTAssertEqual(PodcastDateLabel.published(nil), "")
    }

    // MARK: 短名

    func testShortName() {
        XCTAssertEqual(PodcastShowName.short("忽左忽右｜文化沙龙"), "忽左忽右")
        XCTAssertEqual(PodcastShowName.short("声东击西：一档聊天节目"), "声东击西")
        XCTAssertEqual(PodcastShowName.short("不合时宜"), "不合时宜")
        XCTAssertEqual(PodcastShowName.short("一个非常非常长的节目名字"), "一个非常…")
        XCTAssertEqual(PodcastShowName.short("Hard Fork"), "Hard Fork")
        XCTAssertEqual(PodcastShowName.short("The Daily Show Podcast"), "The Daily…")
        XCTAssertEqual(PodcastShowName.short("｜开头就是分隔符"), "｜开头就…")
        for title in ["忽左忽右｜文化沙龙", "一个非常非常长的节目名字", "The Daily Show Podcast"] {
            XCTAssertLessThanOrEqual(PodcastShowName.width(PodcastShowName.short(title)), PodcastShowName.maxWidth)
        }
    }

    // MARK: 小熊猫

    func testPandaOnlyForEmptyStates() {
        XCTAssertEqual(PodcastPandaCue.empty(showCount: 0, playableCount: 0, loading: false), .idle)
        XCTAssertEqual(PodcastPandaCue.empty(showCount: 2, playableCount: 0, loading: false), .rest)
        XCTAssertNil(PodcastPandaCue.empty(showCount: 2, playableCount: 0, loading: true), "读单集时不画")
        XCTAssertNil(PodcastPandaCue.empty(showCount: 1, playableCount: 5, loading: false), "有内容（含播放中）不画")
    }

    func testFinishPulseIsShortAndDone() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let pulse = PodcastPandaCue.finishPulse(at: now)
        XCTAssertEqual(pulse.state, .done)
        XCTAssertEqual(pulse.until.timeIntervalSince(pulse.started), 2.4, accuracy: 0.001)
        XCTAssertTrue(pulse.isActive(at: now.addingTimeInterval(1)))
        XCTAssertFalse(pulse.isActive(at: now.addingTimeInterval(3)))
    }
}
