import SwiftUI

/// One Wi-Fi reading: nil RSSI means off or not joined.
struct WifiReading: Equatable {
    var rssi: Int?

    var percent: Int { rssi.map(WifiQuality.percent(rssi:)) ?? 0 }
    var bars: Int { rssi.map(WifiQuality.bars(rssi:)) ?? 0 }
    var label: String { rssi.map(WifiQuality.label(rssi:)) ?? tr("未连接") }
}

/// The signal as a three-quarter ring with the Wi-Fi glyph inside and four
/// coloured dots in the gap at its foot, one lit per signal step.
struct WifiRingView: View {
    var style: WifiRingStyle
    var reading: WifiReading
    var diameter: CGFloat

    /// Blue, green, orange, purple: one per step, read left to right.
    static let dotColors: [Color] = [
        Color(red: 0.16, green: 0.52, blue: 1.0),
        Color(red: 0.2, green: 0.78, blue: 0.4),
        Color(red: 1.0, green: 0.62, blue: 0.1),
        Color(red: 0.72, green: 0.38, blue: 0.95),
    ]

    private static let sweep: CGFloat = 0.75
    private static let gradient = AngularGradient(
        colors: [Color(red: 0.42, green: 0.36, blue: 1.0), Color(red: 0.2, green: 0.8, blue: 0.85)],
        center: .center, startAngle: .degrees(0), endAngle: .degrees(270))

    private var lineWidth: CGFloat { max(3, diameter * 0.08) }

    private var stroke: StrokeStyle { StrokeStyle(lineWidth: lineWidth, lineCap: .round) }

    /// 数字款中央的数字：约直径的 0.3，卡片小环里也不小于 13pt。
    private var numberSize: CGFloat { max(13, diameter * 0.3) }

    /// 数字款的图标让位给数字，缩到约直径的 0.16；经典款照旧 0.3。
    private var glyphSize: CGFloat { diameter * (style == .numeric ? 0.16 : 0.3) }

    var body: some View {
        ZStack {
            // 135° puts the gap at the bottom, centred.
            Circle()
                .trim(from: 0, to: Self.sweep)
                .stroke(Color.primary.opacity(0.14), style: stroke)
                .rotationEffect(.degrees(135))
            Circle()
                .trim(from: 0, to: Self.sweep * CGFloat(reading.percent) / 100)
                .stroke(Self.gradient, style: stroke)
                .rotationEffect(.degrees(135))
                .animation(.easeOut(duration: 0.5), value: reading.percent)

            VStack(spacing: style == .numeric ? 0 : diameter * 0.04) {
                if style == .numeric {
                    Text(reading.rssi == nil ? "--" : "\(reading.percent)")
                        .font(.system(size: numberSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(WidgetStyle.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(min(1, 13 / numberSize))
                        // 三位数（100）也收在环里，不顶到环线。
                        .frame(maxWidth: diameter * 0.68)
                }
                Image(systemName: reading.rssi == nil ? "wifi.slash" : "wifi",
                      variableValue: reading.rssi == nil ? nil : Double(reading.percent) / 100)
                    .font(.system(size: glyphSize, weight: .semibold))
                    .foregroundStyle(reading.rssi == nil ? WidgetStyle.secondary : WidgetStyle.primary)
            }
            // 数字款整组往上提一点，图标底边离下面的四个圆点留出空隙。
            .offset(y: -diameter * (style == .numeric ? 0.07 : 0.04))

            HStack(spacing: diameter * 0.05) {
                ForEach(0..<4, id: \.self) { index in
                    Circle()
                        .fill(Self.dotColors[index].opacity(index < reading.bars ? 1 : 0.22))
                        .frame(width: diameter * 0.085, height: diameter * 0.085)
                }
            }
            .offset(y: diameter * 0.36)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Wi-Fi 信号")
        .accessibilityValue(reading.rssi.map { "\(reading.label)，\($0) dBm" } ?? tr("未连接"))
    }
}

/// 网络活动 in a Wi-Fi layout: the ring, and beside it how good the signal
/// is in a word and in dBm. A column has room for the ring alone.
struct WifiSignalTile: View {
    var style: WifiRingStyle
    var context: WidgetContext

    private var reading: WifiReading {
        context.isPreview ? WifiReading(rssi: -52) : WifiReading(rssi: WifiMetrics.shared.rssi)
    }

    var body: some View {
        let reading = reading
        Group {
            if context.position.isVertical {
                WifiRingView(style: style, reading: reading, diameter: 58)
            } else {
                HStack(spacing: 8) {
                    WifiRingView(style: style, reading: reading, diameter: 48)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(reading.label)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(WidgetStyle.primary)
                        Text(reading.rssi.map { "\($0) dBm" } ?? "Wi-Fi")
                            .font(WidgetStyle.caption(13))
                            .monospacedDigit()
                            .foregroundStyle(WidgetStyle.secondary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { if !context.isPreview { WifiMetrics.shared.start() } }
    }
}
