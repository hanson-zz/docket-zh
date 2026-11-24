import Foundation

/// 扩展栏底板颜色（Pro）：给扩展栏底板染一层颜色。
///
/// A thank-you for supporting Docket, unlocked from the sponsor window. It
/// is on the honour system on purpose: Docket is open source and has no
/// server, so any check could be built around, and pretending otherwise
/// would only inconvenience the people who did pay. Stored as a raw value in
/// `CustomDockSettings.shelfColor`, empty for none, or `followWidgetsRaw`
/// to take the colour from 设置 ▸ 通用 ▸ 小组件外观 (see `ShelfColorChoice`).
/// The follow value is deliberately not a case, so `allCases` stays the six
/// colours and the Pro style count does not move.
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

    /// 存储值“跟随小组件外观”。
    public static let followWidgetsRaw = "followWidgets"

    /// The stored value read back; nil for empty, unknown, or the follow value.
    public static func parse(_ raw: String) -> ShelfColor? {
        raw.isEmpty ? nil : ShelfColor(rawValue: raw)
    }
}

/// 底板颜色这一项选了什么：无、跟随小组件外观、或六色之一。
/// 旧存储值（空串、六色的 rawValue）原样读回；认不出的当“无”。
public enum ShelfColorChoice: Equatable, Sendable {
    case plain
    case followWidgets
    case color(ShelfColor)

    public init(raw: String) {
        if raw == ShelfColor.followWidgetsRaw {
            self = .followWidgets
        } else if let color = ShelfColor.parse(raw) {
            self = .color(color)
        } else {
            self = .plain
        }
    }

    public var raw: String {
        switch self {
        case .plain: ""
        case .followWidgets: ShelfColor.followWidgetsRaw
        case .color(let color): color.rawValue
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
    ///   这时用码头的品牌色小熊猫橙，和六色里的第一种一样。
    public func resolved(global: WidgetConfig) -> Resolved? {
        switch self {
        case .plain:
            return nil
        case .color(let color):
            return .hex(color.hex)
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
