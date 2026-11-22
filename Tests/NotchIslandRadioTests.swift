import Foundation
import XCTest

/// 刘海小岛电台卡片：插画按所选外观、台号和电台面板同一套。
final class NotchIslandRadioTests: XCTestCase {
    private let a = RadioStation(id: "a", name: "音乐之声", url: "https://example.com/a.m3u8")
    private let b = RadioStation(id: "b", name: "经典 947", url: "https://example.com/b.mp3",
                                 backups: ["https://backup.example.com/b.mp3"])
    private let c = RadioStation(id: "c", name: "中国之声", url: "https://example.com/c.aac")

    func testSkinReadsTheRadioWidgetConfig() {
        XCTAssertEqual(NotchIslandRadio.skin(nil), .classic, "读不到小组件配置用经典")
        XCTAssertEqual(NotchIslandRadio.skin(WidgetConfig()), .classic)
        XCTAssertEqual(NotchIslandRadio.skin(WidgetConfig([RadioSkin.key: .string("pixel")])), .pixel)
        XCTAssertEqual(NotchIslandRadio.skin(WidgetConfig([RadioSkin.key: .string("bogus")])), .classic)
    }

    func testArtNamesFallBackToMeow() {
        XCTAssertEqual(NotchIslandRadio.artNames(.wood), ["radio-art-wood", "RadioMeow"])
        for skin in RadioSkin.allCases {
            XCTAssertEqual(NotchIslandRadio.artNames(skin).first, RadioPanelReadout.artName(skin))
            XCTAssertEqual(NotchIslandRadio.artNames(skin).last, NotchIslandRadio.fallbackArtName)
        }
        XCTAssertTrue(NotchIslandRadio.pixelated(.pixel), "掌机像素最近邻缩放")
        XCTAssertFalse(RadioSkin.allCases.filter { $0 != .pixel }.contains(where: NotchIslandRadio.pixelated))
    }

    func testChannelFollowsThePlayingStation() {
        let list = [a, b, c]
        XCTAssertEqual(NotchIslandRadio.index(of: b, in: list, stored: 0), 1, "按正在放的那台找")
        var moved = b
        moved.url = "https://backup.example.com/b.mp3"
        XCTAssertEqual(NotchIslandRadio.index(of: moved, in: list, stored: 0), 1, "换到备用地址也认得")
        let other = RadioStation(id: "x", name: "别处", url: "https://example.com/x.mp3")
        XCTAssertEqual(NotchIslandRadio.index(of: other, in: list, stored: 2), 2, "找不到用存的序号")
        XCTAssertEqual(NotchIslandRadio.index(of: nil, in: list, stored: 9), 2, "越界夹到最后一台")
        XCTAssertEqual(NotchIslandRadio.index(of: a, in: [], stored: 3), 0)

        let parts = NotchIslandRadio.channel(of: c, in: list, stored: 0)
        XCTAssertEqual(parts.current, "03")
        XCTAssertEqual(parts.total, "03")
        XCTAssertEqual(NotchIslandRadio.channel(of: nil, in: [], stored: 0).current, "--")
        XCTAssertEqual(NotchIslandRadio.spokenChannel(of: b, in: list, stored: 0), RadioDial.channelOfTotal(1, count: 3))
        XCTAssertEqual(NotchIslandRadio.spokenChannel(of: b, in: [], stored: 0), "")
    }
}
