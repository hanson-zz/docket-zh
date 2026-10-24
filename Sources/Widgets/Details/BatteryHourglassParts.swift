import SwiftUI

/// 电池格沙漏样式（Pro）面板的零件：品牌沙色、今天按小时的沙柱、健康小格。
/// 什么时候用见 `BatteryHourglass.panelHeader`，数据整理在 Core 的
/// `BatteryHourglassPanel`（有测试）。其他电池样式的面板不用这些。
enum BatterySand {
    /// 品牌沙色：深色暖金 #E9B65C，浅色压到图形 3 : 1。
    static func color(_ scheme: ColorScheme) -> Color {
        BatteryHourglassPanel.sand(dark: scheme == .dark).swiftUI
    }

    /// 充电上限里的 Pro 胶囊：浅沙色底、深棕字，浅色深色一样。
    struct ProCapsule: View {
        var body: some View {
            Text(ProFeatures.badgeTitle)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(code: BatteryHourglassPanel.proInk))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(LinearGradient(colors: [Color(code: BatteryHourglassPanel.proFillTop),
                                                                   Color(code: BatteryHourglassPanel.proFillBottom)],
                                                          startPoint: .top, endPoint: .bottom)))
                .fixedSize()
                .help(ProFeatures.help)
                .accessibilityLabel(ProFeatures.label)
        }
    }
}

/// 「今天」：24 根沙柱，一小时一根，高度是那个小时最后一次记下的电量。
/// 充过电的柱顶落一粒沙，现在这一小时描边，还没到的小时只有一粒小点；20% 及以下
/// 没在充电的柱子是报警红（和卡片同一条线）。一根都没记到时不画坐标线，写
/// 「刚开始记录」，不会只剩一条竖线。
struct BatteryHourglassDayChart: View {
    var history: BatteryHistory
    var day: Date
    var now: Date

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
        let samples = history.samples(from: start, to: end)
        let columns = BatteryHourglassPanel.hourColumns(samples: samples, dayStart: start, now: now)
        let empty = BatteryHourglassPanel.isEmpty(columns)
        let summary = BatteryHourglassPanel.summaryText(BatteryHourglassPanel.daySummary(samples: samples))
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("今天")
                    .font(WidgetStyle.label(13))
                    .foregroundStyle(.panelSecondary)
                Spacer(minLength: 0)
                if let summary {
                    Text(summary)
                        .font(WidgetStyle.caption(13))
                        .monospacedDigit()
                        .foregroundStyle(.panelSecondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            ZStack {
                bars(columns, empty: empty)
                if empty {
                    VStack(spacing: 2) {
                        Text("刚开始记录，每 5 分钟落一粒沙")
                            .font(WidgetStyle.label(13))
                        Text("稍后这里会堆出今天每小时的电量")
                            .font(WidgetStyle.caption(13))
                    }
                    .foregroundStyle(.panelSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.bottom, 8)
                }
            }
            .frame(height: 60)
            HStack {
                ForEach([tr("0 时"), tr("6 时"), tr("12 时"), tr("18 时"), tr("24 时")], id: \.self) { label in
                    Text(label)
                    if label != tr("24 时") { Spacer(minLength: 0) }
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(.panelSecondary)
        }
        .padding(10)
        .glassPane(cornerRadius: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("今天每小时的电量"))
        .accessibilityValue(summary ?? tr("刚开始记录，每 5 分钟落一粒沙"))
    }

    /// 一张静止的 Canvas：样本 5 分钟才多一个，不用动画。
    private func bars(_ columns: [BatteryHourglassPanel.HourColumn], empty: Bool) -> some View {
        let dark = scheme == .dark
        let sand = BatteryHourglassPanel.sand(dark: dark)
        let red = dark ? BatteryTheme.warningRed : BatteryHourglassPanel.readableOnLight(BatteryTheme.warningRed)
        let ink: Color = dark ? .white : Color(red: 0.094, green: 0.086, blue: 0.11)
        return Canvas { context, size in
            let slot = size.width / 24
            let base = size.height - 1
            // 柱顶上留出一粒沙的位置。
            let height = size.height - 8
            if !empty {
                for (mark, dashed) in [(CGFloat(0), false), (CGFloat(0.5), true), (CGFloat(1), false)] {
                    var guide = Path()
                    let y = base - height * mark
                    guide.move(to: CGPoint(x: 0, y: y))
                    guide.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(guide, with: .color(ink.opacity(dark ? 0.12 : 0.1)),
                                   style: StrokeStyle(lineWidth: 0.5, dash: dashed ? [3, 3] : []))
                }
            }
            for column in columns {
                let width = max(2, slot * 0.62)
                let x = CGFloat(column.hour) * slot + (slot - width) / 2
                guard column.percent != nil else {
                    let r: CGFloat = 1.3
                    let dot = CGRect(x: x + width / 2 - r, y: base - r * 2, width: r * 2, height: r * 2)
                    context.fill(Path(ellipseIn: dot),
                                 with: .color(ink.opacity(column.isFuture || empty ? 0.28 : 0.14)))
                    continue
                }
                let top = base - height * CGFloat(BatteryHourglassPanel.columnHeight(column))
                let rgb = column.warns ? red : sand
                let rect = CGRect(x: x, y: top, width: width, height: base - top)
                let shape = Path(roundedRect: rect, cornerRadius: min(2.5, width / 2))
                let colors = dark
                    ? [rgb.mixed(with: .white, 0.25).swiftUI, rgb.swiftUI]
                    : [rgb.swiftUI, rgb.mixed(with: .white, 0.2).swiftUI]
                context.fill(shape, with: .linearGradient(Gradient(colors: colors),
                                                          startPoint: CGPoint(x: rect.midX, y: rect.minY),
                                                          endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
                if column.charging {
                    let r: CGFloat = 1.6
                    let grain = CGRect(x: rect.midX - r, y: top - 3.5 - r, width: r * 2, height: r * 2)
                    context.fill(Path(ellipseIn: grain),
                                 with: .color((dark ? sand.mixed(with: .white, 0.35) : sand).swiftUI))
                }
                if column.isCurrent {
                    context.stroke(Path(roundedRect: rect.insetBy(dx: -1.5, dy: -1.5), cornerRadius: 3.5),
                                   with: .color(ink.opacity(0.55)), lineWidth: 0.8)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// 最大容量、循环次数、温度的玻璃小格：左上一个图示（容量是沙色圆环，循环是
/// 沙漏，温度是温度计），旁边 17pt 的数，下面 13pt 的名字。
struct BatteryHourglassHealthChip: View {
    enum Icon {
        case capacity(Int)
        case cycles
        case temperature
    }

    var title: String
    var value: String
    var icon: Icon

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                iconView
                Text(value)
                    .font(WidgetStyle.value(17))
                    .monospacedDigit()
                    .foregroundStyle(WidgetStyle.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.77)
            }
            Text(title)
                .font(WidgetStyle.caption(13))
                .foregroundStyle(.panelSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
        .glassPane(cornerRadius: 12)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var iconView: some View {
        let sand = BatterySand.color(scheme)
        switch icon {
        case .capacity(let percent):
            let tint = BatteryHourglassPanel.capacityWarns(percent) ? Color(hex: "#FF9F0A").panelGraphic : sand
            MetricProgressRing(progress: BatteryHourglassPanel.capacityFraction(percent), tint: tint,
                               track: .panelTrack, diameter: 24, lineWidth: 3.5) { EmptyView() }
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)
        case .cycles:
            well(Image(systemName: "hourglass"), sand: sand)
        case .temperature:
            well(Image(systemName: "thermometer.medium"), sand: sand)
        }
    }

    private func well(_ image: Image, sand: Color) -> some View {
        image
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(sand)
            .frame(width: 24, height: 24)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(sand.opacity(0.16)))
            .accessibilityHidden(true)
    }
}
