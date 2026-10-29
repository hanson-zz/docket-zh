import XCTest
@testable import Docket

/// 扫雷的规则（Core 的 `MineBoard`、`Minesweeper`）：首击安全、0 扩散、插旗、和弦、
/// 胜负、计时、存进卡片配置、最佳成绩，以及卡片、面板、桌面卡片的尺寸。
final class MinesweeperTests: XCTestCase {

    // MARK: 难度

    func testLevels() {
        XCTAssertEqual(MineLevel.beginner.rows, 9)
        XCTAssertEqual(MineLevel.beginner.columns, 9)
        XCTAssertEqual(MineLevel.beginner.mines, 10)
        XCTAssertEqual(MineLevel.intermediate.rows, 16)
        XCTAssertEqual(MineLevel.intermediate.columns, 16)
        XCTAssertEqual(MineLevel.intermediate.mines, 40)
        XCTAssertEqual(MineLevel.beginner.title, "初级")
        XCTAssertEqual(MineLevel.intermediate.detail, "16×16 · 40 雷")
        XCTAssertEqual(MineBoard(level: .intermediate).level, .intermediate)
    }

    // MARK: 随机数

    func testSeededRandomIsRepeatable() {
        var a = MineRandom(seed: 42), b = MineRandom(seed: 42), c = MineRandom(seed: 43)
        let first = (0..<5).map { _ in a.next() }
        XCTAssertEqual(first, (0..<5).map { _ in b.next() })
        XCTAssertNotEqual(first, (0..<5).map { _ in c.next() })
    }

    func testSameSeedSameBoard() {
        func play(_ seed: UInt64) -> [Bool] {
            var board = MineBoard(level: .intermediate)
            var rng = MineRandom(seed: seed)
            board.reveal(100, now: 0, using: &rng)
            return board.mines
        }
        XCTAssertEqual(play(7), play(7))
        XCTAssertNotEqual(play(7), play(8))
    }

    // MARK: 首击安全

    func testFirstClickAndItsNeighboursAreNeverMines() {
        for level in MineLevel.allCases {
            for seed in UInt64(0)..<60 {
                var board = MineBoard(level: level)
                var rng = MineRandom(seed: seed)
                let first = Int(seed) % board.cellCount
                XCTAssertTrue(board.reveal(first, now: 10, using: &rng))
                XCTAssertEqual(board.mines.filter { $0 }.count, level.mines, "雷数正好")
                XCTAssertFalse(board.isMine(first))
                for n in board.neighbors(of: first) { XCTAssertFalse(board.isMine(n), "首击周围无雷") }
                XCTAssertEqual(board.adjacentMines(first), 0)
                XCTAssertNotEqual(board.status, .lost)
                XCTAssertTrue(board.revealed[first])
                XCTAssertGreaterThan(board.revealed.filter { $0 }.count, 1, "首击是 0，至少往外扩一圈")
            }
        }
    }

    func testCrowdedBoardStillKeepsTheFirstCellSafe() {
        // 3×3 放 8 颗雷：避不开一圈，至少点的那一格安全。
        var board = MineBoard(rows: 3, columns: 3, mines: 8)
        var rng = MineRandom(seed: 1)
        board.reveal(4, now: 0, using: &rng)
        XCTAssertFalse(board.isMine(4))
        XCTAssertEqual(board.mines.filter { $0 }.count, 8)
        XCTAssertEqual(board.status, .won, "唯一的安全格揭开就赢")
    }

    func testMinesClampToLeaveOneSafeCell() {
        XCTAssertEqual(MineBoard(rows: 3, columns: 3, mines: 50).mineCount, 8)
        XCTAssertEqual(MineBoard(rows: 3, columns: 3, mines: 0).mineCount, 1)
    }

    // MARK: 邻居和数字

    func testNeighbours() {
        let board = MineBoard(level: .beginner)
        XCTAssertEqual(Set(board.neighbors(of: 0)), [1, 9, 10], "角上 3 个")
        XCTAssertEqual(board.neighbors(of: 4).count, 5, "边上 5 个")
        XCTAssertEqual(board.neighbors(of: 40).count, 8, "中间 8 个")
        XCTAssertEqual(board.neighbors(of: 81), [])
    }

    func testAdjacentCountsAndFaces() {
        // 3×3，雷在左上角。
        let board = MineBoard.fixed(rows: 3, columns: 3, mines: [0])
        XCTAssertEqual(board.adjacentMines(1), 1)
        XCTAssertEqual(board.adjacentMines(4), 1)
        XCTAssertEqual(board.adjacentMines(8), 0)
        XCTAssertEqual(board.face(8), .hidden)
    }

    // MARK: 揭开和扩散

    func testZeroFloodFillsUpToNumbers() {
        // 4×4，雷在左上角：点右下角，除了雷全部揭开，直接赢。
        var board = MineBoard.fixed(rows: 4, columns: 4, mines: [0])
        board.reveal(15, now: 5)
        XCTAssertEqual(board.status, .won)
        XCTAssertFalse(board.revealed[0])
        XCTAssertEqual(board.face(5), .open(1))
        XCTAssertEqual(board.face(15), .open(0))
        XCTAssertTrue(board.flagged[0], "赢了自动插上剩下的旗")
        XCTAssertEqual(board.minesLeft, 0)
    }

    func testFloodStopsAtNumbersAndSkipsFlags() {
        // 5×5，中间一列第 0 行和第 4 行之间隔着雷墙（第 2 列全是雷）。
        let mines: Set<Int> = [2, 7, 12, 17, 22]
        var board = MineBoard.fixed(rows: 5, columns: 5, mines: mines)
        board.toggleFlag(5, now: 0)
        board.reveal(0, now: 1)
        XCTAssertTrue(board.revealed[0])
        XCTAssertFalse(board.revealed[5], "插了旗的不被扩散揭开")
        XCTAssertFalse(board.revealed[4], "雷墙另一边不动")
        XCTAssertEqual(board.status, .playing)
    }

    func testRevealingAMineLoses() {
        var board = MineBoard.fixed(rows: 3, columns: 3, mines: [0, 8], startedAt: 100)
        board.toggleFlag(1, now: 101)
        XCTAssertTrue(board.reveal(0, now: 112))
        XCTAssertEqual(board.status, .lost)
        XCTAssertEqual(board.exploded, 0)
        XCTAssertEqual(board.face(0), .exploded)
        XCTAssertEqual(board.face(8), .mine, "输了亮出其余的雷")
        XCTAssertEqual(board.face(1), .wrongFlag, "插错的旗打叉")
        XCTAssertEqual(board.elapsed(now: 999), 12, "计时停在输的那一刻")
        XCTAssertFalse(board.reveal(4, now: 113), "结束后不能再点")
        XCTAssertFalse(board.toggleFlag(4, now: 113))
    }

    func testFlaggedCellCannotBeRevealed() {
        var board = MineBoard.fixed(rows: 3, columns: 3, mines: [0])
        XCTAssertTrue(board.toggleFlag(0, now: 0))
        XCTAssertEqual(board.face(0), .flagged)
        XCTAssertFalse(board.reveal(0, now: 1))
        XCTAssertEqual(board.status, .playing)
        XCTAssertTrue(board.toggleFlag(0, now: 2), "再点一次拔旗")
        XCTAssertEqual(board.face(0), .hidden)
    }

    func testFlagsBeforeFirstClickDoNotStartTheGame() {
        var board = MineBoard(level: .beginner)
        XCTAssertTrue(board.toggleFlag(0, now: 5))
        XCTAssertEqual(board.status, .ready)
        XCTAssertNil(board.startedAt)
        XCTAssertEqual(board.minesLeft, 9)
        XCTAssertEqual(board.elapsed(now: 100), 0)
    }

    func testMinesLeftGoesNegativeWithTooManyFlags() {
        var board = MineBoard.fixed(rows: 3, columns: 3, mines: [0])
        board.toggleFlag(1, now: 0)
        board.toggleFlag(2, now: 0)
        XCTAssertEqual(board.minesLeft, -1)
    }

    // MARK: 和弦

    func testChordRevealsNeighboursWhenFlagsMatch() {
        // 3×3，雷在左上角；揭开中间（1），插好旗后点中间揭开其余。
        var board = MineBoard.fixed(rows: 3, columns: 3, mines: [0])
        board.reveal(4, now: 0)
        XCTAssertEqual(board.face(4), .open(1))
        XCTAssertFalse(board.chord(4, now: 1), "旗数不够不动")
        board.toggleFlag(0, now: 2)
        XCTAssertTrue(board.reveal(4, now: 3), "点揭开的数字就是和弦")
        XCTAssertEqual(board.status, .won)
    }

    func testFlagClickOnANumberAlsoChords() {
        var board = MineBoard.fixed(rows: 3, columns: 3, mines: [0])
        board.reveal(4, now: 0)
        board.toggleFlag(0, now: 1)
        XCTAssertTrue(board.toggleFlag(4, now: 2), "右键点数字也是和弦，不会插旗")
        XCTAssertFalse(board.flagged[4])
        XCTAssertEqual(board.status, .won)
    }

    func testChordWithAWrongFlagLoses() {
        // 雷在 0，旗插在 1：中间的 1 满足旗数，和弦揭开 0 踩雷。
        var board = MineBoard.fixed(rows: 3, columns: 3, mines: [0])
        board.reveal(4, now: 0)
        board.toggleFlag(1, now: 1)
        XCTAssertTrue(board.chord(4, now: 2))
        XCTAssertEqual(board.status, .lost)
        XCTAssertEqual(board.exploded, 0)
        XCTAssertEqual(board.face(1), .wrongFlag)
    }

    func testChordOnZeroOrHiddenDoesNothing() {
        var board = MineBoard.fixed(rows: 4, columns: 4, mines: [0, 3])
        XCTAssertFalse(board.chord(10, now: 0), "没揭开的不和弦")
        board.reveal(13, now: 0)
        XCTAssertEqual(board.face(13), .open(0))
        XCTAssertFalse(board.chord(13, now: 1), "0 不和弦")
    }

    // MARK: 计时

    func testTimerStartsOnFirstRevealAndStopsOnWin() {
        var board = MineBoard(rows: 3, columns: 3, mines: 8)
        XCTAssertEqual(board.elapsed(now: 50), 0)
        var rng = MineRandom(seed: 3)
        board.reveal(4, now: 100, using: &rng)
        XCTAssertEqual(board.startedAt, 100)
        XCTAssertEqual(board.elapsed(now: 9999), 0, "第一下就赢，0 秒")
    }

    func testDisplaySecondsCapsAt999() {
        let board = MineBoard.fixed(rows: 3, columns: 3, mines: [0], startedAt: 0)
        XCTAssertEqual(board.displaySeconds(now: 12.7), 12)
        XCTAssertEqual(board.displaySeconds(now: 5000), 999)
    }

    // MARK: 存进配置

    func testBoardRoundTripsThroughJSON() throws {
        var board = MineBoard(level: .beginner)
        var rng = MineRandom(seed: 9)
        board.reveal(40, now: 1000, using: &rng)
        if let mine = (0..<board.cellCount).first(where: { board.isMine($0) }) { board.toggleFlag(mine, now: 1001) }
        let data = try JSONEncoder().encode(board)
        let decoded = try JSONDecoder().decode(MineBoard.self, from: data)
        XCTAssertEqual(decoded, board)
        XCTAssertLessThan(data.count, 600, "初级一局存成一小段文字")
    }

    func testReadyBoardRoundTrips() throws {
        let board = MineBoard(level: .intermediate)
        let decoded = try JSONDecoder().decode(MineBoard.self, from: JSONEncoder().encode(board))
        XCTAssertEqual(decoded, board)
        XCTAssertEqual(decoded.status, .ready)
        XCTAssertTrue(decoded.mines.isEmpty)
    }

    func testBrokenOrMismatchedSavesFallBackToAFreshBoard() {
        var config = WidgetConfig([Minesweeper.gameKey(.beginner): .string("{oops")])
        XCTAssertEqual(Minesweeper.board(config, level: .beginner), MineBoard(level: .beginner))
        // 存的是中级的局，却按初级读：不认，给新的初级。
        Minesweeper.store(MineBoard(level: .intermediate), level: .beginner, in: &config)
        XCTAssertEqual(Minesweeper.board(config, level: .beginner), MineBoard(level: .beginner))
        // 尺寸对不上的格子串。
        config.set(Minesweeper.gameKey(.beginner), .string(#"{"r":9,"c":9,"n":10,"m":"","s":"hhh","st":"ready"}"#))
        XCTAssertEqual(Minesweeper.board(config, level: .beginner), MineBoard(level: .beginner))
    }

    func testLevelSelectionAndSeparateGames() {
        var config = WidgetConfig()
        XCTAssertEqual(Minesweeper.level(config), .beginner, "默认初级")
        var rng = MineRandom(seed: 5)
        Minesweeper.apply(.reveal, at: 40, level: .beginner, to: &config, now: 10, using: &rng)
        Minesweeper.select(.intermediate, in: &config)
        XCTAssertEqual(Minesweeper.level(config), .intermediate)
        XCTAssertEqual(Minesweeper.board(config, level: .intermediate).status, .ready)
        XCTAssertNotEqual(Minesweeper.board(config, level: .beginner).status, .ready, "换难度不丢另一局")
        config.set(Minesweeper.levelKey, .string("expert"))
        XCTAssertEqual(Minesweeper.level(config), .beginner, "认不出的难度按初级")
    }

    func testRestartGivesAFreshBoardButKeepsTheBest() {
        var config = WidgetConfig([Minesweeper.bestKey(.beginner): .number(30)])
        var rng = MineRandom(seed: 5)
        Minesweeper.apply(.reveal, at: 40, level: .beginner, to: &config, now: 10, using: &rng)
        Minesweeper.restart(.beginner, in: &config)
        XCTAssertEqual(Minesweeper.board(config, level: .beginner), MineBoard(level: .beginner))
        XCTAssertEqual(Minesweeper.best(config, level: .beginner), 30)
    }

    // MARK: 最佳成绩

    /// 把一局按固定种子打完（只点安全格），返回每一下的结果。
    private func win(_ level: MineLevel, seed: UInt64, start: Double, end: Double,
                     config: inout WidgetConfig) -> Minesweeper.Outcome {
        var rng = MineRandom(seed: seed)
        var outcome = Minesweeper.apply(.reveal, at: 0, level: level, to: &config, now: start, using: &rng)
        var board = Minesweeper.board(config, level: level)
        while board.status == .playing {
            guard let safe = (0..<board.cellCount).first(where: { !board.isMine($0) && !board.revealed[$0] }) else { break }
            outcome = Minesweeper.apply(.reveal, at: safe, level: level, to: &config, now: end, using: &rng)
            board = Minesweeper.board(config, level: level)
        }
        return outcome
    }

    func testWinningRecordsTheBestTime() {
        var config = WidgetConfig()
        XCTAssertNil(Minesweeper.best(config, level: .beginner))
        let first = win(.beginner, seed: 11, start: 100, end: 142.36, config: &config)
        XCTAssertTrue(first.justWon)
        XCTAssertTrue(first.newRecord)
        XCTAssertEqual(Minesweeper.best(config, level: .beginner), 42.4, "存到 0.1 秒")
        XCTAssertNil(Minesweeper.best(config, level: .intermediate), "各难度分开记")

        Minesweeper.restart(.beginner, in: &config)
        let slower = win(.beginner, seed: 12, start: 200, end: 260, config: &config)
        XCTAssertTrue(slower.justWon)
        XCTAssertFalse(slower.newRecord)
        XCTAssertEqual(Minesweeper.best(config, level: .beginner), 42.4)

        Minesweeper.restart(.beginner, in: &config)
        let faster = win(.beginner, seed: 13, start: 300, end: 320, config: &config)
        XCTAssertTrue(faster.newRecord)
        XCTAssertEqual(Minesweeper.best(config, level: .beginner), 20)
    }

    /// 9×9、10 雷全在第 0 行和第 1 行最左一格：点右下角一下就把其余格子全翻开、直接赢。
    private func oneClickBoard(startedAt: Double) -> MineBoard {
        MineBoard.fixed(rows: 9, columns: 9, mines: Set(0..<9).union([9]), startedAt: startedAt)
    }

    func testWinningOnTheFirstClickStillRecordsABest() {
        var config = WidgetConfig()
        Minesweeper.store(oneClickBoard(startedAt: 50), level: .beginner, in: &config)
        let outcome = Minesweeper.apply(.reveal, at: 80, level: .beginner, to: &config, now: 50)
        XCTAssertTrue(outcome.justWon)
        XCTAssertTrue(outcome.newRecord)
        XCTAssertEqual(Minesweeper.best(config, level: .beginner), 0.1, "用时 0 也要记下，不能当成暂无")
        XCTAssertTrue(Minesweeper.isRecord(Minesweeper.board(config, level: .beginner), level: .beginner, in: config))
    }

    func testOnlyTheRecordGameIsMarkedAsRecord() {
        var config = WidgetConfig()
        Minesweeper.store(oneClickBoard(startedAt: 100), level: .beginner, in: &config)
        XCTAssertTrue(Minesweeper.apply(.reveal, at: 80, level: .beginner, to: &config, now: 112.34).newRecord)
        XCTAssertEqual(Minesweeper.best(config, level: .beginner), 12.3)
        XCTAssertTrue(Minesweeper.isRecord(Minesweeper.board(config, level: .beginner), level: .beginner, in: config))

        // 平了纪录（四舍五入后也是 12.3 秒）：不是新纪录，面板也不能写「新纪录」。
        Minesweeper.store(oneClickBoard(startedAt: 200), level: .beginner, in: &config)
        let tie = Minesweeper.apply(.reveal, at: 80, level: .beginner, to: &config, now: 212.3)
        XCTAssertTrue(tie.justWon)
        XCTAssertFalse(tie.newRecord)
        XCTAssertEqual(tie.rank, 2, "平分排在原来那条后面")
        XCTAssertEqual(Minesweeper.rank(Minesweeper.board(config, level: .beginner), level: .beginner, in: config), 2)
        XCTAssertFalse(Minesweeper.isRecord(Minesweeper.board(config, level: .beginner), level: .beginner, in: config))

        Minesweeper.restart(.beginner, in: &config)
        XCTAssertFalse(Minesweeper.isRecord(Minesweeper.board(config, level: .beginner), level: .beginner, in: config))
    }

    func testIntermediateCanBeWonAndRecorded() {
        var config = WidgetConfig()
        let outcome = win(.intermediate, seed: 21, start: 0, end: 95, config: &config)
        XCTAssertTrue(outcome.justWon)
        XCTAssertEqual(Minesweeper.best(config, level: .intermediate), 95)
        XCTAssertEqual(Minesweeper.board(config, level: .intermediate).minesLeft, 0)
    }

    func testLosingDoesNotRecordAndReportsJustLost() {
        var config = WidgetConfig()
        var rng = MineRandom(seed: 4)
        Minesweeper.apply(.reveal, at: 0, level: .beginner, to: &config, now: 0, using: &rng)
        let board = Minesweeper.board(config, level: .beginner)
        let mine = try! XCTUnwrap((0..<board.cellCount).first { board.isMine($0) })
        let outcome = Minesweeper.apply(.reveal, at: mine, level: .beginner, to: &config, now: 3, using: &rng)
        XCTAssertTrue(outcome.justLost)
        XCTAssertFalse(outcome.newRecord)
        XCTAssertNil(Minesweeper.best(config, level: .beginner))
        let again = Minesweeper.apply(.reveal, at: 1, level: .beginner, to: &config, now: 4, using: &rng)
        XCTAssertFalse(again.changed, "结束后点了不变、不写")
    }

    func testBestText() {
        XCTAssertEqual(Minesweeper.bestText(nil), "暂无")
        XCTAssertEqual(Minesweeper.bestText(42.9), "42.9 秒")
        XCTAssertEqual(Minesweeper.scoreText(0.3), "0.3 秒", "存的 0.1 秒精度原样显示，不被浮点误差往下舍")
        XCTAssertEqual(Minesweeper.scoreText(12), "12.0 秒")
    }

    // MARK: 排行榜

    func testInsertKeepsTheTopFiveInOrder() {
        var list: [MineScore] = []
        for (i, seconds) in [30.0, 10, 20, 50, 40].enumerated() {
            let placed = Minesweeper.insert(MineScore(seconds: seconds, date: Double(i + 1)), into: list)
            list = placed.list
        }
        XCTAssertEqual(list.map(\.seconds), [10, 20, 30, 40, 50])
        // 比第 5 名慢：不进榜，榜不变。
        let slow = Minesweeper.insert(MineScore(seconds: 60, date: 9), into: list)
        XCTAssertNil(slow.rank)
        XCTAssertEqual(slow.list, list)
        // 平了第 5 名也挤不进去（排在它后面，被截掉）。
        XCTAssertNil(Minesweeper.insert(MineScore(seconds: 50, date: 9), into: list).rank)
        // 进到第 2 名：原来的第 5 名掉出去。
        let second = Minesweeper.insert(MineScore(seconds: 15, date: 9), into: list)
        XCTAssertEqual(second.rank, 2)
        XCTAssertEqual(second.list.map(\.seconds), [10, 15, 20, 30, 40])
        // 平了第一名排第 2。
        XCTAssertEqual(Minesweeper.insert(MineScore(seconds: 10, date: 9), into: list).rank, 2)
        XCTAssertEqual(Minesweeper.insert(MineScore(seconds: 9.9, date: 9), into: list).rank, 1)
    }

    func testLeaderboardIsStoredAsCompactJSONAndFollowsBest() throws {
        var config = WidgetConfig()
        Minesweeper.storeLeaderboard([MineScore(seconds: 20, date: 200), MineScore(seconds: 12.3, date: 100)],
                                     level: .beginner, in: &config)
        let raw = config.string(Minesweeper.topKey(.beginner), default: "")
        XCTAssertFalse(raw.contains(" "), "紧凑 JSON")
        XCTAssertTrue(raw.contains("\"s\""))
        XCTAssertEqual(Minesweeper.leaderboard(config, level: .beginner).map(\.seconds), [12.3, 20], "读出来按快到慢")
        XCTAssertEqual(config.double(Minesweeper.bestKey(.beginner), default: 0), 12.3, "best.* 跟着第一名")
        XCTAssertEqual(config.double(Minesweeper.bestAtKey(.beginner), default: 0), 100)
        XCTAssertTrue(Minesweeper.leaderboard(config, level: .intermediate).isEmpty, "各难度分开")

        let decoded = try JSONDecoder().decode([MineScore].self, from: Data(raw.utf8))
        XCTAssertEqual(decoded.count, 2)
        // 坏数据不崩：退回旧的 best.*。
        config.set(Minesweeper.topKey(.beginner), .string("[oops"))
        XCTAssertEqual(Minesweeper.leaderboard(config, level: .beginner), [MineScore(seconds: 12.3, date: 100)])
        // 超过 5 条、负数、0 都清掉。
        let many = (0..<8).map { MineScore(seconds: Double(8 - $0), date: Double($0 + 1)) } + [MineScore(seconds: 0, date: 1)]
        Minesweeper.storeLeaderboard(many, level: .beginner, in: &config)
        XCTAssertEqual(Minesweeper.leaderboard(config, level: .beginner).map(\.seconds), [1, 2, 3, 4, 5])
    }

    func testOldBestMigratesAsFirstPlace() {
        var config = WidgetConfig([Minesweeper.bestKey(.beginner): .number(42.4),
                                   Minesweeper.bestAtKey(.beginner): .number(142.36)])
        XCTAssertEqual(Minesweeper.leaderboard(config, level: .beginner), [MineScore(seconds: 42.4, date: 142.36)])
        XCTAssertEqual(Minesweeper.best(config, level: .beginner), 42.4)
        // 只有 best.* 的更早配置：日期未知。
        let bare = WidgetConfig([Minesweeper.bestKey(.intermediate): .number(95)])
        let first = Minesweeper.leaderboard(bare, level: .intermediate).first
        XCTAssertEqual(first?.seconds, 95)
        XCTAssertEqual(first?.hasDate, false)

        // 再赢一局：旧的第一名和新成绩一起写进 top.*。
        Minesweeper.store(oneClickBoard(startedAt: 500), level: .beginner, in: &config)
        let outcome = Minesweeper.apply(.reveal, at: 80, level: .beginner, to: &config, now: 560)
        XCTAssertEqual(outcome.rank, 2)
        XCTAssertFalse(outcome.newRecord)
        XCTAssertEqual(Minesweeper.leaderboard(config, level: .beginner).map(\.seconds), [42.4, 60])
        XCTAssertFalse(config.string(Minesweeper.topKey(.beginner), default: "").isEmpty)
        XCTAssertEqual(Minesweeper.best(config, level: .beginner), 42.4)
    }

    func testWinsFillTheLeaderboardAndReportTheirRank() {
        var config = WidgetConfig()
        var ranks: [Int?] = []
        for (i, seconds) in [30.0, 20, 40, 10, 50, 60, 25].enumerated() {
            let start = Double(i * 1000)
            Minesweeper.store(oneClickBoard(startedAt: start), level: .beginner, in: &config)
            ranks.append(Minesweeper.apply(.reveal, at: 80, level: .beginner, to: &config, now: start + seconds).rank)
        }
        XCTAssertEqual(ranks, [1, 1, 3, 1, 5, nil, 3])
        XCTAssertEqual(Minesweeper.leaderboard(config, level: .beginner).map(\.seconds), [10, 20, 25, 30, 40])
        let last = Minesweeper.board(config, level: .beginner)
        XCTAssertEqual(Minesweeper.rank(last, level: .beginner, in: config), 3, "刚进榜的就是这一局")
        XCTAssertFalse(Minesweeper.isRecord(last, level: .beginner, in: config))
        XCTAssertEqual(Minesweeper.best(config, level: .beginner), 10)
    }

    func testWonLine() {
        XCTAssertEqual(Minesweeper.wonLine(seconds: 12, rank: 1), "赢了 · 12 秒 · 新纪录")
        XCTAssertEqual(Minesweeper.wonLine(seconds: 12, rank: 3), "赢了 · 12 秒 · 第 3 名")
        XCTAssertEqual(Minesweeper.wonLine(seconds: 12, rank: nil), "赢了 · 12 秒")
    }

    func testStatusLine() {
        var board = MineBoard(level: .beginner)
        XCTAssertEqual(Minesweeper.statusLine(board, now: 0), "点任意一格开始")
        var rng = MineRandom(seed: 2)
        board.reveal(40, now: 0, using: &rng)
        XCTAssertEqual(Minesweeper.statusLine(board, now: 5), "还剩 10 颗雷")
    }

    // MARK: 尺寸

    func testCellSizeFitsTheSide() {
        for (columns, side) in [(9, 316.0), (16, 316.0), (9, 129.0), (9, 136.0), (16, 280.0), (9, 280.0)] {
            let cell = Minesweeper.cellSize(columns: columns, side: side)
            let width = Minesweeper.boardSize(rows: columns, columns: columns, cell: cell).width
            XCTAssertLessThanOrEqual(width, side, "\(columns) 列放进 \(side)")
            let bigger = Minesweeper.boardSize(rows: columns, columns: columns, cell: cell + 1).width
            XCTAssertGreaterThan(bigger, side, "已经是放得下的最大整数")
        }
        XCTAssertEqual(Minesweeper.cellSize(columns: 9, side: Minesweeper.panelBoardWidth), 26)
        XCTAssertEqual(Minesweeper.cellSize(columns: 16, side: Minesweeper.panelBoardWidth), 15)
    }

    func testHitIndexMapsPointsToCells() {
        let cell = 20.0, gap = Minesweeper.gap(cell: cell)
        XCTAssertEqual(Minesweeper.hitIndex(x: 1, y: 1, rows: 9, columns: 9, cell: cell), 0)
        XCTAssertEqual(Minesweeper.hitIndex(x: cell + gap + 1, y: 1, rows: 9, columns: 9, cell: cell), 1)
        XCTAssertEqual(Minesweeper.hitIndex(x: 1, y: (cell + gap) * 2 + 1, rows: 9, columns: 9, cell: cell), 18)
        XCTAssertNil(Minesweeper.hitIndex(x: -1, y: 1, rows: 9, columns: 9, cell: cell))
        XCTAssertNil(Minesweeper.hitIndex(x: (cell + gap) * 9 + 1, y: 1, rows: 9, columns: 9, cell: cell))
    }

    func testPanelBoardFitsThePanel() {
        for level in MineLevel.allCases {
            let cell = Minesweeper.cellSize(columns: level.columns, side: Minesweeper.panelBoardWidth)
            let size = Minesweeper.boardSize(rows: level.rows, columns: level.columns, cell: cell)
            XCTAssertLessThanOrEqual(size.width, Minesweeper.panelBoardWidth)
            XCTAssertLessThanOrEqual(size.height, Minesweeper.panelBoardWidth)
            XCTAssertGreaterThanOrEqual(cell, 14, "面板里的格子不小于 14pt")
        }
        XCTAssertLessThan(Minesweeper.panelBoardWidth, Minesweeper.panelWidth)
        // 棋盘宽 = 面板宽 - 内容区两侧 16 - 侧边尾巴 10 - 卡片两侧 16，不会再顶到右边被裁。
        XCTAssertEqual(Minesweeper.panelBoardWidth, 266)
        for level in MineLevel.allCases {
            let cell = Minesweeper.cellSize(columns: level.columns, side: Minesweeper.panelBoardWidth)
            let width = Minesweeper.boardSize(rows: level.rows, columns: level.columns, cell: cell).width
            let used = width + Minesweeper.panelCardPadding * 2 + Double(DetailPanelWidth.padding) * 2
                + Minesweeper.panelTailDepth
            XCTAssertLessThanOrEqual(used, Minesweeper.panelWidth, "\(level) 连边距一起放进面板")
        }
    }

    func testDesktopCardsArePlayable() {
        XCTAssertTrue(DesktopCardsGamesPlan.handles(.minesweeper))
        XCTAssertFalse(DesktopCardsGamesPlan.handles(.clock))
        XCTAssertEqual(DesktopCardsGamesPlan.level(for: .small, chosen: .intermediate), .beginner)
        XCTAssertEqual(DesktopCardsGamesPlan.level(for: .medium, chosen: .intermediate), .beginner)
        XCTAssertEqual(DesktopCardsGamesPlan.level(for: .large, chosen: .intermediate), .intermediate)
        XCTAssertEqual(DesktopPinSupport.mode(.minesweeper, hasDetail: true, panelWidth: Minesweeper.panelWidth),
                       .dedicated)
        for size in DesktopPinSize.allCases {
            for chosen in MineLevel.allCases {
                let level = DesktopCardsGamesPlan.level(for: size, chosen: chosen)
                let cell = DesktopCardsGamesPlan.cell(for: size, level: level)
                XCTAssertGreaterThanOrEqual(cell, 13, "\(size) \(level) 的格子能点")
                let board = Minesweeper.boardSize(rows: level.rows, columns: level.columns, cell: cell)
                let inset = DesktopCardsGamesPlan.inset(size)
                XCTAssertLessThanOrEqual(board.width + inset * 2, size.width)
                XCTAssertLessThanOrEqual(board.height + inset * 2, size.height)
                if size != .medium {
                    XCTAssertLessThanOrEqual(board.height + inset * 2 + DesktopCardsGamesPlan.headerHeight(size)
                                             + DesktopCardsGamesPlan.headerSpacing(size), size.height)
                }
            }
        }
        // 中号右边一列要放得下读数和重开键。
        let medium = Minesweeper.boardSize(rows: 9, columns: 9, cell: DesktopCardsGamesPlan.cell(for: .medium, level: .beginner))
        XCTAssertGreaterThanOrEqual(DesktopPinSize.medium.width - medium.width - 3 * DesktopCardsGamesPlan.inset(.medium), 150)
    }

    // MARK: 目录

    func testCatalogEntry() throws {
        let entry = try XCTUnwrap(WidgetCatalog.entry(.minesweeper))
        XCTAssertEqual(entry.name, "扫雷")
        XCTAssertEqual(entry.category, .tools)
        XCTAssertTrue(entry.selfContained)
        XCTAssertTrue(WidgetCatalog.configurableKeys(.minesweeper).isEmpty, "局和成绩不进设置页")
        XCTAssertFalse(ProFeatures.isProKind(.minesweeper), "免费")
        XCTAssertTrue(ProLicenseGate.canAdd(.minesweeper, overrides: [:], unlocked: false))
        XCTAssertNil(WidgetCatalog.openTarget(.minesweeper), "点卡片打开面板")
        XCTAssertTrue(WidgetLibraryGroups.isNew(.minesweeper))
        XCTAssertEqual(WidgetKind.minesweeper.rawValue, "minesweeper")
        let card = try XCTUnwrap(WidgetCatalog.make(.minesweeper))
        XCTAssertEqual(WidgetCatalog.contentSize(card, position: .bottom).width, Minesweeper.tileWidth)
        XCTAssertEqual(WidgetCatalog.contentSize(card, position: .left).height, Minesweeper.columnHeight)
        XCTAssertNotNil(WidgetSearch.keywords["minesweeper"])
    }
}
