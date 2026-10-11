import Foundation

/// Reads and writes the single `state.json` that holds everything Docket knows.
///
/// No database, no sync, no migration framework - one JSON file the user can
/// read, back up, and delete. `version` exists so a future format change can
/// refuse to silently misread an old file.
public struct Store: Sendable {
    public let url: URL

    public init(bundleID: String = Bundle.main.bundleIdentifier ?? "com.docket-zh.app") {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: bundleID, directoryHint: .isDirectory)
        self.url = base.appending(path: "state.json")
    }

    /// Points at a directory of its own, so a test never touches the real one.
    public init(directory: URL) {
        self.url = directory.appending(path: "state.json")
    }

    /// Set when `load()` had to set a file aside, naming where it went.
    ///
    /// Losing a setup silently is the worst thing this type can do, so the
    /// fact is carried out rather than only logged.
    public private(set) nonisolated(unsafe) static var quarantined: URL?

    public func load() -> PersistedState {
        guard let data = try? Data(contentsOf: url) else { return PersistedState() }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let state = try decoder.decode(PersistedState.self, from: data)
            // A file from a newer Docket would decode partially and silently
            // drop what it doesn't understand; refusing is the honest move -
            // but refusing still means the next save overwrites it, so it is
            // put aside first, exactly like an unreadable one.
            guard state.version <= PersistedState.currentVersion else {
                quarantine()
                return PersistedState()
            }
            return state
        } catch {
            quarantine()
            return PersistedState()
        }
    }

    /// Moves an unusable state file aside so the next save cannot overwrite it.
    ///
    /// This used to move it to a fixed `state.json.corrupt`. `moveItem` will
    /// not overwrite an existing destination, so the second time it ran it
    /// failed silently, and the only copy of the user's setup was replaced by
    /// a first-run default on the save that followed. The stamp makes every
    /// quarantine a new file, which is the whole point of keeping one.
    private func quarantine() {
        // Seconds alone are not unique enough: two failures inside the same
        // second collide, moveItem refuses the second, and the file it was
        // meant to protect is left to be overwritten. That is the original
        // defect in a smaller form, so the name carries a random suffix too.
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let unique = UUID().uuidString.prefix(8)
        let aside = url.appendingPathExtension("quarantined-\(stamp)-\(unique)")
        guard (try? FileManager.default.moveItem(at: url, to: aside)) != nil else { return }
        Self.quarantined = aside
    }

    public func save(_ state: PersistedState) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        // Atomic: a crash mid-write must not leave a truncated state file.
        try data.write(to: url, options: .atomic)
    }
}
