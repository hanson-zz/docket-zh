import Foundation
import SwiftUI

/// System Activity said at length: the tile's gauges at a size that can hold a
/// number, and under them the figures a 42pt ring has no room for.
///
/// Which metrics appear is the widget's own `metrics` config, chosen per
/// metric in Dock Settings, so the panel has to follow it rather than assume
/// the CPU-and-memory default it happens to ship with.
struct SystemActivityDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    var body: some View {
        // Graphite with a violet cast: a machine's insides, dark enough that
        // the rings' own colours are the only colour in it.
        DetailCard {
            MeshBackdrop(color: Color(red: 0.3, green: 0.24, blue: 0.5))
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: Self.gaugeGap) {
                    ForEach(metrics, id: \.self) { gauge($0) }
                }
                .frame(maxWidth: .infinity)

                // The figures each ring leaves out, side by side rather
                // than a column of rows. Two to a line, since a GiB
                // reading needs the width.
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                    GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(metrics, id: \.self) { chip($0) }
                }

                // The last minute, for the metrics that move. Disk and
                // battery keep a history that would be a flat line, so they
                // are not drawn one.
                if !charted.isEmpty { history }
            }
        }
    }

    // MARK: History

    private var charted: [Metric] {
        metrics.filter { !samples($0).isEmpty }
    }

    /// One line per moving metric, over a shared minute.
    ///
    /// The weather panel earns its keep by showing the shape of the next few
    /// hours rather than one temperature; this is the same idea pointed
    /// backwards. The rings say where things are, and this says whether they
    /// are on their way up.
    ///
    /// To the card's edges and foot, as the ground the readings stand on.
    private var history: some View {
        ZStack(alignment: .topLeading) {
            ZStack {
                ForEach(charted, id: \.self) { metric in
                    // Absolute, so a CPU idling low sits low and the lines
                    // can honestly be read against each other.
                    DitherChart(samples: samples(metric), tint: metric.color,
                                filled: charted.count == 1, range: 0...1)
                }
            }
            .frame(height: 54)
            .frame(maxWidth: .infinity)
            .padding(.top, 14)
            Text(span.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.55))
                .padding(.horizontal, 16)
        }
        .padding(.horizontal, -16)
        .padding(.bottom, -16)
    }

    /// Named with the span the buffer actually holds, which is under a minute
    /// until it fills.
    private var span: String {
        let count = charted.map { samples($0).count }.max() ?? 0
        return count >= SystemMetrics.historyLength ? "最近 60 秒" : "最近 \(count) 秒"
    }

    private func samples(_ metric: Metric) -> [Double] {
        guard !context.isPreview else { return [] }
        return SystemMetrics.shared.history(for: metric.rawValue)
    }

    // MARK: Gauges

    private static let gaugeGap: CGFloat = 12

    /// Small enough to be a reading rather than a poster.
    ///
    /// These were sized to fill the panel's width - 93pt across for three
    /// metrics - which put a 24pt figure inside each and left the gauges
    /// occupying most of the panel while saying one number each. A gauge is
    /// worth its space at the size the eye can take in at a glance; the width
    /// it gives back is what lets the figures and the graph below it fit.
    ///
    /// Larger on the card than it was on the form, now that the rows under
    /// it have become chips and given the height back.
    private var diameter: CGFloat {
        let content = WidgetDetail.width(instance.kind) - 32
        let count = CGFloat(metrics.count)
        return min(72, (content - Self.gaugeGap * (count - 1)) / count)
    }

    private func gauge(_ metric: Metric) -> some View {
        VStack(spacing: 6) {
            MetricProgressRing(progress: value(metric),
                               tint: metric.color,
                               // Neutral, not a dim copy of the arc's own
                               // colour: tinting both made the unfilled part
                               // read as a second, muddier reading.
                               track: .white.opacity(0.12),
                               diameter: diameter,
                               lineWidth: diameter * 0.11) {
                percent(value(metric), size: diameter * 0.30)
            }
            // The tile's ring carries a symbol because a 42pt card has nowhere
            // to put a caption. At this size the reading goes back inside and
            // the name underneath, with the arc's colour tying the two.
            Text(metric.label)
                .font(WidgetStyle.caption(11))
                .foregroundStyle(WidgetStyle.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(metric.label)
        .accessibilityValue("百分之 \(whole(value(metric)))")
    }

    @ViewBuilder
    private func percent(_ value: Double, size: CGFloat) -> some View {
        let reading = whole(value)
        HStack(spacing: 0) {
            Text("\(reading)")
                .font(.system(size: size, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(WidgetStyle.primary)
                .rollingValue(reading)
            // Smaller than the figure, so a three-digit reading still clears
            // the arc it sits inside.
            Text("%")
                .font(.system(size: size * 0.62, weight: .bold))
                .foregroundStyle(WidgetStyle.secondary)
        }
    }

    // MARK: Detail

    private func chip(_ metric: Metric) -> some View {
        let line = detail(metric)
        return StatChip(label: line.label, value: line.value)
    }

    /// The one fact each gauge leaves out.
    ///
    /// The sampler publishes fractions, so memory is the only one that can be
    /// restated in bytes - its fraction is measured against
    /// `physicalMemory`, which makes the multiplication the reading itself
    /// rather than a guess. The others say what they are a fraction *of*, or
    /// what the number cannot show, instead of inventing an absolute figure.
    private func detail(_ metric: Metric) -> (label: String, value: String) {
        switch metric {
        case .cpu:
            // The ring is this second; the average is the minute behind it,
            // off the same series the tile's sparkline draws. Named with the
            // span it actually has, which is shorter than a minute until the
            // history fills.
            let series = context.isPreview ? [] : SystemMetrics.shared.cpuHistory
            guard !series.isEmpty else { return ("CPU 平均占用", "-") }
            let average = series.reduce(0, +) / Double(series.count)
            return ("CPU 平均占用", "\(whole(average))%")
        case .memory:
            let total = Double(ProcessInfo.processInfo.physicalMemory)
            let gib = 1024.0 * 1024 * 1024
            return ("已用内存",
                    String(format: "%.1f / %.0f GiB", value(metric) * total / gib, total / gib))
        case .disk:
            // The percentage is the ring's job. This is the figure you
            // actually act on, off the same sample.
            let free = Double(SystemMetrics.shared.diskFree)
            let total = Double(SystemMetrics.shared.diskTotal)
            guard !context.isPreview, total > 0 else { return ("启动磁盘", "-") }
            let gib = 1024.0 * 1024 * 1024
            return ("启动磁盘可用空间",
                    String(format: "%.0f / %.0f GiB", free / gib, total / gib))
        case .battery:
            let mac = context.isPreview ? nil : BatteryMetrics.shared.device(.mac)
            guard let mac, mac.present else { return ("Mac 电池", "未报告") }
            // The 电池 widget's own status line: adapter watts and macOS's
            // time estimate, not just which way the level is going.
            return ("Mac 电池", BatteryMetrics.shared.statusLine ?? (mac.charging ? "正在充电" : "使用电池"))
        }
    }

    // MARK: Data

    /// The tile's key and the tile's fallback, so the panel cannot disagree
    /// with the card that opened it.
    private var metrics: [Metric] {
        let parsed = instance.config
            .strings("metrics", default: ["cpu", "memory"])
            .compactMap(Metric.init(rawValue:))
        return parsed.isEmpty ? [.cpu, .memory] : parsed
    }

    private func value(_ metric: Metric) -> Double {
        if context.isPreview { return metric.sample }
        switch metric {
        case .cpu, .memory, .disk:
            return SystemMetrics.shared.value(for: metric.rawValue)
        // The Mac's own battery: the other devices belong to the battery
        // widget, which is the one that can show more than one of them.
        case .battery:
            return BatteryMetrics.shared.device(.mac)?.level ?? 0
        }
    }

    private func whole(_ value: Double) -> Int {
        Int((min(max(value, 0), 1) * 100).rounded())
    }

    /// The tile's metric list, which is nested and private to it. Same raw
    /// values because both sides read the same config key - a metric added
    /// there has to be added here too, or the panel drops it silently.
    private enum Metric: String {
        case cpu, memory, disk, battery

        var label: String {
            switch self {
            case .cpu: "CPU"
            case .memory: "内存"
            case .disk: "磁盘"
            case .battery: "电池"
            }
        }

        var color: Color {
            switch self {
            case .cpu: Color(hex: MetricColor.cpu)
            case .memory: Color(hex: MetricColor.memory)
            case .disk: Color(hex: MetricColor.storage)
            case .battery: Color(hex: MetricColor.batteryPresent)
            }
        }

        /// The library has no sampler behind it.
        var sample: Double {
            switch self {
            case .cpu: 0.24
            case .memory: 0.63
            case .disk: 0.41
            case .battery: 0.78
            }
        }
    }
}
