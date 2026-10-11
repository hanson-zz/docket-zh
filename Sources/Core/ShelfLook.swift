import Foundation

/// The shelf's look as one choice.
///
/// Stored as three settings (material, glass style and glass tint) because
/// that is what the renderer needs, and offered as one list because that is
/// what anyone is choosing between. This is the mapping both ways, kept pure
/// so the round trip can be tested without drawing anything.
public enum ShelfLook: String, CaseIterable, Sendable {
    case frosted
    case glass
    case clearGlass
    case lightGlass
    case darkGlass
    case white
    case black
    /// No plate. Every widget keeps its own card.
    case transparent

    /// Settings order: the materials that sample the desktop first, then the
    /// ones that pin a colour, then none at all.
    public static let ordered: [ShelfLook] = [
        .glass, .clearGlass, .lightGlass, .darkGlass, .frosted, .white, .black, .transparent,
    ]

    public var title: String {
        switch self {
        case .frosted: "磨砂"
        case .glass: "玻璃"
        case .clearGlass: "清透玻璃"
        case .lightGlass: "浅色玻璃"
        case .darkGlass: "深色玻璃"
        case .white: "白色"
        case .black: "黑色"
        case .transparent: "透明"
        }
    }

    /// The look the stored settings currently describe.
    ///
    /// The tint is only read for glass, so a frosted shelf that once had a
    /// tint chosen still reads as frosted.
    public init(_ settings: CustomDockSettings) {
        switch settings.material {
        case .frosted: self = .frosted
        case .solidLight: self = .white
        case .solidDark: self = .black
        case .plateless: self = .transparent
        case .liquidGlass:
            switch settings.glassTint {
            case .light: self = .lightGlass
            case .dark: self = .darkGlass
            case .automatic: self = settings.glass == .clear ? .clearGlass : .glass
            }
        }
    }

    /// Writes this look into the settings, leaving everything else alone.
    public func apply(to settings: inout CustomDockSettings) {
        switch self {
        case .frosted: settings.material = .frosted
        case .white: settings.material = .solidLight
        case .black: settings.material = .solidDark
        case .transparent: settings.material = .plateless
        case .glass, .clearGlass, .lightGlass, .darkGlass:
            settings.material = .liquidGlass
            settings.glass = self == .clearGlass ? .clear : .regular
            settings.glassTint = switch self {
            case .lightGlass: .light
            case .darkGlass: .dark
            default: .automatic
            }
        }
    }

    /// The appearance the shelf's own contents are drawn in, if the look
    /// pins one.
    ///
    /// A white plate needs dark ink whatever the system is set to, and a black
    /// one light ink; the same goes for glass that has been leaned light or
    /// dark. Nil means follow the system.
    public var forcedAppearance: AppAppearance? {
        switch self {
        case .white, .lightGlass: .light
        case .black, .darkGlass: .dark
        case .frosted, .glass, .clearGlass, .transparent: nil
        }
    }
}
