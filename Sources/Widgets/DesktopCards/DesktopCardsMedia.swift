import AppKit
import SwiftUI

// MARK: - 钉在桌面 · 媒体组
//
// 正在播放、播客、收音机、复古卡带、录音、麦克风、环境音、应用音量在桌面上的专属布局，
// 小 160×160 / 中 340×160 / 大 340×340 各排一套：一眼看清、播放暂停这些常用操作直接点、
// 不截断、不滚动。和扩展栏读同一个服务、写同一份配置，两边同步。
//
// - 小号：一个核心（封面 / 台名 / 状态）加一个能点的大键。
// - 中号：核心加次要信息和一排键（进度、上一首下一首、快退快进）。
// - 大号：核心、完整的控制，再加列表（收藏电台、单集、最近录音、正在用麦克风的应用）
//   或操作区（环境音的声音格子、定时和音量）。
//
// 每档放哪些键、列表几行、电台列表从哪台开始这些判断在 Core 的 `DesktopCardsMediaPlan`。
// 卡片的玻璃底和悬停操作条由 `DesktopCard` 画，这里只画内容；字最小 13pt，颜色都用面板
// 语义色（跟着卡片的浅色 / 深色），主题色从 `panelTint` 读。Pro 小组件没解锁照旧盖小锁。

@MainActor
enum DesktopCardsMedia {
    /// 分发入口：媒体组的小组件返回专属布局，其余返回 nil 走通用逻辑。
    static func view(for widget: WidgetInstance, size: DesktopPinSize, now: Date) -> AnyView? {
        guard DesktopCardsMediaPlan.handles(widget.kind) else { return nil }
        let content: AnyView
        switch widget.kind {
        case .music: content = AnyView(DMMusicCard(widget: widget, size: size))
        case .cassette: content = AnyView(DMCassetteCard(widget: widget, size: size))
        case .podcast: content = AnyView(DMPodcastCard(widget: widget, size: size))
        case .radio: content = AnyView(DMRadioCard(widget: widget, size: size))
        case .recorder: content = AnyView(DMRecorderCard(widget: widget, size: size, now: now))
        case .microphone: content = AnyView(DMMicrophoneCard(widget: widget, size: size, now: now))
        case .ambient: content = AnyView(DMAmbientCard(widget: widget, size: size))
        case .appVolume: content = AnyView(DMAppVolumeCard(widget: widget, size: size))
        default: return nil
        }
        return AnyView(content.proLocked(widget))
    }
}

// MARK: - 共用小件

/// 布局常量：卡片内边距、最小字号。
private enum DM {
    static let pad: CGFloat = 14
    static let small: CGFloat = 13

    static func accent(_ tint: PanelTint?, own: Color) -> Color { tint.accent(or: own) }
}

/// 中号、大号左上角的小标题：图标 + 小组件名，右边可放一句状态。
private struct DMHeader: View {
    var symbol: String
    var title: String
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: DM.small, weight: .semibold))
            Text(title)
                .font(.system(size: DM.small, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 4)
            if let trailing {
                Text(trailing)
                    .font(.system(size: DM.small))
                    .lineLimit(1)
                    .monospacedDigit()
            }
        }
        .foregroundStyle(Color.panelSecondary)
    }
}

/// 圆形控制键。主键（播放暂停）实心：没选主题色时是反色（浅色下深底白字、深色下白底深字），
/// 选了主题色用主题色；次键是薄玻璃小圆。点击区域就是整个圆，不小于 30pt。
private struct DMRoundKey: View {
    var symbol: String
    var label: String
    var size: CGFloat
    var prominent = false
    var fill: Color? = nil
    var ink: Color? = nil
    var action: (() -> Void)?

    var body: some View {
        Button { action?() } label: {
            ZStack {
                if prominent {
                    Circle().fill(fill ?? Color.panelPrimary)
                } else {
                    Circle().fill(Color.panelFill)
                    Circle().strokeBorder(Color.panelStroke, lineWidth: 0.5)
                }
                Image(systemName: symbol)
                    .playPauseMorph(symbol)
                    .font(.system(size: max(DM.small, size * (prominent ? 0.4 : 0.38)), weight: .bold))
                    .foregroundStyle(prominent ? (ink ?? Color.panelOnPrimary) : Color.panelPrimary)
                    .offset(x: symbol == "play.fill" ? size * 0.03 : 0)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .opacity(action == nil ? 0.45 : 1)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// 进度条加两头的时间（13pt）。`onSeek` 不是 nil 时点条上任一处跳过去。
private struct DMProgress: View {
    var elapsed: Double
    var duration: Double
    var tint: Color
    var onSeek: ((Double) -> Void)? = nil

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.panelTrack)
                    Capsule().fill(tint)
                        .frame(width: max(0, geo.size.width
                                * DesktopCardsMediaPlan.fraction(elapsed: elapsed, duration: duration)))
                }
                .frame(height: 5)
                .frame(maxHeight: .infinity)
                .contentShape(.rect)
                .onTapGesture { location in
                    guard let onSeek,
                          let target = DesktopCardsMediaPlan.seekTarget(x: location.x, width: geo.size.width,
                                                                         duration: duration) else { return }
                    onSeek(target)
                }
            }
            .frame(height: 12)
            HStack {
                Text(MusicTime.clock(elapsed))
                Spacer(minLength: 4)
                Text("-" + MusicTime.clock(max(0, duration - elapsed)))
            }
            .font(.system(size: DM.small, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(Color.panelSecondary)
            .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("进度"))
        .accessibilityValue(Text(verbatim: "\(MusicTime.clock(elapsed)) / \(MusicTime.clock(duration))"))
    }
}

/// 封面方块：有封面铺封面，没有就画来源 App 的图标，都没有画音符。
private struct DMArtwork: View {
    var image: NSImage?
    var fallback: NSImage?
    var symbol = "music.note"
    var side: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: side * 0.16, style: .continuous)
        ZStack {
            shape.fill(Color.panelFill)
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
            } else if let fallback {
                Image(nsImage: fallback).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
                    .padding(side * 0.18)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: side * 0.4, weight: .medium))
                    .foregroundStyle(Color.panelSecondary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.panelStroke, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
        .accessibilityHidden(true)
    }
}

/// 空状态：一个大图标、一句话、一句说明，可带一个按钮（「连接」「打开设置」）。
private struct DMEmpty: View {
    var symbol: String
    var title: String
    var caption: String?
    var size: DesktopPinSize
    var button: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: size == .small ? 28 : 34, weight: .medium))
                .foregroundStyle(Color.panelSecondary)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.panelPrimary)
                .lineLimit(1)
            if let caption, size != .small || button == nil {
                Text(caption)
                    .font(.system(size: DM.small))
                    .foregroundStyle(Color.panelSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(size == .large ? 3 : 2)
            }
            if let button, let action {
                Button(action: action) {
                    Text(button)
                        .font(.system(size: DM.small, weight: .semibold))
                        .foregroundStyle(Color.panelOnPrimary)
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(Capsule().fill(Color.panelPrimary))
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DM.pad)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 一排播放键：按 Core 给的顺序摆，主键大一号。
private struct DMKeyRow: View {
    var keys: [DesktopCardsMediaPlan.Key]
    var playing: Bool
    var main: CGFloat
    var side: CGFloat
    var fill: Color?
    var ink: Color?
    var backSymbol = "gobackward.15"
    var forwardSymbol = "goforward.15"
    var previousLabel = tr("上一首")
    var nextLabel = tr("下一首")
    var perform: (DesktopCardsMediaPlan.Key) -> Void
    var enabled: (DesktopCardsMediaPlan.Key) -> Bool = { _ in true }

    var body: some View {
        HStack(spacing: side * 0.42) {
            ForEach(keys, id: \.self) { key in
                switch key {
                case .back:
                    DMRoundKey(symbol: backSymbol, label: tr("后退"), size: side * 0.9,
                               action: enabled(key) ? { perform(key) } : nil)
                case .previous:
                    DMRoundKey(symbol: "backward.end.fill", label: previousLabel, size: side,
                               action: enabled(key) ? { perform(key) } : nil)
                case .playPause:
                    DMRoundKey(symbol: playing ? "pause.fill" : "play.fill", label: playing ? tr("暂停") : tr("播放"),
                               size: main, prominent: true, fill: fill, ink: ink,
                               action: enabled(key) ? { perform(key) } : nil)
                case .next:
                    DMRoundKey(symbol: "forward.end.fill", label: nextLabel, size: side,
                               action: enabled(key) ? { perform(key) } : nil)
                case .forward:
                    DMRoundKey(symbol: forwardSymbol, label: tr("前进"), size: side * 0.9,
                               action: enabled(key) ? { perform(key) } : nil)
                }
            }
        }
    }
}

/// SF Symbols 只有几种带数字的快进快退图标，别的秒数用不带数字的箭头。
private func skipSymbol(_ base: String, _ seconds: Int) -> String {
    let numbered: Set<Int> = [5, 10, 15, 30, 45, 60, 75, 90]
    return numbered.contains(seconds) ? "\(base).\(seconds)" : base
}

// MARK: - 正在播放

/// 正在播放：读和扩展栏卡片同一个「当前显示来源」，控制调同一套服务。
private struct DMMusicCard: View {
    var widget: WidgetInstance
    var size: DesktopPinSize

    @Environment(\.panelTint) private var panelTint

    private var config: WidgetConfig { widget.config }
    private var browsersEnabled: Bool { config.bool("browsers", default: true) }
    private var skipSeconds: Int { max(1, config.int("skip", default: 15)) }

    private var browserState: MusicCardChoice.Browser? {
        guard browsersEnabled, let track = BrowserMedia.shared.track else { return nil }
        return MusicCardChoice.Browser(hasTrack: true, isPlaying: track.isPlaying)
    }

    var body: some View {
        Group {
            if let track = MusicNow.playing(browsersEnabled: browsersEnabled) {
                switch size {
                case .small: small(track)
                case .medium: medium(track)
                case .large: large(track)
                }
            } else if MusicNow.needsPermission(browsersEnabled: browsersEnabled) {
                DMEmpty(symbol: "music.note", title: tr("正在播放"), caption: tr("连接后读取正在播放的歌曲"),
                        size: size, button: tr("连接")) {
                    MusicNow.requestPermission(browsersEnabled: browsersEnabled)
                }
            } else {
                DMEmpty(symbol: MusicService.shared.hasPlayer ? "music.note" : "music.note.list",
                        title: tr("未在播放"), caption: tr("播放器开始播放后这里显示歌曲"), size: size)
            }
        }
        .onAppear {
            MusicService.shared.configure(config)
            MusicService.shared.start()
            BrowserMedia.shared.enabled = browsersEnabled
            BrowserMedia.shared.start()
        }
        .onChange(of: browserState) { _, _ in MusicService.shared.reconcile() }
    }

    private var fill: Color? { panelTint?.color }
    private var ink: Color? { panelTint?.ink }
    private var barTint: Color { panelTint.map { $0.color.panelGraphic } ?? Color.panelPrimary }

    private func keys(_ track: Playing) -> [DesktopCardsMediaPlan.Key] {
        DesktopCardsMediaPlan.musicKeys(size, skips: track.hasSkipControls && track.source != nil,
                                        canSeek: track.canSeek && !track.isBrowser,
                                        previous: config.bool("previous", default: true),
                                        next: config.bool("next", default: true))
    }

    private func perform(_ key: DesktopCardsMediaPlan.Key, _ track: Playing) {
        switch key {
        case .playPause: MusicNow.toggle(track)
        case .previous: if let source = track.source { MusicService.shared.previous(on: source) }
        case .next: if let source = track.source { MusicService.shared.next(on: source) }
        case .back: if let source = track.source { MusicService.shared.skip(on: source, by: -Double(skipSeconds)) }
        case .forward: if let source = track.source { MusicService.shared.skip(on: source, by: Double(skipSeconds)) }
        }
    }

    private func keyRow(_ track: Playing, main: CGFloat, side: CGFloat) -> some View {
        DMKeyRow(keys: keys(track), playing: track.isPlaying, main: main, side: side, fill: fill, ink: ink,
                 backSymbol: skipSymbol("gobackward", skipSeconds),
                 forwardSymbol: skipSymbol("goforward", skipSeconds)) { perform($0, track) }
    }

    private func seek(_ track: Playing) -> ((Double) -> Void)? {
        guard !track.isBrowser, track.canSeek, let source = track.source else { return nil }
        return { MusicService.shared.seek(on: source, to: $0) }
    }

    private func titleBlock(_ track: Playing, title: CGFloat, lines: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(track.title)
                .font(.system(size: title, weight: .semibold))
                .foregroundStyle(Color.panelPrimary)
                .lineLimit(lines)
                .truncationMode(.tail)
            HStack(spacing: 5) {
                PlayingBarsView(playing: track.isPlaying, tint: barTint, height: 11, visible: true)
                Text(track.artist)
                    .font(.system(size: DM.small))
                    .foregroundStyle(Color.panelSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    // 小：封面 + 播放键，下面歌名、歌手。
    private func small(_ track: Playing) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                DMArtwork(image: track.artwork, fallback: MusicNow.icon(track), side: 68)
                Spacer(minLength: 6)
                DMRoundKey(symbol: track.isPlaying ? "pause.fill" : "play.fill",
                           label: track.isPlaying ? tr("暂停") : tr("播放"), size: 44, prominent: true,
                           fill: fill, ink: ink) { MusicNow.toggle(track) }
            }
            Spacer(minLength: 8)
            titleBlock(track, title: 15, lines: 1)
        }
        .padding(DM.pad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // 中：大封面在左，右边歌名、歌手、进度和一排键。
    private func medium(_ track: Playing) -> some View {
        HStack(spacing: 14) {
            DMArtwork(image: track.artwork, fallback: MusicNow.icon(track), side: 132)
            VStack(alignment: .leading, spacing: 0) {
                titleBlock(track, title: 17, lines: 1)
                Spacer(minLength: 6)
                if DesktopCardsMediaPlan.showsProgress(size, duration: track.duration) {
                    DMProgress(elapsed: track.elapsed, duration: track.duration, tint: barTint, onSeek: seek(track))
                    Spacer(minLength: 6)
                }
                keyRow(track, main: 42, side: 32)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(DM.pad)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // 大：封面和曲目信息、能点的进度条、五个键。
    private func large(_ track: Playing) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                DMArtwork(image: track.artwork, fallback: MusicNow.icon(track), side: 136)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if let icon = MusicNow.icon(track) {
                            Image(nsImage: icon).resizable().interpolation(.high).frame(width: 16, height: 16)
                                .accessibilityHidden(true)
                        }
                        if let name = track.source?.displayName {
                            Text(name)
                                .font(.system(size: DM.small, weight: .medium))
                                .foregroundStyle(Color.panelSecondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    Text(track.title)
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(Color.panelPrimary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                    HStack(spacing: 5) {
                        PlayingBarsView(playing: track.isPlaying, tint: barTint, height: 12, visible: true)
                        Text(track.artist)
                            .font(.system(size: 15))
                            .foregroundStyle(Color.panelSecondary)
                            .lineLimit(1)
                    }
                    if !track.album.isEmpty {
                        Text(track.album)
                            .font(.system(size: DM.small))
                            .foregroundStyle(Color.panelTertiary)
                            .lineLimit(1)
                    }
                }
                .frame(height: 136, alignment: .topLeading)
            }
            Spacer(minLength: 10)
            if DesktopCardsMediaPlan.showsProgress(size, duration: track.duration) {
                DMProgress(elapsed: track.elapsed, duration: track.duration, tint: barTint, onSeek: seek(track))
                Spacer(minLength: 10)
            }
            keyRow(track, main: 56, side: 40)
                .frame(maxWidth: .infinity)
        }
        .padding(DM.pad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - 复古卡带

/// 复古卡带：机身是放在玻璃上的实物（颜色写死，和扩展栏一样），键用卡带自己的玻璃键帽，
/// 播放键珊瑚色。小号只放磁带；中号、大号按设置的机型（磁带 / 随身听 / 收录机）画一条机身。
private struct DMCassetteCard: View {
    var widget: WidgetInstance
    var size: DesktopPinSize

    private var config: WidgetConfig { widget.config }
    private var browsersEnabled: Bool { config.bool("browsers", default: true) }
    private var model: CassetteModel { CassetteModel.stored(config) }

    var body: some View {
        let playing = MusicNow.playing(browsersEnabled: browsersEnabled)
        let deck = MusicNow.cassetteTrack(playing, preview: false)
        let actions = connectOrActions(playing)
        Group {
            switch size {
            case .small: small(deck, actions)
            case .medium: medium(deck, actions, playing)
            case .large: large(deck, actions, playing)
            }
        }
        .padding(DM.pad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            MusicService.shared.configure(config)
            MusicService.shared.start()
            BrowserMedia.shared.enabled = browsersEnabled
            BrowserMedia.shared.start()
        }
    }

    private func connectOrActions(_ track: Playing?) -> CassetteActions {
        if track == nil, MusicNow.needsPermission(browsersEnabled: browsersEnabled) {
            let browsers = browsersEnabled
            return CassetteActions(toggle: { MusicNow.requestPermission(browsersEnabled: browsers) })
        }
        return MusicNow.actions(track, config: config, preview: false)
    }

    private func titleLines(_ deck: CassetteTrack, title: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(deck.title)
                .font(.system(size: title, weight: .semibold))
                .foregroundStyle(Color.panelPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            if !deck.artist.isEmpty {
                Text(deck.artist)
                    .font(.system(size: DM.small))
                    .foregroundStyle(Color.panelSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private func keys(_ deck: CassetteTrack, _ actions: CassetteActions, size key: CGFloat, all: Bool) -> some View {
        HStack(spacing: key * 0.18) {
            if all {
                GlassKey(symbol: "backward.end.fill", label: tr("上一首"), glyph: key * 0.36,
                         corner: key * 0.3, action: actions.previous)
                    .frame(width: key, height: key)
            }
            GlassKey(symbol: deck.isPlaying ? "pause.fill" : "play.fill",
                     label: deck.isPlaying ? tr("暂停") : tr("播放"), coral: true, latched: deck.isPlaying,
                     glyph: key * 0.4, corner: key * 0.3, action: actions.toggle)
                .frame(width: key, height: key)
            if all {
                GlassKey(symbol: "forward.end.fill", label: tr("下一首"), glyph: key * 0.36,
                         corner: key * 0.3, action: actions.next)
                    .frame(width: key, height: key)
            }
        }
    }

    // 小：一盒磁带，下面歌名和珊瑚播放键。
    private func small(_ deck: CassetteTrack, _ actions: CassetteActions) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CassetteShell(track: deck, visible: true, simplified: true)
                .frame(width: 124, height: 124 * CassetteShell.size.height / CassetteShell.size.width)
                .frame(maxWidth: .infinity)
            HStack(spacing: 8) {
                titleLines(deck, title: 15)
                    .frame(maxWidth: .infinity, alignment: .leading)
                keys(deck, actions, size: 34, all: false)
            }
        }
    }

    // 中：一条机身，下面歌名歌手、细进度和三个键。
    private func medium(_ deck: CassetteTrack, _ actions: CassetteActions, _ track: Playing?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            machine(deck, height: 66)
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    titleLines(deck, title: 15)
                    if deck.showsTime {
                        ThinBar(progress: deck.progress, track: Color.panelTrack, fill: CassettePalette.needle,
                                height: 4)
                            .accessibilityHidden(true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                keys(deck, actions, size: 36, all: track?.hasSkipControls ?? false)
            }
        }
    }

    // 大：大机身，下面歌名、进度和两头时间、三个大键。
    private func large(_ deck: CassetteTrack, _ actions: CassetteActions, _ track: Playing?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            machine(deck, height: 136)
            Spacer(minLength: 12)
            VStack(alignment: .leading, spacing: 3) {
                Text(deck.title)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Color.panelPrimary)
                    .lineLimit(1)
                if !deck.artist.isEmpty {
                    Text(deck.artist)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.panelSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 10)
            if deck.showsTime {
                DMProgress(elapsed: deck.elapsed, duration: deck.duration, tint: CassettePalette.needle)
                Spacer(minLength: 10)
            }
            keys(deck, actions, size: 48, all: track?.hasSkipControls ?? false)
                .frame(maxWidth: .infinity)
        }
    }

    /// 机身横条：磁带居中摆一盒；随身听奶油机身（小窗转轮 + 灰绿液晶）；收录机苔绿机身
    /// （两只喇叭夹着调台条和磁带仓）。
    @ViewBuilder
    private func machine(_ deck: CassetteTrack, height: CGFloat) -> some View {
        switch model {
        case .tape:
            CassetteShell(track: deck, visible: true)
                .frame(width: height * CassetteShell.size.width / CassetteShell.size.height, height: height)
                .frame(maxWidth: .infinity)
        case .portable:
            let casing = RoundedRectangle(cornerRadius: 12, style: .continuous)
            HStack(spacing: 8) {
                PortableWindow(track: deck, visible: true)
                    .frame(width: (height - 12) * 1.6, height: height - 12)
                PortableLCD(track: deck, compact: height < 100)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, height < 100 ? 6 : 14)
            }
            .padding(.horizontal, 6)
            .frame(height: height)
            .background(casing.fill(LinearGradient(colors: [CassettePalette.creamTop, CassettePalette.creamBottom],
                                                   startPoint: .top, endPoint: .bottom)))
            .overlay(casing.strokeBorder(.white.opacity(0.5), lineWidth: 0.6).padding(1))
            .overlay(casing.strokeBorder(.black.opacity(0.16), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.22), radius: 3, y: 2)
        case .boombox:
            let casing = RoundedRectangle(cornerRadius: 12, style: .continuous)
            let speaker = height - 12
            HStack(spacing: 6) {
                Speaker(diameter: speaker, playing: deck.isPlaying, visible: true)
                VStack(spacing: height * 0.08) {
                    TuningStrip(track: deck, height: max(22, height * 0.34), titleSize: height < 100 ? 13 : 15)
                    HStack(spacing: 6) {
                        BoomboxDeck(track: deck, visible: true)
                            .frame(height: height * 0.26)
                        CopperKnob(diameter: height * 0.24)
                    }
                }
                .frame(maxWidth: .infinity)
                Speaker(diameter: speaker, playing: deck.isPlaying, visible: true)
            }
            .padding(.horizontal, 6)
            .frame(height: height)
            .background(casing.fill(LinearGradient(colors: [CassettePalette.oliveTop, CassettePalette.oliveBottom],
                                                   startPoint: .top, endPoint: .bottom)))
            .overlay(casing.strokeBorder(CassettePalette.rgb(220, 230, 190, 0.3), lineWidth: 0.6).padding(1))
            .overlay(casing.strokeBorder(.black.opacity(0.25), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
        }
    }
}

// MARK: - 播客

/// 播客：这张卡片选的节目，正在放的那一集或最新一集；大号再列 3 个单集，点一下就放。
private struct DMPodcastCard: View {
    var widget: WidgetInstance
    var size: DesktopPinSize

    @Environment(\.panelTint) private var panelTint

    private var player: PodcastPlayer { PodcastPlayer.shared }
    private var service: PodcastService { PodcastService.shared }
    private var show: PodcastShow? { PodcastRemote.show(for: widget) }

    private var episode: PodcastEpisode? {
        guard let show else { return nil }
        if player.showID == show.id, let current = player.episode { return current }
        return show.episodes.first
    }

    private var isCurrent: Bool { episode.map { player.isCurrent($0) } ?? false }
    private var playing: Bool { isCurrent && player.isPlaying }
    private var unheard: Int { service.library.unheardCount }

    private var accent: Color { DM.accent(panelTint, own: PodcastCover.accent) }
    private var ink: Color { panelTint.ink(or: .white) }

    private var caption: String {
        guard let show else { return "" }
        if let episode, player.isCurrent(episode) {
            if player.problem != nil { return tr("播放失败") }
            if player.isBuffering, player.isPlaying { return tr("正在缓冲…") }
            if player.isPlaying,
               let chapter = PodcastChapters.current(PodcastRemote.chapters(for: episode), at: player.position) {
                return chapter.title
            }
            return player.isPlaying ? tr("正在播放") : tr("已暂停")
        }
        if service.problems[show.id] != nil, show.episodes.isEmpty { return tr("暂时连不上小宇宙") }
        return episode == nil ? tr("还没有单集") : tr("最新单集")
    }

    var body: some View {
        Group {
            if let show {
                switch size {
                case .small: small(show)
                case .medium: medium(show)
                case .large: large(show)
                }
            } else {
                DMEmpty(symbol: "mic.fill", title: tr("添加订阅"), caption: tr("在面板中粘贴小宇宙链接"), size: size)
            }
        }
    }

    private func toggle(_ show: PodcastShow) {
        guard let episode, episode.audioURL != nil else { return }
        player.toggle(episode, show: show.id)
    }

    private func cover(_ show: PodcastShow, side: CGFloat) -> some View {
        PodcastCover(url: show.imageURL, size: side)
            .overlay(alignment: .bottomLeading) {
                if isCurrent {
                    PlayingBarsView(playing: playing, tint: .white, height: max(11, side * 0.18), visible: true)
                        .padding(5)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.black.opacity(0.4)))
                        .padding(6)
                }
            }
            .overlay(alignment: .topTrailing) {
                if unheard > 0 {
                    Text(unheard > 9 ? "9+" : "\(unheard)")
                        .font(.system(size: DM.small, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 22, minHeight: 22)
                        .background(Capsule().fill(Color(hex: "#FF3B30")))
                        .offset(x: 6, y: -6)
                        .accessibilityLabel(tr("\(unheard) 个新单集"))
                }
            }
            .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
    }

    private func playKey(_ show: PodcastShow, size key: CGFloat) -> some View {
        DMRoundKey(symbol: playing ? "pause.fill" : "play.fill", label: playing ? tr("暂停") : tr("播放"),
                   size: key, prominent: true, fill: accent, ink: ink,
                   action: episode?.audioURL == nil ? nil : { toggle(show) })
    }

    private func keyRow(_ show: PodcastShow, main: CGFloat, side: CGFloat) -> some View {
        DMKeyRow(keys: DesktopCardsMediaPlan.podcastKeys(size, current: isCurrent), playing: playing,
                 main: main, side: side, fill: accent, ink: ink,
                 backSymbol: "gobackward.15", forwardSymbol: "goforward.30") { key in
            switch key {
            case .back: player.skip(by: -PodcastPlayback.backSeconds)
            case .forward: player.skip(by: PodcastPlayback.forwardSeconds)
            default: toggle(show)
            }
        } enabled: { key in
            key == .playPause ? episode?.audioURL != nil : true
        }
    }

    private var duration: Double {
        guard let episode else { return 0 }
        return isCurrent && player.duration > 0 ? player.duration : Double(episode.duration)
    }

    // 小：封面 + 播放键，下面节目名和这一集。
    private func small(_ show: PodcastShow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                cover(show, side: 64)
                Spacer(minLength: 6)
                playKey(show, size: 44)
            }
            Spacer(minLength: 8)
            Text(show.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.panelPrimary)
                .lineLimit(1)
            Text(episode?.title ?? caption)
                .font(.system(size: DM.small))
                .foregroundStyle(Color.panelSecondary)
                .lineLimit(1)
        }
        .padding(DM.pad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // 中：大封面在左，右边节目、单集标题、进度和后退 / 播放 / 前进。
    private func medium(_ show: PodcastShow) -> some View {
        HStack(spacing: 14) {
            cover(show, side: 132)
            VStack(alignment: .leading, spacing: 2) {
                Text(show.title)
                    .font(.system(size: DM.small, weight: .medium))
                    .foregroundStyle(Color.panelSecondary)
                    .lineLimit(1)
                Text(episode?.title ?? caption)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.panelPrimary)
                    .lineLimit(isCurrent && duration > 0 ? 1 : 2)
                Spacer(minLength: 4)
                if isCurrent, DesktopCardsMediaPlan.showsProgress(size, duration: duration) {
                    DMProgress(elapsed: player.position, duration: duration, tint: accent.panelGraphic) {
                        player.seek(to: $0)
                    }
                    Spacer(minLength: 4)
                } else {
                    Text(caption)
                        .font(.system(size: DM.small))
                        .foregroundStyle(Color.panelSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                }
                keyRow(show, main: 42, side: 32)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(DM.pad)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // 大：封面、单集和进度、控制，下面最新 3 个单集。
    private func large(_ show: PodcastShow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                cover(show, side: 80)
                VStack(alignment: .leading, spacing: 2) {
                    Text(show.title)
                        .font(.system(size: DM.small, weight: .medium))
                        .foregroundStyle(Color.panelSecondary)
                        .lineLimit(1)
                    Text(episode?.title ?? caption)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.panelPrimary)
                        .lineLimit(2)
                    Text(caption)
                        .font(.system(size: DM.small))
                        .foregroundStyle(Color.panelSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if isCurrent, DesktopCardsMediaPlan.showsProgress(size, duration: duration) {
                DMProgress(elapsed: player.position, duration: duration, tint: accent.panelGraphic) {
                    player.seek(to: $0)
                }
                Spacer(minLength: 8)
            }
            keyRow(show, main: 46, side: 34)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 10)
            Text(tr("最新单集"))
                .font(.system(size: DM.small, weight: .semibold))
                .foregroundStyle(Color.panelSecondary)
            Spacer(minLength: 4)
            let rows = DesktopCardsMediaPlan.listRows(.podcast, size: size)
            VStack(spacing: 2) {
                ForEach(Array(show.episodes.prefix(rows))) { item in
                    episodeRow(item, show: show)
                }
            }
        }
        .padding(DM.pad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func episodeRow(_ item: PodcastEpisode, show: PodcastShow) -> some View {
        let current = player.isCurrent(item)
        let on = current && player.isPlaying
        return Button {
            guard item.audioURL != nil else { return }
            player.toggle(item, show: show.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: on ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(current ? accent.panelReadable : Color.panelSecondary)
                Text(item.title)
                    .font(.system(size: DM.small, weight: current ? .semibold : .regular))
                    .foregroundStyle(Color.panelPrimary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if item.duration > 0 {
                    Text(MusicTime.clock(Double(item.duration)))
                        .font(.system(size: DM.small))
                        .monospacedDigit()
                        .foregroundStyle(Color.panelTertiary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background {
                if current { RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.panelSelected) }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(item.audioURL == nil)
        .help(item.title)
    }
}

// MARK: - 收音机

/// 收音机：调到的台、上一台 / 播放 / 下一台；大号列 4 台收藏，点一下切过去播放。
/// 桌面上统一画液态玻璃的经典样子（皮肤是扩展栏卡片的外观）。
private struct DMRadioCard: View {
    var widget: WidgetInstance
    var size: DesktopPinSize

    @Environment(\.panelTint) private var panelTint

    private var player: RadioPlayer { RadioPlayer.shared }
    private var stations: [RadioStation] { RadioDial.stations(widget.config) }
    private var index: Int { RadioDial.index(widget.config, count: stations.count) }
    private var station: RadioStation? { stations.isEmpty ? nil : stations[index] }
    private var volume: Double { widget.config.double("volume", default: 60) }
    private var playing: Bool { player.plays(station) }

    private var accent: Color { DM.accent(panelTint, own: RadioIcon.glow) }
    private var ink: Color { panelTint.ink(or: .white) }

    private var caption: String {
        guard playing else { return tr("已暂停") }
        if player.problem != nil { return tr("正在重新连接") }
        if player.isBuffering { return tr("正在连接…") }
        return player.nowTitle ?? tr("正在收听")
    }

    private var channel: String { RadioDial.channelOfTotal(index, count: stations.count) }

    var body: some View {
        Group {
            if let station {
                switch size {
                case .small: small(station)
                case .medium: medium(station)
                case .large: large(station)
                }
            } else {
                DMEmpty(symbol: "radio", title: tr("收音机"), caption: tr("在面板中添加电台"), size: size)
            }
        }
    }

    private func toggle(_ station: RadioStation) {
        player.toggle(station, volume: volume, stations: stations, owner: widget.id)
    }

    private func perform(_ key: DesktopCardsMediaPlan.Key, _ station: RadioStation) {
        switch key {
        case .previous: RadioRemote.tune(widget, to: RadioDial.previous(index, count: stations.count))
        case .next: RadioRemote.tune(widget, to: RadioDial.next(index, count: stations.count))
        default: toggle(station)
        }
    }

    private func keyRow(_ station: RadioStation, main: CGFloat, side: CGFloat) -> some View {
        DMKeyRow(keys: DesktopCardsMediaPlan.radioKeys(size, stations: stations.count), playing: playing,
                 main: main, side: side, fill: accent, ink: ink,
                 previousLabel: tr("上一台"), nextLabel: tr("下一台")) { perform($0, station) }
    }

    private func name(_ station: RadioStation, size font: CGFloat) -> some View {
        Text(station.name)
            .font(.system(size: font, weight: .bold))
            .foregroundStyle(Color.panelPrimary)
            .lineLimit(1)
            .minimumScaleFactor(max(DM.small / font, 0.8))
    }

    private func statusLine(lines: Int = 1) -> some View {
        Text(caption)
            .font(.system(size: DM.small, weight: .medium))
            .foregroundStyle(playing && player.problem != nil ? Color(hex: PaletteColor.orange.hex).panelReadable
                                                              : Color.panelSecondary)
            .lineLimit(lines)
    }

    // 小：收音机图标 + 播放键，下面台名和正在播的节目。
    private func small(_ station: RadioStation) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                RadioIcon(size: 60, playing: playing)
                Spacer(minLength: 6)
                DMRoundKey(symbol: playing ? "pause.fill" : "play.fill", label: playing ? tr("暂停") : tr("播放"),
                           size: 44, prominent: true, fill: accent, ink: ink) { toggle(station) }
            }
            Spacer(minLength: 8)
            name(station, size: 15)
            statusLine()
        }
        .padding(DM.pad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // 中：大图标在左，右边台名、节目、频道和三个键。
    private func medium(_ station: RadioStation) -> some View {
        HStack(spacing: 16) {
            RadioIcon(size: 112, playing: playing)
                .frame(width: 120)
            VStack(alignment: .leading, spacing: 3) {
                name(station, size: 19)
                statusLine(lines: 2)
                Text(channel)
                    .font(.system(size: DM.small))
                    .monospacedDigit()
                    .foregroundStyle(Color.panelTertiary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                keyRow(station, main: 44, side: 34)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(DM.pad)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // 大：台名和控制，下面 4 台收藏。
    private func large(_ station: RadioStation) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                RadioIcon(size: 64, playing: playing)
                VStack(alignment: .leading, spacing: 2) {
                    name(station, size: 19)
                    statusLine()
                    Text(channel)
                        .font(.system(size: DM.small))
                        .monospacedDigit()
                        .foregroundStyle(Color.panelTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 10)
            keyRow(station, main: 50, side: 38)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 12)
            Text(tr("收藏电台"))
                .font(.system(size: DM.small, weight: .semibold))
                .foregroundStyle(Color.panelSecondary)
            Spacer(minLength: 4)
            let window = DesktopCardsMediaPlan.stationWindow(
                current: index, count: stations.count, rows: DesktopCardsMediaPlan.listRows(.radio, size: size))
            VStack(spacing: 2) {
                ForEach(Array(window), id: \.self) { i in
                    stationRow(i)
                }
            }
        }
        .padding(DM.pad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func stationRow(_ i: Int) -> some View {
        let tuned = i == index
        let item = stations[i]
        return Button {
            if tuned { toggle(item) } else { RadioRemote.tune(widget, to: i, play: true) }
        } label: {
            HStack(spacing: 10) {
                Text(String(format: "%02d", i + 1))
                    .font(.system(size: DM.small, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(tuned ? accent.panelReadable : Color.panelTertiary)
                    .frame(width: 22, alignment: .leading)
                Text(item.name)
                    .font(.system(size: 15, weight: tuned ? .semibold : .regular))
                    .foregroundStyle(Color.panelPrimary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if tuned, playing {
                    PlayingBarsView(playing: true, tint: accent.panelGraphic, height: 12, visible: true)
                } else if item.mayBeDead {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: DM.small))
                        .foregroundStyle(Color.panelTertiary)
                        .help(tr("可能失效"))
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background {
                if tuned { RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.panelSelected) }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(tuned ? (playing ? tr("暂停") : tr("播放")) : tr("切到 \(item.name)"))
    }
}

// MARK: - 录音

/// 录音：一个大红键开始 / 停止，录着时每秒走时间；中号带最近一条，大号列最近 3 条，能直接回放。
private struct DMRecorderCard: View {
    var widget: WidgetInstance
    var size: DesktopPinSize
    var now: Date

    @Environment(\.panelTint) private var panelTint

    private var recorder: VoiceRecorder { VoiceRecorder.shared }
    private var folderPath: String { widget.config.string("folder") }
    private var recording: Bool { recorder.isRecording }

    private var red: Color { Color(hex: PaletteColor.red.hex) }
    private var accent: Color { DM.accent(panelTint, own: red) }

    private func reading(_ at: Date) -> String {
        guard let started = recorder.startedAt else { return "0:00" }
        return RecordingNaming.elapsed(at.timeIntervalSince(started))
    }

    private func caption(_ at: Date) -> String {
        if recorder.error != nil { return tr("没有麦克风权限") }
        if recording { return tr("正在录音…") }
        if let last = recorder.recordings.first,
           case .running(let p)? = RecordingTranscriber.shared.status(last.url) {
            return p > 0 ? tr("正在转文字 \(Int(p * 100))%") : tr("正在转文字…")
        }
        if let last = recorder.recordings.first {
            return tr("上次 \(RelativeAge.caption(last.date, now: at))")
        }
        return tr("保存到“\(recorder.folder.lastPathComponent)”")
    }

    var body: some View {
        // 录着时每秒走一次，平时跟着卡片按分钟。
        TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: recording ? 1 : 60)) { timeline in
            let at = recording ? timeline.date : now
            Group {
                switch size {
                case .small: small(at)
                case .medium: medium(at)
                case .large: large(at)
                }
            }
            .padding(DM.pad)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear { recorder.use(folderPath: folderPath) }
    }

    private func recordKey(size key: CGFloat) -> some View {
        Button { recorder.toggle(folderPath: folderPath) } label: {
            ZStack {
                Circle().fill(Color.panelFill)
                Circle().strokeBorder(Color.panelStroke, lineWidth: 0.5)
                if recording {
                    RoundedRectangle(cornerRadius: key * 0.08, style: .continuous)
                        .fill(accent)
                        .frame(width: key * 0.34, height: key * 0.34)
                } else {
                    Circle().fill(accent).padding(key * 0.12)
                    Image(systemName: "mic.fill")
                        .font(.system(size: key * 0.32, weight: .bold))
                        .foregroundStyle(panelTint.ink(or: .white))
                }
            }
            .frame(width: key, height: key)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(recording ? tr("停止录音") : tr("开始录音"))
        .accessibilityLabel(recording ? tr("停止录音") : tr("开始录音"))
    }

    private func clock(_ at: Date, size font: CGFloat) -> some View {
        Text(recording ? reading(at) : tr("录音"))
            .font(.system(size: font, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(recording ? accent.panelReadable : Color.panelPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private func captionText(_ at: Date) -> some View {
        Text(caption(at))
            .font(.system(size: DM.small))
            .foregroundStyle(recorder.error != nil ? Color(hex: PaletteColor.orange.hex).panelReadable
                                                   : Color.panelSecondary)
            .lineLimit(1)
    }

    // 小：居中一个大红键，下面时间和一句状态。
    private func small(_ at: Date) -> some View {
        VStack(spacing: 8) {
            recordKey(size: 72)
            VStack(spacing: 2) {
                clock(at, size: 22)
                captionText(at)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // 中：大红键在左，右边大字时间、状态，最近一条（没在录时）。
    private func medium(_ at: Date) -> some View {
        HStack(spacing: 18) {
            recordKey(size: 100)
            VStack(alignment: .leading, spacing: 2) {
                clock(at, size: 34)
                captionText(at)
                Spacer(minLength: 6)
                if !recording, let last = recorder.recordings.first {
                    recordingRow(last, at: at, compact: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
    }

    // 大：大红键和时间，下面最近 3 条录音，能回放、能在访达里打开文件夹。
    private func large(_ at: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 18) {
                recordKey(size: 96)
                VStack(alignment: .leading, spacing: 2) {
                    clock(at, size: 38)
                    captionText(at)
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 12)
            HStack {
                Text(tr("最近录音"))
                    .font(.system(size: DM.small, weight: .semibold))
                    .foregroundStyle(Color.panelSecondary)
                Spacer(minLength: 4)
                Button { NSWorkspace.shared.open(recorder.folder) } label: {
                    Label(tr("打开文件夹"), systemImage: "folder")
                        .font(.system(size: DM.small, weight: .medium))
                        .foregroundStyle(Color.panelSecondary)
                        .labelStyle(.titleAndIcon)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 6)
            let rows = DesktopCardsMediaPlan.listRows(.recorder, size: size)
            if recorder.recordings.isEmpty {
                Text(tr("还没有录音，点上面的红键开始"))
                    .font(.system(size: DM.small))
                    .foregroundStyle(Color.panelSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 18)
            } else {
                VStack(spacing: 4) {
                    ForEach(Array(recorder.recordings.prefix(rows))) { item in
                        recordingRow(item, at: at, compact: false)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func recordingRow(_ item: VoiceRecorder.Recording, at: Date, compact: Bool) -> some View {
        let on = recorder.playingURL == item.url && recorder.isPlaying
        let duration = item.duration ?? recorder.analyses[item.url]?.duration
        return HStack(spacing: 10) {
            DMRoundKey(symbol: on ? "pause.fill" : "play.fill", label: on ? tr("暂停") : tr("播放"), size: 30,
                       action: recording ? nil : { recorder.togglePlay(item.url) })
            VStack(alignment: .leading, spacing: 0) {
                Text(item.url.deletingPathExtension().lastPathComponent)
                    .font(.system(size: compact ? DM.small : 15, weight: .medium))
                    .foregroundStyle(Color.panelPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !compact {
                    Text(RelativeAge.caption(item.date, now: at))
                        .font(.system(size: DM.small))
                        .foregroundStyle(Color.panelTertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if let duration {
                Text(RecorderClock.text(duration))
                    .font(.system(size: DM.small))
                    .monospacedDigit()
                    .foregroundStyle(Color.panelSecondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, compact ? 0 : 8)
        .padding(.vertical, compact ? 0 : 5)
        .background {
            if !compact { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.panelFill) }
        }
        .onAppear { if duration == nil { recorder.analyzeIfNeeded(item.url) } }
    }
}

// MARK: - 麦克风

/// 麦克风：有没有应用在用、谁在用，全局静音一键切；大号加输入音量和正在用的应用列表。
/// 设置里开着「静音时卡片变红」时，静音中卡片铺一层淡红。
private struct DMMicrophoneCard: View {
    var widget: WidgetInstance
    var size: DesktopPinSize
    var now: Date

    private var mic: MicrophoneMonitor { MicrophoneMonitor.shared }
    private var inUse: Bool { mic.inUse || !mic.apps.isEmpty }
    private var muted: Bool { mic.globalMuted }
    private var red: Bool { muted && MicPrivacySettings(config: widget.config).redWhenMuted }
    private var orange: Color { Color(hex: PaletteColor.orange.hex) }
    private var redColor: Color { Color(hex: MicPanelStyle.red) }
    /// 静音键的实心红：白字要读得清，比面板的珊瑚红深一档。
    private var redFill: Color { Color(hex: "#D93B2B") }

    private var value: String { MicrophoneText.value(inUse: inUse, muted: muted) }
    private var caption: String {
        mic.hasDevice ? MicrophoneText.caption(deviceName: mic.deviceName, apps: mic.apps.map(\.name))
                      : tr("没有输入设备")
    }

    var body: some View {
        Group {
            switch size {
            case .small: small
            case .medium: medium
            case .large: large
            }
        }
        .padding(DM.pad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { if red { redColor.opacity(0.22) } }
        .onAppear { mic.start() }
    }

    private func badge(side: CGFloat) -> some View {
        ZStack {
            Circle().fill(inUse && !muted ? orange.opacity(0.18) : Color.panelFill)
            Image(systemName: muted ? "mic.slash.fill" : "mic.fill")
                .font(.system(size: side * 0.42, weight: .semibold))
                .foregroundStyle(muted ? redColor.panelReadable
                                       : (inUse ? orange.panelReadable : Color.panelPrimary))
        }
        .frame(width: side, height: side)
        .overlay(alignment: .topTrailing) {
            if inUse && !muted {
                Circle().fill(orange).frame(width: side * 0.2, height: side * 0.2)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if mic.cameraOn {
                Circle().fill(Color(hex: MicPanelStyle.camera)).frame(width: side * 0.2, height: side * 0.2)
                    .accessibilityLabel(tr("摄像头开着"))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("麦克风"))
        .accessibilityValue(value)
    }

    private var muteLabel: String { muted ? tr("取消静音麦克风") : tr("静音麦克风") }

    private func muteKey(size key: CGFloat) -> some View {
        DMRoundKey(symbol: muted ? "mic.fill" : "mic.slash.fill", label: muteLabel, size: key, prominent: true,
                   fill: muted ? redFill : nil, ink: muted ? .white : nil,
                   action: mic.canGlobalMute ? { mic.toggleGlobalMute() } : nil)
    }

    /// 宽的静音键：图标 + 「静音」/「取消静音」。
    private func wideMute(height: CGFloat) -> some View {
        Button { mic.toggleGlobalMute() } label: {
            HStack(spacing: 8) {
                Image(systemName: muted ? "mic.fill" : "mic.slash.fill")
                    .font(.system(size: 17, weight: .bold))
                Text(muted ? tr("取消静音") : tr("静音"))
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(muted ? Color.white : Color.panelOnPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: height * 0.32, style: .continuous)
                .fill(muted ? redFill : Color.panelPrimary))
            .contentShape(.rect(cornerRadius: height * 0.32))
        }
        .buttonStyle(.plain)
        .disabled(!mic.canGlobalMute)
        .opacity(mic.canGlobalMute ? 1 : 0.45)
        .help(muteLabel)
        .accessibilityLabel(muteLabel)
    }

    private func valueText(size font: CGFloat) -> some View {
        Text(value)
            .font(.system(size: font, weight: .bold))
            .foregroundStyle(Color.panelPrimary)
            .lineLimit(1)
    }

    private var captionText: some View {
        Text(caption)
            .font(.system(size: DM.small))
            .foregroundStyle(Color.panelSecondary)
            .lineLimit(1)
    }

    // 小：状态图标 + 静音键，下面状态和谁在用。
    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                badge(side: 56)
                Spacer(minLength: 6)
                if mic.canGlobalMute { muteKey(size: 44) }
            }
            Spacer(minLength: 8)
            valueText(size: 17)
            captionText
        }
    }

    // 中：左边状态、设备和摄像头，右边一块大静音键。
    private var medium: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                badge(side: 52)
                Spacer(minLength: 6)
                valueText(size: 20)
                captionText
                if mic.cameraOn {
                    Label(tr("摄像头开着"), systemImage: "video.fill")
                        .font(.system(size: DM.small, weight: .medium))
                        .foregroundStyle(Color(hex: MicPanelStyle.camera).panelReadable)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if mic.canGlobalMute {
                Button { mic.toggleGlobalMute() } label: {
                    VStack(spacing: 8) {
                        Image(systemName: muted ? "mic.fill" : "mic.slash.fill")
                            .font(.system(size: 28, weight: .bold))
                        Text(muted ? tr("取消静音") : tr("静音"))
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.87)
                    }
                    .foregroundStyle(muted ? Color.white : Color.panelOnPrimary)
                    .frame(width: 118)
                    .frame(maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(muted ? redFill : Color.panelPrimary))
                    .contentShape(.rect(cornerRadius: 20))
                }
                .buttonStyle(.plain)
                .help(muteLabel)
                .accessibilityLabel(muteLabel)
            }
        }
    }

    // 大：状态、宽静音键、输入音量、正在用麦克风的应用。
    private var large: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                badge(side: 56)
                VStack(alignment: .leading, spacing: 2) {
                    valueText(size: 20)
                    Text(mic.hasDevice ? mic.deviceName : tr("没有输入设备"))
                        .font(.system(size: DM.small))
                        .foregroundStyle(Color.panelSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 12)
            wideMute(height: 46)
            if mic.volumeSettable, let level = mic.volume {
                Spacer(minLength: 12)
                HStack(spacing: 10) {
                    Text(tr("输入音量"))
                        .font(.system(size: DM.small, weight: .medium))
                        .foregroundStyle(Color.panelSecondary)
                        .lineLimit(1)
                        .fixedSize()
                    Slider(value: Binding(get: { level }, set: { mic.setVolume($0) }), in: 0...1)
                        .controlSize(.small)
                    Text("\(Int((level * 100).rounded()))%")
                        .font(.system(size: DM.small, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Color.panelSecondary)
                        .frame(width: 42, alignment: .trailing)
                }
            }
            Spacer(minLength: 12)
            Text(tr("正在使用"))
                .font(.system(size: DM.small, weight: .semibold))
                .foregroundStyle(Color.panelSecondary)
            Spacer(minLength: 4)
            let rows = DesktopCardsMediaPlan.listRows(.microphone, size: size)
            let split = DesktopCardsMediaPlan.split(count: mic.apps.count, rows: rows)
            if mic.apps.isEmpty {
                Text(mic.cameraOn ? tr("没有应用在用麦克风 · 摄像头开着") : tr("没有应用在用麦克风"))
                    .font(.system(size: DM.small))
                    .foregroundStyle(Color.panelSecondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(mic.apps.prefix(split.shown))) { app in
                        HStack(spacing: 10) {
                            if let icon = AppIconCache.icon(url: app.bundleURL, bundleID: app.id) {
                                Image(nsImage: icon).resizable().interpolation(.high).frame(width: 24, height: 24)
                            } else {
                                Image(systemName: "app.dashed")
                                    .font(.system(size: 18))
                                    .foregroundStyle(Color.panelSecondary)
                                    .frame(width: 24, height: 24)
                            }
                            Text(app.name)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.panelPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            Text(DesktopCardsMediaPlan.usedFor(since: app.since, now: now))
                                .font(.system(size: DM.small))
                                .foregroundStyle(Color.panelTertiary)
                                .lineLimit(1)
                                .fixedSize()
                        }
                        .frame(height: 30)
                    }
                    if split.more > 0 {
                        Text(tr("还有 \(split.more) 个"))
                            .font(.system(size: DM.small))
                            .foregroundStyle(Color.panelTertiary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - 环境音

/// 环境音：当前组合、播放暂停；中号一排声音开关，大号声音格子、定时和音量。
/// 改声音、定时、音量和面板写同一份配置、同一个播放器。
private struct DMAmbientCard: View {
    var widget: WidgetInstance
    var size: DesktopPinSize

    @Environment(\.panelTint) private var panelTint
    @State private var dragging: Double?

    private var player: AmbientPlayer { AmbientPlayer.shared }
    private var config: WidgetConfig { widget.config }
    private var sounds: [AmbientSound] { AmbientSound.parse(config.strings("sounds", default: ["rain"])) }
    private var volume: Double { dragging ?? config.double("volume", default: 50) }
    private var levels: [AmbientSound: Int] { AmbientLevels.parse(config.strings(AmbientLevels.key, default: [])) }
    private var title: String {
        let mixes = AmbientMixes.all(config.strings(AmbientMixes.key, default: []))
        return AmbientMixes.matching(sounds: sounds, levels: levels, in: mixes)?.name ?? AmbientSound.summary(sounds)
    }
    private var playing: Bool { player.isPlaying }

    private var accent: Color { DM.accent(panelTint, own: Color(hex: PaletteColor.teal.hex)) }
    private var ink: Color { panelTint.ink(or: .white) }

    private func caption(_ at: Date) -> String {
        guard player.isPlaying else { return sounds.isEmpty ? tr("在设置中选择声音") : tr("已暂停") }
        if let end = player.stopAt { return tr("\(AmbientTimer.remaining(until: end, now: at)) 后停止") }
        return tr("正在播放")
    }

    var body: some View {
        // 定时关闭在走时每秒刷新剩余时间，平时不刷。
        TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: player.stopAt != nil ? 1 : 3600)) { timeline in
            Group {
                switch size {
                case .small: small(timeline.date)
                case .medium: medium(timeline.date)
                case .large: large(timeline.date)
                }
            }
            .padding(DM.pad)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear { player.apply(sounds: sounds, levels: levels, volume: volume) }
    }

    private func toggle() {
        guard !sounds.isEmpty else { return }
        player.toggle(sounds: sounds, levels: levels, volume: volume)
    }

    private func flip(_ sound: AmbientSound) {
        let next = DesktopCardsMediaPlan.toggling(sound, in: sounds)
        guard next != sounds else { return }
        let latest = WidgetWriter.current(widget.id) ?? widget
        WidgetWriter.write(latest) { config in
            config.set("sounds", .list(next.map { .string($0.rawValue) }))
        }
        player.apply(sounds: next, levels: levels, volume: volume)
    }

    private func badge(side: CGFloat) -> some View {
        ZStack {
            Circle().fill(playing ? accent.opacity(0.18) : Color.panelFill)
            Image(systemName: sounds.first?.symbol ?? "speaker.wave.2")
                .font(.system(size: side * 0.42, weight: .medium))
                .foregroundStyle(playing ? accent.panelReadable : Color.panelPrimary)
                .symbolEffect(.variableColor.iterative, options: .repeating, isActive: playing)
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    private func playKey(size key: CGFloat) -> some View {
        DMRoundKey(symbol: playing ? "pause.fill" : "play.fill", label: playing ? tr("暂停环境音") : tr("播放环境音"),
                   size: key, prominent: true, fill: accent, ink: ink, action: sounds.isEmpty ? nil : { toggle() })
    }

    private func titleBlock(_ at: Date, title font: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: font, weight: .bold))
                .foregroundStyle(Color.panelPrimary)
                .lineLimit(1)
            Text(caption(at))
                .font(.system(size: DM.small))
                .monospacedDigit()
                .foregroundStyle(Color.panelSecondary)
                .lineLimit(1)
        }
    }

    // 小：声音图标 + 播放键，下面组合名和状态。
    private func small(_ at: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                badge(side: 56)
                Spacer(minLength: 6)
                playKey(size: 44)
            }
            Spacer(minLength: 8)
            titleBlock(at, title: 15)
        }
    }

    // 中：组合名、状态、播放键，下面一排七种声音的开关。
    private func medium(_ at: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                badge(side: 48)
                titleBlock(at, title: 17)
                Spacer(minLength: 6)
                playKey(size: 48)
            }
            Spacer(minLength: 10)
            HStack(spacing: 0) {
                ForEach(AmbientSound.allCases, id: \.self) { sound in
                    soundDot(sound)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func soundDot(_ sound: AmbientSound) -> some View {
        let on = sounds.contains(sound)
        return Button { flip(sound) } label: {
            Image(systemName: sound.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(on ? ink : Color.panelSecondary)
                .frame(width: 38, height: 38)
                .background(Circle().fill(on ? accent : Color.panelFill))
                .overlay { if !on { Circle().strokeBorder(Color.panelStroke, lineWidth: 0.5) } }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(on ? tr("拿掉\(sound.title)") : tr("加上\(sound.title)"))
        .accessibilityLabel(sound.title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // 大：组合和播放，声音格子两行，定时一排，音量一条。
    private func large(_ at: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                badge(side: 52)
                titleBlock(at, title: 19)
                Spacer(minLength: 6)
                playKey(size: 52)
            }
            Spacer(minLength: 12)
            let columns = Array(repeating: GridItem(.flexible(), spacing: 8),
                                count: DesktopCardsMediaPlan.ambientColumns)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(AmbientSound.allCases, id: \.self) { sound in
                    soundCell(sound)
                }
            }
            Spacer(minLength: 12)
            HStack(spacing: 6) {
                ForEach(AmbientTimer.choices, id: \.self) { minutes in
                    timerChip(minutes)
                }
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                Image(systemName: "speaker.fill")
                    .font(.system(size: DM.small))
                    .foregroundStyle(Color.panelSecondary)
                Slider(value: Binding(get: { volume }, set: { value in
                    dragging = value
                    player.apply(sounds: sounds, levels: levels, volume: value)
                }), in: 0...100, onEditingChanged: { editing in
                    guard !editing, let value = dragging else { return }
                    let latest = WidgetWriter.current(widget.id) ?? widget
                    WidgetWriter.write(latest) { $0.set("volume", .number(value)) }
                    dragging = nil
                })
                .tint(panelTint.control)
                .controlSize(.small)
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: DM.small))
                    .foregroundStyle(Color.panelSecondary)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(tr("总音量"))
            Spacer(minLength: 0)
        }
    }

    private func soundCell(_ sound: AmbientSound) -> some View {
        let on = sounds.contains(sound)
        return Button { flip(sound) } label: {
            VStack(spacing: 4) {
                Image(systemName: sound.symbol)
                    .font(.system(size: 17, weight: .semibold))
                Text(sound.title)
                    .font(.system(size: DM.small, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(on ? ink : Color.panelPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? accent : Color.panelFill))
            .overlay {
                if !on { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.panelStroke, lineWidth: 0.5) }
            }
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .help(on ? tr("拿掉\(sound.title)") : tr("加上\(sound.title)"))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func timerChip(_ minutes: Int) -> some View {
        let on = player.timerMinutes == minutes
        return Button { player.setTimer(minutes: minutes) } label: {
            Text(AmbientTimer.title(minutes))
                .font(.system(size: DM.small, weight: on ? .semibold : .medium))
                .foregroundStyle(on ? Color.panelPrimary : Color.panelSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background {
                    if on {
                        Capsule().fill(Color.panelRaised).panelLift()
                    } else {
                        Capsule().fill(Color.panelFill)
                    }
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help(tr("定时关闭"))
    }
}

// MARK: - 应用音量

/// 应用音量：正在出声的应用一行一个，点或拖音量条直接定音量（0 到 150%，靠近 100% 吸住），
/// 点图标静音。小号 1 个、中号 3 个、大号 6 个，改过的排前面；大号带「全部恢复」。
private struct DMAppVolumeCard: View {
    var widget: WidgetInstance
    var size: DesktopPinSize

    private var service: AppVolumeService { AppVolumeService.shared }
    @State private var drag: (id: String, value: Double)?

    private var permissionNeeded: Bool {
        service.permission == .denied && service.rows.contains { !$0.setting.isDefault }
    }

    var body: some View {
        let split = DesktopCardsMediaPlan.appVolumeRows(service.rows, size: size) { !$0.setting.isDefault }
        Group {
            if service.rows.isEmpty {
                DMEmpty(symbol: "slider.vertical.3", title: AppVolumeText.value(playing: 0),
                        caption: tr("应用开始出声后在这里调音量"), size: size)
            } else {
                switch size {
                case .small: small(split.shown.first, more: split.more)
                case .medium, .large: list(split.shown, more: split.more)
                }
            }
        }
        .onAppear { service.start() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tr("应用音量"))
    }

    private func value(_ row: AppVolumeService.Row) -> Double {
        if let drag, drag.id == row.bundleID { return drag.value }
        return row.setting.percent
    }

    private func label(_ row: AppVolumeService.Row) -> String {
        AppVolumeStrip.label(percent: value(row), muted: row.setting.muted)
    }

    private func icon(_ row: AppVolumeService.Row, size side: CGFloat) -> some View {
        Button { service.setMuted(!row.setting.muted, for: row.bundleID) } label: {
            AppIconView(bundleID: row.bundleID, preview: false, size: side)
                .opacity(row.setting.muted ? 0.45 : 1)
                .overlay(alignment: .bottomTrailing) {
                    if row.setting.muted {
                        Image(systemName: "speaker.slash.fill")
                            .font(.system(size: max(9, side * 0.34), weight: .bold))
                            .foregroundStyle(.white)
                            .padding(2)
                            .background(Circle().fill(Color(hex: PaletteColor.red.hex)))
                            .offset(x: 3, y: 3)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(row.setting.muted ? tr("取消静音\(row.name)") : tr("静音\(row.name)"))
        .accessibilityLabel(row.setting.muted ? tr("取消静音\(row.name)") : tr("静音\(row.name)"))
    }

    /// 音量条：点哪就是多少，按住拖也行。一道小刻度标 100%（不处理）。
    private func bar(_ row: AppVolumeService.Row, height: CGFloat) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            let muted = row.setting.muted
            let fill = AppVolumeStrip.fraction(percent: value(row), muted: muted)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.panelTrack)
                if !muted {
                    Capsule().fill(AppTint.color(for: row.bundleID, preview: false))
                        .frame(width: max(height, width * fill))
                }
                Rectangle()
                    .fill(Color.panelTertiary)
                    .frame(width: 1.5, height: height + 6)
                    .offset(x: width * AppVolumeStrip.unityFraction - 0.75)
            }
            .frame(height: height)
            .frame(maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { change in
                        let next = DesktopCardsMediaPlan.appVolumePercent(x: change.location.x, width: width)
                        drag = (row.bundleID, next)
                        if row.setting.muted { service.setMuted(false, for: row.bundleID) }
                        service.setPercent(next, for: row.bundleID)
                    }
                    .onEnded { _ in drag = nil })
        }
        .frame(height: max(24, height + 12))
        .help(row.problem ?? tr("\(row.name)：点或拖音量条调音量，点图标静音"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.name)
        .accessibilityValue(label(row))
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 10.0 : -10.0
            service.setPercent(row.setting.percent + step, for: row.bundleID)
        }
    }

    private func percentText(_ row: AppVolumeService.Row, size font: CGFloat) -> some View {
        Text(label(row))
            .font(.system(size: font, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(row.setting.muted ? Color(hex: PaletteColor.red.hex).panelReadable : Color.panelPrimary)
            .lineLimit(1)
    }

    @ViewBuilder
    private func footer(more: Int) -> some View {
        if permissionNeeded {
            Button { service.openPrivacySettings() } label: {
                Label(tr("需要录音权限，点这里打开设置"), systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: DM.small, weight: .medium))
                    .foregroundStyle(Color(hex: PaletteColor.orange.hex).panelReadable)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        } else if more > 0 {
            Text(tr("还有 \(more) 个"))
                .font(.system(size: DM.small))
                .foregroundStyle(Color.panelTertiary)
                .lineLimit(1)
        }
    }

    // 小：一个应用，大字百分比、能拖的条。
    @ViewBuilder
    private func small(_ row: AppVolumeService.Row?, more: Int) -> some View {
        if let row {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    icon(row, size: 40)
                    Spacer(minLength: 6)
                    percentText(row, size: 26)
                }
                Spacer(minLength: 4)
                Text(row.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.panelPrimary)
                    .lineLimit(1)
                bar(row, height: 10)
                footer(more: more)
                    .frame(height: more > 0 || permissionNeeded ? nil : 0)
            }
            .padding(DM.pad)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // 中、大：小标题，每行图标、名字、音量条、百分比；大号底下「全部恢复」。
    private func list(_ rows: [AppVolumeService.Row], more: Int) -> some View {
        let large = size == .large
        return VStack(alignment: .leading, spacing: large ? 6 : 2) {
            DMHeader(symbol: "slider.horizontal.3", title: WidgetCatalog.entry(.appVolume)?.name ?? tr("应用音量"),
                     trailing: more > 0 && !large ? tr("还有 \(more) 个") : nil)
            ForEach(rows) { row in
                HStack(spacing: 10) {
                    icon(row, size: large ? 26 : 24)
                    Text(row.name)
                        .font(.system(size: DM.small, weight: .medium))
                        .foregroundStyle(Color.panelPrimary)
                        .lineLimit(1)
                        .frame(width: large ? 76 : 70, alignment: .leading)
                    bar(row, height: 8)
                    Text(label(row))
                        .font(.system(size: DM.small, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(row.setting.muted ? Color(hex: PaletteColor.red.hex).panelReadable
                                                           : Color.panelSecondary)
                        .lineLimit(1)
                        .frame(width: 44, alignment: .trailing)
                }
                .frame(height: large ? 34 : 32)
            }
            if large {
                Spacer(minLength: 0)
                HStack {
                    footer(more: more)
                    Spacer(minLength: 6)
                    if service.rows.contains(where: { !$0.setting.isDefault }) {
                        Button { service.resetAll() } label: {
                            Text(tr("全部恢复 100%"))
                                .font(.system(size: DM.small, weight: .semibold))
                                .foregroundStyle(Color.panelPrimary)
                                .padding(.horizontal, 12)
                                .frame(height: 30)
                                .background(Capsule().fill(Color.panelRaised).panelLift())
                                .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if permissionNeeded {
                footer(more: 0)
            }
        }
        .padding(DM.pad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
