import Foundation
import XCTest

/// 程序坞 App 自定义显示图标（Pro）：存储键、映射读写、方形规范化尺寸、Pro 回退和清理。
final class DockAppIconsTests: XCTestCase {

    private func app(_ bundleID: String) -> DockItem {
        .app(id: UUID(), bundleID: bundleID,
             ref: FileRef(url: URL(fileURLWithPath: "/Applications/\(bundleID).app")))
    }

    // MARK: 存储键

    func testFileNameIsTheLowercasedBundleID() {
        XCTAssertEqual(DockAppIcons.fileName(for: "com.apple.finder"), "com.apple.finder.png")
        XCTAssertEqual(DockAppIcons.fileName(for: "com.Tencent.XinWeChat"), "com.tencent.xinwechat.png")
        XCTAssertEqual(DockAppIcons.fileName(for: "  com.apple.Safari \n"), "com.apple.safari.png")
        XCTAssertEqual(DockAppIcons.fileName(for: "org.my_app-2"), "org.my_app-2.png")
    }

    func testUnsafeBundleIDsGetNoFile() {
        XCTAssertNil(DockAppIcons.fileName(for: ""))
        XCTAssertNil(DockAppIcons.fileName(for: "   "))
        XCTAssertNil(DockAppIcons.fileName(for: ".."))
        XCTAssertNil(DockAppIcons.fileName(for: "."))
        XCTAssertNil(DockAppIcons.fileName(for: "../../etc/passwd"))
        XCTAssertNil(DockAppIcons.fileName(for: "com/evil"))
        XCTAssertNil(DockAppIcons.fileName(for: "微信"))
        XCTAssertNil(DockAppIcons.fileName(for: String(repeating: "a", count: 201)))
    }

    func testOwnFileNames() {
        XCTAssertTrue(DockAppIcons.isOwnFileName("com.apple.finder.png"))
        XCTAssertFalse(DockAppIcons.isOwnFileName("Com.Apple.Finder.png"), "只认自己写的小写文件名")
        XCTAssertFalse(DockAppIcons.isOwnFileName("com.apple.finder.jpg"))
        XCTAssertFalse(DockAppIcons.isOwnFileName(".DS_Store"))
        XCTAssertFalse(DockAppIcons.isOwnFileName(".png"))
        XCTAssertFalse(DockAppIcons.isOwnFileName("a/b.png"))
    }

    // MARK: 映射

    func testSettingAndClearingIgnoresCase() {
        var map: [String: String] = [:]
        map = DockAppIcons.setting("com.apple.finder.png", for: "com.apple.Finder", in: map)
        XCTAssertEqual(map, ["com.apple.finder": "com.apple.finder.png"])
        XCTAssertEqual(DockAppIcons.file(for: "COM.APPLE.FINDER", in: map), "com.apple.finder.png")
        XCTAssertNil(DockAppIcons.file(for: "com.apple.Safari", in: map))
        map = DockAppIcons.setting(nil, for: "com.apple.finder", in: map)
        XCTAssertTrue(map.isEmpty)
        // 空 bundle id 不写。
        XCTAssertEqual(DockAppIcons.setting("x.png", for: " ", in: ["a": "a.png"]), ["a": "a.png"])
    }

    func testHandEditedMapEntriesThatAreNotOurFilesAreIgnored() {
        let map = ["com.apple.finder": "../../secret.png", "com.apple.safari": "com.apple.safari.png"]
        XCTAssertNil(DockAppIcons.file(for: "com.apple.finder", in: map))
        XCTAssertEqual(DockAppIcons.file(for: "com.apple.safari", in: map), "com.apple.safari.png")
    }

    // MARK: Pro

    func testLockedFallsBackToTheDefaultIconButKeepsTheSetting() {
        let map = ["com.apple.finder": "com.apple.finder.png"]
        XCTAssertEqual(DockAppIcons.display(for: "com.apple.finder", in: map, unlocked: true), "com.apple.finder.png")
        XCTAssertNil(DockAppIcons.display(for: "com.apple.finder", in: map, unlocked: false))
        // 过期只影响画哪张，映射本身不动，解锁后同一张回来。
        XCTAssertEqual(DockAppIcons.file(for: "com.apple.finder", in: map), "com.apple.finder.png")
        XCTAssertNil(DockAppIcons.display(for: "com.apple.safari", in: map, unlocked: true))
    }

    func testItIsAProSetting() {
        XCTAssertTrue(ProFeatures.Setting.allCases.contains(.dockAppIcons))
        XCTAssertTrue(ProLicenseGate.canUse(.dockAppIcons, unlocked: true))
        XCTAssertFalse(ProLicenseGate.canUse(.dockAppIcons, unlocked: false))
        XCTAssertTrue(ProUnlockHighlights.allItems.contains(.setting(.dockAppIcons)))
        XCTAssertEqual(ProUnlockHighlights.title(.setting(.dockAppIcons)), "换 App 图标")
    }

    // MARK: 规范化尺寸

    func testSquareImagesScaleDownToTheStoredSize() throws {
        let big = try XCTUnwrap(DockAppIcons.squareLayout(pixelWidth: 1024, pixelHeight: 1024))
        XCTAssertEqual(big, .init(side: 512, x: 0, y: 0, width: 512, height: 512))
        let small = try XCTUnwrap(DockAppIcons.squareLayout(pixelWidth: 64, pixelHeight: 64))
        XCTAssertEqual(small, .init(side: 64, x: 0, y: 0, width: 64, height: 64), "小图不放大")
    }

    func testWideAndTallImagesAreCentredInASquare() throws {
        let wide = try XCTUnwrap(DockAppIcons.squareLayout(pixelWidth: 4032, pixelHeight: 3024))
        XCTAssertEqual(wide.side, 512)
        XCTAssertEqual(wide.width, 512)
        XCTAssertEqual(wide.height, 384)
        XCTAssertEqual(wide.x, 0)
        XCTAssertEqual(wide.y, 64)

        let tall = try XCTUnwrap(DockAppIcons.squareLayout(pixelWidth: 100, pixelHeight: 300))
        XCTAssertEqual(tall.side, 300)
        XCTAssertEqual(tall.width, 100)
        XCTAssertEqual(tall.height, 300)
        XCTAssertEqual(tall.x, 100)
        XCTAssertEqual(tall.y, 0)

        // 极端长条也至少一像素宽，画布里放得下。
        let strip = try XCTUnwrap(DockAppIcons.squareLayout(pixelWidth: 10_000, pixelHeight: 3))
        XCTAssertEqual(strip.side, 512)
        XCTAssertGreaterThanOrEqual(strip.height, 1)
        XCTAssertLessThanOrEqual(strip.y + strip.height, 512)
    }

    func testEveryLayoutFitsInsideItsCanvas() throws {
        for (w, h) in [(16, 16), (17, 513), (513, 17), (999, 1000), (512, 511), (3000, 2000), (1, 1)] {
            let layout = try XCTUnwrap(DockAppIcons.squareLayout(pixelWidth: w, pixelHeight: h))
            XCTAssertLessThanOrEqual(layout.side, DockAppIcons.storedPixels)
            XCTAssertGreaterThanOrEqual(layout.x, 0)
            XCTAssertGreaterThanOrEqual(layout.y, 0)
            XCTAssertLessThanOrEqual(layout.x + layout.width, Double(layout.side))
            XCTAssertLessThanOrEqual(layout.y + layout.height, Double(layout.side))
            XCTAssertEqual(max(layout.width, layout.height), Double(layout.side), "长边贴满画布")
        }
    }

    func testEmptyOrBrokenSizesGiveNothing() {
        XCTAssertNil(DockAppIcons.squareLayout(pixelWidth: 0, pixelHeight: 100))
        XCTAssertNil(DockAppIcons.squareLayout(pixelWidth: 100, pixelHeight: -1))
    }

    func testAcceptance() {
        XCTAssertTrue(DockAppIcons.accepts(bytes: 2_000, pixelWidth: 16, pixelHeight: 16))
        XCTAssertFalse(DockAppIcons.accepts(bytes: 0, pixelWidth: 512, pixelHeight: 512), "空文件")
        XCTAssertFalse(DockAppIcons.accepts(bytes: 2_000, pixelWidth: 15, pixelHeight: 512), "太窄")
        XCTAssertFalse(DockAppIcons.accepts(bytes: 2_000, pixelWidth: 0, pixelHeight: 0), "读不出尺寸（坏图）")
        XCTAssertFalse(DockAppIcons.accepts(bytes: DockAppIcons.maximumBytes + 1, pixelWidth: 512, pixelHeight: 512))
        XCTAssertTrue(DockAppIcons.accepts(bytes: DockAppIcons.maximumBytes, pixelWidth: 4032, pixelHeight: 3024))
    }

    func testUploadTypes() {
        for ext in ["png", "jpg", "jpeg", "heic", "icns"] {
            XCTAssertTrue(DockAppIcons.imageExtensions.contains(ext), ext)
        }
    }

    // MARK: 清理

    func testReferencedBundleIDsIncludeGroupsAcrossProfiles() {
        let work = DockProfile(kind: .customDock, name: "工作", items: [
            app("com.apple.Finder"),
            .group(DockGroup(name: "聊天", items: [app("com.tencent.xinWeChat")])),
            .spacer(id: UUID(), size: .regular),
        ])
        let home = DockProfile(kind: .customDock, name: "家", items: [app("com.apple.Safari"), app("")])
        XCTAssertEqual(DockAppIcons.referencedBundleIDs(in: [work, home]),
                       ["com.apple.finder", "com.tencent.xinwechat", "com.apple.safari"])
    }

    func testPruneDropsOnlyUninstalledAppsThatAreNoLongerOnAnyShelf() {
        let map = [
            "com.apple.finder": "com.apple.finder.png",          // 装着
            "com.gone.still.docked": "com.gone.still.docked.png", // 卸载了但还在布局里
            "com.gone.app": "com.gone.app.png",                   // 卸载了也不在布局里
            "com.weird": "../oops.png",                           // 手改的坏项
        ]
        let installed: Set<String> = ["com.apple.finder"]
        let result = DockAppIcons.pruned(map, referenced: ["com.gone.still.docked"]) { installed.contains($0) }
        XCTAssertEqual(result.kept, ["com.apple.finder": "com.apple.finder.png",
                                     "com.gone.still.docked": "com.gone.still.docked.png"])
        XCTAssertEqual(result.removedFiles, ["com.gone.app.png"], "坏项只丢映射，不删不属于自己的文件")
    }

    func testOrphanFilesAreOnlyOurOwnUnusedOnes() {
        let map = ["com.apple.finder": "com.apple.finder.png"]
        let disk = ["com.apple.finder.png", "com.old.app.png", ".DS_Store", "notes.txt", "Upper.png"]
        XCTAssertEqual(DockAppIcons.orphanFiles(onDisk: disk, map: map), ["com.old.app.png"])
    }
}
