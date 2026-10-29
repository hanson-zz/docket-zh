import Foundation
import XCTest

/// 书签自定义图标：`icons` 映射的读写和兼容、文字图标的默认字和颜色、取图标的顺序、
/// 表单保存（新加 / 改名改网址）。
final class BookmarkIconTests: XCTestCase {
    private let links = ["GitHub https://github.com/hanson-zz/docket-zh",
                         "https://cn.bing.com",
                         "哔哩哔哩 https://www.bilibili.com",
                         "知乎 https://www.zhihu.com"]

    private func url(_ text: String) -> URL { URL(string: text)! }

    private func config(_ extra: [String: WidgetConfig.Value] = [:]) -> WidgetConfig {
        var values: [String: WidgetConfig.Value] = ["links": .list(links.map { .string($0) })]
        for (key, value) in extra { values[key] = value }
        return WidgetConfig(values)
    }

    // MARK: 兼容

    func testOldCardsWithoutTheMapKeepTheirLook() {
        let old = config()
        XCTAssertTrue(BookmarkIcons.stored(old).isEmpty)
        XCTAssertNil(BookmarkIcons.icon(for: url("https://cn.bing.com"), in: BookmarkIcons.stored(old)))
        XCTAssertTrue(BookmarkIcons.uploadFiles(old).isEmpty)
        // 只清理不写入时，没有映射的卡片配置一个键都不多。
        var pruned = old
        BookmarkIcons.prune(&pruned)
        XCTAssertEqual(pruned, old)
    }

    func testTheMapIsNotACatalogDefault() throws {
        let entry = try XCTUnwrap(WidgetCatalog.entry(.bookmarks))
        XCTAssertNil(entry.defaults[BookmarkIcons.key], "图标映射由面板写，不进设置页")
    }

    // MARK: 读写

    func testStoringEachKindRoundTrips() {
        var c = config()
        BookmarkIcons.store(.text("必应", color: 3), for: url("https://cn.bing.com"), in: &c)
        BookmarkIcons.store(.image(BookmarkIcons.uploadFileName(UUID(uuidString: "00000000-0000-0000-0000-0000000000AB")!)),
                            for: url("https://www.zhihu.com"), in: &c)
        BookmarkIcons.store(.site, for: url("https://www.bilibili.com"), in: &c)
        let stored = BookmarkIcons.stored(c)
        XCTAssertEqual(stored.count, 3)
        XCTAssertEqual(BookmarkIcons.icon(for: url("https://cn.bing.com"), in: stored), .text("必应", color: 3))
        XCTAssertEqual(BookmarkIcons.icon(for: url("https://www.zhihu.com"), in: stored),
                       .image("upload-00000000-0000-0000-0000-0000000000ab.png"))
        XCTAssertEqual(BookmarkIcons.icon(for: url("https://www.bilibili.com"), in: stored), .site)
        XCTAssertEqual(BookmarkIcons.uploadFiles(c), ["upload-00000000-0000-0000-0000-0000000000ab.png"])
    }

    func testLookupIgnoresCaseAndATrailingSlash() {
        var c = config()
        BookmarkIcons.store(.text("B", color: 0), for: url("https://cn.bing.com"), in: &c)
        let stored = BookmarkIcons.stored(c)
        XCTAssertEqual(BookmarkIcons.icon(for: url("https://CN.bing.com/"), in: stored), .text("B", color: 0))
    }

    func testStoringNilClearsAndStoringAgainReplaces() {
        var c = config()
        let bing = url("https://cn.bing.com")
        BookmarkIcons.store(.text("B", color: 0), for: bing, in: &c)
        BookmarkIcons.store(.text("必", color: 5), for: bing, in: &c)
        XCTAssertEqual(c.strings(BookmarkIcons.key).count, 1)
        XCTAssertEqual(BookmarkIcons.icon(for: bing, in: BookmarkIcons.stored(c)), .text("必", color: 5))
        BookmarkIcons.store(nil, for: bing, in: &c)
        XCTAssertNil(c[BookmarkIcons.key], "最后一个清掉后整个键去掉")
    }

    func testIconsOfRemovedBookmarksArePruned() {
        var c = config()
        BookmarkIcons.store(.text("知", color: 1), for: url("https://www.zhihu.com"), in: &c)
        BookmarkIcons.store(.image("upload-abc.png"), for: url("https://cn.bing.com"), in: &c)
        // 删掉必应。
        c.set("links", .list(BookmarkList.removing(url("https://cn.bing.com"), from: links).map { .string($0) }))
        BookmarkIcons.prune(&c)
        XCTAssertEqual(BookmarkIcons.stored(c).count, 1)
        XCTAssertTrue(BookmarkIcons.uploadFiles(c).isEmpty, "删掉的书签的上传图片不再算用到")
        // 存别的书签时也会顺手丢掉不在列表里的。
        BookmarkIcons.store(.text("X", color: 2), for: url("https://nowhere.example"), in: &c)
        XCTAssertNil(BookmarkIcons.icon(for: url("https://nowhere.example"), in: BookmarkIcons.stored(c)))
    }

    func testBrokenEntriesAreSkipped() {
        let c = config([BookmarkIcons.key: .list([
            .string("not json"),
            .string(#"{"url":"https://cn.bing.com","kind":"sparkles"}"#),
            .string(#"{"url":"https://cn.bing.com","kind":"image","file":"../../etc/passwd"}"#),
            .string(#"{"url":"https://cn.bing.com","kind":"text","text":"   "}"#),
            .string(#"{"url":"https://www.zhihu.com","kind":"text","text":"知乎日报","color":23}"#),
        ])])
        let stored = BookmarkIcons.stored(c)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(BookmarkIcons.icon(for: url("https://www.zhihu.com"), in: stored), .text("知乎", color: 3),
                       "多的字截到两个，越界的颜色折回色板")
    }

    func testAPathOutsideTheFolderIsNeverWritten() {
        var c = config()
        BookmarkIcons.store(.image("../secret.png"), for: url("https://cn.bing.com"), in: &c)
        XCTAssertNil(c[BookmarkIcons.key])
    }

    // MARK: 文字图标

    func testDefaultTextIsTheNamesFirstCharacter() {
        XCTAssertEqual(BookmarkIcons.defaultText(for: "github"), "G")
        XCTAssertEqual(BookmarkIcons.defaultText(for: "哔哩哔哩"), "哔")
        XCTAssertEqual(BookmarkIcons.defaultText(for: "  《知乎》"), "知")
        XCTAssertEqual(BookmarkIcons.defaultText(for: ""), "?")
        XCTAssertEqual(BookmarkIcons.defaultText(for: "github"), Bookmark(title: "github", url: url("https://github.com")).initial,
                       "和卡片原来的首字一致")
    }

    func testCleanTextKeepsAtMostTwoCharacters() {
        XCTAssertEqual(BookmarkIcons.cleanText(" gh "), "GH")
        XCTAssertEqual(BookmarkIcons.cleanText("知 乎 日报"), "知乎")
        XCTAssertEqual(BookmarkIcons.cleanText("👨‍👩‍👧‍👦a b"), "👨‍👩‍👧‍👦A", "表情按一个字算")
        XCTAssertNil(BookmarkIcons.cleanText("   "))
        XCTAssertEqual(BookmarkIcons.maxTextLength, 2)
    }

    func testPaletteHasTenColoursAndIndicesWrap() {
        XCTAssertEqual(BookmarkIcons.palette.count, 10)
        XCTAssertEqual(Set(BookmarkIcons.palette).count, 10)
        for hex in BookmarkIcons.palette {
            XCTAssertTrue(hex.hasPrefix("#") && hex.count == 7, hex)
        }
        XCTAssertEqual(BookmarkIcons.clampedColor(0), 0)
        XCTAssertEqual(BookmarkIcons.clampedColor(9), 9)
        XCTAssertEqual(BookmarkIcons.clampedColor(10), 0)
        XCTAssertEqual(BookmarkIcons.clampedColor(-1), 9)
    }

    func testDefaultColourIsStablePerSite() {
        let a = BookmarkIcons.defaultColor(for: url("https://www.github.com/x"))
        let b = BookmarkIcons.defaultColor(for: url("https://github.com"))
        XCTAssertEqual(a, b, "同一个网站同一种颜色，www. 不算")
        for link in Bookmark.list(links) {
            XCTAssertTrue(BookmarkIcons.palette.indices.contains(BookmarkIcons.defaultColor(for: link.url)))
        }
    }

    // MARK: 取图标

    func testCandidatesTryThePageIconThenTouchIconThenFavicon() {
        let page = url("https://www.zhihu.com/question/1")
        XCTAssertEqual(BookmarkIcons.iconCandidates(page: page, pageIcon: "https://static.zhihu.com/icon.png"),
                       [url("https://static.zhihu.com/icon.png"),
                        url("https://www.zhihu.com/apple-touch-icon.png"),
                        url("https://www.zhihu.com/favicon.ico")])
        // 页面没写 icon 时 LinkPreview 给的就是 /favicon.ico，不重复试。
        XCTAssertEqual(BookmarkIcons.iconCandidates(page: page, pageIcon: "https://www.zhihu.com/favicon.ico"),
                       [url("https://www.zhihu.com/favicon.ico"), url("https://www.zhihu.com/apple-touch-icon.png")])
        XCTAssertEqual(BookmarkIcons.iconCandidates(page: url("http://localhost:3000/a"), pageIcon: nil),
                       [url("http://localhost:3000/apple-touch-icon.png"), url("http://localhost:3000/favicon.ico")])
        XCTAssertTrue(BookmarkIcons.iconCandidates(page: url("mailto:a@b.c"), pageIcon: nil).isEmpty)
        XCTAssertEqual(BookmarkIcons.iconCandidates(page: page, pageIcon: "data:image/png;base64,AAAA").count, 2)
    }

    func testSiteFilesAreSharedPerHost() {
        XCTAssertEqual(BookmarkIcons.siteFileName(for: url("https://www.GitHub.com/a")), "github.com.png")
        XCTAssertEqual(BookmarkIcons.siteFileName(for: url("https://github.com/b")), "github.com.png")
        XCTAssertNil(BookmarkIcons.siteFileName(for: url("mailto:a@b.c")))
        XCTAssertNil(BookmarkIcons.siteFileName(for: url("obsidian://open?vault=x")))
    }

    func testUploadFileNames() {
        let name = BookmarkIcons.uploadFileName(UUID())
        XCTAssertTrue(BookmarkIcons.isUploadFileName(name))
        XCTAssertFalse(BookmarkIcons.isUploadFileName("upload-../../x.png"))
        XCTAssertFalse(BookmarkIcons.isUploadFileName("upload-a/b.png"))
        XCTAssertFalse(BookmarkIcons.isUploadFileName("photo.png"))
        XCTAssertFalse(BookmarkIcons.isUploadFileName("upload-abc.jpg"))
    }

    func testAutomaticRetryWaitsAfterAFailure() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(BookmarkIcons.shouldRetry(failed: nil, now: now))
        XCTAssertFalse(BookmarkIcons.shouldRetry(failed: now.addingTimeInterval(-60), now: now))
        XCTAssertTrue(BookmarkIcons.shouldRetry(failed: now.addingTimeInterval(-BookmarkIcons.retryAfter), now: now))
    }

    func testDownloadsThatAreNotIconsAreRejected() {
        XCTAssertFalse(BookmarkIcons.acceptsDownload(bytes: 43, pixelWidth: 1), "1×1 透明占位")
        XCTAssertFalse(BookmarkIcons.acceptsDownload(bytes: 5_000, pixelWidth: 8))
        XCTAssertFalse(BookmarkIcons.acceptsDownload(bytes: 3_000_000, pixelWidth: 1024))
        XCTAssertTrue(BookmarkIcons.acceptsDownload(bytes: 1_150, pixelWidth: 16))
        XCTAssertTrue(BookmarkIcons.acceptsDownload(bytes: 9_000, pixelWidth: 180))
    }

    // MARK: 表单保存

    func testSavingANewBookmarkAppends() {
        XCTAssertEqual(BookmarkList.saving(title: "笔记", url: url("https://notes.example.com"), replacing: nil, in: links),
                       .added(links + ["笔记 https://notes.example.com"]))
        XCTAssertEqual(BookmarkList.saving(title: "", url: url("https://notes.example.com"), replacing: nil, in: links),
                       .added(links + ["https://notes.example.com"]))
        XCTAssertEqual(BookmarkList.saving(title: "x", url: url("https://CN.bing.com/"), replacing: nil, in: links),
                       .duplicate)
        let full = (1...Bookmark.maxCount).map { "https://site\($0).com" }
        XCTAssertEqual(BookmarkList.saving(title: "", url: url("https://example.com"), replacing: nil, in: full), .full)
    }

    func testEditingKeepsThePlaceAndCanChangeTheAddress() {
        let bing = url("https://cn.bing.com")
        XCTAssertEqual(BookmarkList.saving(title: "必应", url: bing, replacing: bing, in: links),
                       .added([links[0], "必应 https://cn.bing.com", links[2], links[3]]))
        XCTAssertEqual(BookmarkList.saving(title: "必应", url: url("https://www.bing.com"), replacing: bing, in: links),
                       .added([links[0], "必应 https://www.bing.com", links[2], links[3]]))
        XCTAssertEqual(BookmarkList.saving(title: "", url: url("https://www.zhihu.com"), replacing: bing, in: links),
                       .duplicate, "改成另一个书签的网址算重复")
        // 编辑放满的列表不算超出。
        let full = (1...Bookmark.maxCount).map { "https://site\($0).com" }
        XCTAssertEqual(BookmarkList.saving(title: "一", url: url("https://site1.com"), replacing: url("https://site1.com"), in: full),
                       .added(["一 https://site1.com"] + full.dropFirst()))
    }

    func testFormAddressParsingMatchesTheList() {
        XCTAssertEqual(Bookmark.parseAddress(" bilibili.com "), url("https://bilibili.com"))
        XCTAssertEqual(Bookmark.parseAddress("https://github.com/x"), url("https://github.com/x"))
        XCTAssertNil(Bookmark.parseAddress("两个 词"))
        XCTAssertNil(Bookmark.parseAddress(""))
        XCTAssertNil(Bookmark.parseAddress("随便写点"))
    }
}
