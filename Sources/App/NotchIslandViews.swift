import AppKit
import SwiftUI

// MARK: - 根视图

/// 刘海小岛，照效果图 design/notch-island/dockling-island-*.webp：
///
/// - compact：一个活动，刘海左右两侧长出黑色小岛（顶边贴住屏幕、外侧往里弯一小段，
///   和刘海连成一块），计时器在刘海下方多出一条显示剩余时间；
/// - split：第二个活动是右边单独的黑色小圆岛；
/// - expanded：指针停在小岛上时向下展开成液态玻璃卡片，顶上一条和刘海同宽的黑色
///   过渡接住硬件刘海（同消息灵动岛）。
///
/// 坐标以刘海顶边中点为原点（见 `NotchIslandLayout`）。窗口以刘海中线对称，所以每块
/// 东西都按「离中线多远」摆。黑色小岛浅色深色都是黑底，强调色是暖橙，字至少 13pt。
struct NotchIslandRootView: View {
    var model: NotchIslandModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animation: Animation {
        reduceMotion
            ? .easeInOut(duration: NotchIslandMotion.reducedFade)
            : .spring(response: NotchIslandMotion.morphResponse, dampingFraction: NotchIslandMotion.morphDamping)
    }

    private var expandAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: NotchIslandMotion.reducedFade)
            : .spring(response: NotchIslandMotion.expandResponse, dampingFraction: NotchIslandMotion.expandDamping)
    }

    var body: some View {
        let geometry = model.geometry
        ZStack(alignment: .top) {
            if let form = model.form {
                switch form {
                case .compact(let primary):
                    compact(primary, geometry: geometry, secondary: nil)
                case .split(let primary, let secondary):
                    compact(primary, geometry: geometry, secondary: secondary)
                case .expanded(let primary, let secondary):
                    // 刘海那一段留着黑色，卡片从它下面长出来。电台、音乐卡片顶上一截和刘海同宽、
                    // 紧贴着刘海下沿，这里下面两角不圆，两块接成一体。
                    NotchIslandShape(flare: NotchIslandLayout.topFlare,
                                     bottomRadius: NotchIslandLayout.grows(primary.kind) ? 0 : 8)
                        .fill(.black)
                        .place(NotchIslandLayout.notch(geometry))
                        .id("island-body")
                    if NotchIslandHanging.available, NotchHangingPanda.hangs(primary),
                       case .timer(let deadline, let pausedLeft, let total, _, _, _) = primary {
                        // 专注计时：小熊猫用尾巴缠着绳子从刘海倒挂下来，捧着计时牌。
                        let rect = NotchIslandLayout.hanging(geometry, hasSecondary: secondary != nil)
                        NotchIslandHangingFocus(model: model, deadline: deadline, pausedLeft: pausedLeft,
                                                total: total, secondary: secondary)
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.midX, y: rect.minY)
                            .transition(reduceMotion
                                ? .opacity
                                : .move(edge: .top).combined(with: .opacity))
                            .id("island-hanging")
                    } else {
                        let card = NotchIslandLayout.card(geometry, kind: primary.kind, hasSecondary: secondary != nil)
                        NotchIslandCard(model: model, primary: primary, secondary: secondary)
                            .frame(width: card.width, height: card.height)
                            .offset(x: card.midX, y: card.minY)
                            .transition(reduceMotion
                                ? .opacity
                                : .scale(scale: 0.4, anchor: .top).combined(with: .opacity))
                            .id("island-card")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .animation(model.form?.isExpanded == true ? expandAnimation : animation, value: model.form)
    }

    @ViewBuilder
    private func compact(_ primary: NotchIslandActivity, geometry: NotchIslandGeometry,
                         secondary: NotchIslandActivity?) -> some View {
        let main = NotchIslandLayout.body(geometry, primary)
        NotchIslandBody(activity: primary, geometry: geometry)
            .place(main)
            .id("island-body")
        if case .charging = primary {
            NotchIslandPanda()
                .place(NotchIslandLayout.panda(geometry, body: main))
                .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
                .id("island-panda")
        }
        if let secondary {
            let bubble = NotchIslandLayout.bubble(geometry, body: main)
            NotchIslandBubble(activity: secondary)
                .place(bubble)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.3).combined(with: .opacity))
                .id("island-bubble")
        }
    }
}

private extension View {
    /// 按原点坐标（刘海顶边中点）摆到这块地方。
    func place(_ rect: CGRect) -> some View {
        frame(width: rect.width, height: rect.height)
            .offset(x: rect.midX, y: rect.minY)
    }
}

/// 暖橙：黑底上偏亮，浅色玻璃上加深一点，免得发白看不清。
enum NotchIslandPalette {
    static let onBlack = Color(hex: "#FF9A3C")
    static func accent(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "#FF9A3C") : Color(hex: "#D9590B")
    }
    /// 实心橙底按钮（上面是白色图标）。
    static func solid(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(hex: "#F07A1E") : Color(hex: "#E2650F")
    }
}

// MARK: - 形状

/// 小岛的形状：顶边一整条贴住屏幕顶边，两端往外弯出一小段（和屏幕边框接上，看起来是
/// 刘海长出来的，不是飘着的胶囊），底下两角圆角。
struct NotchIslandShape: Shape {
    var flare: CGFloat
    var bottomRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(bottomRadius, rect.height / 2, rect.width / 2)
        let f = min(flare, rect.height / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX - f, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX + f, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + f), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.maxX - radius, y: rect.maxY), radius: radius)
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.minX, y: rect.maxY - radius), radius: radius)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + f))
        path.addQuadCurve(to: CGPoint(x: rect.minX - f, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - compact 的主岛

private struct NotchIslandBody: View {
    var activity: NotchIslandActivity
    var geometry: NotchIslandGeometry

    var body: some View {
        let wings = NotchIslandLayout.wings(activity)
        ZStack(alignment: .topLeading) {
            NotchIslandShape(flare: NotchIslandLayout.topFlare, bottomRadius: NotchIslandLayout.bottomRadius)
                .fill(.black)
            HStack(spacing: 0) {
                // 两侧耳朵只留刚好放下内容的宽度（Core 的 `NotchIslandLayout.wings`）；内容贴着刘海那侧摆，
                // 万一字比估的宽，多出来的往外侧长，不会钻到刘海底下看不见。
                left
                    .padding(.trailing, NotchIslandLayout.wingNotchGap)
                    .frame(width: wings.left, height: geometry.notchHeight, alignment: .trailing)
                Spacer(minLength: geometry.notchWidth)
                right
                    .padding(.leading, NotchIslandLayout.wingNotchGap)
                    .frame(width: wings.right, height: geometry.notchHeight, alignment: .leading)
            }
            if wings.chin > 0 {
                chin
                    .frame(maxWidth: .infinity)
                    .frame(height: wings.chin)
                    .offset(y: geometry.notchHeight - 2)
            }
        }
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("刘海小岛"))
        .accessibilityValue(spoken)
    }

    private var spoken: String {
        NotchIslandText.spoken(activity, now: Date())
    }

    @ViewBuilder private var left: some View {
        switch activity {
        case .charging:
            Image(systemName: "bolt.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(NotchIslandPalette.onBlack)
        case .download(_, let done):
            Image(systemName: done ? "arrow.down.circle.fill" : "arrow.down.to.line")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(NotchIslandPalette.onBlack)
        case .timer(_, _, _, _, .focus, _):
            // 专注计时：左边是选好的吉祥物（专注中、暂停、休息、刚完成各一种样子）。
            // 有刘海专用的小头（notch-<吉祥物>-peek，小熊猫是现有那张）时是从刘海底下探出来的小脑袋
            // （展开后整只倒挂下来），没有时用面板那套状态图。
            TimelineView(.periodic(from: .now, by: 1)) { tick in
                let state = TimerStateProvider.shared.state
                let mascot = FocusMascot.of(state, unlocked: ProAccess.isUnlocked)
                if case .image(let name) = NotchMascotArt.peek(mascot, exists: { NotchIslandHanging.exists($0) }),
                   let peek = NotchIslandHanging.image(named: name) {
                    Image(nsImage: peek)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(height: min(NotchIslandLayout.focusMascotHeight, max(16, geometry.notchHeight - 10)))
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .accessibilityHidden(true)
                } else {
                    FocusMascotImage(mascot: mascot, state: FocusMascotState.of(state, now: tick.date),
                                     height: min(NotchIslandLayout.focusMascotHeight, max(16, geometry.notchHeight - 6)))
                }
            }
        case .timer:
            EmptyView()
        case .meeting:
            Image(systemName: "calendar")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(NotchIslandPalette.onBlack)
        case .radio:
            Image(systemName: "radio.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NotchIslandPalette.onBlack)
        case .music(let song):
            // 圆角封面缩略图，暂停时压暗。
            NotchIslandMusicThumb(playing: song.playing, size: NotchIslandLayout.musicArtSize,
                                  cornerRadius: 5)
        }
    }

    @ViewBuilder private var right: some View {
        switch activity {
        case .charging(let percent):
            Text(verbatim: NotchIslandText.battery(percent))
                .font(.system(size: NotchIslandLayout.compactFontSize, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .fixedSize()
        case .download(let fraction, let done):
            if done {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(NotchIslandPalette.onBlack)
                    .transition(.scale.combined(with: .opacity))
            } else {
                HStack(spacing: 6) {
                    if let fraction {
                        Text(verbatim: NotchIslandText.percent(fraction))
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white)
                            .contentTransition(.numericText())
                            .fixedSize()
                    }
                    NotchIslandRing(fraction: fraction, tint: NotchIslandPalette.onBlack,
                                    track: .white.opacity(0.18), lineWidth: 2.5)
                        .frame(width: 16, height: 16)
                }
            }
        case .timer(let deadline, let pausedLeft, _, _, .focus, _):
            // 专注计时：右边只有剩余时间；暂停时不加暂停号（省宽度），数字调暗表示停着。
            TimelineView(.periodic(from: .now, by: 1)) { tick in
                Text(verbatim: NotchIslandText.clock(
                    NotchIslandTimer.remaining(deadline: deadline, pausedLeft: pausedLeft, now: tick.date)))
                    .font(.system(size: NotchIslandLayout.compactFontSize, weight: .semibold,
                                  design: .rounded).monospacedDigit())
                    .foregroundStyle(pausedLeft == nil ? NotchIslandPalette.onBlack : .white.opacity(0.5))
                    .contentTransition(.numericText(countsDown: true))
                    .lineLimit(1)
                    .fixedSize()
            }
        case .timer:
            EmptyView()
        case .meeting(_, let start):
            TimelineView(.periodic(from: .now, by: 1)) { tick in
                Text(verbatim: NotchIslandText.meetingShort(secondsUntil: start.timeIntervalSince(tick.date)))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(countsDown: true))
                    .lineLimit(1)
                    .fixedSize()
            }
        case .radio(_, let playing):
            NotchIslandWave(playing: playing, tint: NotchIslandPalette.onBlack)
                .frame(width: 20, height: 14)
        case .music(let song):
            // 细音波条，颜色取封面主色；暂停时三条静止短竖线。
            NotchIslandMusicWave(playing: song.playing, color: NotchIslandMusicPalette.wave(song.tint))
                .frame(width: NotchIslandLayout.musicWaveWidth, height: 14)
        }
    }

    @ViewBuilder private var chin: some View {
        if case .timer(let deadline, let pausedLeft, _, _, _, _) = activity {
            TimelineView(.periodic(from: .now, by: 1)) { tick in
                HStack(spacing: 5) {
                    if pausedLeft != nil {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(NotchIslandPalette.onBlack)
                            .accessibilityHidden(true)
                    }
                    Text(verbatim: NotchIslandText.clock(
                        NotchIslandTimer.remaining(deadline: deadline, pausedLeft: pausedLeft, now: tick.date)))
                        .font(.system(size: 15, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(pausedLeft == nil ? 1 : 0.7))
                        .contentTransition(.numericText(countsDown: true))
                }
            }
        }
    }
}

// MARK: - split 的小圆岛

private struct NotchIslandBubble: View {
    var activity: NotchIslandActivity

    var body: some View {
        ZStack {
            Circle().fill(.black)
            content
        }
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("刘海小岛"))
        .accessibilityValue(NotchIslandText.spoken(activity, now: Date()))
    }

    @ViewBuilder private var content: some View {
        switch activity {
        case .charging:
            Image(systemName: "bolt.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(NotchIslandPalette.onBlack)
        case .download(let fraction, let done):
            if done {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(NotchIslandPalette.onBlack)
            } else {
                NotchIslandRing(fraction: fraction, tint: NotchIslandPalette.onBlack,
                                track: .white.opacity(0.18), lineWidth: 2.5)
                    .padding(7)
            }
        case .timer(let deadline, let pausedLeft, let total, _, _, _):
            TimelineView(.periodic(from: .now, by: 1)) { tick in
                let left = NotchIslandTimer.remaining(deadline: deadline, pausedLeft: pausedLeft, now: tick.date)
                NotchIslandRing(fraction: NotchIslandTimer.elapsedFraction(remaining: left, total: total),
                                tint: NotchIslandPalette.onBlack, track: .white.opacity(0.18), lineWidth: 2.5)
                    .padding(7)
            }
        case .meeting:
            Image(systemName: "calendar")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NotchIslandPalette.onBlack)
        case .radio(_, let playing):
            NotchIslandWave(playing: playing, tint: NotchIslandPalette.onBlack)
                .padding(8)
        case .music(let song):
            NotchIslandMusicWave(playing: song.playing, color: NotchIslandMusicPalette.wave(song.tint))
                .padding(8)
        }
    }
}

// MARK: - 零件

/// 圆环进度；`fraction` 为 nil 时是转圈的一段弧（减弱动态效果时静止）。
struct NotchIslandRing: View {
    var fraction: Double?
    var tint: Color
    var track: Color
    var lineWidth: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            if let fraction {
                Circle()
                    .trim(from: 0, to: max(0.02, min(1, fraction)))
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.3), value: fraction)
            } else if reduceMotion {
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else {
                TimelineView(.animation) { tick in
                    let turn = tick.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1)
                    Circle()
                        .trim(from: 0, to: 0.3)
                        .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(turn * 360 - 90))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// 收音机的音波：四根橙色竖条，播放时轻轻起伏；暂停或减弱动态效果时静止。
struct NotchIslandWave: View {
    var playing: Bool
    var tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let rest: [CGFloat] = [0.45, 0.85, 0.6, 0.95, 0.5]

    var body: some View {
        if playing, !reduceMotion {
            TimelineView(.animation(minimumInterval: 1 / 20)) { tick in
                bars(at: tick.date.timeIntervalSinceReferenceDate)
            }
        } else {
            bars(at: nil)
        }
    }

    private func bars(at time: TimeInterval?) -> some View {
        GeometryReader { proxy in
            let count = Self.rest.count
            let gap: CGFloat = 2
            let width = max(1.5, (proxy.size.width - gap * CGFloat(count - 1)) / CGFloat(count))
            HStack(alignment: .center, spacing: gap) {
                ForEach(0..<count, id: \.self) { index in
                    let level: CGFloat = {
                        guard let time else { return playing ? Self.rest[index] : 0.3 }
                        let phase = time * (4.2 + Double(index) * 0.9) + Double(index) * 1.3
                        return 0.35 + 0.65 * CGFloat((sin(phase) + 1) / 2)
                    }()
                    Capsule(style: .continuous)
                        .fill(tint.opacity(playing ? 1 : 0.55))
                        .frame(width: width, height: max(width, proxy.size.height * level))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityHidden(true)
    }
}

/// 插电时趴在小岛旁边的小熊猫（Resources/Pet/sprites/pet-sprite-lie-1.png）。
struct NotchIslandPanda: View {
    @MainActor private static let image: NSImage? = {
        guard let url = Bundle.main.url(forResource: "pet-sprite-lie-1", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        if let rep = image.representations.first, rep.pixelsWide > 0 {
            image.size = CGSize(width: CGFloat(rep.pixelsWide) / 2, height: CGFloat(rep.pixelsHigh) / 2)
        }
        return image
    }()

    var body: some View {
        if let image = Self.image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - 展开的卡片

private struct NotchIslandCard: View {
    var model: NotchIslandModel
    var primary: NotchIslandActivity
    var secondary: NotchIslandActivity?

    @Environment(\.colorScheme) private var scheme

    /// 电台、音乐卡片从刘海下沿长出来。
    private var grows: Bool { NotchIslandLayout.grows(primary.kind) }

    private var shape: AnyShape {
        if grows {
            // 电台、音乐卡片从刘海下沿长出来：顶上一截和刘海同宽，往两侧弯出去再铺满整宽，
            // 两侧仍在菜单栏下面，不盖住右边的状态栏图标。
            return AnyShape(NotchIslandGrownShape(neck: model.geometry.notchWidth,
                                                  shoulder: NotchIslandLayout.radioShoulder,
                                                  topRadius: NotchIslandLayout.radioTopRadius,
                                                  bottomRadius: 24))
        }
        // 卡片整个在菜单栏下面（不再从屏幕顶边往两侧铺开盖住菜单栏图标），四角都圆。
        return AnyShape(UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 26,
                                               bottomTrailingRadius: 26, topTrailingRadius: 22, style: .continuous))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
            if let secondary {
                NotchIslandSecondaryRow(activity: secondary)
                    .padding(.top, 12)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, grows ? NotchIslandLayout.radioShoulder + 10 : 12)
        .padding(.horizontal, grows ? 18 : 20)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { surface }
        .contentShape(shape)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tr("刘海小岛"))
    }

    private var surface: some View {
        Color.clear
        .readableGlass(in: shape)
        .overlay { glow }
        .clipShape(shape)
        .overlay { shape.stroke(Color.panelStroke, lineWidth: 0.6) }
        .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.16), radius: 18, y: 8)
    }

    /// 音乐卡片顶部一层很淡的封面主色光晕（不超过 15%），往下渐隐；没有封面主色时不画。
    @ViewBuilder private var glow: some View {
        if case .music(let song) = primary, let tint = song.tint {
            let color = NotchIslandMusicPalette.color(tint.glow)
            LinearGradient(stops: [
                .init(color: color.opacity(NotchIslandMusicLook.glowOpacity), location: 0),
                .init(color: color.opacity(0), location: NotchIslandMusicLook.glowReach),
            ], startPoint: .top, endPoint: .bottom)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var content: some View {
        switch primary {
        case .music(let song):
            NotchIslandMusicCard(model: model, song: song)
        case .radio(let station, _):
            NotchIslandRadioCard(model: model, fallbackStation: station)
        case .timer(let deadline, let pausedLeft, let total, let focus, let source, let name):
            NotchIslandTimerCard(model: model, deadline: deadline, pausedLeft: pausedLeft, total: total,
                                 focus: focus, source: source, name: name)
        case .meeting(let title, let start):
            NotchIslandMeetingCard(model: model, title: title, start: start)
        case .download(let fraction, let done):
            NotchIslandDownloadCard(model: model, fraction: fraction, done: done)
        case .charging(let percent):
            NotchIslandChargingCard(percent: percent)
        }
    }
}

/// 卡片上的圆形按钮：实心橙（主操作）或薄玻璃。
struct NotchIslandCircleButton: View {
    var symbol: String
    var label: String
    var solid: Bool
    var enabled = true
    var diameter: CGFloat = 38
    var action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: diameter < 38 ? 13 : 15, weight: .bold))
                .foregroundStyle(solid ? Color.white : Color.panelPrimary)
                .frame(width: diameter, height: diameter)
                .background(Circle().fill(solid ? NotchIslandPalette.solid(scheme) : Color.panelFill))
                .overlay(Circle().strokeBorder(Color.panelStroke, lineWidth: solid ? 0 : 0.5))
                .contentShape(Circle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityLabel(label)
    }
}

/// 卡片上的胶囊按钮。
private struct NotchIslandCapsuleButton: View {
    var title: String
    var solid: Bool
    var action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(solid ? Color.white : Color.panelPrimary)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .frame(height: 32)
                .background(Capsule().fill(solid ? NotchIslandPalette.solid(scheme) : Color.panelFill))
                .overlay(Capsule().strokeBorder(Color.panelStroke, lineWidth: solid ? 0 : 0.5))
                .contentShape(Capsule())
                .fixedSize()
        }
        .buttonStyle(.plain)
    }
}

/// 电台卡片：左边当前所选外观的收音机插画，中间台名、副标题和上一台 / 播放暂停 / 下一台，
/// 右边「CH 03 / 06」和播放波形，底下音量条。
///
///     [插画]  音乐之声                CH 03 / 06
///             正在播放
///             (<<) ( || ) (>>)          ||||
///     音量 ----------------o----
private struct NotchIslandRadioCard: View {
    var model: NotchIslandModel
    var fallbackStation: String

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let radio = RadioPlayer.shared
        let playing = radio.isPlaying
        // 外观和台号都读开始播放的那个收音机小组件（和电台面板同一份配置），读不到时外观用经典。
        let config = radio.ownerConfig
        let stations = radio.switchList
        let stored = config.map { RadioDial.index($0, count: stations.count) } ?? 0
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                NotchIslandRadioArt(skin: NotchIslandRadio.skin(config))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: radio.station?.name ?? fallbackStation)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.panelPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                            .truncationMode(.tail)
                            .layoutPriority(1)
                        Spacer(minLength: 0)
                        if !stations.isEmpty {
                            channel(NotchIslandRadio.channel(of: radio.station, in: stations, stored: stored),
                                    spoken: NotchIslandRadio.spokenChannel(of: radio.station, in: stations,
                                                                          stored: stored))
                        }
                    }
                    Text(verbatim: subtitle(radio, playing: playing))
                        .font(.system(size: 13))
                        .foregroundStyle(.panelSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    HStack(spacing: 8) {
                        NotchIslandCircleButton(symbol: "backward.end.fill", label: tr("上一台"), solid: false,
                                                enabled: model.canSwitchStation, diameter: 32) {
                            model.act?(.radioPrevious)
                        }
                        NotchIslandCircleButton(symbol: playing ? "pause.fill" : "play.fill",
                                                label: playing ? tr("暂停") : tr("播放"), solid: true) {
                            model.act?(.radioToggle)
                        }
                        NotchIslandCircleButton(symbol: "forward.end.fill", label: tr("下一台"), solid: false,
                                                enabled: model.canSwitchStation, diameter: 32) {
                            model.act?(.radioNext)
                        }
                        Spacer(minLength: 6)
                        // 播放时跳，暂停、连接中停成一排矮条；减弱动态效果时 PlayingBarsView 自己静止。
                        PlayingBarsView(playing: playing && !radio.isBuffering,
                                        tint: NotchIslandPalette.accent(scheme), height: 18, visible: true)
                            .padding(.trailing, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 10) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelSecondary)
                    .accessibilityHidden(true)
                Slider(value: Binding(
                    get: { model.radioVolume },
                    set: { value in
                        model.radioVolume = value
                        model.act?(.radioVolume(value))
                    }), in: 0...100)
                    .controlSize(.small)
                    .tint(NotchIslandPalette.accent(scheme))
                    .accessibilityLabel(tr("音量"))
            }
        }
    }

    /// 「CH 03 / 06」紧凑写法，和电台面板头部同一套编号（`RadioPanelReadout.channel`）。
    private func channel(_ parts: (current: String, total: String), spoken: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(verbatim: "CH")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.panelSecondary)
            Text(verbatim: parts.current)
                .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(NotchIslandPalette.accent(scheme))
            Text(verbatim: "/ \(parts.total)")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(.panelSecondary)
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private func subtitle(_ radio: RadioPlayer, playing: Bool) -> String {
        if playing, let title = radio.nowTitle, !title.isEmpty { return title }
        if radio.isBuffering { return tr("正在连接") }
        return playing ? tr("正在播放") : tr("已暂停")
    }
}

/// 电台卡片左边的插画：当前所选外观的 Resources/RadioArt/radio-art-<外观>.png（同名 @2x 一起认，
/// Retina 用 512），透明图直接放、不垫底色；缺图退回 RadioMeow，再没有画个收音机图标。
/// 掌机像素那套最近邻缩放，不糊边。
private struct NotchIslandRadioArt: View {
    var skin: RadioSkin

    @Environment(\.colorScheme) private var scheme

    @MainActor private static var cache: [String: NSImage?] = [:]

    @MainActor private static func image(_ name: String) -> NSImage? {
        if let hit = cache[name] { return hit }
        let image = Bundle.main.image(forResource: name)
        cache.updateValue(image, forKey: name)
        return image
    }

    var body: some View {
        let names = NotchIslandRadio.artNames(skin)
        let found: (name: String, image: NSImage)? = names.lazy
            .compactMap { name in Self.image(name).map { (name: name, image: $0) } }
            .first
        Group {
            if let found {
                Image(nsImage: found.image)
                    .resizable()
                    .interpolation(found.name == names.first && NotchIslandRadio.pixelated(skin) ? .none : .high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "radio.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(NotchIslandPalette.accent(scheme))
            }
        }
        .frame(width: 64, height: 64)
        .accessibilityHidden(true)
    }
}

/// 电台卡片的形状：顶上一截和刘海同宽（`neck`），紧贴刘海下沿；往下 `shoulder` 处两侧各弯出一段
/// 内凹的圆弧，再铺满整宽，顶上两角 `topRadius`、底下两角 `bottomRadius`。看起来是刘海往下长出来的，
/// 中间没有缝；两侧弯出去的地方在菜单栏下面，不盖住菜单栏上的图标。
struct NotchIslandGrownShape: Shape {
    var neck: CGFloat
    var shoulder: CGFloat
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let s = min(shoulder, rect.height / 4)
        let top = min(topRadius, (rect.height - s) / 2)
        let bottom = min(bottomRadius, (rect.height - s) / 2, rect.width / 4)
        let half = max(0, min(neck / 2, rect.width / 2 - s - top))
        let cx = rect.midX
        let bodyTop = rect.minY + s
        var path = Path()
        path.move(to: CGPoint(x: cx - half, y: rect.minY))
        path.addLine(to: CGPoint(x: cx + half, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: cx + half + s, y: bodyTop), control: CGPoint(x: cx + half, y: bodyTop))
        path.addLine(to: CGPoint(x: rect.maxX - top, y: bodyTop))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: bodyTop),
                    tangent2End: CGPoint(x: rect.maxX, y: bodyTop + top), radius: top)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottom))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.maxX - bottom, y: rect.maxY), radius: bottom)
        path.addLine(to: CGPoint(x: rect.minX + bottom, y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.minX, y: rect.maxY - bottom), radius: bottom)
        path.addLine(to: CGPoint(x: rect.minX, y: bodyTop + top))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: bodyTop),
                    tangent2End: CGPoint(x: rect.minX + top, y: bodyTop), radius: top)
        path.addLine(to: CGPoint(x: cx - half - s, y: bodyTop))
        path.addQuadCurve(to: CGPoint(x: cx - half, y: rect.minY), control: CGPoint(x: cx - half, y: bodyTop))
        path.closeSubpath()
        return path
    }
}

private struct NotchIslandTimerCard: View {
    var model: NotchIslandModel
    var deadline: Date?
    var pausedLeft: TimeInterval?
    var total: TimeInterval
    var focus: Bool
    var source: NotchIslandTimerSource
    var name: String

    @Environment(\.colorScheme) private var scheme

    /// 专注计时写第几轮、专注还是休息；倒计时写「泡面 · 共 3 分钟」。
    private var caption: String {
        switch source {
        case .focus: FocusCycle.caption(TimerStateProvider.shared.state)
        case .countdown: CountdownRun.runningCaption(name: name, duration: total)
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tick in
            let left = NotchIslandTimer.remaining(deadline: deadline, pausedLeft: pausedLeft, now: tick.date)
            VStack(alignment: .leading, spacing: 10) {
                Text(verbatim: caption)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(1)
                HStack(alignment: .center, spacing: 10) {
                    Text(verbatim: NotchIslandText.clock(left))
                        .font(.system(size: 34, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.panelPrimary)
                        .contentTransition(.numericText(countsDown: true))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 6)
                    NotchIslandCapsuleButton(title: pausedLeft != nil ? tr("继续") : tr("暂停"), solid: true) {
                        model.act?(.timerToggle(source))
                    }
                    NotchIslandCapsuleButton(title: tr("结束"), solid: false) {
                        model.act?(.timerEnd(source))
                    }
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.panelTrack)
                        Capsule()
                            .fill(NotchIslandPalette.accent(scheme))
                            .frame(width: proxy.size.width
                                * NotchIslandTimer.elapsedFraction(remaining: left, total: total))
                    }
                }
                .frame(height: 4)
                .accessibilityHidden(true)
            }
            .accessibilityElement(children: .contain)
            .accessibilityValue(NotchIslandText.spoken(
                .timer(deadline: deadline, pausedLeft: pausedLeft, total: total, focus: focus,
                       source: source, name: name),
                now: tick.date))
        }
    }
}

private struct NotchIslandDownloadCard: View {
    var model: NotchIslandModel
    var fraction: Double?
    var done: Bool

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                NotchIslandRing(fraction: done ? 1 : fraction, tint: NotchIslandPalette.accent(scheme),
                                track: Color.panelTrack, lineWidth: 4)
                Image(systemName: done ? "checkmark" : "arrow.down")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(NotchIslandPalette.accent(scheme))
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text(done ? tr("下载完成") : tr("正在下载"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.panelPrimary)
                Text(verbatim: detail)
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(.panelSecondary)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 6)
            NotchIslandCapsuleButton(title: tr("打开下载文件夹"), solid: false) {
                model.act?(.openDownloads)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var detail: String {
        if done { return tr("已存到「下载」") }
        guard let fraction else { return tr("进度未知") }
        return NotchIslandText.percent(fraction)
    }
}

/// 快开始的会议：标题、还有几分钟、几点开始，和打开日历的按钮。
private struct NotchIslandMeetingCard: View {
    var model: NotchIslandModel
    var title: String
    var start: Date

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tick in
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.panelFill)
                    Image(systemName: "calendar")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(NotchIslandPalette.accent(scheme))
                }
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: displayTitle)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.panelPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(verbatim: "\(IslandCountdown.text(secondsUntil: start.timeIntervalSince(tick.date))) · "
                        + start.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(.panelSecondary)
                        .lineLimit(1)
                        .contentTransition(.numericText(countsDown: true))
                }
                Spacer(minLength: 6)
                NotchIslandCapsuleButton(title: tr("打开日历"), solid: false) {
                    model.act?(.openCalendar)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityValue(NotchIslandText.spoken(.meeting(title: title, start: start), now: tick.date))
        }
    }

    private var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? tr("新日程") : trimmed
    }
}

private struct NotchIslandChargingCard: View {
    var percent: Int

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(NotchIslandPalette.accent(scheme))
                .accessibilityHidden(true)
            Text(verbatim: NotchIslandText.battery(percent))
                .font(.system(size: 30, weight: .bold).monospacedDigit())
                .foregroundStyle(.panelPrimary)
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("已接通电源"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                Text(tr("充电中"))
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
            }
            Spacer(minLength: 4)
            NotchIslandPanda()
                .frame(width: 92, height: 40)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NotchIslandText.spoken(.charging(percent: percent), now: Date()))
    }
}

/// 卡片底下一行：第二个活动的一句话。
private struct NotchIslandSecondaryRow: View {
    var activity: NotchIslandActivity

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tick in
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NotchIslandPalette.accent(scheme))
                    .frame(width: 18)
                    .accessibilityHidden(true)
                Text(verbatim: NotchIslandText.spoken(activity, now: tick.date))
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Capsule().fill(Color.panelFill))
        }
    }

    private var symbol: String {
        switch activity {
        case .charging: "bolt.fill"
        case .download(_, let done): done ? "checkmark.circle.fill" : "arrow.down.circle"
        case .timer: "timer"
        case .meeting: "calendar"
        case .radio: "radio.fill"
        case .music: "music.note"
        }
    }
}

// MARK: - 专注计时展开：倒挂小熊猫

/// 倒挂小熊猫的图（Resources/NotchPanda），读一次存着；缺图时专注照旧用展开卡片。
/// 别的吉祥物的刘海图（Resources/NotchMascots/notch-<吉祥物>-<样子>.png）按名字查，也读一次存着，
/// 没有时按 `NotchMascotArt` 回退到小熊猫。
@MainActor
enum NotchIslandHanging {
    static let poses: [NotchHangingPanda.Pose: NSImage] = {
        var result: [NotchHangingPanda.Pose: NSImage] = [:]
        for pose in NotchHangingPanda.Pose.allCases {
            if let image = Bundle.main.image(forResource: pose.imageName) { result[pose] = image }
        }
        return result
    }()
    static let peek = Bundle.main.image(forResource: NotchHangingPanda.peekImageName)

    static var available: Bool { poses.count == NotchHangingPanda.Pose.allCases.count }

    private static var cache: [String: NSImage] = [:]
    private static var missing: Set<String> = []

    /// 按图名取（带 @2x 的也认）；查过没有的记下来，不反复查。
    static func image(named name: String) -> NSImage? {
        if let image = cache[name] { return image }
        guard !missing.contains(name), let image = Bundle.main.image(forResource: name) else {
            missing.insert(name)
            return nil
        }
        cache[name] = image
        return image
    }

    static func exists(_ name: String) -> Bool { image(named: name) != nil }

    /// 展开时这只吉祥物这个样子的图，缺图回退小熊猫。
    static func image(_ mascot: FocusMascot, _ pose: NotchMascotPose, blinking: Bool) -> NSImage? {
        NotchMascotArt.resolve(mascot, pose, blinking: blinking, exists: { exists($0) }).flatMap(image(named:))
    }
}

/// 专注计时展开后的样子（照效果图）：刘海底边中间垂下一根细绳，小熊猫尾巴缠着绳子倒挂，
/// 两只爪子搭在下面的液态玻璃计时牌上。专注中睁眼、隔几秒眨一下，整只轻轻左右摆；
/// 暂停时闭眼打盹、头上飘「zZ」、时间变淡；刚完成和休息时开心大笑。减弱动态效果时不摆不眨。
private struct NotchIslandHangingFocus: View {
    var model: NotchIslandModel
    var deadline: Date?
    var pausedLeft: TimeInterval?
    var total: TimeInterval
    var secondary: NotchIslandActivity?

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var blinking = false

    private var cardShape: RoundedRectangle { RoundedRectangle(cornerRadius: 24, style: .continuous) }

    var body: some View {
        let geometry = model.geometry
        // 这一套的范围从刘海底边开始（不伸进菜单栏那一条），里面的偏移都从刘海底边量。
        let cardTop = NotchIslandLayout.hangCardTop(geometry) - geometry.notchHeight
        let panda = NotchIslandLayout.hangPanda
        TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1.0 / 30, paused: false)) { tick in
            let state = TimerStateProvider.shared.state
            let mascotState = FocusMascotState.of(state, now: tick.date)
            // 跟随所选吉祥物（没解锁 Pro 时是小熊猫）；它的图还没有时回退倒挂小熊猫，眨眼只在回退时有。
            let mascot = FocusMascot.of(state, unlocked: ProAccess.isUnlocked)
            let pose = NotchMascotPose.of(mascotState)
            let swing = NotchHangingPanda.sway(at: tick.date.timeIntervalSinceReferenceDate,
                                               reduceMotion: reduceMotion || pausedLeft != nil)
            ZStack(alignment: .top) {
                // 计时牌在下面，小熊猫和绳子压在它上面（爪子搭在牌子上沿）。
                card(now: tick.date)
                    .frame(width: NotchIslandLayout.hangWidth,
                           height: NotchIslandLayout.hangCardHeight
                               + (secondary != nil ? NotchIslandLayout.secondaryRowHeight : 0))
                    .offset(y: cardTop)
                ZStack(alignment: .top) {
                    Capsule()
                        .fill(Color(hex: "#F3D9B8"))
                        .frame(width: 2, height: NotchIslandLayout.hangRope + panda * 0.12)
                        .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                    if let image = NotchIslandHanging.image(mascot, pose, blinking: blinking && !reduceMotion) {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: panda, height: panda, alignment: .top)
                            .offset(y: NotchIslandLayout.hangRope)
                            .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.18), radius: 6, y: 3)
                    }
                    // 自己的打盹图已经画了 zz，只在回退小熊猫时补一个。
                    if pose == .sleep,
                       NotchMascotArt.usesPandaFallback(mascot, .sleep, exists: { NotchIslandHanging.exists($0) }) {
                        Text(verbatim: "zZ")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(NotchIslandPalette.accent(scheme))
                            .offset(x: panda * 0.42, y: NotchIslandLayout.hangRope + panda * 0.3)
                            .accessibilityHidden(true)
                    }
                }
                .rotationEffect(.degrees(swing), anchor: .top)
                .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .task(id: reduceMotion) { await blinkLoop() }
    }

    @ViewBuilder private func card(now: Date) -> some View {
        let left = NotchIslandTimer.remaining(deadline: deadline, pausedLeft: pausedLeft, now: now)
        let paused = pausedLeft != nil
        VStack(spacing: 10) {
            Text(verbatim: FocusCycle.caption(TimerStateProvider.shared.state))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.panelSecondary)
                .lineLimit(1)
            Text(verbatim: NotchIslandText.clock(left))
                .font(.system(size: 36, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(paused ? Color.panelSecondary : NotchIslandPalette.accent(scheme))
                .contentTransition(.numericText(countsDown: true))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(spacing: 10) {
                NotchIslandCapsuleButton(title: paused ? tr("继续") : tr("暂停"), solid: true) {
                    model.act?(.timerToggle(.focus))
                }
                NotchIslandCapsuleButton(title: tr("结束"), solid: false) {
                    model.act?(.timerEnd(.focus))
                }
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.panelTrack)
                    Capsule()
                        .fill(NotchIslandPalette.accent(scheme))
                        .frame(width: proxy.size.width * NotchIslandTimer.elapsedFraction(remaining: left, total: total))
                }
            }
            .frame(height: 4)
            .padding(.horizontal, 6)
            .accessibilityHidden(true)
            if let secondary {
                NotchIslandSecondaryRow(activity: secondary)
                    .padding(.top, 4)
            }
        }
        .padding(.top, NotchIslandLayout.hangPawOverlap + 6)
        .padding(.horizontal, 18)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            NotchMessageGlass(shape: cardShape)
                .overlay { cardShape.stroke(Color.panelStroke, lineWidth: 0.6) }
                .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.16), radius: 18, y: 8)
        }
        .contentShape(cardShape)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tr("刘海小岛"))
        .accessibilityValue(NotchIslandText.spoken(
            .timer(deadline: deadline, pausedLeft: pausedLeft, total: total, focus: true), now: now))
    }

    /// 专注中隔 3 到 6 秒眨一下眼（闭眼 0.15 秒）。
    private func blinkLoop() async {
        guard !reduceMotion else { blinking = false; return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(NotchHangingPanda.blinkDelay(Double.random(in: 0...1))))
            if Task.isCancelled { return }
            blinking = true
            try? await Task.sleep(for: .milliseconds(150))
            blinking = false
        }
    }
}
