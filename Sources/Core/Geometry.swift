import Foundation

/// Layout maths for the Docket shelf.
///
/// These formulas are the load-bearing part of the whole product: every tile
/// size, gap, corner radius and drag gesture derives from them. They are
/// deliberately written as free functions so they stay trivially testable and
/// have no dependency on AppKit.
public enum Geometry {

    // MARK: Scale

    public static let scaleRange: ClosedRange<Double> = 0.25...1.5
    public static let defaultScale: Double = 0.35

    /// Widget content grows at double rate below 50%, half rate above.
    ///
    /// The two branches meet at `s == 0.5` (both give `1.0`), so the curve is
    /// continuous. Below 50% the shelf is small enough that linear scaling
    /// would make widget text unreadable, hence the steeper slope.
    public static func contentScale(_ s: Double) -> Double {
        s < 0.5 ? 2 * s : 0.75 + 0.5 * s
    }

    // MARK: Icon geometry (native points)

    public struct IconGeometry: Equatable, Sendable {
        public var width, height, icon, dot, dotOffset, dotBottom, factor: Double
    }

    /// - Parameter hasWidgets: shelves holding only app icons scale linearly;
    ///   once a widget is present everything follows `contentScale` so icons
    ///   and tiles stay in proportion.
    public static func iconGeometry(scale: Double, vertical: Bool, hasWidgets: Bool = true) -> IconGeometry {
        let f = hasWidgets ? contentScale(scale) : scale
        return IconGeometry(
            width: (vertical ? 62 : 50) * f,
            height: (vertical ? 50 : 62) * f,
            icon: 48 * f,
            dot: 4 * f,
            dotOffset: 28 * f,
            dotBottom: 24 * f,
            factor: f
        )
    }

    /// Cross-axis extent of a widget tile: 62pt tall on a top or bottom
    /// shelf, 76pt wide on a side shelf.
    public static func widgetCross(_ position: DockPosition) -> Double {
        position.isHorizontal ? 62 : 76
    }

    // MARK: Spacers

    /// Length along the shelf of a spacer item.
    ///
    /// A regular spacer is one tile, as in Apple's Dock. A small one used to
    /// be half a tile, which with a gap on each side opened a hole about
    /// three times the gap between any other two items, and it is what the
    /// default layout puts between the apps and the widgets. Now it is one
    /// gap, so the seam reads as a slightly wider gap rather than a missing
    /// item.
    public static func spacerLength(_ size: SpacerSize, tile: Double, itemGap: Double) -> Double {
        size == .small ? itemGap : tile
    }

    // MARK: Chrome

    public struct Chrome: Equatable, Sendable {
        public var padding, radius, itemGap, adjacentGap: Double
        public var gripLong, gripShort, gripCross: Double
    }

    public static func chrome(scale: Double) -> Chrome {
        let inverse = 1 / min(1, scale)
        return Chrome(
            padding: (8 + 2 * inverse) * scale,
            radius: 22 / clamp(scale, 0.5, 1) * scale,
            itemGap: 4 * scale * inverse,
            // Widgets sit flush against their neighbours; the negative gap
            // closes the hairline the tile's own inset would otherwise leave.
            adjacentGap: -scale * inverse,
            gripLong: 28 * scale.squareRoot(),
            gripShort: 4 * scale.squareRoot(),
            // Grips stop shrinking below 50% or they become untargetable.
            gripCross: max(52 * scale, 28)
        )
    }

    // MARK: Drag resize

    /// Inverse of the tile-extent function: given a drag delta in points,
    /// returns the scale that makes the shelf exactly that much bigger.
    ///
    /// The two branches mirror `contentScale`'s two branches - collapsing this
    /// into a single linear map is the obvious "simplification" and it makes
    /// the grip feel wrong below 50%, which is exactly where users drag.
    public static func resizedScale(_ scale: Double, delta: Double,
                                    position: DockPosition, hasWidgets: Bool = true) -> Double {
        guard hasWidgets else {
            return clamp(scale + delta / (position.isHorizontal ? 86 : 112), scaleRange)
        }
        let cross = widgetCross(position)
        let extent = cross * contentScale(scale) + 24 * scale + delta
        let s = extent < cross + 12
            ? extent / (2 * cross + 24)
            : (extent - 0.75 * cross) / (0.5 * cross + 24)
        return clamp(s, scaleRange)
    }

    /// Sign of the drag delta differs per edge: dragging *away* from the
    /// screen edge always grows the shelf.
    public static func resizeDelta(from start: CGPoint, to point: CGPoint, position: DockPosition) -> Double {
        switch position {
        // `start` and `point` come from a global SwiftUI drag, where y runs
        // down the screen: away from the bottom edge is up, away from the
        // top edge is down.
        case .bottom: return start.y - point.y
        case .top: return point.y - start.y
        case .right: return start.x - point.x
        case .left: return point.x - start.x
        }
    }

    // MARK: Magnification

    /// Raised-cosine falloff: 1.0 at the pointer, 0 at `radius`, with zero
    /// slope at both ends so there is no visible seam where it cuts off.
    public static func influence(distance: Double, radius: Double) -> Double {
        distance >= radius ? 0 : (1 + cos(.pi * distance / radius)) / 2
    }

    public static let magnificationRadius: Double = 110
    public static let magnificationPeak: Double = 0.35
    /// Widget tiles are large already; the app-icon peak looks cartoonish on them.
    public static let widgetMagnificationPeak: Double = 0.20

    /// Critically-ish damped spring, integrated explicitly.
    /// - Parameter seconds: caller must clamp to <= 0.032 so a dropped frame
    ///   cannot blow the integrator up.
    public static func springStep(value: Double, velocity: Double,
                                  target: Double, seconds: Double) -> (value: Double, velocity: Double) {
        let nextVelocity = velocity + (420 * (target - value) - 41 * velocity) * seconds
        return (value + nextVelocity * seconds, nextVelocity)
    }

    public static let maxStep: Double = 0.032

    // MARK: Reorder

    /// Index an item dragged to `position` should occupy, given the current
    /// item centres. Walks only in the direction of travel so an item cannot
    /// jump past a neighbour it has not actually crossed.
    public static func reorderIndex(centers: [Double], from: Int, position: Double, direction: Double) -> Int {
        var to = from
        if direction > 0 { while to < centers.count - 1 && position >= centers[to + 1] { to += 1 } }
        if direction < 0 { while to > 0 && position <= centers[to - 1] { to -= 1 } }
        return to
    }

    // MARK: Placement on screen
    //
    // Everything below works in AppKit screen coordinates: y runs up from the
    // bottom of the main display, so the top of a screen is its `maxY`.

    /// The highest a top shelf may reach on a screen.
    ///
    /// Normally the top of `visibleFrame`, which is the underside of the menu
    /// bar (and on a notched display already accounts for the notch). When
    /// the menu bar hides itself `visibleFrame` runs to the bezel, and a shelf
    /// up there would cover the menu bar the moment it slides in, so the
    /// menu bar's own height is kept clear regardless.
    ///
    /// - Parameters:
    ///   - frameMaxY: top of the screen's full frame.
    ///   - visibleMaxY: top of the screen's `visibleFrame`.
    ///   - menuBarHeight: the menu bar's thickness on that screen.
    public static func topCeiling(frameMaxY: CGFloat, visibleMaxY: CGFloat,
                                  menuBarHeight: CGFloat) -> CGFloat {
        min(visibleMaxY, frameMaxY - max(0, menuBarHeight))
    }

    /// Where a shelf of `size` sits when shown, inside `bounds`, `inset`
    /// points in from its edge and centred along it.
    ///
    /// `bounds` is the usable area: for a top shelf its `maxY` must already
    /// be the underside of the menu bar (see `topCeiling`). The result is
    /// clamped so a shelf larger than the screen never hangs off it.
    public static func shelfOrigin(edge: DockPosition, size: CGSize,
                                   bounds: CGRect, inset: CGFloat) -> CGPoint {
        let origin: CGPoint = switch edge {
        case .bottom: CGPoint(x: bounds.midX - size.width / 2, y: bounds.minY + inset)
        case .top: CGPoint(x: bounds.midX - size.width / 2, y: bounds.maxY - size.height - inset)
        case .left: CGPoint(x: bounds.minX + inset, y: bounds.midY - size.height / 2)
        case .right: CGPoint(x: bounds.maxX - size.width - inset, y: bounds.midY - size.height / 2)
        }
        return CGPoint(
            x: min(max(origin.x, bounds.minX), max(bounds.minX, bounds.maxX - size.width)),
            y: min(max(origin.y, bounds.minY), max(bounds.minY, bounds.maxY - size.height))
        )
    }

    /// Where an auto-hidden shelf waits: off its edge of `screen`, with
    /// `peek` points left showing as a handle. Only the cross axis moves, so
    /// the shelf slides straight out and back in.
    ///
    /// A top shelf leaves past the bezel rather than tucking under the menu
    /// bar, because the menu bar is translucent and a shelf parked behind it
    /// would show through.
    public static func hiddenShelfOrigin(edge: DockPosition, shown: CGPoint, size: CGSize,
                                         screen: CGRect, peek: CGFloat) -> CGPoint {
        switch edge {
        case .bottom: CGPoint(x: shown.x, y: screen.minY - size.height + peek)
        case .top: CGPoint(x: shown.x, y: screen.maxY - peek)
        case .left: CGPoint(x: screen.minX - size.width + peek, y: shown.y)
        case .right: CGPoint(x: screen.maxX - peek, y: shown.y)
        }
    }

    /// The strip that brings a hidden shelf back, spanning the shelf's extent.
    ///
    /// On the bottom and the sides it runs along the bezel. On the top the
    /// bezel belongs to the menu bar, which reveals itself from there when it
    /// auto-hides, so the strip is a narrow band hanging just below `ceiling`
    /// (see `topCeiling`) instead.
    public static func revealZone(edge: DockPosition, shelf: CGRect, screen: CGRect,
                                  ceiling: CGFloat, depth: CGFloat) -> CGRect {
        switch edge {
        case .bottom:
            CGRect(x: shelf.minX, y: screen.minY, width: shelf.width, height: depth)
        case .top:
            CGRect(x: shelf.minX, y: ceiling - depth, width: shelf.width, height: depth)
        case .left:
            CGRect(x: screen.minX, y: shelf.minY, width: depth, height: shelf.height)
        case .right:
            CGRect(x: screen.maxX - depth, y: shelf.minY, width: depth, height: shelf.height)
        }
    }

    /// Origin of a popup of `size` (hover label, group sheet, widget panel)
    /// opened from a tile, `gap` points from `anchor` on the shelf's open
    /// side: above a bottom shelf, below a top one, beside a side one.
    ///
    /// `anchor` is the point on the tile's outer edge the popup grows from.
    public static func popupOrigin(edge: DockPosition, anchor: CGPoint,
                                   size: CGSize, gap: CGFloat) -> CGPoint {
        switch edge {
        case .bottom: CGPoint(x: anchor.x - size.width / 2, y: anchor.y + gap)
        case .top: CGPoint(x: anchor.x - size.width / 2, y: anchor.y - size.height - gap)
        case .left: CGPoint(x: anchor.x + gap, y: anchor.y - size.height / 2)
        case .right: CGPoint(x: anchor.x - size.width - gap, y: anchor.y - size.height / 2)
        }
    }

    /// Origin of a popup centred beside the whole shelf, on its open side.
    public static func besideShelfOrigin(edge: DockPosition, shelf: CGRect,
                                         size: CGSize, gap: CGFloat) -> CGPoint {
        switch edge {
        case .bottom: CGPoint(x: shelf.midX - size.width / 2, y: shelf.maxY + gap)
        case .top: CGPoint(x: shelf.midX - size.width / 2, y: shelf.minY - size.height - gap)
        case .left: CGPoint(x: shelf.maxX + gap, y: shelf.midY - size.height / 2)
        case .right: CGPoint(x: shelf.minX - size.width - gap, y: shelf.midY - size.height / 2)
        }
    }

    /// How far a popup's tail has to reach from the popup's middle to point
    /// at `anchor`, once clamping has moved the popup to `placed`.
    ///
    /// Measured in the popup's own SwiftUI space, where y runs down, so the
    /// sign flips against screen coordinates on a side shelf.
    public static func popupTailOffset(edge: DockPosition, anchor: CGPoint,
                                       placed: CGPoint, size: CGSize) -> CGFloat {
        switch edge {
        case .bottom, .top: anchor.x - (placed.x + size.width / 2)
        case .left, .right: (placed.y + size.height / 2) - anchor.y
        }
    }

    // MARK: Helpers

    public static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        min(max(v, lo), hi)
    }

    public static func clamp(_ v: Double, _ range: ClosedRange<Double>) -> Double {
        min(max(v, range.lowerBound), range.upperBound)
    }
}
