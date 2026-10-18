import SwiftUI

/// 股票、自选股、加密货币行情共用的涨跌颜色。
///
/// 涨是红还是绿由小组件自己的“涨跌颜色”设置决定（`ChangeColors`，默认红涨绿跌），
/// 这里只管红和绿在深色、浅色下各取哪一种，保证对比度。深色里压低饱和度：系统的
/// 信号红绿是扩展栏上最亮的东西，比它们修饰的数字还抢眼。
enum StockInk {
    static func color(_ tone: ChangeTone, scheme: ColorScheme) -> Color {
        switch tone {
        case .red: Color(hex: scheme == .dark ? "#E0858B" : "#C7212B")
        case .green: Color(hex: scheme == .dark ? "#6CC18A" : "#0D7533")
        case .neutral: WidgetStyle.secondary
        }
    }

    /// 一个涨跌幅的颜色。
    static func color(_ percent: Double?, colors: ChangeColors, scheme: ColorScheme) -> Color {
        color(StockBoard.tone(percent, colors: colors), scheme: scheme)
    }

    /// 涨（`rising`）或跌各是什么颜色，给成交量小柱这类只分涨跌的地方。
    static func color(rising: Bool, colors: ChangeColors, scheme: ColorScheme) -> Color {
        color(rising ? 1 : -1, colors: colors, scheme: scheme)
    }

    /// 到价提醒的橙色。
    static let alert = Color(hex: "#F2A33A")
}

/// 报价怎么取、贵金属怎么换算，卡片和面板共用，保证两边说的是同一个数。
@MainActor
enum StockDisplay {
    /// 一只的报价。黄金白银按设置的单位换算；要元/克但还没有汇率时照旧是美元/盎司。
    static func quote(_ symbol: String, preview: Bool, unit: PreciousMetal.DisplayUnit) -> StockQuote? {
        let raw = preview ? StockQuote.preview(symbol) : StockService.shared.quote(symbol)
        guard let raw, PreciousMetal(symbol: symbol) != nil,
              let factor = PreciousMetal.factor(unit, usdToCny: rate(preview: preview))
        else { return raw }
        return raw.scaled(by: factor)
    }

    /// 贵金属显示的单位（`元/克`），别的代码是 nil。
    static func unitLabel(_ symbol: String, preview: Bool, unit: PreciousMetal.DisplayUnit) -> String? {
        guard PreciousMetal(symbol: symbol) != nil else { return nil }
        return PreciousMetal.shownUnit(unit, usdToCny: rate(preview: preview)).title
    }

    /// 要取的代码：有贵金属又要元/克时顺带取汇率。
    static func tracked(_ symbols: [String], unit: PreciousMetal.DisplayUnit) -> [String] {
        PreciousMetal.needsExchangeRate(symbols, unit: unit) ? symbols + [PreciousMetal.exchangeSymbol] : symbols
    }

    private static func rate(preview: Bool) -> Double? {
        (preview ? StockQuote.preview(PreciousMetal.exchangeSymbol)
                 : StockService.shared.quote(PreciousMetal.exchangeSymbol))?.price
    }

    /// 代码旁边的小字：贵金属写单位，其他写中文名。
    static func subtitle(_ symbol: String, quote: StockQuote?, preview: Bool,
                         unit: PreciousMetal.DisplayUnit) -> String {
        unitLabel(symbol, preview: preview, unit: unit)
            ?? StockBoard.displayName(symbol, fallback: quote?.name)
    }
}

/// 当日分时：按交易时段铺满，盘中只画到现在；昨收一条虚线，线在虚线上方就是涨；
/// 有提醒价且离得不远时一条橙色细线；底部贴着成交量小柱，不抢主线。
struct IntradayChart: View {
    var quote: StockQuote?
    var tint: Color
    var alert: Double?
    var showsVolume = true
    var upInk: Color
    var downInk: Color
    var lineWidth: CGFloat = 1.3
    /// 昨收虚线的颜色：卡片上跟着系统，面板是深色底所以用白。
    var guide: Color = .secondary

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            guard let quote, size.width > 0, size.height > 0 else { return }
            let values = quote.history
            let volumeHeight: CGFloat = showsVolume ? max(size.height * 0.2, 3) : 0
            let plotHeight = size.height - volumeHeight - (showsVolume ? 2 : 0)
            guard values.count >= 2, plotHeight > 4,
                  let range = StockBoard.yRange(values: values, previousClose: quote.previousClose, alert: alert)
            else { return }
            let xs = StockBoard.xPositions(timestamps: quote.times, count: values.count,
                                           start: quote.sessionStart, end: quote.sessionEnd)
            let inset = lineWidth / 2
            func y(_ value: Double) -> CGFloat {
                let fraction = StockBoard.yFraction(value, in: range) ?? 0
                return inset + CGFloat(1 - fraction) * (plotHeight - lineWidth)
            }
            let points = zip(xs, values).map { CGPoint(x: CGFloat($0) * size.width, y: y($1)) }
            guard let first = points.first, let last = points.last else { return }

            var area = Path()
            area.move(to: CGPoint(x: first.x, y: plotHeight))
            area.addLines(points)
            area.addLine(to: CGPoint(x: last.x, y: plotHeight))
            area.closeSubpath()
            context.fill(area, with: .linearGradient(
                Gradient(colors: [tint.opacity(0.30), tint.opacity(0)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: plotHeight)))

            if let previous = quote.previousClose, StockBoard.yFraction(previous, in: range) != nil {
                var dash = Path()
                dash.move(to: CGPoint(x: 0, y: y(previous)))
                dash.addLine(to: CGPoint(x: size.width, y: y(previous)))
                context.stroke(dash, with: .color(guide.opacity(0.55)),
                               style: StrokeStyle(lineWidth: 0.7, dash: [2, 2]))
            }

            if let alert, StockBoard.yFraction(alert, in: range) != nil {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y(alert)))
                line.addLine(to: CGPoint(x: size.width, y: y(alert)))
                context.stroke(line, with: .color(StockInk.alert), lineWidth: 0.9)
            }

            var stroke = Path()
            stroke.addLines(points)
            context.stroke(stroke, with: .color(tint),
                           style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            let dot = lineWidth + 1.4
            context.fill(Path(ellipseIn: CGRect(x: last.x - dot, y: last.y - dot, width: dot * 2, height: dot * 2)),
                         with: .color(tint))

            if showsVolume {
                let buckets = max(Int(size.width / 3), 1)
                let bars = StockBoard.volumeBars(volumes: quote.volumes, closes: values,
                                                 positions: xs, buckets: buckets)
                let barWidth = max(size.width / CGFloat(buckets) - 1, 1)
                for bar in bars {
                    let height = max(CGFloat(bar.height) * volumeHeight, 0.8)
                    let rect = CGRect(x: CGFloat(bar.position) * size.width - barWidth / 2,
                                      y: size.height - height, width: barWidth, height: height)
                    context.fill(Path(rect), with: .color((bar.rising ? upInk : downInk).opacity(0.7)))
                }
            }
        }
    }
}

/// 一条细细的迷你走势，自选股每行、加密货币每币用。可选一条虚线基准（昨收、7 天前）。
struct MiniTrend: View {
    var samples: [Double]
    var tint: Color
    var baseline: Double?
    var lineWidth: CGFloat = 1.1
    var guide: Color = .secondary

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            let values = samples.filter(\.isFinite)
            guard values.count >= 2, size.width > 0, size.height > 0,
                  let range = StockBoard.yRange(values: values, previousClose: baseline, alert: nil)
            else { return }
            let inset = lineWidth / 2
            func y(_ value: Double) -> CGFloat {
                inset + CGFloat(1 - (StockBoard.yFraction(value, in: range) ?? 0)) * (size.height - lineWidth)
            }
            if let baseline, StockBoard.yFraction(baseline, in: range) != nil {
                var dash = Path()
                dash.move(to: CGPoint(x: 0, y: y(baseline)))
                dash.addLine(to: CGPoint(x: size.width, y: y(baseline)))
                context.stroke(dash, with: .color(guide.opacity(0.45)),
                               style: StrokeStyle(lineWidth: 0.6, dash: [1.5, 1.5]))
            }
            var path = Path()
            for (index, value) in values.enumerated() {
                let point = CGPoint(x: size.width * CGFloat(index) / CGFloat(values.count - 1), y: y(value))
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(tint),
                           style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
    }
}

/// 涨跌幅色块：实心底、白字，幅度越大底色越深（`StockBoard.chipStrength`）。
struct ChangeChip: View {
    var percent: Double?
    var colors: ChangeColors
    var size: CGFloat = 9
    var minWidth: CGFloat = 0

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let tone = StockBoard.tone(percent, colors: colors)
        let ink = StockInk.color(tone, scheme: .dark)
        Text(StockBoard.percentText(percent))
            .font(.system(size: size, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(tone == .neutral ? WidgetStyle.secondary : Color.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, size * 0.4)
            .padding(.vertical, size * 0.1)
            .frame(minWidth: minWidth)
            .background(
                RoundedRectangle(cornerRadius: size * 0.35, style: .continuous)
                    .fill(tone == .neutral
                          ? Color.primary.opacity(0.1)
                          : ink.opacity(StockBoard.chipStrength(percent) * (scheme == .dark ? 0.85 : 1)))
            )
            .rollingValue(StockBoard.percentText(percent))
    }
}

/// 涨跌比例条：左边“涨”的颜色占 `upShare`，右边“跌”的颜色。
struct BreadthBar: View {
    var breadth: StockBoard.Breadth
    var colors: ChangeColors
    var height: CGFloat = 3

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            let up = StockInk.color(rising: true, colors: colors, scheme: scheme)
            let down = StockInk.color(rising: false, colors: colors, scheme: scheme)
            let share = CGFloat(breadth.upShare)
            HStack(spacing: 1.5) {
                Capsule().fill(up).frame(width: max((geo.size.width - 1.5) * share, 0))
                Capsule().fill(down)
            }
        }
        .frame(height: height)
        .accessibilityLabel(StockBoard.breadthText(breadth))
    }
}

/// 轮播的小圆点：当前的一只亮，点一下换到那一只。
struct RotationDots: View {
    var count: Int
    var index: Int
    var size: CGFloat = 4
    var pick: (Int) -> Void

    var body: some View {
        HStack(spacing: size * 0.8) {
            ForEach(0..<count, id: \.self) { item in
                Button { pick(item) } label: {
                    Circle()
                        .fill(item == index ? Color.primary.opacity(0.85) : Color.primary.opacity(0.25))
                        .frame(width: size, height: size)
                        .padding(size * 0.4)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("第 \(index + 1) 只，共 \(count) 只"))
    }
}
