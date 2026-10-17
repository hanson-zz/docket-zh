import XCTest
@testable import Docket

final class WidgetLibraryGroupsTests: XCTestCase {

    // MARK: 分类

    func testOldCategoryValuesStillDecode() throws {
        let json = #"["Clocks","Calendar","Reminders","Sticky Notes","Business","Stocks","Tools","Media","Files","System","Weather","不认识的值"]"#
        let decoded = try JSONDecoder().decode([WidgetCategory].self, from: Data(json.utf8))
        XCTAssertEqual(decoded, [.time, .time, .todo, .todo, .stocks, .stocks, .tools, .media, .files,
                                 .system, .weather, .tools])
    }

    func testCategoriesRoundTrip() throws {
        let data = try JSONEncoder().encode(WidgetCategory.allCases)
        let back = try JSONDecoder().decode([WidgetCategory].self, from: data)
        XCTAssertEqual(back, WidgetCategory.allCases)
    }

    func testLegacyInitializer() {
        XCTAssertEqual(WidgetCategory(legacy: "Clocks"), .time)
        XCTAssertEqual(WidgetCategory(legacy: "Business"), .stocks)
        XCTAssertEqual(WidgetCategory(legacy: "AI"), .ai)
        XCTAssertNil(WidgetCategory(legacy: "nope"))
    }

    func testOrderedListsEveryCategoryOnceWithNamesAndSymbols() {
        XCTAssertEqual(Set(WidgetCategory.ordered), Set(WidgetCategory.allCases))
        XCTAssertEqual(WidgetCategory.ordered.count, WidgetCategory.allCases.count)
        XCTAssertEqual(Set(WidgetCategory.allCases.map(\.displayName)).count, WidgetCategory.allCases.count)
        for category in WidgetCategory.allCases {
            XCTAssertFalse(category.symbol.isEmpty)
        }
        XCTAssertEqual(WidgetCategory.ordered.first, .appsAndFolders)
    }

    func testEveryCategoryHasWidgets() {
        let used = Set(WidgetCatalog.entries.filter(\.selfContained).map(\.category))
        XCTAssertEqual(used, Set(WidgetCategory.allCases), "没有小组件的分类不该留着")
    }

    func testAssignments() {
        func category(_ kind: WidgetKind) -> WidgetCategory? { WidgetCatalog.entry(kind)?.category }
        XCTAssertEqual(category(.appSwitcher), .appsAndFolders)
        XCTAssertEqual(category(.shortcut), .appsAndFolders)
        XCTAssertEqual(category(.slacker), .time)
        XCTAssertEqual(category(.lunar), .time)
        XCTAssertEqual(category(.notes), .todo)
        XCTAssertEqual(category(.timer), .health)
        XCTAssertEqual(category(.perfectDay), .health)
        XCTAssertEqual(category(.aiUsage), .ai)
        XCTAssertEqual(category(.mail), .ai)
        XCTAssertEqual(category(.toggles), .tools)
        XCTAssertEqual(category(.appVolume), .media)
        XCTAssertEqual(category(.airdrop), .files)
        XCTAssertEqual(category(.wallpaper), .system)
        XCTAssertEqual(category(.crypto), .stocks)
    }

    func testDisplayOrderCoversTheCatalog() {
        let listed = Set(WidgetLibraryGroups.displayOrder)
        XCTAssertEqual(listed.count, WidgetLibraryGroups.displayOrder.count, "顺序表里有重复")
        for entry in WidgetCatalog.entries where entry.selfContained {
            XCTAssertTrue(listed.contains(entry.kind), "\(entry.kind) 不在顺序表里")
        }
        XCTAssertLessThan(WidgetLibraryGroups.rank(.clock), WidgetLibraryGroups.rank(.world))
        XCTAssertEqual(WidgetLibraryGroups.rank(.stripe), WidgetLibraryGroups.displayOrder.count)
    }

    // MARK: 推荐和“新”

    func testRecommendedIsFeaturedThenNewWithoutDuplicates() {
        let all = WidgetCatalog.entries.filter(\.selfContained).map(\.kind)
        let recommended = WidgetLibraryGroups.recommended(available: all)
        XCTAssertEqual(Array(recommended.prefix(8)),
                       [.clock, .weather, .calendar, .todo, .water, .aiAssistant, .music, .battery])
        XCTAssertEqual(Set(recommended).count, recommended.count)
        XCTAssertTrue(recommended.contains(.slacker))
        XCTAssertEqual(recommended.filter { $0 == .water }.count, 1, "既是精选又是新的只出现一次")
    }

    func testRecommendedSkipsKindsTheLibraryDoesNotOffer() {
        XCTAssertEqual(WidgetLibraryGroups.recommended(available: [.battery, .clock, .pet]),
                       [.clock, .battery, .pet])
    }

    func testNewMarksComeFromTheCatalog() {
        XCTAssertTrue(WidgetCatalog.isNew(.aiAssistant))
        XCTAssertTrue(WidgetCatalog.isNew(.slacker))
        XCTAssertFalse(WidgetCatalog.isNew(.clock))
        XCTAssertFalse(WidgetCatalog.isNew(.toggles))
        for kind in WidgetLibraryGroups.newKinds {
            XCTAssertNotNil(WidgetCatalog.entry(kind), "\(kind) 不在目录里")
        }
    }

    func testKindCountIgnoresVariants() {
        XCTAssertEqual(WidgetLibraryGroups.kindCount([.clock, .clock, .clock, .weather]), 2)
        XCTAssertEqual(WidgetLibraryGroups.kindCount([]), 0)
    }

    func testEmptyCategoriesAreHidden() {
        XCTAssertEqual(WidgetLibraryGroups.visibleCategories([.stocks, .time]),
                       [.appsAndFolders, .time, .stocks])
        XCTAssertEqual(WidgetLibraryGroups.visibleCategories([.weather], alwaysShown: []), [.weather])
    }

    // MARK: 应用和文件夹

    func testAppTitleDropsSuffix() {
        XCTAssertEqual(WidgetLibraryGroups.appTitle("Safari.app"), "Safari")
        XCTAssertEqual(WidgetLibraryGroups.appTitle("App Store.APP"), "App Store")
        XCTAssertEqual(WidgetLibraryGroups.appTitle("访达"), "访达")
        XCTAssertEqual(WidgetLibraryGroups.appTitle(".app"), ".app")
    }

    func testHomeFolderIsCalledPersonal() {
        XCTAssertEqual(WidgetLibraryGroups.folderTitle(path: "/Users/han/", systemName: "han",
                                                       homePath: "/Users/han"), "个人")
        XCTAssertEqual(WidgetLibraryGroups.folderTitle(path: "/Users/han/Downloads", systemName: "下载",
                                                       homePath: "/Users/han"), "下载")
    }

    // MARK: 小组件管理

    private func widget(_ kind: WidgetKind, _ mode: WidgetVisibilityMode? = nil) -> DockItem {
        var config = WidgetConfig([:])
        if let mode { config.set(WidgetVisibility.modeKey, .string(mode.rawValue)) }
        return .widget(WidgetInstance(kind: kind, config: config))
    }

    private func link(_ title: String) -> DockItem {
        .link(id: UUID(), url: URL(string: "https://example.com")!, title: title)
    }

    func testListsOnlyWidgetsInOrder() {
        let items = [widget(.clock), link("a"), widget(.weather)]
        XCTAssertEqual(WidgetManagement.widgets(items).map(\.kind), [.clock, .weather])
    }

    func testToggleWritesHiddenAndRestores() {
        let items = [widget(.clock), widget(.music, .conditional)]
        let clock = items[0].id
        let hidden = WidgetManagement.setShown(false, id: clock, in: items)
        XCTAssertFalse(WidgetManagement.isShown(hidden[0].widget!))
        XCTAssertEqual(WidgetVisibility.mode(hidden[0].widget!.config), .hidden)
        let back = WidgetManagement.setShown(true, id: clock, in: hidden)
        XCTAssertEqual(WidgetVisibility.mode(back[0].widget!.config), .always)
        // 条件显示的打开时不被改成始终显示。
        let music = items[1].id
        XCTAssertEqual(WidgetManagement.setShown(true, id: music, in: items), items)
        XCTAssertTrue(WidgetManagement.isShown(items[1].widget!))
        XCTAssertEqual(WidgetManagement.setShown(false, id: UUID(), in: items), items)
    }

    func testMoveKeepsOtherItemsInPlace() {
        let a = widget(.clock), b = widget(.weather), c = widget(.battery)
        let l1 = link("1"), l2 = link("2")
        let items = [a, l1, b, l2, c]
        // 把第一个小组件挪到最后。
        let moved = WidgetManagement.move(widgetsAt: [0], to: 3, in: items)
        XCTAssertEqual(moved.map(\.id), [b.id, l1.id, c.id, l2.id, a.id])
        // 把最后一个挪到最前。
        let front = WidgetManagement.move(widgetsAt: [2], to: 0, in: items)
        XCTAssertEqual(front.map(\.id), [c.id, l1.id, a.id, l2.id, b.id])
        // 原地不动和越界都原样返回。
        XCTAssertEqual(WidgetManagement.move(widgetsAt: [1], to: 1, in: items), items)
        XCTAssertEqual(WidgetManagement.move(widgetsAt: [5], to: 0, in: items), items)
        XCTAssertEqual(WidgetManagement.move(widgetsAt: [0], to: 9, in: items), items)
    }
}
