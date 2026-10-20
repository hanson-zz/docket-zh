import Foundation
import XCTest

/// 第三批面板实用性：取色器（拷贝格式、我的色板、删最近）、算（小数位、千分位）、
/// 便签（字体字号、10 张、清单项）。
final class ColorCalcNoteOptionsTests: XCTestCase {

    // MARK: 取色器：拷贝格式

    private let coral = ColorCode(hex: "#FF8A6B")!

    func testEveryCopyFormat() {
        XCTAssertEqual(coral.text(.hex), "#FF8A6B")
        XCTAssertEqual(coral.text(.hex, hexStyle: .lower), "#ff8a6b")
        XCTAssertEqual(coral.text(.hex, hexStyle: .bare), "FF8A6B")
        XCTAssertEqual(coral.text(.rgb), "rgb(255, 138, 107)")
        XCTAssertEqual(coral.text(.rgb, hexStyle: .lower), "rgb(255, 138, 107)", "HEX 写法只管 HEX")
        XCTAssertEqual(coral.text(.hsl), coral.hsl)
        XCTAssertEqual(coral.text(.swiftUI), "Color(red: 1.000, green: 0.541, blue: 0.420)")
    }

    func testCopyStyleReadsTheCardAndFallsBack() {
        XCTAssertEqual(ColorCopyStyle(WidgetConfig()), ColorCopyStyle(format: .hex, hexStyle: .upper))
        let config = WidgetConfig([ColorCopyFormat.key: .string("swiftui"), ColorHexStyle.key: .string("lower")])
        XCTAssertEqual(ColorCopyStyle(config), ColorCopyStyle(format: .swiftUI, hexStyle: .lower))
        let junk = WidgetConfig([ColorCopyFormat.key: .string("cmyk"), ColorHexStyle.key: .string("?")])
        XCTAssertEqual(ColorCopyStyle(junk), ColorCopyStyle(), "认不出的按大写 HEX")
    }

    func testCopyStyleSurvivesDefaults() {
        let defaults = UserDefaults(suiteName: "ColorCalcNoteOptionsTests.copy")!
        defaults.removePersistentDomain(forName: "ColorCalcNoteOptionsTests.copy")
        XCTAssertEqual(ColorCopyStyle.saved(in: defaults), ColorCopyStyle(), "没同步过就是大写 HEX")
        ColorCopyStyle(format: .rgb, hexStyle: .bare).save(in: defaults)
        XCTAssertEqual(ColorCopyStyle.saved(in: defaults), ColorCopyStyle(format: .rgb, hexStyle: .bare))
    }

    func testColorPickerOffersItsSettingsInOrder() {
        XCTAssertEqual(WidgetCatalog.configurableKeys(.colorPicker), ["copyFormat", "hexStyle", "showPalette"])
    }

    // MARK: 取色器：我的色板

    func testPaletteKeepsWhatIsStarredAndCaps() {
        var raw = ""
        raw = ColorPalette.adding(coral, to: raw)
        raw = ColorPalette.adding(coral, to: raw)
        XCTAssertEqual(ColorPalette.decode(raw), ["#FF8A6B"], "不重复收")
        raw = ColorPalette.toggling(ColorCode(hex: "#000000")!, in: raw)
        XCTAssertEqual(ColorPalette.decode(raw), ["#FF8A6B", "#000000"], "后收藏的在后")
        raw = ColorPalette.toggling(coral, in: raw)
        XCTAssertEqual(ColorPalette.decode(raw), ["#000000"], "再点星移出")

        var full = ""
        for i in 0..<30 { full = ColorPalette.adding(ColorCode(red: Double(i) / 30, green: 0, blue: 0), to: full) }
        XCTAssertEqual(ColorPalette.decode(full).count, ColorPalette.limit)
        XCTAssertTrue(ColorPalette.isFull(full))
        XCTAssertEqual(ColorPalette.adding(coral, to: full), full, "满了不收")
        XCTAssertEqual(ColorPalette.colors(""), [])
    }

    func testNewPicksDoNotPushThePaletteOut() {
        let palette = ColorPalette.adding(coral, to: "")
        var history = ""
        for i in 0..<20 { history = ColorHistory.adding(ColorCode(red: 0, green: Double(i) / 20, blue: 0), to: history) }
        XCTAssertFalse(ColorHistory.decode(history).contains("#FF8A6B"))
        XCTAssertEqual(ColorPalette.decode(palette), ["#FF8A6B"], "色板和最近是两份")
    }

    // MARK: 取色器：删最近

    func testRemovingFromHistoryFoldsTheLegacyListInFirst() {
        let raw = ColorHistory.encode(["#FF0000", "#00FF00"])
        let after = ColorHistory.removing(ColorCode(hex: "#00FF00")!, from: raw, legacy: ["#0000FF", "#ff0000"])
        XCTAssertEqual(ColorHistory.decode(after), ["#FF0000", "#0000FF"])
        XCTAssertEqual(ColorHistory.removing(coral, from: "", legacy: []), "", "删最后一个/空列表不出错")
        XCTAssertEqual(ColorHistory.removing(ColorCode(hex: "#FF0000")!, from: ColorHistory.encode(["#FF0000"])), "")
    }

    func testRetiredLegacyStaysGone() {
        let shared = ColorHistory.encode(["#FF0000"])
        XCTAssertEqual(ColorHistory.shown(shared: shared, legacy: ["#00FF00"], retired: false).map(\.hex),
                       ["#FF0000", "#00FF00"])
        XCTAssertEqual(ColorHistory.shown(shared: shared, legacy: ["#00FF00"], retired: true).map(\.hex),
                       ["#FF0000"], "删过或清空过后旧颜色不再冒回来")
        XCTAssertEqual(ColorHistory.shown(shared: "", legacy: ["#00FF00"], retired: true), [])
    }

    // MARK: 算：小数位和千分位

    func testDecimalsAndGrouping() {
        let auto = CalcNumberStyle(decimals: .auto, grouping: true)
        XCTAssertEqual(auto.text(1234567.891011, auto: "1234567.891011"), "1,234,567.891011")
        XCTAssertEqual(auto.text(-1234, auto: "-1234"), "-1,234")
        XCTAssertEqual(auto.text(999, auto: "999"), "999")

        let two = CalcNumberStyle(decimals: .two, grouping: true)
        XCTAssertEqual(two.text(712.3456789, auto: "712.3456789"), "712.35")
        XCTAssertEqual(two.text(1234567.891011, auto: "x"), "1,234,567.89")
        XCTAssertEqual(two.text(12, auto: "12"), "12.00", "固定位数留尾巴的零")
        XCTAssertEqual(two.text(-0.001, auto: "-0.001"), "0.00", "不出现 -0.00")

        let four = CalcNumberStyle(decimals: .four, grouping: false)
        XCTAssertEqual(four.text(7.123456789, auto: "7.123456789"), "7.1235")
        XCTAssertEqual(four.text(15000, auto: "15,000"), "15000.0000")

        let plain = CalcNumberStyle(decimals: .auto, grouping: false)
        XCTAssertEqual(plain.text(15000, auto: "15,000"), "15000", "关掉千分位连汇率的逗号也去掉")
        XCTAssertEqual(two.text(2e20, auto: "2e+20"), "2e+20", "科学计数照旧")
        XCTAssertEqual(CalcNumberStyle().text(1234, auto: "1234"), "1234", "没给千分位时不动")
    }

    func testCalcStyleReadsTheCard() {
        XCTAssertEqual(CalcNumberStyle(WidgetConfig()), CalcNumberStyle(decimals: .auto, grouping: true))
        let config = WidgetConfig([CalcNumberStyle.decimalsKey: .string("4"), CalcNumberStyle.groupingKey: .bool(false)])
        XCTAssertEqual(CalcNumberStyle(config), CalcNumberStyle(decimals: .four, grouping: false))
        XCTAssertEqual(CalcNumberStyle(WidgetConfig([CalcNumberStyle.decimalsKey: .string("9")])).decimals, .auto)
    }

    func testTheCardsResultFollowsItsSettings() throws {
        let config = WidgetConfig([CalcNumberStyle.decimalsKey: .string("2"), CalcNumberStyle.groupingKey: .bool(true)])
        let out = try SmartCalc.evaluate("1234567.891011*1", rates: nil, preferences: SmartCalc.Preferences(config)).get()
        XCTAssertEqual(out.text, "1,234,567.89")
        XCTAssertEqual(out.copyText, "1234567.89", "拷贝按显示的位数，不带千分位")
        let unit = try SmartCalc.evaluate("5 km", rates: nil,
                                          preferences: SmartCalc.Preferences(WidgetConfig([CalcNumberStyle.decimalsKey: .string("2")]))).get()
        XCTAssertEqual(unit.text, "3.11")
        XCTAssertEqual(WidgetCatalog.configurableKeys(.calculator), ["currencyFrom", "currencyTo", "decimals", "grouping"])
    }

    // MARK: 便签：字体字号

    func testNoteFontAndSize() {
        XCTAssertEqual(StickyNoteFont.of(WidgetConfig()), .hand, "旧便签照旧手写")
        XCTAssertEqual(StickyNoteSize.of(WidgetConfig()), .medium)
        XCTAssertEqual(StickyNoteFont.of(WidgetConfig(["font": .string("mono")])), .mono)
        XCTAssertEqual(StickyNoteSize.of(WidgetConfig(["fontSize": .string("huge")])), .medium)
        XCTAssertEqual(StickyNoteType.panel(.hand, .medium), 22, "中就是原来的 22")
        XCTAssertEqual(StickyNoteType.card(.hand, .medium, column: false), 15)
        XCTAssertEqual(StickyNoteType.card(.hand, .medium, column: true), 12)
        for font in StickyNoteFont.allCases {
            XCTAssertLessThan(StickyNoteType.panel(font, .small), StickyNoteType.panel(font, .large))
            for size in StickyNoteSize.allCases {
                XCTAssertGreaterThanOrEqual(StickyNoteType.panel(font, size), 13, "面板字不小于 13pt")
            }
        }
    }

    func testTenSheets() {
        XCTAssertEqual(StickyStack.limit, 10)
        var pile = StickyStack.Pile(sheets: [StickySheet()])
        for _ in 0..<15 { pile = pile.adding(color: StickyStack.nextColor(after: pile)) }
        XCTAssertEqual(pile.count, 10)
        XCTAssertFalse(pile.canAdd)
        XCTAssertEqual(pile.marker, "10/10")
        var config = WidgetConfig()
        StickyStack.store(pile.writing("最后一张"), in: &config)
        let back = StickyStack.pile(config)
        XCTAssertEqual(back.count, 10, "重启后十张都在")
        XCTAssertEqual(back.front.text, "最后一张")
    }

    // MARK: 便签：清单项

    func testChecklistLines() {
        let text = "周五前\n[ ] 交设计稿\n[x] 给小王回电话\n[] 买猫粮\n【】确认会议室\n- [X] 订票\n[?] 不是框"
        XCTAssertEqual(StickyChecklist.lines(text), [
            .text("周五前"),
            .item(done: false, text: "交设计稿"),
            .item(done: true, text: "给小王回电话"),
            .item(done: false, text: "买猫粮"),
            .item(done: false, text: "确认会议室"),
            .item(done: true, text: "订票"),
            .text("[?] 不是框"),
        ])
        XCTAssertTrue(StickyChecklist.hasItems(text))
        XCTAssertFalse(StickyChecklist.hasItems("普通的字\n[没关上"))
        XCTAssertFalse(StickyChecklist.hasItems(""))
        XCTAssertEqual(StickyChecklist.progress(text).done, 2)
        XCTAssertEqual(StickyChecklist.progress(text).total, 5)
    }

    func testTogglingOnlyTouchesThatBox() {
        let text = "标题\n[ ] 交设计稿\n- [x] 订票"
        XCTAssertEqual(StickyChecklist.toggling(line: 1, in: text), "标题\n[x] 交设计稿\n- [x] 订票")
        XCTAssertEqual(StickyChecklist.toggling(line: 2, in: text), "标题\n[ ] 交设计稿\n- [ ] 订票")
        XCTAssertEqual(StickyChecklist.toggling(line: 0, in: text), text, "不是清单项不动")
        XCTAssertEqual(StickyChecklist.toggling(line: 9, in: text), text, "越界不动")
        XCTAssertEqual(StickyChecklist.toggling(line: 0, in: "【】买菜"), "[x] 买菜")
    }

    func testReturnContinuesTheList() {
        XCTAssertEqual(StickyChecklist.submitting("[ ] 一").text, "[ ] 一\n[ ] ")
        XCTAssertTrue(StickyChecklist.submitting("[ ] 一").keepWriting)
        let ended = StickyChecklist.submitting("[ ] 一\n[ ] ")
        XCTAssertEqual(ended.text, "[ ] 一")
        XCTAssertFalse(ended.keepWriting, "空的一项上回车收尾")
        XCTAssertFalse(StickyChecklist.submitting("普通一行").keepWriting)
        XCTAssertEqual(StickyChecklist.submitting("").text, "")
    }

    func testTheCardShowsBoxesAsGlyphs() {
        XCTAssertEqual(StickyChecklist.display("买菜\n[ ] 牛奶\n[x] 面包"), "买菜\n☐ 牛奶\n☑ 面包")
    }
}
