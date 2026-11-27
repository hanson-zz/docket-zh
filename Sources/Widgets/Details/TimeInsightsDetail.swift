import AppKit
import SwiftUI

/// 时间洞察：Dock 扩展栏展开面板，浅色/深色跟随系统。
/// 只显示本地实际记录；窗口标题、网站与 AI 统计仍待单独授权/接通。
/// 日/周/月的完整统计和详细历史继续放在独立窗口中。
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
            VStack(alignment: .leading, spacing: TimeInsightsMetrics.spacing) {
                header
                if let problem = tracker.storageProblem {
                    warning(problem)
                }
                heroCards(day)
                currentActivity
                distribution(day)
                topApps(day)
                activityPreview(day)
                actions
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

    // MARK: 标题与控制

    private var header: some View {
        HStack(spacing: 10) {
            TimeInsightsBrandIcon()
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 3) {
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
                .frame(width: 31, height: 31)
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
                .foregroundStyle(.orange)
            Text(text)
                .foregroundStyle(.panelPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 13))
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .readableGlass(in: RoundedRectangle(cornerRadius: TimeInsightsMetrics.corner, style: .continuous))
    }

    // MARK: 顶部两张卡片（真实数据）

    @ViewBuilder
    private func heroCards(_ day: TimeInsightsDay) -> some View {
        if wide {
            HStack(spacing: TimeInsightsMetrics.spacing) {
                activeHero(day)
                    .frame(maxWidth: .infinity)
                workHero(day)
                    .frame(maxWidth: .infinity)
            }
        } else {
            VStack(spacing: TimeInsightsMetrics.spacing) {
                activeHero(day)
                workHero(day)
            }
        }
    }

    private func activeHero(_ day: TimeInsightsDay) -> some View {
        let change = TimeInsightsStats.change(today: day.active, yesterday: tracker.yesterday)
        return HStack(alignment: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text(tr("今日活跃"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
                Text(TimeInsightsFormat.duration(day.active))
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(.panelPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let change {
                    Text(tr("较昨日 \(TimeInsightsStats.changeText(change))"))
                        .font(.system(size: 12))
                        .foregroundStyle(.panelTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            TimeInsightsMascot()
                .frame(width: wide ? 72 : 90, height: 84, alignment: .bottom)
                .padding(.trailing, -5)
                .padding(.bottom, -6)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
        .readableGlass(in: RoundedRectangle(cornerRadius: TimeInsightsMetrics.corner, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func workHero(_ day: TimeInsightsDay) -> some View {
        let percentage = TimeInsightsStats.percent(day.work, of: day.active)
        return HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("已分类工作"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(TimeInsightsFormat.duration(day.work))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.panelPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ZStack {
                Circle()
                    .stroke(Color.panelTrack, lineWidth: 6)
                Circle()
                    .trim(from: 0, to: min(1, max(0, day.active > 0 ? day.work / day.active : 0)))
                    .stroke(TimeInsightsStyle.accent,
                            style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(percentage)%")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(.panelPrimary)
                    .monospacedDigit()
            }
            .frame(width: 53, height: 53)
            .accessibilityLabel(tr("已分类工作占活跃时间 \(percentage)%"))
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 110)
        .readableGlass(in: RoundedRectangle(cornerRadius: TimeInsightsMetrics.corner, style: .continuous))
    }

    // MARK: 当前应用：不在浏览器扩展接通前伪造站点和页面

    private var currentActivity: some View {
        HStack(spacing: 8) {
            Text(tr("当前应用"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.panelSecondary)
            Spacer(minLength: 3)
            if tracker.status == .recording, let app = tracker.currentApp {
                TimeInsightsAppIcon(bundleID: app.bundleID)
                    .frame(width: 18, height: 18)
                Text(app.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                TimeInsightsCategoryTag(category: tracker.currentCategory)
            } else {
                Image(systemName: tracker.status.symbol)
                    .foregroundStyle(.panelSecondary)
                    .font(.system(size: 12))
                Text(tracker.status.shortTitle)
                    .foregroundStyle(.panelSecondary)
                    .font(.system(size: 13))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 39)
        .readableGlass(in: RoundedRectangle(cornerRadius: TimeInsightsMetrics.corner, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: 分类分布：灰色明确表示未分类

    private func distribution(_ day: TimeInsightsDay) -> some View {
        let ranking = day.categoryRanking
        return TimeInsightsCard(title: tr("今日时间分布")) {
            if day.active <= 0 || ranking.isEmpty {
                TimeInsightsEmptyNote(text: emptyText, symbol: "chart.bar")
            } else {
                VStack(alignment: .leading, spacing: 9) {
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
                    .frame(height: 12)
                    .accessibilityLabel(tr("今日时间分布"))
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                              alignment: .leading, spacing: 6) {
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

    // MARK: 常用应用 Top 3

    private func topApps(_ day: TimeInsightsDay) -> some View {
        let top = day.top(3)
        let leader = top.first?.active ?? 0
        return TimeInsightsCard(title: tr("常用应用 Top 3")) {
            if top.isEmpty {
                TimeInsightsEmptyNote(text: tr("还没有应用记录。"), symbol: "app.dashed")
            } else {
                VStack(spacing: 9) {
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
                .frame(width: 27, height: 27)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(usage.appName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.panelPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(usage.category.title)
                            .font(.system(size: 12))
                            .foregroundStyle(.panelSecondary)
                            .lineLimit(1)
                    }
                    .layoutPriority(1)
                    Spacer(minLength: 3)
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

    // MARK: 时间轴预览：每格一个小时，显示该小时占主导的活动分类

    private func activityPreview(_ day: TimeInsightsDay) -> some View {
        TimeInsightsCard(title: tr("活动时间轴（预览）")) {
            if day.active <= 0 {
                TimeInsightsEmptyNote(text: tr("暂无活动记录"), symbol: "clock")
            } else {
                VStack(spacing: 7) {
                    HStack {
                        Text("00:00")
                        Spacer()
                        Text("06:00")
                        Spacer()
                        Text("12:00")
                        Spacer()
                        Text("18:00")
                        Spacer()
                        Text("24:00")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.panelTertiary)
                    HStack(spacing: 2) {
                        ForEach(0..<24, id: \.self) { hour in
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(timelineColor(day, hour: hour))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 10)
                    Text(tr("按小时展示主要活动分类，详细记录请打开完整统计"))
                        .font(.system(size: 11))
                        .foregroundStyle(.panelTertiary)
                        .lineLimit(2)
                }
            }
        }
    }

    private func timelineColor(_ day: TimeInsightsDay, hour: Int) -> Color {
        let categories = TimeInsightsCategory.allCases
        let strongest = categories.max { lhs, rhs in
            (day.hourCategories[lhs]?[hour] ?? 0) < (day.hourCategories[rhs]?[hour] ?? 0)
        }
        guard let strongest, (day.hourCategories[strongest]?[hour] ?? 0) > 0 else {
            return Color.panelTrack
        }
        return Color(hex: strongest.colorHex)
    }

    // MARK: 唯一主操作入口 + 隐私设置

    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                WidgetDetailWindow.shared.close()
                tracker.openStats()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(TimeInsightsStyle.accent)
                    Text(tr("打开完整统计"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.panelPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13))
                        .foregroundStyle(.panelTertiary)
                }
                .padding(.horizontal, 11)
                .frame(height: 42)
                .readableGlass(in: RoundedRectangle(cornerRadius: TimeInsightsMetrics.corner, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: TimeInsightsMetrics.corner, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(tr("查看日、周、月统计及应用详情；高级数据需 Pro 和单独授权。"))

            Button { openSettings() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                    Text(tr("隐私与设置…"))
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .foregroundStyle(.panelSecondary)
                .padding(.horizontal, 10)
                .frame(height: 42)
                .readableGlass(in: RoundedRectangle(cornerRadius: TimeInsightsMetrics.corner, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: TimeInsightsMetrics.corner, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(tr("打开 设置 ▸ 时间洞察：记录开关、排除的应用、导出和清空数据"))
        }
    }

    private var privacyFooter: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .font(.system(size: 12))
                .foregroundStyle(.panelTertiary)
            Text(tr("数据仅保存在本机"))
                .font(.system(size: 12))
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
        }
        .padding(.horizontal, 3)
    }

    private func openSettings() {
        WidgetDetailWindow.shared.close()
        tracker.openSettings()
    }
}

/// 直接复用码头现有的小熊猫笔记本插画，避免图像模型临时重画造成形象不统一。
private struct TimeInsightsMascot: View {
    var body: some View {
        Group {
            if let image = PandaStateArt.image("panda-scene-ai-input") {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
