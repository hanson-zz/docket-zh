import XCTest
@testable import Docket

/// 拔牙的规则（Core 的 `ToothGame`、`PullTooth`）：随机疼牙（可注入种子）、拔牙、合嘴、
/// 赢、存进卡片配置、最高连拔和胜场、音效，以及面板、扩展栏卡片和桌面卡片的尺寸和点击区。
final class PullToothTests: XCTestCase {

    // MARK: 开局

    func testNewGameIsReadyWithTwelveTeeth() {
        let game = ToothGame()
        XCTAssertEqual(game.count, 12)
        XCTAssertEqual(PullTooth.toothCount, 12)
        XCTAssertEqual(game.status, .ready)
        XCTAssertNil(game.sore, "疼牙第一下才定")
        XCTAssertEqual(game.pulledCount, 0)
        XCTAssertEqual(game.remaining, 11)
        XCTAssertEqual(game.maxPulls, 11)
        XCTAssertFalse(game.isOver)
        XCTAssertTrue((0..<12).allSatisfy(game.isInMouth))
        XCTAssertNil(game.revealedSore)
    }

    func testCountIsClamped() {
        XCTAssertEqual(ToothGame(count: 0).count, 2)
        XCTAssertEqual(ToothGame(count: 1000).count, 64)
    }

    // MARK: 随机疼牙

    func testSameSeedSameSoreTooth() {
        func sore(_ seed: UInt64) -> Int? {
            var game = ToothGame()
            var rng = MineRandom(seed: seed)
            game.pull(5, now: 0, using: &rng)
            return game.sore
        }
        XCTAssertEqual(sore(7), sore(7))
        let all = Set((UInt64(0)..<200).compactMap(sore))
        XCTAssertEqual(all, Set(0..<12), "200 个种子里每颗牙都当过疼牙")
    }

    func testFirstPullDecidesSoreAndStartsTheClock() {
        var game = ToothGame()
        var rng = MineRandom(seed: 3)
        let result = game.pull(0, now: 50, using: &rng)
        XCTAssertNotNil(game.sore)
        XCTAssertEqual(game.startedAt, 50)
        XCTAssertNotEqual(result, .ignored)
        if game.sore == 0 {
            XCTAssertEqual(result, .bitten)
        } else {
            XCTAssertEqual(result, .pulled)
            XCTAssertEqual(game.status, .playing)
        }
    }

    func testFirstPullCanHitTheSoreTooth() {
        // 疼牙在 12 颗里任选，第一下也可能拔到。
        var hits = 0
        for seed in UInt64(0)..<240 {
            var game = ToothGame()
            var rng = MineRandom(seed: seed)
            if game.pull(4, now: 0, using: &rng) == .bitten { hits += 1 }
        }
        XCTAssertGreaterThan(hits, 0)
        XCTAssertLessThan(hits, 60, "大约十二分之一")
    }

    // MARK: 拔牙、合嘴、赢

    func testPullingGoodTeeth() {
        var game = ToothGame.fixed(sore: 4)
        XCTAssertEqual(game.pull(0, now: 1), .pulled)
        XCTAssertEqual(game.pull(1, now: 2), .pulled)
        XCTAssertEqual(game.pulledCount, 2)
        XCTAssertEqual(game.remaining, 9)
        XCTAssertFalse(game.isInMouth(0))
        XCTAssertEqual(game.pull(0, now: 3), .ignored, "拔过的不能再拔")
        XCTAssertEqual(game.pull(-1, now: 3), .ignored)
        XCTAssertEqual(game.pull(12, now: 3), .ignored)
        XCTAssertNil(game.revealedSore, "没结束不告诉哪颗疼")
    }

    func testSoreToothBites() {
        var game = ToothGame.fixed(sore: 7)
        game.pull(0, now: 1)
        game.pull(1, now: 2)
        XCTAssertEqual(game.pull(7, now: 9), .bitten)
        XCTAssertEqual(game.status, .bitten)
        XCTAssertTrue(game.isOver)
        XCTAssertEqual(game.endedAt, 9)
        XCTAssertEqual(game.pulledCount, 2, "拔到疼牙那一下不算")
        XCTAssertTrue(game.isInMouth(7), "疼牙留在嘴里")
        XCTAssertEqual(game.revealedSore, 7)
        XCTAssertEqual(game.pull(3, now: 10), .ignored, "合嘴了不能再拔")
    }

    func testPullingEveryOtherToothWins() {
        var game = ToothGame.fixed(sore: 11)
        for index in 0..<10 { XCTAssertEqual(game.pull(index, now: Double(index)), .pulled) }
        XCTAssertEqual(game.pull(10, now: 20), .won)
        XCTAssertEqual(game.status, .won)
        XCTAssertEqual(game.pulledCount, 11)
        XCTAssertEqual(game.remaining, 0)
        XCTAssertEqual(game.endedAt, 20)
        XCTAssertEqual(game.revealedSore, 11)
        XCTAssertEqual(game.pull(11, now: 21), .ignored)
    }

    func testSystemRandomGameAlwaysEnds() {
        for _ in 0..<20 {
            var game = ToothGame()
            for index in 0..<12 where !game.isOver { game.pull(index, now: 0) }
            XCTAssertTrue(game.isOver)
            XCTAssertNotNil(game.sore)
        }
    }

    // MARK: 存取

    func testCodableRoundTrip() throws {
        var game = ToothGame.fixed(sore: 2, startedAt: 100)
        game.pull(0, now: 101)
        game.pull(8, now: 102)
        let data = try JSONEncoder().encode(game)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"p\":\"100000001000\""), text)
        XCTAssertEqual(try JSONDecoder().decode(ToothGame.self, from: data), game)

        game.pull(2, now: 110)
        let bitten = try JSONDecoder().decode(ToothGame.self, from: JSONEncoder().encode(game))
        XCTAssertEqual(bitten, game)
        XCTAssertEqual(bitten.status, .bitten)
    }

    func testDamagedSavesAreRepaired() throws {
        func decode(_ json: String) throws -> ToothGame {
            try JSONDecoder().decode(ToothGame.self, from: Data(json.utf8))
        }
        // 没有疼牙却写着进行中：按还没开始读。
        let noSore = try decode(#"{"n":12,"p":"110000000000","st":"playing","t0":5}"#)
        XCTAssertEqual(noSore.status, .ready)
        XCTAssertEqual(noSore.pulledCount, 0)
        XCTAssertNil(noSore.startedAt)
        // 疼牙写成拔掉了：疼牙放回嘴里。
        let pulledSore = try decode(#"{"n":12,"s":1,"p":"110000000000","st":"playing"}"#)
        XCTAssertTrue(pulledSore.isInMouth(1))
        XCTAssertEqual(pulledSore.pulledCount, 1)
        // 写着赢了但没拔光：按进行中读。
        let fakeWin = try decode(#"{"n":12,"s":1,"p":"100000000000","st":"won","t1":9}"#)
        XCTAssertEqual(fakeWin.status, .playing)
        XCTAssertNil(fakeWin.endedAt)
        // 长度不对、牙数离谱：解不出来。
        XCTAssertThrowsError(try decode(#"{"n":12,"p":"10","st":"ready"}"#))
        XCTAssertThrowsError(try decode(#"{"n":1,"p":"1","st":"ready"}"#))
    }

    func testConfigFallsBackToANewGame() {
        var config = WidgetConfig()
        XCTAssertEqual(PullTooth.game(config), ToothGame())
        config.set(PullTooth.gameKey, .string("not json"))
        XCTAssertEqual(PullTooth.game(config), ToothGame())
        // 牙数不是 12 的旧局也不认。
        var other = ToothGame.fixed(count: 8, sore: 1)
        other.pull(0, now: 0)
        PullTooth.store(other, in: &config)
        XCTAssertEqual(PullTooth.game(config), ToothGame())
    }

    // MARK: 纪录、胜场

    func testApplyStoresTheGameAndRecords() {
        var config = WidgetConfig()
        var rng = MineRandom(seed: 11)
        // 先拔一颗，定下疼牙。
        var outcome = PullTooth.apply(pull: 0, to: &config, now: 1, using: &rng)
        var game = PullTooth.game(config)
        let sore = try! XCTUnwrap(game.sore)
        if sore == 0 {
            XCTAssertEqual(outcome.result, .bitten)
            return
        }
        XCTAssertEqual(outcome.result, .pulled)
        XCTAssertEqual(outcome.sound, .pop)
        XCTAssertFalse(outcome.newRecord, "没结束不记纪录")
        XCTAssertEqual(PullTooth.best(config), 0)
        // 再拔两颗好牙，然后拔疼牙。
        let good = (1..<12).filter { $0 != sore }
        PullTooth.apply(pull: good[0], to: &config, now: 2, using: &rng)
        PullTooth.apply(pull: good[1], to: &config, now: 3, using: &rng)
        outcome = PullTooth.apply(pull: sore, to: &config, now: 4, using: &rng)
        XCTAssertEqual(outcome.result, .bitten)
        XCTAssertEqual(outcome.sound, .snap)
        XCTAssertTrue(outcome.newRecord)
        XCTAssertEqual(PullTooth.best(config), 3)
        XCTAssertEqual(PullTooth.wins(config), 0)
        game = PullTooth.game(config)
        XCTAssertTrue(PullTooth.isRecord(game, in: config))
        XCTAssertEqual(PullTooth.apply(pull: good[2], to: &config, now: 5, using: &rng).result, .ignored)

        // 下一局只拔一颗就合嘴：纪录不变、不是新纪录。
        PullTooth.restart(in: &config)
        XCTAssertEqual(PullTooth.game(config).status, .ready)
        XCTAssertFalse(PullTooth.isRecord(PullTooth.game(config), in: config))
        var short = ToothGame.fixed(sore: 5, startedAt: 10)
        short.pull(0, now: 11)
        PullTooth.store(short, in: &config)
        outcome = PullTooth.apply(pull: 5, to: &config, now: 12, using: &rng)
        XCTAssertEqual(outcome.result, .bitten)
        XCTAssertFalse(outcome.newRecord)
        XCTAssertEqual(PullTooth.best(config), 3)
        XCTAssertFalse(PullTooth.isRecord(PullTooth.game(config), in: config))
    }

    func testWinningCountsAWinAndTheBestRun() {
        var config = WidgetConfig()
        var rng = MineRandom(seed: 1)
        PullTooth.store(ToothGame.fixed(sore: 6, startedAt: 0), in: &config)
        var last = PullTooth.Outcome(result: .ignored, newRecord: false)
        for index in 0..<12 where index != 6 {
            last = PullTooth.apply(pull: index, to: &config, now: Double(index + 1), using: &rng)
        }
        XCTAssertEqual(last.result, .won)
        XCTAssertEqual(last.sound, .win)
        XCTAssertTrue(last.newRecord)
        XCTAssertEqual(PullTooth.best(config), 11)
        XCTAssertEqual(PullTooth.wins(config), 1)
        XCTAssertTrue(PullTooth.isRecord(PullTooth.game(config), in: config))

        // 再赢一局：胜场加一，平了纪录不算新纪录。
        PullTooth.store(ToothGame.fixed(sore: 0, startedAt: 100), in: &config)
        for index in 1..<12 {
            last = PullTooth.apply(pull: index, to: &config, now: Double(100 + index), using: &rng)
        }
        XCTAssertEqual(last.result, .won)
        XCTAssertFalse(last.newRecord)
        XCTAssertEqual(PullTooth.wins(config), 2)
        XCTAssertFalse(PullTooth.isRecord(PullTooth.game(config), in: config))
    }

    func testDamagedRecordsReadAsZero() {
        var config = WidgetConfig()
        config.set(PullTooth.bestKey, .number(-4))
        config.set(PullTooth.winsKey, .string("x"))
        XCTAssertEqual(PullTooth.best(config), 0)
        XCTAssertEqual(PullTooth.wins(config), 0)
    }

    // MARK: 音效开关

    func testSoundIsOnByDefaultAndStoredOnTheCard() {
        var config = WidgetConfig()
        XCTAssertTrue(PullTooth.soundOn(config))
        PullTooth.setSound(false, in: &config)
        XCTAssertFalse(PullTooth.soundOn(config))
        XCTAssertEqual(config.values[PullTooth.soundKey], .bool(false))
        PullTooth.setSound(true, in: &config)
        XCTAssertTrue(PullTooth.soundOn(config))
    }

    func testSoundsAreShortCleanWavs() {
        for sound in ToothSound.allCases {
            let samples = ToothSoundSynth.render(sound)
            let seconds = Double(samples.count) / ToothSoundSynth.sampleRate
            XCTAssertGreaterThan(seconds, 0.05, "\(sound)")
            XCTAssertLessThan(seconds, 0.6, "\(sound)")
            XCTAssertTrue(samples.allSatisfy { abs($0) <= 0.95 }, "\(sound) 限幅")
            XCTAssertGreaterThan(samples.map { abs($0) }.max() ?? 0, 0.1, "\(sound) 听得见")
            XCTAssertEqual(samples.last ?? 1, 0, accuracy: 0.001, "\(sound) 尾巴收到 0，不咔哒")
            let wav = ToothSoundSynth.wav(sound)
            XCTAssertEqual(String(decoding: wav.prefix(4), as: UTF8.self), "RIFF")
            XCTAssertEqual(wav.count, 44 + samples.count * 2)
        }
        XCTAssertEqual(ToothSoundSynth.render(.snap), ToothSoundSynth.render(.snap), "每次合成一样")
    }

    // MARK: 文案

    func testStatusLines() {
        XCTAssertEqual(PullTooth.statusLine(ToothGame()), "张大嘴了，点一颗牙拔下来")
        var game = ToothGame.fixed(sore: 3)
        game.pull(0, now: 0)
        XCTAssertEqual(PullTooth.statusLine(game), "还剩 10 颗好牙，哪颗是疼牙？")
        game.pull(3, now: 1)
        XCTAssertEqual(PullTooth.statusLine(game), "啊呜！拔到疼牙了")
        XCTAssertEqual(PullTooth.recordLine(best: 9, wins: 2), "最高 9 颗 · 赢 2 局")
        XCTAssertEqual(PullTooth.animalName, "河马圆圆")
    }

    // MARK: 颜色

    func testAccentNumberIsReadableOnLightGlass() {
        let light = ColorCode(hex: PullTooth.accentLightHex)!
        XCTAssertGreaterThanOrEqual(WidgetTint.contrastRatio(light, PanelContrast.lightGlass), 4.5)
        XCTAssertGreaterThanOrEqual(WidgetTint.contrastRatio(light, ColorCode(red: 1, green: 1, blue: 1)), 4.5)
        // 深色玻璃按 #2C2C30 算。
        let dark = ColorCode(hex: PullTooth.accentDarkHex)!
        XCTAssertGreaterThanOrEqual(WidgetTint.contrastRatio(dark, ColorCode(hex: "#2C2C30")!), 4.5)
    }

    // MARK: 尺寸和点击区

    func testPanelArtFitsTheRealContentWidth() {
        // 340 宽面板：减内容区两侧 16、侧边尾巴 10、卡片两侧 16，剩 266。
        XCTAssertEqual(PullTooth.panelWidth, 340)
        XCTAssertEqual(PullTooth.panelContentWidth, 266, accuracy: 0.001)
        XCTAssertLessThanOrEqual(PullTooth.panelArtWidth, PullTooth.panelContentWidth)
        let layout = ToothLayout(width: PullTooth.panelArtWidth)
        for index in 0..<12 {
            let hit = layout.hit(index)
            XCTAssertGreaterThanOrEqual(hit.x, 0)
            XCTAssertLessThanOrEqual(hit.maxX, layout.width + 0.001, "第 \(index) 颗点击区不出右边")
            XCTAssertLessThanOrEqual(hit.maxY, layout.height)
        }
        XCTAssertGreaterThanOrEqual(layout.smallestHitSide, 24, "面板里每颗牙的点击区至少 24pt")
    }

    func testTeethSitInsideTheirHitAreasWithoutOverlap() {
        let layout = ToothLayout(width: 266)
        for i in 0..<12 {
            let tooth = layout.tooth(i), hit = layout.hit(i)
            XCTAssertGreaterThanOrEqual(tooth.x, hit.x - 0.001)
            XCTAssertLessThanOrEqual(tooth.maxX, hit.maxX + 0.001)
            XCTAssertGreaterThanOrEqual(tooth.y, hit.y - 0.001)
            XCTAssertLessThanOrEqual(tooth.maxY, hit.maxY + 0.001)
            for j in (i + 1)..<12 {
                XCTAssertFalse(layout.hit(i).intersects(layout.hit(j)), "\(i) 和 \(j) 点击区重叠")
                XCTAssertFalse(layout.tooth(i).intersects(layout.tooth(j)), "\(i) 和 \(j) 牙重叠")
            }
        }
        // 上排在上、下排在下。
        XCTAssertLessThan(layout.tooth(0).maxY, layout.tooth(6).y)
    }

    func testHitIndexFindsEachTooth() {
        for width in [266.0, 148, 165, 316] {
            let layout = ToothLayout(width: width)
            for i in 0..<12 {
                let hit = layout.hit(i)
                XCTAssertEqual(layout.hitIndex(x: hit.x + hit.width / 2, y: hit.y + hit.height / 2), i)
                let tooth = layout.tooth(i)
                XCTAssertEqual(layout.hitIndex(x: tooth.x + tooth.width / 2, y: tooth.y + tooth.height / 2), i)
            }
            XCTAssertNil(layout.hitIndex(x: 1, y: 1), "头顶不是牙")
            XCTAssertNil(layout.hitIndex(x: width / 2, y: layout.height - 1), "下巴不是牙")
        }
    }

    func testClosingStaysInsideTheFrame() {
        let layout = ToothLayout(width: 266)
        // 合嘴时上半边往下移，上牙最低处仍在河马框里。
        XCTAssertLessThanOrEqual(layout.tooth(0).maxY + layout.closeTravel, layout.height)
        XCTAssertGreaterThan(layout.closeTravel, 0)
    }

    func testFitting() {
        let wide = ToothLayout.fitting(maxWidth: 400, maxHeight: 100)
        XCTAssertLessThanOrEqual(wide.height, 100)
        let tall = ToothLayout.fitting(maxWidth: 100, maxHeight: 400)
        XCTAssertEqual(tall.width, 100)
    }

    // MARK: 扩展栏卡片

    func testShelfCardSizes() {
        XCTAssertEqual(PullTooth.tileWidth, 188)
        XCTAssertEqual(PullTooth.columnHeight, 120)
        // 横排缩略图 52 宽，高不超过 58pt 的卡片。
        XCTAssertLessThanOrEqual(ToothLayout(width: 52).height, 58)
        // 竖排缩略图 60 宽放进 76 宽的竖条。
        XCTAssertLessThanOrEqual(ToothLayout(width: 60).width, 76)
    }

    // MARK: 钉在桌面

    func testDesktopPlanHandlesOnlyPullTooth() {
        XCTAssertTrue(DesktopCardsToothPlan.handles(.pullTooth))
        XCTAssertFalse(DesktopCardsToothPlan.handles(.minesweeper))
        XCTAssertEqual(DesktopPinSupport.mode(.pullTooth, hasDetail: true, panelWidth: 340), .dedicated)
    }

    func testDesktopHippoFitsEverySizeAndStaysClickable() {
        for size in DesktopPinSize.allCases {
            let layout = DesktopCardsToothPlan.layout(for: size)
            let inset = DesktopCardsToothPlan.inset(size)
            switch size {
            case .medium:
                XCTAssertLessThanOrEqual(layout.width + inset * 2 + DesktopCardsToothPlan.mediumSideWidth
                                         + DesktopCardsToothPlan.mediumSpacing, size.width, "\(size)")
                XCTAssertLessThanOrEqual(layout.height + inset * 2, size.height, "\(size)")
            case .small, .large:
                XCTAssertLessThanOrEqual(layout.width + inset * 2, size.width, "\(size)")
                XCTAssertLessThanOrEqual(layout.height + inset * 2 + DesktopCardsToothPlan.headerHeight(size)
                                         + DesktopCardsToothPlan.headerSpacing(size), size.height, "\(size)")
            }
            XCTAssertGreaterThanOrEqual(layout.smallestHitSide, DesktopCardsToothPlan.minimumHitSide, "\(size)")
        }
        XCTAssertGreaterThan(DesktopCardsToothPlan.layout(for: .large).width,
                             DesktopCardsToothPlan.layout(for: .small).width)
    }

    // MARK: 目录

    func testCatalogEntry() {
        let entry = WidgetCatalog.entry(.pullTooth)
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.name, "拔牙")
        XCTAssertEqual(entry?.category, .tools)
        XCTAssertEqual(entry?.selfContained, true)
        XCTAssertTrue(WidgetLibraryGroups.isNew(.pullTooth))
        XCTAssertFalse(ProFeatures.isProKind(.pullTooth), "免费")
        XCTAssertEqual(WidgetKind(rawValue: "pull-tooth"), .pullTooth)
        let keywords = WidgetSearch.keywords["pull-tooth"] ?? []
        XCTAssertTrue(keywords.contains("拔牙"))
        XCTAssertTrue(keywords.contains("河马"))
        XCTAssertTrue(keywords.contains("小游戏"))
    }
}
