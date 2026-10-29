import Foundation

// MARK: - 扫雷
//
// 扫雷小组件（免费）的全部规则：棋盘、首击安全的布雷、揭开（0 自动扩散）、插旗、
// 和弦（数字周围的旗数够了就揭开周围）、胜负和计时，以及进行中的局和各难度最佳成绩
// 怎么存进卡片配置。界面（扩展栏卡片、面板、桌面卡片）只调这里，测试也只测这里。
//
// 借的是扫雷的玩法，不借任何系统扫雷的素材、名字或外观：格子是液态玻璃小块，
// 旗子是小熊猫橙，结果用小熊猫表情。

/// 难度。高级（30×16）在 340 宽的面板里格子会小于 10pt，不做。
public enum MineLevel: String, Codable, Sendable, CaseIterable {
    case beginner
    case intermediate

    public var rows: Int { self == .beginner ? 9 : 16 }
    public var columns: Int { self == .beginner ? 9 : 16 }
    public var mines: Int { self == .beginner ? 10 : 40 }

    public var title: String {
        switch self {
        case .beginner: tr("初级", context: "mines")
        case .intermediate: tr("中级", context: "mines")
        }
    }

    /// 「9×9 · 10 雷」
    public var detail: String { tr("\(columns)×\(rows) · \(mines) 雷") }
}

/// 可注入种子的随机数（SplitMix64），测试里同一个种子得到同一盘。
public struct MineRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// 一盘扫雷。格子按行优先编号：`index = row * columns + column`。
public struct MineBoard: Equatable, Sendable {
    public enum Status: String, Codable, Sendable {
        /// 还没点第一下：雷还没布，计时没开始。
        case ready
        case playing
        case won
        case lost
    }

    /// 一格画成什么样。
    public enum Face: Equatable, Sendable {
        case hidden
        case flagged
        /// 揭开的空格（0）或数字。
        case open(Int)
        /// 输了以后亮出来的雷。
        case mine
        /// 踩到的那颗。
        case exploded
        /// 输了以后，插错旗的格子（下面没有雷）。
        case wrongFlag
    }

    public private(set) var rows: Int
    public private(set) var columns: Int
    public private(set) var mineCount: Int
    /// 第一下之前是空的（首击安全，点了才布雷）。
    public private(set) var mines: [Bool]
    public private(set) var revealed: [Bool]
    public private(set) var flagged: [Bool]
    public private(set) var status: Status
    /// 第一下的时间（1970 起的秒）。
    public private(set) var startedAt: Double?
    /// 赢或输的时间。
    public private(set) var endedAt: Double?
    /// 踩到的那颗雷。
    public private(set) var exploded: Int?

    public init(rows: Int, columns: Int, mines: Int) {
        let rows = max(2, rows), columns = max(2, columns)
        self.rows = rows
        self.columns = columns
        self.mineCount = min(max(1, mines), rows * columns - 1)
        self.mines = []
        self.revealed = Array(repeating: false, count: rows * columns)
        self.flagged = Array(repeating: false, count: rows * columns)
        self.status = .ready
    }

    public init(level: MineLevel) {
        self.init(rows: level.rows, columns: level.columns, mines: level.mines)
    }

    public var cellCount: Int { rows * columns }
    public var isOver: Bool { status == .won || status == .lost }
    public var flagCount: Int { flagged.lazy.filter { $0 }.count }
    /// 剩余雷数：总雷数减去插的旗，插多了是负数（和常见扫雷一样照实写）。
    public var minesLeft: Int { mineCount - flagCount }

    /// 难度（行列雷数正好是某一档时）。
    public var level: MineLevel? {
        MineLevel.allCases.first { $0.rows == rows && $0.columns == columns && $0.mines == mineCount }
    }

    public func index(row: Int, column: Int) -> Int { row * columns + column }

    public func contains(_ index: Int) -> Bool { index >= 0 && index < cellCount }

    /// 周围最多 8 格。
    public func neighbors(of index: Int) -> [Int] {
        guard contains(index) else { return [] }
        let row = index / columns, column = index % columns
        var result: [Int] = []
        result.reserveCapacity(8)
        for dr in -1...1 {
            for dc in -1...1 where dr != 0 || dc != 0 {
                let r = row + dr, c = column + dc
                if r >= 0, r < rows, c >= 0, c < columns { result.append(r * columns + c) }
            }
        }
        return result
    }

    public func isMine(_ index: Int) -> Bool { mines.indices.contains(index) && mines[index] }

    /// 周围几颗雷。
    public func adjacentMines(_ index: Int) -> Int {
        neighbors(of: index).reduce(0) { $0 + (isMine($1) ? 1 : 0) }
    }

    public func adjacentFlags(_ index: Int) -> Int {
        neighbors(of: index).reduce(0) { $0 + (flagged[$1] ? 1 : 0) }
    }

    public func face(_ index: Int) -> Face {
        guard contains(index) else { return .hidden }
        if status == .lost {
            if index == exploded { return .exploded }
            if flagged[index] { return isMine(index) ? .flagged : .wrongFlag }
            if isMine(index) { return .mine }
        }
        if revealed[index] { return .open(adjacentMines(index)) }
        return flagged[index] ? .flagged : .hidden
    }

    // MARK: 计时

    /// 用了多少秒：没开始是 0，进行中按现在算，结束了停在结束那一刻。
    public func elapsed(now: Double) -> Double {
        guard let start = startedAt else { return 0 }
        return max(0, (endedAt ?? now) - start)
    }

    /// 显示用的整秒，封顶 999（和常见扫雷的三位计时一样）。
    public func displaySeconds(now: Double) -> Int {
        min(999, Int(elapsed(now: now)))
    }

    // MARK: 操作

    /// 布雷：避开第一下点的格子和它周围（放不下时只避开那一格）。
    public mutating func placeMines<G: RandomNumberGenerator>(safe index: Int, using rng: inout G) {
        var excluded = Set([index])
        let ring = Set(neighbors(of: index)).union([index])
        if cellCount - ring.count >= mineCount { excluded = ring }
        var candidates = (0..<cellCount).filter { !excluded.contains($0) }
        candidates.shuffle(using: &rng)
        var layout = Array(repeating: false, count: cellCount)
        for i in candidates.prefix(mineCount) { layout[i] = true }
        mines = layout
    }

    /// 左键：没揭开的揭开（第一下先布雷、开始计时），揭开的数字做和弦。
    /// 插了旗的、已经结束的不动。返回棋盘有没有变。
    @discardableResult
    public mutating func reveal<G: RandomNumberGenerator>(_ index: Int, now: Double,
                                                          using rng: inout G) -> Bool {
        guard contains(index), !isOver, !flagged[index] else { return false }
        if revealed[index] { return chord(index, now: now) }
        if status == .ready {
            placeMines(safe: index, using: &rng)
            status = .playing
            startedAt = now
        }
        open(index, now: now)
        return true
    }

    /// 不传随机数时用系统随机。
    @discardableResult
    public mutating func reveal(_ index: Int, now: Double) -> Bool {
        var rng = SystemRandomNumberGenerator()
        return reveal(index, now: now, using: &rng)
    }

    /// 右键或 ⌥ 点：没揭开的插旗 / 拔旗；点在揭开的数字上等于和弦。
    @discardableResult
    public mutating func toggleFlag(_ index: Int, now: Double) -> Bool {
        guard contains(index), !isOver else { return false }
        if revealed[index] { return chord(index, now: now) }
        flagged[index].toggle()
        return true
    }

    /// 和弦：揭开的数字周围插的旗正好等于数字时，揭开周围其余没插旗的格子。
    /// 旗插错了会踩雷。
    @discardableResult
    public mutating func chord(_ index: Int, now: Double) -> Bool {
        guard contains(index), status == .playing, revealed[index] else { return false }
        let count = adjacentMines(index)
        guard count > 0, adjacentFlags(index) == count else { return false }
        let targets = neighbors(of: index).filter { !revealed[$0] && !flagged[$0] }
        guard !targets.isEmpty else { return false }
        for target in targets where !isOver {
            open(target, now: now)
        }
        return true
    }

    /// 揭开一格：雷就输；0 自动往外扩散；揭完看赢没赢。
    private mutating func open(_ index: Int, now: Double) {
        guard !revealed[index], !flagged[index] else { return }
        if isMine(index) {
            revealed[index] = true
            exploded = index
            status = .lost
            endedAt = now
            return
        }
        var stack = [index]
        while let current = stack.popLast() {
            guard !revealed[current], !flagged[current] else { continue }
            revealed[current] = true
            if adjacentMines(current) == 0 {
                stack.append(contentsOf: neighbors(of: current).filter { !revealed[$0] && !flagged[$0] })
            }
        }
        if hasWon {
            status = .won
            endedAt = now
            // 赢了把剩下的雷都插上旗，剩余雷数归零。
            for i in 0..<cellCount where isMine(i) { flagged[i] = true }
        }
    }

    /// 所有不是雷的格子都揭开了。
    public var hasWon: Bool {
        guard !mines.isEmpty else { return false }
        for i in 0..<cellCount where !mines[i] && !revealed[i] { return false }
        return true
    }

    /// 测试用：直接指定雷的位置（开始计时，状态进行中）。
    public static func fixed(rows: Int, columns: Int, mines: Set<Int>, startedAt: Double = 0) -> MineBoard {
        var board = MineBoard(rows: rows, columns: columns, mines: max(1, mines.count))
        board.mineCount = mines.count
        board.mines = (0..<(rows * columns)).map { mines.contains($0) }
        board.status = .playing
        board.startedAt = startedAt
        return board
    }
}

// MARK: - 存进卡片配置

extension MineBoard: Codable {
    private enum CodingKeys: String, CodingKey {
        case rows = "r", columns = "c", mineCount = "n", mines = "m", cells = "s"
        case status = "st", startedAt = "t0", endedAt = "t1", exploded = "x"
    }

    /// 雷是一串 0 / 1；格子是一串字母：h 没揭开、o 揭开、f 插旗。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rows = try c.decode(Int.self, forKey: .rows)
        let columns = try c.decode(Int.self, forKey: .columns)
        let count = rows * columns
        guard rows >= 2, columns >= 2, count <= 1024 else {
            throw DecodingError.dataCorruptedError(forKey: .rows, in: c, debugDescription: "bad size")
        }
        let total = try c.decode(Int.self, forKey: .mineCount)
        self.init(rows: rows, columns: columns, mines: total)
        let mineText = try c.decodeIfPresent(String.self, forKey: .mines) ?? ""
        if !mineText.isEmpty {
            guard mineText.count == count else {
                throw DecodingError.dataCorruptedError(forKey: .mines, in: c, debugDescription: "bad mines")
            }
            mines = mineText.map { $0 == "1" }
            mineCount = mines.lazy.filter { $0 }.count
        }
        let cells = try c.decode(String.self, forKey: .cells)
        guard cells.count == count else {
            throw DecodingError.dataCorruptedError(forKey: .cells, in: c, debugDescription: "bad cells")
        }
        revealed = cells.map { $0 == "o" }
        flagged = cells.map { $0 == "f" }
        status = try c.decode(Status.self, forKey: .status)
        // 没布雷就不可能在进行中，按还没开始读。
        if mines.isEmpty, status != .ready { status = .ready }
        startedAt = try c.decodeIfPresent(Double.self, forKey: .startedAt)
        endedAt = try c.decodeIfPresent(Double.self, forKey: .endedAt)
        exploded = try c.decodeIfPresent(Int.self, forKey: .exploded)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(rows, forKey: .rows)
        try c.encode(columns, forKey: .columns)
        try c.encode(mineCount, forKey: .mineCount)
        try c.encode(mines.map { $0 ? "1" : "0" }.joined(), forKey: .mines)
        let cells = (0..<cellCount).map { revealed[$0] ? "o" : (flagged[$0] ? "f" : "h") }
        try c.encode(cells.joined(), forKey: .cells)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(startedAt, forKey: .startedAt)
        try c.encodeIfPresent(endedAt, forKey: .endedAt)
        try c.encodeIfPresent(exploded, forKey: .exploded)
    }
}

/// 进行中的局、选的难度和各难度最佳成绩，都存在卡片配置里（不在设置页列出：
/// 这些键不放进目录的默认值）。扩展栏卡片、面板和桌面卡片读写同一份。
public enum Minesweeper {
    /// 面板里选的难度。
    public static let levelKey = "level"

    /// 每个难度各存一局，换难度不丢另一局。
    public static func gameKey(_ level: MineLevel) -> String { "game.\(level.rawValue)" }
    /// 最快通关秒数。
    public static func bestKey(_ level: MineLevel) -> String { "best.\(level.rawValue)" }

    public static func level(_ config: WidgetConfig) -> MineLevel {
        MineLevel(rawValue: config.string(levelKey, default: "")) ?? .beginner
    }

    public static func board(_ config: WidgetConfig, level: MineLevel) -> MineBoard {
        let raw = config.string(gameKey(level), default: "")
        guard let data = raw.data(using: .utf8), !raw.isEmpty,
              let board = try? JSONDecoder().decode(MineBoard.self, from: data),
              board.level == level else { return MineBoard(level: level) }
        return board
    }

    public static func store(_ board: MineBoard, level: MineLevel, in config: inout WidgetConfig) {
        guard let data = try? JSONEncoder().encode(board),
              let text = String(data: data, encoding: .utf8) else { return }
        config.set(gameKey(level), .string(text))
    }

    public static func best(_ config: WidgetConfig, level: MineLevel) -> Double? {
        let value = config.double(bestKey(level), default: 0)
        return value > 0 ? value : nil
    }

    /// 「12 秒」；没有记录是「暂无」。
    public static func bestText(_ seconds: Double?) -> String {
        guard let seconds else { return tr("暂无") }
        return tr("\(Int(seconds.rounded(.down))) 秒")
    }

    public enum Action: Sendable {
        /// 左键：揭开或和弦。
        case reveal
        /// 右键或 ⌥ 点：插旗、拔旗，点在数字上是和弦。
        case flag
    }

    public struct Outcome: Equatable, Sendable {
        public var changed: Bool
        /// 这一下刚赢。
        public var justWon: Bool
        /// 这一下刚输。
        public var justLost: Bool
        /// 刚赢而且是这个难度的新纪录。
        public var newRecord: Bool
    }

    /// 在某个难度的那一局上点一下，写回配置；刚赢时更新最佳成绩。
    @discardableResult
    public static func apply<G: RandomNumberGenerator>(_ action: Action, at index: Int, level: MineLevel,
                                                       to config: inout WidgetConfig, now: Double,
                                                       using rng: inout G) -> Outcome {
        var game = board(config, level: level)
        let before = game.status
        let changed: Bool
        switch action {
        case .reveal: changed = game.reveal(index, now: now, using: &rng)
        case .flag: changed = game.toggleFlag(index, now: now)
        }
        var outcome = Outcome(changed: changed, justWon: false, justLost: false, newRecord: false)
        guard changed else { return outcome }
        store(game, level: level, in: &config)
        if before != .won, game.status == .won {
            outcome.justWon = true
            let time = game.elapsed(now: now)
            if best(config, level: level).map({ time < $0 }) ?? true {
                config.set(bestKey(level), .number((time * 10).rounded() / 10))
                outcome.newRecord = true
            }
        }
        if before != .lost, game.status == .lost { outcome.justLost = true }
        return outcome
    }

    /// 用系统随机。
    @discardableResult
    public static func apply(_ action: Action, at index: Int, level: MineLevel,
                             to config: inout WidgetConfig, now: Double) -> Outcome {
        var rng = SystemRandomNumberGenerator()
        return apply(action, at: index, level: level, to: &config, now: now, using: &rng)
    }

    /// 重开这个难度：一盘新的、还没布雷的棋盘。
    public static func restart(_ level: MineLevel, in config: inout WidgetConfig) {
        store(MineBoard(level: level), level: level, in: &config)
    }

    /// 面板换难度：只换选择，两个难度的局各自留着。
    public static func select(_ level: MineLevel, in config: inout WidgetConfig) {
        config.set(levelKey, .string(level.rawValue))
    }

    /// 一句状态：「还剩 7 颗」「赢了 · 23 秒」「踩雷了」「点任意一格开始」。
    public static func statusLine(_ board: MineBoard, now: Double) -> String {
        switch board.status {
        case .ready: return tr("点任意一格开始")
        case .playing: return tr("还剩 \(board.minesLeft) 颗雷")
        case .won: return tr("赢了 · \(board.displaySeconds(now: now)) 秒")
        case .lost: return tr("踩雷了，再来一盘")
        }
    }

    // MARK: 尺寸（扩展栏卡片、面板、桌面卡片）

    /// 扩展栏横排卡片宽：小棋盘缩略图、剩余雷数和计时、重开键。
    public static let tileWidth: Double = 188
    /// 左右两侧扩展栏的竖条高：缩略图在上，两行读数在下。
    public static let columnHeight: Double = 120
    /// 面板宽。
    public static let panelWidth: Double = 340
    /// 面板里棋盘的宽（初级、中级一样宽，换难度面板不跳）。
    public static let panelBoardWidth: Double = 316
    /// 格子之间的缝。
    public static func gap(cell: Double) -> Double { cell >= 24 ? 3 : (cell >= 17 ? 2 : 1) }

    /// 在 `side` 宽里放 `columns` 列时每格多大：放得下的最大整数（连缝一起算）。
    public static func cellSize(columns: Int, side: Double) -> Double {
        let count = max(1, columns)
        var cell = (side / Double(count)).rounded(.down)
        while cell > 1, boardSize(rows: 1, columns: count, cell: cell).width > side { cell -= 1 }
        return max(1, cell)
    }

    /// 棋盘实际占的宽高。
    public static func boardSize(rows: Int, columns: Int, cell: Double) -> (width: Double, height: Double) {
        let g = gap(cell: cell)
        return (Double(columns) * cell + Double(max(0, columns - 1)) * g,
                Double(rows) * cell + Double(max(0, rows - 1)) * g)
    }

    /// 在棋盘坐标里点到哪一格（缝算给左上那格），点在棋盘外是 nil。
    public static func hitIndex(x: Double, y: Double, rows: Int, columns: Int, cell: Double) -> Int? {
        let pitch = cell + gap(cell: cell)
        guard x >= 0, y >= 0, pitch > 0 else { return nil }
        let column = Int(x / pitch), row = Int(y / pitch)
        guard row < rows, column < columns else { return nil }
        return row * columns + column
    }
}

/// 钉在桌面：扫雷的小 / 中 / 大三档都能直接玩。小号、中号放初级（9×9），大号放面板里
/// 选的难度。桌面卡片的边距、读数行高和每档格子大小放这里，测试保证格子不小于 13pt。
public enum DesktopCardsGamesPlan {
    public static let kinds: Set<WidgetKind> = [.minesweeper]

    public static func handles(_ kind: WidgetKind) -> Bool { kinds.contains(kind) }

    /// 这一档玩哪个难度。
    public static func level(for size: DesktopPinSize, chosen: MineLevel) -> MineLevel {
        size == .large ? chosen : .beginner
    }

    /// 卡片边距。
    public static func inset(_ size: DesktopPinSize) -> Double { size == .small ? 6 : 12 }
    /// 顶上读数一行的高（小号、大号在棋盘上面；中号读数在右边一列）。
    public static func headerHeight(_ size: DesktopPinSize) -> Double { size == .small ? 16 : 30 }
    /// 读数行和棋盘之间。
    public static func headerSpacing(_ size: DesktopPinSize) -> Double { size == .small ? 3 : 6 }

    /// 棋盘能用的边长。
    public static func boardSide(_ size: DesktopPinSize) -> Double {
        let inset = inset(size)
        switch size {
        case .medium:
            return size.height - inset * 2
        case .small, .large:
            return min(size.width - inset * 2,
                       size.height - inset * 2 - headerHeight(size) - headerSpacing(size))
        }
    }

    public static func cell(for size: DesktopPinSize, level: MineLevel) -> Double {
        Minesweeper.cellSize(columns: max(level.columns, level.rows), side: boardSide(size))
    }
}
