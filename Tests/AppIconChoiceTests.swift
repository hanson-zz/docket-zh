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

    func testOnlyLightAndDarkAreFree() {
        XCTAssertEqual(AppIconCatalog.classic.title, "浅色")
        XCTAssertEqual(AppIconCatalog.all.filter { !$0.isSupporterOnly }.map(\.id), ["classic", "classicDark"])
        XCTAssertEqual(AppIconCatalog.shown("classicHalloween", unlocked: false), AppIconCatalog.classic)
    }

    func testRetiredPandaIconsFallBackToClassic() {
        XCTAssertEqual(AppIconCatalog.option("panda"), AppIconCatalog.classic)
        XCTAssertEqual(AppIconCatalog.option("pandaDark"), AppIconCatalog.classic)
        XCTAssertEqual(AppIconCatalog.all.map(\.id), ["classic", "classicDark", "classicBlue", "classicRed", "classicGold",
                                                   "classicRainbow", "classicHalloween", "classicChristmas"])
    }

    func testFinderPlan() {
        XCTAssertEqual(AppIconCatalog.finderAction(for: AppIconCatalog.classicDark, hasCustomIcon: false), .set)
        XCTAssertEqual(AppIconCatalog.finderAction(for: AppIconCatalog.classicDark, hasCustomIcon: true,
                                                   lastApplied: "classicDark"), .none)
        XCTAssertEqual(AppIconCatalog.finderAction(for: AppIconCatalog.classicHalloween, hasCustomIcon: true,
                                                   lastApplied: "classicDark"), .set)
        XCTAssertEqual(AppIconCatalog.finderAction(for: AppIconCatalog.classic, hasCustomIcon: true), .clear)
        XCTAssertEqual(AppIconCatalog.finderAction(for: AppIconCatalog.classic, hasCustomIcon: false), .none)
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

    func testProIconsAreCrownsAndHolidays() {
        let pro = AppIconCatalog.all.filter(\.isSupporterOnly).map(\.id)
        XCTAssertEqual(pro, ["classicBlue", "classicRed", "classicGold", "classicRainbow",
                             "classicHalloween", "classicChristmas"])
        XCTAssertEqual(AppIconCatalog.all.count, 8)
        XCTAssertEqual(AppIconCatalog.option("classicHalloween"), AppIconCatalog.classicHalloween)
        XCTAssertTrue(AppIconCatalog.classicChristmas.isSupporterOnly)
    }

    func testHiddenHeroSeriesOnlyWhenUnlocked() {
        XCTAssertEqual(AppIconCatalog.hidden.count, 8)
        XCTAssertTrue(AppIconCatalog.hidden.allSatisfy(\.isSupporterOnly))
        XCTAssertEqual(AppIconCatalog.visible(unlocked: false), AppIconCatalog.all)
        XCTAssertEqual(AppIconCatalog.visible(unlocked: true).count, 16)
        XCTAssertEqual(AppIconCatalog.option("heroNinja"), AppIconCatalog.heroNinja)
        XCTAssertEqual(AppIconCatalog.shown("heroNinja", unlocked: false), AppIconCatalog.classic)
        XCTAssertEqual(AppIconCatalog.shown("heroNinja", unlocked: true), AppIconCatalog.heroNinja)
        let ids = AppIconCatalog.visible(unlocked: true).map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testLicenseChangeSwapsProIconOnlyWhenNeeded() {
        // 试用到期：选的皇冠图标换回经典。
        XCTAssertEqual(AppIconCatalog.relicensed("classicGold", unlocked: false, applied: "classicGold"),
                       AppIconCatalog.classic)
        // 已经是经典了，不重换。
        XCTAssertNil(AppIconCatalog.relicensed("classicGold", unlocked: false, applied: "classic"))
        // 重新解锁：换回所选。
        XCTAssertEqual(AppIconCatalog.relicensed("classicGold", unlocked: true, applied: "classic"),
                       AppIconCatalog.classicGold)
        // 免费图标和授权无关。
        XCTAssertNil(AppIconCatalog.relicensed("classicDark", unlocked: false, applied: "classicDark"))
        // 下架的小熊猫图标：贴着的换回经典。
        XCTAssertEqual(AppIconCatalog.relicensed("panda", unlocked: true, applied: "panda"), AppIconCatalog.classic)
        XCTAssertNil(AppIconCatalog.relicensed(nil, unlocked: true, applied: "classic"))
    }
}
