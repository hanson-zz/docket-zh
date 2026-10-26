import XCTest

/// 便签 v3：清单行编辑和显示统一（原文 ↔ 编辑器的一行对一行）、回车、光标、发到快速待办。
final class StickyNoteV3Tests: XCTestCase {
    private let m = String(StickyEditing.mark)

    // MARK: 原文 ↔ 编辑器

    func testDisplayReplacesBoxesWithOneMark() {
        let text = "周末采购\n[ ] 牛奶\n- [x] 鸡蛋\n【】面包\n普通一行"
        XCTAssertEqual(StickyEditing.display(text), "周末采购\n\(m)牛奶\n- \(m)鸡蛋\n\(m)面包\n普通一行")
    }

    func testRoundTripKeepsEveryOriginalSpelling() {
        // 没动过的行一字不差地还原：打开便签不会被改写、多存一次。
        let text = "【】面包\n- [ ]牛奶\n  * [X]  缩进\n☐ 五\n[✔] 十三\n[1]对对对\n\n结尾"
        XCTAssertEqual(StickyEditing.raw(StickyEditing.pieces(text)), text)
        for piece in StickyEditing.pieces(text) {
            var runs: [StickyEditing.Run] = []
            if !piece.prefix.isEmpty { runs.append(.text(piece.prefix)) }
            if let box = piece.box { runs.append(.box(box)) }
            runs.append(.text(piece.rest))
            XCTAssertEqual(StickyEditing.rawLine(runs), piece.raw)
        }
    }

    func testLineCountMatches() {
        let text = "[ ] a\n\nb\n[x] c\n"
        XCTAssertEqual(StickyEditing.display(text).split(separator: "\n", omittingEmptySubsequences: false).count,
                       text.split(separator: "\n", omittingEmptySubsequences: false).count)
    }

    func testPieceParts() {
        let piece = StickyEditing.pieces("  - [x] 牛奶 两盒")[0]
        XCTAssertEqual(piece.prefix, "  - ")
        XCTAssertEqual(piece.box, StickyEditing.Box(token: "[x] ", done: true))
        XCTAssertEqual(piece.rest, "牛奶 两盒")
    }

    func testMarkMovedMidLineIsDropped() {
        // 删掉换行把下一条接上来：圆圈落到行中间，去掉它，字留下。
        let open = StickyEditing.Box.open
        XCTAssertEqual(StickyEditing.rawLine([.text("牛奶"), .box(open), .text("鸡蛋")]), "牛奶鸡蛋")
        // 第二个圆圈也去掉。
        XCTAssertEqual(StickyEditing.rawLine([.box(open), .text("a"), .box(open), .text("b")]), "[ ] ab")
        // 缩进和列表符号之后的圆圈照认。
        XCTAssertEqual(StickyEditing.rawLine([.text("  - "), .box(open), .text("x")]), "  - [ ] x")
        XCTAssertEqual(StickyEditing.rawLine([.text("ab "), .box(open), .text("x")]), "ab x")
    }

    func testStrayMarkCharactersAreRemoved() {
        XCTAssertEqual(StickyEditing.rawLine([.text("a\u{FFFC}b")]), "ab")
    }

    func testToggledBoxUsesCanonicalToken() {
        XCTAssertEqual(StickyEditing.Box(token: "【】", done: false).toggled, .init(token: "[x] ", done: true))
        XCTAssertEqual(StickyEditing.Box(token: "☑", done: true).toggled, .init(token: "[ ] ", done: false))
    }

    // MARK: 回车

    func testComposingAlwaysPassesThrough() {
        // 输入法组字时回车用来上屏，不能插行（2e38f63 组字闪退那一类问题）。
        let item = StickyEditing.pieces("[ ] 牛奶")[0]
        for command in [false, true] {
            for shift in [false, true] {
                XCTAssertEqual(StickyEditing.returnAction(command: command, shift: shift, option: false,
                                                          composing: true, line: item), .passThrough)
            }
        }
    }

    func testReturnOnItems() {
        let item = StickyEditing.pieces("[ ] 牛奶")[0]
        let empty = StickyEditing.pieces("[ ]  ")[0]
        let plain = StickyEditing.pieces("随手一行")[0]
        func action(_ line: StickyEditing.Piece?, command: Bool = false, shift: Bool = false, option: Bool = false) -> StickyEditing.Return {
            StickyEditing.returnAction(command: command, shift: shift, option: option, composing: false, line: line)
        }
        XCTAssertEqual(action(item), .nextItem)
        XCTAssertEqual(action(empty), .endItem)
        XCTAssertEqual(action(plain), .newline)
        XCTAssertEqual(action(nil), .newline)
        XCTAssertEqual(action(item, shift: true), .newline)
        XCTAssertEqual(action(item, option: true), .newline)
        XCTAssertEqual(action(item, command: true), .collapse)
        XCTAssertEqual(action(plain, command: true), .collapse)
    }

    func testNextItemKeepsIndentAndBullet() {
        let item = StickyEditing.pieces("  - [x] 牛奶")[0]
        let next = StickyEditing.nextItem(after: item)
        XCTAssertEqual(next.raw, "  - [ ] ")
        XCTAssertEqual(next.display, "  - \(m)")
    }

    func testEndingItemKeepsOnlyIndent() {
        let item = StickyEditing.pieces("  - [ ] ")[0]
        XCTAssertEqual(StickyEditing.endingItem(item).raw, "  ")
        XCTAssertEqual(StickyEditing.endingItem(StickyEditing.pieces("[ ]")[0]).raw, "")
    }

    // MARK: 光标

    func testCaretAnchorSurvivesBoxConversion() {
        // 打了「[ ] 牛」，框子变成圆圈：光标还在「牛」后面。
        let before = "abc\n[ ] 牛"
        let caret = (before as NSString).length
        let anchor = StickyEditing.caretAnchor(in: before, utf16: caret)
        XCTAssertEqual(anchor.line, 1)
        XCTAssertEqual(anchor.fromEnd, 0)
        let after = "abc\n\(m)牛"
        XCTAssertEqual(StickyEditing.location(in: after, line: anchor.line, fromEnd: anchor.fromEnd),
                       (after as NSString).length)
    }

    func testLocationNeverLandsBeforeTheCircle() {
        let display = "\(m)牛奶\n\(m)"
        XCTAssertEqual(StickyEditing.location(in: display, line: 0, fromEnd: 99), 1)
        // 空的一条：光标在圆圈后面。
        XCTAssertEqual(StickyEditing.location(in: display, line: 1, fromEnd: 0), 5)
        XCTAssertEqual(StickyEditing.location(in: display, line: 1, fromEnd: 3), 5)
        // 行号越界：放到末尾。
        XCTAssertEqual(StickyEditing.location(in: display, line: 9, fromEnd: 0), 5)
        XCTAssertEqual(StickyEditing.location(in: "", line: 0, fromEnd: 0), 0)
    }

    func testCaretAnchorClampsOutOfRange() {
        XCTAssertEqual(StickyEditing.caretAnchor(in: "ab", utf16: 99).line, 0)
        XCTAssertEqual(StickyEditing.caretAnchor(in: "ab", utf16: -3).fromEnd, 2)
        // 表情是两个 UTF-16 单位：只用整数，不碰外来的 String.Index。
        XCTAssertEqual(StickyEditing.caretAnchor(in: "😀\nx", utf16: 1).line, 0)
    }

    func testAdjustedCaretSkipsTheCircle() {
        let display = "上一行\n\(m)牛奶"
        let markAt = 4
        // 点到圆圈前面：放到圆圈后面。
        XCTAssertEqual(StickyEditing.adjustedCaret(in: display, from: 0, to: markAt), markAt + 1)
        // 从圆圈后面往左：跳到上一行行尾。
        XCTAssertEqual(StickyEditing.adjustedCaret(in: display, from: markAt + 1, to: markAt), markAt - 1)
        // 第一行就是圆圈，往左没地方去：留在圆圈后面。
        XCTAssertEqual(StickyEditing.adjustedCaret(in: "\(m)a", from: 1, to: 0), 1)
        // 别处不动。
        XCTAssertEqual(StickyEditing.adjustedCaret(in: display, from: 0, to: 2), 2)
        XCTAssertEqual(StickyEditing.adjustedCaret(in: display, from: 0, to: 99), 99)
    }

    // MARK: 发到快速待办

    func testSendableLine() {
        let text = "周末采购\n[ ] 牛奶 两盒\n- 交房租\n\n[x]   "
        XCTAssertEqual(StickyEditing.sendable(line: 0, in: text), "周末采购")
        XCTAssertEqual(StickyEditing.sendable(line: 1, in: text), "牛奶 两盒")
        XCTAssertEqual(StickyEditing.sendable(line: 2, in: text), "交房租")
        XCTAssertNil(StickyEditing.sendable(line: 3, in: text))
        XCTAssertNil(StickyEditing.sendable(line: 4, in: text))
        XCTAssertNil(StickyEditing.sendable(line: 9, in: text))
        XCTAssertNil(StickyEditing.sendable(line: -1, in: text))
        let long = String(repeating: "长", count: 500)
        XCTAssertEqual(StickyEditing.sendable(line: 0, in: long)?.count, QuickTodo.maxLength)
    }

    func testSendingDoesNotChangeTheNote() {
        // 原行保留：只读不改。
        let text = "[ ] 牛奶"
        _ = StickyEditing.sendable(line: 0, in: text)
        XCTAssertEqual(text, "[ ] 牛奶")
    }
}
