import AppKit
import SwiftUI

/// 播客的面板（2.0，沉浸式播放器）。从上到下：
/// - 顶栏：耳机图标、「播客」和订阅数，右边刷新和「…」（订阅管理、添加订阅）；
/// - 订阅多个节目时一排切换胶囊（小封面加短名，选中描边），右边下拉列出全部节目；
/// - 当前播放卡：左边封面（完整显示，不裁切、不叠东西），右边状态标签、单集名、
///   「主播 · 节目」、已收听约多少；进度条、已播和剩余、后退 15 秒、播放、前进 30 秒
///   （按钮下有说明），底部「章节 | 在小宇宙打开」；
/// - 「最近单集」：筛选全部 / 未听 / 收听中，默认两条，「查看全部」展开。
///
/// 所有强调色（选中描边、标签、进度条、播放键、「查看全部」、单集图标、背景氛围）都从当前
/// 封面的主色算出来（`PodcastPalette`，按浅色 / 深色校正对比度），灰白或没有封面时用中性色。
/// 面板高度交给详情面板的通用容器（限高、滚动、外观栏钉底），这里不设固定高度、不套滚动。
/// 小熊猫只在没有订阅或没有可播单集时当空状态，听完一整集时短暂表态一次。
struct PodcastDetail: View {
    /// 颜色面板里选的颜色只用在通知开关上；播放器的强调色跟封面走。
    @Environment(\.panelTint) private var panelTint
    @Environment(\.colorScheme) private var scheme
    @Environment(\.panelForcedDark) private var forcedDark
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var instance: WidgetInstance
    var context: WidgetContext

    private var service: PodcastService { PodcastService.shared }
    private var player: PodcastPlayer { PodcastPlayer.shared }

    @FocusState private var addingFocused: Bool
    @State private var link = ""
    @State private var adding = false
    @State private var showAdd = false
    @State private var message: String?
    @State private var messageIsError = false
    /// The progress bar's value while dragging, so the player seeks once at the end.
    @State private var scrubbing: Double?
    /// 单集筛选：全部 / 未听 / 收听中。
    @State private var filter: PodcastEpisodeFilter = .all
    /// 「查看全部」展开了。
    @State private var expanded = false
    /// 播放卡里展开了章节。
    @State private var chaptersShown = false

    /// 播放卡左边封面的边长。
    private static let heroCover: CGFloat = 96
    /// 切换胶囊里封面的边长。
    private static let chipCover: CGFloat = 28

    private var shows: [PodcastShow] {
        context.isPreview ? [PodcastTile.sample] : service.library.shows
    }

    private var show: PodcastShow? {
        context.isPreview ? PodcastTile.sample : PodcastRemote.show(for: instance)
    }

    private var notify: Bool { instance.config.bool("notify", default: true) }

    /// 封面的主色；没有封面或灰白封面时 nil。
    private var coverColor: ColorCode? {
        guard !context.isPreview, let url = show?.imageURL else { return nil }
        return service.coverColor[url]
    }

    private var dark: Bool { forcedDark || scheme == .dark }

    /// 这一刻的整套强调色，换节目、换浅色深色都会重算。
    private var palette: PodcastPalette { PodcastPalette.make(coverColor, dark: dark) }
    private var accent: Color { Color(code: palette.accent) }

    var body: some View {
        DetailCard {
            PodcastPlayerBackdrop(color: coverColor)
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                topBar
                if let issue = service.loadIssue, !context.isPreview { loadIssueCard(issue) }
                if shows.isEmpty {
                    addSection
                    if service.recovering {
                        loadingRow(tr("正在重新获取之前的订阅…"))
                    } else {
                        pandaEmpty(.idle, title: tr("添加订阅"), message: tr("在上面粘贴小宇宙节目或单集的链接")) {
                            WidgetDetailWindow.shared.focusField { addingFocused = true }
                        }
                    }
                } else {
                    if showAdd { addSection }
                    if shows.count > 1 { switcher }
                    if let show {
                        playerCard(show)
                        if let problem = service.problems[show.id], !context.isPreview {
                            problemCard(problem, show: show)
                        }
                        episodeSection(show)
                    }
                }
                footer
            }
        }
        .onChange(of: show?.id) { _, _ in
            expanded = false
            filter = .all
            chaptersShown = false
        }
    }

    // MARK: 顶栏

    private var topBar: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(accent.opacity(0.16))
                .frame(width: 38, height: 38)
                .overlay {
                    Image(systemName: "headphones")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(accent)
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("播客")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                Text(shows.isEmpty ? tr("粘贴小宇宙节目或单集链接来订阅") : tr("\(shows.count) 个订阅"))
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(1)
            }
            .layoutPriority(1)
            Spacer(minLength: 4)
            if let show, !shows.isEmpty {
                if service.loading.contains(show.id), !context.isPreview {
                    ProgressView().controlSize(.small)
                        .frame(width: 32, height: 32)
                } else {
                    circleButton("arrow.clockwise", label: tr("刷新单集")) {
                        Task { await service.refresh(show.id) }
                    }
                }
            }
            moreMenu
        }
    }

    private func circleButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            guard !context.isPreview else { return }
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.panelPrimary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(.panelFill))
                .overlay(Circle().strokeBorder(.panelStroke, lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    /// 「…」：当前节目的订阅管理，加上「添加订阅…」。
    private var moreMenu: some View {
        Menu {
            if let show, !shows.isEmpty {
                manageItems(show)
                Divider()
            }
            Button(tr("添加订阅…")) {
                showAdd = true
                WidgetDetailWindow.shared.focusField { addingFocused = true }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.panelPrimary)
                .frame(width: 32, height: 32)
                .background(Circle().fill(.panelFill))
                .overlay(Circle().strokeBorder(.panelStroke, lineWidth: 0.5))
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(context.isPreview)
        .help(tr("管理订阅"))
        .accessibilityLabel(tr("管理订阅"))
    }

    /// 订阅管理：「…」菜单和切换胶囊的右键菜单共用。
    @ViewBuilder
    private func manageItems(_ item: PodcastShow) -> some View {
        Button("刷新") { Task { await service.refresh(item.id) } }
        Button("全部标为已听") { service.markHeard(item.id) }
        Button("在小宇宙网页打开") { NSWorkspace.shared.open(item.pageURL) }
        Divider()
        Button("取消订阅", role: .destructive) { service.remove(item.id) }
    }

    // MARK: 切换胶囊

    /// 胶囊里露哪两个节目：选中的一定在，另一个是列表里最靠前的其他节目，顺序按订阅顺序。
    private var chipShows: [PodcastShow] {
        guard let show else { return Array(shows.prefix(2)) }
        let other = shows.first { $0.id != show.id }
        return shows.filter { $0.id == show.id || $0.id == other?.id }
    }

    private var switcher: some View {
        HStack(spacing: 8) {
            ForEach(chipShows) { item in chip(item) }
            if shows.count > 2 { switcherMenu }
        }
    }

    private func chip(_ item: PodcastShow) -> some View {
        let selected = item.id == show?.id
        let fresh = context.isPreview ? 0 : service.library.unheard(item.id).count
        let failed = !context.isPreview && service.problems[item.id] != nil
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return HStack(spacing: 8) {
            PodcastCover(url: item.imageURL, size: Self.chipCover, preview: context.isPreview)
            Text(PodcastShowName.short(item.title))
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.panelPrimary : .panelSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if failed {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "#FF9F0A").panelGraphic)
                    .accessibilityLabel(tr("没读出来"))
            } else if fresh > 0 {
                Text(fresh > 9 ? "9+" : "\(fresh)")
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(Capsule().fill(Color(hex: "#FF3B30")))
                    .accessibilityLabel(tr("\(fresh) 个新单集"))
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity, minHeight: 42)
        .background(shape.fill(selected ? accent.opacity(0.12) : Color.panelFill))
        .overlay(shape.strokeBorder(selected ? accent.opacity(0.9) : Color.panelStroke, lineWidth: selected ? 1.5 : 0.5))
        .contentShape(shape)
        .onTapGesture {
            guard !context.isPreview else { return }
            PodcastRemote.choose(item.id, in: instance)
        }
        .contextMenu { manageItems(item) }
        .help(tr("\(item.title)\n右键可刷新、取消订阅"))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    /// 右边的下拉：列出全部订阅，打勾的是当前节目。
    private var switcherMenu: some View {
        Menu {
            ForEach(shows) { item in
                Button {
                    PodcastRemote.choose(item.id, in: instance)
                } label: {
                    if item.id == show?.id {
                        Label(item.title, systemImage: "checkmark")
                    } else {
                        Text(item.title)
                    }
                }
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelPrimary)
                .frame(width: 36, height: 42)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.panelFill))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.panelStroke, lineWidth: 0.5))
                .contentShape(.rect(cornerRadius: 12))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(context.isPreview)
        .help(tr("切换节目"))
        .accessibilityLabel(tr("切换节目"))
    }

    // MARK: 播放卡

    /// 播放卡里放的那一集：这个节目正在放（或暂停）的，否则听了一半的，否则最新的。
    private func heroEpisode(_ show: PodcastShow) -> PodcastEpisode? {
        if context.isPreview { return show.episodes.first }
        if player.showID == show.id, let current = player.episode { return current }
        return service.library.resumeEpisode(in: show.id)
    }

    @ViewBuilder
    private func playerCard(_ show: PodcastShow) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        if let episode = heroEpisode(show) {
            episodeCard(episode, show: show)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                // 氛围渐变是封面背后单独一层，玻璃在它下面；封面本身不动。
                .background { PodcastPlayerBackdrop(color: coverColor).clipShape(shape) }
                .readableGlass(in: shape)
                .overlay(shape.strokeBorder(.panelStroke, lineWidth: 0.5))
        } else if service.loading.contains(show.id) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在获取单集…")
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .readableGlass(in: shape)
        }
    }

    /// 单集状态（正在播放、未听、收听中、已听完）。
    private func status(_ episode: PodcastEpisode, in show: PodcastShow) -> PodcastEpisodeStatus {
        if context.isPreview { return .unheard }
        let current = player.isCurrent(episode)
        return PodcastEpisodeStatus.of(service.library.state(of: episode, in: show.id),
                                       isPlaying: current && player.isPlaying,
                                       livePosition: current ? player.position : nil,
                                       liveDuration: current ? player.duration : nil)
    }

    private func episodeCard(_ episode: PodcastEpisode, show: PodcastShow) -> some View {
        let current = !context.isPreview && player.isCurrent(episode)
        let playing = current && player.isPlaying
        let saved = context.isPreview ? nil : service.library.progress[episode.id]
        let duration = current ? max(player.duration, 1)
            : max(Double(episode.duration), saved?.duration ?? 0, 1)
        let position: Double = {
            if current { return scrubbing ?? player.position }
            guard !context.isPreview, let saved, !saved.finished else { return 0 }
            return saved.position
        }()
        let tag: String = {
            if current {
                if player.isBuffering, player.isPlaying { return tr("正在缓冲") }
                return player.isPlaying ? tr("正在播放") : tr("已暂停")
            }
            return position > 0 ? tr("继续收听") : tr("最新单集")
        }()
        let byline = [show.author, show.title].filter { !$0.isEmpty }
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            .joined(separator: " · ")
        let progressLine: String = {
            switch status(episode, in: show) {
            case .finished: return tr("已听完")
            case .listening(let percent): return tr("已收听约 \(percent)%")
            case .playing:
                return position > 0 ? tr("已收听约 \(PodcastEpisodeStatus.percent(position / duration))%") : tr("正在播放")
            case .unheard: return PodcastPlayback.durationText(episode.duration)
            }
        }()
        let published = PodcastDateLabel.published(episode.pubDate)
        let chapters = PodcastRemote.chapters(for: episode)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                PodcastCover(url: show.imageURL, size: Self.heroCover, preview: context.isPreview)
                    .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        HStack(spacing: 5) {
                            if current {
                                PlayingBarsView(playing: playing, tint: accent, height: 10, visible: true)
                            }
                            Text(tag)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(accent)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(Capsule().fill(accent.opacity(0.14)))
                        Spacer(minLength: 0)
                        PodcastFinishPanda(pulse: context.isPreview ? nil : player.finishPulse, size: 36)
                    }
                    Text(episode.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.panelPrimary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                        .help(episode.title)
                    if !byline.isEmpty {
                        Text(byline)
                            .font(.system(size: 13))
                            .foregroundStyle(.panelSecondary)
                            .lineLimit(1)
                            .help(byline)
                    }
                    ViewThatFits(in: .horizontal) {
                        metaLine([progressLine, published])
                        metaLine([progressLine])
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            }
            VStack(spacing: 6) {
                progressBar(position: position, duration: duration, live: current)
                HStack {
                    Text(PodcastPlayback.clock(position))
                    Spacer()
                    Text(tr("剩余 \(PodcastPlayback.clock(max(0, duration - position)))"))
                }
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(.panelSecondary)
            }
            HStack(alignment: .top, spacing: 30) {
                labeledButton("gobackward.15", caption: tr("\(Int(PodcastPlayback.backSeconds)) 秒"),
                              label: tr("后退 15 秒"), enabled: current) {
                    player.skip(by: -PodcastPlayback.backSeconds)
                }
                playButton(episode, show: show, playing: playing)
                labeledButton("goforward.30", caption: tr("\(Int(PodcastPlayback.forwardSeconds)) 秒"),
                              label: tr("前进 30 秒"), enabled: current) {
                    player.skip(by: PodcastPlayback.forwardSeconds)
                }
            }
            .frame(maxWidth: .infinity)
            Rectangle().fill(.panelSeparator).frame(height: 0.5)
            HStack(spacing: 0) {
                footerAction("list.bullet", title: tr("章节"), enabled: !chapters.isEmpty) {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { chaptersShown.toggle() }
                }
                .help(chapters.isEmpty ? tr("这一集没有章节") : tr("章节"))
                Rectangle().fill(.panelSeparator).frame(width: 0.5, height: 18)
                footerAction("arrow.up.right.square", title: tr("在小宇宙打开"), enabled: true) {
                    NSWorkspace.shared.open(XiaoyuzhouLink.episode(episode.id).pageURL)
                }
            }
            if chaptersShown, !chapters.isEmpty {
                chapterList(chapters, episode: episode, show: show, position: position, live: current)
            }
            if current, let problem = player.problem {
                Text(problem)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "#FF9F0A").panelReadable)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func metaLine(_ parts: [String]) -> some View {
        Text(parts.filter { !$0.isEmpty }.joined(separator: " · "))
            .font(.system(size: 13))
            .foregroundStyle(.panelTertiary)
            .lineLimit(1)
            .fixedSize()
    }

    private func footerAction(_ symbol: String, title: String, enabled: Bool,
                              action: @escaping () -> Void) -> some View {
        Button {
            guard !context.isPreview, enabled else { return }
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.panelPrimary.opacity(enabled ? 1 : 0.35))
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled && !context.isPreview)
    }

    /// 进度条：正在放的这一集可以拖（松手才跳），其他时候只显示听到哪了。
    private func progressBar(position: Double, duration: Double, live: Bool) -> some View {
        let fraction = min(1, max(0, position / max(duration, 1)))
        return GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.panelTrack)
                    .frame(height: 5)
                Capsule().fill(accent)
                    .frame(width: max(5, width * fraction), height: 5)
                if live {
                    Circle()
                        .fill(.panelPrimary)
                        .frame(width: 12, height: 12)
                        .shadow(color: .black.opacity(0.2), radius: 1.5, y: 0.5)
                        .offset(x: min(max(0, width * fraction - 6), width - 12))
                }
            }
            .frame(height: 16)
            .contentShape(.rect)
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard live, width > 0 else { return }
                    scrubbing = min(1, max(0, value.location.x / width)) * duration
                }
                .onEnded { _ in
                    guard live, let target = scrubbing else { return }
                    player.seek(to: target)
                    scrubbing = nil
                })
        }
        .frame(height: 16)
        .accessibilityElement()
        .accessibilityLabel(tr("播放进度"))
        .accessibilityValue(tr("已播 \(PodcastPlayback.clock(position))，共 \(PodcastPlayback.clock(duration))"))
        .accessibilityAdjustableAction { direction in
            guard live else { return }
            switch direction {
            case .increment: player.skip(by: PodcastPlayback.forwardSeconds)
            case .decrement: player.skip(by: -PodcastPlayback.backSeconds)
            @unknown default: break
            }
        }
    }

    /// 中间的大播放键：底色和图标色都从封面色校正而来（浅色深底白图标，深色浅底深图标）。
    private func playButton(_ episode: PodcastEpisode, show: PodcastShow, playing: Bool) -> some View {
        let symbol = playing ? "pause.fill" : "play.fill"
        let label = playing ? tr("暂停") : tr("播放")
        return Button {
            guard !context.isPreview else { return }
            player.toggle(episode, show: show.id)
        } label: {
            Image(systemName: symbol)
                .playPauseMorph(symbol)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Color(code: palette.playIcon))
                .offset(x: playing ? 0 : 2)
                .frame(width: 60, height: 60)
                .background(Circle().fill(Color(code: palette.playFill)))
                .shadow(color: Color(code: palette.accent).opacity(0.28), radius: 8, y: 3)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!context.isPreview && episode.audioURL == nil)
        .opacity(!context.isPreview && episode.audioURL == nil ? 0.4 : 1)
        .help(episode.audioURL == nil ? tr("这一集没有可播放的音频") : label)
        .accessibilityLabel(label)
    }

    /// 后退 / 前进：圆按钮，下面一行「15 秒」「30 秒」。
    private func labeledButton(_ symbol: String, caption: String, label: String, enabled: Bool,
                               action: @escaping () -> Void) -> some View {
        Button {
            guard !context.isPreview, enabled else { return }
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(.panelFill))
                    .overlay(Circle().strokeBorder(.panelStroke, lineWidth: 0.5))
                Text(caption)
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
            }
            .opacity(enabled || context.isPreview ? 1 : 0.4)
            .padding(.top, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!enabled && !context.isPreview)
        .help(enabled ? label : tr("先播放这一集"))
        .accessibilityLabel(label)
    }

    /// 点「章节」展开的时间轴：当前章亮，点哪一行跳到那里（没在放就先开始放这一集）。
    private func chapterList(_ chapters: [PodcastChapter], episode: PodcastEpisode, show: PodcastShow,
                             position: Double, live: Bool) -> some View {
        let currentIndex = live ? PodcastChapters.currentIndex(chapters, at: position) : nil
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
                let isCurrent = index == currentIndex
                Button {
                    guard !context.isPreview else { return }
                    if live { player.seek(to: chapter.start) } else { player.toggle(episode, show: show.id) }
                } label: {
                    HStack(spacing: 8) {
                        Text(PodcastPlayback.clock(chapter.start))
                            .font(.system(size: 13).monospacedDigit())
                            .foregroundStyle(isCurrent ? accent : Color.panelTertiary)
                        Text(chapter.title)
                            .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                            .foregroundStyle(.panelPrimary.opacity(isCurrent ? 1 : 0.7))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(tr("跳到 \(PodcastPlayback.clock(chapter.start))"))
                .accessibilityLabel("\(isCurrent ? tr("当前章节，") : "")\(chapter.title)")
            }
        }
        .transition(.opacity)
    }

    // MARK: 最近单集

    private func episodeSection(_ show: PodcastShow) -> some View {
        let all = show.episodes
        let filtered = filter.apply(all) { status($0, in: show) }
        let visible = PodcastEpisodeListing.visibleCount(total: filtered.count, expanded: expanded)
        let refreshing = !context.isPreview && service.loading.contains(show.id)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("最近单集")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                if !all.isEmpty {
                    Text(verbatim: "\(show.episodeCount > 0 ? show.episodeCount : all.count)")
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(.panelTertiary)
                }
                Spacer(minLength: 4)
                if PodcastEpisodeListing.needsToggle(total: filtered.count) {
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { expanded.toggle() }
                    } label: {
                        HStack(spacing: 3) {
                            Text(expanded ? tr("收起") : tr("查看全部"))
                            Image(systemName: expanded ? "chevron.up" : "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            }
            if all.isEmpty {
                if refreshing || service.problems[show.id] != nil || context.isPreview {
                    EmptyView()
                } else if let state = PodcastPandaCue.empty(showCount: shows.count, playableCount: 0, loading: refreshing) {
                    pandaEmpty(state, title: tr("重新获取"), message: tr("这个节目还没有单集。")) {
                        Task { await service.refresh(show.id) }
                    }
                }
            } else {
                let updated = PodcastDateLabel.updated(show.newestDate)
                if !updated.isEmpty {
                    Text(updated)
                        .font(.system(size: 13))
                        .foregroundStyle(.panelTertiary)
                        .lineLimit(1)
                }
                filterBar
                if refreshing { refreshingRow }
                if filtered.isEmpty {
                    Text(filter.emptyText)
                        .font(.system(size: 13))
                        .foregroundStyle(.panelTertiary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                } else {
                    // 展开后不另套滚动：整张面板由详情面板的通用容器限高、滚动。
                    VStack(spacing: 6) {
                        ForEach(filtered.prefix(visible)) { episode in episodeRow(episode, show: show) }
                    }
                    if expanded { listEnd(show) }
                }
            }
        }
    }

    /// 全部 / 未听 / 收听中。
    private var filterBar: some View {
        HStack(spacing: 2) {
            ForEach(PodcastEpisodeFilter.allCases, id: \.self) { item in
                let selected = item == filter
                Button {
                    filter = item
                    expanded = false
                } label: {
                    Text(item.title)
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? accent : Color.panelSecondary)
                        .lineLimit(1)
                        .fixedSize()
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .background {
                            if selected { Capsule().fill(.panelRaised).panelLift() }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(2)
        .background(Capsule().fill(.panelFill))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: filter)
    }

    /// 刷新中列表最上面的一行小转圈。
    private var refreshingRow: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.mini)
            Text("正在刷新")
                .font(.system(size: 13))
                .foregroundStyle(.panelTertiary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 24)
    }

    /// 展开后最底下一行：小宇宙页面只给最新一批，更早的拿不到，就写明白。
    private func listEnd(_ show: PodcastShow) -> some View {
        Text(PodcastLibrary.hasOlderEpisodes(show)
             ? tr("更早的单集小宇宙页面没有提供，订阅后的新单集会一直保留")
             : tr("没有更早的单集了"))
            .font(.system(size: 13))
            .foregroundStyle(.panelTertiary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
    }

    /// 一集：左边状态图标，标题，下面「未听 · 时长 · 发布于」或「收听中 32%」「已听完」，右边箭头。
    /// 窄的时候先省发布日期，再省时长。点整行播放或暂停。
    private func episodeRow(_ episode: PodcastEpisode, show: PodcastShow) -> some View {
        let current = !context.isPreview && player.isCurrent(episode)
        let state: PodcastEpisodeState = context.isPreview ? .unplayed
            : service.library.state(of: episode, in: show.id)
        let shown = status(episode, in: show)
        let published = PodcastDateLabel.published(episode.pubDate)
        let length = PodcastPlayback.durationText(episode.duration)
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return HStack(spacing: 12) {
            rowIcon(state, status: shown, current: current)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    if state == .new {
                        Circle().fill(Color(hex: "#FF3B30")).frame(width: 6, height: 6)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                            .accessibilityLabel(tr("新单集"))
                    }
                    Text(episode.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.panelPrimary.opacity(shown == .finished && !current ? 0.65 : 1))
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ViewThatFits(in: .horizontal) {
                    rowMeta(shown, parts: shown == .finished ? [published] : [length, published])
                    rowMeta(shown, parts: shown == .finished ? [] : [length])
                    rowMeta(shown, parts: [])
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelTertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(shape.fill(current ? accent.opacity(0.1) : Color.clear))
        .glassPane(cornerRadius: 14)
        .contentShape(shape)
        .onTapGesture {
            guard !context.isPreview else { return }
            player.toggle(episode, show: show.id)
        }
        .help(episode.audioURL == nil ? tr("这一集没有可播放的音频") : "\(episode.title)\n\(tr("点按播放或暂停"))")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func rowMeta(_ status: PodcastEpisodeStatus, parts: [String]) -> some View {
        let tint: Color = switch status {
        case .playing, .listening: accent
        case .unheard: .panelSecondary
        case .finished: .panelTertiary
        }
        return HStack(spacing: 5) {
            Text(status.label)
                .fontWeight(status == .unheard || status == .finished ? .regular : .semibold)
                .foregroundStyle(tint)
            ForEach(parts.filter { !$0.isEmpty }, id: \.self) { part in
                Text(verbatim: "·").foregroundStyle(.panelTertiary)
                Text(part).foregroundStyle(.panelTertiary)
            }
        }
        .font(.system(size: 13))
        .lineLimit(1)
        .fixedSize()
    }

    /// 单集左边的图标，36pt 圆角方块：未听是封面色的播放，收听中是进度环，
    /// 已听完是灰色的勾，正在放的是跳动小竖条（暂停时是播放）。
    private func rowIcon(_ state: PodcastEpisodeState, status: PodcastEpisodeStatus, current: Bool) -> some View {
        let side: CGFloat = 36
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return ZStack {
            switch status {
            case .finished:
                shape.fill(.panelFill)
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.panelSecondary)
            case .playing:
                shape.fill(accent.opacity(0.16))
                PlayingBarsView(playing: true, tint: accent, height: 14, visible: true)
            case .listening(let percent):
                shape.fill(accent.opacity(0.12))
                Circle().stroke(.panelTrack, lineWidth: 2.5).frame(width: 22, height: 22)
                Circle().trim(from: 0, to: max(0.04, Double(percent) / 100))
                    .stroke(accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 22, height: 22)
                Image(systemName: current ? "pause.fill" : "play.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(accent)
            case .unheard:
                shape.fill(accent.opacity(0.16))
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(accent)
                    .offset(x: 1)
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    // MARK: 读不出来

    /// 启动时存档没读全：说清楚、给「重新获取」，也能关掉。
    private func loadIssueCard(_ issue: PodcastService.LoadIssue) -> some View {
        noticeCard(symbol: "externaldrive.badge.exclamationmark",
                   title: tr("之前的订阅没有全部读出来"),
                   detail: issue.message,
                   busy: service.recovering,
                   action: { Task { await service.recover() } },
                   dismiss: { service.dismissLoadIssue() })
    }

    /// 选中节目这次没读到：原因加「重新获取」。
    private func problemCard(_ problem: String, show: PodcastShow) -> some View {
        noticeCard(symbol: "exclamationmark.triangle.fill",
                   title: show.episodes.isEmpty ? tr("这个节目还没读出来") : tr("没读到最新的单集"),
                   detail: problem,
                   busy: service.loading.contains(show.id),
                   action: { Task { await service.refresh(show.id) } },
                   dismiss: nil)
    }

    private func noticeCard(symbol: String, title: String, detail: String, busy: Bool,
                            action: @escaping () -> Void, dismiss: (() -> Void)?) -> some View {
        let warning = Color(hex: "#FF9F0A")
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(warning.panelGraphic)
                .frame(width: 20)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button {
                        guard !context.isPreview, !busy else { return }
                        action()
                    } label: {
                        HStack(spacing: 5) {
                            if busy {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            Text(busy ? tr("正在获取") : tr("重新获取"))
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(.panelPrimary)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(Capsule().fill(.panelRaised).panelLift())
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                    if let dismiss {
                        Button(tr("知道了")) { dismiss() }
                            .buttonStyle(.plain)
                            .font(.system(size: 13))
                            .foregroundStyle(.panelSecondary)
                            .padding(.horizontal, 6)
                            .frame(height: 28)
                    }
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPane(cornerRadius: 12)
        .accessibilityElement(children: .contain)
    }

    private func loadingRow(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .glassPane(cornerRadius: 12)
    }

    // MARK: 空状态

    /// 没订阅（待机）、节目没有可播单集（休息）时的小熊猫。播放时不出现。
    private func pandaEmpty(_ state: PandaState, title: String, message: String,
                            action: @escaping () -> Void) -> some View {
        VStack(spacing: 8) {
            PandaStateView(state, size: 64, fallbackSymbol: "mic")
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                guard !context.isPreview else { return }
                action()
            } label: {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 14)
                    .frame(height: 28)
                    .background(Capsule().fill(.panelRaised).panelLift())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: Adding

    /// 粘贴链接订阅，加上订阅成功、失败的那句话。
    private var addSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            addField
            if let message {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(messageIsError ? Color(hex: "#FF9F0A").panelReadable : .panelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var addField: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelSecondary)
            TextField("", text: $link, prompt: Text("粘贴小宇宙链接，例如 xiaoyuzhoufm.com/podcast/…"))
                .focused($addingFocused)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.panelPrimary)
                .onSubmit { add() }
                .disabled(context.isPreview || adding)
            if adding {
                ProgressView().controlSize(.mini)
            } else if !link.isEmpty {
                Button("订阅") { add() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .glassPane(cornerRadius: 10)
    }

    private func add() {
        let text = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !adding, !context.isPreview else { return }
        adding = true
        message = nil
        Task {
            let result = await service.add(text)
            adding = false
            switch result {
            case .success(let added):
                link = ""
                messageIsError = false
                message = tr("已订阅「\(added.title)」")
                PodcastRemote.choose(added.id, in: instance)
            case .failure(let failure):
                messageIsError = true
                message = failure.message
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            footerRow
            NotificationsOffNote(active: notify, preview: context.isPreview)
        }
    }

    private var footerRow: some View {
        HStack(spacing: 6) {
            Toggle(isOn: Binding(get: { notify },
                                 set: { value in
                                     guard !context.isPreview else { return }
                                     WidgetWriter.write(instance) { $0.set("notify", .bool(value)) }
                                 })) {
                Text("有新单集时通知")
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
            }
            .toggleStyle(.switch)
            .tint(panelTint.control)
            .controlSize(.mini)
            Spacer()
            Text("每小时检查一次")
                .font(.system(size: 13))
                .foregroundStyle(.panelTertiary)
        }
    }
}

// MARK: - 背景

/// 播放器背后的渐变：封面主色压低饱和度、亮度由设计定死（`PodcastCoverColor.backdrop`），
/// 从顶上往下淡出，下半截还是原来的玻璃。没有主色时什么也不画（不铺固定颜色）。
struct PodcastPlayerBackdrop: View {
    var color: ColorCode?

    @Environment(\.colorScheme) private var scheme
    @Environment(\.panelForcedDark) private var forcedDark

    var body: some View {
        let dark = forcedDark || scheme == .dark
        if let look = PodcastCoverColor.backdrop(color, dark: dark) {
            LinearGradient(stops: [
                .init(color: Color(code: look.top).opacity(look.opacity), location: 0),
                .init(color: Color(code: look.bottom).opacity(look.opacity * 0.6), location: 0.35),
                .init(color: Color(code: look.bottom).opacity(0), location: PodcastCoverColor.fadeEnd),
            ], startPoint: .top, endPoint: .bottom)
            .allowsHitTesting(false)
        } else {
            Color.clear
        }
    }
}

// MARK: - 听完一集的小熊猫

/// 听完一整集时在封面角上举爪一次（`PandaPulse` done，约 2.4 秒），然后消失。
/// 别的时候（包括正在播放）什么都不画。减弱动态效果时不弹、不淡入，只换静帧。
struct PodcastFinishPanda: View {
    var pulse: PandaPulse?
    var size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        ZStack(alignment: .bottom) {
            if shown, let pulse {
                PandaStateView(.done, pulse: pulse, size: size)
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size, alignment: .bottom)
        .animation(reduceMotion ? nil : .easeInOut(duration: PandaMotion.transition), value: shown)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: pulse?.started) {
            guard let pulse, pulse.isActive(at: .now) else {
                shown = false
                return
            }
            shown = true
            try? await Task.sleep(for: .seconds(max(0, pulse.until.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            shown = false
        }
    }
}
