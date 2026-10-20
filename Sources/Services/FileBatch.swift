import AppKit
import Foundation

/// 「下载」和「最近截图」多选以后的批量操作：移到、压缩、删除（进废纸篓）、改名，
/// 还有取消正在下载的文件。
///
/// 删除一律 `trashItem`，在废纸篓里能找回，不直接抹掉。移动和压缩撞名时自动
/// 加编号，绝不覆盖已有的文件。
@MainActor
enum FileBatch {
    struct Outcome {
        var done: [URL] = []
        var failed = 0
        /// 移到或压缩以后新文件的位置。
        var created: [URL] = []
    }

    // MARK: 删除

    static func trash(_ urls: [URL]) -> Outcome {
        var outcome = Outcome()
        for url in urls {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                outcome.done.append(url)
            } catch {
                outcome.failed += 1
            }
        }
        if outcome.failed > 0 { NSSound.beep() }
        return outcome
    }

    // MARK: 移到

    static func move(_ urls: [URL], to folder: URL) -> Outcome {
        var outcome = Outcome()
        let fm = FileManager.default
        var taken = Set((try? fm.contentsOfDirectory(atPath: folder.path)) ?? [])
        for url in urls {
            // 已经在这个文件夹里的不动。
            if url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL { continue }
            let name = FileRename.unique(url.lastPathComponent, taken: taken)
            let target = folder.appendingPathComponent(name)
            do {
                try fm.moveItem(at: url, to: target)
                taken.insert(name)
                outcome.done.append(url)
                outcome.created.append(target)
            } catch {
                outcome.failed += 1
            }
        }
        if outcome.failed > 0 { NSSound.beep() }
        return outcome
    }

    // MARK: 改名

    /// 改好返回新位置；名字不对返回原因。
    static func rename(_ url: URL, to proposed: String) -> Result<URL?, FileRename.Problem> {
        let folder = url.deletingLastPathComponent()
        let siblings = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        switch FileRename.check(proposed, original: url.lastPathComponent, siblings: siblings) {
        case .failure(let problem):
            return .failure(problem)
        case .success(nil):
            return .success(nil)
        case .success(let name?):
            let target = folder.appendingPathComponent(name)
            do {
                try FileManager.default.moveItem(at: url, to: target)
                return .success(target)
            } catch {
                return .failure(.taken)
            }
        }
    }

    // MARK: 压缩

    /// 和访达的「压缩」一样放在同一个文件夹里：一个文件用 ditto（保留包和扩展属性），
    /// 几个文件用 zip 打成「归档.zip」。在后台跑，返回新压缩包的位置。
    static func compress(_ urls: [URL]) async -> URL? {
        guard let first = urls.first else { return nil }
        let folder = first.deletingLastPathComponent()
        // 只压同一个文件夹里的（两个面板都只列一个文件夹的第一层）。
        let items = urls.filter { $0.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL }
        guard !items.isEmpty else { return nil }
        let taken = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        let name = ArchiveNaming.name(for: items.map(\.lastPathComponent), taken: taken)
        let target = folder.appendingPathComponent(name)
        let status: Int32
        if items.count == 1 {
            status = await run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent",
                                                  items[0].path, target.path], in: folder)
        } else {
            status = await run("/usr/bin/zip", ["-r", "-y", "-q", name] + items.map(\.lastPathComponent), in: folder)
        }
        guard status == 0, FileManager.default.fileExists(atPath: target.path) else {
            try? FileManager.default.removeItem(at: target)
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

    // MARK: 取消下载

    /// 取消一个还没下完的文件。浏览器（Safari、Chrome）把下载进度发布成系统的
    /// `Progress`，访达图标上那个叉就是 cancel 它；这里一样做。没有浏览器发布
    /// 进度时（别的下载工具），把残件移到废纸篓，浏览器那边会显示下载失败。
    static func cancelDownload(_ url: URL) async -> Bool {
        let box = CancelBox()
        let token = subscribe(url, box: box)
        try? await Task.sleep(for: .milliseconds(900))
        Progress.removeSubscriber(token)
        if box.cancelled { return true }
        guard FileManager.default.fileExists(atPath: url.path) else { return true }
        return (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil
    }

    /// 放在 nonisolated 里：发布回调在系统的线程上调用，不能继承主线程隔离。
    nonisolated private static func subscribe(_ url: URL, box: CancelBox) -> Any {
        Progress.addSubscriber(forFileURL: url) { progress in
            if progress.isCancellable {
                progress.cancel()
                box.markCancelled()
            }
            return nil
        }
    }

    // MARK: 移到哪

    struct Destination: Identifiable, Hashable {
        var url: URL
        var title: String
        var id: URL { url }
    }

    private static let recentKey = "fileBatch.recentFolders"

    /// 菜单里的文件夹：文稿、桌面、最近选过的（最多 3 个），去掉现在这个文件夹和已经不在的。
    static func destinations(excluding current: URL) -> [Destination] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var list = [Destination(url: home.appendingPathComponent("Documents", isDirectory: true), title: tr("文稿")),
                    Destination(url: home.appendingPathComponent("Desktop", isDirectory: true), title: tr("桌面"))]
        for path in UserDefaults.standard.stringArray(forKey: recentKey) ?? [] {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { continue }
            let url = URL(fileURLWithPath: path, isDirectory: true)
            let parent = url.deletingLastPathComponent().lastPathComponent
            list.append(Destination(url: url, title: parent.isEmpty ? url.lastPathComponent : "\(parent) / \(url.lastPathComponent)"))
        }
        var seen = Set<String>()
        let skip = current.standardizedFileURL.path
        return list.filter { seen.insert($0.url.standardizedFileURL.path).inserted && $0.url.standardizedFileURL.path != skip }
    }

    static func remember(_ folder: URL) {
        let next = RecentFolders.adding(folder.standardizedFileURL.path,
                                        to: UserDefaults.standard.stringArray(forKey: recentKey) ?? [])
        UserDefaults.standard.set(next, forKey: recentKey)
    }
}

/// 发布回调里记一下「真的取消了」。回调在系统的线程上，所以加锁。
private final class CancelBox: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var cancelled: Bool { lock.withLock { flag } }
    func markCancelled() { lock.withLock { flag = true } }
}
