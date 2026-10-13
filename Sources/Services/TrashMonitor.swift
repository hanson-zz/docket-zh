import AppKit
import Observation

/// How full the Trash is, for the 废纸篓 widget.
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
    /// When the Trash first went over the widget's threshold; kept across
    /// launches so the hourly flies survive a restart.
    private(set) var overSince: Date?

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastStamp: (Date?, Int)?
    @ObservationIgnored private var lastFullCount: Date = .distantPast
    @ObservationIgnored private var counting = false
    @ObservationIgnored private var threshold: Int64 = TrashFlies.thresholdBytes(TrashFlies.defaultThreshold)

    private static let overSinceKey = "trash.overSince"

    static var trashURL: URL {
        FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash")
    }

    private init() {
        let stored = UserDefaults.standard.double(forKey: Self.overSinceKey)
        overSince = stored > 0 ? Date(timeIntervalSince1970: stored) : nil
    }

    func start(threshold: Int64) {
        self.threshold = threshold
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

    func flies(now: Date) -> Int {
        TrashFlies.count(bytes: bytes, threshold: threshold, overSince: overSince, now: now)
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

        var total: Int64 = 0
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        if let walker = manager.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) {
            for case let file as URL in walker {
                guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
                total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            }
        }
        return TrashReading(stamp: stamp, items: visible.count, bytes: total)
    }

    private func apply(_ result: TrashReading) {
        counting = false
        loaded = true
        needsAccess = result.denied
        guard !result.denied else { return }
        lastStamp = result.stamp
        if let items = result.items { self.items = items }
        if let bytes = result.bytes {
            self.bytes = bytes
            lastFullCount = .now
        }
        if items == 0 { bytes = 0 }
        updateOverSince()
    }

    private func updateOverSince() {
        let next = TrashFlies.overSince(previous: overSince, bytes: bytes, threshold: threshold, now: .now)
        guard next != overSince else { return }
        overSince = next
        if let next {
            UserDefaults.standard.set(next.timeIntervalSince1970, forKey: Self.overSinceKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.overSinceKey)
        }
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
