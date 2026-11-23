import AppKit
import SwiftUI

// MARK: - 刘海小岛的「音乐」活动
//
// 收起：刘海左边圆角封面缩略图，右边细音波条（封面主色，暂停时三条静止短竖线、封面压暗）。
// 展开：从刘海下沿长出来的玻璃卡片（和电台卡片同一套接缝、同高 150），左边 96 点封面，
// 封面左下角趴着戴耳机的小熊猫贴纸；右边歌名、歌手、细进度条和两端时间，一排上一首、
// 播放暂停、下一首，右边音量和来源 App 图标。顶部一层很淡的封面主色光晕。
//
// 读数都来自 `MusicService`（和「正在播放」小组件同一首），纯逻辑在 Core 的 NotchIslandMusic.swift。
// 音波只是按播放状态的装饰：不读麦克风、不采集音频。

/// 封面主色换成 SwiftUI 颜色。
enum NotchIslandMusicPalette {
    static func color(_ rgb: (red: Double, green: Double, blue: Double)) -> Color {
        Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }

    /// 收起时音波的颜色（Core `NotchIslandMusicLook.waveColor`）。
    static func wave(_ tint: ArtworkTint?) -> Color {
        color(NotchIslandMusicLook.waveColor(tint))
    }
}

/// 当前这首的封面；还没读到时是一块带音符的底。暂停时压暗。
struct NotchIslandMusicThumb: View {
    var playing: Bool
    var size: CGFloat
    var cornerRadius: CGFloat

    var body: some View {
        let artwork = MusicService.shared.nowPlaying?.artwork
        ZStack {
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.white.opacity(0.14)
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.55, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .opacity(playing ? 1 : NotchIslandMusicLook.pausedArtOpacity)
        .animation(.easeInOut(duration: 0.25), value: playing)
        .accessibilityHidden(true)
    }
}

/// 细音波条：播放时五根轻轻起伏（纯装饰），暂停时三根一样高的静止短竖线，减弱动态效果时静止。
struct NotchIslandMusicWave: View {
    var playing: Bool
    var color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if NotchIslandMusicLook.animates(playing: playing, reduceMotion: reduceMotion) {
            TimelineView(.animation(minimumInterval: 1 / 20)) { tick in
                bars(NotchIslandMusicLook.barLevels(at: tick.date.timeIntervalSinceReferenceDate,
                                                    playing: true, reduceMotion: false))
            }
        } else {
            bars(NotchIslandMusicLook.barLevels(at: 0, playing: playing, reduceMotion: reduceMotion))
        }
    }

    private func bars(_ levels: [Double]) -> some View {
        GeometryReader { proxy in
            let count = max(1, levels.count)
            let gap: CGFloat = 2
            let width = min(2.5, max(1.5, (proxy.size.width - gap * CGFloat(count - 1)) / CGFloat(count)))
            HStack(alignment: .center, spacing: gap) {
                ForEach(0..<levels.count, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(color.opacity(playing ? 1 : 0.75))
                        .frame(width: width, height: max(width, proxy.size.height * CGFloat(levels[index])))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 展开的卡片

/// 音乐卡片的内容（卡片外形、玻璃和光晕在 `NotchIslandCard`）。
///
///     [封面 96]   晨光里的码头
///     [小熊猫]    海风乐队
///                 ━━━━━━──────────
///                 1:24        -2:10
///                 ⏮  (⏸)  ⏭      🔈 [App]
struct NotchIslandMusicCard: View {
    var model: NotchIslandModel
    var song: NotchIslandMusic

    @Environment(\.colorScheme) private var scheme
    @State private var showVolume = false

    /// 这个播放器此刻的读数（进度每秒都变，不放在活动里）。
    private var reading: NowPlaying? {
        guard let source = song.source else { return MusicService.shared.nowPlaying }
        return MusicService.shared.track(for: source)
    }

    var body: some View {
        let track = reading
        let playing = track?.isPlaying ?? song.playing
        let canControl = song.source.map { MusicService.shared.canControl($0) } ?? true
        HStack(alignment: .center, spacing: 14) {
            cover(playing: playing)
            VStack(alignment: .leading, spacing: 0) {
                titleBlock(track)
                Spacer(minLength: 6)
                if showVolume, model.musicVolume != nil {
                    volumeRow
                } else {
                    progressRow(track)
                }
                Spacer(minLength: 6)
                controls(playing: playing, canControl: canControl)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(NotchIslandText.spoken(.music(song), now: Date()))
    }

    // MARK: 封面和小熊猫

    private func cover(playing: Bool) -> some View {
        Button { model.act?(.musicOpen(song.source)) } label: {
            NotchIslandMusicThumb(playing: playing, size: NotchIslandMusicLook.coverSize, cornerRadius: 16)
                .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.18), radius: 8, y: 3)
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr("打开音乐面板"))
        .overlay(alignment: .bottomLeading) { sticker }
    }

    /// 封面左下角戴耳机的小熊猫贴纸（Resources/PandaStates/panda-scene-listen，戴耳机趴着听歌），
    /// 高度不超过卡片三分之一，不挡字和按钮，也不拦截点击。
    @ViewBuilder private var sticker: some View {
        if let image = PandaStateArt.image(.scene(.listen)) {
            let card = NotchIslandLayout.cardHeight(model.geometry, kind: .music, hasSecondary: false)
            let height = NotchIslandMusicLook.stickerHeight(cardHeight: card)
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(height: height)
                .shadow(color: .black.opacity(0.22), radius: 3, y: 1.5)
                .offset(x: -10, y: 8)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    // MARK: 歌名、进度

    private func titleBlock(_ track: NowPlaying?) -> some View {
        Button { model.act?(.musicOpen(song.source)) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: track?.title ?? song.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.panelPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .truncationMode(.tail)
                let artist = track?.artist ?? song.artist
                if !artist.isEmpty {
                    Text(verbatim: artist)
                        .font(.system(size: 13))
                        .foregroundStyle(.panelSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(song.line)
        .accessibilityHint(tr("打开音乐面板"))
    }

    @ViewBuilder private func progressRow(_ track: NowPlaying?) -> some View {
        if let track, let times = NotchIslandMusicText.times(elapsed: track.elapsed, duration: track.duration) {
            VStack(spacing: 3) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.panelTrack)
                        Capsule()
                            .fill(Color.panelPrimary.opacity(0.72))
                            .frame(width: proxy.size.width
                                * NotchIslandMusicText.progress(elapsed: track.elapsed, duration: track.duration))
                    }
                }
                .frame(height: 4)
                .accessibilityHidden(true)
                HStack {
                    Text(verbatim: times.elapsed)
                    Spacer(minLength: 6)
                    Text(verbatim: times.remaining)
                }
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(.panelSecondary)
                .lineLimit(1)
            }
        } else {
            // 直播流、读不到时长：不画进度，留一行副标题的高度。
            Text(song.playing ? tr("正在播放") : tr("已暂停"))
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
                .lineLimit(1)
        }
    }

    private var volumeRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelSecondary)
                .accessibilityHidden(true)
            Slider(value: Binding(
                get: { model.musicVolume ?? 50 },
                set: { value in
                    model.musicVolume = value
                    model.act?(.musicVolume(value))
                }), in: 0...100)
                .controlSize(.small)
                .tint(Color.panelPrimary.opacity(0.72))
                .accessibilityLabel(tr("音量"))
        }
        .frame(height: 23)
    }

    // MARK: 按钮

    private func controls(playing: Bool, canControl: Bool) -> some View {
        HStack(spacing: 6) {
            glyph("backward.fill", label: tr("上一首"), enabled: canControl) {
                model.act?(.musicPrevious(song.source))
            }
            NotchIslandCircleButton(symbol: playing ? "pause.fill" : "play.fill",
                                    label: playing ? tr("暂停") : tr("播放"), solid: false,
                                    enabled: canControl, diameter: 36) {
                model.act?(.musicToggle(song.source))
            }
            glyph("forward.fill", label: tr("下一首"), enabled: canControl) {
                model.act?(.musicNext(song.source))
            }
            Spacer(minLength: 4)
            if model.musicVolume != nil {
                glyph(showVolume ? "speaker.wave.2.circle.fill" : "speaker.wave.2.fill", label: tr("音量"),
                      enabled: true) {
                    showVolume.toggle()
                }
            }
            sourceIcon
        }
    }

    /// 不带底的小图标按钮（上一首、下一首、音量），点击区 28 点。
    private func glyph(_ symbol: String, label: String, enabled: Bool,
                       action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.panelPrimary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityLabel(label)
    }

    /// 来源 App 的真实图标（从系统读，不内置任何品牌图），读不到时是通用音符。点一下打开那个 App。
    private var sourceIcon: some View {
        let icon = song.source.flatMap { AppCatalog.shared.icon(forBundleID: $0.bundleID) }
        return Button { model.act?(.musicOpenApp(song.source)) } label: {
            Group {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.panelPrimary)
                }
            }
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.panelFill))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.panelStroke, lineWidth: 0.5))
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(song.source.map { tr("打开 \($0.displayName)") } ?? tr("打开音乐"))
        .disabled(song.source == nil)
    }
}
