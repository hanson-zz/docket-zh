import SwiftUI

/// Storage and battery as ring gauges, each with its figure beside it.
///
/// Storage comes from the same sample System Activity takes (the root
/// volume's `URLResourceValues`, "important usage" free space as Finder
/// counts it), battery from the power-source API. CPU temperature is not
/// offered: macOS has no public API for it.
struct GaugesTile: View {
    var instance: WidgetInstance
    var context: WidgetContext

    private var rings: [String] { GaugeReading.rings(instance.config) }

    var body: some View {
        WidgetSurface {
            if context.position.isVertical {
                VStack(spacing: 6) {
                    ForEach(rings, id: \.self) { ring in
                        VStack(spacing: 2) {
                            gauge(ring, diameter: 34)
                            Text(reading(ring).value)
                                .font(WidgetStyle.caption(10))
                                .foregroundStyle(WidgetStyle.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                }
            } else {
                HStack(spacing: 10) {
                    ForEach(rings, id: \.self) { ring in
                        let r = reading(ring)
                        HStack(spacing: 8) {
                            gauge(ring, diameter: 40)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(r.value)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(WidgetStyle.primary)
                                    .monospacedDigit()
                                    .rollingValue(r.value)
                                Text(r.caption)
                                    .font(.system(size: 11))
                                    .foregroundStyle(WidgetStyle.secondary)
                            }
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .onAppear {
            guard !context.isPreview else { return }
            SystemMetrics.shared.start()
            BatteryMetrics.shared.start()
        }
    }

    private func gauge(_ ring: String, diameter: CGFloat) -> some View {
        let r = reading(ring)
        return MetricProgressRing(progress: r.progress,
                                  tint: r.tint,
                                  track: r.known ? r.tint.opacity(0.16) : Color.primary.opacity(0.10),
                                  diameter: diameter,
                                  lineWidth: diameter > 36 ? 4.5 : 4) {
            Image(systemName: r.symbol)
                .font(.system(size: diameter * 0.32, weight: .regular))
                .foregroundStyle(r.known ? r.tint : WidgetStyle.secondary)
        }
    }

    // MARK: Data

    private struct Reading {
        var progress: Double
        var value: String
        var caption: String
        var symbol: String
        var tint: Color
        var known: Bool
    }

    private func reading(_ ring: String) -> Reading {
        ring == "battery" ? battery : storage
    }

    private var storage: Reading {
        let free: Int64, total: Int64
        if context.isPreview {
            free = 245_000_000_000
            total = 494_000_000_000
        } else {
            free = SystemMetrics.shared.diskFree
            total = SystemMetrics.shared.diskTotal
        }
        let known = total > 0
        return Reading(progress: GaugeReading.usedFraction(free: free, total: total),
                       value: known ? GaugeReading.bytes(free) : "-",
                       caption: known ? "可用，共 \(GaugeReading.bytes(total))" : "正在读取",
                       symbol: "internaldrive",
                       tint: Color(hex: MetricColor.storage),
                       known: known)
    }

    private var battery: Reading {
        let state: (level: Double, charging: Bool, onPower: Bool, present: Bool)
        if context.isPreview {
            state = (0.76, false, false, true)
        } else if let mac = BatteryMetrics.shared.device(.mac), mac.present {
            state = (mac.level, mac.charging, mac.onPower, true)
        } else {
            state = (0, false, false, false)
        }
        let (level, charging, onPower, present) = state
        let caption = !present ? "没有电池" : charging ? "正在充电" : onPower ? "已接电源" : "使用电池"
        var tint = Color(hex: MetricColor.batteryPresent)
        if present, !charging, !onPower {
            if level <= 0.10 { tint = Color(hex: "#FF453A") } else if level <= 0.20 { tint = Color(hex: "#FF9F0A") }
        }
        return Reading(progress: present ? level : 0,
                       value: present ? GaugeReading.percent(level) : "-",
                       caption: caption,
                       symbol: charging ? "battery.100percent.bolt" : "battery.75percent",
                       tint: tint,
                       known: present)
    }
}
