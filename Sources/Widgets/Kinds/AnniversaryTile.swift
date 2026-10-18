import SwiftUI

/// Days to go, or days since: one date with a big number and a small ring,
/// or two to three dates side by side.
///
/// The single card has no controls: its own click opens the panel on the
/// page of the date it shows. On the multi card each column is a button that
/// opens the panel straight on that date's page (see `AnniversaryRoute`), and
/// lights up a little under the pointer; the card's own click, between the
/// columns, opens the timeline where dates are added, edited and pinned. See
/// `Anniversary` for the counting.
struct AnniversaryTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    /// 指针下面是第几列（多个卡片），没有指着哪一列时是 nil。
    @State private var hoveredColumn: Int?
    @Environment(\.widgetHovered) private var tileHovered

    private var events: [AnniversaryEvent] {
        context.isPreview ? AnniversarySamples.events : Anniversary.events(instance.config)
    }

    private var pinned: String? {
        context.isPreview ? nil : Anniversary.pinnedID(instance.config)
    }

    private var isMulti: Bool { instance.config.string("layout", default: "single") == "multi" }
    private var showsRing: Bool { instance.config.bool("showRing", default: true) }

    var body: some View {
        let all = events
        let now = context.now
        let featured = Anniversary.featured(all, pinned: pinned, today: now)
        let listed = Array(Anniversary.readings(all, today: now).prefix(Anniversary.multiCount))
        return WidgetSurface {
            Group {
                if all.isEmpty || featured == nil {
                    empty
                } else if context.position.isVertical {
                    if isMulti { columnList(listed) } else { columnSingle(featured!) }
                } else if isMulti {
                    multi(listed)
                } else {
                    single(featured!)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(featured.map { tr("纪念日，\($0.event.title)\($0.sentence)") } ?? tr("纪念日"))
    }

    // MARK: Empty

    @ViewBuilder
    private var empty: some View {
        if context.position.isVertical {
            VStack(spacing: 4) {
                TileBadge(size: WidgetStyle.badgeCompact) { badgeGlyph(size: 14) }
                Text("添加纪念日")
                    .font(.system(size: 10))
                    .foregroundStyle(WidgetStyle.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        } else {
            HStack(spacing: WidgetStyle.rowSpacing) {
                TileBadge { badgeGlyph(size: 16) }
                TileReading(value: tr("纪念日"), caption: tr("点按添加纪念日"), valueSize: 15)
                Spacer(minLength: 0)
            }
        }
    }

    private func badgeGlyph(size: CGFloat) -> some View {
        Image(systemName: "calendar.badge.clock")
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(WidgetStyle.primary)
    }

    // MARK: Wide

    /// The name, the number and what it counts, with the ring on the right.
    private func single(_ reading: AnniversaryReading) -> some View {
        let tint = Self.tint(reading.event)
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 3) {
                    Text(reading.event.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                    if reading.isToday {
                        Image(systemName: "sparkles")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                }
                figure(reading, tint: tint, size: 21)
                Text(caption(reading))
                    .font(WidgetStyle.caption(10))
                    .foregroundStyle(WidgetStyle.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
            if showsRing { ring(reading, tint: tint, diameter: 36) }
        }
    }

    /// The big number: days, or years and days counting up, or today.
    @ViewBuilder
    private func figure(_ reading: AnniversaryReading, tint: Color, size: CGFloat) -> some View {
        if reading.phase == .today || (reading.isToday && reading.event.kind == .countdown) {
            Text("就是今天")
                .font(.system(size: size * 0.82, weight: .bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        } else if reading.event.kind == .countup, reading.phase == .past, reading.years > 0 {
            HStack(alignment: .center, spacing: 4) {
                Text("\(reading.years)")
                    .font(WidgetStyle.value(size))
                    .foregroundStyle(tint)
                Rectangle()
                    .fill(tint.opacity(0.45))
                    .frame(width: 1, height: size * 0.72)
                VStack(alignment: .leading, spacing: -2) {
                    Text("年")
                        .font(.system(size: size * 0.4, weight: .semibold))
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text("\(reading.remainder)")
                            .font(.system(size: size * 0.55, weight: .bold))
                        Text("天")
                            .font(.system(size: size * 0.4, weight: .semibold))
                    }
                }
                .foregroundStyle(tint)
            }
            .monospacedDigit()
            .lineLimit(1)
            .help(tr("共 \(reading.days) 天"))
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(reading.days)")
                    .font(WidgetStyle.value(size))
                    .monospacedDigit()
                    .rollingValue(reading.days)
                Text("天")
                    .font(.system(size: size * 0.5, weight: .semibold))
            }
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
    }

    /// 丁未年正月初一 · 还有, or 2022-10-21 · 已经.
    private func caption(_ reading: AnniversaryReading) -> String {
        if let note = reading.anniversaryNote { return tr("\(note) · 就是今天") }
        let date = reading.event.kind == .countup && reading.phase == .past
            ? reading.original : reading.timelineDate
        let text = reading.event.lunar ? Anniversary.lunarText(date) : Anniversary.solarText(date)
        return reading.phase == .today ? text : "\(text) · \(reading.word)"
    }

    private func ring(_ reading: AnniversaryReading, tint: Color, diameter: CGFloat) -> some View {
        let percent = Int((reading.progress * 100).rounded())
        return MetricProgressRing(progress: reading.progress, tint: tint, track: tint.opacity(0.16),
                                  diameter: diameter, lineWidth: 3.5) {
            Text("\(percent)%")
                .font(.system(size: diameter * 0.26, weight: .semibold, design: .rounded))
                .foregroundStyle(WidgetStyle.primary)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
        }
        .help(reading.event.kind == .countup ? tr("距上一个周年已过 \(percent)%") : tr("这一年已过 \(percent)%"))
    }

    /// Up to three columns, nearest first, split by hairlines.
    private func multi(_ readings: [AnniversaryReading]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(readings.enumerated()), id: \.element.event.id) { index, reading in
                if index > 0 {
                    Rectangle()
                        .fill(WidgetStyle.primary.opacity(0.12))
                        .frame(width: 0.5, height: 34)
                }
                pickable(reading, index: index) {
                    compact(reading, nameSize: 10, valueSize: 17, captionSize: 9)
                        .padding(.vertical, 3)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background { tracker(count: readings.count, vertical: false) }
    }

    // MARK: Columns as buttons

    /// One column of the multi card: a button that opens the panel on this
    /// date's page, lit a little while the pointer is over it. Drawn without
    /// the button in the library, where the card's own click adds the widget.
    @ViewBuilder
    private func pickable<Content: View>(_ reading: AnniversaryReading, index: Int,
                                         @ViewBuilder content: () -> Content) -> some View {
        let lit = tileHovered && hoveredColumn == index && !context.isPreview
        let label = content()
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(WidgetStyle.primary.opacity(lit ? 0.09 : 0))
            }
            .contentShape(.rect)
            .animation(.smooth(duration: 0.15), value: lit)
        if context.isPreview {
            label
        } else {
            Button {
                AnniversaryRoute.shared.open(reading.event.id, in: instance.id)
            } label: {
                label
            }
            .buttonStyle(.plain)
            .accessibilityLabel(tr("打开「\(reading.event.title)」"))
        }
    }

    /// Which column the pointer is over, from where it sits across the row
    /// (or down the column on a side shelf).
    @ViewBuilder
    private func tracker(count: Int, vertical: Bool) -> some View {
        if !context.isPreview, count > 1 {
            PointerFraction { point in
                let index = point.map { point -> Int in
                    let along = min(max(vertical ? point.y : point.x, 0), 0.999)
                    return Int(along * Double(count))
                }
                if index != hoveredColumn { hoveredColumn = index }
            }
        }
    }

    /// Name, number, and 还有 天 under it, centred: one multi column, or the
    /// whole of a single side-shelf card.
    private func compact(_ reading: AnniversaryReading, nameSize: CGFloat, valueSize: CGFloat,
                         captionSize: CGFloat) -> some View {
        let tint = Self.tint(reading.event)
        let today = reading.phase == .today || (reading.isToday && reading.event.kind == .countdown)
        return VStack(spacing: 0) {
            Text(reading.event.title)
                .font(.system(size: nameSize, weight: .semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(today ? tr("今天") : "\(reading.days)")
                .font(WidgetStyle.value(valueSize))
                .foregroundStyle(tint)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(today ? tr("就是今天") : (reading.anniversaryNote ?? tr("\(reading.word) 天")))
                .font(WidgetStyle.caption(captionSize))
                .foregroundStyle(WidgetStyle.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 2)
    }

    // MARK: Column

    private func columnSingle(_ reading: AnniversaryReading) -> some View {
        compact(reading, nameSize: 11, valueSize: 22, captionSize: 10)
    }

    /// 56pt across: a name over its number, up to three.
    private func columnList(_ readings: [AnniversaryReading]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(readings.enumerated()), id: \.element.event.id) { index, reading in
                pickable(reading, index: index) { columnRow(reading) }
            }
        }
        .background { tracker(count: readings.count, vertical: true) }
    }

    private func columnRow(_ reading: AnniversaryReading) -> some View {
        let tint = Self.tint(reading.event)
        let today = reading.phase == .today || (reading.isToday && reading.event.kind == .countdown)
        return VStack(alignment: .leading, spacing: 0) {
            Text(reading.event.title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(WidgetStyle.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(today ? tr("今天") : "\(reading.days)")
                    .font(.system(size: 14, weight: .bold))
                    .monospacedDigit()
                if !today {
                    Text(reading.phase == .past ? tr("天前") : tr("天"))
                        .font(.system(size: 9, weight: .semibold))
                }
            }
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
    }

    // MARK: Colour

    /// The event's own colour, or the widget's, pulled a little toward the
    /// label colour the way every tile's accent is.
    static func tint(_ event: AnniversaryEvent) -> Color {
        base(event).mix(with: WidgetStyle.primary, by: 0.15)
    }

    static func base(_ event: AnniversaryEvent) -> Color {
        Color(hex: event.color?.hex ?? WidgetCatalog.accentHex(.anniversary) ?? PaletteColor.pink.hex)
    }
}

/// The writes both the panel and anything else make, from the instance's
/// current list so they can never disagree.
@MainActor
enum AnniversaryLog {
    static func change(_ instance: WidgetInstance, _ edit: ([AnniversaryEvent]) -> [AnniversaryEvent]) {
        WidgetWriter.write(instance) { config in
            Anniversary.store(edit(Anniversary.events(config)), in: &config)
        }
    }

    static func pin(_ id: String?, in instance: WidgetInstance) {
        WidgetWriter.write(instance) { config in Anniversary.pin(id, in: &config) }
    }
}

/// What the library and the screenshots show: a lunar festival counting
/// down, a new year, and a first day at work counting up. Fixed days in the
/// past, so the numbers follow the day being drawn.
enum AnniversarySamples {
    static let events: [AnniversaryEvent] = [
        AnniversaryEvent(id: "s1", title: tr("春节"), day: "20260217", kind: .countdown,
                         yearly: true, lunar: true, color: .green),
        AnniversaryEvent(id: "s2", title: tr("元旦"), day: "20260101", kind: .countdown,
                         yearly: true, color: .blue),
        AnniversaryEvent(id: "s3", title: tr("入职"), day: "20221021", kind: .countup,
                         yearly: true, color: .pink),
        AnniversaryEvent(id: "s4", title: tr("国庆节"), day: "20261001", kind: .countdown, color: .orange),
    ]
}
