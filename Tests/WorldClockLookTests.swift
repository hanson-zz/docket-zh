import Foundation
import XCTest

/// 世界时钟多城市格子的外观：普通免费（新卡片默认），天空是 Pro；老卡片按天空读，
/// 没解锁时画成普通、不盖锁、配置照存。世界时钟整种和其余部分一直免费。
final class WorldClockLookTests: XCTestCase {
    private let sky = WidgetConfig([WorldClockLook.key: .string("sky")])
    private let plain = WidgetConfig([WorldClockLook.key: .string("plain")])

    private func cities(_ count: Int) -> WidgetConfig {
        let all = ["Asia/Tokyo|东京", "Europe/London|伦敦", "America/New_York|纽约"]
        return WidgetConfig([WorldClockList.key: .list(all.prefix(count).map { .string($0) })])
    }

    func testOldCardsKeepTheSkyAndNewCardsStartPlain() {
        XCTAssertEqual(WorldClockLook.stored(WidgetConfig()), .sky, "a card from before has no key and stays sky")
        XCTAssertEqual(WorldClockLook.stored(WidgetConfig([WorldClockLook.key: .string("bogus")])), .sky)
        XCTAssertEqual(WidgetCatalog.entry(.world)?.defaults.string(WorldClockLook.key), "sky")
        let fresh = WidgetCatalog.make(.world)!
        XCTAssertEqual(WorldClockLook.stored(fresh.config), .plain, "a new card starts on the free look")
        XCTAssertEqual(WorldClockLook.newWidget, .plain)
    }

    func testSkyFallsBackToPlainWithoutProAndKeepsTheChoice() {
        XCTAssertEqual(WorldClockLook.shown(config: sky, unlocked: true), .sky)
        XCTAssertEqual(WorldClockLook.shown(config: sky, unlocked: false), .plain)
        XCTAssertEqual(ProLicenseGate.worldClockLook(config: sky, unlocked: false), .plain)
        XCTAssertEqual(sky.string(WorldClockLook.key), "sky", "the choice is kept for when Pro comes back")
        XCTAssertEqual(WorldClockLook.shown(config: WidgetConfig(), unlocked: true), .sky, "an old card, unlocked")
        XCTAssertEqual(WorldClockLook.shown(config: WidgetConfig(), unlocked: false), .plain, "an old card, locked")
        XCTAssertEqual(WorldClockLook.shown(config: plain, unlocked: true), .plain)
        XCTAssertEqual(WorldClockLook.shown(config: plain, unlocked: false), .plain)
    }

    func testOnlyTheSkyIsPro() {
        XCTAssertTrue(WorldClockLook.sky.isPro)
        XCTAssertFalse(WorldClockLook.plain.isPro)
        XCTAssertTrue(ProFeatures.isProChoice(kind: .world, key: WorldClockLook.key, value: "sky"))
        XCTAssertFalse(ProFeatures.isProChoice(kind: .world, key: WorldClockLook.key, value: "plain"))
        XCTAssertFalse(ProLicenseGate.canChoose(.world, [WorldClockLook.key: .string("sky")], unlocked: false))
        XCTAssertTrue(ProLicenseGate.canChoose(.world, [WorldClockLook.key: .string("sky")], unlocked: true))
        XCTAssertTrue(ProLicenseGate.canChoose(.world, [WorldClockLook.key: .string("plain")], unlocked: false))
        // `look` 为 sky 只在世界时钟上算 Pro。
        XCTAssertFalse(ProFeatures.isKindProStyle(.timer, [WorldClockLook.key: .string("sky")]))
    }

    func testWorldClockItselfStaysFree() {
        XCTAssertFalse(ProFeatures.isProKind(.world))
        XCTAssertFalse(ProFeatures.isPro(WidgetCatalog.make(.world)!))
        XCTAssertTrue(ProFeatures.isPro(WidgetInstance(kind: .world, config: sky)), "the sky card carries the badge")
        XCTAssertFalse(ProLicenseGate.needsLockOverlay(WidgetInstance(kind: .world, config: sky), unlocked: false),
                       "the sky falls back to the plain cells instead of being locked")
        XCTAssertFalse(ProLicenseGate.needsLockOverlay(WidgetInstance(kind: .world, config: WidgetConfig()), unlocked: false))
        XCTAssertFalse(WidgetCatalog.entry(.world)!.variants.contains { ProFeatures.isPro(.world, overrides: $0.overrides) })
    }

    func testTheOptionOnlyShowsWithSeveralCities() {
        XCTAssertFalse(WorldClockLook.applies(WidgetConfig()), "one city looks the same either way")
        XCTAssertFalse(WorldClockLook.applies(cities(1)))
        XCTAssertTrue(WorldClockLook.applies(cities(2)))
        XCTAssertTrue(WorldClockLook.applies(cities(3)))
        XCTAssertTrue(WidgetCatalog.applies(WorldClockLook.key, to: cities(2), kind: .world))
        XCTAssertFalse(WidgetCatalog.applies(WorldClockLook.key, to: cities(1), kind: .world))
        XCTAssertTrue(WidgetCatalog.configurableKeys(.world).contains(WorldClockLook.key))
    }

    func testTitles() {
        XCTAssertEqual(WorldClockLook.allCases, [.plain, .sky], "free first in the picker")
        XCTAssertFalse(WorldClockLook.plain.title.isEmpty)
        XCTAssertFalse(WorldClockLook.sky.title.isEmpty)
    }
}
