import Foundation

/// Offline unit conversion for the converter widget.
///
/// Pure and here in the core so the maths is tested without the app. Every
/// linear unit is stored as its factor to the category's base unit (metres,
/// grams); temperature is the one category that is affine rather than linear,
/// so it goes through Celsius instead of a single factor.
///
/// Currency is deliberately absent: a rate that is out of date is worse than
/// no rate, and fetching one is a network service this widget does not need.
public enum UnitCategory: String, CaseIterable, Sendable {
    case length, weight, temperature

    public var title: String {
        switch self {
        case .length: "长度"
        case .weight: "重量"
        case .temperature: "温度"
        }
    }

    public var units: [ConversionUnit] {
        ConversionUnit.allCases.filter { $0.category == self }
    }

    /// The pair a fresh widget, or a category it has just switched to, shows.
    public var defaultPair: (from: ConversionUnit, to: ConversionUnit) {
        switch self {
        case .length: (.mile, .kilometre)
        case .weight: (.pound, .kilogram)
        case .temperature: (.fahrenheit, .celsius)
        }
    }
}

public enum ConversionUnit: String, CaseIterable, Sendable {
    // Length, base: metre.
    case millimetre = "mm", centimetre = "cm", metre = "m", kilometre = "km"
    case inch = "in", foot = "ft", yard = "yd", mile = "mi"
    // Weight, base: gram.
    case milligram = "mg", gram = "g", kilogram = "kg", tonne = "t"
    case ounce = "oz", pound = "lb", jin = "jin"
    // Temperature.
    case celsius = "C", fahrenheit = "F", kelvin = "K"

    public var category: UnitCategory {
        switch self {
        case .millimetre, .centimetre, .metre, .kilometre, .inch, .foot, .yard, .mile: .length
        case .milligram, .gram, .kilogram, .tonne, .ounce, .pound, .jin: .weight
        case .celsius, .fahrenheit, .kelvin: .temperature
        }
    }

    /// Short mark for a chip.
    public var symbol: String {
        switch self {
        case .jin: "斤"
        case .celsius: "°C"
        case .fahrenheit: "°F"
        case .kelvin: "K"
        default: rawValue
        }
    }

    public var name: String {
        switch self {
        case .millimetre: "毫米"
        case .centimetre: "厘米"
        case .metre: "米"
        case .kilometre: "公里"
        case .inch: "英寸"
        case .foot: "英尺"
        case .yard: "码"
        case .mile: "英里"
        case .milligram: "毫克"
        case .gram: "克"
        case .kilogram: "千克"
        case .tonne: "吨"
        case .ounce: "盎司"
        case .pound: "磅"
        case .jin: "斤"
        case .celsius: "摄氏度"
        case .fahrenheit: "华氏度"
        case .kelvin: "开尔文"
        }
    }

    /// Factor to the base unit, for the linear categories.
    var factor: Double {
        switch self {
        case .millimetre: 0.001
        case .centimetre: 0.01
        case .metre: 1
        case .kilometre: 1000
        case .inch: 0.0254
        case .foot: 0.3048
        case .yard: 0.9144
        case .mile: 1609.344
        case .milligram: 0.001
        case .gram: 1
        case .kilogram: 1000
        case .tonne: 1_000_000
        case .ounce: 28.349523125
        case .pound: 453.59237
        case .jin: 500
        case .celsius, .fahrenheit, .kelvin: 1
        }
    }
}

public enum UnitConverter {
    /// `value` in `from`, expressed in `to`. Nil across categories: a metre
    /// has no weight, and guessing one would be a wrong answer shown as right.
    public static func convert(_ value: Double, from: ConversionUnit, to: ConversionUnit) -> Double? {
        guard from.category == to.category, value.isFinite else { return nil }
        if from == to { return value }
        if from.category == .temperature {
            let celsius: Double = switch from {
            case .fahrenheit: (value - 32) * 5 / 9
            case .kelvin: value - 273.15
            default: value
            }
            return switch to {
            case .fahrenheit: celsius * 9 / 5 + 32
            case .kelvin: celsius + 273.15
            default: celsius
            }
        }
        return value * from.factor / to.factor
    }

    /// At most six significant figures, no trailing zeros, no exponent for
    /// anything a person would type into a converter.
    public static func format(_ value: Double) -> String {
        guard value.isFinite else { return "-" }
        if value == 0 { return "0" }
        let magnitude = abs(value)
        if magnitude >= 1e12 || magnitude < 1e-6 {
            return String(format: "%.4g", value)
        }
        // Six significant figures, then trimmed.
        let digits = max(0, 5 - Int(floor(log10(magnitude))))
        var text = String(format: "%.\(min(digits, 8))f", value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text == "-0" ? "0" : text
    }

    /// Reads what someone typed: tolerant of spaces, a comma for the decimal
    /// point, and full-width digits from a Chinese input method.
    public static func parse(_ text: String) -> Double? {
        var cleaned = ""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0xFF10...0xFF19:
                cleaned.unicodeScalars.append(Unicode.Scalar(scalar.value - 0xFF10 + 0x30)!)
            case 0xFF0E, 0x3002: cleaned.append(".")
            case 0xFF0D: cleaned.append("-")
            default: cleaned.unicodeScalars.append(scalar)
            }
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite else { return nil }
        return value
    }
}
