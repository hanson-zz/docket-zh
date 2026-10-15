import Observation

/// Whether the shelf's cards are actually on screen: the window is ordered
/// in, not slid off the edge by auto-hide, and not covered.
///
/// Animated cards (the 电池 looks) read this to stop drawing frames nobody
/// can see. `DockPanelController` keeps it current. It starts true so a card
/// hosted anywhere else is never frozen by a shelf it does not live in.
@MainActor @Observable
final class ShelfVisibility {
    static let shared = ShelfVisibility()

    private(set) var cardsOnScreen = true

    private init() {}

    func update(_ shown: Bool) {
        if shown != cardsOnScreen { cardsOnScreen = shown }
    }
}
