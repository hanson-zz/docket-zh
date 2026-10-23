import AppKit
import SwiftUI

/// Analog face on the left, digital time and date on the right.
///
/// On a side shelf the same parts stack into a 76pt column: face on top, time
/// under it, and no date - there is no room and it is the least useful part.
///
/// The readout and the face are factored out because World Clock is the same
/// tile pointed at a different time zone.
struct ClockTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    /// 样式和选项读自时钟样式注册表 `ClockStyles`（Core/ClockStyle.swift），
    /// 旧的 layout 值在那里映射成新样式加选项。Pro 样式没解锁时画成翻页，
    /// 从别的 Mac 拷来的配置也能看时间。
    private var face: ClockFace {
        ClockStyles.face(instance.config, unlocked: ProAccess.isUnlocked, preview: context.isPreview)
    }

    private var seconds: Bool { instance.config.bool(ClockHands.secondsKey, default: true) }
    private var vertical: Bool { context.position.isVertical }

    var body: some View {
        // The compact tile is the time and nothing else, whatever the style:
        // 88pt has no room for a face or a card.
        if !instance.expanded && !vertical {
            standard(bold: false)
        } else {
            draw(face)
        }
    }

    /// 每种画法的绘制视图。新增时钟样式时在 `ClockFace` 加一个画法，再在这里
    /// 加一个分支；没有 default，漏写编译不过。
    @ViewBuilder
    private func draw(_ face: ClockFace) -> some View {
        switch face {
        case .standard(let bold): standard(bold: bold)
        case .bigDigits(let heavy): readout("digital", heavy: heavy)
        case .analog: readout("analog")
        case .secondsRing: readout("ring")
        case .flip: readout("flip")
        case .foldFlip: readout("fold")
        case .pixel: readout("pixel")
        case .words: readout("words")
        case .bigFlipCards: proFace("minimal")
        case .neon: proFace("neon")
        case .nixie: proFace("nixie")
        case .lcd: proFace("lcd")
        }
    }

    private func readout(_ style: String, heavy: Bool = true) -> some View {
        ClockStyleReadout(style: style, now: context.now, zone: .current,
                          vertical: vertical, seconds: seconds, heavy: heavy)
    }

    private func proFace(_ style: String) -> some View {
        SupporterClockFace(style: style, now: context.now, zone: .current,
                           vertical: vertical, seconds: seconds)
    }

    private func standard(bold: Bool) -> some View {
        ClockReadout(
            now: context.now,
            zone: .current,
            caption: ClockFormat.date(context.now, zone: .current),
            // Compact clock is the time and nothing else.
            compactCaption: nil,
            expanded: instance.expanded,
            vertical: vertical,
            bold: bold,
            // 小表盘秒针读标准样式自己的「表盘秒针」（secondHand，默认开），
            // 不再看数字样式的「显示秒」：老配置里的 seconds=false 曾把它藏掉。
            secondHand: ClockHands.showsSecondHand(instance.config),
            // 和时钟面板大表盘同一个颜色来源（`ClockHands.source`）。
            secondSource: ClockHands.source(instance.config, unlocked: ProAccess.isUnlocked)
        )
    }
}

// MARK: - Shared readout

/// Face + time + caption. Shared by Clock and World Clock.
struct ClockReadout: View {
    var now: Date
    var zone: TimeZone
    var caption: String
    /// Caption for the compact tile; `nil` renders the time alone.
    var compactCaption: String?
    var expanded: Bool
    /// Column layout for a side shelf.
    var vertical: Bool = false
    /// Line under the time in the column, shrunk to fit rather than truncated.
    var columnLabel: String?
    /// Tiny trailing marker on that line - World Clock's "+1" / "−1".
    var columnBadge: String?
    /// 时钟“标准”样式的粗细选了“粗”：时间用更粗的字。
    var bold: Bool = false
    /// 小表盘画秒针。只有时钟「标准」卡片打开；世界时钟不画。
    var secondHand: Bool = false
    /// 秒针颜色来源，见 `ClockHands.source`。
    var secondSource: ClockHands.SecondHandSource = .color(ClockHands.defaultColor)

    var body: some View {
        WidgetSurface {
            if vertical {
                column
            } else if expanded {
                // The face in the badge every tile leads with, so a clock and
                // the tile beside it share one left edge for their pictures.
                HStack(spacing: WidgetStyle.rowSpacing) {
                    TileBadge {
                        AnalogClockFace(now: now, zone: zone, diameter: 26, showsSeconds: secondHand,
                                        secondSource: secondSource)
                    }
                    TileReading(value: ClockFormat.time(now, zone: zone), caption: caption,
                                valueWeight: bold ? .heavy : .semibold)
                    Spacer(minLength: 0)
                }
            } else {
                VStack(spacing: 2) {
                    time
                    if let compactCaption { text(compactCaption) }
                }
            }
        }
    }

    // MARK: Column

    private var column: some View {
        let parts = ClockFormat.compactTime(now, zone: zone)
        return VStack(spacing: 2) {
            AnalogClockFace(now: now, zone: zone, showsSeconds: secondHand, secondSource: secondSource)
            HStack(alignment: .firstTextBaseline, spacing: 1.5) {
                Text(parts.time)
                    .font(.system(size: 15, weight: bold ? .heavy : .bold))
                    .foregroundStyle(WidgetStyle.primary)
                    .monospacedDigit()
                    .rollingValue(parts.time)
                if let meridiem = parts.meridiem {
                    Text(meridiem)
                        .font(WidgetStyle.label(8))
                        .foregroundStyle(WidgetStyle.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            if let columnLabel {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(columnLabel)
                        .font(WidgetStyle.caption(10))
                        .foregroundStyle(WidgetStyle.secondary)
                    if let columnBadge {
                        Text(columnBadge)
                            .font(WidgetStyle.label(8))
                            .foregroundStyle(WidgetStyle.secondary.opacity(0.8))
                            .monospacedDigit()
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }
        }
    }

    private var time: some View {
        Text(ClockFormat.time(now, zone: zone))
            .font(.system(size: 21, weight: bold ? .heavy : .bold))
            .foregroundStyle(WidgetStyle.primary)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    private func text(_ string: String) -> some View {
        Text(string)
            .font(WidgetStyle.caption(13))
            .foregroundStyle(WidgetStyle.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

// MARK: - Formatting

enum ClockFormat {
    /// Locale's own clock - 24h or 12h with a meridiem, whichever the user has.
    static func time(_ date: Date, zone: TimeZone) -> String {
        var style = Date.FormatStyle.dateTime.hour().minute()
        style.timeZone = zone
        return date.formatted(style)
    }

    static func date(_ date: Date, zone: TimeZone) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated)
        style.timeZone = zone
        return date.formatted(style)
    }

    /// The column's time, with a 12-hour locale's meridiem split off so the
    /// figure itself stays big in 56pt of usable width.
    static func compactTime(_ date: Date, zone: TimeZone) -> (time: String, meridiem: String?) {
        var style = Date.FormatStyle.dateTime.hour(.defaultDigits(amPM: .omitted)).minute()
        style.timeZone = zone
        let time = date.formatted(style)
        guard isTwelveHour else { return (time, nil) }
        var calendar = Calendar.current
        calendar.timeZone = zone
        let hour = calendar.component(.hour, from: date)
        return (time, hour < 12 ? meridiemSymbols.am : meridiemSymbols.pm)
    }

    private static var isTwelveHour: Bool {
        switch Locale.current.hourCycle {
        case .oneToTwelve, .zeroToEleven: true
        default: false
        }
    }

    /// Resolved once: the symbols only change with the locale, and a
    /// DateFormatter per frame would be a silly price for two strings.
    private static let meridiemSymbols: (am: String, pm: String) = {
        let formatter = DateFormatter()
        formatter.locale = .current
        return (formatter.amSymbol ?? "AM", formatter.pmSymbol ?? "PM")
    }()
}

// MARK: - Face

/// A drawn clock face: thin rim, quarter ticks, hour and minute hands, and
/// optionally a thin second hand with a centre dot.
///
/// 秒针默认不画：世界时钟卡片和时钟面板城市行也用这个表盘，只有时钟
/// 「标准」卡片打开 `showsSeconds`。卡片的 `now` 每秒刷新一次
/// （`WidgetContext.now`），所以这里不另起计时器。
struct AnalogClockFace: View {
    var now: Date
    var zone: TimeZone
    var diameter: CGFloat = 30
    var showsSeconds: Bool = false
    /// 秒针颜色来源，和时钟面板大表盘同一个（`ClockHands.source`）。
    var secondSource: ClockHands.SecondHandSource = .color(ClockHands.defaultColor)

    @Environment(\.colorScheme) private var scheme

    /// 秒针和徽章那层淡底是同一个颜色，按徽章底调明暗到对比度够（`ClockHands.cardColor`），
    /// 色相不变。
    private var secondColor: Color {
        secondSource.resolved(dark: scheme == .dark, on: .card)
    }

    var body: some View {
        let angles = ClockHands.angles(now, zone: zone)
        ZStack {
            Circle()
                .strokeBorder(WidgetStyle.secondary.opacity(0.45), lineWidth: 1.2)
            ForEach(0..<4, id: \.self) { quarter in
                tick.rotationEffect(.degrees(Double(quarter) * 90))
            }
            hand(length: diameter * 0.26, width: 2.2, degrees: angles.hour)
            hand(length: diameter * 0.37, width: 1.6, degrees: angles.minute)
            if showsSeconds {
                let color = secondColor
                Capsule()
                    .fill(color)
                    .frame(width: ClockHands.secondWidth, height: diameter * ClockHands.secondLength)
                    .offset(y: -diameter * ClockHands.secondLength / 2)
                    .rotationEffect(.degrees(angles.second))
                    // 每秒跳一格，不做补间：59 秒到 0 秒补间会倒着转一圈。
                    .animation(nil, value: angles.second)
                Circle()
                    .fill(color)
                    .frame(width: ClockHands.dotDiameter(diameter), height: ClockHands.dotDiameter(diameter))
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private var tick: some View {
        Capsule()
            .fill(WidgetStyle.secondary.opacity(0.45))
            .frame(width: 1.2, height: diameter * 0.1)
            .offset(y: -diameter * 0.39)
    }

    /// Offsetting by half the length before rotating pivots the hand on the
    /// centre of the face rather than its own middle.
    private func hand(length: CGFloat, width: CGFloat, degrees: Double) -> some View {
        Capsule()
            .fill(WidgetStyle.primary)
            .frame(width: width, height: length)
            .offset(y: -length / 2)
            .rotationEffect(.degrees(degrees))
    }
}

// MARK: - Second hand colour

extension ClockHands.SecondHandSource {
    /// 秒针画在哪：卡片的淡色徽章上，还是面板的玻璃上。
    enum Surface { case card, panel }

    /// 解成这一刻的颜色。跟随系统时取此刻的系统强调色再调可读性，取不到就用系统强调色本身。
    func resolved(dark: Bool, on surface: Surface) -> Color {
        let base: ColorCode
        switch self {
        case .color(let code): base = code
        case .system:
            guard let rgb = NSColor.controlAccentColor.usingColorSpace(.sRGB) else { return .accentColor }
            base = ColorCode(red: Double(rgb.redComponent), green: Double(rgb.greenComponent),
                             blue: Double(rgb.blueComponent))
        }
        switch surface {
        case .card: return Color(code: ClockHands.cardColor(base, dark: dark))
        case .panel: return Color(code: ClockHands.panelColor(base, dark: dark))
        }
    }
}
