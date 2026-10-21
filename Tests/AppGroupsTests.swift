import Foundation
import XCTest

final class AppGroupsTests: XCTestCase {

    private func app(_ bundleID: String, path: String? = nil) -> DockItem {
        .app(id: UUID(), bundleID: bundleID,
             ref: FileRef(url: URL(fileURLWithPath: path ?? "/Applications/\(bundleID).app")))
    }

    private func group(_ name: String, _ items: [DockItem] = [], keeps: Bool? = nil) -> DockItem {
        .group(DockGroup(name: name, items: items, keepsEmpty: keeps))
    }

    // MARK: 命名

    func testFirstGroupTakesTheBaseName() {
        XCTAssertEqual(AppGroups.uniqueName("分组", existing: []), "分组")
        XCTAssertEqual(AppGroups.uniqueName("分组", existing: ["工作"]), "分组")
    }

    func testTakenNamesCountUpFromTwo() {
        XCTAssertEqual(AppGroups.uniqueName("分组", existing: ["分组"]), "分组 2")
        XCTAssertEqual(AppGroups.uniqueName("分组", existing: ["分组", "分组 2"]), "分组 3")
        // 中间空出来的号先补上。
        XCTAssertEqual(AppGroups.uniqueName("分组", existing: ["分组", "分组 3"]), "分组 2")
    }

    func testNewEmptyGroupAvoidsExistingGroupNamesAndKeepsItself() {
        let shelf = [app("a"), group("分组", [app("b"), app("c")])]
        let id = UUID()
        let (items, newID) = AppGroups.addingEmptyGroup(named: "分组", in: shelf, id: id)
        XCTAssertEqual(newID, id)
        XCTAssertEqual(items.count, 3)
        let made = try! XCTUnwrap(items.last?.group)
        XCTAssertEqual(made.id, id)
        XCTAssertEqual(made.name, "分组 2")
        XCTAssertTrue(made.items.isEmpty)
        XCTAssertTrue(made.keepsWhenSmall)
    }

    // MARK: 空组保留

    func testLibraryGroupSurvivesBeingEmptyOrSingle() {
        let empty = group("分组", keeps: true)
        let single = group("分组 2", [app("a")], keeps: true)
        XCTAssertEqual(ShelfItems.dissolvingSmallGroups(in: [empty, single]), [empty, single])
        XCTAssertEqual(ShelfItems.displayed(profile: [empty], mirrored: [], mirroring: false), [empty])
    }

    func testDraggedGroupStillDissolvesBelowTwo() {
        let inner = app("a")
        XCTAssertEqual(ShelfItems.dissolvingSmallGroups(in: [group("x", [inner])]), [inner])
        XCTAssertEqual(ShelfItems.dissolvingSmallGroups(in: [group("y")]), [])
    }

    func testTakingTheLastAppOutOfALibraryGroupLeavesItEmpty() {
        let inner = app("a")
        let made = DockGroup(name: "分组", items: [inner], keepsEmpty: true)
        let result = ShelfItems.removingFromGroup(inner.id, group: made.id, in: [.group(made)])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].group?.items, [])
        XCTAssertEqual(result[1], inner)
    }

    func testOldGroupsDecodeWithoutTheFlag() throws {
        let made = DockGroup(name: "旧", items: [app("a"), app("b")])
        let data = try JSONEncoder().encode(made)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("keepsEmpty"))
        let back = try JSONDecoder().decode(DockGroup.self, from: data)
        XCTAssertEqual(back, made)
        XCTAssertFalse(back.keepsWhenSmall)

        let kept = DockGroup(name: "新", keepsEmpty: true)
        let round = try JSONDecoder().decode(DockGroup.self, from: JSONEncoder().encode(kept))
        XCTAssertTrue(round.keepsWhenSmall)
    }

    // MARK: 加入去重

    func testAddingSkipsAppsAlreadyInTheGroup() {
        let safari = app("com.apple.Safari")
        let made = DockGroup(name: "分组", items: [safari], keepsEmpty: true)
        let again = app("com.apple.safari", path: "/Applications/Safari Copy.app")
        let notes = app("com.apple.Notes")
        let result = AppGroups.adding([again, notes], toGroup: made.id, in: [.group(made)])
        XCTAssertEqual(result[0].group?.items.count, 2)
        XCTAssertEqual(result[0].group?.items.last, notes)
    }

    func testAddingSkipsDuplicatesInsideOneBatch() {
        let made = DockGroup(name: "分组", keepsEmpty: true)
        let a = app("com.a"), a2 = app("com.a")
        let result = AppGroups.adding([a, a2], toGroup: made.id, in: [.group(made)])
        XCTAssertEqual(result[0].group?.items, [a])
    }

    func testAppsWithoutBundleIDAreComparedByPath() {
        let made = DockGroup(name: "分组", keepsEmpty: true)
        let one = app("", path: "/Applications/Tool.app")
        let same = app("", path: "/Applications/./Tool.app")
        let other = app("", path: "/Applications/Other.app")
        let result = AppGroups.adding([one, same, other], toGroup: made.id, in: [.group(made)])
        XCTAssertEqual(result[0].group?.items, [one, other])
    }

    func testAddingNeverNestsGroupsOrSpacers() {
        let made = DockGroup(name: "分组", keepsEmpty: true)
        let spacer = DockItem.spacer(id: UUID(), size: .small)
        let result = AppGroups.adding([spacer, group("内")], toGroup: made.id, in: [.group(made)])
        XCTAssertEqual(result[0].group?.items, [])
    }

    func testAddingToAMissingGroupChangesNothing() {
        let shelf = [app("a")]
        XCTAssertEqual(AppGroups.adding([app("b")], toGroup: UUID(), in: shelf), shelf)
    }

    func testAddingHasNoUpperLimitAndKeepsThePreviewAtFour() {
        let made = DockGroup(name: "分组", keepsEmpty: true)
        let many = (0..<30).map { app("com.app\($0)") }
        let result = AppGroups.adding(many, toGroup: made.id, in: [.group(made)])
        let filled = try! XCTUnwrap(result[0].group)
        XCTAssertEqual(filled.items.count, 30)
        XCTAssertEqual(filled.preview.count, DockGroup.previewCount)
        XCTAssertEqual(filled.hiddenCount, 26)
    }

    func testContainsMatchesByIdentity() {
        let made = DockGroup(name: "分组", items: [app("com.a")], keepsEmpty: true)
        XCTAssertTrue(AppGroups.contains(app("COM.A"), in: made))
        XCTAssertFalse(AppGroups.contains(app("com.b"), in: made))
    }

    // MARK: 改名、搜索、类型

    func testRenamingByIDKeepsContentsAndIgnoresBlank() {
        let a = app("com.a")
        let made = DockGroup(name: "分组", items: [a], keepsEmpty: true)
        let renamed = AppGroups.renaming(made.id, to: "  工作  ", in: [.group(made)])
        XCTAssertEqual(renamed[0].group?.name, "工作")
        XCTAssertEqual(renamed[0].group?.items, [a])
        XCTAssertEqual(AppGroups.renaming(made.id, to: "   ", in: [.group(made)]), [.group(made)])
    }

    func testSearchMatchesNameOrBundleID() {
        XCTAssertTrue(AppGroups.matches("", name: "备忘录", bundleID: "com.apple.Notes"))
        XCTAssertTrue(AppGroups.matches("备忘", name: "备忘录", bundleID: "com.apple.Notes"))
        XCTAssertTrue(AppGroups.matches("NOTES", name: "备忘录", bundleID: "com.apple.Notes"))
        XCTAssertFalse(AppGroups.matches("safari", name: "备忘录", bundleID: "com.apple.Notes"))
    }

    func testOnlyAppBundlesAreAccepted() {
        XCTAssertTrue(AppGroups.isAppBundle(URL(fileURLWithPath: "/Applications/Safari.app")))
        XCTAssertTrue(AppGroups.isAppBundle(URL(fileURLWithPath: "/Applications/X.APP")))
        XCTAssertFalse(AppGroups.isAppBundle(URL(fileURLWithPath: "/Users/me/Documents")))
        XCTAssertFalse(AppGroups.isAppBundle(URL(fileURLWithPath: "/Users/me/a.txt")))
    }
}
