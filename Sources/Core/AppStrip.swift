import Foundation

/// How a row of running apps fits a card of fixed size.
///
/// When everything fits, everything shows. When it does not, the last slot
/// becomes a "+n" marker for the rest rather than an icon cut in half, so the
/// card never claims to be the whole list when it is not.
public enum AppStrip {
    public struct Fit: Equatable, Sendable {
        public var shown: Int
        public var overflow: Int
    }

    public static func fit(total: Int, capacity: Int) -> Fit {
        let total = max(0, total)
        let capacity = max(1, capacity)
        guard total > capacity else { return Fit(shown: total, overflow: 0) }
        return Fit(shown: capacity - 1, overflow: total - (capacity - 1))
    }

    /// The frontmost app first, the rest in the order they were launched, so
    /// what you are using is always on the card.
    public static func ordered<T>(_ apps: [T], isActive: (T) -> Bool) -> [T] {
        apps.filter(isActive) + apps.filter { !isActive($0) }
    }
}
