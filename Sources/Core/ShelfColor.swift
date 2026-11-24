import Foundation

/// 原来的六种扩展栏底板配色（11-24 之前）。
///
/// 扩展栏不再单独选颜色，改成一个「底板染色」开关（`ShelfTint`），颜色取
/// 设置 ▸ 通用 ▸ 小组件外观。这里留着是因为 `redPanda.hex` 这些色值被各处当
/// 品牌强调色用，色值保持不变；旧配置里存的六色值读回时当作开关打开。
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

    /// The stored value read back; nil for empty or unknown.
    public static func parse(_ raw: String) -> ShelfColor? {
        raw.isEmpty ? nil : ShelfColor(rawValue: raw)
    }
}

/// 设置 ▸ 扩展栏 ▸ 外观 ▸ 底板染色（Pro）：用 设置 ▸ 通用 ▸ 小组件外观 的颜色
/// 给扩展栏底板染一层。
///
/// 存在原来的 `CustomDockSettings.shelfColor` 字段里，旧数据不用迁移：
/// 空串是关；非空是开。新写入的“开”是 `onRaw`，旧版存的六色值（`redPanda`、
/// `sakura`……）或任何认不出的非空值也都读作开，原来选过配色的人升级后底板
/// 照样有颜色，只是颜色改跟小组件外观。
///
/// Pro 是诚信制：码头开源、没有服务器，任何校验都能绕过，解锁判断在界面层。
public enum ShelfTint {
    /// 新写入的“开”。
    public static let onRaw = "followWidgets"

    public static func isOn(_ raw: String) -> Bool { !raw.isEmpty }

    public static func raw(on: Bool) -> String { on ? onRaw : "" }

    /// 底板最终用什么颜色。
    public enum Resolved: Equatable, Sendable {
        /// `#RRGGBB`。
        case hex(String)
        /// 用系统强调色，由界面层取（Core 拿不到 NSColor）。
        case systemAccent
    }

    /// 开着时的颜色，取通用小组件外观（`global`，即 `WidgetTint.global`）当前的颜色：
    /// - 十五种预设、自定义取色：用那个颜色。自定义取色本身是 Pro，染色也只在
    ///   解锁时生效，所以这里不再退回默认。
    /// - 跟随系统：系统强调色。
    /// - 默认：每种小组件的默认颜色各不相同，没有一个“小组件外观的颜色”可取，
    ///   也用系统强调色，和“跟随系统”一致，跟着用户在系统里选的颜色走。
    public static func color(global: WidgetConfig) -> Resolved {
        switch WidgetTint.Choice(raw: global.string(WidgetTint.key)) {
        case .kindDefault, .system: return .systemAccent
        case .preset(let preset): return .hex(preset.hex)
        case .custom(let code): return .hex(code.hex)
        }
    }
}
