import Foundation

/// Which player a reading came from.
///
/// 放在 Core：来源切换、音量走哪一路、「接下来」和「刚才听过」这些判断都按来源
/// 分，测试只编译 Core，所以来源本身也在这里。
public enum MusicSource: String, Sendable, CaseIterable, Codable {
    case spotify, appleMusic, netease, qqmusic, xiaoyuzhou

    public var bundleID: String {
        switch self {
        case .spotify: "com.spotify.client"
        case .appleMusic: "com.apple.Music"
        case .netease: "com.netease.163music"
        // QQ 音乐 Mac 版（Homebrew cask qqmusic 的 uninstall quit 就是这个 id）。
        case .qqmusic: "com.tencent.QQMusicMac"
        // The iPhone app, run on an Apple silicon Mac.
        case .xiaoyuzhou: "app.podcast.cosmos"
        }
    }

    /// 小组件配置里开关这个来源的键。
    public var configKey: String {
        switch self {
        case .spotify: "spotify"
        case .appleMusic: "apple"
        case .netease: "netease"
        case .qqmusic: "qqmusic"
        case .xiaoyuzhou: "xiaoyuzhou"
        }
    }

    /// 网易云音乐、QQ 音乐和小宇宙没有 AppleScript 词典：从系统「正在播放」读，
    /// 用媒体键控制，所以不能拖进度。
    public var readsNowPlaying: Bool { self == .netease || self == .qqmusic || self == .xiaoyuzhou }
    public var canSeek: Bool { !readsNowPlaying }

    /// 随机和循环：只有走 AppleScript 的两个。
    public var hasShuffleAndRepeat: Bool { self == .appleMusic || self == .spotify }
    /// 喜欢：只有 Apple 音乐（Spotify 要 Web API，个人开发者拿不到）。
    public var hasFavorite: Bool { self == .appleMusic }
    /// 「接下来」按当前歌单顺序列：只有 Apple 音乐读得到歌单。
    public var hasUpNext: Bool { self == .appleMusic }
    /// 「刚才听过」码头本机记：Spotify 读不到队列，用这个代替。
    public var keepsRecent: Bool { self == .spotify }
    /// Spotify 只能循环开关，没有单曲循环。
    public var hasRepeatOne: Bool { self == .appleMusic }

    public var displayName: String {
        switch self {
        case .spotify: "Spotify"
        case .appleMusic: tr("Apple 音乐")
        case .netease: tr("网易云音乐")
        case .qqmusic: tr("QQ 音乐")
        case .xiaoyuzhou: tr("小宇宙")
        }
    }

    /// 打开了哪些来源，按卡片的偏好顺序。旧配置没有 qqmusic 键，读默认开。
    public static func enabled(in config: WidgetConfig) -> [MusicSource] {
        let order: [MusicSource] = [.spotify, .appleMusic, .netease, .qqmusic, .xiaoyuzhou]
        return order.filter { config.bool($0.configKey, default: true) }
    }

    public init?(bundleID: String) {
        guard let match = MusicSource.allCases.first(where: { $0.bundleID == bundleID }) else { return nil }
        self = match
    }
}

/// 「谁开始播放就切到谁」和固定来源。
///
/// 配置键 `autoSwitch`（默认开）和 `pinned`（关掉自动切换后停在的来源，面板里选，
/// 设置页不列）。
public enum MusicSourceSwitch {
    public static let autoKey = "autoSwitch"
    public static let pinnedKey = "pinned"

    /// 一个开着的播放器此刻的样子。
    public struct Player: Equatable, Sendable {
        public var source: MusicSource
        /// 读得到曲目（网易云、QQ 不是系统正在播放的那个时读不到）。
        public var hasTrack: Bool
        public var isPlaying: Bool

        public init(source: MusicSource, hasTrack: Bool, isPlaying: Bool) {
            self.source = source
            self.hasTrack = hasTrack
            self.isPlaying = isPlaying
        }
    }

    public static func autoSwitch(_ config: WidgetConfig) -> Bool {
        config.bool(autoKey, default: true)
    }

    public static func pinned(_ config: WidgetConfig) -> MusicSource? {
        MusicSource(rawValue: config.string(pinnedKey))
    }

    /// 该显示哪个来源。
    ///
    /// - `players`：开着的播放器，按偏好顺序。
    /// - `wasPlaying`：上一次读到时各来源是否在放，用来认出「刚开始播放」。
    /// - `current`：上一次显示的（或用户刚在面板里点的）。
    ///
    /// 自动切换开着：有来源从没在放变成在放，就切到它（当前的也在其中时不动）；
    /// 否则留在当前来源，哪怕它暂停了、别的早就在放，这样用户手选的来源不会被
    /// 一直在放的那个抢走；当前来源关掉或读不到了才退到第一个在放的、第一个有
    /// 曲目的、第一个开着的。
    ///
    /// 自动切换关着：固定在 `pinned`，它没开也照样是它（面板显示「打开 X」和
    /// 其他开着的）；还没选过时停在当前来源，不会因为谁开始播放而换。
    public static func choose(players: [Player], wasPlaying: [MusicSource: Bool],
                              current: MusicSource?, autoSwitch: Bool,
                              pinned: MusicSource?) -> MusicSource? {
        if !autoSwitch {
            if let pinned { return pinned }
            if let current, players.contains(where: { $0.source == current }) { return current }
            return fallback(players)
        }
        let starters = players.filter { $0.isPlaying && wasPlaying[$0.source] != true }
        if !starters.isEmpty {
            if let current, starters.contains(where: { $0.source == current }) { return current }
            return starters[0].source
        }
        if let current, let player = players.first(where: { $0.source == current }), player.hasTrack {
            return current
        }
        return fallback(players)
    }

    private static func fallback(_ players: [Player]) -> MusicSource? {
        players.first(where: \.isPlaying)?.source
            ?? players.first(where: \.hasTrack)?.source
            ?? players.first?.source
    }
}

/// 卡片显示哪一首。
///
/// 卡片只回答「现在在放什么」：任一播放器（包括允许的浏览器标签页）在放就显示它，
/// 和面板固定在哪个来源无关（固定只管面板打开时停在哪）。全都没在放时，卡片在
/// 「正在播放时显示」下照旧隐藏（`anyPlaying`），始终显示时停在刚才那首。
public enum MusicCardChoice {
    public enum Pick: Equatable, Sendable {
        case native(MusicSource)
        case browser
        case none

        public var source: MusicSource? {
            if case .native(let source) = self { return source }
            return nil
        }
    }

    /// 浏览器标签页此刻的样子；不允许浏览器时传 nil。
    public struct Browser: Equatable, Sendable {
        public var hasTrack: Bool
        public var isPlaying: Bool

        public init(hasTrack: Bool, isPlaying: Bool) {
            self.hasTrack = hasTrack
            self.isPlaying = isPlaying
        }
    }

    /// - `players`：开着的播放器，按偏好顺序。
    /// - `current`：面板正在看的来源（可能是固定的、暂停的）。
    /// - `last`：卡片上一次显示的，两个同时在放时不来回跳。
    ///
    /// 在放的优先：上次显示的还在放就不换，其次面板的来源，再按偏好顺序；播放器
    /// 在放时浏览器让位（和原来一样）。都没在放：上次显示的还有曲目就留着，否则
    /// 面板的来源、第一个有曲目的播放器、浏览器。
    public static func pick(players: [MusicSourceSwitch.Player], current: MusicSource?,
                            browser: Browser?, last: Pick?) -> Pick {
        let playing = players.filter(\.isPlaying)
        if let source = last?.source, playing.contains(where: { $0.source == source }) { return .native(source) }
        if let current, playing.contains(where: { $0.source == current }) { return .native(current) }
        if let first = playing.first { return .native(first.source) }
        if browser?.isPlaying == true { return .browser }

        switch last {
        case .native(let source) where players.contains(where: { $0.source == source && $0.hasTrack }):
            return .native(source)
        case .browser where browser?.hasTrack == true:
            return .browser
        default:
            break
        }
        if let current, players.contains(where: { $0.source == current && $0.hasTrack }) { return .native(current) }
        if let first = players.first(where: \.hasTrack) { return .native(first.source) }
        if browser?.hasTrack == true { return .browser }
        return .none
    }

    /// 「正在播放时显示」：任一播放器或允许的浏览器标签页在放。
    public static func anyPlaying(players: [MusicSourceSwitch.Player], browser: Browser?) -> Bool {
        players.contains(where: \.isPlaying) || browser?.isPlaying == true
    }
}

/// 面板固定来源的样子：「已固定」小标、「其他正在播的」和「取消固定」。
public enum MusicPin {
    /// 固定着的来源：关了自动切换并且选过来源。
    public static func pinned(_ config: WidgetConfig) -> MusicSource? {
        MusicSourceSwitch.autoSwitch(config) ? nil : MusicSourceSwitch.pinned(config)
    }

    /// 取消固定：回到「谁开始播放就切到谁」，清掉固定的来源。
    public static func unpin(_ config: inout WidgetConfig) {
        config.set(MusicSourceSwitch.autoKey, .bool(true))
        config.set(MusicSourceSwitch.pinnedKey, nil)
    }

    /// 没在播放时下面列哪些播放器：固定着时只列别的正在播的，否则列别的有曲目的。
    public static func others(players: [MusicSourceSwitch.Player], shown: MusicSource?,
                              pinned: Bool) -> [MusicSource] {
        players.filter { $0.source != shown && (pinned ? $0.isPlaying : $0.hasTrack) }.map(\.source)
    }
}

/// 循环模式。Apple 音乐有全部和单曲，Spotify 只有开关（开就是全部）。
public enum MusicRepeat: String, Sendable, Equatable, CaseIterable {
    case off, all, one

    /// AppleScript 里 `song repeat` 的值。
    public init(appleScript text: String) {
        self = MusicRepeat(rawValue: text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) ?? .off
    }

    /// 点一下循环键：Apple 音乐 关 → 全部 → 单曲 → 关；Spotify 关 ↔ 开。
    public func next(allowsOne: Bool) -> MusicRepeat {
        switch self {
        case .off: .all
        case .all: allowsOne ? .one : .off
        case .one: .off
        }
    }

    public var label: String {
        switch self {
        case .off: tr("循环 关")
        case .all: tr("循环全部")
        case .one: tr("单曲循环")
        }
    }
}

/// 音量条走哪一路。
public enum MusicVolumeRoute: Equatable, Sendable {
    /// 播放器自己的音量（AppleScript `sound volume`，0 到 100）。
    case player
    /// 借「应用音量」调这个 App 这一路（要录音权限）。
    case appVolume
    /// 不显示音量条。
    case none

    /// Apple 音乐、Spotify 用自身音量；网易云、QQ 音乐只在已经有录音权限时借应用
    /// 音量，没有权限不显示，也不为了它去弹权限；小宇宙是播客，不放。
    public static func route(for source: MusicSource, recordingGranted: Bool) -> MusicVolumeRoute {
        switch source {
        case .appleMusic, .spotify: .player
        case .netease, .qqmusic: recordingGranted ? .appVolume : .none
        case .xiaoyuzhou: .none
        }
    }
}

/// Apple 音乐「接下来」：按当前歌单顺序取后面几首。
///
/// 读不到系统真正的待播清单，只能按歌单顺序；开随机时顺序没有意义，面板隐藏。
public enum MusicUpNext {
    public static let limit = 5

    /// 当前是第 `current` 首（从 1 数，AppleScript 的下标），歌单共 `count` 首，
    /// 后面最多 `limit` 首的下标。循环全部时到尾接回开头，不会绕回当前这首。
    public static func indices(current: Int, count: Int, limit: Int = MusicUpNext.limit,
                               wrap: Bool) -> [Int] {
        guard current >= 1, current <= count, limit > 0 else { return [] }
        var out: [Int] = []
        var index = current
        while out.count < limit {
            index += 1
            if index > count {
                guard wrap else { break }
                index = 1
            }
            if index == current { break }
            out.append(index)
        }
        return out
    }

    public static func visible(shuffle: Bool) -> Bool { !shuffle }
}

/// Spotify「刚才听过」：只存在本机，最多 20 条，新的在前。
public struct MusicRecent: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable, Identifiable {
        /// `spotify:track:…`，点一下按它重放。
        public var uri: String
        public var title: String
        public var artist: String
        public var duration: Double
        public var artworkURL: String?

        public var id: String { uri }

        public init(uri: String, title: String, artist: String, duration: Double, artworkURL: String? = nil) {
            self.uri = uri
            self.title = title
            self.artist = artist
            self.duration = duration
            self.artworkURL = artworkURL
        }
    }

    public static let capacity = 20
    public static let defaultsKey = "music.spotifyRecent"

    public private(set) var entries: [Entry] = []

    public init(entries: [Entry] = []) {
        self.entries = Array(entries.prefix(Self.capacity))
    }

    /// 只认得出能重放的曲目：本地文件和广告没有 `spotify:track:` URI。
    public static func isReplayable(_ uri: String) -> Bool {
        uri.hasPrefix("spotify:track:") && uri.count > "spotify:track:".count
    }

    /// 记一首。同一首再放一次挪到最前，不重复；超过 20 条丢最旧的。
    public mutating func record(_ entry: Entry) {
        guard Self.isReplayable(entry.uri) else { return }
        entries.removeAll { $0.uri == entry.uri }
        entries.insert(entry, at: 0)
        if entries.count > Self.capacity { entries.removeLast(entries.count - Self.capacity) }
    }

    public mutating func clear() { entries = [] }

    /// 面板里列的：去掉正在放的这首。
    public func listed(excluding current: String?) -> [Entry] {
        entries.filter { $0.uri != current }
    }

    public static func decode(_ data: Data?) -> MusicRecent {
        guard let data, let value = try? JSONDecoder().decode(MusicRecent.self, from: data) else { return MusicRecent() }
        return MusicRecent(entries: value.entries)
    }

    public func encoded() -> Data? { try? JSONEncoder().encode(self) }

    /// AppleScript 播放这首的命令体。URI 里只允许字母数字和冒号，防止拼进脚本出事。
    public static func playCommand(_ uri: String) -> String? {
        guard isReplayable(uri),
              uri.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == ":") }) else { return nil }
        return "play track \"\(uri)\""
    }
}
