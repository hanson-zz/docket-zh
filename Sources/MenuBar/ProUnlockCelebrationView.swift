import AppKit
import SwiftUI

// MARK: - 码头 Pro 解锁成功庆祝动画
//
// 许可证或兑换码第一次激活成功时弹出：屏幕变暗模糊，中间一张 560×760 的卡片。上部是
// 深紫到紫罗兰的夜景，小熊猫站在发光的金色圆台上鞠躬、戴上皇冠、挥手，周围是烟花、
// 彩纸、彩带和金星；下部是奶油白面板，标题、副标题、2×3 功能标签和“开启 Pro 之旅”按钮。
//
// 整个画面都是时间 t 的函数（TimelineView 每帧取一次），时间线、音效调度、标签和
// 首次标记在 Core/ProUnlockCelebrationLogic.swift。“减少动态效果”时 t 固定在最终画面，
// 只响成功音。点小熊猫再鞠一躬、补一轮彩纸，“啵”一声加噼啪。

// MARK: 弹窗

@MainActor
final class ProUnlockCelebration {
    static let shared = ProUnlockCelebration()

    private var panel: ProUnlockPanel?
    /// 正在淡出的上一个面板。
    private var closing: ProUnlockPanel?

    private init() {}

    /// 启动时调用：升级前就已激活的 Mac 补上“已经播过”的标记，以后解绑再激活也不自动弹。
    static func markIfActivatedBefore(isActivated: Bool) {
        let defaults = UserDefaults.standard
        if ProUnlockFirstRun.shouldMarkOnLaunch(isActivated: isActivated,
                                                alreadyShown: defaults.bool(forKey: ProUnlockFirstRun.shownKey)) {
            defaults.set(true, forKey: ProUnlockFirstRun.shownKey)
        }
    }

    /// 许可证或兑换码激活成功。第一次才自动播放，先记标记再弹，弹的过程中出什么事也不会弹第二次。
    func activationSucceeded() {
        let defaults = UserDefaults.standard
        guard ProUnlockFirstRun.shouldAutoPlay(activationSucceeded: true,
                                               alreadyShown: defaults.bool(forKey: ProUnlockFirstRun.shownKey))
        else { return }
        defaults.set(true, forKey: ProUnlockFirstRun.shownKey)
        show()
    }

    /// 设置 ▸ 码头 Pro ▸ 关于 Pro ▸ 重看解锁动画。
    func replay() {
        show()
    }

    private func show() {
        close(animated: false)
        let screen = NSApp.keyWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        // 关掉音效时不必读 WAV。
        if ProUnlockSoundPlayer.isEnabled { ProUnlockSoundPlayer.shared.preload() }

        let panel = ProUnlockPanel(contentRect: screen.frame, styleMask: [.borderless],
                                   backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .modalPanel
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.title = tr("解锁成功，谢谢你！")
        panel.onClose = { [weak self] in self?.close(animated: true) }

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let root = ProUnlockOverlay(reduceMotion: reduceMotion) { [weak self] in
            self?.close(animated: true)
        }
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: screen.frame.size)
        panel.contentView = hosting
        panel.setFrame(screen.frame, display: true)
        self.panel = panel
        panel.orderFrontRegardless()
        NSApp.activate()
        panel.makeKey()
    }

    private func close(animated: Bool) {
        ProUnlockSoundPlayer.shared.stop()
        finishClosing()
        guard let panel else { return }
        self.panel = nil
        panel.onClose = nil
        guard animated else {
            panel.orderOut(nil)
            panel.contentView = nil
            return
        }
        closing = panel
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                self?.finishClosing()
            }
        }
    }

    /// 淡出结束（或又要弹新的一个）时把正在淡出的面板收掉。
    private func finishClosing() {
        guard let closing else { return }
        self.closing = nil
        closing.orderOut(nil)
        closing.contentView = nil
    }
}

/// 无边框的全屏面板：能成为 key 窗口，接收 Esc 和 ⌘W。
final class ProUnlockPanel: NSPanel {
    var onClose: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onClose?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onClose?() } else { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "w" {
            onClose?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: 全屏背景

/// 整个屏幕：变暗加模糊，中间是卡片。时间从这里开始算，声音也从这里排。
struct ProUnlockOverlay: View {
    let reduceMotion: Bool
    let onClose: () -> Void

    @State private var start = Date()
    @State private var taps: [Double] = []

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { context in
            let t = reduceMotion ? ProUnlockScene.stillTime : context.date.timeIntervalSince(start)
            let dim = ProUnlockTimeline.progress(t, from: 0, length: 0.35)
            ZStack {
                VisualEffectPlate(material: .fullScreenUI, blending: .behindWindow)
                    .opacity(0.92 * dim)
                Color.black.opacity(0.38 * dim)
                ProUnlockCard(t: t, still: reduceMotion, taps: taps, onTapPanda: tapPanda, onClose: onClose)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            start = Date()
            let cues = ProUnlockSoundSchedule.cues(soundOn: ProUnlockSoundPlayer.isEnabled,
                                                   reduceMotion: reduceMotion,
                                                   chipCount: ProUnlockHighlights.chips.count)
            ProUnlockSoundPlayer.shared.play(cues)
        }
        .onExitCommand(perform: onClose)
    }

    private func tapPanda() {
        guard !reduceMotion else { return }
        let now = Date().timeIntervalSince(start)
        // 只留最近几次，数组不会越来越长。
        taps = Array((taps + [now]).suffix(6))
        ProUnlockSoundPlayer.shared.add(ProUnlockSoundSchedule.pandaTap)
    }
}

// MARK: 卡片

/// 卡片里各元素的位置（卡片坐标，左上角为原点）和固定的场景数据。
enum ProUnlockScene {
    static let size = CGSize(width: ProUnlockLayout.cardWidth, height: ProUnlockLayout.cardHeight)
    static let sceneHeight = ProUnlockLayout.cardHeight * ProUnlockLayout.sceneFraction
    /// “减少动态效果”时停在的时刻：最终画面。
    static let stillTime: Double = 3.4

    /// 熊猫：容器中心和大小，图都按高度 290 等比放。
    static let pandaCenter = CGPoint(x: 280, y: 250)
    static let pandaSize = CGSize(width: 300, height: 290)
    /// 皇冠在戴皇冠的图（509×640）里的位置是 (190, 0, 158, 132)，换成相对熊猫容器中心的偏移。
    static let crownScale = 290.0 / 640.0
    static let crownSize = CGSize(width: 158 * crownScale, height: 132 * crownScale)
    static let crownOffset = CGSize(width: (190 + 79 - 254.5) * crownScale, height: 66 * crownScale - 145)

    static let pedestal = CGPoint(x: 280, y: 396)
    static let glowCenter = CGPoint(x: 280, y: 240)
    static let leftGift = CGPoint(x: 62, y: 368)
    static let rightGift = CGPoint(x: 490, y: 364)
    static let ticket = CGPoint(x: 112, y: 396)
    static let badge = CGPoint(x: 412, y: 150)
    /// 面板顶部圆弧：两边在 sceneHeight，中间最高处。
    static let panelArcTop: CGFloat = 424
}

private extension Color {
    init(rgb: UInt32, opacity: Double = 1) {
        self.init(red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255, opacity: opacity)
    }
}

/// 卡片本身：每一帧按 t 算出所有元素的位置、透明度和变换。
private struct ProUnlockCard: View {
    let t: Double
    let still: Bool
    let taps: [Double]
    let onTapPanda: () -> Void
    let onClose: () -> Void

    private typealias T = ProUnlockTimeline
    private typealias S = ProUnlockScene
    private typealias L = ProUnlockLayout

    var body: some View {
        ZStack(alignment: .topLeading) {
            night
            ProUnlockBackCanvas(t: t, still: still)
            halo
            props
            panda
            badge
            ProUnlockFrontCanvas(t: t, still: still, taps: taps)
            panel
            ticket
            ProUnlockGlints(t: t, still: still)
            texts
        }
        .frame(width: S.size.width, height: S.size.height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: L.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: L.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
        }
        .shadow(color: Color(rgb: 0x1A0B3A, opacity: 0.45), radius: 40, y: 18)
        .scaleEffect(cardScale)
        .opacity(T.progress(t, from: 0, length: 0.15))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("解锁成功，谢谢你！"))
    }

    // MARK: 曲线

    private func p(_ start: Double, _ length: Double) -> Double { T.progress(t, from: start, length: length) }

    /// 弹性缓出：略微冲过 1 再回来。
    private func springOut(_ x: Double) -> Double {
        guard x < 1 else { return 1 }
        return 1 - exp(-6 * x) * cos(9 * x)
    }

    private func easeOut(_ x: Double) -> Double { 1 - pow(1 - min(1, max(0, x)), 3) }

    private var cardScale: CGFloat { 0.85 + 0.15 * springOut(p(0, 0.45)) }

    /// 一次鞠躬的幅度（0 到 1 再回 0）。
    private func bowCurve(_ age: Double) -> Double {
        guard age >= 0, age <= 0.55 else { return 0 }
        return sin(.pi * age / 0.55)
    }

    /// 第一次鞠躬（0.45 秒）和点熊猫补的几次。
    private var tapBow: Double { taps.map { bowCurve(t - $0) }.max() ?? 0 }
    private var bow: Double { max(bowCurve(t - 0.45), tapBow) }

    // MARK: 夜景

    private var night: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(rgb: 0x1B1142), Color(rgb: 0x3A1D6E), Color(rgb: 0x6A34A0)],
                           startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.62))
            // 熊猫身后的金色背光。
            RadialGradient(colors: [Color(rgb: 0xFFD27A, opacity: 0.75), Color(rgb: 0xFFAA4C, opacity: 0.28), .clear],
                           center: UnitPoint(x: S.glowCenter.x / S.size.width, y: S.glowCenter.y / S.size.height),
                           startRadius: 6, endRadius: 250)
                .opacity(0.35 + 0.65 * p(0.2, 0.7))
        }
        .frame(width: S.size.width, height: S.size.height)
    }

    /// 1.0 秒起转起来的金色光环。
    private var halo: some View {
        let shown = p(T.badgeAt, 0.35)
        return ZStack {
            Circle()
                .strokeBorder(
                    AngularGradient(colors: [Color(rgb: 0xFFE7A0), Color(rgb: 0xFFB43C, opacity: 0.2),
                                             Color(rgb: 0xFFE7A0), Color(rgb: 0xFFB43C, opacity: 0.2), Color(rgb: 0xFFE7A0)],
                                    center: .center),
                    style: StrokeStyle(lineWidth: 3, dash: [14, 9]))
                .frame(width: 290, height: 290)
            Circle()
                .strokeBorder(Color(rgb: 0xFFD98A, opacity: 0.35), lineWidth: 1.2)
                .frame(width: 318, height: 318)
        }
        .rotationEffect(.degrees((t - T.badgeAt) * 38))
        .scaleEffect(0.6 + 0.4 * springOut(shown))
        .opacity(shown * 0.85)
        .position(x: S.glowCenter.x, y: S.glowCenter.y + 6)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: 圆台和礼盒

    private var props: some View {
        ZStack(alignment: .topLeading) {
            pedestal.position(S.pedestal)
            gift(mirrored: false, width: 112, pop: springOut(p(0.22, 0.5)))
                .position(S.leftGift)
            gift(mirrored: true, width: 138, pop: springOut(p(0.3, 0.5)))
                .position(S.rightGift)
        }
        .frame(width: S.size.width, height: S.size.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var pedestal: some View {
        let shown = p(0.05, 0.3)
        let pulse = 0.85 + 0.15 * sin(t * 2.4)
        return ZStack {
            Ellipse()
                .fill(RadialGradient(colors: [Color(rgb: 0xFFE08A, opacity: 0.85 * pulse), Color(rgb: 0xFFB347, opacity: 0.25), .clear],
                                     center: .center, startRadius: 4, endRadius: 170))
                .frame(width: 360, height: 110)
            Ellipse()
                .fill(LinearGradient(colors: [Color(rgb: 0xC98A1E), Color(rgb: 0x8A5410)], startPoint: .top, endPoint: .bottom))
                .frame(width: 252, height: 54)
                .offset(y: 10)
            Ellipse()
                .fill(LinearGradient(colors: [Color(rgb: 0xFFF1B8), Color(rgb: 0xF5C04A), Color(rgb: 0xE09A22)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 252, height: 48)
                .overlay(Ellipse().strokeBorder(Color(rgb: 0xFFF6D6, opacity: 0.9), lineWidth: 1.5))
            Ellipse()
                .fill(RadialGradient(colors: [Color.white.opacity(0.75), .clear], center: .center, startRadius: 2, endRadius: 90))
                .frame(width: 180, height: 26)
                .offset(y: -3)
        }
        .scaleEffect(0.7 + 0.3 * easeOut(shown))
        .opacity(shown)
    }

    private func gift(mirrored: Bool, width: CGFloat, pop: Double) -> some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(rgb: 0xFFE9A0, opacity: 0.8), .clear], center: .center, startRadius: 2, endRadius: 70))
                .frame(width: 140, height: 140)
                .offset(y: -24)
            ProUnlockArt.image("unlock-gift")
                .resizable()
                .scaledToFit()
                .frame(width: width)
                .scaleEffect(x: mirrored ? -1 : 1, y: 1)
        }
        .scaleEffect(0.4 + 0.6 * pop, anchor: .bottom)
        .opacity(min(1, pop * 3))
    }

    // MARK: 熊猫

    private var panda: some View {
        let jump = 180 * (1 - springOut(p(0.06, 0.55)))
        let crownIn = p(T.crownLandAt, 0.12)
        var waveIn = p(T.waveAt, 0.22)
        // 挥手时点熊猫：换回戴皇冠鞠躬的图。
        waveIn *= 1 - min(1, tapBow * 3)
        let wobble = 3 * sin(2 * .pi * 6 * t) * bow
        let wave = t >= T.waveAt ? 2.2 * sin(2 * .pi * 1.1 * (t - T.waveAt)) * waveIn : 0
        return ZStack {
            image(.bow).opacity(1 - crownIn)
            image(.crown).opacity(crownIn * (1 - waveIn))
            image(.wave).opacity(waveIn)
            fallingCrown
        }
        .frame(width: S.pandaSize.width, height: S.pandaSize.height)
        .scaleEffect(x: 1 + 0.02 * bow, y: 1 - 0.07 * bow, anchor: .bottom)
        .rotationEffect(.degrees(wobble + wave), anchor: .bottom)
        .offset(y: 6 * bow + jump)
        .opacity(p(0.06, 0.12))
        .contentShape(Rectangle())
        .onTapGesture(perform: onTapPanda)
        .position(S.pandaCenter)
        .accessibilityElement()
        .accessibilityLabel(Text("小熊猫"))
        .accessibilityAddTraits(.isButton)
    }

    private func image(_ pose: ProUnlockPose) -> some View {
        ProUnlockArt.image(pose.rawValue)
            .resizable()
            .scaledToFit()
            .frame(height: S.pandaSize.height)
    }

    /// 0.55 秒从上方落下，0.9 秒落到头上，之后换成戴皇冠的图。
    private var fallingCrown: some View {
        let fall = p(T.crownDropAt, T.crownLandAt - T.crownDropAt)
        let drop = 230 * (1 - fall * fall)
        let visible = t >= T.crownDropAt && t < T.crownLandAt + 0.12
        return ProUnlockArt.image("unlock-crown")
            .resizable()
            .frame(width: S.crownSize.width, height: S.crownSize.height)
            .rotationEffect(.degrees(-18 * (1 - fall)))
            .offset(x: S.crownOffset.width, y: S.crownOffset.height - drop)
            .opacity(visible ? p(T.crownDropAt, 0.06) * (1 - p(T.crownLandAt, 0.12)) : 0)
    }

    // MARK: PRO 徽章

    private var badge: some View {
        let shown = p(T.badgeAt, 0.6)
        return ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(rgb: 0xFFE9A6, opacity: 0.7), .clear], center: .center, startRadius: 2, endRadius: 50))
                .frame(width: 100, height: 100)
            Circle()
                .fill(LinearGradient(colors: [Color(rgb: 0xFFE68A), Color(rgb: 0xF2B233), Color(rgb: 0xC77C12)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 58, height: 58)
                .overlay(Circle().strokeBorder(Color(rgb: 0xFFF5CC), lineWidth: 2.5).padding(4))
                .shadow(color: Color(rgb: 0x8A4A00, opacity: 0.4), radius: 4, y: 2)
            Text(verbatim: "PRO")
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(Color(rgb: 0x7A3F00))
        }
        .rotation3DEffect(.degrees(540 * (1 - easeOut(shown))), axis: (x: 0, y: 1, z: 0))
        .scaleEffect(0.3 + 0.7 * springOut(shown))
        .offset(y: -14 * sin(.pi * shown))
        .opacity(min(1, shown * 4))
        .position(S.badge)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: 奶油白面板

    private var panel: some View {
        ProUnlockPanelShape(edge: S.sceneHeight, crest: S.panelArcTop)
            .fill(LinearGradient(colors: [Color(rgb: 0xFFFBF3), Color(rgb: 0xFFF4E4)], startPoint: .top, endPoint: .bottom))
            .shadow(color: Color(rgb: 0x2A1050, opacity: 0.35), radius: 12, y: -4)
            .frame(width: S.size.width, height: S.size.height)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: PRO 票券（左下）

    private var ticket: some View {
        let fly = springOut(p(0.36, 0.6))
        return ProUnlockArt.image("unlock-ticket")
            .resizable()
            .scaledToFit()
            .frame(width: 128)
            .shadow(color: Color(rgb: 0x5A3000, opacity: 0.35), radius: 6, y: 3)
            .rotationEffect(.degrees(-14 - 30 * (1 - fly)))
            .offset(x: -170 * (1 - fly), y: 120 * (1 - fly))
            .opacity(min(1, fly * 3))
            .position(S.ticket)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: 文字、标签、按钮

    private var texts: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: S.panelArcTop + 44)
            title
            subtitle.padding(.top, 6)
            chips.padding(.top, 20)
            Spacer(minLength: 0)
            button.padding(.bottom, 26)
        }
        .padding(.horizontal, L.panelPadding)
        .frame(width: S.size.width, height: S.size.height)
    }

    private var title: some View {
        let shown = p(T.titleAt, 0.4)
        return HStack(spacing: 8) {
            ProUnlockSparks(mirrored: false)
            Text("解锁成功，谢谢你！")
                .font(.system(size: L.titleFontSize, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(rgb: 0x4A2814))
                .lineLimit(1)
                .minimumScaleFactor(L.minimumScale)
            ProUnlockSparks(mirrored: true)
        }
        .frame(maxWidth: L.contentWidth)
        .scaleEffect(0.85 + 0.15 * springOut(shown))
        .offset(y: 10 * (1 - easeOut(shown)))
        .opacity(min(1, shown * 2.5))
    }

    private var subtitle: some View {
        let shown = p(T.subtitleAt, 0.35)
        return Text("恭喜码头 Pro 已激活，一次购买，永久使用")
            .font(.system(size: L.subtitleFontSize, weight: .medium, design: .rounded))
            .foregroundStyle(Color(rgb: 0x7A5A44))
            .lineLimit(1)
            .minimumScaleFactor(L.minimumScale)
            .offset(y: 6 * (1 - easeOut(shown)))
            .opacity(shown)
    }

    private var chips: some View {
        let all = ProUnlockHighlights.chips
        let rows = stride(from: 0, to: all.count, by: L.chipColumns).map { Array(all.indices[$0..<min($0 + L.chipColumns, all.count)]) }
        return VStack(spacing: L.chipSpacing) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: L.chipSpacing) {
                    ForEach(row, id: \.self) { index in
                        chip(all[index], index: index)
                    }
                }
            }
        }
    }

    private func chip(_ chip: ProUnlockHighlights.Chip, index: Int) -> some View {
        let shown = p(T.chipTime(index), 0.32)
        let colors = ProUnlockChipColors.colors(chip.tint)
        return HStack(spacing: L.chipIconSpacing) {
            if let symbol = chip.symbol {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: L.chipIconWidth)
            }
            Text(chip.title)
                .font(.system(size: chip.symbol == nil ? 15 : L.chipFontSize, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(L.minimumScale)
        }
        .foregroundStyle(colors.foreground)
        .padding(.horizontal, L.chipHorizontalPadding)
        .frame(width: L.chipWidth, height: L.chipHeight)
        .background(Capsule().fill(colors.background))
        .overlay(Capsule().strokeBorder(colors.foreground.opacity(0.18), lineWidth: 1))
        .scaleEffect(0.4 + 0.6 * springOut(shown))
        .opacity(min(1, shown * 3))
    }

    private var button: some View {
        let shown = p(T.buttonAt - 0.1, 0.35)
        let breath = t >= T.buttonAt ? 0.5 + 0.5 * sin(2 * .pi * 0.75 * (t - T.buttonAt)) : 0
        return Button(action: onClose) {
            Text("开启 Pro 之旅 ›")
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(L.minimumScale)
                .frame(width: L.contentWidth, height: 54)
                .background(
                    Capsule().fill(LinearGradient(colors: [Color(rgb: 0xFFA845), Color(rgb: 0xFF7A2E), Color(rgb: 0xF2562A)],
                                                  startPoint: .leading, endPoint: .trailing))
                )
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.4 + 0.3 * breath), lineWidth: 1.2))
                .shadow(color: Color(rgb: 0xFF7A2E, opacity: 0.35 + 0.3 * breath), radius: 10 + 10 * breath, y: 4)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
        .scaleEffect(1 + 0.012 * breath)
        .offset(y: 12 * (1 - easeOut(shown)))
        .opacity(shown)
        .allowsHitTesting(shown > 0.5)
    }
}

/// 奶油白面板：两边从夜景 60% 处开始，顶部是一道往上鼓的圆弧。
private struct ProUnlockPanelShape: Shape {
    var edge: CGFloat
    var crest: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: edge))
        // 二次曲线的控制点要比顶点再高一倍的差，弧顶才正好落在 crest。
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: edge),
                          control: CGPoint(x: rect.midX, y: crest - (edge - crest)))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// 标签的颜色。
private enum ProUnlockChipColors {
    static func colors(_ tint: ProUnlockHighlights.Tint) -> (foreground: Color, background: Color) {
        switch tint {
        case .orange: (Color(rgb: 0xE2621A), Color(rgb: 0xFFE8D4))
        case .blue: (Color(rgb: 0x2C74E0), Color(rgb: 0xDFEBFF))
        case .purple: (Color(rgb: 0x7A45D6), Color(rgb: 0xEEE4FF))
        case .green: (Color(rgb: 0x2A9452), Color(rgb: 0xDDF4E3))
        case .pink: (Color(rgb: 0xDC3F6A), Color(rgb: 0xFFE1E9))
        case .gray: (Color(rgb: 0x7A716A), Color(rgb: 0xEFEBE6))
        }
    }
}

/// 标题两侧的三道橙色小光芒。
private struct ProUnlockSparks: View {
    let mirrored: Bool

    var body: some View {
        Canvas { context, size in
            let origin = CGPoint(x: mirrored ? 2 : size.width - 2, y: size.height / 2)
            let direction: CGFloat = mirrored ? 1 : -1
            for (angle, length) in [(-0.6, 11.0), (0.0, 15.0), (0.6, 11.0)] as [(Double, Double)] {
                var path = Path()
                path.move(to: CGPoint(x: origin.x + direction * 4 * cos(angle), y: origin.y + 4 * sin(angle)))
                path.addLine(to: CGPoint(x: origin.x + direction * (4 + length) * cos(angle),
                                         y: origin.y + (4 + length) * sin(angle)))
                context.stroke(path, with: .color(Color(rgb: 0xFF8A2A)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }
        .frame(width: ProUnlockLayout.titleSparkWidth - 8, height: 32)
        .accessibilityHidden(true)
    }
}

/// Resources/Unlock 里的图，读一次。
@MainActor
private enum ProUnlockArt {
    private static var cache: [String: NSImage] = [:]

    static func image(_ name: String) -> Image {
        if let image = cache[name] { return Image(nsImage: image) }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return Image(systemName: "photo") }
        cache[name] = image
        return Image(nsImage: image)
    }
}

// MARK: - 粒子

/// 可复现的随机数（SplitMix64）：同一个种子每次生成一样的彩纸，重播稳定。
private struct ProUnlockRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func value(_ range: ClosedRange<Double>) -> Double { Double.random(in: range, using: &self) }
}

/// 粒子用的颜色：粉、金、青、紫、绿、橙。
private enum ProUnlockPalette {
    static let colors: [UInt32] = [0xFF5FA2, 0xFFC83D, 0x4FD1FF, 0xB07CFF, 0x6EE7A0, 0xFF8A3D]
    static func color(_ index: Int, opacity: Double = 1) -> Color { Color(rgb: colors[abs(index) % colors.count], opacity: opacity) }
}

private struct ProUnlockConfetti {
    var birth: Double
    var x: Double
    var y: Double
    var vx: Double
    var vy: Double
    var color: Int
    var width: Double
    var height: Double
    var angle: Double
    var spin: Double
    var flutter: Double
    var frequency: Double
    var phase: Double
    /// “减少动态效果”时停在的年龄。
    var stillAge: Double

    static func burst(count: Int, seed: UInt64, birth: Double) -> [ProUnlockConfetti] {
        var rng = ProUnlockRandom(seed: seed)
        return (0..<count).map { index in
            let ribbonLike = index % 3 == 0
            return ProUnlockConfetti(
                birth: birth + rng.value(0...0.3), x: rng.value(-10...570), y: rng.value(-80 ... -10),
                vx: rng.value(-90...90), vy: rng.value(-40...200), color: index,
                width: ribbonLike ? 11 : 7, height: ribbonLike ? 3.5 : 6,
                angle: rng.value(0...(2 * .pi)), spin: rng.value(-7...7), flutter: rng.value(6...20),
                frequency: rng.value(3...7), phase: rng.value(0...(2 * .pi)), stillAge: rng.value(0.25...1.7))
        }
    }

    static let gravity = 480.0
    static let drag = 2.6

    /// 某个年龄的位置、角度、翻转和透明度；没出生或已经掉出夜景时为 nil。
    func state(age: Double, floor: Double) -> (point: CGPoint, angle: Double, flip: Double, opacity: Double)? {
        guard age >= 0 else { return nil }
        let k = Self.drag
        let terminal = Self.gravity / k
        let decay = (1 - exp(-k * age)) / k
        let py = y + terminal * age + (vy - terminal) * decay
        guard py < floor else { return nil }
        let px = x + vx * decay + flutter * sin(frequency * age + phase) * min(1, age * 2)
        let fade = min(1, (floor - py) / 60) * min(1, age / 0.08)
        return (CGPoint(x: px, y: py), angle + spin * age, cos(frequency * 1.3 * age + phase), fade)
    }
}

private struct ProUnlockFirework {
    var center: CGPoint
    var radius: Double
    var birth: Double
    var colors: [Int]
    var rays: Int
}

private struct ProUnlockRibbon {
    var x: Double
    var rest: Double
    var birth: Double
    var colors: (Int, Int)
    var curl: Double
    var phase: Double
}

private struct ProUnlockStar {
    var center: CGPoint
    var radius: Double
    var speed: Double
    var phase: Double
}

private enum ProUnlockParticles {
    static let confetti = ProUnlockConfetti.burst(count: 90, seed: 11, birth: 0.45)

    /// 左右两发大的（1.0、1.3 秒，和音效对齐），再各补一朵小的。
    static let fireworks = [
        ProUnlockFirework(center: CGPoint(x: 112, y: 104), radius: 80, birth: ProUnlockTimeline.leftFireworkAt, colors: [0, 1, 2], rays: 22),
        ProUnlockFirework(center: CGPoint(x: 448, y: 92), radius: 86, birth: ProUnlockTimeline.rightFireworkAt, colors: [3, 1, 4], rays: 24),
        ProUnlockFirework(center: CGPoint(x: 64, y: 232), radius: 44, birth: 1.5, colors: [2, 5], rays: 16),
        ProUnlockFirework(center: CGPoint(x: 504, y: 226), radius: 48, birth: 1.62, colors: [0, 4], rays: 16),
    ]

    static let ribbons: [ProUnlockRibbon] = {
        var rng = ProUnlockRandom(seed: 5)
        return (0..<6).map { index in
            let left = index % 2 == 0
            return ProUnlockRibbon(x: left ? rng.value(18...96) : rng.value(464...542), rest: rng.value(250...410),
                                   birth: 0.45 + Double(index) * 0.08, colors: (index % 6, (index + 2) % 6),
                                   curl: rng.value(0.24...0.34), phase: rng.value(0...(2 * .pi)))
        }
    }()

    static let stars: [ProUnlockStar] = [
        ProUnlockStar(center: CGPoint(x: 168, y: 170), radius: 13, speed: 2.1, phase: 0.3),
        ProUnlockStar(center: CGPoint(x: 392, y: 300), radius: 14, speed: 2.6, phase: 1.4),
        ProUnlockStar(center: CGPoint(x: 150, y: 318), radius: 10, speed: 3.0, phase: 2.2),
        ProUnlockStar(center: CGPoint(x: 290, y: 44), radius: 8, speed: 2.4, phase: 0.8),
        ProUnlockStar(center: CGPoint(x: 40, y: 150), radius: 7, speed: 3.2, phase: 2.9),
        ProUnlockStar(center: CGPoint(x: 526, y: 150), radius: 8, speed: 2.8, phase: 1.1),
        ProUnlockStar(center: CGPoint(x: 432, y: 236), radius: 9, speed: 1.9, phase: 0.1),
        ProUnlockStar(center: CGPoint(x: 210, y: 70), radius: 6, speed: 3.4, phase: 2.5),
        ProUnlockStar(center: CGPoint(x: 360, y: 52), radius: 6, speed: 2.2, phase: 1.8),
    ]

    static func starPath(center: CGPoint, outer: Double) -> Path {
        var path = Path()
        path.addLines((0..<10).map { i in
            let r = i % 2 == 0 ? outer : outer * 0.45
            let a = -Double.pi / 2 + Double(i) * .pi / 5
            return CGPoint(x: center.x + r * cos(a), y: center.y + r * sin(a))
        })
        path.closeSubpath()
        return path
    }
}

/// 熊猫身后：旋转的金色光芒、烟花、金星。
private struct ProUnlockBackCanvas: View {
    let t: Double
    let still: Bool

    var body: some View {
        Canvas { context, _ in
            drawRays(&context)
            let level = ProUnlockTimeline.fireworkLevel(at: t)
            for burst in ProUnlockParticles.fireworks {
                drawFirework(&context, burst, level: level)
            }
            let starsIn = ProUnlockTimeline.progress(t, from: 0.5, length: 0.3)
            for star in ProUnlockParticles.stars {
                let twinkle = still ? 0.9 : 0.65 + 0.35 * sin(star.speed * t + star.phase)
                let opacity = starsIn * twinkle
                guard opacity > 0.01 else { continue }
                let path = ProUnlockParticles.starPath(center: star.center, outer: star.radius * (0.8 + 0.2 * twinkle))
                context.fill(path, with: .linearGradient(
                    Gradient(colors: [Color(rgb: 0xFFF0A0, opacity: opacity), Color(rgb: 0xF5A623, opacity: opacity)]),
                    startPoint: CGPoint(x: star.center.x, y: star.center.y - star.radius),
                    endPoint: CGPoint(x: star.center.x, y: star.center.y + star.radius)))
            }
        }
        .frame(width: ProUnlockScene.size.width, height: ProUnlockScene.sceneHeight + 20)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawRays(_ context: inout GraphicsContext) {
        let opacity = ProUnlockTimeline.progress(t, from: 0.25, length: 0.8)
        guard opacity > 0.01 else { return }
        let center = ProUnlockScene.glowCenter
        let count = 16
        let half = 0.07
        let length = 420.0
        let turn = t * 0.12
        var path = Path()
        for k in 0..<count {
            let a = Double(k) / Double(count) * 2 * .pi + turn
            path.move(to: center)
            path.addLine(to: CGPoint(x: center.x + length * cos(a - half), y: center.y + length * sin(a - half)))
            path.addLine(to: CGPoint(x: center.x + length * cos(a + half), y: center.y + length * sin(a + half)))
            path.closeSubpath()
        }
        context.fill(path, with: .radialGradient(
            Gradient(colors: [Color(rgb: 0xFFD98A, opacity: 0.4 * opacity), Color(rgb: 0xFFC060, opacity: 0.12 * opacity), .clear]),
            center: center, startRadius: 30, endRadius: 330))
    }

    private func drawFirework(_ context: inout GraphicsContext, _ burst: ProUnlockFirework, level: Double) {
        let age = t - burst.birth
        // 升空的拖尾：爆开前 0.3 秒从下方升上来。
        if !still, age < 0, age > -0.3 {
            let rise = 1 + age / 0.3
            let from = CGPoint(x: burst.center.x + 10, y: burst.center.y + 170)
            let head = CGPoint(x: from.x + (burst.center.x - from.x) * rise, y: from.y + (burst.center.y - from.y) * rise)
            var trail = Path()
            trail.move(to: CGPoint(x: head.x + 3, y: head.y + 40))
            trail.addLine(to: head)
            context.stroke(trail, with: .linearGradient(Gradient(colors: [.clear, Color(rgb: 0xFFF2C0)]),
                                                        startPoint: CGPoint(x: head.x, y: head.y + 40), endPoint: head),
                           style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        }
        guard still || age >= 0 else { return }
        let grown = still ? 1 : 1 - pow(1 - min(1, age / 0.5), 3)
        let inner = still ? 0.35 : 0.2 + 0.3 * min(1, max(0, age - 0.1) / 0.8)
        let sag = still ? 6 : 10 * min(1, age / 1.2)
        let flash = still ? 0 : max(0, 1 - age / 0.18)
        let opacity = (still ? 0.6 : level)
        guard opacity > 0.01 else { return }
        let c = burst.center
        if flash > 0 {
            let r = 26 * flash
            context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                         with: .radialGradient(Gradient(colors: [Color.white.opacity(0.9 * flash), .clear]),
                                               center: c, startRadius: 0, endRadius: r))
        }
        for i in 0..<burst.rays {
            let a = Double(i) / Double(burst.rays) * 2 * .pi
            let scale = i % 2 == 0 ? 1.0 : 0.74
            let outer = burst.radius * grown * scale
            let start = burst.radius * inner * scale * grown
            let color = ProUnlockPalette.color(burst.colors[i % burst.colors.count], opacity: opacity)
            let p1 = CGPoint(x: c.x + start * cos(a), y: c.y + start * sin(a) + sag * 0.4)
            let p2 = CGPoint(x: c.x + outer * cos(a), y: c.y + outer * sin(a) + sag)
            var path = Path()
            path.move(to: p1)
            path.addLine(to: p2)
            context.stroke(path, with: .linearGradient(Gradient(colors: [color.opacity(0), color]), startPoint: p1, endPoint: p2),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round))
            let dot = 2.4
            context.fill(Path(ellipseIn: CGRect(x: p2.x - dot, y: p2.y - dot, width: dot * 2, height: dot * 2)), with: .color(color))
        }
    }
}

/// 熊猫前面：彩纸和彩带（只在夜景里，落到面板前淡出）。
private struct ProUnlockFrontCanvas: View {
    let t: Double
    let still: Bool
    let taps: [Double]

    var body: some View {
        Canvas { context, _ in
            for ribbon in ProUnlockParticles.ribbons {
                drawRibbon(&context, ribbon)
            }
            let floor = ProUnlockScene.sceneHeight - 10
            for piece in ProUnlockParticles.confetti {
                draw(&context, piece, age: still ? piece.stillAge : t - piece.birth, floor: floor)
            }
            guard !still else { return }
            for tap in taps {
                // 种子跟着点的时刻走，不跟数组下标：只留最近 6 次时前面的被挤掉，
                // 后面几次的下标会变，用下标做种子会让半空中的彩纸突然换一批。
                for piece in ProUnlockConfetti.burst(count: 50, seed: 100 &+ UInt64(max(0, tap) * 1000), birth: tap) {
                    draw(&context, piece, age: t - piece.birth, floor: floor)
                }
            }
        }
        .frame(width: ProUnlockScene.size.width, height: ProUnlockScene.sceneHeight + 20)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func draw(_ context: inout GraphicsContext, _ piece: ProUnlockConfetti, age: Double, floor: Double) {
        guard let state = piece.state(age: age, floor: floor), state.opacity > 0.01 else { return }
        var c = context
        c.translateBy(x: state.point.x, y: state.point.y)
        c.rotate(by: .radians(state.angle))
        c.scaleBy(x: max(0.2, abs(state.flip)), y: 1)
        let rect = CGRect(x: -piece.width / 2, y: -piece.height / 2, width: piece.width, height: piece.height)
        let shade = state.flip < 0 ? 0.8 : 1
        c.fill(Path(roundedRect: rect, cornerRadius: 1),
               with: .color(ProUnlockPalette.color(piece.color, opacity: state.opacity * shade)))
    }

    /// 彩带：从上方落下，停在两侧轻轻摆动，渐变两色。
    private func drawRibbon(_ context: inout GraphicsContext, _ ribbon: ProUnlockRibbon) {
        let age = still ? 3 : t - ribbon.birth
        guard age >= 0 else { return }
        let fall = 1 - pow(1 - min(1, age / 1.3), 3)
        let head = -40 + (ribbon.rest + 40) * fall
        let sway = still ? 0 : sin(t * 1.6 + ribbon.phase) * 5
        let points = (0..<26).map { j -> CGPoint in
            let along = Double(j)
            return CGPoint(x: ribbon.x + 12 * sin(along * ribbon.curl + ribbon.phase + age * 1.8) + sway * along / 26,
                           y: head - along * 7)
        }
        var path = Path()
        path.addLines(points)
        let from = points.first ?? .zero
        let to = points.last ?? .zero
        context.stroke(path, with: .linearGradient(
            Gradient(colors: [ProUnlockPalette.color(ribbon.colors.0, opacity: 0.95), ProUnlockPalette.color(ribbon.colors.1, opacity: 0.6)]),
            startPoint: from, endPoint: to),
                       style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
    }
}

/// 2.0 秒起一道星光扫过皇冠，稍后扫过票券。
private struct ProUnlockGlints: View {
    let t: Double
    let still: Bool

    var body: some View {
        Canvas { context, _ in
            guard !still else { return }
            let crown = CGPoint(x: ProUnlockScene.pandaCenter.x + ProUnlockScene.crownOffset.width,
                                y: ProUnlockScene.pandaCenter.y + ProUnlockScene.crownOffset.height)
            glint(&context, from: CGPoint(x: crown.x - 36, y: crown.y + 8), to: CGPoint(x: crown.x + 36, y: crown.y - 12),
                  start: ProUnlockTimeline.shimmerAt, length: 0.35)
            let ticket = ProUnlockScene.ticket
            glint(&context, from: CGPoint(x: ticket.x - 55, y: ticket.y + 18), to: CGPoint(x: ticket.x + 55, y: ticket.y - 22),
                  start: ProUnlockTimeline.shimmerAt + 0.18, length: 0.35)
        }
        .frame(width: ProUnlockScene.size.width, height: ProUnlockScene.size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func glint(_ context: inout GraphicsContext, from: CGPoint, to: CGPoint, start: Double, length: Double) {
        let progress = (t - start) / length
        guard progress >= 0, progress <= 1 else { return }
        let point = CGPoint(x: from.x + (to.x - from.x) * progress, y: from.y + (to.y - from.y) * progress)
        let size = 14 * sin(.pi * progress)
        let glow = size * 1.8
        context.fill(Path(ellipseIn: CGRect(x: point.x - glow, y: point.y - glow, width: glow * 2, height: glow * 2)),
                     with: .radialGradient(Gradient(colors: [Color.white.opacity(0.8), .clear]),
                                           center: point, startRadius: 0, endRadius: glow))
        var star = Path()
        star.move(to: CGPoint(x: point.x, y: point.y - size))
        star.addQuadCurve(to: CGPoint(x: point.x + size, y: point.y), control: point)
        star.addQuadCurve(to: CGPoint(x: point.x, y: point.y + size), control: point)
        star.addQuadCurve(to: CGPoint(x: point.x - size, y: point.y), control: point)
        star.addQuadCurve(to: CGPoint(x: point.x, y: point.y - size), control: point)
        context.fill(star, with: .color(.white))
    }
}
