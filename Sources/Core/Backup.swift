import Foundation

/// Reading and writing a backup of the user's profiles.
///
/// Deliberately not the whole state file. A backup is for moving a setup to
/// another Mac or keeping it before an experiment, and the rest of that file
/// is about *this* machine: which display the shelf is pinned to, whether
/// Apple's Dock is currently lent out, the answer to the update question.
/// Restoring those onto another machine would be restoring somebody else's
/// hardware.
public enum Backup {

    /// What a backup file holds.
    ///
    /// Versioned separately from `PersistedState`, because a backup outlives
    /// the app that wrote it by definition: it is the format most likely to be
    /// read by a much newer build.
    public struct Payload: Codable, Sendable {
        public static let currentVersion = 1

        public var version: Int
        public var exported: Date
        public var profiles: [DockProfile]
        /// Which profiles were active, so a restore lands on the same shelf
        /// rather than on whichever happens to be first.
        public var customProfileID: UUID?
        public var macOSProfileID: UUID?

        public init(version: Int = Payload.currentVersion, exported: Date = .now,
                    profiles: [DockProfile], customProfileID: UUID?, macOSProfileID: UUID?) {
            self.version = version
            self.exported = exported
            self.profiles = profiles
            self.customProfileID = customProfileID
            self.macOSProfileID = macOSProfileID
        }
    }

    public static let fileExtension = "docketprofiles"

    /// A name that sorts and does not collide: "Docket Profiles 2026-09-27".
    public static func suggestedName(on date: Date = .now) -> String {
        let stamp = date.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        return "Docket 布局 \(stamp).\(fileExtension)"
    }

    public static func encode(_ state: PersistedState) throws -> Data {
        let payload = Payload(profiles: state.profiles,
                              customProfileID: state.customDock.profileID,
                              macOSProfileID: state.macOSDock.profileID)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    public static func decode(_ data: Data) throws -> Payload {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(Payload.self, from: data)
        guard payload.version <= Payload.currentVersion else { throw Failure.tooNew }
        return payload
    }

    /// Merges a backup into the current state.
    ///
    /// Adds rather than replaces, matching on identifier. A restore that wiped
    /// what was already there would make importing one setup from another Mac
    /// a destructive act, and there would be nothing to undo it with. A
    /// profile the backup and this machine both have is taken from the
    /// backup, which is what restoring it means.
    public static func merge(_ payload: Payload, into state: inout PersistedState) {
        for incoming in payload.profiles {
            if let existing = state.profiles.firstIndex(where: { $0.id == incoming.id }) {
                state.profiles[existing] = incoming
            } else {
                state.profiles.append(incoming)
            }
        }
        // Only follow the backup's active profile if it actually arrived.
        if let id = payload.customProfileID, state.profiles.contains(where: { $0.id == id }) {
            state.customDock.profileID = id
        }
        if let id = payload.macOSProfileID, state.profiles.contains(where: { $0.id == id }) {
            state.macOSDock.profileID = id
        }
    }

    public enum Failure: LocalizedError {
        case tooNew

        public var errorDescription: String? {
            switch self {
            case .tooNew:
                "此备份由更新版本的 Docket 创建。"
            }
        }
    }
}
