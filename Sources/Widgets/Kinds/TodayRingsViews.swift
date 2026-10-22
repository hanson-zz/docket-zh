import SwiftUI

/// 今日三环的图形：三条同心、约 270° 开口朝下的弧，从外到内喝水、专注、习惯
/// （`TodayRings.order`）。起点在左下，顺时针绕到右下；起点上画小图标（水滴、
/// 计时、勾；扩展栏卡片 icons 为 false，不画）。超过 100% 的部分同色加深一档从起点再绕第二圈，端头带一圈投影，
/// 看起来压在第一圈上。不计入的一项只画一条虚线轨道。颜色见 `PerfectDayItem`。
struct TodayRingsGraphic: View {
    var items: [PerfectDayProgress]
    /// 最外圈的外径。
    var diameter: CGFloat
    var line: CGFloat
    var gap: CGFloat
    var icons = true
    /// 扩展栏卡片：轨道底色深一点，小尺寸下三条环也看得出整圈。
    var strongTrack = false

    var body: some View {
        ZStack {
            ForEach(Array(TodayRings.order.enumerated()), id: \.element) { index, item in
                let centre = diameter - line - CGFloat(index) * 2 * (line + gap)
                TodayRingArc(item: item, progress: items.first { $0.item == item }, line: line, icons: icons,
                             strongTrack: strongTrack)
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
    var strongTrack = false

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
                    .stroke(base.opacity(takes ? trackOpacity : 0.14),
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

    private var trackOpacity: Double {
        if strongTrack { return scheme == .dark ? 0.34 : 0.26 }
        return scheme == .dark ? 0.26 : 0.2
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

/// 三环中心：没全满时是总百分比（13pt，最多 99%），全满时是那一档的小竹叶。
/// 百分比按中心空圆的宽度挑最宽放得下的字宽，再放不下就只写数字，不缩到 13pt 以下。
struct TodayRingsCentre: View {
    var items: [PerfectDayProgress]
    /// 最内环里空出的圆的直径。
    var hole: CGFloat

    var body: some View {
        if let percent = TodayRings.centrePercent(items) {
            ViewThatFits(in: .horizontal) {
                figure("\(percent)%", width: .standard)
                figure("\(percent)%", width: .condensed)
                figure("\(percent)%", width: .compressed)
                figure("\(percent)", width: .compressed)
            }
            .frame(width: max(1, hole - 2))
        } else {
            LeafGlyph(tier: PerfectDay.record(items, key: "").tier, size: max(12, hole - 4))
        }
    }

    private func figure(_ text: String, width: Font.Width) -> some View {
        Text(verbatim: text)
            .font(.system(size: 13, weight: .bold).width(width))
            .foregroundStyle(WidgetStyle.primary)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
    }
}

/// 扩展栏上的三环卡片，内容高度 58：小卡只有三环（中心百分比或竹叶），
/// 中卡左边三环、右边三行「喝水 5/8 杯」，竖排三环。卡片上不画起点小图标，
/// 面板里的大三环才画。
struct TodayRingsTileBody: View {
    var items: [PerfectDayProgress]
    var card: TodayRingsCard
    var vertical: Bool

    var body: some View {
        if vertical {
            rings(diameter: CGFloat(TodayRings.columnDiameter))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if card == .medium {
            medium
        } else {
            rings(diameter: CGFloat(TodayRings.cardDiameter))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func rings(diameter: CGFloat) -> some View {
        let line = CGFloat(TodayRings.cardLine)
        let gap = CGFloat(TodayRings.cardGap)
        let hole = CGFloat(TodayRings.hole(diameter: Double(diameter), line: Double(line), gap: Double(gap)))
        return ZStack {
            TodayRingsGraphic(items: items, diameter: diameter, line: line, gap: gap,
                              icons: false, strongTrack: true)
            TodayRingsCentre(items: items, hole: hole)
                .accessibilityHidden(true)
        }
        .frame(width: diameter, height: diameter)
    }

    private var medium: some View {
        HStack(spacing: 12) {
            rings(diameter: CGFloat(TodayRings.cardDiameter))
            VStack(alignment: .leading, spacing: 2) {
                ForEach(TodayRings.order, id: \.self) { item in
                    if let p = items.first(where: { $0.item == item }) { row(p) }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func row(_ p: PerfectDayProgress) -> some View {
        let takes = p.mark.takesPart
        return HStack(spacing: 6) {
            Circle()
                .fill(Color(hex: p.item.hex).opacity(takes ? 1 : 0.4))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(TodayRings.cardLine(p))
                .font(WidgetStyle.label(13))
                .foregroundStyle(takes ? WidgetStyle.primary : WidgetStyle.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(height: 16)
        .accessibilityElement(children: .combine)
    }
}
