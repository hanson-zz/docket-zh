import AppKit
import SwiftUI

/// 时间洞察：Dock 卡片点击后的轻量展开面板。
/// 保留今日核心数据、真实分类分布、Top 3 与记录状态；日/周/月图表放进独立统计窗口。
/// 宽面板和窄面板使用同一份数据，避免把完整统计页硬塞进 Dock 扩展栏。
struct TimeInsightsDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var tracker: TimeInsightsTracker { .shared }

    @AppStorage(ProAccess.licenseKey) private var licenseUnlocked = false
    @AppStorage(Supporter.key) private var supporter = false
    private var unlocked: Bool { licenseUnlocked || supporter }

    @State private var contentWidth: CGFloat = TimeInsightsLayout.wideWidth - 32
    @State private var notice: String?

    private var wide: Bool { TimeInsightsLayout.isWide(contentWidth: contentWidth) }

    var body: some View {
        let day = tracker.today
        DetailCard {
            MeshBackdrop(color: TimeInsightsStyle.accent)
        } content: {
            VStack(alignment: .leading, spacing: TimeInsightsMetrics.spacing + 2) {
                header
                if let problem = tracker.storageProblem {
                    warning(problem)
                }
                overview(day)
                distribution(day)
                topApps(day)
                currentActivity
                statsLink
                privacyFooter
                if let notice {
                    Text(notice)
                        .font(.system(size: 13))
                        .foregroundStyle(.panelSecondary)
                        .transition(.opacity)
                }
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                if abs(width - contentWidth) >= 1 { contentWidth = width }
            }
        }
    }

    // MARK: - 标题与记录状态

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(TimeInsightsStyle.accent)
                .frame(width: 32, height: 32)
                .readableGlass(in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("时间洞察"))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.panelPrimary)
                HStack(spacing: 5) {
                    Circle()
                        .fill(tracker.status == .recording ? Color.green : Color.panelTertiary)
                        .frame(width: 6, height: 6)
                    Text(tracker.status.shortTitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.panelSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            pauseButton
        }
    }

    private var pauseButton: some View {
        let paused = tracker.settings.paused
        return Button {
            tracker.setPaused(!paused)
        } label: {
            Image(systemName: paused ? "play.fill" : "pause.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelPrimary)
                .frame(width: 30, height: 30)
                .readableGlass(in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(paused ? tr("继续记录") : tr("暂停记录"))
        .help(paused ? tr("从现在起继续记录前台应用") : tr("暂停后不记录任何应用，随时可以继续"))
    }

    private func warning(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13))
                .foregroundStyle(.orange)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.panelPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .readableGlass(in: RoundedRectangle(cornerRadius: TimeInsightsMetrics.corner, style: .continuous))
    }

    // MARK: - 核心指标：一个主数字、两个辅助数字

    private func overview(_ day: TimeInsightsDay) -> some View {
        let change = TimeInsightsStats.change(today: day.active, yesterday: tracker.yesterday)
        return Group {
            if wide {
                HStack(alignment: .center, spacing: 16) {
                    activeMetric(day, change: change)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Rectangle().fill(Color.panelSeparator)
                        .frame(width: 1, height: 58)
                    secondaryMetrics(day)
                        .frame(width: 180, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    activeMetric(day, change: change)
                    Rectangle().fill(Color.panelSeparator)
                        .frame(height: 1)
                    secondaryMetrics(day)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .readableGlass(in: RoundedRectangle(cornerRadius: TimeInsightsMetrics.corner, style: .continuous))
    }

    private func activeMetric(_ day: TimeInsightsDay, change: Double?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(tr("今日活跃"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.panelSecondary)
            Text(TimeInsightsFormat.duration(day.active))
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.panelPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if let change {
                Text(tr("较昨日 \(TimeInsightsStats.changeText(change))"))
                    .font(.system(size: 13))
                    .foregroundStyle(.panelTertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func secondaryMetrics(_ day: TimeInsightsDay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            metricLine(tr("已分类工作"), value: day.work,
                       tint: Color(hex: TimeInsightsCategory.development.colorHex))
            metricLine(tr("未分类"), value: day.uncategorized,
                       tint: Color(hex: TimeInsightsCategory.uncategorized.colorHex))
        }
    }

    private func metricLine(_ label: String, value: TimeInterval, tint: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
                .lineLimit(1)
            Spacer(minLength: 3)
            Text(TimeInsightsFormat.duration(value))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - 今日分类：紧凑分布条，不与独立统计窗口重复

    private func distribution(_ day: TimeInsightsDay) -> some View {
        let ranking = day.categoryRanking
        return TimeInsightsCard(title: tr("今日时间分布")) {
            if day.active <= 0 || ranking.isEmpty {
                TimeInsightsEmptyNote(text: emptyText, symbol: "chart.bar")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    GeometryReader { geo in
                        let gap = CGFloat(max(0, ranking.count - 1)) * 2
                        HStack(spacing: 2) {
                            ForEach(ranking) { usage in
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color(hex: usage.category.colorHex))
                                    .frame(width: max(0, (geo.size.width - gap) * CGFloat(usage.active / day.active)))
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .frame(height: 9)
                    .accessibilityLabel(tr("今日时间分布"))
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                              alignment: .leading, spacing: 7) {
                        ForEach(ranking) { usage in
                            TimeInsightsLegendRow(colorHex: usage.category.colorHex,
                                                  label: usage.category.title,
                                                  value: "\(TimeInsightsStats.percent(usage.active, of: day.active))%")
                        }
                    }
                }
            }
        }
    }

    private var emptyText: String {
        switch tracker.status {
        case .paused: tr("已暂停记录，今天还没有数据。")
        case .storageError: tr("本机数据打不开，暂时没有可显示的记录。")
        default: tr("今天还没有记录。切到别的应用用一会儿，这里就会出现。")
        }
    }

    // MARK: - 应用 Top 3（完整 Top 5 和详情在独立窗口）

    private func topApps(_ day: TimeInsightsDay) -> some View {
        let top = day.top(3)
        let leader = top.first?.active ?? 0
        return TimeInsightsCard(title: tr("常用应用")) {
            if top.isEmpty {
                TimeInsightsEmptyNote(text: tr("还没有应用记录。"), symbol: "app.dashed")
            } else {
                VStack(spacing: 10) {
                    ForEach(top) { usage in
                        appRow(usage, leader: leader)
                    }
                }
            }
        }
    }

    private func appRow(_ usage: TimeInsightsAppUsage, leader: TimeInterval) -> some View {
        HStack(spacing: 9) {
            TimeInsightsAppIcon(bundleID: usage.bundleID)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text(usage.appName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.panelPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .layoutPriority(1)
                    Spacer(minLength: 4)
                    Text(TimeInsightsFormat.duration(usage.active))
                        .font(.system(size: 13))
                        .foregroundStyle(.panelSecondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                }
                TimeInsightsShareBar(fraction: leader > 0 ? usage.active / leader : 0,
                                     colorHex: usage.category.colorHex)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var currentActivity: some View {
        HStack(spacing: 8) {
            if tracker.status == .recording, let app = tracker.currentApp {
                TimeInsightsAppIcon(bundleID: app.bundleID)
                    .frame(width: 18, height: 18)
                Text(app.name)
                    .font(.system(size: 13))
                    .foregroundStyle(.panelPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                TimeInsightsCategoryTag(category: tracker.currentCategory)
            } else {
                Image(systemName: tracker.status.symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
                Text(tracker.status.title)
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
                Spacer(minLength: 4)
            }
        }
        .padding(.horizontal, 3)
        .accessibilityElement(children: .combine)
    }

    // MARK: - 单一详细入口与隐私控制

    private var statsLink: some View {
        Button {
            WidgetDetailWindow.shared.close()
            tracker.openStats()
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TimeInsightsStyle.accent)
                Text(tr("打开完整统计"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelPrimary)
                if !unlocked { ProBadge() }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelTertiary)
            }
            .padding(.horizontal, TimeInsightsMetrics.padding)
            .padding(.vertical, 11)
            .readableGlass(in: RoundedRectangle(cornerRadius: TimeInsightsMetrics.corner, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: TimeInsightsMetrics.corner, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(tr("查看日、周、月统计及应用详情；高级数据需 Pro 和单独授权。"))
    }

    private var privacyFooter: some View {
        HStack(spacing: 7) {
            Image(systemName: "lock.shield")
                .font(.system(size: 13))
                .foregroundStyle(.panelTertiary)
            Text(tr("数据仅保存在本机"))
                .font(.system(size: 13))
                .foregroundStyle(.panelTertiary)
            Spacer(minLength: 4)
            if let app = tracker.lastOtherApp, !tracker.settings.isExcluded(app.bundleID),
               tracker.status == .recording {
                Menu {
                    Button(tr("排除 \(app.name)")) {
                        tracker.exclude(app.bundleID)
                        notice = tr("已排除 \(app.name)，之后不再记录它。")
                    }
                    Button(tr("隐私与设置…")) { openSettings() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(.panelSecondary)
                }
                .menuStyle(.borderlessButton)
                .help(tr("排除当前应用或打开隐私设置"))
            }
            Button {
                openSettings()
            } label: {
                Text(tr("隐私与设置…"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
            }
            .buttonStyle(.plain)
            .help(tr("打开 设置 ▸ 时间洞察：记录开关、排除的应用、导出和清空数据"))
        }
    }

    private func openSettings() {
        WidgetDetailWindow.shared.close()
        tracker.openSettings()
    }
}

/// 简单的折行排布：一行放不下就换行。
struct TimeInsightsFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                y += row + spacing
                x = 0
                row = 0
            }
            x += size.width + spacing
            row = max(row, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += row + spacing
                x = bounds.minX
                row = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}

/// 应用图标：按 bundle ID 找到 App 再取图标，找不到时画一个中性的方块。
struct TimeInsightsAppIcon: View {
    var bundleID: String

    var body: some View {
        if let image = TimeInsightsIconCache.icon(bundleID) {
            Image(nsImage: image).resizable().interpolation(.high)
        } else {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.panelFill)
                .overlay {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 13))
                        .foregroundStyle(.panelTertiary)
                }
        }
    }
}

@MainActor
enum TimeInsightsIconCache {
    private static var cache: [String: NSImage] = [:]
    private static var missing: Set<String> = []

    static func icon(_ bundleID: String) -> NSImage? {
        if let hit = cache[bundleID] { return hit }
        if missing.contains(bundleID) { return nil }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            missing.insert(bundleID)
            return nil
        }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = image
        return image
    }
}
