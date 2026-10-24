import XCTest

/// 便签运行时闪退（beta.32）：输入法组字时选区越界、清单和叠放的边界、垃圾桶重复编号。
final class StickyNoteCrashTests: XCTestCase {

    // MARK: 选区换算只用整数

    func testUTF16OffsetsMapToCharacters() {
        let text = "a😀中\n乙"   // 😀 占两个 UTF-16 单位
        XCTAssertEqual(StickyChecklist.characterOffset(in: text, utf16: 0), 0)
        XCTAssertEqual(StickyChecklist.characterOffset(in: text, utf16: 1), 1)
        XCTAssertEqual(StickyChecklist.characterOffset(in: text, utf16: 2), 1, "落在代理对中间算到这个字之前")
        XCTAssertEqual(StickyChecklist.characterOffset(in: text, utf16: 3), 2)
        XCTAssertEqual(StickyChecklist.characterOffset(in: text, utf16: 4), 3)
        XCTAssertEqual(StickyChecklist.characterOffset(in: text, utf16: 6), 5)
        XCTAssertEqual(StickyChecklist.characterOffset(in: text, utf16: -5), 0)
        XCTAssertEqual(StickyChecklist.characterOffset(in: text, utf16: 999), 5, "超出夹到末尾")
        XCTAssertEqual(StickyChecklist.characterOffset(in: "", utf16: 3), 0)
    }

    func testCombiningCharactersDoNotSplit() {
        let text = "e\u{301}x"   // é 是两个 UTF-16 单位、一个字
        XCTAssertEqual(StickyChecklist.characterOffset(in: text, utf16: 1), 0)
        XCTAssertEqual(StickyChecklist.characterOffset(in: text, utf16: 2), 1)
    }

    /// 组字时系统的选区比现在的字长（拼音还没上屏），不能崩，夹到最后一行。
    func testSelectionLongerThanTextDuringComposition() {
        let draft = "买菜\n[ ] 牛"
        let composing = draft + "nai"
        let range = StickyChecklist.lineRange(in: draft, utf16Location: (composing as NSString).length, length: 0)
        XCTAssertEqual(range, 1...1)
        XCTAssertEqual(StickyChecklist.lineRange(in: "", utf16Location: 40, length: 10), 0...0)
    }

    func testBrokenRangesAreClamped() {
        let text = "一\n二\n三"
        XCTAssertEqual(StickyChecklist.lineRange(in: text, utf16Location: NSNotFound, length: 0), 0...0)
        XCTAssertEqual(StickyChecklist.lineRange(in: text, utf16Location: -3, length: -9), 0...0)
        XCTAssertEqual(StickyChecklist.lineRange(in: text, utf16Location: 2, length: Int.max), 1...2, "长度溢出不崩")
        XCTAssertEqual(StickyChecklist.lineRange(in: text, utf16Location: 0, length: 2), 0...0, "选到下一行开头不算下一行")
    }

    // MARK: 清单和叠放的边界

    func testEditsIgnoreOutOfRangeLines() {
        let text = "[ ] 牛奶\n[x] 面包"
        XCTAssertEqual(StickyChecklist.toggling(line: -1, in: text), text)
        XCTAssertEqual(StickyChecklist.toggling(line: 2, in: text), text)
        XCTAssertEqual(StickyChecklist.toggling(line: 0, in: ""), "")
        XCTAssertEqual(StickyChecklist.togglingItems("", lines: -4...(-1)), "[ ] ")
        XCTAssertEqual(StickyChecklist.togglingItems("一\n二", lines: 9...99), "一\n[ ] 二")
        XCTAssertEqual(StickyChecklist.submitting("").text, "")
        XCTAssertEqual(StickyChecklist.removingDone("").removed, 0)
    }

    /// 勾掉以后行号不变：沉底只是显示，原文每行还在原来的位置，按行号再勾不会认错。
    func testToggleKeepsRowIndicesStable() {
        var text = "采购\n[ ] 牛奶\n[ ] 面包\n[ ] 鸡蛋"
        text = StickyChecklist.toggling(line: 1, in: text)
        let layout = StickyChecklist.layout(text, sinkDone: true)
        XCTAssertEqual(layout.open.map(\.index), [0, 2, 3])
        XCTAssertEqual(layout.done.map(\.index), [1])
        let ids = (layout.open + layout.done).map(\.index)
        XCTAssertEqual(Set(ids).count, ids.count, "行号不重复，ForEach 不会认重")
        text = StickyChecklist.toggling(line: 3, in: text)
        XCTAssertEqual(StickyChecklist.progress(text).done, 2)
    }

    func testPileSurvivesBadStoredValues() {
        for page in [-1e300, -1, 0, 3, 99, 1e300, .nan, .infinity] {
            let config = WidgetConfig(["text": .string("a"), "stack": .list([.list([.string("mint"), .string("b")])]),
                                       "page": .number(page)])
            let pile = StickyStack.pile(config)
            XCTAssertTrue(pile.sheets.indices.contains(pile.page))
            _ = pile.front
            _ = pile.flipped(by: Int.max / 2).front
        }
        let empty = StickyStack.Pile(sheets: [], page: 7)
        XCTAssertEqual(empty.count, 1)
        XCTAssertNil(empty.tearingFront())
    }

    // MARK: 垃圾桶

    func testDuplicateTrashIDsAreMadeUnique() {
        let now = Date(timeIntervalSince1970: 10_000_000)
        let t = now.timeIntervalSince1970
        var config = WidgetConfig([StickyTrash.key: .list([
            .list([.string("mint"), .string("一"), .number(t), .string("dup")]),
            .list([.string("pink"), .string("二"), .number(t - 1), .string("dup")]),
            .list([.string("pink"), .string("三"), .number(t - 2), .string("dup-2")]),
        ])])
        let read = StickyTrash.entries(config, now: now)
        XCTAssertEqual(read.count, 3)
        XCTAssertEqual(Set(read.map(\.id)).count, 3, "编号不重复，列表和恢复不会认错")
        StickyTrash.delete(read[1].id, in: &config, now: now)
        XCTAssertEqual(StickyTrash.entries(config, now: now).map(\.sheet.text), ["一", "三"], "只删一张")
    }

    func testRestoreTwiceDoesNotDuplicate() {
        let now = Date(timeIntervalSince1970: 10_000_000)
        var config = WidgetConfig(["text": .string("留着")])
        guard StickyTrash.tear(&config, now: now, id: "x") != nil else { return XCTFail("应能撕") }
        XCTAssertTrue(StickyTrash.restore("x", in: &config, now: now))
        XCTAssertFalse(StickyTrash.restore("x", in: &config, now: now), "已经恢复过的不会再放回一张")
        XCTAssertEqual(StickyStack.pile(config).count, 1)
    }
}
