import Foundation
import XCTest

/// 网络活动面板的纯逻辑：单位、今天累计、nettop 输出、排前 5、本机 IP、网络名。
final class NetworkUsageTests: XCTestCase {
    // MARK: 单位

    func testUnitDefaultsToBytesAndReadsBits() {
        XCTAssertEqual(NetworkRateUnit.from(WidgetConfig()), .bytes)
        XCTAssertEqual(NetworkRateUnit.from(WidgetConfig(["unit": .string("bits")])), .bits)
        XCTAssertEqual(NetworkRateUnit.from(WidgetConfig(["unit": .string("乱写")])), .bytes)
        XCTAssertEqual(NetworkRateUnit.bytes.label, "MB/s")
        XCTAssertEqual(NetworkRateUnit.bits.label, "Mbps")
    }

    func testBytesFormatMatchesTheOldTile() {
        XCTAssertEqual(NetworkRateFormat.format(0, unit: .bytes).value, "0")
        XCTAssertEqual(NetworkRateFormat.format(0, unit: .bytes).unit, "KB/s")
        XCTAssertEqual(NetworkRateFormat.format(999 * 1024, unit: .bytes).value, "999")
        XCTAssertEqual(NetworkRateFormat.format(12.4 * 1024 * 1024, unit: .bytes).value, "12.4")
        XCTAssertEqual(NetworkRateFormat.format(12.4 * 1024 * 1024, unit: .bytes).unit, "MB/s")
    }

    func testBitsFormat() {
        // 12.375 MB/s（十进制）就是 99 Mbps。
        XCTAssertEqual(NetworkRateFormat.text(12_375_000, unit: .bits), "99.0 Mbps")
        XCTAssertEqual(NetworkRateFormat.text(800_000, unit: .bits), "6.4 Mbps")
        XCTAssertEqual(NetworkRateFormat.text(117_500_000, unit: .bits), "940 Mbps")
        XCTAssertEqual(NetworkRateFormat.text(50_000, unit: .bits), "400 Kbps")
        XCTAssertEqual(NetworkRateFormat.text(-5, unit: .bits), "0 Kbps")
        XCTAssertEqual(NetworkRateFormat.text(.nan, unit: .bits), "0 Kbps")
    }

    func testByteTotals() {
        XCTAssertEqual(NetworkByteFormat.text(0), "0 KB")
        XCTAssertEqual(NetworkByteFormat.text(410 * 1024 * 1024), "410 MB")
        XCTAssertEqual(NetworkByteFormat.text(3_435_973_837), "3.2 GB")
    }

    // MARK: 今天累计

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    func testTotalsAddUpWithinADay() {
        var totals = NetworkDayTotals()
        totals = totals.adding(download: 100, upload: 10, at: date(20, 9), calendar: calendar)
        totals = totals.adding(download: 50, upload: 5, at: date(20, 23, 59), calendar: calendar)
        XCTAssertEqual(totals.day, "2026-10-20")
        XCTAssertEqual(totals.download, 150)
        XCTAssertEqual(totals.upload, 15)
    }

    func testTotalsResetAtMidnight() {
        let yesterday = NetworkDayTotals(day: "2026-10-20", download: 9_000, upload: 900)
        let next = yesterday.adding(download: 7, upload: 3, at: date(21, 0, 0), calendar: calendar)
        XCTAssertEqual(next, NetworkDayTotals(day: "2026-10-21", download: 7, upload: 3))
        // 过了零点还没采样：面板显示 0，不显示昨天的。
        XCTAssertEqual(yesterday.shown(at: date(21, 0, 5), calendar: calendar).download, 0)
        XCTAssertEqual(yesterday.shown(at: date(20, 22), calendar: calendar).download, 9_000)
    }

    func testTotalsSurviveARestartAndBadData() {
        let saved = NetworkDayTotals(day: "2026-10-20", download: 123, upload: 45)
        XCTAssertEqual(NetworkDayTotals.decode(saved.encoded()), saved)
        XCTAssertEqual(NetworkDayTotals.decode(nil), NetworkDayTotals())
        XCTAssertEqual(NetworkDayTotals.decode(Data("不是 JSON".utf8)), NetworkDayTotals())
        XCTAssertEqual(NetworkDayTotals.decode(Data("{\"day\":\"2026-10-20\"}".utf8)).download, 0)
    }

    func testTotalsDoNotOverflow() {
        let full = NetworkDayTotals(day: "2026-10-20", download: .max - 1, upload: 0)
        XCTAssertEqual(full.adding(download: 10, upload: 0, at: date(20, 12), calendar: calendar).download, .max)
    }

    // MARK: nettop

    private let twoBlocks = """
    time,,bytes_in,bytes_out,
    12:00:00.100000,launchd.1,0,0,
    12:00:00.100000,Google Chrome H.812,1000,200,
    12:00:00.100000,com.apple.WebKi.433,500,500,
    12:00:00.100000,mDNSResponder.188,10,10,
    time,,bytes_in,bytes_out,
    12:00:01.100000,launchd.1,0,0,
    12:00:01.100000,Google Chrome H.812,6001000,10200,
    12:00:01.100000,com.apple.WebKi.433,1500,700,
    12:00:01.100000,mDNSResponder.188,10,10,
    12:00:01.100000,newcomer.999,99999,0,
    """

    func testParsesEachSampleBlock() {
        let blocks = NettopParser.parse(twoBlocks)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].count, 4)
        XCTAssertEqual(blocks[1].count, 5)
        XCTAssertEqual(blocks[1][1], NettopSample(name: "Google Chrome H", pid: 812, bytesIn: 6_001_000, bytesOut: 10_200))
    }

    func testRatesAreTheDifferenceAndSkipNewcomers() {
        guard let rates = NettopParser.rates(output: twoBlocks) else { return XCTFail("应该读得出") }
        let chrome = rates.first { $0.pid == 812 }
        XCTAssertEqual(chrome?.download, 6_000_000)
        XCTAssertEqual(chrome?.upload, 10_000)
        XCTAssertNil(rates.first { $0.pid == 999 }, "第一次没有的进程不知道之前收了多少，不算")
    }

    func testSingleHeaderSplitsByTimestamp() {
        let output = """
        time,,bytes_in,bytes_out,
        12:00:00.1,a.1,10,0,
        12:00:00.1,b.2,10,0,
        12:00:01.1,a.1,30,0,
        12:00:01.1,b.2,15,0,
        """
        let blocks = NettopParser.parse(output)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(NettopParser.rates(output: output)?.map(\.download), [20, 5])
    }

    func testUnreadableOutputIsNil() {
        XCTAssertNil(NettopParser.rates(output: ""))
        XCTAssertNil(NettopParser.rates(output: "nettop: illegal option -- t\nusage: nettop ..."))
        // 只有一次采样也算不出速度。
        XCTAssertNil(NettopParser.rates(output: "time,,bytes_in,bytes_out,\n1,a.1,1,1,"))
    }

    func testCounterGoingBackwardsIsZero() {
        let rates = NettopParser.rates(from: [NettopSample(name: "a", pid: 1, bytesIn: 100, bytesOut: 100)],
                                       to: [NettopSample(name: "a", pid: 1, bytesIn: 50, bytesOut: 150)],
                                       interval: 1)
        XCTAssertEqual(rates.first?.download, 0)
        XCTAssertEqual(rates.first?.upload, 50)
        XCTAssertTrue(NettopParser.rates(from: [], to: [], interval: 0).isEmpty)
    }

    func testProcessNamesWithDots() {
        XCTAssertEqual(NettopParser.splitProcess("com.apple.WebKi.433")?.name, "com.apple.WebKi")
        XCTAssertEqual(NettopParser.splitProcess("com.apple.WebKi.433")?.pid, 433)
        XCTAssertNil(NettopParser.splitProcess("nodot"))
        XCTAssertNil(NettopParser.splitProcess(".12"))
        XCTAssertNil(NettopParser.splitProcess("name.abc"))
    }

    // MARK: 排前 5

    func testTopMergesHelpersAndKeepsFive() {
        var rates = [
            ProcessNetRate(name: "Chrome H", pid: 10, download: 100, upload: 0),
            ProcessNetRate(name: "Chrome", pid: 11, download: 50, upload: 10),
            ProcessNetRate(name: "idle", pid: 12, download: 0, upload: 0),
        ]
        for i in 0..<6 {
            rates.append(ProcessNetRate(name: "p\(i)", pid: Int32(20 + i), download: Double(i + 1), upload: 0))
        }
        let top = NetAppRanking.top(rates) { rate in
            rate.pid == 10 || rate.pid == 11 ? ("com.google.Chrome", "Chrome", "com.google.Chrome")
                : (rate.name, rate.name, nil)
        }
        XCTAssertEqual(top.count, 5)
        XCTAssertEqual(top.first?.id, "com.google.Chrome")
        XCTAssertEqual(top.first?.download, 150)
        XCTAssertEqual(top.first?.upload, 10)
        XCTAssertFalse(top.contains { $0.id == "idle" }, "这一秒没流量的不列")
        XCTAssertEqual(top.map(\.id), ["com.google.Chrome", "p5", "p4", "p3", "p2"])
    }

    func testTopOfNothingIsEmpty() {
        XCTAssertTrue(NetAppRanking.top([]) { ($0.name, $0.name, nil) }.isEmpty)
    }

    // MARK: 本机 IP 和网络名

    func testPicksAUsableAddress() {
        XCTAssertEqual(LocalAddress.pick([("utun3", "10.8.0.2"), ("en1", "192.168.1.30"), ("en0", "192.168.1.23")]),
                       "192.168.1.23")
        XCTAssertEqual(LocalAddress.pick([("utun3", "10.8.0.2"), ("en5", "10.0.0.8")]), "10.0.0.8")
        XCTAssertEqual(LocalAddress.pick([("en0", "169.254.3.3"), ("bridge0", "192.168.2.1")]), nil)
        XCTAssertNil(LocalAddress.pick([]))
    }

    func testPlaceNameFallsBackToWiFi() {
        XCTAssertEqual(NetworkPlaceText.name(onWifi: true, ssid: "家里-5G", hasAddress: true), "家里-5G")
        XCTAssertEqual(NetworkPlaceText.name(onWifi: true, ssid: nil, hasAddress: true), "Wi-Fi")
        XCTAssertEqual(NetworkPlaceText.name(onWifi: true, ssid: "  ", hasAddress: false), "Wi-Fi")
        XCTAssertEqual(NetworkPlaceText.name(onWifi: false, ssid: nil, hasAddress: true), "有线网络")
        XCTAssertEqual(NetworkPlaceText.name(onWifi: false, ssid: nil, hasAddress: false), "没有联网")
    }
}

/// 应用音量的预设列表和开会模式。
final class AppVolumeMeetingTests: XCTestCase {
    func testPresetsAddOnceAndCap() {
        var list: [String] = []
        list = AppVolumePresets.adding("com.tencent.xinWeChat", to: list)
        list = AppVolumePresets.adding("com.tencent.xinwechat", to: list)
        list = AppVolumePresets.adding("  ", to: list)
        XCTAssertEqual(list, ["com.tencent.xinWeChat"])
        for i in 0..<20 { list = AppVolumePresets.adding("app.\(i)", to: list) }
        XCTAssertEqual(list.count, AppVolumePresets.limit)
        list = AppVolumePresets.removing("COM.tencent.xinWeChat", from: list)
        XCTAssertFalse(list.contains("com.tencent.xinWeChat"))
        XCTAssertTrue(AppVolumePresets.removing("x", from: []).isEmpty, "删最后一个、删空列表都不出错")
    }

    func testIdlePresetsKeepOrderAndDropPlaying() {
        XCTAssertEqual(AppVolumePresets.idle(pinned: ["a", "b", "c"], playing: ["b"]), ["a", "c"])
    }

    func testPresetsRoundTrip() {
        let list = ["a", "b"]
        XCTAssertEqual(AppVolumePresets.decode(AppVolumePresets.encode(list)), list)
        XCTAssertEqual(AppVolumePresets.decode(nil), [])
        XCTAssertEqual(AppVolumePresets.decode(try? JSONEncoder().encode(["a", "A", ""])), ["a"])
    }

    func testMeetingLowersOthersToThirty() {
        let loud = AppVolumeSetting(percent: 120)
        XCTAssertEqual(MeetingMode.effective(loud, active: true, isMeetingApp: false).percent, 30)
        XCTAssertEqual(MeetingMode.effective(loud, active: true, isMeetingApp: true), loud, "会议 App 不动")
        XCTAssertEqual(MeetingMode.effective(loud, active: false, isMeetingApp: false), loud, "关掉就是原来的")
        // 本来更低、静音的不往上拉。
        XCTAssertEqual(MeetingMode.effective(AppVolumeSetting(percent: 10), active: true, isMeetingApp: false).percent, 10)
        XCTAssertTrue(MeetingMode.effective(AppVolumeSetting(muted: true), active: true, isMeetingApp: false).muted)
        // 没动过的（100%）开会时也要降，所以需要接入。
        XCTAssertTrue(AppVolume.needsTap(MeetingMode.effective(AppVolumeSetting(), active: true, isMeetingApp: false)))
    }

    func testMeetingOverrideWins() {
        let override = AppVolumeSetting(percent: 80)
        XCTAssertEqual(MeetingMode.effective(AppVolumeSetting(), active: true, isMeetingApp: false,
                                             override: override), override)
        XCTAssertEqual(MeetingMode.effective(AppVolumeSetting(), active: false, isMeetingApp: false,
                                             override: override), AppVolumeSetting(), "开会结束临时值不起作用")
        XCTAssertTrue(MeetingMode.editsOverride(active: true, isMeetingApp: false))
        XCTAssertFalse(MeetingMode.editsOverride(active: true, isMeetingApp: true))
        XCTAssertFalse(MeetingMode.editsOverride(active: false, isMeetingApp: false))
    }

    func testMeetingAppList() {
        XCTAssertTrue(MeetingMode.isMeetingApp("us.zoom.xos"))
        XCTAssertTrue(MeetingMode.isMeetingApp("COM.TENCENT.MEETING"))
        XCTAssertTrue(MeetingMode.isMeetingApp("com.tencent.xinWeChat"), "微信语音视频通话不降低")
        XCTAssertFalse(MeetingMode.isMeetingApp("com.tencent.xinWeChat", custom: ["com.tencent.xinWeChat": false]))
        XCTAssertFalse(MeetingMode.isMeetingApp("com.apple.Music"))
        XCTAssertTrue(MeetingMode.isMeetingApp("com.apple.Music", custom: ["com.apple.Music": true]))
        XCTAssertFalse(MeetingMode.isMeetingApp("us.zoom.xos", custom: ["us.zoom.xos": false]))
        XCTAssertEqual(MeetingMode.decodeCustom(MeetingMode.encodeCustom(["a": true])), ["a": true])
        XCTAssertEqual(MeetingMode.decodeOverrides(MeetingMode.encodeOverrides(["a": AppVolumeSetting(percent: 100)]))["a"]?.percent,
                       100, "临时值拖回 100% 也要记住")
    }

    func testPresetCaption() {
        XCTAssertEqual(AppVolumeText.preset(AppVolumeSetting(muted: true)), "没在出声 · 预设静音")
        XCTAssertEqual(AppVolumeText.preset(AppVolumeSetting(percent: 40)), "没在出声 · 预设 40%")
        XCTAssertEqual(AppVolumeText.preset(AppVolumeSetting()), "没在出声 · 原音量")
        XCTAssertEqual(AppVolumeText.meetingCaption(active: false), "除会议 App 外降到 30%")
    }
}
