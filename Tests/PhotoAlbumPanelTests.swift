import XCTest

/// 相册面板分标准、宽幅之后的规则：标题、显示方式、序号和倒计时、照片下沿的字段、
/// 预览张数、缩略图菜单、空状态，以及老配置的兼容。
final class PhotoAlbumPanelTests: XCTestCase {

    // MARK: 样式和标题

    func testLayoutReadsTheOldKeyAndDefaultsToStandard() {
        XCTAssertEqual(PhotoAlbumPanel.layout(WidgetConfig()), .standard)
        XCTAssertEqual(PhotoAlbumPanel.layout(WidgetConfig(["layout": .string("wide")])), .wide)
        XCTAssertEqual(PhotoAlbumPanel.layout(WidgetConfig(["layout": .string("??")])), .standard)
        XCTAssertEqual(PhotoAlbumPanel.title(.standard), "相册 · 标准")
        XCTAssertEqual(PhotoAlbumPanel.title(.wide), "相册 · 宽幅")
    }

    // MARK: 显示方式

    func testFitDefaultsToWholePictureAndReadsOldSpellings() {
        XCTAssertEqual(PhotoAlbumPanel.fit(WidgetConfig()), .fit)
        XCTAssertEqual(PhotoAlbumPanel.fit(WidgetConfig(["fit": .string("fill")])), .fill)
        XCTAssertEqual(PhotoAlbumPanel.fit(WidgetConfig(["fit": .string("Crop")])), .fill)
        XCTAssertEqual(PhotoAlbumPanel.fit(WidgetConfig(["fit": .string("contain")])), .fit)
        XCTAssertEqual(PhotoAlbumPanel.fit(WidgetConfig(["fit": .bool(true)])), .fill)
        XCTAssertEqual(PhotoAlbumPanel.fit(WidgetConfig(["fit": .number(3)])), .fit)
        XCTAssertEqual(PhotoAlbumPanel.Fit.allCases.map(PhotoAlbumPanel.fitTitle), ["完整显示", "铺满裁切"])
    }

    // MARK: 设置迁移

    func testOldConfigReadsWithDefaults() {
        let old = WidgetConfig(["layout": .string("wide"), "folder": .string(""), "interval": .number(30)])
        let settings = PhotoAlbumPanel.settings(old)
        XCTAssertEqual(settings.layout, .wide)
        XCTAssertEqual(settings.fit, .fit)
        XCTAssertEqual(settings.interval, 30)
        XCTAssertFalse(settings.shuffle)
        XCTAssertTrue(settings.memoriesFirst)
    }

    func testIntervalStoredAsTextIsReadAndClamped() {
        XCTAssertEqual(PhotoAlbumPanel.interval(WidgetConfig(["interval": .string("600")])), 600)
        XCTAssertEqual(PhotoAlbumPanel.interval(WidgetConfig(["interval": .string("1")])), 5)
        XCTAssertEqual(PhotoAlbumPanel.interval(WidgetConfig(["interval": .string("abc")])), PhotoRotation.defaultInterval)
        XCTAssertEqual(PhotoAlbumPanel.interval(WidgetConfig(["interval": .number(3_600)])), 3_600)
    }

    func testMigrateNormalisesOnlyTheKeysItOwns() {
        var config = WidgetConfig(["fit": .string("crop"), "interval": .string("60"),
                                   "anchor": .string("/p/a.jpg"), "excluded": .list([.string("/p/b.jpg")])])
        XCTAssertTrue(PhotoAlbumPanel.migrate(&config))
        XCTAssertEqual(config.string("fit"), "fill")
        XCTAssertEqual(config.double("interval"), 60)
        XCTAssertEqual(config.string("anchor"), "/p/a.jpg")
        XCTAssertEqual(config.strings("excluded"), ["/p/b.jpg"])
        XCTAssertFalse(PhotoAlbumPanel.migrate(&config))

        var untouched = WidgetConfig(["layout": .string("standard")])
        XCTAssertFalse(PhotoAlbumPanel.migrate(&untouched))
        XCTAssertNil(untouched.values["fit"])
    }

    // MARK: 序号和倒计时

    func testPositionText() {
        XCTAssertEqual(PhotoAlbumPanel.positionText(index: 11, count: 300), "第 12 / 300 张")
        XCTAssertEqual(PhotoAlbumPanel.positionText(index: 0, count: 1), "第 1 / 1 张")
        XCTAssertEqual(PhotoAlbumPanel.positionText(index: 9, count: 3), "第 3 / 3 张")
        XCTAssertNil(PhotoAlbumPanel.positionText(index: nil, count: 3))
        XCTAssertNil(PhotoAlbumPanel.positionText(index: 0, count: 0))
    }

    func testStatusTextUsesTheRealCountdown() {
        XCTAssertEqual(PhotoAlbumPanel.statusText(paused: true, secondsToNext: nil), "已暂停")
        XCTAssertEqual(PhotoAlbumPanel.statusText(paused: false, secondsToNext: 480), "8 分钟后换下一张")
        XCTAssertNil(PhotoAlbumPanel.statusText(paused: false, secondsToNext: nil))
    }

    // MARK: 照片下沿

    func testCaptionHidesMissingFields() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 9))!
        let thatDay = calendar.date(from: DateComponents(year: 2024, month: 10, day: 18, hour: 15))!
        let other = calendar.date(from: DateComponents(year: 2024, month: 3, day: 2, hour: 15))!

        XCTAssertEqual(PhotoAlbumPanel.caption(date: thatDay, place: "杭州", today: today, calendar: calendar),
                       PhotoAlbumPanel.Caption(onThisDay: true, date: "2024.10.18", place: "杭州"))
        XCTAssertEqual(PhotoAlbumPanel.caption(date: other, place: "  ", today: today, calendar: calendar),
                       PhotoAlbumPanel.Caption(onThisDay: false, date: "2024.03.02", place: nil))
        let none = PhotoAlbumPanel.caption(date: nil, place: nil, today: today, calendar: calendar)
        XCTAssertTrue(none.isEmpty)
        XCTAssertEqual(PhotoAlbumPanel.caption(date: nil, place: "上海", today: today, calendar: calendar),
                       PhotoAlbumPanel.Caption(place: "上海"))
    }

    // MARK: 预览

    func testPreviewCounts() {
        XCTAssertEqual(PhotoAlbumPanel.previewCount(.standard, others: 299), 8)
        XCTAssertEqual(PhotoAlbumPanel.previewCount(.standard, others: 3), 3)
        XCTAssertEqual(PhotoAlbumPanel.previewCount(.wide, others: 299), PhotoAlbumPanel.wideMaxPreviews)
        XCTAssertEqual(PhotoAlbumPanel.previewCount(.wide, others: 5), 5)
        XCTAssertEqual(PhotoAlbumPanel.previewCount(.wide, others: -1), 0)
        XCTAssertEqual(PhotoAlbumPanel.gridColumns * PhotoAlbumPanel.gridRows, PhotoRotation.upcomingCount)
        XCTAssertEqual(PhotoAlbumPanel.wideVisible, 4)
        XCTAssertEqual(PhotoAlbumPanel.stripNext, 2)
    }

    func testWidePreviewSkipsTheStripOnlyWhenThereAreEnough() {
        XCTAssertEqual(PhotoAlbumPanel.widePreviewOffset(others: 20), 2)
        XCTAssertEqual(PhotoAlbumPanel.widePreviewOffset(others: 6), 0)
        XCTAssertEqual(PhotoAlbumPanel.widePreviewOffset(others: 2), 0)
    }

    func testAfterWrapsAndNeverRepeats() {
        let ids = ["a", "b", "c", "d"]
        XCTAssertEqual(PhotoAlbumPanel.after("c", in: ids, count: 8), ["d", "a", "b"])
        XCTAssertEqual(PhotoAlbumPanel.after("a", in: ids, count: 2), ["b", "c"])
        XCTAssertEqual(PhotoAlbumPanel.after(nil, in: ids, count: 2), ["a", "b"])
        XCTAssertEqual(PhotoAlbumPanel.after("a", in: ["a"], count: 4), [])
        XCTAssertEqual(PhotoAlbumPanel.after("a", in: [], count: 4), [])
    }

    // MARK: 缩略图菜单

    func testThumbMenu() {
        XCTAssertEqual(PhotoAlbumPanel.thumbActions(excluded: false, canOpen: true), [.exclude, .open])
        XCTAssertEqual(PhotoAlbumPanel.thumbActions(excluded: true, canOpen: true), [.undo, .open])
        XCTAssertEqual(PhotoAlbumPanel.thumbActions(excluded: false, canOpen: false), [.exclude])
        XCTAssertEqual(PhotoAlbumPanel.ThumbAction.allCases.map(PhotoAlbumPanel.thumbActionTitle),
                       ["排除", "撤销排除", "打开原图"])
    }

    // MARK: 空状态

    func testEmptyReasons() {
        XCTAssertEqual(PhotoAlbumPanel.empty(activeFolders: 0, loading: false, failed: false, denied: false, total: 0),
                       .noFolder)
        XCTAssertEqual(PhotoAlbumPanel.empty(activeFolders: 1, loading: false, failed: true, denied: true, total: 0),
                       .denied)
        XCTAssertEqual(PhotoAlbumPanel.empty(activeFolders: 1, loading: false, failed: true, denied: false, total: 0),
                       .failed)
        XCTAssertEqual(PhotoAlbumPanel.empty(activeFolders: 1, loading: true, failed: false, denied: false, total: 0),
                       .loading)
        XCTAssertEqual(PhotoAlbumPanel.empty(activeFolders: 1, loading: false, failed: false, denied: false, total: 4),
                       .allExcluded)
        XCTAssertEqual(PhotoAlbumPanel.empty(activeFolders: 1, loading: false, failed: false, denied: false, total: 0),
                       .emptyFolder)
        // 文件夹都勾掉了，但照片图库里有往年今天的照片，都排除了。
        XCTAssertEqual(PhotoAlbumPanel.empty(activeFolders: 0, loading: false, failed: false, denied: false, total: 2),
                       .allExcluded)
    }
}
