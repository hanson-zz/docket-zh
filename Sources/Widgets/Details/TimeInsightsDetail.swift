import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 时间洞察的面板：今日总览（活跃、工作、其他、未分类四格和前台停留的说明）、应用 Top 5、
/// 免费摘要、Pro 功能说明（阶段 A 全部「待接通」，只写说明不放数据），最后是隐私与数据：
/// 暂停、排除当前应用、导出 CSV、清空数据、在访达中显示，全部免费。
///
/// 面板高度由通用的 `DetailPanelFit` 管：不超过屏幕，内容多时整块滚动。带字的玻璃底用
/// `readableGlass(in:)`，字号最小 13pt，跟随浅色、深色。
struct TimeInsightsDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var tracker: TimeInsightsTracker { .shared }

    @AppStorage(ProAccess.licenseKey) private var licenseUnlocked = false
    @AppStorage(Supporter.key) private var supporter = false
    private var unlocked: Bool { licenseUnlocked || supporter }

    @State private var confirmingClear = false
    @State private var notice: String? = nil

    var body: some View {
        let day = tracker.today
        DetailCard {
            MeshBackdrop(color: TimeInsightsStyle.accent)
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                header(day)
                if let problem = tracker.storageProblem {
                    warning(problem)
                }
                overview(day)
                topApps(day)
                summary(day)
                proSection
                privacySection
                if let notice {
                    Text(notice)
                        .font(.system(size: 13))
                        .foregroundStyle(.panelSecondary)
                        .transition(.opacity)
                }
            }
        }
    }

    // MARK: 头部

    private func header(_ day: TimeInsightsDay) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(tr("今日活跃"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelSecondary)
                Text(TimeInsightsFormat.duration(day.active))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.panelPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                HStack(spacing: 5) {
                    Image(systemName: tracker.status.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tracker.status == .recording ? TimeInsightsStyle.accent : Color.panelSecondary)
                    Text(statusLine)
                        .font(.system(size: 13))
                        .foregroundStyle(.panelSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            pauseButton
        }
    }

    private var statusLine: String {
        let status = tracker.status
        if status == .recording, let app = tracker.currentApp {
            return tr("正在记录：\(app.name) · \(tracker.currentCategory.title)")
        }
        return status.title
    }

    private var pauseButton: some View {
        let paused = tracker.settings.paused
        return Button {
            tracker.setPaused(!paused)
        } label: {
            Label(paused ? tr("继续记录") : tr("暂停记录"), systemImage: paused ? "play.fill" : "pause.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelPrimary)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .readableGlass(in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
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
        .readableGlass(in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: 今日总览

    private func overview(_ day: TimeInsightsDay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    StatChip(label: tr("活跃"), value: TimeInsightsFormat.duration(day.active))
                    StatChip(label: tr("工作"), value: TimeInsightsFormat.duration(day.work))
                }
                GridRow {
                    StatChip(label: tr("其他"), value: TimeInsightsFormat.duration(day.other))
                    StatChip(label: tr("未分类"), value: TimeInsightsFormat.duration(day.uncategorized))
                }
            }
            Text(tr("前台停留 \(TimeInsightsFormat.duration(day.foreground))，其中 \(TimeInsightsFormat.duration(day.idleForeground)) 没有键盘鼠标操作，不算活跃。"))
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(tr("工作只算开发、设计、学习、沟通几类；认不出的应用留在未分类，不当成工作。"))
                .font(.system(size: 13))
                .foregroundStyle(.panelTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Top 5

    private func topApps(_ day: TimeInsightsDay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("应用 Top 5"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelSecondary)
            let top = day.top()
            if top.isEmpty {
                Text(emptyText)
                    .font(.system(size: 13))
                    .foregroundStyle(.panelSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                let most = max(1, top.first?.active ?? 1)
                VStack(spacing: 6) {
                    ForEach(top) { usage in
                        appRow(usage, fraction: usage.active / most)
                    }
                }
                .padding(10)
                .readableGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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

    private func appRow(_ usage: TimeInsightsAppUsage, fraction: Double) -> some View {
        HStack(spacing: 8) {
            TimeInsightsAppIcon(bundleID: usage.bundleID)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(usage.appName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.panelPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(usage.category.title)
                        .font(.system(size: 13))
                        .foregroundStyle(.panelTertiary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(TimeInsightsFormat.duration(usage.active))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.panelSecondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                TimeInsightsBar(fraction: fraction, color: TimeInsightsStyle.accent.opacity(0.85))
                    .frame(height: 4)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: 免费摘要

    @ViewBuilder
    private func summary(_ day: TimeInsightsDay) -> some View {
        if let longest = day.longest, day.active > 0 {
            Text(tr("今天共 \(day.segments) 段活跃，最长一段连续 \(TimeInsightsFormat.duration(longest.active))，在 \(longest.appName)。"))
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Pro（待接通）

    private var proSection: some View {
        DetailFold(key: "timeInsights.proFold") {
            HStack(spacing: 6) {
                Text(tr("更多统计"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.panelSecondary)
                ProBadge()
                Text(tr("待接通"))
                    .font(.system(size: 13))
                    .foregroundStyle(.panelTertiary)
            }
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(TimeInsightsProFeature.allCases, id: \.self) { feature in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: feature.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.panelSecondary)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(feature.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.panelPrimary)
                                Text(tr("待接通"))
                                    .font(.system(size: 13))
                                    .foregroundStyle(.panelTertiary)
                            }
                            Text(feature.detail)
                                .font(.system(size: 13))
                                .foregroundStyle(.panelSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Text(unlocked
                     ? tr("这些功能还在开发中，接通前不会采集任何窗口标题或网站。")
                     : tr("这些是 Pro 功能，还在开发中。接通前不会采集任何窗口标题或网站。"))
                    .font(.system(size: 13))
                    .foregroundStyle(.panelTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(tr("购买 Pro 不等于同意采集：窗口标题和网站需要你逐项单独打开，默认关闭，随时可以撤销。"))
                    .font(.system(size: 13))
                    .foregroundStyle(.panelTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .readableGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: 隐私与数据（免费）

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("隐私与数据"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.panelSecondary)
            Text(tr("只记前台应用的名称和时长，不读按键内容、不截图、不上传，数据只存在这台 Mac 上。无操作满 \(tracker.settings.idleMinutes) 分钟算离开，可在设置 ▸ 小组件 ▸ 时间洞察里改。"))
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
                .fixedSize(horizontal: false, vertical: true)
            FlowButtons {
                if let app = tracker.lastOtherApp, !tracker.settings.isExcluded(app.bundleID) {
                    glassButton(tr("排除 \(app.name)"), symbol: "eye.slash") {
                        tracker.exclude(app.bundleID)
                        say(tr("已排除 \(app.name)，之后不再记录它。"))
                    }
                }
                glassButton(tr("导出 CSV…"), symbol: "square.and.arrow.up") { export() }
                glassButton(tr("在访达中显示"), symbol: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([tracker.storageURL])
                }
                glassButton(tr("清空数据…"), symbol: "trash") { confirmingClear = true }
            }
            if confirmingClear {
                HStack(spacing: 8) {
                    Text(tr("清空这台 Mac 上全部时间洞察记录？不能撤销。"))
                        .font(.system(size: 13))
                        .foregroundStyle(.panelPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    glassButton(tr("取消"), symbol: nil) { confirmingClear = false }
                    Button {
                        tracker.clearAll()
                        confirmingClear = false
                        say(tr("已清空全部记录。"))
                    } label: {
                        Text(tr("清空"))
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 12)
                            .frame(height: 28)
                    }
                    .buttonStyle(PanelSolidButtonStyle(fill: Color(hex: "#D64545"), shape: Capsule()))
                }
                .padding(10)
                .readableGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
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

    private func export() {
        let panel = NSSavePanel()
        let stamp = Date.now.formatted(.iso8601.year().month().day())
        panel.nameFieldStringValue = "TimeInsights-\(stamp).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true
        // 面板在扩展栏那一层之上，存储窗口要再高一层才不会被它挡住。
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 3)
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try tracker.exportCSV(to: url)
            say(tr("已导出：\(url.lastPathComponent)"))
        } catch {
            say(tr("导出失败"))
        }
    }
}

/// 按钮多了自动折行。
private struct FlowButtons<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        TimeInsightsFlowLayout(spacing: 6) { content() }
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
