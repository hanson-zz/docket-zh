import XCTest

/// 网易云、QQ 音乐、小宇宙的面板按钮：走哪条路、怎么判断生效、点哪个菜单项。
final class NowPlayingControlTests: XCTestCase {
    typealias C = NowPlayingControl

    func testCommandsFromServiceBodies() {
        XCTAssertEqual(C.Command(body: "playpause"), .playPause)
        XCTAssertEqual(C.Command(body: "next track"), .next)
        XCTAssertEqual(C.Command(body: "previous track"), .previous)
        XCTAssertNil(C.Command(body: "set player position to 0.00"))
        XCTAssertEqual(C.Command.playPause.remoteCode, 2)
        XCTAssertEqual(C.Command.next.remoteCode, 4)
        XCTAssertEqual(C.Command.previous.remoteCode, 5)
        XCTAssertEqual(C.Command.allCases.map(\.mediaKey), [16, 17, 18])
    }

    func testRoutesPreferTheSystemCommandWhichNeedsNoPermission() {
        XCTAssertEqual(C.routes(remote: .unknown, trusted: false), [.remote])
        XCTAssertEqual(C.routes(remote: .unknown, trusted: true), [.remote, .menu, .mediaKey])
        XCTAssertEqual(C.routes(remote: .works, trusted: false), [.remote])
        XCTAssertEqual(C.routes(remote: .works, trusted: true), [.remote, .menu, .mediaKey])
    }

    func testRoutesSkipTheSystemCommandOnceItIsKnownNotToWork() {
        XCTAssertEqual(C.routes(remote: .fails, trusted: true), [.menu, .mediaKey])
        // 没权限时还是发一次系统命令，不至于什么都不做。
        XCTAssertEqual(C.routes(remote: .fails, trusted: false), [.remote])
    }

    func testOnlyAnUncheckedSystemCommandIsVerified() {
        XCTAssertTrue(C.verifies(.unknown))
        XCTAssertFalse(C.verifies(.works))
        XCTAssertFalse(C.verifies(.fails))
    }

    func testAccessibilityHintOnlyWhenTheFallbackIsNeededAndMissing() {
        XCTAssertTrue(C.needsAccessibility(remote: .fails, trusted: false))
        XCTAssertFalse(C.needsAccessibility(remote: .fails, trusted: true))
        XCTAssertFalse(C.needsAccessibility(remote: .unknown, trusted: false))
        XCTAssertFalse(C.needsAccessibility(remote: .works, trusted: false))
    }

    func testPlayPauseTookWhenThePlayingStateFlips() {
        let playing = C.Snapshot(title: "晴天", isPlaying: true, elapsed: 30)
        let paused = C.Snapshot(title: "晴天", isPlaying: false, elapsed: 30.4)
        XCTAssertTrue(C.took(.playPause, before: playing, after: paused))
        XCTAssertFalse(C.took(.playPause, before: playing, after: playing))
    }

    func testNextAndPreviousTookWhenTheTrackChangesOrRestarts() {
        let a = C.Snapshot(title: "晴天", isPlaying: true, elapsed: 60)
        let b = C.Snapshot(title: "七里香", isPlaying: true, elapsed: 0.5)
        let restarted = C.Snapshot(title: "晴天", isPlaying: true, elapsed: 0.3)
        let same = C.Snapshot(title: "晴天", isPlaying: true, elapsed: 61)
        XCTAssertTrue(C.took(.next, before: a, after: b))
        XCTAssertTrue(C.took(.previous, before: a, after: b))
        XCTAssertTrue(C.took(.previous, before: a, after: restarted))
        XCTAssertFalse(C.took(.next, before: a, after: same))
        XCTAssertFalse(C.took(.previous, before: a, after: same))
    }

    func testMissingReadingCountsAsTakenSoNothingIsPressedTwice() {
        let a = C.Snapshot(title: "晴天", isPlaying: true, elapsed: 60)
        XCTAssertTrue(C.took(.next, before: nil, after: a))
        XCTAssertTrue(C.took(.playPause, before: a, after: nil))
    }

    func testMenuItemPrefersTheControlMenu() {
        let menus = [
            C.Menu(title: "网易云音乐", items: ["关于网易云音乐", "", "暂停"]),
            C.Menu(title: "文件", items: ["新建歌单", "播放"]),
            C.Menu(title: "控制", items: ["暂停", "", "下一首", "上一首", "播放模式", "音量加"]),
        ]
        XCTAssertEqual(C.menuItem(for: .playPause, in: menus)?.menu, 2)
        XCTAssertEqual(C.menuItem(for: .playPause, in: menus)?.item, 0)
        XCTAssertEqual(C.menuItem(for: .next, in: menus)?.item, 2)
        XCTAssertEqual(C.menuItem(for: .previous, in: menus)?.item, 3)
    }

    func testMenuItemMatchesWholeTitlesOnly() {
        let menus = [
            C.Menu(title: "QQ音乐", items: []),
            C.Menu(title: "播放控制", items: ["播放列表", "播放模式", "下一首歌词"]),
        ]
        XCTAssertNil(C.menuItem(for: .playPause, in: menus))
        XCTAssertNil(C.menuItem(for: .next, in: menus))
    }

    func testMenuItemToleratesSpacingEllipsisAndEnglish() {
        let menus = [
            C.Menu(title: "App", items: []),
            C.Menu(title: "Controls", items: ["Play / Pause", "Next Track…", "  Previous  "]),
        ]
        XCTAssertEqual(C.menuItem(for: .playPause, in: menus)?.item, 0)
        XCTAssertEqual(C.menuItem(for: .next, in: menus)?.item, 1)
        XCTAssertEqual(C.menuItem(for: .previous, in: menus)?.item, 2)
    }

    func testMenuItemFallsBackToOtherMenusAndSkipsTheAppMenu() {
        let menus = [
            C.Menu(title: "小宇宙", items: ["播放"]),
            C.Menu(title: "编辑", items: ["拷贝"]),
            C.Menu(title: "单集", items: ["播放", "下一个"]),
        ]
        XCTAssertEqual(C.menuItem(for: .playPause, in: menus)?.menu, 2)
        XCTAssertEqual(C.menuItem(for: .next, in: menus)?.item, 1)
        XCTAssertNil(C.menuItem(for: .previous, in: menus))
        XCTAssertNil(C.menuItem(for: .next, in: []))
    }
}
