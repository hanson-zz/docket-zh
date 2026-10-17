import Foundation

/// Pro 专属配色：给扩展栏底板染一层颜色。
///
/// A thank-you for supporting Docket, unlocked from the sponsor window. It
/// is on the honour system on purpose: Docket is open source and has no
/// server, so any check could be built around, and pretending otherwise
/// would only inconvenience the people who did pay. Stored as a raw value in
/// `CustomDockSettings.shelfColor`, empty for none.
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
