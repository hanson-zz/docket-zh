import AppKit
import SwiftUI

/// 时间洞察的独立统计窗口。真正的日统计免费；周/月趋势只对已解锁 Pro 展示。
/// 不截图，不读取网页或窗口标题；所有数据从本机 TimeInsights 数据库获得。
@MainActor
final class TimeInsightsStatsWindow {
    static let shared = TimeInsightsStatsWindow()
    private let host = HostedWindow()

    func show() {
        host.present(TimeInsightsStatsView(), title: tr("时间洞察 · 完整统计"),
                     size: NSSize(width: 950, height: 680), resizable: true)
    }
}

private enum TimeInsightsStatsTab: String, CaseIterable, Identifiable {
    case day, week, month
    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: tr("日统计")
        case .week: tr("周统计")
        case .month: tr("月统计")
        }
    }
}

struct TimeInsightsStatsView: View {
    @AppStorage(ProAccess.licenseKey) private var licenseUnlocked = false
    @AppStorage(Supporter.key) private var supporter = false

    @State private var tab: TimeInsightsStatsTab = .day
    @State private var offset = 0

    private var tracker: TimeInsightsTracker { .shared }
    private var unlocked: Bool { licenseUnlocked || supporter }

    private var date: Date {
        switch tab {
        case .day:
            Calendar.current.date(byAdding: .day, value: offset, to: .now) ?? .now
        case .week:
            TimeInsightsPeriod.shift(.now, kind: .week, by: offset)
        case .month:
            TimeInsightsPeriod.shift(.now, kind: .month, by: offset)
        }
    }

    var body: some View {
        // 观察每日真实记录，让窗口在采集或暂停时更新，不依赖演示数据。
        let _ = tracker.today
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                TimeInsightsBrandIcon().frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text(tr("时间洞察"))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.panelPrimary)
                    Text(tr("本机活动统计"))
                        .font(.system(size: 13))
                        .foregroundStyle(.panelSecondary)
                }
                Spacer(minLength: 12)
                Button(tracker.settings.paused ? tr("继续记录") : tr("暂停记录")) {
                    tracker.setPaused(!tracker.settings.paused)
                }
                Button(tr("隐私与设置…")) { tracker.openSettings() }
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 16)

            HStack(alignment: .center, spacing: 14) {
                Picker("", selection: $tab) {
                    ForEach(TimeInsightsStatsTab.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 280)
                .onChange(of: tab) { _, _ in offset = 0 }

                Spacer()
                Button { offset -= 1 } label: {
                    Image(systemName: "chevron.left")
                }
                .help(tr("上一期"))

                Text(date.formatted(.dateTime.year().month().day()))
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .frame(minWidth: 108)

                Button { offset += 1 } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(offset >= 0)
                .help(tr("下一期"))
                Button(tr("今天")) { offset = 0 }
                    .disabled(offset == 0)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if tracker.storageProblem != nil {
                        Label(tracker.storageProblem ?? tr("本机数据不可用"), systemImage: "exclamationmark.triangle")
                            .font(.system(size: 13))
                            .foregroundStyle(.orange)
                    } else if tab != .day && !unlocked {
                        proPlaceholder
                    } else {
                        actualStatistics
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(24)
            }
        }
        .frame(minWidth: 700, minHeight: 480)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var actualStatistics: some View {
        let interval = intervalForSelection
        if let sessions = tracker.sessions(overlapping: interval) {
            if tab == .day {
                dayStatistics(TimeInsightsDay.make(sessions, day: date))
            } else {
                let period = TimeInsightsPeriod.make(sessions, interval: interval)
                periodStatistics(period)
            }
        } else {
            TimeInsightsEmptyNote(text: tr("本机记录暂时无法读取，请检查隐私与数据设置。"),
                                  symbol: "exclamationmark.triangle")
        }
    }

    private var intervalForSelection: DateInterval {
        switch tab {
        case .day: TimeInsightsMath.dayInterval(date)
        case .week: TimeInsightsPeriod.interval(.week, containing: date)
        case .month: TimeInsightsPeriod.interval(.month, containing: date)
        }
    }

    private func metrics(active: TimeInterval, work: TimeInterval, uncategorized: TimeInterval) -> some View {
        HStack(spacing: 12) {
            metric(tr("有效活跃"), value: TimeInsightsFormat.duration(active))
            metric(tr("已分类工作"), value: TimeInsightsFormat.duration(work))
            metric(tr("未分类"), value: TimeInsightsFormat.duration(uncategorized))
        }
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.panelSecondary)
            Text(value)
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundStyle(.panelPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .readableGlass(in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func dayStatistics(_ day: TimeInsightsDay) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            metrics(active: day.active, work: day.work, uncategorized: day.uncategorized)

            TimeInsightsCard(title: tr("24 小时活动分布")) {
                if day.active <= 0 {
                    TimeInsightsEmptyNote(text: tr("这一天没有有效活跃记录。"), symbol: "chart.bar")
                } else {
                    TimeInsightsHourChart(slices: TimeInsightsChart.byCategory(day), height: 180)
                }
            }

            HStack(alignment: .top, spacing: 12) {
                TimeInsightsCard(title: tr("常用应用")) {
                    appRanking(day.apps, maxItems: 5)
                }
                TimeInsightsCard(title: tr("分类占比")) {
                    categoryBreakdown(day.categoryRanking, total: day.active)
                }
            }

            Text(tr("前台停留含 \(TimeInsightsFormat.duration(day.idleForeground)) 无操作时间；未分类不会计入工作。"))
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
        }
    }

    private func periodStatistics(_ period: TimeInsightsPeriod) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            metrics(active: period.active, work: period.work, uncategorized: period.uncategorized)

            TimeInsightsCard(title: tr("每日活动分布")) {
                if period.isEmpty {
                    TimeInsightsEmptyNote(text: tr("这一段时间没有有效活跃记录。"), symbol: "calendar")
                } else {
                    VStack(spacing: 10) {
                        ForEach(period.days) { day in
                            periodDayRow(day, maximum: period.days.map(\.active).max() ?? 0)
                        }
                    }
                }
            }

            HStack(alignment: .top, spacing: 12) {
                TimeInsightsCard(title: tr("常用应用")) {
                    appRanking(period.apps, maxItems: 10)
                }
                TimeInsightsCard(title: tr("分类占比")) {
                    categoryBreakdown(period.categories, total: period.active)
                }
            }
            Text(tr("每段时间都由本机活动记录计算。更细的窗口标题、网站域名和完整时间轴仍在开发中。"))
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
        }
    }

    private func periodDayRow(_ day: TimeInsightsPeriod.DayTotal, maximum: TimeInterval) -> some View {
        HStack(spacing: 10) {
            Text(day.date.formatted(.dateTime.month().day().weekday(.abbreviated)))
                .font(.system(size: 12))
                .foregroundStyle(.panelSecondary)
                .frame(width: 90, alignment: .leading)
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    ForEach(TimeInsightsCategory.allCases, id: \.rawValue) { category in
                        let seconds = day.categories[category] ?? 0
                        if seconds > 0, maximum > 0 {
                            Rectangle()
                                .fill(Color(hex: category.colorHex))
                                .frame(width: geometry.size.width * CGFloat(seconds / maximum))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.panelTrack)
                .clipShape(Capsule())
            }
            .frame(height: 12)
            Text(TimeInsightsFormat.compactDuration(day.active))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.panelSecondary)
                .monospacedDigit()
                .frame(width: 77, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func appRanking(_ apps: [TimeInsightsAppUsage], maxItems: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            let visible = Array(apps.prefix(maxItems))
            if visible.isEmpty {
                TimeInsightsEmptyNote(text: tr("还没有应用记录。"), symbol: "app.dashed")
            }
            ForEach(visible) { usage in
                HStack(spacing: 9) {
                    TimeInsightsAppIcon(bundleID: usage.bundleID)
                        .frame(width: 25, height: 25)
                    Text(usage.appName)
                        .font(.system(size: 13))
                        .foregroundStyle(.panelPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text(TimeInsightsFormat.duration(usage.active))
                        .font(.system(size: 13))
                        .foregroundStyle(.panelSecondary)
                        .monospacedDigit()
                }
            }
        }
    }

    private func categoryBreakdown(_ categories: [TimeInsightsCategoryUsage], total: TimeInterval) -> some View {
        VStack(spacing: 12) {
            TimeInsightsDonut(ranking: categories, total: total, size: 125)
            if categories.isEmpty {
                Text(tr("暂无数据")).foregroundStyle(.panelSecondary).font(.system(size: 13))
            } else {
                ForEach(categories) { category in
                    TimeInsightsLegendRow(colorHex: category.category.colorHex,
                                          label: category.category.title,
                                          value: "\(TimeInsightsStats.percent(category.active, of: total))%")
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var proPlaceholder: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(tr("周、月趋势属于码头 Pro"), systemImage: "crown")
                .font(.system(size: 18, weight: .semibold))
            Text(tr("免费版仍可查看今日应用使用时间。解锁 Pro 后可查看真实的每周、每月分类和应用趋势。"))
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
            Button(tr("了解码头 Pro")) { PaywallWindow.shared.show() }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .readableGlass(in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}
