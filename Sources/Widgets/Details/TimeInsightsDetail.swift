import AppKit
import SwiftUI

/// 时间洞察的主面板：顶上标题、「暂停记录」「完整统计」；四张指标卡（今日活跃、工作时长、
/// 未分类、空闲，较昨日只在昨天有真实记录时写）；24 小时活动分布（按分类堆叠）和图例；
/// 应用 Top 5、分类占比环形图、当前记录三块；底部一条 Pro 提示和隐私入口。
///
/// 面板宽 680（`TimeInsightsLayout.wideWidth`），高度由通用的 `DetailPanelFit` 管：
/// 不超过屏幕，内容多时整块滚动；内容区窄于 560 时（钉在桌面的小卡片）排成单列。
/// 统计页面只在这里和「完整统计」窗口里，设置页只管采集权限、隐私和配置。
/// 带字的玻璃底用 `readableGlass(in:)`，字号最小 13pt，跟随浅色、深色。
struct TimeInsightsDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var tracker: TimeInsightsTracker { .shared }

    @AppStorage(ProAccess.licenseKey) private var licenseUnlocked = false
    @AppStorage(Supporter.key) private var supporter = false
    private var unlocked: Bool { licenseUnlocked || supporter }

    @State private var contentWidth: CGFloat = TimeInsightsLayout.wideWidth - 32
    @State private var notice: String? = nil

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
                metrics(day)
                hourCard(day)
                lowerRow(day)
                proBar
                footer
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

    // MARK: 头部

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "clock")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(TimeInsightsStyle.accent)
                .frame(width: 32, height: 32)
                .readableGlass(in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(tr("时间洞察"))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.panelPrimary)
                HStack(spacing: 4) {
                    Image(systemName: tracker.status.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tracker.status == .recording ? TimeInsightsStyle.accent : Color.panelSecondary)
                    Text(tracker.status.title)
                        .font(.system(size: 13))
                        .foregroundStyle(.panelSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            pauseButton
            glassButton(tr("完整统计"), symbol: "chart.bar.xaxis") { openStats() }
                .help(tr("打开完整统计窗口：日、周、月统计、历史和分类规则"))
        }
    }

    private var pauseButton: some View {
        let paused = tracker.settings.paused
        return glassButton(paused ? tr("继续记录") : tr("暂停记录"), symbol: paused ? "play.fill" : "pause.fill") {
            tracker.setPaused(!paused)
        }
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

    // MARK: 指标卡

    @ViewBuilder
    private func metrics(_ day: TimeInsightsDay) -> some View {
        let cards = metricCards(day)
        if wide {
            HStack(spacing: TimeInsightsMetrics.spacing) {
                ForEach(cards.indices, id: \.self) { cards[$0] }
            }
        } else {
            Grid(horizontalSpacing: TimeInsightsMetrics.spacing, verticalSpacing: TimeInsightsMetrics.spacing) {
                GridRow {
                    cards[0]
                    cards[1]
                }
                GridRow {
                    cards[2]
                    cards[3]
                }
            }
        }
    }

    private func metricCards(_ day: TimeInsightsDay) -> [TimeInsightsMetricCard] {
        let change = TimeInsightsStats.change(today: day.active, yesterday: tracker.yesterday)
        let activeCaption = change.map { tr("较昨日 \(TimeInsightsStats.changeText($0))") }
        let share: (TimeInterval) -> String? = { part in
            day.active > 0 ? tr("占活跃时长 \(TimeInsightsStats.percent(part, of: day.active))%") : nil
        }
        let idleCaption = day.foreground > 0
            ? tr("占前台停留 \(TimeInsightsStats.percent(day.idleForeground, of: day.foreground))%") : nil
        return [
            TimeInsightsMetricCard(symbol: "waveform.path.ecg", title: tr("今日活跃"),
                                   value: TimeInsightsFormat.duration(day.active), caption: activeCaption,
                                   tint: TimeInsightsStyle.accent),
            TimeInsightsMetricCard(symbol: "laptopcomputer", title: tr("工作时长"),
                                   value: TimeInsightsFormat.duration(day.work), caption: share(day.work),
                                   tint: Color(hex: TimeInsightsCategory.development.colorHex)),
            TimeInsightsMetricCard(symbol: "tag", title: tr("未分类"),
                                   value: TimeInsightsFormat.duration(day.uncategorized),
                                   caption: share(day.uncategorized),
                                   tint: Color(hex: TimeInsightsCategory.uncategorized.colorHex)),
            TimeInsightsMetricCard(symbol: "cup.and.saucer", title: tr("空闲"),
                                   value: TimeInsightsFormat.duration(day.idleForeground), caption: idleCaption,
                                   tint: Color(hex: TimeInsightsCategory.other.colorHex)),
        ]
    }

    // MARK: 24 小时活动分布

    private func hourCard(_ day: TimeInsightsDay) -> some View {
        let slices = TimeInsightsChart.byCategory(day)
        let legend = TimeInsightsChart.legend(slices)
        return TimeInsightsCard(title: tr("24 小时活动分布")) {
            if slices.isEmpty {
                TimeInsightsEmptyNote(text: emptyText, symbol: "chart.bar")
            } else if wide {
                HStack(alignment: .top, spacing: 14) {
                    TimeInsightsHourChart(slices: slices, height: 140)
                    legendList(legend)
                        .frame(width: 170)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    TimeInsightsHourChart(slices: slices, height: 130)
                    legendList(legend)
                }
            }
        }
    }

    private func legendList(_ items: [TimeInsightsLegendItem]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(items) { item in
                TimeInsightsLegendRow(colorHex: item.colorHex, label: item.label,
                                      value: TimeInsightsFormat.duration(item.seconds))
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

    // MARK: Top 5、分类占比、当前记录

    @ViewBuilder
    private func lowerRow(_ day: TimeInsightsDay) -> some View {
        if wide {
            HStack(alignment: .top, spacing: TimeInsightsMetrics.spacing) {
                topApps(day)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .layoutPriority(1)
                categoryCard(day)
                    .frame(width: 216)
                    .frame(maxHeight: .infinity, alignment: .top)
                currentCard
                    .frame(width: 172)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: TimeInsightsMetrics.spacing) {
                topApps(day)
                categoryCard(day)
                currentCard
            }
        }
    }

    private func topApps(_ day: TimeInsightsDay) -> some View {
        let top = day.top()
        return TimeInsightsCard(title: tr("应用 Top 5")) {
            if top.isEmpty {
                TimeInsightsEmptyNote(text: tr("还没有应用记录。"), symbol: "app.dashed")
            } else {
                VStack(spacing: 7) {
                    ForEach(top) { usage in
                        appRow(usage)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func appRow(_ usage: TimeInsightsAppUsage) -> some View {
        HStack(spacing: 7) {
            TimeInsightsAppIcon(bundleID: usage.bundleID)
                .frame(width: 18, height: 18)
            Text(usage.appName)
                .font(.system(size: 13))
                .foregroundStyle(.panelPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
            TimeInsightsCategoryTag(category: usage.category)
            Spacer(minLength: 4)
            Text(TimeInsightsFormat.duration(usage.active))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.panelSecondary)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
    }

    private func categoryCard(_ day: TimeInsightsDay) -> some View {
        let ranking = day.categoryRanking
        return TimeInsightsCard(title: tr("分类占比")) {
            HStack(alignment: .center, spacing: 10) {
                TimeInsightsDonut(ranking: ranking, total: day.active, size: 92)
                VStack(alignment: .leading, spacing: 4) {
                    if ranking.isEmpty {
                        Text(tr("暂无数据"))
                            .font(.system(size: 13))
                            .foregroundStyle(.panelTertiary)
                    }
                    ForEach(ranking.prefix(6)) { usage in
                        TimeInsightsLegendRow(colorHex: usage.category.colorHex, label: usage.category.title,
                                              value: "\(TimeInsightsStats.percent(usage.active, of: day.active))%")
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var currentCard: some View {
        TimeInsightsCard(title: tr("当前记录")) {
            VStack(alignment: .leading, spacing: 8) {
                if tracker.status == .recording, let app = tracker.currentApp {
                    HStack(spacing: 8) {
                        TimeInsightsAppIcon(bundleID: app.bundleID)
                            .frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.panelPrimary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            TimeInsightsCategoryTag(category: tracker.currentCategory)
                        }
                    }
                    if let start = tracker.currentSegmentStart {
                        Text(tr("本段 \(TimeInsightsFormat.duration(context.now.timeIntervalSince(start)))"))
                            .font(.system(size: 13))
                            .foregroundStyle(.panelSecondary)
                            .monospacedDigit()
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: tracker.status.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.panelSecondary)
                        Text(tracker.status.title)
                            .font(.system(size: 13))
                            .foregroundStyle(.panelSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                pauseButton
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let app = tracker.lastOtherApp, !tracker.settings.isExcluded(app.bundleID),
                   tracker.status == .recording {
                    Button {
                        tracker.exclude(app.bundleID)
                        say(tr("已排除 \(app.name)，之后不再记录它。"))
                    } label: {
                        Text(tr("排除此应用"))
                            .font(.system(size: 13))
                            .foregroundStyle(.panelSecondary)
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .help(tr("排除后，这个应用在前台时不记录。可在 设置 ▸ 时间洞察 里移除。"))
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: Pro 提示、隐私入口

    private var proBar: some View {
        Button { openStats() } label: {
            HStack(spacing: 10) {
                Image(systemName: "crown")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: ShelfColor.redPanda.hex))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(tr("更多统计"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.panelPrimary)
                        ProBadge()
                    }
                    Text(unlocked
                         ? tr("周、月趋势、完整应用排行和自定义分类规则都在完整统计里。")
                         : tr("解锁 Pro 查看周、月趋势、完整应用排行和自定义分类规则。"))
                        .font(.system(size: 13))
                        .foregroundStyle(.panelSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelTertiary)
            }
            .padding(.horizontal, TimeInsightsMetrics.padding)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .readableGlass(in: RoundedRectangle(cornerRadius: TimeInsightsMetrics.corner, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: TimeInsightsMetrics.corner, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield")
                .font(.system(size: 13))
                .foregroundStyle(.panelTertiary)
            Text(tr("只记应用名称和时长，不读按键、不截图，数据只存在这台 Mac 上。"))
                .font(.system(size: 13))
                .foregroundStyle(.panelTertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button {
                WidgetDetailWindow.shared.close()
                tracker.openSettings()
            } label: {
                Text(tr("隐私与设置…"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
            }
            .buttonStyle(.plain)
            .help(tr("打开 设置 ▸ 时间洞察：记录开关、排除的应用、导出和清空数据"))
        }
    }

    // MARK: 小工具

    private func openStats() {
        WidgetDetailWindow.shared.close()
        tracker.openStats()
    }

    private func glassButton(_ title: String, symbol: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                }
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(.panelPrimary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .readableGlass(in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func say(_ text: String) {
        withAnimation(.easeOut(duration: 0.2)) { notice = text }
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
