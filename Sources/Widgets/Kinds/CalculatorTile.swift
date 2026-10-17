import SwiftUI

/// The last sum and its answer. Working it out happens in the panel, which
/// has the keypad and takes the keyboard; the shelf cannot.
struct CalculatorTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var expression: String {
        context.isPreview ? "128 × 3.5" : instance.config.string("expression")
    }

    private var answer: String {
        guard !expression.isEmpty else { return "0" }
        switch Calculator.evaluate(expression) {
        case .success(let value): return Calculator.format(value)
        case .failure: return "-"
        }
    }

    var body: some View {
        let column = context.position.isVertical
        return WidgetSurface {
            if column {
                VStack(spacing: 4) {
                    badge(size: 30)
                    Text(answer)
                        .font(WidgetStyle.title)
                        .foregroundStyle(WidgetStyle.primary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            } else {
                HStack(spacing: WidgetStyle.rowSpacing) {
                    badge(size: WidgetStyle.badge)
                    TileReading(value: answer,
                                caption: expression.isEmpty ? tr("点按开始计算") : expression)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func badge(size: CGFloat) -> some View {
        TileBadge(size: size) {
            Image(systemName: "plus.forwardslash.minus")
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(WidgetStyle.primary)
        }
    }
}
