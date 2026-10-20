import XCTest

/// 卡片和面板共用的「当前显示来源」（`MusicDisplay`），和面板固定来源的样子。
final class MusicCardChoiceTests: XCTestCase {
    private typealias P = MusicSourceSwitch.Player
    private typealias B = MusicCardChoice.Browser

    /// 默认：没手点、没固定、谁开始播放就切到谁、浏览器上次没在放。
    private func pick(_ players: [P], browser: B? = nil, was: [MusicSource: Bool] = [:],
                      browserWas: Bool = false, current: MusicCardChoice.Pick? = nil,
                      manual: Bool = false, pinned: MusicSource? = nil,
                      auto: Bool = true) -> MusicCardChoice.Pick {
        MusicDisplay.pick(players: players, browser: browser, wasPlaying: was, browserWasPlaying: browserWas,
                          current: current, manual: manual, pinned: pinned, autoSwitch: auto)
    }

    // MARK: 固定的来源在播

    func testPinnedSourcePlayingWinsForCardAndPanel() {
        let players = [P(source: .spotify, hasTrack: true, isPlaying: true),
                       P(source: .appleMusic, hasTrack: true, isPlaying: true)]
        XCTAssertEqual(pick(players, was: [.spotify: true, .appleMusic: true], current: .native(.spotify),
                            pinned: .appleMusic, auto: false), .native(.appleMusic))
    }

    func testPinnedStartingAgainTakesOverAManualChoice() {
        let players = [P(source: .spotify, hasTrack: true, isPlaying: true),
                       P(source: .appleMusic, hasTrack: true, isPlaying: true)]
        XCTAssertEqual(pick(players, was: [.spotify: true, .appleMusic: true], current: .native(.spotify),
                            manual: true, pinned: .appleMusic, auto: false), .native(.spotify),
                       "手点的先留着")
        XCTAssertEqual(pick(players, was: [.spotify: true, .appleMusic: false], current: .native(.spotify),
                            manual: true, pinned: .appleMusic, auto: false), .native(.appleMusic),
                       "固定的重新开始放就回到它")
    }

    func testPinIsIgnoredWhileAutoSwitchIsOn() {
        let players = [P(source: .spotify, hasTrack: true, isPlaying: true),
                       P(source: .appleMusic, hasTrack: true, isPlaying: true)]
        XCTAssertEqual(pick(players, was: [.spotify: true, .appleMusic: true], current: .native(.spotify),
                            pinned: .appleMusic, auto: true), .native(.spotify))
    }

    // MARK: 固定的来源没在播

    func testPinnedPausedShowsTheOneThatPlays() {
        let players = [P(source: .spotify, hasTrack: true, isPlaying: true),
                       P(source: .appleMusic, hasTrack: true, isPlaying: false)]
        let shown = pick(players, current: .native(.appleMusic), pinned: .appleMusic, auto: false)
        XCTAssertEqual(shown, .native(.spotify))
        XCTAssertEqual(MusicDisplay.pinIdle(pinned: .appleMusic, shown: shown, players: players, browser: nil),
                       .appleMusic, "面板写「固定的 Apple 音乐没在播」")
    }

    func testPinnedNotOpenShowsTheOneThatPlays() {
        let players = [P(source: .qqmusic, hasTrack: true, isPlaying: true)]
        let shown = pick(players, pinned: .appleMusic, auto: false)
        XCTAssertEqual(shown, .native(.qqmusic))
        XCTAssertNil(MusicDisplay.pinnedClosed(pinned: .appleMusic, shown: shown, players: players),
                     "有来源在放时不显示「没开」")
    }

    func testPinnedNotPlayingDoesNotFlipBetweenTwoPlaying() {
        let players = [P(source: .spotify, hasTrack: true, isPlaying: true),
                       P(source: .netease, hasTrack: true, isPlaying: true)]
        XCTAssertEqual(pick(players, was: [.spotify: true, .netease: false], current: .native(.spotify),
                            pinned: .appleMusic, auto: false), .native(.spotify),
                       "固定着时别的来源开始放也不跳，留在正在显示的")
        XCTAssertEqual(pick(players, was: [.spotify: true, .netease: true], current: .native(.netease),
                            pinned: .appleMusic, auto: false), .native(.netease))
    }

    func testPinIdleOnlyWhenSomethingElseIsShownAndPlaying() {
        let playing = [P(source: .spotify, hasTrack: true, isPlaying: true)]
        XCTAssertNil(MusicDisplay.pinIdle(pinned: nil, shown: .native(.spotify), players: playing, browser: nil))
        XCTAssertNil(MusicDisplay.pinIdle(pinned: .spotify, shown: .native(.spotify), players: playing, browser: nil),
                     "显示的就是固定的：「已固定」小标")
        let paused = [P(source: .spotify, hasTrack: true, isPlaying: false)]
        XCTAssertNil(MusicDisplay.pinIdle(pinned: .appleMusic, shown: .native(.spotify), players: paused, browser: nil))
        XCTAssertEqual(MusicDisplay.pinIdle(pinned: .appleMusic, shown: .browser, players: paused,
                                            browser: B(hasTrack: true, isPlaying: true)), .appleMusic)
    }

    // MARK: 手点

    func testManualChoiceIsSharedAndHoldsUntilSomethingElseStarts() {
        // 面板里点了暂停着的 Spotify，网易云一直在放：卡片和面板都显示 Spotify。
        let players = [P(source: .netease, hasTrack: true, isPlaying: true),
                       P(source: .spotify, hasTrack: true, isPlaying: false)]
        let was: [MusicSource: Bool] = [.netease: true, .spotify: false]
        XCTAssertEqual(pick(players, was: was, current: .native(.spotify), manual: true), .native(.spotify))
        XCTAssertTrue(MusicDisplay.keepsManual(players: players, browser: nil, wasPlaying: was,
                                               browserWasPlaying: false, current: .native(.spotify)))

        let started = [P(source: .netease, hasTrack: true, isPlaying: true),
                       P(source: .spotify, hasTrack: true, isPlaying: false),
                       P(source: .qqmusic, hasTrack: true, isPlaying: true)]
        XCTAssertEqual(pick(started, was: was, current: .native(.spotify), manual: true), .native(.qqmusic),
                       "别的来源开始放：手点不再算数")
        XCTAssertFalse(MusicDisplay.keepsManual(players: started, browser: nil, wasPlaying: was,
                                                browserWasPlaying: false, current: .native(.spotify)))
    }

    func testManualChoiceDropsWhenItCloses() {
        let players = [P(source: .netease, hasTrack: true, isPlaying: true)]
        XCTAssertEqual(pick(players, was: [.netease: true], current: .native(.spotify), manual: true),
                       .native(.netease))
        XCTAssertFalse(MusicDisplay.keepsManual(players: players, browser: nil, wasPlaying: [.netease: true],
                                                browserWasPlaying: false, current: .native(.spotify)))
    }

    func testOtherRowPlayKeepsThePin() {
        // 「其他开着的」点了 Spotify 播放：显示切到它（手点），固定还是 Apple 音乐。
        let players = [P(source: .spotify, hasTrack: true, isPlaying: true)]
        let shown = pick(players, was: [.spotify: false], current: .native(.spotify), manual: true,
                         pinned: .appleMusic, auto: false)
        XCTAssertEqual(shown, .native(.spotify))
        XCTAssertEqual(MusicDisplay.pinIdle(pinned: .appleMusic, shown: shown, players: players, browser: nil),
                       .appleMusic)
    }

    func testPausingTheShownSourceDoesNotJumpToThePin() {
        // 对显示中的 Spotify 按了暂停（算手点）：留在 Spotify，不跳回没在播的固定来源。
        let players = [P(source: .spotify, hasTrack: true, isPlaying: false),
                       P(source: .appleMusic, hasTrack: true, isPlaying: false)]
        XCTAssertEqual(pick(players, was: [.spotify: true], current: .native(.spotify), manual: true,
                            pinned: .appleMusic, auto: false), .native(.spotify))
        XCTAssertEqual(pick(players, was: [.spotify: true], current: .native(.spotify),
                            pinned: .appleMusic, auto: false), .native(.appleMusic),
                       "不是手点的：都没在播时回到固定的")
    }

    // MARK: 谁开始播放就切到谁

    func testWhoeverStartsPlayingWins() {
        let players = [P(source: .netease, hasTrack: true, isPlaying: true),
                       P(source: .spotify, hasTrack: true, isPlaying: true)]
        XCTAssertEqual(pick(players, was: [.netease: true, .spotify: false], current: .native(.netease)),
                       .native(.spotify))
    }

    func testCurrentAmongStartersStays() {
        let players = [P(source: .appleMusic, hasTrack: true, isPlaying: true),
                       P(source: .spotify, hasTrack: true, isPlaying: true)]
        XCTAssertEqual(pick(players, current: .native(.spotify)), .native(.spotify))
    }

    func testTwoPlayingDoNotFlipBackAndForth() {
        let players = [P(source: .spotify, hasTrack: true, isPlaying: true),
                       P(source: .appleMusic, hasTrack: true, isPlaying: true)]
        XCTAssertEqual(pick(players, was: [.spotify: true, .appleMusic: true], current: .native(.appleMusic)),
                       .native(.appleMusic))
        XCTAssertEqual(pick(players, was: [.spotify: true, .appleMusic: true], current: .native(.spotify)),
                       .native(.spotify))
    }

    func testFirstLookPicksThePlayingOne() {
        let players = [P(source: .appleMusic, hasTrack: true, isPlaying: false),
                       P(source: .qqmusic, hasTrack: true, isPlaying: true)]
        XCTAssertEqual(pick(players), .native(.qqmusic))
    }

    func testPausedShownSourceGivesWayToOneThatPlays() {
        let players = [P(source: .spotify, hasTrack: true, isPlaying: false),
                       P(source: .netease, hasTrack: true, isPlaying: true)]
        XCTAssertEqual(pick(players, was: [.netease: true], current: .native(.spotify)), .native(.netease),
                       "有来源在放时显示正在放的那个")
    }

    // MARK: 浏览器

    func testBrowserTabCountsButNativePlayersComeFirst() {
        let paused = [P(source: .appleMusic, hasTrack: true, isPlaying: false)]
        let tab = B(hasTrack: true, isPlaying: true)
        XCTAssertEqual(pick(paused, browser: tab, current: .native(.appleMusic)), .browser)
        XCTAssertTrue(MusicCardChoice.anyPlaying(players: paused, browser: tab), "浏览器标签页在播也算")

        let playing = [P(source: .spotify, hasTrack: true, isPlaying: true)]
        XCTAssertEqual(pick(playing, browser: tab, was: [.spotify: true], browserWas: true, current: .browser),
                       .native(.spotify), "播放器在放时浏览器让位")
    }

    func testBrowserNotAllowedIsIgnored() {
        XCTAssertFalse(MusicCardChoice.anyPlaying(players: [], browser: nil))
        XCTAssertEqual(pick([]), .none)
        XCTAssertEqual(MusicCardChoice.Pick.native(.spotify).source, .spotify)
        XCTAssertNil(MusicCardChoice.Pick.browser.source)
    }

    // MARK: 都没在播

    func testNothingPlayingHidesAndKeepsTheLastTrack() {
        let players = [P(source: .spotify, hasTrack: true, isPlaying: false),
                       P(source: .appleMusic, hasTrack: true, isPlaying: false)]
        XCTAssertFalse(MusicCardChoice.anyPlaying(players: players, browser: B(hasTrack: true, isPlaying: false)),
                       "全都没在播：「正在播放时显示」照旧隐藏")
        XCTAssertEqual(pick(players, current: .native(.spotify)), .native(.spotify), "刚才那首留着")
        XCTAssertEqual(pick(players), .native(.spotify), "没有就按偏好顺序第一个有曲目的")
    }

    func testNothingPlayingPinnedNotOpenSaysItIsClosed() {
        let players = [P(source: .spotify, hasTrack: true, isPlaying: false)]
        let shown = pick(players, current: .native(.spotify), pinned: .appleMusic, auto: false)
        XCTAssertEqual(shown, .native(.appleMusic), "固定的没开也还是它")
        XCTAssertEqual(MusicDisplay.pinnedClosed(pinned: .appleMusic, shown: shown, players: players), .appleMusic,
                       "面板大标题「Apple 音乐没开」")
        XCTAssertNil(MusicDisplay.pinIdle(pinned: .appleMusic, shown: shown, players: players, browser: nil))
        XCTAssertEqual(MusicPin.others(players: players, shown: shown.source), [.spotify], "「其他开着的」照旧")

        let open = [P(source: .appleMusic, hasTrack: true, isPlaying: false)]
        XCTAssertNil(MusicDisplay.pinnedClosed(pinned: .appleMusic, shown: .native(.appleMusic), players: open))
    }

    func testFallsBackWhenCurrentCloses() {
        let players = [P(source: .netease, hasTrack: false, isPlaying: false),
                       P(source: .appleMusic, hasTrack: true, isPlaying: false)]
        XCTAssertEqual(pick(players, current: .native(.spotify)), .native(.appleMusic))
        XCTAssertEqual(pick([P(source: .netease, hasTrack: false, isPlaying: false)]), .native(.netease),
                       "都没曲目：第一个开着的")
        XCTAssertEqual(pick([], browser: B(hasTrack: true, isPlaying: false), current: .browser), .browser)
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

    func testOthersListsOpenPlayersWithATrack() {
        let players = [P(source: .spotify, hasTrack: true, isPlaying: false),
                       P(source: .netease, hasTrack: true, isPlaying: false),
                       P(source: .qqmusic, hasTrack: false, isPlaying: false)]
        XCTAssertEqual(MusicPin.others(players: players, shown: .appleMusic), [.spotify, .netease])
        XCTAssertEqual(MusicPin.others(players: players, shown: .spotify), [.netease])
    }
}
