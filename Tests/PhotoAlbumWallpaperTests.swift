import XCTest

/// 相册轮播（锚点、暂停、排除、多文件夹）和壁纸（收藏、早中晚自动换）的规则。
final class PhotoAlbumWallpaperTests: XCTestCase {

    private let ids = ["a", "b", "c", "d", "e"]
    private func at(_ seconds: Double) -> Date { Date(timeIntervalSinceReferenceDate: seconds) }

    // MARK: 现在是哪张

    func testOldCardsWithoutAnAnchorStillRotateByTheClock() {
        let state = PhotoRotation.State()
        XCTAssertEqual(PhotoRotation.position(at: at(0), order: ids, state: state, interval: 60), 0)
        XCTAssertEqual(PhotoRotation.position(at: at(59), order: ids, state: state, interval: 60), 0)
        XCTAssertEqual(PhotoRotation.position(at: at(60), order: ids, state: state, interval: 60), 1)
        XCTAssertEqual(PhotoRotation.position(at: at(60 * 7), order: ids, state: state, interval: 60), 2)
    }

    func testEmptyListHasNoCurrentPicture() {
        XCTAssertNil(PhotoRotation.position(at: at(100), order: [], state: .init(), interval: 60))
        XCTAssertEqual(PhotoRotation.upcoming(at: at(100), order: [], state: .init(), interval: 60), [])
        XCTAssertEqual(PhotoRotation.upcoming(at: at(100), order: ["a"], state: .init(), interval: 60), [])
    }

    func testNextAndPreviousRestartTheTimerFromNow() {
        var state = PhotoRotation.State(anchor: "b", anchorAt: 1_000)
        XCTAssertEqual(PhotoRotation.current(at: at(1_030), order: ids, state: state, interval: 60), "b")
        state = PhotoRotation.stepped(1, at: at(1_030), order: ids, state: state, interval: 60)
        XCTAssertEqual(state.anchor, "c")
        XCTAssertEqual(PhotoRotation.secondsToNext(at: at(1_030), count: ids.count, state: state, interval: 60), 60)
        state = PhotoRotation.stepped(-1, at: at(1_031), order: ids, state: state, interval: 60)
        XCTAssertEqual(PhotoRotation.current(at: at(1_031), order: ids, state: state, interval: 60), "b")
        // 第一张往前是最后一张。
        state = PhotoRotation.State(anchor: "a", anchorAt: 0)
        state = PhotoRotation.stepped(-1, at: at(10), order: ids, state: state, interval: 60)
        XCTAssertEqual(state.anchor, "e")
    }

    func testPauseHoldsThePictureAndResumeCarriesOnFromIt() {
        var state = PhotoRotation.State(anchor: "a", anchorAt: 0)
        state = PhotoRotation.paused(at: at(130), order: ids, state: state, interval: 60)
        XCTAssertTrue(state.isPaused)
        XCTAssertEqual(PhotoRotation.current(at: at(10_000), order: ids, state: state, interval: 60), "c")
        XCTAssertNil(PhotoRotation.secondsToNext(at: at(10_000), count: ids.count, state: state, interval: 60))
        state = PhotoRotation.resumed(at: at(10_000), order: ids, state: state, interval: 60)
        XCTAssertFalse(state.isPaused)
        XCTAssertEqual(PhotoRotation.current(at: at(10_000), order: ids, state: state, interval: 60), "c")
        XCTAssertEqual(PhotoRotation.current(at: at(10_060), order: ids, state: state, interval: 60), "d")
    }

    func testExcludingAnUpcomingPictureKeepsTheCurrentOneAndItsCountdown() {
        let state = PhotoRotation.State(anchor: "a", anchorAt: 0)
        let now = at(150) // 第 3 张 c，还剩 30 秒
        let anchored = PhotoRotation.reanchored(at: now, order: ids, state: state, interval: 60, removing: "b")
        let after = ids.filter { $0 != "b" }
        XCTAssertEqual(PhotoRotation.current(at: now, order: after, state: anchored, interval: 60), "c")
        XCTAssertEqual(PhotoRotation.secondsToNext(at: now, count: after.count, state: anchored, interval: 60), 30)
    }

    func testExcludingTheCurrentPictureMovesToTheNextOne() {
        let state = PhotoRotation.State(anchor: "c", anchorAt: 0)
        let anchored = PhotoRotation.reanchored(at: at(10), order: ids, state: state, interval: 60, removing: "c")
        XCTAssertEqual(anchored.anchor, "d")
        let only = PhotoRotation.reanchored(at: at(10), order: ["c"], state: state, interval: 60, removing: "c")
        XCTAssertNil(only.anchor)
    }

    func testUpcomingIsTheNextPicturesWithoutRepeats() {
        let state = PhotoRotation.State(anchor: "d", anchorAt: 0)
        XCTAssertEqual(PhotoRotation.upcoming(at: at(1), order: ids, state: state, interval: 60, count: 8),
                       ["e", "a", "b", "c"])
    }

    func testCountdownText() {
        XCTAssertEqual(PhotoRotation.countdownText(480), "8 分钟后换下一张")
        XCTAssertEqual(PhotoRotation.countdownText(450), "8 分钟后换下一张")
        XCTAssertEqual(PhotoRotation.countdownText(12), "12 秒后换下一张")
        XCTAssertEqual(PhotoRotation.countdownText(86_000), "约 23 小时后换下一张")
    }

    func testClockSetBackDoesNotGoNegative() {
        let state = PhotoRotation.State(anchor: "b", anchorAt: 1_000)
        XCTAssertEqual(PhotoRotation.current(at: at(500), order: ids, state: state, interval: 60), "b")
        XCTAssertEqual(PhotoRotation.secondsToNext(at: at(500), count: ids.count, state: state, interval: 60), 560)
    }

    // MARK: 顺序

    func testOrderDropsExcludedAndDuplicatesAndPutsMemoriesFirst() {
        let order = PhotoRotation.order(memories: ["photos:1"], files: ["a", "b", "a", "c"], excluded: ["b"],
                                        shuffle: false, memoriesFirst: true)
        XCTAssertEqual(order, ["photos:1", "a", "c"])
        let without = PhotoRotation.order(memories: ["photos:1"], files: ["a", "b"], excluded: [],
                                          shuffle: false, memoriesFirst: false)
        XCTAssertEqual(without, ["a", "b"])
    }

    func testShuffleIsStableAndRemovalKeepsTheRestInOrder() {
        let files = (0..<40).map { "/p/IMG_\($0).jpg" }
        let one = PhotoRotation.order(memories: [], files: files, excluded: [], shuffle: true, memoriesFirst: true)
        let two = PhotoRotation.order(memories: [], files: files.reversed(), excluded: [], shuffle: true, memoriesFirst: true)
        XCTAssertEqual(one, two)
        XCTAssertNotEqual(one, files)
        XCTAssertEqual(Set(one), Set(files))
        let fewer = PhotoRotation.order(memories: [], files: files, excluded: [one[5]], shuffle: true, memoriesFirst: true)
        XCTAssertEqual(fewer, one.filter { $0 != one[5] })
    }

    // MARK: 配置

    func testStateRoundTripsThroughTheConfig() {
        var config = WidgetConfig()
        XCTAssertEqual(PhotoRotation.state(config), PhotoRotation.State())
        let state = PhotoRotation.State(anchor: "/p/a.jpg", anchorAt: 12_345, pausedAt: 12_400)
        PhotoRotation.write(state, to: &config)
        XCTAssertEqual(PhotoRotation.state(config), state)
        PhotoRotation.write(PhotoRotation.State(anchor: nil, anchorAt: 5), to: &config)
        XCTAssertEqual(PhotoRotation.state(config), PhotoRotation.State(anchor: nil, anchorAt: 5))
    }

    func testIntervalReadsOldValuesAndClamps() {
        XCTAssertEqual(PhotoRotation.interval(WidgetConfig()), PhotoRotation.defaultInterval)
        XCTAssertEqual(PhotoRotation.interval(WidgetConfig(["interval": .number(30)])), 30)
        XCTAssertEqual(PhotoRotation.interval(WidgetConfig(["interval": .number(1)])), 5)
        XCTAssertEqual(PhotoRotation.interval(WidgetConfig(["interval": .number(1e9)])), 86_400)
        XCTAssertEqual(PhotoRotation.choiceIndex(600), 1)
        XCTAssertNil(PhotoRotation.choiceIndex(30))
        XCTAssertEqual(PhotoRotation.intervalChoices.map(PhotoRotation.intervalTitle),
                       ["1 分钟", "10 分钟", "1 小时", "每天"])
    }

    func testFoldersStartWithTheOldFolderAndCanBeAddedRemovedAndUnticked() {
        var config = WidgetConfig(["folder": .string("/old")])
        XCTAssertEqual(PhotoRotation.folders(config), ["/old"])
        XCTAssertTrue(PhotoRotation.addFolder("/new", to: &config))
        XCTAssertTrue(PhotoRotation.addFolder("/new", to: &config))
        XCTAssertEqual(PhotoRotation.folders(config), ["/old", "/new"])
        PhotoRotation.setFolder("/old", on: false, in: &config)
        XCTAssertEqual(PhotoRotation.activeFolders(config), ["/new"])
        // 卡片设置里改的 folder 仍是第一个。
        config.set("folder", .string("/other"))
        XCTAssertEqual(PhotoRotation.folders(config), ["/other", "/new"])
        PhotoRotation.removeFolder("/other", from: &config)
        XCTAssertEqual(PhotoRotation.folders(config), ["/new"])
        XCTAssertEqual(config.string("folder"), "/new")
        PhotoRotation.removeFolder("/new", from: &config)
        XCTAssertEqual(PhotoRotation.folders(config), [""], "去掉最后一个回到“图片”")
    }

    func testFolderLimit() {
        var config = WidgetConfig()
        for index in 1..<PhotoRotation.maxFolders {
            XCTAssertTrue(PhotoRotation.addFolder("/f\(index)", to: &config))
        }
        XCTAssertEqual(PhotoRotation.folders(config).count, PhotoRotation.maxFolders)
        XCTAssertFalse(PhotoRotation.addFolder("/one-more", to: &config))
    }

    func testExcludeRestoreAndRestoreAll() {
        var config = WidgetConfig()
        PhotoRotation.exclude("/a", in: &config)
        PhotoRotation.exclude("/b", in: &config)
        PhotoRotation.exclude("/a", in: &config)
        XCTAssertEqual(PhotoRotation.excluded(config), ["/b", "/a"])
        PhotoRotation.restore("/b", in: &config)
        XCTAssertEqual(PhotoRotation.excluded(config), ["/a"])
        PhotoRotation.restoreAll(in: &config)
        XCTAssertEqual(PhotoRotation.excluded(config), [])
        for index in 0..<(PhotoRotation.maxExcluded + 3) { PhotoRotation.exclude("/x\(index)", in: &config) }
        XCTAssertEqual(PhotoRotation.excluded(config).count, PhotoRotation.maxExcluded)
        XCTAssertEqual(PhotoRotation.excluded(config).first, "/x3")
    }

    // MARK: 壁纸：收藏

    func testFavoritesToggle() {
        var config = WidgetConfig()
        XCTAssertTrue(WallpaperSchedule.toggleFavorite("/w/1.jpg", in: &config))
        XCTAssertTrue(WallpaperSchedule.isFavorite("/w/1.jpg", config))
        XCTAssertTrue(WallpaperSchedule.toggleFavorite("/w/1.jpg", in: &config))
        XCTAssertEqual(WallpaperSchedule.favorites(config), [])
    }

    // MARK: 壁纸：早中晚

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func time(_ hour: Int, _ minute: Int, day: Int = 20) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    func testTimesParseAndDefault() {
        XCTAssertEqual(WallpaperSchedule.minutes("06:30"), 390)
        XCTAssertNil(WallpaperSchedule.minutes("25:00"))
        XCTAssertNil(WallpaperSchedule.minutes("abc"))
        XCTAssertEqual(WallpaperSchedule.text(390), "06:30")
        let stored = WallpaperSchedule.storedMinutes(WidgetConfig(["noonAt": .string("bad")]))
        XCTAssertEqual(stored[.morning], 360)
        XCTAssertEqual(stored[.noon], 720)
        XCTAssertEqual(stored[.evening], 1_140)
    }

    func testSlotIsTheLastTimePassedAndBeforeMorningIsLastEvening() {
        let minutes = WallpaperSchedule.storedMinutes(WidgetConfig())
        let morning = WallpaperSchedule.slot(at: time(10, 23), minutes: minutes, calendar: calendar)
        XCTAssertEqual(morning?.slot, .morning)
        XCTAssertEqual(morning?.key, "2026-10-20 morning")
        XCTAssertEqual(WallpaperSchedule.slot(at: time(12, 0), minutes: minutes, calendar: calendar)?.slot, .noon)
        XCTAssertEqual(WallpaperSchedule.slot(at: time(23, 0), minutes: minutes, calendar: calendar)?.slot, .evening)
        let early = WallpaperSchedule.slot(at: time(5, 59), minutes: minutes, calendar: calendar)
        XCTAssertEqual(early?.slot, .evening)
        XCTAssertEqual(early?.key, "2026-10-19 evening")
    }

    func testFollowingTheSunReplacesMorningAndEveningOnly() {
        let config = WidgetConfig(["followSun": .bool(true)])
        let minutes = WallpaperSchedule.effectiveMinutes(config, sunrise: 370, sunset: 1_060)
        XCTAssertEqual(minutes[.morning], 370)
        XCTAssertEqual(minutes[.noon], 720)
        XCTAssertEqual(minutes[.evening], 1_060)
        let off = WallpaperSchedule.effectiveMinutes(WidgetConfig(), sunrise: 370, sunset: 1_060)
        XCTAssertEqual(off[.morning], 360)
        // 没有定位时照旧用设的时刻。
        XCTAssertEqual(WallpaperSchedule.effectiveMinutes(config, sunrise: nil, sunset: nil)[.evening], 1_140)
    }

    func testPickFixedAndFromFavorites() {
        var config = WidgetConfig(["morningPicture": .string("/w/m.jpg")])
        XCTAssertEqual(WallpaperSchedule.pick(.morning, config: config, current: nil, available: ["/w/m.jpg"], roll: 0),
                       "/w/m.jpg")
        XCTAssertNil(WallpaperSchedule.pick(.morning, config: config, current: nil, available: [], roll: 0),
                     "图片找不到了不换")
        XCTAssertNil(WallpaperSchedule.pick(.noon, config: config, current: nil, available: nil, roll: 0),
                     "这段没设图片不换")
        config.set("autoSource", .string("favorites"))
        XCTAssertNil(WallpaperSchedule.pick(.noon, config: config, current: nil, available: nil, roll: 0),
                     "没有收藏不换")
        config.set("favorites", .list([.string("/w/1.jpg"), .string("/w/2.jpg")]))
        for roll in [0.0, 0.5, 0.99] {
            XCTAssertEqual(WallpaperSchedule.pick(.noon, config: config, current: "/w/1.jpg", available: nil, roll: roll),
                           "/w/2.jpg", "随机不挑现在这张")
        }
        config.set("favorites", .list([.string("/w/1.jpg")]))
        XCTAssertEqual(WallpaperSchedule.pick(.noon, config: config, current: "/w/1.jpg", available: nil, roll: 0.3),
                       "/w/1.jpg")
    }

    // MARK: Pro

    func testWallpaperIsFreeAndAutoChangeIsPro() {
        XCTAssertFalse(ProFeatures.isProKind(.wallpaper))
        let on = WidgetConfig(["autoChange": .bool(true)])
        XCTAssertTrue(ProLicenseGate.wallpaperAutoChangeActive(on, unlocked: true))
        XCTAssertFalse(ProLicenseGate.wallpaperAutoChangeActive(on, unlocked: false), "没解锁不换")
        XCTAssertTrue(on.bool("autoChange"), "配置不改写")
        XCTAssertFalse(ProLicenseGate.wallpaperAutoChangeActive(WidgetConfig(), unlocked: true))
        let placed = WidgetInstance(kind: .wallpaper, config: on)
        XCTAssertFalse(ProLicenseGate.needsLockOverlay(placed, unlocked: false), "不盖锁")
    }
}
