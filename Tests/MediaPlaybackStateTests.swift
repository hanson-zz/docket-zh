import XCTest

/// 播放动画按窗口真实状态停帧，播客播放失败后再点播放会重新载入。
final class MediaPlaybackStateTests: XCTestCase {

    // MARK: 窗口看得见

    func testWindowShownNeedsVisibleAndUnoccluded() {
        XCTAssertTrue(MediaOnScreen.windowShown(.init(isVisible: true, occlusionVisible: true)))
        XCTAssertFalse(MediaOnScreen.windowShown(.init(isVisible: false, occlusionVisible: true)),
                       "面板关上（orderOut）后不算看得见")
        XCTAssertFalse(MediaOnScreen.windowShown(.init(isVisible: true, occlusionVisible: false)),
                       "被整个挡住、在别的桌面时不算看得见")
        XCTAssertFalse(MediaOnScreen.windowShown(nil), "不在窗口里（量尺寸的临时视图）不算看得见")
    }

    func testVisibleNeedsAppearedAndWindow() {
        XCTAssertTrue(MediaOnScreen.visible(appeared: true, windowShown: true))
        XCTAssertFalse(MediaOnScreen.visible(appeared: true, windowShown: false))
        XCTAssertFalse(MediaOnScreen.visible(appeared: false, windowShown: true))
    }

    func testVinylStopsWhenPanelWindowHidden() {
        let hidden = MediaOnScreen.visible(appeared: true,
                                           windowShown: MediaOnScreen.windowShown(.init(isVisible: false,
                                                                                        occlusionVisible: false)))
        XCTAssertNil(MusicVinyl.framesPerSecond(playing: true, visible: hidden, reduceMotion: false),
                     "面板关上后唱片不再按帧刷新")
        let shown = MediaOnScreen.visible(appeared: true,
                                          windowShown: MediaOnScreen.windowShown(.init(isVisible: true,
                                                                                       occlusionVisible: true)))
        XCTAssertEqual(MusicVinyl.framesPerSecond(playing: true, visible: shown, reduceMotion: false), MusicVinyl.fps)
        XCTAssertNil(MusicVinyl.framesPerSecond(playing: false, visible: shown, reduceMotion: false), "暂停不转")
        XCTAssertNil(MusicVinyl.framesPerSecond(playing: true, visible: shown, reduceMotion: true), "减弱动态效果不转")
    }

    func testPlayingBarsStopWhenWindowHidden() {
        let hidden = MediaOnScreen.visible(appeared: true, windowShown: false)
        XCTAssertNil(PlayingBars.framesPerSecond(playing: true, visible: hidden, reduceMotion: false))
        XCTAssertNotNil(PlayingBars.framesPerSecond(playing: true, visible: true, reduceMotion: false))
    }

    func testDiscAngleHoldsWhilePaused() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let stopped = MusicVinyl.discAngle(base: 0, since: start, now: start.addingTimeInterval(3))
        XCTAssertEqual(stopped, 120, accuracy: 0.001)
        // 停下时把角度存成 base，since 置空：之后多久都停在这个角度。
        XCTAssertEqual(MusicVinyl.discAngle(base: stopped, since: nil, now: start.addingTimeInterval(600)), stopped)
    }

    // MARK: 播客失败后恢复

    func testResumeHealthyItem() {
        XCTAssertEqual(PodcastResume.action(hasEpisode: true, hasItem: true, itemFailed: false), .resume)
    }

    func testFailedItemReloads() {
        XCTAssertEqual(PodcastResume.action(hasEpisode: true, hasItem: true, itemFailed: true), .reload,
                       "坏掉的条目再 play() 没声音，要重新载入")
    }

    func testMissingItemReloads() {
        XCTAssertEqual(PodcastResume.action(hasEpisode: true, hasItem: false, itemFailed: false), .reload)
    }

    func testNoEpisodeDoesNothing() {
        XCTAssertEqual(PodcastResume.action(hasEpisode: false, hasItem: false, itemFailed: false), .nothing)
        XCTAssertEqual(PodcastResume.action(hasEpisode: false, hasItem: true, itemFailed: true), .nothing)
    }
}
