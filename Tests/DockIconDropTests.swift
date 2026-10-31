import Foundation
import XCTest

/// 拖到程序坞 App 图标上：分类、Option 判定、松手做什么、悬停提示和光标。
final class DockIconDropTests: XCTestCase {

    private let option = DockIconDrop.Modifier.option
    private let command = DockIconDrop.Modifier.command
    private let control = DockIconDrop.Modifier.control
    private let shift = DockIconDrop.Modifier.shift

    // MARK: 分类

    func testSourcesByExtension() {
        XCTAssertEqual(DockIconDrop.source(pathExtension: "png", isAppBundle: false), .imageFile)
        XCTAssertEqual(DockIconDrop.source(pathExtension: "JPG", isAppBundle: false), .imageFile)
        XCTAssertEqual(DockIconDrop.source(pathExtension: "heic", isAppBundle: false), .imageFile)
        XCTAssertEqual(DockIconDrop.source(pathExtension: "icns", isAppBundle: false), .imageFile)
        XCTAssertEqual(DockIconDrop.source(pathExtension: "tiff", isAppBundle: false), .imageFile)
        XCTAssertEqual(DockIconDrop.source(pathExtension: "app", isAppBundle: false), .app)
        XCTAssertEqual(DockIconDrop.source(pathExtension: "", isAppBundle: true), .app, "UTType 认出的 App 包")
        XCTAssertEqual(DockIconDrop.source(pathExtension: "pdf", isAppBundle: false), .otherFile)
        XCTAssertEqual(DockIconDrop.source(pathExtension: "", isAppBundle: false), .otherFile, "文件夹")
    }

    func testWhatCanBeAnIcon() {
        XCTAssertTrue(DockIconDrop.Source.imageFile.canBeIcon)
        XCTAssertTrue(DockIconDrop.Source.app.canBeIcon)
        XCTAssertTrue(DockIconDrop.Source.imageData.canBeIcon)
        XCTAssertFalse(DockIconDrop.Source.otherFile.canBeIcon)
        XCTAssertFalse(DockIconDrop.Source.imageData.isFile, "图片数据没有文件，打不开")
    }

    func testOnlyAppTilesTakeTheDrop() {
        let ref = FileRef(url: URL(fileURLWithPath: "/Applications/Safari.app"))
        XCTAssertEqual(DockIconDrop.appBundleID(of: .app(id: UUID(), bundleID: "com.apple.Safari", ref: ref)),
                       "com.apple.Safari")
        XCTAssertNil(DockIconDrop.appBundleID(of: .app(id: UUID(), bundleID: "  ", ref: ref)))
        XCTAssertNil(DockIconDrop.appBundleID(of: .file(id: UUID(), ref: FileRef(url: URL(fileURLWithPath: "/tmp/a.pdf")))))
    }

    // MARK: Option

    func testOptionAloneChangesIcon() {
        XCTAssertTrue(DockIconDrop.wantsIconChange(modifierFlags: option))
        XCTAssertTrue(DockIconDrop.wantsIconChange(modifierFlags: option | shift), "Shift 不影响")
        XCTAssertTrue(DockIconDrop.wantsIconChange(modifierFlags: option | 1 << 16), "大写锁定不影响")
    }

    func testNoOptionOrOtherModifiersDoNot() {
        XCTAssertFalse(DockIconDrop.wantsIconChange(modifierFlags: 0))
        XCTAssertFalse(DockIconDrop.wantsIconChange(modifierFlags: shift))
        XCTAssertFalse(DockIconDrop.wantsIconChange(modifierFlags: option | command), "Command+Option 是做替身")
        XCTAssertFalse(DockIconDrop.wantsIconChange(modifierFlags: option | control))
    }

    // MARK: 松手

    func testWithoutOptionFilesOpenAsBefore() {
        XCTAssertEqual(DockIconDrop.action(sources: [.otherFile], option: false, unlocked: true, place: .shelf), .open([0]))
        XCTAssertEqual(DockIconDrop.action(sources: [.imageFile, .otherFile], option: false, unlocked: true, place: .shelf),
                       .open([0, 1]), "图片不按 Option 也是打开")
        XCTAssertEqual(DockIconDrop.action(sources: [.imageFile], option: false, unlocked: false, place: .shelf), .open([0]),
                       "免费用户的默认行为不变")
    }

    func testAppOnAppNeedsOption() {
        XCTAssertEqual(DockIconDrop.action(sources: [.app], option: false, unlocked: true, place: .shelf), .refuse)
        XCTAssertEqual(DockIconDrop.action(sources: [.app], option: true, unlocked: true, place: .shelf), .changeIcon(0))
        XCTAssertEqual(DockIconDrop.action(sources: [.app, .otherFile], option: false, unlocked: true, place: .shelf),
                       .open([1]), "App 不当文稿打开，别的文件照常")
    }

    func testImageDataNeedsOption() {
        XCTAssertEqual(DockIconDrop.action(sources: [.imageData], option: false, unlocked: true, place: .shelf), .refuse)
        XCTAssertEqual(DockIconDrop.action(sources: [.imageData], option: true, unlocked: true, place: .shelf), .changeIcon(0))
    }

    func testOptionUsesFirstUsableSource() {
        XCTAssertEqual(DockIconDrop.action(sources: [.otherFile, .imageFile, .app], option: true, unlocked: true, place: .shelf),
                       .changeIcon(1))
        XCTAssertEqual(DockIconDrop.action(sources: [.otherFile], option: true, unlocked: true, place: .shelf), .refuse)
        XCTAssertEqual(DockIconDrop.action(sources: [], option: true, unlocked: true, place: .shelf), .refuse)
    }

    func testFreeUserGetsUpgradeInsteadOfChange() {
        XCTAssertEqual(DockIconDrop.action(sources: [.imageFile], option: true, unlocked: false, place: .shelf), .upgrade)
        XCTAssertEqual(DockIconDrop.action(sources: [.app], option: true, unlocked: false, place: .groupWindow), .upgrade)
        XCTAssertEqual(DockIconDrop.action(sources: [.otherFile], option: true, unlocked: false, place: .shelf), .refuse,
                       "当不了图标的东西不弹升级")
    }

    func testGroupWindowStillAddsAppsWithoutOption() {
        XCTAssertEqual(DockIconDrop.action(sources: [.app], option: false, unlocked: true, place: .groupWindow), .addToGroup([0]))
        XCTAssertEqual(DockIconDrop.action(sources: [.otherFile, .app], option: false, unlocked: true, place: .groupWindow),
                       .addToGroup([1]))
        XCTAssertEqual(DockIconDrop.action(sources: [.imageFile], option: false, unlocked: true, place: .groupWindow), .open([0]))
        XCTAssertEqual(DockIconDrop.action(sources: [.app], option: true, unlocked: true, place: .groupWindow), .changeIcon(0))
    }

    // MARK: 提示和光标

    func testHints() {
        XCTAssertEqual(DockIconDrop.hint(sources: [.imageFile], option: false, unlocked: true, place: .shelf), .open(optionTip: true))
        XCTAssertEqual(DockIconDrop.hint(sources: [.otherFile], option: false, unlocked: true, place: .shelf), .open(optionTip: false))
        XCTAssertEqual(DockIconDrop.hint(sources: [.app], option: false, unlocked: true, place: .shelf), .holdOption)
        XCTAssertEqual(DockIconDrop.hint(sources: [.imageFile], option: true, unlocked: true, place: .shelf), .changeIcon(pro: false))
        XCTAssertEqual(DockIconDrop.hint(sources: [.imageFile], option: true, unlocked: false, place: .shelf), .changeIcon(pro: true))
        XCTAssertEqual(DockIconDrop.hint(sources: [.otherFile], option: true, unlocked: true, place: .shelf), .notAnImage)
        XCTAssertEqual(DockIconDrop.hint(sources: [.app], option: false, unlocked: true, place: .groupWindow), .addToGroup)
        XCTAssertEqual(DockIconDrop.hint(sources: [], option: false, unlocked: true, place: .shelf), .none)
    }

    func testCursorBadges() {
        XCTAssertEqual(DockIconDrop.cursor(for: .changeIcon(0)), .copy)
        XCTAssertEqual(DockIconDrop.cursor(for: .upgrade), .copy)
        XCTAssertEqual(DockIconDrop.cursor(for: .open([0])), .plain, "和系统程序坞一样，打开不带角标")
        XCTAssertEqual(DockIconDrop.cursor(for: .refuse), .forbidden)
    }

    func testConfirmPulseIsSubtle() {
        XCTAssertGreaterThan(DockIconDrop.confirmPeakScale, 1)
        XCTAssertLessThanOrEqual(DockIconDrop.confirmPeakScale, 1.15)
        XCTAssertLessThan(DockIconDrop.confirmDuration, 0.6)
    }
}
