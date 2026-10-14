import Foundation

/// The four Wi-Fi ring styles of 网络活动, stored as the widget's `layout`.
///
/// 经典 is free; the other three are 赞助者专属 appearances, like the
/// supporter clock faces. Every style reads the same signal, so locking one
/// never hides information.
public enum WifiRingStyle: String, CaseIterable, Sendable {
    case classic = "wifi"
    case numeric = "wifiNumeric"
    case dotted = "wifiDotted"
    case thin = "wifiThin"

    public var title: String {
        switch self {
        case .classic: "经典"
        case .numeric: "数字"
        case .dotted: "点状"
        case .thin: "细线"
        }
    }

    public var isSupporterOnly: Bool { self != .classic }

    /// The style a layout names, or nil for the throughput layouts.
    public static func from(layout: String) -> WifiRingStyle? { WifiRingStyle(rawValue: layout) }

    /// What is drawn: a locked style falls back to 经典.
    public static func shown(layout: String, unlocked: Bool) -> WifiRingStyle? {
        guard let style = from(layout: layout) else { return nil }
        return style.isSupporterOnly && !unlocked ? .classic : style
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
        case 4: "极好"
        case 3: "良好"
        case 2: "一般"
        case 1: "较弱"
        default: "很差"
        }
    }

    /// Signal-to-noise ratio in dB, or nil when there is no noise reading.
    public static func snr(rssi: Int, noise: Int) -> Int? {
        guard noise < 0, rssi < 0 else { return nil }
        return rssi - noise
    }
}
