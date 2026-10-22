import CoreGraphics
import Foundation
import XCTest

final class WindowSwitcherTests: XCTestCase {

    private typealias E = WindowSwitcher.Entry

    private func entry(_ id: Int, pid: Int32 = 1, app: String = "App", title: String = "",
                       z: Int? = nil, rank: Int = 0, index: Int = 0, minimized: Bool = false,
                       hidden: Bool = false, desktop: WindowSwitcher.Desktop = .current) -> E {
        E(id: id, key: "k\(id)", pid: pid, appName: app, title: title.isEmpty ? "w\(id)" : title,
          zOrder: z, appRank: rank, windowIndex: index, minimized: minimized, hidden: hidden, desktop: desktop)
    }

    // MARK: 设置

    func testDefaultsAreOptionTabAndMinimizedOn() {
        let s = WindowSwitcherSettings()
        XCTAssertEqual(s.hotKey, KeyCombo(keyCode: 48, modifiers: KeyCombo.Modifier.option))
        XCTAssertFalse(s.currentDesktopOnly)
        XCTAssertFalse(s.groupByApp)
        XCTAssertTrue(s.includeMinimized)
        XCTAssertEqual(PersistedState().windowSwitcher, s)
    }

    func testMissingKeyDecodesToDefaultButClearedStaysCleared() throws {
        let old = try JSONDecoder().decode(PersistedState.self, from: Data("{}".utf8))
        XCTAssertEqual(old.windowSwitcher.hotKey, WindowSwitcherSettings.defaultHotKey)

        var cleared = WindowSwitcherSettings()
        cleared.hotKey = nil
        cleared.groupByApp = true
        let data = try JSONEncoder().encode(cleared)
        let back = try JSONDecoder().decode(WindowSwitcherSettings.self, from: data)
        XCTAssertNil(back.hotKey, "清空的快捷键读回来仍是空，不变回 ⌥Tab")
        XCTAssertTrue(back.groupByApp)

        var state = PersistedState()
        state.windowSwitcher = cleared
        let round = try JSONDecoder().decode(PersistedState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(round.windowSwitcher, cleared)
    }

    func testUnreadableHotKeyFallsBackToDefault() throws {
        let s = try JSONDecoder().decode(WindowSwitcherSettings.self,
                                         from: Data(#"{"hotKey":"x","includeMinimized":false}"#.utf8))
        XCTAssertEqual(s.hotKey, WindowSwitcherSettings.defaultHotKey)
        XCTAssertFalse(s.includeMinimized)
    }

    func testRegistrableNeedsAModifier() {
        XCTAssertNil(WindowSwitcherSettings(hotKey: KeyCombo(keyCode: 48, modifiers: KeyCombo.Modifier.shift)).registrableHotKey)
        XCTAssertNil(WindowSwitcherSettings(hotKey: nil).registrableHotKey)
        XCTAssertNotNil(WindowSwitcherSettings().registrableHotKey)
    }

    func testAdviceWarnsOnCommandTabAndDuplicates() {
        let cmdTab = KeyCombo(keyCode: 48, modifiers: KeyCombo.Modifier.command)
        XCTAssertNotNil(WindowSwitcherHotKeyAdvice.warning(for: cmdTab))
        let optTab = WindowSwitcherSettings.defaultHotKey
        XCTAssertNil(WindowSwitcherHotKeyAdvice.warning(for: optTab, others: [nil]))
        XCTAssertNotNil(WindowSwitcherHotKeyAdvice.warning(for: optTab, others: [optTab]))
        XCTAssertNil(WindowSwitcherHotKeyAdvice.warning(for: nil, others: [optTab]))
    }

    // MARK: 排序

    func testFrontWindowFirstThenScreenOrder() {
        let list = [entry(1, z: 2), entry(2, z: 0), entry(3, z: 1)]
        XCTAssertEqual(WindowSwitcher.ordered(list).map(\.id), [2, 3, 1])
    }

    func testOtherDesktopsAfterScreenByAppRecency() {
        let list = [
            entry(1, pid: 3, rank: 2, desktop: .other(2)),
            entry(2, pid: 1, z: 0),
            entry(3, pid: 2, rank: 1, index: 1, desktop: .other(nil)),
            entry(4, pid: 2, rank: 1, index: 0, desktop: .other(nil)),
            entry(5, pid: 1, z: 1),
        ]
        XCTAssertEqual(WindowSwitcher.ordered(list).map(\.id), [2, 5, 4, 3, 1])
    }

    func testMinimizedAndHiddenLast() {
        let list = [entry(1, rank: 0, minimized: true), entry(2, rank: 5, desktop: .other(3)),
                    entry(3, z: 0), entry(4, rank: 1, hidden: true)]
        XCTAssertEqual(WindowSwitcher.ordered(list).map(\.id), [3, 2, 1, 4])
    }

    func testPreviousWindowComesSecondEvenOnAnotherDesktop() {
        let list = [entry(1, z: 0), entry(2, z: 1), entry(3, rank: 4, desktop: .other(2))]
        XCTAssertEqual(WindowSwitcher.ordered(list, previous: "k3").map(\.id), [1, 3, 2])
        XCTAssertEqual(WindowSwitcher.ordered(list, previous: "gone").map(\.id), [1, 2, 3])
    }

    func testInitialSelectionIsSecond() {
        XCTAssertEqual(WindowSwitcher.initialSelection(count: 0), 0)
        XCTAssertEqual(WindowSwitcher.initialSelection(count: 1), 0)
        XCTAssertEqual(WindowSwitcher.initialSelection(count: 5), 1)
        XCTAssertEqual(WindowSwitcher.initialSelection(count: 5, firstIsFront: false), 0)
    }

    // MARK: 过滤、分组

    func testFilterCurrentDesktopAndMinimized() {
        let list = [entry(1), entry(2, desktop: .other(2)), entry(3, minimized: true), entry(4, hidden: true)]
        var s = WindowSwitcherSettings()
        XCTAssertEqual(WindowSwitcher.filtered(list, settings: s).map(\.id), [1, 2, 3, 4])
        s.currentDesktopOnly = true
        XCTAssertEqual(WindowSwitcher.filtered(list, settings: s).map(\.id), [1, 3, 4])
        s.includeMinimized = false
        XCTAssertEqual(WindowSwitcher.filtered(list, settings: s).map(\.id), [1])
    }

    func testGroupKeepsAppsTogetherInRecencyOrder() {
        let list = [entry(1, pid: 1), entry(2, pid: 2), entry(3, pid: 1), entry(4, pid: 3), entry(5, pid: 2)]
        XCTAssertEqual(WindowSwitcher.grouped(list).map(\.id), [1, 3, 2, 5, 4])
    }

    func testArrangeCombinesAll() {
        let list = [entry(1, pid: 1, z: 1), entry(2, pid: 2, z: 0), entry(3, pid: 2, z: 2),
                    entry(4, pid: 1, minimized: true)]
        var s = WindowSwitcherSettings(groupByApp: true)
        XCTAssertEqual(WindowSwitcher.arrange(list, settings: s).map(\.id), [2, 3, 1, 4])
        s.includeMinimized = false
        s.groupByApp = false
        XCTAssertEqual(WindowSwitcher.arrange(list, settings: s).map(\.id), [2, 1, 3])
    }

    // MARK: 文字

    func testCardTitle() {
        XCTAssertEqual(WindowSwitcher.cardTitle(appName: "备忘录", title: "周末采购清单"), "备忘录 · 周末采购清单")
        XCTAssertEqual(WindowSwitcher.cardTitle(appName: "微信", title: "微信"), "微信")
        XCTAssertEqual(WindowSwitcher.cardTitle(appName: "访达", title: "  "), "访达")
        XCTAssertEqual(WindowSwitcher.cardTitle(appName: "", title: "下载"), "下载")
    }

    func testBadgePriority() {
        XCTAssertEqual(WindowSwitcher.badge(for: entry(1, minimized: true, hidden: true, desktop: .other(2))), .minimized)
        XCTAssertEqual(WindowSwitcher.badge(for: entry(1, hidden: true)), .hidden)
        XCTAssertEqual(WindowSwitcher.badge(for: entry(1, desktop: .other(2))), .desktop(2))
        XCTAssertEqual(WindowSwitcher.badge(for: entry(1, desktop: .other(nil))), .desktop(nil))
        XCTAssertNil(WindowSwitcher.badge(for: entry(1)))
        XCTAssertFalse(WindowSwitcher.Badge.desktop(nil).text.isEmpty)
    }

    // MARK: 选中移动

    func testStepWraps() {
        XCTAssertEqual(WindowSwitcher.step(1, by: 1, count: 3), 2)
        XCTAssertEqual(WindowSwitcher.step(2, by: 1, count: 3), 0)
        XCTAssertEqual(WindowSwitcher.step(0, by: -1, count: 3), 2)
        XCTAssertEqual(WindowSwitcher.step(5, by: 0, count: 3), 2)
        XCTAssertEqual(WindowSwitcher.step(0, by: 1, count: 0), 0)
    }

    func testVerticalMovesByRow() {
        // 7 个，一行 3 个：0 1 2 / 3 4 5 / 6
        XCTAssertEqual(WindowSwitcher.vertical(1, rows: 1, columns: 3, count: 7), 4)
        XCTAssertEqual(WindowSwitcher.vertical(4, rows: 1, columns: 3, count: 7), 6, "下一行不够长落到最后一个")
        XCTAssertEqual(WindowSwitcher.vertical(6, rows: 1, columns: 3, count: 7), 6)
        XCTAssertEqual(WindowSwitcher.vertical(6, rows: -1, columns: 3, count: 7), 3)
        XCTAssertEqual(WindowSwitcher.vertical(1, rows: -1, columns: 3, count: 7), 1)
        XCTAssertEqual(WindowSwitcher.vertical(1, rows: 1, columns: 5, count: 3), 1, "只有一行时不动")
    }

    // MARK: 按键

    private func act(_ code: UInt32, _ chars: String = "", mods: UInt32 = KeyCombo.Modifier.option,
                     searching: Bool = false, trigger: UInt32 = 48) -> WindowSwitcher.KeyAction {
        WindowSwitcher.action(keyCode: code, characters: chars, modifiers: mods,
                              triggerKey: trigger, searching: searching)
    }

    func testTabMovesAndShiftTabGoesBack() {
        XCTAssertEqual(act(48), .next)
        XCTAssertEqual(act(48, mods: KeyCombo.Modifier.option | KeyCombo.Modifier.shift), .previous)
        XCTAssertEqual(act(50, "`", trigger: 50), .next, "改成别的键时按那个键也是下一个")
        XCTAssertEqual(act(123), .left)
        XCTAssertEqual(act(126), .up)
        XCTAssertEqual(act(53), .cancel)
        XCTAssertEqual(act(36), .commit)
    }

    func testActionKeysOnlyBeforeSearching() {
        XCTAssertEqual(act(13, "w"), .closeWindow)
        XCTAssertEqual(act(46, "m"), .minimizeWindow)
        XCTAssertEqual(act(12, "q"), .quitApp)
        XCTAssertEqual(act(13, "w", searching: true), .type("w"))
        XCTAssertEqual(act(44, "/"), .startSearch)
    }

    func testTypingStartsSearchAndBackspaceEdits() {
        XCTAssertEqual(act(5, "G"), .type("g"))
        XCTAssertEqual(act(18, "1"), .type("1"))
        XCTAssertEqual(act(51), .ignore)
        XCTAssertEqual(act(51, searching: true), .backspace)
        XCTAssertEqual(act(49, " "), .ignore)
        XCTAssertEqual(act(49, " ", searching: true), .type(" "))
        XCTAssertEqual(act(122, ""), .ignore)
    }

    func testCommandComboPassesThrough() {
        XCTAssertEqual(act(12, "q", mods: KeyCombo.Modifier.option | KeyCombo.Modifier.command), .passThrough)
    }

    func testReleaseOfTriggerModifier() {
        typealias M = KeyCombo.Modifier
        XCTAssertFalse(WindowSwitcher.released(trigger: M.option, current: M.option))
        XCTAssertFalse(WindowSwitcher.released(trigger: M.option, current: M.option | M.shift))
        XCTAssertTrue(WindowSwitcher.released(trigger: M.option, current: M.shift))
        XCTAssertTrue(WindowSwitcher.released(trigger: M.option, current: 0))
        XCTAssertTrue(WindowSwitcher.released(trigger: M.control | M.option, current: M.option))
        XCTAssertFalse(WindowSwitcher.released(trigger: M.option | M.shift, current: M.option))
    }

    // MARK: 搜索

    private func idx(_ app: String, _ title: String = "") -> WindowSwitcherSearch.Index {
        WindowSwitcherSearch.Index(appName: app, title: title)
    }

    func testPinyinInitialsAndFull() {
        let p = WindowSwitcherSearch.pinyin("微信")
        XCTAssertEqual(p.full, "weixin")
        XCTAssertEqual(p.initials, "wx")
        let mixed = WindowSwitcherSearch.pinyin("GitHub 首页")
        XCTAssertEqual(mixed.initials, "gsy")
        XCTAssertEqual(WindowSwitcherSearch.pinyin("Safari Web").initials, "sw")
    }

    func testMatchesAppTitleAndPinyin() {
        let wechat = idx("微信", "文件传输助手")
        XCTAssertNotNil(WindowSwitcherSearch.score("wx", wechat))
        XCTAssertNotNil(WindowSwitcherSearch.score("weixin", wechat))
        XCTAssertNotNil(WindowSwitcherSearch.score("微", wechat))
        XCTAssertNotNil(WindowSwitcherSearch.score("传输", wechat))
        XCTAssertNil(WindowSwitcherSearch.score("safari", wechat))
        XCTAssertNotNil(WindowSwitcherSearch.score("GIT", idx("Safari", "GitHub · docket")))
        XCTAssertNotNil(WindowSwitcherSearch.score("saf doc", idx("Safari", "GitHub · docket")))
        XCTAssertNil(WindowSwitcherSearch.score("saf zzz", idx("Safari", "GitHub · docket")))
    }

    func testFilterRanksPrefixFirstAndKeepsRecencyOtherwise() {
        let list = [idx("Notes", "my safari list"), idx("Safari", "Apple"), idx("Finder", "下载"),
                    idx("Safari", "GitHub")]
        XCTAssertEqual(WindowSwitcherSearch.filter("saf", indexes: list), [1, 3, 0])
        XCTAssertEqual(WindowSwitcherSearch.filter("", indexes: list), [0, 1, 2, 3])
        XCTAssertEqual(WindowSwitcherSearch.filter("xz", indexes: list), [2], "下载 的首字母 xz")
    }

    // MARK: 布局

    private let screen = CGSize(width: 1512, height: 944)

    func testFewWindowsOneRowFullSize() {
        let l = WindowSwitcherLayout.layout(count: 6, visible: screen)
        XCTAssertEqual(l.scale, 1)
        XCTAssertEqual(l.rows, 1)
        XCTAssertEqual(l.columns, 6)
        XCTAssertFalse(l.scrolls)
        XCTAssertEqual(l.cardSize, CGSize(width: 186, height: 164))
        XCTAssertEqual(l.thumbnailSize, CGSize(width: 166, height: 112))
        XCTAssertEqual(l.panelSize.width, 6 * 186 + 5 * 14 + 52)
        XCTAssertLessThanOrEqual(l.panelSize.width, screen.width * WindowSwitcherLayout.maxWidthFraction)
    }

    func testOneWindowKeepsMinimumWidth() {
        let l = WindowSwitcherLayout.layout(count: 1, visible: screen)
        XCTAssertEqual(l.columns, 1)
        XCTAssertEqual(l.panelSize.width, WindowSwitcherLayout.minPanelWidth)
        XCTAssertEqual(WindowSwitcherLayout.layout(count: 0, visible: screen).rows, 1)
    }

    func testManyWindowsWrapThenShrinkThenScroll() {
        let wrapped = WindowSwitcherLayout.layout(count: 10, visible: screen)
        XCTAssertEqual(wrapped.scale, 1)
        XCTAssertEqual(wrapped.rows, 2)
        XCTAssertFalse(wrapped.scrolls)

        let shrunk = WindowSwitcherLayout.layout(count: 24, visible: screen)
        XCTAssertLessThan(shrunk.scale, 1)
        XCTAssertFalse(shrunk.scrolls)
        XCTAssertLessThanOrEqual(shrunk.panelSize.height, screen.height * WindowSwitcherLayout.maxHeightFraction + 1)

        let scrolled = WindowSwitcherLayout.layout(count: 80, visible: screen)
        XCTAssertTrue(scrolled.scrolls)
        XCTAssertEqual(scrolled.scale, WindowSwitcherLayout.scales.last)
        XCTAssertGreaterThanOrEqual(scrolled.columns * scrolled.rows, 80)
        XCTAssertLessThan(scrolled.visibleColumns, scrolled.columns)
        XCTAssertLessThanOrEqual(scrolled.panelSize.width, screen.width * WindowSwitcherLayout.maxWidthFraction)
    }

    func testCardsNeverGoBelowMinimumFont() {
        // 缩到最小卡片时标题仍有 13pt 一行的位置（图标 18 加几个字）。
        let card = WindowSwitcherLayout.cardSize(scale: WindowSwitcherLayout.scales.last ?? 1)
        XCTAssertGreaterThanOrEqual(card.width, 120)
        XCTAssertEqual(card.height - WindowSwitcherLayout.thumbnailSize(scale: WindowSwitcherLayout.scales.last ?? 1).height,
                       3 * WindowSwitcherLayout.cardInset + WindowSwitcherLayout.captionHeight)
    }

    func testOriginCentersOnScreenSlightlyHigh() {
        let visible = CGRect(x: 1512, y: 0, width: 1000, height: 800)
        let o = WindowSwitcherLayout.origin(size: CGSize(width: 600, height: 300), visible: visible)
        XCTAssertEqual(o.x, 1712)
        XCTAssertEqual(o.y, 300)
    }

    func testCaptureSizeFillsBox() {
        let px = WindowSwitcherLayout.captureSize(window: CGSize(width: 1600, height: 1000),
                                                  box: CGSize(width: 166, height: 112), scale: 2)
        XCTAssertEqual(px.height, 224)
        XCTAssertGreaterThanOrEqual(px.width, 332)
        let none = WindowSwitcherLayout.captureSize(window: .zero, box: CGSize(width: 166, height: 112), scale: 2)
        XCTAssertEqual(none, CGSize(width: 332, height: 224))
    }
}
