import Foundation
import XCTest

/// The shelf's look is offered as one choice and stored as three settings.
final class ShelfLookTests: XCTestCase {
    func testEveryLookRoundTripsThroughTheSettings() {
        for look in ShelfLook.allCases {
            var settings = CustomDockSettings()
            look.apply(to: &settings)
            XCTAssertEqual(ShelfLook(settings), look, "\(look)")
        }
    }

    func testEveryLookIsOfferedOnceWithAChineseTitle() {
        XCTAssertEqual(Set(ShelfLook.ordered), Set(ShelfLook.allCases))
        XCTAssertEqual(ShelfLook.ordered.count, ShelfLook.allCases.count)
        XCTAssertEqual(Set(ShelfLook.allCases.map(\.title)).count, ShelfLook.allCases.count)
    }

    func testTheDefaultIsPlainGlass() {
        XCTAssertEqual(ShelfLook(CustomDockSettings()), .glass)
    }

    /// A tint left over from glass must not turn a frosted shelf into glass.
    func testATintOnlyMattersForGlass() {
        var settings = CustomDockSettings()
        ShelfLook.darkGlass.apply(to: &settings)
        ShelfLook.frosted.apply(to: &settings)
        XCTAssertEqual(ShelfLook(settings), .frosted)
        ShelfLook.glass.apply(to: &settings)
        XCTAssertEqual(settings.glassTint, .automatic, "choosing plain glass clears the tint")
    }

    func testPinnedPlatesPinTheInk() {
        XCTAssertEqual(ShelfLook.white.forcedAppearance, .light)
        XCTAssertEqual(ShelfLook.lightGlass.forcedAppearance, .light)
        XCTAssertEqual(ShelfLook.black.forcedAppearance, .dark)
        XCTAssertEqual(ShelfLook.darkGlass.forcedAppearance, .dark)
        XCTAssertNil(ShelfLook.glass.forcedAppearance)
        XCTAssertNil(ShelfLook.transparent.forcedAppearance)
    }

    func testNewAppearanceKeysDecodeLenientlyAndDefault() throws {
        let missing = try JSONDecoder().decode(CustomDockSettings.self, from: Data(#"{}"#.utf8))
        XCTAssertEqual(missing.glassTint, .automatic)
        XCTAssertEqual(missing.widgetColor, .original)
        XCTAssertFalse(missing.reduceTransparency)

        let odd = try JSONDecoder().decode(CustomDockSettings.self, from: Data(
            #"{"material": "neon", "glassTint": "purple", "widgetColor": "sepia"}"#.utf8))
        XCTAssertEqual(odd.material, .liquidGlass)
        XCTAssertEqual(odd.glassTint, .automatic)
        XCTAssertEqual(odd.widgetColor, .original)

        var settings = CustomDockSettings()
        ShelfLook.black.apply(to: &settings)
        settings.widgetColor = .monochrome
        settings.reduceTransparency = true
        let back = try JSONDecoder().decode(CustomDockSettings.self,
                                            from: JSONEncoder().encode(settings))
        XCTAssertEqual(back.material, .solidDark)
        XCTAssertEqual(back.widgetColor, .monochrome)
        XCTAssertTrue(back.reduceTransparency)
    }
}
