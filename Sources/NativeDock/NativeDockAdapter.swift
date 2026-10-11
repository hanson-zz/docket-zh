import Foundation
import AppKit

/// Reads and writes Apple's Dock.
///
/// An actor because rapid profile switching must apply in order - two
/// overlapping writes plus two Dock restarts is how you end up with a Dock
/// that is a mix of both layouts.
///
/// Scope is deliberately narrow: only `persistent-apps` is ever written.
/// `persistent-others` (stacks, downloads folder, recent apps) is left
/// completely alone, which keeps the blast radius of a bug to the part of the
/// Dock the user explicitly asked Docket to manage.
public actor NativeDockAdapter {

    public enum Failure: LocalizedError {
        case readFailed
        case writeFailed
        case verificationFailed(expected: Int, found: Int)
        case rolledBack(reason: String)
        case dockDidNotRestart

        public var errorDescription: String? {
            switch self {
            case .readFailed:
                "无法读取当前的程序坞布局。"
            case .writeFailed:
                "无法写入程序坞布局。"
            case .verificationFailed(let expected, let found):
                "程序坞重启后有 \(found) 个项目，而不是预期的 \(expected) 个。"
            case .dockDidNotRestart:
                "程序坞重启后没有恢复运行。"
            case .rolledBack(let reason):
                "无法应用该布局，已恢复你之前的程序坞。（\(reason)）"
            }
        }
    }

    // Held as String, not CFString: CFString is not Sendable, and a static
    // one would be shared mutable state as far as Swift 6 is concerned.
    private static let domainName = "com.apple.dock"
    private static let keyName = "persistent-apps"
    private var domain: CFString { Self.domainName as CFString }
    private var key: CFString { Self.keyName as CFString }

    public init() {}

    // MARK: Read

    public func readLive() throws -> [MacOSDockTile] {
        CFPreferencesAppSynchronize(domain)
        guard let raw = CFPreferencesCopyValue(key, domain,
                                               kCFPreferencesCurrentUser,
                                               kCFPreferencesAnyHost) as? [[String: Any]]
        else { throw Failure.readFailed }
        return raw.compactMap(MacOSDockTile.init(dictionary:))
    }

    // MARK: Apply

    /// Writes `tiles` to Apple's Dock and restarts it.
    ///
    /// Always snapshots the live Dock first and restores it if the result
    /// doesn't verify. This is the only code in Docket that can visibly damage
    /// a user's setup, so it never writes without a verified read-back.
    public func apply(_ tiles: [MacOSDockTile]) async throws {
        let backup = try readLive()

        do {
            try write(tiles)
            let previous = try restartDock()
            // The Dock coming back is the part that can actually fail. Reading
            // the preference back only ever confirmed our own write.
            guard await waitForNewDock(replacing: previous) else {
                throw Failure.dockDidNotRestart
            }
            let applied = try await readAfterRestart(expecting: tiles)
            guard applied.count == tiles.count else {
                throw Failure.verificationFailed(expected: tiles.count, found: applied.count)
            }
        } catch {
            // Best-effort restore. If this throws too there is nothing further
            // we can do, so surface the original problem.
            try? write(backup)
            try? restartDock()
            throw Failure.rolledBack(reason: error.localizedDescription)
        }
    }

    private func write(_ tiles: [MacOSDockTile]) throws {
        let dicts = tiles.compactMap { $0.dictionary() }
        guard dicts.count == tiles.count else { throw Failure.writeFailed }
        CFPreferencesSetValue(key, dicts as CFArray, domain,
                              kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        guard CFPreferencesAppSynchronize(domain) else { throw Failure.writeFailed }
    }

    /// The Dock only reads `persistent-apps` at launch, so applying a layout
    /// means restarting it. `NSRunningApplication.terminate()` is preferred
    /// over `killall` - no subprocess, and it is the documented API.
    @discardableResult
    public func restartDock() throws -> [pid_t] {
        let docks = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
        guard !docks.isEmpty else { throw Failure.writeFailed }
        let before = docks.map(\.processIdentifier)
        // forceTerminate, not terminate: a graceful quit gives the Dock the
        // chance to flush its own cached prefs over the ones just written.
        for dock in docks { dock.forceTerminate() }
        return before
    }

    /// Waits for launchd to bring a *different* Dock back.
    ///
    /// The previous verification read the preference it had just written and
    /// compared it to itself, so it passed whatever the Dock did, including
    /// not restarting at all. This is the part that can genuinely fail: if no
    /// new process appears, the layout was written and nothing is using it.
    ///
    /// What still cannot be checked is what the Dock actually drew. Nothing
    /// public reports its tiles, so "verified" here means the preference is in
    /// place and a new Dock started after it, which is as far as the platform
    /// allows.
    private func waitForNewDock(replacing old: [pid_t]) async -> Bool {
        for _ in 0 ..< 50 {                                  // ~5s ceiling
            try? await Task.sleep(for: .milliseconds(100))
            let now = NSRunningApplication
                .runningApplications(withBundleIdentifier: "com.apple.dock")
                .map(\.processIdentifier)
            if let pid = now.first, !old.contains(pid) { return true }
        }
        return false
    }

    /// launchd brings the Dock straight back; poll until its prefs reflect the
    /// write rather than guessing at a sleep duration.
    private func readAfterRestart(expecting tiles: [MacOSDockTile]) async throws -> [MacOSDockTile] {
        let wanted = tiles.map(\.signature)
        var last: [MacOSDockTile] = []
        for _ in 0..<30 {                                   // ~3s ceiling
            try? await Task.sleep(for: .milliseconds(100))
            guard let current = try? readLive() else { continue }
            last = current
            if current.map(\.signature) == wanted { return current }
        }
        return last
    }

    // MARK: Capture

    /// Non-destructive capture of whatever the user currently has, for
    /// "Create from Current Dock".
    public func capture() throws -> [MacOSDockTile] {
        try readLive()
    }
}
