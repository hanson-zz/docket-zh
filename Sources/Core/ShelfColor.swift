import Foundation

/// 原来的六种扩展栏底板配色（11-24 之前）。
///
/// 底板颜色现在用小组件同一套 15 种预设（`WidgetTint.Preset`，见
/// `ShelfColorChoice`）。这里只留两件事：旧配置里存的六色值读回时映射到最接近
/// 的预设（`legacyPreset`），以及 `redPanda.hex` 这些色值被各处当品牌强调色用，
/// 色值保持不变。
public enum ShelfColor: String, CaseIterable, Sendable, Identifiable {
    case redPanda, sakura, mint, ocean, galaxy, amber

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .redPanda: tr("小熊猫橙")
        case .sakura: tr("樱花粉")
        case .mint: tr("薄荷绿")
        case .ocean: tr("海盐蓝")
        case .galaxy: tr("星空紫")
        case .amber: tr("琥珀金")
        }
    }

    public var hex: String {
        switch self {
        case .redPanda: "#E8743B"
        case .sakura: "#F2A0B6"
        case .mint: "#4FC3A1"
        case .ocean: "#3A8EDB"
        case .galaxy: "#6E5BD8"
        case .amber: "#E2B13C"
        }
    }

    /// 旧的六色值换成最接近的小组件预设。
    public var legacyPreset: WidgetTint.Preset {
        switch self {
        case .redPanda: .orange
        case .sakura: .blush
        case .mint: .mint
        case .ocean: .blue
        case .galaxy: .purple
        case .amber: .amber
        }
    }

    /// 存储值“跟随小组件外观”。
    public static let followWidgetsRaw = "followWidgets"

    /// The stored value read back; nil for empty, unknown, or the follow value.
    public static func parse(_ raw: String) -> ShelfColor? {
        raw.isEmpty ? nil : ShelfColor(rawValue: raw)
    }
}

/// 设置 ▸ 扩展栏 ▸ 外观 ▸ 底板颜色（Pro）选了什么：无、跟随小组件外观、或小组件
/// 同一套 15 种预设之一。存在 `CustomDockSettings.shelfColor`：空串是无，
/// `followWidgetsRaw` 是跟随，预设存它的 rawValue。
///
/// 旧存储值兼容：原来六色的 rawValue 读回时映射到最接近的预设
/// （`ShelfColor.legacyPreset`）；`mint`、`amber` 两边同名，映射结果一样。认不出的当“无”。
///
/// Pro 是诚信制：码头开源、没有服务器，任何校验都能绕过，解锁判断在界面层。
public enum ShelfColorChoice: Equatable, Sendable {
    case plain
    case followWidgets
    case preset(WidgetTint.Preset)

    public init(raw: String) {
        if raw == ShelfColor.followWidgetsRaw {
            self = .followWidgets
        } else if let preset = WidgetTint.Preset(rawValue: raw) {
            self = .preset(preset)
        } else if let legacy = ShelfColor.parse(raw) {
            self = .preset(legacy.legacyPreset)
        } else {
            self = .plain
        }
    }

    public var raw: String {
        switch self {
        case .plain: ""
        case .followWidgets: ShelfColor.followWidgetsRaw
        case .preset(let preset): preset.rawValue
        }
    }

    /// 底板最终用什么颜色。
    public enum Resolved: Equatable, Sendable {
        /// `#RRGGBB`。
        case hex(String)
        /// 用系统强调色，由界面层取（Core 拿不到 NSColor）。
        case systemAccent
    }

    /// 落到具体颜色；“无”是 nil。
    ///
    /// 跟随小组件外观时读通用外观（`global`，即 `WidgetTint.global`）的颜色：
    /// - 十五种预设、自定义取色：用那个颜色。自定义取色本身是 Pro，底板颜色也
    ///   只在解锁时生效，所以这里不再退回默认。
    /// - 跟随系统：用系统强调色，和小组件一样。
    /// - 默认：每种小组件的默认颜色各不相同，没有一个“小组件外观的颜色”可取，
    ///   这时用码头的品牌色小熊猫橙（`ShelfColor.redPanda`）。
    public func resolved(global: WidgetConfig) -> Resolved? {
        switch self {
        case .plain:
            return nil
        case .preset(let preset):
            return .hex(preset.hex)
        case .followWidgets:
            switch WidgetTint.Choice(raw: global.string(WidgetTint.key)) {
            case .kindDefault: return .hex(ShelfColor.redPanda.hex)
            case .system: return .systemAccent
            case .preset(let preset): return .hex(preset.hex)
            case .custom(let code): return .hex(code.hex)
            }
        }
    }
}
