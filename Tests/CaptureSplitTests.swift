import Foundation
import XCTest

/// 截图工具、最近截图、取色器分工后的纯逻辑：四个动作、文件名、录屏计时、
/// 大图加四格的排法，以及取色器和快速开关共用的取色历史。
final class CaptureSplitTests: XCTestCase {
    // MARK: 截图工具

    func testFourActionsInOrder() {
        XCTAssertEqual(CaptureAction.allCases, [.region, .window, .text, .record])
        XCTAssertEqual(CaptureAction.allCases.map(\.title), ["截区域", "截窗口", "识字", "录屏"])
        XCTAssertEqual(Set(CaptureAction.allCases.map(\.symbol)).count, 4)
    }

    func testTextIsTheQuickToggleProTool() {
        XCTAssertEqual(CaptureAction.text.quickToggle, .textCapture)
        XCTAssertNil(CaptureAction.region.quickToggle)
        XCTAssertNil(CaptureAction.record.quickToggle)
    }

    func testFileNamesAreRecognisedAsCaptures() {
        let date = Date(timeIntervalSince1970: 1_760_791_692) // 2025-10-18 12:48:12 UTC
        let utc = TimeZone(identifier: "UTC")!
        let shot = CaptureFileName.screenshot(at: date, timeZone: utc)
        let movie = CaptureFileName.recording(at: date, timeZone: utc)
        XCTAssertEqual(shot, "截屏2025-10-18 12.48.12.png")
        XCTAssertEqual(movie, "录屏2025-10-18 12.48.12.mov")
        XCTAssertTrue(ScreenshotNaming.looksLikeCapture(shot))
        XCTAssertTrue(ScreenshotNaming.looksLikeCapture(movie))
    }

    func testRecordingClock() {
        XCTAssertEqual(RecordingClock.text(0), "0:00")
        XCTAssertEqual(RecordingClock.text(7.9), "0:07")
        XCTAssertEqual(RecordingClock.text(754), "12:34")
        XCTAssertEqual(RecordingClock.text(3723), "1:02:03")
        XCTAssertEqual(RecordingClock.text(-5), "0:00")
        XCTAssertEqual(RecordingClock.text(.nan), "0:00")
    }

    // MARK: 最近截图

    func testStripLayout() {
        XCTAssertEqual(RecentShots.strip(count: 0), .init(hero: false, thumbs: 0, more: 0))
        XCTAssertEqual(RecentShots.strip(count: 1), .init(hero: true, thumbs: 0, more: 0))
        XCTAssertEqual(RecentShots.strip(count: 3), .init(hero: true, thumbs: 2, more: 0))
        XCTAssertEqual(RecentShots.strip(count: 5), .init(hero: true, thumbs: 4, more: 0))
        // 六张：大图一张，三格缩略图，最后一格写 +2。
        XCTAssertEqual(RecentShots.strip(count: 6), .init(hero: true, thumbs: 3, more: 2))
        XCTAssertEqual(RecentShots.strip(count: 60), .init(hero: true, thumbs: 3, more: 56))
    }

    func testStripNeverOverflowsTheFourSlots() {
        for count in 0...80 {
            let plan = RecentShots.strip(count: count)
            XCTAssertLessThanOrEqual(plan.thumbs + (plan.more > 0 ? 1 : 0), RecentShots.slots)
            XCTAssertEqual((plan.hero ? 1 : 0) + plan.thumbs + plan.more, count)
        }
    }

    // MARK: 取色历史

    func testDecodeNormalisesAndDropsJunk() {
        XCTAssertEqual(ColorHistory.decode("#ff453a,nope,0A84FF,#FF453A,"), ["#FF453A", "#0A84FF"])
        XCTAssertEqual(ColorHistory.decode(""), [])
        XCTAssertEqual(ColorHistory.encode(["#ff453a", "bad", "#30d158"]), "#FF453A,#30D158")
    }

    func testOldCardColoursSurviveTheUpgrade() {
        // 升级前卡片自己存着三种颜色，共享历史还是空的：一个不少。
        let legacy = ["#FF453A", "#0A84FF", "#FFD60A"]
        XCTAssertEqual(ColorHistory.merged(shared: [], legacy: legacy).map(\.hex), legacy)
    }

    func testQuickToggleColoursShowFirstOnTheCard() {
        // 快速开关取了一个绿色，又取了一个卡片上本来就有的蓝色。
        var raw = ColorHistory.adding(ColorCode(hex: "#30D158")!, to: "")
        raw = ColorHistory.adding(ColorCode(hex: "#0A84FF")!, to: raw)
        let shown = ColorHistory.merged(shared: ColorHistory.decode(raw),
                                        legacy: ["#FF453A", "#0A84FF"]).map(\.hex)
        XCTAssertEqual(shown, ["#0A84FF", "#30D158", "#FF453A"])
    }

    func testPickingFromTheCardFoldsItsOldColoursIn() {
        let raw = ColorHistory.adding(ColorCode(hex: "#BF5AF2")!, to: "#30D158",
                                      legacy: ["#FF453A", "#30D158"])
        XCTAssertEqual(ColorHistory.decode(raw), ["#BF5AF2", "#30D158", "#FF453A"])
    }

    func testHistoryIsCapped() {
        var raw = ""
        for i in 0..<20 {
            raw = ColorHistory.adding(ColorCode(red: Double(i) / 20, green: 0, blue: 0), to: raw)
        }
        XCTAssertEqual(ColorHistory.decode(raw).count, ColorHistory.limit)
        XCTAssertEqual(ColorHistory.merged(shared: ColorHistory.decode(raw),
                                           legacy: ["#123456"]).count, ColorHistory.limit)
    }

    func testRecordWritesTheSharedDefaults() throws {
        let name = "CaptureSplitTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(ColorHistory.stored(in: defaults), "")
        ColorHistory.record(ColorCode(hex: "#FF9F0A")!, in: defaults)
        ColorHistory.record(ColorCode(hex: "#64D2FF")!, legacy: ["#FF453A"], in: defaults)
        XCTAssertEqual(ColorHistory.decode(ColorHistory.stored(in: defaults)),
                       ["#64D2FF", "#FF9F0A", "#FF453A"])
    }

    // MARK: 添加面板里的一句话

    func testLibraryNotesSayWhichDoesWhat() {
        XCTAssertNotNil(WidgetLibraryGroups.note(.capture))
        XCTAssertNotNil(WidgetLibraryGroups.note(.screenshots))
        XCTAssertNotNil(WidgetLibraryGroups.note(.colorPicker))
    }

    func testQuickToggleHelpSaysShortcut() {
        XCTAssertTrue(QuickToggle.textCapture.help.hasPrefix("快捷按钮"))
        XCTAssertTrue(QuickToggle.colorPicker.help.hasPrefix("快捷按钮"))
    }
}
