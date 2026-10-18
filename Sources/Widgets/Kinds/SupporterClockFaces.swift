import SwiftUI

/// Pro 专属表盘：霓虹、实景（辉光管）、液晶（原简约），以及翻页样式的
/// “大号带时分秒”卡片（原极简，style 传 minimal）。
///
/// Each face is drawn at one fixed design size and scaled as a whole to the
/// space the tile has, then centred. Laying them out with flexible stacks let
/// the parts drift apart or crowd one edge as the tile changed size; a single
/// uniform scale keeps every proportion exactly as designed and the face
/// dead centre in its card, on the bottom shelf and in a side column alike.
struct SupporterClockFace: View {
    var style: String
    var now: Date
    var zone: TimeZone
    var vertical: Bool
    var seconds: Bool

    /// The faces' own card colours: each is a little object with its own
    /// body, so it does not take the shelf's glass.
    static func fill(_ style: String) -> Color {
        switch style {
        case "neon": Color(red: 0.03, green: 0.04, blue: 0.055)
        case "nixie": Color(red: 0.04, green: 0.035, blue: 0.03)
        case "lcd": Color(red: 0.77, green: 0.775, blue: 0.77)
        default: Color(white: 0.14)
        }
    }

    private var t: ClockDigits { ClockDigits(now: now, zone: zone) }

    var body: some View {
        WidgetSurface(fill: Self.fill(style)) {
            FittedFace(design: vertical ? CGSize(width: 58, height: 64) : CGSize(width: 146, height: 46)) {
                switch style {
                case "neon": NeonFace(t: t, vertical: vertical, seconds: seconds)
                case "nixie": NixieFace(t: t, vertical: vertical, seconds: seconds)
                case "lcd": LCDFace(t: t, vertical: vertical, seconds: seconds)
                default: MinimalFlipFace(t: t, vertical: vertical, seconds: seconds)
                }
            }
            .padding(.vertical, vertical ? 6 : 5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ClockFormat.time(now, zone: zone))
    }
}

/// Lays the face out at `design` and scales it uniformly to fit, centred.
struct FittedFace<Content: View>: View {
    var design: CGSize
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geo in
            let scale = max(0.1, min(geo.size.width / design.width, geo.size.height / design.height))
            content()
                .frame(width: design.width, height: design.height)
                .scaleEffect(scale)
                .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// The time split into the two-digit pieces the faces draw.
struct ClockDigits: Equatable {
    var hour: String
    var minute: String
    var second: String
    var meridiem: String?
    var monthDay: String
    var day: String
    var weekday: String

    init(now: Date, zone: TimeZone) {
        var calendar = Calendar.current
        calendar.timeZone = zone
        let c = calendar.dateComponents([.hour, .minute, .second, .month, .day, .weekday], from: now)
        let parts = ClockFormat.compactTime(now, zone: zone)
        let split = parts.time.split(separator: ":").map(String.init)
        // A 12-hour "4:41" keeps its width: the first tube or card is left
        // dark rather than the whole face shifting by one figure.
        let h = split.first ?? "--"
        hour = h.count == 1 ? " " + h : h
        minute = split.count > 1 ? split[1] : "--"
        second = String(format: "%02d", c.second ?? 0)
        meridiem = parts.meridiem
        monthDay = tr("\(c.month ?? 1)月\(c.day ?? 1)日")
        day = String(format: "%02d", c.day ?? 1)
        weekday = [tr("周日"), tr("周一"), tr("周二"), tr("周三"), tr("周四"), tr("周五"), tr("周六")][((c.weekday ?? 1) - 1) % 7]
    }
}

// MARK: - 霓虹

private struct NeonFace: View {
    var t: ClockDigits
    var vertical: Bool
    var seconds: Bool

    private let pink = Color(red: 1, green: 0.29, blue: 0.45)
    private let teal = Color(red: 0.3, green: 0.68, blue: 0.76)
    private let green = Color(red: 0.45, green: 0.8, blue: 0.45)
    private let amber = Color(red: 0.95, green: 0.8, blue: 0.3)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: vertical ? 10 : 9, style: .continuous)
                .strokeBorder(teal, lineWidth: 1.2)
                .glow(teal, 3)
            VStack(spacing: vertical ? 3 : 2) {
                time
                Capsule().fill(teal).frame(height: 1).glow(teal, 2)
                    .padding(.horizontal, vertical ? 2 : 0)
                if vertical {
                    Text(t.weekday)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(amber)
                        .glow(amber, 2)
                } else {
                    HStack(spacing: 0) {
                        Text(t.monthDay).foregroundStyle(green).glow(green, 2)
                        Spacer(minLength: 4)
                        Capsule().fill(teal).frame(width: 1, height: 7)
                        Spacer(minLength: 4)
                        Text(t.weekday).foregroundStyle(amber).glow(amber, 2)
                    }
                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                }
            }
            .padding(.horizontal, vertical ? 6 : 12)
            .padding(.vertical, vertical ? 6 : 4)
        }
    }

    private var time: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(t.hour.trimmingCharacters(in: .whitespaces) + ":" + t.minute)
                .font(.system(size: vertical ? 17 : 24, weight: .heavy, design: .rounded).monospacedDigit())
            if seconds, !vertical {
                Text(t.second)
                    .font(.system(size: 11, weight: .heavy, design: .rounded).monospacedDigit())
                    .opacity(0.85)
            }
        }
        .foregroundStyle(pink)
        .glow(pink, 4)
        .lineLimit(1)
    }
}

// MARK: - 实景（辉光管）

private struct NixieFace: View {
    var t: ClockDigits
    var vertical: Bool
    var seconds: Bool

    var body: some View {
        if vertical {
            VStack(spacing: 3) {
                tubes(t.hour, width: 22, height: 29)
                tubes(t.minute, width: 22, height: 29)
            }
        } else {
            let pairs = seconds ? [t.hour, t.minute, t.second] : [t.hour, t.minute]
            let w: CGFloat = seconds ? 20 : 27
            HStack(spacing: 0) {
                ForEach(pairs.indices, id: \.self) { i in
                    if i > 0 { NixieColon(height: 40).frame(width: seconds ? 6 : 9) }
                    tubes(pairs[i], width: w, height: 42)
                }
            }
        }
    }

    private func tubes(_ pair: String, width: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(pair.enumerated()), id: \.offset) { _, ch in
                NixieTube(digit: ch == " " ? nil : String(ch), width: width, height: height)
            }
        }
    }
}

private struct NixieTube: View {
    var digit: String?
    var width: CGFloat
    var height: CGFloat

    private let orange = Color(red: 1, green: 0.6, blue: 0.16)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: width * 0.42, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.17), Color(white: 0.09)],
                                     startPoint: .leading, endPoint: .trailing))
            // The anode mesh behind the figures.
            Canvas { context, size in
                var y = size.height * 0.16
                while y < size.height * 0.9 {
                    context.fill(Path(CGRect(x: size.width * 0.16, y: y, width: size.width * 0.68, height: 0.5)),
                                 with: .color(.white.opacity(0.07)))
                    y += 2.2
                }
            }
            RoundedRectangle(cornerRadius: width * 0.42, style: .continuous)
                .strokeBorder(Color(white: 0.32), lineWidth: 0.8)
            // A glint down one side of the glass.
            Capsule()
                .fill(.white.opacity(0.12))
                .frame(width: 1.2, height: height * 0.5)
                .offset(x: -width * 0.3, y: -height * 0.08)
            if let digit {
                Text(digit)
                    .font(.system(size: height * 0.66, weight: .light).monospacedDigit())
                    .foregroundStyle(orange)
                    .glow(orange, 2.5)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: digit)
            }
        }
        .frame(width: width, height: height)
    }
}

private struct NixieColon: View {
    var height: CGFloat
    private let orange = Color(red: 1, green: 0.6, blue: 0.16)

    var body: some View {
        VStack(spacing: height * 0.2) {
            Capsule().frame(width: 2.6, height: 4)
            Capsule().frame(width: 2.6, height: 4)
        }
        .foregroundStyle(orange)
        .glow(orange, 2)
        .frame(height: height)
    }
}

// MARK: - 液晶（原简约）

private struct LCDFace: View {
    var t: ClockDigits
    var vertical: Bool
    var seconds: Bool

    private let ink = Color(white: 0.1)
    private let ghost = Color(white: 0.1).opacity(0.07)

    var body: some View {
        if vertical {
            VStack(spacing: 4) {
                pair(t.hour, w: 22, h: 26, gap: 4)
                pair(t.minute, w: 22, h: 26, gap: 4)
            }
        } else {
            HStack(alignment: .center, spacing: 6) {
                HStack(spacing: 4) {
                    pair(t.hour, w: 20, h: 38, gap: 4)
                    VStack(spacing: 10) {
                        Rectangle().frame(width: 3, height: 3)
                        Rectangle().frame(width: 3, height: 3)
                    }
                    .foregroundStyle(ink)
                    pair(t.minute, w: 20, h: 38, gap: 4)
                }
                VStack(alignment: .leading, spacing: 3) {
                    pair(seconds ? t.second : t.day, w: 8, h: 14, gap: 2)
                    Text(seconds ? "\(t.day) \(t.weekday)" : t.weekday)
                        .font(.system(size: 7.5, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(ink)
                        .fixedSize()
                }
            }
        }
    }

    private func pair(_ text: String, w: CGFloat, h: CGFloat, gap: CGFloat) -> some View {
        HStack(spacing: gap) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, ch in
                SevenSegmentDigit(character: ch, on: ink, off: ghost)
                    .frame(width: w, height: h)
            }
        }
    }
}

/// One seven-segment figure, unlit segments showing faintly as on a real
/// liquid-crystal panel.
struct SevenSegmentDigit: View {
    var character: Character
    var on: Color
    var off: Color

    static let segments: [Character: Set<Character>] = [
        "0": ["a", "b", "c", "d", "e", "f"], "1": ["b", "c"], "2": ["a", "b", "g", "e", "d"],
        "3": ["a", "b", "g", "c", "d"], "4": ["f", "g", "b", "c"], "5": ["a", "f", "g", "c", "d"],
        "6": ["a", "f", "g", "e", "d", "c"], "7": ["a", "b", "c"], "8": ["a", "b", "c", "d", "e", "f", "g"],
        "9": ["a", "b", "f", "g", "c", "d"], "-": ["g"],
    ]

    var body: some View {
        Canvas { context, size in
            let lit = Self.segments[character] ?? []
            let w = size.width, h = size.height
            let t = max(1.4, w * 0.2)
            let g = t * 0.18, hh = t / 2
            func horizontal(_ y: CGFloat) -> Path {
                let x0 = hh, x1 = w - hh
                var p = Path()
                p.move(to: CGPoint(x: x0 + g, y: y))
                p.addLine(to: CGPoint(x: x0 + hh + g, y: y - hh))
                p.addLine(to: CGPoint(x: x1 - hh - g, y: y - hh))
                p.addLine(to: CGPoint(x: x1 - g, y: y))
                p.addLine(to: CGPoint(x: x1 - hh - g, y: y + hh))
                p.addLine(to: CGPoint(x: x0 + hh + g, y: y + hh))
                p.closeSubpath()
                return p
            }
            func vertical(_ x: CGFloat, _ y0: CGFloat, _ y1: CGFloat) -> Path {
                var p = Path()
                p.move(to: CGPoint(x: x, y: y0 + g))
                p.addLine(to: CGPoint(x: x + hh, y: y0 + hh + g))
                p.addLine(to: CGPoint(x: x + hh, y: y1 - hh - g))
                p.addLine(to: CGPoint(x: x, y: y1 - g))
                p.addLine(to: CGPoint(x: x - hh, y: y1 - hh - g))
                p.addLine(to: CGPoint(x: x - hh, y: y0 + hh + g))
                p.closeSubpath()
                return p
            }
            let l = hh, r = w - hh, top = hh, bottom = h - hh, mid = h / 2
            let paths: [(Character, Path)] = [
                ("a", horizontal(top)), ("g", horizontal(mid)), ("d", horizontal(bottom)),
                ("f", vertical(l, top, mid)), ("b", vertical(r, top, mid)),
                ("e", vertical(l, mid, bottom)), ("c", vertical(r, mid, bottom)),
            ]
            for (name, path) in paths {
                context.fill(path, with: .color(lit.contains(name) ? on : off))
            }
        }
    }
}

// MARK: - 翻页的大号带时分秒卡片（原极简）

private struct MinimalFlipFace: View {
    var t: ClockDigits
    var vertical: Bool
    var seconds: Bool

    var body: some View {
        if vertical {
            VStack(spacing: 4) {
                cards(t.hour, w: 17, h: 26)
                cards(t.minute, w: 17, h: 26)
            }
        } else {
            let groups: [(String, String)] = seconds
                ? [(t.hour, tr("时")), (t.minute, tr("分")), (t.second, tr("秒"))]
                : [(t.hour, tr("时")), (t.minute, tr("分"))]
            let w: CGFloat = seconds ? 19 : 25
            HStack(spacing: seconds ? 6 : 10) {
                ForEach(groups.indices, id: \.self) { i in
                    VStack(spacing: 2) {
                        cards(groups[i].0, w: w, h: 34)
                        Text(groups[i].1)
                            .font(.system(size: 7, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
            }
        }
    }

    private func cards(_ pair: String, w: CGFloat, h: CGFloat) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(pair.enumerated()), id: \.offset) { _, ch in
                DarkFlipCard(text: ch == " " ? "" : String(ch), width: w, height: h)
            }
        }
    }
}

private struct DarkFlipCard: View {
    var text: String
    var width: CGFloat
    var height: CGFloat

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Rectangle().fill(Color(white: 0.22))
                Rectangle().fill(Color(white: 0.19))
            }
            .clipShape(RoundedRectangle(cornerRadius: width * 0.18, style: .continuous))
            .shadow(color: .black.opacity(0.45), radius: 1.5, y: 1)
            Text(text)
                .font(.system(size: height * 0.72, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.3), value: text)
            // The hinge shows only at the card's edges, as two pins, so the
            // split never strikes through the figure.
            HStack {
                Capsule().fill(Color(white: 0.4)).frame(width: 1.2, height: height * 0.14)
                Spacer()
                Capsule().fill(Color(white: 0.4)).frame(width: 1.2, height: height * 0.14)
            }
            .padding(.horizontal, -0.6)
        }
        .frame(width: width, height: height)
    }
}

// MARK: - Glow

private extension View {
    /// A soft light around lit figures: two blurred copies behind the shape.
    func glow(_ color: Color, _ radius: CGFloat) -> some View {
        shadow(color: color.opacity(0.85), radius: radius * 0.5)
            .shadow(color: color.opacity(0.5), radius: radius)
    }
}
