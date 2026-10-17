import Foundation
import SwiftUI

/// How much of the current day, week, month or year has already gone.
///
/// Four layouts share one number: the old `bars` run and the three looks of
/// the redesign, `ring` (the default for new cards), `percentage` and
/// `liquid`. The three new ones are built alike: a 24pt figure, an 11pt
/// caption and the same margins, so swapping looks does not reshuffle the
/// card. The fraction, the label and what is left come from `TimeProgress`
/// in Core, which reads the real calendar around `context.now`.
///
/// A click on the period name - and only on the name - moves the span on:
/// day → week → month → year. The card's own click belongs to the shelf, so
/// the control is as small as the thing it changes. The choice is `period` in
/// the widget's own config, the same key the catalog seeds, so it survives a
/// relaunch and follows the widget between profiles.
struct TimeProgressTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.widgetHovered) private var hovered
    @Environment(\.widgetTint) private var tint
    @Environment(\.colorScheme) private var scheme

    /// One bar per 3pt of the 156pt content width.
    private static let barCount = 52

    private var period: TimeProgress.Period { TimeProgress.period(instance.config) }

    private var layout: String { TimeProgress.layout(instance.config) }

    /// 0…1 through the current period.
    private var fraction: Double { TimeProgress.fraction(period, now: context.now) }

    private var percent: Int { TimeProgress.percent(fraction) }

    private var label: String { TimeProgress.label(period, now: context.now) }

    /// 「2026年 · 剩 80 天」
    private var caption: String { TimeProgress.caption(period, now: context.now) }

    /// 原来圆环、进度条和水共用的蓝色渐变。扩展栏上的卡片改用颜色主题
    /// （`WidgetTint`，时间进度默认紫），环境里没有主题色时才用这一对。
    static let light = Color(hex: TimeProgress.gradientHex.0)
    static let deep = Color(hex: TimeProgress.gradientHex.1)

    /// 主题色，调到在当前外观下看得清。
    private var accent: Color { tint?.main(dark: scheme == .dark) ?? Self.deep }

    var body: some View {
        WidgetSurface {
            Group {
                if context.position.isVertical {
                    // The 52-bar run cannot survive 56pt of usable width, so a
                    // column always rings - whatever the horizontal layout is.
                    if layout == "percentage" {
                        columnPercentage
                    } else if layout == LiquidMotion.layout {
                        columnLiquid
                    } else {
                        columnRing
                    }
                } else {
                    switch layout {
                    case "ring": ringLayout
                    case "percentage": percentageLayout
                    case LiquidMotion.layout: liquidLayout
                    default: barsLayout
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tr("时间进度，\(period.spoken)已过去 \(percent)%，\(TimeProgress.remaining(period, now: context.now))"))
    }

    /// Every layout reads `period`, so one write swaps the span in place and
    /// leaves the chosen layout alone.
    private func cycle() {
        let next = period.next
        withAnimation(.snappy(duration: 0.3)) {
            WidgetWriter.write(instance) { config in
                config.set(TimeProgress.periodKey, .string(next.rawValue))
            }
        }
    }

    // MARK: Layouts

    private var barsLayout: some View {
        VStack(alignment: .leading, spacing: 7) {
            // The shelf's two type styles: the figure as the value, the span
            // as the caption, on one line above the run of bars.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                legacyPercentText(19)
                periodLabel(12, text: label)
                Spacer(minLength: 0)
            }
            bars
        }
    }

    private var bars: some View {
        let filled = Int(fraction * Double(Self.barCount))
        return HStack(spacing: 4.0 / 3.0) {
            ForEach(0..<Self.barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 0.85, style: .continuous)
                    // Softened from full ink: a run of 52 solid white bars was
                    // the brightest thing on the shelf.
                    .fill(index < filled ? accent.opacity(0.85) : WidgetStyle.primary.opacity(0.12))
                    .frame(width: 5.0 / 3.0)
            }
        }
        .frame(height: 16)
    }

    /// 圆环版：圆环直接画在卡片上（不再垫一块方底），渐变描边；右边是
    /// 24pt 的百分比和 11pt 的「2026年 · 剩 80 天」。
    private var ringLayout: some View {
        HStack(spacing: 10) {
            GradientRing(progress: fraction, lineWidth: 5)
                .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 1) {
                percentText(24)
                periodLabel(11, text: caption)
            }
            Spacer(minLength: 0)
        }
    }

    /// 百分比版：数字靠左、周期靠右，底下一条进度条，端点有一点光。
    private var percentageLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                percentText(24)
                Spacer(minLength: 0)
                periodLabel(11, text: label)
            }
            GlowBar(progress: fraction, height: 5)
        }
    }

    /// 液态：整张卡片是一杯水，水从底边满宽涨到这段时间过去的比例，
    /// 水面一道亮线，几颗气泡慢慢往上冒。
    private var liquidLayout: some View {
        ZStack {
            water
            VStack(spacing: 1) {
                percentText(24)
                periodLabel(11, text: label)
            }
        }
    }

    private var water: some View {
        LiquidWater(level: fraction, tint: accent,
                    visible: !context.isPreview && ShelfVisibility.shared.cardsOnScreen,
                    still: !TimeProgress.liquidAnimates(instance.config, reduceMotion: reduceMotion),
                    shine: true, bubbles: 4)
            .fillingCard()
    }

    // MARK: Column layouts (76pt wide, 56pt usable)

    /// 侧边栏里的液态：一样铺满，数字在上，时段在下。
    private var columnLiquid: some View {
        ZStack {
            water
            VStack(spacing: 2) {
                percentText(21)
                    .minimumScaleFactor(0.6)
                periodLabel(10, text: label)
            }
        }
    }

    /// 76×80: ring with the figure inside, period beneath.
    private var columnRing: some View {
        VStack(spacing: 5) {
            ZStack {
                GradientRing(progress: fraction, lineWidth: 5)
                percentText(13)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, 3)
            }
            .frame(width: 44, height: 44)

            periodLabel(10, text: label)
        }
    }

    /// 76×58: the figure over the period, and the bar under both.
    private var columnPercentage: some View {
        VStack(spacing: 3) {
            percentText(21)
                .minimumScaleFactor(0.6)
            periodLabel(10, text: label)
            GlowBar(progress: fraction, height: 4)
        }
    }

    // MARK: Pieces

    /// The period name, and the tile's one control: clicking it moves the span
    /// on. Only the name is clickable, because a target that filled the card
    /// would beat the shelf's own click and the card would stop opening.
    ///
    /// The library draws live previews, where an action must never write
    /// config - and a button that refused to act would still swallow the
    /// click - so there the name is plain text.
    ///
    /// The chevron only shows while the pointer is on the card: the redesign
    /// keeps the caption quiet at rest, and the hover is when the control is
    /// about to be used.
    @ViewBuilder
    private func periodLabel(_ size: CGFloat, text: String) -> some View {
        if context.isPreview {
            periodText(size, text: text)
        } else {
            Button(action: cycle) {
                HStack(spacing: 2) {
                    periodText(size, text: text)
                    // Sized off the name beside it, so it never out-shouts
                    // the word it belongs to.
                    Image(systemName: "chevron.right")
                        .font(.system(size: size - 2, weight: .semibold))
                        .foregroundStyle(WidgetStyle.secondary)
                        .opacity(hovered ? 1 : 0)
                        .animation(.easeOut(duration: 0.15), value: hovered)
                }
                // Inside the row, so the target is the name and the glyph and
                // not a pixel more of the card.
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help("点按切换日、周、月、年")
            .accessibilityLabel("显示下一个时段")
        }
    }

    /// Long captions scale rather than truncating.
    private func periodText(_ size: CGFloat, text: String) -> some View {
        Text(text)
            .font(WidgetStyle.caption(size))
            .foregroundStyle(WidgetStyle.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    /// The figure is bold and primary, the sign smaller and quieter - reads as
    /// one number rather than a number shouting a unit.
    private func percentText(_ size: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(percent.formatted())
                .font(WidgetStyle.value(size))
                .foregroundStyle(WidgetStyle.primary)
                .rollingValue(percent)
            // 百分号用主题色做强调，数字本身保持主色最清楚。
            Text("%")
                .font(.system(size: size * 0.6, weight: .semibold))
                .foregroundStyle(tint == nil ? WidgetStyle.secondary : accent)
        }
        .monospacedDigit()
        .lineLimit(1)
    }

    /// The bars layout keeps its old figure: a saved card should not change.
    private func legacyPercentText(_ size: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text(percent.formatted())
                .foregroundStyle(WidgetStyle.primary)
            Text("%")
                .foregroundStyle(WidgetStyle.secondary)
        }
        .font(.system(size: size, weight: .semibold))
        .monospacedDigit()
        .lineLimit(1)
    }
}

/// 圆环版的环：淡淡的底环，上面一段主题色渐变的进度，圆头。
struct GradientRing: View {
    var progress: Double
    var lineWidth: CGFloat = 5

    @Environment(\.widgetTint) private var tint
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let light = tint?.light(dark: dark) ?? TimeProgressTile.light
        let deep = tint?.main(dark: dark) ?? TimeProgressTile.deep
        let value = min(1, max(0, progress.isFinite ? progress : 0))
        ZStack {
            Circle()
                .stroke(WidgetStyle.primary.opacity(0.12), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: value)
                .stroke(AngularGradient(colors: [light, deep],
                                        center: .center,
                                        startAngle: .degrees(0),
                                        endAngle: .degrees(360 * max(value, 0.01))),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
        .accessibilityHidden(true)
    }
}

/// 百分比版的进度条：浅底，主题色渐变的进度，端点一颗对比色的小点，
/// 只有一点点光晕。
struct GlowBar: View {
    var progress: Double
    var height: CGFloat = 5

    @Environment(\.widgetTint) private var tint
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let light = tint?.light(dark: dark) ?? TimeProgressTile.light
        let deep = tint?.main(dark: dark) ?? TimeProgressTile.deep
        let dotColor = tint?.contrast(dark: dark) ?? Color.white
        let glow = tint?.contrast(dark: dark) ?? TimeProgressTile.light
        let value = min(1, max(0, progress.isFinite ? progress : 0))
        GeometryReader { geometry in
            let width = geometry.size.width
            let dot = height + 3
            ZStack(alignment: .leading) {
                Capsule().fill(WidgetStyle.primary.opacity(0.12))
                Capsule()
                    .fill(LinearGradient(colors: [light, deep],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, width * value))
                Circle()
                    .fill(dotColor)
                    .frame(width: dot, height: dot)
                    .shadow(color: glow.opacity(tint == nil ? 0.9 : 0.5), radius: tint == nil ? 3 : 2)
                    .offset(x: min(max(0, width * value - dot / 2), width - dot))
            }
        }
        .frame(height: height + 3)
        .accessibilityHidden(true)
    }
}
