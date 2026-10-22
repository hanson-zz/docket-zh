import Foundation

/// The two Wi-Fi ring styles of 网络活动, stored as the widget's `layout`.
///
/// 经典 is free; 数字 is a Pro 专属 appearance. Both read the same signal, so
/// locking one never hides information.
///
/// 原来还有点状（wifiDotted）和细线（wifiThin）两款，已并入经典：存着这两个
/// 旧值的卡片读配置时换成经典（见 `migrating`），`from(layout:)` 也把它们读成
/// 经典，卡片不会丢。
public enum WifiRingStyle: String, CaseIterable, Sendable {
    case classic = "wifi"
    case numeric = "wifiNumeric"

    /// 并入经典的旧样式值。
    public static let legacyClassicLayouts: Set<String> = ["wifiDotted", "wifiThin"]
    public static let layoutKey = "layout"

    public var title: String {
        switch self {
        case .classic: tr("经典")
        case .numeric: tr("数字")
        }
    }

    public var isSupporterOnly: Bool { self != .classic }

    /// The style a layout names, or nil for the throughput layouts.
    /// 旧的点状、细线读成经典。
    public static func from(layout: String) -> WifiRingStyle? {
        if legacyClassicLayouts.contains(layout) { return .classic }
        return WifiRingStyle(rawValue: layout)
    }

    /// What is drawn: a locked style falls back to 经典.
    public static func shown(layout: String, unlocked: Bool) -> WifiRingStyle? {
        guard let style = from(layout: layout) else { return nil }
        return style.isSupporterOnly && !unlocked ? .classic : style
    }

    /// 读配置时把旧的点状、细线换成经典，只改 `layout`，其余配置原样保留。
    public static func migrating(_ config: WidgetConfig) -> WidgetConfig {
        guard case .string(let raw) = config.values[layoutKey], legacyClassicLayouts.contains(raw) else { return config }
        var copy = config
        copy.set(layoutKey, .string(WifiRingStyle.classic.rawValue))
        return copy
    }
}

/// 面板顶部「信号大环」右侧的几行字，按真实读数算。
public struct WifiSignalSummary: Equatable, Sendable {
    /// 强度一个词（极好、良好……），没连上时是「未连接」。
    public var label: String
    /// 「-52 dBm · 63%」，没连上时是 nil。
    public var level: String?
    /// 「连接 866 Mbps」，读不到速率时是 nil。
    public var link: String?

    public init(rssi: Int?, rate: Double?) {
        guard let rssi, rssi < 0 else {
            label = tr("未连接")
            level = nil
            link = nil
            return
        }
        label = WifiQuality.label(rssi: rssi)
        level = "\(rssi) dBm · \(WifiQuality.percent(rssi: rssi))%"
        if let rate, rate > 0 {
            link = tr("连接 \(Int(rate.rounded())) Mbps")
        } else {
            link = nil
        }
    }
}

/// Signal quality read off an RSSI in dBm.
///
/// CoreWLAN reports RSSI as a negative dBm figure, with 0 meaning "not
/// associated". The mapping is linear between -90 dBm (unusable) and
/// -30 dBm (next to the router), which is how macOS's own Wi-Fi
/// diagnostics bucket it closely enough for a glance.
public enum WifiQuality {
    public static let floor = -90
    public static let ceiling = -30

    /// 0...100.
    public static func percent(rssi: Int) -> Int {
        let clamped = min(max(rssi, floor), ceiling)
        return Int((Double(clamped - floor) / Double(ceiling - floor) * 100).rounded())
    }

    /// 0...4, the lit dots under the ring.
    public static func bars(rssi: Int) -> Int {
        switch rssi {
        case (-55)...: 4
        case (-67)...: 3
        case (-75)...: 2
        case (-85)...: 1
        default: 0
        }
    }

    public static func label(rssi: Int) -> String {
        switch bars(rssi: rssi) {
        case 4: tr("极好")
        case 3: tr("良好")
        case 2: tr("一般")
        case 1: tr("较弱")
        default: tr("很差")
        }
    }

    /// Signal-to-noise ratio in dB, or nil when there is no noise reading.
    public static func snr(rssi: Int, noise: Int) -> Int? {
        guard noise < 0, rssi < 0 else { return nil }
        return rssi - noise
    }
}
