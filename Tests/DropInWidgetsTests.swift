import XCTest

/// 拖文字或文件到 AI 任意门、拖链接到书签、拖文字到便签。
final class DropInWidgetsTests: XCTestCase {
    // MARK: 提示

    func testNewDropTargetsReuseTheFourColors() {
        XCTAssertEqual(DropPrompt.askAI.tint, .blue, "拿去问和发出去一样是蓝")
        XCTAssertEqual(DropPrompt.bookmark.tint, .teal, "存下来是青")
        XCTAssertEqual(DropPrompt.stickyNote.tint, .orange, "记下来是橙")
        XCTAssertEqual(DropPrompt.askAI.title, "拿去问 AI")
        XCTAssertEqual(DropPrompt.bookmark.title, "加一条书签")
        XCTAssertEqual(DropPrompt.stickyNote.title, "贴到便签上")
        for prompt in [DropPrompt.askAI, .bookmark, .stickyNote] {
            XCTAssertEqual(prompt.compactTitle.split(separator: "\n").count, 2, "\(prompt)")
            XCTAssertFalse(prompt.caption.isEmpty)
            XCTAssertFalse(prompt.symbol.isEmpty)
        }
    }

    // MARK: 便签

    func testStickyAppendsALine() {
        let pile = StickyStack.Pile(sheets: [StickySheet(text: "买咖啡\n", color: "yellow")])
        XCTAssertEqual(pile.appendingLine("  给小王回电话 ").front.text, "买咖啡\n给小王回电话")
        let blank = StickyStack.Pile(sheets: [StickySheet()])
        XCTAssertEqual(blank.appendingLine("第一行").front.text, "第一行", "空白的纸直接写上")
        XCTAssertEqual(pile.appendingLine("  \n "), pile, "空白不动")
    }

    func testStickyAppendsToTheFrontSheetOnly() {
        let pile = StickyStack.Pile(sheets: [StickySheet(text: "一"), StickySheet(text: "二", color: "mint")], page: 1)
        let next = pile.appendingLine("三")
        XCTAssertEqual(next.sheets[0].text, "一")
        XCTAssertEqual(next.sheets[1].text, "二\n三")
        XCTAssertEqual(next.page, 1)
    }

    // MARK: 书签

    func testDroppedTextMustBeOneAddress() {
        XCTAssertEqual(Bookmark.dropped(" https://example.com/a ")?.absoluteString, "https://example.com/a")
        XCTAssertEqual(Bookmark.dropped("bilibili.com")?.absoluteString, "https://bilibili.com")
        XCTAssertNil(Bookmark.dropped("看看 https://example.com"), "一句话里带网址不算")
        XCTAssertNil(Bookmark.dropped("随便写点"))
        XCTAssertNil(Bookmark.dropped(""))
    }

    func testAddingSkipsDuplicatesAndStopsWhenFull() {
        let entries = ["GitHub https://github.com/hanson-zz/docket-zh"]
        let url = URL(string: "https://example.com")!
        XCTAssertEqual(Bookmark.adding(url, to: entries), entries + ["https://example.com"])
        XCTAssertNil(Bookmark.adding(URL(string: "https://GitHub.com/hanson-zz/docket-zh/")!, to: entries),
                     "同一个地址（大小写、结尾斜杠不同）不重复加")
        let full = (1...Bookmark.dropLimit).map { "https://site\($0).com" }
        XCTAssertNil(Bookmark.adding(url, to: full), "卡片上放满了")
    }

    // MARK: AI 任意门

    func testAIDropComposesTextAndFiles() {
        let prompt = AIDrop.compose(texts: ["  这段是什么意思？ "],
                                    files: [AIDrop.File(name: "notes.md", path: "/tmp/notes.md", contents: "# 标题\n内容"),
                                            AIDrop.File(name: "photo.png", path: "/tmp/photo.png", contents: nil)])
        XCTAssertEqual(prompt, "这段是什么意思？\n\n文件 notes.md：\n# 标题\n内容\n\n文件：/tmp/photo.png")
        XCTAssertNil(AIDrop.compose(texts: [" \n"], files: []))
    }

    func testAIDropIsCappedAtTheClipboardLimit() {
        let long = String(repeating: "字", count: AIClipboard.insertLimit + 100)
        XCTAssertEqual(AIDrop.compose(texts: [long], files: [])?.count, AIClipboard.insertLimit)
        let many = (1...9).map { AIDrop.File(name: "f\($0)", path: "/f\($0)", contents: nil) }
        let composed = AIDrop.compose(texts: [], files: many) ?? ""
        XCTAssertEqual(composed.components(separatedBy: "\n\n").count, AIDrop.maxFiles)
    }
}
