import AppKit
import XCTest

/// 输入框的编辑快捷键（码头没有「编辑」菜单，由窗口自己派发），以及面板被钉在
/// 别的桌面时要不要重建。
@MainActor
final class EditShortcutTests: XCTestCase {

    func testCommandLettersMapToTheEditActions() {
        XCTAssertEqual(EditShortcut.resolve(characters: "a", command: true, shift: false), .selectAll)
        XCTAssertEqual(EditShortcut.resolve(characters: "c", command: true, shift: false), .copy)
        XCTAssertEqual(EditShortcut.resolve(characters: "x", command: true, shift: false), .cut)
        XCTAssertEqual(EditShortcut.resolve(characters: "v", command: true, shift: false), .paste)
        XCTAssertEqual(EditShortcut.resolve(characters: "z", command: true, shift: false), .undo)
    }

    func testShiftCommandZIsRedoWhateverTheCase() {
        XCTAssertEqual(EditShortcut.resolve(characters: "z", command: true, shift: true), .redo)
        XCTAssertEqual(EditShortcut.resolve(characters: "Z", command: true, shift: true), .redo)
    }

    func testOtherCombinationsAreLeftAlone() {
        // 没按 ⌘。
        XCTAssertNil(EditShortcut.resolve(characters: "a", command: false, shift: false))
        // 带 ⌥ 或 ⌃ 的留给别的功能。
        XCTAssertNil(EditShortcut.resolve(characters: "a", command: true, shift: false, option: true))
        XCTAssertNil(EditShortcut.resolve(characters: "v", command: true, shift: false, control: true))
        // ⌘⇧A、⌘⇧C（汇率页拷贝整句）不是编辑快捷键。
        XCTAssertNil(EditShortcut.resolve(characters: "a", command: true, shift: true))
        XCTAssertNil(EditShortcut.resolve(characters: "C", command: true, shift: true))
        // ⌘W 归面板自己（关面板）。
        XCTAssertNil(EditShortcut.resolve(characters: "w", command: true, shift: false))
        XCTAssertNil(EditShortcut.resolve(characters: nil, command: true, shift: false))
    }

    func testANonLatinLayoutFallsBackToTheKeyCode() {
        // 俄文布局下 ⌘V 打出来的是「м」，按键码 9 认成粘贴。
        XCTAssertEqual(EditShortcut.resolve(characters: "м", keyCode: 9, command: true, shift: false), .paste)
        XCTAssertNil(EditShortcut.resolve(characters: "м", keyCode: 40, command: true, shift: false))
        // 打出拉丁字母时以字为准（Dvorak 等布局），不看键码。
        XCTAssertEqual(EditShortcut.resolve(characters: "c", keyCode: 34, command: true, shift: false), .copy)
    }

    func testSelectorsAreTheEditMenusOwn() {
        XCTAssertEqual(EditShortcut.allCases.map(\.selectorName),
                       ["selectAll:", "copy:", "cut:", "paste:", "undo:", "redo:"])
    }

    func testTypingGivesTheFieldFirstSay() {
        for shortcut in [EditShortcut.selectAll, .paste, .undo, .redo] {
            XCTAssertEqual(EditShortcut.route(shortcut, textFocused: true, hasSelection: false), .fieldFirst)
        }
        XCTAssertEqual(EditShortcut.route(.copy, textFocused: true, hasSelection: true), .fieldFirst)
        XCTAssertEqual(EditShortcut.route(.cut, textFocused: true, hasSelection: true), .fieldFirst)
    }

    func testCopyWithNothingSelectedStaysWithThePanel() {
        // 汇率页、计算器的 ⌘C 拷贝结果：输入框里没选字时照旧归面板。
        XCTAssertEqual(EditShortcut.route(.copy, textFocused: true, hasSelection: false), .panelFirst)
        XCTAssertEqual(EditShortcut.route(.cut, textFocused: true, hasSelection: false), .panelFirst)
    }

    func testWithoutAFieldThePanelGoesFirst() {
        for shortcut in EditShortcut.allCases {
            XCTAssertEqual(EditShortcut.route(shortcut, textFocused: false, hasSelection: false), .panelFirst)
        }
    }

    func testAPanelPinnedElsewhereIsRebuiltOnce() {
        XCTAssertTrue(PanelSpaceRescue.shouldRebuild(isOnActiveSpace: false, alreadyRebuilt: false))
        XCTAssertFalse(PanelSpaceRescue.shouldRebuild(isOnActiveSpace: false, alreadyRebuilt: true))
        XCTAssertFalse(PanelSpaceRescue.shouldRebuild(isOnActiveSpace: true, alreadyRebuilt: false))
    }

    // MARK: AppKit 这一侧

    private func key(_ character: String, _ flags: NSEvent.ModifierFlags = .command,
                     keyCode: UInt16 = 0) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                         timestamp: 0, windowNumber: 0, context: nil,
                         characters: character, charactersIgnoringModifiers: character,
                         isARepeat: false, keyCode: keyCode)!
    }

    func testKeyEventsAreReadTheSameWay() {
        XCTAssertEqual(EditKeyRouting.shortcut(for: key("a")), .selectAll)
        XCTAssertEqual(EditKeyRouting.shortcut(for: key("Z", [.command, .shift], keyCode: 6)), .redo)
        XCTAssertNil(EditKeyRouting.shortcut(for: key("a", [.command, .option])))
        XCTAssertNil(EditKeyRouting.shortcut(for: key("w")))
    }

    /// 不是编辑快捷键：原样交给窗口原本的处理。
    func testANonEditKeyGoesStraightToThePanel() {
        let panel = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: 120, height: 40),
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        var passed = false
        let handled = EditKeyRouting.perform(key("k"), in: panel) {
            passed = true
            return true
        }
        XCTAssertTrue(handled)
        XCTAssertTrue(passed)
    }

    /// 没有输入框时面板先接：面板接了就不再沿响应链发。
    func testThePanelsOwnShortcutWinsWithoutAField() {
        let panel = KeyablePanel(contentRect: NSRect(x: 0, y: 0, width: 120, height: 40),
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        var passed = 0
        XCTAssertTrue(EditKeyRouting.perform(key("c"), in: panel) {
            passed += 1
            return true
        })
        XCTAssertEqual(passed, 1)
    }
}
