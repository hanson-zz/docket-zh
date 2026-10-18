import XCTest

/// 拖入类四张卡片的拖入提示，和便签的多张叠放（含旧便签的兼容）。
final class DropStickyTests: XCTestCase {

    // MARK: 拖入提示

    func testEachDropSaysWhereThingsGo() {
        XCTAssertEqual(DropPrompt.fileShelf(files: 3).title, "暂存在这里")
        XCTAssertEqual(DropPrompt.fileShelf(files: 3).caption, "3 个文件")
        XCTAssertEqual(DropPrompt.airDrop(files: 3).title, "发送给附近设备")
        XCTAssertEqual(DropPrompt.airDrop(files: 3).caption, "3 个文件 · 松手选设备")
        XCTAssertEqual(DropPrompt.trash(items: 3).title, "移到废纸篓")
        XCTAssertEqual(DropPrompt.trash(items: 3).caption, "3 个 · 之后还能拿回来")
        XCTAssertEqual(DropPrompt.todo.title, "记一条待办")
        XCTAssertEqual(DropPrompt.todo.caption, "文字、链接、文件都行")
    }

    func testNoCountStillSaysTheConsequence() {
        XCTAssertEqual(DropPrompt.fileShelf(files: 0).caption, "只记位置，原文件不动")
        XCTAssertEqual(DropPrompt.trash(items: 0).caption, "之后还能拿回来")
        XCTAssertEqual(DropPrompt.airDrop(files: 0).caption, "松手选设备")
    }

    func testTrashNeverSaysDelete() {
        for prompt in [DropPrompt.trash(items: 0), .trash(items: 5)] {
            XCTAssertFalse(prompt.title.contains("删除"))
            XCTAssertFalse(prompt.caption.contains("删除"))
        }
    }

    func testEachResultHasItsOwnColor() {
        let tints = [DropPrompt.fileShelf(files: 1), .airDrop(files: 1), .trash(items: 1), .todo].map(\.tint)
        XCTAssertEqual(tints, [.teal, .blue, .red, .orange])
        XCTAssertEqual(DropPrompt.Tint.blue.darkHex, DockMetrics.dropBlueDark)
        XCTAssertLessThan(DropPrompt.Tint.blue.fillOpacity(dark: true), DropPrompt.Tint.teal.fillOpacity(dark: true),
                          "系统蓝只垫很淡的一层")
        for prompt in [DropPrompt.fileShelf(files: 1), .airDrop(files: 1), .trash(items: 1), .todo] {
            XCTAssertEqual(prompt.compactTitle.split(separator: "\n").count, 2, "\(prompt)")
        }
    }

    // MARK: 便签

    func testAnOldNoteReadsAsOneSheetUnchanged() {
        let config = WidgetConfig(["text": .string("周五前交房租"), "color": .string("pink")])
        let pile = StickyStack.pile(config)
        XCTAssertEqual(pile.count, 1)
        XCTAssertEqual(pile.front, StickySheet(text: "周五前交房租", color: "pink"))
        XCTAssertNil(pile.marker)
        // 写回去也和原来一样，不多出键。
        var copy = config
        StickyStack.store(pile, in: &copy)
        XCTAssertEqual(copy, config)
    }

    func testAnOldColorStyleCardKeepsItsColor() {
        // 原来添加面板里的颜色样式卡就是把 color 写进配置。
        for color in PaperColor.picker {
            let pile = StickyStack.pile(WidgetConfig(["text": .string(""), "color": .string(color.rawValue)]))
            XCTAssertEqual(pile.front.paper(unlocked: true), color)
        }
        XCTAssertEqual(StickyStack.pile(WidgetConfig()).front.color, "yellow", "没有颜色时是柠檬黄")
    }

    func testStackUpToThreeAndFlip() {
        var pile = StickyStack.pile(WidgetConfig(["text": .string("一"), "color": .string("yellow")]))
        pile = pile.adding(color: StickyStack.nextColor(after: pile)).writing("二")
        XCTAssertEqual(pile.count, 2)
        XCTAssertEqual(pile.front.color, "mint", "新的一张挑一个还没用上的免费色")
        XCTAssertEqual(pile.marker, "2/2")
        pile = pile.adding(color: StickyStack.nextColor(after: pile)).writing("三")
        XCTAssertEqual(pile.marker, "3/3")
        XCTAssertFalse(pile.canAdd)
        XCTAssertEqual(pile.adding(color: "pink"), pile, "最多 3 张")

        let flipped = pile.flipped()
        XCTAssertEqual(flipped.front.text, "一")
        XCTAssertEqual(flipped.marker, "1/3")
        XCTAssertEqual(flipped.behind.map(\.text), ["二", "三"])
        XCTAssertEqual(flipped.flipped().front.text, "二")
    }

    func testStoredPileRoundTrips() {
        var pile = StickyStack.Pile(sheets: [StickySheet(text: "a", color: "yellow"),
                                             StickySheet(text: "b", color: "coral"),
                                             StickySheet(text: "c", color: "mint")], page: 1)
        var config = WidgetConfig()
        StickyStack.store(pile, in: &config)
        // 设置里改的 text / color 是最上面那张。
        XCTAssertEqual(config.string("text"), "b")
        XCTAssertEqual(config.string("color"), "coral")
        XCTAssertEqual(StickyStack.pile(config), pile)

        pile = pile.coloring("peach")
        StickyStack.store(pile, in: &config)
        XCTAssertEqual(StickyStack.pile(config).sheets.map(\.color), ["yellow", "peach", "mint"],
                       "换颜色只改这一张")
    }

    func testTearingOffASheet() {
        let pile = StickyStack.Pile(sheets: [StickySheet(text: "a"), StickySheet(text: "b")], page: 1)
        let torn = pile.removingFront()
        XCTAssertEqual(torn.count, 1)
        XCTAssertEqual(torn.front.text, "a")
        XCTAssertEqual(torn.removingFront(), torn, "最后一张撕不掉")
        var config = WidgetConfig(["stack": .list([]), "page": .number(2)])
        StickyStack.store(torn, in: &config)
        XCTAssertNil(config["stack"])
        XCTAssertNil(config["page"])
    }

    func testProColorsFallBackPerSheet() {
        let sheet = StickySheet(text: "x", color: "coral")
        XCTAssertEqual(sheet.paper(unlocked: false), .yellow)
        XCTAssertEqual(sheet.paper(unlocked: true), .coral)
        XCTAssertEqual(StickySheet(color: "mint").paper(unlocked: false), .mint)
        XCTAssertEqual(StickySheet(color: "nope").paper(unlocked: true), .yellow)
    }

    func testABrokenStackIsReadLeniently() {
        let config = WidgetConfig(["text": .string("a"),
                                   "stack": .list([.string("junk"), .list([.string("mint")]),
                                                   .list([.string("pink"), .string("c")]),
                                                   .list([.string("blue"), .string("d")])]),
                                   "page": .number(9)])
        let pile = StickyStack.pile(config)
        XCTAssertEqual(pile.count, 3)
        XCTAssertEqual(pile.page, 2)
        XCTAssertEqual(pile.front.text, "a")
    }

    func testNotesAreNoLongerListedByColor() {
        guard let entry = WidgetCatalog.entry(.notes) else { return XCTFail("no entry") }
        XCTAssertTrue(entry.variants.isEmpty, "颜色在面板和设置里选，不占添加面板")
        XCTAssertEqual(WidgetCatalog.configurableKeys(.notes), ["color", "text"])
    }

    func testFlippingBackAndForthWraps() {
        let pile = StickyStack.Pile(sheets: [StickySheet(text: "一"), StickySheet(text: "二"), StickySheet(text: "三")])
        XCTAssertEqual(pile.flipped(by: -1).front.text, "三", "第一张往前是最后一张")
        XCTAssertEqual(pile.flipped(by: 1).front.text, "二")
        XCTAssertEqual(pile.flipped(by: 4).front.text, "二")
        XCTAssertEqual(pile.flipped(by: -1).flipped(by: 1), pile)
        let single = StickyStack.Pile(sheets: [StickySheet(text: "独")])
        XCTAssertEqual(single.flipped(by: -1), single)
    }

    func testWheelPagingStepsOncePerGesture() {
        // 滚轮一格就翻；触控板滑够距离翻一张，同一下手势不连翻。
        var gesture = LayoutGesture()
        XCTAssertEqual(gesture.feed(-1, precise: false, at: 0), 1)
        XCTAssertEqual(gesture.feed(1, precise: false, at: 1), -1)
        var swipe = LayoutGesture()
        swipe.begin()
        XCTAssertNil(swipe.feed(-20, precise: true, at: 10))
        XCTAssertEqual(swipe.feed(-30, precise: true, at: 10.05), 1)
        XCTAssertNil(swipe.feed(-80, precise: true, at: 10.1))
    }
}
