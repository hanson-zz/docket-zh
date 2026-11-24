import Foundation

/// 扩展栏背景颜色（Pro）的六种颜色：给扩展栏底板染一层颜色。
///
/// `redPanda.hex` 等色值也被各处当品牌强调色用，不要改。
///
/// A thank-you for supporting Docket, unlocked from the sponsor window. It
/// is on the honour system on purpose: Docket is open source and has no
/// server, so any check could be built around, and pretending otherwise
/// would only inconvenience the people who did pay. Stored as a raw value in
/// `CustomDockSettings.shelfColor`, empty for none. A third kind of value,
/// `followWidgetsRaw`, follows 设置 ▸ 通用 ▸ 小组件默认外观; it is deliberately
/// not a case, so `allCases` stays the six colours (see `ShelfColorChoice`).
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

    /// 存储值“跟随小组件默认外观”。
    public static let followWidgetsRaw = "followWidgets"

    /// The stored value read back; nil for empty, unknown, or the follow value.
    public static func parse(_ raw: String) -> ShelfColor? {
        raw.isEmpty ? nil : ShelfColor(rawValue: raw)
    }
}

/// 设置 ▸ 扩展栏 ▸ 外观 ▸ 扩展栏背景颜色 选了什么：无、跟随小组件默认外观、或六色之一。
///
/// 存在 `CustomDockSettings.shelfColor`，字段含义不变：空串是无，六色存 rawValue，
/// 新增的跟随存 `ShelfColor.followWidgetsRaw`。旧存储值原样读回；认不出的当“无”。
///
/// 只管扩展栏底板。小组件的主题色只由小组件自己的配置和通用外观决定
/// （`WidgetTint.choice`），这里只读通用外观、从不写它。
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

    /// 设置里标题旁的状态：无 / 跟随默认 / 颜色名。
    public var statusTitle: String {
        switch self {
        case .plain: tr("无")
        case .followWidgets: tr("跟随默认")
        case .color(let color): color.title
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
    /// 跟随小组件默认外观时读通用外观（`global`，即 `WidgetTint.global`）的颜色：
    /// - 十五种预设、自定义取色：用那个颜色。
    /// - 跟随系统：系统强调色。
    /// - 默认：每种小组件用自己的主题色，没有一个统一的颜色可取，也用系统强调色，
    ///   和“跟随系统”一致，跟着用户在系统里选的颜色走。
    public func resolved(global: WidgetConfig) -> Resolved? {
        switch self {
        case .plain:
            return nil
        case .color(let color):
            return .hex(color.hex)
        case .followWidgets:
            switch WidgetTint.Choice(raw: global.string(WidgetTint.key)) {
            case .kindDefault, .system: return .systemAccent
            case .preset(let preset): return .hex(preset.hex)
            case .custom(let code): return .hex(code.hex)
            }
        }
    }
}
