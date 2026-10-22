import Foundation
import XCTest

final class AppShortNamesTests: XCTestCase {

    private func app(_ name: String) -> DockItem {
        .app(id: UUID(), bundleID: "com.example.\(name.filter(\.isLetter))",
             ref: FileRef(url: URL(fileURLWithPath: "/Applications/\(name).app")))
    }

    private func names(_ list: [String]) -> [String] {
        let entries = list.map { (id: UUID(), name: $0) }
        let shown = AppShortNames.displayNames(entries)
        return entries.map { shown[$0.id]! }
    }

    // MARK: 单个短名

    func testDropsVendorAndYear() {
        XCTAssertEqual(AppShortNames.shortName("Adobe Illustrator 2026"), "Illustrator")
        XCTAssertEqual(AppShortNames.shortName("Adobe Photoshop 2026"), "Photoshop")
        XCTAssertEqual(AppShortNames.shortName("Microsoft Word"), "Word")
        XCTAssertEqual(AppShortNames.shortName("Google Chrome"), "Chrome")
        XCTAssertEqual(AppShortNames.shortName("Adobe Photoshop CC 2019"), "Photoshop")
    }

    func testDropsTrailingVersionNumbers() {
        XCTAssertEqual(AppShortNames.shortName("1Password 8"), "1Password")
        XCTAssertEqual(AppShortNames.shortName("Navicat Premium 16.3"), "Navicat Premium")
        XCTAssertEqual(AppShortNames.shortName("Sketch v2"), "Sketch")
    }

    func testVendorMatchesWholeWordOnly() {
        XCTAssertEqual(AppShortNames.shortName("AppleScript Editor"), "AppleScript Editor")
        XCTAssertEqual(AppShortNames.shortName("adobe Acrobat"), "Acrobat")
    }

    func testFallsBackWhenNothingUsefulIsLeft() {
        XCTAssertEqual(AppShortNames.shortName("Adobe 2026"), "Adobe 2026")
        XCTAssertEqual(AppShortNames.shortName("Google Q"), "Google Q")
        XCTAssertEqual(AppShortNames.shortName("Adobe XD"), "XD")
    }

    func testLeavesOrdinaryNamesAlone() {
        XCTAssertEqual(AppShortNames.shortName("Safari"), "Safari")
        XCTAssertEqual(AppShortNames.shortName("Final Cut Pro"), "Final Cut Pro")
        XCTAssertEqual(AppShortNames.shortName("腾讯会议"), "腾讯会议")
        XCTAssertEqual(AppShortNames.shortName("2048"), "2048")
        XCTAssertEqual(AppShortNames.shortName("  Microsoft Excel  "), "Excel")
        XCTAssertEqual(AppShortNames.shortName(""), "")
    }

    func testSuffixShapes() {
        XCTAssertTrue(AppShortNames.isStrippableSuffix("2025"))
        XCTAssertTrue(AppShortNames.isStrippableSuffix("cc"))
        XCTAssertTrue(AppShortNames.isStrippableSuffix("(2024)"))
        XCTAssertTrue(AppShortNames.isStrippableSuffix("12.0.1"))
        XCTAssertFalse(AppShortNames.isStrippableSuffix("X"))
        XCTAssertFalse(AppShortNames.isStrippableSuffix("Pro"))
        XCTAssertFalse(AppShortNames.isStrippableSuffix("1.2."))
        XCTAssertFalse(AppShortNames.isStrippableSuffix("3D"))
        XCTAssertFalse(AppShortNames.isStrippableSuffix("1984"))
    }

    // MARK: 同组撞名

    func testCollidingYearsKeepTheYear() {
        XCTAssertEqual(names(["Adobe Photoshop 2025", "Adobe Photoshop 2026", "Adobe Illustrator 2026"]),
                       ["Photoshop 2025", "Photoshop 2026", "Illustrator"])
    }

    func testCollidingVendorKeepsTheVendor() {
        XCTAssertEqual(names(["Microsoft Word", "Word"]), ["Microsoft Word", "Word"])
    }

    func testCollisionIsCaseInsensitive() {
        // 「Drive」和「drive」算撞名：先加回版本号就分得清。
        XCTAssertEqual(names(["Google Drive", "drive 2"]), ["Drive", "drive 2"])
    }

    func testIdenticalNamesFallBackToOriginal() {
        XCTAssertEqual(names(["Adobe Photoshop 2026", "Adobe Photoshop 2026"]),
                       ["Adobe Photoshop 2026", "Adobe Photoshop 2026"])
    }

    func testCustomNameWinsAndIsNotShortened() {
        let a = (id: UUID(), name: "Adobe Photoshop 2026")
        let b = (id: UUID(), name: "Adobe Photoshop 2025")
        let shown = AppShortNames.displayNames([a, b], custom: [a.id: "PS 2026"])
        XCTAssertEqual(shown[a.id], "PS 2026")
        // 另一个不再撞名，正常缩短。
        XCTAssertEqual(shown[b.id], "Photoshop")
    }

    // MARK: 存进分组

    func testRenamingAnItemStoresAndRestores() throws {
        let ps = app("Adobe Photoshop 2026")
        let group = DockGroup(name: "设计", items: [ps, app("Safari")])
        var items = AppGroups.renamingItem(ps.id, inGroup: group.id, to: "  PS  ", in: [.group(group)])
        var stored = try XCTUnwrap(items[0].group)
        XCTAssertEqual(stored.customName(for: ps.id), "PS")
        XCTAssertEqual(stored.items, group.items)

        items = AppGroups.renamingItem(ps.id, inGroup: group.id, to: nil, in: items)
        stored = try XCTUnwrap(items[0].group)
        XCTAssertNil(stored.customName(for: ps.id))
        XCTAssertNil(stored.itemNames)
    }

    func testRenamingToTheOriginalOrBlankClearsIt() throws {
        let ps = app("Adobe Photoshop 2026")
        let group = DockGroup(name: "设计", items: [ps],
                              itemNames: [ps.id.uuidString: "PS"])
        var items = AppGroups.renamingItem(ps.id, inGroup: group.id, to: "Adobe Photoshop 2026",
                                           original: "Adobe Photoshop 2026", in: [.group(group)])
        XCTAssertNil(try XCTUnwrap(items[0].group).itemNames)
        items = AppGroups.renamingItem(ps.id, inGroup: group.id, to: "PS", in: items)
        items = AppGroups.renamingItem(ps.id, inGroup: group.id, to: "   ", in: items)
        XCTAssertNil(try XCTUnwrap(items[0].group).itemNames)
    }

    func testRenamingPrunesNamesOfItemsNoLongerInTheGroup() throws {
        let ps = app("Photoshop")
        let gone = UUID()
        let group = DockGroup(name: "设计", items: [ps], itemNames: [gone.uuidString: "旧"])
        let items = AppGroups.renamingItem(ps.id, inGroup: group.id, to: "PS", in: [.group(group)])
        XCTAssertEqual(try XCTUnwrap(items[0].group).itemNames, [ps.id.uuidString: "PS"])
    }

    func testRenamingUnknownItemOrGroupChangesNothing() {
        let ps = app("Photoshop")
        let shelf: [DockItem] = [.group(DockGroup(name: "设计", items: [ps]))]
        XCTAssertEqual(AppGroups.renamingItem(UUID(), inGroup: shelf[0].id, to: "X", in: shelf), shelf)
        XCTAssertEqual(AppGroups.renamingItem(ps.id, inGroup: UUID(), to: "X", in: shelf), shelf)
    }

    func testShowNamesToggleDefaultsOnAndStoresNilWhenOn() throws {
        let group = DockGroup(name: "设计", items: [app("Safari")])
        XCTAssertTrue(group.showsNames)
        var items = AppGroups.settingShowsNames(false, inGroup: group.id, in: [.group(group)])
        XCTAssertFalse(try XCTUnwrap(items[0].group).showsNames)
        items = AppGroups.settingShowsNames(true, inGroup: group.id, in: items)
        XCTAssertNil(try XCTUnwrap(items[0].group).hidesNames)
    }

    func testOldGroupsDecodeWithoutTheNewFields() throws {
        let old = #"{"id":"\#(UUID().uuidString)","name":"旧","tint":"none","items":[]}"#
        let group = try JSONDecoder().decode(DockGroup.self, from: Data(old.utf8))
        XCTAssertNil(group.itemNames)
        XCTAssertTrue(group.showsNames)
        let data = try JSONEncoder().encode(group)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("itemNames"))
        XCTAssertFalse(text.contains("hidesNames"))

        let ps = UUID()
        let named = DockGroup(name: "新", itemNames: [ps.uuidString: "PS"], hidesNames: true)
        let back = try JSONDecoder().decode(DockGroup.self, from: JSONEncoder().encode(named))
        XCTAssertEqual(back, named)
        XCTAssertEqual(back.customName(for: ps), "PS")
    }

    func testGroupDisplayNamesShortenAppsOnly() {
        let ps25 = app("Adobe Photoshop 2025")
        let ps26 = app("Adobe Photoshop 2026")
        let word = app("Microsoft Word")
        let link = DockItem.link(id: UUID(), url: URL(string: "https://example.com")!,
                                 title: "Google Docs")
        let group = DockGroup(name: "办公", items: [ps25, ps26, word, link],
                              itemNames: [word.id.uuidString: "写作"])
        let shown = AppGroups.displayNames(in: group) { item in
            if case .link(_, _, let title) = item { return title }
            return item.fileRef!.url.deletingPathExtension().lastPathComponent
        }
        XCTAssertEqual(shown[ps25.id], "Photoshop 2025")
        XCTAssertEqual(shown[ps26.id], "Photoshop 2026")
        XCTAssertEqual(shown[word.id], "写作")
        XCTAssertEqual(shown[link.id], "Google Docs")
    }
}
