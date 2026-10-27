import Foundation
import XCTest

/// 钉在桌面 · 媒体组：每档放哪些键、列表几行、电台列表窗口、进度和音量条换算。
final class DesktopCardsMediaTests: XCTestCase {

    func testMediaKindsOfferAllThreeSizes() {
        for kind in [WidgetKind.music, .podcast, .radio, .cassette, .recorder, .microphone, .ambient, .appVolume] {
            XCTAssertTrue(DesktopCardsMediaPlan.handles(kind), "\(kind)")
            XCTAssertEqual(DesktopCardsMediaPlan.sizes(kind), [.small, .medium, .large])
        }
        XCTAssertFalse(DesktopCardsMediaPlan.handles(.todo))
        XCTAssertFalse(DesktopCardsMediaPlan.handles(.volume))
        XCTAssertEqual(DesktopCardsMediaPlan.sizes(.todo), [])
    }

    func testMusicKeysGrowWithTheCard() {
        XCTAssertEqual(DesktopCardsMediaPlan.musicKeys(.small, skips: true, canSeek: true), [.playPause])
        XCTAssertEqual(DesktopCardsMediaPlan.musicKeys(.medium, skips: true, canSeek: true),
                       [.previous, .playPause, .next])
        XCTAssertEqual(DesktopCardsMediaPlan.musicKeys(.large, skips: true, canSeek: true),
                       [.back, .previous, .playPause, .next, .forward])
        // 不能拖进度的来源没有快退快进；设置里关掉的上一首不放。
        XCTAssertEqual(DesktopCardsMediaPlan.musicKeys(.large, skips: true, canSeek: false, previous: false),
                       [.playPause, .next])
    }

    func testBrowserVideoOnlyGetsPlayPause() {
        for size in DesktopPinSize.allCases {
            XCTAssertEqual(DesktopCardsMediaPlan.musicKeys(size, skips: false, canSeek: true), [.playPause])
        }
    }

    func testPodcastAndRadioKeys() {
        XCTAssertEqual(DesktopCardsMediaPlan.podcastKeys(.small, current: true), [.playPause])
        XCTAssertEqual(DesktopCardsMediaPlan.podcastKeys(.medium, current: true), [.back, .playPause, .forward])
        // 还没开始放这一集：只有播放。
        XCTAssertEqual(DesktopCardsMediaPlan.podcastKeys(.large, current: false), [.playPause])
        XCTAssertEqual(DesktopCardsMediaPlan.radioKeys(.small, stations: 5), [.playPause])
        XCTAssertEqual(DesktopCardsMediaPlan.radioKeys(.medium, stations: 5), [.previous, .playPause, .next])
        XCTAssertEqual(DesktopCardsMediaPlan.radioKeys(.large, stations: 1), [.playPause])
    }

    func testListRowsPerSize() {
        XCTAssertEqual(DesktopCardsMediaPlan.listRows(.appVolume, size: .small), 1)
        XCTAssertEqual(DesktopCardsMediaPlan.listRows(.appVolume, size: .medium), 3)
        XCTAssertEqual(DesktopCardsMediaPlan.listRows(.appVolume, size: .large), 6)
        XCTAssertEqual(DesktopCardsMediaPlan.listRows(.radio, size: .large), 4)
        XCTAssertEqual(DesktopCardsMediaPlan.listRows(.radio, size: .medium), 0)
        XCTAssertEqual(DesktopCardsMediaPlan.listRows(.podcast, size: .large), 3)
        XCTAssertEqual(DesktopCardsMediaPlan.listRows(.recorder, size: .medium), 1)
        XCTAssertEqual(DesktopCardsMediaPlan.listRows(.recorder, size: .large), 3)
        XCTAssertEqual(DesktopCardsMediaPlan.listRows(.microphone, size: .large), 3)
        XCTAssertEqual(DesktopCardsMediaPlan.listRows(.music, size: .large), 0)
    }

    func testSplitCountsWhatIsLeft() {
        XCTAssertEqual(DesktopCardsMediaPlan.split(count: 8, rows: 3).shown, 3)
        XCTAssertEqual(DesktopCardsMediaPlan.split(count: 8, rows: 3).more, 5)
        XCTAssertEqual(DesktopCardsMediaPlan.split(count: 2, rows: 3).shown, 2)
        XCTAssertEqual(DesktopCardsMediaPlan.split(count: 2, rows: 3).more, 0)
        XCTAssertEqual(DesktopCardsMediaPlan.split(count: -1, rows: 3).shown, 0)
    }

    func testAppVolumeRowsPutChangedAppsFirst() {
        let rows = ["a", "b*", "c", "d*", "e"]
        let small = DesktopCardsMediaPlan.appVolumeRows(rows, size: .small) { $0.hasSuffix("*") }
        XCTAssertEqual(small.shown, ["b*"])
        XCTAssertEqual(small.more, 4)
        let medium = DesktopCardsMediaPlan.appVolumeRows(rows, size: .medium) { $0.hasSuffix("*") }
        XCTAssertEqual(medium.shown, ["b*", "d*", "a"])
        XCTAssertEqual(medium.more, 2)
        let large = DesktopCardsMediaPlan.appVolumeRows(rows, size: .large) { $0.hasSuffix("*") }
        XCTAssertEqual(large.shown.count, 5)
        XCTAssertEqual(large.more, 0)
    }

    func testStationWindowKeepsTheTunedStationSecond() {
        XCTAssertEqual(DesktopCardsMediaPlan.stationWindow(current: 4, count: 10, rows: 4), 3..<7)
        // 第一台贴顶，最后一台贴底，不留空行。
        XCTAssertEqual(DesktopCardsMediaPlan.stationWindow(current: 0, count: 10, rows: 4), 0..<4)
        XCTAssertEqual(DesktopCardsMediaPlan.stationWindow(current: 9, count: 10, rows: 4), 6..<10)
        // 不够 4 台全放；越界的序号夹回来。
        XCTAssertEqual(DesktopCardsMediaPlan.stationWindow(current: 2, count: 3, rows: 4), 0..<3)
        XCTAssertEqual(DesktopCardsMediaPlan.stationWindow(current: 99, count: 6, rows: 4), 2..<6)
        XCTAssertEqual(DesktopCardsMediaPlan.stationWindow(current: 0, count: 0, rows: 4), 0..<0)
    }

    func testProgressOnlyOnBiggerCardsWithADuration() {
        XCTAssertFalse(DesktopCardsMediaPlan.showsProgress(.small, duration: 200))
        XCTAssertTrue(DesktopCardsMediaPlan.showsProgress(.medium, duration: 200))
        XCTAssertFalse(DesktopCardsMediaPlan.showsProgress(.large, duration: 0))
        XCTAssertFalse(DesktopCardsMediaPlan.showsProgress(.large, duration: .infinity))
        XCTAssertEqual(DesktopCardsMediaPlan.fraction(elapsed: 30, duration: 120), 0.25, accuracy: 0.0001)
        XCTAssertEqual(DesktopCardsMediaPlan.fraction(elapsed: 300, duration: 120), 1)
        XCTAssertEqual(DesktopCardsMediaPlan.fraction(elapsed: 3, duration: 0), 0)
    }

    func testSeekTargetFollowsTheTap() {
        XCTAssertEqual(DesktopCardsMediaPlan.seekTarget(x: 50, width: 200, duration: 240) ?? -1, 60, accuracy: 0.001)
        XCTAssertEqual(DesktopCardsMediaPlan.seekTarget(x: -10, width: 200, duration: 240) ?? -1, 0)
        XCTAssertEqual(DesktopCardsMediaPlan.seekTarget(x: 500, width: 200, duration: 240) ?? -1, 240)
        XCTAssertNil(DesktopCardsMediaPlan.seekTarget(x: 50, width: 0, duration: 240))
        XCTAssertNil(DesktopCardsMediaPlan.seekTarget(x: 50, width: 200, duration: 0))
    }

    func testAppVolumeBarMapsPositionToPercent() {
        XCTAssertEqual(DesktopCardsMediaPlan.appVolumePercent(x: 0, width: 150), 0)
        XCTAssertEqual(DesktopCardsMediaPlan.appVolumePercent(x: 150, width: 150), 150)
        XCTAssertEqual(DesktopCardsMediaPlan.appVolumePercent(x: 75, width: 150), 75)
        // 靠近 100% 吸过去。
        XCTAssertEqual(DesktopCardsMediaPlan.appVolumePercent(x: 101, width: 150), 100)
        XCTAssertEqual(DesktopCardsMediaPlan.appVolumePercent(x: 999, width: 150), 150)
        XCTAssertEqual(DesktopCardsMediaPlan.appVolumePercent(x: 10, width: 0), 100)
    }

    func testAmbientToggleKeepsAtLeastOneSound() {
        XCTAssertEqual(DesktopCardsMediaPlan.toggling(.waves, in: [.rain]), [.rain, .waves])
        XCTAssertEqual(DesktopCardsMediaPlan.toggling(.rain, in: [.rain, .waves]), [.waves])
        XCTAssertEqual(DesktopCardsMediaPlan.toggling(.rain, in: [.rain]), [.rain])
        XCTAssertEqual(DesktopCardsMediaPlan.ambientColumns, 4)
    }

    func testUsedForReadsInMinutesAndHours() {
        let now = Date(timeIntervalSinceReferenceDate: 100_000)
        XCTAssertEqual(DesktopCardsMediaPlan.usedFor(since: now.addingTimeInterval(-20), now: now), tr("刚刚"))
        XCTAssertEqual(DesktopCardsMediaPlan.usedFor(since: now.addingTimeInterval(-12 * 60), now: now), tr("已 \(12) 分钟"))
        XCTAssertEqual(DesktopCardsMediaPlan.usedFor(since: now.addingTimeInterval(-120 * 60), now: now), tr("已 \(2) 小时"))
        XCTAssertEqual(DesktopCardsMediaPlan.usedFor(since: now.addingTimeInterval(-75 * 60), now: now), tr("已 \(1) 小时 \(15) 分"))
        XCTAssertEqual(DesktopCardsMediaPlan.usedFor(since: now.addingTimeInterval(60), now: now), tr("刚刚"))
    }
}
