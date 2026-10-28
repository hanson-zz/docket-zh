import XCTest

final class MenuBarIconStyleTests: XCTestCase {
    func testDefaultIsHead() {
        XCTAssertEqual(MenuBarSettings().iconStyle, .head)
    }

    func testOldStateWithoutStyleDecodesAsHead() throws {
        let data = Data(#"{"showIcon":true}"#.utf8)
        let settings = try JSONDecoder().decode(MenuBarSettings.self, from: data)
        XCTAssertEqual(settings.iconStyle, .head)
    }

    func testUnknownStyleFallsBackToHead() throws {
        let data = Data(#"{"showIcon":true,"iconStyle":"rocket"}"#.utf8)
        let settings = try JSONDecoder().decode(MenuBarSettings.self, from: data)
        XCTAssertEqual(settings.iconStyle, .head)
        XCTAssertTrue(settings.showIcon)
    }

    func testRoundTrip() throws {
        var settings = MenuBarSettings()
        settings.iconStyle = .badge
        let back = try JSONDecoder().decode(MenuBarSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(back.iconStyle, .badge)
    }

    func testEveryStyleHasItsOwnResourceAndEighteenPointHeight() {
        let names = Set(MenuBarIconStyle.allCases.map(\.resourceName))
        XCTAssertEqual(names.count, MenuBarIconStyle.allCases.count)
        for style in MenuBarIconStyle.allCases {
            XCTAssertEqual(style.pointSize.height, 18)
        }
    }
}
