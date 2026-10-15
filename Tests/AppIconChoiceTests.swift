import XCTest

final class AppIconChoiceTests: XCTestCase {
    func testDefaultIsClassic() {
        XCTAssertEqual(AppIconCatalog.defaultOption, AppIconCatalog.classic)
        XCTAssertEqual(AppIconCatalog.all.first, AppIconCatalog.classic)
        XCTAssertEqual(AppIconCatalog.option(nil), AppIconCatalog.classic)
        XCTAssertTrue(AppIconCatalog.classic.isBundleIcon)
        XCTAssertNil(AppIconCatalog.classic.resourceName)
    }

    func testUnknownIdFallsBackToClassic() {
        XCTAssertEqual(AppIconCatalog.option("nonsense"), AppIconCatalog.classic)
        XCTAssertEqual(AppIconCatalog.option(""), AppIconCatalog.classic)
        XCTAssertEqual(AppIconCatalog.shown("nonsense", unlocked: true), AppIconCatalog.classic)
    }

    func testPandaIsFreeAndResolves() {
        let panda = AppIconCatalog.option("panda")
        XCTAssertEqual(panda.title, "小熊猫码头")
        XCTAssertEqual(panda.resourceName, "AppIcon-Panda")
        XCTAssertFalse(panda.isSupporterOnly)
        XCTAssertFalse(panda.isBundleIcon)
        XCTAssertEqual(AppIconCatalog.shown("panda", unlocked: false), panda)
    }

    func testSupporterOnlyFallsBackWhenLocked() {
        let locked = AppIconOption(id: "x", title: "X", resourceName: "X", isSupporterOnly: true)
        XCTAssertTrue(locked.isSupporterOnly)
        // shown 只认 catalog 里的项，所以这里只校验 catalog 内每一项的规则。
        for option in AppIconCatalog.all {
            let shownLocked = AppIconCatalog.shown(option.id, unlocked: false)
            XCTAssertEqual(shownLocked, option.isSupporterOnly ? AppIconCatalog.classic : option)
            XCTAssertEqual(AppIconCatalog.shown(option.id, unlocked: true), option)
        }
    }

    func testIdsAreUniqueAndResourcesNamed() {
        let ids = AppIconCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(AppIconCatalog.all.filter(\.isBundleIcon).count, 1)
        XCTAssertEqual(AppIconCatalog.key, "appIcon.choice")
    }
}
