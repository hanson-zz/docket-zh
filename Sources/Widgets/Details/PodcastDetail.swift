import AppKit
import SwiftUI

/// 播客的面板（v2）：选中节目的大封面和信息做主体，下面是这一集（正在放的、
/// 听了一半的或最新的）的进度条、已播 / 剩余时间和后退 15 秒、播放、前进 30 秒，
/// 再往下是最近的单集（标题、日期、时长、新单集、听了多少）。读不出来的时候
/// 说清楚原因并给「重新获取」，不再留一片空白。订阅多个节目时顶上一排切换，
/// 粘贴链接订阅放在最下面。封面的主色只在卡片角上淡淡一抹（`MeshBackdrop`）。
struct PodcastDetail: View {
    /// 颜色面板里选的强调色，没选过是 nil，用原来的颜色（见 `PanelTint`）。
    @Environment(\.panelTint) private var panelTint

    /// 播客的强调色：小宇宙青，颜色面板里选了颜色就换成选的。
    private var accent: Color { panelTint.accent(or: PodcastCover.accent) }
    var instance: WidgetInstance
    var context: WidgetContext

    private var service: PodcastService { PodcastService.shared }
    private var player: PodcastPlayer { PodcastPlayer.shared }

    @FocusState private var addingFocused: Bool
    @State private var link = ""
    @State private var adding = false
    @State private var message: String?
    @State private var messageIsError = false
    /// The progress bar's value while dragging, so the player seeks once at the end.
    @State private var scrubbing: Double?
    /// 单集列表顶部向下过拉了多少点（0 表示没在过拉）。
    @State private var pull: CGFloat = 0
    /// 过拉已经超过阈值，松手就刷新。
    @State private var pullArmed = false
    @State private var scrollPhase: ScrollPhase = .idle

    /// 过拉超过这么多点松手才刷新。
    private static let pullThreshold: CGFloat = 40
    /// 主体封面的边长。
    private static let heroCover: CGFloat = 76

    private var shows: [PodcastShow] {
        context.isPreview ? [PodcastTile.sample] : service.library.shows
    }

    private var show: PodcastShow? {
        context.isPreview ? PodcastTile.sample : PodcastRemote.show(for: instance)
    }

    private var notify: Bool { instance.config.bool("notify", default: true) }

    /// 封面压淡后的颜色，角上那一抹用；没有封面或灰白封面时是 nil，用小宇宙青
    /// （颜色面板里选了颜色就用选的）。
    private var coverTint: Color? {
        guard !context.isPreview, let url = show?.imageURL, let tint = service.artworkTint[url] else { return nil }
        return Color(code: tint)
    }

    var body: some View {
        DetailCard {
            MeshBackdrop(color: coverTint ?? PodcastCover.accent, fixed: coverTint != nil)
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                PanelHeader(symbol: "mic", title: tr("播客"),
                            subtitle: shows.isEmpty ? tr("粘贴小宇宙节目或单集链接来订阅") : tr("已订阅 \(shows.count) 个节目 · 来自小宇宙"))
                if let issue = service.loadIssue, !context.isPreview { loadIssueCard(issue) }
                if shows.isEmpty {
                    addSection
                    if service.recovering {
                        loadingRow(tr("正在重新获取之前的订阅…"))
                    } else {
                        PandaEmptyState(empty: .podcast, title: tr("添加订阅"), panel: true,
                                        message: tr("在上面粘贴小宇宙节目或单集的链接")) {
                            WidgetDetailWindow.shared.focusField { addingFocused = true }
                        }
                        .frame(height: 140)
                    }
                } else {
                    if shows.count > 1 { showStrip }
                    if let show {
                        hero(show)
                        if let problem = service.problems[show.id], !context.isPreview {
                            problemCard(problem, show: show)
                        }
                        episodeList(show)
                    }
                    addSection
                }
                footer
            }
        }
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
                                    .font(.system(size: 12, weight: .semibold))
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
                    .foregroundStyle(accent.panelReadable)
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

    // MARK: Shows

    private var showStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(shows) { item in showChip(item) }
            }
        }
        .scrollIndicators(.never)
    }

    private func showChip(_ item: PodcastShow) -> some View {
        let selected = item.id == show?.id
        let fresh = context.isPreview ? 0 : service.library.unheard(item.id).count
        let failed = !context.isPreview && service.problems[item.id] != nil
        return HStack(spacing: 6) {
            PodcastCover(url: item.imageURL, size: 22, preview: context.isPreview)
            Text(item.title)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundStyle(.panelPrimary.opacity(selected ? 1 : 0.7))
                .lineLimit(1)
                .frame(maxWidth: 110)
            if failed {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "#FF9F0A").panelGraphic)
                    .accessibilityLabel(tr("没读出来"))
            } else if fresh > 0 {
                Text("\(fresh)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .frame(minHeight: 18)
                    .background(Capsule().fill(Color(hex: "#FF3B30")))
                    .accessibilityLabel(tr("\(fresh) 个新单集"))
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(selected ? Color.panelRaised : Color.panelFill).panelLift(selected))
        .contentShape(Capsule())
        .onTapGesture {
            guard !context.isPreview else { return }
            PodcastRemote.choose(item.id, in: instance)
        }
        .contextMenu {
            Button("刷新") { Task { await service.refresh(item.id) } }
            Button("全部标为已听") { service.markHeard(item.id) }
            Button("在小宇宙网页打开") { NSWorkspace.shared.open(item.pageURL) }
            Divider()
            Button("取消订阅", role: .destructive) { service.remove(item.id) }
        }
        .help(tr("\(item.title)\n右键可刷新、取消订阅"))
    }

    // MARK: 主体：封面、节目信息和这一集

    /// 主体卡片里放的那一集：这个节目正在放（或暂停）的，否则听了一半的，否则最新的。
    private func heroEpisode(_ show: PodcastShow) -> PodcastEpisode? {
        if context.isPreview { return show.episodes.first }
        if player.showID == show.id, let current = player.episode { return current }
        return service.library.resumeEpisode(in: show.id)
    }

    private func hero(_ show: PodcastShow) -> some View {
        let episode = heroEpisode(show)
        return VStack(alignment: .leading, spacing: 12) {
            showInfo(show)
            if let episode {
                Rectangle().fill(.panelSeparator).frame(height: 0.5)
                episodeBlock(episode, show: show)
            } else if service.loading.contains(show.id) {
                Rectangle().fill(.panelSeparator).frame(height: 0.5)
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在获取单集…")
                        .font(.system(size: 13))
                        .foregroundStyle(.panelSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .frame(height: 36)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPane(cornerRadius: 16)
    }

    /// 封面加节目名、主播、集数和更新日期，有新单集时一个小标签。
    private func showInfo(_ show: PodcastShow) -> some View {
        let fresh = context.isPreview ? 1 : service.library.unheard(show.id).count
        let updated = PodcastPlayback.dateText(show.newestDate)
        let count = show.episodeCount > 0 ? tr("共 \(show.episodeCount) 集") : ""
        let meta = [count, updated.isEmpty ? "" : tr("\(updated)更新")].filter { !$0.isEmpty }.joined(separator: " · ")
        return HStack(alignment: .top, spacing: 12) {
            PodcastCover(url: show.imageURL, size: Self.heroCover, preview: context.isPreview)
                .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
            VStack(alignment: .leading, spacing: 4) {
                Text(show.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                if !show.author.isEmpty {
                    Text(show.author)
                        .font(.system(size: 13))
                        .foregroundStyle(.panelSecondary)
                        .lineLimit(1)
                }
                if !meta.isEmpty {
                    Text(meta)
                        .font(.system(size: 13))
                        .foregroundStyle(.panelTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }
                if fresh > 0 {
                    Text(tr("\(fresh) 集新单集"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(accent.panelReadable)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(Capsule().fill(accent.opacity(0.14)))
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .help(show.title)
    }

    /// 这一集：状态、标题、进度条、已播和剩余、后退 15 秒、播放、前进 30 秒，有时间轴时下面是章节。
    private func episodeBlock(_ episode: PodcastEpisode, show: PodcastShow) -> some View {
        let current = !context.isPreview && player.isCurrent(episode)
        let playing = current && player.isPlaying
        let saved = context.isPreview ? nil : service.library.progress[episode.id]
        let duration = current ? max(player.duration, 1)
            : max(Double(episode.duration), saved?.duration ?? 0, 1)
        let position: Double = {
            if current { return scrubbing ?? player.position }
            if context.isPreview { return Double(episode.duration) * 0.32 }
            guard let saved, !saved.finished else { return 0 }
            return saved.position
        }()
        let label: String = {
            if current {
                if player.isBuffering, player.isPlaying { return tr("正在缓冲") }
                return player.isPlaying ? tr("正在播放") : tr("已暂停")
            }
            if context.isPreview || position > 0 { return tr("继续收听") }
            return tr("最新单集")
        }()
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if current {
                    PlayingBarsView(playing: playing, tint: accent.panelGraphic, height: 11, visible: true)
                }
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accent.panelReadable)
                Spacer(minLength: 4)
                Text(PodcastPlayback.dateText(episode.pubDate))
                    .font(.system(size: 13))
                    .foregroundStyle(.panelTertiary)
                    .lineLimit(1)
            }
            Text(episode.title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.panelPrimary)
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .help(episode.title)
            progressBar(position: position, duration: duration, live: current)
            HStack {
                Text(PodcastPlayback.clock(position))
                Spacer()
                Text("-" + PodcastPlayback.clock(max(0, duration - position)))
            }
            .font(.system(size: 13).monospacedDigit())
            .foregroundStyle(.panelSecondary)
            HStack(spacing: 24) {
                Spacer()
                roundButton("gobackward.15", size: 36, label: tr("后退 15 秒"), enabled: current) {
                    player.skip(by: -PodcastPlayback.backSeconds)
                }
                playButton(episode, show: show, playing: playing)
                roundButton("goforward.30", size: 36, label: tr("前进 30 秒"), enabled: current) {
                    player.skip(by: PodcastPlayback.forwardSeconds)
                }
                Spacer()
            }
            .padding(.top, 2)
            if current { chapterLines(episode, position: position) }
            if current, let problem = player.problem {
                Text(problem)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "#FF9F0A").panelReadable)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 进度条：正在放的这一集可以拖（松手才跳），其他时候只显示听到哪了。
    private func progressBar(position: Double, duration: Double, live: Bool) -> some View {
        let fraction = min(1, max(0, position / max(duration, 1)))
        return GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.panelTrack)
                    .frame(height: 5)
                Capsule().fill(accent.panelGraphic)
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

    /// 中间的大播放键：实心主文字色圆配反色图标，浅色、深色玻璃上都最醒目。
    private func playButton(_ episode: PodcastEpisode, show: PodcastShow, playing: Bool) -> some View {
        let symbol = playing ? "pause.fill" : "play.fill"
        let label = playing ? tr("暂停") : tr("播放")
        return Button {
            guard !context.isPreview else { return }
            player.toggle(episode, show: show.id)
        } label: {
            Image(systemName: symbol)
                .playPauseMorph(symbol)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.panelOnPrimary)
                .offset(x: playing ? 0 : 1.5)
                .frame(width: 52, height: 52)
                .background(Circle().fill(.panelPrimary))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!context.isPreview && episode.audioURL == nil)
        .opacity(!context.isPreview && episode.audioURL == nil ? 0.4 : 1)
        .help(episode.audioURL == nil ? tr("这一集没有可播放的音频") : label)
        .accessibilityLabel(label)
    }

    /// 进度条下面的章节，像歌词：上一章淡、当前章亮、下一章淡，跟着播放
    /// 位置往上走。点哪一行就跳到那一章。没有时间轴的单集不显示。
    @ViewBuilder
    private func chapterLines(_ episode: PodcastEpisode, position: Double) -> some View {
        let chapters = PodcastRemote.chapters(for: episode)
        if !chapters.isEmpty {
            let current = PodcastChapters.currentIndex(chapters, at: position)
            let center = current ?? -1
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
                    if abs(index - center) <= 1 || (current == nil && index == 0) {
                        chapterLine(chapter, isCurrent: index == current)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeInOut(duration: 0.35), value: current)
        }
    }

    private func chapterLine(_ chapter: PodcastChapter, isCurrent: Bool) -> some View {
        Button {
            guard !context.isPreview else { return }
            player.seek(to: chapter.start)
        } label: {
            HStack(spacing: 6) {
                Text(PodcastPlayback.clock(chapter.start))
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(isCurrent ? accent.panelReadable : .panelTertiary)
                Text(chapter.title)
                    .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(.panelPrimary.opacity(isCurrent ? 1 : 0.45))
                    .lineLimit(1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(tr("跳到 \(PodcastPlayback.clock(chapter.start))"))
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityLabel("\(isCurrent ? tr("当前章节，") : "")\(chapter.title)")
    }

    private func roundButton(_ symbol: String, size: CGFloat, label: String, enabled: Bool,
                             action: @escaping () -> Void) -> some View {
        Button {
            guard !context.isPreview, enabled else { return }
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(.panelPrimary.opacity(enabled || context.isPreview ? 1 : 0.35))
                .frame(width: size, height: size)
                .background(Circle().fill(.panelFill))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled && !context.isPreview)
        .help(enabled ? label : tr("先播放这一集"))
        .accessibilityLabel(label)
    }

    // MARK: Episodes

    private func episodeList(_ show: PodcastShow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("最近单集")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelSecondary)
                if !show.episodes.isEmpty {
                    Text("\(show.episodes.count)")
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(.panelTertiary)
                }
                Spacer()
                if service.loading.contains(show.id) {
                    ProgressView().controlSize(.mini)
                } else if !context.isPreview {
                    Button {
                        Task { await service.refresh(show.id) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.panelPrimary)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(.panelFill))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("刷新单集")
                    .accessibilityLabel("刷新单集")
                }
            }
            if show.episodes.isEmpty {
                if service.loading.contains(show.id) || service.problems[show.id] != nil {
                    EmptyView()
                } else {
                    PandaEmptyState(empty: .podcast, title: tr("重新获取"), panel: true,
                                    message: tr("这个节目还没有单集。")) {
                        guard !context.isPreview else { return }
                        Task { await service.refresh(show.id) }
                    }
                }
            } else {
                let refreshing = !context.isPreview && service.loading.contains(show.id)
                ScrollView {
                    LazyVStack(spacing: 4) {
                        if refreshing { refreshingRow }
                        ForEach(show.episodes) { episode in episodeRow(episode, show: show) }
                        listEnd(show)
                    }
                }
                .scrollIndicators(.never)
                // 内容不足一屏时也能向下过拉（弹性），下拉刷新才拉得动。
                .scrollBounceBehavior(.always, axes: .vertical)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    max(0, -(geometry.contentOffset.y + geometry.contentInsets.top))
                } action: { _, value in
                    pullChanged(value, show: show)
                }
                .onScrollPhaseChange { old, new in
                    scrollPhase = new
                    // 手指离开触控板（或松开鼠标）那一刻还拉过阈值，就刷新。
                    if old == .interacting, new != .interacting, pullArmed { pullRefresh(show) }
                }
                .overlay(alignment: .top) { pullIndicator(refreshing: refreshing) }
                .frame(height: min(260, CGFloat(show.episodes.count) * 60 + 44))
            }
        }
    }

    /// 跟着过拉的距离：超过阈值就待命；还按着的时候拉回阈值以内就取消；
    /// 系统没有报告滚动阶段时，弹回顶部那一刻补一次刷新。
    private func pullChanged(_ value: CGFloat, show: PodcastShow) {
        pull = value
        guard !context.isPreview else { return }
        if value >= Self.pullThreshold {
            pullArmed = true
        } else if pullArmed, scrollPhase == .interacting, value > 0 {
            pullArmed = false
        } else if pullArmed, value <= 0.5 {
            pullRefresh(show)
        }
    }

    private func pullRefresh(_ show: PodcastShow) {
        pullArmed = false
        guard !context.isPreview, !service.loading.contains(show.id) else { return }
        Task { await service.refresh(show.id) }
    }

    /// 过拉时露出来的那块：箭头加「下拉刷新」，过了阈值箭头朝上、写「松手刷新」。
    @ViewBuilder
    private func pullIndicator(refreshing: Bool) -> some View {
        if pull > 2, !refreshing, !context.isPreview {
            HStack(spacing: 5) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 12, weight: .semibold))
                    .rotationEffect(.degrees(pullArmed ? 180 : 0))
                    .animation(.easeInOut(duration: 0.15), value: pullArmed)
                Text(pullArmed ? tr("松手刷新") : tr("下拉刷新"))
                    .font(.system(size: 13))
            }
            .foregroundStyle(.panelSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: pull, alignment: .center)
            .clipped()
            .opacity(min(1, pull / Self.pullThreshold))
            .allowsHitTesting(false)
        }
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

    /// 列表最底下一行：小宇宙页面只给最新一批，更早的拿不到，就写明白。
    private func listEnd(_ show: PodcastShow) -> some View {
        Text(PodcastLibrary.hasOlderEpisodes(show)
             ? tr("更早的单集小宇宙页面没有提供，订阅后的新单集会一直保留")
             : tr("没有更早的单集了"))
            .font(.system(size: 13))
            .foregroundStyle(.panelTertiary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }

    /// 一集：左边的状态（新、听了多少的小圆环、听完的勾、正在放），标题最多两行，
    /// 下面日期、时长和还剩多少。
    private func episodeRow(_ episode: PodcastEpisode, show: PodcastShow) -> some View {
        let current = !context.isPreview && player.isCurrent(episode)
        let playing = current && player.isPlaying
        let state: PodcastEpisodeState = context.isPreview ? .unplayed
            : service.library.state(of: episode, in: show.id)
        let saved = context.isPreview ? nil : service.library.progress[episode.id]
        var meta = [PodcastPlayback.dateText(episode.pubDate), PodcastPlayback.durationText(episode.duration)]
            .filter { !$0.isEmpty }.joined(separator: " · ")
        var progressText: String?
        switch state {
        case .inProgress:
            if let saved { progressText = PodcastPlayback.remainingText(position: saved.position, duration: saved.duration) }
        case .finished:
            progressText = tr("已听完")
        case .new, .unplayed:
            break
        }
        if meta.isEmpty, let progressText { meta = progressText; progressText = nil }
        return HStack(alignment: .top, spacing: 10) {
            stateGlyph(state, current: current, playing: playing)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    if state == .new {
                        Circle().fill(Color(hex: "#FF3B30")).frame(width: 6, height: 6)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                            .accessibilityLabel(tr("新单集"))
                    }
                    Text(episode.title)
                        .font(.system(size: 13, weight: current || state == .new ? .semibold : .regular))
                        .foregroundStyle(.panelPrimary.opacity(state == .finished && !current ? 0.6 : 1))
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 6) {
                    Text(meta)
                        .foregroundStyle(.panelTertiary)
                    if let progressText {
                        Text(progressText)
                            .foregroundStyle(state == .finished ? Color.panelTertiary : accent.panelReadable)
                    }
                }
                .font(.system(size: 13))
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(current ? Color.panelSelected : Color.clear)
        }
        .glassPane(cornerRadius: 10)
        .contentShape(.rect(cornerRadius: 10))
        .onTapGesture {
            guard !context.isPreview else { return }
            player.toggle(episode, show: show.id)
        }
        .help(episode.audioURL == nil ? tr("这一集没有可播放的音频") : "\(episode.title)\n\(tr("点按播放或暂停"))")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    /// 一集左边的状态图标，24pt。
    @ViewBuilder
    private func stateGlyph(_ state: PodcastEpisodeState, current: Bool, playing: Bool) -> some View {
        let side: CGFloat = 24
        if current {
            Image(systemName: playing ? "pause.circle.fill" : "play.circle.fill")
                .playPauseMorph(playing ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: side - 2))
                .foregroundStyle(accent.panelGraphic)
                .frame(width: side, height: side)
        } else {
            switch state {
            case .inProgress(let fraction):
                ZStack {
                    Circle().stroke(.panelTrack, lineWidth: 2.5)
                    Circle().trim(from: 0, to: max(0.04, fraction))
                        .stroke(accent.panelGraphic, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "play.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.panelPrimary)
                        .offset(x: 0.5)
                }
                .padding(2)
                .frame(width: side, height: side)
                .accessibilityLabel(tr("听了 \(Int(fraction * 100))%"))
            case .finished:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: side - 2))
                    .foregroundStyle(.panelTertiary)
                    .frame(width: side, height: side)
                    .accessibilityLabel(tr("已听完"))
            case .new:
                Image(systemName: "play.circle.fill")
                    .font(.system(size: side - 2))
                    .foregroundStyle(accent.panelGraphic)
                    .frame(width: side, height: side)
            case .unplayed:
                Image(systemName: "play.circle")
                    .font(.system(size: side - 2))
                    .foregroundStyle(.panelSecondary)
                    .frame(width: side, height: side)
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
