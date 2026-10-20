import CoreGraphics
import Foundation
import XCTest

/// 截图工具的设置（第三批 H2）：截完后、格式、延时、卡片上的按钮，screencapture 的
/// 参数，以及框选区域和延时截窗口的坐标换算。
final class CaptureSettingsTests: XCTestCase {
    // MARK: 默认值和读配置

    func testOldCardsWithoutTheKeysKeepTheirLook() {
        // 升级前放的卡片没存过 after、buttons：照旧存文件，第 4 个按钮还是录屏。
        let options = CaptureOptions(config: WidgetConfig())
        XCTAssertEqual(options.after, .save)
        XCTAssertEqual(options.format, .png)
        XCTAssertEqual(options.delay, 0)
        XCTAssertEqual(CaptureButtons.from(WidgetConfig()), [.region, .window, .text, .record])
        // 老卡片显示前会并上目录默认值，并上后也一样。
        let merged = WidgetConfig().merging(defaults: WidgetCatalog.entry(.capture)!.defaults)
        XCTAssertEqual(CaptureAfter.from(merged), .save)
        XCTAssertEqual(CaptureButtons.from(merged), [.region, .window, .text, .record])
    }

    func testNewCardsAreBothWithRecordRegion() throws {
        let fresh = try XCTUnwrap(WidgetCatalog.make(.capture))
        XCTAssertEqual(CaptureAfter.from(fresh.config), .both)
        XCTAssertEqual(CaptureButtons.from(fresh.config), [.region, .window, .text, .recordRegion])
        XCTAssertEqual(CaptureOptions(config: fresh.config).summary, "截完：存文件 + 拷贝 · PNG")
        var config = WidgetConfig()
        CaptureNewWidget.apply(to: &config)
        XCTAssertEqual(config.string(CaptureAfter.key), "both")
        XCTAssertEqual(config.strings(CaptureButtons.key), ["region", "window", "text", "recordRegion"])
        // 用户改过的值，重启后读回来不被新默认盖掉。
        var edited = fresh.config
        edited.set(CaptureAfter.key, .string("copy"))
        XCTAssertEqual(CaptureAfter.from(edited.merging(defaults: WidgetCatalog.entry(.capture)!.defaults)), .copy)
    }

    func testCatalogDefaultsMatchTheReaders() {
        let defaults = WidgetCatalog.entry(.capture)!.defaults
        XCTAssertEqual(CaptureOptions(config: defaults), CaptureOptions())
        XCTAssertEqual(CaptureButtons.from(defaults), CaptureButtons.defaults)
        XCTAssertEqual(WidgetCatalog.configurableKeys(.capture), ["after", "buttons", "delay", "format"])
    }

    func testJunkValuesFallBack() {
        let config = WidgetConfig([CaptureAfter.key: .string("print"), CaptureFormat.key: .string("gif"),
                                   CaptureDelay.key: .string("7")])
        XCTAssertEqual(CaptureOptions(config: config), CaptureOptions())
        XCTAssertEqual(CaptureOptions(delay: 4).delay, 0)
    }

    func testStoredValuesAreRead() {
        let config = WidgetConfig([CaptureAfter.key: .string("markup"), CaptureFormat.key: .string("jpg"),
                                   CaptureDelay.key: .string("10")])
        let options = CaptureOptions(config: config)
        XCTAssertEqual(options.after, .markup)
        XCTAssertEqual(options.format, .jpg)
        XCTAssertEqual(options.delay, 10)
        XCTAssertEqual(options.summary, "截完：打开标注 · JPG · 10 秒")
        XCTAssertEqual(CaptureOptions(after: .both).summary, "截完：存文件 + 拷贝 · PNG")
    }

    func testWhatEachAfterDoes() {
        XCTAssertFalse(CaptureAfter.copy.savesFile)
        XCTAssertTrue(CaptureAfter.save.savesFile)
        XCTAssertTrue(CaptureAfter.both.savesFile && CaptureAfter.both.copiesAfterSaving)
        XCTAssertFalse(CaptureAfter.save.copiesAfterSaving)
        XCTAssertTrue(CaptureAfter.markup.savesFile && CaptureAfter.markup.opensMarkup)
        XCTAssertEqual(CaptureAfter.allCases.map(\.title), ["存文件", "拷贝", "两者", "标注"])
        XCTAssertEqual(CaptureDelay.choices.map(CaptureDelay.title), ["不延时", "3 秒", "5 秒", "10 秒"])
    }

    // MARK: screencapture 参数

    func testArguments() {
        let png = CaptureOptions()
        XCTAssertEqual(png.arguments(.interactiveRegion, path: "/a.png"), ["-i", "-s", "/a.png"])
        XCTAssertEqual(png.arguments(.interactiveWindow, path: "/a.png"), ["-i", "-W", "/a.png"])
        XCTAssertEqual(png.arguments(.interactiveRegion, path: nil), ["-i", "-s", "-c"])
        let jpg = CaptureOptions(format: .jpg)
        XCTAssertEqual(jpg.arguments(.rect(CaptureRect(x: 10, y: 20, width: 300, height: 200)), path: "/b.jpg"),
                       ["-R", "10,20,300,200", "-t", "jpg", "/b.jpg"])
        XCTAssertEqual(jpg.arguments(.window(4242), path: nil), ["-l4242", "-t", "jpg", "-c"])
        XCTAssertEqual(png.arguments(.fullScreen, path: "/c.png"), ["/c.png"])
    }

    func testFileNameFollowsTheFormat() {
        let date = Date(timeIntervalSince1970: 1_760_791_692)
        let utc = TimeZone(identifier: "UTC")!
        let name = CaptureFileName.screenshot(at: date, timeZone: utc, format: .jpg)
        XCTAssertEqual(name, "截屏2025-10-18 12.48.12.jpg")
        XCTAssertTrue(ScreenshotNaming.looksLikeCapture(name))
        XCTAssertTrue(ListedFile(url: URL(fileURLWithPath: "/x/" + name), date: date).isImage)
    }

    // MARK: 卡片上的按钮

    func testButtonsResolve() {
        XCTAssertEqual(CaptureButtons.resolve(["record", "nope", "record", "text"]), [.record, .text])
        XCTAssertEqual(CaptureButtons.resolve([]), CaptureButtons.defaults)
        XCTAssertEqual(CaptureButtons.resolve(["junk"]), CaptureButtons.defaults)
        XCTAssertEqual(CaptureButtons.resolve(CaptureAction.allCases.map(\.rawValue)).count, CaptureButtons.limit)
    }

    func testTogglingKeepsBetweenOneAndFour() {
        let full = CaptureButtons.defaults
        XCTAssertNil(CaptureButtons.toggling(.recordRegion, in: full), "已满 4 个不能再加")
        XCTAssertEqual(CaptureButtons.toggling(.text, in: full), [.region, .window, .record])
        XCTAssertNil(CaptureButtons.toggling(.region, in: [.region]), "最后一个不能去掉")
        XCTAssertEqual(CaptureButtons.toggling(.record, in: [.region]), [.region, .record])
    }

    func testMoving() {
        let list: [CaptureAction] = [.region, .window, .text]
        XCTAssertEqual(CaptureButtons.moving(.window, by: -1, in: list), [.window, .region, .text])
        XCTAssertEqual(CaptureButtons.moving(.text, by: 1, in: list), list)
        XCTAssertEqual(CaptureButtons.moving(.region, by: -1, in: list), list)
        XCTAssertEqual(CaptureButtons.moving(.record, by: 1, in: list), list)
    }

    // MARK: 坐标

    func testCocoaRectBecomesTopLeft() {
        // 主显示器 1080 高：底边在 100、高 200 的框，顶边离屏幕顶 780。
        let rect = CaptureRect.from(cocoa: CGRect(x: 50, y: 100, width: 400, height: 200), primaryHeight: 1080)
        XCTAssertEqual(rect, CaptureRect(x: 50, y: 780, width: 400, height: 200))
        XCTAssertEqual(rect?.argument, "50,780,400,200")
        // 反着拖出来的框也一样。
        XCTAssertEqual(CaptureRect.from(cocoa: CGRect(x: 450, y: 300, width: -400, height: -200), primaryHeight: 1080),
                       rect)
        // 主显示器上方的副屏：y 是负的。
        XCTAssertEqual(CaptureRect.from(cocoa: CGRect(x: 0, y: 1080, width: 1920, height: 1200), primaryHeight: 1080),
                       CaptureRect(x: 0, y: -1200, width: 1920, height: 1200))
    }

    func testTinyRectIsNotARegion() {
        XCTAssertNil(CaptureRect.from(cocoa: CGRect(x: 0, y: 0, width: 3, height: 300), primaryHeight: 900))
        XCTAssertNil(CaptureRect.from(cocoa: .zero, primaryHeight: 900))
    }

    func testWindowUnderPointer() {
        let me: Int32 = 99
        let windows = [
            CaptureWindowPick.Window(id: 1, layer: 25, bounds: CGRect(x: 0, y: 0, width: 2000, height: 30), ownerPID: 1),
            CaptureWindowPick.Window(id: 2, layer: 0, bounds: CGRect(x: 0, y: 0, width: 800, height: 600), ownerPID: me),
            CaptureWindowPick.Window(id: 3, layer: 0, bounds: CGRect(x: 0, y: 0, width: 800, height: 600), ownerPID: 5,
                                     alpha: 0),
            CaptureWindowPick.Window(id: 4, layer: 0, bounds: CGRect(x: 100, y: 100, width: 500, height: 400), ownerPID: 6),
            CaptureWindowPick.Window(id: 5, layer: 0, bounds: CGRect(x: 0, y: 0, width: 1500, height: 900), ownerPID: 7),
        ]
        XCTAssertEqual(CaptureWindowPick.topmost(at: CGPoint(x: 200, y: 200), in: windows, excluding: me), 4)
        XCTAssertEqual(CaptureWindowPick.topmost(at: CGPoint(x: 1000, y: 10), in: windows, excluding: me), 5)
        XCTAssertNil(CaptureWindowPick.topmost(at: CGPoint(x: 3000, y: 10), in: windows, excluding: me))
        XCTAssertNil(CaptureWindowPick.topmost(at: .zero, in: [], excluding: me))
    }
}
