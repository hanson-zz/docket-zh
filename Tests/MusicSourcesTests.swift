import XCTest

/// 「正在播放」面板改版：来源、切换规则、音量走哪一路、接下来、刚才听过。
final class MusicSourcesTests: XCTestCase {
    private typealias P = MusicSourceSwitch.Player

    // MARK: 来源

    func testQQMusicIsANowPlayingSourceLikeNetease() {
        XCTAssertEqual(MusicSource.qqmusic.bundleID, "com.tencent.QQMusicMac")
        XCTAssertTrue(MusicSource.qqmusic.readsNowPlaying)
        XCTAssertFalse(MusicSource.qqmusic.canSeek, "QQ 音乐进度只读")
        XCTAssertFalse(MusicSource.qqmusic.hasShuffleAndRepeat)
        XCTAssertFalse(MusicSource.qqmusic.hasFavorite)
        XCTAssertEqual(MusicSource(bundleID: "com.tencent.QQMusicMac"), .qqmusic)
    }

    func testCapabilitiesPerPlayer() {
        XCTAssertTrue(MusicSource.appleMusic.hasFavorite)
        XCTAssertTrue(MusicSource.appleMusic.hasUpNext)
        XCTAssertTrue(MusicSource.appleMusic.hasRepeatOne)
        XCTAssertFalse(MusicSource.spotify.hasFavorite, "Spotify 没有喜欢")
        XCTAssertFalse(MusicSource.spotify.hasUpNext, "Spotify 没有队列")
        XCTAssertTrue(MusicSource.spotify.keepsRecent)
        XCTAssertFalse(MusicSource.spotify.hasRepeatOne)
        XCTAssertTrue(MusicSource.spotify.canSeek)
        XCTAssertFalse(MusicSource.netease.canSeek)
    }

    func testEnabledSourcesReadTheConfigAndDefaultOn() {
        XCTAssertEqual(MusicSource.enabled(in: WidgetConfig()),
                       [.spotify, .appleMusic, .netease, .qqmusic, .xiaoyuzhou],
                       "旧配置没有 qqmusic 键，默认开")
        var config = WidgetConfig()
        config.set("qqmusic", .bool(false))
        config.set("spotify", .bool(false))
        XCTAssertEqual(MusicSource.enabled(in: config), [.appleMusic, .netease, .xiaoyuzhou])
    }

    func testCatalogOffersTheNewKeys() {
        let keys = WidgetCatalog.configurableKeys(.music)
        for key in ["qqmusic", MusicSourceSwitch.autoKey, MusicSourceSwitch.pinnedKey] {
            XCTAssertTrue(keys.contains(key), key)
        }
        XCTAssertTrue(MusicSourceSwitch.autoSwitch(WidgetConfig()), "默认谁开始播放就切到谁")
        XCTAssertNil(MusicSourceSwitch.pinned(WidgetConfig()))
        XCTAssertFalse(WidgetCatalog.applies(MusicSourceSwitch.pinnedKey, to: WidgetConfig(), kind: .music),
                       "固定来源在面板里选，设置页不列")
    }

    // MARK: 切换规则

    func testWhoeverStartsPlayingWins() {
        let players = [P(source: .netease, hasTrack: true, isPlaying: true),
                       P(source: .spotify, hasTrack: true, isPlaying: true)]
        let chosen = MusicSourceSwitch.choose(players: players,
                                              wasPlaying: [.netease: true, .spotify: false],
                                              current: .netease, autoSwitch: true, pinned: nil)
        XCTAssertEqual(chosen, .spotify, "Spotify 刚开始放，切过去")
    }

    func testAPausedChoiceIsNotStolenByOneAlreadyPlaying() {
        // 用户在面板里选了暂停着的 Spotify，网易云一直在放：不切走。
        let players = [P(source: .netease, hasTrack: true, isPlaying: true),
                       P(source: .spotify, hasTrack: true, isPlaying: false)]
        let chosen = MusicSourceSwitch.choose(players: players,
                                              wasPlaying: [.netease: true, .spotify: false],
                                              current: .spotify, autoSwitch: true, pinned: nil)
        XCTAssertEqual(chosen, .spotify)
    }

    func testCurrentAmongStartersStays() {
        let players = [P(source: .appleMusic, hasTrack: true, isPlaying: true),
                       P(source: .spotify, hasTrack: true, isPlaying: true)]
        let chosen = MusicSourceSwitch.choose(players: players, wasPlaying: [:],
                                              current: .spotify, autoSwitch: true, pinned: nil)
        XCTAssertEqual(chosen, .spotify)
    }

    func testFirstLookPicksThePlayingOne() {
        let players = [P(source: .appleMusic, hasTrack: true, isPlaying: false),
                       P(source: .qqmusic, hasTrack: true, isPlaying: true)]
        XCTAssertEqual(MusicSourceSwitch.choose(players: players, wasPlaying: [:], current: nil,
                                                autoSwitch: true, pinned: nil), .qqmusic)
    }

    func testFallsBackWhenCurrentCloses() {
        let players = [P(source: .netease, hasTrack: false, isPlaying: false),
                       P(source: .appleMusic, hasTrack: true, isPlaying: false)]
        XCTAssertEqual(MusicSourceSwitch.choose(players: players,
                                                wasPlaying: [.spotify: false, .appleMusic: false],
                                                current: .spotify, autoSwitch: true, pinned: nil),
                       .appleMusic, "Spotify 关了：退到有曲目的那个")
        XCTAssertEqual(MusicSourceSwitch.choose(players: [P(source: .netease, hasTrack: false, isPlaying: false)],
                                                wasPlaying: [:], current: nil, autoSwitch: true, pinned: nil),
                       .netease, "都没曲目：第一个开着的")
        XCTAssertNil(MusicSourceSwitch.choose(players: [], wasPlaying: [:], current: nil,
                                              autoSwitch: true, pinned: nil))
    }

    func testPinnedSourceHoldsWhenSwitchingIsOff() {
        let players = [P(source: .netease, hasTrack: true, isPlaying: true),
                       P(source: .spotify, hasTrack: true, isPlaying: false)]
        XCTAssertEqual(MusicSourceSwitch.choose(players: players, wasPlaying: [.netease: false],
                                                current: .spotify, autoSwitch: false, pinned: .spotify),
                       .spotify, "网易云开始放也不切")
        XCTAssertEqual(MusicSourceSwitch.choose(players: players, wasPlaying: [:],
                                                current: .netease, autoSwitch: false, pinned: .qqmusic),
                       .qqmusic, "固定的来源没开也还是它，面板显示打开它")
    }

    func testNoPinYetKeepsCurrentWhenOff() {
        let players = [P(source: .netease, hasTrack: true, isPlaying: false),
                       P(source: .spotify, hasTrack: true, isPlaying: true)]
        XCTAssertEqual(MusicSourceSwitch.choose(players: players, wasPlaying: [.spotify: false],
                                                current: .netease, autoSwitch: false, pinned: nil),
                       .netease)
    }

    // MARK: 循环

    func testRepeatCycles() {
        XCTAssertEqual(MusicRepeat.off.next(allowsOne: true), .all)
        XCTAssertEqual(MusicRepeat.all.next(allowsOne: true), .one)
        XCTAssertEqual(MusicRepeat.one.next(allowsOne: true), .off)
        XCTAssertEqual(MusicRepeat.all.next(allowsOne: false), .off, "Spotify 只有开关")
        XCTAssertEqual(MusicRepeat(appleScript: "all"), .all)
        XCTAssertEqual(MusicRepeat(appleScript: " one\n"), .one)
        XCTAssertEqual(MusicRepeat(appleScript: "???"), .off)
    }

    // MARK: 音量

    func testVolumeRoute() {
        XCTAssertEqual(MusicVolumeRoute.route(for: .appleMusic, recordingGranted: false), .player)
        XCTAssertEqual(MusicVolumeRoute.route(for: .spotify, recordingGranted: false), .player)
        XCTAssertEqual(MusicVolumeRoute.route(for: .netease, recordingGranted: true), .appVolume)
        XCTAssertEqual(MusicVolumeRoute.route(for: .qqmusic, recordingGranted: true), .appVolume)
        XCTAssertEqual(MusicVolumeRoute.route(for: .netease, recordingGranted: false), .none,
                       "没有录音权限不显示音量条")
        XCTAssertEqual(MusicVolumeRoute.route(for: .qqmusic, recordingGranted: false), .none)
        XCTAssertEqual(MusicVolumeRoute.route(for: .xiaoyuzhou, recordingGranted: true), .none)
    }

    // MARK: 接下来

    func testUpNextFollowsThePlaylist() {
        XCTAssertEqual(MusicUpNext.indices(current: 3, count: 20, wrap: false), [4, 5, 6, 7, 8])
        XCTAssertEqual(MusicUpNext.indices(current: 18, count: 20, wrap: false), [19, 20])
        XCTAssertEqual(MusicUpNext.indices(current: 18, count: 20, wrap: true), [19, 20, 1, 2, 3])
        XCTAssertEqual(MusicUpNext.indices(current: 2, count: 3, wrap: true), [3, 1], "不绕回当前这首")
        XCTAssertEqual(MusicUpNext.indices(current: 20, count: 20, wrap: false), [])
        XCTAssertEqual(MusicUpNext.indices(current: 0, count: 20, wrap: false), [], "找不到当前这首")
        XCTAssertFalse(MusicUpNext.visible(shuffle: true), "开随机时隐藏")
        XCTAssertTrue(MusicUpNext.visible(shuffle: false))
    }

    // MARK: 刚才听过

    private func entry(_ n: Int) -> MusicRecent.Entry {
        .init(uri: "spotify:track:id\(n)", title: "Song \(n)", artist: "A", duration: 200)
    }

    func testRecentKeepsTwentyNewestFirstWithoutRepeats() {
        var recent = MusicRecent()
        for n in 1...25 { recent.record(entry(n)) }
        XCTAssertEqual(recent.entries.count, MusicRecent.capacity)
        XCTAssertEqual(recent.entries.first?.uri, "spotify:track:id25")
        XCTAssertEqual(recent.entries.last?.uri, "spotify:track:id6")
        recent.record(entry(10))
        XCTAssertEqual(recent.entries.first?.uri, "spotify:track:id10")
        XCTAssertEqual(recent.entries.filter { $0.uri == "spotify:track:id10" }.count, 1)
        XCTAssertEqual(recent.entries.count, MusicRecent.capacity)
    }

    func testRecentSkipsUnreplayableAndListsWithoutTheCurrent() {
        var recent = MusicRecent()
        recent.record(.init(uri: "spotify:local:abc", title: "Local", artist: "", duration: 0))
        recent.record(.init(uri: "spotify:ad:1", title: "Ad", artist: "", duration: 0))
        XCTAssertTrue(recent.entries.isEmpty)
        recent.record(entry(1))
        recent.record(entry(2))
        XCTAssertEqual(recent.listed(excluding: "spotify:track:id2").map(\.uri), ["spotify:track:id1"])
        recent.clear()
        XCTAssertTrue(recent.entries.isEmpty)
    }

    func testRecentRoundTripsAndBuildsASafeCommand() {
        var recent = MusicRecent()
        recent.record(entry(1))
        XCTAssertEqual(MusicRecent.decode(recent.encoded()), recent)
        XCTAssertEqual(MusicRecent.decode(nil), MusicRecent())
        XCTAssertEqual(MusicRecent.playCommand("spotify:track:4uLU6hMCjMI75M1A2tKUQC"),
                       "play track \"spotify:track:4uLU6hMCjMI75M1A2tKUQC\"")
        XCTAssertNil(MusicRecent.playCommand("spotify:track:x\" & do shell script \"rm"), "拼不进脚本")
        XCTAssertNil(MusicRecent.playCommand("spotify:album:1"))
    }

    // MARK: 光晕

    func testGlowNeverExceedsFifteenPercent() {
        XCTAssertLessThanOrEqual(ArtworkTint.glowOpacity, 0.15)
        let tint = ArtworkTint(hue: 0.6, saturation: 0.5)
        let glow = tint.glow
        XCTAssertGreaterThan(max(glow.red, glow.green, glow.blue), tint.top.red,
                             "光晕用亮色，叠在深色上看得出颜色")
    }
}
