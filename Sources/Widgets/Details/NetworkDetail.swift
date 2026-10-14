import SwiftUI

/// Network said at length: the two rates the tile leads with, and under them
/// the minute they came out of.
///
/// The tile answers "how fast, right now" - a figure that is already stale by
/// the time it is read. What a card cannot hold is the *shape*: whether this
/// second is a spike in an idle minute or the tail of a long download, and how
/// the two directions relate. That is the whole reason this panel exists.
///
/// Only what `NetworkMetrics` publishes: instantaneous rates and the last
/// sixty one-second samples of each. The sampler sums every non-loopback link,
/// so there is no interface to name, and it keeps rates rather than counters,
/// so there is no session total to report. The averages and peaks below are
/// read off the same history the chart draws - nothing here is a second
/// source.
struct NetworkDetail: View {
    var instance: WidgetInstance
    var context: WidgetContext

    var body: some View {
        // Deep teal, the colour of a line carrying something, with the
        // minute's traffic as the ground along its foot.
        DetailCard {
            MeshBackdrop(color: Color(red: 0.05, green: 0.45, blue: 0.5))
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                if let wifi = wifiStyle { wifiSection(wifi) }
                headline

                // Two samples is the minimum a line can be drawn from, and
                // the sampler's first tick is only a baseline - so a panel
                // opened in the first seconds of the shelf's life honestly
                // shows the rates alone until the history catches up.
                if window >= 2 {
                    table
                    history
                }
            }
        }
    }

    // MARK: Wi-Fi
    //
    // Shown when the card is one of the Wi-Fi rings: the same ring larger,
    // then what the tile has no room for. The rates still follow, because
    // the link and what flows over it are one question.

    private var wifiStyle: WifiRingStyle? {
        WifiRingStyle.shown(layout: instance.config.string("layout", default: "speed"),
                            unlocked: Supporter.isUnlocked || context.isPreview)
    }

    private var wifiRSSI: Int? { context.isPreview ? -52 : WifiMetrics.shared.rssi }
    private var wifiNoise: Int? { context.isPreview ? -92 : WifiMetrics.shared.noise }
    private var wifiRate: Double? { context.isPreview ? 866 : WifiMetrics.shared.rate }
    private var wifiName: String? { context.isPreview ? nil : WifiMetrics.shared.ssid }

    private func wifiSection(_ style: WifiRingStyle) -> some View {
        let reading = WifiReading(rssi: wifiRSSI)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                WifiRingView(style: style, reading: reading, diameter: 84)
                VStack(alignment: .leading, spacing: 2) {
                    Text(reading.label)
                        .font(WidgetStyle.value(28))
                        .foregroundStyle(WidgetStyle.primary)
                    Text(wifiName ?? "Wi-Fi 信号")
                        .font(WidgetStyle.caption(11))
                        .foregroundStyle(WidgetStyle.secondary)
                        .lineLimit(1)
                }
            }
            if let rssi = wifiRSSI {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                    GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    StatChip(label: "信号强度", value: "\(rssi) dBm")
                    StatChip(label: "信号质量", value: "\(reading.percent)%")
                    if let noise = wifiNoise, let snr = WifiQuality.snr(rssi: rssi, noise: noise) {
                        StatChip(label: "信噪比", value: "\(snr) dB")
                    }
                    if let rate = wifiRate {
                        StatChip(label: "连接速率", value: "\(Int(rate.rounded())) Mbps")
                    }
                }
            }
        }
        .onAppear { if !context.isPreview { WifiMetrics.shared.start() } }
    }

    // MARK: Now

    private var headline: some View {
        HStack(spacing: 12) {
            if showsDownload { reading("arrow.down", "下载", download, Self.downTint) }
            if showsUpload { reading("arrow.up", "上传", upload, Self.upTint) }
        }
    }

    private func reading(_ symbol: String, _ name: String, _ rate: Double, _ tint: Color) -> some View {
        let value = formatted(rate)
        return VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                Text(value.value)
                    .font(WidgetStyle.value(34))
                    .monospacedDigit()
                    .foregroundStyle(WidgetStyle.primary)
                    .rollingValue(value.value)
                Text(value.unit)
                    .font(WidgetStyle.caption(12))
                    .foregroundStyle(WidgetStyle.secondary)
            }
            // The tile has room for an arrow and nothing else; at this width
            // the direction can be said in words.
            Text(name)
                .font(WidgetStyle.caption(11))
                .foregroundStyle(WidgetStyle.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(name)
        .accessibilityValue("\(value.value) \(value.unit)")
    }

    // MARK: History

    /// Both directions over one shared minute.
    ///
    /// Throughput has no natural ceiling the way a percentage does, so the
    /// scale is the larger of the two series' own peaks - the same choice the
    /// tile's sparkline makes, and the only one under which the lines can be
    /// read against each other. Let each auto-scale and a 2 KB/s keepalive
    /// would draw exactly as tall as a 40 MB/s download sitting beside it.
    ///
    /// Floored at 1 KB/s so an idle minute stays pinned to the bottom of the
    /// frame: without a floor the scale collapses onto the noise and a few
    /// stray bytes are drawn as a mountain range.
    private var history: some View {
        ZStack(alignment: .topLeading) {
            ZStack {
                if showsDownload {
                    DitherChart(samples: downloadHistory, tint: Self.downTint,
                                filled: false, range: scale)
                }
                if showsUpload {
                    DitherChart(samples: uploadHistory, tint: Self.upTint,
                                filled: false, range: scale)
                }
            }
            .frame(height: 58)
            .frame(maxWidth: .infinity)
            .padding(.top, 14)
            // Named with the span the buffer actually holds, which is under a
            // minute until it fills.
            Text((window >= NetworkMetrics.historyLength ? "最近 60 秒" : "最近 \(window) 秒")
                    .uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.55))
                .padding(.horizontal, 16)
        }
        // To the card's edges and foot.
        .padding(.horizontal, -16)
        .padding(.bottom, -16)
    }

    private var scale: ClosedRange<Double> {
        let peaks = [showsDownload ? peak(downloadHistory) : 0, showsUpload ? peak(uploadHistory) : 0]
        return 0...max(peaks.max() ?? 0, 1024)
    }

    // MARK: Table

    /// What the chart's shape cannot be read off it: the level the lines are
    /// drawn against. The peak names the top of the frame, and the average
    /// says whether a spike was the whole minute or a moment in it. Chips,
    /// two to a direction, in place of a table with a header row.
    private var table: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                            GridItem(.flexible(), spacing: 8)], spacing: 8) {
            if showsDownload {
                StatChip(label: "下载平均", value: text(average(downloadHistory)))
                StatChip(label: "下载峰值", value: text(peak(downloadHistory)))
            }
            if showsUpload {
                StatChip(label: "上传平均", value: text(average(uploadHistory)))
                StatChip(label: "上传峰值", value: text(peak(uploadHistory)))
            }
        }
    }

    private func text(_ rate: Double) -> String {
        let value = formatted(rate)
        return "\(value.value) \(value.unit)"
    }

    private func average(_ series: [Double]) -> Double {
        series.isEmpty ? 0 : series.reduce(0, +) / Double(series.count)
    }

    private func peak(_ series: [Double]) -> Double { series.max() ?? 0 }

    // MARK: Config & data
    //
    // The tile's keys, key for key: a widget set to watch one direction must
    // not have the panel quietly report both.

    private static let downTint = Color(hex: MetricColor.netDownload)
    private static let upTint = Color(hex: MetricColor.netUpload)

    private var display: String { instance.config.string("display", default: "both") }
    private var showsDownload: Bool { display != "upload" }
    private var showsUpload: Bool { display != "download" }

    /// The shorter of the two buffers, so the axis under the chart cannot
    /// claim more seconds than both lines actually cover.
    private var window: Int {
        min(downloadHistory.count, uploadHistory.count)
    }

    private var download: Double {
        context.isPreview ? 999 * 1024 : NetworkMetrics.shared.download
    }

    private var upload: Double {
        context.isPreview ? 292 * 1024 : NetworkMetrics.shared.upload
    }

    private var downloadHistory: [Double] {
        context.isPreview ? Self.sample(peak: 999 * 1024, phase: 0) : NetworkMetrics.shared.downloadHistory
    }

    private var uploadHistory: [Double] {
        context.isPreview ? Self.sample(peak: 292 * 1024, phase: 1.7) : NetworkMetrics.shared.uploadHistory
    }

    /// Deterministic, plausible-looking traffic for the library, matching the
    /// tile's own preview by eye so a widget and its panel do not disagree.
    private static func sample(peak: Double, phase: Double) -> [Double] {
        (0..<40).map { i in
            let t = Double(i) / 4 + phase
            return peak * (0.45 + 0.35 * sin(t) + 0.18 * sin(t * 2.3))
        }
    }

    /// KB/s until it no longer fits, then MB/s - the tile's rule, so the
    /// headline reads the same before and after the panel opens.
    private func formatted(_ bytesPerSecond: Double) -> (value: String, unit: String) {
        let kb = max(bytesPerSecond, 0) / 1024
        if kb < 1024 { return ("\(Int(kb.rounded()))", "KB/s") }
        return (String(format: "%.1f", kb / 1024), "MB/s")
    }
}
