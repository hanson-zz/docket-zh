import AppKit
import SwiftUI
import XCTest


final class GeometryTests: XCTestCase {

    // MARK: contentScale

    func testContentScaleIsContinuousAtTheBranchPoint() {
        // The two branches must meet exactly, or the shelf visibly jumps when
        // the size slider crosses 50%.
        XCTAssertEqual(Geometry.contentScale(0.5), 1.0, accuracy: 1e-12)
        let below = Geometry.contentScale(0.5 - 1e-9)
        let above = Geometry.contentScale(0.5 + 1e-9)
        XCTAssertEqual(below, above, accuracy: 1e-6)
    }

    func testContentScaleIsMonotonic() {
        var previous = -Double.infinity
        for step in 0...125 {
            let value = Geometry.contentScale(0.25 + Double(step) * 0.01)
            XCTAssertGreaterThan(value, previous)
            previous = value
        }
    }

    // MARK: resizedScale

    func testResizeWithNoDeltaIsAFixedPoint() {
        // Grabbing the grip and not moving must not resize the shelf.
        for position in DockPosition.allCases {
            for scale in stride(from: 0.25, through: 1.5, by: 0.05) {
                let result = Geometry.resizedScale(scale, delta: 0, position: position)
                XCTAssertEqual(result, scale, accuracy: 1e-9,
                               "\(position) @ \(scale) drifted to \(result)")
            }
        }
    }

    func testResizeIsInvertibleAcrossTheBranchPoint() {
        // Drag out by n points then back by n and you must land where you
        // started - including across the 50% branch, which is exactly where a
        // naive linear map breaks.
        for position in DockPosition.allCases {
            for start in [0.3, 0.45, 0.5, 0.55, 0.9, 1.4] {
                for delta in [-20.0, -5.0, 5.0, 20.0] {
                    let out = Geometry.resizedScale(start, delta: delta, position: position)
                    guard Geometry.scaleRange.contains(out),
                          out > Geometry.scaleRange.lowerBound,
                          out < Geometry.scaleRange.upperBound else { continue }
                    let back = Geometry.resizedScale(out, delta: -delta, position: position)
                    XCTAssertEqual(back, start, accuracy: 1e-6,
                                   "\(position) \(start) +\(delta) -> \(out) -> \(back)")
                }
            }
        }
    }

    func testResizeStaysInRange() {
        for position in DockPosition.allCases {
            XCTAssertEqual(Geometry.resizedScale(0.25, delta: -10_000, position: position), 0.25)
            XCTAssertEqual(Geometry.resizedScale(1.5, delta: 10_000, position: position), 1.5)
        }
    }

    func testResizeGrowsWhenDraggingAwayFromTheEdge() {
        for position in DockPosition.allCases {
            let bigger = Geometry.resizedScale(0.5, delta: 12, position: position)
            let smaller = Geometry.resizedScale(0.5, delta: -12, position: position)
            XCTAssertGreaterThan(bigger, 0.5)
            XCTAssertLessThan(smaller, 0.5)
        }
    }

    func testResizeDeltaSignPerEdge() {
        let start = CGPoint(x: 100, y: 100)
        // Dragging up grows a bottom shelf; left grows a right shelf; right grows a left shelf.
        XCTAssertGreaterThan(Geometry.resizeDelta(from: start, to: CGPoint(x: 100, y: 80), position: .bottom), 0)
        XCTAssertGreaterThan(Geometry.resizeDelta(from: start, to: CGPoint(x: 80, y: 100), position: .right), 0)
        XCTAssertGreaterThan(Geometry.resizeDelta(from: start, to: CGPoint(x: 120, y: 100), position: .left), 0)
    }

    // MARK: magnification

    func testInfluenceFalloff() {
        XCTAssertEqual(Geometry.influence(distance: 0, radius: 110), 1.0, accuracy: 1e-12)
        XCTAssertEqual(Geometry.influence(distance: 55, radius: 110), 0.5, accuracy: 1e-12)
        XCTAssertEqual(Geometry.influence(distance: 110, radius: 110), 0)
        XCTAssertEqual(Geometry.influence(distance: 400, radius: 110), 0)
    }

    func testInfluenceHasNoSeamAtTheRadius() {
        // Zero slope at the edge is the whole point of the raised cosine; a
        // discontinuity here shows up as a visible pop as the pointer leaves.
        let justInside = Geometry.influence(distance: 110 - 1e-6, radius: 110)
        XCTAssertEqual(justInside, 0, accuracy: 1e-10)
    }

    func testSpringSettlesOnTarget() {
        var value = 1.0, velocity = 0.0
        for _ in 0..<600 {
            (value, velocity) = Geometry.springStep(value: value, velocity: velocity,
                                                    target: 1.35, seconds: Geometry.maxStep)
        }
        XCTAssertEqual(value, 1.35, accuracy: 1e-3)
        XCTAssertEqual(velocity, 0, accuracy: 1e-3)
    }

    func testSpringIsStableAtTheStepCeiling() {
        // dt is clamped to maxStep precisely so a dropped frame cannot make
        // this explicit integrator diverge.
        var value = 1.0, velocity = 0.0
        for _ in 0..<2_000 {
            (value, velocity) = Geometry.springStep(value: value, velocity: velocity,
                                                    target: 1.2, seconds: Geometry.maxStep)
            XCTAssertTrue(value.isFinite && abs(value) < 10)
        }
    }

    // MARK: reorder

    func testReorderOnlyMovesInTheDirectionOfTravel() {
        let centers = [10.0, 30.0, 50.0, 70.0]
        XCTAssertEqual(Geometry.reorderIndex(centers: centers, from: 0, position: 55, direction: 1), 2)
        XCTAssertEqual(Geometry.reorderIndex(centers: centers, from: 3, position: 25, direction: -1), 1)
        // Travelling right must never shuffle an item leftwards.
        XCTAssertEqual(Geometry.reorderIndex(centers: centers, from: 2, position: 0, direction: 1), 2)
    }

    func testReorderStaysInBounds() {
        let centers = [10.0, 30.0, 50.0]
        XCTAssertEqual(Geometry.reorderIndex(centers: centers, from: 2, position: 9_999, direction: 1), 2)
        XCTAssertEqual(Geometry.reorderIndex(centers: centers, from: 0, position: -9_999, direction: -1), 0)
    }

    // MARK: chrome

    func testGripsStayTargetableWhenTiny() {
        // Below 50% the grip must stop shrinking or it becomes impossible to hit.
        XCTAssertEqual(Geometry.chrome(scale: 0.25).gripCross, 28)
        XCTAssertGreaterThan(Geometry.chrome(scale: 1.5).gripCross, 28)
    }

    func testChromeIsFiniteAcrossTheRange() {
        for step in 0...125 {
            let chrome = Geometry.chrome(scale: 0.25 + Double(step) * 0.01)
            for value in [chrome.padding, chrome.radius, chrome.itemGap,
                          chrome.adjacentGap, chrome.gripLong, chrome.gripShort, chrome.gripCross] {
                XCTAssertTrue(value.isFinite)
            }
        }
    }
}

final class WidgetCatalogTests: XCTestCase {

    func testEveryKindWithVariantsDeclaresTheDefaultAmongThem() {
        for entry in WidgetCatalog.entries where !entry.variants.isEmpty {
            let keys = Set(entry.variants.flatMap(\.overrides.keys))
            for key in keys {
                XCTAssertNotNil(entry.defaults[key],
                                "\(entry.kind) varies '\(key)' but has no default for it")
            }
        }
    }

    func testInstancesDoNotShareMutableDefaults() {
        guard var a = WidgetCatalog.make(.system), let b = WidgetCatalog.make(.system) else {
            return XCTFail("system widget missing from catalog")
        }
        a.config.set("metrics", .list([.string("cpu")]))
        XCTAssertEqual(b.config.strings("metrics"), ["cpu", "memory"],
                       "mutating one widget's config leaked into another")
    }

    func testCompactOnlyAppliesWhereSupported() {
        for entry in WidgetCatalog.entries where !entry.supportsCompact {
            guard var instance = WidgetCatalog.make(entry.kind) else { continue }
            instance.expanded = false
            XCTAssertEqual(WidgetCatalog.naturalSize(instance),
                           WidgetCatalog.naturalSize(WidgetCatalog.make(entry.kind)!),
                           "\(entry.kind) has no compact variant but collapsed anyway")
        }
    }

    func testBottomShelfOwnsTileHeight() {
        // On a bottom shelf the height is the cross axis and every widget is
        // the same strip, however tall the widget was drawn.
        let f = Geometry.contentScale(0.5)
        for entry in WidgetCatalog.entries {
            guard let instance = WidgetCatalog.make(entry.kind) else { continue }
            XCTAssertEqual(WidgetCatalog.tileSize(instance, position: .bottom, scale: 0.5).height,
                           58 * f, accuracy: 1e-9, "\(entry.kind)")
        }
    }

    /// Cards are deliberately shorter than the icon tile that pins the plate.
    ///
    /// Matching it exactly is what made them read as oversized, and the plate
    /// cannot follow them down: its cross extent is a max over every slot, and
    /// app icons hold it at the icon tile height whatever the catalog says.
    func testWidgetCardsSitInsideTheIconTile() {
        let f = Geometry.contentScale(0.5)
        let tile = Geometry.iconGeometry(scale: 0.5, vertical: false).height
        for entry in WidgetCatalog.entries {
            guard let instance = WidgetCatalog.make(entry.kind) else { continue }
            let card = WidgetCatalog.tileSize(instance, position: .bottom, scale: 0.5).height
            XCTAssertLessThan(card, tile, "\(entry.kind) is not inside the plate")
            XCTAssertGreaterThan(card, 50 * f, "\(entry.kind) shrank too far to be readable")
        }
    }

    func testSideShelfKeepsWidgetsReadable() {
        // A side shelf must NOT squeeze widgets into the 76pt column that suits
        // app icons - doing so cropped two metrics into "1%7%". Height becomes
        // the long axis there, so tall layouts get the room they were drawn for.
        let f = Geometry.contentScale(0.5)
        for entry in WidgetCatalog.entries {
            guard let instance = WidgetCatalog.make(entry.kind) else { continue }
            let side = WidgetCatalog.tileSize(instance, position: .left, scale: 0.5)
            let content = WidgetCatalog.contentSize(instance, position: .left)
            XCTAssertEqual(side.width, content.width * f, accuracy: 1e-9, "\(entry.kind)")
            XCTAssertGreaterThanOrEqual(side.width, 76 * f - 1e-9,
                                        "\(entry.kind) is narrower than the icon column")
            XCTAssertGreaterThanOrEqual(side.height, 62 * f - 1e-9, "\(entry.kind)")
        }
    }

    func testSideShelfUsesThePurposeBuiltColumnHeight() {
        // A column layout is not the wide layout rotated: each kind declares
        // the height its stacked form actually needs.
        for entry in WidgetCatalog.entries {
            guard let instance = WidgetCatalog.make(entry.kind) else { continue }
            XCTAssertEqual(WidgetCatalog.contentSize(instance, position: .left).height,
                           WidgetCatalog.verticalHeight(instance), "\(entry.kind)")
            XCTAssertEqual(WidgetCatalog.contentSize(instance, position: .bottom).height, 58,
                           "\(entry.kind)")
            XCTAssertEqual(WidgetCatalog.contentSize(instance, position: .left).width,
                           WidgetCatalog.columnWidth, "\(entry.kind)")
        }
    }

    func testWidgetsNeedingRoomGetItInAColumn() {
        // Where a stacked layout genuinely needs more than the bottom shelf's
        // 62pt strip, the column must grant it.
        for kind in [WidgetKind.timer, .water, .notes, .clock] {
            guard let instance = WidgetCatalog.make(kind) else { continue }
            XCTAssertGreaterThan(WidgetCatalog.verticalHeight(instance), 62, "\(kind)")
        }
    }

    func testConfigMergePreservesUserValuesAndBackfillsNewKeys() {
        var saved = WidgetConfig(["layout": .string("rings")])
        saved = saved.merging(defaults: WidgetCatalog.entry(.system)!.defaults)
        XCTAssertEqual(saved.string("layout"), "rings")          // user's choice wins
        XCTAssertEqual(saved.strings("metrics"), ["cpu", "memory"]) // new key backfilled
    }
}

final class MagnificationTests: XCTestCase {

    private let lengths: [CGFloat] = [40, 40, 40, 134, 40, 40]
    private let peaks = [0.35, 0.35, 0.35, 0.20, 0.35, 0.35]
    private let gap: CGFloat = 2

    func testTheShelfGrowsOnlyAlongItsLength() {
        // Apple's Dock keeps its thickness and gets longer, so icons grow out
        // of the plate and push neighbours aside. Growing both axes inflates
        // the whole shelf on hover; growing neither forces every item to be
        // nudged by hand, which slides the row over a wide widget.
        let centers = DockMagnification.restCenters(lengths: lengths, gap: gap)
        for pointer in stride(from: 0.0, through: 340.0, by: 11.0) {
            let scales = DockMagnification.scales(pointer: CGFloat(pointer), centers: centers,
                                                  peaks: peaks, radius: 110)
            for scale in scales {
                XCTAssertGreaterThanOrEqual(scale, 1)
                XCTAssertLessThanOrEqual(scale, 1.36)
            }
        }
    }

    func testDistantItemsAreUntouched() {
        // The regression behind "hovering a widget shakes the whole dock":
        // anything beyond the falloff radius must not move at all.
        let centers = DockMagnification.restCenters(lengths: lengths, gap: gap)
        let scales = DockMagnification.scales(pointer: centers[0], centers: centers,
                                              peaks: peaks, radius: 110)
        for (index, centre) in centers.enumerated() where abs(centre - centers[0]) >= 110 {
            XCTAssertEqual(scales[index], 1, accuracy: 1e-12,
                           "item \(index) moved despite being out of range")
        }
    }

    func testPeakIsReachedOnlyUnderThePointer() {
        let centers = DockMagnification.restCenters(lengths: lengths, gap: gap)
        let scales = DockMagnification.scales(pointer: centers[1], centers: centers,
                                              peaks: peaks, radius: 110)
        XCTAssertEqual(scales[1], 1.35, accuracy: 1e-9)
        for (index, scale) in scales.enumerated() where index != 1 {
            XCTAssertLessThan(scale, scales[1])
        }
    }
}

extension MagnificationTests {

    /// The regression test for the shelf visibly shaking as the pointer swept
    /// across it: re-centring used to snap to the nearest item's offset, so
    /// every midpoint crossing moved the whole row in one discontinuous jump.
    func testScalesAreContinuousAcrossTheWholeSweep() {
        let centers = DockMagnification.restCenters(lengths: lengths, gap: gap)
        let total = (centers.last ?? 0) + 60

        var previous: [CGFloat]?
        var pointer: CGFloat = 0
        while pointer <= total {
            let scales = DockMagnification.scales(pointer: pointer, centers: centers,
                                                  peaks: peaks, radius: 110)
            if let previous {
                for (index, scale) in scales.enumerated() {
                    XCTAssertLessThan(abs(scale - previous[index]), 0.02,
                        "scale \(index) jumped at pointer \(pointer)")
                }
            }
            previous = scales
            pointer += 0.1
        }
    }

}

final class ReorderTests: XCTestCase {

    private func spacer(_ n: Int) -> DockItem {
        .spacer(id: UUID.stable(from: "s\(n)"), size: .regular)
    }

    private func widget(_ n: Int) -> DockItem {
        .widget(WidgetInstance(id: UUID.stable(from: "w\(n)"), kind: .clock, config: WidgetConfig()))
    }

    private var items: [DockItem] {
        [widget(1), spacer(1), widget(2), spacer(2), widget(3)]
    }

    func testReorderNeverLosesOrDuplicatesAnItem() {
        // The failure that matters: a drag must not be able to delete a
        // pinned item or clone it.
        let original = items
        let shuffled = original.map(\.id).reversed().map { $0 }
        let result = Reorder.apply(order: Array(shuffled), to: original)
        XCTAssertEqual(result.count, original.count)
        XCTAssertEqual(Set(result.map(\.id)), Set(original.map(\.id)))
    }

    func testReorderFollowsTheDisplayedOrder() {
        let original = items
        let wanted = [original[4].id, original[0].id, original[2].id, original[1].id, original[3].id]
        let result = Reorder.apply(order: wanted, to: original)
        XCTAssertEqual(result.map(\.id), wanted)
    }

    func testItemsNotOnScreenSurviveAReorder() {
        // While mirroring, the shelf shows only part of the profile. Anything
        // it was not showing must still be there afterwards.
        let original = items
        let partial = [original[3].id, original[1].id]
        let result = Reorder.apply(order: partial, to: original)
        XCTAssertEqual(result.count, original.count)
        XCTAssertEqual(result.prefix(2).map(\.id), partial)
        XCTAssertEqual(Set(result.map(\.id)), Set(original.map(\.id)))
    }

    func testUnknownIdsAreIgnored() {
        // Ids from the mirrored Dock are not in the profile; they must not
        // introduce phantom entries.
        let original = items
        let order = [UUID.stable(from: "ghost"), original[1].id]
        let result = Reorder.apply(order: order, to: original)
        XCTAssertEqual(result.count, original.count)
        XCTAssertEqual(result.first?.id, original[1].id)
    }

    func testEmptyOrderLeavesEverythingIntact() {
        let original = items
        XCTAssertEqual(Reorder.apply(order: [], to: original).map(\.id), original.map(\.id))
    }
}

final class LiveReorderTests: XCTestCase {

    private let gapSize: CGFloat = 42

    func testItemsBetweenTheOldAndNewSlotPartToMakeRoom() {
        // Dragging item 1 rightwards to slot 3: items 2 and 3 slide back by
        // one slot so the gap appears under the cursor.
        XCTAssertEqual(DockMagnification.gapShift(for: 2, from: 1, to: 3, gapSize: gapSize), -gapSize)
        XCTAssertEqual(DockMagnification.gapShift(for: 3, from: 1, to: 3, gapSize: gapSize), -gapSize)
        // Outside the span nothing moves.
        XCTAssertEqual(DockMagnification.gapShift(for: 0, from: 1, to: 3, gapSize: gapSize), 0)
        XCTAssertEqual(DockMagnification.gapShift(for: 4, from: 1, to: 3, gapSize: gapSize), 0)
    }

    func testDraggingBackwardsPartsTheOtherWay() {
        XCTAssertEqual(DockMagnification.gapShift(for: 2, from: 4, to: 2, gapSize: gapSize), gapSize)
        XCTAssertEqual(DockMagnification.gapShift(for: 3, from: 4, to: 2, gapSize: gapSize), gapSize)
        XCTAssertEqual(DockMagnification.gapShift(for: 1, from: 4, to: 2, gapSize: gapSize), 0)
        XCTAssertEqual(DockMagnification.gapShift(for: 5, from: 4, to: 2, gapSize: gapSize), 0)
    }

    func testNoMovementWhenTheSlotIsUnchanged() {
        for index in 0..<6 {
            XCTAssertEqual(DockMagnification.gapShift(for: index, from: 2, to: 2, gapSize: gapSize), 0)
        }
    }

    func testExactlyOneSlotOpensUp() {
        // The shifts must sum to exactly one slot's worth in the direction of
        // travel, or the row grows or collapses mid-drag.
        for (from, to) in [(0, 4), (4, 0), (1, 2), (2, 1)] {
            let total = (0..<5)
                .filter { $0 != from }
                .map { DockMagnification.gapShift(for: $0, from: from, to: to, gapSize: gapSize) }
                .reduce(0, +)
            let expected = CGFloat(abs(to - from)) * gapSize * (from < to ? -1 : 1)
            XCTAssertEqual(total, expected, accuracy: 1e-9, "from \(from) to \(to)")
        }
    }
}

extension MagnificationTests {

    /// Widgets must never magnify.
    ///
    /// Beyond matching the shipped behaviour, the geometry makes it necessary:
    /// a wide tile growing even slightly displaces far more of the shelf than
    /// an icon does, so hovering one shoves everything around it.
    func testAWidgetSizedTileNeverGrows() {
        let centers = DockMagnification.restCenters(lengths: lengths, gap: gap)
        let widget = 3                      // the 134pt tile
        var peaks = self.peaks
        peaks[widget] = 0                   // what the shelf now passes in

        var pointer: CGFloat = 0
        while pointer <= (centers.last ?? 0) + 60 {
            let scales = DockMagnification.scales(pointer: pointer, centers: centers,
                                                  peaks: peaks, radius: 110)
            XCTAssertEqual(scales[widget], 1, accuracy: 1e-12,
                           "widget grew at pointer \(pointer)")
            pointer += 2
        }
    }

    func testIconsStillMagnifyBesideAWidget() {
        // The fix must not quietly disable magnification for everything.
        let centers = DockMagnification.restCenters(lengths: lengths, gap: gap)
        var peaks = self.peaks
        peaks[3] = 0
        let scales = DockMagnification.scales(pointer: centers[4], centers: centers,
                                              peaks: peaks, radius: 110)
        XCTAssertEqual(scales[4], 1.35, accuracy: 1e-9)
        XCTAssertEqual(scales[3], 1, accuracy: 1e-12)
    }
}

extension WidgetCatalogTests {

    /// A widget saved before an option existed must still get that option's
    /// catalog default, not Swift's zero value.
    ///
    /// This is how browser support silently stayed off: the stored Now Playing
    /// widget had no `browsers` key, so `config.bool("browsers")` returned
    /// false rather than the catalog's true.
    func testOptionsAddedLaterFallBackToTheCatalog() {
        guard let entry = WidgetCatalog.entry(.music) else { return XCTFail("missing") }
        // A config from before `browsers` was introduced.
        let old = WidgetConfig(["spotify": .bool(true), "apple": .bool(true)])
        XCTAssertFalse(old.bool("browsers"), "precondition: the key is absent")

        let resolved = old.merging(defaults: entry.defaults)
        XCTAssertEqual(resolved.bool("browsers"), entry.defaults.bool("browsers"))
        // And the user's own choices must survive the merge untouched.
        XCTAssertTrue(resolved.bool("spotify"))
    }

    func testMergePreservesAnExplicitlyDisabledOption() {
        guard let entry = WidgetCatalog.entry(.music) else { return XCTFail("missing") }
        let off = WidgetConfig(["browsers": .bool(false)])
        XCTAssertFalse(off.merging(defaults: entry.defaults).bool("browsers"),
                       "a deliberate opt-out was overwritten by the default")
    }

    // MARK: PollGate

    func testPollGateRefusesWhileAProbeIsInFlight() {
        XCTAssertFalse(PollGate.shouldStart(inFlight: true, blocked: false,
                                            sinceLastStart: 99, interval: 1))
    }

    func testPollGateRefusesWhenBlocked() {
        XCTAssertFalse(PollGate.shouldStart(inFlight: false, blocked: true,
                                            sinceLastStart: 99, interval: 1))
    }

    func testPollGateThrottles() {
        XCTAssertFalse(PollGate.shouldStart(inFlight: false, blocked: false,
                                            sinceLastStart: 1, interval: 8))
    }

    /// The regression this type exists for.
    ///
    /// The timer ticks every second while the idle interval is eight, so a
    /// throttled tick is guaranteed one second after launch. Arming the
    /// in-flight flag before that check leaked it forever and the Now Playing
    /// widget froze for the life of the process. A refused tick must leave the
    /// gate exactly as it found it.
    func testAThrottledTickDoesNotPoisonTheNextEligibleOne() {
        XCTAssertFalse(PollGate.shouldStart(inFlight: false, blocked: false,
                                            sinceLastStart: 1, interval: 8))
        XCTAssertTrue(PollGate.shouldStart(inFlight: false, blocked: false,
                                           sinceLastStart: 8, interval: 8))
    }

    func testPollGateOpensExactlyAtTheInterval() {
        XCTAssertTrue(PollGate.shouldStart(inFlight: false, blocked: false,
                                           sinceLastStart: 0.85, interval: 0.85))
    }

    // MARK: Launch bounce

    private func bounceTimeline(peak: CGFloat) -> KeyframeTimeline<CGFloat> {
        KeyframeTimeline(initialValue: CGFloat.zero) {
            KeyframeTrack {
                LinearKeyframe(peak, duration: Bounce.arc / 2, timingCurve: Bounce.rise)
                LinearKeyframe(0, duration: Bounce.arc / 2, timingCurve: Bounce.fall)
            }
        }
    }

    /// The icon must never go below its resting place.
    ///
    /// A `CubicKeyframe` track sank it 0.43pt into the shelf on the way to the
    /// floor, because one C¹ curve through every control point cannot hold a
    /// cusp at the contact.
    func testTheBounceNeverSinksIntoTheShelf() {
        let timeline = bounceTimeline(peak: 46)
        for step in stride(from: 0.0, through: timeline.duration, by: 0.002) {
            XCTAssertGreaterThanOrEqual(timeline.value(time: step), -1e-6,
                                        "sank below rest at \(step)s")
        }
    }

    /// It leaves the shelf at speed rather than creeping off it.
    ///
    /// The cubic track had a start tangent of zero and covered 1.7% of the
    /// peak in its first 20ms; a real throw covers roughly 19%.
    func testTheBounceLeavesTheShelfFast() {
        // Measured as a fraction of the arc, not a fixed instant, so retuning
        // the duration cannot break a test about the curve's shape. A
        // constant-deceleration rise covers ~19% of the peak in the first
        // tenth of its climb; the cubic spline this replaced covered ~2%.
        let timeline = bounceTimeline(peak: 46)
        XCTAssertGreaterThan(timeline.value(time: Bounce.arc * 0.05), 46 * 0.08)
    }

    /// Velocity is zero at the apex and nowhere else.
    func testTheBouncePeaksOnceAtTheTop() {
        let timeline = bounceTimeline(peak: 46)
        let apex = timeline.value(time: Bounce.arc / 2)
        XCTAssertEqual(apex, 46, accuracy: 0.5)
        XCTAssertLessThan(timeline.value(time: Bounce.arc / 2 - 0.05), apex)
        XCTAssertLessThan(timeline.value(time: Bounce.arc / 2 + 0.05), apex)
    }

    /// Every arc is the same height: the Dock does not decay while an app is
    /// still starting up.
    func testTheBounceDoesNotDecay() {
        XCTAssertEqual(bounceTimeline(peak: 46).duration, Bounce.arc, accuracy: 1e-9)
    }

    // MARK: Scrolling

    /// A two-finger horizontal swipe drives a bottom shelf.
    func testHorizontalSwipeWins() {
        XCTAssertEqual(ScrollRelay.step(dx: -30, dy: 2, precise: true), -30, accuracy: 1e-9)
    }

    /// A mouse wheel only ever reports Y, and must still drive a bottom shelf.
    func testWheelDrivesTheShelfOnEitherAxis() {
        XCTAssertEqual(ScrollRelay.step(dx: 0, dy: 3, precise: false), 48, accuracy: 1e-9)
    }

    /// A notch is not a point: unscaled, one wheel click crept the shelf 1pt.
    func testNotchesAreScaledButTrackpadPointsAreNot() {
        XCTAssertEqual(ScrollRelay.step(dx: 1, dy: 0, precise: true), 1, accuracy: 1e-9)
        XCTAssertGreaterThan(ScrollRelay.step(dx: 1, dy: 0, precise: false), 8)
    }

    /// Direction must survive both the axis pick and the scaling, or the
    /// shelf runs the opposite way to the fingers.
    func testScrollKeepsItsSign() {
        XCTAssertLessThan(ScrollRelay.step(dx: -12, dy: 0, precise: true), 0)
        XCTAssertGreaterThan(ScrollRelay.step(dx: 12, dy: 0, precise: true), 0)
        XCTAssertLessThan(ScrollRelay.step(dx: 0, dy: -2, precise: false), 0)
    }

    func testAnIdleEventMovesNothing() {
        XCTAssertEqual(ScrollRelay.step(dx: 0, dy: 0, precise: true), 0, accuracy: 1e-9)
    }

    // MARK: Mirrored app list

    private func sampleApp(_ bundleID: String) -> DockItem {
        .app(id: UUID.stable(from: bundleID), bundleID: bundleID,
             ref: FileRef(url: URL(fileURLWithPath: "/Applications/\(bundleID).app")))
    }

    private func sampleWidget() -> DockItem? {
        WidgetCatalog.make(.clock).map { DockItem.widget($0) }
    }

    /// The trap that made "Remove from Dock" and "Keep in Dock" look dead.
    ///
    /// While mirroring, an app added to the profile is filtered straight back
    /// out and one removed from it is re-supplied by the Dock, so both edits
    /// are invisible. Editing has to stop mirroring first.
    func testMirroringHidesProfileAppEdits() {
        let mine = sampleApp("com.example.mine")
        let dock = [sampleApp("com.apple.Safari")]
        let shown = ShelfItems.displayed(profile: [mine], mirrored: dock, mirroring: true)
        XCTAssertFalse(shown.contains { $0.id == mine.id },
                       "a profile app must not survive mirroring - that is the trap")
        XCTAssertEqual(shown.map(\.id), dock.map(\.id))
    }

    func testTakingOwnershipMakesEditsVisible() {
        let mine = sampleApp("com.example.mine")
        let shown = ShelfItems.displayed(profile: [mine], mirrored: [sampleApp("com.apple.Safari")],
                                         mirroring: false)
        XCTAssertEqual(shown.map(\.id), [mine.id])
    }

    /// Non-app items are the whole point of the shelf, so they survive
    /// mirroring - and lead, so a long Dock cannot push them off-screen.
    func testWidgetsSurviveMirroringAndComeFirst() throws {
        let widget = try XCTUnwrap(sampleWidget())
        let dock = [sampleApp("com.apple.Safari")]
        let shown = ShelfItems.displayed(profile: [sampleApp("com.example.mine"), widget],
                                         mirrored: dock, mirroring: true)
        XCTAssertEqual(shown.map(\.id), [widget.id] + dock.map(\.id))
    }

    // MARK: Tile hit testing

    /// Delivers a real click to the centre of a tile-shaped hierarchy and
    /// reports how many taps the interior control actually received.
    @MainActor
    private func tapsReachingInterior(filled: Bool) -> Int {
        final class Box { var count = 0 }
        let box = Box()

        struct Probe: View {
            var filled: Bool
            var onTap: () -> Void
            var body: some View {
                Color.blue
                    .frame(width: 40, height: 40)
                    .contentShape(.rect)
                    .onTapGesture(perform: onTap)
                    .frame(width: 200, height: 60)
                    .modifier(TileHitShape(filled: filled))
            }
        }

        let frame = NSRect(x: 0, y: 0, width: 200, height: 60)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        let host = NSHostingView(rootView: Probe(filled: filled) { box.count += 1 })
        host.frame = frame
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))

        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(
                with: type, location: NSPoint(x: 100, y: 30), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1) {
                window.sendEvent(event)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.12))
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        window.orderOut(nil)
        return box.count
    }

    /// A widget's own controls must receive their own clicks.
    ///
    /// This broke twice and was twice cleared as "hit testing is fine", because
    /// the broken version reads as though it only empties the tile's own hit
    /// region. It does not: an empty content shape takes the entire subtree out
    /// of hit testing, so every control inside every widget was dead.
    @MainActor
    func testAWidgetsInteriorControlsAreClickable() {
        XCTAssertEqual(tapsReachingInterior(filled: false), 1)
    }

    /// And an icon tile, which wants the whole tile clickable, still is.
    @MainActor
    func testAnIconTileIsClickableAcrossItsWholeArea() {
        XCTAssertEqual(tapsReachingInterior(filled: true), 1)
    }

    // MARK: Widget click targets

    /// The ones the user names: battery opens Battery, clock opens Clock,
    /// CPU/memory open Activity Monitor.
    func testWidgetsOpenTheThingTheyReportOn() {
        XCTAssertEqual(WidgetCatalog.openTarget(.battery),
                       .settings("com.apple.Battery-Settings.extension"))
        XCTAssertEqual(WidgetCatalog.openTarget(.clock), .app(bundleID: "com.apple.clock"))
        XCTAssertEqual(WidgetCatalog.openTarget(.system),
                       .app(bundleID: "com.apple.ActivityMonitor"))
        XCTAssertEqual(WidgetCatalog.openTarget(.network),
                       .app(bundleID: "com.apple.ActivityMonitor"))
    }

    /// Every clock-family widget goes to the same place, so adding one to the
    /// enum without a destination is caught here rather than on the shelf.
    func testEveryClockKindHasADestination() {
        for kind in [WidgetKind.clock, .world, .alarm, .timer, .stopwatch, .countdown] {
            XCTAssertEqual(WidgetCatalog.openTarget(kind), .app(bundleID: "com.apple.clock"),
                           "\(kind)")
        }
    }

    /// A tile with no honest destination must report none - a tap gesture with
    /// a no-op action still consumes the click, which would eat the controls
    /// inside the card.
    func testSelfContainedWidgetsAdvertiseNoDestination() {
        for kind in [WidgetKind.music, .water, .progress] {
            XCTAssertNil(WidgetCatalog.openTarget(kind), "\(kind)")
        }
    }

    func testSettingsTargetsBuildADeepLink() {
        XCTAssertEqual(WidgetTarget.settings("com.apple.Battery-Settings.extension").settingsURL,
                       URL(string: "x-apple.systempreferences:com.apple.Battery-Settings.extension"))
        XCTAssertNil(WidgetTarget.app(bundleID: "com.apple.clock").settingsURL)
    }

    // MARK: Groups

    private func groupOf(_ count: Int) -> DockGroup {
        DockGroup(name: "Favorites", tint: .teal,
                  items: (0..<count).map { sampleApp("com.example.app\($0)") })
    }

    /// The closed tile is a 2×2 grid, so it can only ever show four.
    func testAClosedGroupShowsAtMostFour() {
        XCTAssertEqual(groupOf(2).preview.count, 2)
        XCTAssertEqual(groupOf(4).preview.count, 4)
        XCTAssertEqual(groupOf(9).preview.count, 4)
    }

    /// Nothing may be hidden silently: the last cell becomes a count.
    func testAGroupReportsWhatItIsNotShowing() {
        XCTAssertEqual(groupOf(4).hiddenCount, 0)
        XCTAssertEqual(groupOf(5).hiddenCount, 1)
        XCTAssertEqual(groupOf(9).hiddenCount, 5)
    }

    func testAGroupSurvivesACodableRoundTrip() throws {
        let item = DockItem.group(groupOf(3))
        let data = try JSONEncoder().encode(item)
        let back = try JSONDecoder().decode(DockItem.self, from: data)
        XCTAssertEqual(back, item)
        XCTAssertEqual(back.group?.name, "Favorites")
        XCTAssertEqual(back.group?.tint, .teal)
        XCTAssertEqual(back.id, item.id)
    }

    /// Adding a case must not break state written before it existed.
    func testStateWrittenBeforeGroupsExistedStillDecodes() throws {
        let legacy = Data("""
        {"app":{"id":"00000000-0000-0000-0000-000000000001",
                "bundleID":"com.apple.Safari",
                "ref":{"url":"file:///Applications/Safari.app"}}}
        """.utf8)
        let item = try JSONDecoder().decode(DockItem.self, from: legacy)
        XCTAssertNil(item.group)
    }

    /// A group is the user's own creation, so mirroring the real Dock's apps
    /// must never drop it.
    func testGroupsSurviveMirroring() {
        let group = DockItem.group(groupOf(3))
        let shown = ShelfItems.displayed(profile: [group, sampleApp("com.example.mine")],
                                         mirrored: [sampleApp("com.apple.Safari")],
                                         mirroring: true)
        XCTAssertTrue(shown.contains { $0.id == group.id })
    }

    /// Apple's Dock has no group tile, so there is nothing to mirror back.
    func testAGroupIsNotRepresentableInTheMacOSDock() {
        XCTAssertFalse(DockItem.group(groupOf(2)).isRepresentableInMacOSDock)
    }

    // MARK: Combining and dissolving

    /// Dropping one icon on another makes a group where the target already
    /// was, so the shelf does not reshuffle around the gesture.
    func testDroppingAnIconOnAnotherMakesAGroupInTheTargetsSlot() {
        let a = sampleApp("com.example.a")
        let b = sampleApp("com.example.b")
        let c = sampleApp("com.example.c")
        let out = ShelfItems.combining(c.id, into: b.id, named: "Work", in: [a, b, c])
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[0].id, a.id)
        let group = try? XCTUnwrap(out[1].group)
        XCTAssertEqual(group?.name, "Work")
        XCTAssertEqual(group?.items.map(\.id), [b.id, c.id])
    }

    /// Dropping onto a group joins it rather than nesting a second group.
    func testDroppingOntoAGroupJoinsIt() {
        let a = sampleApp("com.example.a")
        let group = DockItem.group(DockGroup(name: "Work", items: [sampleApp("com.example.b"),
                                                                   sampleApp("com.example.c")]))
        let out = ShelfItems.combining(a.id, into: group.id, named: "unused", in: [a, group])
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0].group?.items.count, 3)
        XCTAssertNil(out[0].group?.items.first { $0.group != nil }, "must not nest")
    }

    func testAnItemCannotBeDroppedOnItself() {
        let a = sampleApp("com.example.a")
        XCTAssertEqual(ShelfItems.combining(a.id, into: a.id, named: "x", in: [a]).count, 1)
    }

    /// Taking one out of a pair leaves a single icon, not a group of one.
    func testAGroupDownToOneDissolves() {
        let b = sampleApp("com.example.b")
        let c = sampleApp("com.example.c")
        let group = DockItem.group(DockGroup(name: "Work", items: [b, c]))
        let out = ShelfItems.removingFromGroup(c.id, group: group.id, in: [group])
        XCTAssertEqual(out.map(\.id), [b.id, c.id])
        XCTAssertNil(out.first { $0.group != nil }, "no group should survive with one item")
    }

    /// Taking one out of three leaves a group of two.
    func testAGroupOfThreeSurvivesLosingOne() {
        let items = (0..<3).map { sampleApp("com.example.app\($0)") }
        let group = DockItem.group(DockGroup(name: "Work", items: items))
        let out = ShelfItems.removingFromGroup(items[2].id, group: group.id, in: [group])
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[0].group?.items.count, 2)
        XCTAssertEqual(out[1].id, items[2].id, "the removed icon lands beside its group")
    }

    func testAnEmptyGroupDisappears() {
        let group = DockItem.group(DockGroup(name: "Empty", items: []))
        XCTAssertTrue(ShelfItems.dissolvingSmallGroups(in: [group]).isEmpty)
    }

    /// However a group of one came to exist - an older build, a restored
    /// backup - it must never reach the shelf.
    func testAGroupOfOneNeverRenders() {
        let inner = sampleApp("com.apple.Safari")
        let stray = DockItem.group(DockGroup(name: "New Group", items: [inner]))
        let shown = ShelfItems.displayed(profile: [stray], mirrored: [], mirroring: false)
        XCTAssertEqual(shown.map(\.id), [inner.id])
        XCTAssertNil(shown.first { $0.group != nil })
    }

    // MARK: Dragging out of a group

    private var sheet: CGSize { CGSize(width: 300, height: 120) }

    func testDraggingPastTheSheetEdgeLeavesTheGroup() {
        XCTAssertTrue(GroupDrag.leavesSheet(CGPoint(x: -1, y: 60), sheet: sheet))
        XCTAssertTrue(GroupDrag.leavesSheet(CGPoint(x: 301, y: 60), sheet: sheet))
        XCTAssertTrue(GroupDrag.leavesSheet(CGPoint(x: 150, y: -1), sheet: sheet))
        XCTAssertTrue(GroupDrag.leavesSheet(CGPoint(x: 150, y: 121), sheet: sheet))
    }

    func testDraggingWithinTheSheetKeepsTheIcon() {
        XCTAssertFalse(GroupDrag.leavesSheet(CGPoint(x: 0, y: 0), sheet: sheet))
        XCTAssertFalse(GroupDrag.leavesSheet(CGPoint(x: 150, y: 60), sheet: sheet))
        XCTAssertFalse(GroupDrag.leavesSheet(CGPoint(x: 300, y: 120), sheet: sheet))
    }

    /// Before the sheet has been measured, nothing may count as leaving it -
    /// a zero size would report every point as outside and throw the icon out
    /// on the very first drag event.
    func testAnUnmeasuredSheetNeverDropsAnIcon() {
        XCTAssertFalse(GroupDrag.leavesSheet(CGPoint(x: 40, y: 40), sheet: .zero))
    }

    /// An icon dragged out lands in the gap the shelf opened for it, not
    /// always beside the group it left.
    func testAnIconLeavingAGroupLandsWhereItWasDropped() {
        let a = sampleApp("com.example.a")
        let b = sampleApp("com.example.b")
        let inner = (0..<3).map { sampleApp("com.example.in\($0)") }
        let group = DockItem.group(DockGroup(name: "Work", items: inner))
        let items = [a, group, b]

        let front = ShelfItems.removingFromGroup(inner[0].id, group: group.id, in: items, at: 0)
        XCTAssertEqual(front.first?.id, inner[0].id)

        let back = ShelfItems.removingFromGroup(inner[0].id, group: group.id, in: items, at: 99)
        XCTAssertEqual(back.last?.id, inner[0].id, "an out-of-range drop clamps to the end")
    }

    /// With no destination it still lands somewhere predictable.
    func testALeavingIconWithoutADestinationLandsBesideItsGroup() {
        let inner = (0..<3).map { sampleApp("com.example.in\($0)") }
        let group = DockItem.group(DockGroup(name: "Work", items: inner))
        let out = ShelfItems.removingFromGroup(inner[1].id, group: group.id, in: [group])
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[1].id, inner[1].id)
    }

    // MARK: Resizing past a limit

    /// Driving the grip well past the maximum and then back by one step.
    ///
    /// `absolute` recomputes from where the drag began, which is how the grip
    /// used to work; `incremental` steps from the size it is now.
    private func resizeRun(absolute: Bool, steps: Int, step: Double) -> (atLimit: Double, afterReversing: Double) {
        let start = Geometry.defaultScale
        var scale = start
        var travelled = 0.0

        // A fixed number of events, so the sign of `step` cannot run away -
        // counting distance against a positive target loops forever when the
        // drag is towards the minimum.
        for _ in 0..<steps {
            travelled += step
            scale = absolute
                ? Geometry.resizedScale(start, delta: travelled, position: .bottom)
                : Geometry.resizedScale(scale, delta: step, position: .bottom)
        }
        let atLimit = scale

        // Now one step back the other way.
        travelled -= step
        scale = absolute
            ? Geometry.resizedScale(start, delta: travelled, position: .bottom)
            : Geometry.resizedScale(scale, delta: -step, position: .bottom)
        return (atLimit, scale)
    }

    /// Dragging back off a limit must be felt immediately.
    ///
    /// Recomputing the size from the drag's origin lets travel past the limit
    /// accumulate in a value nothing can see: overshoot the maximum by a long
    /// way and dragging back does nothing at all until every point of that
    /// overshoot has been undone, which reads as a grip that has stopped
    /// responding. Stepping from the current size cannot accumulate.
    func testDraggingBackFromTheMaximumRespondsAtOnce() {
        let run = resizeRun(absolute: false, steps: 50, step: 12)
        XCTAssertEqual(run.atLimit, Geometry.scaleRange.upperBound, accuracy: 1e-9)
        XCTAssertLessThan(run.afterReversing, run.atLimit,
                          "one step back should leave the limit straight away")
    }

    /// The same run the old way, which is the behaviour being guarded against.
    func testRecomputingFromTheDragsOriginStrandsItAtTheLimit() {
        let run = resizeRun(absolute: true, steps: 50, step: 12)
        XCTAssertEqual(run.atLimit, Geometry.scaleRange.upperBound, accuracy: 1e-9)
        XCTAssertEqual(run.afterReversing, run.atLimit, accuracy: 1e-9,
                       "this is the dead travel the incremental grip removes")
    }

    /// And the same at the bottom of the range.
    func testDraggingBackFromTheMinimumRespondsAtOnce() {
        let run = resizeRun(absolute: false, steps: 50, step: -12)
        XCTAssertEqual(run.atLimit, Geometry.scaleRange.lowerBound, accuracy: 1e-9)
        XCTAssertGreaterThan(run.afterReversing, run.atLimit)
    }

    /// Stepping never escapes the range, however far the drag goes.
    func testSteppingStaysInRange() {
        var scale = Geometry.defaultScale
        for step in stride(from: -40.0, through: 40.0, by: 7) {
            for _ in 0..<50 {
                scale = Geometry.resizedScale(scale, delta: step, position: .bottom)
                XCTAssertTrue(Geometry.scaleRange.contains(scale), "escaped at step \(step)")
            }
        }
    }

    func testSmallSpacerIsOneGapNotHalfATile() {
        let gap = Geometry.chrome(scale: 0.35).itemGap
        XCTAssertEqual(Geometry.spacerLength(.small, tile: 50, itemGap: gap), gap)
        XCTAssertEqual(Geometry.spacerLength(.regular, tile: 50, itemGap: gap), 50)
        XCTAssertLessThan(Geometry.spacerLength(.small, tile: 50, itemGap: gap), 25)
    }
}
