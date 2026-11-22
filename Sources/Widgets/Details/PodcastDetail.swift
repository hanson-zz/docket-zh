import AppKit
import SwiftUI

/// 播客的面板（2.0，沉浸式播放器）：订阅多个节目时顶上一排封面选择器（小封面加短名，
/// 不再截断长节目名）；中间是当前节目的大封面，下面单集名、节目名各只出现一次，
/// 再往下进度条、已播 / 剩余时间和后退 15 秒、播放、前进 30 秒；有时间轴时显示章节。
/// 最下面是单集：「全部 / 未听 / 收听中」筛选，默认只露 3 条，「查看全部」展开后在列表里滚。
/// 背景是从封面取的主色生成的克制渐变（`PodcastCoverColor`），浅色外观保持浅底。
/// 小熊猫只在没有订阅或没有可播单集时当空状态，听完一整集时短暂表态一次。
struct PodcastDetail: View {
    /// 颜色面板里选的强调色，没选过是 nil，用原来的颜色（见 `PanelTint`）。
    @Environment(\.panelTint) private var panelTint

    /// 播客的强调色：小宇宙青，颜色面板里选了颜色就换成选的。只用在进度条、状态字这类小面积。
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
    /// 单集筛选：全部 / 未听 / 收听中。
    @State private var filter: PodcastEpisodeFilter = .all
    /// 「查看全部」展开了。
    @State private var expanded = false

    /// 过拉超过这么多点松手才刷新。
    private static let pullThreshold: CGFloat = 40
    /// 播放器中间封面的边长。
    private static let heroCover: CGFloat = 116
    /// 选择器里封面的边长和每一格的宽度（大约 5 个汉字宽，放得下短名）。
    private static let pickerCover: CGFloat = 40
    private static let pickerWidth: CGFloat = 70

    private var shows: [PodcastShow] {
        context.isPreview ? [PodcastTile.sample] : service.library.shows
    }

    private var show: PodcastShow? {
        context.isPreview ? PodcastTile.sample : PodcastRemote.show(for: instance)
    }

    private var notify: Bool { instance.config.bool("notify", default: true) }

    /// 封面的主色，背景渐变用；没有封面或灰白封面时 nil，背景只留玻璃，不铺固定颜色。
    private var coverColor: ColorCode? {
        guard !context.isPreview, let url = show?.imageURL else { return nil }
        return service.coverColor[url]
    }

    var body: some View {
        DetailCard {
            PodcastPlayerBackdrop(color: coverColor)
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
                        pandaEmpty(.idle, title: tr("添加订阅"), message: tr("在上面粘贴小宇宙节目或单集的链接")) {
                            WidgetDetailWindow.shared.focusField { addingFocused = true }
                        }
                    }
                } else {
                    if shows.count > 1 { coverPicker }
                    if let show {
                        playerView(show)
                        if let problem = service.problems[show.id], !context.isPreview {
                            problemCard(problem, show: show)
                        }
                        episodeSection(show)
                    }
                    addSection
                }
                footer
            }
        }
        .onChange(of: show?.id) { _, _ in
            expanded = false
            filter = .all
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

    // MARK: 封面选择器

    /// 顶上一排：小封面加短名，选中的封面描一圈边、名字加粗。完整节目名在悬停提示和播放器里。
    private var coverPicker: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 4) {
                ForEach(shows) { item in pickerItem(item) }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.never)
    }

    private func pickerItem(_ item: PodcastShow) -> some View {
        let selected = item.id == show?.id
        let fresh = context.isPreview ? 0 : service.library.unheard(item.id).count
        let failed = !context.isPreview && service.problems[item.id] != nil
        let corner = Self.pickerCover * 0.24
        return VStack(spacing: 4) {
            PodcastCover(url: item.imageURL, size: Self.pickerCover, preview: context.isPreview)
                .padding(2)
                .overlay {
                    RoundedRectangle(cornerRadius: corner + 2, style: .continuous)
                        .strokeBorder(selected ? Color.panelPrimary.opacity(0.85) : .clear, lineWidth: 1.5)
                }
                .opacity(selected ? 1 : 0.78)
                .overlay(alignment: .topTrailing) {
                    if failed {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(hex: "#FF9F0A").panelGraphic)
                            .background(Circle().fill(.panelRaised))
                            .offset(x: 3, y: -3)
                            .accessibilityLabel(tr("没读出来"))
                    } else if fresh > 0 {
                        Text(fresh > 9 ? "9+" : "\(fresh)")
                            .font(.system(size: 13, weight: .bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Capsule().fill(Color(hex: "#FF3B30")))
                            .offset(x: 4, y: -4)
                            .accessibilityLabel(tr("\(fresh) 个新单集"))
                    }
                }
            Text(PodcastShowName.short(item.title))
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.panelPrimary : .panelSecondary)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(width: Self.pickerWidth)
        .padding(.vertical, 4)
        .contentShape(.rect(cornerRadius: 10))
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

    /// 订阅管理：右键菜单和播放器里「…」按钮共用。
    @ViewBuilder
    private func manageItems(_ item: PodcastShow) -> some View {
        Button("刷新") { Task { await service.refresh(item.id) } }
        Button("全部标为已听") { service.markHeard(item.id) }
        Button("在小宇宙网页打开") { NSWorkspace.shared.open(item.pageURL) }
        Divider()
        Button("取消订阅", role: .destructive) { service.remove(item.id) }
    }

    // MARK: 播放器

    /// 播放器里放的那一集：这个节目正在放（或暂停）的，否则听了一半的，否则最新的。
    private func heroEpisode(_ show: PodcastShow) -> PodcastEpisode? {
        if context.isPreview { return show.episodes.first }
        if player.showID == show.id, let current = player.episode { return current }
        return service.library.resumeEpisode(in: show.id)
    }

    private func playerView(_ show: PodcastShow) -> some View {
        let episode = heroEpisode(show)
        return VStack(spacing: 10) {
            PodcastCover(url: show.imageURL, size: Self.heroCover, preview: context.isPreview)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
                .overlay(alignment: .bottomTrailing) {
                    PodcastFinishPanda(pulse: context.isPreview ? nil : player.finishPulse, size: 48)
                        .offset(x: 30, y: 6)
                }
                .padding(.top, 2)
            if let episode {
                episodeBlock(episode, show: show)
            } else {
                showLine(show)
                if service.loading.contains(show.id) {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在获取单集…")
                            .font(.system(size: 13))
                            .foregroundStyle(.panelSecondary)
                    }
                    .frame(height: 36)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// 节目名（完整，最多两行）和主播，右边一个「…」放订阅管理。按钮固定宽度，长名换行不挤它。
    private func showLine(_ show: PodcastShow) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Color.clear.frame(width: 26, height: 1)
            VStack(spacing: 2) {
                Text(show.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !show.author.isEmpty, show.author != show.title {
                    Text(show.author)
                        .font(.system(size: 13))
                        .foregroundStyle(.panelTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .layoutPriority(1)
            .help(show.title)
            manageMenu(show)
        }
    }

    private func manageMenu(_ show: PodcastShow) -> some View {
        Menu {
            manageItems(show)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelPrimary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(.panelFill))
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

    /// 单集状态（正在播放、未听、收听中、已听完）。
    private func status(_ episode: PodcastEpisode, in show: PodcastShow) -> PodcastEpisodeStatus {
        if context.isPreview { return .unheard }
        let current = player.isCurrent(episode)
        return PodcastEpisodeStatus.of(service.library.state(of: episode, in: show.id),
                                       isPlaying: current && player.isPlaying,
                                       livePosition: current ? player.position : nil,
                                       liveDuration: current ? player.duration : nil)
    }

    private func statusColor(_ status: PodcastEpisodeStatus) -> Color {
        switch status {
        case .playing, .listening: accent.panelReadable
        case .unheard: .panelSecondary
        case .finished: .panelTertiary
        }
    }

    /// 这一集：单集名（只在这里大字出现一次）、节目名、状态和发布日期、进度条、时间、三个按钮、章节。
    private func episodeBlock(_ episode: PodcastEpisode, show: PodcastShow) -> some View {
        let current = !context.isPreview && player.isCurrent(episode)
        let playing = current && player.isPlaying
        let saved = context.isPreview ? nil : service.library.progress[episode.id]
        let duration = current ? max(player.duration, 1)
            : max(Double(episode.duration), saved?.duration ?? 0, 1)
        let position: Double = {
            if current { return scrubbing ?? player.position }
            if context.isPreview { return 0 }
            guard let saved, !saved.finished else { return 0 }
            return saved.position
        }()
        let state = status(episode, in: show)
        let label: String = {
            if current, player.isBuffering, player.isPlaying { return tr("正在缓冲") }
            if current, !player.isPlaying { return tr("已暂停") }
            return state.label
        }()
        let published = PodcastDateLabel.published(episode.pubDate)
        return VStack(spacing: 8) {
            VStack(spacing: 4) {
                Text(episode.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(episode.title)
                showLine(show)
                HStack(spacing: 6) {
                    if current {
                        PlayingBarsView(playing: playing, tint: accent.panelGraphic, height: 11, visible: true)
                    }
                    Text(label)
                        .foregroundStyle(statusColor(state))
                        .fontWeight(.semibold)
                    if !published.isEmpty {
                        Text(verbatim: "·").foregroundStyle(.panelTertiary)
                        Text(published).foregroundStyle(.panelTertiary)
                    }
                }
                .font(.system(size: 13))
                .lineLimit(1)
            }
            progressBar(position: position, duration: duration, live: current)
                .padding(.top, 4)
            HStack {
                Text(PodcastPlayback.clock(position))
                Spacer()
                Text("-" + PodcastPlayback.clock(max(0, duration - position)))
            }
            .font(.system(size: 13).monospacedDigit())
            .foregroundStyle(.panelSecondary)
            .padding(.top, -4)
            HStack(spacing: 28) {
                roundButton("gobackward.15", size: 40, label: tr("后退 15 秒"), enabled: current) {
                    player.skip(by: -PodcastPlayback.backSeconds)
                }
                playButton(episode, show: show, playing: playing)
                roundButton("goforward.30", size: 40, label: tr("前进 30 秒"), enabled: current) {
                    player.skip(by: PodcastPlayback.forwardSeconds)
                }
            }
            .frame(maxWidth: .infinity)
            if current { chapterLines(episode, position: position) }
            if current, let problem = player.problem {
                Text(problem)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "#FF9F0A").panelReadable)
                    .multilineTextAlignment(.center)
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
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.panelOnPrimary)
                .offset(x: playing ? 0 : 1.5)
                .frame(width: 56, height: 56)
                .background(Circle().fill(.panelPrimary))
                .shadow(color: .black.opacity(0.14), radius: 6, y: 3)
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
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPane(cornerRadius: 10)
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
                Spacer(minLength: 0)
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

    // MARK: 单集

    private func episodeSection(_ show: PodcastShow) -> some View {
        let all = show.episodes
        let filtered = filter.apply(all) { status($0, in: show) }
        let visible = PodcastEpisodeListing.visibleCount(total: filtered.count, expanded: expanded)
        let refreshing = !context.isPreview && service.loading.contains(show.id)
        return VStack(alignment: .leading, spacing: 8) {
            episodeHeader(show, refreshing: refreshing)
            if all.isEmpty {
                if refreshing || service.problems[show.id] != nil || context.isPreview {
                    EmptyView()
                } else if let state = PodcastPandaCue.empty(showCount: shows.count, playableCount: 0, loading: refreshing) {
                    pandaEmpty(state, title: tr("重新获取"), message: tr("这个节目还没有单集。")) {
                        Task { await service.refresh(show.id) }
                    }
                }
            } else {
                filterBar
                if filtered.isEmpty {
                    Text(filter.emptyText)
                        .font(.system(size: 13))
                        .foregroundStyle(.panelTertiary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                } else if expanded {
                    expandedList(Array(filtered), show: show, refreshing: refreshing)
                } else {
                    VStack(spacing: 4) {
                        if refreshing { refreshingRow }
                        ForEach(filtered.prefix(visible)) { episode in episodeRow(episode, show: show) }
                    }
                }
                if PodcastEpisodeListing.needsToggle(total: filtered.count) {
                    moreButton(hidden: PodcastEpisodeListing.hiddenCount(total: filtered.count, expanded: expanded))
                }
            }
        }
    }

    /// 「单集」加上节目最近更新的日期（和单集的「发布于」分开写），右边刷新。
    private func episodeHeader(_ show: PodcastShow, refreshing: Bool) -> some View {
        let updated = PodcastDateLabel.updated(show.newestDate)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("单集")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelSecondary)
            if show.episodeCount > 0 {
                Text(tr("共 \(show.episodeCount) 集"))
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(.panelTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if !updated.isEmpty {
                Text(updated)
                    .font(.system(size: 13))
                    .foregroundStyle(.panelTertiary)
                    .lineLimit(1)
                    .layoutPriority(-1)
            }
            if refreshing {
                ProgressView().controlSize(.mini)
                    .frame(width: 26, height: 26)
            } else if !context.isPreview {
                Button {
                    Task { await service.refresh(show.id) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
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
                        .foregroundStyle(selected ? Color.panelPrimary : .panelSecondary)
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
        .animation(.easeInOut(duration: 0.2), value: filter)
    }

    private func moreButton(hidden: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.25)) { expanded.toggle() }
        } label: {
            HStack(spacing: 4) {
                Text(expanded ? tr("收起") : tr("查看全部（\(hidden + PodcastEpisodeListing.collapsedCount)）"))
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.panelSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// 展开后的完整列表：在面板里滚，顶上可以下拉刷新。
    private func expandedList(_ episodes: [PodcastEpisode], show: PodcastShow, refreshing: Bool) -> some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                if refreshing { refreshingRow }
                ForEach(episodes) { episode in episodeRow(episode, show: show) }
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
        .frame(height: min(CGFloat(PodcastEpisodeListing.expandedMaxHeight), CGFloat(episodes.count) * 60 + 44))
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
                    .font(.system(size: 13, weight: .semibold))
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

    /// 一集：左边状态图标，标题最多两行，下面状态字（未听、收听中 32%、已听完、正在播放）、
    /// 发布日期和时长；窄的时候先省掉时长。
    private func episodeRow(_ episode: PodcastEpisode, show: PodcastShow) -> some View {
        let current = !context.isPreview && player.isCurrent(episode)
        let playing = current && player.isPlaying
        let state: PodcastEpisodeState = context.isPreview ? .unplayed
            : service.library.state(of: episode, in: show.id)
        let shown = status(episode, in: show)
        let published = PodcastDateLabel.published(episode.pubDate)
        let length = PodcastPlayback.durationText(episode.duration)
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
                        .foregroundStyle(.panelPrimary.opacity(shown == .finished && !current ? 0.6 : 1))
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ViewThatFits(in: .horizontal) {
                    rowMeta(shown, parts: [published, length])
                    rowMeta(shown, parts: [published])
                    rowMeta(shown, parts: [])
                }
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

    private func rowMeta(_ status: PodcastEpisodeStatus, parts: [String]) -> some View {
        HStack(spacing: 5) {
            Text(status.label)
                .fontWeight(status == .unheard ? .regular : .semibold)
                .foregroundStyle(statusColor(status))
            ForEach(parts.filter { !$0.isEmpty }, id: \.self) { part in
                Text(verbatim: "·").foregroundStyle(.panelTertiary)
                Text(part).foregroundStyle(.panelTertiary)
            }
        }
        .font(.system(size: 13))
        .lineLimit(1)
        .fixedSize()
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
                .accessibilityHidden(true)
            case .finished:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: side - 2))
                    .foregroundStyle(.panelTertiary)
                    .frame(width: side, height: side)
                    .accessibilityHidden(true)
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
