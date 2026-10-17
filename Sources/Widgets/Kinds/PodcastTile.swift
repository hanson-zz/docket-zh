import AppKit
import SwiftUI

/// 播客：the chosen show's cover, the episode playing or the newest one, and
/// play and pause on the card. A red count on the cover says how many new
/// episodes across every subscription have not been played.
///
/// The subscriptions are shared by every 播客 widget and kept by
/// `PodcastService`; which show this card shows is its own, under `show`.
/// A click anywhere but the button belongs to the shelf and opens the panel.
struct PodcastTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var service: PodcastService { PodcastService.shared }
    private var player: PodcastPlayer { PodcastPlayer.shared }

    private var show: PodcastShow? {
        if context.isPreview { return Self.sample }
        return PodcastRemote.show(for: instance)
    }

    /// The episode playing from this show, else its newest.
    private var episode: PodcastEpisode? {
        guard let show else { return nil }
        if !context.isPreview, player.showID == show.id, let current = player.episode { return current }
        return show.episodes.first
    }

    private var playing: Bool {
        if context.isPreview { return false }
        guard let episode else { return false }
        return player.isCurrent(episode) && player.isPlaying
    }

    private var unheard: Int { context.isPreview ? 1 : service.library.unheardCount }

    private var caption: String {
        if context.isPreview { return tr("最新：心灵音乐 005") }
        guard let show else { return tr("在面板中粘贴小宇宙链接") }
        if let episode, player.isCurrent(episode) {
            if player.problem != nil { return tr("播放失败") }
            if player.isBuffering, player.isPlaying { return tr("正在缓冲…") }
            // 有时间轴时，播放中的说明换成当前章节，像歌词一样跟着走。
            if player.isPlaying,
               let chapter = PodcastChapters.current(PodcastRemote.chapters(for: episode), at: player.position) {
                return chapter.title
            }
            return player.isPlaying ? episode.title : tr("已暂停 · \(episode.title)")
        }
        if service.problems[show.id] != nil, show.episodes.isEmpty { return tr("暂时连不上小宇宙") }
        return episode.map { tr("最新：\($0.title)") } ?? tr("还没有单集")
    }

    var body: some View {
        WidgetSurface {
            if context.position.isVertical {
                VStack(spacing: 4) {
                    cover(size: 34)
                    Text(show?.title ?? tr("播客"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WidgetStyle.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    playButton(size: 9)
                }
            } else {
                HStack(spacing: 9) {
                    cover(size: 40)
                    TileReading(value: show?.title ?? tr("播客"), caption: caption, valueSize: 15)
                    Spacer(minLength: 0)
                    playButton(size: 11)
                }
            }
        }
    }

    /// 这张卡片的节目正在放（或暂停在）某一集。
    private var isCurrentShow: Bool {
        guard !context.isPreview, let episode else { return false }
        return player.isCurrent(episode)
    }

    private func cover(size: CGFloat) -> some View {
        PodcastCover(url: show?.imageURL, size: size, preview: context.isPreview)
            // 正在播放的跳动小竖条，压在封面左下角，和“正在播放”卡片同一套。
            .overlay(alignment: .bottomLeading) {
                if isCurrentShow {
                    PlayingBarsView(playing: playing, tint: .white, height: size * 0.3,
                                    visible: ShelfVisibility.shared.cardsOnScreen)
                        .padding(.horizontal, size * 0.1)
                        .padding(.vertical, size * 0.08)
                        .background {
                            RoundedRectangle(cornerRadius: size * 0.12, style: .continuous)
                                .fill(.black.opacity(0.35))
                        }
                        .padding(size * 0.06)
                }
            }
            .overlay(alignment: .topTrailing) {
                if unheard > 0 {
                    Text(unheard > 9 ? "9+" : "\(unheard)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3.5)
                        .frame(minWidth: 13, minHeight: 13)
                        .background(Capsule().fill(Color(hex: "#FF3B30")))
                        .offset(x: 4, y: -4)
                        .accessibilityLabel(tr("\(unheard) 个新单集"))
                }
            }
    }

    private func playButton(size: CGFloat) -> some View {
        TileGlyph(symbol: playing ? "pause.fill" : "play.fill", size: size,
                  tint: playing ? PodcastCover.accent : WidgetStyle.primary,
                  morphs: true,
                  action: context.isPreview || episode?.audioURL == nil ? nil : {
            if let episode, let show { player.toggle(episode, show: show.id) }
        })
        .help(playing ? tr("暂停") : tr("播放"))
        .accessibilityLabel(playing ? tr("暂停播客") : tr("播放 \(episode?.title ?? tr("播客"))"))
    }

    static let sample = PodcastShow(id: "sample", title: tr("冥想音疗馆"), author: tr("Hanson汉森"),
                                    episodeCount: 5,
                                    episodes: [PodcastEpisode(id: "sample-5", title: tr("心灵音乐 005"),
                                                              pubDate: nil, duration: 3602, audioURL: nil)])
}

/// Shared by the tile and the panel.
@MainActor
enum PodcastRemote {
    static let showKey = "show"

    /// The show this widget has chosen, or the first subscription.
    static func show(for instance: WidgetInstance) -> PodcastShow? {
        let shows = PodcastService.shared.library.shows
        let chosen = instance.config.string(showKey)
        return shows.first { $0.id == chosen } ?? shows.first
    }

    /// 一集的章节：播放器手里的那份可能是开始播放时的旧数据，先找订阅里
    /// 最新读到的同一集。
    static func chapters(for episode: PodcastEpisode) -> [PodcastChapter] {
        for show in PodcastService.shared.library.shows {
            if let fresh = show.episodes.first(where: { $0.id == episode.id }), let chapters = fresh.chapters {
                return chapters
            }
        }
        return episode.chapters ?? []
    }

    static func choose(_ showID: String, in instance: WidgetInstance) {
        WidgetWriter.write(instance) { $0.set(showKey, .string(showID)) }
    }
}

/// A show's cover from `PodcastService`'s cache, a microphone until it arrives.
struct PodcastCover: View {
    var url: URL?
    var size: CGFloat
    var preview: Bool = false

    /// 小宇宙's own turquoise.
    static let accent = Color(hex: "#25B4E1")

    var body: some View {
        let image = preview ? nil : PodcastService.shared.image(url)
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [Self.accent, Self.accent.mix(with: .black, by: 0.35)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "mic.fill")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.24, style: .continuous))
        .accessibilityHidden(true)
    }
}
