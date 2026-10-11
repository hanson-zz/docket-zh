import Foundation
import XCTest
@testable import Docket

// Pure logic behind the v0.4.1 additions: per-widget visibility, fitting the
// shelf by shrinking, the stand-up reminder's schedule and the ring gauges.

final class WidgetPlateTests: XCTestCase {
    func testPlateIsShownByDefaultAndToggles() {
        let clock = WidgetCatalog.make(.clock)!
        XCTAssertFalse(WidgetPlate.isHidden(clock.config))
        let bare = WidgetPlate.toggled(clock)
        XCTAssertTrue(WidgetPlate.isHidden(bare.config))
        XCTAssertEqual(bare.id, clock.id)
        XCTAssertFalse(WidgetPlate.isHidden(WidgetPlate.toggled(bare).config))
    }

    /// Not a catalog default, so it is never offered as a generic option
    /// beside the widget's own settings.
    func testPlateIsNotAConfigurableKey() {
        for kind in WidgetKind.allCases {
            XCTAssertFalse(WidgetCatalog.configurableKeys(kind).contains(WidgetPlate.key), "\(kind)")
        }
    }
}

final class ShelfFitTests: XCTestCase {
    func testFitsAlreadyKeepsTheBase() {
        XCTAssertEqual(ShelfFit.fittedScale(base: 0.5, available: 1000) { $0 * 1000 }, 0.5)
    }

    func testShrinksToTheLargestScaleThatFits() {
        let fitted = ShelfFit.fittedScale(base: 0.6, available: 800) { $0 * 2000 }
        XCTAssertEqual(fitted, 0.4, accuracy: 0.001)
        XCTAssertLessThanOrEqual(fitted * 2000, 800)
    }

    func testNeverBelowTheMinimum() {
        // Would need 0.1; the floor is half of 0.6.
        let fitted = ShelfFit.fittedScale(base: 0.6, available: 200) { $0 * 2000 }
        XCTAssertEqual(fitted, 0.3, accuracy: 0.0001)
        XCTAssertEqual(ShelfFit.minimum(for: 0.35), Geometry.scaleRange.lowerBound)
    }

    func testOverflowDecodesLeniently() throws {
        let decoded = try JSONDecoder().decode([ShelfOverflow].self, from: Data(#"["shrink","sideways"]"#.utf8))
        XCTAssertEqual(decoded, [.shrink, .scroll])
    }

    func testSettingsWithoutOverflowDefaultToScroll() throws {
        let settings = try JSONDecoder().decode(CustomDockSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(settings.overflow, .scroll)
        var changed = settings
        changed.overflow = .shrink
        let again = try JSONDecoder().decode(CustomDockSettings.self,
                                             from: JSONEncoder().encode(changed))
        XCTAssertEqual(again.overflow, .shrink)
    }
}
