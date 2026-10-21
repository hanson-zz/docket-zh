import CoreGraphics
import Foundation
import XCTest

final class FolderGroupsTests: XCTestCase {

    private func folder(_ path: String, id: UUID = UUID()) -> DockItem {
        .folder(id: id, ref: FileRef(url: URL(fileURLWithPath: path)), icon: FolderIcon())
    }

    private func app(_ bundleID: String) -> DockItem {
        .app(id: UUID(), bundleID: bundleID,
             ref: FileRef(url: URL(fileURLWithPath: "/Applications/\(bundleID).app")))
    }

    private func folderGroup(_ name: String = "文件夹分组", _ items: [DockItem] = [],
                             selected: UUID? = nil, id: UUID = UUID()) -> DockItem {
        .group(DockGroup(id: id, name: name, items: items, keepsEmpty: true,
                         kind: .folders, selectedFolder: selected))
    }

    private func groupIn(_ items: [DockItem], _ id: UUID) -> DockGroup? {
        items.first { $0.id == id }?.group
    }

    // MARK: 新建

    func testNewFolderGroupIsEmptyKeptAndNamedAroundAllGroups() {
        let shelf = [app("a"), .group(DockGroup(name: "文件夹分组", items: [app("b"), app("c")]))]
        let id = UUID()
        let (items, made) = FolderGroups.addingEmptyGroup(named: "文件夹分组", in: shelf, id: id)
        XCTAssertEqual(made, id)
        XCTAssertEqual(items.count, 3)
        let group = try! XCTUnwrap(items.last?.group)
        XCTAssertEqual(group.name, "文件夹分组 2")
        XCTAssertTrue(group.isFolderGroup)
        XCTAssertTrue(group.keepsWhenSmall)
        XCTAssertTrue(group.items.isEmpty)
        XCTAssertNil(group.selectedFolder)
    }

    func testEmptyFolderGroupSurvivesOnTheShelf() {
        let shelf = [folderGroup(), app("a")]
        XCTAssertEqual(ShelfItems.displayed(profile: shelf, mirrored: [], mirroring: false).count, 2)
        let one = [folderGroup("G", [folder("/tmp/a")])]
        XCTAssertTrue(ShelfItems.dissolvingSmallGroups(in: one).first?.group?.isFolderGroup == true)
    }

    // MARK: 旧数据

    func testOldGroupsDecodeAsAppGroups() throws {
        let old = #"{"id":"\#(UUID().uuidString)","name":"Work","tint":"none","items":[]}"#
        let group = try JSONDecoder().decode(DockGroup.self, from: Data(old.utf8))
        XCTAssertNil(group.kind)
        XCTAssertFalse(group.isFolderGroup)
        XCTAssertNil(group.selectedFolder)
    }

    func testFolderGroupRoundTrips() throws {
        let pick = UUID()
        let original = DockGroup(name: "常用", items: [folder("/tmp/a", id: pick)], keepsEmpty: true,
                                 kind: .folders, selectedFolder: pick)
        let data = try JSONEncoder().encode(original)
        let back = try JSONDecoder().decode(DockGroup.self, from: data)
        XCTAssertEqual(back, original)
        XCTAssertTrue(back.isFolderGroup)
        XCTAssertEqual(back.selectedFolder, pick)
    }

    // MARK: 只收文件夹

    func testAcceptsOnlyPlainDirectories() {
        XCTAssertTrue(FolderGroups.accepts(isDirectory: true, isPackage: false))
        XCTAssertFalse(FolderGroups.accepts(isDirectory: true, isPackage: true))
        XCTAssertFalse(FolderGroups.accepts(isDirectory: false, isPackage: false))
    }

    func testIsFolderReadsTheDisk() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderGroupsTests-\(UUID().uuidString)")
        let dir = base.appendingPathComponent("资料")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = base.appendingPathComponent("a.txt")
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: base) }
        XCTAssertTrue(FolderGroups.isFolder(dir))
        XCTAssertFalse(FolderGroups.isFolder(file))
        XCTAssertFalse(FolderGroups.isFolder(base.appendingPathComponent("不存在")))
    }

    func testCombineIntoFolderGroupOnlyTakesFolders() {
        let target = folderGroup()
        XCTAssertTrue(FolderGroups.canCombine(folder("/tmp/a"), into: target))
        XCTAssertFalse(FolderGroups.canCombine(app("a"), into: target))
        // 应用分组和普通格子照旧什么都能合。
        let appGroup = DockItem.group(DockGroup(name: "G", items: [app("x"), app("y")]))
        XCTAssertTrue(FolderGroups.canCombine(folder("/tmp/a"), into: appGroup))
        XCTAssertTrue(FolderGroups.canCombine(app("a"), into: app("b")))
    }

    func testDraggingAnAppOntoAFolderGroupChangesNothing() {
        let gid = UUID()
        let a = app("a")
        let shelf = [a, folderGroup(id: gid)]
        XCTAssertEqual(ShelfItems.combining(a.id, into: gid, named: "x", in: shelf), shelf)
        let f = folder("/tmp/f")
        let joined = ShelfItems.combining(f.id, into: gid, named: "x", in: [f, folderGroup(id: gid)])
        XCTAssertEqual(joined.count, 1)
        XCTAssertEqual(joined.first?.group?.items.count, 1)
    }

    // MARK: 加入

    func testAddingFoldersSkipsDuplicatesAndNonFolders() {
        let gid = UUID()
        let existing = folder("/Users/me/Downloads")
        let shelf = [folderGroup("G", [existing], id: gid)]
        let result = FolderGroups.adding([folder("/Users/me/Downloads"), folder("/Users/me/Desktop"),
                                          app("a"), folder("/Users/me/Desktop")],
                                         toGroup: gid, in: shelf)
        let group = try! XCTUnwrap(groupIn(result, gid))
        XCTAssertEqual(group.items.count, 2)
        XCTAssertEqual(group.items.last?.fileRef?.url.lastPathComponent, "Desktop")
    }

    func testFirstFolderIntoAnEmptyGroupBecomesSelected() {
        let gid = UUID()
        let first = folder("/a")
        let result = FolderGroups.adding([first, folder("/b")], toGroup: gid, in: [folderGroup(id: gid)])
        XCTAssertEqual(groupIn(result, gid)?.selectedFolder, first.id)
    }

    func testAddingToAnAppGroupIsLeftAlone() {
        let gid = UUID()
        let shelf: [DockItem] = [.group(DockGroup(id: gid, name: "G", items: [app("a"), app("b")]))]
        XCTAssertEqual(FolderGroups.adding([folder("/a")], toGroup: gid, in: shelf), shelf)
        XCTAssertEqual(FolderGroups.adding([folder("/a")], toGroup: UUID(), in: shelf), shelf)
    }

    func testFolderItemCarriesThePath() {
        let item = FolderGroups.folderItem(for: URL(fileURLWithPath: "/Users/me/项目"))
        guard case .folder(_, let ref, let icon) = item else { return XCTFail("不是文件夹") }
        XCTAssertEqual(ref.url.lastPathComponent, "项目")
        XCTAssertTrue(icon.isEmpty)
    }

    // MARK: 移除

    func testRemovingKeepsTheGroupEvenWhenEmpty() {
        let gid = UUID()
        let only = folder("/a")
        let shelf = [folderGroup("G", [only], selected: only.id, id: gid), app("x")]
        let result = FolderGroups.removing(only.id, fromGroup: gid, in: shelf)
        XCTAssertEqual(result.count, 2, "组和旁边的 App 都在，文件夹不放回扩展栏")
        let group = try! XCTUnwrap(groupIn(result, gid))
        XCTAssertTrue(group.items.isEmpty)
        XCTAssertNil(group.selectedFolder)
        XCTAssertNil(FolderGroups.selected(in: group))
    }

    func testRemovingTheSelectedMovesToItsRightThenLeft() {
        let gid = UUID()
        let a = folder("/a"), b = folder("/b"), c = folder("/c")
        let shelf = [folderGroup("G", [a, b, c], selected: b.id, id: gid)]
        let afterB = FolderGroups.removing(b.id, fromGroup: gid, in: shelf)
        XCTAssertEqual(groupIn(afterB, gid)?.selectedFolder, c.id)
        let lastPicked = [folderGroup("G", [a, b, c], selected: c.id, id: gid)]
        let afterC = FolderGroups.removing(c.id, fromGroup: gid, in: lastPicked)
        XCTAssertEqual(groupIn(afterC, gid)?.selectedFolder, b.id)
    }

    func testRemovingAnotherKeepsTheSelection() {
        let gid = UUID()
        let a = folder("/a"), b = folder("/b")
        let shelf = [folderGroup("G", [a, b], selected: b.id, id: gid)]
        let result = FolderGroups.removing(a.id, fromGroup: gid, in: shelf)
        XCTAssertEqual(groupIn(result, gid)?.items.map(\.id), [b.id])
        XCTAssertEqual(groupIn(result, gid)?.selectedFolder, b.id)
        XCTAssertEqual(FolderGroups.removing(UUID(), fromGroup: gid, in: shelf), shelf)
    }

    // MARK: 重排

    func testMovingClampsAndKeepsEveryone() {
        let gid = UUID()
        let a = folder("/a"), b = folder("/b"), c = folder("/c")
        let shelf = [folderGroup("G", [a, b, c], id: gid)]
        XCTAssertEqual(groupIn(FolderGroups.moving(c.id, to: 0, inGroup: gid, in: shelf), gid)?.items.map(\.id),
                       [c.id, a.id, b.id])
        XCTAssertEqual(groupIn(FolderGroups.moving(a.id, to: 99, inGroup: gid, in: shelf), gid)?.items.map(\.id),
                       [b.id, c.id, a.id])
        XCTAssertEqual(groupIn(FolderGroups.moving(b.id, to: -3, inGroup: gid, in: shelf), gid)?.items.map(\.id),
                       [b.id, a.id, c.id])
        XCTAssertEqual(FolderGroups.moving(UUID(), to: 0, inGroup: gid, in: shelf), shelf)
    }

    func testShiftingLeftAndRight() {
        let gid = UUID()
        let a = folder("/a"), b = folder("/b"), c = folder("/c")
        let shelf = [folderGroup("G", [a, b, c], id: gid)]
        XCTAssertEqual(groupIn(FolderGroups.shifting(b.id, by: -1, inGroup: gid, in: shelf), gid)?.items.map(\.id),
                       [b.id, a.id, c.id])
        XCTAssertEqual(groupIn(FolderGroups.shifting(b.id, by: 1, inGroup: gid, in: shelf), gid)?.items.map(\.id),
                       [a.id, c.id, b.id])
        // 两端再往外挪不变。
        XCTAssertEqual(groupIn(FolderGroups.shifting(a.id, by: -1, inGroup: gid, in: shelf), gid)?.items.map(\.id),
                       [a.id, b.id, c.id])
    }

    // MARK: 记住上次看的

    func testSelectingRemembersOnlyFoldersInTheGroup() {
        let gid = UUID()
        let a = folder("/a"), b = folder("/b")
        let shelf = [folderGroup("G", [a, b], id: gid)]
        XCTAssertEqual(FolderGroups.selected(in: try! XCTUnwrap(groupIn(shelf, gid)))?.id, a.id,
                       "没记过时看第一个")
        let picked = FolderGroups.selecting(b.id, inGroup: gid, in: shelf)
        XCTAssertEqual(groupIn(picked, gid)?.selectedFolder, b.id)
        XCTAssertEqual(FolderGroups.selected(in: try! XCTUnwrap(groupIn(picked, gid)))?.id, b.id)
        XCTAssertEqual(FolderGroups.selecting(UUID(), inGroup: gid, in: shelf), shelf)
        // 已经是它时原样返回（不白存一次）。
        XCTAssertEqual(FolderGroups.selecting(b.id, inGroup: gid, in: picked), picked)
    }

    func testStaleSelectionFallsBackToFirst() {
        let a = folder("/a")
        let group = DockGroup(name: "G", items: [a], keepsEmpty: true, kind: .folders, selectedFolder: UUID())
        XCTAssertEqual(FolderGroups.selected(in: group)?.id, a.id)
    }

    // MARK: 标签名字

    func testTabTitlesUseFolderNames() {
        let urls = ["/Users/me/Downloads", "/Users/me/Desktop"].map { URL(fileURLWithPath: $0) }
        XCTAssertEqual(FolderGroups.tabTitles(for: urls), ["Downloads", "Desktop"])
        XCTAssertEqual(FolderGroups.tabTitles(for: []), [])
    }

    func testDuplicateNamesShowTheirParent() {
        let urls = ["/Users/me/工作/素材", "/Users/me/个人/素材", "/Users/me/文档"].map { URL(fileURLWithPath: $0) }
        XCTAssertEqual(FolderGroups.tabTitles(for: urls), ["素材（工作）", "素材（个人）", "文档"])
        XCTAssertEqual(FolderGroups.tabTitles(for: Array(urls.prefix(2)), parenthesize: { " (\($0))" }),
                       ["素材 (工作)", "素材 (个人)"])
    }

    func testStillDuplicateFallsBackToThePath() {
        let urls = ["/Volumes/A/项目/素材", "/Users/me/项目/素材"].map { URL(fileURLWithPath: $0) }
        XCTAssertEqual(FolderGroups.tabTitles(for: urls), ["/Volumes/A/项目/素材", "/Users/me/项目/素材"])
    }

    func testRootFolderHasAName() {
        XCTAssertEqual(FolderGroups.displayName(URL(fileURLWithPath: "/")), "/")
    }

    // MARK: 小窗大小

    func testTabRowAddsToTheBrowserHeight() {
        let screen = CGSize(width: 1728, height: 1080)
        let plain = FolderBrowse.layout(visible: screen)
        let grouped = FolderBrowse.layout(visible: screen, extra: FolderGroups.tabRowHeight)
        XCTAssertEqual(grouped.columns, plain.columns)
        XCTAssertEqual(grouped.size.width, plain.size.width)
        XCTAssertEqual(grouped.size.height, plain.size.height + FolderGroups.tabRowHeight)
        XCTAssertGreaterThanOrEqual(FolderGroups.tabRowHeight, 13 + 2 * 8, "标签字至少 13pt")
        // 小屏上也不比没有标签时矮。
        let small = CGSize(width: 500, height: 400)
        XCTAssertGreaterThanOrEqual(FolderBrowse.layout(visible: small, extra: FolderGroups.tabRowHeight).size.height,
                                    FolderBrowse.layout(visible: small).size.height)
    }

    // MARK: Pro

    func testCreatingGroupsFromTheLibraryIsPro() {
        XCTAssertFalse(ProLicenseGate.canCreateShelfGroup(unlocked: false))
        XCTAssertTrue(ProLicenseGate.canCreateShelfGroup(unlocked: true))
        XCTAssertTrue(ProFeatures.Setting.allCases.contains(.shelfGroups))
        XCTAssertTrue(ProUnlockHighlights.allItems.contains(.setting(.shelfGroups)))
    }
}
