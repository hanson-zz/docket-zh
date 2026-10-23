import Foundation

/// 世界时钟扩展栏卡片放 2 到 3 个城市时，每城一格用哪种外观，存在 `look` 键。
///
/// - 普通：免费，新放的卡片默认。每城一格，普通液态玻璃底，字用浅色 / 深色语义色，
///   没有天空色、星星和地标线稿。
/// - 天空：Pro。每格底色是当地此刻的天空（清晨、白天、黄昏、夜里），夜里加星，
///   右下角地标线稿（`WorldClockSky`）。
///
/// 没存 `look` 的老卡片按天空读（2026-10-23 前的卡片就是天空格子），已解锁的照旧；
/// 没解锁时画成普通，不盖锁、不改写配置，解锁或试用后自动回到天空（和纪念日的
/// 玻璃沙漏、收音机皮肤一样）。
///
/// 只管扩展栏卡片的多城市格子。一个城市的卡片、面板城市卡、联系状态圆点、科普卡、
/// 菜单栏第二时区都和外观无关，一直免费。
public enum WorldClockLook: String, CaseIterable, Sendable {
    case plain
    case sky

    public static let key = "look"
    /// 没存 `look` 的老卡片按天空读，和目录默认值一致。
    public static let legacy: WorldClockLook = .sky
    /// 新放的世界时钟写进去的外观。
    public static let newWidget: WorldClockLook = .plain

    public var title: String {
        switch self {
        case .plain: tr("普通")
        case .sky: tr("天空")
        }
    }

    /// 只有天空是 Pro。
    public var isPro: Bool { self == .sky }

    /// 存着的外观，认不出的值按老卡片的天空读。
    public static func stored(_ config: WidgetConfig) -> WorldClockLook {
        WorldClockLook(rawValue: config.string(key, default: legacy.rawValue)) ?? legacy
    }

    /// 卡片上实际画哪种：没解锁时天空退回普通。
    public static func shown(config: WidgetConfig, unlocked: Bool) -> WorldClockLook {
        let look = stored(config)
        return look.isPro && !unlocked ? .plain : look
    }

    /// 外观选项只在卡片有多个城市时有意义（一个城市的卡片两种长得一样）。
    public static func applies(_ config: WidgetConfig) -> Bool {
        WorldClockList.tileCities(config).count > 1
    }
}
