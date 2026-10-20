import Foundation
import XCTest

final class RadioFavouriteListTests: XCTestCase {
    func testNoRowsHasNoHeight() {
        XCTAssertEqual(RadioFavouriteList.height(rowCount: 0, rowHeight: 34), 0)
        XCTAssertEqual(RadioFavouriteList.height(rowCount: 3, rowHeight: 0), 0)
    }

    func testFewRowsLeaveNoBlankSpace() {
        XCTAssertEqual(RadioFavouriteList.height(rowCount: 1, rowHeight: 34), 34)
        XCTAssertEqual(RadioFavouriteList.height(rowCount: 3, rowHeight: 34), 3 * 34 + 2 * 2)
        XCTAssertFalse(RadioFavouriteList.scrolls(rowCount: 3))
    }

    func testFiveRowsShowExactlyFive() {
        XCTAssertEqual(RadioFavouriteList.height(rowCount: 5, rowHeight: 43), 5 * 43 + 4 * 2)
        XCTAssertFalse(RadioFavouriteList.scrolls(rowCount: 5))
    }

    func testMoreThanFiveRowsCapAtFiveAndScroll() {
        let five = RadioFavouriteList.height(rowCount: 5, rowHeight: 34)
        XCTAssertEqual(RadioFavouriteList.height(rowCount: 6, rowHeight: 34), five)
        XCTAssertEqual(RadioFavouriteList.height(rowCount: 40, rowHeight: 34), five)
        XCTAssertTrue(RadioFavouriteList.scrolls(rowCount: 6))
    }

    func testFiveRowsShowMoreThanTheOld150Cap() {
        XCTAssertGreaterThan(RadioFavouriteList.height(rowCount: 5, rowHeight: RadioFavouriteList.fallbackRowHeight(retro: false)), 150)
        XCTAssertGreaterThan(RadioFavouriteList.height(rowCount: 5, rowHeight: RadioFavouriteList.fallbackRowHeight(retro: true)), 150)
    }
}
