import AppKit
import Observation

/// How full the Trash is, for the 废纸篓 widget and the shelf's Trash icon.
///
/// macOS guards ~/.Trash: an app without Full Disk Access gets "Operation
/// not permitted" listing it, so `needsAccess` is a state the widget shows
/// with a button to the right Settings pane rather than a silent zero.
/// Checking is cheap (the folder's modification date and item count) every
/// few seconds; the full size, which walks every file, is only recounted
/// when that changes or every five minutes. External volumes' trashes are
/// not counted.
@MainActor @Observable
final class TrashMonitor {
    static let shared = TrashMonitor()

    private(set) var bytes: Int64 = 0
    private(set) var items = 0
    private(set) var needsAccess = false
    private(set) var loaded = false
    /// 最近扔进来的几个（最新的在前，最多 `TrashedItem.shownLimit` 个），带访达
    /// 记下的原位置，面板的「最近扔的」用。
    private(set) var recent: [TrashedItem] = []
    /// When the Trash first went over each threshold anything shows flies
    /// for (the widget's and the shelf Trash icon's), kept across launches
    /// so the hourly flies survive a restart.
    private(set) var overSince: [Int64: Date] = [:]

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastStamp: (Date?, Int)?
    @ObservationIgnored private var lastFullCount: Date = .distantPast
    @ObservationIgnored private var counting = false
    @ObservationIgnored private var watching: Set<Int64> = []

    /// One date per threshold, keyed by its byte count as text.
    private static let overSinceKey = "trash.overSinceByThreshold"
    /// The single date written before thresholds were tracked separately;
    /// read once as the default threshold's.
    private static let legacyOverSinceKey = "trash.overSince"

    static var trashURL: URL {
        FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash")
    }

    private init() {
        let defaults = UserDefaults.standard
        if let stored = defaults.dictionary(forKey: Self.overSinceKey) as? [String: Double] {
            for (key, seconds) in stored {
                guard let threshold = Int64(key), seconds > 0 else { continue }
                overSince[threshold] = Date(timeIntervalSince1970: seconds)
            }
        } else {
            let legacy = defaults.double(forKey: Self.legacyOverSinceKey)
            if legacy > 0 {
                overSince[TrashFlies.thresholdBytes(TrashFlies.defaultThreshold)] = Date(timeIntervalSince1970: legacy)
            }
        }
    }

    /// Starts watching, and counts flies for `threshold` from now on. Called
    /// by everything that shows flies, each with its own size; safe to call
    /// again.
    func start(threshold: Int64) {
        watching.insert(threshold)
        guard timer == nil else {
            updateOverSince()
            return
        }
        check(force: true)
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check(force: false) }
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// None while access is missing: an unreadable Trash has no size, and
    /// flies over a zero would be a guess.
    func flies(now: Date, threshold: Int64) -> Int {
        guard !needsAccess else { return 0 }
        return TrashFlies.count(bytes: bytes, threshold: threshold, overSince: overSince[threshold], now: now)
    }

    func check(force: Bool) {
        guard !counting else { return }
        counting = true
        let url = Self.trashURL
        let wantsFull = force || Date.now.timeIntervalSince(lastFullCount) > 300
        let previous = lastStamp
        Task.detached(priority: .utility) {
            let result = Self.measure(url, previous: previous, full: wantsFull)
            await MainActor.run { self.apply(result) }
        }
    }

    private struct TrashReading: Sendable {
        var denied = false
        var stamp: (Date?, Int)?
        var items: Int?
        var bytes: Int64?
        var recent: [TrashedItem]?
    }

    nonisolated private static func measure(_ url: URL, previous: (Date?, Int)?, full: Bool) -> TrashReading {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: url.path) else {
            return TrashReading(denied: true)
        }
        let visible = names.filter { $0 != ".DS_Store" && $0 != ".localized" }
        let modified = (try? manager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        let stamp = (modified, visible.count)
        let changed = previous.map { $0.0 != stamp.0 || $0.1 != stamp.1 } ?? true
        guard full || changed else { return TrashReading(stamp: stamp, items: visible.count) }
        let recent = listRecent(url, names: visible)

        var total: Int64 = 0
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        if let walker = manager.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) {
            for case let file as URL in walker {
                guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
                total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            }
        }
        return TrashReading(stamp: stamp, items: visible.count, bytes: total, recent: recent)
    }

    /// 按加入废纸篓的时间排出最近几个，并从 .DS_Store 读出访达记下的原位置。
    nonisolated private static func listRecent(_ url: URL, names: [String]) -> [TrashedItem] {
        let keys: Set<URLResourceKey> = [.addedToDirectoryDateKey, .contentModificationDateKey,
                                         .isDirectoryKey, .isPackageKey]
        let all = names.filter(TrashedItem.isListed).map { name -> TrashedItem in
            let values = try? url.appendingPathComponent(name).resourceValues(forKeys: keys)
            let date = values?.addedToDirectoryDate ?? values?.contentModificationDate ?? .distantPast
            let folder = values?.isDirectory == true && values?.isPackage != true
            return TrashedItem(trashName: name, date: date, isDirectory: folder)
        }
        var recent = TrashedItem.recent(all)
        guard !recent.isEmpty else { return [] }
        let store = (try? Data(contentsOf: url.appendingPathComponent(".DS_Store"))) ?? Data()
        let origins = TrashPutBack.origins(DSStore.records(store))
        for index in recent.indices {
            recent[index].origin = origins[recent[index].trashName]
        }
        return recent
    }

    private func apply(_ result: TrashReading) {
        counting = false
        loaded = true
        needsAccess = result.denied
        guard !result.denied else {
            if !recent.isEmpty { recent = [] }
            return
        }
        lastStamp = result.stamp
        if let items = result.items { self.items = items }
        if let recent = result.recent, recent != self.recent { self.recent = recent }
        if let bytes = result.bytes {
            self.bytes = bytes
            lastFullCount = .now
        }
        if items == 0 {
            bytes = 0
            if !recent.isEmpty { recent = [] }
        }
        updateOverSince()
    }

    private func updateOverSince() {
        let next = TrashFlies.overSince(previous: overSince, watching: watching, bytes: bytes, now: .now)
        guard next != overSince else { return }
        overSince = next
        let stored = Dictionary(uniqueKeysWithValues: next.map { (String($0.key), $0.value.timeIntervalSince1970) })
        UserDefaults.standard.set(stored, forKey: Self.overSinceKey)
        UserDefaults.standard.removeObject(forKey: Self.legacyOverSinceKey)
    }

    // MARK: Actions

    /// Moves dropped files to the Trash, the same as ⌘⌫ in Finder, so they
    /// can be put back.
    @discardableResult
    func trash(_ urls: [URL]) -> Bool {
        var moved = false
        for url in urls where url.isFileURL {
            if (try? FileManager.default.trashItem(at: url, resultingItemURL: nil)) != nil { moved = true }
        }
        if moved { check(force: true) }
        return moved
    }

    func open() {
        NSWorkspace.shared.open(Self.trashURL)
    }

    /// 废纸篓里这一项的位置。
    func location(of item: TrashedItem) -> URL {
        Self.trashURL.appendingPathComponent(item.trashName)
    }

    /// 在访达里选中它（访达的「放回原处」和手动拖出来都从这里开始）。
    func reveal(_ item: TrashedItem) {
        NSWorkspace.shared.activateFileViewerSelecting([location(of: item)])
    }

    /// 放回访达记下的原位置。成功返回 nil，否则返回给用户看的一句话：不知道原位置、
    /// 原文件夹不在了、原位置有同名的、没有权限、或者这一项已经不在废纸篓里了。
    func putBack(_ item: TrashedItem) -> String? {
        let manager = FileManager.default
        let source = location(of: item)
        guard manager.fileExists(atPath: source.path) else {
            check(force: true)
            return tr("「\(item.displayName)」已经不在废纸篓里了")
        }
        var isFolder: ObjCBool = false
        let folderExists = item.origin.map { manager.fileExists(atPath: $0.folder, isDirectory: &isFolder) } ?? false
        let targetExists = item.origin.map { manager.fileExists(atPath: $0.path) } ?? false
        let plan = TrashPutBack.plan(origin: item.origin, folderExists: folderExists && isFolder.boolValue,
                                     targetExists: targetExists)
        guard case .move(let path) = plan else {
            return TrashPutBack.message(plan, item: item.displayName)
        }
        do {
            try manager.moveItem(at: source, to: URL(fileURLWithPath: path))
        } catch {
            check(force: true)
            if Self.isPermissionError(error) { return TrashPutBack.deniedMessage(item: item.displayName) }
            return tr("没能放回「\(item.displayName)」：\(error.localizedDescription)")
        }
        recent.removeAll { $0.id == item.id }
        check(force: true)
        return nil
    }

    nonisolated private static func isPermissionError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain,
           [NSFileWriteNoPermissionError, NSFileReadNoPermissionError].contains(ns.code) { return true }
        let underlying = (ns.userInfo[NSUnderlyingErrorKey] as? NSError) ?? ns
        return underlying.domain == NSPOSIXErrorDomain && [Int(EPERM), Int(EACCES)].contains(underlying.code)
    }

    /// Asks first, then has Finder empty it, which is the one public way to
    /// empty every trash including external disks'.
    func empty() {
        QuickActions.perform(.emptyTrash) { [weak self] in
            self?.check(force: true)
        }
    }

    static let fullDiskAccessURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!

    func openAccessSettings() {
        NSWorkspace.shared.open(Self.fullDiskAccessURL)
    }
}
