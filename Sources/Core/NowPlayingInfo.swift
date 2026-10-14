import Foundation

/// The system's Now Playing, as `NowPlayingReader`'s script prints it: one
/// JSON object, or an empty line when nothing is playing.
///
/// Kept apart from the reader so the parsing, including which app the
/// reading belongs to and how far a playing track has moved since the
/// system stamped it, can be tested without a Mac playing anything.
public struct NowPlayingInfo: Decodable, Equatable, Sendable {
    public var id: String?
    public var parent: String?
    public var title: String?
    public var artist: String?
    public var album: String?
    public var duration: Double?
    public var elapsed: Double?
    public var rate: Double?
    /// When `elapsed` was true, seconds since 1970.
    public var stamp: Double?
    public var playing: Bool?

    public struct Track: Equatable, Sendable {
        public var title: String
        public var artist: String
        public var album: String
        public var duration: TimeInterval
        public var elapsed: TimeInterval
        public var isPlaying: Bool
    }

    public static func decode(_ text: String) -> NowPlayingInfo? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(NowPlayingInfo.self, from: data)
    }

    /// The track, when the reading belongs to `bundleID` (the app itself or
    /// a helper whose parent it is) and has a title.
    public func track(for bundleID: String, now: Date) -> Track? {
        guard id == bundleID || parent == bundleID else { return nil }
        guard let title, !title.isEmpty else { return nil }
        let isPlaying = playing ?? ((rate ?? 0) > 0)
        let duration = max(0, duration ?? 0)
        var elapsed = max(0, elapsed ?? 0)
        // The system stamps elapsed time when it changes, not every second.
        if isPlaying, let stamp, stamp > 0 {
            elapsed += max(0, now.timeIntervalSince1970 - stamp) * max(rate ?? 1, 0.0001)
        }
        if duration > 0 { elapsed = min(elapsed, duration) }
        return Track(title: title, artist: artist ?? "", album: album ?? "",
                     duration: duration, elapsed: elapsed, isPlaying: isPlaying)
    }
}
