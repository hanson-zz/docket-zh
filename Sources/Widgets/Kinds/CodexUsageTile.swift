import SwiftUI

/// Codex 的状态、5 小时和每周额度。
///
/// 小卡：一行状态（点、状态字、开着提示音时的小喇叭），下面两个圆环各带
/// 重置倒计时。中卡：左边小熊猫随状态换姿势，项目名和正在做什么，右边两条
/// 进度条。扩展栏在左右两侧（竖排）时照旧是上下两个圆环。
struct CodexUsageTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @Environment(\.widgetTint) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 圆环和水杯的颜色：默认照旧按用掉多少变绿、橙、红；颜色面板里选过
    /// 颜色时，用掉不到 70% 用选的颜色，快用完的橙和红照旧提醒。
    private func usageTint(_ used: Double) -> Color {
        if let theme, theme.isChosen, used < 0.7 { return theme.main(dark: scheme == .dark) }
        return CodexStyle.tint(used: used)
    }

    private var service: CodexService { CodexService.shared }
    private var showsRemaining: Bool { instance.config.string("show", default: "used") == "remaining" }
    private var isMedium: Bool { CodexCard.isMedium(instance.config) }

    private var report: CodexUsageReport? {
        context.isPreview ? CodexSample.report(now: context.now) : service.report
    }

    private var activity: CodexActivity {
        context.isPreview ? (isMedium ? .waiting : .working) : service.activity
    }

    /// 卡片上那一个会话：中卡显示它的项目和正在做什么。
    private var lead: CodexSession? {
        context.isPreview ? CodexSample.sessions(now: context.now).first : CodexSessionList.lead(service.sessions)
    }

    /// 状态点只在工作中、卡片看得见时一闪一闪；其余时候只给一个阶段，
    /// phaseAnimator 不再常驻循环（以前空闲、等你确认时也一直在跑动画）。
    private var pulses: Bool {
        activity == .working && !reduceMotion
            && !context.isPreview && ShelfVisibility.shared.cardsOnScreen
    }

    private var chime: CodexChimeSettings {
        context.isPreview ? CodexChimeSettings(config: instance.config) : service.chime
    }

    var body: some View {
        WidgetSurface {
            if context.position.isVertical {
                verticalBody
            } else if isMedium {
                mediumBody
            } else {
                smallBody
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

    // MARK: 竖排

    @ViewBuilder private var verticalBody: some View {
        if let report, !report.ringWindows.isEmpty {
            VStack(spacing: 6) {
                ForEach(report.ringWindows) { w in
                    VStack(spacing: 2) {
                        ring(w, diameter: 34)
                        Text(CodexCard.label(w))
                            .font(WidgetStyle.caption(10))
                            .foregroundStyle(WidgetStyle.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .overlay(alignment: .topTrailing) { statusDot }
        } else {
            placeholder
        }
    }

    // MARK: 小卡

    @ViewBuilder private var smallBody: some View {
        if let report, !report.ringWindows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                statusLine(size: 14)
                HStack(spacing: 10) {
                    ForEach(report.ringWindows) { w in
                        HStack(spacing: 7) {
                            ring(w, diameter: 36)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(CodexCard.label(w))
                                    .font(WidgetStyle.label(13))
                                    .foregroundStyle(WidgetStyle.primary)
                                Text(resetShort(w))
                                    .font(WidgetStyle.caption(13))
                                    .foregroundStyle(WidgetStyle.secondary)
                                    .monospacedDigit()
                            }
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            placeholder
        }
    }

    // MARK: 中卡

    private var mediumBody: some View {
        HStack(alignment: .center, spacing: 10) {
            CodexPanda(activity: activity, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                statusLine(size: 14)
                Text(lead?.project ?? (activity == .idle ? tr("没有进行中的会话") : "Codex"))
                    .font(WidgetStyle.label(14))
                    .foregroundStyle(WidgetStyle.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let doing = lead?.doing?.text ?? service.problem.map(CodexStyle.short), !doing.isEmpty {
                    Text(doing)
                        .font(WidgetStyle.caption(13))
                        .foregroundStyle(WidgetStyle.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(width: 136, alignment: .leading)
            VStack(alignment: .leading, spacing: 10) {
                if let report, !report.ringWindows.isEmpty {
                    ForEach(report.ringWindows) { w in bar(w) }
                } else {
                    Text(service.problem.map(CodexStyle.short) ?? tr("正在读取…"))
                        .font(WidgetStyle.caption(13))
                        .foregroundStyle(WidgetStyle.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func bar(_ w: CodexLimitWindow) -> some View {
        let fraction = showsRemaining ? w.remainingFraction : w.usedFraction
        let tint = usageTint(w.usedFraction)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(CodexCard.label(w))
                    .font(WidgetStyle.label(13))
                    .foregroundStyle(WidgetStyle.primary)
                Spacer(minLength: 2)
                if let resets = w.resetsAt {
                    Text(resetMedium(resets))
                        .font(WidgetStyle.caption(13))
                        .foregroundStyle(WidgetStyle.secondary)
                        .monospacedDigit()
                }
                Text(GaugeReading.percent(fraction))
                    .font(WidgetStyle.label(13))
                    .foregroundStyle(WidgetStyle.primary)
                    .monospacedDigit()
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(WidgetStyle.primary.opacity(0.12))
                    Capsule().fill(tint).frame(width: max(6, geo.size.width * fraction))
                }
            }
            .frame(height: 6)
        }
        .opacity(report?.isStale(now: context.now) == true && !context.isPreview ? 0.55 : 1)
        .accessibilityElement(children: .combine)
    }

    // MARK: 状态行

    /// 点 + 状态字 + 小喇叭（这个状态的提示音开着时才画）。
    private func statusLine(size: CGFloat) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(CodexStyle.color(activity))
                .frame(width: 8, height: 8)
                .phaseAnimator(pulses ? [false, true] : [false]) { dot, on in
                    dot.opacity(activity == .working && on ? 0.4 : 1)
                } animation: { _ in .easeInOut(duration: 0.9) }
            Text(activity.title)
                .font(WidgetStyle.label(size))
                .foregroundStyle(CodexStyle.text(activity, dark: scheme == .dark))
                .lineLimit(1)
            if CodexChime.speaker(for: activity, settings: chime) == .on {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WidgetStyle.secondary)
                    .help(tr("这个状态会响提示音"))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Codex \(activity.title)")
    }

    /// "2:14"、"1天22时"，没有重置时间时是已用 / 剩余。
    private func resetShort(_ w: CodexLimitWindow) -> String {
        guard let resets = w.resetsAt else { return showsRemaining ? tr("剩余") : tr("已用") }
        return CodexCard.resetShort(resets.timeIntervalSince(context.now))
    }

    /// 中卡：一天内 "2:14 后"，更远的写星期几（"周五"）。
    private func resetMedium(_ resets: Date) -> String {
        let seconds = resets.timeIntervalSince(context.now)
        if seconds < 86_400 { return tr("\(CodexPace.compact(seconds)) 后") }
        let f = DateFormatter()
        f.locale = L10n.interfaceLocale
        f.setLocalizedDateFormatFromTemplate("EEE")
        return f.string(from: resets)
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
        let tint = usageTint(w.usedFraction)
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
        let tint = usageTint(w.usedFraction)
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

    @ViewBuilder private var statusDot: some View {
        if activity != .idle {
            Circle()
                .fill(CodexStyle.color(activity))
                .frame(width: 7, height: 7)
                .phaseAnimator(pulses ? [false, true] : [false]) { dot, on in
                    dot.opacity(activity == .working && on ? 0.35 : 1)
                } animation: { _ in .easeInOut(duration: 0.9) }
                .help("Codex \(activity.title)")
                .accessibilityLabel("Codex \(activity.title)")
        }
    }

    private var placeholder: some View {
        HStack(spacing: WidgetStyle.rowSpacing) {
            TileBadge(size: WidgetStyle.badge) {
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WidgetStyle.primary)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Codex 用量")
                    .font(WidgetStyle.title)
                    .foregroundStyle(WidgetStyle.primary)
                Text(service.problem.map(CodexStyle.short) ?? tr("正在读取…"))
                    .font(WidgetStyle.note)
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

    /// 状态点：工作中青绿、等你确认橙、已完成绿、空闲灰（按效果图，不用蓝）。
    static func color(_ activity: CodexActivity) -> Color {
        switch activity {
        case .working: Color(hex: "#26AAA0")
        case .waiting: Color(hex: "#FF953C")
        case .done: Color(hex: "#34BE6E")
        case .idle: Color(hex: "#96969E")
        }
    }

    /// 状态字：浅色下压深一档，深色下略提亮，免得浅色玻璃上看不清。
    static func text(_ activity: CodexActivity, dark: Bool) -> Color {
        guard activity != .idle else { return .primary }
        let c = color(activity)
        return dark ? c.mix(with: .white, by: 0.18) : c.mix(with: .black, by: 0.28)
    }

    /// The problem in a few words, for the tile.
    static func short(_ p: CodexService.Problem) -> String {
        switch p {
        case .notSignedIn: tr("Codex 未登录")
        case .expired: tr("登录已过期")
        case .offline: tr("无法连接，检查代理")
        case .rateLimited: tr("请求太频繁")
        case .server, .unreadable: tr("接口有变动")
        }
    }
}

/// The numbers drawn in the library and in screenshots. Never a real account.
enum CodexSample {
    /// 面板和中卡预览里的三个会话。
    static func sessions(now: Date) -> [CodexSession] {
        [
            CodexSession(id: "sample-1", project: "docket", state: .waiting,
                         doing: .askingToRun("git push"), since: now.addingTimeInterval(-4 * 60), modified: now),
            CodexSession(id: "sample-2", project: "bake-cost", state: .working,
                         doing: .running("npm test"), since: now.addingTimeInterval(-23 * 60), modified: now),
            CodexSession(id: "sample-3", project: "dockling-site", state: .done,
                         doing: .finished, since: now.addingTimeInterval(-20), modified: now),
        ]
    }

    static func stats() -> (today: CodexStatBucket, week: CodexStatBucket) {
        (CodexStatBucket(sessions: 6, seconds: 2 * 3600 + 35 * 60, tokens: 12_400_000),
         CodexStatBucket(sessions: 31, seconds: 14 * 3600, tokens: 58_600_000))
    }

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
                CodexLimitWindow(id: "primary", label: tr("5 小时额度"), usedFraction: 0.38,
                                 resetsAt: now.addingTimeInterval(2 * 3600 + 14 * 60), duration: 18_000),
                CodexLimitWindow(id: "secondary", label: tr("每周额度"), usedFraction: 0.61,
                                 resetsAt: now.addingTimeInterval(86_400 + 22 * 3600), duration: 604_800),
            ],
            plan: "plus", resetCredits: 1, daily: daily, fetchedAt: now)
    }
}

/// 中卡和面板角落的小熊猫，随状态换姿势。图读不到时画一个状态色的圆点。
struct CodexPanda: View {
    var activity: CodexActivity
    var size: CGFloat

    var body: some View {
        Group {
            if let image = PandaArt.image(CodexCard.pandaImage(activity)) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Circle().fill(CodexStyle.color(activity).opacity(0.3))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
