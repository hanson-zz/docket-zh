import Foundation

/// Which picture the wallpaper widget moves to next.
///
/// Pure, so the wrap-around and the "random never repeats" rule can be tested
/// without touching anybody's desktop.
public enum WallpaperCycle {
    public enum Step: String, Sendable, CaseIterable {
        case previous, next, random
    }

    /// The index to show after `current` in a folder of `count` pictures.
    ///
    /// `current` is nil when the desktop shows something outside the folder;
    /// then "next" starts at the first picture and "previous" at the last.
    /// Random never lands on the picture already showing when there is any
    /// other to choose. `roll` is a number in 0..<1, passed in so the choice
    /// is reproducible.
    public static func index(after current: Int?, count: Int, step: Step, roll: Double) -> Int? {
        guard count > 0 else { return nil }
        let here = current.flatMap { (0..<count).contains($0) ? $0 : nil }
        switch step {
        case .next:
            guard let here else { return 0 }
            return (here + 1) % count
        case .previous:
            guard let here else { return count - 1 }
            return (here - 1 + count) % count
        case .random:
            let clamped = min(max(roll.isFinite ? roll : 0, 0), 0.999_999)
            guard let here, count > 1 else { return Int(clamped * Double(count)) }
            // Pick among the others, then step over the current one.
            let pick = Int(clamped * Double(count - 1))
            return pick >= here ? pick + 1 : pick
        }
    }
}
