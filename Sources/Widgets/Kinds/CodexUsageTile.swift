import SwiftUI

/// Codex's session and weekly limits as two rings, each with the time to its
/// reset, and a dot saying whether Codex is working, waiting for you or done.
struct CodexUsageTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var service: CodexService { CodexService.shared }
    private var showsRemaining: Bool { instance.config.string("show", default: "used") == "remaining" }

    private var report: CodexUsageReport? {
        context.isPreview ? CodexSample.report(now: context.now) : service.report
    }

    private var activity: CodexActivity { context.isPreview ? .working : service.activity }

    var body: some View {
        WidgetSurface {
            if let report, !report.ringWindows.isEmpty {
                let windows = report.ringWindows
                if context.position.isVertical {
                    VStack(spacing: 6) {
                        ForEach(windows) { w in
                            VStack(spacing: 2) {
                                ring(w, diameter: 34)
                                Text(w.shortLabel)
                                    .font(WidgetStyle.caption(10))
                                    .foregroundStyle(WidgetStyle.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .overlay(alignment: .topTrailing) { statusDot }
                } else {
                    HStack(spacing: 10) {
                        ForEach(windows) { w in
                            HStack(spacing: 8) {
                                ring(w, diameter: 40)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(w.shortLabel)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(WidgetStyle.primary)
                                    Text(resetText(w))
                                        .font(.system(size: 11))
                                        .foregroundStyle(WidgetStyle.secondary)
                                        .monospacedDigit()
                                }
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .overlay(alignment: .topTrailing) { statusDot.offset(x: 4, y: -2) }
                }
            } else {
                placeholder
            }
        }
        .onAppear {
            guard !context.isPreview else { return }
            service.configure(instance.config)
            service.startActivity()
            service.refresh()
        }
        .onChange(of: instance.config) { _, config in
            guard !context.isPreview else { return }
            service.configure(config)
        }
        // The shelf ticks every second; the service keeps its own five minutes.
        .onChange(of: Int(context.now.timeIntervalSince1970) / 60) {
            if !context.isPreview { service.refresh() }
        }
    }

    /// 圆环（默认）或液态小圆杯，见 `LiquidLooks`。
    private var isLiquid: Bool { LiquidLooks.codexLook(instance.config) == .liquid }

    @ViewBuilder
    private func ring(_ w: CodexLimitWindow, diameter: CGFloat) -> some View {
        if isLiquid {
            cup(w, diameter: diameter)
        } else {
            progressRing(w, diameter: diameter)
        }
    }

    /// 液态：一个小圆杯，水位是圆环原来显示的数（已用或剩余），颜色和圆环
    /// 一样按用掉多少变绿、橙、红；快用完时水波更急。只在卡片可见时动。
    private func cup(_ w: CodexLimitWindow, diameter: CGFloat) -> some View {
        let level = LiquidLooks.codexLevel(usedFraction: w.usedFraction, showsRemaining: showsRemaining)
        let tint = CodexStyle.tint(used: w.usedFraction)
        return ZStack {
            LiquidWater(level: level, tint: tint, shape: .circle,
                        visible: !context.isPreview && ShelfVisibility.shared.cardsOnScreen,
                        speed: LiquidMotion.busySpeed(w.usedFraction))
            Text("\(Int((level * 100).rounded()))")
                .font(.system(size: diameter * 0.32, weight: .semibold, design: .rounded))
                .foregroundStyle(WidgetStyle.primary)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .shadow(color: .black.opacity(0.35), radius: 1)
        }
        .frame(width: diameter, height: diameter)
        .opacity(report?.isStale(now: context.now) == true && !context.isPreview ? 0.55 : 1)
    }

    private func progressRing(_ w: CodexLimitWindow, diameter: CGFloat) -> some View {
        let fraction = showsRemaining ? w.remainingFraction : w.usedFraction
        let tint = CodexStyle.tint(used: w.usedFraction)
        return MetricProgressRing(progress: fraction, tint: tint, track: tint.opacity(0.16),
                                  diameter: diameter, lineWidth: diameter > 36 ? 4.5 : 4) {
            Text("\(Int((fraction * 100).rounded()))")
                .font(.system(size: diameter * 0.32, weight: .semibold, design: .rounded))
                .foregroundStyle(WidgetStyle.primary)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
        }
        .opacity(report?.isStale(now: context.now) == true && !context.isPreview ? 0.55 : 1)
    }

    private func resetText(_ w: CodexLimitWindow) -> String {
        guard let resets = w.resetsAt else { return showsRemaining ? "剩余" : "已用" }
        return "\(CodexPace.compact(resets.timeIntervalSince(context.now))) 后重置"
    }

    @ViewBuilder private var statusDot: some View {
        if activity != .idle {
            Circle()
                .fill(CodexStyle.color(activity))
                .frame(width: 7, height: 7)
                .phaseAnimator([false, true]) { dot, on in
                    dot.opacity(activity == .working && on ? 0.35 : 1)
                } animation: { _ in .easeInOut(duration: 0.9) }
                .help("Codex \(activity.title)")
                .accessibilityLabel("Codex \(activity.title)")
        }
    }

    private var placeholder: some View {
        HStack(spacing: 10) {
            TileBadge(size: 40) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WidgetStyle.primary)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Codex 用量")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WidgetStyle.primary)
                Text(service.problem.map(CodexStyle.short) ?? "正在读取…")
                    .font(.system(size: 11))
                    .foregroundStyle(WidgetStyle.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Spacer(minLength: 0)
        }
    }
}

enum CodexStyle {
    /// Green while there is room, amber past 70%, red past 90%.
    static func tint(used: Double) -> Color {
        if used >= 0.9 { return Color(hex: "#FF453A") }
        if used >= 0.7 { return Color(hex: "#FF9F0A") }
        return Color(hex: "#30D158")
    }

    static func color(_ activity: CodexActivity) -> Color {
        switch activity {
        case .working: Color(hex: "#0A84FF")
        case .waiting: Color(hex: "#FF9F0A")
        case .done: Color(hex: "#30D158")
        case .idle: Color.secondary
        }
    }

    /// The problem in a few words, for the tile.
    static func short(_ p: CodexService.Problem) -> String {
        switch p {
        case .notSignedIn: "Codex 未登录"
        case .expired: "登录已过期"
        case .offline: "无法连接，检查代理"
        case .rateLimited: "请求太频繁"
        case .server, .unreadable: "接口有变动"
        }
    }
}

/// The numbers drawn in the library and in screenshots. Never a real account.
enum CodexSample {
    static func report(now: Date) -> CodexUsageReport {
        let daily = (0..<30).map { i -> CodexDailyTokens in
            let day = Calendar.current.date(byAdding: .day, value: i - 29, to: now) ?? now
            let c = Calendar.current.dateComponents([.year, .month, .day], from: day)
            let wave = [180, 420, 260, 0, 610, 380, 720, 540, 90, 300][i % 10]
            return CodexDailyTokens(day: String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0),
                                    tokens: wave * 1_000 + i * 9_000)
        }
        return CodexUsageReport(
            windows: [
                CodexLimitWindow(id: "primary", label: "5 小时额度", usedFraction: 0.42,
                                 resetsAt: now.addingTimeInterval(2 * 3600 + 14 * 60), duration: 18_000),
                CodexLimitWindow(id: "secondary", label: "每周额度", usedFraction: 0.18,
                                 resetsAt: now.addingTimeInterval(4 * 86_400 + 3 * 3600), duration: 604_800),
            ],
            plan: "plus", resetCredits: 1, daily: daily, fetchedAt: now)
    }
}
