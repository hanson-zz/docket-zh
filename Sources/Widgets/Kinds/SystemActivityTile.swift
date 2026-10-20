import SwiftUI

/// CPU / memory / disk, as numbers, segments (竖条), bars or liquid.
///
/// The card itself belongs to the shelf: a click opens the detail panel, which
/// draws every configured metric at a size that can hold a number. Which
/// metrics those are is `metrics` in the widget's own config, picked per metric
/// in Dock Settings, so it survives a relaunch and follows the widget between
/// profiles.
struct SystemActivityTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    @Environment(\.widgetTint) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        WidgetSurface {
            Group {
                if context.position.isVertical { vertical } else { horizontal }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // The sampler is shared; nobody stops it because a single tile went
        // away. ponytail: start-only, add refcounting if idle cost ever shows.
        .onAppear { if !context.isPreview { SystemMetrics.shared.start() } }
    }

    private var layout: String { instance.config.string("layout", default: "numbers") }

    /// Asks whether a chart applies here as well as whether it is wanted.
    ///
    /// Switching to rings or bars did not clear the stored value, so a widget
    /// could sit on chart true while showing bars and produce a graph nobody
    /// asked for the moment it went back to numbers. Reading the rule rather
    /// than rewriting the config on every layout change means a stale value is
    /// simply inert, and the setting is remembered if the layout comes back.
    private var showsChart: Bool {
        WidgetCatalog.applies("chart", to: instance.config, kind: .system)
            && instance.config.bool("chart", default: false)
    }

    @ViewBuilder
    private var horizontal: some View {
        switch layout {
        case ShapeMeters.systemSegmentsLayout: segmentsRow
        case "bars": bars
        case LiquidMotion.layout: liquid(diameter: 42, size: 12)
        default: numbers
        }
    }

    @ViewBuilder
    private var vertical: some View {
        switch layout {
        case ShapeMeters.systemSegmentsLayout: verticalSegments
        case "bars": verticalBars
        case LiquidMotion.layout: verticalLiquid
        default: verticalNumbers
        }
    }

    // MARK: Wide layouts

    private var numbers: some View {
        HStack(spacing: 0) {
            ForEach(metrics, id: \.self) { metric in
                VStack(spacing: 3) {
                    // The shelf's value and caption styles, so these figures
                    // sit level with every other tile's reading.
                    reading(metric, size: 19)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(tint(metric))
                            .frame(width: 6, height: 6)
                        Text(metric.label)
                            .font(.system(size: 12))
                            .foregroundStyle(WidgetStyle.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // The number says where the machine is; the graph says where
                // it is heading. Low opacity so the figure still leads.
                // Opt-in. A short strip along the floor, inset so the card's
                // rounded corners do not slice its ends off.
                .background(alignment: .bottom) {
                    if showsChart {
                        graph(metric)
                            .frame(height: 9)
                            .padding(.horizontal, 3)
                            .padding(.bottom, 4)
                    }
                }
            }
        }
        .lineLimit(1)
    }

    /// 竖条（存的值仍是 rings）：每个读数一根一格一格亮起来的竖条，旁边是
    /// 大数字和名字。圆只留给圆环仪表，摆在一排一眼就分得开。
    private var segmentsRow: some View {
        HStack(spacing: 0) {
            ForEach(metrics, id: \.self) { metric in
                HStack(spacing: 6) {
                    segmentMeter(metric, width: 7)
                        .frame(height: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        reading(metric, size: 18)
                        Text(metric.label)
                            .font(WidgetStyle.note)
                            .foregroundStyle(WidgetStyle.secondary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(metric.label)
                .accessibilityValue(tr("百分之 \(Int((value(metric) * 100).rounded()))"))
            }
        }
    }

    /// 八格竖条，从下往上亮，亮的用读数的颜色，没亮的是淡淡的底。
    private func segmentMeter(_ metric: Metric, width: CGFloat) -> some View {
        let count = ShapeMeters.segments
        let lit = ShapeMeters.litSegments(value(metric), segments: count)
        return GeometryReader { geo in
            let gap: CGFloat = 1.5
            let cell = max(1, (geo.size.height - gap * CGFloat(count - 1)) / CGFloat(count))
            VStack(spacing: gap) {
                ForEach((0..<count).reversed(), id: \.self) { index in
                    RoundedRectangle(cornerRadius: min(2, cell / 2), style: .continuous)
                        .fill(index < lit ? tint(metric) : Color.primary.opacity(0.13))
                        .frame(width: width, height: cell)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: width)
        .animation(reduceMotion || context.isPreview ? nil : .easeOut(duration: 0.25), value: lit)
    }

    private var bars: some View {
        VStack(spacing: 6) {
            ForEach(metrics, id: \.self) { metric in
                HStack(spacing: 8) {
                    Text(metric.label)
                        .font(WidgetStyle.note)
                        .foregroundStyle(WidgetStyle.secondary)
                        .frame(width: 44, alignment: .leading)
                    GeometryReader { geo in
                        let width = geo.size.width * min(max(value(metric), 0), 1)
                        ZStack(alignment: .leading) {
                            Capsule().fill(tint(metric).opacity(0.18))
                            Capsule().fill(tint(metric)).frame(width: width)
                        }
                    }
                    .frame(height: 6)
                    reading(metric, size: 11)
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
        .lineLimit(1)
    }

    // MARK: 液态

    /// 每个读数一个小水杯：水位是占用率，占用越高水波越急，过了 85% 变红。
    private func liquidCup(_ metric: Metric, diameter: CGFloat, size: CGFloat) -> some View {
        let load = value(metric)
        // 颜色面板里选过颜色时水杯用选的颜色，过了 85% 照旧变红。
        let chosen = theme?.isChosen == true ? theme?.main(dark: scheme == .dark) : nil
        // 超阈值提醒正在响时也变红。
        let alerting = tint(metric) != metric.color
        let cupTint = LiquidMotion.isHot(load) || alerting ? Color.red : (chosen ?? metric.color)
        return ZStack {
            LiquidWater(level: load, tint: cupTint, shape: .circle,
                        visible: !context.isPreview && ShelfVisibility.shared.cardsOnScreen,
                        speed: LiquidMotion.busySpeed(load))
            reading(metric, size: size)
                .minimumScaleFactor(0.6)
                .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
                .padding(.horizontal, 3)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.label)
        .accessibilityValue(tr("百分之 \(Int((load * 100).rounded()))"))
    }

    private func liquid(diameter: CGFloat, size: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(metrics, id: \.self) { metric in
                liquidCup(metric, diameter: diameter, size: size)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var verticalLiquid: some View {
        VStack(spacing: 0) {
            ForEach(metrics, id: \.self) { metric in
                VStack(spacing: 2) {
                    liquidCup(metric, diameter: 36, size: 11)
                    Text(metric.short)
                        .font(WidgetStyle.label(9))
                        .foregroundStyle(WidgetStyle.secondary)
                }
                .frame(height: 54)
            }
        }
        .lineLimit(1)
        .padding(.vertical, 4)
    }

    // MARK: Column layouts
    //
    // Each metric owns a 54pt row - `WidgetCatalog.verticalHeight` hands out
    // `metrics * 54 + 8`, the 8 being this stack's vertical padding.

    private var verticalNumbers: some View {
        VStack(spacing: 0) {
            ForEach(metrics, id: \.self) { metric in
                ZStack(alignment: .top) {
                    // Same switch as the wide layout: one config key, one
                    // answer, so the widget does not change character when
                    // the shelf moves to a side.
                    if showsChart {
                        graph(metric)
                            .frame(height: 26)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                    }
                    VStack(spacing: 0) {
                        reading(metric, size: 18)
                        Text(metric.short)
                            .font(WidgetStyle.label(9))
                            .foregroundStyle(tint(metric))
                    }
                    .padding(.top, 2)
                }
                .frame(height: 54)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.vertical, 4)
    }

    /// 侧边栏里的竖条：左边一根竖条，右边百分比和名字。
    private var verticalSegments: some View {
        VStack(spacing: 0) {
            ForEach(metrics, id: \.self) { metric in
                HStack(spacing: 5) {
                    segmentMeter(metric, width: 6)
                        .frame(height: 38)
                    VStack(alignment: .leading, spacing: 0) {
                        reading(metric, size: 14)
                        Text(metric.short)
                            .font(WidgetStyle.label(9))
                            .foregroundStyle(WidgetStyle.secondary)
                    }
                }
                .frame(height: 54)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(metric.label)
                .accessibilityValue(tr("百分之 \(Int((value(metric) * 100).rounded()))"))
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.vertical, 4)
    }

    private var verticalBars: some View {
        VStack(spacing: 0) {
            ForEach(metrics, id: \.self) { metric in
                VStack(spacing: 5) {
                    HStack(spacing: 4) {
                        Text(metric.short)
                            .font(WidgetStyle.label(10))
                            .foregroundStyle(WidgetStyle.secondary)
                        Spacer(minLength: 0)
                        reading(metric, size: 12)
                    }
                    bar(metric).frame(height: 6)
                }
                .frame(height: 54)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.vertical, 4)
    }

    // MARK: Graphs

    /// History behind a metric: a filled sparkline, or a bar for disk, which
    /// the sampler keeps no history for (a flat line would say nothing).
    @ViewBuilder
    private func graph(_ metric: Metric) -> some View {
        if metric == .disk {
            bar(metric)
                .frame(height: 5)
                .frame(maxHeight: .infinity, alignment: .bottom)
        } else {
            let series = history(metric)
            // Scale to the range the series actually occupies, not 0...max.
            // A metric sitting at 77% would otherwise fill the whole box and
            // read as a coloured block behind the label rather than a graph.
            // The minimum span keeps a near-flat series looking flat instead
            // of amplifying sampling noise into a mountain range.
            let lo = series.min() ?? 0
            let hi = series.max() ?? 0
            let span = max(hi - lo, 0.08)
            let mid = (hi + lo) / 2
            let floor = mid - span * 0.9
            let peak = mid + span * 0.9
            ZStack {
                Sparkline(values: series, peak: peak, floor: floor, closed: true)
                    .fill(tint(metric).opacity(0.14))
                Sparkline(values: series, peak: peak, floor: floor)
                    .stroke(tint(metric).opacity(0.65),
                            style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
        }
    }

    private func bar(_ metric: Metric) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(tint(metric).opacity(0.18))
                Capsule().fill(tint(metric).opacity(0.7))
                    .frame(width: geo.size.width * min(max(value(metric), 0), 1))
            }
        }
    }

    // MARK: Data

    private var metrics: [Metric] {
        let parsed = instance.config
            .strings("metrics", default: ["cpu", "memory"])
            .compactMap(Metric.init(rawValue:))
        return parsed.isEmpty ? [.cpu, .memory] : parsed
    }

    private func value(_ metric: Metric) -> Double {
        if context.isPreview { return metric.sample }
        let live = SystemMetrics.shared
        switch metric {
        case .cpu: return live.cpu
        case .memory: return live.memory
        case .disk: return live.disk
        // 网络没有百分比，按对数折成 0...1 给条形、竖条和液态用；数字样式写速率。
        case .network: return SystemCardMetrics.networkFraction(NetworkMetrics.shared.download)
        // The Mac's own battery: the other devices belong to the battery
        // widget, which is the one that can show more than one of them.
        case .battery:
            return BatteryMetrics.shared.devices.first { $0.kind == .mac }?.level ?? 0
        }
    }

    /// Most recent last; empty until the sampler has two readings.
    private func history(_ metric: Metric) -> [Double] {
        if context.isPreview { return metric.sampleHistory }
        if metric == .network { return NetworkMetrics.shared.downloadHistory }
        return SystemMetrics.shared.history(for: metric.rawValue)
    }

    /// 读数的颜色。超阈值提醒（Pro）正在响的读数变红，没解锁时不会出现。
    private func tint(_ metric: Metric) -> Color {
        if !context.isPreview, let kind = metric.alertKind, SystemAlerts.shared.firing.contains(kind) {
            return Color(hex: SystemActivityStyle.alertRed)
        }
        return metric.color
    }

    /// 百分比，网络写速率（“2.4M”）。
    @ViewBuilder
    private func reading(_ metric: Metric, size: CGFloat) -> some View {
        if metric == .network {
            let text = context.isPreview ? "2.4M" : SystemReadout.shortRate(NetworkMetrics.shared.download)
            Text(verbatim: text)
                .font(.system(size: size, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(WidgetStyle.primary)
        } else {
            percent(value(metric), size: size)
        }
    }

    @ViewBuilder
    private func percent(_ value: Double, size: CGFloat) -> some View {
        let whole = Int((min(max(value, 0), 1) * 100).rounded())
        HStack(spacing: 0) {
            Text("\(whole)")
                .font(.system(size: size, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(WidgetStyle.primary)
                .rollingValue(whole)
            Text("%")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(WidgetStyle.secondary)
        }
    }

    private enum Metric: String {
        case cpu, memory, network, disk, battery

        var label: String {
            switch self {
            case .cpu: "CPU"
            case .memory: tr("内存")
            case .network: tr("网络")
            case .disk: tr("磁盘")
            case .battery: tr("电池")
            }
        }

        /// The column has 56pt of usable width, so the long label is out.
        var short: String { label }

        var color: Color {
            switch self {
            case .cpu: Color(hex: MetricColor.cpu)
            case .memory: Color(hex: MetricColor.memory)
            case .network: Color(hex: MetricColor.netDownload)
            case .disk: Color(hex: MetricColor.storage)
            case .battery: Color(hex: MetricColor.batteryPresent)
            }
        }

        /// 超阈值提醒对应的读数，电池没有。
        var alertKind: SystemMetricKind? { SystemMetricKind(rawValue: rawValue) }

        /// The library has no sampler behind it, so preview tiles show these.
        var sample: Double {
            switch self {
            case .cpu: 0.24
            case .memory: 0.63
            case .network: 0.42
            case .disk: 0.41
            case .battery: 0.78
            }
        }

        /// Deterministic, plausible-looking history for the library.
        var sampleHistory: [Double] {
            // Neither has a meaningful minute-by-minute history.
            guard self != .disk, self != .battery else { return [] }
            let phase = self == .cpu ? 0.0 : (self == .network ? 3.1 : 1.7)
            return (0..<40).map { i in
                let t = Double(i) / 4 + phase
                return min(max(sample + 0.2 * sin(t) + 0.09 * sin(t * 2.3), 0), 1)
            }
        }
    }
}

/// A round progress gauge with something in the middle. 卡片上只有圆环仪表
/// （以及喝水、Codex 用量这些本来就是圆的进度）画它；电池和系统活动的卡片
/// 不再用圆，详情面板里照旧。
struct MetricProgressRing<Content: View>: View {
    var progress: Double
    var tint: Color
    var track: Color
    var diameter: CGFloat
    var lineWidth: CGFloat
    /// The highest this metric reached recently, marked on the track.
    ///
    /// A ring reading 20% cannot say whether that is a machine settling down
    /// or one about to be busy, and the sampler has kept a minute of history
    /// all along that nothing on the tile ever drew. One tick costs no space
    /// and turns an instant into a direction.
    var peak: Double?
    /// 超过 100% 时不封顶，在满圈上面再画第二圈（最多两圈，见 `RingLap`）。
    /// 只有喝水和圆环仪表打开；其余读数本来就不会超过一圈。
    var laps: Bool
    var content: Content

    init(progress: Double,
         tint: Color,
         track: Color,
         diameter: CGFloat,
         lineWidth: CGFloat,
         peak: Double? = nil,
         laps: Bool = false,
         @ViewBuilder content: () -> Content) {
        self.progress = progress
        self.tint = tint
        self.track = track
        self.diameter = diameter
        self.lineWidth = lineWidth
        self.peak = peak
        self.laps = laps
        self.content = content()
    }

    /// Open at the bottom rather than a closed circle.
    ///
    /// Measured off the reference shelf: its gauges leave about 35° clear at
    /// the foot of the ring, which is what stops a full-value ring from
    /// reading as a plain filled disc and gives the arc a visible start and
    /// end. Stroke is 0.12 of the diameter there, which is what this draws.
    var body: some View {
        let sweep: Double = 320
        let clamped = min(max(progress, 0), 1)
        let lap = laps ? RingLap.split(progress).second : 0
        let fraction = sweep / 360
        // Rotated so the gap is centred on the bottom of the ring.
        let rotation = Angle.degrees(90 + (360 - sweep) / 2)
        ZStack {
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(track, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(rotation)
            // Only when it is meaningfully above the arc. A tick sitting on
            // the head of the arc is the same fact twice, and a tick that
            // follows the reading around is just a thicker arc.
            if let peak, peak > clamped + 0.08 {
                let at = fraction * min(max(peak, 0), 1)
                Circle()
                    .trim(from: max(0, at - 0.006), to: min(fraction, at + 0.006))
                    .stroke(tint.opacity(0.5),
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
                    .rotationEffect(rotation)
            }
            if clamped > 0 {
                Circle()
                    .trim(from: 0, to: fraction * clamped)
                    // 套圈时第一圈稍微淡一点，叠在上面的第二圈才分得出来。
                    .stroke(lap > 0 ? tint.opacity(0.55) : tint,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(rotation)
            }
            if lap > 0 {
                // 第二圈从同一个起点再走一遍，压在第一圈上面；头上带一点阴影，
                // 看得出它是叠上去的一圈而不是同一条弧。
                Circle()
                    .trim(from: 0, to: fraction * lap)
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .shadow(color: .black.opacity(0.35), radius: lineWidth * 0.35)
                    .rotationEffect(rotation)
            }
            content
        }
        .frame(width: diameter, height: diameter)
    }
}
