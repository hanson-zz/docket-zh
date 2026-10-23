import XCTest

/// 「正在播放」控制键下的歌单入口（方案 A）：显示条件、标题、占位、截断、尺寸。
final class MusicQueueTests: XCTestCase {

    private func apple(shuffle: Bool = false, repeatMode: MusicRepeat = .off, playlist: String? = "通勤路上",
                       isLibrary: Bool = false, loaded: Int? = 3, remaining: Int? = 24,
                       loading: Bool = false) -> MusicQueue.Input {
        .init(source: .appleMusic, isNative: true, shuffle: shuffle, repeatMode: repeatMode,
              playlist: playlist, isLibrary: isLibrary, loaded: loaded, remaining: remaining, loading: loading)
    }

    // MARK: 显示条件

    func testSourcesWithoutAQueueHideTheWholeBlockAndKeepTheBigCover() {
        for source in [MusicSource.netease, .qqmusic, .xiaoyuzhou] {
            let block = MusicQueue.block(.init(source: source, isNative: true))
            XCTAssertNil(block, "\(source) 读不到队列，整块不出现")
            XCTAssertEqual(MusicQueue.coverSide(block), 204)
        }
        XCTAssertNil(MusicQueue.block(.init(source: nil, isNative: false)), "浏览器标签页")
        XCTAssertNil(MusicQueue.block(.init(source: .appleMusic, isNative: false)), "没有播放器读数")
    }

    func testUnreadablePlaylistHidesTheBlock() {
        var input = apple(loaded: nil, remaining: nil)
        input.unreadable = true
        XCTAssertNil(MusicQueue.block(input), "电台、在线流读不到歌单：整块不出现，封面回到 204")
        input.shuffle = true
        XCTAssertEqual(MusicQueue.block(input)?.content, .shuffle, "随机时本来就不读，照样说明")
    }

    func testAppleMusicListsThreeWithAnAllPill() {
        let block = MusicQueue.block(apple())
        XCTAssertEqual(block?.kind, .upNext)
        XCTAssertEqual(block?.title, .playlist("通勤路上"))
        XCTAssertEqual(block?.content, .rows)
        XCTAssertEqual(block?.allCount, 24, "全部 N 首按歌单剩下的算，不按读到的 3 首")
        XCTAssertEqual(MusicQueue.coverSide(block), 128)
    }

    func testNoAllPillWhenThreeOrFewerAreLeft() {
        XCTAssertNil(MusicQueue.block(apple(loaded: 3, remaining: 3))?.allCount)
        XCTAssertNil(MusicQueue.block(apple(loaded: 2, remaining: 2))?.allCount)
        XCTAssertEqual(MusicQueue.block(apple(loaded: 3, remaining: 4))?.allCount, 4)
        XCTAssertEqual(MusicQueue.block(apple(loaded: 3, remaining: nil))?.allCount, nil,
                       "不知道剩几首时按读到的算")
    }

    func testShuffleSaysAppleMusicDecidesTheOrder() {
        let block = MusicQueue.block(apple(shuffle: true))
        XCTAssertEqual(block?.content, .shuffle)
        XCTAssertEqual(block?.title, .upNext, "随机时不写歌单名")
        XCTAssertNil(block?.allCount)
        XCTAssertEqual(MusicQueue.coverSide(block), 128, "随机时整块还在，不再消失")
    }

    func testLastTrackOffersLoopingFromTheTop() {
        XCTAssertEqual(MusicQueue.block(apple(loaded: 0, remaining: 0))?.content, .end(canLoop: true))
        XCTAssertEqual(MusicQueue.block(apple(repeatMode: .one, loaded: 0, remaining: 0))?.content,
                       .end(canLoop: true))
        XCTAssertEqual(MusicQueue.block(apple(repeatMode: .all, loaded: 0, remaining: 0))?.content,
                       .end(canLoop: false), "已经循环全部（只有一首）时不再给按钮")
    }

    func testLoadingShowsGreyPlaceholders() {
        XCTAssertEqual(MusicQueue.block(apple(loaded: nil, remaining: nil, loading: true))?.content,
                       .loading(placeholders: 3))
        XCTAssertEqual(MusicQueue.block(apple(loaded: 0, remaining: 2, loading: true))?.content,
                       .loading(placeholders: 2), "读到的是空、但知道后面还有：还在读")
    }

    // MARK: 标题

    func testWholeLibraryIsCalledLibrary() {
        XCTAssertEqual(MusicQueue.title(playlist: "音乐", isLibrary: false), .library)
        XCTAssertEqual(MusicQueue.title(playlist: "Music", isLibrary: false), .library)
        XCTAssertEqual(MusicQueue.title(playlist: "随便什么", isLibrary: true), .library)
        XCTAssertEqual(MusicQueue.title(playlist: " 通勤路上 ", isLibrary: false), .playlist("通勤路上"))
        XCTAssertEqual(MusicQueue.title(playlist: "", isLibrary: false), .upNext)
        XCTAssertEqual(MusicQueue.title(playlist: nil, isLibrary: false), .upNext)
        XCTAssertEqual(MusicQueue.block(apple(playlist: "音乐"))?.title, .library)
    }

    // MARK: Spotify

    func testSpotifyShowsRecentlyPlayedInTheSameSpot() {
        let block = MusicQueue.block(.init(source: .spotify, isNative: true, recentCount: 12))
        XCTAssertEqual(block?.kind, .recent)
        XCTAssertEqual(block?.title, .recent)
        XCTAssertEqual(block?.content, .rows)
        XCTAssertEqual(block?.allCount, 12)
        let empty = MusicQueue.block(.init(source: .spotify, isNative: true, recentCount: 0))
        XCTAssertEqual(empty?.content, .empty)
        XCTAssertNil(empty?.allCount)
        XCTAssertEqual(MusicQueue.coverSide(empty), 128)
    }

    func testAgoLabels() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertNil(MusicQueue.ago(nil, now: now), "旧记录没有时间")
        XCTAssertEqual(MusicQueue.ago(now.addingTimeInterval(-20), now: now), .justNow)
        XCTAssertEqual(MusicQueue.ago(now.addingTimeInterval(-3 * 60), now: now), .minutes(3))
        XCTAssertEqual(MusicQueue.ago(now.addingTimeInterval(-59 * 60), now: now), .minutes(59))
        XCTAssertEqual(MusicQueue.ago(now.addingTimeInterval(-61 * 60), now: now), .hours(1))
        XCTAssertEqual(MusicQueue.ago(now.addingTimeInterval(-49 * 3600), now: now), .days(2))
        XCTAssertEqual(MusicQueue.ago(now.addingTimeInterval(30), now: now), .justNow, "时钟往回拨")
    }

    func testRecentEntryKeepsWhenItWasPlayedAndOldDataStillDecodes() throws {
        var recent = MusicRecent()
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        recent.record(.init(uri: "spotify:track:a1", title: "A", artist: "B", duration: 200, playedAt: at))
        XCTAssertEqual(MusicRecent.decode(recent.encoded()).entries.first?.playedAt, at)
        let old = #"{"entries":[{"uri":"spotify:track:a1","title":"A","artist":"B","duration":200}]}"#
        let decoded = MusicRecent.decode(Data(old.utf8))
        XCTAssertEqual(decoded.entries.count, 1, "升级前的记录照样读")
        XCTAssertNil(decoded.entries.first?.playedAt)
    }

    // MARK: 延展态

    func testExpandedReadsTwentyFiveCollapsedReadsAFew() {
        XCTAssertEqual(MusicQueue.readLimit(expanded: true), 25)
        XCTAssertEqual(MusicQueue.readLimit(expanded: false), 3)
    }

    func testExpandedPlaceholdersAndTruncation() {
        XCTAssertEqual(MusicQueue.placeholders(loaded: 3, remaining: 24, loading: true), 6, "最多 6 行占位")
        XCTAssertEqual(MusicQueue.placeholders(loaded: 3, remaining: 5, loading: true), 2)
        XCTAssertEqual(MusicQueue.placeholders(loaded: 3, remaining: 24, loading: false), 0)
        XCTAssertEqual(MusicQueue.placeholders(loaded: 25, remaining: 80, loading: true), 0)
        XCTAssertEqual(MusicQueue.truncated(loaded: 25, remaining: 80, loading: false), 55, "只列前 25 首")
        XCTAssertEqual(MusicQueue.truncated(loaded: 24, remaining: 24, loading: false), 0)
        XCTAssertEqual(MusicQueue.truncated(loaded: 3, remaining: 80, loading: true), 0, "读取中不写")
        XCTAssertEqual(MusicQueue.truncated(loaded: 3, remaining: nil, loading: false), 0)
    }

    func testRemainingCountsTheRestOfThePlaylist() {
        XCTAssertEqual(MusicUpNext.remaining(current: 3, count: 27, wrap: false), 24)
        XCTAssertEqual(MusicUpNext.remaining(current: 27, count: 27, wrap: false), 0)
        XCTAssertEqual(MusicUpNext.remaining(current: 27, count: 27, wrap: true), 26)
        XCTAssertEqual(MusicUpNext.remaining(current: 0, count: 27, wrap: true), 0)
    }

    /// 收起态内容底约 520，离 550 视口底部的 18pt 渐隐带（532 起）至少 12pt；延展态
    /// 吸顶 198 加列表 346 不超过 550。照效果图 A_collapsed / A_expanded 逐项累加。
    func testLayoutStaysOutOfTheFadeBand() {
        let rows = CGFloat(MusicQueue.collapsedRows) * MusicQueue.collapsedRowHeight + MusicQueue.rowsInset * 2
        let collapsed: CGFloat = 16 + 32 + 12 + MusicQueue.coverCompact + 14 + 42 + 12 + 14 + 10 + 52 + 8 + 14
            + 14 + 26 + 6 + rows
        XCTAssertLessThanOrEqual(collapsed, 550 - 18 - 12)
        XCTAssertLessThanOrEqual(198 + MusicQueue.expandedListMax, 550)
        XCTAssertGreaterThanOrEqual(MusicQueue.collapsedRowHeight, 36, "整行可点，行高至少 36")
        XCTAssertGreaterThanOrEqual(MusicQueue.minHitHeight, 28)
        XCTAssertEqual(MusicQueue.listHeight(rows: 3), 3 * 44 + 4)
        XCTAssertEqual(MusicQueue.listHeight(rows: 25), MusicQueue.expandedListMax, "再多在列表区内滚")
        XCTAssertEqual(MusicQueue.listHeight(rows: 2, footer: 50), 2 * 44 + 4 + 50)
        XCTAssertEqual(MusicQueue.listHeight(rows: 0, footer: 50), 50)
    }
}
