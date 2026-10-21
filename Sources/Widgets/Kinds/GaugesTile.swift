import SwiftUI

/// 圆环仪表：存储、电池、CPU、内存任意拼装，每个一个圆环、旁边写读数。
///
/// 码头里只有它画圆：电池画成电池形状，系统活动画成竖条，想要圆的人来这里拼。
/// Storage comes from the same sample System Activity takes (the root
/// volume's `URLResourceValues`, "important usage" free space as Finder
/// counts it), battery from the power-source API, CPU and memory from the
/// System Activity sampler. CPU temperature is not offered: macOS has no
/// public API for it.
///
/// 圆环的先后按设置里拖好的；每个圆环过了警戒线（`GaugeAlert`）变红。点卡片打开
/// 面板：每个圆环一行详情，存储分应用、下载、废纸篓，CPU 和内存列最高的进程。
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
                                    .foregroundStyle(r.alert ? GaugeLive.red : WidgetStyle.primary)
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

    // MARK: Data

    private func reading(_ ring: String) -> GaugeLive.Reading {
        GaugeLive.reading(ring, config: instance.config, preview: context.isPreview)
    }

    private func gauge(_ ring: String, diameter: CGFloat) -> some View {
        GaugeRing(reading: reading(ring), diameter: diameter)
    }
}

/// 一个圆环，卡片和面板共用。面板里（`inPanel`）浅色玻璃上浅蓝、绿、橙这类
/// 高亮度色偏淡，圆环和图标换成 `panelGraphic`（不到 3:1 才往黑里压）；
/// 深色下和扩展栏卡片上颜色不变。
struct GaugeRing: View {
    var reading: GaugeLive.Reading
    var diameter: CGFloat
    var inPanel: Bool = false

    var body: some View {
        let r = reading
        let tint = inPanel ? r.tint.panelGraphic : r.tint
        MetricProgressRing(progress: r.progress,
                           tint: tint,
                           track: r.known ? r.tint.opacity(0.16) : Color.primary.opacity(0.10),
                           diameter: diameter,
                           lineWidth: diameter > 36 ? 4.5 : 4,
                           peak: r.peak,
                           laps: true) {
            Image(systemName: r.symbol)
                .font(.system(size: diameter * 0.32, weight: .regular))
                .foregroundStyle(r.known ? tint : WidgetStyle.secondary)
        }
    }
}

/// 圆环仪表的读数，卡片和面板共用。过了警戒线（`GaugeAlert`）圆环和读数变红。
@MainActor
enum GaugeLive {
    static let red = Color(hex: "#FF453A")

    struct Reading {
        var progress: Double
        var value: String
        var caption: String
        var symbol: String
        var tint: Color
        var known: Bool
        /// 最近一分钟的最高值，CPU 和内存在圆环上标一下；存储和电池没有。
        var peak: Double?
        /// 过了警戒线。
        var alert: Bool = false
    }

    static func reading(_ ring: String, config: WidgetConfig, preview: Bool) -> Reading {
        let line = GaugeAlert.value(ring, config)
        switch ring {
        case "battery": return battery(line: line, preview: preview)
        case "cpu": return activity(cpu: true, line: line, preview: preview)
        case "memory": return activity(cpu: false, line: line, preview: preview)
        default: return storage(line: line, preview: preview)
        }
    }

    /// CPU 或内存，和系统活动读同一个采样器。
    private static func activity(cpu: Bool, line: Int, preview: Bool) -> Reading {
        let value: Double
        let history: [Double]
        if preview {
            value = cpu ? 0.23 : 0.64
            history = []
        } else {
            let live = SystemMetrics.shared
            value = cpu ? live.cpu : live.memory
            history = live.history(for: cpu ? "cpu" : "memory")
        }
        let alert = GaugeAlert.isOver(cpu ? "cpu" : "memory", fraction: value, line: line)
        return Reading(progress: min(max(value, 0), 1),
                       value: GaugeReading.percent(value),
                       caption: cpu ? "CPU" : tr("内存"),
                       symbol: cpu ? "cpu" : "memorychip",
                       tint: alert ? red : Color(hex: cpu ? MetricColor.cpu : MetricColor.memory),
                       known: true,
                       peak: history.max(),
                       alert: alert)
    }

    private static func storage(line: Int, preview: Bool) -> Reading {
        let (free, total) = storageBytes(preview: preview)
        let known = total > 0
        let used = GaugeReading.usedFraction(free: free, total: total)
        let alert = known && GaugeAlert.isOver("storage", fraction: used, line: line)
        return Reading(progress: used,
                       value: known ? GaugeReading.bytes(free) : "-",
                       caption: known ? tr("可用，共 \(GaugeReading.bytes(total))") : tr("正在读取"),
                       symbol: "internaldrive",
                       tint: alert ? red : Color(hex: MetricColor.storage),
                       known: known,
                       alert: alert)
    }

    static func storageBytes(preview: Bool) -> (free: Int64, total: Int64) {
        preview ? (245_000_000_000, 494_000_000_000) : (SystemMetrics.shared.diskFree, SystemMetrics.shared.diskTotal)
    }

    private static func battery(line: Int, preview: Bool) -> Reading {
        let state: (level: Double, charging: Bool, onPower: Bool, present: Bool)
        if preview {
            state = (0.76, false, false, true)
        } else if let mac = BatteryMetrics.shared.device(.mac), mac.present {
            state = (mac.level, mac.charging, mac.onPower, true)
        } else {
            state = (0, false, false, false)
        }
        let (level, charging, onPower, present) = state
        let caption = !present ? tr("没有电池") : charging ? tr("正在充电") : onPower ? tr("已接电源") : tr("使用电池")
        var tint = Color(hex: MetricColor.batteryPresent)
        let alert = present && GaugeAlert.isOver("battery", fraction: level, line: line, charging: charging || onPower)
        if alert {
            tint = red
        } else if present, !charging, !onPower, level <= 0.20 {
            tint = Color(hex: "#FF9F0A")
        }
        return Reading(progress: present ? level : 0,
                       value: present ? GaugeReading.percent(level) : "-",
                       caption: caption,
                       symbol: charging ? "battery.100percent.bolt" : "battery.75percent",
                       tint: tint,
                       known: present,
                       alert: alert)
    }
}
