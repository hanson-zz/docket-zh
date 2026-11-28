import Foundation
import XCTest

final class CassetteDeckThemeTests: XCTestCase {
    func testLegacyAndUnknownThemesStayMechanical() {
        XCTAssertEqual(CassetteDeckTheme.stored(WidgetConfig()), .mechanical)
        for raw in ["", "unknown", "dark", "system"] {
            XCTAssertEqual(CassetteDeckTheme.stored(WidgetConfig([
                CassetteDeckTheme.key: .string(raw)])), .mechanical)
        }
        XCTAssertEqual(CassetteModel.allCases, [.tape, .portable, .boombox, .deck])
    }

    func testThemeSelectionChangesOnlyOneVisualKey() throws {
        let original = WidgetConfig([
            CassetteModel.key: .string("deck"),
            "spotify": .bool(true), "apple": .bool(false),
            MusicSourceSwitch.autoKey: .bool(false),
            "previous": .bool(true), "next": .bool(false),
        ])
        for theme in CassetteDeckTheme.allCases {
            let selected = CassetteDeckTheme.choosing(theme, in: original)
            XCTAssertEqual(CassetteDeckTheme.stored(selected), theme)
            for (key, value) in original.values { XCTAssertEqual(selected.values[key], value) }
            XCTAssertEqual(selected.values.count, original.values.count + 1)
            let restored = try JSONDecoder().decode(WidgetConfig.self,
                from: JSONEncoder().encode(selected))
            XCTAssertEqual(CassetteDeckTheme.stored(restored), theme)
        }
        XCTAssertNil(original.values[CassetteDeckTheme.key])
    }

    func testOtherModelsAndOtherWidgetConfigurationsAreUnaffected() {
        for model in [CassetteModel.tape, .portable, .boombox] {
            let config = WidgetConfig([CassetteModel.key: .string(model.rawValue)])
            XCTAssertEqual(CassetteDeckTheme.choosing(.pearl, in: config), config)
        }
        let other = WidgetConfig([CassetteModel.key: .string("deck")])
        let selected = CassetteDeckTheme.choosing(.pearl, in: other)
        XCTAssertEqual(CassetteDeckTheme.stored(other), .mechanical)
        XCTAssertEqual(CassetteDeckTheme.stored(selected), .pearl)
        XCTAssertEqual(CassetteDeckTheme.pearl.side, "A")
        XCTAssertEqual(CassetteDeckTheme.mechanical.side, "B")
        XCTAssertEqual(CassetteModel.stored(selected), .deck)
    }
}
