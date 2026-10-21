import CoreGraphics
import Foundation
import XCTest

final class FolderBrowseTests: XCTestCase {

    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func entry(_ name: String, folder: Bool = false, ago: TimeInterval? = nil,
                       size: Int64? = nil, kind: String = "") -> FolderEntry {
        FolderEntry(url: URL(fileURLWithPath: "/Users/me/Downloads/\(name)"), name: name,
                    isFolder: folder, modified: ago.map { now.addingTimeInterval(-$0) },
                    size: folder ? nil : size, kind: kind)
    }

    // MARK: 设置

    func testFolderClickDefaultsToBrowseForOldState() throws {
        let json = #"{"version": 1, "customDock": {"position": "bottom"}}"#
        let state = try JSONDecoder().decode(PersistedState.self, from: Data(json.utf8))
        XCTAssertEqual(state.customDock.folderClick, .browse)
    }

    func testFolderClickRoundTripsAndUnknownFallsBack() throws {
        var settings = CustomDockSettings()
        settings.folderClick = .finder
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(CustomDockSettings.self, from: data).folderClick, .finder)

        let odd = #"{"folderClick": "somethingNew"}"#
        XCTAssertEqual(try JSONDecoder().decode(CustomDockSettings.self, from: Data(odd.utf8)).folderClick,
                       .browse, "a value from a newer build must not throw away the whole shelf")
    }

    // MARK: 隐藏文件

    func testHiddenRules() {
        XCTAssertTrue(FolderBrowse.isHidden(name: ".DS_Store", hiddenFlag: false))
        XCTAssertTrue(FolderBrowse.isHidden(name: ".git", hiddenFlag: false))
        XCTAssertTrue(FolderBrowse.isHidden(name: ".报告.pdf.icloud", hiddenFlag: false))
        XCTAssertTrue(FolderBrowse.isHidden(name: "Icon\r", hiddenFlag: false))
        XCTAssertTrue(FolderBrowse.isHidden(name: "隐藏的", hiddenFlag: true))
        XCTAssertTrue(FolderBrowse.isHidden(name: "", hiddenFlag: false))
        XCTAssertFalse(FolderBrowse.isHidden(name: "报价单.pdf", hiddenFlag: false))
        XCTAssertFalse(FolderBrowse.isHidden(name: "Icon", hiddenFlag: false))
    }

    // MARK: 排序

    func testModifiedNewestFirstUndatedLast() {
        let list = [entry("旧", ago: 9000), entry("无日期"), entry("新", ago: 60), entry("中", ago: 600)]
        XCTAssertEqual(FolderBrowse.sorted(list, by: .modified).map(\.name), ["新", "中", "旧", "无日期"])
    }

    func testNameUsesFinderOrder() {
        let list = [entry("file 10"), entry("file 2"), entry("b"), entry("A")]
        XCTAssertEqual(FolderBrowse.sorted(list, by: .name).map(\.name), ["A", "b", "file 2", "file 10"])
    }

    func testSizeLargestFirstFoldersLast() {
        let list = [entry("小", size: 10), entry("文件夹", folder: true), entry("大", size: 5000),
                    entry("中", size: 300)]
        XCTAssertEqual(FolderBrowse.sorted(list, by: .size).map(\.name), ["大", "中", "小", "文件夹"])
    }

    func testKindGroupsThenName() {
        let list = [entry("b.pdf", kind: "PDF"), entry("z", folder: true, kind: "Folder"),
                    entry("a.pdf", kind: "PDF"), entry("a", folder: true, kind: "Folder")]
        XCTAssertEqual(FolderBrowse.sorted(list, by: .kind).map(\.name), ["a", "z", "a.pdf", "b.pdf"])
    }

    func testDefaultSortIsModified() {
        XCTAssertEqual(FolderSort.defaultValue, .modified)
        XCTAssertEqual(FolderClickAction.defaultValue, .browse)
    }

    // MARK: 过滤

    func testFilterIgnoresCaseWidthAndSpaces() {
        let list = [entry("Report.PDF"), entry("截图 1.png"), entry("ＡＢＣ.txt"), entry("café.doc")]
        XCTAssertEqual(FolderBrowse.filter(list, query: "  report ").map(\.name), ["Report.PDF"])
        XCTAssertEqual(FolderBrowse.filter(list, query: "截图").map(\.name), ["截图 1.png"])
        XCTAssertEqual(FolderBrowse.filter(list, query: "abc").map(\.name), ["ＡＢＣ.txt"])
        XCTAssertEqual(FolderBrowse.filter(list, query: "cafe").map(\.name), ["café.doc"])
        XCTAssertEqual(FolderBrowse.filter(list, query: "   ").count, 4)
        XCTAssertTrue(FolderBrowse.filter(list, query: "没有").isEmpty)
        XCTAssertTrue(FolderBrowse.filter([], query: "a").isEmpty)
    }

    // MARK: 相对时间

    func testAgeBuckets() {
        func age(_ seconds: TimeInterval) -> FolderBrowse.Age {
            FolderBrowse.age(of: now.addingTimeInterval(-seconds), now: now)
        }
        XCTAssertEqual(age(-300), .justNow, "a date in the future reads as just now")
        XCTAssertEqual(age(59), .justNow)
        XCTAssertEqual(age(27 * 60), .minutes(27))
        XCTAssertEqual(age(2 * 3600 + 59), .hours(2))
        XCTAssertEqual(age(26 * 3600), .days(1))
        XCTAssertEqual(age(8 * 86400), .weeks(1))
        XCTAssertEqual(age(29 * 86400), .weeks(4))
        XCTAssertEqual(age(31 * 86400), .months(1))
        XCTAssertEqual(age(62 * 86400), .months(2))
        XCTAssertEqual(age(400 * 86400), .years(1))
    }

    func testRelativeTextIsLocalized() {
        let zh = FolderBrowse.relativeText(for: now.addingTimeInterval(-27 * 60), now: now,
                                           locale: Locale(identifier: "zh-Hans"))
        XCTAssertTrue(zh.contains("27"), zh)
        XCTAssertTrue(zh.contains("分钟"), zh)
        let en = FolderBrowse.relativeText(for: now.addingTimeInterval(-2 * 86400), now: now,
                                           locale: Locale(identifier: "en"))
        XCTAssertTrue(en.contains("2"), en)
        XCTAssertTrue(en.lowercased().contains("day"), en)
        XCTAssertEqual(FolderBrowse.relativeText(for: now, now: now, locale: Locale(identifier: "en")), "刚刚",
                       "the test bundle has no strings table, so tr returns the Chinese key")
    }

    // MARK: 子文件夹路径

    func testTrailAndParent() {
        let root = URL(fileURLWithPath: "/Users/me/Downloads", isDirectory: true)
        let deep = root.appendingPathComponent("视频/2026", isDirectory: true)
        XCTAssertEqual(FolderBrowse.trail(root: root, current: root), ["Downloads"])
        XCTAssertEqual(FolderBrowse.trail(root: root, current: deep), ["Downloads", "视频", "2026"])
        XCTAssertEqual(FolderBrowse.parent(of: deep, root: root)?.lastPathComponent, "视频")
        XCTAssertNil(FolderBrowse.parent(of: root, root: root))
        let elsewhere = URL(fileURLWithPath: "/tmp/x", isDirectory: true)
        XCTAssertEqual(FolderBrowse.trail(root: root, current: elsewhere), ["x"])
        XCTAssertNil(FolderBrowse.parent(of: elsewhere, root: root))
    }

    // MARK: 拖进来移动

    func testMovableSkipsSelfAncestorsAndSiblings() {
        let folder = URL(fileURLWithPath: "/Users/me/Downloads/视频", isDirectory: true)
        let sources = [
            URL(fileURLWithPath: "/Users/me/Desktop/a.mov"),
            URL(fileURLWithPath: "/Users/me/Desktop/a.mov"),
            URL(fileURLWithPath: "/Users/me/Downloads/视频/b.mov"),
            URL(fileURLWithPath: "/Users/me/Downloads/视频", isDirectory: true),
            URL(fileURLWithPath: "/Users/me/Downloads", isDirectory: true),
            URL(fileURLWithPath: "/Users/me/Downloads/视频片段.mov"),
        ]
        XCTAssertEqual(FolderBrowse.movable(sources, into: folder).map(\.lastPathComponent),
                       ["a.mov", "视频片段.mov"])
        XCTAssertTrue(FolderBrowse.movable([], into: folder).isEmpty)
    }

    // MARK: 窗口大小

    func testLayoutSixColumnsOnABigScreen() {
        let fit = FolderBrowse.layout(visible: CGSize(width: 1728, height: 1080))
        XCTAssertEqual(fit.columns, 6)
        let rowsShown = (fit.size.height - FolderBrowse.headerHeight - FolderBrowse.padding * 2)
            / (FolderBrowse.cellHeight + FolderBrowse.spacing)
        XCTAssertGreaterThan(rowsShown, 2.2)
        XCTAssertLessThan(rowsShown, 2.8)
    }

    func testLayoutShrinksOnASmallScreen() {
        let fit = FolderBrowse.layout(visible: CGSize(width: 500, height: 400))
        XCTAssertGreaterThanOrEqual(fit.columns, 3)
        XCTAssertLessThan(fit.columns, 6)
        XCTAssertLessThanOrEqual(fit.size.height, 240)
        XCTAssertGreaterThanOrEqual(fit.size.height, 220)
        let tiny = FolderBrowse.layout(visible: CGSize(width: 200, height: 200))
        XCTAssertEqual(tiny.columns, 3)
    }
}
