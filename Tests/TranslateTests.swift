import Foundation
import XCTest

final class TranslateTests: XCTestCase {

    // MARK: Detecting

    func testChineseIsToldByItsCharacters() {
        XCTAssertTrue(Translate.looksChinese("今天天气不错"))
        XCTAssertTrue(Translate.looksChinese("我在用 Docket 的翻译"))
        XCTAssertTrue(Translate.looksChinese("Hello 世界"), "two of seven letters, but a word each")
        XCTAssertFalse(Translate.looksChinese("Hello world, 你"))
        XCTAssertFalse(Translate.looksChinese("The quick brown fox"))
        XCTAssertFalse(Translate.looksChinese("12345 !?"))
        XCTAssertFalse(Translate.looksChinese(""))
    }

    func testKanaAndHangulAreNotChinese() {
        XCTAssertFalse(Translate.looksChinese("日本語を勉強しています"))
        XCTAssertEqual(Translate.scriptLanguage("日本語を勉強しています"), "ja")
        XCTAssertEqual(Translate.scriptLanguage("안녕하세요"), "ko")
        XCTAssertEqual(Translate.scriptLanguage("你好"), "zh-Hans")
        XCTAssertNil(Translate.scriptLanguage("Bonjour"))
        XCTAssertNil(Translate.scriptLanguage("   "))
    }

    func testTheHanRatioIgnoresSpacesDigitsAndPunctuation() {
        XCTAssertEqual(Translate.hanRatio("你好，世界！123"), 1)
        XCTAssertEqual(Translate.hanRatio("ab你好"), 0.5)
        XCTAssertEqual(Translate.hanRatio("..."), 0)
    }

    func testDetectingByScriptNeedsNoRecogniser() {
        XCTAssertEqual(Translate.detect("  这是一段中文  "), "zh-Hans")
        XCTAssertEqual(Translate.detect("こんにちは"), "ja")
        XCTAssertNil(Translate.detect("   \n "))
    }

    // MARK: Direction

    func testTheSmartDirectionSendsChineseToEnglishAndTheRestToChinese() {
        XCTAssertEqual(Translate.target(source: "zh-Hans", text: "", chosen: "ja", smart: true), "en")
        XCTAssertEqual(Translate.target(source: "zh-Hant", text: "", chosen: "ja", smart: true), "en")
        XCTAssertEqual(Translate.target(source: "en", text: "", chosen: "ja", smart: true), "zh-Hans")
        XCTAssertEqual(Translate.target(source: "fr", text: "", chosen: "ja", smart: true), "zh-Hans")
        XCTAssertEqual(Translate.target(source: nil, text: "我们明天见", chosen: "ja", smart: true), "en")
        XCTAssertEqual(Translate.target(source: nil, text: "See you tomorrow", chosen: "ja", smart: true), "zh-Hans")
    }

    func testWithTheSmartDirectionOffTheChosenTargetStands() {
        XCTAssertEqual(Translate.target(source: "zh-Hans", text: "你好", chosen: "ja", smart: false), "ja")
        XCTAssertEqual(Translate.target(source: "en", text: "hi", chosen: "", smart: false), "zh-Hans")
    }

    // MARK: Languages

    func testSystemIdentifiersMapOntoTheList() {
        XCTAssertEqual(Translate.code(for: "zh-Hans-CN"), "zh-Hans")
        XCTAssertEqual(Translate.code(for: "zh-CN"), "zh-Hans")
        XCTAssertEqual(Translate.code(for: "zh"), "zh-Hans")
        XCTAssertEqual(Translate.code(for: "zh-TW"), "zh-Hant")
        XCTAssertEqual(Translate.code(for: "zh_Hant_HK"), "zh-Hant")
        XCTAssertEqual(Translate.code(for: "en-US"), "en")
        XCTAssertEqual(Translate.code(for: "en-Latn-GB"), "en")
        XCTAssertEqual(Translate.code(for: "pt-BR"), "pt")
    }

    func testCommonLanguagesHaveChineseNamesAndShortForms() {
        XCTAssertEqual(Translate.name("en-US"), "英语")
        XCTAssertEqual(Translate.name("zh-Hans"), "简体中文")
        XCTAssertEqual(Translate.name("zh-TW"), "繁体中文")
        XCTAssertEqual(Translate.name("ja"), "日语")
        XCTAssertEqual(Translate.name(Translate.auto), "自动检测")
        XCTAssertEqual(Translate.name("xx"), "xx")
        XCTAssertEqual(Translate.pairText(source: "zh-Hans", target: "en"), "中 ⇄ 英")
        let codes = Translate.common.map(\.code)
        XCTAssertEqual(Set(codes).count, codes.count, "no language twice")
        for language in Translate.common {
            XCTAssertFalse(language.name.isEmpty)
            XCTAssertFalse(language.short.isEmpty)
            XCTAssertLessThanOrEqual(language.short.count, 2)
        }
    }

    func testSpeechCodesCarryARegionForChinese() {
        XCTAssertEqual(Translate.speechCode("zh-Hans"), "zh-CN")
        XCTAssertEqual(Translate.speechCode("zh-Hant-TW"), "zh-TW")
        XCTAssertEqual(Translate.speechCode("en"), "en-US")
        XCTAssertEqual(Translate.speechCode("fr"), "fr")
    }

    func testSameLanguageIgnoresTheRegion() {
        XCTAssertTrue(Translate.same("en", "en-GB"))
        XCTAssertTrue(Translate.same("zh-CN", "zh-Hans"))
        XCTAssertFalse(Translate.same("zh-Hans", "zh-Hant"))
    }

    // MARK: Text

    func testTheEditorStopsAtTheLimit() {
        let long = String(repeating: "字", count: Translate.maxCharacters + 50)
        XCTAssertEqual(Translate.clamped(long).count, Translate.maxCharacters)
        XCTAssertEqual(Translate.clamped("短"), "短")
    }

    func testASnippetIsTheFirstLine() {
        XCTAssertEqual(Translate.snippet("  Hello\nworld  "), "Hello")
        XCTAssertEqual(Translate.snippet(String(repeating: "a", count: 10), limit: 4), "aaaa…")
        XCTAssertEqual(Translate.snippet("\n\n"), "")
    }

    // MARK: History

    private func record(_ text: String, _ result: String = "r", from: String = "en", to: String = "zh-Hans") -> TranslateRecord {
        TranslateRecord(source: from, target: to, sourceText: text, resultText: result)
    }

    func testARecordSurvivesTabsLineBreaksAndBackslashes() {
        let tricky = record("a\tb\nc\\d\\t", "第一行\n第二行\t\\")
        let line = Translate.encode(tricky)
        XCTAssertFalse(line.contains("\n"))
        XCTAssertEqual(line.components(separatedBy: "\t").count, 4)
        XCTAssertEqual(Translate.decode(line), tricky)
    }

    func testMalformedLinesAreSkipped() {
        XCTAssertNil(Translate.decode("en\tzh-Hans\tonly three"))
        XCTAssertNil(Translate.decode("en\tzh-Hans\t  \tx"))
        XCTAssertNil(Translate.decode(""))
        let config = WidgetConfig([Translate.historyKey: .list([.string("junk"),
                                                                .string(Translate.encode(record("ok")))])])
        XCTAssertEqual(Translate.history(config).map(\.sourceText), ["ok"])
    }

    func testTheNewestComesFirstAndTheListIsCapped() {
        var history: [TranslateRecord] = []
        for i in 0..<(Translate.maxHistory + 5) {
            history = Translate.recording(record("item \(i) done"), in: history)
        }
        XCTAssertEqual(history.count, Translate.maxHistory)
        XCTAssertEqual(history.first?.sourceText, "item 24 done")
        var config = WidgetConfig()
        Translate.store(history, in: &config)
        XCTAssertEqual(Translate.history(config), history)
    }

    func testTypingReplacesTheEntryItGrewFrom() {
        var history = Translate.recording(record("good"), in: [])
        history = Translate.recording(record("good morning"), in: history)
        XCTAssertEqual(history.map(\.sourceText), ["good morning"])
        history = Translate.recording(record("good mor"), in: history)
        XCTAssertEqual(history.map(\.sourceText), ["good mor"], "backspacing trims it too")
        history = Translate.recording(record("thanks"), in: history)
        XCTAssertEqual(history.map(\.sourceText), ["thanks", "good mor"])
        history = Translate.recording(record("thanks", from: "en", to: "ja"), in: history)
        XCTAssertEqual(history.count, 3, "another direction is another entry")
    }

    func testTheSameTextAgainMovesToTheTop() {
        var history = Translate.recording(record("apple"), in: [])
        history = Translate.recording(record("banana"), in: history)
        history = Translate.recording(record("apple", "苹果"), in: history)
        XCTAssertEqual(history.map(\.sourceText), ["apple", "banana"])
        XCTAssertEqual(history.first?.resultText, "苹果")
    }

    func testBlankTextIsNotRecordedAndLongTextIsCut() {
        XCTAssertEqual(Translate.recording(record("   "), in: []), [])
        let long = String(repeating: "x", count: Translate.maxHistoryText + 10)
        let history = Translate.recording(record(long, long), in: [])
        XCTAssertEqual(history.first?.sourceText.count, Translate.maxHistoryText)
        XCTAssertEqual(history.first?.resultText.count, Translate.maxHistoryText)
        XCTAssertEqual(Translate.removing(at: 0, from: history), [])
        XCTAssertEqual(Translate.removing(at: 5, from: history), history)
    }

    // MARK: Settings and catalog

    func testTheSettingsReadTheirDefaults() {
        let bare = WidgetConfig()
        XCTAssertEqual(Translate.clickAction(bare), .panel)
        XCTAssertTrue(Translate.smartDirection(bare))
        XCTAssertEqual(Translate.source(bare), Translate.auto)
        XCTAssertEqual(Translate.chosenTarget(bare), "en")
        XCTAssertEqual(Translate.clickAction(WidgetConfig(["clickAction": .string("clipboard")])), .clipboard)
        XCTAssertEqual(Translate.clickAction(WidgetConfig(["clickAction": .string("bogus")])), .panel)
        XCTAssertEqual(Translate.ClickAction.allCases.map(\.title), ["打开面板", "翻译剪贴板"])
    }

    func testTheTileShowsTheLastPairOrTheDefaultOne() {
        XCTAssertEqual(Translate.tilePair(WidgetConfig()), "中 ⇄ 英")
        var config = WidgetConfig()
        Translate.store([record("bonjour", from: "fr", to: "zh-Hans")], in: &config)
        XCTAssertEqual(Translate.tilePair(config), "法 ⇄ 中")
        let manual = WidgetConfig(["autoDirection": .bool(false), "source": .string("en"), "target": .string("ja")])
        XCTAssertEqual(Translate.tilePair(manual), "英 ⇄ 日")
    }

    func testTheWidgetIsAToolWithItsOwnSizes() {
        let entry = WidgetCatalog.entry(.translate)
        XCTAssertEqual(entry?.name, "翻译")
        XCTAssertEqual(entry?.category, .ai)
        XCTAssertEqual(WidgetCatalog.configurableKeys(.translate), ["autoDirection", "clickAction"])
        let widget = WidgetCatalog.make(.translate)!
        XCTAssertEqual(WidgetCatalog.contentSize(widget, position: .bottom).height, 58)
        XCTAssertGreaterThanOrEqual(WidgetCatalog.verticalHeight(widget), 76)
        XCTAssertNil(WidgetCatalog.openTarget(.translate), "its click opens the panel")
    }
}
