import SwiftUI

/// The clock's other faces: a full analogue dial, flip cards, and a dot
/// matrix. Each is the same time from the same tick, only drawn differently.
struct ClockStyleReadout: View {
    var style: String
    var now: Date
    var zone: TimeZone
    var vertical: Bool

    private var parts: (time: String, meridiem: String?) { ClockFormat.compactTime(now, zone: zone) }

    var body: some View {
        WidgetSurface {
            switch style {
            case "analog": analog
            case "flip": flip
            default: pixel
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ClockFormat.time(now, zone: zone))
    }

    // MARK: Analogue

    private var analog: some View {
        Group {
            if vertical {
                VStack(spacing: 3) {
                    DialFace(now: now, zone: zone, diameter: 50)
                    Text(ClockFormat.date(now, zone: zone))
                        .font(WidgetStyle.caption(9))
                        .foregroundStyle(WidgetStyle.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            } else {
                HStack(spacing: 10) {
                    DialFace(now: now, zone: zone, diameter: 46)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ClockPanelWeekday.of(now, zone: zone))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(WidgetStyle.primary)
                        Text(ClockFormat.date(now, zone: zone))
                            .font(.system(size: 12))
                            .foregroundStyle(WidgetStyle.secondary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: Flip

    private var flip: some View {
        let digits = parts.time.split(separator: ":").map(String.init)
        let hours = digits.first ?? "--"
        let minutes = digits.count > 1 ? digits[1] : "--"
        return Group {
            if vertical {
                VStack(spacing: 3) {
                    FlipCard(text: hours, size: 20)
                    FlipCard(text: minutes, size: 20)
                }
            } else {
                HStack(spacing: 5) {
                    FlipCard(text: hours, size: 26)
                    FlipCard(text: minutes, size: 26)
                    if let meridiem = parts.meridiem {
                        Text(meridiem)
                            .font(WidgetStyle.label(10))
                            .foregroundStyle(WidgetStyle.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: Pixel

    private var pixel: some View {
        let text = parts.time.count == 4 ? " " + parts.time : parts.time
        return Group {
            if vertical {
                PixelText(text: text, dot: 1.9)
            } else {
                HStack(spacing: 6) {
                    PixelText(text: text, dot: 3.3)
                    if let meridiem = parts.meridiem {
                        Text(meridiem)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(WidgetStyle.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

/// A dial with all twelve hour marks and a second hand.
struct DialFace: View {
    var now: Date
    var zone: TimeZone
    var diameter: CGFloat

    private var angles: (hour: Double, minute: Double, second: Double) {
        var calendar = Calendar.current
        calendar.timeZone = zone
        let c = calendar.dateComponents([.hour, .minute, .second], from: now)
        let second = Double(c.second ?? 0)
        let minute = Double(c.minute ?? 0) + second / 60
        let hour = Double((c.hour ?? 0) % 12) + minute / 60
        return (hour / 12 * 360, minute / 60 * 360, second / 60 * 360)
    }

    var body: some View {
        let a = angles
        ZStack {
            Circle().fill(WidgetStyle.primary.opacity(0.06))
            Circle().strokeBorder(WidgetStyle.secondary.opacity(0.45), lineWidth: 1)
            ForEach(0..<12, id: \.self) { mark in
                Capsule()
                    .fill(WidgetStyle.secondary.opacity(mark % 3 == 0 ? 0.8 : 0.4))
                    .frame(width: mark % 3 == 0 ? 1.6 : 1, height: diameter * (mark % 3 == 0 ? 0.1 : 0.07))
                    .offset(y: -diameter * 0.4)
                    .rotationEffect(.degrees(Double(mark) * 30))
            }
            hand(length: diameter * 0.24, width: 2.4, degrees: a.hour, color: WidgetStyle.primary)
            hand(length: diameter * 0.35, width: 1.6, degrees: a.minute, color: WidgetStyle.primary)
            hand(length: diameter * 0.38, width: 0.8, degrees: a.second, color: .orange)
            Circle().fill(Color.orange).frame(width: 3, height: 3)
        }
        .frame(width: diameter, height: diameter)
    }

    private func hand(length: CGFloat, width: CGFloat, degrees: Double, color: Color) -> some View {
        Capsule()
            .fill(color)
            .frame(width: width, height: length)
            .offset(y: -length / 2)
            .rotationEffect(.degrees(degrees))
    }
}

/// Two digits on a split card, the way a flip clock shows them.
struct FlipCard: View {
    var text: String
    var size: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(WidgetStyle.primary)
            .padding(.horizontal, size * 0.18)
            .frame(height: size * 1.32)
            .background {
                RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                    .fill(WidgetStyle.primary.opacity(0.1))
            }
            .overlay {
                // The hinge across the middle.
                Rectangle()
                    .fill(Color.black.opacity(0.28))
                    .frame(height: 1)
            }
            .contentTransition(.numericText())
            .animation(.snappy(duration: 0.3), value: text)
    }
}

/// A string drawn in `PixelFont` dots.
struct PixelText: View {
    var text: String
    var dot: CGFloat

    var body: some View {
        let grid = PixelFont.render(text)
        let columns = grid.first?.count ?? 0
        Canvas { context, _ in
            for (row, line) in grid.enumerated() {
                for (column, lit) in line.enumerated() {
                    let rect = CGRect(x: CGFloat(column) * dot, y: CGFloat(row) * dot,
                                      width: dot * 0.82, height: dot * 0.82)
                    context.fill(Path(roundedRect: rect, cornerRadius: dot * 0.2),
                                 with: .color(lit ? WidgetStyle.primary : WidgetStyle.primary.opacity(0.07)))
                }
            }
        }
        .frame(width: CGFloat(columns) * dot, height: CGFloat(PixelFont.height) * dot)
    }
}

/// "星期一", for the analogue face's caption.
enum ClockPanelWeekday {
    static func of(_ date: Date, zone: TimeZone) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.wide)
        style.timeZone = zone
        return date.formatted(style)
    }
}
