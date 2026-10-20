import AppKit
import Foundation

/// 文件暂存里选中的几个文件压成一个包。
///
/// 暂存里的文件来自不同文件夹，访达的「压缩」只压同一个文件夹里的。都在
/// 一个文件夹时照「下载」面板的做法（`FileBatch.compress`）；分散在几处时，
/// 在临时文件夹里给每个文件建一个替身，用 zip 跟着替身把原文件打进去（不加
/// -y，所以存的是文件本身不是替身），压缩包放在第一个文件旁边。原文件一概
/// 不动，临时文件夹用完就删。
@MainActor
enum ShelfArchive {
    static func compress(_ urls: [URL]) async -> URL? {
        guard let first = urls.first else { return nil }
        let folder = first.deletingLastPathComponent().standardizedFileURL
        let together = urls.allSatisfy { $0.deletingLastPathComponent().standardizedFileURL == folder }
        if together { return await FileBatch.compress(urls) }

        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("docket-shelf-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        } catch {
            NSSound.beep()
            return nil
        }
        var names: [String] = []
        for url in urls {
            let name = FileRename.unique(url.lastPathComponent, taken: Set(names))
            do {
                try fm.createSymbolicLink(at: staging.appendingPathComponent(name), withDestinationURL: url)
                names.append(name)
            } catch {
                continue
            }
        }
        guard !names.isEmpty else {
            NSSound.beep()
            return nil
        }
        let taken = Set((try? fm.contentsOfDirectory(atPath: folder.path)) ?? [])
        let target = folder.appendingPathComponent(ArchiveNaming.name(for: names, taken: taken))
        let status = await run("/usr/bin/zip", ["-r", "-q", target.path] + names, in: staging)
        guard status == 0, fm.fileExists(atPath: target.path) else {
            try? fm.removeItem(at: target)
            NSSound.beep()
            return nil
        }
        return target
    }

    nonisolated private static func run(_ tool: String, _ arguments: [String], in folder: URL) async -> Int32 {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            process.currentDirectoryURL = folder
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: -1)
            }
        }
    }
}
