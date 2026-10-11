import Foundation
import Observation

/// Spotlight, by name, through `/usr/bin/mdfind`.
///
/// The command line tool rather than `NSMetadataQuery`: it is the same
/// index, it answers once and exits, and the result is a list of paths
/// that crosses back to the main thread as plain strings.
@MainActor @Observable
final class FileSearch {
    static let shared = FileSearch()

    private(set) var results: [ListedFile] = []
    private(set) var query = ""
    private(set) var searching = false

    @ObservationIgnored private var generation = 0

    private init() {}

    func search(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        query = trimmed
        generation &+= 1
        let ticket = generation
        guard !trimmed.isEmpty else {
            results = []
            searching = false
            return
        }
        searching = true
        Task {
            let paths = await Self.run(trimmed)
            guard ticket == generation else { return }
            searching = false
            results = paths.prefix(30).map { path in
                let url = URL(fileURLWithPath: path)
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey,
                                                               .isDirectoryKey, .isPackageKey,
                                                               .fileSizeKey])
                return ListedFile(url: url,
                                  date: values?.contentModificationDate ?? .distantPast,
                                  isDirectory: values?.isDirectory == true && values?.isPackage != true,
                                  size: values?.fileSize.map(Int64.init))
            }
        }
    }

    nonisolated private static func run(_ query: String) async -> [String] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
                process.arguments = ["-name", query]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: [])
                    return
                }
                // Read before waiting, or a long answer fills the pipe and
                // the tool never exits.
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let text = String(decoding: data, as: UTF8.self)
                let paths = text.split(whereSeparator: \.isNewline).map(String.init)
                    .filter { !$0.contains("/.") && !$0.hasPrefix("/System/") && !$0.hasPrefix("/Library/") }
                continuation.resume(returning: paths)
            }
        }
    }
}
