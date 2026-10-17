import Foundation

// MARK: - 灵动提示: settings

/// The floating capsule under the notch, and what it is allowed to show.
///
/// Everything defaults to off: a window that appears over the menu bar on
/// its own is something a person should ask for.
public struct IslandSettings: Codable, Hashable, Sendable {
    public var volume: Bool = false
    public var brightness: Bool = false
    public var meeting: Bool = false
    /// How many minutes before an event the countdown appears.
    public var meetingMinutes: Int = IslandSettings.defaultMinutes

    public static let defaultMinutes = 5
    public static let minuteChoices: [Int] = [1, 3, 5, 10, 15]

    public init() {}

    public var anyEnabled: Bool { volume || brightness || meeting }

    /// A saved choice that is no longer offered falls back to the default
    /// rather than to a number no picker row shows.
    public var leadMinutes: Int {
        IslandSettings.minuteChoices.contains(meetingMinutes) ? meetingMinutes : IslandSettings.defaultMinutes
    }

    /// Lenient decoding, so a state file from before this existed, or from a
    /// later version with more keys, still loads.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        volume = try c.decodeIfPresent(Bool.self, forKey: .volume) ?? false
        brightness = try c.decodeIfPresent(Bool.self, forKey: .brightness) ?? false
        meeting = try c.decodeIfPresent(Bool.self, forKey: .meeting) ?? false
        meetingMinutes = try c.decodeIfPresent(Int.self, forKey: .meetingMinutes) ?? IslandSettings.defaultMinutes
    }
}

// MARK: - Levels

/// A level as the capsule draws it: a row of segments, a glyph and a figure.
public enum IslandLevel {
    public static let segments = 16

    /// How many segments are lit. Anything above silence lights at least
    /// one, so the lowest audible step never draws as empty.
    public static func lit(_ level: Double, of count: Int = segments) -> Int {
        guard count > 0, level.isFinite else { return 0 }
        let clamped = min(1, max(0, level))
        if clamped == 0 { return 0 }
        return max(1, min(count, Int((clamped * Double(count)).rounded())))
    }

    public static func percent(_ level: Double) -> Int {
        guard level.isFinite else { return 0 }
        return Int((min(1, max(0, level)) * 100).rounded())
    }

    /// Whether a new reading is worth showing. Core Audio reports the same
    /// volume again after unrelated property changes, and a display's
    /// brightness wobbles in the last decimal place while auto-brightness
    /// settles; neither should flash the capsule.
    public static func changed(from old: Double?, to new: Double, threshold: Double = 0.004) -> Bool {
        guard let old else { return false }
        return abs(new - old) >= threshold
    }

    public static func volumeSymbol(_ level: Double, muted: Bool) -> String {
        if muted || level <= 0 { return "speaker.slash.fill" }
        switch level {
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }

    public static func brightnessSymbol(_ level: Double) -> String {
        level < 0.5 ? "sun.min.fill" : "sun.max.fill"
    }
}

// MARK: - Meeting countdown

public enum IslandCountdown {
    /// "5 分钟后": whole minutes, rounded up, so a meeting 4 minutes 10
    /// seconds away says 5 rather than claiming more time than there is
    /// left to spare. Under a minute says so; at or past the start, 现在.
    public static func text(secondsUntil seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return tr("现在") }
        if seconds < 60 { return tr("不到 1 分钟后") }
        let minutes = Int((seconds / 60).rounded(.up))
        return tr("\(minutes) 分钟后")
    }

    /// The capsule's whole line.
    public static func line(title: String, secondsUntil seconds: TimeInterval) -> String {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(text(secondsUntil: seconds))：\(name.isEmpty ? tr("新日程") : name)"
    }

    /// Whether an event starting at `start` is inside the countdown window.
    /// Shown from `lead` minutes before until the minute it starts.
    public static func inWindow(start: Date, now: Date, leadMinutes: Int) -> Bool {
        let seconds = start.timeIntervalSince(now)
        return seconds > -60 && seconds <= Double(max(0, leadMinutes)) * 60
    }

    public struct Candidate: Equatable, Sendable {
        public var title: String
        public var start: Date
        public var isAllDay: Bool

        public init(title: String, start: Date, isAllDay: Bool) {
            self.title = title
            self.start = start
            self.isAllDay = isAllDay
        }
    }

    /// The event to count down to: the soonest timed one in the window. An
    /// all-day event has no start worth counting to.
    public static func next(_ events: [Candidate], now: Date, leadMinutes: Int) -> Candidate? {
        events.filter { !$0.isAllDay && inWindow(start: $0.start, now: now, leadMinutes: leadMinutes) }
            .min { $0.start == $1.start ? $0.title < $1.title : $0.start < $1.start }
    }
}

// MARK: - What the capsule shows

/// The capsule's content, decided apart from the window that draws it.
public enum IslandContent: Equatable, Sendable {
    case volume(level: Double, muted: Bool)
    case brightness(level: Double)
    case meeting(title: String, start: Date)

    /// A level change outranks the countdown for a moment, then the
    /// countdown comes back.
    public static func resolve(flash: IslandContent?, meeting: IslandContent?) -> IslandContent? {
        flash ?? meeting
    }

    /// How long a level flash stays up after the last change.
    public static let flashDuration: TimeInterval = 1.6
}

// MARK: - Where the capsule sits

/// The capsule's window and the part of it that is actually drawn, decided
/// apart from AppKit so the shelf can steer clear of it and tests can check
/// the numbers.
///
/// AppKit screen coordinates throughout: y runs up, a screen's top is its
/// `maxY`.
public enum IslandLayout {
    /// The window: wider and much taller than the capsule, so the capsule's
    /// spring and shadow are never clipped. It is clear and ignores the mouse.
    public static let panelSize = CGSize(width: 440, height: 96)

    /// The capsule itself is 34pt tall and grows from the window's top edge.
    public static let capsuleHeight: CGFloat = 34

    /// Room under the capsule for its shadow (radius 8, 3pt down) and the
    /// little overshoot of its entrance spring.
    public static let shadowAllowance: CGFloat = 12

    /// How long the capsule holds back when the shelf has to step aside
    /// first, so it never draws over a shelf that is still on its way out.
    /// Matches the shelf's own slide.
    public static let yieldDelay: TimeInterval = 0.22

    /// The window's frame on the screen with the menu bar: centred, just
    /// under the notch when there is one, just under the menu bar when not.
    ///
    /// - Parameters:
    ///   - screen: that screen's full frame.
    ///   - visibleMaxY: the top of its `visibleFrame`.
    ///   - notch: `safeAreaInsets.top`, zero on a display without a notch.
    public static func panelFrame(screen: CGRect, visibleMaxY: CGFloat, notch: CGFloat) -> CGRect {
        let top = notch > 0 ? screen.maxY - notch - 4 : visibleMaxY - 6
        return CGRect(x: screen.midX - panelSize.width / 2, y: top - panelSize.height,
                      width: panelSize.width, height: panelSize.height)
    }

    /// What the capsule can cover inside its window, in any state it draws:
    /// the full width (the widest capsule, a meeting title, is 392pt), from
    /// the window's top edge down to the bottom of the capsule's shadow.
    /// The rest of the window is empty and is not worth keeping clear.
    public static func occupied(panel: CGRect) -> CGRect {
        let height = min(panel.height, capsuleHeight + shadowAllowance)
        return CGRect(x: panel.minX, y: panel.maxY - height, width: panel.width, height: height)
    }
}
