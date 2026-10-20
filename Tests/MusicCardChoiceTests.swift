import XCTest

/// 「正在播放」卡片显示哪一首，和面板固定来源的样子。
final class MusicCardChoiceTests: XCTestCase {
    private typealias P = MusicSourceSwitch.Player
    private typealias B = MusicCardChoice.Browser

    // MARK: 卡片

    func testCardShowsWhatIsPlayingEvenWhenThePanelIsPinnedElsewhere() {
        // 面板固定在 Apple 音乐（已暂停），Spotify 正在播：卡片显示 Spotify。
        let players = [P(source: .spotify, hasTrack: true, isPlaying: true),
                       P(source: .appleMusic, hasTrack: true, isPlaying: false)]
        XCTAssertEqual(MusicCardChoice.pick(players: players, current: .appleMusic, browser: nil, last: nil),
                       .native(.spotify))
        XCTAssertTrue(MusicCardChoice.anyPlaying(players: players, browser: nil), "卡片不因为固定而隐藏")
    }

    func testPinnedSourceNotOpenStillShowsTheOneThatPlays() {
        let players = [P(source: .qqmusic, hasTrack: true, isPlaying: true)]
        XCTAssertEqual(MusicCardChoice.pick(players: players, current: .appleMusic, browser: nil, last: nil),
                       .native(.qqmusic))
    }

    func testPanelSourceWinsWhenItIsPlayingToo() {
        let players = [P(source: .spotify, hasTrack: true, isPlaying: true),
                       P(source: .appleMusic, hasTrack: true, isPlaying: true)]
        XCTAssertEqual(MusicCardChoice.pick(players: players, current: .appleMusic, browser: nil, last: nil),
                       .native(.appleMusic))
    }

    func testTwoPlayingDoNotFlipBackAndForth() {
        let players = [P(source: .spotify, hasTrack: true, isPlaying: true),
                       P(source: .appleMusic, hasTrack: true, isPlaying: true)]
        XCTAssertEqual(MusicCardChoice.pick(players: players, current: .appleMusic, browser: nil,
                                            last: .native(.spotify)), .native(.spotify),
                       "上次显示的还在放就不换")
    }

    func testBrowserTabCountsButNativePlayersComeFirst() {
        let paused = [P(source: .appleMusic, hasTrack: true, isPlaying: false)]
        let tab = B(hasTrack: true, isPlaying: true)
        XCTAssertEqual(MusicCardChoice.pick(players: paused, current: .appleMusic, browser: tab, last: nil), .browser)
        XCTAssertTrue(MusicCardChoice.anyPlaying(players: paused, browser: tab), "浏览器标签页在播也算")

        let playing = [P(source: .spotify, hasTrack: true, isPlaying: true)]
        XCTAssertEqual(MusicCardChoice.pick(players: playing, current: nil, browser: tab, last: .browser),
                       .native(.spotify), "播放器在放时浏览器让位")
    }

    func testBrowserNotAllowedIsIgnored() {
        XCTAssertFalse(MusicCardChoice.anyPlaying(players: [], browser: nil))
        XCTAssertEqual(MusicCardChoice.pick(players: [], current: nil, browser: nil, last: nil), .none)
    }

    func testNothingPlayingHidesAndKeepsTheLastTrackForAlwaysShown() {
        let players = [P(source: .spotify, hasTrack: true, isPlaying: false),
                       P(source: .appleMusic, hasTrack: true, isPlaying: false)]
        XCTAssertFalse(MusicCardChoice.anyPlaying(players: players, browser: B(hasTrack: true, isPlaying: false)),
                       "全都没在播：「正在播放时显示」照旧隐藏")
        XCTAssertEqual(MusicCardChoice.pick(players: players, current: .appleMusic, browser: nil,
                                            last: .native(.spotify)), .native(.spotify),
                       "刚在卡片上暂停的那首留着，还能点回来")
        XCTAssertEqual(MusicCardChoice.pick(players: players, current: .appleMusic, browser: nil, last: nil),
                       .native(.appleMusic), "没有上次就跟面板的来源")
    }

    func testNothingPlayingFallsBackWhenTheLastOneIsGone() {
        let players = [P(source: .netease, hasTrack: false, isPlaying: false),
                       P(source: .appleMusic, hasTrack: true, isPlaying: false)]
        XCTAssertEqual(MusicCardChoice.pick(players: players, current: .netease, browser: nil,
                                            last: .native(.spotify)), .native(.appleMusic))
        XCTAssertEqual(MusicCardChoice.pick(players: [], current: .appleMusic,
                                            browser: B(hasTrack: true, isPlaying: false), last: .browser), .browser)
        XCTAssertEqual(MusicCardChoice.Pick.native(.spotify).source, .spotify)
        XCTAssertNil(MusicCardChoice.Pick.browser.source)
    }

    // MARK: 固定

    func testPinnedOnlyWhenAutoSwitchIsOff() {
        var config = WidgetConfig()
        config.set(MusicSourceSwitch.pinnedKey, .string("appleMusic"))
        XCTAssertNil(MusicPin.pinned(config), "自动切换开着时不算固定")
        config.set(MusicSourceSwitch.autoKey, .bool(false))
        XCTAssertEqual(MusicPin.pinned(config), .appleMusic)
    }

    func testUnpinGoesBackToAutoSwitchAndClearsThePin() {
        var config = WidgetConfig()
        config.set(MusicSourceSwitch.autoKey, .bool(false))
        config.set(MusicSourceSwitch.pinnedKey, .string("appleMusic"))
        MusicPin.unpin(&config)
        XCTAssertTrue(MusicSourceSwitch.autoSwitch(config))
        XCTAssertNil(MusicSourceSwitch.pinned(config))
        XCTAssertNil(MusicPin.pinned(config))
    }

    func testOthersListOnlyPlayingWhilePinned() {
        let players = [P(source: .spotify, hasTrack: true, isPlaying: true),
                       P(source: .netease, hasTrack: true, isPlaying: false),
                       P(source: .qqmusic, hasTrack: false, isPlaying: false)]
        XCTAssertEqual(MusicPin.others(players: players, shown: .appleMusic, pinned: true), [.spotify],
                       "固定着：「其他正在播的」")
        XCTAssertEqual(MusicPin.others(players: players, shown: .appleMusic, pinned: false), [.spotify, .netease],
                       "没固定：「其他开着的」照旧列有曲目的")
        XCTAssertEqual(MusicPin.others(players: players, shown: .spotify, pinned: true), [])
    }
}
