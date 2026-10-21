import AppKit
import SwiftUI

/// Every limit window with its reset and its pace, the last 30 days of
/// tokens, and the proxy the requests go through.
struct CodexUsageDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @State private var proxy = ""
    @State private var proxyRejected = false

    private var service: CodexService { CodexService.shared }
    private var showsRemaining: Bool { instance.config.string("show", default: "used") == "remaining" }

    private var report: CodexUsageReport? {
        context.isPreview ? CodexSample.report(now: context.now) : service.report
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
        }
    }

    private func content(now: Date) -> some View {
        DetailCard {
            MeshBackdrop(color: WidgetStyle.tint(.indigo))
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                PanelHeader(symbol: "gauge.with.dots.needle.33percent", title: tr("Codex 用量"), subtitle: subtitle(now: now))
                activityRow
                if let report, !report.windows.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(report.windows) { w in windowRow(w, now: now) }
                    }
                    stats(report, now: now)
                    chart(report, now: now)
                    if let source = report.source, !context.isPreview {
                        Text(tr("来源：\(source.title)"))
                            .font(WidgetStyle.caption(13))
                            .foregroundStyle(.panelTertiary)
                    }
                } else {
                    PanelNote(symbol: "network", text: service.problem?.message ?? tr("正在读取…")).frame(height: 100)
                }
                if let problem = service.problem, report != nil, !context.isPreview {
                    Text(problem.message)
                        .font(WidgetStyle.caption(13))
                        .foregroundStyle(Color(hex: "#FF9F0A").panelReadable)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    PanelButton(title: tr("刷新"), symbol: "arrow.clockwise", prominent: true) {
                        guard !context.isPreview else { return }
                        service.refresh(force: true)
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
        }
        return parts.isEmpty ? tr("读取 ~/.codex 的登录") : parts.joined(separator: " · ")
    }

    private var activityRow: some View {
        let activity = context.isPreview ? CodexActivity.working : service.activity
        let project = context.isPreview ? "docket" : service.activityProject
        return HStack(spacing: 8) {
            Circle().fill(CodexStyle.color(activity)).frame(width: 8, height: 8)
            Text(activity.title)
                .font(WidgetStyle.label(13))
                .foregroundStyle(.panelPrimary)
            if let project, activity != .idle {
                Text(project)
                    .font(WidgetStyle.caption(13))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 28)
        .glassPane(cornerRadius: 9)
    }

    private func windowRow(_ w: CodexLimitWindow, now: Date) -> some View {
        let fraction = showsRemaining ? w.remainingFraction : w.usedFraction
        let tint = CodexStyle.tint(used: w.usedFraction)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(w.group.map { "\($0) · \(w.label)" } ?? w.label)
                    .font(WidgetStyle.label(13))
                    .foregroundStyle(.panelPrimary)
                Spacer(minLength: 4)
                Text("\(showsRemaining ? tr("剩余") : tr("已用")) \(GaugeReading.percent(fraction))")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.panelTrack)
                    Capsule().fill(tint).frame(width: geo.size.width * fraction)
                    // Where an even pace would be by now.
                    if let elapsed = CodexPace.elapsedFraction(w, now: now) {
                        Rectangle().fill(.panelSecondary)
                            .frame(width: 1.5)
                            .offset(x: geo.size.width * (showsRemaining ? 1 - elapsed : elapsed) - 0.75)
                    }
                }
            }
            .frame(height: 6)
            Text(caption(w, now: now))
                .font(WidgetStyle.caption(13))
                .foregroundStyle(.panelSecondary)
                .lineLimit(1)
        }
        .padding(10)
        .glassPane(cornerRadius: 10)
    }

    private func caption(_ w: CodexLimitWindow, now: Date) -> String {
        var parts: [String] = []
        if let resets = w.resetsAt {
            let f = DateFormatter()
            f.dateFormat = Calendar.current.isDate(resets, inSameDayAs: now) ? "HH:mm" : tr("M月d日 HH:mm")
            parts.append(tr("\(CodexPace.duration(resets.timeIntervalSince(now)))后重置（\(f.string(from: resets))）"))
        }
        if let out = CodexPace.runsOutAt(w, now: now) {
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            parts.append(tr("按当前速度约 \(f.string(from: out)) 用完"))
        } else if let delta = CodexPace.delta(w, now: now) {
            parts.append(delta > 0.05 ? tr("用得偏快") : tr("节奏正常"))
        }
        return parts.joined(separator: " · ")
    }

    private func stats(_ report: CodexUsageReport, now: Date) -> some View {
        let series = CodexPace.series(report.daily, now: now)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            StatChip(label: tr("今天"), value: report.daily.isEmpty ? "-" : CodexPace.tokens(series.last ?? 0))
            StatChip(label: tr("30 天"), value: report.daily.isEmpty ? "-" : CodexPace.tokens(series.reduce(0, +)))
            StatChip(label: tr("可用重置"), value: report.resetCredits.map { tr("\($0) 次") } ?? "-")
        }
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

    private func saveProxy() {
        guard !context.isPreview else { return }
        proxyRejected = !service.setProxy(proxy)
        if !proxyRejected { proxy = service.proxyText }
    }
}
