import XCTest

/// 便签改版：更宽的清单写法、清单键、清单视图的排法、淡墨对比度，撕掉和垃圾桶。
final class StickyNoteV2Tests: XCTestCase {

    // MARK: 清单写法

    func testMoreWaysToWriteABox() {
        let text = "- [ ] 一\n-[ ] 二\n* [ ] 三\n+ [x] 四\n☐ 五\n□六\n○ 七\n☑ 八\n✓ 九\n[√] 十\n【 】十一\n［x］十二\n[✔] 十三"
        XCTAssertEqual(StickyChecklist.lines(text), [
            .item(done: false, text: "一"),
            .item(done: false, text: "二"),
            .item(done: false, text: "三"),
            .item(done: true, text: "四"),
            .item(done: false, text: "五"),
            .item(done: false, text: "六"),
            .item(done: false, text: "七"),
            .item(done: true, text: "八"),
            .item(done: true, text: "九"),
            .item(done: true, text: "十"),
            .item(done: false, text: "十一"),
            .item(done: true, text: "十二"),
            .item(done: true, text: "十三"),
        ])
    }

    func testThingsThatAreNotBoxes() {
        let text = "- 牛奶\n1. 鸡蛋\n√2 约 1.414\n[1]对对对\n[链接](https://a.b)\n[没关上\n* 星号"
        XCTAssertFalse(StickyChecklist.hasItems(text))
        XCTAssertEqual(StickyChecklist.lines(text).first, .text("- 牛奶"))
    }

    func testTogglingKeepsBulletsAndIndent() {
        XCTAssertEqual(StickyChecklist.toggling(line: 0, in: "  * [ ] 牛奶"), "  * [x] 牛奶")
        XCTAssertEqual(StickyChecklist.toggling(line: 0, in: "○ 牛奶"), "[x] 牛奶")
        XCTAssertEqual(StickyChecklist.toggling(line: 0, in: "☑ 牛奶"), "[ ] 牛奶")
        XCTAssertEqual(StickyChecklist.toggling(line: 0, in: "-[x] 牛奶"), "-[ ] 牛奶")
    }

    // MARK: 认不出的写法

    func testUnknownBoxesAreAskedNotRewritten() {
        let text = "周五前\n[1]对对对\n[a] 买菜\n[?] 问问\n[ ] 已经是\n[链接](x)\n[1]"
        XCTAssertEqual(StickyChecklist.ambiguousLines(text), [1, 2, 3])
        XCTAssertEqual(StickyChecklist.lines(text)[1], .text("[1]对对对"), "认不出的不偷改")
        XCTAssertEqual(StickyChecklist.convertingAmbiguous(text),
                       "周五前\n[ ] 对对对\n[ ] 买菜\n[ ] 问问\n[ ] 已经是\n[链接](x)\n[1]")
        XCTAssertEqual(StickyChecklist.ambiguousLines("- [2] 二"), [0])
        XCTAssertEqual(StickyChecklist.convertingAmbiguous("- [2] 二"), "- [ ] 二")
    }

    // MARK: 清单键

    func testChecklistKeyTurnsLinesIntoItems() {
        let text = "周末采购\n牛奶\n- 鸡蛋\n\n2. 面包\n  苹果"
        XCTAssertEqual(StickyChecklist.togglingItems(text, lines: 1...5),
                       "周末采购\n[ ] 牛奶\n[ ] 鸡蛋\n\n[ ] 面包\n  [ ] 苹果")
        XCTAssertEqual(StickyChecklist.togglingItems(text, lines: 1...1), "周末采购\n[ ] 牛奶\n- 鸡蛋\n\n2. 面包\n  苹果")
    }

    func testChecklistKeyTogglesBack() {
        let text = "[ ] 牛奶\n- [x] 鸡蛋\n  ○ 面包"
        XCTAssertEqual(StickyChecklist.togglingItems(text, lines: 0...2), "牛奶\n鸡蛋\n  面包")
        // 混着的：只把不是清单项的补上框，已经是的不动。
        XCTAssertEqual(StickyChecklist.togglingItems("[x] 一\n二", lines: 0...1), "[x] 一\n[ ] 二")
        XCTAssertEqual(StickyChecklist.togglingItems("[1]对对对", lines: 0...0), "[ ] 对对对")
    }

    func testChecklistKeyOnAnEmptyLineStartsAnItem() {
        XCTAssertEqual(StickyChecklist.togglingItems("", lines: 0...0), "[ ] ")
        XCTAssertEqual(StickyChecklist.togglingItems("标题\n", lines: 1...1), "标题\n[ ] ")
        XCTAssertEqual(StickyChecklist.togglingItems("\n\n", lines: 0...2), "\n\n", "好几行空行不动")
        XCTAssertEqual(StickyChecklist.togglingItems("一", lines: 3...9), "[ ] 一", "越界夹到最后一行")
    }

    func testSelectionMapsToLines() {
        let text = "一\n二二\n三"
        XCTAssertEqual(StickyChecklist.lineRange(in: text, from: 0, to: 0), 0...0)
        XCTAssertEqual(StickyChecklist.lineRange(in: text, from: 3, to: 3), 1...1)
        XCTAssertEqual(StickyChecklist.lineRange(in: text, from: 1, to: 6), 0...2)
        XCTAssertEqual(StickyChecklist.lineRange(in: text, from: 2, to: 5), 1...1, "选到下一行开头不算下一行")
        XCTAssertEqual(StickyChecklist.lineRange(in: text, from: 99, to: 99), 2...2)
    }

    // MARK: 清单视图

    func testDoneItemsSinkWhenAsked() {
        let text = "周末采购\n[x] 面包\n[ ] 牛奶\n[x] 苹果\n[ ] 鸡蛋\n\n"
        let sunk = StickyChecklist.layout(text, sinkDone: true)
        XCTAssertEqual(sunk.open.map(\.index), [0, 2, 4])
        XCTAssertEqual(sunk.done.map(\.index), [1, 3])
        let kept = StickyChecklist.layout(text, sinkDone: false)
        XCTAssertEqual(kept.open.map(\.index), [0, 1, 2, 3, 4], "末尾空行不画")
        XCTAssertTrue(kept.done.isEmpty)
    }

    func testTitleLineCarriesProgress() {
        XCTAssertEqual(StickyChecklist.titleLine("\n周末采购\n[ ] 牛奶"), 1)
        XCTAssertNil(StickyChecklist.titleLine("[ ] 牛奶\n周末"))
        XCTAssertNil(StickyChecklist.titleLine("只是一段字"))
    }

    func testUncheckAndClearDone() {
        let text = "标题\n[x] 面包\n[ ] 牛奶\n- [X] 苹果"
        XCTAssertEqual(StickyChecklist.uncheckingAll(text), "标题\n[ ] 面包\n[ ] 牛奶\n- [ ] 苹果")
        let cleared = StickyChecklist.removingDone(text)
        XCTAssertEqual(cleared.text, "标题\n[ ] 牛奶")
        XCTAssertEqual(cleared.removed, 2)
    }

    func testSinkSettingDefaultsOn() {
        XCTAssertTrue(StickyChecklist.sinksDone(WidgetConfig()))
        XCTAssertFalse(StickyChecklist.sinksDone(WidgetConfig([StickyChecklist.sinkKey: .bool(false)])))
    }

    func testFadedInkStaysReadableOnEveryPaper() {
        for paper in PaperColor.allCases {
            let faded = PaperInk.faded(on: paper.hex)
            let contrast = PaperInk.contrast(paper: paper.hex, ink: faded)
            XCTAssertGreaterThanOrEqual(contrast, PaperInk.minimumContrast, "\(paper) 淡墨不到 4.5")
            let ink = PaperInk.contrast(paper: paper.hex, ink: paper.inkHex)
            if ink >= PaperInk.fadedContrast + 0.6 {
                XCTAssertLessThan(contrast, ink, "\(paper) 淡墨要比正文淡")
                XCTAssertLessThan(contrast, 5.6, "\(paper) 淡到约 5.0")
            }
        }
    }

    // MARK: 撕掉

    func testTearingPutsWrittenSheetsInTheTrash() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var config = WidgetConfig()
        StickyStack.store(StickyStack.Pile(sheets: [StickySheet(text: "一", color: "yellow"),
                                                    StickySheet(text: "二", color: "mint"),
                                                    StickySheet(text: "", color: "peach")], page: 1), in: &config)
        let torn = StickyTrash.tear(&config, now: now, id: "a")
        XCTAssertEqual(torn?.index, 1)
        XCTAssertEqual(torn?.entryID, "a")
        XCTAssertEqual(StickyStack.pile(config).sheets.map(\.text), ["一", ""])
        XCTAssertEqual(StickyTrash.entries(config, now: now).map(\.sheet.text), ["二"])

        // 空白的纸撕掉不进垃圾桶。
        let blank = StickyTrash.tear(&config, now: now, id: "b")
        XCTAssertNil(blank?.entryID)
        XCTAssertEqual(StickyTrash.entries(config, now: now).count, 1)
        XCTAssertEqual(StickyStack.pile(config).sheets.map(\.text), ["一"])
    }

    func testTearingTheLastSheetLeavesBlankPaper() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var config = WidgetConfig(["text": .string("唯一"), "color": .string("mint")])
        let torn = StickyTrash.tear(&config, now: now, id: "a")
        XCTAssertNotNil(torn)
        XCTAssertEqual(StickyStack.pile(config).front, StickySheet(text: "", color: "mint"))
        XCTAssertNil(StickyTrash.tear(&config, now: now, id: "b"), "只剩一张空白纸撕不了")
        // 撤销：空白纸换回原来那张，垃圾桶里拿掉。
        XCTAssertTrue(StickyTrash.undo(torn!, in: &config, now: now))
        XCTAssertEqual(StickyStack.pile(config).sheets, [StickySheet(text: "唯一", color: "mint")])
        XCTAssertTrue(StickyTrash.entries(config, now: now).isEmpty)
        XCTAssertNil(config[StickyTrash.key], "空了不留这一项")
    }

    func testUndoPutsTheSheetBackWhereItWas() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var config = WidgetConfig()
        let pile = StickyStack.Pile(sheets: [StickySheet(text: "一"), StickySheet(text: "二"), StickySheet(text: "三")], page: 1)
        StickyStack.store(pile, in: &config)
        let torn = StickyTrash.tear(&config, now: now, id: "x")!
        StickyTrash.undo(torn, in: &config, now: now)
        XCTAssertEqual(StickyStack.pile(config), pile)
    }

    // MARK: 垃圾桶

    func testRestoreGoesOnTop() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var config = WidgetConfig()
        StickyStack.store(StickyStack.Pile(sheets: [StickySheet(text: "一"), StickySheet(text: "二")], page: 0), in: &config)
        _ = StickyTrash.tear(&config, now: now, id: "t")
        XCTAssertEqual(StickyStack.pile(config).front.text, "二")
        XCTAssertTrue(StickyTrash.restore("t", in: &config, now: now.addingTimeInterval(60)))
        XCTAssertEqual(StickyStack.pile(config).front.text, "一", "恢复的放回最上面")
        XCTAssertEqual(StickyStack.pile(config).count, 2)
        XCTAssertFalse(StickyTrash.restore("t", in: &config, now: now), "已经恢复过了")
    }

    func testRestoreWaitsWhenThePileIsFull() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var config = WidgetConfig()
        let sheets = (0..<StickyStack.limit).map { StickySheet(text: "\($0)") }
        StickyStack.store(StickyStack.Pile(sheets: sheets), in: &config)
        _ = StickyTrash.tear(&config, now: now, id: "t")
        StickyStack.store(StickyStack.pile(config).adding(color: "yellow"), in: &config)
        XCTAssertFalse(StickyTrash.canRestore(config))
        XCTAssertFalse(StickyTrash.restore("t", in: &config, now: now))
        XCTAssertEqual(StickyTrash.entries(config, now: now).count, 1, "放不下时留在垃圾桶")
    }

    func testTrashKeepsSevenDaysAndThirtySheets() {
        let now = Date(timeIntervalSince1970: 10_000_000)
        var list: [StickyTrash.Entry] = []
        for i in 0..<40 {
            list.append(StickyTrash.Entry(id: "\(i)", sheet: StickySheet(text: "\(i)"),
                                          tornAt: now.addingTimeInterval(-Double(i) * 600)))
        }
        list.append(StickyTrash.Entry(id: "old", sheet: StickySheet(text: "old"),
                                      tornAt: now.addingTimeInterval(-StickyTrash.maxAge - 1)))
        let kept = StickyTrash.pruned(list.shuffled(), now: now)
        XCTAssertEqual(kept.count, StickyTrash.maxCount)
        XCTAssertEqual(kept.first?.id, "0", "最近的在前")
        XCTAssertEqual(kept.last?.id, "29")
        XCTAssertFalse(kept.contains { $0.id == "old" }, "超过 7 天的去掉")
    }

    func testTrashRoundTripsAndPurges() {
        let now = Date(timeIntervalSince1970: 10_000_000)
        var config = WidgetConfig()
        StickyTrash.store([StickyTrash.Entry(id: "a", sheet: StickySheet(text: "[x] 一\n[ ] 二", color: "mint"),
                                             tornAt: now),
                           StickyTrash.Entry(id: "b", sheet: StickySheet(text: "很久以前"),
                                             tornAt: now.addingTimeInterval(-8 * 24 * 3600))], in: &config)
        let read = StickyTrash.entries(config, now: now)
        XCTAssertEqual(read.map(\.id), ["a"])
        XCTAssertEqual(read.first?.sheet.color, "mint")
        XCTAssertEqual(read.first?.title, "一")
        XCTAssertEqual(read.first?.summary, "清单 1/2")
        XCTAssertTrue(StickyTrash.purge(&config, now: now))
        XCTAssertFalse(StickyTrash.purge(&config, now: now), "没变时不写")
        StickyTrash.delete("a", in: &config, now: now)
        XCTAssertNil(config[StickyTrash.key])
    }

    func testABrokenTrashIsReadLeniently() {
        let now = Date(timeIntervalSince1970: 10_000_000)
        let config = WidgetConfig([StickyTrash.key: .list([
            .string("junk"),
            .list([.string("mint")]),
            .list([.string("pink"), .string("好的"), .number(now.timeIntervalSince1970)]),
            .list([.string("pink"), .string("坏时间"), .number(.infinity)]),
        ])])
        let read = StickyTrash.entries(config, now: now)
        XCTAssertEqual(read.map(\.sheet.text), ["好的"])
        XCTAssertFalse(read[0].id.isEmpty, "旧项没有编号时补一个")
        XCTAssertTrue(StickyTrash.entries(WidgetConfig(), now: now).isEmpty, "旧便签没有垃圾桶")
    }

    func testOldNotesStillReadTheSame() {
        let config = WidgetConfig(["text": .string("[ ] 牛奶\n[x] 面包"), "color": .string("yellow")])
        let pile = StickyStack.pile(config)
        XCTAssertEqual(pile.count, 1)
        XCTAssertEqual(StickyChecklist.progress(pile.front.text).total, 2)
        var copy = config
        StickyStack.store(pile, in: &copy)
        XCTAssertEqual(copy, config)
    }

    func testTrashAges() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-15 06:13 北京时间
        XCTAssertEqual(StickyTrash.age(of: now.addingTimeInterval(-10), now: now, calendar: calendar), "刚刚")
        XCTAssertEqual(StickyTrash.age(of: now.addingTimeInterval(-300), now: now, calendar: calendar), "5 分钟前")
        XCTAssertEqual(StickyTrash.age(of: now.addingTimeInterval(-3 * 3600), now: now, calendar: calendar), "3 小时前")
        XCTAssertEqual(StickyTrash.age(of: now.addingTimeInterval(-20 * 3600), now: now, calendar: calendar), "昨天")
        XCTAssertEqual(StickyTrash.age(of: now.addingTimeInterval(-5 * 86400), now: now, calendar: calendar), "5 天前")
    }
}
