import AppKit
import CoreServices
import Foundation
import Observation

/// Which player a reading came from.
public enum MusicSource: String, Sendable, CaseIterable {
    case spotify, appleMusic, netease

    var bundleID: String {
        switch self {
        case .spotify: "com.spotify.client"
        case .appleMusic: "com.apple.Music"
        case .netease: "com.netease.163music"
        }
    }

    /// 网易云音乐 has no AppleScript dictionary: it is read from the system's
    /// Now Playing and driven with the media keys, so it cannot be seeked.
    public var canSeek: Bool { self != .netease }

    var displayName: String {
        switch self {
        case .spotify: "Spotify"
        case .appleMusic: "音乐"
        case .netease: "网易云音乐"
        }
    }
}

/// One player's current track.
///
/// `@unchecked Sendable` only because of `artwork`: `NSImage` carries no
/// `Sendable` conformance, but the image here is built once and never mutated,
/// so handing the struct between actors is safe in practice.
public struct NowPlaying: @unchecked Sendable, Equatable {
    public var title: String
    public var artist: String
    public var album: String
    public var duration: TimeInterval
    public var elapsed: TimeInterval
    public var isPlaying: Bool
    public var artwork: NSImage?
    /// The colour the panel stands on, taken from the artwork's bytes at
    /// decode time rather than from the image afterwards.
    public var tint: ArtworkTint?
    public var source: MusicSource

    /// 0…1, and never NaN - a live stream reports a zero duration.
    public var progress: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, elapsed / duration))
    }

    /// Identity of the *track*, used to decide when artwork has to be refetched.
    var trackKey: String { "\(source.rawValue)\u{1}\(title)\u{1}\(artist)\u{1}\(album)" }
}

/// Spotify and Apple Music, over Apple events.
///
/// Deliberately not MediaRemote: that framework has been entitlement-gated
/// since macOS 15.4. It loads and the symbol resolves, so it looks like it
/// works; the callback is then handed nil, with no error and no diagnostic.
/// Claiming the entitlement is not a way round it either, since an ad-hoc
/// binary asserting a private entitlement is killed at launch.
///
/// Nothing here ever launches a player - an app that is not already running is
/// skipped, so the shelf cannot boot iTunes to ask what is playing.
@MainActor @Observable
public final class MusicService {
    public static let shared = MusicService()

    /// Last good reading. A failed poll leaves it alone rather than blanking
    /// the tile every time a script times out.
    public private(set) var nowPlaying: NowPlaying?
    /// True when a player is running but macOS has not been asked for consent
    /// yet (or consent was refused). The tile shows a "Connect" button for
    /// this instead of us triggering a prompt at launch.
    public private(set) var needsAutomationPermission = false

    /// Whether a *supported* player is open at all.
    ///
    /// Only Spotify and Apple Music can be read. Browser audio cannot: the
    /// one system-wide source is MediaRemote, which Apple entitlement-gated
    /// in macOS 15.4. The widget needs to say which of "nothing is open" and
    /// "something is open but idle" it is looking at, or it reads as broken
    /// whenever music is playing in a tab.
    public private(set) var hasPlayer = false

    /// Sources to consult, in the order the config prefers them.
    public var enabled: [MusicSource] = MusicSource.allCases

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var polling = false
    /// Consecutive probes that never came back.
    @ObservationIgnored private var timeouts = 0

    /// When we last spoke to the player ourselves.
    @ObservationIgnored private var lastCommand: Date = .distantPast

    /// The play state the user asked for, until a reading confirms it.
    @ObservationIgnored private var asked: Bool?

    /// How long a reading may contradict what was just asked for before it is
    /// believed. Same bargain as the browser side: long enough for the player
    /// to hear the command and be read again, short enough that a command
    /// which never landed corrects itself quickly.
    private static let commandHold: TimeInterval = 1.5

    /// How long after one of our own commands a timed-out probe is treated as
    /// our own traffic rather than as the player refusing.
    ///
    /// Long enough to cover a burst of clicks plus one probe's budget, short
    /// enough that something genuinely unresponsive still gives up within a
    /// few seconds of the last press.
    private static let commandGrace: TimeInterval = 5

    /// Set once a probe has hung; cleared when the user asks to connect.
    @ObservationIgnored private var blocked = false
    @ObservationIgnored private var lastProbe: Date = .distantPast

    /// Only a playing track needs second-by-second refreshing, for its scrubber.
    private var probeInterval: TimeInterval {
        guard let playing = nowPlaying else { return 8 }
        // 0.85 rather than 1: a strict 1.0 against a 1s timer means jitter
        // makes every other tick miss, halving the scrubber's update rate.
        return playing.isPlaying ? 0.85 : 5
    }
    @ObservationIgnored private var artworkKey: String?

    private init() {}

    // MARK: Lifecycle

    /// Idempotent; every Now Playing tile on the shelf shares one poll.
    public func start() {
        guard timer == nil else { return }
        refresh()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: Reading

    public func refresh() {
        // Every reason not to poll is weighed *before* the in-flight flag is
        // armed. This used to set `polling = true` first and then return early
        // on the throttle below, which leaked the flag permanently: the timer
        // ticks at 1s, the idle interval is 8s, so the very first tick after
        // launch wedged the service for the life of the process.
        //
        // The conditions, in order: a slow player (Music with a huge library
        // can take a beat) must not queue a second poll behind the first; a
        // player we were never granted access to blocks the Apple Event
        // indefinitely, because the consent dialog is never shown for a
        // background agent that is never frontmost; and a paused player's
        // track does not change, so a synchronous Apple Event round trip once
        // a second is far too expensive to spend on nothing.
        let now = Date.now
        guard PollGate.shouldStart(inFlight: polling,
                                   blocked: blocked,
                                   sinceLastStart: now.timeIntervalSince(lastProbe),
                                   interval: probeInterval) else { return }
        polling = true
        lastProbe = now
        let sources = enabled
        Task { [sources] in
            let result = await withTimeout(seconds: 2) {
                await Bridge.probe(sources)
            }
            if let result {
                await self.apply(result)
            } else {
                self.stall()
            }
        }
    }

    /// The probe hung: stop asking (each attempt would strand another thread)
    /// and show the affordance that can actually resolve it.
    /// Slowness is not refusal.
    ///
    /// One slow probe used to block the service for the life of the process,
    /// but a player busy with a large library recovers on its own - only a
    /// player that never answers is actually refusing. Mirrors the browser
    /// side's three-strike backoff.
    private func stall() {
        polling = false
        // Back off rather than hammering a player that is busy.
        lastProbe = .now
        // Our own traffic, not a refusal. Same shape as the browser side:
        // commands and probes share a queue, so a run of presses starves the
        // probe behind them and three of those blocked the service, leaving
        // the tile asking for consent it already had.
        guard Date().timeIntervalSince(lastCommand) >= Self.commandGrace else { return }
        timeouts += 1

        // A player that has answered Docket before has been granted access,
        // and consent, once given, is not silently withdrawn: revoking it in
        // System Settings comes back as a -1743 on the next real attempt,
        // which the probe already reports as such. So a stall from a player
        // that has answered is slowness - a big library, a Mac just woken -
        // and the answer is to wait and ask again, never to stop syncing and
        // show a Connect button for permission that is already there. That
        // is what happened: three slow probes and the tile asked to connect
        // and stopped updating until it was clicked.
        if Self.hasAnswered {
            // Waits a little longer each time, to half a minute, so a player
            // that is struggling is not hammered while it recovers.
            lastProbe = Date().addingTimeInterval(min(30, 2 * Double(timeouts)))
            return
        }

        // Never answered: a player that has not been asked for consent does
        // not refuse, it hangs, because a background agent's consent prompt
        // is never shown. Only then is Connect the thing that can fix it.
        guard timeouts >= 3 else { return }
        blocked = true
        needsAutomationPermission = true
    }

    /// Whether a player has ever answered one of Docket's probes.
    ///
    /// Kept across launches, because the permission it stands for is too.
    private static var hasAnswered: Bool {
        get { UserDefaults.standard.bool(forKey: "music.hasAnswered") }
        set { UserDefaults.standard.set(newValue, forKey: "music.hasAnswered") }
    }



    private func apply(_ result: Bridge.Probe) async {
        defer { polling = false }
        timeouts = 0            // it answered, so it is not refusing
        needsAutomationPermission = result.needsPermission
        if result.sawRunningPlayer, !result.needsPermission { Self.hasAnswered = true }
        hasPlayer = result.sawRunningPlayer

        guard var track = result.track else {
            // Only clear once we know nothing is running. A script that failed
            // mid-song keeps the last good reading on screen.
            if result.sawRunningPlayer == false { nowPlaying = nil; artworkKey = nil }
            return
        }

        // A probe already in flight when the button was pressed comes back
        // describing the player as it was, and believing it flips the glyph
        // back under the pointer. Held until a reading agrees, or until the
        // window closes and a command that never landed is admitted.
        if let asked {
            if track.isPlaying == asked || Date().timeIntervalSince(lastCommand) >= Self.commandHold {
                self.asked = nil
            } else {
                track.isPlaying = asked
            }
        }

        if track.trackKey == artworkKey {
            track.artwork = nowPlaying?.artwork
            track.tint = nowPlaying?.tint
            nowPlaying = track
            return
        }

        // Show the new track immediately; artwork catches up a moment later.
        artworkKey = track.trackKey
        nowPlaying = track

        let key = track.trackKey
        // Budgeted. `apply` clears `polling` with a defer, which never runs if
        // the function never returns - and this await had no bound at all: an
        // Apple Music artwork event can hang indefinitely, and a URL fetch
        // only stops at URLSession's 60s default. Either wedged the service
        // exactly the way arming the flag too early used to.
        let found = await withTimeout(seconds: 5) {
            await Bridge.artwork(for: result.artworkRef)
        }
        // A later track may have landed while the download was in flight.
        guard artworkKey == key, var current = nowPlaying, current.trackKey == key else { return }
        current.artwork = found?.image
        current.tint = found?.tint
        nowPlaying = current
    }

    // MARK: Transport

    public func playPause() { command("playpause") }

    public func next() { command("next track") }

    /// What both apps do natively: restart the track if we are past the first
    /// few seconds, otherwise step back one.
    public func previous() {
        guard let source = nowPlaying?.source else { return }
        let restart = source.canSeek && (nowPlaying?.elapsed ?? 0) > 3
        if restart {
            seek(to: 0)
        } else {
            optimistically { $0.elapsed = 0 }
            Bridge.send("previous track", to: source)
        }
    }

    public func seek(to seconds: TimeInterval) {
        guard let track = nowPlaying, track.source.canSeek else { return }
        let target = max(0, track.duration > 0 ? min(seconds, track.duration) : seconds)
        optimistically { $0.elapsed = target }
        Bridge.send("set player position to \(String(format: "%.2f", target))", to: track.source)
    }

    /// Skip forward (positive) or back (negative) from where we are.
    public func skip(by seconds: TimeInterval) {
        guard let track = nowPlaying else { return }
        seek(to: track.elapsed + seconds)
    }

    private func command(_ body: String) {
        guard let source = nowPlaying?.source else { return }
        if body == "playpause" {
            optimistically { $0.isPlaying.toggle() }
            asked = nowPlaying?.isPlaying
        }
        lastCommand = .now
        Bridge.send(body, to: source)
    }

    /// Update the local reading straight away so a tap feels instant; the next
    /// poll (≤1s) replaces it with the truth either way.
    private func optimistically(_ change: (inout NowPlaying) -> Void) {
        guard var track = nowPlaying else { return }
        change(&track)
        nowPlaying = track
    }

    // MARK: Permission

    /// The only place that is allowed to raise the system consent dialog, and
    /// it runs solely because the user clicked "Connect".
    public func requestAutomationPermission() {
        let sources = enabled
        // The consent dialog is only shown for the frontmost app, and an
        // accessory agent with no ordinary window never becomes frontmost.
        let policy = NSApp.activationPolicy()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        blocked = false
        polling = false
        // The strike count too. You only reach Connect *because* three probes
        // timed out, so leaving the counter at three meant the very next
        // timeout hit four and re-blocked instantly - Connect became a
        // one-shot that flickered straight back.
        timeouts = 0
        lastProbe = .distantPast
        Task { [sources] in
            await Bridge.ask(sources)
            NSApp.setActivationPolicy(policy)
            self.refresh()
        }
    }
}

// MARK: - Apple event plumbing

/// Everything that talks to another process, kept off the main thread.
///
/// AppleScript execution is serialised onto one queue: `NSAppleScript` is not
/// documented as thread-safe, and a 1s poll has no need for concurrency.
enum Bridge {
    struct Probe: Sendable {
        var track: NowPlaying?
        var needsPermission = false
        /// Distinguishes "nothing is running" from "the script failed", so a
        /// transient error does not blank the tile.
        var sawRunningPlayer = false
        var artworkRef: ArtworkRef?
    }

    /// How to obtain artwork for the track we just read.
    enum ArtworkRef: Sendable {
        case url(URL)          // Spotify hands out an https image URL
        case appleMusic        // Music hands out raw bytes, over another event
        case nowPlaying        // 网易云音乐: the system's Now Playing artwork
    }

    private static let queue = DispatchQueue(label: "com.namanparashar.plinth.music")

    private static func offMain<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    // MARK: Probing

    /// Consent is judged from the result of the actual Apple Event, never
    /// from a pre-flight check.
    ///
    /// `AEDeterminePermissionToAutomateTarget` blocks - on a background queue
    /// it wedged this service permanently (one hung probe, and `polling` never
    /// cleared, so the widget sat on "Not playing" forever); moved to the main
    /// actor it froze the whole app and the shelf never appeared at all.
    /// Running the script and reading its error code tells us the same thing
    /// without blocking anything.
    static func probe(_ sources: [MusicSource]) async -> Probe {
        await offMain {
            var result = Probe()
            var fallback: (NowPlaying, ArtworkRef?)?

            for source in sources where isRunning(source) {
                result.sawRunningPlayer = true
                switch read(source) {
                case .denied:
                    // The pre-flight check can report a player as reachable
                    // when consent has merely never been asked for, so trust
                    // what the actual attempt says.
                    result.needsPermission = true
                case .idle:
                    continue
                case .track(let track, let artwork):
                    // Whatever is actually playing wins; otherwise the first
                    // enabled source that has a track loaded.
                    if track.isPlaying {
                        result.track = track
                        result.artworkRef = artwork
                        result.needsPermission = false
                        return result
                    }
                    if fallback == nil { fallback = (track, artwork) }
                }
            }

            if let fallback {
                result.track = fallback.0
                result.artworkRef = fallback.1
                result.needsPermission = false
            }
            return result
        }
    }

    /// The image and the colour behind it, together.
    ///
    /// Both branches already had the bytes in hand and dropped them into
    /// `NSImage(data:)`, so the tint costs one call beside the decode. Doing
    /// it later from the NSImage would mean re-encoding a picture we had.
    /// `Bridge` is a bare enum and so nonisolated, which is where this work
    /// belongs.
    static func artwork(for ref: ArtworkRef?) async -> (image: NSImage?, tint: ArtworkTint?) {
        switch ref {
        case .none:
            return (nil, nil)
        case .url(let url):
            // Never on the main thread, and a dead CDN just means no artwork.
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return (nil, nil) }
            return (NSImage(data: data), ArtworkTint.extract(data))
        case .appleMusic:
            let data = await offMain { () -> Data? in
                guard case .value(let descriptor) = script(
                    "tell application id \"com.apple.Music\" to get raw data of artwork 1 of current track"
                ) else { return nil }
                return descriptor.data
            }
            guard let data, !data.isEmpty else { return (nil, nil) }
            return (NSImage(data: data), ArtworkTint.extract(data))
        case .nowPlaying:
            let data = await offMain { NowPlayingReader.artwork() }
            guard let data, !data.isEmpty else { return (nil, nil) }
            return (NSImage(data: data), ArtworkTint.extract(data))
        }
    }

    // MARK: Commands

    static func send(_ body: String, to source: MusicSource) {
        guard isRunning(source) else { return }
        if source == .netease {
            switch body {
            case "playpause": MediaKeys.press(.playPause)
            case "next track": MediaKeys.press(.next)
            case "previous track": MediaKeys.press(.previous)
            default: break
            }
            return
        }
        let id = source.bundleID
        queue.async {
            guard permitted(source, ask: false) else { return }
            _ = script("tell application id \"\(id)\" to \(body)")
        }
    }

    static func ask(_ sources: [MusicSource]) async {
        await offMain {
            for source in sources where isRunning(source) && source != .netease {
                // A real event raises the dialog; the permission-check API
                // blocks instead of prompting.
                _ = script("tell application id \"\(source.bundleID)\" to return name")
            }
        }
    }

    // MARK: Primitives

    static func isRunning(_ source: MusicSource) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleID).isEmpty
    }

    /// `askUserIfNeeded: false` unless the user explicitly asked to connect -
    /// otherwise every launch throws a consent sheet at them.
    static func permitted(_ source: MusicSource, ask: Bool) -> Bool {
        guard let target = NSAppleEventDescriptor(bundleIdentifier: source.bundleID).aeDesc else { return false }
        return AEDeterminePermissionToAutomateTarget(target, typeWildCard, typeWildCard, ask) == noErr
    }

    enum ScriptOutcome {
        case value(NSAppleEventDescriptor)
        /// The Apple Event was refused, or consent has never been given.
        case denied
        case failed
    }

    /// Compiled scripts, keyed by source.
    ///
    /// Confined to the serial `music` queue - every call reaches here through
    /// `offMain`, so no locking is needed. Recompiling on each poll was the
    /// single biggest cost in a profile of the running app.
    nonisolated(unsafe) private static var compiled: [String: NSAppleScript] = [:]

    private static func script(_ source: String) -> ScriptOutcome {
        let script: NSAppleScript
        if let cached = compiled[source] {
            script = cached
        } else {
            guard let made = NSAppleScript(source: source) else { return .failed }
            made.compileAndReturnError(nil)
            compiled[source] = made
            script = made
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        guard let error else { return .value(result) }
        // -1743 not permitted, -1744 consent never granted. Swallowing these
        // made a blocked player indistinguishable from a stopped one, so the
        // widget sat on "Not playing" and never offered the way to fix it.
        let code = (error[NSAppleScript.errorNumber] as? Int) ?? 0
        return (code == -1743 || code == -1744) ? .denied : .failed
    }

    /// One round trip per player. Fields are tab-separated because a track
    /// title can contain almost anything else.
    enum Reading {
        case track(NowPlaying, ArtworkRef?)
        case idle
        case denied
    }

    private static func read(_ source: MusicSource) -> Reading {
        if source == .netease {
            guard let track = NowPlayingReader.read(bundleID: source.bundleID) else { return .idle }
            return .track(track, .nowPlaying)
        }
        let id = source.bundleID
        let extra = source == .spotify ? " & tab & (artwork url of t)" : ""
        let body = """
        tell application id "\(id)"
            if player state is stopped then return ""
            set t to current track
            return (name of t) & tab & (artist of t) & tab & (album of t) & tab \
        & ((duration of t) as text) & tab & ((player position) as text) & tab \
        & (player state as text)\(extra)
        end tell
        """
        let outcome = script(body)
        guard case .value(let descriptor) = outcome else {
            if case .denied = outcome { return .denied }
            return .idle
        }
        guard let raw = descriptor.stringValue else { return .idle }
        let f = raw.components(separatedBy: "\t")
        guard f.count >= 6, !f[0].isEmpty else { return .idle }

        // Spotify reports duration in milliseconds, Music in seconds.
        let rawDuration = Double(f[3]) ?? 0
        let duration = source == .spotify ? rawDuration / 1000 : rawDuration

        var track = NowPlaying(
            title: f[0], artist: f[1], album: f[2],
            duration: max(0, duration),
            elapsed: max(0, Double(f[4]) ?? 0),
            isPlaying: f[5] == "playing",
            artwork: nil, source: source
        )
        // A live stream reports no duration; clamp rather than draw a scrubber
        // past its own end.
        if track.duration > 0 { track.elapsed = min(track.elapsed, track.duration) }

        let ref: ArtworkRef? = switch source {
        case .spotify: f.count > 6 ? URL(string: f[6]).map(ArtworkRef.url) : nil
        case .appleMusic: .appleMusic
        case .netease: .nowPlaying
        }
        return .track(track, ref)
    }
}

// MARK: - Formatting

enum MusicTime {
    /// `m:ss`, growing to `h:mm:ss` for anything an hour long.
    static func clock(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let (h, m, s) = (total / 3600, (total / 60) % 60, total % 60)
        return h > 0
            ? "\(h):\(String(format: "%02d:%02d", m, s))"
            : "\(m):\(String(format: "%02d", s))"
    }
}
