import Foundation
import XCTest

/// 「用 ⌘Tab 打开窗口切换器」：设置编解码、要注册的快捷键、⌘ 按住时的按键含义。
final class WindowSwitcherCommandTabTests: XCTestCase {

    private typealias M = KeyCombo.Modifier
    private let cmdTab = WindowSwitcherSettings.commandTabHotKey
    private let cmdShiftTab = WindowSwitcherSettings.commandShiftTabHotKey

    // MARK: 设置

    func testOffByDefaultAndOldDataReadsOff() throws {
        XCTAssertFalse(WindowSwitcherSettings().commandTab)
        let old = try JSONDecoder().decode(WindowSwitcherSettings.self,
                                           from: Data(#"{"hotKey":null,"groupByApp":true}"#.utf8))
        XCTAssertFalse(old.commandTab, "旧数据没有这个键时读成关")
        XCTAssertNil(old.hotKey)
        XCTAssertTrue(old.groupByApp)
        let state = try JSONDecoder().decode(PersistedState.self, from: Data("{}".utf8))
        XCTAssertFalse(state.windowSwitcher.commandTab)
    }

    func testUnreadableValueReadsOff() throws {
        let s = try JSONDecoder().decode(WindowSwitcherSettings.self,
                                         from: Data(#"{"commandTab":"yes"}"#.utf8))
        XCTAssertFalse(s.commandTab)
        XCTAssertEqual(s.hotKey, WindowSwitcherSettings.defaultHotKey)
    }

    func testRoundTripKeepsCommandTab() throws {
        var s = WindowSwitcherSettings()
        s.commandTab = true
        let data = try JSONEncoder().encode(s)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("\"commandTab\":true"))
        XCTAssertEqual(try JSONDecoder().decode(WindowSwitcherSettings.self, from: data), s)

        var state = PersistedState()
        state.windowSwitcher = s
        let back = try JSONDecoder().decode(PersistedState.self, from: JSONEncoder().encode(state))
        XCTAssertTrue(back.windowSwitcher.commandTab)
    }

    // MARK: 注册哪些快捷键

    func testCommandTabCombos() {
        XCTAssertEqual(cmdTab, KeyCombo(keyCode: 48, modifiers: M.command))
        XCTAssertEqual(cmdShiftTab, KeyCombo(keyCode: 48, modifiers: M.command | M.shift))
        XCTAssertFalse(WindowSwitcherSettings.opensBackward(cmdTab))
        XCTAssertTrue(WindowSwitcherSettings.opensBackward(cmdShiftTab))
        XCTAssertFalse(WindowSwitcherSettings.opensBackward(WindowSwitcherSettings.defaultHotKey))
    }

    func testHotKeysCoexistWithOptionTab() {
        var s = WindowSwitcherSettings()
        XCTAssertEqual(s.hotKeys(trusted: true), [WindowSwitcherSettings.defaultHotKey])
        XCTAssertFalse(s.takesOverCommandTab(trusted: true))

        s.commandTab = true
        XCTAssertTrue(s.takesOverCommandTab(trusted: true))
        XCTAssertEqual(s.hotKeys(trusted: true), [WindowSwitcherSettings.defaultHotKey, cmdTab, cmdShiftTab],
                       "⌥Tab 和 ⌘Tab 都能用")

        s.hotKey = nil
        XCTAssertEqual(s.hotKeys(trusted: true), [cmdTab, cmdShiftTab], "清空 ⌥Tab 后 ⌘Tab 照样接管")

        s.hotKey = cmdTab
        XCTAssertEqual(s.hotKeys(trusted: true), [cmdTab, cmdShiftTab], "自己录的也是 ⌘Tab 时不重复注册")
    }

    func testNoTakeOverWithoutAccessibility() {
        var s = WindowSwitcherSettings()
        s.commandTab = true
        XCTAssertFalse(s.takesOverCommandTab(trusted: false), "没辅助功能权限时保持系统 ⌘Tab")
        XCTAssertEqual(s.hotKeys(trusted: false), [])
    }

    // MARK: 打开时选谁

    func testCommandShiftTabSelectsLast() {
        XCTAssertEqual(WindowSwitcher.initialSelection(count: 5, backward: true), 4)
        XCTAssertEqual(WindowSwitcher.initialSelection(count: 5, firstIsFront: false, backward: true), 4)
        XCTAssertEqual(WindowSwitcher.initialSelection(count: 1, backward: true), 0)
        XCTAssertEqual(WindowSwitcher.initialSelection(count: 0, backward: true), 0)
        XCTAssertEqual(WindowSwitcher.initialSelection(count: 5, backward: false), 1)
    }

    // MARK: 按住 ⌘ 时的按键

    private func act(_ code: UInt32, _ chars: String = "", mods: UInt32 = M.command,
                     searching: Bool = false) -> WindowSwitcher.KeyAction {
        WindowSwitcher.action(keyCode: code, characters: chars, modifiers: mods,
                              triggerKey: 48, searching: searching, holding: M.command)
    }

    func testHoldingCommandTabAndShiftTab() {
        XCTAssertEqual(act(48), .next)
        XCTAssertEqual(act(48, mods: M.command | M.shift), .previous)
        XCTAssertEqual(act(53), .cancel)
        XCTAssertEqual(act(36), .commit)
    }

    func testCommandHeldIsNotPassThrough() {
        XCTAssertEqual(act(13, "w"), .closeWindow, "按着 ⌘ 按 W 关选中的窗口，不把 ⌘W 交给前台 App")
        XCTAssertEqual(act(46, "m"), .minimizeWindow)
        XCTAssertEqual(act(12, "q"), .quitApp)
        XCTAssertEqual(act(5, "g"), .type("g"))
        XCTAssertEqual(act(13, "w", searching: true), .type("w"))
    }

    func testExtraModifiersStillPassThrough() {
        // ⌥Tab 打开时按着 ⌥ 再加 ⌘ 照旧交还前台 App。
        XCTAssertEqual(WindowSwitcher.action(keyCode: 12, characters: "q", modifiers: M.option | M.command,
                                             searching: false, holding: M.option), .passThrough)
        XCTAssertEqual(WindowSwitcher.action(keyCode: 12, characters: "q", modifiers: M.option | M.command,
                                             searching: false), .passThrough)
    }

    func testCommandGraveIsLeftToTheSystem() {
        XCTAssertEqual(act(50, "`"), .passThrough, "⌘` 不动，交还给系统")
        XCTAssertEqual(WindowSwitcher.action(keyCode: 50, characters: "`", modifiers: M.option,
                                             triggerKey: 50, searching: false, holding: M.option), .next)
    }
}
