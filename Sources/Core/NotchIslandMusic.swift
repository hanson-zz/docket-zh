import CoreGraphics
import Foundation

// MARK: - 刘海小岛的「音乐」活动
//
// 别的 App（Apple Music、Spotify、网易云等）正在播放时，刘海两侧一边是圆角封面缩略图、
// 一边是细音波条；悬停展开成从刘海长出来的玻璃卡片：封面、歌名歌手、进度和时间、
// 上一首 / 播放暂停 / 下一首、音量和来源 App 图标。读数复用「正在播放」那一套
// （`MusicService` 的当前显示来源），这里只放纯逻辑：活动的值、暂停后留多久、
// 时间文字、音波的样子、点歌曲区域打开哪张小组件面板。
//
// 音波只是按播放状态的装饰性律动：不读麦克风、不采集也不分析音频。

/// 音乐活动携带的真实值。值只在歌、播放状态或封面主色变了时才变（进度每秒都变，不放这里），
/// 小岛不会每秒重排。
public struct NotchIslandMusic: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var playing: Bool
    /// 封面主色（`ArtworkTint`），封面还没读到或是灰白封面时 nil。
    public var tint: ArtworkTint?
    /// 哪个播放器，按钮和来源图标按它找。
    public var source: MusicSource?

    public init(title: String, artist: String, playing: Bool, tint: ArtworkTint? = nil, source: MusicSource? = nil) {
        self.title = title
        self.artist = artist
        self.playing = playing
        self.tint = tint
        self.source = source
    }

    /// 一个播放器的读数换成活动的值；没有歌名（停止、没有会话、还在载入）时 nil，小岛不显示。
    public static func reading(title: String, artist: String, playing: Bool, tint: ArtworkTint?,
                               source: MusicSource?) -> NotchIslandMusic? {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return NotchIslandMusic(title: name, artist: artist.trimmingCharacters(in: .whitespacesAndNewlines),
                                playing: playing, tint: tint, source: source)
    }

    /// 读屏和第二行用的一句「歌名 · 歌手」，没有歌手时只有歌名。
    public var line: String {
        artist.isEmpty ? title : "\(title) · \(artist)"
    }
}

// MARK: - 暂停后留多久

/// 音乐活动什么时候上小岛：在播就显示；从在播变成暂停后再留 `musicPauseLinger` 秒
/// （暂停态有自己的样子），到点收起；停止、没有会话立刻收起。一开始就是暂停着的
/// （打开小岛前就停在那儿的歌）不显示，免得刘海旁常驻一首没在听的歌。
public struct NotchIslandMusicTracker: Equatable, Sendable {
    private enum Phase: Equatable, Sendable {
        /// 没有歌，或一直是暂停着的。
        case idle
        case playing
        case paused(since: Date)
    }

    private var phase: Phase = .idle
    private var last: NotchIslandMusic?

    public init() {}

    /// 读了一次「正在播放」：当前显示来源的歌，没有时 nil。
    public mutating func update(_ reading: NotchIslandMusic?, now: Date) {
        guard let reading else {
            phase = .idle
            last = nil
            return
        }
        last = reading
        if reading.playing {
            phase = .playing
            return
        }
        switch phase {
        case .playing: phase = .paused(since: now)
        case .paused, .idle: break
        }
    }

    /// 指针停在小岛上（卡片展开着）：暂停的计时从现在重新算，不在用户看着时收起。
    public mutating func keepAlive(now: Date) {
        if case .paused = phase { phase = .paused(since: now) }
    }

    /// 现在要显示的音乐活动，没有时 nil。
    public func activity(now: Date) -> NotchIslandActivity? {
        guard let last else { return nil }
        switch phase {
        case .idle:
            return nil
        case .playing:
            return .music(last)
        case .paused(let since):
            guard now.timeIntervalSince(since) < NotchIslandTiming.musicPauseLinger else { return nil }
            return .music(last)
        }
    }
}

// MARK: - 时间文字

public enum NotchIslandMusicText {
    /// 卡片进度条两端：已播「1:24」（向下取整）和剩余「-2:10」（总长向上取整减已播，两边加起来
    /// 正好是总长）。没有时长（直播流、读不到）时 nil，卡片不画进度。一小时以上「1:02:03」。
    public static func times(elapsed: TimeInterval, duration: TimeInterval) -> (elapsed: String, remaining: String)? {
        guard duration.isFinite, duration > 0 else { return nil }
        let total = duration.rounded(.up)
        let played = elapsed.isFinite ? min(total, max(0, elapsed.rounded(.down))) : 0
        return (NotchIslandText.clock(played), "-" + NotchIslandText.clock(total - played))
    }

    /// 进度条走了多少，0...1。
    public static func progress(elapsed: TimeInterval, duration: TimeInterval) -> Double {
        guard duration.isFinite, duration > 0, elapsed.isFinite else { return 0 }
        return min(1, max(0, elapsed / duration))
    }
}

// MARK: - 样子

public enum NotchIslandMusicLook {
    /// 收起时音波的颜色：封面主色的亮色（`ArtworkTint.glow`，黑底上看得出是什么颜色），
    /// 没有封面主色时用小岛的暖橙。sRGB 0...1。
    public static func waveColor(_ tint: ArtworkTint?) -> (red: Double, green: Double, blue: Double) {
        tint?.glow ?? fallbackWave
    }

    /// 暖橙 #FF9A3C，和小岛其他图标同色。
    public static let fallbackWave: (red: Double, green: Double, blue: Double) = (1, 154.0 / 255, 60.0 / 255)

    /// 暂停时封面压暗到多少（不透明度）。
    public static let pausedArtOpacity: Double = 0.55

    /// 播放时五根、暂停时三根静止短竖线。
    public static let playingBars = 5
    public static let pausedBars = 3
    /// 暂停时三根短竖线的高度（占音波条高度的比例）。
    public static let pausedLevel: Double = 0.42
    /// 减弱动态效果时播放中的静止高低。
    public static let restLevels: [Double] = [0.45, 0.8, 0.6, 0.95, 0.5]

    /// 每根竖条此刻的高度（0...1）。播放且没开减弱动态效果时按时间轻轻起伏（纯装饰，
    /// 和真实音频无关）；减弱动态效果时停在固定的高低；暂停时三根一样高的短竖线。
    public static func barLevels(at time: TimeInterval, playing: Bool, reduceMotion: Bool) -> [Double] {
        guard playing else { return Array(repeating: pausedLevel, count: pausedBars) }
        guard !reduceMotion else { return restLevels }
        return (0..<playingBars).map { index in
            let phase = time * (3.6 + Double(index) * 0.85) + Double(index) * 1.7
            return 0.3 + 0.7 * (sin(phase) + 1) / 2
        }
    }

    /// 播放时音波要不要按时间重画（暂停、减弱动态效果时不用定时器）。
    public static func animates(playing: Bool, reduceMotion: Bool) -> Bool {
        playing && !reduceMotion
    }

    /// 展开卡片左边封面的边长。
    public static let coverSize: CGFloat = 96
    /// 卡片顶部封面主色光晕的不透明度上限和往下渐隐到哪儿（沿用「正在播放」面板那一套）。
    public static let glowOpacity: Double = ArtworkTint.glowOpacity
    public static let glowReach: Double = ArtworkTint.glowReach

    /// 封面左下角戴耳机小熊猫贴纸的高度：不超过卡片高度的三分之一，也不超过 46 点。
    public static func stickerHeight(cardHeight: CGFloat) -> CGFloat {
        min(46, floor(cardHeight / 3))
    }
}

// MARK: - 点歌曲区域打开哪里

public enum NotchIslandMusicRoute {
    /// 点卡片上的歌曲区域打开哪张小组件的面板：先找当前布局里的「正在播放」，再找别的布局里的，
    /// 都没有时找「复古卡带」（读同一份正在播放）；一张都没有时 nil，改为打开来源 App。
    public static func panelWidget(current: [WidgetInstance], all: [WidgetInstance]) -> UUID? {
        for kind in [WidgetKind.music, .cassette] {
            if let hit = current.first(where: { $0.kind == kind }) ?? all.first(where: { $0.kind == kind }) {
                return hit.id
            }
        }
        return nil
    }
}
