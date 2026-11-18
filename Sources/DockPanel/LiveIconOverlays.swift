import SwiftUI

/// An opt-in visual accent for Finder in Dockling's shelf, not a replacement for Finder's artwork.
/// 小脸要一眼看得出：占图标一半大，眼白加黑眼珠跟着指针转，冒出时弹一下。
struct LiveFinderCompanion: View {
    var side: CGFloat
    var pointer: CGPoint?

    @State private var popped = false

    private var face: CGFloat { side * 0.5 }

    private var pupilOffset: CGSize {
        guard let pointer else { return .zero }
        let x = max(-1, min(1, (pointer.x / max(side, 1) - 0.5) * 2))
        let y = max(-1, min(1, (pointer.y / max(side, 1) - 0.5) * 2))
        return CGSize(width: x * face * 0.07, height: y * face * 0.07)
    }

    var body: some View {
        ZStack {
            Circle().fill(.regularMaterial)
            Circle().fill(Color(red: 1.0, green: 0.84, blue: 0.45).opacity(0.55))
            Circle().strokeBorder(.white.opacity(0.85), lineWidth: max(1, face * 0.04))
            HStack(spacing: face * 0.1) {
                eye
                eye
            }
            .offset(y: -face * 0.08)
            Capsule()
                .fill(Color.black.opacity(0.8))
                .frame(width: face * 0.26, height: max(1.5, face * 0.06))
                .offset(y: face * 0.24)
        }
        .frame(width: face, height: face)
        .shadow(color: .black.opacity(0.35), radius: face * 0.08, y: face * 0.03)
        .scaleEffect(popped ? 1 : 0.4, anchor: .bottomTrailing)
        .animation(.spring(response: 0.28, dampingFraction: 0.55), value: popped)
        .onAppear { popped = true }
        .onDisappear { popped = false }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private var eye: some View {
        ZStack {
            Circle().fill(.white)
            Circle()
                .fill(Color.black.opacity(0.85))
                .frame(width: face * 0.13, height: face * 0.13)
                .offset(pupilOffset)
        }
        .frame(width: face * 0.26, height: face * 0.26)
        .overlay(Circle().strokeBorder(Color.black.opacity(0.25), lineWidth: max(0.5, face * 0.015)))
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

// MARK: - ChatGPT / Codex：水位与流光

/// 画在 ChatGPT、Codex 图标内部：Codex 5 小时额度已用多少就有多高的一层半透明「水」，
/// 水面轻轻晃，裁剪在图标的圆角方形里；Codex 正在干活时一道柔和白光沿圆角方形边缘绕圈。
/// 没有数据或数据过期时不画水（未知），不拿猜的数顶上。
struct LiveOpenAIOverlay: View {
    var side: CGFloat
    var showPercent: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var codex: CodexService { .shared }

    var body: some View {
        let report = codex.report
        let used = report?.primary?.usedFraction
        let fetchedAt = report?.fetchedAt
        let working = LiveIconUsage.isWorking(codex.activity)
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let interval = LiveIconMotion.frameInterval(working ? .flow : .water, lowPower: lowPower)
        // 没水可画也不在干活时，TimelineView 暂停，不空转。
        let idle = LiveIconUsage.level(primaryUsed: used, fetchedAt: fetchedAt, now: .now) == nil && !working

        Group {
            if reduceMotion {
                // 减弱动态效果：水位静止，流光换成一圈不动的淡光；每分钟看一次数据有没有过期。
                TimelineView(.everyMinute) { context in
                    let level = LiveIconUsage.level(primaryUsed: used, fetchedAt: fetchedAt, now: context.date)
                    canvas(level: level, working: working, time: nil)
                        .overlay(alignment: .bottomTrailing) { percent(level) }
                }
            } else {
                TimelineView(.animation(minimumInterval: interval,
                                        paused: idle)) { context in
                    let level = LiveIconUsage.level(primaryUsed: used, fetchedAt: fetchedAt, now: context.date)
                    canvas(level: level, working: working,
                           time: context.date.timeIntervalSinceReferenceDate)
                        .overlay(alignment: .bottomTrailing) { percent(level) }
                }
            }
        }
        .frame(width: side, height: side)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            // 只为动态图标拉起时不发通知、不响；有 Codex 小组件时它照常提醒。
            codex.startActivity(quiet: true)
            while !Task.isCancelled {
                codex.refresh()
                try? await Task.sleep(for: .seconds(CodexService.interval))
            }
        }
    }

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

    private func canvas(level: Double?, working: Bool, time: Double?) -> some View {
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
