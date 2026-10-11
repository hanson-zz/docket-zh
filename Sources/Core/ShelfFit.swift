import Foundation

/// What the shelf does when its contents are longer than the screen.
public enum ShelfOverflow: String, Codable, Sendable, CaseIterable {
    /// Keep the size and scroll along the shelf. What it always did.
    case scroll
    /// Draw everything smaller until it fits, down to `ShelfFit.minimum`.
    case shrink
}

extension ShelfOverflow: LenientChoice { public static var fallback: Self { .scroll } }

/// The size a shelf is drawn at so that it fits.
public enum ShelfFit {
    /// Never smaller than this share of the size the user chose, and never
    /// below the smallest size the slider allows. Below roughly half, widget
    /// text stops being readable, and scrolling is the better answer.
    public static let minimumShare = 0.5

    public static func minimum(for base: Double) -> Double {
        max(Geometry.scaleRange.lowerBound, base * minimumShare)
    }

    /// The largest scale, at most `base`, at which `length(scale)` fits in
    /// `available`.
    ///
    /// `length` must grow with scale, which every shelf measurement does.
    /// When even the minimum does not fit, the minimum is returned and the
    /// shelf scrolls the rest, so shrinking never hides anything.
    public static func fittedScale(base: Double, available: Double,
                                   length: (Double) -> Double) -> Double {
        guard available > 0, length(base) > available else { return base }
        let floor = minimum(for: base)
        guard floor < base else { return base }
        if length(floor) >= available { return floor }
        var low = floor, high = base
        // Twenty halvings of a range under 1.5 is far below a visible point.
        for _ in 0 ..< 20 {
            let mid = (low + high) / 2
            if length(mid) <= available { low = mid } else { high = mid }
        }
        return low
    }
}
