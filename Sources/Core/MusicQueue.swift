import CoreGraphics
import Foundation

/// 「正在播放」面板控制键下的歌单入口（效果图 design/music-queue-2.png、-3.png，方案 A）。
///
/// 原来入口是播放页最底下一行「接下来 · 歌单「音乐」 >」，落在 517 到 557pt，面板最高
/// 560（视口 550），被底部 18pt 渐隐压成灰色、只剩半截。现在：
///
/// - 收起态：封面 204 缩到 128，控制键下直接列「接下来」3 首（每行 38pt 整行可点即播），
///   右边「全部 N 首」胶囊；内容底约 520，离开渐隐带。
/// - 延展态：封面缩成 48pt 迷你播放条吸顶，列表往下占满，面板不突破 560，列表区内滚。
/// - Spotify 读不到队列，同一位置是码头本机记的「刚才听过」。
/// - 网易云、QQ 音乐、小宇宙、浏览器读不到队列：整块不出现，封面回到 204。
///
/// 显示条件、标题、各种占位和截断都在这里，界面只照着画。
public enum MusicQueue {
    // MARK: 尺寸（效果图 music-queue.py A_collapsed / A_expanded）

    /// 没有入口时的大封面。
    public static let coverFull: CGFloat = 204
    /// 有入口时（收起态）的封面。
    public static let coverCompact: CGFloat = 128
    /// 延展态迷你播放条里的封面。
    public static let coverMini: CGFloat = 48
    /// 收起态列几首。
    public static let collapsedRows = 3
    /// 收起态每行高度。
    public static let collapsedRowHeight: CGFloat = 38
    /// 延展态每行高度。
    public static let expandedRowHeight: CGFloat = 44
    /// 延展态列表区最高：560 面板减去吸顶部分（来源胶囊、迷你条、标题行，约 198）。
    public static let expandedListMax: CGFloat = 346
    /// 行列表上下各 2pt 内边距。
    public static let rowsInset: CGFloat = 2
    /// 「全部」「收起」胶囊和状态卡按钮的最小点击高度。
    public static let minHitHeight: CGFloat = 28
    /// 读取中最多画几行灰色占位，再多看不出区别。
    public static let maxPlaceholders = 6

    // MARK: 状态

    /// 这块画成哪种。
    public enum Kind: Equatable, Sendable {
        /// Apple 音乐「接下来」。
        case upNext
        /// Spotify「刚才听过」。
        case recent
    }

    /// 标题。
    public enum Title: Equatable, Sendable {
        /// 「接下来」，读不到歌单名或随机播放时。
        case upNext
        /// 「接下来 · 通勤路上」。
        case playlist(String)
        /// 整库播放：「接下来 · 资料库」（原来写成「歌单「音乐」」，像标签签名）。
        case library
        /// 「刚才听过」。
        case recent
    }

    /// 列表部分的样子。
    public enum Content: Equatable, Sendable {
        /// 有歌可列。
        case rows
        /// 还没读到：画几行灰色占位。
        case loading(placeholders: Int)
        /// 随机播放中：「顺序由 Apple 音乐决定」+「关掉随机」。
        case shuffle
        /// 放到最后一首：「后面没有歌了」，没开循环全部时带「从头循环」。
        case end(canLoop: Bool)
        /// Spotify 还没记下听过的歌。
        case empty
    }

    public struct Block: Equatable, Sendable {
        public var kind: Kind
        public var title: Title
        public var content: Content
        /// 「全部 N 首」里的 N；不够收起态那几首时为 nil，不画胶囊。
        public var allCount: Int?

        public init(kind: Kind, title: Title, content: Content, allCount: Int?) {
            self.kind = kind
            self.title = title
            self.content = content
            self.allCount = allCount
        }
    }

    /// 面板拿来判断的输入，和服务里的类型无关（测试只编译 Core）。
    public struct Input: Equatable, Sendable {
        public var source: MusicSource?
        /// 是播放器本身（不是浏览器标签页）在放。
        public var isNative: Bool
        public var shuffle: Bool
        public var repeatMode: MusicRepeat
        /// 读到的歌单名，没读到为 nil。
        public var playlist: String?
        /// 读到的是整个资料库（AppleScript `library playlist`）。
        public var isLibrary: Bool
        /// 已经读到的接下来几首；nil 是还没读到。
        public var loaded: Int?
        /// 歌单里当前这首后面一共还有几首（循环全部时是歌单首数减一）。
        public var remaining: Int?
        /// 正在读。
        public var loading: Bool
        /// 连读几次都读不到歌单（电台、在线流）：当作读不到队列，整块不出现。
        public var unreadable: Bool
        /// Spotify 本机记的听过几首（去掉正在放的）。
        public var recentCount: Int

        public init(source: MusicSource?, isNative: Bool, shuffle: Bool = false,
                    repeatMode: MusicRepeat = .off, playlist: String? = nil, isLibrary: Bool = false,
                    loaded: Int? = nil, remaining: Int? = nil, loading: Bool = false,
                    unreadable: Bool = false, recentCount: Int = 0) {
            self.source = source
            self.isNative = isNative
            self.shuffle = shuffle
            self.repeatMode = repeatMode
            self.playlist = playlist
            self.isLibrary = isLibrary
            self.loaded = loaded
            self.remaining = remaining
            self.loading = loading
            self.unreadable = unreadable
            self.recentCount = recentCount
        }
    }

    /// 这块怎么画；nil 是整块不出现（读不到队列的来源、浏览器），封面回到 204。
    public static func block(_ input: Input) -> Block? {
        guard input.isNative, let source = input.source else { return nil }
        if source.hasUpNext {
            if input.unreadable, !input.shuffle { return nil }
            if input.shuffle {
                return Block(kind: .upNext, title: .upNext, content: .shuffle, allCount: nil)
            }
            let title = title(playlist: input.playlist, isLibrary: input.isLibrary)
            guard let loaded = input.loaded else {
                return Block(kind: .upNext, title: title,
                             content: .loading(placeholders: collapsedRows), allCount: nil)
            }
            let remaining = max(loaded, input.remaining ?? loaded)
            if loaded == 0 {
                if remaining > 0, input.loading {
                    return Block(kind: .upNext, title: title,
                                 content: .loading(placeholders: min(remaining, collapsedRows)), allCount: nil)
                }
                return Block(kind: .upNext, title: title,
                             content: .end(canLoop: input.repeatMode != .all), allCount: nil)
            }
            return Block(kind: .upNext, title: title, content: .rows, allCount: allCount(remaining))
        }
        if source.keepsRecent {
            let count = input.recentCount
            return Block(kind: .recent, title: .recent, content: count == 0 ? .empty : .rows,
                         allCount: allCount(count))
        }
        return nil
    }

    /// 歌单名：整库播放叫「资料库」。AppleScript 读不出类时按名字认（中文系统叫「音乐」，
    /// 英文叫 Music 或 Library）。
    public static func title(playlist: String?, isLibrary: Bool) -> Title {
        let name = playlist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if isLibrary || libraryNames.contains(name) { return .library }
        return name.isEmpty ? .upNext : .playlist(name)
    }

    /// Apple 音乐资料库在各语言下的名字。
    public static let libraryNames: Set<String> = ["音乐", "Music", "Library", "资料库", "資料庫", "音樂"]

    /// 多于收起态那几首才有「全部 N 首」。
    public static func allCount(_ total: Int) -> Int? {
        total > collapsedRows ? total : nil
    }

    /// 封面多大：有入口 128，没有 204。
    public static func coverSide(_ block: Block?) -> CGFloat {
        block == nil ? coverFull : coverCompact
    }

    // MARK: 延展态

    /// 延展态读取中，在已经列出的几首下面再画几行灰色占位：要读的总数（最多 25，
    /// 不超过歌单剩下的）减去已经有的，最多 `maxPlaceholders` 行。
    public static func placeholders(loaded: Int, remaining: Int?, loading: Bool) -> Int {
        guard loading else { return 0 }
        let wanted = min(MusicUpNext.limit, remaining ?? MusicUpNext.limit)
        return max(0, min(maxPlaceholders, wanted - loaded))
    }

    /// 读完以后歌单里还有多少首没列出来（只列前 25 首），画一行「还有 N 首」。
    public static func truncated(loaded: Int, remaining: Int?, loading: Bool) -> Int {
        guard !loading, let remaining else { return 0 }
        return max(0, remaining - loaded)
    }

    /// 延展态列表区高度：行加上底下的说明，不超过 `expandedListMax`，再多就在区内滚。
    public static func listHeight(rows: Int, footer: CGFloat = 0) -> CGFloat {
        let natural = rows > 0 ? CGFloat(rows) * expandedRowHeight + rowsInset * 2 : 0
        return min(expandedListMax, natural + footer)
    }

    /// 只在延展态读满 25 首，收起态按需读少量。
    public static func readLimit(expanded: Bool) -> Int {
        expanded ? MusicUpNext.limit : collapsedRows
    }

    // MARK: 刚才听过的时间

    public enum Ago: Equatable, Sendable {
        case justNow
        case minutes(Int)
        case hours(Int)
        case days(Int)
    }

    /// 行尾「几分钟前」。旧记录没有时间（升级前记的）时为 nil，界面改写时长。
    public static func ago(_ date: Date?, now: Date) -> Ago? {
        guard let date else { return nil }
        let seconds = max(0, now.timeIntervalSince(date))
        let minutes = Int(seconds / 60)
        if minutes < 1 { return .justNow }
        if minutes < 60 { return .minutes(minutes) }
        let hours = minutes / 60
        if hours < 24 { return .hours(hours) }
        return .days(hours / 24)
    }
}
