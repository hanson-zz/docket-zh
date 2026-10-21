import Foundation

/// 网易云音乐、QQ 音乐、小宇宙这些没有 AppleScript 的播放器，面板按钮怎么控制。
///
/// 按顺序试：
/// 1. 系统「正在播放」命令（MediaRemote 的 MRMediaRemoteSendCommand，经 osascript
///    发，和读数同一条路），不要任何权限；第一次按完核对读数变没变。
/// 2. 核对过不灵，且已有辅助功能权限：点这个 App 菜单栏里的「播放 / 暂停」「下一首」
///    「上一首」菜单项（只认这个 App，不会落到别的播放器上）。
/// 3. 菜单里找不到：模拟键盘媒体键（同样要辅助功能权限，发给系统当前的正在播放 App）。
///
/// 第 1 步核对过不灵又没有辅助功能权限时，面板写一行说明和「去授权」。
public enum NowPlayingControl {
    public enum Command: String, Sendable, CaseIterable {
        case playPause, next, previous

        /// `MusicService` 发给 AppleScript 播放器的那几句。
        public init?(body: String) {
            switch body {
            case "playpause": self = .playPause
            case "next track": self = .next
            case "previous track": self = .previous
            default: return nil
            }
        }

        /// MRMediaRemoteCommand：kMRTogglePlayPause = 2、kMRNextTrack = 4、kMRPreviousTrack = 5。
        public var remoteCode: Int {
            switch self {
            case .playPause: 2
            case .next: 4
            case .previous: 5
            }
        }

        /// NX_KEYTYPE_PLAY = 16、NX_KEYTYPE_NEXT = 17、NX_KEYTYPE_PREVIOUS = 18。
        public var mediaKey: Int {
            switch self {
            case .playPause: 16
            case .next: 17
            case .previous: 18
            }
        }
    }

    public enum Route: Equatable, Sendable {
        /// 系统「正在播放」命令，不要权限。
        case remote
        /// 点 App 菜单栏里的菜单项，要辅助功能。
        case menu
        /// 模拟媒体键，要辅助功能。
        case mediaKey
    }

    /// 系统「正在播放」命令对这个来源灵不灵。只记在内存里，码头重启后重新核对。
    public enum Verdict: Equatable, Sendable {
        case unknown, works, fails
    }

    /// 这次按键按顺序试哪几条路。
    ///
    /// 不灵又没权限时仍发一次系统命令（不花什么，偶尔是读数慢了才判成不灵）。
    public static func routes(remote: Verdict, trusted: Bool) -> [Route] {
        switch (remote, trusted) {
        case (.fails, true): [.menu, .mediaKey]
        case (.fails, false): [.remote]
        case (_, true): [.remote, .menu, .mediaKey]
        case (_, false): [.remote]
        }
    }

    /// 系统命令要不要核对：没核对过才核对，核对过灵的就不再等。
    public static func verifies(_ remote: Verdict) -> Bool { remote == .unknown }

    /// 面板写「需要辅助功能权限」：系统命令核对过不灵，又没给辅助功能。
    public static func needsAccessibility(remote: Verdict, trusted: Bool) -> Bool {
        remote == .fails && !trusted
    }

    /// 按键前后读到的系统「正在播放」。
    public struct Snapshot: Equatable, Sendable {
        public var title: String
        public var isPlaying: Bool
        public var elapsed: TimeInterval

        public init(title: String, isPlaying: Bool, elapsed: TimeInterval) {
            self.title = title
            self.isPlaying = isPlaying
            self.elapsed = elapsed
        }
    }

    /// 读数说明这次命令生效了没有。前后有一个读不到就当生效（宁可少回退一次，
    /// 也不要连按两次：暂停又播放、连跳两首）。
    public static func took(_ command: Command, before: Snapshot?, after: Snapshot?) -> Bool {
        guard let before, let after else { return true }
        switch command {
        case .playPause:
            return after.isPlaying != before.isPlaying
        case .next:
            return after.title != before.title || after.elapsed + 2 < before.elapsed
        case .previous:
            // 播了一会儿再按上一首，很多播放器是从头放这一首。
            return after.title != before.title || after.elapsed + 2 < before.elapsed
        }
    }

    // MARK: 菜单项

    /// 播放器菜单栏里可能放控制项的菜单，先找这几个。
    static let controlMenus: Set<String> = ["控制", "播放", "播放控制", "Controls", "Control", "Playback"]

    /// 菜单项标题（去掉空白和省略号后整句相同才算，不认「播放列表」「播放模式」这类）。
    static func titles(for command: Command) -> [String] {
        switch command {
        case .playPause:
            ["播放/暂停", "暂停/播放", "播放", "暂停", "Play/Pause", "Play / Pause", "Play", "Pause"]
        case .next:
            ["下一首", "下一曲", "下一个", "Next", "Next Track", "Next Song"]
        case .previous:
            ["上一首", "上一曲", "上一个", "Previous", "Previous Track", "Previous Song"]
        }
    }

    static func normalized(_ title: String) -> String {
        var text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("…") || text.hasSuffix(".") { text.removeLast() }
        return text.replacingOccurrences(of: " / ", with: "/")
            .lowercased()
    }

    /// 一个菜单：菜单栏上的标题和下面各项的标题（分隔线是空字符串）。
    public struct Menu: Equatable, Sendable {
        public var title: String
        public var items: [String]

        public init(title: String, items: [String]) {
            self.title = title
            self.items = items
        }
    }

    /// 该点哪个菜单项：(第几个菜单, 第几项)。控制类菜单优先，其余菜单其次；同一个
    /// 菜单里按标题候选的先后挑。第一个菜单（App 名字那个）不找。
    public static func menuItem(for command: Command, in menus: [Menu]) -> (menu: Int, item: Int)? {
        let wanted = titles(for: command).map(normalized)
        let order = menus.indices.dropFirst().sorted { a, b in
            let ca = controlMenus.contains(menus[a].title.trimmingCharacters(in: .whitespaces))
            let cb = controlMenus.contains(menus[b].title.trimmingCharacters(in: .whitespaces))
            return ca == cb ? a < b : ca
        }
        for m in order {
            let items = menus[m].items.map(normalized)
            for title in wanted {
                if let i = items.firstIndex(of: title) { return (m, i) }
            }
        }
        return nil
    }
}
