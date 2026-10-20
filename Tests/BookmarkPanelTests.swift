import Foundation
import XCTest

/// 书签面板改版：面板里直接加、改名、删、排序，以及 Pro 的分组文件夹。
final class BookmarkPanelTests: XCTestCase {
    private let entries = ["GitHub https://github.com/hanson-zz/docket-zh",
                           "https://cn.bing.com",
                           "哔哩哔哩 https://www.bilibili.com",
                           "知乎 https://www.zhihu.com"]

    private func url(_ text: String) -> URL { URL(string: text)! }

    // MARK: 添加

    func testAddingAppendsAndRejectsDuplicatesAndJunk() {
        XCTAssertEqual(BookmarkList.adding(" notes.example.com ", to: entries),
                       .added(entries + ["https://notes.example.com"]))
        XCTAssertEqual(BookmarkList.adding("前端 笔记 https://notes.example.com", to: entries),
                       .added(entries + ["前端 笔记 https://notes.example.com"]))
        XCTAssertEqual(BookmarkList.adding("https://CN.bing.com/", to: entries), .duplicate)
        XCTAssertEqual(BookmarkList.adding("随便写点", to: entries), .invalid)
        let full = (1...Bookmark.maxCount).map { "https://site\($0).com" }
        XCTAssertEqual(BookmarkList.adding("https://example.com", to: full), .full)
    }

    func testTheCardStillShowsEightButDropsGoFurther() {
        XCTAssertEqual(Bookmark.tileLimit, 8)
        XCTAssertGreaterThan(Bookmark.dropLimit, Bookmark.tileLimit, "面板放得下更多，拖入不再停在 8 个")
        let nine = (1...9).map { "https://site\($0).com" }
        XCTAssertNotNil(Bookmark.adding(url("https://example.com"), to: nine))
    }

    func testAnEntryNeverKeepsACommaOrTheBareHostAsATitle() {
        let link = url("https://www.zhihu.com")
        XCTAssertEqual(BookmarkList.entry(title: "知乎, 问答", url: link), "知乎 问答 https://www.zhihu.com")
        XCTAssertEqual(BookmarkList.entry(title: "  ", url: link), "https://www.zhihu.com")
        XCTAssertEqual(BookmarkList.entry(title: "zhihu.com", url: link), "https://www.zhihu.com")
    }

    // MARK: 改名、删除、排序

    func testRenamingKeepsTheAddressAndAnEmptyNameFallsBack() {
        let renamed = BookmarkList.renaming(url("https://cn.bing.com"), to: "必应", in: entries)
        XCTAssertEqual(renamed[1], "必应 https://cn.bing.com")
        XCTAssertEqual(Bookmark(parsing: renamed[1])?.title, "必应")
        let cleared = BookmarkList.renaming(url("https://www.zhihu.com"), to: "", in: entries)
        XCTAssertEqual(cleared[3], "https://www.zhihu.com")
        XCTAssertEqual(BookmarkList.renaming(url("https://nowhere.example"), to: "x", in: entries), entries)
    }

    func testRemovingLeavesUnreadableEntriesAlone() {
        let mixed = ["随便写点"] + entries
        let removed = BookmarkList.removing(url("https://www.bilibili.com"), from: mixed)
        XCTAssertEqual(removed, ["随便写点", entries[0], entries[1], entries[3]])
    }

    func testMovingWithinAllAndWithinAGroup() {
        let all = Bookmark.list(entries).map(\.url)
        // 全部：第 0 个挪到最后。
        let down = BookmarkList.moving(from: 0, to: 3, visible: all, in: entries)
        XCTAssertEqual(down, [entries[1], entries[2], entries[3], entries[0]])
        let up = BookmarkList.moving(from: 3, to: 1, visible: all, in: entries)
        XCTAssertEqual(up, [entries[0], entries[3], entries[1], entries[2]])
        // 分组里只看得到第 1、3 个：互换它俩，别的不动。
        let visible = [all[1], all[3]]
        let swapped = BookmarkList.moving(from: 0, to: 1, visible: visible, in: entries)
        XCTAssertEqual(swapped, [entries[0], entries[2], entries[3], entries[1]])
        XCTAssertEqual(BookmarkList.moving(from: 1, to: 1, visible: all, in: entries), entries)
        XCTAssertEqual(BookmarkList.moving(from: 7, to: 0, visible: all, in: entries), entries)
    }

    // MARK: 分组

    func testGroupsRoundTripAndOldCardsHaveNone() {
        XCTAssertEqual(BookmarkGroups.groups(WidgetConfig()), [], "旧卡片没有分组")
        var config = WidgetConfig(["links": .list(entries.map { .string($0) })])
        let groups = [BookmarkGroup(name: "工作", urls: ["https://github.com/hanson-zz/docket-zh"]),
                      BookmarkGroup(name: "学习", urls: [])]
        BookmarkGroups.write(groups, into: &config)
        XCTAssertEqual(BookmarkGroups.groups(config), groups)
        XCTAssertEqual(config.strings("links"), entries, "写分组不碰书签列表")
        BookmarkGroups.write([], into: &config)
        XCTAssertNil(config.values[BookmarkGroups.key])
    }

    func testAnAddressWithAnEqualsSignSurvives() {
        let config = WidgetConfig([BookmarkGroups.key: .list([.string("搜索=https://x.com/?q=a https://y.com"),
                                                              .string("=https://z.com"),
                                                              .string("搜索=https://dup.com"),
                                                              .string("没有等号")])])
        XCTAssertEqual(BookmarkGroups.groups(config),
                       [BookmarkGroup(name: "搜索", urls: ["https://x.com/?q=a", "https://y.com"])])
    }

    func testGroupNamesAreCleanedAndCapped() {
        XCTAssertEqual(BookmarkGroups.cleanName("  工作=, 日常 "), "工作 日常")
        XCTAssertNil(BookmarkGroups.cleanName(" ,= "))
        XCTAssertEqual(BookmarkGroups.cleanName(String(repeating: "长", count: 30))?.count,
                       BookmarkGroups.maxNameLength)
        let one = BookmarkGroups.adding("工作", to: [])
        XCTAssertEqual(one, [BookmarkGroup(name: "工作")])
        XCTAssertNil(BookmarkGroups.adding("工作", to: one ?? []), "重名")
        let full = (1...BookmarkGroups.maxGroups).map { BookmarkGroup(name: "组\($0)") }
        XCTAssertNil(BookmarkGroups.adding("再来", to: full))
    }

    func testABookmarkLivesInOneGroupAtMost() {
        var groups = [BookmarkGroup(name: "工作"), BookmarkGroup(name: "学习")]
        let bing = url("https://cn.bing.com")
        groups = BookmarkGroups.moving(bing, to: "工作", in: groups)
        XCTAssertEqual(BookmarkGroups.group(of: url("https://CN.bing.com/"), in: groups), "工作")
        groups = BookmarkGroups.moving(bing, to: "学习", in: groups)
        XCTAssertEqual(groups[0].urls, [])
        XCTAssertEqual(groups[1].urls, ["https://cn.bing.com"])
        groups = BookmarkGroups.moving(bing, to: nil, in: groups)
        XCTAssertNil(BookmarkGroups.group(of: bing, in: groups))
        XCTAssertEqual(groups.count, 2, "移出分组不删分组")
    }

    func testRemovingAGroupKeepsItsBookmarksInAll() {
        let links = Bookmark.list(entries)
        let groups = [BookmarkGroup(name: "工作", urls: ["https://cn.bing.com"])]
        let left = BookmarkGroups.removing("工作", from: groups)
        XCTAssertEqual(left, [])
        XCTAssertEqual(BookmarkGroups.visible(links, tab: nil, groups: left, unlocked: true), links)
    }

    func testPruningDropsAddressesNoLongerListed() {
        let links = Bookmark.list(entries)
        let groups = [BookmarkGroup(name: "工作", urls: ["https://cn.bing.com", "https://gone.example"])]
        XCTAssertEqual(BookmarkGroups.pruned(groups, links: links),
                       [BookmarkGroup(name: "工作", urls: ["https://cn.bing.com"])])
    }

    // MARK: Pro

    func testWithoutProOnlyAllShowsAndNothingIsLost() {
        let links = Bookmark.list(entries)
        let groups = [BookmarkGroup(name: "工作", urls: ["https://cn.bing.com", "https://www.zhihu.com"])]
        XCTAssertEqual(BookmarkGroups.tabs(groups, unlocked: true), ["工作"])
        XCTAssertEqual(BookmarkGroups.tabs(groups, unlocked: false), [])
        XCTAssertEqual(BookmarkGroups.visible(links, tab: "工作", groups: groups, unlocked: true).map(\.title),
                       ["cn.bing.com", "知乎"])
        XCTAssertEqual(BookmarkGroups.visible(links, tab: "工作", groups: groups, unlocked: false), links,
                       "没解锁退回全部")
        XCTAssertNil(BookmarkGroups.selectedTab("工作", groups: groups, unlocked: false))
        XCTAssertNil(BookmarkGroups.selectedTab("已删", groups: groups, unlocked: true))
        XCTAssertFalse(ProLicenseGate.canUseBookmarkGroups(unlocked: false))
        XCTAssertTrue(ProLicenseGate.canUseBookmarkGroups(unlocked: true))
        XCTAssertFalse(ProFeatures.isProKind(.bookmarks), "书签整种免费")
    }
}
