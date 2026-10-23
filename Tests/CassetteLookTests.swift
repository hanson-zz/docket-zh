import Foundation
import XCTest

/// 复古卡带（Pro 小组件）：磁带量随进度、转速、机型、卡片尺寸、面板上的几样东西，
/// 以及卡带外观搬出正在播放时的迁移。
final class CassetteLookTests: XCTestCase {

    /// 正在播放的中卡，带上以前的卡带外观。
    private func medium(_ look: CassetteLook? = nil) -> WidgetConfig {
        var config = WidgetConfig(["mini": .bool(false), MusicCard.layoutKey: .string(MusicCard.medium)])
        if let look { config.set(CassetteLook.key, .string(look.rawValue)) }
        return config
    }

    private func cassette(_ model: CassetteModel, compact: Bool = false) -> WidgetConfig {
        var config = WidgetCatalog.make(.cassette)!.config
        config.set(CassetteModel.key, .string(model.rawValue))
        config.set(CassetteWidget.compactKey, .bool(compact))
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

    func testSpinKeepsTurningSmoothlyAcrossASpeedChange() {
        var spin = CassetteMotion.Spin(phase: 10)
        XCTAssertEqual(spin.angle(at: 1000, degreesPerSecond: 120), 10, accuracy: 1e-9)
        let before = spin.angle(at: 1001, degreesPerSecond: 120)
        XCTAssertEqual(before, 130, accuracy: 1e-9)
        // 换档那一刻角度不变，之后按新转速走。
        XCTAssertEqual(spin.angle(at: 1001, degreesPerSecond: 240), before, accuracy: 1e-9)
        XCTAssertEqual(spin.angle(at: 1002, degreesPerSecond: 240), 10, accuracy: 1e-9)
    }

    func testSpinRestsWhilePausedAndResumesFromThere() {
        var spin = CassetteMotion.Spin()
        _ = spin.angle(at: 50, degreesPerSecond: 90)
        _ = spin.angle(at: 51, degreesPerSecond: 90)
        spin.pause(at: 51.5)
        XCTAssertEqual(spin.restingAngle, 135, accuracy: 1e-9)
        // 停了很久再播放：从停下的角度接着转，不会一下跳到 t × 转速。
        XCTAssertEqual(spin.angle(at: 900, degreesPerSecond: 90), 135, accuracy: 1e-9)
        XCTAssertEqual(spin.angle(at: 901, degreesPerSecond: 90), 225, accuracy: 1e-9)
    }

    func testSpinIgnoresBadTimesAndClockGoingBack() {
        var spin = CassetteMotion.Spin()
        _ = spin.angle(at: 10, degreesPerSecond: 120)
        let a = spin.angle(at: 11, degreesPerSecond: 120)
        XCTAssertEqual(spin.angle(at: .nan, degreesPerSecond: 120), spin.restingAngle)
        let back = spin.angle(at: 5, degreesPerSecond: 120)
        XCTAssertTrue((0..<360).contains(back))
        XCTAssertEqual(a, 120, accuracy: 1e-9)
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

    // MARK: 机型和小组件

    func testModelsAndTheirTitles() {
        XCTAssertEqual(CassetteModel.allCases, [.tape, .portable, .boombox])
        XCTAssertEqual(CassetteModel.tape.title, "磁带")
        XCTAssertEqual(CassetteModel.portable.title, "随身听")
        XCTAssertEqual(CassetteModel.boombox.title, "收录机")
        XCTAssertEqual(CassetteModel.stored(WidgetConfig()), .tape, "没存按磁带读")
        XCTAssertEqual(CassetteModel.stored(WidgetConfig([CassetteModel.key: .string("bogus")])), .tape)
        XCTAssertEqual(CassetteModel.stored(WidgetConfig([CassetteModel.key: .string("boombox")])), .boombox)
    }

    func testCassetteIsAProMediaWidgetWithThreeModels() throws {
        let entry = try XCTUnwrap(WidgetCatalog.entry(.cassette))
        XCTAssertEqual(entry.name, "复古卡带")
        XCTAssertEqual(entry.category, .media)
        XCTAssertEqual(entry.variants.map(\.title), ["磁带", "随身听", "收录机"], "库里三种机型各占一格")
        XCTAssertEqual(WidgetKind.cassette.rawValue, "cassette")
        XCTAssertTrue(ProFeatures.isProKind(.cassette), "整种 Pro")
        for variant in entry.variants {
            XCTAssertTrue(ProFeatures.isPro(.cassette, overrides: variant.overrides), variant.title)
            XCTAssertFalse(ProLicenseGate.canAdd(.cassette, overrides: variant.overrides, unlocked: false))
            XCTAssertTrue(ProLicenseGate.canAdd(.cassette, overrides: variant.overrides, unlocked: true))
        }
        XCTAssertNil(WidgetCatalog.openTarget(.cassette), "点卡片打开面板")
        XCTAssertTrue(WidgetLibraryGroups.isNew(.cassette))
        XCTAssertEqual(WidgetLibraryGroups.note(.cassette), "3 种机型，各占一格")
        XCTAssertGreaterThan(WidgetLibraryGroups.rank(.cassette), WidgetLibraryGroups.rank(.music),
                             "排在正在播放后面")
        let locked = WidgetCatalog.make(.cassette)!
        XCTAssertTrue(ProLicenseGate.needsLockOverlay(locked, unlocked: false), "没解锁时和别的 Pro 小组件一样盖锁")
        XCTAssertFalse(ProLicenseGate.needsLockOverlay(locked, unlocked: true))
    }

    func testVariantsMatchTheStoredModel() {
        for model in CassetteModel.allCases {
            XCTAssertEqual(WidgetCatalog.variantTitle(matching: cassette(model), kind: .cassette), model.title)
        }
        XCTAssertEqual(WidgetCatalog.variantTitle(matching: WidgetCatalog.make(.cassette)!.config, kind: .cassette),
                       "磁带", "新放的默认磁带")
    }

    func testMediumCardIs404AndCompactIs216ForTapeOnly() {
        for model in CassetteModel.allCases {
            let card = WidgetInstance(kind: .cassette, config: cassette(model))
            XCTAssertEqual(WidgetCatalog.naturalSize(card), CGSize(width: 404, height: 104), "\(model)")
            XCTAssertEqual(WidgetCatalog.contentSize(card, position: .bottom), CGSize(width: 404, height: 58),
                           "扩展栏里内容高 58")
            XCTAssertEqual(WidgetCatalog.contentSize(card, position: .left).width, WidgetCatalog.columnWidth)
            XCTAssertEqual(WidgetCatalog.verticalHeight(card), CassetteWidget.columnHeight)
        }
        let compactTape = WidgetInstance(kind: .cassette, config: cassette(.tape, compact: true))
        XCTAssertEqual(WidgetCatalog.naturalSize(compactTape).width, 216)
        XCTAssertEqual(WidgetCatalog.contentSize(compactTape, position: .bottom).width, 216)
        XCTAssertTrue(CassetteWidget.isCompact(compactTape.config))
        for model in [CassetteModel.portable, .boombox] {
            let card = WidgetInstance(kind: .cassette, config: cassette(model, compact: true))
            XCTAssertFalse(CassetteWidget.isCompact(card.config), "\(model) 的机身放不进 216")
            XCTAssertEqual(WidgetCatalog.naturalSize(card).width, 404)
        }
        XCTAssertFalse(CassetteWidget.isCompact(cassette(.tape)), "默认不紧凑")
    }

    func testSettingsListOnlyWhatTheSettingsPageCanChange() {
        let keys = WidgetCatalog.configurableKeys(.cassette)
        for key in CassetteWidget.sharedMusicKeys {
            XCTAssertTrue(keys.contains(key), key)
            XCTAssertEqual(WidgetCatalog.entry(.cassette)?.defaults.values[key],
                           WidgetCatalog.entry(.music)?.defaults.values[key], "\(key) 的默认和正在播放一样")
        }
        XCTAssertFalse(WidgetCatalog.applies(CassetteModel.key, to: cassette(.tape), kind: .cassette),
                       "机型在样式和面板里选")
        XCTAssertFalse(WidgetCatalog.applies(MusicSourceSwitch.pinnedKey, to: cassette(.tape), kind: .cassette))
        XCTAssertTrue(WidgetCatalog.applies(CassetteWidget.compactKey, to: cassette(.tape), kind: .cassette))
        XCTAssertFalse(WidgetCatalog.applies(CassetteWidget.compactKey, to: cassette(.portable), kind: .cassette))
        XCTAssertTrue(WidgetCatalog.applies(CassetteWidget.compactKey, to: cassette(.boombox, compact: true),
                                            kind: .cassette), "已经开着的也列出来好关掉")
        XCTAssertTrue(WidgetCatalog.applies("spotify", to: cassette(.boombox), kind: .cassette))
    }

    func testMusicNoLongerOffersCassetteLooks() {
        let keys = WidgetCatalog.configurableKeys(.music)
        XCTAssertFalse(keys.contains(CassetteLook.key))
        XCTAssertFalse(keys.contains(CassetteLook.legacyCompactKey))
        XCTAssertNil(WidgetCatalog.make(.music)!.config.values[CassetteLook.key])
        XCTAssertFalse(ProFeatures.isProKind(.music), "正在播放整种免费")
        XCTAssertFalse(ProFeatures.isPro(WidgetInstance(kind: .music, config: medium(.tape))),
                       "旧值不再算 Pro 样式")
        XCTAssertFalse(ProLicenseGate.needsLockOverlay(WidgetInstance(kind: .music, config: medium(.tape)),
                                                       unlocked: false))
    }

    func testFollowsNowPlayingVisibility() {
        XCTAssertTrue(WidgetVisibility.supportsCondition(.cassette))
        XCTAssertEqual(WidgetVisibility.conditionTitle(.cassette, config: WidgetConfig()), "正在播放时显示")
        let card = WidgetInstance(kind: .cassette, config: WidgetConfig([WidgetVisibility.modeKey: .string("conditional")]))
        XCTAssertEqual(WidgetVisibility.conditionHolds(card, WidgetConditions(musicPlaying: true)), true)
        XCTAssertEqual(WidgetVisibility.conditionHolds(card, WidgetConditions(musicPlaying: false)), false)
    }

    // MARK: 卡带的三档（正在播放）

    func testNowPlayingKeepsItsThreeSizes() {
        let wide = WidgetCatalog.make(.music)!
        let mini = WidgetCatalog.make(.music, overrides: ["mini": .bool(true)])!
        let mid = WidgetCatalog.make(.music, overrides: [MusicCard.layoutKey: .string(MusicCard.medium)])!
        XCTAssertEqual(WidgetCatalog.naturalSize(wide), CGSize(width: 264, height: 132))
        XCTAssertEqual(WidgetCatalog.naturalSize(mini), CGSize(width: 64, height: 62))
        XCTAssertEqual(WidgetCatalog.naturalSize(mid), CGSize(width: 404, height: 104))
        XCTAssertEqual(WidgetCatalog.contentSize(mid, position: .left).width, WidgetCatalog.columnWidth)
        XCTAssertTrue(MusicCard.isMedium(mid.config))
        XCTAssertFalse(MusicCard.isMedium(wide.config))
        // 迁移前存着紧凑的中卡也按 404 量，紧凑只属于复古卡带。
        var leftover = medium(.tape)
        leftover.set(CassetteLook.legacyCompactKey, .bool(true))
        XCTAssertEqual(WidgetCatalog.naturalSize(WidgetInstance(kind: .music, config: leftover)).width, 404)
    }

    func testVariantsMatchIncludingCardsSavedBeforeTheMediumSize() {
        XCTAssertEqual(WidgetCatalog.variantTitle(matching: WidgetCatalog.make(.music)!.config, kind: .music), "完整")
        let mid = WidgetCatalog.make(.music, overrides: [MusicCard.layoutKey: .string(MusicCard.medium)])!
        XCTAssertEqual(WidgetCatalog.variantTitle(matching: mid.config, kind: .music), "中")
        XCTAssertEqual(WidgetCatalog.variantTitle(matching: WidgetConfig(["mini": .bool(false)]), kind: .music), "完整")
        XCTAssertEqual(WidgetCatalog.variantTitle(matching: WidgetConfig(["mini": .bool(true)]), kind: .music), "迷你")
        XCTAssertNil(WidgetCatalog.variantTitle(matching: WidgetConfig(), kind: .music), "空配置照旧谁都不匹配")
    }

    // MARK: 面板

    func testUpNextShowsThreeAndOffersShowAll() {
        XCTAssertEqual(CassetteWidget.upNextShown(count: 5, expanded: false), 3)
        XCTAssertEqual(CassetteWidget.upNextShown(count: 5, expanded: true), 5)
        XCTAssertEqual(CassetteWidget.upNextShown(count: 2, expanded: false), 2)
        XCTAssertEqual(CassetteWidget.upNextShown(count: -1, expanded: true), 0)
        XCTAssertFalse(CassetteWidget.offersShowAll(count: 3))
        XCTAssertTrue(CassetteWidget.offersShowAll(count: 4))
        XCTAssertEqual(CassetteWidget.upNextSummary(count: 3), "B 面 · 3 首")
        XCTAssertNil(CassetteWidget.upNextSummary(count: 0))
    }

    func testTrackNumbersAreTwoDigits() {
        XCTAssertEqual(CassetteWidget.trackNumber(offset: 0), "01")
        XCTAssertEqual(CassetteWidget.trackNumber(offset: 0, current: 3), "04")
        XCTAssertEqual(CassetteWidget.trackNumber(offset: 2, current: 3), "06")
        XCTAssertEqual(CassetteWidget.trackNumber(offset: 1, current: 9), "11")
        XCTAssertEqual(CassetteWidget.trackNumber(offset: -5), "01", "不会出现 00 或负数")
    }

    func testCounterReadsLikeATapeDeck() {
        XCTAssertEqual(CassetteWidget.counter(102), "01:42")
        XCTAssertEqual(CassetteWidget.counter(245), "04:05")
        XCTAssertEqual(CassetteWidget.counter(0), "00:00")
        XCTAssertEqual(CassetteWidget.counter(-3), "00:00")
        XCTAssertEqual(CassetteWidget.counter(.nan), "00:00")
        XCTAssertEqual(CassetteWidget.counter(3723), "1:02:03")
        XCTAssertEqual(CassetteWidget.counterLine(elapsed: 102, duration: 245), "01:42 · 04:05")
        XCTAssertEqual(CassetteWidget.counterLine(elapsed: 102, duration: 0), "01:42", "直播没有总长")
    }

    func testPickingAModelAppliesOrAsksForPro() {
        XCTAssertEqual(CassetteWidget.pick(.portable, current: .tape, unlocked: true), .apply)
        XCTAssertEqual(CassetteWidget.pick(.tape, current: .tape, unlocked: true), .unchanged)
        for model in CassetteModel.allCases {
            XCTAssertEqual(CassetteWidget.pick(model, current: .tape, unlocked: false), .paywall)
        }
        let compact = cassette(.tape, compact: true)
        let portable = CassetteWidget.choosing(.portable, in: compact)
        XCTAssertEqual(CassetteModel.stored(portable), .portable)
        XCTAssertFalse(portable.bool(CassetteWidget.compactKey), "换成随身听时关掉紧凑")
        let back = CassetteWidget.choosing(.tape, in: compact)
        XCTAssertTrue(back.bool(CassetteWidget.compactKey), "换回磁带不动紧凑")
        XCTAssertEqual(back.values["spotify"], compact.values["spotify"], "别的键不动")
    }

    // MARK: 迁移

    private func music(_ config: WidgetConfig) -> WidgetInstance {
        WidgetInstance(kind: .music, config: config)
    }

    func testUnlockedCassetteCardsBecomeTheNewWidgetInPlace() {
        for look in [CassetteLook.tape, .portable, .boombox] {
            var config = medium(look)
            config.set("spotify", .bool(false))
            config.set(MusicSourceSwitch.autoKey, .bool(false))
            config.set(MusicSourceSwitch.pinnedKey, .string("appleMusic"))
            config.set("previous", .bool(false))
            config.set(WidgetTint.key, .string("blue"))
            config.set(WidgetVisibility.modeKey, .string("conditional"))
            config.set("skip", .number(30))
            let old = music(config)
            let new = CassetteMigration.migrated(old, unlocked: true)
            XCTAssertEqual(new.kind, .cassette, "\(look)")
            XCTAssertEqual(new.id, old.id, "同一个 id，位置不变")
            XCTAssertEqual(CassetteModel.stored(new.config), look.model)
            XCTAssertFalse(new.config.bool("spotify"), "来源照搬")
            XCTAssertFalse(MusicSourceSwitch.autoSwitch(new.config))
            XCTAssertEqual(new.config.string(MusicSourceSwitch.pinnedKey, default: ""), "appleMusic")
            XCTAssertFalse(new.config.bool("previous", default: true))
            XCTAssertEqual(new.config.values[WidgetTint.key], .string("blue"), "颜色照搬")
            XCTAssertEqual(WidgetVisibility.mode(new.config), .conditional, "按条件显示照搬")
            for key in ["mini", MusicCard.layoutKey, "skip", "backward", "forward",
                        CassetteLook.key, CassetteLook.legacyCompactKey] {
                XCTAssertNil(new.config.values[key], "\(key) 只属于正在播放")
            }
            XCTAssertEqual(WidgetCatalog.naturalSize(new).width, 404)
        }
    }

    func testCompactTapeStaysCompactAndOthersDoNot() {
        var tape = medium(.tape)
        tape.set(CassetteLook.legacyCompactKey, .bool(true))
        let migratedTape = CassetteMigration.migrated(music(tape), unlocked: true)
        XCTAssertTrue(CassetteWidget.isCompact(migratedTape.config))
        XCTAssertEqual(WidgetCatalog.naturalSize(migratedTape).width, 216, "紧凑磁带还是 216 宽")
        var portable = medium(.portable)
        portable.set(CassetteLook.legacyCompactKey, .bool(true))
        let migratedPortable = CassetteMigration.migrated(music(portable), unlocked: true)
        XCTAssertEqual(migratedPortable.kind, .cassette)
        XCTAssertFalse(migratedPortable.config.bool(CassetteWidget.compactKey), "紧凑只给磁带")
    }

    func testLockedCardsStayInNowPlayingWithTheDefaultLook() {
        var config = medium(.boombox)
        config.set(CassetteLook.legacyCompactKey, .bool(true))
        config.set("spotify", .bool(false))
        let old = music(config)
        let new = CassetteMigration.migrated(old, unlocked: false)
        XCTAssertEqual(new.kind, .music, "没解锁不换种类，卡片不丢")
        XCTAssertEqual(new.id, old.id)
        XCTAssertNil(new.config.values[CassetteLook.key])
        XCTAssertNil(new.config.values[CassetteLook.legacyCompactKey])
        XCTAssertTrue(MusicCard.isMedium(new.config), "还是中卡，画默认样式")
        XCTAssertFalse(new.config.bool("spotify"), "别的设置不动")
        XCTAssertFalse(CassetteMigration.needsMigration(new))
    }

    func testCardsThatNeverShowedACassetteOnlyLoseTheOldKeys() {
        var wide = medium(.tape)
        wide.set(MusicCard.layoutKey, .string(MusicCard.wide))
        let wideNew = CassetteMigration.migrated(music(wide), unlocked: true)
        XCTAssertEqual(wideNew.kind, .music, "完整卡片上没画过卡带")
        XCTAssertNil(wideNew.config.values[CassetteLook.key])
        var mini = medium(.portable)
        mini.set("mini", .bool(true))
        XCTAssertEqual(CassetteMigration.migrated(music(mini), unlocked: true).kind, .music)
        let plain = CassetteMigration.migrated(music(medium(.plain)), unlocked: true)
        XCTAssertEqual(plain.kind, .music, "默认样式本来就免费")
        XCTAssertNil(plain.config.values[CassetteLook.key])
    }

    func testMigrationIsOneTimeAndLeavesOthersAlone() {
        let fresh = WidgetCatalog.make(.music)!
        XCTAssertFalse(CassetteMigration.needsMigration(fresh), "新卡片没有旧键")
        XCTAssertEqual(CassetteMigration.migrated(fresh, unlocked: true), fresh)
        let clock = WidgetCatalog.make(.clock)!
        XCTAssertEqual(CassetteMigration.migrated(clock, unlocked: true), clock)
        let once = CassetteMigration.migrated(music(medium(.tape)), unlocked: true)
        XCTAssertEqual(CassetteMigration.migrated(once, unlocked: true), once, "再跑一遍不变")
        XCTAssertEqual(CassetteMigration.migrated(once, unlocked: false), once, "迁过去的不会因为后来没解锁再迁回来")
    }

    func testMigratesEveryItemIncludingGroups() throws {
        let tape = music(medium(.tape))
        let locked = music(medium(.portable))
        let clock = WidgetCatalog.make(.clock)!
        let group = DockGroup(id: UUID(), name: "媒体", tint: .graphite, items: [.widget(locked)])
        let items: [DockItem] = [.widget(clock), .widget(tape), .group(group)]
        let result = try XCTUnwrap(CassetteMigration.migrated(items, unlocked: true))
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].widget, clock)
        XCTAssertEqual(result[1].widget?.kind, .cassette)
        XCTAssertEqual(result[1].id, tape.id)
        XCTAssertEqual(result[2].group?.items.first?.widget?.kind, .cassette, "文件夹里的也迁")
        XCTAssertNil(CassetteMigration.migrated(result, unlocked: true), "没有要迁的返回 nil，不写")
        XCTAssertNil(CassetteMigration.migrated([.widget(clock), .widget(WidgetCatalog.make(.music)!)], unlocked: false))
    }
}
