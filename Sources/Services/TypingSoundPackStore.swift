import Foundation

// 导入 Mechvibes 声音包（码头 Pro）：用户选一个 .zip 或文件夹，读 config.json，确认每个用到的
// 声音文件都在、都解得开，再把 config.json 和这些文件拷到
// Application Support/<bundle id>/TypingSoundPacks/<id>/。不内置下载、不联网。

enum TypingSoundPackStore {
    /// 导入失败的原因，直接给用户看。
    struct ImportError: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private static var bundleID: String { Bundle.main.bundleIdentifier ?? "com.docket-zh.app" }

    static var folder: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: bundleID, directoryHint: .isDirectory)
            .appending(path: TypingSoundPacks.folderName, directoryHint: .isDirectory)
    }

    static func url(for id: String) -> URL? {
        guard TypingSoundPacks.isValidID(id) else { return nil }
        return folder?.appending(path: id, directoryHint: .isDirectory)
    }

    /// 导入一个 .zip 或文件夹，成功时返回记录（还没写进设置）。很慢的事（解压、解码），
    /// 别在主线程调。
    static func importPack(from source: URL) throws -> TypingSoundPackRecord {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: source.path, isDirectory: &isDirectory) else {
            throw ImportError(message: tr("找不到这个文件。"))
        }
        var cleanup: URL?
        defer { if let cleanup { try? fm.removeItem(at: cleanup) } }

        let root: URL
        if isDirectory.boolValue {
            root = source
        } else {
            guard source.pathExtension.lowercased() == "zip" else {
                throw ImportError(message: tr("请选 Mechvibes 声音包的 .zip 或解压后的文件夹。"))
            }
            let size = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size <= TypingSoundPacks.maxZipBytes else {
                throw ImportError(message: tr("压缩包太大（超过 80 MB）。"))
            }
            let temp = fm.temporaryDirectory.appending(path: "dockling-pack-\(UUID().uuidString)",
                                                       directoryHint: .isDirectory)
            try fm.createDirectory(at: temp, withIntermediateDirectories: true)
            cleanup = temp
            try unzip(source, to: temp)
            root = temp
        }

        guard let packRoot = findConfig(in: root) else {
            throw ImportError(message: tr("没找到 config.json，这不像 Mechvibes 声音包。"))
        }
        let configURL = packRoot.appending(path: "config.json")
        let pack: MechvibesPack
        do {
            pack = try MechvibesPack.parse(try Data(contentsOf: configURL))
        } catch let error as MechvibesPack.ParseError {
            throw ImportError(message: error.message)
        } catch {
            throw ImportError(message: tr("读不了 config.json。"))
        }

        // 每个用到的文件都要在包里，而且这台 Mac 解得开。
        let rootPath = packRoot.standardizedFileURL.resolvingSymlinksInPath().path
        let segmentsByFile = Dictionary(grouping: Set(pack.definitions.values), by: \.file)
        var usableSegments = 0
        for file in pack.files {
            let url = packRoot.appending(path: file)
            let resolved = url.standardizedFileURL.resolvingSymlinksInPath().path
            guard resolved.hasPrefix(rootPath + "/"), fm.fileExists(atPath: resolved) else {
                throw ImportError(message: tr("声音包里缺少文件：\(file)"))
            }
            do {
                let whole = try TypingSoundDecoder.decode(url)
                let frames = Int(whole.frameLength)
                usableSegments += (segmentsByFile[file] ?? []).filter {
                    TypingSoundPacks.frameRange(startMs: $0.start, endMs: $0.end, sampleRate: whole.format.sampleRate,
                                                totalFrames: frames) != nil
                }.count
            } catch TypingSoundDecoder.Failure.tooLong(_) {
                throw ImportError(message: tr("\(file) 太长（超过 3 分钟），不像按键声音。"))
            } catch {
                let ext = (file as NSString).pathExtension.lowercased()
                if ext == "ogg" || ext == "flac" {
                    throw ImportError(message: tr("这台 Mac 解不开 \(file)（.\(ext) 格式）。可以先用音频软件转成 wav 或 m4a，改好 config.json 里的文件名再导入。"))
                }
                throw ImportError(message: tr("解不开 \(file)，文件可能坏了或格式不支持。"))
            }
        }

        // 时间段全落在声音文件外面（sprite 写错了）：导进来也只会默默退回青轴，直接说清楚。
        guard usableSegments > 0 else {
            throw ImportError(message: tr("config.json 里每个键的时间段都超出了声音文件的长度。"))
        }

        // 拷到 Application Support：只拷 config.json 和用到的声音文件。
        guard let base = folder else { throw ImportError(message: tr("找不到存声音包的文件夹。")) }
        let id = UUID().uuidString.lowercased()
        let destination = base.appending(path: id, directoryHint: .isDirectory)
        do {
            try fm.createDirectory(at: destination, withIntermediateDirectories: true)
            try fm.copyItem(at: configURL, to: destination.appending(path: "config.json"))
            for file in pack.files {
                let target = destination.appending(path: file)
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.copyItem(at: packRoot.appending(path: file), to: target)
            }
        } catch {
            try? fm.removeItem(at: destination)
            throw ImportError(message: tr("保存声音包时出错：\(error.localizedDescription)"))
        }

        let fallback = isDirectory.boolValue ? source.lastPathComponent : source.deletingPathExtension().lastPathComponent
        return TypingSoundPackRecord(id: id, name: TypingSoundPacks.displayName(pack, fallback: fallback),
                                     author: String(pack.author.prefix(60)), method: pack.method.rawValue,
                                     keyCount: pack.definitions.count)
    }

    /// 删掉一个导入的包的文件。
    static func remove(_ id: String) {
        guard let url = url(for: id) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// 删掉设置里已经没有的包的文件夹（比如恢复了旧备份）。只动自己文件夹里、名字像 id 的。
    static func prune(keeping ids: Set<String>) {
        guard let base = folder,
              let names = try? FileManager.default.contentsOfDirectory(atPath: base.path) else { return }
        for name in names where TypingSoundPacks.isValidID(name) && !ids.contains(name) {
            try? FileManager.default.removeItem(at: base.appending(path: name, directoryHint: .isDirectory))
        }
    }

    // MARK: 解压和找 config.json

    /// 用系统自带的 ditto 解压（访达「解压」用的同一个）。
    private static func unzip(_ zip: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zip.path, destination.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw ImportError(message: tr("解压失败。"))
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw ImportError(message: tr("解压失败，压缩包可能坏了。")) }
    }

    /// config.json 在顶层或往下三层以内（zip 里常多包一层文件夹），跳过 __MACOSX。
    private static func findConfig(in root: URL) -> URL? {
        var queue: [(URL, Int)] = [(root, 0)]
        let fm = FileManager.default
        while !queue.isEmpty {
            let (folder, depth) = queue.removeFirst()
            if fm.fileExists(atPath: folder.appending(path: "config.json").path) { return folder }
            guard depth < 3, let items = try? fm.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]) else { continue }
            for item in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
            where item.lastPathComponent != "__MACOSX" {
                let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values?.isDirectory == true, values?.isSymbolicLink != true { queue.append((item, depth + 1)) }
            }
        }
        return nil
    }
}
