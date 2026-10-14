import XCTest

/// 网易云音乐, read from the system's Now Playing.
final class NowPlayingInfoTests: XCTestCase {
    private let netease = "com.netease.163music"

    func testReadsItsOwnTrackAndMovesThePlayhead() {
        let json = """
        {"id":"com.netease.163music","parent":null,"title":"晴天","artist":"周杰伦","album":"叶惠美",
         "duration":269.5,"elapsed":30,"rate":1,"stamp":1000,"playing":true}
        """
        let info = NowPlayingInfo.decode(json)
        let track = info?.track(for: netease, now: Date(timeIntervalSince1970: 1010))
        XCTAssertEqual(track?.title, "晴天")
        XCTAssertEqual(track?.artist, "周杰伦")
        XCTAssertEqual(track?.isPlaying, true)
        XCTAssertEqual(track?.elapsed ?? 0, 40, accuracy: 0.001)
    }

    func testPausedDoesNotMoveAndOtherAppsAreIgnored() {
        let json = """
        {"id":"com.netease.163music","title":"晴天","duration":269,"elapsed":30,"rate":0,"stamp":1000,"playing":false}
        """
        let info = NowPlayingInfo.decode(json)
        XCTAssertEqual(info?.track(for: netease, now: Date(timeIntervalSince1970: 2000))?.elapsed, 30)
        XCTAssertNil(info?.track(for: "com.spotify.client", now: .now))
        XCTAssertNil(NowPlayingInfo.decode(""))
        let helper = NowPlayingInfo.decode(#"{"id":"x.helper","parent":"com.netease.163music","title":"a"}"#)
        XCTAssertNotNil(helper?.track(for: netease, now: .now))
    }

    func testNetEaseCannotSeek() {
        XCTAssertFalse(MusicSource.netease.canSeek)
        XCTAssertTrue(MusicSource.spotify.canSeek)
        XCTAssertEqual(MusicSource.netease.displayName, "网易云音乐")
    }
}
