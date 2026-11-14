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
                    // 刘海那一段留着黑色，卡片从它下面长出来。
                    NotchIslandShape(flare: NotchIslandLayout.topFlare, bottomRadius: 8)
                        .fill(.black)
                        .place(NotchIslandLayout.notch(geometry))
                        .id("island-body")
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
                left
                    .frame(width: wings.left, height: geometry.notchHeight)
                Spacer(minLength: geometry.notchWidth)
                right
                    .frame(width: wings.right, height: geometry.notchHeight)
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
        case .timer:
            EmptyView()
        case .radio:
            Image(systemName: "radio.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NotchIslandPalette.onBlack)
        }
    }

    @ViewBuilder private var right: some View {
        switch activity {
        case .charging(let percent):
            Text(verbatim: NotchIslandText.battery(percent))
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
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
        case .timer:
            EmptyView()
        case .radio(_, let playing):
            NotchIslandWave(playing: playing, tint: NotchIslandPalette.onBlack)
                .frame(width: 20, height: 14)
        }
    }

    @ViewBuilder private var chin: some View {
        if case .timer(let deadline, let pausedLeft, _, _) = activity {
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
        case .timer(let deadline, let pausedLeft, let total, _):
            TimelineView(.periodic(from: .now, by: 1)) { tick in
                let left = NotchIslandTimer.remaining(deadline: deadline, pausedLeft: pausedLeft, now: tick.date)
                NotchIslandRing(fraction: NotchIslandTimer.elapsedFraction(remaining: left, total: total),
                                tint: NotchIslandPalette.onBlack, track: .white.opacity(0.18), lineWidth: 2.5)
                    .padding(7)
            }
        case .radio(_, let playing):
            NotchIslandWave(playing: playing, tint: NotchIslandPalette.onBlack)
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

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 26,
                               bottomTrailingRadius: 26, topTrailingRadius: 10, style: .continuous)
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
        .padding(.top, model.geometry.notchHeight + 12)
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background { surface }
        .contentShape(shape)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tr("刘海小岛"))
    }

    private var surface: some View {
        ZStack(alignment: .top) {
            NotchMessageGlass(shape: shape)
            NotchMessageBlend()
                .frame(width: model.geometry.notchWidth + 24, height: model.geometry.notchHeight + 10)
        }
        .clipShape(shape)
        .overlay { shape.stroke(Color.panelStroke, lineWidth: 0.6) }
        .shadow(color: .black.opacity(scheme == .dark ? 0.35 : 0.16), radius: 18, y: 8)
    }

    @ViewBuilder private var content: some View {
        switch primary {
        case .radio(let station, _):
            NotchIslandRadioCard(model: model, fallbackStation: station)
        case .timer(let deadline, let pausedLeft, let total, _):
            NotchIslandTimerCard(model: model, deadline: deadline, pausedLeft: pausedLeft, total: total)
        case .download(let fraction, let done):
            NotchIslandDownloadCard(model: model, fraction: fraction, done: done)
        case .charging(let percent):
            NotchIslandChargingCard(percent: percent)
        }
    }
}

/// 卡片上的圆形按钮：实心橙（主操作）或薄玻璃。
private struct NotchIslandCircleButton: View {
    var symbol: String
    var label: String
    var solid: Bool
    var enabled = true
    var action: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(solid ? Color.white : Color.panelPrimary)
                .frame(width: 38, height: 38)
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

private struct NotchIslandRadioCard: View {
    var model: NotchIslandModel
    var fallbackStation: String

    @Environment(\.colorScheme) private var scheme

    @MainActor private static let artwork: NSImage? = {
        guard let url = Bundle.main.url(forResource: "RadioMeow", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    var body: some View {
        let radio = RadioPlayer.shared
        let playing = radio.isPlaying
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                artwork
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: radio.station?.name ?? fallbackStation)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.panelPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(verbatim: subtitle(radio, playing: playing))
                            .font(.system(size: 13))
                            .foregroundStyle(.panelSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    HStack(spacing: 10) {
                        NotchIslandCircleButton(symbol: playing ? "pause.fill" : "play.fill",
                                                label: playing ? tr("暂停") : tr("播放"), solid: true) {
                            model.act?(.radioToggle)
                        }
                        NotchIslandCircleButton(symbol: "forward.end.fill", label: tr("下一台"), solid: false,
                                                enabled: model.canSwitchStation) {
                            model.act?(.radioNext)
                        }
                    }
                }
                Spacer(minLength: 0)
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

    private func subtitle(_ radio: RadioPlayer, playing: Bool) -> String {
        if playing, let title = radio.nowTitle, !title.isEmpty { return title }
        if radio.isBuffering { return tr("正在连接") }
        return playing ? tr("正在播放") : tr("已暂停")
    }

    @ViewBuilder private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: "#FFB066"), Color(hex: "#E2650F")],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            if let image = Self.artwork {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(8)
            } else {
                Image(systemName: "radio.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 72, height: 72)
        .accessibilityHidden(true)
    }
}

private struct NotchIslandTimerCard: View {
    var model: NotchIslandModel
    var deadline: Date?
    var pausedLeft: TimeInterval?
    var total: TimeInterval

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let state = TimerStateProvider.shared.state
        TimelineView(.periodic(from: .now, by: 1)) { tick in
            let left = NotchIslandTimer.remaining(deadline: deadline, pausedLeft: pausedLeft, now: tick.date)
            VStack(alignment: .leading, spacing: 10) {
                Text(verbatim: FocusCycle.caption(state))
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
                        model.act?(.timerToggle)
                    }
                    NotchIslandCapsuleButton(title: tr("结束"), solid: false) {
                        model.act?(.timerEnd)
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
                .timer(deadline: deadline, pausedLeft: pausedLeft, total: total, focus: state.phase == .focus),
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
        case .radio: "radio.fill"
        }
    }
}
