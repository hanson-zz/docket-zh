import Foundation
import Observation

/// Runs `/usr/bin/shortcuts`, which is how a shortcut is listed and fired
/// without any consent of our own.
///
/// The tool ships with macOS 26 and offers `run`, `list`, `view` and `sign`,
/// and listing costs no TCC prompt. What a *shortcut* then does may well need
/// consent, but that is the shortcut's own business with the system, not
/// something this app can grant or inherit.
///
/// This is the first place in the app that reads a child process's output.
/// `DockStrut` runs `killall` and discards everything, which works only
/// because killall has nothing worth hearing. The two things that costs us,
/// the pipe deadlock and the orphan a timeout leaves behind, are handled in
/// `Tool` below rather than discovered later.
@MainActor @Observable
final class ShortcutsService {
    static let shared = ShortcutsService()

    /// Names as the tool last reported them.
    private(set) var names: [String] = []

    /// `nil` until a load has finished, which is what separates "not asked
    /// yet" from "asked, and there are none". A panel says something
    /// different for each and would be guessing without this.
    private(set) var loadedAt: Date?

    /// Set when listing failed outright, as opposed to succeeding with
    /// nothing to report.
    private(set) var loadError: String?

    /// The shortcuts running right now. Each runs in its own child, so the
    /// panel can start a second while the first is still going and stop
    /// either one without touching the other.
    private(set) var running: Set<String> = []

    /// The last finished run of each shortcut, kept across launches so the
    /// panel can still say "yesterday 18:40, done" after a restart.
    private(set) var records: [String: ShortcutRun.Record] = [:]

    @ObservationIgnored private var loading = false
    @ObservationIgnored private var children: [String: ProcessBox] = [:]

    private static let recordsKey = "shortcuts.lastRuns"
    /// Old records for shortcuts long since removed are dropped past this.
    private static let recordLimit = 60

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.recordsKey),
           let stored = try? JSONDecoder().decode([String: ShortcutRun.Record].self, from: data) {
            records = stored
        }
    }

    func isRunning(_ name: String) -> Bool { running.contains(name) }

    func record(for name: String) -> ShortcutRun.Record? { records[name] }

    /// Re-reads the shortcut list. Cheap enough to call whenever a panel
    /// opens: the tool answered in 15ms on the machine this was written on.
    func load() async {
        guard !loading else { return }
        loading = true
        let result = await Tool.offMain { Tool.capture(["list"], seconds: 5) }
        loading = false
        loadedAt = .now
        guard result.status == 0 else {
            loadError = ShortcutRun.reason(fromStderr: result.err) ?? tr("“快捷指令”命令行工具没有响应。")
            return
        }
        loadError = nil
        names = ShortcutList.parse(String(decoding: result.out, as: UTF8.self))
    }

    /// Fires a shortcut.
    ///
    /// Deliberately not routed through `withTimeout` or `PollGate`. Those
    /// exist to stop a *poll* stacking up behind a hung script; this is a
    /// thing a person just clicked, and making it wait out a poll interval
    /// would make the shelf feel broken. It gets a long ceiling instead,
    /// because a shortcut that takes a minute is doing its job.
    func run(_ name: String) {
        guard !name.isEmpty, !running.contains(name) else { return }
        running.insert(name)
        let box = ProcessBox()
        children[name] = box
        Task {
            let result = await Tool.offMain { Tool.capture(["run", name], seconds: 300, box: box) }
            running.remove(name)
            children[name] = nil
            let status: ShortcutRun.Status
            if result.signalled {
                status = .cancelled
            } else if result.status == 0 {
                status = .ok
            } else {
                // The tool puts its reason on stderr and nowhere else, and a
                // renamed shortcut is the common case: "Couldn't find
                // shortcut". Showing it is what makes that recoverable
                // instead of a tile that quietly stopped working.
                status = .failed(ShortcutRun.reason(fromStderr: result.err) ?? tr("快捷指令未能完成。"))
            }
            // Whatever the shortcut printed to stdout, when it is text. A
            // shortcut that ends on an image or a file prints bytes, and
            // those are not shown rather than shown as noise.
            let output = status == .cancelled ? nil : ShortcutRun.output(from: result.out)
            remember(name, ShortcutRun.Record(finishedAt: .now, status: status, output: output))
        }
    }

    /// Stops one running shortcut. The tool exits on the signal and `run`
    /// reports it as cancelled rather than as a failure.
    func stop(_ name: String) { children[name]?.terminate() }

    private func remember(_ name: String, _ record: ShortcutRun.Record) {
        records[name] = record
        if records.count > Self.recordLimit {
            let keep = records.sorted { $0.value.finishedAt > $1.value.finishedAt }.prefix(Self.recordLimit)
            records = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: Self.recordsKey)
        }
    }
}

/// Everything that touches the process, kept out of the main actor so the
/// blocking parts cannot be called from it by accident. Same shape as
/// `MusicService`'s `Bridge`.
private enum Tool {
    static let path = "/usr/bin/shortcuts"

    static let queue = DispatchQueue(label: "com.namanparashar.plinth.shortcuts")

    static func offMain<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    struct Result: Sendable {
        var status: Int32
        var signalled: Bool
        var out: Data
        var err: String
    }

    static func capture(_ arguments: [String], seconds: Double,
                        box: ProcessBox? = nil) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        // Arguments go to the child as argv, so a shortcut named with a
        // quote or a semicolon is passed through intact. There is no shell
        // here and there must never be one.
        process.arguments = arguments
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err

        do {
            try process.run()
        } catch {
            return Result(status: -1, signalled: false, out: Data(),
                          err: tr("无法启动 \(path)：\(error.localizedDescription)"))
        }
        box?.hold(process)

        // `withTimeout` is the app's usual guard and it is the wrong tool
        // here: it abandons its work rather than cancelling it, and work
        // abandoned by this function is a live child still holding a pipe
        // open. Terminating the process is the only thing that ends it.
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds, execute: watchdog)

        // Both pipes drained at once, each on its own thread. Reading one to
        // the end while the other fills its buffer is the standard pipe
        // deadlock: the child blocks writing to the pipe nobody is reading,
        // so the pipe being read never reaches its end and the wait below
        // never returns.
        let stdout = DataBox(), stderr = DataBox()
        let group = DispatchGroup()
        DispatchQueue.global().async(group: group) {
            stdout.value = out.fileHandleForReading.readDataToEndOfFile()
        }
        DispatchQueue.global().async(group: group) {
            stderr.value = err.fileHandleForReading.readDataToEndOfFile()
        }
        group.wait()
        process.waitUntilExit()
        watchdog.cancel()
        box?.hold(nil)

        return Result(status: process.terminationStatus,
                      signalled: process.terminationReason == .uncaughtSignal,
                      out: stdout.value,
                      err: String(decoding: stderr.value, as: UTF8.self))
    }
}

/// Carries a running child across threads so a stop can reach it.
private final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?

    func hold(_ process: Process?) {
        lock.lock(); defer { lock.unlock() }
        self.process = process
    }

    func terminate() {
        lock.lock(); defer { lock.unlock() }
        if let process, process.isRunning { process.terminate() }
    }
}

/// One pipe's bytes, written by exactly one reader and read only after the
/// group it belongs to has finished, which is what makes the unchecked
/// conformance true rather than merely convenient.
private final class DataBox: @unchecked Sendable {
    var value = Data()
}
