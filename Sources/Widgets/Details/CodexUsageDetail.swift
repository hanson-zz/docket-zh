import AppKit
import SwiftUI

/// Codex 的详情面板，跟着卡片样式走（`CodexDetailEmphasis`）：
///
/// - 小卡（圆环）点开「用量优先」：头部只有状态点和总状态，下面两个大圆环
///   （外观选了液态时是两只大号液态杯），今日 / 本周统计，正在运行的会话收成
///   一行摘要，点开展开。
/// - 中卡（小熊猫）点开「会话优先」：角落小熊猫和总状态，正在运行的会话（项目、
///   在做什么、耗时，等你确认的给「去终端」）在上，用量是两条粗进度条，统计在下。
///
/// 两种都有「打开终端」、提醒声音开关、设置和「更多」（刷新、网页版用量、
/// 近 30 天 token、代理）。面板拿的是卡片配置的值，设置里换样式时
/// `WidgetDetailWindow.refresh` 换上新配置，已打开的面板当场跟着变。
///
/// Codex 不把审批交给别的程序，所以这里不画「允许 / 拒绝」，只把开着会话的
/// 终端叫到前台。读不准的统计项直接不显示。
struct CodexUsageDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @State private var proxy = ""
    @State private var proxyRejected = false
    @State private var showsMore = false
    /// 用量优先时会话摘要是否展开。
    @State private var showsSessions = false
    @Environment(\.colorScheme) private var scheme

    private var service: CodexService { CodexService.shared }
    private var showsRemaining: Bool { instance.config.string("show", default: "used") == "remaining" }
    private var emphasis: CodexDetailEmphasis { CodexDetailEmphasis.from(instance.config) }

    private var report: CodexUsageReport? {
        context.isPreview ? CodexSample.report(now: context.now) : service.report
    }

    private var sessions: [CodexSession] {
        context.isPreview ? CodexSample.sessions(now: context.now) : service.sessions
    }

    private var activity: CodexActivity {
        context.isPreview ? CodexSessionList.overall(sessions) : service.activity
    }

    private var chime: CodexChimeSettings {
        context.isPreview ? CodexChimeSettings(config: instance.config) : service.chime
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { tick in
            content(now: context.isPreview ? context.now : tick.date)
        }
        .onAppear {
            guard !context.isPreview else { return }
            proxy = service.proxyText
            service.configure(instance.config)
            service.startActivity()
            service.refresh()
            service.loadStats()
        }
    }

    private func content(now: Date) -> some View {
        DetailCard {
            MeshBackdrop(color: WidgetStyle.tint(.indigo))
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                header
                if emphasis.usageFirst {
                    gaugesSection(now: now)
                    statsSection(now: now)
                    sessionsSummary(now: now)
                } else {
                    sessionsSection(now: now)
                    usageSection(now: now)
                    statsSection(now: now)
                }
                Button {
                    guard !context.isPreview else { return }
                    service.openTerminal(for: CodexSessionList.lead(sessions))
                } label: {
                    Text("打开终端")
                        .font(WidgetStyle.label(15))
                        .foregroundStyle(.panelOnPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Capsule().fill(.panelPrimary))
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                footer(now: now)
                moreSection(now: now)
            }
        }
        .onChange(of: Int(now.timeIntervalSince1970) / 300) {
            if !context.isPreview { service.loadStats() }
        }
    }

    // MARK: 头

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            if emphasis.showsPanda {
                CodexPanda(activity: activity, size: 46)
            } else {
                // 用量优先：和小卡一样不画小熊猫，左边一枚仪表盘图标。
                Image(systemName: "gauge.with.dots.needle.33percent")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Color.panelFill))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "Codex")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.panelPrimary)
                HStack(spacing: 6) {
                    Circle().fill(CodexStyle.color(activity)).frame(width: 8, height: 8)
                    Text(activity.title)
                        .font(WidgetStyle.label(13))
                        .foregroundStyle(CodexStyle.color(activity).panelReadable)
                    speakerButton
                }
            }
            Spacer(minLength: 4)
            Button {
                guard !context.isPreview, let app = AIChatCenter.shared.app else { return }
                WidgetDetailWindow.shared.close()
                SettingsWindow.shared.show(app: app, tab: "Widgets")
            } label: {
                Text("设置")
                    .font(WidgetStyle.label(13))
                    .foregroundStyle(.panelPrimary)
                    .padding(.horizontal, 14)
                    .frame(height: 28)
                    .background(Capsule().fill(Color.panelFill))
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .help(tr("设置 ▸ 小组件 ▸ Codex 用量，声音也在那里"))
        }
    }

    /// 标题里的小喇叭：这个状态有声音开关时画，点一下直接开关这一项。
    @ViewBuilder private var speakerButton: some View {
        let mark = CodexChime.speaker(for: activity, settings: chime)
        if mark != .hidden, let key = CodexChime.toggleKey(for: activity) {
            Button {
                guard !context.isPreview else { return }
                WidgetWriter.write(instance) { $0.set(key, .bool(mark != .on)) }
            } label: {
                Image(systemName: mark == .on ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(mark == .on ? Color.panelSecondary : Color.panelTertiary)
                    .frame(width: 22, height: 22)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(mark == .on ? tr("这个状态会响，点按静音") : tr("这个状态静音，点按打开提示音"))
        }
    }

    // MARK: 正在运行

    @ViewBuilder private func sessionsSection(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(sessions.isEmpty ? tr("正在运行") : tr("正在运行 · \(sessions.count) 个会话"))
            if sessions.isEmpty {
                Text("现在没有进行中的会话。在终端里运行 codex 后，这里会列出它在做什么。")
                    .font(WidgetStyle.caption(13))
                    .foregroundStyle(.panelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassPane(cornerRadius: 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sessions.prefix(5).enumerated()), id: \.element.id) { index, session in
                        if index > 0 { Divider().overlay(.panelSeparator).padding(.horizontal, 12) }
                        sessionRow(session, now: now)
                    }
                }
                .glassPane(cornerRadius: 12)
            }
        }
    }

    private func sessionRow(_ session: CodexSession, now: Date) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Circle().fill(CodexStyle.color(session.state)).frame(width: 8, height: 8)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(session.project ?? "Codex")
                        .font(WidgetStyle.label(14))
                        .foregroundStyle(.panelPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(session.state.title)
                        .font(WidgetStyle.label(13))
                        .foregroundStyle(CodexStyle.color(session.state).panelReadable)
                        .lineLimit(1)
                        .fixedSize()
                }
                if let doing = session.doing?.text {
                    Text(doing)
                        .font(WidgetStyle.caption(13))
                        .foregroundStyle(.panelSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 4)
            Text(session.elapsedText(now: now))
                .font(WidgetStyle.caption(13))
                .foregroundStyle(.panelSecondary)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
            if session.state == .waiting {
                goToTerminalButton(session)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private func goToTerminalButton(_ session: CodexSession) -> some View {
        Button {
            guard !context.isPreview else { return }
            service.openTerminal(for: session)
        } label: {
            Text("去终端")
                .font(WidgetStyle.label(13))
                .foregroundStyle(.panelPrimary)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Capsule().fill(Color.panelRaised).panelLift(true))
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(tr("Codex 不让别的程序替你批准，点按把开着这个会话的终端带到前面。"))
    }

    // MARK: 用量

    @ViewBuilder private func usageSection(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle(tr("用量"))
                Spacer(minLength: 4)
                if let report, let pace = paceText(report, now: now) {
                    Text(pace)
                        .font(WidgetStyle.caption(13))
                        .foregroundStyle(.panelSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            if let report, !report.windows.isEmpty {
                VStack(spacing: 12) {
                    ForEach(report.windows) { w in windowRow(w, now: now, thick: true) }
                }
                .padding(12)
                .glassPane(cornerRadius: 12)
                if let problem = service.problem, !context.isPreview {
                    Text(problem.message)
                        .font(WidgetStyle.caption(13))
                        .foregroundStyle(Color(hex: "#FF9F0A").panelReadable)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                PanelNote(symbol: "network", text: service.problem?.message ?? tr("正在读取…"))
                    .frame(height: 96)
                    .glassPane(cornerRadius: 12)
            }
        }
    }

    /// 标题右边一句：照现在的速度够不够用到重置（看 5 小时窗口）。
    private func paceText(_ report: CodexUsageReport, now: Date) -> String? {
        guard let w = report.primary else { return nil }
        if let out = CodexPace.runsOutAt(w, now: now) {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return tr("照现在的速度，约 \(f.string(from: out)) 用完")
        }
        return CodexPace.elapsedFraction(w, now: now) == nil ? nil : tr("照现在的速度，够用到重置")
    }

    /// 一条额度：名字、百分比、进度条（带匀速参考线）、重置倒计时和时刻。
    /// `thick` 是会话优先时的粗条（主额度 12、分组 8），用量优先时大圆环下面
    /// 列的分组额度是细条（8、6）。
    private func windowRow(_ w: CodexLimitWindow, now: Date, thick: Bool) -> some View {
        let fraction = showsRemaining ? w.remainingFraction : w.usedFraction
        let tint = CodexStyle.tint(used: w.usedFraction)
        let main = w.group == nil
        let height: CGFloat = thick
            ? (main ? CodexDetailEmphasis.mainBarHeight : CodexDetailEmphasis.groupBarHeight)
            : (main ? 8 : 6)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(w.group.map { "\($0) · \(w.label)" } ?? CodexCard.label(w))
                    .font(WidgetStyle.label(main ? 15 : 13))
                    .foregroundStyle(.panelPrimary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(GaugeReading.percent(fraction))
                    .font(.system(size: main ? 19 : 14, weight: .bold))
                    .foregroundStyle(.panelPrimary)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.panelTrack)
                    Capsule().fill(tint.panelGraphic).frame(width: max(height, geo.size.width * fraction))
                    // Where an even pace would be by now.
                    if let elapsed = CodexPace.elapsedFraction(w, now: now) {
                        Rectangle().fill(.panelSecondary)
                            .frame(width: thick ? 2 : 1.5)
                            .offset(x: geo.size.width * (showsRemaining ? 1 - elapsed : elapsed) - (thick ? 1 : 0.75))
                    }
                }
            }
            .frame(height: height)
            if let resets = w.resetsAt {
                HStack {
                    Text(tr("\(CodexPace.duration(resets.timeIntervalSince(now)))后重置"))
                    Spacer(minLength: 4)
                    Text(resetClock(resets, now: now))
                }
                .font(WidgetStyle.caption(13))
                .foregroundStyle(.panelSecondary)
                .monospacedDigit()
                .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "14:20"；不是今天的写星期几，"周五 09:00"。
    private func resetClock(_ date: Date, now: Date) -> String {
        let f = DateFormatter()
        f.locale = L10n.interfaceLocale
        if Calendar.current.isDate(date, inSameDayAs: now) {
            f.dateFormat = "HH:mm"
        } else {
            f.setLocalizedDateFormatFromTemplate("EEE HH:mm")
        }
        return f.string(from: date)
    }

    // MARK: 用量优先：大圆环 / 大液态杯

    /// 小卡点开时的用量：5 小时和本周两格，各一个大圆环（或液态杯），中间
    /// 百分比大字，下面窗口名、重置倒计时和时刻。分组的小额度（没有圆环的）
    /// 在下面列成细条，数据和会话优先时一样全。
    @ViewBuilder private func gaugesSection(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle(tr("用量"))
                Spacer(minLength: 4)
                if let report, let pace = paceText(report, now: now) {
                    Text(pace)
                        .font(WidgetStyle.caption(13))
                        .foregroundStyle(.panelSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            if let report, !report.windows.isEmpty {
                let rings = report.ringWindows
                let rest = report.windows.filter { w in !rings.contains { $0.id == w.id } }
                if !rings.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(rings) { w in gaugeCell(w, now: now) }
                    }
                    // 两格一样高：倒计时一格折成两行时另一格跟着拉长。
                    .fixedSize(horizontal: false, vertical: true)
                }
                if !rest.isEmpty {
                    VStack(spacing: 12) {
                        ForEach(rest) { w in windowRow(w, now: now, thick: false) }
                    }
                    .padding(12)
                    .glassPane(cornerRadius: 12)
                }
                if let problem = service.problem, !context.isPreview {
                    Text(problem.message)
                        .font(WidgetStyle.caption(13))
                        .foregroundStyle(Color(hex: "#FF9F0A").panelReadable)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                PanelNote(symbol: "network", text: service.problem?.message ?? tr("正在读取…"))
                    .frame(height: 96)
                    .glassPane(cornerRadius: 12)
            }
        }
    }

    private func gaugeCell(_ w: CodexLimitWindow, now: Date) -> some View {
        VStack(spacing: 8) {
            if emphasis == .usageLiquid {
                bigCup(w, now: now)
            } else {
                bigRing(w, now: now)
            }
            VStack(spacing: 2) {
                Text(CodexCard.label(w))
                    .font(WidgetStyle.label(15))
                    .foregroundStyle(.panelPrimary)
                    .lineLimit(1)
                if let resets = w.resetsAt {
                    Text(tr("\(CodexPace.duration(resets.timeIntervalSince(now)))后重置"))
                        .font(WidgetStyle.caption(13))
                        .foregroundStyle(.panelSecondary)
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(resetClock(resets, now: now))
                        .font(WidgetStyle.caption(13))
                        .foregroundStyle(.panelTertiary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .glassPane(cornerRadius: 14)
        .accessibilityElement(children: .combine)
    }

    /// 圆环中间：百分比大字，下面一行「已用 / 剩余」。
    private func gaugeCenter(_ fraction: Double, onWater: Bool = false) -> some View {
        VStack(spacing: 0) {
            Text(GaugeReading.percent(fraction))
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.panelPrimary)
                .monospacedDigit()
                .lineLimit(1)
            Text(showsRemaining ? tr("剩余") : tr("已用"))
                .font(WidgetStyle.caption(13))
                .foregroundStyle(onWater ? Color.panelPrimary : Color.panelSecondary)
                .lineLimit(1)
        }
        // 液态杯里的字压在水上：深色外观描一圈淡黑，浅色外观描一圈淡白。
        .shadow(color: onWater ? (scheme == .dark ? .black.opacity(0.45) : .white.opacity(0.7)) : .clear,
                radius: 1.5)
    }

    private func bigRing(_ w: CodexLimitWindow, now: Date) -> some View {
        let fraction = showsRemaining ? w.remainingFraction : w.usedFraction
        let tint = CodexStyle.tint(used: w.usedFraction).panelGraphic
        let d = CGFloat(CodexDetailEmphasis.gaugeDiameter)
        let line: CGFloat = 10
        return ZStack {
            MetricProgressRing(progress: fraction, tint: tint, track: .panelTrack,
                               diameter: d, lineWidth: line) {
                gaugeCenter(fraction)
            }
            // 匀速参考线：照平均速度到现在该在哪，和进度条上的细线是同一件事。
            if let elapsed = CodexPace.elapsedFraction(w, now: now) {
                let sweep = 320.0 / 360
                let at = sweep * (showsRemaining ? 1 - elapsed : elapsed)
                Circle()
                    .trim(from: max(0, at - 0.005), to: min(sweep, at + 0.005))
                    .stroke(Color.panelSecondary, style: StrokeStyle(lineWidth: line + 4, lineCap: .butt))
                    .rotationEffect(.degrees(90 + 20))
                    .frame(width: d, height: d)
            }
        }
    }

    /// 液态外观：一只大号圆杯，复用卡片上的 `LiquidWater`，水位是圆环原来
    /// 显示的数（`LiquidLooks.codexLevel`），快用完时水波更急。
    private func bigCup(_ w: CodexLimitWindow, now: Date) -> some View {
        let level = LiquidLooks.codexLevel(usedFraction: w.usedFraction, showsRemaining: showsRemaining)
        let tint = CodexStyle.tint(used: w.usedFraction).panelGraphic
        let d = CGFloat(CodexDetailEmphasis.gaugeDiameter)
        return ZStack {
            LiquidWater(level: level, tint: tint, shape: .circle,
                        visible: !context.isPreview,
                        speed: LiquidMotion.busySpeed(w.usedFraction))
            // 匀速参考线：杯子左边沿一道短横线，标在匀速该到的水位上。
            if let elapsed = CodexPace.elapsedFraction(w, now: now) {
                let mark = showsRemaining ? 1 - elapsed : elapsed
                Capsule()
                    .fill(Color.panelSecondary)
                    .frame(width: 12, height: 2.5)
                    .position(x: 4, y: d * (1 - mark))
            }
            gaugeCenter(level, onWater: true)
        }
        .frame(width: d, height: d)
    }

    // MARK: 用量优先：会话摘要

    /// 会话列表收成一行：「2 个会话进行中」，点开展开成和会话优先一样的列表。
    /// 有等你确认的会话时右边直接给「去终端」，不用先展开。
    @ViewBuilder private func sessionsSummary(now: Date) -> some View {
        let states = sessions.map(\.state)
        let waiting = sessions.first { $0.state == .waiting }
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    guard !sessions.isEmpty else { return }
                    withAnimation(.snappy(duration: 0.2)) { showsSessions.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Circle().fill(CodexStyle.color(CodexDetailEmphasis.summaryState(states)))
                            .frame(width: 8, height: 8)
                        Text(CodexDetailEmphasis.sessionSummary(states))
                            .font(WidgetStyle.label(14))
                            .foregroundStyle(.panelPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                        Spacer(minLength: 4)
                        if !sessions.isEmpty {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.panelSecondary)
                                .rotationEffect(.degrees(showsSessions ? 180 : 0))
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 26)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(showsSessions ? tr("收起会话列表") : tr("展开会话列表"))
                if let waiting, !showsSessions {
                    goToTerminalButton(waiting)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            if showsSessions, !sessions.isEmpty {
                ForEach(Array(sessions.prefix(5).enumerated()), id: \.element.id) { _, session in
                    Divider().overlay(.panelSeparator).padding(.horizontal, 12)
                    sessionRow(session, now: now)
                }
            }
        }
        .glassPane(cornerRadius: 12)
    }

    // MARK: 统计

    @ViewBuilder private func statsSection(now: Date) -> some View {
        let local: (today: CodexStatBucket, week: CodexStatBucket)? = context.isPreview ? CodexSample.stats() : service.stats
        let server = context.isPreview ? nil : report.flatMap { CodexStats.serverTokens($0.daily, now: now) }
        let today = statCell(title: tr("今天"), bucket: local?.today, serverTokens: server?.today)
        let week = statCell(title: tr("本周"), bucket: local?.week, serverTokens: server?.week)
        if today != nil || week != nil {
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle(tr("统计"))
                HStack(spacing: 8) {
                    if let today { today }
                    if let week { week }
                }
            }
        }
    }

    /// 一格统计。token 优先用 chatgpt.com 按天给的数，没有时用本机会话记录里的；
    /// 时长读不准时不写；什么都没有时这一格不画。
    private func statCell(title: String, bucket: CodexStatBucket?, serverTokens: Int?) -> AnyView? {
        let tokens = serverTokens ?? bucket?.tokens
        var details: [String] = []
        if let bucket {
            details.append(tr("\(bucket.sessions) 个会话"))
            if let seconds = bucket.seconds, bucket.sessions > 0 { details.append(CodexStats.durationText(seconds)) }
        }
        guard tokens != nil || !details.isEmpty else { return nil }
        let parts = tokens.map { CodexStats.tokenParts($0, english: L10n.isEnglish) }
        return AnyView(
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(WidgetStyle.caption(13))
                    .foregroundStyle(.panelSecondary)
                if let parts {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(parts.number)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.panelPrimary)
                            .monospacedDigit()
                        Text(parts.unit)
                            .font(WidgetStyle.caption(13))
                            .foregroundStyle(.panelSecondary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
                if !details.isEmpty {
                    Text(details.joined(separator: " · "))
                        .font(WidgetStyle.caption(13))
                        .foregroundStyle(.panelSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassPane(cornerRadius: 12)
        )
    }

    // MARK: 底部

    private func footer(now: Date) -> some View {
        Text(footerText(now: now))
            .font(WidgetStyle.caption(13))
            .foregroundStyle(.panelTertiary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity)
    }

    private func footerText(now: Date) -> String {
        if context.isPreview { return tr("示例数据") }
        guard let at = service.scannedAt ?? report?.fetchedAt else { return tr("数据来自本机 Codex 记录") }
        let minutes = Int(max(0, now.timeIntervalSince(at)) / 60)
        let ago = minutes < 1 ? tr("刚刚") : tr("\(minutes) 分钟前")
        return tr("数据来自本机 Codex 记录 · \(ago)")
    }

    // MARK: 更多

    private func moreSection(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { showsMore.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Text("更多")
                        .font(WidgetStyle.label(13))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(showsMore ? 180 : 0))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.panelSecondary)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if showsMore {
                Text(subtitle(now: now))
                    .font(WidgetStyle.caption(13))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                if let report {
                    chart(report, now: now)
                    if let resets = report.resetCredits {
                        Text(tr("可用重置 \(resets) 次"))
                            .font(WidgetStyle.caption(13))
                            .foregroundStyle(.panelSecondary)
                    }
                }
                HStack(spacing: 8) {
                    PanelButton(title: tr("刷新"), symbol: "arrow.clockwise", prominent: true) {
                        guard !context.isPreview else { return }
                        service.refresh(force: true)
                        service.loadStats(force: true)
                    }
                    PanelButton(title: tr("网页版用量"), symbol: "arrow.up.right") {
                        guard !context.isPreview, let url = URL(string: "https://chatgpt.com/codex/settings/usage") else { return }
                        NSWorkspace.shared.open(url)
                    }
                }
                proxySection
            }
        }
    }

    private func subtitle(now: Date) -> String {
        if context.isPreview { return tr("示例数据") }
        var parts: [String] = []
        if let email = service.email { parts.append(email) }
        if let plan = CodexUsageParser.planTitle(report?.plan) { parts.append(plan) }
        if let report {
            let f = DateFormatter()
            f.dateFormat = Calendar.current.isDate(report.fetchedAt, inSameDayAs: now) ? "HH:mm" : tr("M月d日 HH:mm")
            parts.append(report.isStale(now: now) ? tr("\(f.string(from: report.fetchedAt)) 的缓存") : tr("\(f.string(from: report.fetchedAt)) 更新"))
            if let source = report.source { parts.append(tr("来源：\(source.title)")) }
        }
        return parts.isEmpty ? tr("读取 ~/.codex 的登录") : parts.joined(separator: " · ")
    }

    @ViewBuilder private func chart(_ report: CodexUsageReport, now: Date) -> some View {
        let series = CodexPace.series(report.daily, now: now).map(Double.init)
        if series.contains(where: { $0 > 0 }) {
            VStack(alignment: .leading, spacing: 4) {
                Text("近 30 天 token")
                    .font(WidgetStyle.caption(13))
                    .foregroundStyle(.panelSecondary)
                DitherChart(samples: series, tint: .panelPrimary, range: 0...(series.max() ?? 1))
                    .frame(height: 44)
            }
        }
    }

    private var proxySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("代理（可选）")
                .font(WidgetStyle.label(13))
                .foregroundStyle(.panelPrimary)
            HStack(spacing: 6) {
                TextField("", text: $proxy, prompt: Text("127.0.0.1:7890 或 socks5://127.0.0.1:7891"))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.panelPrimary)
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .glassPane(cornerRadius: 7)
                    .onSubmit(saveProxy)
                Button("保存", action: saveProxy)
                    .buttonStyle(.plain)
                    .font(WidgetStyle.label(13))
                    .foregroundStyle(.panelPrimary)
                    .disabled(context.isPreview)
            }
            Text(proxyRejected ? tr("地址格式不对，应为“主机:端口”。")
                 : tr("留空则使用系统代理。只在终端里设置了 HTTPS_PROXY 时，应用读不到，需要填在这里。"))
                .font(WidgetStyle.caption(13))
                .foregroundStyle(proxyRejected ? Color(hex: "#FF9F0A").panelReadable : .panelTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(WidgetStyle.label(13))
            .foregroundStyle(.panelSecondary)
    }

    private func saveProxy() {
        guard !context.isPreview else { return }
        proxyRejected = !service.setProxy(proxy)
        if !proxyRejected { proxy = service.proxyText }
    }
}
