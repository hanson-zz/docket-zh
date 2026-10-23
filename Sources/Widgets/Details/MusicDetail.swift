import AppKit
import SwiftUI

/// 「正在播放」面板（效果图 design/media-panel.png）。
///
/// 从上到下：来源胶囊（App 图标、名字、播放中小竖条、展开箭头）和「在 App 中打开」，
/// 大封面，歌名 / 歌手 · 专辑，进度条（能拖才有圆点），上一首 / 播放 / 下一首
/// （白色实心钮、深色字形；Apple 音乐和 Spotify 两侧加随机、循环），音量条，再往下是
/// Apple 音乐的「接下来」或 Spotify 的「刚才听过」3 首（方案 A，design/music-queue-2.png：
/// 有这块时封面 128、控制键收紧，内容底约 520，不再落进底部渐隐带；点「全部 N 首」
/// 延展成迷你播放条吸顶加整张列表，判断在 Core `MusicQueue`）。底部「外观」行由面板外框画。
/// 卡带外观搬成了单独的「复古卡带」小组件，面板里不再有「卡带外观」选择条。
///
/// 原来是一张铺满封面的卡片，往外多画 10pt（`bleed`），超出面板内边距，右边贴着面板
/// 边缘露出一条亮边；现在不再越界，背景改成深色玻璃加封面主色光晕（外框按
/// `ground` 画，不超过 15%）。
///
/// 点来源胶囊展开来源列表（开着的播放器、浏览器标签页、「谁开始播放就切到谁」）；
/// 没在播放时是小熊猫空状态、「打开 X」和其他开着的播放器。
///
/// It does not start the services: the panel only ever opens from a tile that
/// is already on screen, and that tile owns the poll and the source list.
struct MusicDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private enum Page { case player, sources, list }

    @State private var page: Page = .player
    /// Where a drag is holding the playhead, 0…1, or nil when the bar is
    /// following playback.
    @State private var scrubbing: Double?
    /// 拖音量时先跟手，松开前不让读数把滑块拉回去。
    @State private var dragVolume: Double?
    @State private var hovered: String?
    @Namespace private var coverSpace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 写过之后面板拿到的仍可能是打开时的那份，读最新存着的。
    private var current: WidgetInstance { WidgetWriter.current(instance.id) ?? instance }
    private var config: WidgetConfig { current.config }
    private var sources: [MusicSource] { MusicSource.enabled(in: config) }
    private var browsersEnabled: Bool { config.bool("browsers", default: true) }
    private var autoSwitch: Bool { MusicSourceSwitch.autoSwitch(config) }
    /// 固定着的来源（关了自动切换并选过来源）。
    private var pinnedSource: MusicSource? { MusicPin.pinned(config) }

    private static let base = Color(.sRGB, red: 0.11, green: 0.11, blue: 0.125, opacity: 1)
    private let ink = Color.panelPrimary

    /// 面板外框画的底色：封面主色做顶部光晕。没有封面时给一个没有颜色的，外框
    /// 照样画深色底。
    /// 液态玻璃：只在深色外观下画这层深色底；浅色外观返回 nil，面板和其他面板一样
    /// 是浅色玻璃，文字是语义色（封面自己的光晕还在封面背后）。
    @MainActor
    static func ground(instance: WidgetInstance, context: WidgetContext) -> ArtworkTint? {
        guard NSApp.effectiveAppearance.panelIsDark else { return nil }
        return MusicDetail(instance: instance, context: context).playing?.tint
            ?? ArtworkTint(hue: 0, saturation: 0)
    }

    /// 和卡片同一个「当前显示来源」（服务的 `display`，Core `MusicDisplay.pick`）。
    fileprivate var playing: Playing? {
        guard !context.isPreview else { return nil }
        switch MusicService.shared.display {
        case .native(let source): return MusicService.shared.track(for: source).map(Playing.init(native:))
        case .browser: return browserPlaying
        case .none: return nil
        }
    }

    /// 给 Core 判断用的开着的播放器和浏览器标签页。
    private var corePlayers: [MusicSourceSwitch.Player] {
        context.isPreview ? [] : MusicService.shared.switchPlayers
    }

    private var coreBrowser: MusicCardChoice.Browser? {
        browserPlaying.map { MusicCardChoice.Browser(hasTrack: true, isPlaying: $0.isPlaying) }
    }

    /// 固定着、有来源在放、显示的却不是固定的：「固定的 X 没在播」。
    private var pinIdle: MusicSource? {
        guard !context.isPreview else { return nil }
        return MusicDisplay.pinIdle(pinned: pinnedSource, shown: MusicService.shared.display,
                                    players: corePlayers, browser: coreBrowser)
    }

    private var browserPlaying: Playing? {
        guard browsersEnabled else { return nil }
        return BrowserMedia.shared.track.map {
            Playing(browser: $0, artwork: BrowserMedia.shared.artwork,
                    icon: BrowserMedia.shared.siteIcon, tint: BrowserMedia.shared.tint)
        }
    }

    private var needsPermission: Bool {
        guard !context.isPreview else { return false }
        return MusicService.shared.needsAutomationPermission
            || (browsersEnabled && BrowserMedia.shared.needsPermission)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch page {
            case .sources:
                topRow(playing)
                sourcesPage
            case .list where expandedBlock != nil:
                topRow(playing)
                expandedPage(playing!, expandedBlock!)
            default:
                if let track = playing {
                    topRow(track)
                    player(track)
                } else if needsPermission {
                    connect
                } else {
                    topRow(nil)
                    idle
                }
            }
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            guard !context.isPreview else { return }
            MusicService.shared.configure(config)
            MusicService.shared.setWantsUpNext(true)
            // 只有已经给过录音权限才启动应用音量（它会按需建 tap），绝不为了
            // 音量条去弹权限。
            if AppVolumeService.recordingGranted { AppVolumeService.shared.start() }
        }
        .onDisappear {
            guard !context.isPreview else { return }
            MusicService.shared.setWantsUpNext(false)
        }
        // 只在延展态读满 25 首，收起态按需读 3 首。
        .onChange(of: page) { _, now in
            guard !context.isPreview else { return }
            MusicService.shared.setUpNextExpanded(now == .list)
        }
    }

    // MARK: 来源

    /// 正在看的来源：卡片和面板共用的显示来源，没有就是服务停着的（可能没开）。
    private var shownSource: MusicSource? {
        if let source = playing?.source { return source }
        if context.isPreview { return sources.first }
        return MusicService.shared.display.source ?? MusicService.shared.current
            ?? sources.first(where: { MusicService.isInstalled($0) })
    }

    private func accent(_ source: MusicSource?) -> Color {
        switch source {
        case .netease: Color(hex: "#FF5A66")
        case .appleMusic: Color(hex: "#FF6A86")
        case .qqmusic: Color(hex: "#45D483")
        case .spotify: Color(hex: "#1ED760")
        case .xiaoyuzhou: Color(hex: "#25B4E1")
        case nil: Color(hex: "#5AA9FF")
        }
    }

    /// 强调色上的深色字（实心按钮用）。
    private func accentInk(_ source: MusicSource?) -> Color {
        switch source {
        case .netease: Color(hex: "#2B0306")
        case .appleMusic: Color(hex: "#33040F")
        case .qqmusic: Color(hex: "#04230F")
        case .spotify: Color(hex: "#04210D")
        case .xiaoyuzhou: Color(hex: "#03202B")
        case nil: Color(hex: "#03152E")
        }
    }

    private func icon(for bundleID: String) -> NSImage? {
        context.isPreview ? nil : AppCatalog.shared.icon(forBundleID: bundleID)
    }

    // MARK: 顶部

    private func topRow(_ track: Playing?) -> some View {
        let source = track?.source ?? (track == nil ? shownSource : nil)
        let name = track.map { $0.isBrowser ? $0.artist : ($0.source?.displayName ?? "") }
            ?? source?.displayName ?? tr("正在播放")
        let image = track?.icon ?? track.flatMap { icon(for: $0.sourceBundleID) }
            ?? source.flatMap { icon(for: $0.bundleID) }
        let bundleID = track?.sourceBundleID ?? source?.bundleID
        let idlePin = pinIdle
        return VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { page = page == .sources ? .player : .sources }
            } label: {
                HStack(spacing: 8) {
                    appIcon(image, size: 20)
                    Text(name)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    if track?.isPlaying == true {
                        PlayingBarsView(playing: true, tint: accent(track?.source), height: 12, visible: true)
                    }
                    Image(systemName: page == .sources ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.panelSecondary)
                }
                .padding(.leading, 6)
                .padding(.trailing, 12)
                .frame(height: 32)
                .background(Capsule().fill(.panelFill))
                .overlay(Capsule().strokeBorder(.panelStroke, lineWidth: 0.6))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tr("切换来源"))
            if let pinned = pinnedSource, idlePin == nil, source == pinned, track?.isBrowser != true {
                Text("已固定")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(Capsule().fill(.panelFill))
                    .padding(.leading, 8)
                    .help(tr("你固定了这个来源，别的播放器不会顶掉它"))
            }
            Spacer(minLength: 8)
            if let bundleID {
                Button {
                    guard !context.isPreview else { return }
                    openApp(bundleID)
                } label: {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(.panelFill))
                        .overlay(Circle().strokeBorder(.panelStroke, lineWidth: 0.6))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(tr("在 App 中打开"))
                .accessibilityLabel(tr("在 App 中打开"))
            }
        }
        if let idlePin {
            // 固定的来源没在播（没开或暂停），显示的是正在播的那个：一行提示加取消固定。
            HStack(spacing: 8) {
                Text(tr("固定的 \(idlePin.displayName) 没在播"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Button(tr("取消固定")) { unpin() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: "#45D483"))
                    .fixedSize()
            }
            .padding(.top, 8)
        }
        }
    }

    private func openApp(_ bundleID: String) {
        if let source = MusicSource(bundleID: bundleID) {
            MusicService.shared.open(source)
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
        }
    }

    @ViewBuilder
    private func appIcon(_ image: NSImage?, size: CGFloat) -> some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(.panelFillStrong)
                .frame(width: size, height: size)
                .overlay(Image(systemName: "music.note").font(.system(size: size * 0.5, weight: .semibold)))
        }
    }

    // MARK: 播放中

    /// 有歌单入口时收紧（封面 128、歌名 18pt、进度一行、控制键 48），把「接下来」3 首
    /// 摆进视口；读不到队列的来源照旧大封面。
    @ViewBuilder
    private func player(_ track: Playing) -> some View {
        if let block = queueBlock(track) {
            VStack(alignment: .leading, spacing: 0) {
                cover(track, side: MusicQueue.coverSide(block))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                titles(track, big: 18)
                    .padding(.top, 14)
                scrubber(track, inline: true)
                    .padding(.top, 12)
                transport(track, play: 48, height: 52, gap: 26, glyph: 20)
                    .padding(.top, 10)
                volume(track, top: 8)
                queueCollapsed(track, block)
                    .padding(.top, 14)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                cover(track, side: MusicQueue.coverFull)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 18)
                titles(track)
                    .padding(.top, 22)
                if track.duration > 0 || !track.isBrowser {
                    scrubber(track)
                        .padding(.top, 18)
                }
                transport(track)
                    .padding(.top, 16)
                volume(track)
            }
        }
    }

    private func cover(_ track: Playing, side: CGFloat) -> some View {
        let glow = track.tint.map { Self.colour($0.glow) } ?? .white
        return Group {
            if let image = track.artwork {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [glow.opacity(0.55), Color(white: 0.16)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay {
                        appIcon(track.icon ?? icon(for: track.sourceBundleID), size: 64)
                            .opacity(0.9)
                    }
            }
        }
        .frame(width: side, height: side)
        .clipShape(.rect(cornerRadius: side > 100 ? 16 : 10, style: .continuous))
        .matchedGeometryEffect(id: "cover", in: coverSpace)
        .overlay(RoundedRectangle(cornerRadius: side > 100 ? 16 : 10, style: .continuous)
            .strokeBorder(.panelStroke, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
        .accessibilityLabel(tr("封面"))
        // 封面主色的光晕，不超过 15%。画在背景里，只往四周溢出、不参与排版：
        // 原来它和封面一起放在 ZStack 里，1.64 倍封面宽（约 335pt）比 320 面板
        // 的内容区（288pt）还宽，把整列内容撑宽，进度条、总时长和底部「外观」
        // 右边都被面板裁掉（见 Core `DetailPanelWidth`）。
        .background {
            Circle()
                .fill(RadialGradient(colors: [glow.opacity(ArtworkTint.glowOpacity), glow.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: side * 0.82))
                .frame(width: side * 1.64, height: side * 1.64)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func titles(_ track: Playing, big: CGFloat = 20) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.system(size: big, weight: .bold))
                Text(subtitle(track))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.panelSecondary)
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            if track.source?.hasFavorite == true, let native = track.native {
                heart(native.favorited ?? false, source: track.source, size: 34)
            }
        }
    }

    private func subtitle(_ track: Playing) -> String {
        [track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func heart(_ on: Bool, source: MusicSource?, size: CGFloat) -> some View {
        Button {
            guard !context.isPreview else { return }
            MusicService.shared.toggleFavorite()
        } label: {
            Image(systemName: on ? "heart.fill" : "heart")
                .font(.system(size: size * 0.47, weight: .semibold))
                .foregroundStyle(on ? accent(source).panelReadable : .panelSecondary)
                .frame(width: size, height: size)
                .background(Circle().fill(.panelFill))
                .overlay(Circle().strokeBorder(.panelStroke, lineWidth: 0.6))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(on ? tr("取消喜欢") : tr("喜欢"))
    }

    // MARK: 进度

    /// `inline`：两端时间和进度条排一行（有歌单入口时、迷你播放条里）。
    @ViewBuilder
    private func scrubber(_ track: Playing, inline: Bool = false) -> some View {
        if inline {
            HStack(spacing: 10) {
                time(MusicTime.clock(scrubbing.map { $0 * track.duration } ?? track.elapsed))
                scrubBar(track)
                time(MusicTime.clock(track.duration))
            }
        } else {
            VStack(spacing: 8) {
                scrubBar(track)
                HStack {
                    time(MusicTime.clock(scrubbing.map { $0 * track.duration } ?? track.elapsed))
                    Spacer()
                    time(MusicTime.clock(track.duration))
                }
            }
        }
    }

    private func scrubBar(_ track: Playing) -> some View {
        let seekable = canSeek(track)
        let ratio = scrubbing ?? track.progress
        return GeometryReader { geo in
                let width = geo.size.width
                let height: CGFloat = seekable ? 5 : 4
                ZStack(alignment: .leading) {
                    Capsule().fill(.panelTrack).frame(height: height)
                    Capsule().fill(.panelPrimary)
                        .frame(width: max(0, width * ratio), height: height)
                        .animation(track.isPlaying && scrubbing == nil
                                   ? .linear(duration: MusicTile.pollInterval) : nil, value: ratio)
                    if seekable {
                        // 圆点 = 能拖；网易云、QQ 只读，没有圆点。
                        Circle().fill(.white)
                            .frame(width: 14, height: 14)
                            .shadow(color: .black.opacity(0.25), radius: 1)
                            .offset(x: min(max(0, width * ratio - 7), width - 14))
                            .animation(track.isPlaying && scrubbing == nil
                                       ? .linear(duration: MusicTile.pollInterval) : nil, value: ratio)
                    }
                }
                .frame(height: 14)
                .contentShape(Rectangle())
                .gesture(seek(track, width: width))
            }
            .frame(height: 14)
    }

    private func seek(_ track: Playing, width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard canSeek(track), width > 0 else { return }
                scrubbing = min(1, max(0, value.location.x / width))
            }
            .onEnded { value in
                guard canSeek(track), width > 0 else { return }
                let ratio = min(1, max(0, value.location.x / width))
                scrubbing = nil
                MusicService.shared.seek(to: ratio * track.duration)
            }
    }

    private func canSeek(_ track: Playing) -> Bool {
        !context.isPreview && !track.isBrowser && track.canSeek && track.duration > 0
    }

    private func time(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .monospacedDigit()
            .rollingValue(text)
            .foregroundStyle(.panelSecondary)
            .lineLimit(1)
            .fixedSize()
    }

    // MARK: 播放控制

    @ViewBuilder
    private func transport(_ track: Playing, play: CGFloat = 62, height: CGFloat = 64, gap: CGFloat = 30,
                           glyph: CGFloat = 24) -> some View {
        if track.isBrowser {
            // 浏览器标签页只能播放 / 暂停。
            playButton(track.isPlaying, size: play) { BrowserMedia.shared.playPause() }
                .frame(maxWidth: .infinity)
        } else {
            let native = track.native
            let extras = track.source?.hasShuffleAndRepeat == true
            ZStack {
                HStack(spacing: gap) {
                    glyphButton("backward.end.fill", glyph, label: tr("上一首")) { MusicService.shared.previous() }
                    playButton(track.isPlaying, size: play) { MusicService.shared.playPause() }
                    glyphButton("forward.end.fill", glyph, label: tr("下一首")) { MusicService.shared.next() }
                }
                if extras {
                    HStack {
                        toggleGlyph("shuffle", on: native?.shuffle == true, source: track.source,
                                    label: tr("随机播放")) {
                            MusicService.shared.setShuffle(!(native?.shuffle ?? false))
                        }
                        Spacer()
                        let mode = native?.repeatMode ?? .off
                        toggleGlyph(mode == .one ? "repeat.1" : "repeat", on: mode != .off,
                                    source: track.source, label: mode.label) {
                            MusicService.shared.cycleRepeat()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            controlHint(track)
        }
    }

    /// 白色实心圆，深色字形。
    private func playButton(_ playing: Bool, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button {
            guard !context.isPreview else { return }
            action()
        } label: {
            Image(systemName: playing ? "pause.fill" : "play.fill")
                .font(.system(size: size * 0.36, weight: .bold))
                .offset(x: playing ? 0 : size * 0.03)
                .playPauseMorph(playing ? "pause.fill" : "play.fill")
                .foregroundStyle(.panelOnPrimary)
                .frame(width: size, height: size)
                .background(Circle().fill(.panelPrimary))
                .contentShape(Circle())
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(playing ? tr("暂停") : tr("播放"))
    }

    private func glyphButton(_ symbol: String, _ size: CGFloat, hit: CGFloat = 40, label: String,
                             action: @escaping () -> Void) -> some View {
        Button {
            guard !context.isPreview else { return }
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.panelPrimary)
                .frame(width: hit, height: 40)
                .contentShape(Circle())
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(label)
    }

    private func toggleGlyph(_ symbol: String, on: Bool, source: MusicSource?, label: String,
                             action: @escaping () -> Void) -> some View {
        Button {
            guard !context.isPreview else { return }
            action()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(on ? accent(source).panelReadable : .panelSecondary)
                Circle().fill(on ? accent(source) : .clear).frame(width: 4, height: 4)
            }
            .frame(width: 32, height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScale())
        .help(label)
        .accessibilityLabel(label)
        .accessibilityValue(on ? tr("开") : tr("关"))
    }

    // MARK: 音量

    @ViewBuilder
    private func volume(_ track: Playing, top: CGFloat = 14) -> some View {
        if let source = track.source, !track.isBrowser {
            switch MusicVolumeRoute.route(for: source, recordingGranted: AppVolumeService.recordingGranted) {
            case .player:
                if let level = track.native?.volume {
                    volumeRow(value: dragVolume ?? level / 100, top: top) { value, done in
                        dragVolume = done ? nil : value
                        MusicService.shared.setVolume(value * 100)
                    }
                }
            case .appVolume:
                let setting = AppVolumeService.shared.setting(for: source.bundleID)
                volumeRow(value: dragVolume ?? min(100, setting.percent) / 100, top: top) { value, done in
                    dragVolume = done ? nil : value
                    AppVolumeService.shared.setPercent(value * 100, for: source.bundleID)
                }
            case .none:
                EmptyView()
            }
        }
    }

    private func volumeRow(value: Double, top: CGFloat, change: @escaping (Double, Bool) -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(.panelTrack).frame(height: 5)
                    Capsule().fill(.panelPrimary).frame(width: max(0, width * value), height: 5)
                    Circle().fill(.white)
                        .frame(width: 14, height: 14)
                        .shadow(color: .black.opacity(0.25), radius: 1)
                        .offset(x: min(max(0, width * value - 7), width - 14))
                }
                .frame(height: 14)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard !context.isPreview, width > 0 else { return }
                        change(min(1, max(0, drag.location.x / width)), false)
                    }
                    .onEnded { drag in
                        guard !context.isPreview, width > 0 else { return }
                        change(min(1, max(0, drag.location.x / width)), true)
                    })
            }
            .frame(height: 14)
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
        }
        .padding(.top, top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("音量"))
        .accessibilityValue(Text(verbatim: "\(Int((value * 100).rounded()))%"))
    }

    // MARK: 歌单入口（方案 A，Core `MusicQueue`）

    /// 控制键下这块怎么画；nil 是整块不出现（网易云、QQ、小宇宙、浏览器），封面回到 204。
    private func queueBlock(_ track: Playing) -> MusicQueue.Block? {
        guard !context.isPreview, let native = track.native else { return nil }
        let service = MusicService.shared
        let list = track.source == .appleMusic ? service.upNext : nil
        return MusicQueue.block(.init(
            source: track.source, isNative: true, shuffle: native.shuffle ?? false,
            repeatMode: native.repeatMode ?? .off, playlist: list?.playlist,
            isLibrary: list?.isLibrary ?? false, loaded: list?.items.count, remaining: list?.remaining,
            loading: service.upNextReading, unreadable: service.upNextUnreadable,
            recentCount: service.recent.listed(excluding: native.trackID).count))
    }

    /// 延展态：有入口时才进得去，来源换成没有队列的就退回播放页。
    private var expandedBlock: MusicQueue.Block? {
        guard page == .list, let track = playing else { return nil }
        return queueBlock(track)
    }

    /// 展开 / 收起：封面在 128 和 48 之间飞（`coverSpace`），减少动态效果时直接切换。
    private func setExpanded(_ on: Bool) {
        let change = { page = on ? Page.list : .player }
        if reduceMotion { change() } else { withAnimation(.snappy(duration: 0.3), change) }
    }

    private func queueTitle(_ title: MusicQueue.Title, expanded: Bool) -> String {
        switch title {
        case .upNext: tr("接下来")
        case .playlist(let name): tr("接下来 · \(name)")
        case .library: tr("接下来 · 资料库")
        case .recent: expanded ? tr("刚才听过 · 只存在本机") : tr("刚才听过")
        }
    }

    /// 标题一行：左边标题，右边「全部 N 首」或「收起」胶囊（点击区至少 28pt）。
    private func queueHeader(_ title: String, pill: String?, symbol: String,
                             action: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.panelPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            if let pill {
                Button(action: action) {
                    HStack(spacing: 4) {
                        Text(pill).lineLimit(1)
                        Image(systemName: symbol).font(.system(size: 11, weight: .bold))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                    .padding(.horizontal, 12)
                    .frame(height: MusicQueue.minHitHeight)
                    .background(Capsule().fill(.panelFillStrong))
                    .overlay(Capsule().strokeBorder(.panelStroke, lineWidth: 0.6))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .fixedSize()
            }
        }
        .frame(height: MusicQueue.minHitHeight)
    }

    /// 收起态：标题行加 3 首（或随机、最后一首、读取中、还没听过）。
    @ViewBuilder
    private func queueCollapsed(_ track: Playing, _ block: MusicQueue.Block) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            queueHeader(queueTitle(block.title, expanded: false),
                        pill: block.allCount.map { tr("全部 \($0) 首") }, symbol: "chevron.right") {
                setExpanded(true)
            }
            queueContent(track, block, expanded: false)
        }
    }

    @ViewBuilder
    private func queueContent(_ track: Playing, _ block: MusicQueue.Block, expanded: Bool) -> some View {
        switch block.content {
        case .rows:
            if block.kind == .recent {
                let all = recentEntries(track)
                queueRows { recentRows(Array(all.prefix(expanded ? all.count : MusicQueue.collapsedRows)),
                                       compact: !expanded) }
            } else {
                let items = MusicService.shared.upNext?.items ?? []
                queueRows {
                    upNextRows(track, Array(items.prefix(expanded ? items.count : MusicQueue.collapsedRows)),
                               compact: !expanded)
                    if expanded {
                        let list = MusicService.shared.upNext
                        ForEach(0..<MusicQueue.placeholders(loaded: items.count, remaining: list?.remaining,
                                                            loading: MusicService.shared.upNextReading),
                                id: \.self) { _ in placeholderRow(compact: false) }
                    }
                }
            }
        case .loading(let count):
            queueRows {
                ForEach(0..<count, id: \.self) { _ in placeholderRow(compact: !expanded) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(tr("正在读取歌单"))
        case .shuffle:
            statusCard(symbol: "shuffle", title: tr("随机播放中"),
                       detail: tr("顺序由 \(track.source?.displayName ?? "") 决定"), action: tr("关掉随机")) {
                MusicService.shared.setShuffle(false)
            }
        case .end(let canLoop):
            statusCard(symbol: "repeat", title: tr("最后一首"), detail: tr("后面没有歌了"),
                       action: canLoop ? tr("从头循环") : nil) {
                MusicService.shared.setRepeat(.all)
            }
        case .empty:
            note(tr("放过的歌会记在这里，点一下重放"))
        }
    }

    private func recentEntries(_ track: Playing) -> [MusicRecent.Entry] {
        MusicService.shared.recent.listed(excluding: track.native?.trackID)
    }

    private func upNextRows(_ track: Playing, _ items: [MusicService.UpNext.Item], compact: Bool) -> some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            if index > 0 { rowDivider(compact: compact) }
            queueRow(id: "up-\(item.id)", title: item.title, artist: item.artist,
                     trailing: item.duration > 0 ? MusicTime.clock(item.duration) : nil,
                     artwork: nil, glow: track.tint.map { Self.colour($0.glow) },
                     compact: compact, replay: false, label: tr("播放 \(item.title)")) {
                MusicService.shared.play(item)
            }
        }
    }

    private func recentRows(_ entries: [MusicRecent.Entry], compact: Bool) -> some View {
        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
            if index > 0 { rowDivider(compact: compact) }
            queueRow(id: "re-\(entry.uri)", title: entry.title, artist: entry.artist,
                     trailing: agoText(entry), artwork: entry.artworkURL.flatMap { URL(string: $0) },
                     glow: nil, compact: compact, replay: true, label: tr("重放 \(entry.title)")) {
                MusicService.shared.replay(entry)
            }
        }
    }

    /// 行尾「几分钟前」；升级前记的没有时间，写时长。
    private func agoText(_ entry: MusicRecent.Entry) -> String? {
        switch MusicQueue.ago(entry.playedAt, now: Date()) {
        case .justNow: tr("刚刚")
        case .minutes(let n): tr("\(n) 分钟前")
        case .hours(let n): tr("\(n) 小时前")
        case .days(let n): tr("\(n) 天前")
        case nil: entry.duration > 0 ? MusicTime.clock(entry.duration) : nil
        }
    }

    private func rowDivider(compact: Bool) -> some View {
        Rectangle()
            .fill(.panelSeparator)
            .frame(height: 0.5)
            .padding(.leading, compact ? 48 : 54)
            .padding(.trailing, 10)
    }

    /// 一首：整行可点即播。收起态 38pt，歌名和歌手同一行；延展态 44pt 两行。悬停时
    /// 行尾换成播放（Spotify 是重放）圆钮。
    private func queueRow(id: String, title: String, artist: String, trailing: String?,
                          artwork: URL?, glow: Color?, compact: Bool, replay: Bool, label: String,
                          action: @escaping () -> Void) -> some View {
        let hover = hovered == id
        let side: CGFloat = compact ? 32 : 36
        return Button {
            guard !context.isPreview else { return }
            action()
        } label: {
            HStack(spacing: 10) {
                Group {
                    if let artwork {
                        AsyncImage(url: artwork) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            thumb(nil, glow: glow, size: side, corner: 7)
                        }
                        .frame(width: side, height: side)
                        .clipShape(.rect(cornerRadius: 7, style: .continuous))
                    } else {
                        thumb(nil, glow: glow, size: side, corner: 7)
                    }
                }
                Group {
                    if compact {
                        HStack(spacing: 8) {
                            Text(title).font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.panelPrimary)
                                .layoutPriority(1)
                            Text(artist).font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.panelSecondary)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.panelPrimary)
                            Text(artist).font(.system(size: 13, weight: .medium)).foregroundStyle(.panelSecondary)
                        }
                    }
                }
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                if hover {
                    Image(systemName: replay ? "arrow.counterclockwise" : "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.panelOnPrimary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(.panelPrimary))
                } else if let trailing {
                    Text(trailing)
                        .font(.system(size: 13, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.panelSecondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.leading, 6)
            .padding(.trailing, 8)
            .frame(height: compact ? MusicQueue.collapsedRowHeight : MusicQueue.expandedRowHeight)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(hover ? Color.panelFill : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in hovered = inside ? id : (hovered == id ? nil : hovered) }
        .help(replay ? tr("重放") : tr("从这首开始放"))
        .accessibilityLabel(label)
    }

    /// 读取中的灰色占位行，和真行一样高，读到后原位换掉。
    private func placeholderRow(compact: Bool) -> some View {
        let side: CGFloat = compact ? 32 : 36
        return HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.panelTrack)
                .frame(width: side, height: side)
            VStack(alignment: .leading, spacing: 6) {
                Capsule().fill(.panelTrack).frame(width: 110, height: 9)
                if !compact { Capsule().fill(.panelTrack).frame(width: 70, height: 8) }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 6)
        .frame(height: compact ? MusicQueue.collapsedRowHeight : MusicQueue.expandedRowHeight)
        .accessibilityHidden(true)
    }

    private func queueRows<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .padding(MusicQueue.rowsInset)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.panelFill))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.panelStroke, lineWidth: 0.6))
    }

    /// 随机播放中 / 最后一首：一行图标加标题，右边按钮，下面一行说明。
    private func statusCard(symbol: String, title: String, detail: String, action: String?,
                            perform: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Label {
                    Text(title).font(.system(size: 14, weight: .bold))
                } icon: {
                    Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.panelPrimary)
                Text(detail)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let action {
                Button {
                    guard !context.isPreview else { return }
                    perform()
                } label: {
                    Text(action)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.panelPrimary)
                        .padding(.horizontal, 12)
                        .frame(height: MusicQueue.minHitHeight)
                        .background(Capsule().fill(.panelFillStrong))
                        .overlay(Capsule().strokeBorder(.panelStroke, lineWidth: 0.6))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .fixedSize()
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.panelFill))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.panelStroke, lineWidth: 0.6))
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.panelSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.panelFill))
    }

    // MARK: 延展态

    /// 迷你播放条吸顶，下面标题行和「收起」，列表往下占满，面板不突破 560，列表区内滚。
    private func expandedPage(_ track: Playing, _ block: MusicQueue.Block) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            miniBar(track)
                .padding(.top, 12)
            queueHeader(queueTitle(block.title, expanded: true), pill: tr("收起"), symbol: "chevron.up") {
                setExpanded(false)
            }
            .padding(.top, 12)
            expandedList(track, block)
                .padding(.top, 6)
                .transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .bottom)))
        }
    }

    /// 迷你播放条：48pt 封面、歌名歌手、上一首 / 播放 / 下一首，下面一条细进度。
    /// 点空白处回到大封面。
    private func miniBar(_ track: Playing) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                thumb(track.artwork, glow: track.tint.map { Self.colour($0.glow) },
                      size: MusicQueue.coverMini, corner: 9)
                    .matchedGeometryEffect(id: "cover", in: coverSpace)
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title).font(.system(size: 15, weight: .bold))
                    Text(track.artist)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.panelSecondary)
                }
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 2) {
                    glyphButton("backward.end.fill", 15, hit: 32, label: tr("上一首")) { MusicService.shared.previous() }
                    playButton(track.isPlaying, size: 34) { MusicService.shared.playPause() }
                    glyphButton("forward.end.fill", 15, hit: 32, label: tr("下一首")) { MusicService.shared.next() }
                }
            }
            if track.duration > 0 {
                scrubber(track, inline: true)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.panelFill))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.panelStroke, lineWidth: 0.6))
        .contentShape(Rectangle())
        .onTapGesture { setExpanded(false) }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(tr("回到正在播放"))
    }

    /// 延展态列表：行数乘行高加底下说明，不超过 346，再多在区内滚。
    @ViewBuilder
    private func expandedList(_ track: Playing, _ block: MusicQueue.Block) -> some View {
        switch (block.kind, block.content) {
        case (.upNext, .rows):
            let service = MusicService.shared
            let items = service.upNext?.items ?? []
            let remaining = service.upNext?.remaining
            let reading = service.upNextReading
            let placeholders = MusicQueue.placeholders(loaded: items.count, remaining: remaining, loading: reading)
            let hidden = MusicQueue.truncated(loaded: items.count, remaining: remaining, loading: reading)
            let footer: CGFloat = hidden > 0 ? 44 : 0
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    queueContent(track, block, expanded: true)
                    if hidden > 0 {
                        Button {
                            guard !context.isPreview else { return }
                            MusicService.shared.open(.appleMusic)
                        } label: {
                            HStack(spacing: 6) {
                                Text(tr("还有 \(hidden) 首，在 Apple 音乐里看"))
                                    .lineLimit(1)
                                Image(systemName: "arrow.up.forward.square")
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.panelSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: MusicQueue.listHeight(rows: items.count + placeholders, footer: footer))
        case (.recent, _):
            let entries = recentEntries(track)
            // Spotify 说明卡 10 + 72，有记录时再加一行「清空记录」32。
            let footer: CGFloat = 82 + (entries.isEmpty ? 0 : 32)
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    queueContent(track, block, expanded: true)
                    if !entries.isEmpty {
                        Button(tr("清空记录")) {
                            guard !context.isPreview else { return }
                            MusicService.shared.clearRecent()
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.panelSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                    }
                    spotifyQueueCard
                        .padding(.top, 10)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: MusicQueue.listHeight(rows: entries.count, footer: footer)
                   + (entries.isEmpty ? 56 : 0))
        default:
            // 随机、最后一首、读取中：和收起态同一张卡片，不用滚。
            queueContent(track, block, expanded: true)
        }
    }

    /// Spotify 不开放读取接下来的队列：一张说明卡，「去看」打开 Spotify。
    private var spotifyQueueCard: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("接下来的队列").font(.system(size: 14, weight: .bold))
                Text("Spotify 不开放给小工具读取")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                guard !context.isPreview else { return }
                MusicService.shared.open(.spotify)
            } label: {
                Text(tr("去看"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                    .padding(.horizontal, 14)
                    .frame(height: MusicQueue.minHitHeight)
                    .background(Capsule().fill(.panelFillStrong))
                    .overlay(Capsule().strokeBorder(.panelStroke, lineWidth: 0.6))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .accessibilityLabel(tr("在 Spotify 中查看"))
        }
        .padding(.horizontal, 14)
        .frame(height: 72)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.panelFill))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.panelStroke, lineWidth: 0.6))
    }

    // MARK: 来源页共用

    /// 一行迷你正在播放；点空白处回到大封面。
    private func miniNow(_ track: Playing) -> some View {
        HStack(spacing: 12) {
            thumb(track.artwork, glow: track.tint.map { Self.colour($0.glow) }, size: 48, corner: 9)
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title).font(.system(size: 15, weight: .bold))
                Text(track.isBrowser ? track.artist : subtitle(track))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            if track.source?.hasFavorite == true, let native = track.native {
                heart(native.favorited ?? false, source: track.source, size: 30)
            }
            playButton(track.isPlaying, size: 34) {
                if track.isBrowser { BrowserMedia.shared.playPause() } else { MusicService.shared.playPause() }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.panelFill))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.panelStroke, lineWidth: 0.6))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.snappy(duration: 0.2)) { page = .player } }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(tr("回到正在播放"))
    }

    private func section(_ title: String, right: String? = nil, rightTint: Color = .panelSecondary,
                         action: (() -> Void)? = nil) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelSecondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if let right {
                if let action {
                    Button(right) { guard !context.isPreview else { return }; action() }
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(rightTint)
                } else {
                    Text(right)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.panelSecondary)
                }
            }
        }
        .padding(.top, 20)
        .padding(.bottom, 10)
    }

    private func thumb(_ image: NSImage?, glow: Color?, size: CGFloat, corner: CGFloat) -> some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [(glow ?? .white).opacity(0.45), Color(white: 0.18)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(Image(systemName: "music.note")
                        .font(.system(size: size * 0.38, weight: .semibold))
                        .foregroundStyle(.panelSecondary))
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: corner, style: .continuous))
    }

    // MARK: 次页：来源列表

    private var sourcesPage: some View {
        let service = MusicService.shared
        let players = context.isPreview ? [] : service.players
        let browser = browserPlaying
        let shown = playing
        return VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                if players.isEmpty && browser == nil {
                    Text("没有开着的播放器")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.panelSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                }
                ForEach(Array(players.enumerated()), id: \.element.source) { index, player in
                    if index > 0 { divider }
                    sourceRow(player, selected: shown?.source == player.source && shown?.isBrowser == false)
                }
                if let browser {
                    if !players.isEmpty { divider }
                    browserRow(browser, selected: shown?.isBrowser == true)
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.panelFill))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.panelStroke, lineWidth: 0.6))
            .padding(.top, 12)

            switchCard
                .padding(.top, 14)

            if let shown {
                miniNow(shown)
                    .padding(.top, 16)
            }
        }
    }

    private var divider: some View {
        Rectangle().fill(.panelSeparator).frame(height: 0.6).padding(.leading, 56).padding(.trailing, 10)
    }

    private func sourceRow(_ player: MusicService.Player, selected: Bool) -> some View {
        let source = player.source
        let track = player.track
        let detail: String = if let track {
            track.isPlaying
                ? [track.title, track.artist].filter { !$0.isEmpty }.joined(separator: " · ")
                : tr("已暂停 · \(track.title)")
        } else {
            tr("开着，读不到曲目")
        }
        return HStack(spacing: 12) {
            appIcon(icon(for: source.bundleID), size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(source.displayName).font(.system(size: 15, weight: .bold))
                Text(detail).font(.system(size: 13, weight: .medium)).foregroundStyle(.panelSecondary)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            if track?.isPlaying == true {
                PlayingBarsView(playing: true, tint: accent(source), height: 14, visible: true)
                    .padding(.trailing, 6)
            } else if track != nil, MusicService.shared.canControl(source) {
                smallPlay { MusicService.shared.playPause(source) }
            } else {
                // 网易云、QQ 不是系统正在播放的那个时控制不了，只能打开它。
                Button(tr("打开")) { guard !context.isPreview else { return }; MusicService.shared.open(source) }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 28)
                    .background(Capsule().fill(.panelFill))
                    .overlay(Capsule().strokeBorder(.panelStroke, lineWidth: 0.6))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 58)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(selected ? accent(source).opacity(0.14) : .clear))
        .contentShape(Rectangle())
        .onTapGesture { choose(source) }
        .accessibilityAddTraits(.isButton)
    }

    private func browserRow(_ track: Playing, selected: Bool) -> some View {
        HStack(spacing: 12) {
            appIcon(track.icon ?? icon(for: track.sourceBundleID), size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("\(track.artist) 标签页")).font(.system(size: 15, weight: .bold))
                Text(tr("视频 · 只能播放暂停")).font(.system(size: 13, weight: .medium)).foregroundStyle(.panelSecondary)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            smallPlay(playing: track.isPlaying) { BrowserMedia.shared.playPause() }
        }
        .padding(.horizontal, 10)
        .frame(height: 58)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(selected ? accent(nil).opacity(0.14) : .clear))
    }

    private func smallPlay(playing: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            guard !context.isPreview else { return }
            action()
        } label: {
            Image(systemName: playing ? "pause.fill" : "play.fill")
                .font(.system(size: 11, weight: .bold))
                .frame(width: 28, height: 28)
                .background(Circle().fill(.panelFill))
                .contentShape(Circle())
        }
        .buttonStyle(PressScale())
        .accessibilityLabel(playing ? tr("暂停") : tr("播放"))
    }

    /// 点一个来源：显示它；自动切换关着时它就是固定的来源。
    private func choose(_ source: MusicSource) {
        guard !context.isPreview else { return }
        if !autoSwitch {
            WidgetWriter.write(current) { $0.set(MusicSourceSwitch.pinnedKey, .string(source.rawValue)) }
            var updated = config
            updated.set(MusicSourceSwitch.pinnedKey, .string(source.rawValue))
            MusicService.shared.configure(updated)
        }
        MusicService.shared.select(source)
        withAnimation(.snappy(duration: 0.2)) { page = .player }
    }

    private var switchCard: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("谁开始播放就切到谁").font(.system(size: 14, weight: .semibold))
                Text("关掉后停在你选的来源")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle("", isOn: Binding(get: { autoSwitch }, set: { setAutoSwitch($0) }))
                .toggleStyle(.switch)
                .tint(accent(shownSource))
                .labelsHidden()
                .accessibilityLabel(tr("谁开始播放就切到谁"))
        }
        .padding(.horizontal, 14)
        .frame(height: 56)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.panelFill))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.panelStroke, lineWidth: 0.6))
    }

    /// 关掉时把现在显示的来源记成固定来源，之后谁开始播放都不换。
    private func setAutoSwitch(_ on: Bool) {
        guard !context.isPreview else { return }
        let pin = on ? nil : (playing?.source ?? MusicService.shared.current)
        WidgetWriter.write(current) { config in
            config.set(MusicSourceSwitch.autoKey, .bool(on))
            if let pin { config.set(MusicSourceSwitch.pinnedKey, .string(pin.rawValue)) }
        }
        var updated = config
        updated.set(MusicSourceSwitch.autoKey, .bool(on))
        if let pin { updated.set(MusicSourceSwitch.pinnedKey, .string(pin.rawValue)) }
        MusicService.shared.configure(updated)
    }

    /// 取消固定：回到「谁开始播放就切到谁」（autoSwitch 开、清掉 pinned）。
    private func unpin() {
        guard !context.isPreview else { return }
        WidgetWriter.write(current) { MusicPin.unpin(&$0) }
        var updated = config
        MusicPin.unpin(&updated)
        MusicService.shared.configure(updated)
    }

    // MARK: 没在播放

    private var idle: some View {
        let target = shownSource
        let pinned = pinnedSource != nil
        let players = context.isPreview ? [] : MusicService.shared.players
        // 固定的 App 没开：大标题「X 没开」。
        let closed = context.isPreview ? nil
            : MusicDisplay.pinnedClosed(pinned: pinnedSource, shown: MusicService.shared.display, players: corePlayers)
        // 都没在播：列别的有曲目的（「其他开着的」）。
        let otherSources = MusicPin.others(players: corePlayers, shown: target)
        let others = players.filter { otherSources.contains($0.source) }
        let setup = browserSetupHint
        return VStack(spacing: 0) {
            if let image = PandaArt.image("pet-panda-rest") {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 128)
                    .padding(.top, 14)
                    .accessibilityHidden(true)
            }
            Text(idleTitle(setup: setup, closed: closed))
                .font(.system(size: 19, weight: .bold))
                .multilineTextAlignment(.center)
                .padding(.top, 12)
            Text(setup ?? (closed != nil ? tr("打开它就能在这里控制") : idleLine(target)))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.panelSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            if let target, MusicService.isInstalled(target) {
                Button {
                    guard !context.isPreview else { return }
                    MusicService.shared.open(target)
                } label: {
                    Text(tr("打开 \(target.displayName)"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(accentInk(target))
                        .padding(.horizontal, 26)
                        .frame(height: 40)
                        .background(Capsule().fill(accent(target)))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressScale())
                .padding(.top, 18)
            }
            if pinned {
                // 固定着：「其他开着的」右边「取消固定」回到谁开始播放就切到谁。
                section(tr("其他开着的"), right: tr("取消固定"), rightTint: Color(hex: "#45D483")) { unpin() }
                if others.isEmpty {
                    note(tr("别的播放器也没在播"))
                } else {
                    VStack(spacing: 8) {
                        ForEach(others, id: \.source) { player in
                            otherRow(player)
                        }
                    }
                }
            } else if !others.isEmpty {
                section(tr("其他开着的"))
                VStack(spacing: 8) {
                    ForEach(others, id: \.source) { player in
                        otherRow(player)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func idleTitle(setup: String?, closed: MusicSource?) -> String {
        if setup != nil { return tr("有标签页正在播放码头无法读取的媒体") }
        if let closed { return tr("\(closed.displayName)没开") }
        return tr("没在播放")
    }

    private func idleLine(_ target: MusicSource?) -> String {
        if let target { return tr("在 \(target.displayName) 里放首歌，这里就会出现") }
        let names = sources.map(\.displayName)
        let list = names.isEmpty ? tr("无来源") : names.joined(separator: tr("、"))
        return tr("码头可读取\(list)，以及可脚本控制的浏览器标签页中的视频。")
    }

    private func otherRow(_ player: MusicService.Player) -> some View {
        let track = player.track
        return HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                thumb(track?.artwork, glow: nil, size: 42, corner: 8)
                appIcon(icon(for: player.source.bundleID), size: 18)
                    .offset(x: 4, y: 4)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(track?.title ?? player.source.displayName).font(.system(size: 15, weight: .bold))
                Text(track?.isPlaying == true ? tr("\(player.source.displayName) · 播放中")
                                              : tr("\(player.source.displayName) · 已暂停"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 点播放：只把显示切到它并播放，不改固定。
            playButton(false, size: 30) { playOther(player.source) }
        }
        .padding(10)
        .contentShape(Rectangle())
        .onTapGesture { playOther(player.source) }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.panelFill))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.panelStroke, lineWidth: 0.6))
    }

    /// 「其他开着的」里点一行：卡片和面板都切到它并播放，固定不动。
    private func playOther(_ source: MusicSource) {
        guard !context.isPreview else { return }
        MusicService.shared.showAndPlay(source)
        withAnimation(.snappy(duration: 0.2)) { page = .player }
    }

    // MARK: 权限

    /// The only thing that ever raises the automation consent dialog, and it
    /// runs solely because the user clicked it.
    private var connect: some View {
        VStack(spacing: 10) {
            Text("码头需要你允许它读取音乐 App")
                .font(.system(size: 14, weight: .semibold))
                .multilineTextAlignment(.center)
            Button {
                guard !context.isPreview else { return }
                MusicService.shared.requestAutomationPermission()
                if browsersEnabled { BrowserMedia.shared.requestPermission() }
            } label: {
                Text("连接")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.panelOnPrimary)
                    .padding(.horizontal, 26)
                    .frame(height: 36)
                    .background(Capsule().fill(.panelPrimary))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressScale())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    /// The menu item the user has to switch on, or nil when nothing is asking.
    private var browserSetupHint: String? {
        guard !context.isPreview, browsersEnabled, BrowserMedia.shared.needsSetup else { return nil }
        let hint = BrowserMedia.shared.setupHint
        return hint.isEmpty ? nil : hint
    }

    private static func colour(_ rgb: (red: Double, green: Double, blue: Double)) -> Color {
        Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }
}

extension MusicDetail {
    /// 网易云、QQ 音乐、小宇宙的按钮退到菜单项或媒体键才能用、却没有辅助功能权限时，
    /// 按钮下面一行说明和「去授权」（和应用切换器窗口列表同一个做法）。
    @ViewBuilder
    fileprivate func controlHint(_ track: Playing) -> some View {
        if !context.isPreview, let source = track.source, source.readsNowPlaying,
           MusicService.shared.controlNeedsAccessibility(source) {
            HStack(spacing: 8) {
                Text(tr("按钮控制需要辅助功能权限"))
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button {
                    AppWindows.requestAccess()
                } label: {
                    Text(tr("去授权"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.panelOnPrimary)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(Capsule().fill(.panelPrimary))
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 30)
        }
    }
}

/// 按下时缩一点，松开弹回；面板里的圆钮都用它。
private struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.snappy(duration: 0.14), value: configuration.isPressed)
    }
}
