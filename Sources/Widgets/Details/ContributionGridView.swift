import SwiftUI

/// 周格子的画法：一列一周，周一在上，按深浅档上色。
///
/// 第一次出现时格子从左往右一列一列亮起来，像贡献慢慢堆上去；今天那格描一圈白边，
/// 今天的档位变了会轻轻弹一下。打开“减少动态效果”时直接画成最终的样子。
struct ContributionGridView: View {
    var columns: [[ContributionGrid.Cell]]
    var color: Color
    var cell: CGFloat = 8
    var spacing: CGFloat = 2
    /// 悬停提示和读屏里数量后面的单位，比如“次”“条”。
    var unit: String = tr("次")

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var shown = false

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            ForEach(columns.indices, id: \.self) { column in
                VStack(spacing: spacing) {
                    ForEach(columns[column].indices, id: \.self) { row in
                        square(columns[column][row], column: column, row: row)
                    }
                }
            }
        }
        .onAppear {
            if reduceMotion { shown = true } else {
                withAnimation(.easeOut(duration: 0.3)) { shown = true }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }

    private func square(_ day: ContributionGrid.Cell, column: Int, row: Int) -> some View {
        let radius = max(1.5, cell * 0.25)
        let lit = shown || reduceMotion
        return RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(fill(day))
            .overlay {
                if day.isToday {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(.panelPrimary, lineWidth: cell >= 8 ? 1 : 0.75)
                }
            }
            .frame(width: cell, height: cell)
            .scaleEffect(lit ? 1 : 0.3)
            .opacity(lit ? 1 : 0)
            .animation(reduceMotion ? nil : Animation.spring(duration: 0.35, bounce: 0.4)
                .delay(ContributionGrid.delay(column: column, row: row, columns: columns.count)),
                       value: shown)
            .keyframeAnimator(initialValue: 1.0, trigger: reduceMotion || !day.isToday ? 0 : day.level) { view, scale in
                view.scaleEffect(scale)
            } keyframes: { _ in
                KeyframeTrack {
                    SpringKeyframe(1.0, duration: 0.01)
                    SpringKeyframe(1.35, duration: 0.15)
                    SpringKeyframe(1.0, duration: 0.3)
                }
            }
            .help(ContributionGrid.describe(day, unit: unit))
    }

    private func fill(_ day: ContributionGrid.Cell) -> Color {
        if day.isFuture { return Color.panelTrack.opacity(0.35) }
        return contributionShade(day.level, color: color, light: scheme == .light)
    }

    private var summary: String {
        let past = columns.joined().filter { !$0.isFuture }
        let active = past.filter { $0.count > 0 }.count
        return tr("最近 \(columns.count) 周，有记录的 \(active) 天")
    }
}

/// “少 ▢▢▢▢▢ 多”的图例。
struct ContributionLegend: View {
    var color: Color
    var cell: CGFloat = 7

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 2) {
            Text("少").padding(.trailing, 2)
            ForEach(0...ContributionGrid.maxLevel, id: \.self) { level in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(contributionShade(level, color: color, light: scheme == .light))
                    .frame(width: cell, height: cell)
            }
            Text("多").padding(.leading, 2)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.panelSecondary)
        .accessibilityHidden(true)
    }
}

/// 格子按档位上色。空格子用 `.panelTrack`（浅色玻璃上是淡淡的深色，深色下是原来的淡白）。
/// 深色外观沿用原来的透明度梯度；浅色外观下淡档在浅玻璃上发白看不清，
/// 改成像 GitHub 浅色主题那样越多越深：淡、中、原色、再加深一档。
private func contributionShade(_ level: Int, color: Color, light: Bool) -> Color {
    switch level {
    case ...0: return .panelTrack
    case 1: return color.opacity(light ? 0.42 : 0.35)
    case 2: return color.opacity(light ? 0.7 : 0.55)
    case 3: return light ? color : color.opacity(0.75)
    default: return light ? color.panelReadable : color
    }
}
