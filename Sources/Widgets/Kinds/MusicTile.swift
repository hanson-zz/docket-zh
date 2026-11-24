import AppKit
import SwiftUI

/// Now Playing: two sizes on a bottom shelf (`MusicCard`): 精简 232×62, a
/// horizontal strip with artwork, track and previous / play / next; 完整
/// 312×132, a small turntable with the record spinning, the tone arm, the
/// controls and a scrubber. A side shelf draws the 76pt column for both.
///
/// 正在播放只管这首歌：封面、曲目、上一首 / 暂停 / 下一首、进度。不放音量，
/// 总音量和输出设备在“音量”，每个应用的音量在“应用音量”。
///
/// Reads Spotify and Apple Music directly, and falls back to whatever video is
/// playing in a scriptable browser tab.
struct MusicTile: View {
    /// 颜色面板里选的主题色（`WidgetTintStyle`），选过颜色时原来写死的强调色跟着换。
    @Environment(\.widgetTint) private var theme
    @Environment(\.colorScheme) private var scheme
    var instance: WidgetInstance
    var context: WidgetContext
    private var config: WidgetConfig { instance.config }
    private var size: MusicCard.Size { MusicCard.size(config) }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Sources the user allows, in preference order. 加了 QQ 音乐；顺序和读法在
    /// Core 的 `MusicSource.enabled`，面板读同一份。
    private var sources: [MusicSource] { MusicSource.enabled(in: config) }

    private var browsersEnabled: Bool { config.bool("browsers", default: true) }

    /// The artwork, when there is one to stand on.
    private var cover: NSImage? {
        guard !context.isPreview else { return nil }
        return playing?.artwork
    }

    /// Ink, pinned once a cover is behind it.
    ///
    /// `WidgetSurface` lays 60% black over the artwork, which makes the card
    /// a dark surface in either appearance. `WidgetStyle.primary` follows the
    /// system, so in a light appearance it would go black and disappear into
    /// exactly the scrim that is there to keep text readable. Same reasoning
    /// as the detail panel's ground and the sticky note's fixed paper.
    private var ink: Color { cover == nil ? WidgetStyle.primary : .white }

    private var subInk: Color {
        cover == nil ? WidgetStyle.secondary : Color(white: 0.82)
    }

    /// The icon of whichever app is playing, for the tile to show when there
    /// is no album art.
    ///
    /// `AppCatalog` caches these; `NSWorkspace.icon(forFile:)` hits the disk
    /// and this is asked on every layout pass. Nil when the app is not
    /// installed, which leaves the generic note rather than a blank square.
    private func sourceIcon(_ track: Playing?) -> NSImage? {
        guard let track, !context.isPreview else { return nil }
        return track.icon ?? AppCatalog.shared.icon(forBundleID: track.sourceBundleID)
    }

    /// How often a playing track is re-read. The scrubber glides over exactly
    /// this long, so it arrives just as the next reading does.
    static let pollInterval: TimeInterval = 0.85

    /// Whichever source has something to show.
    ///
    /// 卡片和面板共用一个「当前显示来源」（服务里的 `display`，Core `MusicDisplay.pick`
    /// 挑的）：有来源在放时两边显示同一首，面板里手点来源卡片也跟着换。
    private var pick: MusicCardChoice.Pick {
        guard !context.isPreview else { return .none }
        return MusicService.shared.display
    }

    /// 浏览器标签页播放状态变了，叫服务马上重挑，不等下一次轮询。
    private var browserState: MusicCardChoice.Browser? {
        guard !context.isPreview, browsersEnabled, let track = BrowserMedia.shared.track else { return nil }
        return MusicCardChoice.Browser(hasTrack: true, isPlaying: track.isPlaying)
    }

    private var browserTrack: Playing? {
        guard browsersEnabled else { return nil }
        return BrowserMedia.shared.track.map {
            Playing(browser: $0, artwork: BrowserMedia.shared.artwork,
                    icon: BrowserMedia.shared.siteIcon, tint: BrowserMedia.shared.tint)
        }
    }

    private var playing: Playing? {
        if context.isPreview { return Self.sample }
        switch pick {
        case .native(let source):
            return MusicService.shared.track(for: source).map(Playing.init(native:))
        case .browser:
            return browserTrack
        case .none:
            return nil
        }
    }

    /// Consent is per target app, so a browser can be blocked while Spotify is
    /// fine, and vice versa. One button clears whichever it is.
    private var needsPermission: Bool {
        guard !context.isPreview else { return false }
        return MusicService.shared.needsAutomationPermission
            || (browsersEnabled && BrowserMedia.shared.needsPermission)
    }

    private static let sample = Playing(native: NowPlaying(
        title: tr("日光"), artist: tr("示例艺人"), album: tr("示例专辑"),
        duration: 240, elapsed: 74, isPlaying: true, artwork: nil, source: .spotify
    ))

    var body: some View {
        // The cover is the card.
        //
        // It used to be a thumbnail drawn inside the card, which on a 64pt
        // chip is a square crop of a 16:9 frame and on the wide tile is
        // 38 points of picture competing with the text beside it. Behind
        // everything it is the record you are listening to rather than a
        // stamp of it.
        // 卡带外观搬成了单独的「复古卡带」小组件（CassetteTile），这里只画默认样式。
        WidgetSurface(image: cover) {
            content
        }
        .onAppear {
            guard !context.isPreview else { return }
            // ponytail: shared poll, start-only - the shelf is always on
            // screen, so there is nothing to stop it for.
            // 来源、「谁开始播放就切到谁」和固定来源一起同步。
            MusicService.shared.configure(config)
            MusicService.shared.start()
            BrowserMedia.shared.enabled = browsersEnabled
            BrowserMedia.shared.start()
        }
        .onChange(of: config) { _, new in
            if !context.isPreview { MusicService.shared.configure(new) }
        }
        .onChange(of: browsersEnabled) { _, new in
            if !context.isPreview { BrowserMedia.shared.enabled = new }
        }
        .onChange(of: browserState) { _, _ in
            if !context.isPreview { MusicService.shared.reconcile() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if needsPermission, playing == nil {
            connect
        } else if let playing {
            if context.position.isVertical { column(playing) }
            else if size == .compact { strip(playing) }
            else { full(playing) }
        } else {
            idle
        }
    }

    // MARK: 精简 232×62 / 完整 312×62

    /// Whichever service actually owns what is on screen. Firing both meant
    /// pausing a YouTube tab also started Spotify, and the tile then jumped to
    /// a different track.
    private func toggle(_ track: Playing) {
        // The artwork reaches this without going through `button`, which is
        // where every other control's preview guard sits.
        guard !context.isPreview else { return }
        if track.isBrowser { BrowserMedia.shared.playPause() }
        else if let source = track.source { MusicService.shared.playPause(on: source) }
        else { MusicService.shared.playPause() }
    }

    /// 精简：横排一条，封面、歌名和歌手、上一首 / 播放 / 下一首，不画进度条。
    /// 封面不再兼做播放键，播放键就在控制里，免得同一排出现两个。
    private func strip(_ track: Playing) -> some View {
        HStack(spacing: 10) {
            Artwork(image: track.artwork, fallback: sourceIcon(track), badge: badge(track), side: 38, corner: 8)
            VStack(alignment: .leading, spacing: 1) {
                title(track, size: 14)
                HStack(spacing: 5) {
                    bars(track, height: 10)
                    artist(track, size: 12)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // 控制固定在右边，歌名再长也只省略自己，按钮不跟着跳。
            transport(track, size: 14, spacing: 12, softPlay: true)
                .fixedSize()
                .layoutPriority(1)
        }
        // 38pt 封面加上下各 3，装进 62 高的卡片不顶边（见 WidgetSurface 的内边距）。
        .padding(.vertical, 3)
        .overlay(alignment: .bottom) { progressLine(track) }
    }

    /// 精简卡片底边 2pt 进度线：不占高度，离卡片底边和左右都留一点，不像裁切线；
    /// 浅色深色、铺了封面底时都换对比色。读不到时长（直播等）不画。
    @ViewBuilder
    private func progressLine(_ track: Playing) -> some View {
        if track.duration > 0 {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(cover == nil ? WidgetStyle.secondary.opacity(0.28) : .white.opacity(0.32))
                    Capsule()
                        .fill(cover == nil ? ink.opacity(0.85) : .white.opacity(0.9))
                        .frame(width: max(2, geo.size.width * track.progress))
                        .animation(track.isPlaying ? .linear(duration: MusicTile.pollInterval) : nil,
                                   value: track.progress)
                }
            }
            .frame(height: 2)
            .padding(.horizontal, 4)
            // 卡片 62 高，内容 44：往下挪到离卡片底边约 4pt。
            .offset(y: 5)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    /// 完整（312×62）：扩展栏横向一排只有 58pt 高（WidgetCatalog.contentSize），
    /// 所以不能按 132 高画，否则上下被裁、圆角变直角。左边 44 的小唱盘（播放时转、
    /// 唱臂落下；暂停停转、唱臂抬回，点唱片也能播放 / 暂停），中间歌名和歌手，
    /// 右边固定上一首 / 实心圆播放键 / 下一首，底边和精简一样一条 2pt 进度线。
    /// 左边是唱盘还是封面看面板样式（`disc`）。
    private func full(_ track: Playing) -> some View {
        HStack(spacing: 10) {
            disc(track)
            VStack(alignment: .leading, spacing: 1) {
                title(track, size: 14)
                HStack(spacing: 5) {
                    bars(track, height: 10)
                    artist(track, size: 12)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            fullTransport(track)
                .fixedSize()
                .layoutPriority(1)
        }
        .overlay(alignment: .bottom) { progressLine(track) }
    }

    /// 完整卡片左边跟着面板样式走：黑胶面板画转着的小唱盘，精简面板只画封面，
    /// 免得选了精简面板，扩展栏上还是一张唱片。点它都是播放 / 暂停。
    @ViewBuilder
    private func disc(_ track: Playing) -> some View {
        if ProLicenseGate.musicPanelStyle(config: config, unlocked: true) == .vinyl {
            MusicMiniTurntable(artwork: track.artwork, fallback: sourceIcon(track), tint: track.tint,
                               playing: track.isPlaying,
                               spinning: track.isPlaying && !reduceMotion && !context.isPreview
                                   && ShelfVisibility.shared.cardsOnScreen,
                               dark: scheme == .dark || cover != nil)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .onTapGesture { toggle(track) }
                .accessibilityLabel(track.isPlaying ? tr("暂停") : tr("播放"))
        } else {
            Artwork(image: track.artwork, fallback: sourceIcon(track), badge: badge(track), side: 42, corner: 9)
                .contentShape(Rectangle())
                .onTapGesture { toggle(track) }
                .accessibilityLabel(track.isPlaying ? tr("暂停") : tr("播放"))
        }
    }

    /// 完整卡片的控制：播放 / 暂停是中间的实心圆，两边上一首、下一首（设置里开了快退快进时在最外侧）。
    /// 浏览器视频只有播放键。
    @ViewBuilder
    private func fullTransport(_ track: Playing) -> some View {
        let play = Button(action: { toggle(track) }) {
            Image(systemName: track.isPlaying ? "pause.fill" : "play.fill")
                .playPauseMorph(track.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(cover == nil ? (scheme == .dark ? Color.black : Color.white) : Color.black)
                .frame(width: 30, height: 30)
                .background(Circle().fill(cover == nil ? ink : .white))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(track.isPlaying ? tr("暂停") : tr("播放"))
        if track.isBrowser {
            play
        } else {
            let skip = max(1, config.int("skip", default: 15))
            HStack(spacing: 10) {
                if config.bool("backward"), track.canSeek {
                    button(skipSymbol("gobackward", skip), 13) { skipBy(track, -Double(skip)) }
                }
                if config.bool("previous", default: true) {
                    button("backward.end.fill", 15) {
                        if let source = track.source { MusicService.shared.previous(on: source) }
                    }
                }
                play
                if config.bool("next", default: true) {
                    button("forward.end.fill", 15) {
                        if let source = track.source { MusicService.shared.next(on: source) }
                    }
                }
                if config.bool("forward"), track.canSeek {
                    button(skipSymbol("goforward", skip), 13) { skipBy(track, Double(skip)) }
                }
            }
        }
    }

    private func scrubber(_ track: Playing) -> some View {
        HStack(spacing: 7) {
            time(MusicTime.clock(track.elapsed))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(cover == nil ? WidgetStyle.secondary.opacity(0.3)
                                                : .white.opacity(0.42))
                    Capsule()
                        .fill(ink)
                        .frame(width: max(0, geo.size.width * track.progress))
                        // Playback advances at a constant rate, so gliding to
                        // each new reading at that rate *is* the truth - and a
                        // bar that steps once a second reads as a stutter even
                        // though the number behind it is correct. Linear, and
                        // only while playing: a seek or a pause should land.
                        .animation(track.isPlaying ? .linear(duration: MusicTile.pollInterval)
                                                   : nil,
                                   value: track.progress)
                }
                .contentShape(Rectangle())
                .onTapGesture { location in
                    // Browser playback is read-only apart from play/pause.
                    guard !context.isPreview, !track.isBrowser, track.canSeek,
                          geo.size.width > 0, track.duration > 0 else { return }
                    let ratio = min(1, max(0, location.x / geo.size.width))
                    if let source = track.source { MusicService.shared.seek(on: source, to: ratio * track.duration) }
                }
            }
            .frame(height: 4)
            time(MusicTime.clock(track.duration))
        }
    }

    private func time(_ text: String) -> some View {
        Text(text)
            .font(WidgetStyle.note)
            .monospacedDigit()
            .rollingValue(text)
            .foregroundStyle(subInk)
            .lineLimit(1)
            .fixedSize()
    }

    // MARK: Column, 76pt wide

    /// No scrubber here: 56pt of usable width cannot carry two clocks and a
    /// bar, so the column spends its height on the track instead.
    private func column(_ track: Playing) -> some View {
        VStack(spacing: 3) {
            Artwork(image: track.artwork, fallback: sourceIcon(track), badge: badge(track), side: 32, corner: 7)
            VStack(spacing: 0) {
                title(track, size: 10)
                HStack(spacing: 3) {
                    bars(track, height: 8)
                    artist(track, size: 9)
                }
            }
            transport(track, size: 11, spacing: 6)
        }
        .padding(.vertical, 2)
    }

    // MARK: Shared pieces

    /// 正在播放的跳动小竖条，放在艺人名前面。小宇宙、网易云、Spotify、
    /// Apple Music 和浏览器视频都一样：播放时跳，暂停时停。
    private func bars(_ track: Playing, height: CGFloat) -> some View {
        PlayingBarsView(playing: track.isPlaying, tint: ink, height: height,
                        visible: !context.isPreview && ShelfVisibility.shared.cardsOnScreen)
    }

    private func title(_ track: Playing, size: CGFloat) -> some View {
        Text(track.title)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(ink)
            .lineLimit(1)
            // Truncated, never shrunk. A video title runs long, and scaling it
            // to fit drove the most important line on the tile down to a few
            // points - smaller than the artist underneath it.
            .truncationMode(.tail)
    }

    private func artist(_ track: Playing, size: CGFloat) -> some View {
        Text(track.artist)
            .font(WidgetStyle.caption(size))
            .foregroundStyle(subInk)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    /// Browser video gets play/pause only: seeking, skipping and track changes
    /// mean nothing to a `<video>` element, and a button that does nothing is
    /// worse than one that is not there.
    ///
    /// `playPause` is false where the layout already puts it on the artwork -
    /// the wide strip does, the column does not - because the two rendered it
    /// side by side otherwise, twice in the same row.
    @ViewBuilder
    private func transport(_ track: Playing, size: CGFloat, spacing: CGFloat,
                           playPause: Bool = true, softPlay: Bool = false) -> some View {
        if track.isBrowser {
            button(track.isPlaying ? "pause.fill" : "play.fill", size) { toggle(track) }
        } else {
            let skip = max(1, config.int("skip", default: 15))
            HStack(spacing: spacing) {
                if config.bool("backward"), track.canSeek {
                    button(skipSymbol("gobackward", skip), size) { skipBy(track, -Double(skip)) }
                }
                if config.bool("previous", default: true) {
                    button("backward.end.fill", size) {
                        if let source = track.source { MusicService.shared.previous(on: source) }
                    }
                }
                if playPause {
                    // 精简卡片：播放键垫一个淡灰圆底，和两边的上一首、下一首分出主次。
                    button(track.isPlaying ? "pause.fill" : "play.fill", size) { toggle(track) }
                        .background {
                            if softPlay {
                                Circle()
                                    .fill(cover == nil ? WidgetStyle.secondary.opacity(0.16) : .white.opacity(0.22))
                                    .frame(width: 28, height: 28)
                                    .allowsHitTesting(false)
                            }
                        }
                }
                if config.bool("next", default: true) {
                    button("forward.end.fill", size) {
                        if let source = track.source { MusicService.shared.next(on: source) }
                    }
                }
                if config.bool("forward"), track.canSeek {
                    button(skipSymbol("goforward", skip), size) { skipBy(track, Double(skip)) }
                }
            }
        }
    }

    /// 卡片按钮控制卡片上这首的来源（和面板显示的是同一个）。
    private func skipBy(_ track: Playing, _ seconds: Double) {
        guard let source = track.source else { return }
        MusicService.shared.skip(on: source, by: seconds)
    }

    /// 封面左下角的来源小图标：有封面时才叠，一眼看出是哪个 App 在放。没封面时
    /// 方块里画的就是这个图标，不再叠一份。
    private func badge(_ track: Playing) -> NSImage? {
        guard track.artwork != nil else { return nil }
        return sourceIcon(track)
    }

    /// SF Symbols only ships numbered skip glyphs for a handful of intervals;
    /// anything else falls back to the plain arrow rather than a blank square.
    private func skipSymbol(_ base: String, _ seconds: Int) -> String {
        let numbered: Set<Int> = [5, 10, 15, 30, 45, 60, 75, 90]
        return numbered.contains(seconds) ? "\(base).\(seconds)" : base
    }

    private func button(_ symbol: String, _ size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: { if !context.isPreview { action() } }) {
            Image(systemName: symbol)
                .playPauseMorph(symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(ink)
                .frame(minWidth: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Empty states

    /// Shown instead of silently failing, and it is the *only* thing that ever
    /// raises the automation consent dialog.
    ///
    /// Sized to the glyph and its label, not to the card: the card's own click
    /// belongs to the detail panel, which offers the same button.
    private var connect: some View {
        Button {
            MusicService.shared.requestAutomationPermission()
            if browsersEnabled { BrowserMedia.shared.requestPermission() }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "music.note")
                    .font(.system(size: 14, weight: .medium))
                Text("连接")
                    .font(WidgetStyle.label(11))
                    .lineLimit(1)
                    // A side shelf leaves 56pt inside the card, which the word
                    // only just fits; truncating it to "Conne…" reads as a bug.
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(ink)
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Three different empty states, because they mean different things.
    ///
    /// "Not playing" when a player is open and idle; the menu path when a
    /// browser has media tabs but will not run our JavaScript; the app names
    /// when nothing at all is open.
    private var idle: some View {
        let open = !context.isPreview && MusicService.shared.hasPlayer
        let setup = browserSetupHint
        return VStack(spacing: 2) {
            Image(systemName: setup != nil ? "switch.2" : (open ? "music.note" : "music.note.list"))
                .font(.system(size: 14, weight: .medium))
            Text(setup ?? (open ? tr("未在播放") : sourceNames))
                .font(WidgetStyle.note)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
        }
        .foregroundStyle(subInk)
        .frame(maxWidth: .infinity)
        .help(setup.map { tr("有浏览器标签页正在播放媒体，但码头无法读取。请开启：\($0)。") }
              ?? (open ? tr("当前没有播放内容。") : tr("码头可读取\(sourceNames)，以及可脚本控制的浏览器标签页中的视频。")))
    }

    /// The menu item the user has to switch on, or nil when nothing is asking.
    private var browserSetupHint: String? {
        guard !context.isPreview, browsersEnabled, BrowserMedia.shared.needsSetup else { return nil }
        let hint = BrowserMedia.shared.setupHint
        return hint.isEmpty ? nil : hint
    }

    /// The players this widget is configured to read, e.g. "Spotify or Music".
    private var sourceNames: String {
        let names = sources.map(\.displayName)
        guard !names.isEmpty else { return tr("无来源") }
        return names.count == 1 ? names[0] : names.joined(separator: tr("或"))
    }
}

/// One reading, whatever produced it, so the layouts do not care whether they
/// are drawing Spotify or a YouTube tab.
struct Playing {
    var title: String
    var artist: String
    var isPlaying: Bool
    var elapsed: TimeInterval
    var duration: TimeInterval
    var progress: Double
    var artwork: NSImage?
    var isBrowser: Bool
    /// Whether the scrubber and the skip-by-seconds buttons can move it.
    var canSeek = true

    /// The app the sound is actually coming from, so the tile can show its
    /// icon when there is no album art.
    ///
    /// Browser video never has artwork, which used to mean every YouTube or
    /// Netflix tab drew the same generic note. The browser's own icon says
    /// far more, and it is the honest answer besides: the browser is what is
    /// playing. Read from the system at runtime rather than shipped, which
    /// is also the only way to show Spotify's mark without redistributing
    /// it.
    var sourceBundleID: String

    /// A better icon than the source app's, when there is one: the site's
    /// own, for browser playback. Netflix in Safari is Netflix, not Safari.
    var icon: NSImage?

    /// The ground the detail panel stands on, when the artwork yielded one.
    var tint: ArtworkTint?

    /// 哪个播放器（浏览器标签页是 nil），面板按它决定随机、循环、喜欢这些。
    var source: MusicSource?
    var album = ""
    /// 原始读数，面板要读随机、循环、音量、喜欢。
    var native: NowPlaying?

    /// Whether anything beyond play/pause is meaningful.
    ///
    /// A `<video>` element has nothing to skip to, so browser playback offers
    /// play/pause and nothing else. Which view draws that one button is the
    /// layout's business - see `transport`'s `playPause`.
    var hasSkipControls: Bool { !isBrowser }

    init(native: NowPlaying) {
        title = native.title
        artist = native.artist
        isPlaying = native.isPlaying
        elapsed = native.elapsed
        duration = native.duration
        progress = native.progress
        artwork = native.artwork
        isBrowser = false
        canSeek = native.source.canSeek
        sourceBundleID = native.source.bundleID
        tint = native.tint
        source = native.source
        album = native.album
        self.native = native
    }

    /// Artwork comes from `BrowserMedia`, which fetches it once per video
    /// rather than once per poll, so it is passed in rather than read here.
    init(browser: BrowserTrack, artwork: NSImage?, icon: NSImage?, tint: ArtworkTint?) {
        title = browser.title
        artist = browser.site
        isPlaying = browser.isPlaying
        elapsed = browser.elapsed
        duration = browser.duration
        progress = browser.progress
        self.artwork = artwork
        isBrowser = true
        sourceBundleID = browser.browser.bundleID
        self.icon = icon
        self.tint = tint
    }
}

/// Album art, or a music-note placeholder when there is none - the tile must
/// never show an empty hole while artwork is still downloading.
private struct Artwork: View {
    var image: NSImage?
    /// Drawn instead of the note when there is no album art: the icon of
    /// whichever app is playing.
    var fallback: NSImage?
    /// 叠在封面左下角的来源 App 小图标（约 18pt）。
    var badge: NSImage? = nil
    var side: CGFloat
    var corner: CGFloat
    /// When set, the artwork itself toggles playback.
    var isPlaying: Bool?
    var onToggle: (() -> Void)?

    /// Plain album art takes no gesture at all. A tap gesture with nothing to
    /// do still *consumes* the tap, so an always-attached handler was how the
    /// column's artwork ate the shelf's click and left the panel unreachable.
    var body: some View {
        if let onToggle, let isPlaying {
            square(control: isPlaying)
                .contentShape(.rect)
                .onTapGesture(perform: onToggle)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(isPlaying ? tr("暂停") : tr("播放"))
        } else {
            square(control: nil)
                .accessibilityLabel("封面")
        }
    }

    /// `control` carries the play state while the artwork is acting as a
    /// button, and is nil when it is only showing the album art.
    private func square(control: Bool?) -> some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(WidgetStyle.primary.opacity(0.08))
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else if let fallback {
                    // The playing app's own icon. Inset, because an app icon
                    // already carries its own rounded shape and padding, and
                    // filling the square with it made the tile look like a
                    // launcher for that app rather than a reading from it.
                    Image(nsImage: fallback)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(side * 0.17)
                } else if control == nil {
                    // Nothing playing and nothing to name, so the generic
                    // note. Only when nothing else occupies the square: with
                    // the play control on top, the note showed through
                    // behind it and read as two overlapping glyphs.
                    Image(systemName: "music.note")
                        .font(.system(size: side * 0.48, weight: .medium))
                        .foregroundStyle(WidgetStyle.primary)
                }
            }
            .overlay {
                // The control lives on the artwork rather than beside it: for
                // video there is nothing to skip to, so a lone button was
                // spending width the title badly needed.
                if let control {
                    ZStack {
                        // Fixed, not hover-driven: SwiftUI's .onHover never
                        // fires in this non-activating accessory panel (see
                        // HoverCatcher), so a hover-only affordance is invisible.
                        Color.black.opacity(0.34)
                        // Full strength, and large. The artwork renders about
                        // 31pt on a default-sized shelf, so a small
                        // semi-transparent glyph over a dark placeholder was
                        // invisible in practice - it read as no control at all.
                        Image(systemName: control ? "pause.fill" : "play.fill")
                            .playPauseMorph(control ? "pause.fill" : "play.fill")
                            .font(.system(size: side * 0.46, weight: .bold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.6), radius: 2)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if let badge {
                    // 在圆角外裁之后叠，图标自己的圆角和阴影不被封面裁掉；
                    // 往外探 2pt，压在封面角上而不是盖住画面中间。
                    let size = min(18, side * 0.5)
                    Image(nsImage: badge)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size, height: size)
                        .shadow(color: .black.opacity(0.45), radius: 1.5, y: 0.5)
                        .offset(x: -2, y: 2)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }
}
