import Foundation

/// Names and times for the voice recorder, kept pure so they can be tested.
public enum RecordingNaming {
    public static let prefix = "录音 "
    public static let fileExtension = "m4a"

    /// "录音 2026-10-12 09.30.05.m4a": sortable, and with no colon, which
    /// Finder shows as a slash.
    public static func fileName(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let stamp = String(format: "%04d-%02d-%02d %02d.%02d.%02d",
                           c.year ?? 0, c.month ?? 0, c.day ?? 0,
                           c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
        return "\(prefix)\(stamp).\(fileExtension)"
    }

    /// A name that does not collide with one already taken, by adding " 2",
    /// " 3" before the extension. Two presses in the same second are
    /// otherwise the same file, and the second would overwrite the first.
    public static func unique(_ name: String, taken: Set<String>) -> String {
        guard taken.contains(name) else { return name }
        let base = name.hasSuffix("." + fileExtension) ? String(name.dropLast(fileExtension.count + 1)) : name
        var n = 2
        while taken.contains("\(base) \(n).\(fileExtension)") { n += 1 }
        return "\(base) \(n).\(fileExtension)"
    }

    /// Whether a file in the folder is one of ours.
    public static func isRecording(_ name: String) -> Bool {
        name.hasPrefix(prefix) && name.lowercased().hasSuffix("." + fileExtension)
    }

    /// "0:07", "12:34", "1:02:03".
    public static func elapsed(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.isFinite ? seconds : 0))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
