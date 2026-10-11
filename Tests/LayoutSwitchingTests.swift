import Foundation
import XCTest

/// Switching layouts without the menu: hotkeys, the shelf gesture and Focus.
///
/// The parts with rules live in `Sources/Core/LayoutSwitching.swift` so they
/// can be checked here; the Carbon registration, the scroll handling and the
/// Focus filter itself sit in the app, which this target does not compile.
final class LayoutSwitchingTests: XCTestCase {

    private let controlOption = KeyCombo.Modifier.control | KeyCombo.Modifier.option

    // MARK: Key combinations

    func testDisplayStringUsesMenuSymbols() {
        XCTAssertEqual(KeyCombo(keyCode: 18, modifiers: controlOption).displayString, "⌃⌥1")
        XCTAssertEqual(KeyCombo(keyCode: 25, modifiers: controlOption).displayString, "⌃⌥9")
    }

    /// The order macOS menus use, whatever order the bits were set in.
    func testModifiersAreDrawnInMenuOrder() {
        let all = KeyCombo.modifiers(control: true, option: true, shift: true, command: true)
        XCTAssertEqual(KeyCombo(keyCode: 0, modifiers: all).displayString, "⌃⌥⇧⌘A")
    }

    func testSpecialKeysHaveSymbols() {
        let command = KeyCombo.Modifier.command
        XCTAssertEqual(KeyCombo(keyCode: 123, modifiers: command).displayString, "⌘←")
        XCTAssertEqual(KeyCombo(keyCode: 49, modifiers: command).displayString, "⌘空格")
        XCTAssertEqual(KeyCombo(keyCode: 122, modifiers: command).displayString, "⌘F1")
    }

    /// An unknown code still reads as something rather than as nothing.
    func testAnUnknownKeyIsNamedByCode() {
        XCTAssertEqual(KeyCombo(keyCode: 200, modifiers: KeyCombo.Modifier.command).keyName,
                       "键 200")
    }

    func testShiftAloneIsNotEnough() {
        XCTAssertFalse(KeyCombo(keyCode: 0, modifiers: KeyCombo.Modifier.shift).hasRequiredModifier)
        XCTAssertFalse(KeyCombo(keyCode: 0, modifiers: 0).hasRequiredModifier)
        XCTAssertTrue(KeyCombo(keyCode: 0, modifiers: KeyCombo.Modifier.control).hasRequiredModifier)
        XCTAssertTrue(KeyCombo(keyCode: 0, modifiers: KeyCombo.Modifier.option).hasRequiredModifier)
        XCTAssertTrue(KeyCombo(keyCode: 0, modifiers: KeyCombo.Modifier.command).hasRequiredModifier)
    }

    /// The bits `RegisterEventHotKey` expects. A typo here would register
    /// every hotkey on the wrong modifiers with no error anywhere.
    func testModifierBitsMatchCarbon() {
        XCTAssertEqual(KeyCombo.Modifier.command, 0x0100)
        XCTAssertEqual(KeyCombo.Modifier.shift, 0x0200)
        XCTAssertEqual(KeyCombo.Modifier.option, 0x0800)
        XCTAssertEqual(KeyCombo.Modifier.control, 0x1000)
    }

    // MARK: Assigning

    private func state(_ count: Int) -> PersistedState {
        var state = PersistedState()
        state.profiles = (0 ..< count).map { DockProfile(kind: .customDock, name: "布局 \($0)") }
        return state
    }

    func testAssigningSetsTheShortcut() {
        var s = state(2)
        let combo = KeyCombo(keyCode: 18, modifiers: controlOption)
        s.assignShortcut(combo, to: s.profiles[0].id)
        XCTAssertEqual(s.profiles[0].shortcut, combo)
        XCTAssertEqual(s.shortcutBindings, [ShortcutBinding(profileID: s.profiles[0].id, combo: combo)])
    }

    /// Two registrations of one combination cannot both work, so it moves.
    func testATakenCombinationMoves() {
        var s = state(2)
        let combo = KeyCombo(keyCode: 18, modifiers: controlOption)
        s.assignShortcut(combo, to: s.profiles[0].id)
        s.assignShortcut(combo, to: s.profiles[1].id)
        XCTAssertNil(s.profiles[0].shortcut)
        XCTAssertEqual(s.profiles[1].shortcut, combo)
    }

    func testNilClears() {
        var s = state(1)
        s.assignShortcut(KeyCombo(keyCode: 18, modifiers: controlOption), to: s.profiles[0].id)
        s.assignShortcut(nil, to: s.profiles[0].id)
        XCTAssertNil(s.profiles[0].shortcut)
        XCTAssertTrue(s.shortcutBindings.isEmpty)
    }

    func testAnUnsafeCombinationIsRefused() {
        var s = state(1)
        s.assignShortcut(KeyCombo(keyCode: 0, modifiers: KeyCombo.Modifier.shift), to: s.profiles[0].id)
        XCTAssertNil(s.profiles[0].shortcut)
    }

    /// A shortcut that came in from a hand-edited file or an old backup is
    /// kept, but never handed to the system.
    func testBindingsSkipUnsafeStoredCombinations() {
        var s = state(1)
        s.profiles[0].shortcut = KeyCombo(keyCode: 0, modifiers: KeyCombo.Modifier.shift)
        XCTAssertTrue(s.shortcutBindings.isEmpty)
    }

    func testAShortcutSurvivesARoundTrip() throws {
        var s = state(1)
        let combo = KeyCombo(keyCode: 18, modifiers: controlOption)
        s.assignShortcut(combo, to: s.profiles[0].id)
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(PersistedState.self, from: data)
        XCTAssertEqual(back.profiles[0].shortcut, combo)
    }

    // MARK: Cycling

    private let a = UUID(), b = UUID(), c = UUID()

    func testStepsForwardAndBack() {
        XCTAssertEqual(LayoutCycle.neighbour(of: a, in: [a, b, c], step: 1), b)
        XCTAssertEqual(LayoutCycle.neighbour(of: b, in: [a, b, c], step: -1), a)
    }

    func testWrapsAtBothEnds() {
        XCTAssertEqual(LayoutCycle.neighbour(of: c, in: [a, b, c], step: 1), a)
        XCTAssertEqual(LayoutCycle.neighbour(of: a, in: [a, b, c], step: -1), c)
    }

    func testOneLayoutGoesNowhere() {
        XCTAssertEqual(LayoutCycle.neighbour(of: a, in: [a], step: 1), a)
    }

    func testNoLayoutsIsNil() {
        XCTAssertNil(LayoutCycle.neighbour(of: a, in: [], step: 1))
    }

    func testAMissingCurrentStartsFromTheEndTheStepPointsAt() {
        XCTAssertEqual(LayoutCycle.neighbour(of: nil, in: [a, b, c], step: 1), a)
        XCTAssertEqual(LayoutCycle.neighbour(of: UUID(), in: [a, b, c], step: -1), c)
    }

    // MARK: Gesture

    /// A swipe is many small deltas; it must add up to one step, not many.
    func testOneSwipeIsOneStep() {
        var gesture = LayoutGesture()
        gesture.begin()
        var steps: [Int] = []
        for i in 0 ..< 30 {
            if let step = gesture.feed(-8, precise: true, at: Double(i) * 0.016) { steps.append(step) }
        }
        XCTAssertEqual(steps, [1])
    }

    func testASmallSwipeDoesNothing() {
        var gesture = LayoutGesture()
        gesture.begin()
        XCTAssertNil(gesture.feed(-10, precise: true, at: 0))
        XCTAssertNil(gesture.feed(-10, precise: true, at: 0.016))
    }

    func testDirection() {
        var forward = LayoutGesture()
        XCTAssertEqual(forward.feed(-1, precise: false, at: 0), 1)
        var back = LayoutGesture()
        XCTAssertEqual(back.feed(1, precise: false, at: 0), -1)
    }

    func testANewGestureCanStepAgainAfterTheCooldown() {
        var gesture = LayoutGesture()
        gesture.begin()
        XCTAssertEqual(gesture.feed(-50, precise: true, at: 0), 1)
        gesture.begin()
        XCTAssertNil(gesture.feed(-50, precise: true, at: 0.1), "inside the cooldown")
        gesture.begin()
        XCTAssertEqual(gesture.feed(-50, precise: true, at: 1), 1)
    }

    /// A wheel spun quickly sends several notches; the cooldown makes that
    /// one step, and a deliberate notch later still moves.
    func testWheelNotchesRespectTheCooldown() {
        var gesture = LayoutGesture()
        XCTAssertEqual(gesture.feed(-1, precise: false, at: 0), 1)
        XCTAssertNil(gesture.feed(-1, precise: false, at: 0.05))
        XCTAssertNil(gesture.feed(-1, precise: false, at: 0.1))
        XCTAssertEqual(gesture.feed(-1, precise: false, at: 0.5), 1)
    }

    /// No phase arrives from some devices; a pause is taken as a lift.
    func testAPauseStartsANewGesture() {
        var gesture = LayoutGesture()
        XCTAssertEqual(gesture.feed(-50, precise: true, at: 0), 1)
        XCTAssertEqual(gesture.feed(-50, precise: true, at: 2), 1)
    }

    func testSideways() {
        XCTAssertTrue(LayoutGesture.isSideways(dx: 10, dy: 1))
        XCTAssertFalse(LayoutGesture.isSideways(dx: 10, dy: 9), "diagonal")
        XCTAssertFalse(LayoutGesture.isSideways(dx: 0, dy: 10))
    }

    // MARK: Focus

    func testOnlyTheFirstLayoutIsRemembered() {
        var revert = FocusRevert()
        revert.remember(.customDock, current: a)
        revert.remember(.customDock, current: b)
        XCTAssertEqual(revert.customDock, FocusRevert.Saved(profileID: a))
        XCTAssertNil(revert.macOSDock)
    }

    /// "No layout" on Apple's Dock is a real answer and must be told apart
    /// from "the Focus never touched it".
    func testNoMacOSLayoutIsRemembered() {
        var revert = FocusRevert()
        revert.remember(.macOSDock, current: nil)
        XCTAssertEqual(revert.macOSDock, FocusRevert.Saved(profileID: nil))
        XCTAssertNil(revert.customDock)
    }

    /// The record is persisted, and a state file that predates it, or a
    /// shelf setting that predates the gesture toggle, still decodes.
    func testOlderStateDecodesWithDefaults() throws {
        let json = #"{"version":1,"customDock":{"position":"left"}}"#
        let state = try JSONDecoder().decode(PersistedState.self, from: Data(json.utf8))
        XCTAssertNil(state.focusRevert)
        XCTAssertTrue(state.customDock.switchLayoutsByGesture)
    }

    func testFocusRevertRoundTrips() throws {
        var s = PersistedState()
        s.focusRevert = FocusRevert(customDock: .init(profileID: a), macOSDock: .init(profileID: nil))
        let back = try JSONDecoder().decode(PersistedState.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back.focusRevert, s.focusRevert)
    }
}
