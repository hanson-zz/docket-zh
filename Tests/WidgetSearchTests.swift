import XCTest

/// The widget library's search: Chinese, pinyin, initials, English, synonyms.
final class WidgetSearchTests: XCTestCase {
    private func hit(_ query: String, _ name: String, _ kind: String) -> Bool {
        WidgetSearch.matches(query, names: [name], kind: kind)
    }

    func testChineseName() { XCTAssertTrue(hit("天气", "天气", "weather")) }
    func testPinyin() {
        XCTAssertTrue(hit("tianqi", "天气", "weather"))
        XCTAssertTrue(hit("Tian Qi", "天气", "weather"))
    }
    func testInitials() {
        XCTAssertTrue(hit("tq", "天气", "weather"))
        XCTAssertTrue(hit("jsq", "计算器", "calculator"))
    }
    func testEnglishAndSynonyms() {
        XCTAssertTrue(hit("Weather", "天气", "weather"))
        XCTAssertTrue(hit("番茄钟", "专注计时", "timer"))
        XCTAssertTrue(hit("pomodoro", "专注计时", "timer"))
    }
    func testNoFalseHits() {
        XCTAssertFalse(hit("bitcoin", "天气", "weather"))
        XCTAssertFalse(hit("zq", "电池", "battery"))
    }
    func testEveryCatalogKindHasKeywords() {
        for entry in WidgetCatalog.entries where entry.selfContained {
            XCTAssertNotNil(WidgetSearch.keywords[entry.kind.rawValue], entry.kind.rawValue)
        }
    }
}
