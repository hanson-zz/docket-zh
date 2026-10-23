import AppKit
import SwiftUI

/// 「复古卡带」小组件（Pro）的卡片：磁带、随身听、收录机三种机型（`CassetteModel`）。
///
/// 扩展栏横排是中卡 404×58，三种机型都有（效果图 design/cassette-widget-glass-*.png
/// 的「扩展栏上」）：
/// - 磁带：玻璃卡片上放一盒茶色磁带（封面当标签贴纸，两个转轮），旁边歌名、歌手、
///   上一首 / 珊瑚播放键 / 下一首和一条细进度。
/// - 随身听：奶油机身（小窗转轮、灰绿液晶写歌名和时间），右边三个玻璃键。
/// - 收录机：苔绿机身（双喇叭、调台条上的红指针走到哪就是进度、磁带仓和铜旋钮），
///   右边三个玻璃键。
/// - 紧凑（只有磁带，216 宽）：精简磁带加歌名歌手两行，点磁带播放暂停。
/// - 扩展栏在左右两侧时是 76 宽的竖条：小磁带、歌名、播放键。
///
/// 播放数据和控制都走正在播放的服务（`MusicNow`）：卡片和正在播放、面板显示同一首。
/// 卡片负责启动服务（和正在播放一样，只开不停），点卡片打开面板。
struct CassetteTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var config: WidgetConfig { instance.config }
    private var model: CassetteModel { CassetteModel.stored(config) }
    private var browsersEnabled: Bool { config.bool("browsers", default: true) }

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

    /// 浏览器标签页播放状态变了，叫服务马上重挑，不等下一次轮询。
    private var browserState: MusicCardChoice.Browser? {
        guard !context.isPreview, browsersEnabled, let track = BrowserMedia.shared.track else { return nil }
        return MusicCardChoice.Browser(hasTrack: true, isPlaying: track.isPlaying)
    }

    /// 卡片看得见、而且不是预览：转轮才可能转。
    private var visible: Bool { !context.isPreview && ShelfVisibility.shared.cardsOnScreen }

    var body: some View {
        let track = playing
        let deck = MusicNow.cassetteTrack(track, preview: context.isPreview)
        let actions = connectOrActions(track)
        WidgetSurface {
            if context.position.isVertical {
                CassetteColumnFace(track: deck, actions: actions, visible: visible)
            } else if CassetteWidget.isCompact(config) {
                CompactTapeFace(track: deck, actions: actions, visible: visible)
            } else {
                switch model {
                case .tape: TapeCardFace(track: deck, actions: actions, visible: visible)
                case .portable: PortableCardFace(track: deck, actions: actions, visible: visible)
                case .boombox: BoomboxCardFace(track: deck, actions: actions, visible: visible)
                }
            }
        }
        .onAppear {
            guard !context.isPreview else { return }
            // 和正在播放共用一个轮询，只开不停（扩展栏一直在屏幕上）。
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

    /// 要授权又没有曲目时，珊瑚播放键就是「连接」：只有点了才弹系统授权。
    private func connectOrActions(_ track: Playing?) -> CassetteActions {
        if track == nil, needsPermission {
            let browsers = browsersEnabled
            return CassetteActions(toggle: { MusicNow.requestPermission(browsersEnabled: browsers) })
        }
        return MusicNow.actions(track, config: config, preview: context.isPreview)
    }
}

// MARK: - 共用小件

/// 卡片上的上一首 / 珊瑚播放键 / 下一首。
private struct CardKeys: View {
    var track: CassetteTrack
    var actions: CassetteActions
    var size: CGFloat
    var spacing: CGFloat = 5

    var body: some View {
        HStack(spacing: spacing) {
            GlassKey(symbol: "backward.end.fill", label: tr("上一首"), glyph: size * 0.36,
                     corner: size * 0.3, action: actions.previous)
                .frame(width: size, height: size)
            GlassKey(symbol: track.isPlaying ? "pause.fill" : "play.fill",
                     label: track.isPlaying ? tr("暂停") : tr("播放"), coral: true, latched: track.isPlaying,
                     glyph: size * 0.4, corner: size * 0.3, action: actions.toggle)
                .frame(width: size, height: size)
            GlassKey(symbol: "forward.end.fill", label: tr("下一首"), glyph: size * 0.36,
                     corner: size * 0.3, action: actions.next)
                .frame(width: size, height: size)
        }
    }
}

private struct TitleLines: View {
    var track: CassetteTrack
    var titleSize: CGFloat = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(track.title)
                .font(.system(size: titleSize, weight: .semibold))
                .foregroundStyle(WidgetStyle.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            if !track.artist.isEmpty {
                HStack(spacing: 4) {
                    if let icon = track.sourceIcon {
                        Image(nsImage: icon).resizable().interpolation(.high).scaledToFit()
                            .frame(width: 13, height: 13)
                            .accessibilityHidden(true)
                    }
                    Text(track.artist)
                        .font(WidgetStyle.caption(13))
                        .foregroundStyle(WidgetStyle.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
    }
}

// MARK: - 磁带 404×58

private struct TapeCardFace: View {
    var track: CassetteTrack
    var actions: CassetteActions
    var visible: Bool

    var body: some View {
        HStack(spacing: 10) {
            CassetteShell(track: track, visible: visible)
                .frame(width: 84, height: 52)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 8) {
                    TitleLines(track: track)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    CardKeys(track: track, actions: actions, size: 26, spacing: 4)
                }
                if track.showsTime {
                    ThinBar(progress: track.progress, track: WidgetStyle.secondary.opacity(0.3),
                            fill: WidgetStyle.primary, height: 4)
                        .accessibilityElement()
                        .accessibilityLabel(tr("进度"))
                        .accessibilityValue(Text(verbatim: "\(MusicTime.clock(track.elapsed)) / \(MusicTime.clock(track.duration))"))
                }
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - 紧凑磁带 216×58

/// 精简磁带（两个转轮、卷带量随进度）加歌名、歌手两行 13pt。没有按键和进度条
/// （216 宽放不下），点磁带播放暂停，点右边照常打开面板。
private struct CompactTapeFace: View {
    var track: CassetteTrack
    var actions: CassetteActions
    var visible: Bool

    var body: some View {
        HStack(spacing: 10) {
            shell
            TitleLines(track: track, titleSize: 13)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var shell: some View {
        let art = CassetteShell(track: track, visible: visible, simplified: true)
            .frame(width: 80, height: 50)
        if let toggle = actions.toggle {
            art
                .contentShape(.rect)
                .onTapGesture(perform: toggle)
                .help(track.isPlaying ? tr("暂停") : tr("播放"))
                .accessibilityElement()
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(track.isPlaying ? tr("暂停") : tr("播放"))
        } else {
            art
        }
    }
}

// MARK: - 竖条 76 宽

/// 扩展栏在左右两侧：小磁带、歌名一行、珊瑚播放键。不缩放机身。
private struct CassetteColumnFace: View {
    var track: CassetteTrack
    var actions: CassetteActions
    var visible: Bool

    var body: some View {
        VStack(spacing: 5) {
            CassetteShell(track: track, visible: visible, simplified: true)
                .frame(width: 54, height: 34)
            Text(track.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WidgetStyle.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            GlassKey(symbol: track.isPlaying ? "pause.fill" : "play.fill",
                     label: track.isPlaying ? tr("暂停") : tr("播放"), coral: true, latched: track.isPlaying,
                     glyph: 11, corner: 8, action: actions.toggle)
                .frame(width: 40, height: 24)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 随身听 404×58

/// 奶油机身：左边小窗看得见转轮，右边灰绿液晶写歌名、歌手和时间；机身外三个玻璃键。
private struct PortableCardFace: View {
    var track: CassetteTrack
    var actions: CassetteActions
    var visible: Bool

    var body: some View {
        HStack(spacing: 8) {
            casing(height: 52)
                .frame(maxWidth: .infinity)
            CardKeys(track: track, actions: actions, size: 34, spacing: 5)
        }
    }

    private func casing(height: CGFloat) -> some View {
        let casing = RoundedRectangle(cornerRadius: 11, style: .continuous)
        return HStack(spacing: 6) {
            PortableWindow(track: track, visible: visible)
                .frame(width: 78, height: height - 10)
            PortableLCD(track: track, compact: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 5)
        }
        .padding(.horizontal, 5)
        .frame(height: height)
        .background(casing.fill(LinearGradient(colors: [CassettePalette.creamTop, CassettePalette.creamBottom],
                                               startPoint: .top, endPoint: .bottom)))
        .overlay(casing.strokeBorder(.white.opacity(0.5), lineWidth: 0.6).padding(1))
        .overlay(casing.strokeBorder(.black.opacity(0.16), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.22), radius: 2.5, y: 1.5)
    }
}

/// 随身听的小窗：深色窗里两个转轮，一道斜高光。
struct PortableWindow: View {
    var track: CassetteTrack
    var visible: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let inner = RoundedRectangle(cornerRadius: min(9, h * 0.22), style: .continuous)
            ZStack {
                CassettePalette.rgb(40, 32, 28)
                ReelPair(progress: track.progress, minRadius: h * 0.13, maxRadius: h * 0.34, hubRadius: h * 0.11,
                         spacing: w * 0.48, playing: track.isPlaying, visible: visible)
                Path { p in
                    p.move(to: CGPoint(x: w * 0.55, y: 0)); p.addLine(to: CGPoint(x: w * 0.72, y: 0))
                    p.addLine(to: CGPoint(x: w * 0.4, y: h)); p.addLine(to: CGPoint(x: w * 0.23, y: h)); p.closeSubpath()
                }
                .fill(.white.opacity(0.08))
            }
            .clipShape(inner)
            .padding(2.5)
            .background(RoundedRectangle(cornerRadius: min(11, h * 0.26), style: .continuous)
                .fill(CassettePalette.rgb(70, 60, 52)))
        }
        .accessibilityHidden(true)
    }
}

/// 随身听的灰绿液晶：歌名加粗，下面歌手和已放时间（紧凑）或大号带长计数（面板）。
struct PortableLCD: View {
    var track: CassetteTrack
    /// 卡片上：歌名、歌手和时间两行；面板上：歌名一行、大号计数一行。
    var compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 1 : 3) {
            Text(track.title)
                .font(.system(size: compact ? 14 : 17, weight: .bold))
                .foregroundStyle(CassettePalette.lcdInk)
                .lineLimit(1)
                .truncationMode(.tail)
            if compact {
                HStack(spacing: 6) {
                    Text(track.artist)
                        .font(WidgetStyle.caption(13))
                        .foregroundStyle(CassettePalette.lcdInk.opacity(0.78))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if track.showsTime {
                        Text(MusicTime.clock(track.elapsed))
                            .font(.system(size: 13, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(CassettePalette.lcdInk)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            } else {
                Text(CassetteWidget.counter(track.elapsed))
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundStyle(CassettePalette.lcdInk)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(LinearGradient(colors: [CassettePalette.lcdTop, CassettePalette.lcdBottom],
                                 startPoint: .top, endPoint: .bottom)))
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(CassettePalette.rgb(96, 86, 74)))
    }
}

// MARK: - 收录机 404×58

/// 苔绿机身：左右铜圈喇叭，中间调台条写歌名、红指针走到哪就是进度，下面磁带仓和铜旋钮；
/// 机身外三个玻璃键。
private struct BoomboxCardFace: View {
    var track: CassetteTrack
    var actions: CassetteActions
    var visible: Bool

    var body: some View {
        HStack(spacing: 8) {
            casing
                .frame(maxWidth: .infinity)
            CardKeys(track: track, actions: actions, size: 34, spacing: 5)
        }
    }

    private var casing: some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        return HStack(spacing: 5) {
            Speaker(diameter: 44, playing: track.isPlaying, visible: visible)
            VStack(spacing: 4) {
                TuningStrip(track: track, height: 22, titleSize: 13)
                HStack(spacing: 5) {
                    BoomboxDeck(track: track, visible: visible)
                        .frame(height: 16)
                    CopperKnob(diameter: 15)
                }
            }
            .frame(maxWidth: .infinity)
            Speaker(diameter: 44, playing: track.isPlaying, visible: visible)
        }
        .padding(.horizontal, 4)
        .frame(height: 52)
        .background(shape.fill(LinearGradient(colors: [CassettePalette.oliveTop, CassettePalette.oliveBottom],
                                              startPoint: .top, endPoint: .bottom)))
        .overlay(shape.strokeBorder(CassettePalette.rgb(220, 230, 190, 0.3), lineWidth: 0.6).padding(1))
        .overlay(shape.strokeBorder(.black.opacity(0.25), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 2.5, y: 1.5)
    }
}

/// 收录机的调台条：奶白底写歌名，右边一排刻度，红指针的位置就是进度。
struct TuningStrip: View {
    var track: CassetteTrack
    var height: CGFloat
    var titleSize: CGFloat
    /// 面板里刻度占整条（歌名在上面一行），卡片上歌名在左、刻度在右。
    var stacked = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        Group {
            if stacked {
                VStack(spacing: 2) {
                    title
                    ticks.frame(height: height * 0.32)
                }
                .padding(.vertical, 4)
            } else {
                HStack(spacing: 6) {
                    title
                    ticks.frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 7)
        .frame(height: height)
        .background(shape.fill(CassettePalette.strip))
        .overlay(shape.strokeBorder(.black.opacity(0.18), lineWidth: 0.5))
    }

    private var title: some View {
        Text(track.title)
            .font(.system(size: titleSize, weight: .bold))
            .foregroundStyle(CassettePalette.stripInk)
            .lineLimit(1)
            .truncationMode(.tail)
            .layoutPriority(1)
    }

    /// 刻度和红指针。没有时长时指针停在开头。
    private var ticks: some View {
        Canvas { ctx, size in
            let count = 9
            var lines = Path()
            for i in 0...count {
                let x = size.width * CGFloat(i) / CGFloat(count)
                let tall = i % 3 == 0
                lines.move(to: CGPoint(x: x, y: size.height * (tall ? 0.15 : 0.4)))
                lines.addLine(to: CGPoint(x: x, y: size.height * 0.85))
            }
            ctx.stroke(lines, with: .color(CassettePalette.stripInk.opacity(0.45)), lineWidth: 0.7)
            let p = track.showsTime ? min(max(track.progress, 0), 1) : 0
            let x = 1 + (size.width - 2) * CGFloat(p)
            var needle = Path()
            needle.move(to: CGPoint(x: x, y: 0))
            needle.addLine(to: CGPoint(x: x, y: size.height))
            ctx.stroke(needle, with: .color(CassettePalette.needle), lineWidth: 1.6)
        }
        .accessibilityHidden(true)
    }
}

/// 收录机中间的磁带仓：深色小窗里两个转轮。
struct BoomboxDeck: View {
    var track: CassetteTrack
    var visible: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                CassettePalette.rgb(34, 30, 26)
                ReelPair(progress: track.progress, minRadius: h * 0.16, maxRadius: h * 0.4, hubRadius: h * 0.14,
                         spacing: min(w * 0.5, h * 2.6), playing: track.isPlaying, visible: visible)
            }
            .clipShape(RoundedRectangle(cornerRadius: min(5, h * 0.3), style: .continuous))
            .padding(1.5)
            .background(RoundedRectangle(cornerRadius: min(6, h * 0.35), style: .continuous)
                .fill(CassettePalette.olivePlate))
        }
        .accessibilityHidden(true)
    }
}

/// 收录机的铜色旋钮（音量的样子，卡片上不动）。
struct CopperKnob: View {
    var diameter: CGFloat
    /// 0...1：指示线转到哪（面板里跟着音量）。
    var level: Double = 0.62

    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [CassettePalette.rgb(240, 214, 150), CassettePalette.copper,
                                                  CassettePalette.rgb(150, 116, 60)],
                                         center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0,
                                         endRadius: diameter * 0.7))
            Circle().strokeBorder(CassettePalette.rgb(90, 70, 36), lineWidth: 0.8)
            Capsule().fill(CassettePalette.rgb(60, 44, 20))
                .frame(width: max(1.2, diameter * 0.08), height: diameter * 0.32)
                .offset(y: -diameter * 0.2)
                .rotationEffect(.degrees(-135 + 270 * min(max(level, 0), 1)))
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: .black.opacity(0.3), radius: 1, y: 0.8)
        .accessibilityHidden(true)
    }
}
