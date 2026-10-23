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
}

/// 卡片和面板共用的「当前显示来源」的样子，和「正在播放时显示」。
///
/// 挑哪个在 `MusicDisplay.pick`：卡片和面板显示同一个来源。全都没在放时，卡片在
/// 「正在播放时显示」下照旧隐藏（`anyPlaying`）。
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

    /// 「正在播放时显示」：任一播放器或允许的浏览器标签页在放。
    public static func anyPlaying(players: [MusicSourceSwitch.Player], browser: Browser?) -> Bool {
        players.contains(where: \.isPlaying) || browser?.isPlaying == true
    }
}

/// 「当前显示来源」：卡片和面板都调这一个函数，两边永远显示同一首。
///
/// 有任何来源在放时：
/// - 固定的来源在放，就是它（用户在面板里手点了别的，点的那个先留着，直到固定的
///   重新开始放或别的来源开始放）。
/// - 固定的来源没在放（没开或暂停）、或者没固定：用户手点的来源还开着就留着；
///   没固定（谁开始播放就切到谁）时刚开始放的来源顶上；否则正在显示的还在放就不换
///   （不来回跳），再按偏好顺序第一个在放的播放器，播放器都没在放才轮到浏览器。
///
/// 都没在放时：用户手点的来源还开着就留着；固定着就是固定的来源（没开也是它，面板
/// 显示「X 没开」）；否则正在显示的还有曲目就留着，再第一个有曲目的播放器、浏览器、
/// 第一个开着的播放器。
///
/// 「手点」（`manual`）：面板来源列表里点的、「其他开着的」里点播放的、对显示中的来源按了播放键的。
/// 有别的来源开始放、或这个来源关了，就不再算手点（`keepsManual`）。
public enum MusicDisplay {
    public typealias Pick = MusicCardChoice.Pick
    public typealias Player = MusicSourceSwitch.Player
    public typealias Browser = MusicCardChoice.Browser

    /// - `players`：开着的播放器，按偏好顺序。
    /// - `browser`：允许的浏览器标签页（不允许或没有时 nil）。
    /// - `wasPlaying` / `browserWasPlaying`：上一次读到时是否在放，认「刚开始播放」。
    /// - `current`：正在显示的。
    /// - `manual`：`current` 是用户手点的。
    /// - `pinned`：固定的来源（`MusicPin.pinned`，自动切换开着时是 nil）。
    /// - `autoSwitch`：谁开始播放就切到谁。
    public static func pick(players: [Player], browser: Browser?,
                            wasPlaying: [MusicSource: Bool], browserWasPlaying: Bool,
                            current: Pick?, manual: Bool,
                            pinned: MusicSource?, autoSwitch: Bool) -> Pick {
        let pin = autoSwitch ? nil : pinned
        let playingNative = players.filter(\.isPlaying)
        let browserPlaying = browser?.isPlaying == true
        let starters = playingNative.filter { wasPlaying[$0.source] != true }.map(\.source)
        let browserStarted = browserPlaying && !browserWasPlaying
        let held = manual && keepsManual(players: players, browser: browser, wasPlaying: wasPlaying,
                                         browserWasPlaying: browserWasPlaying, current: current)

        guard !playingNative.isEmpty || browserPlaying else {
            if held, let current { return current }
            if let pin { return .native(pin) }
            switch current {
            case .native(let source) where players.contains(where: { $0.source == source && $0.hasTrack }):
                return .native(source)
            case .browser where browser?.hasTrack == true:
                return .browser
            default:
                break
            }
            if let first = players.first(where: \.hasTrack) { return .native(first.source) }
            if browser?.hasTrack == true { return .browser }
            if let first = players.first { return .native(first.source) }
            return .none
        }

        if let pin, playingNative.contains(where: { $0.source == pin }) {
            if held, let current, !starters.contains(pin) { return current }
            return .native(pin)
        }
        if held, let current { return current }
        if autoSwitch {
            if let source = current?.source, starters.contains(source) { return .native(source) }
            if let first = starters.first { return .native(first) }
            if browserStarted, playingNative.isEmpty { return .browser }
        }
        switch current {
        case .native(let source) where playingNative.contains(where: { $0.source == source }):
            return .native(source)
        case .browser where browserPlaying && playingNative.isEmpty:
            return .browser
        default:
            break
        }
        if let first = playingNative.first { return .native(first.source) }
        return .browser
    }

    /// 手点的来源还算不算数：还开着（浏览器还有标签页），并且没有别的来源刚开始放。
    public static func keepsManual(players: [Player], browser: Browser?,
                                   wasPlaying: [MusicSource: Bool], browserWasPlaying: Bool,
                                   current: Pick?) -> Bool {
        let otherStarted = players.contains {
            $0.isPlaying && wasPlaying[$0.source] != true && current?.source != $0.source
        } || (browser?.isPlaying == true && !browserWasPlaying && current != .browser)
        guard !otherStarted else { return false }
        switch current {
        case .native(let source): return players.contains(where: { $0.source == source })
        case .browser: return browser != nil
        case .some(.none), nil: return false
        }
    }

    /// 来源胶囊旁的提示：固定着、有来源在放、显示的却不是固定的那个，返回固定的来源
    /// （面板写「固定的 X 没在播」+「取消固定」）。
    public static func pinIdle(pinned: MusicSource?, shown: Pick,
                               players: [Player], browser: Browser?) -> MusicSource? {
        guard let pinned, shown != .native(pinned),
              MusicCardChoice.anyPlaying(players: players, browser: browser) else { return nil }
        return pinned
    }

    /// 显示的是固定的来源，但它没开：面板大标题「X 没开」。
    public static func pinnedClosed(pinned: MusicSource?, shown: Pick, players: [Player]) -> MusicSource? {
        guard let pinned, shown == .native(pinned),
              !players.contains(where: { $0.source == pinned }) else { return nil }
        return pinned
    }
}

/// 面板固定来源的样子：「已固定」小标、「其他开着的」和「取消固定」。
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

    /// 没在播放时下面「其他开着的」列哪些播放器：别的有曲目的（固定着也一样，有来源
    /// 在放时卡片和面板已经显示它了，不会落到这里）。
    public static func others(players: [MusicSourceSwitch.Player], shown: MusicSource?) -> [MusicSource] {
        players.filter { $0.source != shown && $0.hasTrack }.map(\.source)
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
/// 读不到系统真正的待播清单，只能按歌单顺序；开随机时顺序没有意义，面板改写
/// 「顺序由 Apple 音乐决定」（见 `MusicQueue`）。最多读 25 首，只在延展态读满，
/// 收起态只读 3 首（`MusicQueue.readLimit`）。
public enum MusicUpNext {
    public static let limit = 25

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

    /// 当前这首后面一共还有几首：「全部 N 首」和延展态「还有 N 首」用。循环全部时
    /// 是除当前外的整张歌单；找不到当前这首为 0。
    public static func remaining(current: Int, count: Int, wrap: Bool) -> Int {
        guard current >= 1, current <= count else { return 0 }
        return wrap ? count - 1 : count - current
    }
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
        /// 什么时候开始放的，行尾写「几分钟前」。升级前记的没有。
        public var playedAt: Date?

        public var id: String { uri }

        public init(uri: String, title: String, artist: String, duration: Double, artworkURL: String? = nil,
                    playedAt: Date? = nil) {
            self.uri = uri
            self.title = title
            self.artist = artist
            self.duration = duration
            self.artworkURL = artworkURL
            self.playedAt = playedAt
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
