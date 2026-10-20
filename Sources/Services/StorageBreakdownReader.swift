import Foundation
import Observation

/// 圆环仪表面板里「存储被谁占了」：/Applications、下载文件夹和废纸篓各多大。
///
/// 只在面板打开时量，而且十分钟内不重量（结果留在内存里）。逐个文件加实际占用
/// （`totalFileAllocatedSize`），在后台线程走，量完回主线程发布。读不到的那块
/// （下载文件夹没给权限、废纸篓要完全磁盘访问权限）是 nil，面板不画它，算进「其他」。
@MainActor @Observable
final class StorageBreakdownReader {
    static let shared = StorageBreakdownReader()

    private(set) var breakdown: StorageBreakdown?
    private(set) var measuring = false

    @ObservationIgnored private var measuredAt = Date.distantPast
    @ObservationIgnored private var task: Task<Void, Never>?

    private init() {}

    /// 面板出现时调；正在量或十分钟内量过就不动。
    func refresh() {
        guard !measuring, Date.now.timeIntervalSince(measuredAt) > 600 else { return }
        measuring = true
        task = Task.detached(priority: .utility) {
            let result = Self.measure()
            await MainActor.run {
                let reader = StorageBreakdownReader.shared
                reader.breakdown = result
                reader.measuredAt = .now
                reader.measuring = false
                reader.task = nil
            }
        }
    }

    nonisolated private static func measure() -> StorageBreakdown {
        let manager = FileManager.default
        let home = manager.homeDirectoryForCurrentUser
        let apps = size(of: URL(fileURLWithPath: "/Applications", isDirectory: true))
        let downloads = size(of: home.appendingPathComponent("Downloads", isDirectory: true))
        let trashURL = manager.urls(for: .trashDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent(".Trash", isDirectory: true)
        let trash = size(of: trashURL)
        return StorageBreakdown(apps: apps, downloads: downloads, trash: trash)
    }

    /// 一个文件夹里所有文件的实际占用；列不出（没权限、不存在）是 nil。
    nonisolated private static func size(of folder: URL) -> Int64? {
        let manager = FileManager.default
        // 先试着列一层：没权限时这里就失败，不当成 0。
        guard (try? manager.contentsOfDirectory(atPath: folder.path)) != nil else { return nil }
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        guard let walker = manager.enumerator(at: folder, includingPropertiesForKeys: keys, options: [],
                                              errorHandler: { _, _ in true }) else { return nil }
        var total: Int64 = 0
        for case let url as URL in walker {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }
}
