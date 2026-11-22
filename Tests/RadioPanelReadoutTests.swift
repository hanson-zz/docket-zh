import Foundation
import XCTest

/// 收音机面板的紧凑头部（CH 03 / 06、HLS · 网络直播）、收藏数、插画资源名、
/// 画廊列数，以及九套外观浅深两版的配色。
final class RadioPanelReadoutTests: XCTestCase {

    func testChannelFollowsTheTunedStationAndTheFavouriteCount() {
        XCTAssertEqual(RadioPanelReadout.channel(index: 2, count: 6).current, "03")
        XCTAssertEqual(RadioPanelReadout.channel(index: 2, count: 6).total, "06")
        XCTAssertEqual(RadioPanelReadout.channel(index: 0, count: 1).total, "01")
        XCTAssertEqual(RadioPanelReadout.channel(index: 9, count: 3).current, "03", "越界夹到最后一台")
        XCTAssertEqual(RadioPanelReadout.channel(index: 0, count: 0).current, "--")
        XCTAssertEqual(RadioPanelReadout.channel(index: 0, count: 0).total, "00")
    }

    func testStreamLineReadsTheStationItself() {
        let hls = RadioStation(name: "音乐之声", url: "https://example.com/live/index.m3u8", codec: "HLS")
        XCTAssertEqual(RadioPanelReadout.streamLine(hls), "HLS · 网络直播")
        let mp3 = RadioStation(name: "动感 101", url: "https://example.com/64k.mp3", codec: "MP3", bitrate: 64)
        XCTAssertEqual(RadioPanelReadout.streamLine(mp3), "MP3 · 64 kbps · 网络直播")
        let guessed = RadioStation(name: "某台", url: "https://example.com/live/index.m3u8")
        XCTAssertEqual(RadioPanelReadout.streamLine(guessed), "HLS · 网络直播", "没存格式时按地址认")
        let unknown = RadioStation(name: "某台", url: "https://example.com/stream", codec: "unknown")
        XCTAssertEqual(RadioPanelReadout.streamLine(unknown), "网络直播")
        XCTAssertNil(RadioPanelReadout.streamLine(nil))
    }

    func testCountsArtAndGallery() {
        XCTAssertEqual(RadioPanelReadout.stationCount(6), "6 个电台")
        XCTAssertEqual(RadioPanelReadout.stationCount(-1), "0 个电台")
        XCTAssertEqual(RadioPanelReadout.artName(.porcelain), "radio-art-porcelain")
        XCTAssertEqual(RadioPanelReadout.galleryColumns(width: 288), 3)
        XCTAssertEqual(RadioPanelReadout.galleryColumns(width: 120), 2, "再窄也至少两格")
        XCTAssertEqual(RadioPanelReadout.galleryColumns(width: 900), 4)
    }

    func testRenamedTitlesKeepTheStoredValues() {
        XCTAssertEqual(RadioSkin.allCases.map(\.title),
                       ["经典调谐", "木壳电子管", "复古便携", "数码卡座", "烟晶玻璃", "琥珀点阵", "白瓷转盘",
                        "掌机像素", "黑白刻度"])
        XCTAssertEqual(RadioSkin.allCases.map(\.rawValue),
                       ["classic", "wood", "transistor", "deck", "smoke", "led", "porcelain", "pixel", "ruler"])
        XCTAssertEqual(RadioSkin(stored: "transistor"), .transistor, "旧配置照常读")
        XCTAssertEqual(RadioSkin(stored: "ruler"), .ruler)
    }

    func testEveryLookHasALightAndADarkVersionThatReads() {
        for skin in RadioSkin.allCases {
            let dark = RadioSkinPalette.look(skin, tone: .dark)
            let light = RadioSkinPalette.look(skin, tone: .light)
            XCTAssertFalse(dark.isLight, "\(skin) 深色版底色是深的")
            XCTAssertTrue(light.isLight, "\(skin) 浅色版底色是浅的")
            for p in [dark, light] {
                XCTAssertGreaterThanOrEqual(p.minimumContrast, 4.5, "\(skin)")
                XCTAssertFalse(p.ink.isLight, "\(skin) 实心按钮深色字")
            }
            if let modern = RadioSkinPalette.palette(skin, tone: .light) {
                XCTAssertEqual(modern, light, "\(skin) 新外观照旧用自己的配色")
            }
        }
    }
}
