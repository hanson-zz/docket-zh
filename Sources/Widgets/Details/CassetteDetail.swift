import AppKit
import SwiftUI

/// 「复古卡带」面板（效果图 design/cassette-widget-glass-light.png、-dark.png，320 宽）。
///
/// 从上到下：玻璃吊牌「来源：音乐」（点开换来源）和「打开 App」，机身（磁带、随身听、
/// 收录机，实物质感、颜色写死），歌名 / 歌手 · 专辑，磁带款多一行「两边带卷粗细 +
/// 中间计数器」，玻璃键帽（随机、上一首、珊瑚播放键、下一首、循环；播放中珊瑚键锁住
/// 下沉 1pt，不发光），玻璃推子音量，「接下来」B 面 3 首玻璃行，最底下机型分段。
/// 底部「外观」行由面板外框画。
///
/// 底板、字和控件是液态玻璃，跟着浅色 / 深色走（面板语义色、`GlassKeyStyle`），
/// 珊瑚只给播放键。播放数据和控制全部走正在播放的服务（`MusicNow`、`MusicService`），
/// 不另写一份。拖带子（磁带的计数行、随身听的进度条、收录机的调台条）可以跳到那里，
/// 只读的来源（网易云、QQ 音乐、网页视频）不能拖。
struct CassetteDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private enum Page { case player, sources }

    @State private var page: Page = .player
    @State private var scrubbing: Double?
    @State private var dragVolume: Double?
    @State private var showAll = false
    /// 刚点的机型：写回配置后面板不一定马上拿到新的一份，先按点的显示。
    @State private var pickedModel: CassetteModel?

    private var current: WidgetInstance { WidgetWriter.current(instance.id) ?? instance }
    private var config: WidgetConfig { current.config }
    private var model: CassetteModel { pickedModel ?? CassetteModel.stored(config) }
    private var browsersEnabled: Bool { config.bool("browsers", default: true) }
    private var autoSwitch: Bool { MusicSourceSwitch.autoSwitch(config) }

    private static let sample = Playing(native: NowPlaying(
        title: tr("海边的晚风"), artist: tr("林间乐队"), album: tr("夏末合集"),
        duration: 245, elapsed: 102, isPlaying: true, artwork: nil, source: .appleMusic
    ))

    private var playing: Playing? {
        context.isPreview ? Self.sample : MusicNow.playing(browsersEnabled: browsersEnabled)
    }

    private var needsPermission: Bool {
        !context.isPreview && MusicNow.needsPermission(browsersEnabled: browsersEnabled)
    }

    var body: some View {
        let track = playing
        VStack(alignment: .leading, spacing: 0) {
            if track == nil, needsPermission {
                connect
            } else {
                topRow(track)
                if page == .sources {
                    sourcesPage(track)
                } else {
                    machine(track)
                        .padding(.top, 14)
                    if let track {
                        player(track)
                    } else {
                        idle
                    }
                }
            }
            modelPicker
                .padding(.top, 20)
        }
        .foregroundStyle(.panelPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            guard !context.isPreview else { return }
            MusicService.shared.configure(config)
            MusicService.shared.setWantsUpNext(true)
            // 只有已经给过录音权限才启动应用音量，绝不为了音量条去弹权限。
            if AppVolumeService.recordingGranted { AppVolumeService.shared.start() }
        }
        .onDisappear {
            guard !context.isPreview else { return }
            MusicService.shared.setWantsUpNext(false)
        }
    }

    // MARK: 顶部：来源吊牌和打开 App

    private var shownSource: MusicSource? {
        if let source = playing?.source { return source }
        if context.isPreview { return .appleMusic }
        let enabled = MusicSource.enabled(in: config)
        return MusicService.shared.display.source ?? MusicService.shared.current
            ?? enabled.first(where: { MusicService.isInstalled($0) })
    }

    private func topRow(_ track: Playing?) -> some View {
        let name = track.map { $0.isBrowser ? $0.artist : ($0.source?.displayName ?? "") }
            ?? shownSource?.displayName ?? tr("音乐")
        let bundleID = track?.sourceBundleID ?? shownSource?.bundleID
        return HStack(spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { page = page == .sources ? .player : .sources }
            } label: {
                SourceTag(name: name, playing: track?.isPlaying == true, open: page == .sources)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tr("切换来源"))
            .help(tr("点开换来源"))
            Spacer(minLength: 6)
            if let bundleID {
                Button {
                    guard !context.isPreview else { return }
                    openApp(bundleID)
                } label: {
                    Text(tr("打开 App"))
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                }
                .buttonStyle(GlassKeyStyle(corner: 15))
                .fixedSize()
                .help(tr("在 App 中打开"))
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

    // MARK: 机身

    /// 现在画的这一首；拖带子时进度先跟手。
    private func deck(_ track: Playing?) -> CassetteTrack {
        var deck = MusicNow.cassetteTrack(track, preview: context.isPreview)
        if let scrubbing, deck.duration > 0 {
            deck.progress = scrubbing
            deck.elapsed = scrubbing * deck.duration
        }
        return deck
    }

    @ViewBuilder
    private func machine(_ track: Playing?) -> some View {
        let deck = deck(track)
        let visible = !context.isPreview
        switch model {
        case .tape:
            PanelTape(track: deck, visible: visible)
                .frame(maxWidth: .infinity)
        case .portable:
            PanelPortable(track: deck, visible: visible, volume: volumeLevel(track),
                          seek: seekHandler(track))
        case .boombox:
            PanelBoombox(track: deck, visible: visible, volume: volumeLevel(track),
                         seek: seekHandler(track))
        }
    }

    // MARK: 播放中

    private func player(_ track: Playing) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            titles(track)
                .padding(.top, 16)
            if model == .tape {
                counterRow(track)
                    .padding(.top, 12)
            }
            keys(track)
                .padding(.top, 14)
            controlHint(track)
            volume(track)
            upNext(track)
        }
    }

    private func titles(_ track: Playing) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.system(size: 20, weight: .bold))
                Text([track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.panelSecondary)
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            // A 面：正在放的这一面；「接下来」是 B 面。
            Text(tr("A 面"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelSecondary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10)
                .frame(height: 26)
                .glassPane(cornerRadius: 13)
        }
    }

    /// 磁带款：左右两卷带子的粗细跟着进度，中间是带长计数器；拖中间这段带子跳到那里。
    private func counterRow(_ track: Playing) -> some View {
        let deck = deck(track)
        let left = CassetteMotion.packRadius(min: 6, max: 15, progress: deck.progress, left: true)
        let right = CassetteMotion.packRadius(min: 6, max: 15, progress: deck.progress, left: false)
        return HStack(spacing: 0) {
            PackReel(radius: CGFloat(left))
            tapeLine
            Text(CassetteWidget.counterLine(elapsed: deck.elapsed, duration: deck.showsTime ? deck.duration : 0))
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(CassettePalette.rgb(242, 196, 109))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(CassettePalette.rgb(30, 26, 24)))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
            tapeLine
            PackReel(radius: CGFloat(right))
        }
        .frame(height: 40)
        .seekable(seekHandler(track))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("进度"))
        .accessibilityValue(Text(verbatim: CassetteWidget.counterLine(elapsed: deck.elapsed, duration: deck.duration)))
    }

    private var tapeLine: some View {
        Rectangle().fill(CassettePalette.tape.opacity(0.75)).frame(height: 1.2).frame(maxWidth: .infinity)
    }

    // MARK: 拖带子跳转

    private func canSeek(_ track: Playing?) -> Bool {
        guard let track else { return false }
        return !context.isPreview && !track.isBrowser && track.canSeek && track.duration > 0
    }

    /// 横着拖（或点一下）带子跳到那个位置：拖的时候进度先跟手，松开才跳。
    private func seekHandler(_ track: Playing?) -> SeekHandler {
        let enabled = canSeek(track)
        let duration = track?.duration ?? 0
        return SeekHandler(enabled: enabled,
                           changed: { ratio in scrubbing = ratio },
                           ended: { ratio in
                               scrubbing = nil
                               MusicService.shared.seek(to: ratio * duration)
                           })
    }

    // MARK: 玻璃键帽

    @ViewBuilder
    private func keys(_ track: Playing) -> some View {
        if track.isBrowser {
            // 网页标签页只能播放 / 暂停。
            GlassKey(symbol: track.isPlaying ? "pause.fill" : "play.fill",
                     label: track.isPlaying ? tr("暂停") : tr("播放"), coral: true, latched: track.isPlaying,
                     glyph: 20, corner: 13, action: context.isPreview ? nil : { BrowserMedia.shared.playPause() })
                .frame(height: 50)
        } else {
            let native = track.native
            let extras = track.source?.hasShuffleAndRepeat == true
            let mode = native?.repeatMode ?? .off
            let live = !context.isPreview
            HStack(spacing: 8) {
                if extras {
                    GlassKey(text: tr("随机"), label: tr("随机播放"), lit: native?.shuffle == true, glyph: 14,
                             corner: 13, action: live ? { MusicService.shared.setShuffle(!(native?.shuffle ?? false)) } : nil)
                        .accessibilityValue(native?.shuffle == true ? tr("开") : tr("关"))
                }
                GlassKey(symbol: "backward.end.fill", label: tr("上一首"), glyph: 18, corner: 13,
                         action: live ? { MusicService.shared.previous() } : nil)
                GlassKey(symbol: track.isPlaying ? "pause.fill" : "play.fill",
                         label: track.isPlaying ? tr("暂停") : tr("播放"), coral: true, latched: track.isPlaying,
                         glyph: 20, corner: 13, action: live ? { MusicService.shared.playPause() } : nil)
                GlassKey(symbol: "forward.end.fill", label: tr("下一首"), glyph: 18, corner: 13,
                         action: live ? { MusicService.shared.next() } : nil)
                if extras {
                    GlassKey(text: mode == .one ? tr("单曲") : tr("循环"), label: mode.label, lit: mode != .off,
                             glyph: 14, corner: 13, action: live ? { MusicService.shared.cycleRepeat() } : nil)
                }
            }
            .frame(height: 50)
        }
    }

    /// 网易云、QQ 音乐、小宇宙的按钮退到菜单项或媒体键才能用、却没有辅助功能权限时，
    /// 键下面一行说明和「去授权」（和正在播放面板一样）。
    @ViewBuilder
    private func controlHint(_ track: Playing) -> some View {
        if !context.isPreview, let source = track.source, source.readsNowPlaying,
           MusicService.shared.controlNeedsAccessibility(source) {
            HStack(spacing: 8) {
                Text(tr("按钮控制需要辅助功能权限"))
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Button(tr("去授权")) { AppWindows.requestAccess() }
                    .buttonStyle(GlassKeyStyle(corner: 12))
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 70, height: 26)
            }
            .padding(.top, 10)
        }
    }

    // MARK: 音量（玻璃推子）

    /// 现在的音量 0...1，读不到是 nil（收录机旋钮、随身听拨轮跟着它转）。
    private func volumeLevel(_ track: Playing?) -> Double? {
        guard let track, let source = track.source, !track.isBrowser, !context.isPreview else {
            return context.isPreview ? 0.62 : nil
        }
        switch MusicVolumeRoute.route(for: source, recordingGranted: AppVolumeService.recordingGranted) {
        case .player: return dragVolume ?? track.native?.volume.map { $0 / 100 }
        case .appVolume: return dragVolume ?? min(100, AppVolumeService.shared.setting(for: source.bundleID).percent) / 100
        case .none: return nil
        }
    }

    @ViewBuilder
    private func volume(_ track: Playing) -> some View {
        if let source = track.source, !track.isBrowser, let level = volumeLevel(track) {
            let route = MusicVolumeRoute.route(for: source, recordingGranted: AppVolumeService.recordingGranted)
            GlassFader(value: level, label: tr("音量")) { value, done in
                guard !context.isPreview else { return }
                dragVolume = done ? nil : value
                switch route {
                case .player: MusicService.shared.setVolume(value * 100)
                case .appVolume: AppVolumeService.shared.setPercent(value * 100, for: source.bundleID)
                case .none: break
                }
            }
            .padding(.top, 16)
        } else if context.isPreview {
            GlassFader(value: 0.62, label: tr("音量")) { _, _ in }
                .padding(.top, 16)
        }
    }

    // MARK: 接下来（B 面）

    @ViewBuilder
    private func upNext(_ track: Playing) -> some View {
        if let source = track.source, let native = track.native, !context.isPreview {
            if source.hasUpNext {
                let shuffle = native.shuffle ?? false
                let items = MusicService.shared.upNext?.items ?? []
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader(tr("接下来"), count: MusicUpNext.visible(shuffle: shuffle) ? items.count : 0)
                    if !MusicUpNext.visible(shuffle: shuffle) {
                        note(tr("随机播放时没有固定的接下来"))
                    } else if items.isEmpty {
                        note(MusicService.shared.upNext == nil ? tr("正在读取歌单…") : tr("歌单里后面没有歌了"))
                    } else {
                        let shown = CassetteWidget.upNextShown(count: items.count, expanded: showAll)
                        ForEach(Array(items.prefix(shown).enumerated()), id: \.element.id) { offset, item in
                            UpNextRow(number: CassetteWidget.trackNumber(offset: offset), title: item.title,
                                      artist: item.artist, duration: item.duration, first: offset == 0) {
                                MusicService.shared.play(item)
                            }
                        }
                    }
                }
                .padding(.top, 18)
            } else if source.keepsRecent {
                // Spotify 不给读队列，同一位置是本机记的「刚才听过」。
                let entries = MusicService.shared.recent.listed(excluding: native.trackID)
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader(tr("刚才听过"), count: 0, showAllCount: entries.count)
                    if entries.isEmpty {
                        note(tr("放过的歌会记在这里，点一下重放"))
                    } else {
                        let shown = CassetteWidget.upNextShown(count: entries.count, expanded: showAll)
                        ForEach(Array(entries.prefix(shown).enumerated()), id: \.element.id) { offset, entry in
                            UpNextRow(number: nil, title: entry.title, artist: entry.artist,
                                      duration: entry.duration, first: offset == 0) {
                                MusicService.shared.replay(entry)
                            }
                        }
                    }
                }
                .padding(.top, 18)
            }
        } else if context.isPreview {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeader(tr("接下来"), count: 3)
                UpNextRow(number: "04", title: tr("晚风轻拂"), artist: tr("林间乐队"), duration: 228, first: true) {}
                UpNextRow(number: "05", title: tr("退潮"), artist: tr("林间乐队"), duration: 252, first: false) {}
                UpNextRow(number: "06", title: tr("灯塔与船"), artist: tr("林间乐队"), duration: 211, first: false) {}
            }
            .padding(.top, 18)
        }
    }

    /// 「接下来」标题行：右边「B 面 · 3 首」和「查看全部」（多于 3 首才有）。
    private func sectionHeader(_ title: String, count: Int, showAllCount: Int? = nil) -> some View {
        let total = showAllCount ?? count
        return HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
            Spacer(minLength: 6)
            if let summary = CassetteWidget.upNextSummary(count: count) {
                Text(summary)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(1)
            }
            if CassetteWidget.offersShowAll(count: total) {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { showAll.toggle() }
                } label: {
                    HStack(spacing: 2) {
                        Text(showAll ? tr("收起") : tr("查看全部"))
                        Image(systemName: showAll ? "chevron.up" : "chevron.right")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelSecondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.panelSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .glassPane(cornerRadius: 12)
    }

    // MARK: 机型分段

    private var modelPicker: some View {
        HStack(spacing: 12) {
            Text(tr("机型"))
                .font(.system(size: 14, weight: .semibold))
                .fixedSize()
            HStack(spacing: 2) {
                ForEach(CassetteModel.allCases, id: \.self) { option in
                    segment(option)
                }
            }
            .padding(3)
            .background(Capsule().fill(.panelFill))
            .overlay(Capsule().strokeBorder(.panelStroke, lineWidth: 0.6))
        }
    }

    private func segment(_ option: CassetteModel) -> some View {
        let on = option == model
        return Button {
            choose(option)
        } label: {
            Text(option.title)
                .font(.system(size: 13, weight: on ? .semibold : .medium))
                .foregroundStyle(on ? Color.panelPrimary : Color.panelSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background {
                    if on { Capsule().fill(.panelRaised).panelLift() }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func choose(_ option: CassetteModel) {
        guard !context.isPreview else { return }
        switch CassetteWidget.pick(option, current: CassetteModel.stored(config), unlocked: ProAccess.isUnlocked) {
        case .paywall:
            PaywallWindow.shared.show()
        case .unchanged:
            pickedModel = option
        case .apply:
            withAnimation(.snappy(duration: 0.2)) { pickedModel = option }
            // 写之前取一次存着的最新一份，免得盖掉面板打开后别处的改动。
            let latest = WidgetWriter.current(instance.id) ?? instance
            WidgetWriter.write(latest) { config in
                config = CassetteWidget.choosing(option, in: config)
            }
        }
    }

    // MARK: 来源列表

    private func sourcesPage(_ track: Playing?) -> some View {
        let players = context.isPreview ? [] : MusicService.shared.players
        let browser = context.isPreview ? nil : MusicNow.browserTrack(browsersEnabled: browsersEnabled)
        return VStack(alignment: .leading, spacing: 8) {
            if players.isEmpty && browser == nil {
                note(tr("没有开着的播放器"))
            }
            ForEach(players, id: \.source) { player in
                sourceRow(player, selected: track?.source == player.source && track?.isBrowser == false)
            }
            if let browser {
                HStack(spacing: 10) {
                    appIcon(browser.icon ?? AppCatalog.shared.icon(forBundleID: browser.sourceBundleID))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("\(browser.artist) 标签页")).font(.system(size: 14, weight: .semibold))
                        Text(tr("视频 · 只能播放暂停")).font(.system(size: 13)).foregroundStyle(.panelSecondary)
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 10)
                .frame(height: 50)
                .glassPane(cornerRadius: 12)
            }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("谁开始播放就切到谁")).font(.system(size: 14, weight: .semibold))
                    Text(tr("关掉后停在你选的来源")).font(.system(size: 13)).foregroundStyle(.panelSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Toggle("", isOn: Binding(get: { autoSwitch }, set: { setAutoSwitch($0) }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .accessibilityLabel(tr("谁开始播放就切到谁"))
            }
            .padding(.horizontal, 12)
            .frame(height: 54)
            .glassPane(cornerRadius: 12)
            .padding(.top, 4)
        }
        .padding(.top, 14)
    }

    private func sourceRow(_ player: MusicService.Player, selected: Bool) -> some View {
        let source = player.source
        let detail: String = if let track = player.track {
            track.isPlaying
                ? [track.title, track.artist].filter { !$0.isEmpty }.joined(separator: " · ")
                : tr("已暂停 · \(track.title)")
        } else {
            tr("开着，读不到曲目")
        }
        return Button {
            chooseSource(source)
        } label: {
            HStack(spacing: 10) {
                appIcon(AppCatalog.shared.icon(forBundleID: source.bundleID))
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.displayName).font(.system(size: 14, weight: .semibold))
                    Text(detail).font(.system(size: 13)).foregroundStyle(.panelSecondary)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(CassettePalette.coralBottom.panelReadable)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 50)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? Color.panelSelected : .clear))
            .glassPane(cornerRadius: 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func appIcon(_ image: NSImage?) -> some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.panelSelected)
                    .overlay(Image(systemName: "music.note").font(.system(size: 13, weight: .semibold)))
            }
        }
        .frame(width: 28, height: 28)
    }

    /// 点一个来源：显示它；自动切换关着时它就是固定的来源（和正在播放面板一样）。
    private func chooseSource(_ source: MusicSource) {
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

    // MARK: 没在播放 / 要授权

    private var idle: some View {
        let target = shownSource
        return VStack(spacing: 8) {
            Text(tr("没在播放"))
                .font(.system(size: 18, weight: .bold))
            Text(target.map { tr("在 \($0.displayName) 里放首歌，这里就会出现") } ?? tr("放首歌，这里就会出现"))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.panelSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let target, MusicService.isInstalled(target) {
                Button {
                    guard !context.isPreview else { return }
                    MusicService.shared.open(target)
                } label: {
                    Text(tr("打开 \(target.displayName)"))
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .padding(.horizontal, 22)
                        .frame(height: 38)
                }
                .buttonStyle(GlassKeyStyle(corner: 19))
                .fixedSize()
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
    }

    /// 唯一会弹系统「自动化」授权的地方，而且只在点了以后。
    private var connect: some View {
        VStack(spacing: 12) {
            machine(nil)
            Text(tr("码头需要你允许它读取音乐 App"))
                .font(.system(size: 14, weight: .semibold))
                .multilineTextAlignment(.center)
            Button {
                guard !context.isPreview else { return }
                MusicNow.requestPermission(browsersEnabled: browsersEnabled)
            } label: {
                Text(tr("连接"))
                    .font(.system(size: 14, weight: .bold))
                    .padding(.horizontal, 28)
                    .frame(height: 38)
            }
            .buttonStyle(GlassKeyStyle(coral: true, corner: 19))
            .fixedSize()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

// MARK: - 零件

/// 拖带子跳转：能不能拖、拖动中、松开时（都给 0...1 的位置）。
private struct SeekHandler {
    var enabled: Bool
    var changed: (Double) -> Void
    var ended: (Double) -> Void
}

private extension View {
    /// 在这块上横着拖或点一下跳到那里，位置按这块自己的宽算。不能拖时什么都不加，
    /// 点击照常落到下面。
    func seekable(_ handler: SeekHandler) -> some View {
        overlay {
            if handler.enabled {
                GeometryReader { geo in
                    let width = geo.size.width
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard width > 0 else { return }
                                handler.changed(min(1, max(0, value.location.x / width)))
                            }
                            .onEnded { value in
                                guard width > 0 else { return }
                                handler.ended(min(1, max(0, value.location.x / width)))
                            })
                }
                .help(tr("拖动跳到这里"))
            }
        }
    }
}

/// 玻璃吊牌：左边穿绳的小孔、珊瑚小竖条（在播时跳）、「来源：音乐」和展开箭头。
private struct SourceTag: View {
    var name: String
    var playing: Bool
    var open: Bool

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .strokeBorder(.panelTertiary, lineWidth: 1)
                .frame(width: 7, height: 7)
            PlayingBarsView(playing: playing, tint: CassettePalette.coralBottom, height: 12, visible: true)
            Text(tr("来源：\(name)"))
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            Image(systemName: open ? "chevron.up" : "chevron.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelSecondary)
        }
        .padding(.leading, 12)
        .padding(.trailing, 12)
        .frame(height: 32)
        .background(TagShape().fill(.panelRaised).panelLift())
        .overlay(TagShape().stroke(.panelStroke, lineWidth: 0.6))
        .contentShape(TagShape())
    }
}

/// 吊牌形状：右边圆角，左边两个角斜切。
private struct TagShape: Shape {
    func path(in rect: CGRect) -> Path {
        let cut = min(9, rect.height * 0.3)
        let r = min(8, rect.height * 0.25)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + cut, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + cut, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - cut))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cut))
        p.closeSubpath()
        return p
    }
}

/// 计数行两边的一卷带子：玻璃圆底上一卷茶色带盘，半径就是剩多少带。
private struct PackReel: View {
    var radius: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(.panelFill)
                .overlay(Circle().strokeBorder(.panelStroke, lineWidth: 0.6))
            Circle().fill(CassettePalette.tape).frame(width: radius * 2, height: radius * 2)
            Circle().fill(CassettePalette.hub).frame(width: 9, height: 9)
            Circle().fill(CassettePalette.hubHole).frame(width: 4, height: 4)
        }
        .frame(width: 38, height: 38)
        .animation(.linear(duration: MusicTile.pollInterval), value: radius)
        .accessibilityHidden(true)
    }
}

/// 玻璃推子：凹进去的轨道、浮起的玻璃帽子、下面一排刻度，右边数字。
private struct GlassFader: View {
    var value: Double
    var label: String
    var change: (Double, Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .fixedSize()
            GeometryReader { geo in
                let width = geo.size.width
                let v = min(max(value, 0), 1)
                let thumb: CGFloat = 20
                ZStack(alignment: .leading) {
                    // 轨道：凹槽，上沿一道暗边。
                    Capsule().fill(.panelTrack)
                        .overlay(Capsule().strokeBorder(.panelShade, lineWidth: 0.6))
                        .frame(height: 6)
                    Capsule().fill(.panelSecondary)
                        .frame(width: max(6, width * v), height: 6)
                    // 刻度。
                    HStack(spacing: 0) {
                        ForEach(0..<11, id: \.self) { i in
                            Rectangle().fill(.panelQuaternary)
                                .frame(width: 1, height: i % 5 == 0 ? 5 : 3)
                            if i < 10 { Spacer(minLength: 0) }
                        }
                    }
                    .padding(.horizontal, thumb / 2)
                    .offset(y: 11)
                    Circle()
                        .fill(.panelRaised)
                        .overlay(Circle().strokeBorder(.panelStroke, lineWidth: 0.8))
                        .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
                        .frame(width: thumb, height: thumb)
                        .offset(x: min(max(0, width * v - thumb / 2), width - thumb))
                }
                .frame(height: 24)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        guard width > 0 else { return }
                        change(min(1, max(0, drag.location.x / width)), false)
                    }
                    .onEnded { drag in
                        guard width > 0 else { return }
                        change(min(1, max(0, drag.location.x / width)), true)
                    })
            }
            .frame(height: 28)
            Text(verbatim: "\(Int((min(max(value, 0), 1) * 100).rounded()))")
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.panelSecondary)
                .frame(minWidth: 26, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(Text(verbatim: "\(Int((min(max(value, 0), 1) * 100).rounded()))%"))
        .accessibilityAdjustableAction { direction in
            let step = 0.05
            switch direction {
            case .increment: change(min(1, value + step), true)
            case .decrement: change(max(0, value - step), true)
            @unknown default: break
            }
        }
    }
}

/// 「接下来」的一行玻璃：曲序、歌名、歌手、时长；第一行左边一道珊瑚小竖条。整行点一下播放。
private struct UpNextRow: View {
    var number: String?
    var title: String
    var artist: String
    var duration: Double
    var first: Bool
    var action: () -> Void

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let number {
                    Text(verbatim: number)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.panelSecondary)
                        .fixedSize()
                }
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .layoutPriority(1)
                Text(artist)
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if hover {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.panelSecondary)
                } else if duration > 0 {
                    Text(MusicTime.clock(duration))
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(.panelSecondary)
                        .fixedSize()
                }
            }
            .padding(.leading, first ? 14 : 12)
            .padding(.trailing, 12)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(hover ? Color.panelSelected : .clear))
            .glassPane(cornerRadius: 11)
            .overlay(alignment: .leading) {
                if first {
                    Capsule().fill(CassettePalette.needle)
                        .frame(width: 3, height: 18)
                        .padding(.leading, 5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityLabel(tr("播放 \(title)"))
    }
}

// MARK: - 面板里的大机身

/// 大磁带：标签上沿印「A 歌名」和「1:42 / 4:05」（按实际字号盖在缩放后的外壳上，字不糊）。
private struct PanelTape: View {
    var track: CassetteTrack
    var visible: Bool

    var body: some View {
        let size = CassetteShell.size
        CassetteShell(track: track, visible: visible, labeled: true)
            .aspectRatio(size.width / size.height, contentMode: .fit)
            .overlay {
                GeometryReader { geo in
                    let s = geo.size.width / size.width
                    let strip = CassetteShell.labelStrip
                    HStack(spacing: 6) {
                        Text(verbatim: "A")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(CassettePalette.needle)
                        Text(track.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(CassettePalette.rgb(46, 36, 30))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 4)
                        if track.showsTime {
                            Text(verbatim: "\(MusicTime.clock(track.elapsed)) / \(MusicTime.clock(track.duration))")
                                .font(.system(size: 13, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(CassettePalette.rgb(70, 58, 50))
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(width: strip.width * s, height: strip.height * s)
                    .offset(x: strip.minX * s, y: strip.minY * s)
                }
            }
    }
}

/// 大随身听（上半）：小窗转轮、液晶（歌名和带长计数）、右边音量拨轮；下面带长进度条
/// （能拖），机身上印「A 面 · 自动翻面」和「音量」。
private struct PanelPortable: View {
    var track: CassetteTrack
    var visible: Bool
    var volume: Double?
    var seek: SeekHandler

    private let ink = CassettePalette.rgb(88, 78, 68)

    var body: some View {
        let casing = RoundedRectangle(cornerRadius: 18, style: .continuous)
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                PortableWindow(track: track, visible: visible)
                    .frame(width: 112, height: 72)
                PortableLCD(track: track, compact: false)
                    .frame(maxWidth: .infinity)
                    .frame(height: 72)
                wheel
            }
            ThinBar(progress: track.showsTime ? track.progress : 0,
                    track: CassettePalette.rgb(120, 104, 88, 0.3), fill: CassettePalette.coralBottom, height: 5)
                .frame(height: 16)
                .seekable(seek)
                .accessibilityLabel(tr("进度"))
            HStack {
                Text(tr("A 面 · 自动翻面"))
                Spacer()
                Text(tr("音量"))
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(ink)
        }
        .padding(12)
        .background(casing.fill(LinearGradient(colors: [CassettePalette.creamTop, CassettePalette.creamBottom],
                                               startPoint: .top, endPoint: .bottom)))
        .overlay(casing.strokeBorder(.white.opacity(0.55), lineWidth: 0.8).padding(1.5))
        .overlay(casing.strokeBorder(.black.opacity(0.14), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.22), radius: 6, y: 3)
    }

    /// 侧面的音量拨轮：一排横纹，珊瑚刻线停在音量的位置。
    private var wheel: some View {
        let level = volume ?? 0.5
        return ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(LinearGradient(colors: [CassettePalette.rgb(208, 198, 180), CassettePalette.rgb(236, 228, 214),
                                              CassettePalette.rgb(196, 186, 168)],
                                     startPoint: .leading, endPoint: .trailing))
            VStack(spacing: 3) {
                ForEach(0..<12, id: \.self) { _ in
                    Rectangle().fill(.black.opacity(0.16)).frame(height: 1)
                }
            }
            .padding(.vertical, 5)
            Capsule().fill(CassettePalette.coralBottom)
                .frame(height: 3)
                .padding(.horizontal, 2)
                .offset(y: 4 + (72 - 11) * CGFloat(1 - min(max(level, 0), 1)))
        }
        .frame(width: 16, height: 72)
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.black.opacity(0.18), lineWidth: 0.5))
        .accessibilityHidden(true)
    }
}

/// 大收录机（上半）：提手、左右喇叭、中间调台条（歌名，红指针就是进度，能拖）、
/// 磁带仓和铜旋钮（跟着音量转）。
private struct PanelBoombox: View {
    var track: CassetteTrack
    var visible: Bool
    var volume: Double?
    var seek: SeekHandler

    var body: some View {
        let casing = RoundedRectangle(cornerRadius: 18, style: .continuous)
        HStack(spacing: 6) {
            Speaker(diameter: 72, playing: track.isPlaying, visible: visible)
            VStack(spacing: 7) {
                TuningStrip(track: track, height: 48, titleSize: 15, stacked: true)
                    .seekable(seek)
                    .accessibilityLabel(tr("进度"))
                BoomboxDeck(track: track, visible: visible)
                    .frame(height: 24)
                CopperKnob(diameter: 26, level: volume ?? 0.5)
            }
            .frame(maxWidth: .infinity)
            Speaker(diameter: 72, playing: track.isPlaying, visible: visible)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
        .background(casing.fill(LinearGradient(colors: [CassettePalette.oliveTop, CassettePalette.oliveBottom],
                                               startPoint: .top, endPoint: .bottom)))
        .overlay(casing.strokeBorder(CassettePalette.rgb(220, 230, 190, 0.3), lineWidth: 0.8).padding(1.5))
        .overlay(casing.strokeBorder(.black.opacity(0.25), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
        .padding(.top, 12)
        .overlay(alignment: .top) {
            // 提手。
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(CassettePalette.olivePlate, lineWidth: 4)
                .frame(width: 130, height: 20)
                .mask(Rectangle().frame(height: 13).frame(maxHeight: .infinity, alignment: .top))
        }
    }
}
