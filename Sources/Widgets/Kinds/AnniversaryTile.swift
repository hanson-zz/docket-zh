import SwiftUI

/// 纪念日卡片。单个和多个长得完全不一样：
///
/// - 单个是一张“日子”：左边一页小日历撕页（顶上事件色条写名字，中间大号日，下面
///   月份，农历事件写农历），右边“已经/还有”、大数字和一行小字。日子到了那天，卡片
///   换成事件色的淡底，小熊猫捧场，写“就是今天”。卡片自己的点击开这一个的专属页。
/// - 多个是一条“接下来一年”的时间轴：从今天到一年后，月份刻度，每个纪念日一个
///   事件色的点，最近的那个点大一些。点某个点开它的专属页（`AnniversaryRoute`），
///   点空白处是卡片自己的点击，开时间线。指针停在点上，标题右边换成名字和日期。
///
/// 竖排货架窄，单个是竖着的撕页，多个是最近三个排在一根短轴上。位置怎么算见
/// `Anniversary.axisPoints` 这些 Core 里的纯函数。
struct AnniversaryTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    /// 指针下面是第几个点（多个卡片横排）或第几行（竖排），没有指着时是 nil。
    @State private var hovered: Int?
    @Environment(\.widgetHovered) private var tileHovered
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var events: [AnniversaryEvent] {
        context.isPreview ? AnniversarySamples.events : Anniversary.events(instance.config)
    }

    private var pinned: String? {
        context.isPreview ? nil : Anniversary.pinnedID(instance.config)
    }

    private var isMulti: Bool { instance.config.string("layout", default: "single") == "multi" }
    /// 老的“显示进度圈”开关，现在管单个卡片左边那页撕页画不画。
    private var showsLeaf: Bool { instance.config.bool("showRing", default: true) }

    var body: some View {
        let all = events
        let now = context.now
        let featured = Anniversary.featured(all, pinned: pinned, today: now)
        let celebrating = !isMulti && featured.map(Self.isCelebrating) == true
        return WidgetSurface(fill: celebrating ? featured.map { Self.base($0.event).opacity(0.30) } : nil) {
            Group {
                if all.isEmpty || featured == nil {
                    empty
                } else if context.position.isVertical {
                    if isMulti {
                        columnList(Array(Anniversary.readings(all, today: now).prefix(Anniversary.multiCount)))
                    } else {
                        columnSingle(featured!)
                    }
                } else if isMulti {
                    yearAxis(Anniversary.axisPoints(all, today: now))
                } else {
                    single(featured!)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityText(all, featured: featured))
    }

    private func accessibilityText(_ all: [AnniversaryEvent], featured: AnniversaryReading?) -> String {
        if isMulti {
            let count = Anniversary.axisPoints(all, today: context.now).count
            return tr("纪念日，接下来一年 \(count) 个")
        }
        return featured.map { tr("纪念日，\($0.event.title)\($0.sentence)") } ?? tr("纪念日")
    }

    /// 那一天就是今天：倒数日到了，正数日开始那天，或者正数日的周年。
    static func isCelebrating(_ reading: AnniversaryReading) -> Bool {
        reading.phase == .today || reading.isToday
    }

    // MARK: Empty

    @ViewBuilder
    private var empty: some View {
        PandaEmptyTile(empty: .anniversary, title: tr("添加纪念日"), instance: instance, context: context)
    }

    private func badgeGlyph(size: CGFloat) -> some View {
        Image(systemName: "calendar.badge.clock")
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(WidgetStyle.primary)
    }

    // MARK: Single

    private func single(_ reading: AnniversaryReading) -> some View {
        let tint = Self.tint(reading.event)
        return Group {
            if Self.isCelebrating(reading) {
                HStack(spacing: 8) {
                    panda(height: 50)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(reading.event.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(tint)
                            .lineLimit(1)
                        Text(reading.anniversaryNote.map { tr("\($0)啦") } ?? tr("就是今天"))
                            .font(.system(size: 19, weight: .bold))
                            .foregroundStyle(WidgetStyle.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("点开生成分享图")
                            .font(WidgetStyle.caption(13))
                            .foregroundStyle(WidgetStyle.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    Spacer(minLength: 0)
                }
            } else {
                HStack(spacing: 9) {
                    if showsLeaf { flippingLeaf(reading, width: 40, height: 48) }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: showsLeaf ? reading.word : "\(reading.event.title) · \(reading.word)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(showsLeaf ? WidgetStyle.secondary : tint)
                            .lineLimit(1)
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(reading.days.formatted())
                                .font(WidgetStyle.value(22))
                                .foregroundStyle(WidgetStyle.primary)
                                .monospacedDigit()
                                .rollingValue(reading.days)
                            Text("天")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(WidgetStyle.secondary)
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        Text(Anniversary.tileLine(reading, today: context.now))
                            .font(WidgetStyle.caption(13))
                            .foregroundStyle(WidgetStyle.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// 小熊猫捧场。图读不到时退回一个礼物符号。
    @ViewBuilder
    private func panda(height: CGFloat) -> some View {
        if let image = PandaArt.image("pet-panda-cheer") {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(height: height)
                .accessibilityHidden(true)
        } else {
            Image(systemName: "gift.fill")
                .font(.system(size: height * 0.45, weight: .medium))
                .foregroundStyle(WidgetStyle.primary)
                .frame(width: height, height: height)
        }
    }

    /// 撕页。日子变了（过了零点）旧的一页往上翻走，新的一页露出来；打开“减少动态
    /// 效果”时只是淡入淡出。
    private func flippingLeaf(_ reading: AnniversaryReading, width: CGFloat, height: CGFloat) -> some View {
        let key = "\(reading.event.id)-\(Anniversary.dayKey(reading.kindDate))"
        let tear = AnyTransition.modifier(active: LeafTear(progress: 1), identity: LeafTear(progress: 0))
        let change: AnyTransition = reduceMotion
            ? AnyTransition.opacity
            : AnyTransition.asymmetric(insertion: AnyTransition.opacity, removal: tear)
        return ZStack {
            CalendarLeaf(reading: reading, tint: Self.base(reading.event))
                .id(key)
                .transition(change)
        }
        .frame(width: width, height: height)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .easeIn(duration: 0.55), value: key)
    }

    // MARK: Multi: a year

    /// 横轴两头留的空，免得点被切掉一半。
    private static let axisPad: CGFloat = 6
    /// 一个点能点到的半径（就近，见 `Anniversary.hitZones`）。
    private static let hitRadius: Double = 14

    private func yearAxis(_ points: [AnniversaryAxisPoint]) -> some View {
        var pointed: AnniversaryAxisPoint?
        if tileHovered, !context.isPreview, let index = hovered, points.indices.contains(index) {
            pointed = points[index]
        }
        let lit = pointed
        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text("接下来一年")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(WidgetStyle.primary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Group {
                    if let lit {
                        Text(verbatim: "\(lit.reading.event.title) · \(Self.shortDate(lit))")
                            .foregroundStyle(Self.tint(lit.reading.event))
                    } else {
                        Text(tr("\(points.count) 个"))
                            .foregroundStyle(WidgetStyle.secondary)
                    }
                }
                .font(WidgetStyle.caption(9))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
            .padding(.top, 4)
            GeometryReader { proxy in
                axisBody(points, size: proxy.size, lit: lit?.id)
            }
        }
        .padding(.bottom, 3)
    }

    /// 2026-10-30，农历事件写农历。
    private static func shortDate(_ point: AnniversaryAxisPoint) -> String {
        point.reading.event.lunar ? Anniversary.lunarShort(point.date) : Anniversary.solarText(point.date)
    }

    private func axisBody(_ points: [AnniversaryAxisPoint], size: CGSize, lit: String?) -> some View {
        let width = Double(size.width)
        let pad = Double(Self.axisPad)
        let usable = max(1, width - pad * 2)
        let xs = points.map { pad + $0.fraction * usable }
        // 名字在线上面，天数在线下面，两行一起算宽，一起放或一起不放。最近那个先放。
        let widths: [Double] = points.enumerated().map { index, point in
            max(Self.textWidth(point.reading.event.title, size: index == 0 ? 10 : 8.5),
                Self.textWidth(Self.daysText(point), size: index == 0 ? 10 : 8.5)) + 2
        }
        let labels = Anniversary.placeLabels(centers: xs, widths: widths, total: width, gap: 3)
        let ticks = Anniversary.axisTicks(today: context.now)
        let monthMarks = Self.monthMarks(ticks, today: context.now, pad: pad, usable: usable, total: width)
        let lineY: CGFloat = 16
        let zones = Anniversary.hitZones(centers: xs, radius: Self.hitRadius)

        return ZStack(alignment: .topLeading) {
            // 轴和月份刻度。
            Rectangle()
                .fill(WidgetStyle.primary.opacity(0.22))
                .frame(width: CGFloat(usable), height: 1)
                .offset(x: CGFloat(pad), y: lineY)
            ForEach(Array(ticks.enumerated()), id: \.offset) { _, tick in
                Rectangle()
                    .fill(WidgetStyle.primary.opacity(0.28))
                    .frame(width: 1, height: 4)
                    .offset(x: CGFloat(pad + tick.fraction * usable) - 0.5, y: lineY - 1.5)
            }
            ForEach(Array(monthMarks.enumerated()), id: \.offset) { _, mark in
                Text(mark.text)
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(WidgetStyle.secondary.opacity(0.85))
                    .fixedSize()
                    .frame(width: 30)
                    .offset(x: CGFloat(mark.x) - 15, y: lineY + 15)
            }
            // 今天：线头一个小白点。
            Circle()
                .fill(WidgetStyle.primary.opacity(0.8))
                .frame(width: 4, height: 4)
                .offset(x: CGFloat(pad) - 2, y: lineY - 1.5)
            if points.isEmpty {
                Text("一年内没有要到的纪念日")
                    .font(WidgetStyle.caption(9))
                    .foregroundStyle(WidgetStyle.secondary)
                    .frame(width: size.width)
                    .offset(y: 2)
            }
            // 点，远的先画，最近的压在最上面。
            ForEach(Array(points.enumerated().reversed()), id: \.element.id) { index, point in
                let lead = index == 0
                let isLit = lit == point.id
                let diameter: CGFloat = lead ? 9 : (isLit ? 8 : 6)
                Circle()
                    .fill(Self.base(point.reading.event))
                    .overlay { Circle().strokeBorder(.white.opacity(lead ? 0.9 : 0.5), lineWidth: lead ? 1.5 : 0.5) }
                    .frame(width: diameter, height: diameter)
                    .offset(x: CGFloat(xs[index]) - diameter / 2, y: lineY + 0.5 - diameter / 2)
                    .animation(.smooth(duration: 0.15), value: isLit)
            }
            // 标签。
            ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                if let center = labels[index] {
                    let lead = index == 0
                    let tint = Self.tint(point.reading.event)
                    let w = CGFloat(widths[index])
                    Text(point.reading.event.title)
                        .font(.system(size: lead ? 10 : 8.5, weight: .semibold))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .frame(width: w)
                        .offset(x: CGFloat(center) - w / 2, y: lineY - (lead ? 14 : 12))
                    Text(Self.daysText(point))
                        .font(.system(size: lead ? 10 : 8.5, weight: lead ? .bold : .medium))
                        .foregroundStyle(lead ? WidgetStyle.primary : WidgetStyle.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .frame(width: w)
                        .offset(x: CGFloat(center) - w / 2, y: lineY + 3)
                }
            }
            // 每个点一段能点的地方，就近分；段外面是空白，交给卡片自己的点击开时间线。
            if !context.isPreview {
                ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                    let zone = zones[index]
                    let w = CGFloat(zone.upperBound - zone.lowerBound)
                    if w > 0.5 {
                        Button {
                            AnniversaryRoute.shared.open(point.reading.event.id, in: instance.id)
                        } label: {
                            Color.clear
                                .frame(width: w, height: size.height)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .offset(x: CGFloat(zone.lowerBound))
                        .accessibilityLabel(tr("打开「\(point.reading.event.title)」，\(Self.daysText(point))"))
                    }
                }
                PointerFraction { fraction in
                    let index = fraction.flatMap {
                        Anniversary.nearestPoint(to: Double($0.x) * width, centers: xs, radius: Self.hitRadius)
                    }
                    if index != hovered { hovered = index }
                }
                .frame(width: size.width, height: size.height)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// 12 天，今天的写“今天”。
    private static func daysText(_ point: AnniversaryAxisPoint) -> String {
        point.daysLeft == 0 ? tr("今天") : tr("\(point.daysLeft) 天")
    }

    /// 月份字：今天所在的月写在线头，之后每季度的第一个月（1、4、7、10 月）写在刻度下，
    /// 挤在一起的去掉。
    private static func monthMarks(_ ticks: [AnniversaryAxisTick], today: Date, pad: Double, usable: Double,
                                   total: Double) -> [(text: String, x: Double)] {
        let month = Anniversary.calendar.component(.month, from: today)
        var marks: [(String, Double)] = [(Anniversary.monthShort(month), pad)]
        for tick in ticks where tick.month % 3 == 1 {
            marks.append((Anniversary.monthShort(tick.month), pad + tick.fraction * usable))
        }
        let placed = Anniversary.placeLabels(centers: marks.map { $0.1 },
                                             widths: marks.map { textWidth($0.0, size: 7) },
                                             total: total, gap: 6)
        var result: [(text: String, x: Double)] = []
        for (mark, center) in zip(marks, placed) {
            if let center { result.append((text: mark.0, x: center)) }
        }
        return result
    }

    /// 估一段字的宽度：汉字一个字号宽，其余大约六成。只用来决定标签放不放得下。
    static func textWidth(_ text: String, size: Double) -> Double {
        text.unicodeScalars.reduce(0) { sum, scalar in
            sum + (scalar.value >= 0x2E80 ? size : size * 0.6)
        }
    }

    // MARK: Column

    /// 竖排的单个：竖着一页撕页，下面是天数。
    private func columnSingle(_ reading: AnniversaryReading) -> some View {
        let tint = Self.tint(reading.event)
        return VStack(spacing: 2) {
            if Self.isCelebrating(reading) {
                panda(height: 42)
                Text(reading.event.title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("就是今天")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WidgetStyle.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                if showsLeaf {
                    flippingLeaf(reading, width: 36, height: 42)
                } else {
                    Text(reading.event.title)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(verbatim: "\(reading.days)")
                        .font(WidgetStyle.value(16))
                        .foregroundStyle(WidgetStyle.primary)
                        .monospacedDigit()
                    Text("天")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(WidgetStyle.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                Text(reading.word)
                    .font(WidgetStyle.caption(8.5))
                    .foregroundStyle(WidgetStyle.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }

    /// 竖排的多个：最近三个挂在一根短轴上，每行是一个按钮，开那一个的专属页。
    private func columnList(_ readings: [AnniversaryReading]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(readings.enumerated()), id: \.element.event.id) { index, reading in
                pickable(reading, index: index) { columnRow(reading, lead: index == 0) }
            }
        }
        .background(alignment: .leading) {
            Rectangle()
                .fill(WidgetStyle.primary.opacity(0.2))
                .frame(width: 1)
                .padding(.vertical, 10)
                .padding(.leading, 3.5)
        }
        .background { tracker(count: readings.count) }
    }

    private func columnRow(_ reading: AnniversaryReading, lead: Bool) -> some View {
        let today = Self.isCelebrating(reading)
        return HStack(spacing: 5) {
            Circle()
                .fill(Self.base(reading.event))
                .overlay { Circle().strokeBorder(.white.opacity(lead ? 0.9 : 0.4), lineWidth: lead ? 1.2 : 0.5) }
                .frame(width: lead ? 8 : 6, height: lead ? 8 : 6)
                .frame(width: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text(reading.event.title)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Self.tint(reading.event))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(verbatim: today ? tr("今天") : "\(reading.days)")
                        .font(.system(size: lead ? 14 : 12, weight: .bold))
                        .monospacedDigit()
                    if !today {
                        Text(reading.phase == .past ? tr("天前") : tr("天"))
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(WidgetStyle.secondary)
                    }
                }
                .foregroundStyle(WidgetStyle.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
    }

    /// 竖排多个的一行：一个按钮，开这一行的专属页，指着时轻轻亮一下。库里不画按钮，
    /// 那里卡片自己的点击是添加小组件。
    @ViewBuilder
    private func pickable<Content: View>(_ reading: AnniversaryReading, index: Int,
                                         @ViewBuilder content: () -> Content) -> some View {
        let lit = tileHovered && hovered == index && !context.isPreview
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

    @ViewBuilder
    private func tracker(count: Int) -> some View {
        if !context.isPreview, count > 1 {
            PointerFraction { point in
                let index = point.map { point -> Int in
                    Int(min(max(point.y, 0), 0.999) * Double(count))
                }
                if index != hovered { hovered = index }
            }
        }
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

/// 一页小日历：顶上事件色条写名字，中间大号的日，下面月份。白纸黑字，深色货架上也是
/// 一张白纸，像真的撕页。
private struct CalendarLeaf: View {
    var reading: AnniversaryReading
    var tint: Color

    var body: some View {
        let leaf = Anniversary.leaf(reading)
        GeometryReader { proxy in
            let h = proxy.size.height
            VStack(spacing: 0) {
                Text(reading.event.title)
                    .font(.system(size: h * 0.16, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 2)
                    .frame(maxWidth: .infinity)
                    .frame(height: h * 0.27)
                    .background(tint)
                Spacer(minLength: 0)
                Text(leaf.day)
                    .font(.system(size: h * (leaf.day.count > 2 || reading.event.lunar ? 0.27 : 0.4),
                                  weight: .bold, design: .rounded))
                    .foregroundStyle(Color(white: 0.12))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(leaf.month)
                    .font(.system(size: h * 0.15, weight: .medium))
                    .foregroundStyle(Color(white: 0.42))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.bottom, h * 0.05)
            }
            .frame(width: proxy.size.width, height: h)
            .background(Color(white: 0.97))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
        }
        .accessibilityHidden(true)
    }
}

/// 撕页翻走：绕上沿往后翻，边翻边淡出。
private struct LeafTear: ViewModifier {
    var progress: Double

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(-85 * progress), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.6)
            .opacity(1 - progress)
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
