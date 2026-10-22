import SwiftUI

/// 今日三环的图形：三条同心、约 270° 开口朝下的弧，从外到内喝水、专注、习惯
/// （`TodayRings.order`）。起点在左下，顺时针绕到右下；起点上画小图标（水滴、
/// 计时、勾）。超过 100% 的部分同色加深一档从起点再绕第二圈，端头带一圈投影，
/// 看起来压在第一圈上。不计入的一项只画一条虚线轨道。颜色见 `PerfectDayItem`。
struct TodayRingsGraphic: View {
    var items: [PerfectDayProgress]
    /// 最外圈的外径。
    var diameter: CGFloat
    var line: CGFloat
    var gap: CGFloat
    var icons = true

    var body: some View {
        ZStack {
            ForEach(Array(TodayRings.order.enumerated()), id: \.element) { index, item in
                let centre = diameter - line - CGFloat(index) * 2 * (line + gap)
                TodayRingArc(item: item, progress: items.first { $0.item == item }, line: line, icons: icons)
                    .frame(width: max(1, centre), height: max(1, centre))
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement()
        .accessibilityLabel(accessibility)
    }

    private var accessibility: String {
        TodayRings.order.compactMap { item in
            guard let p = items.first(where: { $0.item == item }), p.mark.takesPart else { return nil }
            return "\(item.title) \(TodayRings.percent(p))%"
        }.joined(separator: tr("、"))
    }
}

/// 一条弧。frame 是弧中线的直径，描边一半在外、一半在内。
struct TodayRingArc: View {
    var item: PerfectDayItem
    var progress: PerfectDayProgress?
    var line: CGFloat
    var icons: Bool

    @Environment(\.colorScheme) private var scheme

    private static var span: CGFloat { CGFloat(TodayRings.sweep / 360) }

    var body: some View {
        let base = Color(hex: item.hex)
        let light = Color(hex: item.lightHex)
        let deep = Color(hex: item.deepHex)
        let takes = progress?.mark.takesPart ?? false
        let laps = TodayRings.laps(progress?.ratio ?? 0)
        let round = StrokeStyle(lineWidth: line, lineCap: .round)
        let sweep = Angle.degrees(TodayRings.sweep)
        return GeometryReader { geo in
            let r = min(geo.size.width, geo.size.height) / 2
            let start = point(r: r, in: geo.size)
            ZStack {
                // 轨道：主色淡淡一层；不计入时是虚线。
                Circle()
                    .trim(from: 0, to: Self.span)
                    .stroke(base.opacity(takes ? (scheme == .dark ? 0.26 : 0.2) : 0.14),
                            style: takes ? round : StrokeStyle(lineWidth: line * 0.55, lineCap: .round,
                                                               dash: [max(1, line * 0.5), max(2, line * 0.9)]))
                    .rotationEffect(.degrees(TodayRings.startAngle))
                if takes, laps.first > 0.004 {
                    Circle()
                        .trim(from: 0, to: Self.span * laps.first)
                        .stroke(AngularGradient(colors: [base, light], center: .center,
                                                startAngle: .zero, endAngle: sweep), style: round)
                        .rotationEffect(.degrees(TodayRings.startAngle))
                }
                if takes, laps.second > 0.004 {
                    Circle()
                        .trim(from: 0, to: Self.span * laps.second)
                        .stroke(AngularGradient(colors: [base, deep], center: .center,
                                                startAngle: .zero, endAngle: sweep), style: round)
                        .rotationEffect(.degrees(TodayRings.startAngle))
                        .shadow(color: .black.opacity(0.3), radius: max(1, line * 0.3))
                }
                // 起点：一个主色圆头，渐变绕回来的颜色不会落在这里。
                if takes {
                    Circle()
                        .fill(base)
                        .frame(width: line, height: line)
                        .position(start)
                }
                if icons {
                    Image(systemName: item.symbol)
                        .font(.system(size: max(4, line * 0.62), weight: .bold))
                        .foregroundStyle(takes ? Color.white : base.opacity(0.7))
                        .position(start)
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// 起点（左下 135°）在 frame 里的位置。
    private func point(r: CGFloat, in size: CGSize) -> CGPoint {
        let a = TodayRings.startAngle * .pi / 180
        return CGPoint(x: size.width / 2 + r * CGFloat(cos(a)), y: size.height / 2 + r * CGFloat(sin(a)))
    }
}

/// 行首的小圆章：主题色底 + 白图标。
struct TodayRingBadge: View {
    var item: PerfectDayItem
    var size: CGFloat
    var dimmed = false

    var body: some View {
        Circle()
            .fill(Color(hex: item.hex).opacity(dimmed ? 0.4 : 1))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: item.symbol)
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

/// 扩展栏上的三环卡片：小卡三环 + 百分比和「还差 N 环」，中卡三环 + 右边三项数字，
/// 竖排三环 + 一行百分比。
struct TodayRingsTileBody: View {
    var items: [PerfectDayProgress]
    var card: TodayRingsCard
    var vertical: Bool

    var body: some View {
        if vertical {
            column
        } else if card == .medium {
            medium
        } else {
            small
        }
    }

    private var graphic: some View {
        TodayRingsGraphic(items: items, diameter: 54, line: 5.5, gap: 1.5)
    }

    private var small: some View {
        HStack(spacing: 10) {
            graphic
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "\(TodayRings.percent(items))%")
                    .font(WidgetStyle.value(22))
                    .foregroundStyle(WidgetStyle.primary)
                    .monospacedDigit()
                Text(TodayRings.cardCaption(items))
                    .font(WidgetStyle.caption(13))
                    .foregroundStyle(WidgetStyle.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var medium: some View {
        HStack(spacing: 10) {
            graphic
            VStack(alignment: .leading, spacing: 1) {
                ForEach(TodayRings.order, id: \.self) { item in
                    if let p = items.first(where: { $0.item == item }) { row(p) }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func row(_ p: PerfectDayProgress) -> some View {
        let figure = TodayRings.figure(p)
        let takes = p.mark.takesPart
        return HStack(spacing: 5) {
            TodayRingBadge(item: p.item, size: 14, dimmed: !takes)
            Text(p.item.title)
                .font(WidgetStyle.label(13))
                .foregroundStyle(takes ? WidgetStyle.primary : WidgetStyle.secondary)
            if takes {
                Text(verbatim: "\(TodayRings.percent(p))%")
                    .font(WidgetStyle.caption(13))
                    .foregroundStyle(WidgetStyle.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 4)
            if !figure.value.isEmpty {
                Text(figure.value)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.panelText(Color(hex: p.item.hex)))
                    .monospacedDigit()
            }
            Text(figure.unit)
                .font(WidgetStyle.caption(13))
                .foregroundStyle(WidgetStyle.secondary)
                .monospacedDigit()
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .frame(height: 17)
        .accessibilityElement(children: .combine)
    }

    private var column: some View {
        VStack(spacing: 4) {
            graphic
            Text(verbatim: "\(TodayRings.percent(items))%")
                .font(WidgetStyle.label(13))
                .foregroundStyle(WidgetStyle.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .combine)
    }
}
