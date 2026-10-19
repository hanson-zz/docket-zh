import AppKit
import SwiftUI

/// 播客's panel: a field to paste a 小宇宙 link, the subscriptions as chips
/// to switch between or remove, the episode playing with a draggable
/// progress bar and 15 second back, 30 second forward, and the chosen
/// show's episodes with their dates and lengths.
struct PodcastDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var service: PodcastService { PodcastService.shared }
    private var player: PodcastPlayer { PodcastPlayer.shared }

    @FocusState private var addingFocused: Bool
    @State private var link = ""
    @State private var adding = false
    @State private var message: String?
    @State private var messageIsError = false
    /// The slider's value while dragging, so the player seeks once at the end.
    @State private var scrubbing: Double?

    private var shows: [PodcastShow] {
        context.isPreview ? [PodcastTile.sample] : service.library.shows
    }

    private var show: PodcastShow? {
        context.isPreview ? PodcastTile.sample : PodcastRemote.show(for: instance)
    }

    private var notify: Bool { instance.config.bool("notify", default: true) }

    var body: some View {
        DetailCard {
            MeshBackdrop(color: PodcastCover.accent)
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                PanelHeader(symbol: "mic", title: tr("播客"),
                            subtitle: shows.isEmpty ? tr("粘贴小宇宙节目或单集链接来订阅") : tr("已订阅 \(shows.count) 个节目 · 来自小宇宙"))
                addField
                if let message {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(messageIsError ? Color(hex: "#FF9F0A") : .white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if shows.isEmpty {
                    PandaEmptyState(empty: .podcast, title: tr("添加订阅"), panel: true) { addingFocused = true }
                        .frame(height: 120)
                } else {
                    showStrip
                    if let episode = player.episode, !context.isPreview { nowPlaying(episode) }
                    if let show { episodeList(show) }
                }
                footer
            }
        }
    }

    // MARK: Adding

    private var addField: some View {
        HStack(spacing: 6) {
            Image(systemName: "link")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
            TextField("", text: $link, prompt: Text("粘贴小宇宙链接，例如 xiaoyuzhoufm.com/podcast/…"))
                .focused($addingFocused)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .onSubmit { add() }
                .disabled(context.isPreview || adding)
            if adding {
                ProgressView().controlSize(.mini)
            } else if !link.isEmpty {
                Button("订阅") { add() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PodcastCover.accent)
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
        return HStack(spacing: 6) {
            PodcastCover(url: item.imageURL, size: 22, preview: context.isPreview)
            Text(item.title)
                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                .foregroundStyle(.white.opacity(selected ? 1 : 0.7))
                .lineLimit(1)
                .frame(maxWidth: 110)
            if fresh > 0 {
                Text("\(fresh)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .frame(minHeight: 14)
                    .background(Capsule().fill(Color(hex: "#FF3B30")))
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(.white.opacity(selected ? 0.18 : 0.07)))
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

    // MARK: Playing

    private func nowPlaying(_ episode: PodcastEpisode) -> some View {
        let duration = max(player.duration, 1)
        let position = scrubbing ?? player.position
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(player.isPlaying ? (player.isBuffering ? tr("正在缓冲") : tr("正在播放")) : tr("已暂停"))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(PodcastCover.accent)
                Text(episode.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Slider(value: Binding(get: { min(position, duration) },
                                  set: { scrubbing = $0 }),
                   in: 0...duration,
                   onEditingChanged: { editing in
                       if !editing, let target = scrubbing {
                           player.seek(to: target)
                           scrubbing = nil
                       }
                   })
                .controlSize(.mini)
                .tint(PodcastCover.accent)
            HStack {
                Text(PodcastPlayback.clock(position))
                Spacer()
                Text("-" + PodcastPlayback.clock(max(0, duration - position)))
            }
            .font(.system(size: 10).monospacedDigit())
            .foregroundStyle(.white.opacity(0.6))
            chapterLines(episode, position: position)
            HStack(spacing: 22) {
                Spacer()
                roundButton("gobackward.15", size: 32, label: tr("后退 15 秒")) {
                    player.skip(by: -PodcastPlayback.backSeconds)
                }
                roundButton(player.isPlaying ? "pause.fill" : "play.fill", size: 44,
                            label: player.isPlaying ? tr("暂停") : tr("播放"), filled: true) {
                    player.isPlaying ? player.pause() : player.resume()
                }
                roundButton("goforward.30", size: 32, label: tr("前进 30 秒")) {
                    player.skip(by: PodcastPlayback.forwardSeconds)
                }
                Spacer()
            }
            if let problem = player.problem {
                Text(problem)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "#FF9F0A"))
            }
        }
        .padding(10)
        .glassPane(cornerRadius: 12)
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
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(isCurrent ? PodcastCover.accent : .white.opacity(0.35))
                Text(chapter.title)
                    .font(.system(size: isCurrent ? 12 : 10.5, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(.white.opacity(isCurrent ? 1 : 0.45))
                    .lineLimit(1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(tr("跳到 \(PodcastPlayback.clock(chapter.start))"))
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityLabel("\(isCurrent ? tr("当前章节，") : "")\(chapter.title)")
    }

    private func roundButton(_ symbol: String, size: CGFloat, label: String, filled: Bool = false,
                             action: @escaping () -> Void) -> some View {
        Button {
            guard !context.isPreview else { return }
            action()
        } label: {
            Image(systemName: symbol)
                .playPauseMorph(symbol)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Circle().fill(.white.opacity(filled ? 0.2 : 0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    // MARK: Episodes

    private func episodeList(_ show: PodcastShow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(show.author.isEmpty ? show.title : "\(show.title) · \(show.author)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                Spacer()
                if service.loading.contains(show.id) {
                    ProgressView().controlSize(.mini)
                } else if !context.isPreview {
                    Button {
                        Task { await service.refresh(show.id) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help("刷新单集")
                    .accessibilityLabel("刷新单集")
                }
            }
            if let problem = service.problems[show.id], !context.isPreview {
                Text(problem)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: "#FF9F0A"))
            }
            if show.episodes.isEmpty {
                Text("这个节目还没有单集。")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(show.episodes) { episode in episodeRow(episode, show: show) }
                    }
                }
                .scrollIndicators(.never)
                .frame(height: min(220, CGFloat(show.episodes.count) * 50))
            }
        }
    }

    private func episodeRow(_ episode: PodcastEpisode, show: PodcastShow) -> some View {
        let current = !context.isPreview && player.isCurrent(episode)
        let saved = context.isPreview ? nil : service.library.progress[episode.id]
        let isNew = !context.isPreview && service.library.unheard(show.id).contains { $0.id == episode.id }
        return HStack(spacing: 8) {
            Image(systemName: current && player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .playPauseMorph(current && player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(current ? PodcastCover.accent : .white.opacity(0.75))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    if isNew {
                        Circle().fill(Color(hex: "#FF3B30")).frame(width: 6, height: 6)
                    }
                    Text(episode.title)
                        .font(.system(size: 12, weight: current ? .semibold : .regular))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text([PodcastPlayback.dateText(episode.pubDate),
                          PodcastPlayback.durationText(episode.duration)]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                    if let saved {
                        Text(saved.finished ? tr("已听完") : tr("已听 \(Int(saved.fraction * 100))%"))
                            .foregroundStyle(PodcastCover.accent.opacity(0.9))
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.55))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .glassPane(cornerRadius: 9)
        .contentShape(.rect(cornerRadius: 9))
        .onTapGesture {
            guard !context.isPreview else { return }
            player.toggle(episode, show: show.id)
        }
        .help(episode.audioURL == nil ? tr("这一集没有可播放的音频") : tr("点按播放或暂停"))
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
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            Spacer()
            Text("每小时检查一次")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
        }
    }
}
