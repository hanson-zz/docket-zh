import Foundation

/// The numbers behind the ring gauges, kept pure for tests.
public enum GaugeReading {
    /// Used share of a volume, 0...1. Zero when the total is unknown.
    public static func usedFraction(free: Int64, total: Int64) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, 1 - Double(max(0, free)) / Double(total)))
    }

    /// Bytes in decimal units, the way Finder counts them: "245 GB",
    /// "1.2 TB", "512 MB". One decimal only below ten.
    public static func bytes(_ value: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB", "PB"]
        var amount = Double(max(0, value))
        var index = 0
        while amount >= 1000, index < units.count - 1 {
            amount /= 1000
            index += 1
        }
        if index == 0 { return "\(Int(amount)) B" }
        let text = amount < 10 ? String(format: "%.1f", amount) : String(format: "%.0f", amount)
        return "\(text) \(units[index])"
    }

    /// "62%" for a fraction.
    public static func percent(_ fraction: Double) -> String {
        "\(Int((min(max(fraction, 0), 1) * 100).rounded()))%"
    }

    /// 圆环仪表能拼的指标，按卡片上的先后：存储、电池、CPU、内存。
    /// 圆只留给圆环仪表，系统活动的指标也能拼进来。
    public static let allRings = ["storage", "battery", "cpu", "memory"]

    /// 没选过时的默认，也是旧卡片没存 `rings` 时读到的：存储和电池。
    public static let defaultRings = ["storage", "battery"]

    /// Which rings a gauge widget shows, never none. 按设置里拖好的先后
    /// （`OrderedChecklist`）；以前固定按存储、电池、CPU、内存排，存着的旧列表
    /// 本来就是勾选先后，读出来顺序可能和以前不同。
    public static func rings(_ config: WidgetConfig) -> [String] {
        let ordered = OrderedChecklist.ordered(config.strings("rings", default: defaultRings), all: allRings)
        return ordered.isEmpty ? defaultRings : ordered
    }

    /// Natural width of the gauge tile for that many rings.
    public static func tileWidth(rings: Int) -> Double {
        Double(max(1, rings)) * 112 + 20
    }
}
