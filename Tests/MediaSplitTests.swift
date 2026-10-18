import XCTest

/// 音量 / 应用音量 / 正在播放分工，相册宽幅和 AI 任意门竖版。
final class MediaSplitTests: XCTestCase {

    // MARK: 输出设备

    private func device(_ id: UInt32, _ name: String, _ transport: OutputTransport) -> OutputDevice {
        OutputDevice(id: id, uid: "uid-\(id)", name: name, transport: transport)
    }

    func testTransportFromFourCC() {
        XCTAssertEqual(OutputTransport(fourCC: OutputTransport.fourCC("bltn")), .builtIn)
        XCTAssertEqual(OutputTransport(fourCC: OutputTransport.fourCC("blue")), .bluetooth)
        XCTAssertEqual(OutputTransport(fourCC: OutputTransport.fourCC("blea")), .bluetooth)
        XCTAssertEqual(OutputTransport(fourCC: OutputTransport.fourCC("hdmi")), .hdmi)
        XCTAssertEqual(OutputTransport(fourCC: OutputTransport.fourCC("dprt")), .displayPort)
        XCTAssertEqual(OutputTransport(fourCC: OutputTransport.fourCC("airp")), .airPlay)
        XCTAssertEqual(OutputTransport(fourCC: OutputTransport.fourCC("usb ")), .usb)
        XCTAssertEqual(OutputTransport(fourCC: 0), .other)
    }

    func testSymbolsFollowTheDevice() {
        XCTAssertEqual(OutputDevices.symbol(for: device(1, "MacBook Pro 扬声器", .builtIn)), "laptopcomputer")
        XCTAssertEqual(OutputDevices.symbol(for: device(1, "iMac 扬声器", .builtIn)), "desktopcomputer")
        XCTAssertEqual(OutputDevices.symbol(for: device(2, "韩的 AirPods Pro", .bluetooth)), "airpodspro")
        XCTAssertEqual(OutputDevices.symbol(for: device(2, "AirPods Max", .bluetooth)), "airpodsmax")
        XCTAssertEqual(OutputDevices.symbol(for: device(2, "AirPods", .bluetooth)), "airpods")
        XCTAssertEqual(OutputDevices.symbol(for: device(2, "Sony WH-1000XM5", .bluetooth)), "headphones")
        XCTAssertEqual(OutputDevices.symbol(for: device(3, "DELL U2723QE", .hdmi)), "display")
        XCTAssertEqual(OutputDevices.symbol(for: device(4, "客厅", .airPlay)), "airplayaudio")
        XCTAssertEqual(OutputDevices.symbol(for: device(5, "BlackHole 2ch", .virtual)), "waveform")
    }

    func testDevicesSortBuiltInFirst() {
        let list = [device(3, "显示器", .hdmi), device(2, "AirPods Pro", .bluetooth), device(1, "MacBook 扬声器", .builtIn)]
        XCTAssertEqual(OutputDevices.sorted(list).map(\.id), [1, 2, 3])
    }

    func testVisibleKeepsTheCurrentOne() {
        let list = [device(1, "MacBook", .builtIn), device(2, "AirPods", .bluetooth),
                    device(3, "显示器", .hdmi), device(4, "客厅", .airPlay), device(5, "BlackHole", .virtual)]
        let first = OutputDevices.visible(list, current: 2)
        XCTAssertEqual(first.shown.map(\.id), [1, 2, 3])
        XCTAssertEqual(first.overflow, 2)
        let far = OutputDevices.visible(list, current: 5)
        XCTAssertEqual(far.shown.map(\.id), [1, 2, 5], "当前设备排在后面时换掉最后一格")
        XCTAssertEqual(far.overflow, 2)
        let few = OutputDevices.visible(Array(list.prefix(2)), current: nil)
        XCTAssertEqual(few.shown.count, 2)
        XCTAssertEqual(few.overflow, 0)
    }

    func testPercentText() {
        XCTAssertEqual(OutputDevices.percentText(0.584), "58%")
        XCTAssertEqual(OutputDevices.percentText(1.4), "100%")
        XCTAssertEqual(OutputDevices.percentText(.nan), "0%")
    }

    // MARK: 应用音量每一格

    func testStripFractionAndUnity() {
        XCTAssertEqual(AppVolumeStrip.fraction(percent: 150, muted: false), 1)
        XCTAssertEqual(AppVolumeStrip.fraction(percent: 75, muted: false), 0.5)
        XCTAssertEqual(AppVolumeStrip.fraction(percent: 80, muted: true), 0)
        XCTAssertEqual(AppVolumeStrip.unityFraction, 100.0 / 150.0, accuracy: 1e-9)
    }

    func testDragMapsWidthToFullRangeAndSnaps() {
        // 拖过半条（宽 60 拖 30）就是 75 个百分点。
        XCTAssertEqual(AppVolumeStrip.percent(start: 20, dragged: 30, width: 60), 95)
        // 落在 100 附近吸过去。
        XCTAssertEqual(AppVolumeStrip.percent(start: 90, dragged: 4, width: 60), 100)
        XCTAssertEqual(AppVolumeStrip.percent(start: 140, dragged: 100, width: 60), 150)
        XCTAssertEqual(AppVolumeStrip.percent(start: 10, dragged: -100, width: 60), 0)
        XCTAssertEqual(AppVolumeStrip.percent(start: 40, dragged: 10, width: 0), 40)
    }

    func testCellsPutChangedAppsFirst() {
        struct App { var name: String; var changed: Bool }
        let apps = [App(name: "A", changed: false), App(name: "B", changed: false), App(name: "C", changed: false),
                    App(name: "D", changed: false), App(name: "E", changed: true)]
        let cells = AppVolumeStrip.cells(apps) { $0.changed }
        XCTAssertEqual(cells.shown.map(\.name), ["E", "A", "B", "C"])
        XCTAssertFalse(cells.named, "四格只写百分比")
        XCTAssertEqual(cells.more, 1)
        let three = AppVolumeStrip.cells(Array(apps.prefix(3))) { $0.changed }
        XCTAssertTrue(three.named)
        XCTAssertEqual(three.more, 0)
    }

    func testCellLabel() {
        XCTAssertEqual(AppVolumeStrip.label(percent: 80, muted: false), "80%")
        XCTAssertEqual(AppVolumeStrip.label(percent: 80, muted: true), "静音")
    }

    // MARK: 相册宽幅

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func testOnThisDay() {
        let today = date(2026, 10, 18)
        XCTAssertTrue(PhotoMemory.isOnThisDay(date(2024, 10, 18, 9), today: today, calendar: calendar))
        XCTAssertFalse(PhotoMemory.isOnThisDay(date(2026, 10, 18, 9), today: today, calendar: calendar), "今年的不算")
        XCTAssertFalse(PhotoMemory.isOnThisDay(date(2024, 10, 17), today: today, calendar: calendar))
        XCTAssertEqual(PhotoMemory.headline(date: date(2024, 10, 18), today: today, calendar: calendar), "那年今天")
        XCTAssertNil(PhotoMemory.headline(date: date(2024, 3, 1), today: today, calendar: calendar))
    }

    func testDayRangesGoBackYearByYear() {
        let ranges = PhotoMemory.dayRanges(today: date(2026, 10, 18), years: 3, calendar: calendar)
        XCTAssertEqual(ranges.count, 3)
        XCTAssertEqual(ranges[0].start, calendar.date(from: DateComponents(year: 2025, month: 10, day: 18)))
        XCTAssertEqual(ranges[0].end, calendar.date(from: DateComponents(year: 2025, month: 10, day: 19)))
        XCTAssertEqual(ranges[2].start, calendar.date(from: DateComponents(year: 2023, month: 10, day: 18)))
        // 2 月 29 日只在闰年有。
        let leap = PhotoMemory.dayRanges(today: date(2028, 2, 29), years: 8, calendar: calendar)
        XCTAssertEqual(leap.count, 2, "2024 和 2020")
    }

    func testCaptionWithAndWithoutPlace() {
        let shot = date(2024, 10, 18)
        XCTAssertEqual(PhotoMemory.dateText(shot, calendar: calendar), "2024.10.18")
        XCTAssertEqual(PhotoMemory.caption(date: shot, place: "杭州", calendar: calendar), "2024.10.18 · 杭州")
        XCTAssertEqual(PhotoMemory.caption(date: shot, place: nil, calendar: calendar), "2024.10.18")
        XCTAssertEqual(PhotoMemory.caption(date: shot, place: "  ", calendar: calendar), "2024.10.18", "反查失败只写日期")
    }

    func testPlaceNameKeepsTheCity() {
        XCTAssertEqual(PhotoMemory.placeName(cityWithContext: "杭州市, 浙江省"), "杭州市")
        XCTAssertEqual(PhotoMemory.placeName(cityWithContext: "杭州，浙江"), "杭州")
        XCTAssertEqual(PhotoMemory.placeName(cityWithContext: "Kyoto"), "Kyoto")
        XCTAssertNil(PhotoMemory.placeName(cityWithContext: nil))
        XCTAssertNil(PhotoMemory.placeName(cityWithContext: " "))
    }

    func testExifDateAndCoordinates() {
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        let parsed = PhotoMemory.exifDate("2024:10:18 15:42:07", timeZone: zone)
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        XCTAssertEqual(parsed, c.date(from: DateComponents(year: 2024, month: 10, day: 18, hour: 15, minute: 42, second: 7)))
        XCTAssertNil(PhotoMemory.exifDate("0000:00:00 00:00:00", timeZone: zone))
        XCTAssertNil(PhotoMemory.exifDate("not a date", timeZone: zone))
        XCTAssertEqual(PhotoMemory.coordinate(30.25, ref: "N", isLatitude: true), 30.25)
        XCTAssertEqual(PhotoMemory.coordinate(120.16, ref: "W", isLatitude: false), -120.16)
        XCTAssertNil(PhotoMemory.coordinate(200, ref: "E", isLatitude: false))
        XCTAssertNil(PhotoMemory.coordinate(nil, ref: "N", isLatitude: true))
    }

    func testDots() {
        XCTAssertEqual(PhotoMemory.dot(index: 1, count: 3), 1)
        XCTAssertEqual(PhotoMemory.dot(index: 0, count: 20), 0)
        XCTAssertEqual(PhotoMemory.dot(index: 19, count: 20), 4)
        XCTAssertEqual(PhotoMemory.dot(index: 0, count: 1), 0)
    }

    // MARK: AI 任意门竖版

    func testSquareKeepsItsWidthAndHasAFixedColumn() {
        XCTAssertEqual(AIServices.tileWidth(count: 3, square: true), 108)
        XCTAssertEqual(AIServices.columnHeight(count: 1, square: true), AIServices.squareColumnHeight)
        XCTAssertEqual(AIServices.columnHeight(count: 8, square: true), AIServices.squareColumnHeight,
                       "竖版没有字牌，高度不跟着字牌数变")
    }

    // MARK: 旧卡片不变样

    func testPlacedCardsKeepTheirStylesAndSizes() {
        let mini = WidgetCatalog.make(.music, overrides: ["mini": .bool(true)])!
        XCTAssertEqual(WidgetCatalog.naturalSize(mini).width, 64)
        let wide = WidgetCatalog.make(.photos, overrides: ["layout": .string("wide")])!
        XCTAssertEqual(WidgetCatalog.naturalSize(wide).width, 176)
        XCTAssertEqual(WidgetCatalog.naturalSize(WidgetCatalog.make(.volume)!).width, 200)
        XCTAssertEqual(WidgetCatalog.naturalSize(WidgetCatalog.make(.appVolume)!).width, 196)
    }

    func testLibraryNotesSplitTheThreeSoundCards() {
        XCTAssertEqual(WidgetLibraryGroups.note(.volume), "换输出设备和总音量")
        XCTAssertEqual(WidgetLibraryGroups.note(.appVolume), "每个应用各调各的")
        XCTAssertEqual(WidgetLibraryGroups.note(.music), "只管这首歌")
    }
}
