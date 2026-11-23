import XCTest
@testable import Docket

/// 柴犬翻翻乐的规则（Core 的 `ShibaMatchGame`、`ShibaMatch`）：可注入种子洗牌、翻第一张和第二张、
/// 配上保持翻开、已配禁点、没配上停 0.8 秒再翻回（期间点击不算）、步数、计时、最佳纪录、存档恢复
/// 和坏数据回退、重新开始，以及棋盘规格、面板和桌面卡片的尺寸、点击区和目录接入。
final class ShibaMatchTests: XCTestCase {

    /// 固定种子的随机数（SplitMix64），洗牌可重复。
    private struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// 3 行 4 列的一副固定牌：0 和 9 是柴犬，1 和 3 是爪印，2 和 10 是骨头，4 和 6 是狗窝，
    /// 5 和 8 是网球，7 和 11 是饭碗。
    private let deck: [ShibaFace] = [.shiba, .paw, .bone, .paw,
                                     .house, .ball, .house, .bowl,
                                     .ball, .shiba, .bone, .bowl]
    private let pairs: [(Int, Int)] = [(0, 9), (1, 3), (2, 10), (4, 6), (5, 8), (7, 11)]

    private func fixed() throws -> ShibaMatchGame {
        try XCTUnwrap(ShibaMatchGame.fixed(cards: deck))
    }

    // MARK: 规格

    func testStandardSpecIsThreeByFourWithSixPairs() {
        let spec = ShibaBoardSpec.standard
        XCTAssertEqual(spec.rows, 3)
        XCTAssertEqual(spec.columns, 4)
        XCTAssertEqual(spec.pairs, 6)
        XCTAssertEqual(spec.key, "3x4")
        XCTAssertEqual(spec.faces, [.shiba, .paw, .bone, .house, .ball, .bowl], "这一版六种图案")
        XCTAssertTrue(spec.isValid)
    }

    func testFutureSpecsAreValidAndOddBoardsAreNot() {
        XCTAssertEqual(ShibaBoardSpec.medium.pairs, 8)
        XCTAssertEqual(ShibaBoardSpec.hard.pairs, 10)
        XCTAssertTrue(ShibaBoardSpec.medium.isValid)
        XCTAssertTrue(ShibaBoardSpec.hard.isValid)
        XCTAssertFalse(ShibaBoardSpec(rows: 3, columns: 3).isValid, "格子数是奇数")
        XCTAssertFalse(ShibaBoardSpec(rows: 6, columns: 6).isValid, "图案不够 18 对")
        XCTAssertFalse(ShibaBoardSpec(rows: 1, columns: 2).isValid)
        // 不合法的规格开局时按标准规格。
        XCTAssertEqual(ShibaMatchGame(spec: ShibaBoardSpec(rows: 3, columns: 3)).spec, .standard)
    }

    func testNewGameDealsEachFaceTwiceForEverySpec() {
        for spec in [ShibaBoardSpec.standard, .medium, .hard] {
            var rng = Seeded(state: 7)
            let game = ShibaMatchGame(spec: spec, using: &rng)
            XCTAssertEqual(game.cards.count, spec.count, spec.key)
            for face in spec.faces {
                XCTAssertEqual(game.cards.filter { $0 == face }.count, 2, "\(spec.key) \(face)")
            }
            XCTAssertEqual(game.status, .ready)
            XCTAssertEqual(game.moves, 0)
            XCTAssertEqual(game.pairsFound, 0)
            XCTAssertEqual(game.pairs, spec.pairs)
            XCTAssertTrue((0..<spec.count).allSatisfy { game.state($0) == .hidden })
        }
    }

    func testShuffleIsReproducibleWithASeed() {
        var a = Seeded(state: 42), b = Seeded(state: 42), c = Seeded(state: 43)
        let first = ShibaMatchGame(using: &a), second = ShibaMatchGame(using: &b), other = ShibaMatchGame(using: &c)
        XCTAssertEqual(first.cards, second.cards, "同一个种子洗出同一副")
        XCTAssertNotEqual(first.cards, other.cards, "换种子换顺序")
    }

    func testFixedRejectsADeckThatIsNotPairs() {
        XCTAssertNil(ShibaMatchGame.fixed(cards: Array(repeating: .paw, count: 12)))
        XCTAssertNil(ShibaMatchGame.fixed(cards: Array(deck.prefix(10))))
        XCTAssertNotNil(ShibaMatchGame.fixed(cards: deck))
    }

    // MARK: 翻牌

    func testFirstFlipStartsTheClockAndShowsTheCard() throws {
        var game = try fixed()
        XCTAssertEqual(game.flip(0, now: 100), .first)
        XCTAssertEqual(game.status, .playing)
        XCTAssertEqual(game.startedAt, 100)
        XCTAssertEqual(game.state(0), .faceUp)
        XCTAssertEqual(game.moves, 0, "第一张不算步")
        XCTAssertEqual(game.flip(0, now: 101), .ignored, "已经翻着的再点不算")
        XCTAssertEqual(game.moves, 0)
    }

    func testMatchingPairStaysUpAndCannotBeFlippedAgain() throws {
        var game = try fixed()
        game.flip(0, now: 0)
        XCTAssertEqual(game.flip(9, now: 1), .matched)
        XCTAssertEqual(game.moves, 1, "翻第二张算一步")
        XCTAssertEqual(game.pairsFound, 1)
        XCTAssertEqual(game.state(0), .matched)
        XCTAssertEqual(game.state(9), .matched)
        XCTAssertTrue(game.faceUp.isEmpty)
        XCTAssertEqual(game.flip(0, now: 2), .ignored, "已配对的禁点")
        XCTAssertEqual(game.flip(9, now: 2), .ignored)
        XCTAssertEqual(game.moves, 1)
    }

    func testMismatchWaitsThenFlipsBackAndIgnoresClicksMeanwhile() throws {
        var game = try fixed()
        game.flip(1, now: 10)
        XCTAssertEqual(game.flip(2, now: 11), .mismatched)
        XCTAssertEqual(game.moves, 1)
        XCTAssertEqual(game.state(1), .wrong)
        XCTAssertEqual(game.state(2), .wrong)
        XCTAssertTrue(game.isWaiting(now: 11.5))
        // 等的这段时间里连点都不算：不翻、不加步。
        XCTAssertEqual(game.flip(3, now: 11.2), .ignored)
        XCTAssertEqual(game.flip(4, now: 11.79), .ignored)
        XCTAssertEqual(game.moves, 1)
        XCTAssertFalse(game.settle(now: 11.5), "没等够不翻回")
        XCTAssertEqual(game.state(1), .wrong)
        XCTAssertTrue(game.settle(now: 11 + ShibaMatchGame.mismatchDelay))
        XCTAssertEqual(game.state(1), .hidden)
        XCTAssertEqual(game.state(2), .hidden)
        XCTAssertFalse(game.settle(now: 20), "翻回过了就没事可做")
    }

    func testClickAfterTheDelayFlipsBackFirstThenStartsANewTurn() throws {
        var game = try fixed()
        game.flip(1, now: 10)
        game.flip(2, now: 11)
        // 没调 settle（比如界面的定时没跑），够时间后直接点下一张也行。
        XCTAssertEqual(game.flip(4, now: 12), .first)
        XCTAssertEqual(game.state(1), .hidden)
        XCTAssertEqual(game.state(2), .hidden)
        XCTAssertEqual(game.state(4), .faceUp)
        XCTAssertNil(game.mismatchAt)
    }

    func testClockGoingBackwardsDoesNotLockTheBoard() throws {
        var game = try fixed()
        game.flip(1, now: 1000)
        game.flip(2, now: 1000)
        XCTAssertFalse(game.isWaiting(now: 500), "系统时间往回拨了按已经等够算")
        XCTAssertEqual(game.flip(4, now: 500), .first)
    }

    func testOutOfRangeIsIgnored() throws {
        var game = try fixed()
        XCTAssertEqual(game.flip(-1, now: 0), .ignored)
        XCTAssertEqual(game.flip(12, now: 0), .ignored)
        XCTAssertEqual(game.status, .ready, "点空不开始计时")
        XCTAssertNil(game.startedAt)
    }

    func testWinningStopsTheClockAndCountsMoves() throws {
        var game = try fixed()
        var t = 100.0
        // 先错一次，再把六对都配上：7 步。
        game.flip(1, now: t); t += 1
        game.flip(2, now: t); t += 1
        var last = ShibaMatchGame.FlipResult.ignored
        for (a, b) in pairs {
            game.flip(a, now: t); t += 1
            last = game.flip(b, now: t); t += 1
        }
        XCTAssertEqual(last, .won)
        XCTAssertEqual(game.status, .won)
        XCTAssertEqual(game.moves, 7)
        XCTAssertEqual(game.pairsFound, 6)
        let ended = try XCTUnwrap(game.endedAt)
        XCTAssertEqual(game.elapsed(now: ended + 500), ended - 100, "完成后计时停住")
        XCTAssertEqual(game.flip(0, now: t), .ignored, "完成后点哪都不算")
    }

    func testElapsedBeforeStartIsZeroAndRunsWhilePlaying() throws {
        var game = try fixed()
        XCTAssertEqual(game.elapsed(now: 999), 0)
        game.flip(0, now: 50)
        XCTAssertEqual(game.elapsed(now: 78), 28)
        XCTAssertEqual(game.elapsed(now: 10), 0, "时间往回拨不出负数")
    }

    func testIdleTimeIsNotCounted() throws {
        var game = try fixed()
        game.flip(0, now: 100)
        XCTAssertEqual(game.elapsed(now: 110), 10)
        XCTAssertEqual(game.elapsed(now: 1000), ShibaMatchGame.idleCap, "离开后计时停在上次翻牌后 idleCap 秒")
        game.flip(3, now: 1000)
        XCTAssertEqual(game.elapsed(now: 1000), ShibaMatchGame.idleCap, "回来接着翻从停住的地方继续")
        XCTAssertEqual(game.elapsed(now: 1005), ShibaMatchGame.idleCap + 5)
        let data = try JSONEncoder().encode(game)
        let back = try JSONDecoder().decode(ShibaMatchGame.self, from: data)
        XCTAssertEqual(back.elapsed(now: 1005), ShibaMatchGame.idleCap + 5, "存档后扣掉的离开时间还在")
    }

    // MARK: 存档

    func testRoundTripKeepsAGameInProgress() throws {
        var game = try fixed()
        game.flip(0, now: 1)
        game.flip(9, now: 2)
        game.flip(1, now: 3)
        game.flip(2, now: 4)
        var config = WidgetConfig()
        ShibaMatch.store(game, in: &config)
        XCTAssertEqual(ShibaMatch.stored(config), game)
        XCTAssertEqual(ShibaMatch.game(config), game, "读回同一盘，不重新洗牌")
        XCTAssertTrue(config.string(ShibaMatch.gameKey(.standard)).contains("shiba"))
    }

    func testMissingOrBrokenSaveFallsBackToANewGame() {
        var config = WidgetConfig()
        XCTAssertNil(ShibaMatch.stored(config))
        XCTAssertEqual(ShibaMatch.game(config).status, .ready)
        let key = ShibaMatch.gameKey(.standard)
        let broken = [
            "{oops",
            #"{"r":3,"c":4,"k":"shiba,paw","m":"000000000000","n":0}"#,
            // 一种图案三张。
            #"{"r":3,"c":4,"k":"shiba,shiba,shiba,paw,bone,bone,house,house,ball,ball,bowl,bowl","m":"000000000000","n":0}"#,
            // 一对只配上了一张。
            #"{"r":3,"c":4,"k":"shiba,paw,bone,paw,house,ball,house,bowl,ball,shiba,bone,bowl","m":"100000000000","n":1,"t0":1}"#,
            // 翻着两张却没在等。
            #"{"r":3,"c":4,"k":"shiba,paw,bone,paw,house,ball,house,bowl,ball,shiba,bone,bowl","m":"000000000000","u":[1,2],"n":1,"t0":1}"#,
            // 有进度却没开始时间。
            #"{"r":3,"c":4,"k":"shiba,paw,bone,paw,house,ball,house,bowl,ball,shiba,bone,bowl","m":"100000000100","n":1}"#,
            // 全配完了却没结束时间。
            #"{"r":3,"c":4,"k":"shiba,paw,bone,paw,house,ball,house,bowl,ball,shiba,bone,bowl","m":"111111111111","n":6,"t0":1}"#,
            // 步数比配上的对数还少。
            #"{"r":3,"c":4,"k":"shiba,paw,bone,paw,house,ball,house,bowl,ball,shiba,bone,bowl","m":"100000000100","n":0,"t0":1}"#,
            // 认不出的图案。
            #"{"r":3,"c":4,"k":"shiba,paw,bone,paw,house,ball,house,bowl,ball,shiba,bone,cat","m":"000000000000","n":0}"#,
            // 规格不合法。
            #"{"r":3,"c":3,"k":"shiba","m":"0","n":0}"#,
        ]
        for raw in broken {
            config.set(key, .string(raw))
            XCTAssertNil(ShibaMatch.stored(config), raw)
            let fallback = ShibaMatch.game(config)
            XCTAssertEqual(fallback.status, .ready, raw)
            XCTAssertEqual(fallback.cards.count, 12, raw)
        }
    }

    func testASaveOfAnotherSpecIsNotReadAsThisOne() {
        var config = WidgetConfig()
        var rng = Seeded(state: 1)
        let medium = ShibaMatchGame(spec: .medium, using: &rng)
        ShibaMatch.store(medium, in: &config)
        XCTAssertEqual(ShibaMatch.stored(config, spec: .medium), medium, "存在各自的键下")
        XCTAssertNil(ShibaMatch.stored(config, spec: .standard))
        XCTAssertEqual(ShibaMatch.gameKey(.medium), "game.4x4")
    }

    func testRestoredMismatchFlipsBackWhenSettled() throws {
        var game = try fixed()
        game.flip(1, now: 10)
        game.flip(2, now: 10.2)
        var config = WidgetConfig()
        ShibaMatch.store(game, in: &config)
        // 面板关了过了很久再打开：等着的两张一 settle 就翻回去。
        XCTAssertTrue(ShibaMatch.settle(in: &config, now: 5000))
        let restored = try XCTUnwrap(ShibaMatch.stored(config))
        XCTAssertEqual(restored.state(1), .hidden)
        XCTAssertEqual(restored.moves, 1)
        XCTAssertFalse(ShibaMatch.settle(in: &config, now: 5001))
    }

    // MARK: 通过配置玩

    func testApplyWritesBackAndPlaysTheRightSounds() throws {
        var config = WidgetConfig()
        let dealt = try fixed()
        ShibaMatch.store(dealt, in: &config)
        let first = ShibaMatch.apply(flip: 0, to: &config, now: 1)
        XCTAssertEqual(first.result, .first)
        XCTAssertEqual(first.sound, .flip)
        XCTAssertFalse(first.needsSettle)
        let miss = ShibaMatch.apply(flip: 1, to: &config, now: 2)
        XCTAssertEqual(miss.result, .mismatched)
        XCTAssertNil(miss.sound, "没配上不放声")
        XCTAssertTrue(miss.needsSettle)
        let ignored = ShibaMatch.apply(flip: 3, to: &config, now: 2.3)
        XCTAssertEqual(ignored.result, .ignored, "等翻回去时快速连点不算")
        XCTAssertNil(ignored.sound)
        XCTAssertTrue(ShibaMatch.settle(in: &config, now: 2.9))
        ShibaMatch.apply(flip: 0, to: &config, now: 3)
        let hit = ShibaMatch.apply(flip: 9, to: &config, now: 4)
        XCTAssertEqual(hit.result, .matched)
        XCTAssertEqual(hit.sound, .match)
        XCTAssertEqual(ShibaMatch.game(config).pairsFound, 1)
        XCTAssertEqual(ShibaMatch.game(config).moves, 2)
    }

    func testApplyOnAFreshConfigDealsWithTheInjectedSeed() {
        var config = WidgetConfig()
        var rng = Seeded(state: 9)
        ShibaMatch.apply(flip: 5, to: &config, now: 1, using: &rng)
        var again = Seeded(state: 9)
        let expected = ShibaMatchGame(using: &again)
        XCTAssertEqual(ShibaMatch.game(config).cards, expected.cards)
        XCTAssertEqual(ShibaMatch.game(config).state(5), .faceUp)
    }

    /// 从 `start` 开始用 `extra` 次失误、最后把六对配完，返回最后一下的结果。
    @discardableResult
    private func play(_ config: inout WidgetConfig, start: Double, seconds: Double, misses: Int) throws -> ShibaMatch.Outcome {
        let dealt = try fixed()
        ShibaMatch.store(dealt, in: &config)
        var t = start
        for _ in 0..<misses {
            ShibaMatch.apply(flip: 1, to: &config, now: t)
            ShibaMatch.apply(flip: 2, to: &config, now: t)
            t += 1
        }
        var outcome = ShibaMatch.Outcome(result: .ignored, newRecord: false)
        // 配对均匀摊到 start + seconds，两次翻牌间隔不超过 idleCap，用时就正好是 seconds。
        let from = t
        for (index, pair) in pairs.enumerated() {
            let time = from + (start + seconds - from) * Double(index) / Double(pairs.count - 1)
            ShibaMatch.apply(flip: pair.0, to: &config, now: time)
            outcome = ShibaMatch.apply(flip: pair.1, to: &config, now: time)
        }
        return outcome
    }

    func testBestRecordIsFewestMovesThenFastest() throws {
        var config = WidgetConfig()
        XCTAssertNil(ShibaMatch.best(config))
        var outcome = try play(&config, start: 100, seconds: 40, misses: 2)
        XCTAssertEqual(outcome.result, .won)
        XCTAssertEqual(outcome.sound, .win)
        XCTAssertTrue(outcome.newRecord, "第一次完成就是纪录")
        XCTAssertEqual(ShibaMatch.best(config)?.moves, 8)
        XCTAssertEqual(ShibaMatch.best(config)?.seconds, 40)
        XCTAssertTrue(ShibaMatch.isRecord(ShibaMatch.game(config), in: config))

        // 步数更多，再快也不算。
        outcome = try play(&config, start: 1000, seconds: 10, misses: 3)
        XCTAssertFalse(outcome.newRecord)
        XCTAssertEqual(ShibaMatch.best(config)?.moves, 8)
        XCTAssertFalse(ShibaMatch.isRecord(ShibaMatch.game(config), in: config))

        // 步数一样，更快的算。
        outcome = try play(&config, start: 2000, seconds: 30, misses: 2)
        XCTAssertTrue(outcome.newRecord)
        XCTAssertEqual(ShibaMatch.best(config)?.seconds, 30)

        // 步数一样、用时一样，不算新纪录。
        outcome = try play(&config, start: 3000, seconds: 30, misses: 2)
        XCTAssertFalse(outcome.newRecord)

        // 步数更少的算，哪怕更慢。
        outcome = try play(&config, start: 4000, seconds: 90, misses: 0)
        XCTAssertTrue(outcome.newRecord)
        XCTAssertEqual(ShibaMatch.best(config)?.moves, 6)
        XCTAssertEqual(ShibaMatch.best(config)?.seconds, 90)
    }

    func testRecordComparison() {
        let base = ShibaRecord(moves: 10, seconds: 30, date: 0)
        XCTAssertTrue(base.isBetter(than: nil))
        XCTAssertTrue(ShibaRecord(moves: 9, seconds: 99, date: 0).isBetter(than: base))
        XCTAssertFalse(ShibaRecord(moves: 11, seconds: 1, date: 0).isBetter(than: base))
        XCTAssertTrue(ShibaRecord(moves: 10, seconds: 29.9, date: 0).isBetter(than: base))
        XCTAssertFalse(ShibaRecord(moves: 10, seconds: 30, date: 0).isBetter(than: base))
    }

    func testBrokenBestIsIgnored() {
        var config = WidgetConfig([ShibaMatch.bestKey(.standard): .string("[oops")])
        XCTAssertNil(ShibaMatch.best(config))
        config.set(ShibaMatch.bestKey(.standard), .string(#"{"moves":0,"seconds":3,"date":1}"#))
        XCTAssertNil(ShibaMatch.best(config), "0 步不可能")
        XCTAssertEqual(ShibaMatch.bestKey(.standard), "best.3x4")
    }

    func testRestartDealsANewGameAndKeepsRecordAndSound() throws {
        var config = WidgetConfig()
        try play(&config, start: 0, seconds: 20, misses: 1)
        ShibaMatch.setSound(false, in: &config)
        let best = ShibaMatch.best(config)
        var rng = Seeded(state: 3)
        ShibaMatch.restart(in: &config, using: &rng)
        let game = ShibaMatch.game(config)
        XCTAssertEqual(game.status, .ready)
        XCTAssertEqual(game.moves, 0)
        XCTAssertEqual(ShibaMatch.best(config), best)
        XCTAssertFalse(ShibaMatch.soundOn(config))
        XCTAssertFalse(ShibaMatch.isRecord(game, in: config))
    }

    func testRestartAsksForConfirmationOnlyMidGame() throws {
        var game = try fixed()
        XCTAssertFalse(ShibaMatch.restartNeedsConfirm(game), "没开始直接重开")
        game.flip(0, now: 0)
        XCTAssertTrue(ShibaMatch.restartNeedsConfirm(game))
        for (a, b) in pairs {
            game.flip(a, now: 1)
            game.flip(b, now: 1)
        }
        XCTAssertEqual(game.status, .won)
        XCTAssertFalse(ShibaMatch.restartNeedsConfirm(game), "完成后直接再来一盘")
        XCTAssertGreaterThan(ShibaMatch.restartConfirmWindow, 0)
    }

    func testSoundDefaultsOnLikeMinesweeper() {
        var config = WidgetConfig()
        XCTAssertTrue(ShibaMatch.soundOn(config))
        ShibaMatch.setSound(false, in: &config)
        XCTAssertFalse(ShibaMatch.soundOn(config))
        XCTAssertEqual(config.values[ShibaMatch.soundKey], .bool(false))
        XCTAssertEqual(ShibaSound.flip.systemName, "Tink")
        XCTAssertEqual(Set(ShibaSound.allCases.map(\.systemName)).count, 3)
    }

    // MARK: 文案

    func testStatusLines() throws {
        var game = try fixed()
        XCTAssertEqual(ShibaMatch.statusLine(game), "未开始")
        XCTAssertEqual(ShibaMatch.statusWord(game), "未开始")
        XCTAssertEqual(ShibaMatch.entryTitle(game), "开始游戏")
        game.flip(0, now: 0)
        game.flip(9, now: 1)
        game.flip(1, now: 2)
        game.flip(3, now: 3)
        game.flip(2, now: 4)
        game.flip(10, now: 5)
        XCTAssertEqual(ShibaMatch.statusLine(game), "进行中 · 已配对 3/6")
        XCTAssertEqual(ShibaMatch.progressText(game), "3/6")
        XCTAssertEqual(ShibaMatch.entryTitle(game), "继续游戏")
        XCTAssertEqual(ShibaMatch.entryShortTitle(game), "继续")
        game.flip(4, now: 6); game.flip(6, now: 7)
        game.flip(5, now: 8); game.flip(8, now: 9)
        game.flip(7, now: 10); game.flip(11, now: 38)
        XCTAssertEqual(ShibaMatch.statusLine(game), "完成 · 6 步")
        XCTAssertEqual(ShibaMatch.statusWord(game), "完成")
        XCTAssertEqual(ShibaMatch.entryTitle(game), "再来一盘")
        XCTAssertEqual(ShibaMatch.resultDetail(game), "6 步 · 用时 00:38")
    }

    func testClockAndReadouts() throws {
        XCTAssertEqual(ShibaMatch.clockText(seconds: 0), "00:00")
        XCTAssertEqual(ShibaMatch.clockText(seconds: 28.9), "00:28")
        XCTAssertEqual(ShibaMatch.clockText(seconds: 754), "12:34")
        XCTAssertEqual(ShibaMatch.clockText(seconds: 1e12), "99:59", "太大也不崩")
        XCTAssertEqual(ShibaMatch.clockText(seconds: -3), "00:00")
        XCTAssertEqual(ShibaMatch.clockText(seconds: .nan), "00:00")
        XCTAssertEqual(ShibaMatch.clockText(seconds: .infinity), "00:00")
        XCTAssertEqual(ShibaMatch.movesText(12), "步数 12")
        XCTAssertEqual(ShibaMatch.bestText(nil), "最佳 暂无")
        XCTAssertEqual(ShibaMatch.bestText(ShibaRecord(moves: 14, seconds: 42, date: 0)), "最佳 14 步")
        XCTAssertEqual(ShibaMatch.bestDetail(ShibaRecord(moves: 14, seconds: 42, date: 0)), "14 步 · 00:42")
        var game = try fixed()
        game.flip(0, now: 100)
        XCTAssertEqual(ShibaMatch.timeText(game, now: 128), "用时 00:28")
        XCTAssertEqual(ShibaMatch.resultTitle(newRecord: true), "新纪录！")
        XCTAssertEqual(ShibaMatch.resultTitle(newRecord: false), "全部配对完成！")
    }

    func testCardAccessibilityLabels() throws {
        var game = try fixed()
        XCTAssertEqual(ShibaMatch.cardLabel(game, index: 6), "第 2 行第 3 张，未翻开")
        game.flip(2, now: 0)
        XCTAssertEqual(ShibaMatch.cardLabel(game, index: 2), "第 1 行第 3 张，骨头")
        game.flip(10, now: 1)
        XCTAssertEqual(ShibaMatch.cardLabel(game, index: 2), "骨头，已配对")
        XCTAssertEqual(ShibaMatch.cardLabel(game, index: 99), "")
    }

    func testEveryFaceHasAFallbackAndAnImageName() {
        for face in ShibaFace.allCases {
            XCTAssertFalse(face.emoji.isEmpty, face.rawValue)
            XCTAssertFalse(face.title.isEmpty, face.rawValue)
            XCTAssertEqual(face.imageName, "match-\(face.rawValue)")
        }
        XCTAssertEqual(Set(ShibaFace.allCases.map(\.emoji)).count, ShibaFace.allCases.count, "缺图时也分得清")
        XCTAssertEqual(ShibaMatch.faceFallbackImage, "notch-shiba-peek", "柴犬脸缺图时用柴犬母版")
    }

    func testOnlyConfirmedShibaMasterArtIsUsed() {
        let names = [ShibaMatchArt.avatar, ShibaMatchArt.lying, ShibaMatchArt.cheer]
            + [ShibaMatchGame.Status.ready, .playing, .won].map(ShibaMatchArt.tile)
        for name in names {
            XCTAssertTrue(name.contains("shiba"), name)
        }
        XCTAssertEqual(Set([ShibaMatchGame.Status.ready, .playing, .won].map(ShibaMatchArt.tile)).count, 3)
    }

    func testAccentColoursAreReadable() throws {
        let light = try XCTUnwrap(ColorCode(hex: ShibaMatch.accentLightHex))
        let dark = try XCTUnwrap(ColorCode(hex: ShibaMatch.accentDarkHex))
        XCTAssertGreaterThanOrEqual(WidgetTint.contrastRatio(light, WidgetTint.lightCard), 4.5)
        XCTAssertGreaterThanOrEqual(WidgetTint.contrastRatio(dark, WidgetTint.darkCard), 4.5)
        let fill = try XCTUnwrap(ColorCode(hex: ShibaMatch.accentHex))
        let ink = try XCTUnwrap(ColorCode(hex: PaperInk.ink(on: ShibaMatch.accentHex)))
        XCTAssertGreaterThanOrEqual(WidgetTint.contrastRatio(ink, fill), 4.5, "入口胶囊上的字")
    }

    // MARK: 尺寸

    func testPanelBoardFitsTheCardAndKeepsCardsTappable() {
        XCTAssertEqual(ShibaMatch.panelWidth, 340)
        XCTAssertEqual(ShibaMatch.panelContentWidth, 266, accuracy: 0.001)
        for spec in [ShibaBoardSpec.standard, .medium, .hard] {
            let layout = ShibaMatch.panelLayout(spec)
            XCTAssertLessThanOrEqual(layout.width, ShibaMatch.panelContentWidth, spec.key)
            XCTAssertGreaterThanOrEqual(min(layout.cardWidth, layout.cardHeight), ShibaMatch.minimumHitSide, spec.key)
            XCTAssertLessThanOrEqual(layout.height, 300, spec.key)
        }
        let standard = ShibaMatch.panelLayout()
        XCTAssertEqual(standard.cardWidth, 60)
        XCTAssertEqual(standard.cardHeight, 64)
        // 底部趴着的柴犬加两行读数放得下（读数胶囊至少要 180 宽）。
        XCTAssertGreaterThanOrEqual(ShibaMatch.panelContentWidth - ShibaMatch.panelLyingShibaWidth - 8, 180)
    }

    func testHitIndexAndKeyboardMovement() {
        let layout = ShibaMatch.panelLayout()
        let pitchX = layout.cardWidth + layout.gap, pitchY = layout.cardHeight + layout.gap
        XCTAssertEqual(layout.hitIndex(x: 1, y: 1), 0)
        XCTAssertEqual(layout.hitIndex(x: pitchX + 1, y: 1), 1)
        XCTAssertEqual(layout.hitIndex(x: 1, y: pitchY * 2 + 1), 8)
        XCTAssertEqual(layout.hitIndex(x: pitchX * 3 + 1, y: pitchY * 2 + 1), 11)
        XCTAssertNil(layout.hitIndex(x: layout.cardWidth + layout.gap / 2, y: 1), "缝里不算")
        XCTAssertNil(layout.hitIndex(x: -1, y: 1))
        XCTAssertNil(layout.hitIndex(x: layout.width + 1, y: 1))
        XCTAssertNil(layout.hitIndex(x: 1, y: layout.height + 1))
        let origin = layout.origin(5)
        XCTAssertEqual(origin.x, pitchX)
        XCTAssertEqual(origin.y, pitchY)
        XCTAssertEqual(layout.move(0, row: 0, column: 1), 1)
        XCTAssertEqual(layout.move(0, row: 1, column: 0), 4)
        XCTAssertEqual(layout.move(0, row: -1, column: -1), 0, "到边就停")
        XCTAssertEqual(layout.move(11, row: 1, column: 1), 11)
        XCTAssertEqual(layout.move(3, row: 0, column: 1), 3, "不绕到下一行")
    }

    func testTileSizes() throws {
        XCTAssertEqual(ShibaMatch.tileWidth, 176)
        XCTAssertEqual(ShibaMatch.tileHeight, 62)
        XCTAssertEqual(ShibaMatch.columnHeight, 120)
        let card = try XCTUnwrap(WidgetCatalog.make(.shibaMatch))
        XCTAssertEqual(WidgetCatalog.contentSize(card, position: .bottom).width, ShibaMatch.tileWidth)
        XCTAssertEqual(WidgetCatalog.contentSize(card, position: .left).height, ShibaMatch.columnHeight)
    }

    func testDesktopPlan() {
        XCTAssertTrue(DesktopCardsShibaPlan.handles(.shibaMatch))
        XCTAssertFalse(DesktopCardsShibaPlan.handles(.minesweeper))
        XCTAssertFalse(DesktopCardsToothPlan.handles(.shibaMatch))
        XCTAssertFalse(DesktopCardsGamesPlan.handles(.shibaMatch))
        XCTAssertEqual(DesktopPinSupport.mode(.shibaMatch, hasDetail: true, panelWidth: ShibaMatch.panelWidth), .dedicated)
        XCTAssertNil(DesktopCardsShibaPlan.layout(for: .small), "小号只显示状态")
        XCTAssertFalse(DesktopCardsShibaPlan.isPlayable(.small))
        for size in [DesktopPinSize.medium, .large] {
            guard let layout = DesktopCardsShibaPlan.layout(for: size) else { return XCTFail("\(size)") }
            XCTAssertTrue(DesktopCardsShibaPlan.isPlayable(size))
            let inset = DesktopCardsShibaPlan.inset(size)
            XCTAssertGreaterThanOrEqual(min(layout.cardWidth, layout.cardHeight), ShibaMatch.minimumHitSide, "\(size)")
            XCTAssertLessThanOrEqual(layout.height, size.height - inset * 2, "\(size)")
            if size == .medium {
                XCTAssertLessThanOrEqual(layout.width + DesktopCardsShibaPlan.mediumSpacing + DesktopCardsShibaPlan.mediumSideWidth,
                                         size.width - inset * 2)
            } else {
                XCTAssertLessThanOrEqual(layout.width, size.width - inset * 2)
                XCTAssertLessThanOrEqual(layout.height + DesktopCardsShibaPlan.headerHeight + DesktopCardsShibaPlan.headerSpacing,
                                         size.height - inset * 2)
            }
        }
    }

    // MARK: 目录

    func testCatalogEntry() throws {
        let entry = try XCTUnwrap(WidgetCatalog.entry(.shibaMatch))
        XCTAssertEqual(entry.name, "柴犬翻翻乐")
        XCTAssertEqual(entry.category, .games)
        XCTAssertTrue(entry.selfContained)
        XCTAssertTrue(WidgetCatalog.configurableKeys(.shibaMatch).isEmpty, "局、纪录和音效不进设置页")
        XCTAssertFalse(ProFeatures.isProKind(.shibaMatch), "免费，和扫雷、拔牙一样")
        XCTAssertTrue(ProLicenseGate.canAdd(.shibaMatch, overrides: [:], unlocked: false))
        XCTAssertNil(WidgetCatalog.openTarget(.shibaMatch), "点卡片打开面板")
        XCTAssertTrue(WidgetLibraryGroups.isNew(.shibaMatch))
        XCTAssertEqual(WidgetKind.shibaMatch.rawValue, "shiba-match")
        XCTAssertEqual(WidgetKind(rawValue: "shiba-match"), .shibaMatch)
        let keywords = WidgetSearch.keywords["shiba-match"] ?? []
        XCTAssertTrue(keywords.contains("柴犬翻翻乐"))
        XCTAssertTrue(keywords.contains("翻牌"))
    }
}
