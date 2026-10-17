import Foundation

// MARK: - Key combinations

public extension KeyCombo {
    /// Carbon's modifier bits, spelled out rather than imported.
    ///
    /// The values are `cmdKey`, `shiftKey`, `optionKey` and `controlKey` from
    /// Carbon's HIToolbox. Copied because this file is compiled into the test
    /// target, which has no reason to pull Carbon in, and because these are
    /// the bits `RegisterEventHotKey` expects, so they cannot drift.
    enum Modifier {
        public static let command: UInt32 = 1 << 8
        public static let shift: UInt32 = 1 << 9
        public static let option: UInt32 = 1 << 11
        public static let control: UInt32 = 1 << 12
    }

    /// Virtual key codes that the recorder treats specially.
    enum Key {
        public static let escape: UInt32 = 53
        public static let delete: UInt32 = 51
        public static let forwardDelete: UInt32 = 117
    }

    static func modifiers(control: Bool, option: Bool, shift: Bool, command: Bool) -> UInt32 {
        (control ? Modifier.control : 0)
            | (option ? Modifier.option : 0)
            | (shift ? Modifier.shift : 0)
            | (command ? Modifier.command : 0)
    }

    /// Whether this combination is safe to claim system wide.
    ///
    /// Shift alone is not enough: a global hotkey on Shift-A would eat every
    /// capital A typed in every app, and the user would have no idea why.
    var hasRequiredModifier: Bool {
        modifiers & (Modifier.control | Modifier.option | Modifier.command) != 0
    }

    /// Modifiers in the order the menus of macOS draw them.
    var modifierSymbols: String {
        var out = ""
        if modifiers & Modifier.control != 0 { out += "⌃" }
        if modifiers & Modifier.option != 0 { out += "⌥" }
        if modifiers & Modifier.shift != 0 { out += "⇧" }
        if modifiers & Modifier.command != 0 { out += "⌘" }
        return out
    }

    /// The key's label on an ANSI keyboard.
    ///
    /// Only the code is stored, so this is what the key is called on a US
    /// layout. On another layout a letter key can be labelled differently,
    /// but the code, which is what the hotkey actually matches, is the same
    /// physical key either way.
    var keyName: String {
        Self.names[keyCode] ?? tr("键 \(keyCode)")
    }

    var displayString: String { modifierSymbols + keyName }

    private static let names: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
        27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        36: "↩", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "N", 46: "M", 47: ".", 48: "⇥", 49: tr("空格"), 50: "`", 51: "⌫", 53: "⎋",
        65: tr("小键盘 ."), 67: tr("小键盘 *"), 69: tr("小键盘 +"), 71: tr("小键盘清除"), 75: tr("小键盘 /"),
        76: "⌤", 78: tr("小键盘 -"), 81: tr("小键盘 ="),
        82: tr("小键盘 0"), 83: tr("小键盘 1"), 84: tr("小键盘 2"), 85: tr("小键盘 3"), 86: tr("小键盘 4"),
        87: tr("小键盘 5"), 88: tr("小键盘 6"), 89: tr("小键盘 7"), 91: tr("小键盘 8"), 92: tr("小键盘 9"),
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11",
        105: "F13", 106: "F16", 107: "F14", 109: "F10", 111: "F12", 113: "F15",
        64: "F17", 79: "F18", 80: "F19", 90: "F20",
        114: tr("帮助"), 115: "↖", 116: "⇞", 117: "⌦", 118: "F4", 119: "↘", 120: "F2",
        121: "⇟", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑",
    ]
}

/// One layout's claim on a key combination, as the hotkey service sees it.
public struct ShortcutBinding: Hashable, Sendable {
    public var profileID: UUID
    public var combo: KeyCombo

    public init(profileID: UUID, combo: KeyCombo) {
        self.profileID = profileID
        self.combo = combo
    }
}

public extension PersistedState {
    /// Every layout that has a usable shortcut, in list order.
    var shortcutBindings: [ShortcutBinding] {
        profiles.compactMap { profile in
            guard let combo = profile.shortcut, combo.hasRequiredModifier else { return nil }
            return ShortcutBinding(profileID: profile.id, combo: combo)
        }
    }

    /// Gives a layout a shortcut, or takes it away with nil.
    ///
    /// A combination already held by another layout moves rather than being
    /// shared. Two registrations of one combination cannot both succeed, so
    /// sharing would leave whichever registered second silently dead, while
    /// the settings row went on showing it as if it worked.
    mutating func assignShortcut(_ combo: KeyCombo?, to id: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        if let combo {
            guard combo.hasRequiredModifier else { return }
            for other in profiles.indices where other != index && profiles[other].shortcut == combo {
                profiles[other].shortcut = nil
            }
        }
        profiles[index].shortcut = combo
    }
}

// MARK: - Cycling

public enum LayoutCycle {
    /// The layout `step` places away from `current`, wrapping at either end.
    ///
    /// A current layout that is not in the list, which is what a deleted or
    /// never-chosen one looks like, starts from the end the step points at
    /// rather than doing nothing: the gesture should always land somewhere.
    public static func neighbour(of current: UUID?, in ids: [UUID], step: Int) -> UUID? {
        guard !ids.isEmpty else { return nil }
        guard let current, let index = ids.firstIndex(of: current) else {
            return step >= 0 ? ids.first : ids.last
        }
        let count = ids.count
        return ids[((index + step) % count + count) % count]
    }
}

// MARK: - Gesture

/// Turns a stream of scroll deltas into whole layout steps.
///
/// A trackpad swipe arrives as dozens of small deltas followed by a momentum
/// tail, and a mouse wheel as one event per notch. Without this a single
/// swipe would race through every layout, so a precise gesture is allowed
/// one step until it ends, and every step is followed by a cooldown.
public struct LayoutGesture: Sendable {
    /// Points of trackpad travel for one step. Far enough that a swipe which
    /// was meant as a scroll does not change the shelf under the pointer.
    public static let threshold = 40.0
    /// Long enough to cover a quick spin of a wheel, short enough that a
    /// deliberate second notch still moves.
    public static let cooldown: TimeInterval = 0.35
    /// A pause this long means the fingers lifted, even if no phase said so.
    public static let idleReset: TimeInterval = 0.3

    private var travelled = 0.0
    private var spent = false
    private var lastEvent: TimeInterval = -.greatestFiniteMagnitude
    private var lastStep: TimeInterval = -.greatestFiniteMagnitude

    public init() {}

    /// A new gesture has started under the fingers.
    public mutating func begin() {
        travelled = 0
        spent = false
    }

    /// One scroll event. Returns +1, -1, or nil when no step is due.
    ///
    /// Negative deltas step forward: the content moves towards the start,
    /// which is how paging to the next thing feels on a trackpad.
    public mutating func feed(_ delta: Double, precise: Bool, at time: TimeInterval) -> Int? {
        if time - lastEvent > Self.idleReset { begin() }
        lastEvent = time
        guard delta != 0, !spent, time - lastStep >= Self.cooldown else { return nil }

        // A notch is already one deliberate click, so it moves at once.
        travelled = precise ? travelled + delta : delta
        guard !precise || abs(travelled) >= Self.threshold else { return nil }

        let step = travelled < 0 ? 1 : -1
        lastStep = time
        travelled = 0
        if precise { spent = true }
        return step
    }

    /// Whether a trackpad delta is a sideways swipe rather than a scroll that
    /// wobbled. The margin keeps a diagonal drag from counting as either.
    public static func isSideways(dx: Double, dy: Double) -> Bool {
        abs(dx) > abs(dy) * 1.5
    }
}

// MARK: - Focus

/// What a Focus changed, so ending the Focus can put it back.
///
/// Persisted because the Focus can end while Docket is not running: macOS
/// launches the app to report it, and an in-memory record would be gone by
/// then.
public struct FocusRevert: Codable, Hashable, Sendable {
    /// The layout a surface had before the first Focus switched it. The
    /// wrapper exists because nil is a real answer for Apple's Dock ("no
    /// layout") and has to be told apart from "not switched".
    public struct Saved: Codable, Hashable, Sendable {
        public var profileID: UUID?
        public init(profileID: UUID?) { self.profileID = profileID }
    }

    public var customDock: Saved?
    public var macOSDock: Saved?

    public init(customDock: Saved? = nil, macOSDock: Saved? = nil) {
        self.customDock = customDock
        self.macOSDock = macOSDock
    }

    /// Records what a surface showed, unless something already did.
    ///
    /// Only the first record counts. Moving from one Focus straight into
    /// another reports the second layout without an end in between, and
    /// recording again would make the first Focus's layout the one that
    /// ending the Focus returns to.
    public mutating func remember(_ kind: ProfileKind, current: UUID?) {
        switch kind {
        case .customDock: if customDock == nil { customDock = Saved(profileID: current) }
        case .macOSDock: if macOSDock == nil { macOSDock = Saved(profileID: current) }
        }
    }
}
