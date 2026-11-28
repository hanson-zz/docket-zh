import Charts
import SwiftUI

// MARK: - 时间洞察 · 主面板和完整统计共用的图表与小部件
//
// 分类固定色来自 Core 的 `TimeInsightsCategory.colorHex`，柱状图、环形图、图例、标签
// 一套颜色。卡片统一 12pt 圆角、12pt 内边距，带字的玻璃底用 `readableGlass(in:)`，
// 字号最小 13pt。数据全部来自真实记录，没有数据时画空状态，不放示例数字。

enum TimeInsightsMetrics {
    static let corner: CGFloat = 12
    static let padding: CGFloat = 12
    static let spacing: CGFloat = 10
}

/// 一块带字的玻璃卡片，标题可选。
struct TimeInsightsCard<Content: View, Accessory: View>: View {
    var title: String?
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.panelPrimary)
                    Spacer(minLength: 4)
                    accessory()
                }
            }
            content()
        }
        .padding(TimeInsightsMetrics.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .readableGlass(in: RoundedRectangle(cornerRadius: TimeInsightsMetrics.corner, style: .continuous))
    }
}

extension TimeInsightsCard where Accessory == EmptyView {
    init(title: String?, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.accessory = { EmptyView() }
        self.content = content
    }
}

/// 一张指标卡：图标、名字、大数字和一行说明。
struct TimeInsightsMetricCard: View {
    var symbol: String
    var title: String
    var value: String
    var caption: String?
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.panelSecondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.panelPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption ?? " ")
                .font(.system(size: 13))
                .foregroundStyle(.panelTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .opacity(caption == nil ? 0 : 1)
        }
        .padding(TimeInsightsMetrics.padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .readableGlass(in: RoundedRectangle(cornerRadius: TimeInsightsMetrics.corner, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// 分类的小标签：一点分类色加分类名。
struct TimeInsightsCategoryTag: View {
    var category: TimeInsightsCategory

    var body: some View {
        let color = Color(hex: category.colorHex)
        Text(category.title)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(color.panelReadable)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(color.opacity(0.16)))
            .fixedSize()
    }
}

/// 图例的一行：色块、名字、时长（可选百分比）。
struct TimeInsightsLegendRow: View {
    var colorHex: String
    var label: String
    var value: String

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color(hex: colorHex))
                .frame(width: 10, height: 10)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(.panelPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
                .monospacedDigit()
                .lineLimit(1)
        }
    }
}

/// 24 小时堆叠柱状图（Swift Charts）。横轴 0 到 23 点每 3 小时一个刻度，纵轴是分钟。
struct TimeInsightsHourChart: View {
    var slices: [TimeInsightsHourSlice]
    var height: CGFloat = 150

    private static let hours = (0..<24).map { String($0) }
    private static let ticks = stride(from: 0, to: 24, by: 3).map { String($0) }

    var body: some View {
        let top = TimeInsightsChart.axisMinutes(slices)
        Chart(slices) { slice in
            BarMark(x: .value("hour", String(slice.hour)),
                    y: .value("minutes", slice.seconds / 60),
                    width: .ratio(0.68))
                .foregroundStyle(Color(hex: slice.colorHex))
                .cornerRadius(2)
        }
        .chartXScale(domain: Self.hours)
        .chartYScale(domain: 0...Double(top))
        .chartXAxis {
            AxisMarks(values: Self.ticks) { value in
                AxisValueLabel {
                    if let hour = value.as(String.self) {
                        Text(tr("\(hour)时"))
                            .font(.system(size: 13))
                            .foregroundStyle(.panelTertiary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading,
                      values: Array(stride(from: 0.0, through: Double(top), by: 15.0))) { value in
                AxisGridLine().foregroundStyle(Color.panelSeparator)
                AxisValueLabel {
                    if let minutes = value.as(Double.self) {
                        Text(tr("\(Int(minutes)) 分"))
                            .font(.system(size: 13))
                            .foregroundStyle(.panelTertiary)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .frame(height: height)
        .accessibilityLabel(tr("24 小时活动分布"))
    }
}

/// 分类占比环形图，中间写总时长。
struct TimeInsightsDonut: View {
    var ranking: [TimeInsightsCategoryUsage]
    var total: TimeInterval
    var size: CGFloat = 116

    var body: some View {
        ZStack {
            if ranking.isEmpty {
                Circle()
                    .stroke(Color.panelTrack, lineWidth: 14)
                    .padding(7)
            } else {
                Chart(ranking) { usage in
                    SectorMark(angle: .value("seconds", usage.active),
                               innerRadius: .ratio(0.66),
                               angularInset: 1.2)
                        .foregroundStyle(Color(hex: usage.category.colorHex))
                        .cornerRadius(2)
                }
                .chartLegend(.hidden)
            }
            VStack(spacing: 1) {
                Text(TimeInsightsFormat.duration(total))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.panelPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(tr("总活跃"))
                    .font(.system(size: 13))
                    .foregroundStyle(.panelTertiary)
            }
            .padding(.horizontal, 22)
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .combine)
    }
}

/// 一行横向占比条：淡底加实色。
struct TimeInsightsShareBar: View {
    var fraction: Double
    var colorHex: String

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.panelTrack)
                Capsule()
                    .fill(Color(hex: colorHex))
                    .frame(width: max(fraction > 0 ? 4 : 0, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

/// 没有数据时的一句话，居中、淡色。
struct TimeInsightsEmptyNote: View {
    var text: String
    var symbol: String = "hourglass"

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.panelTertiary)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.panelSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}
