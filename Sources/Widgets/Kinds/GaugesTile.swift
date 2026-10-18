import SwiftUI

/// 圆环仪表：存储、电池、CPU、内存任意拼装，每个一个圆环、旁边写读数。
///
/// 码头里只有它画圆：电池画成电池形状，系统活动画成竖条，想要圆的人来这里拼。
/// Storage comes from the same sample System Activity takes (the root
/// volume's `URLResourceValues`, "important usage" free space as Finder
/// counts it), battery from the power-source API, CPU and memory from the
/// System Activity sampler. CPU temperature is not offered: macOS has no
/// public API for it.
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
                                    .font(WidgetStyle.note)
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
                                  lineWidth: diameter > 36 ? 4.5 : 4,
                                  peak: r.peak,
                                  laps: true) {
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
        /// 最近一分钟的最高值，CPU 和内存在圆环上标一下；存储和电池没有。
        var peak: Double?
    }

    private func reading(_ ring: String) -> Reading {
        switch ring {
        case "battery": battery
        case "cpu": activity(cpu: true)
        case "memory": activity(cpu: false)
        default: storage
        }
    }

    /// CPU 或内存，和系统活动读同一个采样器。
    private func activity(cpu: Bool) -> Reading {
        let value: Double
        let history: [Double]
        if context.isPreview {
            value = cpu ? 0.23 : 0.64
            history = []
        } else {
            let live = SystemMetrics.shared
            value = cpu ? live.cpu : live.memory
            history = live.history(for: cpu ? "cpu" : "memory")
        }
        return Reading(progress: min(max(value, 0), 1),
                       value: GaugeReading.percent(value),
                       caption: cpu ? "CPU" : tr("内存"),
                       symbol: cpu ? "cpu" : "memorychip",
                       tint: Color(hex: cpu ? MetricColor.cpu : MetricColor.memory),
                       known: true,
                       peak: history.max())
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
                       caption: known ? tr("可用，共 \(GaugeReading.bytes(total))") : tr("正在读取"),
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
        let caption = !present ? tr("没有电池") : charging ? tr("正在充电") : onPower ? tr("已接电源") : tr("使用电池")
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
