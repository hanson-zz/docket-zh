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

    /// Which rings a gauge widget shows, in a fixed order, never none.
    public static func rings(_ config: WidgetConfig) -> [String] {
        let known = ["storage", "battery"]
        let chosen = config.strings("rings", default: known).filter(known.contains)
        let ordered = known.filter(chosen.contains)
        return ordered.isEmpty ? known : ordered
    }

    /// Natural width of the gauge tile for that many rings.
    public static func tileWidth(rings: Int) -> Double {
        Double(max(1, rings)) * 112 + 20
    }
}
