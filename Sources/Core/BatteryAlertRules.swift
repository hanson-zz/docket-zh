import Foundation

/// Which battery reminders the 电池 widget sends.
///
/// Off by default except the three that earn their place: charged to 80%,
/// down to 20%, and a Bluetooth accessory below 15%. The rest can be ticked,
/// so one charge does not ring five times.
public struct BatteryAlertSettings: Equatable, Sendable {
    public var charge: Set<Int>
    public var low: Set<Int>
    public var accessory: Bool
    public var full: Bool
    public var hot: Bool

    public static let chargeChoices = [80, 90, 95]
    public static let lowChoices = [20, 10]
    public static let accessoryLevel = 15
    /// An accessory has to climb back above this before it can warn again.
    public static let accessoryRearm = 25
    public static let hotCelsius = 40.0
    public static let coolCelsius = 35.0
    public static let fullAfter: TimeInterval = 2 * 60 * 60

    public static let chargeKey = "alertCharge"
    public static let lowKey = "alertLow"
    public static let accessoryKey = "alertAccessory"
    public static let fullKey = "alertFull"
    public static let hotKey = "alertHot"

    public init(charge: Set<Int> = [80], low: Set<Int> = [20], accessory: Bool = true,
                full: Bool = false, hot: Bool = false) {
        self.charge = charge
        self.low = low
        self.accessory = accessory
        self.full = full
        self.hot = hot
    }

    public init(config: WidgetConfig) {
        self.init(
            charge: Set(config.strings(Self.chargeKey, default: ["80"]).compactMap { Int($0) }),
            low: Set(config.strings(Self.lowKey, default: ["20"]).compactMap { Int($0) }),
            accessory: config.bool(Self.accessoryKey, default: true),
            full: config.bool(Self.fullKey),
            hot: config.bool(Self.hotKey))
    }

    public static func encode(_ levels: Set<Int>) -> WidgetConfig.Value {
        .list(levels.sorted().map { .string(String($0)) })
    }
}

public struct BatteryAlert: Equatable, Sendable {
    public var id: String
    public var title: String
    public var body: String
}

public struct BatteryReading: Sendable {
    public var percent: Int
    public var onPower: Bool
    public var celsius: Double?

    public init(percent: Int, onPower: Bool, celsius: Double? = nil) {
        self.percent = percent
        self.onPower = onPower
        self.celsius = celsius
    }
}

public struct AccessoryReading: Sendable {
    public var id: String
    public var name: String
    public var percent: Int

    public init(id: String, name: String, percent: Int) {
        self.id = id
        self.name = name
        self.percent = percent
    }
}

/// Remembers what has been said, so each level speaks once per charge.
///
/// Plugging in or unplugging rearms the other direction. The first reading
/// after either, and the first reading at launch, marks every level already
/// passed as said: plugging in at 85% is not "charged to 80%".
public struct BatteryAlertTracker: Sendable {
    private var lastOnPower: Bool?
    private var firedCharge: Set<Int> = []
    private var firedLow: Set<Int> = []
    private var fullSince: Date?
    private var firedFull = false
    private var firedHot = false
    private var firedAccessory: Set<String> = []

    public init() {}

    public mutating func check(_ mac: BatteryReading?, accessories: [AccessoryReading],
                               settings: BatteryAlertSettings, now: Date = .now) -> [BatteryAlert] {
        var alerts: [BatteryAlert] = []
        if let mac { alerts += checkMac(mac, settings: settings, now: now) }
        for item in accessories {
            if item.percent <= BatteryAlertSettings.accessoryLevel {
                if settings.accessory, !firedAccessory.contains(item.id) {
                    alerts.append(BatteryAlert(id: "accessory.\(item.id)",
                                               title: "\(item.name)电量低",
                                               body: "只剩 \(item.percent)%，记得充电。"))
                }
                firedAccessory.insert(item.id)
            } else if item.percent > BatteryAlertSettings.accessoryRearm {
                firedAccessory.remove(item.id)
            }
        }
        return alerts
    }

    private mutating func checkMac(_ mac: BatteryReading, settings: BatteryAlertSettings,
                                   now: Date) -> [BatteryAlert] {
        var alerts: [BatteryAlert] = []
        let percent = mac.percent
        if lastOnPower != mac.onPower {
            if mac.onPower {
                firedLow = []
                firedCharge = Set(BatteryAlertSettings.chargeChoices.filter { percent >= $0 })
            } else {
                firedCharge = []
                firedFull = false
                fullSince = nil
                firedLow = Set(BatteryAlertSettings.lowChoices.filter { percent <= $0 })
            }
            lastOnPower = mac.onPower
        }

        if mac.onPower {
            let reached = settings.charge.filter { percent >= $0 && !firedCharge.contains($0) }
            firedCharge.formUnion(BatteryAlertSettings.chargeChoices.filter { percent >= $0 })
            if let top = reached.max() {
                alerts.append(BatteryAlert(id: "charge", title: "电量已充到 \(percent)%",
                                           body: top >= 95 ? "快充满了，可以拔掉电源。"
                                                           : "已经够用了，想保护电池可以拔掉电源。"))
            }
            if percent >= 100 {
                let since = fullSince ?? now
                fullSince = since
                if settings.full, !firedFull, now.timeIntervalSince(since) >= BatteryAlertSettings.fullAfter {
                    firedFull = true
                    alerts.append(BatteryAlert(id: "full", title: "电池已充满 2 小时",
                                               body: "一直插着电对电池不太好，可以拔掉电源。"))
                }
            } else {
                fullSince = nil
            }
        } else {
            let reached = settings.low.filter { percent <= $0 && !firedLow.contains($0) }
            firedLow.formUnion(BatteryAlertSettings.lowChoices.filter { percent <= $0 })
            if !reached.isEmpty {
                alerts.append(BatteryAlert(id: "low", title: "电量只剩 \(percent)%",
                                           body: "该接上电源了。"))
            }
        }

        if let celsius = mac.celsius {
            if celsius >= BatteryAlertSettings.hotCelsius {
                if settings.hot, !firedHot {
                    alerts.append(BatteryAlert(id: "hot", title: "电池温度偏高",
                                               body: "现在约 \(Int(celsius.rounded()))°C，可以把 Mac 放到通风的地方，或先关掉占用高的 App。"))
                }
                firedHot = true
            } else if celsius < BatteryAlertSettings.coolCelsius {
                firedHot = false
            }
        }
        return alerts
    }
}
