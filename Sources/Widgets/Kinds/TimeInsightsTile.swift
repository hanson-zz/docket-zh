import AppKit
import SwiftUI

// MARK: - 时间洞察 · 扩展栏卡片
//
// 横排：方底里是状态图标，右边今日有效活跃时长、当前 App 和分类（或暂停、离开这类状态），
// 下面一条小进度条（8 小时满格，只是参照）。竖排 76 宽：图标、「3:12」、当前 App、进度条。
// 数据来自 `TimeInsightsTracker`，库里预览也读真实的今日数据，没有记录时写 0，不放示例数字。
// 点卡片打开面板（`TimeInsightsDetail`）。

struct TimeInsightsTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @Environment(\.widgetTint) private var tint
    @Environment(\.colorScheme) private var scheme

    private var tracker: TimeInsightsTracker { .shared }

    private var accent: Color { tint?.main(dark: scheme == .dark) ?? TimeInsightsStyle.accent }

    var body: some View {
        let day = tracker.today
        let status = tracker.status
        return WidgetSurface {
            Group {
                if context.position.isVertical {
                    column(day, status)
                } else {
                    row(day, status)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("时间洞察，今日活跃 \(TimeInsightsFormat.duration(day.active))"))
        .accessibilityValue(caption(status))
        .help(tr("今日有效活跃时长，进度条以 8 小时为满格。点开查看今日总览。"))
    }

    /// 正在记的时候写「Xcode · 开发」，别的时候写状态。
    private func caption(_ status: TimeInsightsStatus) -> String {
        if context.isPreview, tracker.today.isEmpty { return tr("放上扩展栏后开始记录") }
        if status == .recording, let app = tracker.currentApp {
            return "\(app.name) · \(tracker.currentCategory.title)"
        }
        return status.shortTitle
    }

    private func row(_ day: TimeInsightsDay, _ status: TimeInsightsStatus) -> some View {
        HStack(spacing: CGFloat(DockMetrics.rowSpacing)) {
            TileBadge {
                Image(systemName: status.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(status == .recording ? accent : WidgetStyle.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(TimeInsightsFormat.duration(day.active))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(WidgetStyle.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(caption(status))
                    .font(.system(size: 13))
                    .foregroundStyle(WidgetStyle.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                TimeInsightsBar(fraction: TimeInsightsFormat.barFraction(day.active), color: accent)
                    .frame(height: 4)
            }
            Spacer(minLength: 0)
        }
    }

    private func column(_ day: TimeInsightsDay, _ status: TimeInsightsStatus) -> some View {
        VStack(spacing: 4) {
            TileBadge(size: CGFloat(DockMetrics.badgeColumn)) {
                Image(systemName: status.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(status == .recording ? accent : WidgetStyle.secondary)
            }
            Text(verbatim: TimeInsightsFormat.clock(day.active))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(WidgetStyle.primary)
                .monospacedDigit()
            Text(status == .recording ? (tracker.currentApp?.name ?? status.shortTitle) : status.shortTitle)
                .font(.system(size: 13))
                .foregroundStyle(WidgetStyle.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            TimeInsightsBar(fraction: TimeInsightsFormat.barFraction(day.active), color: accent)
                .frame(height: 4)
                .padding(.horizontal, 4)
        }
    }
}

/// 一条细进度条：淡底加实色的已用部分。
struct TimeInsightsBar: View {
    var fraction: Double
    var color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(WidgetStyle.primary.opacity(0.1))
                Capsule()
                    .fill(color)
                    .frame(width: max(fraction > 0 ? 4 : 0, geo.size.width * fraction))
            }
        }
        .accessibilityHidden(true)
    }
}

/// 时间洞察的颜色：沉静的青绿（和 `WidgetTint` 里这种卡片的默认色一致），不用大面积蓝色。
enum TimeInsightsStyle {
    static let accent = Color(hex: "#2BA58C")
}
