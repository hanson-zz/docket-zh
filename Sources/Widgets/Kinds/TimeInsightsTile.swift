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
                TimeInsightsBrandIcon()
                    .frame(width: 21, height: 21)
                    .opacity(status == .recording ? 1 : 0.75)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(tr("时间洞察"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WidgetStyle.secondary)
                    .lineLimit(1)
                Text(TimeInsightsFormat.duration(day.active))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(WidgetStyle.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(caption(status))
                    .font(.system(size: 12))
                    .foregroundStyle(WidgetStyle.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                TimeInsightsBar(fraction: TimeInsightsFormat.barFraction(day.active), color: accent)
                    .frame(height: 3)
            }
            Spacer(minLength: 0)
        }
    }

    private func column(_ day: TimeInsightsDay, _ status: TimeInsightsStatus) -> some View {
        VStack(spacing: 4) {
            TileBadge(size: CGFloat(DockMetrics.badgeColumn)) {
                TimeInsightsBrandIcon()
                    .frame(width: 19, height: 19)
                    .opacity(status == .recording ? 1 : 0.75)
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

/// 码头「时间洞察」专属图形：蓝色玻璃方底、时钟和三根青色统计柱。
/// 在 Dock 组件、展开面板和图标预览复用同一造型，缩小仍可识别。
struct TimeInsightsBrandIcon: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                RoundedRectangle(cornerRadius: side * 0.24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: scheme == .dark
                                ? [Color(hex: "#346DBA"), Color(hex: "#173F85")]
                                : [Color(hex: "#67CBF8"), Color(hex: "#385DE7")],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                RoundedRectangle(cornerRadius: side * 0.24, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.4), lineWidth: max(0.5, side * 0.018))
                Circle()
                    .trim(from: 0.04, to: 0.81)
                    .stroke(Color.white.opacity(0.95),
                            style: StrokeStyle(lineWidth: side * 0.075, lineCap: .round))
                    .rotationEffect(.degrees(-102))
                    .frame(width: side * 0.58, height: side * 0.58)
                    .offset(x: -side * 0.07, y: -side * 0.055)
                Path { path in
                    path.move(to: CGPoint(x: side * 0.45, y: side * 0.26))
                    path.addLine(to: CGPoint(x: side * 0.45, y: side * 0.45))
                    path.addLine(to: CGPoint(x: side * 0.56, y: side * 0.45))
                }
                .stroke(Color.white, style: StrokeStyle(lineWidth: side * 0.065, lineCap: .round, lineJoin: .round))
                HStack(alignment: .bottom, spacing: side * 0.026) {
                    RoundedRectangle(cornerRadius: side * 0.035, style: .continuous)
                        .frame(width: side * 0.105, height: side * 0.20)
                    RoundedRectangle(cornerRadius: side * 0.035, style: .continuous)
                        .frame(width: side * 0.105, height: side * 0.29)
                    RoundedRectangle(cornerRadius: side * 0.035, style: .continuous)
                        .frame(width: side * 0.105, height: side * 0.37)
                }
                .foregroundStyle(
                    LinearGradient(colors: [Color(hex: "#66E0ED"), Color(hex: "#18B4DC")],
                                   startPoint: .top, endPoint: .bottom)
                )
                .offset(x: side * 0.19, y: side * 0.22)
            }
            .frame(width: side, height: side)
        }
        .accessibilityHidden(true)
    }
}

/// 时间洞察的默认强调色与专属时钟图标统一；用户自定义 WidgetTint 仍优先。
enum TimeInsightsStyle {
    static let accent = Color(hex: "#3B8DEA")
}
