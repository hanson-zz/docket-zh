import XCTest

/// 跟随系统时的界面语言：有中文显示简体，有英文显示英文，都没有显示英文。
final class AppLanguageTests: XCTestCase {
    func testChineseVariantsShowSimplifiedChinese() {
        for identifier in ["zh-Hans-CN", "zh-Hans", "zh-Hant-TW", "zh-Hant", "zh-HK", "zh-TW", "zh_CN", "zh-Hant-HK", "ZH-hans"] {
            XCTAssertEqual(AppLanguage.resolved(preferredLanguages: [identifier]), .simplifiedChinese, identifier)
        }
    }

    func testEnglishShowsEnglish() {
        XCTAssertEqual(AppLanguage.resolved(preferredLanguages: ["en-US"]), .english)
        XCTAssertEqual(AppLanguage.resolved(preferredLanguages: ["en-CN", "zh-Hans-CN"]), .english)
    }

    func testOtherLanguagesFallBackToEnglish() {
        XCTAssertEqual(AppLanguage.resolved(preferredLanguages: ["fr-FR"]), .english)
        XCTAssertEqual(AppLanguage.resolved(preferredLanguages: ["ja-JP", "de-DE"]), .english)
        XCTAssertEqual(AppLanguage.resolved(preferredLanguages: []), .english)
    }

    func testFirstChineseOrEnglishInOrderWins() {
        XCTAssertEqual(AppLanguage.resolved(preferredLanguages: ["fr-FR", "zh-Hans-CN", "en-US"]), .simplifiedChinese)
        XCTAssertEqual(AppLanguage.resolved(preferredLanguages: ["ja-JP", "en-US", "zh-Hans-CN"]), .english)
    }

    func testLanguageCode() {
        XCTAssertEqual(AppLanguage.languageCode("zh-Hant-TW"), "zh")
        XCTAssertEqual(AppLanguage.languageCode("en_GB"), "en")
        XCTAssertEqual(AppLanguage.languageCode("FR"), "fr")
        XCTAssertEqual(AppLanguage.languageCode(""), "")
    }

    func testLaunchOverrideOnlyWhenFollowingSystem() {
        XCTAssertNil(AppLanguage.launchOverride(stored: .english, preferredLanguages: ["zh-Hant"], bundlePick: "zh-Hans"))
        XCTAssertNil(AppLanguage.launchOverride(stored: .simplifiedChinese, preferredLanguages: ["fr-FR"], bundlePick: "zh-Hans"))
    }

    func testLaunchOverrideWhenBundlePickDisagrees() {
        // 系统挑对了就不动。
        XCTAssertNil(AppLanguage.launchOverride(stored: .system, preferredLanguages: ["fr-FR"], bundlePick: "en"))
        XCTAssertNil(AppLanguage.launchOverride(stored: .system, preferredLanguages: ["zh-Hant-TW"], bundlePick: "zh-Hant"))
        XCTAssertNil(AppLanguage.launchOverride(stored: .system, preferredLanguages: ["zh-HK"], bundlePick: "zh-HK"))
        XCTAssertNil(AppLanguage.launchOverride(stored: .system, preferredLanguages: ["en-US"], bundlePick: "en"))
        // 挑错了才临时指定。
        XCTAssertEqual(AppLanguage.launchOverride(stored: .system, preferredLanguages: ["ja-JP"], bundlePick: "zh-Hans"), "en")
        XCTAssertEqual(AppLanguage.launchOverride(stored: .system, preferredLanguages: ["zh-MO"], bundlePick: "en"), "zh-Hans")
        XCTAssertEqual(AppLanguage.launchOverride(stored: .system, preferredLanguages: ["de-DE"], bundlePick: nil), "en")
    }

    func testChineseTextUnchangedInTests() {
        // 测试包里没有本地化表，tr() 原样返回中文。
        XCTAssertEqual(tr("跟随系统"), "跟随系统")
        XCTAssertFalse(L10n.isEnglish)
    }
}
