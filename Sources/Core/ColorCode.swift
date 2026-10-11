import Foundation

/// A sampled colour as the three numbers people actually copy.
///
/// Pure so the formatting is tested without AppKit. Components are sRGB in
/// 0...1; the picker converts whatever `NSColorSampler` hands back into sRGB
/// before it gets here.
public struct ColorCode: Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
    }

    /// `#RRGGBB` or `RRGGBB`, either case. Nil for anything else.
    public init?(hex: String) {
        var raw = hex.trimmingCharacters(in: .whitespaces)
        if raw.hasPrefix("#") { raw.removeFirst() }
        guard raw.count == 6, let value = UInt32(raw, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }

    private static func clamp(_ v: Double) -> Double {
        v.isFinite ? min(1, max(0, v)) : 0
    }

    private static func byte(_ v: Double) -> Int { Int((v * 255).rounded()) }

    public var bytes: (r: Int, g: Int, b: Int) { (Self.byte(red), Self.byte(green), Self.byte(blue)) }

    /// `#1C1C1E`.
    public var hex: String {
        let b = bytes
        return String(format: "#%02X%02X%02X", b.r, b.g, b.b)
    }

    /// `rgb(28, 28, 30)`, the form CSS and most design tools accept.
    public var rgb: String {
        let b = bytes
        return "rgb(\(b.r), \(b.g), \(b.b))"
    }

    /// `hsl(240, 3%, 11%)`.
    public var hsl: String {
        let maxV = max(red, green, blue), minV = min(red, green, blue)
        let l = (maxV + minV) / 2
        var h = 0.0, s = 0.0
        let d = maxV - minV
        if d > 0 {
            s = l > 0.5 ? d / (2 - maxV - minV) : d / (maxV + minV)
            if maxV == red { h = (green - blue) / d + (green < blue ? 6 : 0) }
            else if maxV == green { h = (blue - red) / d + 2 }
            else { h = (red - green) / d + 4 }
            h *= 60
        }
        return "hsl(\(Int(h.rounded()) % 360), \(Int((s * 100).rounded()))%, \(Int((l * 100).rounded()))%)"
    }

    /// Whether dark ink reads better than white on this colour.
    public var isLight: Bool {
        0.2126 * red + 0.7152 * green + 0.0722 * blue > 0.6
    }
}

/// Newest-first, de-duplicated, capped: the shape every "recent" list in the
/// widgets has (colours, clipboard entries, held files).
public enum RecentList {
    public static func inserting<T>(_ item: T, into list: [T], limit: Int,
                                    same: (T, T) -> Bool) -> [T] {
        var result = list.filter { !same($0, item) }
        result.insert(item, at: 0)
        if result.count > max(0, limit) { result.removeLast(result.count - max(0, limit)) }
        return result
    }

    public static func inserting<T: Equatable>(_ item: T, into list: [T], limit: Int) -> [T] {
        inserting(item, into: list, limit: limit, same: ==)
    }
}
