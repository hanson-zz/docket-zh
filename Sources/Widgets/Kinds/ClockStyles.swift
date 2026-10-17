import SwiftUI

/// The clock's other faces: a full analogue dial, flip cards, folding flip
/// cards, and a dot matrix. Each is the same time from the same tick, only drawn differently.
struct ClockStyleReadout: View {
    var style: String
    var now: Date
    var zone: TimeZone
    var vertical: Bool
    /// Show the seconds on the faces that are digits.
    var seconds = true

    private var secondText: String {
        var calendar = Calendar.current
        calendar.timeZone = zone
        return String(format: "%02d", calendar.component(.second, from: now))
    }

    private var parts: (time: String, meridiem: String?) { ClockFormat.compactTime(now, zone: zone) }

    var body: some View {
        WidgetSurface {
            switch style {
            case "analog": analog
            case "flip": flip
            case FoldFlip.clockLayout: fold
            case "digital": digital
            case "ring": ring
            case "words": words
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
                        Text(ClockPanelWeekday.monthDay(now, zone: zone))
                            .font(.system(size: 12))
                            .foregroundStyle(WidgetStyle.secondary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
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
                    FlipCard(text: hours, size: seconds ? 16 : 20)
                    FlipCard(text: minutes, size: seconds ? 16 : 20)
                    if seconds { FlipCard(text: secondText, size: 16) }
                }
            } else {
                HStack(spacing: seconds ? 4 : 5) {
                    FlipCard(text: hours, size: seconds ? 22 : 26)
                    FlipCard(text: minutes, size: seconds ? 22 : 26)
                    if seconds { FlipCard(text: secondText, size: 22) }
                    if let meridiem = parts.meridiem {
                        Text(meridiem)
                            .font(WidgetStyle.label(10))
                            .foregroundStyle(WidgetStyle.secondary)
                    }
                }
            }
        }
    }

    // MARK: Folding flip

    /// 每个数字一张会折的翻页卡片：时、分（和秒）各一对，数字变时上半张
    /// 往下折、下半张落下来。横排一行，侧边栏竖排三行。
    private var fold: some View {
        let digits = parts.time.split(separator: ":").map(String.init)
        let hours = digits.first ?? "--"
        let minutes = digits.count > 1 ? digits[1] : "--"
        // 12 小时制的“9:05”补成两位，卡片数不跟着时间变。
        let paddedHours = hours.count == 1 ? "0" + hours : hours
        return Group {
            if vertical {
                VStack(spacing: 3) {
                    FoldFlipText(text: paddedHours, size: seconds ? 15 : 19, maxWidth: 56)
                    FoldFlipText(text: minutes, size: seconds ? 15 : 19, maxWidth: 56)
                    if seconds { FoldFlipText(text: secondText, size: 15, maxWidth: 56) }
                }
            } else {
                HStack(spacing: 4) {
                    FoldFlipText(text: seconds ? "\(paddedHours):\(minutes):\(secondText)" : "\(paddedHours):\(minutes)",
                                 size: seconds ? 22 : 28, maxWidth: parts.meridiem == nil ? 146 : 120)
                    if let meridiem = parts.meridiem {
                        Text(meridiem)
                            .font(WidgetStyle.label(10))
                            .foregroundStyle(WidgetStyle.secondary)
                    }
                }
            }
        }
    }

    // MARK: Big digits

    /// Heavy figures with the seconds riding small beside them, and the date
    /// underneath.
    private var digital: some View {
        Group {
            if vertical {
                VStack(spacing: 1) {
                    Text(parts.time)
                        .font(.system(size: 20, weight: .heavy, design: .rounded).monospacedDigit())
                        .foregroundStyle(WidgetStyle.primary)
                        .rollingValue(parts.time)
                    if seconds {
                        Text(secondText)
                            .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.orange)
                            .rollingValue(secondText)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            } else {
                VStack(alignment: .center, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(parts.time)
                            .font(.system(size: 30, weight: .heavy, design: .rounded).monospacedDigit())
                            .foregroundStyle(WidgetStyle.primary)
                            .rollingValue(parts.time)
                        if seconds {
                            Text(secondText)
                                .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(.orange)
                                .rollingValue(secondText)
                        }
                        if let meridiem = parts.meridiem {
                            Text(meridiem)
                                .font(WidgetStyle.label(10))
                                .foregroundStyle(WidgetStyle.secondary)
                        }
                    }
                    Text(ClockFormat.date(now, zone: zone))
                        .font(WidgetStyle.note)
                        .foregroundStyle(WidgetStyle.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    // MARK: Seconds ring

    /// The time inside a ring that fills once a minute.
    private var ring: some View {
        let progress = (Double(secondText) ?? 0) / 60
        let diameter: CGFloat = vertical ? 50 : 46
        return Group {
            if vertical {
                SecondsRing(progress: progress, diameter: diameter) {
                    Text(parts.time)
                        .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(WidgetStyle.primary)
                }
            } else {
                HStack(spacing: 10) {
                    SecondsRing(progress: progress, diameter: diameter) {
                        Text(secondText)
                            .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.orange)
                            .rollingValue(secondText)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(parts.time)
                            .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(WidgetStyle.primary)
                            .rollingValue(parts.time)
                        Text(ClockPanelWeekday.monthDay(now, zone: zone) + " " + ClockPanelWeekday.of(now, zone: zone))
                            .font(WidgetStyle.note)
                            .foregroundStyle(WidgetStyle.secondary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                }
            }
        }
    }

    // MARK: Words

    /// "下午" over "四点四十三分".
    private var words: some View {
        var calendar = Calendar.current
        calendar.timeZone = zone
        let c = calendar.dateComponents([.hour, .minute], from: now)
        let said = ChineseTimeText.say(hour: c.hour ?? 0, minute: c.minute ?? 0)
        return VStack(alignment: .center, spacing: 1) {
            Text(said.period + " · " + ClockPanelWeekday.of(now, zone: zone))
                .font(WidgetStyle.caption(vertical ? 9 : 11))
                .foregroundStyle(WidgetStyle.secondary)
            Text(said.time)
                .font(.system(size: vertical ? 13 : 20, weight: .semibold, design: .serif))
                .foregroundStyle(WidgetStyle.primary)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.4), value: said.time)
        }
        .lineLimit(vertical ? 2 : 1)
        .minimumScaleFactor(0.55)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: Pixel

    private var pixel: some View {
        let base = parts.time.count == 4 ? " " + parts.time : parts.time
        let text = seconds && !vertical ? base + ":" + secondText : base
        return Group {
            if vertical {
                PixelText(text: text, dot: 1.9)
            } else {
                HStack(spacing: 6) {
                    PixelText(text: text, dot: seconds ? 2.7 : 3.3)
                    if let meridiem = parts.meridiem {
                        Text(meridiem)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(WidgetStyle.secondary)
                    }
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
                // The hinge sits behind the figures, as a split between the
                // two halves of the card. Drawn over them it struck the
                // digits through.
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.2, style: .continuous)
                        .fill(WidgetStyle.primary.opacity(0.1))
                    Rectangle()
                        .fill(Color.black.opacity(0.22))
                        .frame(height: 1)
                }
            }
            .contentTransition(.numericText())
            .animation(.snappy(duration: 0.3), value: text)
    }
}

/// A ring that fills with the seconds, around whatever it holds.
struct SecondsRing<Content: View>: View {
    var progress: Double
    var diameter: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Circle().stroke(WidgetStyle.primary.opacity(0.1), lineWidth: 3.5)
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                // A jump back to empty at the top of the minute, not a sweep
                // backwards round the whole ring.
                .animation(progress == 0 ? nil : .linear(duration: 0.9), value: progress)
            content()
        }
        .frame(width: diameter, height: diameter)
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

    /// "10月12日", without the weekday the line above already gives.
    static func monthDay(_ date: Date, zone: TimeZone) -> String {
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        style.timeZone = zone
        return date.formatted(style)
    }
}
