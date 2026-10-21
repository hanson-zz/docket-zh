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

    private var lineWidth: CGFloat {
        switch style {
        case .thin: max(1.5, diameter * 0.035)
        case .dotted: max(2, diameter * 0.06)
        default: max(3, diameter * 0.08)
        }
    }

    private var stroke: StrokeStyle {
        style == .dotted
            ? StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [0.1, lineWidth * 1.8])
            : StrokeStyle(lineWidth: lineWidth, lineCap: .round)
    }

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

            VStack(spacing: diameter * 0.04) {
                if style == .numeric {
                    Text(reading.rssi == nil ? "--" : "\(reading.percent)")
                        .font(.system(size: diameter * 0.17, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(WidgetStyle.primary)
                }
                Image(systemName: reading.rssi == nil ? "wifi.slash" : "wifi",
                      variableValue: reading.rssi == nil ? nil : Double(reading.percent) / 100)
                    .font(.system(size: diameter * (style == .numeric ? 0.22 : 0.3), weight: .semibold))
                    .foregroundStyle(reading.rssi == nil ? WidgetStyle.secondary : WidgetStyle.primary)
            }
            .offset(y: -diameter * 0.04)

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
