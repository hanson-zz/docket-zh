import Foundation

// MARK: - 取色后拷贝的格式

/// 取色器取到颜色后自动拷贝成什么：HEX、rgb()、hsl() 或 SwiftUI 的 Color。
/// 存在取色器卡片的配置 `copyFormat` 里；认不出的按 HEX。
public enum ColorCopyFormat: String, CaseIterable, Sendable {
    case hex, rgb, hsl, swiftUI = "swiftui"

    public static let key = "copyFormat"
    public static let fallback = ColorCopyFormat.hex

    public init(stored raw: String) {
        self = ColorCopyFormat(rawValue: raw) ?? Self.fallback
    }

    public static func of(_ config: WidgetConfig) -> ColorCopyFormat {
        ColorCopyFormat(stored: config.string(key, default: fallback.rawValue))
    }

    /// 面板上的选项字：和代码里的写法一致，不翻译。
    public var title: String {
        switch self {
        case .hex: "HEX"
        case .rgb: "rgb()"
        case .hsl: "hsl()"
        case .swiftUI: "SwiftUI"
        }
    }
}

/// HEX 的写法：大写带 #、小写带 #、大写不带 #。存在 `hexStyle` 里；认不出的按大写。
public enum ColorHexStyle: String, CaseIterable, Sendable {
    case upper, lower, bare

    public static let key = "hexStyle"
    public static let fallback = ColorHexStyle.upper

    public init(stored raw: String) {
        self = ColorHexStyle(rawValue: raw) ?? Self.fallback
    }

    public static func of(_ config: WidgetConfig) -> ColorHexStyle {
        ColorHexStyle(stored: config.string(key, default: fallback.rawValue))
    }

    /// 选项上直接写出样子。
    public var sample: String {
        switch self {
        case .upper: "#FF8A6B"
        case .lower: "#ff8a6b"
        case .bare: "FF8A6B"
        }
    }

    public func apply(_ hex: String) -> String {
        switch self {
        case .upper: hex.uppercased()
        case .lower: hex.lowercased()
        case .bare: hex.uppercased().replacingOccurrences(of: "#", with: "")
        }
    }
}

/// 拷贝格式和 HEX 写法放在一起：卡片、面板和快速开关都按它拷贝。
public struct ColorCopyStyle: Equatable, Sendable {
    public var format: ColorCopyFormat
    public var hexStyle: ColorHexStyle

    public init(format: ColorCopyFormat = .hex, hexStyle: ColorHexStyle = .upper) {
        self.format = format
        self.hexStyle = hexStyle
    }

    public init(_ config: WidgetConfig) {
        self.init(format: .of(config), hexStyle: .of(config))
    }

    /// 快速开关里的取色按钮没有卡片配置可读，读取色器卡片最近一次同步过来的这份。
    public static let defaultsKey = "colorPicker.copyStyle"

    /// 存成 `格式,写法`，如 `rgb,upper`。
    public var stored: String { "\(format.rawValue),\(hexStyle.rawValue)" }

    public init(stored raw: String) {
        let parts = raw.split(separator: ",").map(String.init)
        self.init(format: ColorCopyFormat(stored: parts.first ?? ""),
                  hexStyle: ColorHexStyle(stored: parts.count > 1 ? parts[1] : ""))
    }

    public static func saved(in defaults: UserDefaults = .standard) -> ColorCopyStyle {
        ColorCopyStyle(stored: defaults.string(forKey: defaultsKey) ?? "")
    }

    public func save(in defaults: UserDefaults = .standard) {
        guard defaults.string(forKey: Self.defaultsKey) != stored else { return }
        defaults.set(stored, forKey: Self.defaultsKey)
    }

    public func text(_ code: ColorCode) -> String {
        code.text(format, hexStyle: hexStyle)
    }
}

extension ColorCode {
    /// `Color(red: 1.000, green: 0.541, blue: 0.420)`，粘进 SwiftUI 代码直接能用。
    public var swiftUI: String {
        String(format: "Color(red: %.3f, green: %.3f, blue: %.3f)", red, green, blue)
    }

    /// 按格式写出来。HEX 写法只管 HEX，其余格式不受影响。
    public func text(_ format: ColorCopyFormat, hexStyle: ColorHexStyle = .upper) -> String {
        switch format {
        case .hex: hexStyle.apply(hex)
        case .rgb: rgb
        case .hsl: hsl
        case .swiftUI: swiftUI
        }
    }
}

// MARK: - 我的色板

/// 收藏的颜色：取色器卡片、面板共用一份，存在 UserDefaults 里（逗号分隔的 HEX，
/// 收藏的先后顺序，先收藏的在前）。和最近历史不同，新取的颜色挤不掉它们，
/// 只有自己移出才会少。最多 `limit` 个，满了不再收。
public enum ColorPalette {
    public static let defaultsKey = "colorPicker.palette"
    public static let limit = 24
    /// 卡片配置：卡片上那排色块显示我的色板（色板空着时照旧显示最近）。
    public static let showKey = "showPalette"

    public static func decode(_ raw: String) -> [String] { ColorHistory.decode(raw) }

    public static func contains(_ code: ColorCode, in raw: String) -> Bool {
        decode(raw).contains(code.hex)
    }

    public static func isFull(_ raw: String) -> Bool { decode(raw).count >= limit }

    /// 收藏到最后。已经在里面或满了不动。
    public static func adding(_ code: ColorCode, to raw: String) -> String {
        var list = decode(raw)
        guard !list.contains(code.hex), list.count < limit else { return ColorHistory.encode(list) }
        list.append(code.hex)
        return ColorHistory.encode(list)
    }

    public static func removing(_ code: ColorCode, from raw: String) -> String {
        ColorHistory.encode(decode(raw).filter { $0 != code.hex })
    }

    /// 星标：在就移出，不在就收藏（满了不动）。
    public static func toggling(_ code: ColorCode, in raw: String) -> String {
        contains(code, in: raw) ? removing(code, from: raw) : adding(code, to: raw)
    }

    public static func colors(_ raw: String) -> [ColorCode] {
        Array(decode(raw).prefix(limit)).compactMap { ColorCode(hex: $0) }
    }
}

// MARK: - 删最近历史

extension ColorHistory {
    /// 删过或清空过一次后记成 true：以后不再把卡片配置里以前的旧颜色接在后面，
    /// 不然删掉的颜色会从旧列表里冒回来。删之前先把这张卡片的旧颜色并进共享历史，
    /// 所以除了删掉的那个，一个不少。
    public static let legacyRetiredKey = "colorPicker.legacyRetired"

    /// 卡片上显示的颜色，旧颜色退休后只看共享历史。
    public static func shown(shared: String, legacy: [String], retired: Bool,
                             limit: Int = limit) -> [ColorCode] {
        merged(shared: decode(shared), legacy: retired ? [] : legacy, limit: limit)
    }

    /// 删掉一个，返回新的存储字符串。旧颜色先并进来再删。
    public static func removing(_ code: ColorCode, from raw: String, legacy: [String] = [],
                                limit: Int = limit) -> String {
        let current = Array(decode(encode(decode(raw) + legacy)).prefix(max(0, limit)))
        return encode(current.filter { $0 != code.hex })
    }
}
