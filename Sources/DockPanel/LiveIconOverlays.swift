import SwiftUI
import AppKit

// MARK: - 访达：整张换成小熊猫

/// 小熊猫访达的三张图（@1x 128、@2x 256，放在 Resources/LiveIcons）。读一次存着；
/// 缺图时是 nil，程序坞照常画系统的访达图标。
@MainActor
enum LiveFinderPandaArt {
    static let base = Bundle.main.image(forResource: "finder-panda-base")
    static let blink = Bundle.main.image(forResource: "finder-panda-blink")
    static let pupil = Bundle.main.image(forResource: "finder-panda-pupil")

    static var available: Bool { base != nil && blink != nil && pupil != nil }
}

/// 程序坞里的访达图标整张换成小熊猫访达：两颗瞳孔跟着鼠标指针看，指针停下 3 秒后慢慢回正，
/// 每隔 3 到 7 秒眨一下眼（偶尔连眨两下）。指针用 NSEvent.mouseLocation 轮询，不要辅助功能权限；
/// 指针没动、眼睛停稳时 TimelineView 暂停、轮询放慢。减弱动态效果时瞳孔居中、不眨眼、不轮询。
/// 访达复制、移动文件时没有可靠的系统信号，所以不画「专心」表情。
struct LiveFinderPanda: View {
    var side: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var gaze = LiveFinderGazeBox()
    @State private var anchor = LiveScreenAnchor()
    @State private var animating = false
    @State private var blinking = false

    var body: some View {
        Group {
            if reduceMotion {
                face(blink: false, left: .zero, right: .zero)
            } else {
                TimelineView(.animation(minimumInterval: LiveFinderMotion.frameInterval(
                    lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled), paused: !animating)) { context in
                    let eyes = gaze.frame(at: context.date)
                    face(blink: blinking, left: eyes.left, right: eyes.right)
                }
            }
        }
        .frame(width: side, height: side)
        .background(LiveScreenAnchorView(anchor: anchor).allowsHitTesting(false))
        .task(id: reduceMotion) { await followPointer() }
        .task(id: reduceMotion) { await blinkNowAndThen() }
    }

    private func face(blink: Bool, left: LiveFinderFace.Point, right: LiveFinderFace.Point) -> some View {
        let k = side / CGFloat(LiveFinderFace.canvas)
        let d = CGFloat(LiveFinderFace.pupilCrop) * k
        return Image(nsImage: (blink ? LiveFinderPandaArt.blink : LiveFinderPandaArt.base) ?? NSImage())
            .resizable()
            .interpolation(.high)
            .frame(width: side, height: side)
            .overlay {
                if !blink, let pupil = LiveFinderPandaArt.pupil {
                    ZStack {
                        ForEach(0..<2, id: \.self) { i in
                            let eye = i == 0 ? LiveFinderFace.leftEye : LiveFinderFace.rightEye
                            let o = i == 0 ? left : right
                            Image(nsImage: pupil)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: d, height: d)
                                .position(x: CGFloat(eye.x + o.x) * k, y: CGFloat(eye.y + o.y) * k)
                        }
                    }
                    .frame(width: side, height: side)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// 轮询指针：动了就让 TimelineView 跑，停稳了就暂停；指针几秒没动时问得更慢。
    private func followPointer() async {
        gaze.reset()
        animating = false
        guard !reduceMotion else { return }
        while !Task.isCancelled {
            let now = Date()
            if let frame = anchor.screenFrame {
                gaze.observe(pointer: NSEvent.mouseLocation, iconFrame: frame, at: now)
            }
            let settled = gaze.isSettled(at: now)
            if settled, animating {
                animating = false
                gaze.pause()
            } else if !settled, !animating {
                animating = true
            }
            let interval = LiveFinderMotion.pollInterval(lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
                                                         active: !settled || !gaze.isIdle(at: now))
            try? await Task.sleep(for: .seconds(interval))
        }
        animating = false
    }

    /// 每隔 3 到 7 秒眨一下，偶尔连眨两下；闭眼时不画瞳孔。
    private func blinkNowAndThen() async {
        blinking = false
        guard !reduceMotion else { return }
        var rng = SystemRandomNumberGenerator()
        while !Task.isCancelled {
            let plan = LiveFinderBlink.next(using: &rng)
            try? await Task.sleep(for: .seconds(plan.wait))
            for (i, closed) in plan.closed.enumerated() {
                guard !Task.isCancelled else { break }
                if i > 0 { try? await Task.sleep(for: .seconds(plan.gap)) }
                blinking = true
                try? await Task.sleep(for: .seconds(closed))
                blinking = false
            }
        }
        blinking = false
    }
}

/// 弹簧状态放在引用里：TimelineView 每帧往前走一步，不触发视图重算。
@MainActor
final class LiveFinderGazeBox {
    private var gaze = LiveFinderGaze()

    func frame(at now: Date) -> (left: LiveFinderFace.Point, right: LiveFinderFace.Point) { gaze.step(at: now) }
    func observe(pointer: CGPoint, iconFrame: CGRect, at now: Date) {
        gaze.observe(pointer: pointer, iconFrame: iconFrame, at: now)
    }
    func isSettled(at now: Date) -> Bool { gaze.isSettled(at: now) }
    func isIdle(at now: Date) -> Bool { gaze.isIdle(at: now) }
    func pause() { gaze.pause() }
    func reset() { gaze.reset() }
}

/// 图标格在屏幕上的矩形（y 向上），用来算眼睛和指针的相对位置。
@MainActor
final class LiveScreenAnchor {
    weak var view: NSView?

    var screenFrame: CGRect? {
        guard let view, let window = view.window else { return nil }
        let frame = window.convertToScreen(view.convert(view.bounds, to: nil))
        return frame.width > 0 && frame.height > 0 ? frame : nil
    }
}

/// 垫在图标后面的空 NSView，只为拿到它在屏幕上的位置；不接任何点击和拖动。
struct LiveScreenAnchorView: NSViewRepresentable {
    let anchor: LiveScreenAnchor

    final class PassThroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> NSView {
        let view = PassThroughView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchor.view = nsView
    }
}

// MARK: - Chrome：图标本身转

/// Chrome 的图标本身转起来：当前标签页真的在加载时匀速转，加载完用缓动减速停回原角度。
/// 读不到加载状态（拒绝了自动化权限、Chrome 没响应）时，只在启动那一下转一圈。
/// 不画任何挂件，也不显示进度数字。减弱动态效果时由调用方不挂这个修饰。
struct LiveChromeSpin: ViewModifier {
    /// 开关开着且没开减弱动态效果。
    var active: Bool
    var isRunning: Bool

    @State private var spin = LiveIconSpin()
    @State private var animating = false
    @State private var client = UUID()
    @State private var ending: Task<Void, Never>?

    private var monitor: ChromeLoadingMonitor { .shared }

    func body(content: Content) -> some View {
        let interval = LiveIconMotion.frameInterval(.spin, lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
        TimelineView(.animation(minimumInterval: interval, paused: !animating)) { context in
            content.rotationEffect(.degrees(animating ? spin.angle(at: context.date) : 0))
        }
        .onAppear {
            monitor.want(client, active && isRunning)
            if active, monitor.loading { begin() }
        }
        .onDisappear {
            monitor.want(client, false)
            ending?.cancel()
            spin = LiveIconSpin()
            animating = false
        }
        .onChange(of: isRunning) { wasRunning, running in
            monitor.want(client, active && running)
            // 退回方案：读数不可信时，启动那一下转一圈。
            if active, running, !wasRunning, monitor.status != .available {
                spin.turnOnce(at: .now)
                if spin.isAnimating(at: .now) { animating = true }
                scheduleEnd()
            }
        }
        .onChange(of: active) { _, on in
            monitor.want(client, on && isRunning)
            if !on {
                ending?.cancel()
                spin = LiveIconSpin()
                animating = false
            } else if monitor.loading {
                begin()
            }
        }
        .onChange(of: monitor.loading) { _, loading in
            guard active else { return }
            if loading { begin() } else { finish() }
        }
    }

    private func begin() {
        ending?.cancel()
        spin.start(at: .now)
        animating = true
    }

    private func finish() {
        spin.stop(at: .now)
        scheduleEnd()
    }

    /// 减速或转一圈结束时暂停 TimelineView，不让它空转。
    private func scheduleEnd() {
        ending?.cancel()
        guard let end = spin.endDate(at: .now) else { return }
        let wait = max(0, end.timeIntervalSinceNow) + 0.05
        ending = Task { @MainActor in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            spin.settleIfDone(at: .now)
            if !spin.isAnimating(at: .now) { animating = false }
        }
    }
}

// MARK: - ChatGPT / Codex / Claude：额度水位与流光

/// 画在 ChatGPT、Codex 图标内部：Codex 剩余额度有多少就有多高的一层半透明「水」
/// （5 小时和每周里更紧的那个，见 `LiveIconUsage.quota`），水面轻轻晃，裁剪在图标的
/// 圆角方形里；Codex 正在干活时一道柔和白光沿圆角方形边缘绕圈。
/// 没有数据或数据过期时不画水（未知），不拿猜的数顶上。
struct LiveOpenAIOverlay: View {
    var side: CGFloat
    var showPercent: Bool

    private var codex: CodexService { .shared }

    var body: some View {
        let report = codex.report
        let working = LiveIconUsage.isWorking(codex.activity)
        LiveQuotaWater(side: side, showPercent: showPercent, report: report, working: working)
            .task {
                // 只为动态图标拉起时不发通知、不响；有 Codex 小组件时它照常提醒。
                codex.startActivity(quiet: true)
                while !Task.isCancelled {
                    codex.refresh()
                    try? await Task.sleep(for: .seconds(CodexService.interval))
                }
            }
    }
}

/// 画在 Claude 图标内部：读本机 Claude 命令行已登录账号的剩余额度，画法和 Codex 的水位一样。
/// 没有「正在干活」的可靠信号，所以不画流光。没有凭据或数据时不画水。
/// 只有这个视图挂在扩展栏的 Claude 格子上（开关开着）时才轮询。
struct LiveClaudeOverlay: View {
    var side: CGFloat
    var showPercent: Bool

    private var claude: ClaudeUsageService { .shared }

    var body: some View {
        LiveQuotaWater(side: side, showPercent: showPercent, report: claude.report, working: false)
            .task {
                while !Task.isCancelled {
                    claude.refresh()
                    try? await Task.sleep(for: .seconds(ClaudeUsageService.interval))
                }
            }
    }
}

/// 水位（剩余额度）加可选的流光和百分比小字，Codex 和 Claude 共用。
// TODO: 悬停显示重置倒计时（LiveIconUsage.resetCountdown）、大字百分比，等效果图。
struct LiveQuotaWater: View {
    var side: CGFloat
    var showPercent: Bool
    var report: CodexUsageReport?
    var working: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let interval = LiveIconMotion.frameInterval(working ? .flow : .water, lowPower: lowPower)
        // 没水可画也不在干活时，TimelineView 暂停，不空转。
        let idle = LiveIconUsage.quota(report, now: .now) == nil && !working

        Group {
            if reduceMotion {
                // 减弱动态效果：水位静止，流光换成一圈不动的淡光；每分钟看一次数据有没有过期。
                TimelineView(.everyMinute) { context in
                    let level = LiveIconUsage.quota(report, now: context.date)?.remaining
                    canvas(level: level, time: nil)
                        .overlay(alignment: .bottomTrailing) { percent(level) }
                }
            } else {
                TimelineView(.animation(minimumInterval: interval,
                                        paused: idle)) { context in
                    let level = LiveIconUsage.quota(report, now: context.date)?.remaining
                    canvas(level: level, time: context.date.timeIntervalSinceReferenceDate)
                        .overlay(alignment: .bottomTrailing) { percent(level) }
                }
            }
        }
        .frame(width: side, height: side)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 右下角的百分比小字：剩余额度。
    @ViewBuilder
    private func percent(_ level: Double?) -> some View {
        if showPercent, let level {
            Text(LiveIconUsage.percentText(level))
                .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .background(Color.black.opacity(0.62), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
                .offset(x: side * 0.06, y: side * 0.04)
        }
    }

    private func canvas(level: Double?, time: Double?) -> some View {
        Canvas { context, size in
            let g = LiveIconGeometry.content(side: Double(min(size.width, size.height)))
            let rect = CGRect(x: g.inset, y: g.inset, width: g.length, height: g.length)
            let shape = Path(roundedRect: rect, cornerRadius: g.corner, style: .continuous)
            if let level {
                LiveOpenAIDrawing.water(in: context, rect: rect, shape: shape, level: level, time: time)
            }
            if working {
                LiveOpenAIDrawing.flow(in: context, rect: rect, corner: g.corner, time: time)
            }
        }
    }
}

/// 水位和流光的画法，只用传进来的数，不碰视图状态。
enum LiveOpenAIDrawing {
    static func wave(_ rect: CGRect, surface: CGFloat, amplitude: CGFloat, phase: Double,
                      cycles: Double, closed: Bool) -> Path {
        var path = Path()
        let steps = 28
        for i in 0...steps {
            let u = Double(i) / Double(steps)
            let x = rect.minX + rect.width * u
            let y = surface + amplitude * CGFloat(sin(u * cycles * 2 * .pi + phase))
            if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }
        if closed {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY + 1))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY + 1))
            path.closeSubpath()
        }
        return path
    }

    static func water(in context: GraphicsContext, rect: CGRect, shape: Path, level: Double, time: Double?) {
        var ctx = context
        ctx.clip(to: shape)
        let surface = rect.maxY - rect.height * CGFloat(LiveIconUsage.surfaceFraction(level))
        let amplitude = rect.height * (time == nil ? 0.012 : 0.018)
        let phase = (time ?? 0) * 1.7
        let back = wave(rect, surface: surface - amplitude * 0.4, amplitude: amplitude * 0.8,
                        phase: -phase * 0.8 + 1.3, cycles: 1.4, closed: true)
        let front = wave(rect, surface: surface, amplitude: amplitude, phase: phase, cycles: 1.1, closed: true)
        let line = wave(rect, surface: surface, amplitude: amplitude, phase: phase, cycles: 1.1, closed: false)

        // 浅色图标（白底）上靠一层很淡的压暗看得见，深色图标上靠白色看得见。
        var shade = ctx
        shade.blendMode = .multiply
        shade.fill(front, with: .color(.black.opacity(0.10)))
        ctx.fill(back, with: .color(.white.opacity(0.14)))
        ctx.fill(front, with: .linearGradient(
            Gradient(colors: [.white.opacity(0.36), .white.opacity(0.16)]),
            startPoint: CGPoint(x: rect.midX, y: surface), endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
        let width = max(1, rect.width * 0.022)
        ctx.stroke(line.offsetBy(dx: 0, dy: width * 0.8), with: .color(.black.opacity(0.16)), lineWidth: max(0.75, width * 0.7))
        ctx.stroke(line, with: .color(.white.opacity(0.88)), lineWidth: width)
    }

    /// 环形路径上 a 到 b 的一段，a 可以是负数（从终点绕回来）。
    static func segment(_ path: Path, from a: Double, to b: Double) -> Path {
        if b <= 0 { return path.trimmedPath(from: 1 + a, to: 1 + b) }
        guard a < 0 else { return path.trimmedPath(from: a, to: b) }
        var p = path.trimmedPath(from: 1 + a, to: 1)
        p.addPath(path.trimmedPath(from: 0, to: max(0, b)))
        return p
    }

    static func flow(in context: GraphicsContext, rect: CGRect, corner: Double, time: Double?) {
        let lineWidth = max(1.5, rect.width * 0.035)
        let inner = rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        let path = Path(roundedRect: inner, cornerRadius: max(0, corner - lineWidth / 2), style: .continuous)

        guard let time else {
            // 减弱动态效果：一圈不动的淡光，表示正在干活。
            context.stroke(path, with: .color(.white.opacity(0.5)), lineWidth: lineWidth * 0.7)
            return
        }
        let head = (time / 1.8).truncatingRemainder(dividingBy: 1)
        let length = 0.24
        let pieces = 5
        // 白底图标上靠一圈很淡的暗影托住白光，深色图标上几乎看不出。
        context.drawLayer { halo in
            halo.addFilter(.blur(radius: lineWidth))
            halo.stroke(segment(path, from: head - length * 0.8, to: head),
                        with: .color(.black.opacity(0.16)), lineWidth: lineWidth * 1.6)
        }
        context.drawLayer { glow in
            glow.addFilter(.blur(radius: lineWidth * 1.4))
            glow.stroke(segment(path, from: head - length, to: head),
                        with: .color(.white.opacity(0.75)), lineWidth: lineWidth * 1.8)
        }
        for i in 0..<pieces {
            let a = head - length * Double(i + 1) / Double(pieces)
            let b = head - length * Double(i) / Double(pieces)
            let opacity = 0.95 * (1 - Double(i) / Double(pieces))
            context.stroke(segment(path, from: a, to: b),
                           with: .color(.white.opacity(opacity)),
                           style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
    }
}
