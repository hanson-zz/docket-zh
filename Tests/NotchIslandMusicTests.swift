import XCTest

/// 刘海小岛的「音乐」活动：设置迁移、和收音机等的优先级、暂停后留多久、时间文字、
/// 收起宽度、卡片几何、音波和点歌曲区域打开哪张面板。
final class NotchIslandMusicTests: XCTestCase {

    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let geometry = NotchIslandGeometry(notchWidth: 185, notchHeight: 32, hasNotch: true)

    private func song(_ playing: Bool = true, title: String = "晨光里的码头") -> NotchIslandMusic {
        NotchIslandMusic(title: title, artist: "海风乐队", playing: playing,
                         tint: ArtworkTint(hue: 0.9, saturation: 0.5), source: .appleMusic)
    }

    private var music: NotchIslandActivity { .music(song()) }
    private var pausedMusic: NotchIslandActivity { .music(song(false)) }
    private var radio: NotchIslandActivity { .radio(station: "Lo-fi 电台", playing: true) }
    private var timer: NotchIslandActivity {
        .timer(deadline: now.addingTimeInterval(1498), pausedLeft: nil, total: 1500, focus: true)
    }

    // MARK: 设置

    func testMusicKindAndSettingsList() {
        XCTAssertEqual(music.kind, .music)
        XCTAssertEqual(NotchIslandKind.music.title, "音乐")
        XCTAssertFalse(NotchIslandKind.music.detail.isEmpty)
        XCTAssertTrue(NotchIslandKind.settingsOrder.contains(.music), "设置里的开关列表自动出现")
        XCTAssertEqual(NotchIslandKind.settingsOrder.firstIndex(of: .music),
                       NotchIslandKind.settingsOrder.firstIndex(of: .radio)! + 1, "排在收音机后面")
        XCTAssertTrue(NotchIslandSettings().isOn(.music), "新装（没存过设置）默认勾上，总开关仍默认关")
        XCTAssertFalse(NotchIslandSettings().enabled)
    }

    func testExistingUsersGetMusicOff() throws {
        // 加音乐之前存的设置：known 里没有音乐，读回来音乐是关着的，小岛不会突然多出来。
        let before = Data(#"{"enabled":true,"kinds":["charging","download","timer","meeting","radio"],"known":["charging","download","timer","meeting","radio"]}"#.utf8)
        let decoded = try JSONDecoder().decode(NotchIslandSettings.self, from: before)
        XCTAssertFalse(decoded.isOn(.music))
        XCTAssertTrue(decoded.isOn(.meeting))
        // 没有 known 的最老文件：会议照旧默认勾上，音乐照旧关着。
        let oldest = try JSONDecoder().decode(NotchIslandSettings.self,
                                              from: Data(#"{"enabled":true,"kinds":["radio"]}"#.utf8))
        XCTAssertTrue(oldest.isOn(.meeting))
        XCTAssertFalse(oldest.isOn(.music))
        // 自己勾上后存的：读回来是开着的；再取消勾选也记得住。
        var on = decoded
        on.set(.music, true)
        XCTAssertTrue(try JSONDecoder().decode(NotchIslandSettings.self, from: JSONEncoder().encode(on)).isOn(.music))
        var off = NotchIslandSettings()
        off.set(.music, false)
        XCTAssertFalse(try JSONDecoder().decode(NotchIslandSettings.self, from: JSONEncoder().encode(off)).isOn(.music))
        XCTAssertEqual(NotchIslandKind.optIn, [.music])
    }

    // MARK: 优先级

    func testMusicIsLowestPriority() {
        for kind in NotchIslandKind.allCases where kind != .music {
            XCTAssertLessThan(kind.priority, NotchIslandKind.music.priority, "\(kind)")
        }
        let settings = NotchIslandSettings()
        XCTAssertEqual(NotchIslandStack.form([music], settings: settings, hovering: false), .compact(music))
        XCTAssertEqual(NotchIslandStack.form([music, timer], settings: settings, hovering: false), .split(timer, music),
                       "计时器主岛，音乐变成右边的小圆岛")
        XCTAssertEqual(NotchIslandStack.form([music, timer, radio], settings: settings, hovering: false),
                       .split(timer, radio), "最多两个：音乐让位")
        XCTAssertEqual(NotchIslandStack.form([music, timer], settings: settings, hovering: true),
                       .expanded(timer, secondary: music))
    }

    func testDockRadioPlayingTakesPrecedence() {
        let settings = NotchIslandSettings()
        XCTAssertEqual(NotchIslandStack.ordered([music, radio], settings: settings), [radio, music],
                       "码头自带收音机在播：收音机是主岛，音乐让位成小圆岛")
        XCTAssertEqual(NotchIslandStack.form([music, radio], settings: settings, hovering: false), .split(radio, music))
        // 收音机只是暂停后留着、音乐正在播：音乐排前面。
        let heldRadio = NotchIslandActivity.radio(station: "Lo-fi 电台", playing: false)
        XCTAssertEqual(NotchIslandStack.ordered([heldRadio, music], settings: settings), [music, heldRadio])
        // 两个都暂停：照固定优先级。
        XCTAssertEqual(NotchIslandStack.ordered([pausedMusic, heldRadio], settings: settings), [heldRadio, pausedMusic])
        // 对调只发生在收音机和音乐之间，不越过计时器。
        XCTAssertEqual(NotchIslandStack.ordered([music, heldRadio, timer], settings: settings),
                       [timer, music, heldRadio])
    }

    func testMusicOffInSettingsIsDropped() {
        var settings = NotchIslandSettings()
        settings.set(.music, false)
        XCTAssertEqual(NotchIslandStack.ordered([music, radio], settings: settings), [radio])
        XCTAssertNil(NotchIslandStack.form([music], settings: settings, hovering: false))
    }

    func testMediaPlaying() {
        XCTAssertEqual(music.mediaPlaying, true)
        XCTAssertEqual(pausedMusic.mediaPlaying, false)
        XCTAssertEqual(radio.mediaPlaying, true)
        XCTAssertNil(timer.mediaPlaying)
    }

    // MARK: 暂停后留多久

    func testTrackerShowsWhilePlayingAndLingersAfterPause() {
        var tracker = NotchIslandMusicTracker()
        XCTAssertNil(tracker.activity(now: now))
        tracker.update(song(), now: now)
        XCTAssertEqual(tracker.activity(now: now), .music(song()))
        let pausedAt = now.addingTimeInterval(10)
        tracker.update(song(false), now: pausedAt)
        XCTAssertEqual(tracker.activity(now: pausedAt), .music(song(false)), "暂停态照样显示")
        let linger = NotchIslandTiming.musicPauseLinger
        XCTAssertNotNil(tracker.activity(now: pausedAt.addingTimeInterval(linger - 1)))
        // 暂停时再读到暂停，不会把计时往后推。
        tracker.update(song(false), now: pausedAt.addingTimeInterval(linger - 1))
        XCTAssertNil(tracker.activity(now: pausedAt.addingTimeInterval(linger)), "暂停超过一段时间收起")
        // 又播了：马上回来。
        tracker.update(song(), now: pausedAt.addingTimeInterval(linger + 5))
        XCTAssertNotNil(tracker.activity(now: pausedAt.addingTimeInterval(linger + 5)))
    }

    func testTrackerHidesWhenStoppedOrAlreadyPaused() {
        var tracker = NotchIslandMusicTracker()
        tracker.update(song(false), now: now)
        XCTAssertNil(tracker.activity(now: now), "打开时就停在那儿的歌不显示")
        tracker.update(song(), now: now)
        tracker.update(nil, now: now.addingTimeInterval(1))
        XCTAssertNil(tracker.activity(now: now.addingTimeInterval(1)), "停止、没有会话立刻收起")
        tracker.update(song(false), now: now.addingTimeInterval(2))
        XCTAssertNil(tracker.activity(now: now.addingTimeInterval(2)), "停止后再读到暂停也不显示")
    }

    func testTrackerKeepsAliveWhileHovering() {
        var tracker = NotchIslandMusicTracker()
        tracker.update(song(), now: now)
        tracker.update(song(false), now: now)
        let linger = NotchIslandTiming.musicPauseLinger
        tracker.keepAlive(now: now.addingTimeInterval(linger - 1))
        XCTAssertNotNil(tracker.activity(now: now.addingTimeInterval(linger + 5)), "指针停在卡片上时不收")
        // 在播时 keepAlive 不改什么。
        var playing = NotchIslandMusicTracker()
        playing.update(song(), now: now)
        playing.keepAlive(now: now)
        XCTAssertEqual(playing.activity(now: now.addingTimeInterval(3600)), .music(song()))
    }

    func testTrackerFollowsTrackChanges() {
        var tracker = NotchIslandMusicTracker()
        tracker.update(song(), now: now)
        tracker.update(song(false), now: now)
        // 暂停着按了下一首：换歌照样留着，计时不重算。
        let next = song(false, title: "下一首歌")
        tracker.update(next, now: now.addingTimeInterval(5))
        XCTAssertEqual(tracker.activity(now: now.addingTimeInterval(5)), .music(next))
        XCTAssertNil(tracker.activity(now: now.addingTimeInterval(NotchIslandTiming.musicPauseLinger)))
    }

    func testReadingNeedsATitle() {
        XCTAssertNil(NotchIslandMusic.reading(title: "  ", artist: "a", playing: true, tint: nil, source: .spotify))
        let reading = NotchIslandMusic.reading(title: " 晨光 ", artist: " 海风 ", playing: true, tint: nil,
                                               source: .spotify)
        XCTAssertEqual(reading?.title, "晨光")
        XCTAssertEqual(reading?.artist, "海风")
        XCTAssertEqual(reading?.line, "晨光 · 海风")
        XCTAssertEqual(NotchIslandMusic(title: "晨光", artist: "", playing: true).line, "晨光")
    }

    // MARK: 文字

    func testTimes() {
        let times = NotchIslandMusicText.times(elapsed: 84.6, duration: 214)
        XCTAssertEqual(times?.elapsed, "1:24")
        XCTAssertEqual(times?.remaining, "-2:10")
        XCTAssertEqual(NotchIslandMusicText.times(elapsed: 0, duration: 213.4)?.remaining, "-3:34", "总长向上取整")
        XCTAssertEqual(NotchIslandMusicText.times(elapsed: 300, duration: 214)?.elapsed, "3:34", "已播不超过总长")
        XCTAssertEqual(NotchIslandMusicText.times(elapsed: 300, duration: 214)?.remaining, "-0:00")
        XCTAssertEqual(NotchIslandMusicText.times(elapsed: -3, duration: 60)?.elapsed, "0:00")
        XCTAssertEqual(NotchIslandMusicText.times(elapsed: 62, duration: 3725)?.remaining, "-1:01:03")
        XCTAssertNil(NotchIslandMusicText.times(elapsed: 10, duration: 0), "直播流没有时长不画进度")
        XCTAssertNil(NotchIslandMusicText.times(elapsed: 10, duration: .nan))
        XCTAssertEqual(NotchIslandMusicText.progress(elapsed: 107, duration: 214), 0.5, accuracy: 0.0001)
        XCTAssertEqual(NotchIslandMusicText.progress(elapsed: 999, duration: 214), 1)
        XCTAssertEqual(NotchIslandMusicText.progress(elapsed: 5, duration: 0), 0)
        for text in [times!.elapsed, times!.remaining] {
            XCTAssertFalse(text.contains("\u{2014}"))
        }
    }

    func testSpoken() {
        XCTAssertTrue(NotchIslandText.spoken(music, now: now).contains("晨光里的码头 · 海风乐队"))
        XCTAssertNotEqual(NotchIslandText.spoken(music, now: now), NotchIslandText.spoken(pausedMusic, now: now))
    }

    // MARK: 几何

    func testCompactWingsStayNarrow() {
        let wings = NotchIslandLayout.wings(music)
        XCTAssertEqual(wings.left, 30)
        XCTAssertEqual(wings.right, 28)
        XCTAssertEqual(wings.chin, 0, "收起时不在刘海下面多一条")
        XCTAssertLessThanOrEqual(wings.left, NotchIslandLayout.maxWing)
        XCTAssertLessThanOrEqual(wings.right, NotchIslandLayout.maxWing)
        XCTAssertEqual(NotchIslandLayout.wings(pausedMusic).left, wings.left, "暂停时不变宽")
        XCTAssertEqual(NotchIslandLayout.wings(pausedMusic).right, wings.right)
        let body = NotchIslandLayout.body(geometry, music)
        XCTAssertEqual(body.minY, 0)
        XCTAssertEqual(body.height, geometry.notchHeight)
        XCTAssertTrue(body.contains(NotchIslandLayout.notch(geometry)), "和刘海连成一体")
        XCTAssertLessThanOrEqual(NotchIslandLayout.musicArtSize, geometry.notchHeight - 8, "缩略图放得进刘海高度")
    }

    func testCardGrowsFromTheNotch() {
        XCTAssertTrue(NotchIslandLayout.grows(.music))
        XCTAssertTrue(NotchIslandLayout.grows(.radio))
        XCTAssertFalse(NotchIslandLayout.grows(.timer))
        let card = NotchIslandLayout.card(geometry, kind: .music, hasSecondary: false)
        XCTAssertEqual(NotchIslandLayout.cardGap(kind: .music), 0)
        XCTAssertEqual(card.minY, geometry.notchHeight, "顶边和刘海连成一体，不留缝")
        XCTAssertEqual(card.height, 150, "和电台卡片同高")
        XCTAssertEqual(card.height, NotchIslandLayout.card(geometry, kind: .radio, hasSecondary: false).height)
        XCTAssertEqual(card.width, 380)
        XCTAssertEqual(card.midX, 0, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(card.width / 2 - geometry.notchWidth / 2,
                                    NotchIslandLayout.radioShoulder + NotchIslandLayout.radioTopRadius)
        let wide = NotchIslandGeometry(notchWidth: 280, notchHeight: 38, hasNotch: true)
        XCTAssertEqual(NotchIslandLayout.cardWidth(wide, kind: .music), 400)
        let pieces = NotchIslandLayout.pieces(geometry, form: .expanded(music, secondary: timer))
        XCTAssertEqual(pieces.count, 2)
        for piece in pieces where piece != NotchIslandLayout.notch(geometry) {
            XCTAssertGreaterThanOrEqual(piece.minY, geometry.notchHeight, "不伸进菜单栏")
        }
        XCTAssertFalse(NotchHangingPanda.hangs(music))
    }

    func testCardFitsCoverAndSticker() {
        let card = NotchIslandLayout.card(geometry, kind: .music, hasSecondary: false)
        let inner = card.height - NotchIslandLayout.radioShoulder - 10 - 14
        XCTAssertLessThanOrEqual(NotchIslandMusicLook.coverSize, inner, "封面放得进卡片")
        let sticker = NotchIslandMusicLook.stickerHeight(cardHeight: card.height)
        XCTAssertLessThanOrEqual(sticker, card.height / 3, "小熊猫不超过卡片高度的三分之一")
        XCTAssertGreaterThan(sticker, 20)
        XCTAssertLessThanOrEqual(NotchIslandMusicLook.glowOpacity, 0.15, "封面主色光晕很淡")
    }

    // MARK: 音波

    func testWaveLevels() {
        let playing = NotchIslandMusicLook.barLevels(at: 12.3, playing: true, reduceMotion: false)
        XCTAssertEqual(playing.count, NotchIslandMusicLook.playingBars)
        XCTAssertTrue(playing.allSatisfy { $0 >= 0.3 && $0 <= 1 })
        XCTAssertNotEqual(playing, NotchIslandMusicLook.barLevels(at: 12.6, playing: true, reduceMotion: false),
                          "播放时起伏")
        let still = NotchIslandMusicLook.barLevels(at: 12.3, playing: true, reduceMotion: true)
        XCTAssertEqual(still, NotchIslandMusicLook.barLevels(at: 99, playing: true, reduceMotion: true),
                       "减弱动态效果时静止")
        let paused = NotchIslandMusicLook.barLevels(at: 12.3, playing: false, reduceMotion: false)
        XCTAssertEqual(paused.count, 3, "暂停变成三条静止短竖线")
        XCTAssertEqual(Set(paused).count, 1)
        XCTAssertLessThan(paused[0], 0.5)
        XCTAssertTrue(NotchIslandMusicLook.animates(playing: true, reduceMotion: false))
        XCTAssertFalse(NotchIslandMusicLook.animates(playing: true, reduceMotion: true))
        XCTAssertFalse(NotchIslandMusicLook.animates(playing: false, reduceMotion: false))
    }

    func testWaveColorComesFromTheCover() {
        let tint = ArtworkTint(hue: 0.6, saturation: 0.5)
        let color = NotchIslandMusicLook.waveColor(tint)
        XCTAssertEqual(color.red, tint.glow.red, accuracy: 0.0001)
        XCTAssertEqual(color.blue, tint.glow.blue, accuracy: 0.0001)
        let fallback = NotchIslandMusicLook.waveColor(nil)
        XCTAssertEqual(fallback.red, 1, accuracy: 0.0001)
        XCTAssertEqual(fallback.green, 154.0 / 255, accuracy: 0.0001)
        XCTAssertLessThan(NotchIslandMusicLook.pausedArtOpacity, 1, "暂停时封面稍暗")
    }

    // MARK: 点歌曲区域

    func testPanelWidgetRoute() {
        let musicHere = WidgetInstance(kind: .music, config: WidgetConfig())
        let musicElsewhere = WidgetInstance(kind: .music, config: WidgetConfig())
        let cassette = WidgetInstance(kind: .cassette, config: WidgetConfig())
        let weather = WidgetInstance(kind: .weather, config: WidgetConfig())
        XCTAssertEqual(NotchIslandMusicRoute.panelWidget(current: [weather, musicHere],
                                                         all: [musicElsewhere, weather, musicHere]),
                       musicHere.id, "先找当前布局里的")
        XCTAssertEqual(NotchIslandMusicRoute.panelWidget(current: [weather], all: [musicElsewhere]),
                       musicElsewhere.id, "当前布局没有就找别的布局")
        XCTAssertEqual(NotchIslandMusicRoute.panelWidget(current: [cassette], all: [cassette]), cassette.id,
                       "没有正在播放就用复古卡带")
        XCTAssertEqual(NotchIslandMusicRoute.panelWidget(current: [cassette], all: [musicElsewhere, cassette]),
                       musicElsewhere.id, "正在播放优先")
        XCTAssertNil(NotchIslandMusicRoute.panelWidget(current: [weather], all: [weather]), "都没有时打开来源 App")
    }
}
