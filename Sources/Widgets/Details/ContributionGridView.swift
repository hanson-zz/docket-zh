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
                        .strokeBorder(.white.opacity(0.9), lineWidth: cell >= 8 ? 1 : 0.75)
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
        if day.isFuture { return .white.opacity(0.03) }
        switch day.level {
        case 0: return .white.opacity(0.09)
        case 1: return color.opacity(0.35)
        case 2: return color.opacity(0.55)
        case 3: return color.opacity(0.75)
        default: return color
        }
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

    var body: some View {
        HStack(spacing: 2) {
            Text("少").padding(.trailing, 2)
            ForEach(0...ContributionGrid.maxLevel, id: \.self) { level in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(level == 0 ? Color.white.opacity(0.09) : color.opacity([0, 0.35, 0.55, 0.75, 1][level]))
                    .frame(width: cell, height: cell)
            }
            Text("多").padding(.leading, 2)
        }
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(.white.opacity(0.5))
        .accessibilityHidden(true)
    }
}
