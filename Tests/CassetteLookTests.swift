import Foundation
import XCTest

/// 正在播放的中卡和三种卡带外观：磁带量随进度、转速、外观和 Pro 的划分。
final class CassetteLookTests: XCTestCase {

    private func medium(_ look: CassetteLook? = nil) -> WidgetConfig {
        var config = WidgetConfig(["mini": .bool(false), MusicCard.layoutKey: .string(MusicCard.medium)])
        if let look { config.set(CassetteLook.key, .string(look.rawValue)) }
        return config
    }

    // MARK: 磁带量

    func testTapeMovesFromTheLeftReelToTheRight() {
        XCTAssertEqual(CassetteMotion.packRadius(min: 6, max: 15, progress: 0, left: true), 15, accuracy: 1e-9)
        XCTAssertEqual(CassetteMotion.packRadius(min: 6, max: 15, progress: 0, left: false), 6, accuracy: 1e-9)
        XCTAssertEqual(CassetteMotion.packRadius(min: 6, max: 15, progress: 1, left: true), 6, accuracy: 1e-9)
        XCTAssertEqual(CassetteMotion.packRadius(min: 6, max: 15, progress: 1, left: false), 15, accuracy: 1e-9)
        // 半程时两卷一样粗。
        XCTAssertEqual(CassetteMotion.packRadius(min: 6, max: 15, progress: 0.5, left: true),
                       CassetteMotion.packRadius(min: 6, max: 15, progress: 0.5, left: false), accuracy: 1e-9)
    }

    func testTapeAreaIsConservedAcrossBothReels() {
        let lo = 6.5, hi = 15.5
        for p in stride(from: 0.0, through: 1.0, by: 0.1) {
            let l = CassetteMotion.packRadius(min: lo, max: hi, progress: p, left: true)
            let r = CassetteMotion.packRadius(min: lo, max: hi, progress: p, left: false)
            // 两卷带子的面积加起来不变（按面积换半径）。
            XCTAssertEqual(l * l + r * r, lo * lo + hi * hi, accuracy: 1e-6, "进度 \(p)")
        }
    }

    func testLeftReelShrinksMonotonically() {
        var last = Double.infinity
        for p in stride(from: 0.0, through: 1.0, by: 0.05) {
            let l = CassetteMotion.packRadius(min: 5, max: 14, progress: p, left: true)
            XCTAssertLessThanOrEqual(l, last)
            last = l
        }
    }

    func testOutOfRangeProgressIsClamped() {
        XCTAssertEqual(CassetteMotion.packRadius(min: 6, max: 15, progress: -2, left: true), 15, accuracy: 1e-9)
        XCTAssertEqual(CassetteMotion.packRadius(min: 6, max: 15, progress: 7, left: false), 15, accuracy: 1e-9)
        XCTAssertEqual(CassetteMotion.packRadius(min: 6, max: 15, progress: .nan, left: true), 15, accuracy: 1e-9)
    }

    // MARK: 转速

    func testFullerReelsTurnSlower() {
        let full = CassetteMotion.degreesPerSecond(fraction: 1)
        let hub = CassetteMotion.degreesPerSecond(fraction: 0.35)
        XCTAssertEqual(full, 120, accuracy: 1e-9)
        XCTAssertGreaterThan(hub, full)
        XCTAssertLessThanOrEqual(hub, 400, "最快也不到每秒一圈多")
    }

    func testSpeedSnapsToAFewSteps() {
        let speeds = Set(stride(from: 0.0, through: 1.0, by: 0.01).map { CassetteMotion.degreesPerSecond(fraction: $0) })
        XCTAssertLessThanOrEqual(speeds.count, 6, "换档只发生几次，转轮不会一直抖")
        XCTAssertEqual(CassetteMotion.degreesPerSecond(fraction: .nan), 120, accuracy: 1e-9)
    }

    func testAngleStaysInOneTurnAndIsStillAtZero() {
        XCTAssertEqual(CassetteMotion.angle(t: 0, degreesPerSecond: 200), 0)
        XCTAssertEqual(CassetteMotion.angle(t: 1, degreesPerSecond: 90), 90, accuracy: 1e-9)
        for t in [0.3, 12.7, 812_345_678.9, -5] {
            let a = CassetteMotion.angle(t: t, degreesPerSecond: 240)
            XCTAssertGreaterThanOrEqual(a, 0)
            XCTAssertLessThan(a, 360)
        }
        XCTAssertEqual(CassetteMotion.angle(t: .infinity, degreesPerSecond: 120), 0)
    }

    func testFramesOnlyWhilePlayingVisibleAndMotionAllowed() {
        XCTAssertEqual(CassetteMotion.framesPerSecond(playing: true, visible: true, reduceMotion: false),
                       CassetteMotion.fps)
        XCTAssertNil(CassetteMotion.framesPerSecond(playing: false, visible: true, reduceMotion: false))
        XCTAssertNil(CassetteMotion.framesPerSecond(playing: true, visible: false, reduceMotion: false))
        XCTAssertNil(CassetteMotion.framesPerSecond(playing: true, visible: true, reduceMotion: true))
    }

    func testConePulsesGentlyOnlyWhenAnimating() {
        XCTAssertEqual(CassetteMotion.coneScale(t: 3.2, animating: false), 1)
        for t in stride(from: 0.0, through: 5.0, by: 0.05) {
            let s = CassetteMotion.coneScale(t: t, animating: true)
            XCTAssertGreaterThanOrEqual(s, 1)
            XCTAssertLessThanOrEqual(s, 1 + CassetteMotion.coneDepth + 1e-9)
        }
        let samples = stride(from: 0.0, through: 2.0, by: 0.05).map { CassetteMotion.coneScale(t: $0, animating: true) }
        XCTAssertGreaterThan(Set(samples).count, 5, "播放时纸盆真的在动")
    }

    // MARK: 外观

    func testLooksAndTheirPro() {
        XCTAssertEqual(CassetteLook.allCases, [.plain, .tape, .portable, .boombox])
        XCTAssertFalse(CassetteLook.plain.isPro)
        XCTAssertTrue(CassetteLook.tape.isPro && CassetteLook.portable.isPro && CassetteLook.boombox.isPro)
        XCTAssertEqual(CassetteLook.stored(WidgetConfig()), .plain)
        XCTAssertEqual(CassetteLook.stored(WidgetConfig([CassetteLook.key: .string("bogus")])), .plain)
        XCTAssertEqual(CassetteLook.plain.title, "默认")
        for look in CassetteLook.allCases {
            XCTAssertFalse(look.title.isEmpty)
        }
    }

    func testCassetteIsOnlyDrawnOnTheHorizontalMediumCard() {
        XCTAssertEqual(CassetteLook.shown(config: medium(.tape), unlocked: true, vertical: false), .tape)
        XCTAssertEqual(CassetteLook.shown(config: medium(.boombox), unlocked: true, vertical: false), .boombox)
        XCTAssertEqual(CassetteLook.shown(config: medium(.portable), unlocked: true, vertical: true), .plain,
                       "竖排回退默认样式")
        var wide = medium(.tape)
        wide.set(MusicCard.layoutKey, .string(MusicCard.wide))
        XCTAssertEqual(CassetteLook.shown(config: wide, unlocked: true, vertical: false), .plain)
        var mini = medium(.tape)
        mini.set("mini", .bool(true))
        XCTAssertEqual(CassetteLook.shown(config: mini, unlocked: true, vertical: false), .plain,
                       "迷你优先，不画卡带")
    }

    func testLockedProLookFallsBackWithoutRewritingTheConfig() {
        let config = medium(.portable)
        XCTAssertEqual(ProLicenseGate.musicCassette(config: config, unlocked: false, vertical: false), .plain)
        XCTAssertEqual(ProLicenseGate.musicCassette(config: config, unlocked: true, vertical: false), .portable)
        XCTAssertEqual(CassetteLook.stored(config), .portable, "配置照旧存着，解锁后自动回来")
        let instance = WidgetInstance(kind: .music, config: config)
        XCTAssertFalse(ProLicenseGate.needsLockOverlay(instance, unlocked: false), "退回默认样式，不盖锁")
    }

    func testProChoicesInSettings() {
        XCTAssertFalse(ProFeatures.isProChoice(kind: .music, key: CassetteLook.key, value: "plain"))
        for look in [CassetteLook.tape, .portable, .boombox] {
            XCTAssertTrue(ProFeatures.isProChoice(kind: .music, key: CassetteLook.key, value: look.rawValue))
            XCTAssertFalse(ProLicenseGate.canChoose(.music, [CassetteLook.key: .string(look.rawValue)], unlocked: false))
            XCTAssertTrue(ProLicenseGate.canChoose(.music, [CassetteLook.key: .string(look.rawValue)], unlocked: true))
        }
        XCTAssertTrue(ProLicenseGate.canChoose(.music, [CassetteLook.key: .string("plain")], unlocked: false))
        XCTAssertFalse(ProFeatures.isProKind(.music), "正在播放整种免费")
    }

    // MARK: 卡片三档

    func testMediumCardIsANewSizeAndTheOldOnesStay() {
        let wide = WidgetCatalog.make(.music)!
        let mini = WidgetCatalog.make(.music, overrides: ["mini": .bool(true)])!
        let mid = WidgetCatalog.make(.music, overrides: [MusicCard.layoutKey: .string(MusicCard.medium)])!
        XCTAssertEqual(WidgetCatalog.naturalSize(wide), CGSize(width: 264, height: 132))
        XCTAssertEqual(WidgetCatalog.naturalSize(mini), CGSize(width: 64, height: 62))
        XCTAssertEqual(WidgetCatalog.naturalSize(mid), CGSize(width: 404, height: 104))
        XCTAssertEqual(WidgetCatalog.contentSize(mid, position: .bottom).width, 404)
        XCTAssertEqual(WidgetCatalog.contentSize(wide, position: .bottom).width, 264)
        XCTAssertEqual(WidgetCatalog.contentSize(mid, position: .left).width, WidgetCatalog.columnWidth,
                       "竖排还是 76 宽的竖条")
        XCTAssertFalse(MusicCard.isMedium(wide.config))
        XCTAssertTrue(MusicCard.isMedium(mid.config))
        XCTAssertEqual(CassetteLook.stored(mid.config), .plain, "新放的中卡默认样式，免费")
        XCTAssertFalse(ProFeatures.isPro(mid), "中卡本身免费")
    }

    func testVariantsMatchIncludingCardsSavedBeforeTheMediumSize() {
        let wide = WidgetCatalog.make(.music)!
        XCTAssertEqual(WidgetCatalog.variantTitle(matching: wide.config, kind: .music), "完整")
        let mini = WidgetCatalog.make(.music, overrides: ["mini": .bool(true)])!
        XCTAssertEqual(WidgetCatalog.variantTitle(matching: mini.config, kind: .music), "迷你")
        let mid = WidgetCatalog.make(.music, overrides: [MusicCard.layoutKey: .string(MusicCard.medium)])!
        XCTAssertEqual(WidgetCatalog.variantTitle(matching: mid.config, kind: .music), "中")
        // 中卡之前存的卡片没有 layout，按完整读。
        XCTAssertEqual(WidgetCatalog.variantTitle(matching: WidgetConfig(["mini": .bool(false)]), kind: .music), "完整")
        XCTAssertEqual(WidgetCatalog.variantTitle(matching: WidgetConfig(["mini": .bool(true)]), kind: .music), "迷你")
        XCTAssertFalse(MusicCard.isMedium(WidgetConfig(["mini": .bool(false)])))
        XCTAssertNil(WidgetCatalog.variantTitle(matching: WidgetConfig(), kind: .music), "空配置照旧谁都不匹配")
        // 库里默认放的还是完整。
        XCTAssertEqual(WidgetCatalog.entry(.music)?.variants.first?.title, "完整")
    }

    func testLookOptionOnlyOnTheMediumCard() {
        XCTAssertTrue(WidgetCatalog.applies(CassetteLook.key, to: medium(), kind: .music))
        XCTAssertFalse(WidgetCatalog.applies(CassetteLook.key, to: WidgetConfig(), kind: .music))
        XCTAssertFalse(WidgetCatalog.applies(CassetteLook.key, to: WidgetConfig(["mini": .bool(true)]), kind: .music))
        XCTAssertTrue(WidgetCatalog.configurableKeys(.music).contains(CassetteLook.key))
        XCTAssertFalse(WidgetCatalog.configurableKeys(.music).contains(MusicCard.layoutKey))
    }
}
